update = require '../../src/adaptorMethods/update'
Promise = require 'promise'
_ = require 'lodash'

describe 'oomphRedisAdaptor#update', ->

  beforeAll ->
    parentObject = 
      redis: 
        multi: -> {
          zrem: -> null
          exec: -> null
        }
      find: (id) -> 
        new Promise (resolve,reject) -> 
          if id == 'invalidID'
            resolve(null)
          else
            resolve({})
      classAttributes:
        one:
          dataType: 'integer'
    @update = update.bind(parentObject)

  #beforeEach (done) ->
  #  ref1 = @referenceModel.create(secondId: 'ida')
  #  ref2 = @referenceModel.create(secondId: 'idb')
  #  ref3 = @referenceModel.create(secondId: 'idc')
  #  Promise.all([ref1,ref2,ref3]).done (refs) =>
  #    @ref1Id = refs[0].id
  #    @ref2Id = refs[1].id
  #    @ref3Id = refs[2].id
  #    testProps =
  #      one: '0'
  #      integer: 1
  #      identifier: "identifier"
  #      boolean: true
  #      reference: "reference"
  #      manyReferences: [@ref1Id, @ref2Id, @ref3Id]
  #      searchableText: "Search this"
  #      sortableString: "first"
  #      sortableInteger: 1
  #    @redisObjectClassDataStore.create(testProps).done (testObject) =>
  #      @testObj = testObject
  #      done()

  it 'should return a promise', ->
    testObjectPromise = @update 'testObjID', url: 'uniqueValue'
    expect(testObjectPromise).toEqual jasmine.any(Promise)

  it 'should throw an error when the id is not found', (done) ->
    testObjectPromise = @update 'invalidID', url: 'takenURL'
    testObjectPromise.catch (error) ->
      expect(error).toEqual new Error "Not Found"
      done()

  it 'should update the object when a change is made', (done) ->
    testObjectPromise = @update 'testObjID', one: 111
    testObjectPromise.done (obj) ->
      expect(obj.one).toEqual 111
      done()

  #it 'should update the relevant sorted set when an integer field is updated', (done) ->
  #  testObjectPromise = @redisObjectClassDataStore.update @testObj.id, integer: 9
  #  testObjectPromise.done (obj) =>
  #    @redisObjectClassDataStore.redis.zrangebyscore 'RedisObjectClassDataStore>integer', 0, 10, 'withscores', (err, res) =>
  #      expect(res).toEqual [@testObj.id, '9']
  #      done()

  #it 'should update the relevant key-value pair when an identifier field is updated', (done) ->
  #  testObjectPromise = @redisObjectClassDataStore.update @testObj.id, identifier: 'edited'
  #  testObjectPromise.done (obj) =>
  #    multi = @redisObjectClassDataStore.redis.multi()
  #    multi.get 'RedisObjectClassDataStore#identifier:edited'
  #    multi.get 'RedisObjectClassDataStore#identifier:identifier'
  #    multi.exec (err, res) =>
  #      expect(res[0]).toEqual @testObj.id
  #      expect(res[1]).toEqual null
  #      expect(res.length).toEqual 2
  #      done()

  #it 'should add to a set when an reference field is updated', (done) ->
  #  pending()
  #  testObjectPromise = @redisObjectClassDataStore.update(@testObj.id, manyReferences: ['editedId1'])
  #  testObjectPromise.done (obj) =>
  #    @redisObjectClassDataStore.redis.smembers 'RedisObjectClassDataStore:' + @testObj.id + '#manyReferences:ReferenceRefs', (err, members) ->
  #      expect(members).toContain 'editedId1'
  #      expect(members.length).toEqual 4
  #      done()

  #it 'removes from a set', (done) ->
  #  @redisObjectClassDataStore.update(@testObj.id, remove_manyReferences: [@ref1Id]).then (createdObject) =>
  #    @redis.smembers 'Reference:' + @ref1Id + '#manyReferences:RedisObjectClassDataStoreRefs' , (err, obj) =>
  #      expect(obj).not.toContain @testObj.id
  #      done()

  #it 'removes from a set', (done) ->
  #  @redisObjectClassDataStore.attributes.linkedModel = 
  #    dataType: 'reference'
  #    many: true
  #    referenceModelName: 'LinkedModel'
  #  @redisObjectClassDataStore.create(url: 'one', linkedModel: [@ref1Id, @ref2Id, @ref3Id]).done (testObject) =>
  #    multi = @redisObjectClassDataStore.redis.multi()
  #    spyOn(@redisObjectClassDataStore.redis, 'multi').and.returnValue(multi)
  #    spyOn(multi, 'srem')
  #    @redisObjectClassDataStore.update(testObject.id, remove_linkedModel: [@ref1Id, @ref3Id]).then (createdObject) =>
  #      expect(multi.srem).toHaveBeenCalledWith('RedisObjectClassDataStore:' + createdObject.id + '#linkedModel:LinkedModelRefs', @ref1Id, @ref3Id  )
  #      expect(multi.srem).toHaveBeenCalledWith('LinkedModel:' + @ref1Id + '#linkedModel:RedisObjectClassDataStoreRefs', createdObject.id)
  #      expect(multi.srem).toHaveBeenCalledWith('LinkedModel:' + @ref3Id + '#linkedModel:RedisObjectClassDataStoreRefs', createdObject.id)
  #      done()

  #it 'should update the relevant set when a boolean field is updated', (done) ->
  #  testObjectPromise = @redisObjectClassDataStore.update @testObj.id, boolean: false
  #  testObjectPromise.done (obj) =>
  #    multi = @redisObjectClassDataStore.redis.multi()
  #    multi.zrange 'RedisObjectClassDataStore#boolean:false', 0, -1
  #    multi.zrange 'RedisObjectClassDataStore#boolean:true', 0, -1
  #    multi.exec (err, res) =>
  #      expect(res[0]).toEqual [@testObj.id]
  #      expect(res[1]).toEqual []
  #      expect(res.length).toEqual 2
  #      done()

  #it 'should remove partial words sets when there is a searchable field', (done) ->
  #  spyOn(@redisObjectClassDataStore.redis, 'zrem').and.callThrough()
  #  @redisObjectClassDataStore.update(@testObj.id, searchableText: null).then (createdObject) =>
  #    calledArgs = @redisObjectClassDataStore.redis.zrem.calls.allArgs()
  #    keysCalled = []
  #    for call in calledArgs
  #      keysCalled.push call[0]
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/s')
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/se')
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/sea')
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/sear')
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/search')
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/t')
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/th')
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/thi')
  #    expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/this')
  #    done()

  #it 'should update the relevant sorted set when a sortable string is updated', (done) ->
  #  testObjectPromise = @redisObjectClassDataStore.update @testObj.id, sortableString: 'second'
  #  testObjectPromise.done (obj) =>
  #    @redis.zrange "RedisObjectClassDataStore>sortableString", 0, -1, (error, list) =>
  #      expect(list).toEqual [@testObj.id]
  #      done()

  #it 'should update the object', (done) ->
  #  updateProps = { one: 1, integer: 2, identifier: 'newidentifier', sortableString: 'second', sortableInteger: 2, searchableText: 'new Search this', boolean: false }
  #  _.assign(@testObj, updateProps)
  #  testObjectPromise = @redisObjectClassDataStore.update @testObj.id, updateProps
  #  testObjectPromise.done (obj) =>
  #    @redisObjectClassDataStore.find(@testObj.id).done (returnValue) =>
  #      expect(returnValue).toEqual @testObj
  #      done()

  #describe '"remove_" prefix', ->
  #  it 'should remove values from a set when an reference is updated', (done) ->
  #    testObjectPromise = @redisObjectClassDataStore.update @testObj.id, remove_manyReferences: [@ref2Id, '2']
  #    testObjectPromise.done (obj) =>
  #      @redisObjectClassDataStore.redis.smembers 'RedisObjectClassDataStore:' + @testObj.id + '#manyReferences:ReferenceRefs', (err, members) =>
  #        expect(members).toContain @ref1Id 
  #        expect(members).toContain @ref3Id
  #        expect(members.length).toEqual 2
  #        done()

