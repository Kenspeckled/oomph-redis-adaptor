Promise = require 'promise'
_ = require 'lodash'
_utilities = require 'oomph/lib/utilities'

numberOfExtraCharactersOnId = 2 # FIXME: duplicated variable

idToSeconds = (id) ->
  parseInt(id.slice(0, -numberOfExtraCharactersOnId), 36)

idToCreatedAtDate = (id) ->
  new Date(idToSeconds(id))

createObjectFromHash = (hash, modelClass) ->
  obj = {}
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
      else if propertyCastType[1] == 'f' # cast as float 
        obj[plainKey] = parseFloat(value)
    else
      obj[key] = value
  return new modelClass(obj) if modelClass and modelClass.prototype
  obj

# FIXME: In need of refactor - lots of code smell
find = (id) ->
  self = this
  referencePromises = []
  getHash = new Promise (resolve, reject) ->
    self.redis.hgetall self.className + ":" + id, (error, hash) ->
      if !hash
        reject new Error "Not Found"
      else
        resolve(hash)
  modifyHashPromise = getHash.then (hash) ->
    for propertyName in Object.keys(self.classAttributes)
      propertyValue = hash[propertyName]
      attrSettings = self.classAttributes[propertyName]
      continue if _.isUndefined(propertyValue)
      if attrSettings.dataType == 'reference'
        if attrSettings.many
          getReferenceIdsFn = (propertyName, referenceModelName) ->
            new Promise (resolve, reject) ->
              referenceKey = self.className + ':' + id + '#' + propertyName + ':' + referenceModelName + 'Refs'
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
      referenceObjects.forEach (refObj) ->
        hash[refObj.propertyName] = refObj.referenceValue
      obj = createObjectFromHash(hash, self)
      if obj.initializedVal instanceof Promise
        obj.initializedVal.then ->
          delete obj.initializedVal
          obj
      else
        delete obj.initializedVal
        obj

module.exports = find
