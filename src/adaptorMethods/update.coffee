Promise = require 'promise'
_ = require 'lodash'
sendAttributesForSaving = require './_redisObjectSave'

removeIndexedSearchableString = (attr, words, id) ->
  indexPromises = []
  for word in words.split /\s/
    word = word.toLowerCase()
    wordSegment = ''
    for char in word
      wordSegment += char
      wordSegmentKey = @className + '#' + attr + '/' + wordSegment
      indexPromiseFn = (wordSegmentKey, id) =>
        new Promise (resolve) =>
          @redis.zrem wordSegmentKey, id, (res) ->
            resolve()
      indexPromises.push indexPromiseFn(wordSegmentKey, id)
  Promise.all(indexPromises)

update = (id, updateFields, skipValidation) ->
  self = this
  callbackPromises = []
  multi = self.redis.multi()
  getOriginalObjPromise = self.find(id).then (originalObj) ->
    if !originalObj
      throw new Error "Not Found"
    return originalObj
  getOriginalObjPromise.then (originalObj) ->
    updateFieldsDiff = _.clone(originalObj, true)
    for attr in Object.keys(updateFields)
      remove = false
      if attr.match(/^remove_/)
        remove = true
        removeValue = updateFields[attr]
        attr = attr.replace(/^remove_/, '')
      orderedSetName = self.className + '>' + attr
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
            sortedSetName = self.className + '>' + attr
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
              multi.del self.className + "#" + attr + ":" + originalValue
          when 'reference'
            namespace = obj.reverseReferenceAttribute || attr
            if obj.many
              if remove
                multi.srem self.className + ":" +  id + "#" + attr + ':' + obj.referenceModelName + 'Refs', removeValue...
                removeValue.forEach (vid) ->
                  multi.srem obj.referenceModelName + ":" +  vid + "#" + namespace + ':' + self.className + 'Refs', id
              else
                originalIds = _.map(originalValue, 'id')
                intersectingValues = _.intersection(originalIds, newValue)
                updateFieldsDiff[attr] = intersectingValues if !_.isEmpty(intersectingValues)
            else
              if remove
                multi.srem obj.referenceModelName + ":" + originalValue + "#" + namespace + ':' + self.className + 'Refs', id
          when 'boolean'
            multi.zrem self.className + "#" + attr + ":" + originalValue, id
    multiPromise = new Promise (resolve, reject) ->
      multi.exec ->
        findPromise = sendAttributesForSaving.apply(self, [updateFieldsDiff, skipValidation]).then (writtenObj) ->
          self.find(writtenObj.id)
        findPromise.then (found) ->
          resolve(found)
    multiPromise.then (obj) ->
      Promise.all(callbackPromises).then ->
        return obj

module.exports = update
