_ = require 'lodash'

all = (args) ->
  allArgs = _.pick(args, ['sortBy', 'sortDirection', 'limit', 'offset'])
  @where(allArgs)

module.exports = all
