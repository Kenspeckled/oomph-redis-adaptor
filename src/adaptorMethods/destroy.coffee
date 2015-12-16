Promise = require 'promise'
redisUpdate = require './update'

destroy = (id) ->
  return new Error 'Can\'t find object\'s id' if !id
  removeFields = {}
  for attr in Object.keys(@classAttributes)
    removeFields['remove_' + attr] = (this[attr] || "")
  removeAttributes = redisUpdate.apply(this, [id, removeFields, true]).then (newProps) =>
    new Promise (resolve, reject) =>
      @redis.zrem @className + '>id', id, (err, response) ->
        resolve()
  removeAttributes.then =>
    new Promise (resolve, reject) =>
      @redis.del @className + ':' + id, (err, response) ->
        return reject(err) if err
        resolve(true)
  
module.exports = destroy
