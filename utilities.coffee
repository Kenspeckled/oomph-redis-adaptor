Promise = require 'promise'

utilities =

  randomString: (length) ->
    max = parseInt(new Array( length + 1 ).join('z'), 36)
    min = parseInt(((10**(length-1)).toString()),36)
    Math.floor(Math.random()*(max - min)+min).toString(36)

  promiseWhile: (conditionFn, fn) ->
    new Promise (resolve, reject) ->
      promiseLoop = (output) ->
        if !conditionFn()
          return resolve(output)
        fn() # must return a promise
        .then(promiseLoop)
      process.nextTick(promiseLoop)

  promiseEachFn: (promiseFnArray) ->
    promiseReturnArray = []
    if promiseFnArray.length > 0
      firstPromiseFn = promiseFnArray.shift()
      promise = firstPromiseFn()
      promiseReturnArray.push promise
    else
      promise = new Promise (resolve) ->
        resolve()
    promiseFnArray.forEach (fn) =>
      promise = promise.then(fn)
      promiseReturnArray.push promise
    Promise.all(promiseReturnArray)

module.exports = utilities
