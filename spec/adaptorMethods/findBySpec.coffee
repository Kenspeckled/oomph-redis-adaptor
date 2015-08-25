findBy = require '../../src/adaptorMethods/findBy'
create = require '../../src/adaptorMethods/create'
Promise = require 'promise'
_ = require 'lodash'
redis = require 'redis'

describe 'oomphRedisAdaptor#findBy', ->

  beforeAll (done) ->
    @redis = redis.createClient(1111, 'localhost')
    done()

  beforeEach ->
    @parentObject = 
      className: 'TestFindByClass'
      redis: @redis 
      create: create
      classAttributes: 
        name:
          dataType: 'string'
        url:
          dataType: 'string'
          url: true
          urlBaseAttribute: 'name'
        one:
          dataType: 'integer'
          sortable: true
        two:
          dataType: 'integer'
          sortable: true
        three:
          dataType: 'integer'
          sortable: true
        integer:
          dataType: 'integer'
        identifier:
          dataType: 'string'
          identifiable: true
        reference:
          dataType: 'reference'
          referenceModelName: 'Reference'
        manyReferences:
          dataType: 'reference'
          many: true
          referenceModelName: 'Reference'
        sortableString:
          dataType: 'string'
          sortable: true
        sortableInteger:
          dataType: 'integer'
          sortable: true
        searchableText:
          dataType: 'text'
          searchable: true
        searchableString:
          dataType: 'string'
          searchable: true
        boolean:
          dataType: 'boolean'
    @findBy = findBy.bind(@parentObject)

  afterEach (done) ->
    @redis.flushdb()
    done()
  
  afterAll (done) ->
    @redis.flushdb()
    @redis.end()
    done()

  it 'should return a promise', ->
    testObject = @findBy(id: 'test1')
    expect(testObject).toEqual jasmine.any(Promise)

  it "should resolve to a valid instance of the module's class when given an id", (done) ->
    testProps = { url: 'uniqueValue', one: 1, two: 2, three: 3 }
    @parentObject.create(testProps).then (createdObject) =>
      findByPromise = @findBy(id: createdObject.id)
      findByPromise.done (returnValue) ->
        expect(returnValue).toEqual createdObject
        done()

  it "should resolve to a valid instance of the module's class when given a url", (done) ->
    testProps = { url: 'uniqueValue', one: 1, two: 2, three: 3 }
    @parentObject.create(testProps).then (createdObject) =>
      findByPromise = @findBy(url: 'uniqueValue')
      findByPromise.done (returnValue) ->
        expect(returnValue).toEqual createdObject
        done()

  it 'should reject if no object is found', (done) ->
    findByPromise = @findBy(url: 'urlNotFound')
    findByPromise.catch (returnValue) ->
      expect(returnValue).toEqual new Error "Not Found" 
      done()

