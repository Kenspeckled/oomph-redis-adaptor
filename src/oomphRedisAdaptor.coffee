redis = require 'redis'
all = require './adaptorMethods/all'
find = require './adaptorMethods/find'
findBy = require './adaptorMethods/findBy'
where = require './adaptorMethods/where'
create = require './adaptorMethods/create'
update = require './adaptorMethods/update'
save = require './adaptorMethods/save'
destroy = require './adaptorMethods/destroy'

oomphRedisAdaptor =
    
  connectAdaptor: (_class) ->

    port = global.oomphRedisPort || 6379
    host = global.oomphRedisHost || '127.0.0.1'
    options = global.oomphRedisOptions ||  {}
    _class.redis = redis.createClient(port, host, options) 

    _class.create = create
    _class.update = update
    _class.find = find
    _class.findBy = findBy
    _class.where = where
    _class.all = all

    _class::save = save
    _class::destroy = destroy
    #_class::isValid = -> performValidations(this)

    return _class

module.exports =  oomphRedisAdaptor
