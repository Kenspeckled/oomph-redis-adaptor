redisCreate = require './create'
redisUpdate = require './update'
_ = require 'lodash'

save = ->
  if @id
    updateFields = {}
    for attr in Object.keys(@constructor.classAttributes)
      updateFields[attr] = this[attr] if this[attr]
    redisUpdate.apply(@constructor, [@id, updateFields]).then (newProps) =>
      _.assign(this, newProps)
  else
    redisCreate.apply(@constructor, [this]).then (newProps) =>
      _.assign(this, newProps)

module.exports = save
