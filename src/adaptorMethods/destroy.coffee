Promise = require 'promise'
redisCreate = require './create'
redisUpdate = require './update'
_ = require 'lodash'

destroy = ->
  return new Error 'Can\'t find object\'s id' if !@id 
  removeFields = {}
  for attr in Object.keys(@constructor.classAttributes)
    removeFields['remove_' + attr] = this[attr] if this[attr]
  redisUpdate.apply(@constructor, [@id, removeFields]).then (newProps) =>
    new Promise (resolve, reject) =>
      @constructor.redis.del @constructor.className + ':' + @id, (err, response) ->
        return reject(err) if err
        resolve(true)
  
module.exports = destroy
