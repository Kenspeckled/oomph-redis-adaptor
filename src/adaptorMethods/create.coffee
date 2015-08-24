Promise = require 'promise'
sendAttributesForSaving = require './_redisObjectSave'
redisFind = require './find'

create = (props, skipValidation) ->
  sendAttributesForSaving.apply(this, [props, skipValidation]).then (writtenObject) ->
    resolve redisFind(writtenObject.id) if writtenObject
  , (error) ->
    reject error if error

module.exports = create
