Promise = require 'promise'
_ = require 'lodash'
_utilities = require './utilities'
redisFind = require './find'

findKeywordsInAnyFields = (fields, keywords, weightOptions) ->
    unionkeyNames = []
    unionKeyPromises = _.map keywords, (keyword) =>
      keyNames = []
      for field in fields
        weight = (if weightOptions[field] and weightOptions[field].weight then weightOptions[field].weight else 1)
        keyNames.push name: @className + "#" + field + "/" + keyword, weight: weight
      unionKey = 'keywordUnionSet:' + _utilities.randomString(5)
      unionKeyPromise = new Promise (resolve) =>
        @redis.zunionstore unionKey, keyNames.length, _.map(keyNames, 'name')..., 'weights', _.map(keyNames, 'weight')..., ->
          resolve unionKey
      unionKeyPromise.then (unionKey) ->
        unionkeyNames.push unionKey
    Promise.all(unionKeyPromises).then ->
      return unionkeyNames

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

where = (args) ->
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
    sortedSetKeys.push name: self.className + '>id'
  else if args.sortBy != 'relevance'
    sortedSetKeys.push name: self.className + '>' + args.sortBy
  weightOptions = {}
  keywordSearchPromise = new Promise (r) -> r()
  if args.includes
    if args.includes.modifiedWeights
      for modifyObj in args.includes.modifiedWeights
        modifyObjAttrs = if _.isArray(modifyObj.classAttributes) then modifyObj.classAttributes else [modifyObj.classAttributes]
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
          sortedSetKeys.push name: self.className + "#" + field + "/" + keyword, weight: weight
  whereConditionPromises = []
  for option in Object.keys(args)
    optionValue = args[option]
    continue if !self.classAttributes[option]
    switch self.classAttributes[option].dataType
      when 'integer' #add less than and greater than functionality
        tempIntegerKey = 'temporaryIntegerSet:' + _utilities.randomString(5)
        integerSortedSetName = self.className + '>' + option
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
        sortedSetKeys.push  name: self.className + "#" + option + ":" + optionValue
      when 'reference'
        referenceModelName = self.classAttributes[option].referenceModelName
        if referenceModelName 
          namespace = self.classAttributes[option].reverseReferenceAttribute || option
          if self.classAttributes[option].many 
            if optionValue.includesAllOf
              _.each optionValue.includesAllOf, (id) ->
                sortedSetKeys.push name: referenceModelName + ':' + id + '#' + namespace + ':' + self.className + 'Refs'
            if optionValue.includesAnyOf
              _.each optionValue.includesAnyOf, (id) ->
                unionSortedSetKeys.push name: referenceModelName + ':' + id + '#' + namespace + ':' + self.className + 'Refs'
          else
            if optionValue.anyOf
              _.each optionValue.anyOf, (id) ->
                unionSortedSetKeys.push name: referenceModelName + ':' + id + '#' + namespace + ':' + self.className + 'Refs'
            else
              sortedSetKeys.push name: referenceModelName + ':' + optionValue + '#' + namespace + ':' + self.className + 'Refs'
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
          self.redis.sort idKey, 'by', 'nosort', 'get', self.className + ':*->' + f, (err, facetList) ->
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
        redisFind.apply(self, [id])
      Promise.all(promises).then (resultItems) ->
        _resultObject =
          className: self.className
          total: resultObject.totalResults
          offset: start
          facets: resultObject.facetResults
          items: resultItems

module.exports = where
