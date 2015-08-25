Promise = require 'promise'
sendAttributesForSaving = require './_redisObjectSave'
redisFind = require './find'

create = (props, skipValidation) ->
  self = this
  sendAttributesForSaving.apply(self, [props, skipValidation]).then (writtenObject) ->
    throw new Error 'Write error' if !writtenObject
    redisFind.apply(self, [writtenObject.id])
  , (error) ->
    console.log "ERROR", error
    return error

module.exports = create
