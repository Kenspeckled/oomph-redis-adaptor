_ = require 'lodash'
redisObjectClassDataStore = require './redisObjectClassDataStore'

redisObjectInstanceDataStore =
  
  save: ->
    if @id 
      updateFields = {}
      for attr in Object.keys(@constructor.attributes)
        updateFields[attr] = this[attr] if this[attr]
      redisObjectClassDataStore.update.apply(@constructor, [@id, updateFields]).then (newProps) =>
        _.assign(this, newProps)
    else
      redisObjectClassDataStore.create.apply(@constructor, [this]).then (newProps) =>
        _.assign(this, newProps)
    

module.exports = redisObjectInstanceDataStore
