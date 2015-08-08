redis = require 'redis'
Promise = require 'promise'
pluralise = require 'pluralize'
_ = require 'lodash'
_utilities = require '../utilities'
publishSubscribe = require '../publishSubscribe'
ValidationError = require '../models/ValidationError'

numberOfExtraCharactersOnId = 2
generateId = ->
  d = new Date()
  s = (+d).toString(36)
  s + _utilities.randomString(numberOfExtraCharactersOnId)

idToSeconds = (id) ->
  parseInt(id.slice(0, -numberOfExtraCharactersOnId), 36)

idToCreatedAtDate = (id) ->
  new Date idToSeconds(id)

sortAscendingNumbersFn = (a, b) ->  b - a
sortAlphabeticallyFn = (a, b) -> a < b

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

createObjectFromHash = (hash, modelClass) ->
  obj = {}
  obj = new modelClass() if modelClass and modelClass.prototype
  return false if !hash
  obj.createdAt = idToCreatedAtDate(hash.id) if hash.id
  for key, value of hash
    plainKey = key.replace /\[\w\]$/, ''
    propertyCastType = key.match /\[(\w)\]$/
    if propertyCastType
      if propertyCastType[1] == 'b' # cast as boolean
        obj[plainKey] = (value == 'true')
      else if propertyCastType[1] == 'i' # cast as integer 
        obj[plainKey] = parseInt(value)
    else
      obj[key] = value
  obj

validate = (validationObj, attrName, attrValue) ->
  validations = []
  for validationType in Object.keys(validationObj)
    validationSetting = validationObj[validationType]
    if validationType != 'presence' and !attrValue
      continue
    switch validationType
      when 'presence'
        if _utilities.isBlank(attrValue)
          validations.push new ValidationError attrName + " must be present", attribute: attrName, expected: validationSetting
      when 'equalTo'
        unless attrValue == validationSetting
          validations.push new ValidationError attrName + " should equal " + validationSetting, attribute: attrName, actual: attrValue, expected: validationSetting
      when 'lessThan'
        unless attrValue < validationSetting
          validations.push new ValidationError attrName + " should be less than " + validationSetting, attribute: attrName, actual: attrValue, expected: validationSetting
      when 'lessThanOrEqualTo'
        unless attrValue <= validationSetting
          validations.push new ValidationError attrName + " should be less than or equal to " + validationSetting, attribute: attrName, actual: attrValue, expected: validationSetting
      when 'greaterThanOrEqualTo'
        unless attrValue >= validationSetting
          validations.push new ValidationError attrName + " should be greater than or equal to " + validationSetting, attribute: attrName, actual: attrValue, expected: validationSetting
      when 'greaterThan'
        unless attrValue > validationSetting
          validations.push new ValidationError attrName + " should be greater than " + validationSetting, attribute: attrName, actual: attrValue, expected: validationSetting
      when 'inclusionIn'
        unless _.includes(validationSetting, attrValue)
          validations.push new ValidationError attrName + " must be one of the accepted values", attribute: attrName, actual: attrValue, expected: validationSetting
      when 'exclusionIn'
        if _.includes(validationSetting, attrValue)
          validations.push new ValidationError attrName + " must not be one of the forbidden values", attribute: attrName, actual: attrValue, expected: validationSetting
      when 'uniqueness'
        validationPromise = new Promise (resolve, reject) =>
          @redis.get @name + '#' + attrName + ':' + attrValue, (error, obj) ->
            if (error || obj)
              resolve new ValidationError attrName + " should be a unique value", attribute: attrName, actual: attrValue, expected: validationSetting
            else
              resolve()
        validations.push validationPromise
      when 'length'
        if validationSetting.hasOwnProperty('is')
          unless attrValue.length == validationSetting.is
            validations.push new ValidationError attrName + " should have a length of " + validationSetting.is, attribute: attrName, actual: attrValue, expected: validationSetting.is
        else if validationSetting.hasOwnProperty('minimum')
          unless attrValue.length >= validationSetting.minimum
            validations.push new ValidationError attrName + " should have a minimum length of " + validationSetting.minimum, attribute: attrName, actual: attrValue, expected: validationSetting.minimum
        else if validationSetting.hasOwnProperty('maximum')
          unless attrValue.length <= validationSetting.maximum
            validations.push new ValidationError attrName + " should have a maximum length of " + validationSetting.maximum, attribute: attrName, actual: attrValue, expected: validationSetting.maximum
        else
          throw new Error "length validation setting not valid on " + attrName
      when 'format'
        if validationSetting.hasOwnProperty('with')
          if validationSetting.with.exec(attrValue) == null
            validations.push new ValidationError attrName + " should meet the format requirements", attribute: attrName, actual: attrValue, expected: validationSetting.with
        else if validationSetting.hasOwnProperty('without')
          unless validationSetting.without.exec(attrValue) == null
            validations.push new ValidationError attrName + " should meet the format requirements", attribute: attrName, actual: attrValue, expected: validationSetting.without
        else
          throw new Error "format validation setting not valid on " + attrName

  Promise.all(validations)

performValidations = (dataFields) ->
  if _.isEmpty(dataFields)
    throw new Error "No valid fields given"
  returnedValidations = _.map @attributes, (attrObj, attrName) =>
    if attrObj.validates
      attrValue = dataFields[attrName]
      return validate.apply(this, [attrObj.validates, attrName, attrValue])
  Promise.all(returnedValidations).then (validationArray) ->
    errors =  _(validationArray).flattenDeep().compact().value()
    throw errors if not _.isEmpty(errors)

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

removeIndexedSearchableString = (attr, words, id) ->
  indexPromises = []
  for word in words.split /\s/
    word = word.toLowerCase()
    wordSegment = ''
    for char in word
      wordSegment += char
      wordSegmentKey = @name + '#' + attr + '/' + wordSegment
      indexPromiseFn = (wordSegmentKey, id) =>
        new Promise (resolve) =>
          @redis.zrem wordSegmentKey, id, (res) ->
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
      for attr, obj of self.attributes
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
    for attr, obj of self.attributes
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
      publishSubscribe.broadcast.apply(self, ["attributes_written_" + tmpId, obj])
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
        publishSubscribe.removeAllListenersOn.apply self, ["attributes_written_" + tmpId]
        resolve(obj)
      publishSubscribe.listen.apply self, ["attributes_written_" + tmpId, resolveFn]


sendAttributesForSaving = (dataFields, skipValidation) ->
  if skipValidation
    validationPromise = new Promise (resolve) ->
      resolve(true)
    props = dataFields
  else
    attrs = _.keys(@attributes)
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

createIntegerSubset = (integerSortedSetName, tempIntegerKey, minValue, maxValue) ->
  self = this
  new Promise (resolve) ->
    self.redis.zrangebyscore integerSortedSetName, minValue, maxValue, (error, resultList) ->
      multi = self.redis.multi()
      for result in resultList
        multi.zadd tempIntegerKey, 0, result
        multi.expire tempIntegerKey, 1 #key will expire in 1 second. Key not explicitly deleted
      multi.exec ->
        resolve()

findKeywordsInAnyFields = (fields, keywords, weightOptions) ->
    unionkeyNames = []
    unionKeyPromises = _.map keywords, (keyword) =>
      keyNames = []
      for field in fields
        weight = (if weightOptions[field] and weightOptions[field].weight then weightOptions[field].weight else 1)
        keyNames.push name: @name + "#" + field + "/" + keyword, weight: weight
      unionKey = 'keywordUnionSet:' + _utilities.randomString(5)
      unionKeyPromise = new Promise (resolve) =>
        @redis.zunionstore unionKey, keyNames.length, _.map(keyNames, 'name')..., 'weights', _.map(keyNames, 'weight')..., ->
          resolve unionKey
      unionKeyPromise.then (unionKey) ->
        unionkeyNames.push unionKey
    Promise.all(unionKeyPromises).then ->
      return unionkeyNames

redisObjectDataStore =

  moduleName: "redisObjectDataStore"

  moduleInitialise: ->
    port = process.env.REDIS_CLIENT_PORT || 6379
    host = process.env.REDIS_CLIENT_HOST || '127.0.0.1'
    @redis = redis.createClient(port, host) 

  all: (args) ->
    allArgs = _.pick(args, ['sortBy', 'sortDirection', 'limit', 'offset'])
    @where(allArgs)

  # FIXME: In need of refactor - lots of code smell
  find: (id) ->
    self = this
    referencePromises = []
    getHash = new Promise (resolve, reject) ->
      self.redis.hgetall self.name + ":" + id, (error, hash) ->
        if !hash
          reject new Error "Not Found"
        else
          resolve(hash)
    modifyHashPromise = getHash.then (hash) ->
      for propertyName in Object.keys(self.attributes)
        propertyValue = hash[propertyName]
        attrSettings = self.attributes[propertyName]
        continue if _.isUndefined(propertyValue) 
        if attrSettings.dataType == 'reference'
          if attrSettings.many
            getReferenceIdsFn = (propertyName, referenceModelName) ->
              new Promise (resolve, reject) ->
                referenceKey = self.name + ':' + id + '#' + propertyName + ':' + referenceModelName + 'Refs'
                self.redis.smembers referenceKey, (err, ids) ->
                  hashObj = {propertyName, referenceModelName}
                  resolve {ids, hashObj}
            referencePromise = getReferenceIdsFn(propertyName, attrSettings.referenceModelName).then (obj) ->
              getObjects = _.map obj.ids, (id) ->
                new Promise (resolve, reject) ->
                  self.redis.hgetall obj.hashObj.referenceModelName + ':' + id, (err, hash) ->
                    resolve createObjectFromHash hash
              Promise.all(getObjects).then (arr) ->
                obj.hashObj.referenceValue = arr
                obj.hashObj
            referencePromises.push referencePromise
          else
            hashPromiseFn = (propertyName, propertyValue, referenceModelName) ->
              new Promise (resolve, reject) ->
                self.redis.hgetall referenceModelName + ':' + propertyValue, (err, hash) ->
                  hashObj = {propertyName, propertyValue, referenceModelName}
                  hashObj.referenceValue = createObjectFromHash hash
                  resolve hashObj
            referencePromises.push hashPromiseFn(propertyName, propertyValue, attrSettings.referenceModelName)
          delete hash[propertyName]
      hash
    modifyHashPromise.then (hash) ->
      Promise.all(referencePromises).then (referenceObjects) ->
        _.each referenceObjects, (refObj) ->
          hash[refObj.propertyName] = refObj.referenceValue
        createObjectFromHash(hash, self)


  findBy: (option) ->
    p = new Promise (resolve, reject) =>
      optionName = Object.keys(option)[0]
      condition = option[optionName]
      if optionName == 'id'
        resolve condition
      else
        if @attributes[optionName].dataType == 'string' and (@attributes[optionName].identifiable or @attributes[optionName].url)
          stringName = @name + "#" + optionName + ":" + condition
          @redis.get stringName, (err, res) ->
            resolve res
        else
          reject( throw new Error "Not an identifier" )
    p.then (res) =>
      @find(res)

  where: (args) ->
    self = this
    args ||= {}
    args.sortBy ||= (if args.includes then 'relevance' else 'id')
    args.sortDirection ||= 'asc'
    args.sortDirection.toLowerCase()
    args.limit ||= null
    args.offset ||= null
    if args.sortBy == 'random'
      start = 0
      end = -1
    else
      start = +args.offset
      end = if args.limit > 0 then (args.limit - 1) + args.offset else -1
    if args.sortDirection == 'desc'
      end = if args.offset > 0 then -(args.offset + 1) else -1
      start = if args.limit > 0 then end - (args.limit - 1) else 0
    sortedSetKeys = []
    unionSortedSetKeys = []
    if args.sortBy == 'random'
      sortedSetKeys.push name: self.name + '>id'
    else if args.sortBy != 'relevance'
      sortedSetKeys.push name: self.name + '>' + args.sortBy
    weightOptions = {}
    keywordSearchPromise = new Promise (r) -> r()
    if args.includes
      if args.includes.modifiedWeights
        for modifyObj in args.includes.modifiedWeights
          modifyObjAttrs = if _.isArray(modifyObj.attributes) then modifyObj.attributes else [modifyObj.attributes]
          for attr in modifyObjAttrs
            weightOptions[attr] = {}
            weightOptions[attr].weight = +modifyObj.weight
      fields = args.includes.inAllOf || args.includes.inAnyOf || [args.includes.in]
      keywords = args.includes.keywords.split(/\s/)
      keywords = _.reject(keywords, (s) -> s == '' )
      if args.includes.inAnyOf
        keywordSearchPromise = findKeywordsInAnyFields.apply(self, [fields, keywords, weightOptions]).then (keyNames) ->
          _.each keyNames, (key) ->
            sortedSetKeys.push name: key
      else if args.includes.inAllOf or args.includes.in
        for field in fields
          weight = (if weightOptions[field] and weightOptions[field].weight then weightOptions[field].weight else 1)
          for keyword in keywords
            sortedSetKeys.push name: self.name + "#" + field + "/" + keyword, weight: weight
    whereConditionPromises = []
    for option in Object.keys(args)
      optionValue = args[option]
      if not @attributes[option]
        continue
      switch @attributes[option].dataType
        when 'integer' #add less than and greater than functionality
          tempIntegerKey = 'temporaryIntegerSet:' + _utilities.randomString(5)
          integerSortedSetName = self.name + '>' + option
          minValue = '-inf'
          maxValue = '+inf'
          if optionValue.greaterThan
            minValue = optionValue.greaterThan + 1
          if optionValue.greaterThanOrEqualTo
            minValue = optionValue.greaterThanOrEqualTo
          if optionValue.lessThan
            maxValue = optionValue.lessThan - 1
          if optionValue.lessThanOrEqualTo
            maxValue = optionValue.lessThanOrEqualTo
          if optionValue.equalTo
            minValue = optionValue.equalTo
            maxValue = optionValue.equalTo
          whereConditionPromises.push new Promise (resolve) ->
            createIntegerSubset.apply(self, [integerSortedSetName, tempIntegerKey, minValue, maxValue]).then ->
              resolve()
          sortedSetKeys.push name: tempIntegerKey
          sortedSetKeys.push name: integerSortedSetName
        when 'boolean'
          sortedSetKeys.push  name: self.name + "#" + option + ":" + optionValue
        when 'reference'
          referenceModelName = @attributes[option].referenceModelName
          if referenceModelName 
            namespace = @attributes[option].reverseReferenceAttribute || option
            if @attributes[option].many 
              if optionValue.includesAllOf
                _.each optionValue.includesAllOf, (id) ->
                  sortedSetKeys.push name: referenceModelName + ':' + id + '#' + namespace + ':' + self.name + 'Refs'
              if optionValue.includesAnyOf
                _.each optionValue.includesAnyOf, (id) ->
                  unionSortedSetKeys.push name: referenceModelName + ':' + id + '#' + namespace + ':' + self.name + 'Refs'
            else
              if optionValue.anyOf
                _.each optionValue.anyOf, (id) ->
                  unionSortedSetKeys.push name: referenceModelName + ':' + id + '#' + namespace + ':' + self.name + 'Refs'
              else
                sortedSetKeys.push name: referenceModelName + ':' + optionValue + '#' + namespace + ':' + self.name + 'Refs'
    prepareWhereConditionPromise = Promise.all(whereConditionPromises).then -> 
      if _.isEmpty(unionSortedSetKeys)
        keywordSearchPromise
      else
        unionPromise = new Promise (resolve) ->
          unionSortedSetKeyNames = _.map(unionSortedSetKeys, 'name')
          unionKey = 'temporaryUnionSet:' + _utilities.randomString(24)
          self.redis.zunionstore unionKey, unionSortedSetKeys.length, unionSortedSetKeyNames..., (err,numberofresults) ->
            self.redis.expire unionKey, 5 # FIXME: this shoud be cached
            sortedSetKeys.push name: unionKey
            resolve()
        unionPromise.then ->
          keywordSearchPromise
    prepareWhereConditionPromise.then () ->
      idsKeyPromise = new Promise (resolve) ->
        intersectKey = 'temporaryIntersectSet:' + _utilities.randomString(24)
        sortedSetKeyNames = _.map(sortedSetKeys, 'name')
        self.redis.zinterstore intersectKey, sortedSetKeys.length, sortedSetKeyNames..., (err,numberOfResults) ->
          self.redis.expire intersectKey, 5 # FIXME: this shoud be cached
          resolve({intersectKey,numberOfResults})
      matchedIdsPromise = idsKeyPromise.then (resultObj) ->
        idKey = resultObj.intersectKey
        totalResults = resultObj.numberOfResults
        facetResults = {}
        facetsPromises = []
        _.each args.facets, (f) ->
          facetResults[f] = []
          facetsPromises.push new Promise (resolve) ->
            self.redis.sort idKey, 'by', 'nosort', 'get', self.name + ':*->' + f, (err, facetList) ->
              counts = _.countBy facetList, (p) -> p
              for x in Object.keys(counts)
                facetResults[f].push item: x, count: counts[x]
              resolve()
        Promise.all(facetsPromises).then ->
          new Promise (resolve) ->
            self.redis.zrevrange idKey, start, end, (error, ids) ->
              ids.reverse() if args.sortDirection == 'desc'
              self.redis.del idKey, ->
              resolve {ids, totalResults, facetResults}
      matchedIdsPromise.then (resultObject) ->
        ids = resultObject.ids
        if args.sortBy == 'random'
          if args.limit
            ids = _.sample ids, args.limit
          else
            ids = _.shuffle ids
        promises = _.map ids, (id) ->
          self.find(id)
        Promise.all(promises).then (resultItems) ->
          _resultObject =
            name: self.name
            total: resultObject.totalResults
            offset: start
            facets: resultObject.facetResults
            items: resultItems

  create: (props, skipValidation) ->
    new Promise (resolve, reject) =>
      sendAttributesForSaving.apply(this, [props, skipValidation]).then (writtenObject) =>
        resolve @find(writtenObject.id) if writtenObject
      , (error) ->
        reject error if error


  update: (id, updateFields, skipValidation) ->
    self = this
    updateFieldsDiff = { id: id } #need to send existing id to stop new id being generated
    callbackPromises = []
    multi = self.redis.multi()
    getOriginalObjPromise = self.find(id).then (originalObj) ->
      if !originalObj
        throw new Error "Not Found"
      return originalObj
    getOriginalObjPromise.then (originalObj) ->
      for attr in Object.keys(updateFields)
        remove = false
        if attr.match(/^remove_/)
          remove = true
          removeValue = updateFields[attr]
          attr = attr.replace(/^remove_/, '')
        orderedSetName = self.name + '>' + attr
        originalValue = originalObj[attr]
        newValue = updateFields[attr]
        # if there is an actual change or it's a boolean
        if newValue != originalValue or _.includes([true, 'true', false, 'false'], newValue) or removeValue
          updateFieldsDiff[attr] = newValue
          delete updateFieldsDiff[attr] if remove
          obj = self.attributes[attr]
          return if !obj
          switch obj.dataType
            when 'integer'
              sortedSetName = self.name + '>' + attr
              multi.zrem sortedSetName, id
            when 'text'
              if obj.searchable
                callbackPromises.push removeIndexedSearchableString.apply(self, [attr, originalValue, id])
            when 'string'
              if obj.sortable
                multi.zrem orderedSetName, id
              if obj.searchable
                callbackPromises.push removeIndexedSearchableString.apply(self, [attr, originalValue, id])
              if obj.identifiable or obj.url
                multi.del self.name + "#" + attr + ":" + originalValue
            when 'reference'
              namespace = obj.reverseReferenceAttribute || attr
              if obj.many
                if remove
                  multi.srem self.name + ":" +  id + "#" + attr + ':' + obj.referenceModelName + 'Refs', removeValue...
                  removeValue.forEach (vid) ->
                    multi.srem obj.referenceModelName + ":" +  vid + "#" + namespace + ':' + self.name + 'Refs', id
                else
                  originalIds = _.map(originalValue, 'id')
                  intersectingValues = _.intersection(originalIds, newValue)
                  updateFieldsDiff[attr] = intersectingValues if !_.isEmpty(intersectingValues)
              else
                if remove
                  multi.srem obj.referenceModelName + ":" + originalValue + "#" + namespace + ':' + self.name + 'Refs', id
            when 'boolean'
              multi.zrem self.name + "#" + attr + ":" + originalValue, id
      multiPromise = new Promise (resolve, reject) ->
        multi.exec ->
          sendAttributesForSaving.apply(self, [updateFieldsDiff, skipValidation]).then (writtenObj) ->
            resolve self.find(writtenObj.id)
          , (error) ->
            reject error
      multiPromise.then (obj) ->
        Promise.all(callbackPromises).then ->
          return obj

module.exports = redisObjectDataStore
