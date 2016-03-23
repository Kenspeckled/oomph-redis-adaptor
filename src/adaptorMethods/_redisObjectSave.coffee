Promise = require 'promise'
oomph = require 'oomph'
_ = require 'lodash'
_utilities = require 'oomph/lib/utilities'

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
  listKey = setKey + 'TempList' + _utilities.randomString(3)
  setTmpKey = setKey + 'TempList' + _utilities.randomString(3)
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
    storableProps = _.clone props, true
    writeCallbackPromises = []
    for attr, obj of self.classAttributes
      switch obj.dataType
        when 'integer'
          if storableProps[attr] or storableProps[attr] == 0
            props[attr] = parseInt(props[attr]) #override original props
            storableProps[attr + '[i]'] = props[attr]
            delete storableProps[attr]
        when 'float'
          if storableProps[attr] or storableProps[attr] == 0
            props[attr] = parseFloat(props[attr]) #override original props
            storableProps[attr + '[f]'] = props[attr]
            delete storableProps[attr]
        when 'boolean'
          if storableProps[attr]?
            props[attr] = if props[attr] == 'false' then false else !!props[attr] #override original props
            storableProps[attr + '[b]'] = props[attr]
            delete storableProps[attr]
        when 'reference'
          if obj.many
            delete storableProps[attr]
            storableProps[attr] = true if newObjectFlag
        when 'string'
          if obj.identifier
            identifier = _utilities.urlString(props[attr])
            props[attr] = identifier #override original props
            storableProps[attr] = identifier
          if obj.url and obj.urlBaseAttribute and props[obj.urlBaseAttribute]
            findExistingAttr = (attr, identifier) ->
              isUnique = false
              condition = -> !isUnique
              counter = 0
              _utilities.promiseWhile condition, ->
                new Promise (resolve) ->
                  modifiedIdentifier = identifier
                  modifiedIdentifier += ('-' + counter) if counter > 0
                  counter += 1
                  self.redis.get self.className + "#" + attr + ':' + modifiedIdentifier, (err, res) ->
                    props[attr] = modifiedIdentifier #override original props
                    storableProps[attr] = modifiedIdentifier
                    isUnique = true if !res
                    resolve()
            if newObjectFlag # only set url once - this value should not update
              identifier = if storableProps[attr] then _utilities.urlString(storableProps[attr]) else _utilities.urlString(props[obj.urlBaseAttribute])  # only define url automatically if not manually defined
              writeCallbackPromises.push findExistingAttr(attr, identifier)
    Promise.all(writeCallbackPromises).then ->
      new Promise (resolve) ->
        self.redis.hmset self.className + ":" + props.id, storableProps, (err, res) ->
          resolve(storableProps)
  indexPromise = writePromise.then (storedProps) ->
    indexingPromises = []
    multi = self.redis.multi()
    indexPromiseFn = (sortedSetName, attributeName, propsId) ->
      largestSortedSetSize = 9007199254740992 # make sure new elements are added at the end of the set
      new Promise (resolve) ->
        self.redis.zadd sortedSetName, largestSortedSetSize, propsId, (error, res) ->
          indexSortedSet.apply(self, [sortedSetName, attributeName]).then ->
            resolve()
    sortedSetName = self.className + ">id"
    indexingPromises.push indexPromiseFn(sortedSetName, "id", props.id)
    for attr, obj of self.classAttributes
      continue if props[attr] == undefined #props[attr] can be false for boolean dataType
      value = props[attr]
      switch obj.dataType
        when 'integer', 'float'
          sortedSetName = self.className + ">" + attr
          multi.zadd sortedSetName, value, props.id #sorted set
        when 'string'
          if obj.sortable
            sortedSetName = self.className + ">" + attr
            indexingPromises.push indexPromiseFn(sortedSetName, attr, props.id)
          if obj.identifiable or obj.url
            multi.set self.className + "#" + attr + ":" + value, props.id #string
          if obj.searchable
            value = _utilities.sanitisedString(value)
            indexingPromises.push indexSearchableString.apply(self, [attr, value, props.id])
        when 'text'
          if obj.searchable
            value = _utilities.sanitisedString(value)
            indexingPromises.push indexSearchableString.apply(self, [attr, value, props.id])
        when 'boolean'
          if _.includes([true, 'true', false, 'false'], value)
            multi.zadd self.className + "#" + attr + ":" + value, 1, props.id #set
        when 'reference'
          namespace = obj.reverseReferenceAttribute || attr
          if obj.many
            #FIXME: Does this work? !!!!!
            #multipleValues = _.compact(value.split(","))
            multipleValues = value
            multi.sadd self.className + ":" +  props.id + "#" + attr + ':' + obj.referenceModelName + 'Refs', multipleValues...
            multipleValues.forEach (vid) ->
              multi.sadd obj.referenceModelName + ":" +  vid + "#" + namespace + ':' +  self.className + 'Refs', props.id
          else
            multi.sadd obj.referenceModelName + ":" + value + "#" + namespace + ':' +  self.className + 'Refs', props.id
        else
          if obj.dataType != null
            Promise.reject new Error "Unrecognised dataType " + obj.dataType
    new Promise (resolve) ->
      multi.exec ->
        Promise.all(indexingPromises).then ->
          resolve(storedProps)
  return indexPromise

performValidations = (validateFields, dataFields) ->
  self = this
  if _.isEmpty(dataFields)
    return Promise.reject(new Error "No valid fields given")
  returnedValidations = _.map validateFields, (attrName) ->
    attrObj = self.classAttributes[attrName]
    if attrObj and attrObj.validates
      attrValue = dataFields[attrName]
      return oomph.validate.apply(self, [attrObj.validates, attrName, attrValue])
  Promise.all(returnedValidations).then (validationArray) ->
    errors =  _(validationArray).flattenDeep().compact().value()
    Promise.reject(errors) if !_.isEmpty(errors)

sendAttributesForSaving = (dataFields, skipValidation) ->
  self = this
  if skipValidation
    validationPromise = new Promise (resolve) ->
      resolve(true)
    props = dataFields
  else
    isNewObject = !dataFields.id
    if isNewObject
      attrs = ['id'].concat(_.keys(self.classAttributes))
    else
      attrs = _.keys(dataFields)
    sanitisedDataFields = _(dataFields).omit(_.isNull).omit(_.isUndefined).pick(attrs).value()
    props = sanitisedDataFields
    validationPromise = performValidations.apply(self, [attrs, props])
  validationPromise.then ->
    writeAttributes.apply(self, [props])

module.exports = sendAttributesForSaving
