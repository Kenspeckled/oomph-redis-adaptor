redisFind = require './find'
Promise = require 'promise'

findBy = (option) ->
  p = new Promise (resolve, reject) =>
    optionName = Object.keys(option)[0]
    condition = option[optionName]
    if optionName == 'id'
      resolve condition
    else
      if @classAttributes[optionName].dataType == 'string' and (@classAttributes[optionName].identifiable or @classAttributes[optionName].url)
        stringName = @className + "#" + optionName + ":" + condition
        @redis.get stringName, (err, res) ->
          resolve res
      else
        reject( throw new Error "Not an identifier" )
  p.then (res) =>
    redisFind.apply(this, [res])

module.exports = findBy
