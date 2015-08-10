sendAttributesForSaving = require './_redisObjectSave'

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

update = (id, updateFields, skipValidation) ->
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
        obj = self.classAttributes[attr]
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

module.exports = update
