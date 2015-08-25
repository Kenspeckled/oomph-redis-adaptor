Promise = require 'promise'
oomph = require 'oomph'
_ = require 'lodash'
_utilities = require './utilities'

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
      # FIXME: ids become guaranteed to be unique after 1 second since they are time based. This can be done better
      self.redis.lrange self.className + '#uniqueIds', 0, -1, (error, idsArray) ->
        if _.includes(idsArray, id)
          id = generateId()
          resolve()
        else
          self.redis.rpush self.className + '#uniqueIds', id, (error, response) ->
            uniqueId = true
            resolve(id)

indexSortedSet = (setKey, attr) ->
  listKey = setKey + 'TempList'
  setTmpKey = setKey + 'TempList'
  sortPromise = new Promise (resolve, reject) =>
    @redis.sort setKey, 'by', @className + ':*->' + attr, 'alpha', 'store', listKey, (error, newLength) ->
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
      wordSegmentKey = @className + '#' + attr + '/' + wordSegment
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
    writeCallbackPromises = []
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
            findExistingAttr = (attr, identifier, baseAttr) ->
              isUnique = false
              condition = -> !isUnique
              counter = 0
              _utilities.promiseWhile condition, ->
                modifiedIdentifier = identifier 
                modifiedIdentifier += ('-' + counter) if counter > 0
                counter += 1
                new Promise (resolve) ->
                  self.redis.get self.className + "#" + attr + ':' + modifiedIdentifier, (err, res) ->
                    isUnique = !res
                    storableProps[attr] = modifiedIdentifier
                    resolve()
            identifier = _utilities.urlString(props[obj.urlBaseAttribute]) if !storableProps[attr] # only define url if not manually defined
            writeCallbackPromises.push findExistingAttr(attr, identifier, obj.urlBaseAttribute)
    Promise.all(writeCallbackPromises).then ->
      new Promise (resolve) ->
        self.redis.hmset self.className + ":" + props.id, storableProps, (err, res) ->
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
    sortedSetName = self.className + ">id"
    indexingPromises.push indexPromiseFn(sortedSetName, "id")
    for attr, obj of self.classAttributes
      continue if props[attr] == undefined #props[attr] can be false for boolean dataType
      value = props[attr]
      switch obj.dataType
        when 'integer'
          sortedSetName = self.className + ">" + attr
          multi.zadd sortedSetName, parseInt(value), props.id #sorted set
        when 'string'
          if obj.sortable
            sortedSetName = self.className + ">" + attr
            indexingPromises.push indexPromiseFn(sortedSetName, attr)
          if obj.identifiable or obj.url
            multi.set self.className + "#" + attr + ":" + value, props.id #string
          if obj.searchable
            indexingPromises.push indexSearchableString.apply(self, [attr, value, props.id])
        when 'text'
          if obj.searchable
            indexingPromises.push indexSearchableString.apply(self, [attr, value, props.id])
        when 'boolean'
          if _.includes([true, 'true', false, 'false'], value)
            multi.zadd self.className + "#" + attr + ":" + value, 1, props.id #set
        when 'reference'
          namespace = obj.reverseReferenceAttribute || attr
          if obj.many and value != true
            multipleValues = _.compact(value.split(","))
            multi.sadd self.className + ":" +  props.id + "#" + attr + ':' + obj.referenceModelName + 'Refs', multipleValues...
            multipleValues.forEach (vid) ->
              multi.sadd obj.referenceModelName + ":" +  vid + "#" + namespace + ':' +  self.className + 'Refs', props.id
          else
            multi.sadd obj.referenceModelName + ":" + value + "#" + namespace + ':' +  self.className + 'Refs', props.id
        else
          if obj['dataType'] != null
            reject new Error "Unrecognised dataType " + obj.dataType
    new Promise (resolve) ->
      multi.exec ->
        resolve Promise.all(indexingPromises)
  indexPromise.then ->
    return props 

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
    return true

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
  throw new Error "Properties are empty" if _.isEmpty props
  validationPromise.then =>
    writeAttributes.apply(this, [props])
  , (validationErrors) ->
    validationErrors.forEach (error) ->
      console.log error
      throw error

module.exports = sendAttributesForSaving
