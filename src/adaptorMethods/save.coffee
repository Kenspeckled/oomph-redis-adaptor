_ = require 'lodash'

save = ->
  if @id 
    updateFields = {}
    for attr in Object.keys(@constructor.classAttributes)
      updateFields[attr] = this[attr] if this[attr]
    @constructor.update(@id, updateFields).then (newProps) =>
      _.assign(this, newProps)
  else
    @constructor.create(this).then (newProps) =>
      _.assign(this, newProps)
  
module.exports = save
