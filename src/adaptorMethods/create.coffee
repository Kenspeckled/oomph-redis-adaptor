Promise = require 'promise'
sendAttributesForSaving = require './_redisObjectSave'

create = (props, skipValidation) ->
  new Promise (resolve, reject) =>
    sendAttributesForSaving.apply(this, [props, skipValidation]).then (writtenObject) =>
      resolve @find(writtenObject.id) if writtenObject
    , (error) ->
      reject error if error

module.exports = create
