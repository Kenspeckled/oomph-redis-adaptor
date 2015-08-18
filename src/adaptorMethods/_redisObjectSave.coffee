Promise = require 'promise'
oomph = require 'oomph'
_ = require 'lodash'
_utilities = require './utilities'

_oomphRedisObjectSaveQueueCallbacks = {}
numberOfExtraCharactersOnId = 2

generateId = ->
  d = new Date()
  s = (+d).toString(36)
  s + _utilities.randomString(numberOfExtraCharactersOnId)

generateUniqueId = ->
  self = this
  uniqueId = false
  condition = -> uniqueId == false
  newIdPromise = _utilities.promiseWhile condition, ->
    new Promise (resolve) ->
      id = generateId()
      self.redis.lrange self.name + '#uniqueQueuedIds', 0, -1, (error, idsArray) ->
        if _.includes(idsArray, id)
          id = generateId()
          resolve()
        else
          self.redis.rpush self.name + '#uniqueQueuedIds', id, (error, response) ->
            uniqueId = true
            resolve(id)


indexSortedSet = (setKey, attr) ->
  listKey = setKey + 'TempList'
  setTmpKey = setKey + 'TempList'
  sortPromise = new Promise (resolve, reject) =>
    @redis.sort setKey, 'by', @name + ':*->' + attr, 'alpha', 'store', listKey, (error, newLength) ->
      resolve(newLength)
  addToTmpSetPromise = sortPromise.then (listLength) =>
    multi = @redis.multi()
    new Promise (resolve, reject) =>
      _.times listLength, ->
        multi.lpop listKey
      multi.exec (error, ids) =>
        addToSet = _.map ids, (id, i) =>
          new Promise (r) =>
            @redis.zadd setTmpKey, listLength - i, id, (res) ->
              r()
        resolve Promise.all(addToSet)
  addToTmpSetPromise.then =>
    new Promise (resolve) =>
      @redis.rename setTmpKey, setKey, (res) =>
        resolve()

indexSearchableString = (attr, words, id) ->
  indexPromises = []
  for word in words.split /\s/
    word = word.toLowerCase()
    wordSegment = ''
    for char in word
      wordSegment += char
      wordSegmentKey = @name + '#' + attr + '/' + wordSegment
      indexPromiseFn = (wordSegmentKey, id) =>
        new Promise (resolve) =>
          @redis.zadd wordSegmentKey, 1, id, (res) ->
            resolve()
      indexPromises.push indexPromiseFn(wordSegmentKey, id)
  Promise.all(indexPromises)

writeAttributes = (props) ->
  self = this
  newObjectFlag = false
  idPromise = new Promise (resolve) ->
    if !props.id
      newObjectFlag = true
      generateUniqueId.apply(self).then (id) ->
        resolve id
    else
      resolve props.id
  writePromise = idPromise.then (id) ->
    props.id = id
    storableProps = _.clone props
    new Promise (resolve) ->
      for attr, obj of self.classAttributes
        switch obj.dataType
          when 'integer'
            if storableProps[attr]
              storableProps[attr + '[i]'] = storableProps[attr]
              delete storableProps[attr]
          when 'boolean'
            if storableProps[attr]
              storableProps[attr + '[b]'] = storableProps[attr]
              delete storableProps[attr]
          when 'reference'
            if obj.many
              delete storableProps[attr]
              storableProps[attr] = true if newObjectFlag
          when 'string'
            if obj.url and obj.urlBaseAttribute
              # FIXME: Handle duplicate urls and force them to be unique by appending sequential numbers
              storableProps[attr] = _utilities.urlString(props[obj.urlBaseAttribute]) if !storableProps[attr]
      self.redis.hmset self.name + ":" + props.id, storableProps, (err, res) ->
        resolve(storableProps)
  indexPromise = writePromise.then (props) ->
    indexingPromises = []
    multi = self.redis.multi()
    indexPromiseFn = (sortedSetName, attributeName) ->
      largestSortedSetSize = 9007199254740992 # make sure new elements are added at the end of the set
      new Promise (resolve) ->
        self.redis.zadd sortedSetName, largestSortedSetSize, props.id, (error, res) ->
          indexSortedSet.apply(self, [sortedSetName, attributeName]).then ->
            resolve()
    sortedSetName = self.name + ">id"
    indexingPromises.push indexPromiseFn(sortedSetName, "id")
    for attr, obj of self.classAttributes
      continue if props[attr] == undefined #props[attr] can be false for boolean dataType
      value = props[attr]
      switch obj.dataType
        when 'integer'
          sortedSetName = self.name + ">" + attr
          multi.zadd sortedSetName, parseInt(value), props.id #sorted set
        when 'string'
          if obj.sortable
            sortedSetName = self.name + ">" + attr
            indexingPromises.push indexPromiseFn(sortedSetName, attr)
          if obj.identifiable or obj.url
            multi.set self.name + "#" + attr + ":" + value, props.id #string
          if obj.searchable
            indexingPromises.push indexSearchableString.apply(self, [attr, value, props.id])
        when 'text'
          if obj.searchable
            indexingPromises.push indexSearchableString.apply(self, [attr, value, props.id])
        when 'boolean'
          if _.includes([true, 'true', false, 'false'], value)
            multi.zadd self.name + "#" + attr + ":" + value, 1, props.id #set
        when 'reference'
          namespace = obj.reverseReferenceAttribute || attr
          if obj.many
            multipleValues = _.compact(value.split(","))
            multi.sadd self.name + ":" +  props.id + "#" + attr + ':' + obj.referenceModelName + 'Refs', multipleValues...
            multipleValues.forEach (vid) ->
              multi.sadd obj.referenceModelName + ":" +  vid + "#" + namespace + ':' +  self.name + 'Refs', props.id
          else
            multi.sadd obj.referenceModelName + ":" + value + "#" + namespace + ':' +  self.name + 'Refs', props.id
        else
          if obj['dataType'] != null
            reject new Error "Unrecognised dataType " + obj.dataType
    new Promise (resolve) ->
      multi.exec ->
        resolve Promise.all(indexingPromises)
  indexPromise.then ->
    return props 

clearUniqueQueuedIds = ->
  @redis.del @name + '#uniqueQueuedIds'


processWriteQueue = ->
  self = this
  hasQueue = true
  condition = -> hasQueue
  writeReturnObject = {}
  processPromise = _utilities.promiseWhile condition, ->
    writePromise = new Promise (resolve, reject) ->
      self.redis.rpop self.name + "#TmpQueue", (error, tmpId) ->
        if tmpId
          self.redis.hgetall self.name + "#TmpQueueObj:" + tmpId, (err, props) ->
            self.redis.del self.name + "#TmpQueueObj:" + tmpId
            if props
              writeAttributes.apply(self, [props]).then (writtenObject) ->
                writeReturnObject[tmpId] = writtenObject
                resolve()
            else
              reject new Error "No properties in Queued Object " + self.name + "#TmpQueueObj:" + tmpId
        else
          clearUniqueQueuedIds.apply(self)
          hasQueue = false
          resolve()
  processPromise.then ->
    _.each writeReturnObject, (obj, tmpId) ->
      _oomphRedisObjectSaveQueueCallbacks["attributes_written_" + tmpId].call(self, obj)
    return writeObjectArray


addToWriteQueue = (props) ->
  self = this
  tmpId = "TmpId" + generateId() + _utilities.randomString(12)
  p = new Promise (resolve) ->
    self.redis.hmset self.name + "#TmpQueueObj:" + tmpId, props, (err, res) =>
      self.redis.lpush self.name + "#TmpQueue", tmpId, (error, newListLength) =>
        resolve(tmpId)
  p.then (tmpId) ->
    clearTimeout self._ORMWriteQueueTimeout
    self._ORMWriteQueueTimeout = setTimeout ->
      return processWriteQueue.apply(self)
    , 100
    new Promise (resolve) ->
      resolveFn = (obj) -> 
        delete _oomphRedisObjectSaveQueueCallbacks["attributes_written_" + tmpId]
        resolve(obj)
      _oomphRedisObjectSaveQueueCallbacks["attributes_written_" + tmpId] = resolveFn

performValidations = (dataFields) ->
  if _.isEmpty(dataFields)
    throw new Error "No valid fields given"
  returnedValidations = _.map @classAttributes, (attrObj, attrName) =>
    if attrObj.validates
      attrValue = dataFields[attrName]
      return oomph.validate.apply(this, [attrObj.validates, attrName, attrValue])
  Promise.all(returnedValidations).then (validationArray) ->
    errors =  _(validationArray).flattenDeep().compact().value()
    throw errors if not _.isEmpty(errors)

sendAttributesForSaving = (dataFields, skipValidation) ->
  if skipValidation
    validationPromise = new Promise (resolve) ->
      resolve(true)
    props = dataFields
  else
    attrs = _.keys(@classAttributes)
    attrs.push "id"
    sanitisedDataFields = _(dataFields).omit(_.isNull).omit(_.isUndefined).pick(attrs).value()
    props = sanitisedDataFields
    validationPromise = performValidations.apply(this, [props])
  new Promise (resolve, reject) =>
    reject new Error "Properties are empty" if _.isEmpty props
    validationPromise.then =>
      resolve addToWriteQueue.apply(this, [props])
    , (validationErrors) ->
      reject validationErrors

module.exports = sendAttributesForSaving
