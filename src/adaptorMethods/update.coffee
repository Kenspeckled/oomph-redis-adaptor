Promise = require 'promise'
_ = require 'lodash'
sendAttributesForSaving = require './_redisObjectSave'
redisFind = require './find'

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

update = (id, updateFields, skipValidation, skipAfterSave) ->
  self = this
  callbackPromises = []
  multi = self.redis.multi()
  getOriginalObjPromise = redisFind.apply(self, [id]).then (originalObj) ->
    return Promise.reject new Error "Not Found" if !originalObj
    originalObj
  getOriginalObjPromise.then (originalObj) ->
    updateFieldsDiff = id: id # need to set the id in the object
    for attr in Object.keys(updateFields)
      remove = false
      if attr.match(/^remove_/)
        remove = true
        removeValue = updateFields[attr]
        attr = attr.replace(/^remove_/, '')
      orderedSetName = self.className + '>' + attr
      originalValue = originalObj[attr]
      newValue = updateFields[attr]
      updateFieldsDiff[attr] = newValue
      # if there is an actual change and a value to change to
      if !(newValue == undefined or newValue == null) and (newValue != originalValue) or remove 
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
              if remove and removeValue
                multi.srem self.className + ":" +  id + "#" + attr + ':' + obj.referenceModelName + 'Refs', removeValue...
                removeValue.forEach (vid) ->
                  multi.srem obj.referenceModelName + ":" +  vid + "#" + namespace + ':' + self.className + 'Refs', id
              else
                originalIds = _.map(originalValue, 'id')
                intersectingValues = _.intersection(originalIds, newValue)
                updateFieldsDiff[attr] = intersectingValues if !_.isEmpty(intersectingValues)
            else
              multi.srem obj.referenceModelName + ":" + originalValue.id + "#" + namespace + ':' + self.className + 'Refs', id
          when 'boolean'
            multi.zrem self.className + "#" + attr + ":" + originalValue, id
    multiPromise = new Promise (resolve, reject) ->
      multi.exec ->
        resolve()
    multiPromise.then ->
      sendAttributesForSaving.apply(self, [updateFieldsDiff, skipValidation]).then (writtenObj) ->
        Promise.all(callbackPromises).then ->
          redisFind.apply(self, [writtenObj.id]).then (found) ->
            afterSavePromise = if found.afterSave? and !skipAfterSave then found.afterSave() else null 
            Promise.all([afterSavePromise]).then ->
              found

module.exports = update
