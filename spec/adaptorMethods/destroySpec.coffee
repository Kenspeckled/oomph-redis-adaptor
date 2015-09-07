create = require '../../src/adaptorMethods/create'
destroy = require '../../src/adaptorMethods/destroy'
find = require '../../src/adaptorMethods/find'
Promise = require 'promise'
_ = require 'lodash'
redis = require 'redis'

describe 'oomphRedisAdaptor#destroy', ->

  beforeAll (done) ->
    @redis = redis.createClient(1111, 'localhost')
    done()

  beforeEach ->
    @parentObject = 
      className: 'TestUpdateClass'
      redis: @redis
      create: create
      find: find
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

  beforeEach (done) ->
    # set up exisitng test object to destroy
    testProps =
      one: 0
      integer: 1
      identifier: "identifier"
      boolean: true
      reference: "reference"
      manyReferences: ['ref1Id', 'ref2Id', 'ref3Id']
      searchableText: "Search this"
      sortableString: "first"
      sortableInteger: 1
    @parentObject.create(testProps).then (createdTestObj) =>
      @testObj = createdTestObj
      @originalObj = _.clone(@testObj, true)
      @testObj.constructor = @parentObject
      @testObj.destroy = destroy
      done()

  afterEach (done) ->
    @redis.flushdb()
    done()
  
  afterAll (done) ->
    @redis.flushdb()
    @redis.end()
    done()

  it 'should return a promise', ->
    testObjectPromise = @testObj.destroy()
    expect(testObjectPromise).toEqual jasmine.any(Promise)

  it 'should make a find not return item', (done) ->
    @parentObject.find(@testObj.id).then (found) =>
      expect(found).toEqual(@originalObj)
      @testObj.destroy().then =>
        @parentObject.find(@testObj.id).catch (error) =>
          expect(error).toEqual(new Error "Not Found")
          done()

