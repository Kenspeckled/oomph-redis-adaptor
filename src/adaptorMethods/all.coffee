_ = require 'lodash'
redisWhere = require './where'

all = (args) ->
  allArgs = if _.isEmpty(args) then {} else _.pick(args, ['sortBy', 'sortDirection', 'limit', 'offset'])
  redisWhere.apply(this, [allArgs])

module.exports = all
