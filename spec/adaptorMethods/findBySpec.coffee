findBy = require '../../src/adaptorMethods/findBy'
Promise = require 'promise'
_ = require 'lodash'

describe 'oomphRedisAdaptor#findBy', ->
  
  beforeAll ->
    parentObject = 
      classAttributes: {}
    @findBy = findBy.bind(parentObject)

  it 'should return a promise', ->
    testObject = @findBy(id: 'test1')
    expect(testObject).toEqual jasmine.any(Promise)

  it "should resolve to a valid instance of the module's class when given an id", (done) ->
    testProps = { url: 'uniqueValue', one: 1, two: 2, three: 3 }
    @create(testProps).then (createdObject) =>
      findByPromise = @findBy(id: createdObject.id)
      findByPromise.done (returnValue) ->
        expect(returnValue).toEqual createdObject
        done()

  it "should resolve to a valid instance of the module's class when given a url", (done) ->
    testProps = { url: 'uniqueValue', one: 1, two: 2, three: 3 }
    @create(testProps).then (createdObject) =>
      findByPromise = @findBy(url: 'uniqueValue')
      findByPromise.done (returnValue) ->
        expect(returnValue).toEqual createdObject
        done()

  it 'should reject if no object is found', (done) ->
    findByPromise = @findBy(url: 'urlNotFound')
    findByPromise.catch (returnValue) ->
      expect(returnValue).toEqual new Error "Not Found" 
      done()

