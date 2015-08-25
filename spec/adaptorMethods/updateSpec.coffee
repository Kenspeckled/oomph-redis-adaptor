create = require '../../src/adaptorMethods/create'
update = require '../../src/adaptorMethods/update'
find = require '../../src/adaptorMethods/find'
Promise = require 'promise'
_ = require 'lodash'
redis = require 'redis'

describe 'oomphRedisAdaptor#update', ->

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
    @update = update.bind(@parentObject)

  beforeEach (done) ->
    # set up exisitng test object to update
    testProps =
      one: '0'
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
      done()

  afterEach (done) ->
    @redis.flushdb()
    done()
  
  afterAll (done) ->
    @redis.flushdb()
    @redis.end()
    done()

  it 'should return a promise', ->
    testObjectPromise = @update @testObj.id, url: 'uniqueValue'
    expect(testObjectPromise).toEqual jasmine.any(Promise)

  it 'should throw an error when the id is not found', (done) ->
    testObjectPromise = @update 'invalidID', url: 'takenURL'
    testObjectPromise.catch (error) ->
      expect(error).toEqual new Error "Not Found"
      done()

  it 'should update the object when a change is made', (done) ->
    testObjectPromise = @update @testObj.id, one: 111
    testObjectPromise.then (obj) ->
      expect(obj.one).toEqual 111
      done()

  it 'should update the relevant sorted set when an integer field is updated', (done) ->
    testObjectPromise = @update @testObj.id, integer: 9
    testObjectPromise.then (obj) =>
      @redis.zrangebyscore 'TestUpdateClass>integer', 0, 10, 'withscores', (err, res) =>
        expect(res).toEqual [@testObj.id, '9']
        done()

  it 'should update the relevant key-value pair when an identifier field is updated', (done) ->
    testObjectPromise = @update @testObj.id, identifier: 'edited'
    testObjectPromise.then (obj) =>
      multi = @redis.multi()
      multi.get 'TestUpdateClass#identifier:edited'
      multi.get 'TestUpdateClass#identifier:identifier'
      multi.exec (err, res) =>
        expect(res[0]).toEqual @testObj.id
        expect(res[1]).toEqual null
        expect(res.length).toEqual 2
        done()

  it 'should add to a set when an reference field is updated', (done) ->
    pending()
    testObjectPromise = @update(@testObj.id, manyReferences: ['editedId1'])
    testObjectPromise.then (obj) =>
      @redis.smembers 'TestUpdateClass:' + @testObj.id + '#manyReferences:ReferenceRefs', (err, members) ->
        expect(members).toContain 'editedId1'
        expect(members.length).toEqual 4
        done()

  it 'removes from a set', (done) ->
    @update(@testObj.id, remove_manyReferences: [@ref1Id]).then (createdObject) =>
      @redis.smembers 'Reference:' + @ref1Id + '#manyReferences:TestUpdateClassRefs' , (err, obj) =>
        expect(obj).not.toContain @testObj.id
        done()

  it 'removes from a set', (done) ->
    @parentObject.classAttributes.linkedModel = 
      dataType: 'reference'
      many: true
      referenceModelName: 'LinkedModel'
    @parentObject.create = create.bind(@parentObject)
    @parentObject.create(url: 'one', linkedModel: [@ref1Id, @ref2Id, @ref3Id]).then (testObject) =>
      multi = @redis.multi()
      spyOn(@redis, 'multi').and.returnValue(multi)
      spyOn(multi, 'srem')
      @update(testObject.id, remove_linkedModel: [@ref1Id, @ref3Id]).then (createdObject) =>
        expect(multi.srem).toHaveBeenCalledWith('TestUpdateClass:' + createdObject.id + '#linkedModel:LinkedModelRefs', @ref1Id, @ref3Id  )
        expect(multi.srem).toHaveBeenCalledWith('LinkedModel:' + @ref1Id + '#linkedModel:TestUpdateClassRefs', createdObject.id)
        expect(multi.srem).toHaveBeenCalledWith('LinkedModel:' + @ref3Id + '#linkedModel:TestUpdateClassRefs', createdObject.id)
        done()

  it 'should update the relevant set when a boolean field is updated', (done) ->
    testObjectPromise = @update @testObj.id, boolean: false
    testObjectPromise.then (obj) =>
      multi = @redis.multi()
      multi.zrange 'TestUpdateClass#boolean:false', 0, -1
      multi.zrange 'TestUpdateClass#boolean:true', 0, -1
      multi.exec (err, res) =>
        expect(res[0]).toEqual [@testObj.id]
        expect(res[1]).toEqual []
        expect(res.length).toEqual 2
        done()

  it 'should remove partial words sets when there is a searchable field', (done) ->
    spyOn(@redis, 'zrem').and.callThrough()
    @update(@testObj.id, searchableText: null).then (createdObject) =>
      calledArgs = @redis.zrem.calls.allArgs()
      keysCalled = []
      for call in calledArgs
        keysCalled.push call[0]
      expect(keysCalled).toContain('TestUpdateClass#searchableText/s')
      expect(keysCalled).toContain('TestUpdateClass#searchableText/se')
      expect(keysCalled).toContain('TestUpdateClass#searchableText/sea')
      expect(keysCalled).toContain('TestUpdateClass#searchableText/sear')
      expect(keysCalled).toContain('TestUpdateClass#searchableText/search')
      expect(keysCalled).toContain('TestUpdateClass#searchableText/t')
      expect(keysCalled).toContain('TestUpdateClass#searchableText/th')
      expect(keysCalled).toContain('TestUpdateClass#searchableText/thi')
      expect(keysCalled).toContain('TestUpdateClass#searchableText/this')
      done()

  it 'should update the relevant sorted set when a sortable string is updated', (done) ->
    testObjectPromise = @update @testObj.id, sortableString: 'second'
    testObjectPromise.then (obj) =>
      @redis.zrange "TestUpdateClass>sortableString", 0, -1, (error, list) =>
        expect(list).toEqual [@testObj.id]
        done()

  it 'should update the object', (done) ->
    updateProps = { one: 1, integer: 2, identifier: 'newidentifier', sortableString: 'second', sortableInteger: 2, searchableText: 'new Search this', boolean: false }
    _.assign(@testObj, updateProps)
    testObjectPromise = @update(@testObj.id, updateProps)
    testObjectPromise.then (obj) =>
      @parentObject.find(@testObj.id).then (returnValue) =>
        expect(returnValue.one).toEqual @testObj.one
        expect(returnValue.integer).toEqual @testObj.integer
        expect(returnValue.identifier).toEqual @testObj.identifier
        expect(returnValue.sortableString).toEqual @testObj.sortableString
        expect(returnValue.sortableInteger).toEqual @testObj.sortableInteger
        expect(returnValue.searchableText).toEqual @testObj.searchableText
        expect(returnValue.boolean).toEqual @testObj.boolean
        done()

  describe '"remove_" prefix', ->
    it 'should remove values from a set when an reference is updated', (done) ->
      testObjectPromise = @update @testObj.id, remove_manyReferences: ['ref2Id', '2']
      testObjectPromise.then (obj) =>
        @redis.smembers 'TestUpdateClass:' + @testObj.id + '#manyReferences:ReferenceRefs', (err, members) =>
          expect(members).toContain 'ref1Id'
          expect(members).toContain 'ref3Id'
          expect(members.length).toEqual 2
          done()

