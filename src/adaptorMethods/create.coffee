Promise = require 'promise'
sendAttributesForSaving = require './_redisObjectSave'
redisFind = require './find'

create = (props, skipValidation) ->
  sendAttributesForSaving.apply(this, [props, skipValidation]).then (writtenObject) ->
    throw new Error 'Write error' if !writtenObject
    return redisFind.apply(this, [writtenObject.id]) 
  , (error) ->
    return error

module.exports = create
