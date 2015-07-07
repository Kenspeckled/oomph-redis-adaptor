Redis = require 'redis'
Promise = require 'promise'
redisObjectClassDataStore = require '../../src/privateModules/redisObjectClassDataStore'
_ = require 'lodash'
_utilities = require '../../src/utilities'
ValidationError = require '../../src/models/ValidationError'

describe 'redisObjectClassDataStore', ->

  beforeAll (done) ->
    @redis = Redis.createClient(1111, 'localhost')
    @redis.on "error", ->
      throw new Error "Redis server not connected on port 1111 - try running 'redis-server --port 1111 &'"
    @redis.on "ready", =>
      @redis.flushdb()
      done()
    @redisObjectClassDataStore = _.clone redisObjectClassDataStore
    @redisObjectClassDataStore.name = 'RedisObjectClassDataStore'
    @redisObjectClassDataStore.prototype = null
    @redisObjectClassDataStore.redis = @redis

    @referenceModel = _.clone redisObjectClassDataStore
    @referenceModel.name = 'Reference'
    @referenceModel.prototype = null
    @referenceModel.redis = @redis

  beforeEach ->
    @referenceModel.attributes =
      secondId:
        dataType: 'string'
    @redisObjectClassDataStore.attributes =
      url:
        dataType: 'string'
        identifiable: true
        sortable: true
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
        sortable: true
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

  afterEach ->
    @redis.flushdb()

  afterAll ->
    @redis.flushdb()
    @redis.end()

  it 'should be a valid module', ->
    expect(@redisObjectClassDataStore).toEqual jasmine.any(Object)
    expect(@redisObjectClassDataStore.name).toEqual "RedisObjectClassDataStore"

  describe '#create', ->
    it 'should return a promise', ->
      createPromise = @redisObjectClassDataStore.create(integer: 1)
      expect(createPromise).toEqual jasmine.any(Promise)

    describe 'stored data types', ->
      describe 'for string attributes', ->

        describe 'where identifiable is true', ->
          it 'adds to a key-value pair', (done) ->
            multi = @redisObjectClassDataStore.redis.multi()
            spyOn(@redisObjectClassDataStore.redis, 'multi').and.returnValue(multi)
            spyOn(multi, 'set')
            @redisObjectClassDataStore.create(identifier: 'identifierValue').then (createdObject) ->
              expect(multi.set).toHaveBeenCalledWith('RedisObjectClassDataStore#identifier:identifierValue', createdObject.id)
              done()

        describe 'where url is true', ->
          it 'sores the generated url string in the object hash ', (done) ->
            @redisObjectClassDataStore.attributes =
              name:
                dataType: 'string'
              url:
                dataType: 'string'
                url: true
                urlBaseAttribute: 'name'
            @redisObjectClassDataStore.create(name: "Héllo & gøød nîght").then (createdObject) ->
              expect(createdObject.url).toEqual 'hello-and-good-night' 
              done()

          it 'adds to a key-value pair with a generated url string', (done) ->
            @redisObjectClassDataStore.attributes =
              name:
                dataType: 'string'
              url:
                dataType: 'string'
                url: true
                urlBaseAttribute: 'name'
            multi = @redisObjectClassDataStore.redis.multi()
            spyOn(@redisObjectClassDataStore.redis, 'multi').and.returnValue(multi)
            spyOn(multi, 'set')
            @redisObjectClassDataStore.create(name: "Héllo & gøød nîght").then (createdObject) ->
              expect(multi.set).toHaveBeenCalledWith('RedisObjectClassDataStore#url:hello-and-good-night', createdObject.id)
              done()

          it "appends a sequential number for duplicate generated url string", (done) ->
            @redisObjectClassDataStore.attributes =
              name:
                dataType: 'string'
              url:
                dataType: 'string'
                url: true
                urlBaseAttribute: 'name'
            @redisObjectClassDataStore.create(name: "Héllo & gøød nîght").then (obj1) =>
              @redisObjectClassDataStore.create(name: "Héllo & good night").then (obj2) =>
                @redisObjectClassDataStore.create(name: "Hello & good night").then (obj3) ->
                  expect(obj1.url).toEqual 'hello-and-good-night' 
                  expect(obj2.url).toEqual 'hello-and-good-night-1' 
                  expect(obj3.url).toEqual 'hello-and-good-night-2' 
                  done()

        describe 'where sortable is true', ->
          it 'adds to an ordered list', (done) ->
            testPromise1 = @redisObjectClassDataStore.create( sortableString: 'd' )
            testPromise2 = @redisObjectClassDataStore.create( sortableString: 'a' )
            testPromise3 = @redisObjectClassDataStore.create( sortableString: 'c' )
            testPromise4 = @redisObjectClassDataStore.create( sortableString: 'b' )
            Promise.all([testPromise1,testPromise2,testPromise3,testPromise4]).done (testObjectArray) =>
              test1Id = testObjectArray[0].id
              test2Id = testObjectArray[1].id
              test3Id = testObjectArray[2].id
              test4Id = testObjectArray[3].id
              @redis.zrange "RedisObjectClassDataStore>sortableString", 0, -1, (error, list) ->
                expect(list).toEqual [test1Id, test3Id, test4Id, test2Id]
                done()

        describe 'where searchable is true', ->
          it 'adds to partial words sets when the modules class has attributes with the field type of "string" and is searchable', (done) ->
            spyOn(@redisObjectClassDataStore.redis, 'zadd').and.callThrough()
            @redisObjectClassDataStore.create(searchableText: 'Search This').then (createdObject) =>
              calledArgs = @redisObjectClassDataStore.redis.zadd.calls.allArgs()
              keysCalled = []
              for call in calledArgs
                keysCalled.push call[0]
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/s')
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/se')
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/sea')
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/sear')
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/search')
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/t')
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/th')
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/thi')
              expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/this')
              done()

      describe 'for integer attributes', ->

        # Integers are always sortable
        it 'adds to a sorted set', (done) ->
          testPromise1 = @redisObjectClassDataStore.create( integer: 11 )
          testPromise2 = @redisObjectClassDataStore.create( integer: 8 )
          testPromise3 = @redisObjectClassDataStore.create( integer: 10 )
          testPromise4 = @redisObjectClassDataStore.create( integer: 9 )
          Promise.all([testPromise1,testPromise2,testPromise3,testPromise4]).done (testObjectArray) =>
            test1Id = testObjectArray[0].id
            test2Id = testObjectArray[1].id
            test3Id = testObjectArray[2].id
            test4Id = testObjectArray[3].id
            @redis.zrange "RedisObjectClassDataStore>integer", 0, -1, (error, list) ->
              expect(list).toEqual [test2Id, test4Id, test3Id, test1Id]
              done()

        it 'adds to a sorted set with values', (done) ->
          multi = @redisObjectClassDataStore.redis.multi()
          spyOn(@redisObjectClassDataStore.redis, 'multi').and.returnValue(multi)
          spyOn(multi, 'zadd')
          @redisObjectClassDataStore.create(integer: 1).then (createdObject) ->
            expect(multi.zadd).toHaveBeenCalledWith('RedisObjectClassDataStore>integer', 1, createdObject.id)
            done()


      describe 'for boolean attributes', ->
        it 'adds to a zset', (done) ->
          multi = @redisObjectClassDataStore.redis.multi()
          spyOn(@redisObjectClassDataStore.redis, 'multi').and.returnValue(multi)
          spyOn(multi, 'zadd')
          @redisObjectClassDataStore.create(boolean: true).then (createdObject) ->
            expect(multi.zadd).toHaveBeenCalledWith('RedisObjectClassDataStore#boolean:true', 1, createdObject.id)
            done()

      describe 'for reference attributes', ->

        describe 'when many is true', ->

          it "sets the reference to true", (done) ->
            @referenceModel.create(secondId: 'id1').then (ref1) =>
              @redisObjectClassDataStore.create(manyReferences: [ref1.id]).then (createdObject) =>
                @redis.hgetall 'RedisObjectClassDataStore:' + createdObject.id, (err, obj) ->
                  expect(obj.manyReferences).toEqual 'true'
                  done()

          it "sets the reference to even when empty", (done) ->
            @referenceModel.create(secondId: 'id1').then (ref1) =>
              @redisObjectClassDataStore.create(url: 'one').then (createdObject) =>
                @redis.hgetall 'RedisObjectClassDataStore:' + createdObject.id, (err, obj) ->
                  expect(obj.manyReferences).toEqual 'true'
                  done()

          it 'adds to a set', (done) ->
            @redisObjectClassDataStore.attributes =
              linkedModel:
                dataType: 'reference'
                many: true
                referenceModelName: 'LinkedModel'
            multi = @redisObjectClassDataStore.redis.multi()
            spyOn(@redisObjectClassDataStore.redis, 'multi').and.returnValue(multi)
            spyOn(multi, 'sadd')
            @redisObjectClassDataStore.create(linkedModel: ['linkedModelId1', 'linkedModelId2']).then (createdObject) ->
              expect(multi.sadd).toHaveBeenCalledWith('RedisObjectClassDataStore:' + createdObject.id + '#linkedModel:LinkedModelRefs', 'linkedModelId1', 'linkedModelId2')
              expect(multi.sadd).toHaveBeenCalledWith('LinkedModel:linkedModelId1#linkedModel:RedisObjectClassDataStoreRefs', createdObject.id)
              expect(multi.sadd).toHaveBeenCalledWith('LinkedModel:linkedModelId2#linkedModel:RedisObjectClassDataStoreRefs', createdObject.id)
              done()

          it 'adds to a set with a reverseReferenceAttribute', (done) ->
            @redisObjectClassDataStore.attributes =
              linkedModel:
                dataType: 'reference'
                many: true
                referenceModelName: 'LinkedModel'
                reverseReferenceAttribute: 'namespaced'
            multi = @redisObjectClassDataStore.redis.multi()
            spyOn(@redisObjectClassDataStore.redis, 'multi').and.returnValue(multi)
            spyOn(multi, 'sadd')
            @redisObjectClassDataStore.create(linkedModel: ['linkedModelId1', 'linkedModelId2']).then (createdObject) ->
              expect(multi.sadd).toHaveBeenCalledWith('RedisObjectClassDataStore:' + createdObject.id + '#linkedModel:LinkedModelRefs', 'linkedModelId1', 'linkedModelId2')
              expect(multi.sadd).toHaveBeenCalledWith('LinkedModel:linkedModelId1#namespaced:RedisObjectClassDataStoreRefs', createdObject.id)
              expect(multi.sadd).toHaveBeenCalledWith('LinkedModel:linkedModelId2#namespaced:RedisObjectClassDataStoreRefs', createdObject.id)
              done()

        describe 'when many is not true', ->
          it 'stores the reference id', (done) ->
            @referenceModel.create(secondId: 'id1').done (ref1) =>
              @redisObjectClassDataStore.create(reference: ref1.id).then (createdObject) =>
                @redis.hgetall 'RedisObjectClassDataStore:' + createdObject.id, (err, obj) ->
                  expect(obj.reference).toEqual ref1.id 
                  done()


  describe '#find', ->

    it 'should return a promise', ->
      testObject = @redisObjectClassDataStore.find('test1')
      expect(testObject).toEqual jasmine.any(Promise)

    it 'should resolve to a valid instance of the modules class when given an id', (done) ->
      pending()
      #redisObjectClassDataStoreClass = @redisObjectClassDataStoreClass
      #testProps = { one: 1, two: 2, three: 3 }
      #test1Object = new redisObjectClassDataStoreClass(testProps)
      #@redisObjectClassDataStore.create(testProps).then (returnObject) =>
      #  id = returnObject.id
      #  findPromise = @redisObjectClassDataStore.find(id)
      #  findPromise.done (returnValue) ->
      #    # remove generated props for the test
      #    delete returnValue.id
      #    delete returnValue.createdAt
      #    expect(returnValue).toEqual test1Object
      #    done()

    it 'should reject if no object is found', (done) ->
      findPromise = @redisObjectClassDataStore.find('testNotFound')
      findPromise.catch (error) ->
        expect(error).toEqual new Error "Not Found"
        done()

    it 'should create an object of the same class as the module owner', (done) ->
      pending()

    it 'should return an integer correctly', (done) ->
      testProps = { integer: '1'}
      @redisObjectClassDataStore.create(testProps).then (createdObject) =>
        findPromise = @redisObjectClassDataStore.find(createdObject.id)
        findPromise.done (returnValue) ->
          expect(returnValue.integer).toEqual jasmine.any(Number)
          done()

    it 'should return the reference id when many is false', (done) ->
      @redisObjectClassDataStore.attributes =
        singleReference:
          dataType: 'reference'
          referenceModelName: 'Reference'
          many: false
      createReferencePromise =  @referenceModel.create(secondId: 'id1')
      createReferencePromise.then (ref1) =>
        @redisObjectClassDataStore.create(singleReference: ref1.id).then (createdObject) =>
          findPromise = @redisObjectClassDataStore.find(createdObject.id)
          findPromise.done (foundObj) ->
            expect(foundObj.singleReference).toEqual ref1
            done()

    it 'should return an array of reference ids when many is true', (done) ->
      ref1 = @referenceModel.create(secondId: 'id1')
      ref2 = @referenceModel.create(secondId: 'id2')
      ref3 = @referenceModel.create(secondId: 'id3')
      createReferencesPromise = Promise.all([ref1, ref2, ref3])
      createReferencesPromise.done (referencesObjects) =>
        referenceIds = _.map referencesObjects, 'id'
        testProps =  manyReferences: referenceIds, url: 'new'
        @redisObjectClassDataStore.create(testProps).then (createdObject) =>
          findPromise = @redisObjectClassDataStore.find(createdObject.id)
          findPromise.done (foundObj) ->
            expect(foundObj.manyReferences).toContain referencesObjects[0]
            expect(foundObj.manyReferences).toContain referencesObjects[1]
            expect(foundObj.manyReferences).toContain referencesObjects[2]
            expect(foundObj.manyReferences.length).toEqual 3
            done()

  describe '#findBy', ->
    it 'should return a promise', ->
      testObject = @redisObjectClassDataStore.findBy(id: 'test1')
      expect(testObject).toEqual jasmine.any(Promise)

    it "should resolve to a valid instance of the module's class when given an id", (done) ->
      testProps = { url: 'uniqueValue', one: 1, two: 2, three: 3 }
      @redisObjectClassDataStore.create(testProps).then (createdObject) =>
        findByPromise = @redisObjectClassDataStore.findBy(id: createdObject.id)
        findByPromise.done (returnValue) ->
          expect(returnValue).toEqual createdObject
          done()

    it "should resolve to a valid instance of the module's class when given a url", (done) ->
      testProps = { url: 'uniqueValue', one: 1, two: 2, three: 3 }
      @redisObjectClassDataStore.create(testProps).then (createdObject) =>
        findByPromise = @redisObjectClassDataStore.findBy(url: 'uniqueValue')
        findByPromise.done (returnValue) ->
          expect(returnValue).toEqual createdObject
          done()

    it 'should reject if no object is found', (done) ->
      findByPromise = @redisObjectClassDataStore.findBy(url: 'urlNotFound')
      findByPromise.catch (returnValue) ->
        expect(returnValue).toEqual new Error "Not Found" 
        done()

  describe '#where', ->
    it 'should remove temporary sorted sets', (done) ->
      testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', integer: 1 )
      testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', integer: 1 )
      testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', integer: 2 )
      Promise.all([testPromise1,testPromise2,testPromise3]).done =>
        wherePromise = @redisObjectClassDataStore.where(integer: 1)
        wherePromise.done (returnValue) =>
          setTimeout =>
            @redisObjectClassDataStore.redis.keys 'temporary*', (err, keys) ->
              expect(keys).toEqual []
              done()
          ,1100

    it 'should return a promise', ->
      testObject = @redisObjectClassDataStore.where(one: '1')
      expect(testObject).toEqual jasmine.any(Promise)

    it 'should be able to return multiple test objects', (done) ->
      testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', boolean: true )
      testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', boolean: true )
      testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', boolean: false )
      Promise.all([testPromise1,testPromise2,testPromise3]).done =>
        wherePromise = @redisObjectClassDataStore.where(boolean: true)
        wherePromise.done (returnValue) =>
          expect(returnValue.total).toEqual 2
          expect(returnValue.items.length).toEqual 2
          done()

    it 'should be able to return a single test objects', (done) ->
      testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', one: 2 )
      testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', one: 1 )
      testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', one: 1 )
      Promise.all([testPromise1,testPromise2,testPromise3]).done =>
        wherePromise = @redisObjectClassDataStore.where(one: equalTo: 2)
        wherePromise.done (returnValue) =>
          expect(returnValue.total).toEqual 1
          expect(returnValue.items.length).toEqual 1
          expect(returnValue.items[0]).toEqual jasmine.objectContaining  url: 'uniqueValue1'
          done()

    it 'should return correct test objects when multiple properties conditions are met', (done) ->
      testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', one: 1, two: 1 )
      testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', one: 1, two: 2 )
      testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', one: 1, two: 2 )
      Promise.all([testPromise1,testPromise2,testPromise3]).then =>
        whereConditions =
          one:
            equalTo: 1
          two:
            equalTo: 1
        wherePromise = @redisObjectClassDataStore.where(whereConditions)
        wherePromise.done (returnValue) =>
          expect(returnValue.items.length).toEqual 1
          expect(returnValue.total).toEqual 1
          expect(returnValue.items[0]).toEqual jasmine.objectContaining  url: 'uniqueValue1'
          done()

    it 'should return an empty array when nothing matches the conditions', (done) ->
      testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', one: 1, two: 2, three: 3 )
      testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', one: 1, two: 2, three: 3 )
      testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', one: 1, two: 2, three: 3 )
      Promise.all([testPromise1,testPromise2,testPromise3]).then =>
        whereConditions =
          one:
            equalTo: 1
          two:
            equalTo: 2
          three:
            equalTo: 4
        wherePromise = @redisObjectClassDataStore.where(whereConditions)
        wherePromise.done (returnValue) =>
          expect(returnValue.total).toEqual 0
          expect(returnValue.items).toEqual []
          done()

    it "should resolve to an array of valid instances of the module's class", (done) ->
      testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', one: 1 )
      testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', one: 1 )
      testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', one: null )
      Promise.all([testPromise1,testPromise2,testPromise3]).then (createdObjectArray) =>
        wherePromise = @redisObjectClassDataStore.where(one: 1)
        wherePromise.done (returnValue) =>
          expect(returnValue.items).toContain createdObjectArray[0]
          expect(returnValue.items).toContain createdObjectArray[1]
          expect(returnValue.items.length).toEqual 2
          expect(returnValue.total).toEqual 2
          done()

    it 'should return an array of objects sorted consistently (by id)', (done) ->
      integerArray = [1, 1, 1, 2, 2, 3, 4, 5, 5]
      promiseArray = _.map integerArray, (integer) =>
        @redisObjectClassDataStore.create( integer: integer )
      Promise.all(promiseArray).then (createdObjectArray) =>
        @redisObjectClassDataStore.where(integer: equalTo: 1).done (firstResultArray) =>
          @redisObjectClassDataStore.where(integer: equalTo: 1).done (secondResultArray) =>
            expect(secondResultArray).toEqual firstResultArray
            expect(secondResultArray.items.length).toEqual 3
            expect(secondResultArray.total).toEqual 3
            done()

    it "should default to sorting by created at time (alphabetically by id)", (done) ->
      createDelayedObj = (integer) ->
        new Promise (resolve) =>
          setTimeout =>
            resolve @redisObjectClassDataStore.create(integer: integer)
          , 10
      delayedCreatePromises = []
      for i in [0..9]
        delayedCreatePromises.push createDelayedObj.apply(this, [i%2])
      Promise.all(delayedCreatePromises).then (createdObjectArray) =>
        @redisObjectClassDataStore.where(integer: equalTo: 1).done (returnArray) ->
          returnedIds = if returnArray then _.map(returnArray.items.ids, (x) -> x.id ) else []
          sortedReturnedIds = returnedIds.sort (a,b) -> a > b
          expect(returnArray.items.length).toEqual 5
          expect(returnedIds).toEqual sortedReturnedIds
          done()

    describe 'arguements', ->
      describe 'integers', ->
        beforeEach (done) ->
          testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', integer: 5 )
          testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', integer: 10 )
          testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', integer: 15 )
          Promise.all([testPromise1,testPromise2,testPromise3]).then (testObjects) =>
            @testObject1 = testObjects[0]
            @testObject2 = testObjects[1]
            @testObject3 = testObjects[2]
            done()

        it 'should return an array of objects that have an integer greater than', (done) ->
          whereConditions =
            integer:
              greaterThan: 10
          wherePromise = @redisObjectClassDataStore.where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 1
            expect(returnValue.total).toEqual 1
            expect(returnValue.items[0]).toEqual @testObject3
            done()

        it 'should return an array of objects that have an integer greater than or equal to', (done) ->
          whereConditions =
            integer:
              greaterThanOrEqualTo: 10
          wherePromise = @redisObjectClassDataStore.where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.total).toEqual 2
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.items).toContain @testObject3
            expect(returnValue.items).toContain @testObject2
            done()

        it 'should return an array of objects that have an integer less than', (done) ->
          whereConditions =
            integer:
              lessThan: 10
          wherePromise = @redisObjectClassDataStore.where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 1
            expect(returnValue.total).toEqual 1
            expect(returnValue.items[0]).toEqual @testObject1
            done()

        it 'should return an array of objects that have an integer less than or equal to', (done) ->
          whereConditions =
            integer:
              lessThanOrEqualTo: 10
          wherePromise = @redisObjectClassDataStore.where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.total).toEqual 2
            expect(returnValue.items).toContain @testObject1
            expect(returnValue.items).toContain @testObject2
            done()

        it 'should return an array of objects that have an integer equal to', (done) ->
          whereConditions =
            integer:
              equalTo: 10
          wherePromise = @redisObjectClassDataStore.where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 1
            expect(returnValue.total).toEqual 1
            expect(returnValue.items[0]).toEqual @testObject2
            done()

      describe 'keywords', ->
        beforeEach (done) ->
          testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', searchableText: 'bananas apples throat', searchableString: 'tongue' )
          testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', searchableText: 'two one four', searchableString: 'neck apples' )
          testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', searchableText: 'One two Three throat', searchableString: 'throat two' )
          Promise.all([testPromise1,testPromise2,testPromise3]).then (testObjects) =>
            @testObject1 = testObjects[0]
            @testObject2 = testObjects[1]
            @testObject3 = testObjects[2]
            done()

        it 'should return an array of objects that includes case insensitive keywords', (done) ->
          whereConditions =
            includes:
              keywords: 'one'
              in: 'searchableText'
          wherePromise = @redisObjectClassDataStore.where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.total).toEqual 2
            expect(returnValue.items).toContain @testObject2
            expect(returnValue.items).toContain @testObject3
            done()

        it 'should ignore empty spaces and punctuation characters', ->
          pending()

        it 'should return an array of objects that includes partial keywords', (done) ->
          whereConditions =
            includes:
              keywords: 'thr'
              in: 'searchableText'
          wherePromise = @redisObjectClassDataStore.where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.total).toEqual 2
            expect(returnValue.items).toContain @testObject1
            expect(returnValue.items).toContain @testObject3
            done()

        it 'should return an array of objects that includes multiple keywords in any order', (done) ->
          whereConditions =
            includes:
              keywords: 'two one'
              in: 'searchableText'
          wherePromise = @redisObjectClassDataStore.where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.total).toEqual 2
            expect(returnValue.items).toContain @testObject2
            expect(returnValue.items).toContain @testObject3
            done()

        describe 'inAllOf', ->
          it 'should return an array of objects that includes keywords in all different attributes', (done) ->
            whereConditions =
              includes:
                keywords: 'throat'
                inAllOf: ['searchableText', 'searchableString']
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 1
              expect(returnValue.total).toEqual 1
              expect(returnValue.items).toContain @testObject3
              done()

          it 'should return an array of objects that includes multiple keywords in all different attributes', (done) ->
            whereConditions =
              includes:
                keywords: 'throat two'
                inAllOf: ['searchableText', 'searchableString']
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 1
              expect(returnValue.total).toEqual 1
              expect(returnValue.items).toContain @testObject3
              done()

          it 'should return an array of objects that includes multiple keywords in all different attributes', (done) ->
            whereConditions =
              includes:
                keywords: 'throat One'
                inAllOf: ['searchableText', 'searchableString']
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 0
              done()

        describe 'inAnyOf', ->
          it 'should return an array of objects that includes keywords in any different attributes', (done) ->
            whereConditions =
              includes:
                keywords: 'throat'
                inAnyOf: ['searchableText', 'searchableString']
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.total).toEqual 2
              expect(returnValue.items).toContain @testObject1
              expect(returnValue.items).toContain @testObject3
              done()

          it 'should return an array of objects that includes keywords in any different attributes ordered by relevance by default', (done) ->
            whereConditions =
              includes:
                keywords: 'apples'
                inAnyOf: ['searchableText', 'searchableString']
                modifiedWeights: [
                  attributes: 'searchableText'
                  weight: 0.5
                ]
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.total).toEqual 2
              expect(returnValue.items[0]).toEqual @testObject2
              expect(returnValue.items[1]).toEqual @testObject1
              done()

          it 'should return an array of objects that includes keywords in any different attributes ordered by relevance by default', (done) ->
            whereConditions =
              includes:
                keywords: 'apples'
                inAnyOf: ['searchableText', 'searchableString']
                modifiedWeights: [
                  attributes: 'searchableString'
                  weight: 0.5
                ]
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.items[0]).toEqual @testObject1
              expect(returnValue.items[1]).toEqual @testObject2
              done()

          it 'should return an array of objects that includes multiple keywords in any different attributes ordered by relevance by default', (done) ->
            testPromise1 = @redisObjectClassDataStore.create( searchableText: 'bear', searchableString: 'cow cow' )
            testPromise2 = @redisObjectClassDataStore.create( searchableText: 'cow cow', searchableString: 'bear' )
            testPromise3 = @redisObjectClassDataStore.create( searchableText: 'cow', searchableString: 'dog' )
            whereConditions =
              includes:
                keywords: 'bear cow'
                inAnyOf: ['searchableText', 'searchableString']
                modifiedWeights: [
                  attributes: 'searchableString'
                  weight: 0.5
                ]
            Promise.all([testPromise1,testPromise2,testPromise3]).done (testobjects) =>
              wherePromise = @redisObjectClassDataStore.where(whereConditions)
              wherePromise.done (returnValue) =>
                expect(returnValue.items.length).toEqual 2
                expect(returnValue.items).toContain testobjects[1]
                expect(returnValue.items).toContain testobjects[0]
                done()

      describe 'reference', ->
        beforeEach (done) ->
          @redisObjectClassDataStore.attributes.oneRef =
            dataType: 'reference'
            referenceModelName: 'Reference'
          @redisObjectClassDataStore.manyReferences =
            dataType: 'reference'
            many: true
            referenceModelName: 'Reference'
          ref1 = @referenceModel.create(secondId: 'id1')
          ref2 = @referenceModel.create(secondId: 'id2')
          ref3 = @referenceModel.create(secondId: 'id3')
          ref4 = @referenceModel.create(secondId: 'id4')
          ref5 = @referenceModel.create(secondId: 'id5')
          createReferencesPromise = Promise.all([ref1, ref2, ref3, ref4, ref5])
          createTestObjectsPromise = createReferencesPromise.then (references) =>
            @ref1Id = references[0].id
            @ref2Id = references[1].id
            @ref3Id = references[2].id
            @ref4Id = references[3].id
            @ref5Id = references[4].id
            testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', manyReferences: [@ref1Id, @ref2Id], oneRef: @ref4Id )
            testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', manyReferences: [@ref2Id], oneRef: @ref4Id )
            testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', manyReferences: [@ref1Id, @ref2Id, @ref3Id], oneRef: @ref5Id )
            Promise.all([testPromise1,testPromise2,testPromise3])
          createTestObjectsPromise.then (testObjects) =>
            @testObject1 = testObjects[0]
            @testObject2 = testObjects[1]
            @testObject3 = testObjects[2]
            done()

        describe 'includesAllOf', ->
          it 'returns all objects when all match', (done) ->
            wherePromise = @redisObjectClassDataStore.where manyReferences: { includesAllOf: [@ref1Id, @ref2Id, @ref3Id] }
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 1
              expect(returnValue.items).toContain @testObject3
              done()

          it 'returns some objects when some match', (done) ->
            wherePromise = @redisObjectClassDataStore.where manyReferences: { includesAllOf: [@ref1Id, @ref2Id] }
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.items).toContain @testObject1
              expect(returnValue.items).toContain @testObject3
              done()

          it 'returns one object when one matches', (done) ->
            wherePromise = @redisObjectClassDataStore.where manyReferences: { includesAllOf: [@ref2Id] }
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 3
              expect(returnValue.items).toContain @testObject1
              expect(returnValue.items).toContain @testObject2
              expect(returnValue.items).toContain @testObject3
              done()

        describe 'includesAnyOf', ->
          it 'returns all objects when all match', (done) ->
            wherePromise = @redisObjectClassDataStore.where manyReferences: { includesAnyOf: [@ref3Id] }
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 1
              expect(returnValue.items).toContain @testObject3
              done()

          it 'returns some objects when some match', (done) ->
            wherePromise = @redisObjectClassDataStore.where manyReferences: { includesAnyOf: [@ref1Id, @ref3Id] }
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.items).toContain @testObject1
              expect(returnValue.items).toContain @testObject3
              done()

          it 'returns one object when one matches', (done) ->
            wherePromise = @redisObjectClassDataStore.where manyReferences: { includesAnyOf: [@ref2Id] }
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 3
              expect(returnValue.items).toContain @testObject1
              expect(returnValue.items).toContain @testObject2
              expect(returnValue.items).toContain @testObject3
              done()

        describe 'non-many', ->
          it 'returns all objects when all match', (done) ->
            wherePromise = @redisObjectClassDataStore.where oneRef: { anyOf: [@ref4Id, @ref5Id] }
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 3
              expect(returnValue.items).toContain @testObject1
              expect(returnValue.items).toContain @testObject2
              expect(returnValue.items).toContain @testObject3
              done()

          it 'returns some objects when some match', (done) ->
            wherePromise = @redisObjectClassDataStore.where oneRef: @ref4Id
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.items).toContain @testObject1
              expect(returnValue.items).toContain @testObject2
              done()

          it 'returns one object when one matches', (done) ->
            wherePromise = @redisObjectClassDataStore.where oneRef: @ref5Id
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 1
              expect(returnValue.items).toContain @testObject3
              done()

      describe 'sortBy', ->
        it 'should return an array of objects ordered by a sortable field', (done) ->
          testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', sortableString: 'alpha', boolean: true  )
          testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', sortableString: 'beta', boolean: false )
          testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', sortableString: 'charlie', boolean: true )
          whereConditions =
            boolean: true
            sortBy: 'sortableString'
          Promise.all([testPromise1,testPromise2,testPromise3]).done =>
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.items[0]).toEqual jasmine.objectContaining  url: 'uniqueValue1'
              expect(returnValue.items[1]).toEqual jasmine.objectContaining  url: 'uniqueValue3'
              done()

        it 'should return an array of objects that includes keywords in different attributes, ordered by a sortable field (not weight)', (done) ->
          testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', searchableText: 'bananas apples throat', searchableString: 'tongue', sortableString: 'charlie' )
          testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', searchableText: 'two one four', searchableString: 'neck', sortableString: 'beta' )
          testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', searchableText: 'One two Three', searchableString: 'throat', sortableString: 'alpha' )
          whereConditions =
            includes:
              keywords: 'throat'
              inAnyOf: ['searchableText', 'searchableString']
              modifiedWeights: [
                attributes: 'searchableText'
                weight: 2
              ]
            sortBy: 'sortableString'
          Promise.all([testPromise1,testPromise2,testPromise3]).done =>
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) ->
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.items[0]).toEqual jasmine.objectContaining  url: 'uniqueValue3'
              expect(returnValue.items[1]).toEqual jasmine.objectContaining  url: 'uniqueValue1'
              done()

        it 'should return an array of objects randomly ordered', (done) ->
          #FIXME: shouldn't have randomly failing tests
          console.log 'Occassional fail expected - testing random order'
          urlArray = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel','india', 'juliet' ]
          i = 0
          promiseArray = _.map urlArray, (url) =>
            i++
            @redisObjectClassDataStore.create( url: url, boolean: (i <= 5) )
          whereConditions =
            sortBy: 'random'
            boolean: true
          Promise.all(promiseArray).done =>
            wherePromise = @redisObjectClassDataStore.where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 5
              expect(returnValue[4]).not.toEqual jasmine.objectContaining  url: 'echo'
              done()

  describe '#all', ->
    it 'should return a promise', ->
      testObject = @redisObjectClassDataStore.all()
      expect(testObject).toEqual jasmine.any(Promise)

    it "should resolve to an array of all the instances of the module's class", (done) ->
      testPromise1 = @redisObjectClassDataStore.create( url: 'uniqueValue1', one: 1, two: 2, three: 3 )
      testPromise2 = @redisObjectClassDataStore.create( url: 'uniqueValue2', one: 1, two: 2, three: 3 )
      testPromise3 = @redisObjectClassDataStore.create( url: 'uniqueValue3', one: 1, two: 2, three: 3 )
      Promise.all([testPromise1,testPromise2,testPromise3]).then (createdObjectArray) =>
        allPromise = @redisObjectClassDataStore.all()
        allPromise.done (returnValue) ->
          expect(returnValue.items).toContain createdObjectArray[0]
          expect(returnValue.items).toContain createdObjectArray[1]
          expect(returnValue.items).toContain createdObjectArray[2]
          expect(returnValue.items.length).toEqual 3
          expect(returnValue.total).toEqual 3
          done()

    it "should not resolve any instances of a different module's class", (done) ->
      pending()
      #differentModel = _.clone @redisObjectClassDataStore
      #differentModel.name = "DifferentModel"
      #redisObjectClassDataStoreCreatePromise = @redisObjectClassDataStore.create( url: 'redisObjectClassDataStoreModelInstance')
      #differentModelCreatePromise = differentModel.create( url: 'differentModelInstance')
      #Promise.all([redisObjectClassDataStoreCreatePromise, differentModelCreatePromise]).then (createdObjectArray) =>
      #  redisObjectClassDataStoreAllPromise = @redisObjectClassDataStore.all()
      #  differentModelAllPromise = differentModel.all()
      #  Promise.all([redisObjectClassDataStoreAllPromise, differentModelAllPromise]).done (returnArray) =>
      #    expect(returnArray.items[0]).toEqual [createdObjectArray[0]]
      #    expect(returnArray.items[1]).toEqual [createdObjectArray[1]]
      #    done()

    it "should return an array of objects sorted consistently (by id)", (done) ->
      urlArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      promiseArray = _.map urlArray, (url) =>
        @redisObjectClassDataStore.create( url: url )
      Promise.all(promiseArray).then (createdObjectArray) =>
        @redisObjectClassDataStore.all().done (firstResultArray) =>
          @redisObjectClassDataStore.all().done (secondResultArray) ->
            expect(secondResultArray).toEqual firstResultArray
            done()

    it "should default to sorting by create at time (alphabetically by id)", (done) ->
      createDelayedObj = (integer) ->
        new Promise (resolve) =>
          nextTick(resolve @redisObjectClassDataStore.create(integer: integer))
      delayedCreatePromises = []
      for i in [0..9]
        delayedCreatePromises.push createDelayedObj.bind(this, i)
      _utilities.promiseEachFn(delayedCreatePromises).then (createdObjectArray) =>
        @redisObjectClassDataStore.all().done (returnArray) ->
          expect(returnArray.items.length).toEqual 10
          expect(returnArray.items).toEqual createdObjectArray
          done()

    it "should return an array of objects sorted by sortableString when passed sortBy args", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(sortBy: 'sortableString').done (returnArray) ->
          expect(returnArray.items.length).toEqual 10
          expect(returnArray.total).toEqual 10
          expect(returnArray.items[0]).toEqual jasmine.objectContaining sortableString: 'alpha'
          expect(returnArray.items[1]).toEqual jasmine.objectContaining sortableString: 'bravo'
          expect(returnArray.items[2]).toEqual jasmine.objectContaining sortableString: 'charlie'
          expect(returnArray.items[3]).toEqual jasmine.objectContaining sortableString: 'delta'
          expect(returnArray.items[4]).toEqual jasmine.objectContaining sortableString: 'echo'
          expect(returnArray.items[5]).toEqual jasmine.objectContaining sortableString: 'foxtrot'
          expect(returnArray.items[6]).toEqual jasmine.objectContaining sortableString: 'golf'
          expect(returnArray.items[7]).toEqual jasmine.objectContaining sortableString: 'hotel'
          expect(returnArray.items[8]).toEqual jasmine.objectContaining sortableString: 'india'
          expect(returnArray.items[9]).toEqual jasmine.objectContaining sortableString: 'juliet'
          done()

    it "should return an array of objects sorted in ascending order when passed sortBy and sortDirection args", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(sortBy: 'sortableString', sortDirection: 'asc').done (returnArray) ->
          expect(returnArray.items.length).toEqual 10
          expect(returnArray.total).toEqual 10
          expect(returnArray.items[0]).toEqual jasmine.objectContaining sortableString: 'alpha'
          expect(returnArray.items[1]).toEqual jasmine.objectContaining sortableString: 'bravo'
          expect(returnArray.items[2]).toEqual jasmine.objectContaining sortableString: 'charlie'
          expect(returnArray.items[3]).toEqual jasmine.objectContaining sortableString: 'delta'
          expect(returnArray.items[4]).toEqual jasmine.objectContaining sortableString: 'echo'
          expect(returnArray.items[5]).toEqual jasmine.objectContaining sortableString: 'foxtrot'
          expect(returnArray.items[6]).toEqual jasmine.objectContaining sortableString: 'golf'
          expect(returnArray.items[7]).toEqual jasmine.objectContaining sortableString: 'hotel'
          expect(returnArray.items[8]).toEqual jasmine.objectContaining sortableString: 'india'
          expect(returnArray.items[9]).toEqual jasmine.objectContaining sortableString: 'juliet'
          done()

    it "should return an array of objects sorted in decending order when passed sortBy and sortDirection args", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>

        @redisObjectClassDataStore.all(sortBy: 'sortableString', sortDirection: 'desc').done (returnArray) ->
          expect(returnArray.total).toEqual 10
          expect(returnArray.items.length).toEqual 10
          expect(returnArray.items[0]).toEqual jasmine.objectContaining sortableString: 'juliet'
          expect(returnArray.items[1]).toEqual jasmine.objectContaining sortableString: 'india'
          expect(returnArray.items[2]).toEqual jasmine.objectContaining sortableString: 'hotel'
          expect(returnArray.items[3]).toEqual jasmine.objectContaining sortableString: 'golf'
          expect(returnArray.items[4]).toEqual jasmine.objectContaining sortableString: 'foxtrot'
          expect(returnArray.items[5]).toEqual jasmine.objectContaining sortableString: 'echo'
          expect(returnArray.items[6]).toEqual jasmine.objectContaining sortableString: 'delta'
          expect(returnArray.items[7]).toEqual jasmine.objectContaining sortableString: 'charlie'
          expect(returnArray.items[8]).toEqual jasmine.objectContaining sortableString: 'bravo'
          expect(returnArray.items[9]).toEqual jasmine.objectContaining sortableString: 'alpha'
          done()

    it "should return an array of 5 items when passed a limit of 5", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(limit: 5).done (returnArray) ->
          expect(returnArray.items.length).toEqual 5
          expect(returnArray.total).toEqual 10
          done()

    it "should return an array of all available items when passed a limit of 0", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(limit: 0).done (returnArray) ->
          expect(returnArray.items.length).toEqual 10
          expect(returnArray.total).toEqual 10
          done()

    it "should return an array of one item when passed a limit of 1", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(limit: 1).done (returnArray) ->
          expect(returnArray.items.length).toEqual 1
          expect(returnArray.total).toEqual 10
          done()

    it "should return an array of objects sorted with a limit and an offset when passed args", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(sortBy: 'sortableString', offset: 6).done (returnArray) ->
          expect(returnArray.items.length).toEqual 4
          expect(returnArray.total).toEqual 10
          expect(returnArray.items[0]).toEqual jasmine.objectContaining sortableString: 'golf'
          expect(returnArray.items[1]).toEqual jasmine.objectContaining sortableString: 'hotel'
          expect(returnArray.items[2]).toEqual jasmine.objectContaining sortableString: 'india'
          expect(returnArray.items[3]).toEqual jasmine.objectContaining sortableString: 'juliet'
          done()

    it "should return an array of objects sorted with a limit and an offset when passed args", (done) -> #This test failed sporadically once
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(sortBy: 'sortableString', limit: 5, offset: 3).done (returnArray) ->
          expect(returnArray.items.length).toEqual 5
          expect(returnArray.total).toEqual 10
          expect(returnArray.items[0]).toEqual jasmine.objectContaining sortableString: 'delta'
          expect(returnArray.items[1]).toEqual jasmine.objectContaining sortableString: 'echo'
          expect(returnArray.items[2]).toEqual jasmine.objectContaining sortableString: 'foxtrot'
          expect(returnArray.items[3]).toEqual jasmine.objectContaining sortableString: 'golf'
          expect(returnArray.items[4]).toEqual jasmine.objectContaining sortableString: 'hotel'
          done()

    it "should return an array of objects sorted in decending order when passed sortBy and sortDirection args", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(sortBy: 'sortableString', sortDirection: 'desc', limit: 2, offset: 7).done (returnArray) ->
          expect(returnArray.items.length).toEqual 2
          expect(returnArray.total).toEqual 10
          expect(returnArray.items[0]).toEqual jasmine.objectContaining sortableString: 'charlie'
          expect(returnArray.items[1]).toEqual jasmine.objectContaining sortableString: 'bravo'
          done()

    it "should return an array of objects sorted in decending order when passed sortBy and sortDirection args", (done) ->
      stringArray = ['india', 'juliet', 'golf', 'hotel', 'alpha', 'bravo', 'delta', 'echo', 'foxtrot', 'charlie']
      objectsPromise = _.map stringArray, (string) =>
        @redisObjectClassDataStore.create( sortableString: string )
      Promise.all(objectsPromise).then (createdObjectArray) =>
        @redisObjectClassDataStore.all(sortBy: 'sortableString', sortDirection: 'desc', limit: 8, offset: 1).done (returnArray) ->
          expect(returnArray.items.length).toEqual 8
          expect(returnArray.total).toEqual 10
          expect(returnArray.items[0]).toEqual jasmine.objectContaining sortableString: 'india'
          expect(returnArray.items[1]).toEqual jasmine.objectContaining sortableString: 'hotel'
          expect(returnArray.items[2]).toEqual jasmine.objectContaining sortableString: 'golf'
          expect(returnArray.items[3]).toEqual jasmine.objectContaining sortableString: 'foxtrot'
          expect(returnArray.items[4]).toEqual jasmine.objectContaining sortableString: 'echo'
          expect(returnArray.items[5]).toEqual jasmine.objectContaining sortableString: 'delta'
          expect(returnArray.items[6]).toEqual jasmine.objectContaining sortableString: 'charlie'
          expect(returnArray.items[7]).toEqual jasmine.objectContaining sortableString: 'bravo'
          done()

  describe '#create', ->
    it 'should return a promise', ->
      testProps = { url: 'uniqueValue'}
      testObject = @redisObjectClassDataStore.create testProps
      expect(testObject).toEqual jasmine.any(Promise)

    it 'should resolve an object with a 10 character id', (done) ->
      # This test will fail from Sun May 25 2059 18:38:27 BST (2821109907456 unix time)
      # and the number of characters will increase by 1
      testProps =  url: 'uniqueValue'
      testObjectPromise = @redisObjectClassDataStore.create testProps
      testObjectPromise.done (testObject) ->
        expect(testObject.id.length).toEqual 10
        done()

    it "should create an object with properties that are defined in the class' attributes", (done) ->
      testProps = boolean: false
      testObjectPromise = @redisObjectClassDataStore.create testProps
      testObjectPromise.then (testObject) ->
        expect(testObject.boolean).toBe false
        done()

    it "should create an object and ignore properties that are not defined in the class' attributes", (done) ->
      testProps = notAnAttribute: 'value'
      @redisObjectClassDataStore.create(testProps).catch (error) =>
        expect(error).toEqual(new Error "No valid fields given")
        done()


    describe 'presence validation', ->
      it 'should create objects that pass validation', (done) ->
        @redisObjectClassDataStore.attributes.presenceValidation =
          dataType: 'string'
          validates:
            presence: true
        @redisObjectClassDataStore.create(presenceValidation: 'value').then (testObject) =>
          expect(testObject.presenceValidation).toEqual 'value'
          done()

      it 'should not create objects that fail validation', (done) ->
        @redisObjectClassDataStore.attributes.presenceValidation =
          dataType: 'string'
          identifiable: true
          validates:
            presence: true
        @redisObjectClassDataStore.create(one: 1, presenceValidation: null).catch (errors) ->
          expect(errors).toContain(new Error 'presenceValidation must be present')
          done()

    describe 'length validation', ->

      it 'should not create objects that fail length validation by having a length that is greater than', (done) ->
        @redisObjectClassDataStore.attributes.lengthValidation =
          dataType: 'string'
          validates:
            length:
              is: 9
        @redisObjectClassDataStore.create(one: 1, lengthValidation: 'elevenchars').catch (errors) ->
          expect(errors.length).toEqual 1
          expect(errors).toContain jasmine.any ValidationError
          expect(errors).toContain jasmine.objectContaining message: 'lengthValidation should have a length of 9'
          done()

      it 'should not create objects that fail length validation by having a length that is less than', (done) ->
        @redisObjectClassDataStore.attributes.lengthValidation =
          dataType: 'string'
          validates:
            length:
              is: 9
        @redisObjectClassDataStore.create(lengthValidation: 'sixchr').catch (errors) ->
          expect(errors.length).toEqual 1
          expect(errors).toContain jasmine.any ValidationError
          expect(errors).toContain jasmine.objectContaining message: 'lengthValidation should have a length of 9'
          done()

      it 'should create objects that have a length that is equal to the length validation', (done) ->
        @redisObjectClassDataStore.attributes.lengthValidation =
          dataType: 'string'
          validates:
            length:
              is: 9
        @redisObjectClassDataStore.create(lengthValidation: 'ninechars').then (testObject) ->
          expect(testObject.lengthValidation).toEqual 'ninechars'
          done()

      it 'should perform the validation only when the property is present', (done) ->
        @redisObjectClassDataStore.attributes.lengthValidation =
          dataType: 'string'
          validates:
            length:
              is: 9
        @redisObjectClassDataStore.create(one: 1, lengthValidation: null).then (testObject) =>
          expect(testObject.lengthValidation).toEqual undefined
          done()


      describe 'minimum length', ->
        it 'should create objects that have a length that is equal to the minimum length validation', (done) ->
          @redisObjectClassDataStore.attributes.minLengthValidation =
            dataType: 'string'
            validates:
              length:
                minimum: 9
          @redisObjectClassDataStore.create(minLengthValidation: 'ninechars').then (testObject) =>
            expect(testObject.minLengthValidation).toEqual 'ninechars'
            done()

        it 'should create objects that have a length that is greater than the minimum length validation', (done) ->
          @redisObjectClassDataStore.attributes.minLengthValidation =
            dataType: 'string'
            validates:
              length:
                minimum: 9
          @redisObjectClassDataStore.create(minLengthValidation: 'elevenchars').then (testObject) =>
            expect(testObject.minLengthValidation).toEqual 'elevenchars'
            done()

        it 'should not create objects that fail minLength validation', (done) ->
          @redisObjectClassDataStore.attributes.minLengthValidation =
            dataType: 'string'
            validates:
              length:
                minimum: 9
          @redisObjectClassDataStore.create(minLengthValidation: 'sixchr').catch (error) =>
            expect(error).toContain(new Error 'minLengthValidation should have a minimum length of 9')
            done()

      describe 'maximum length', ->
        it 'should create objects that have a length that is equal to the maximum length validation', (done) ->
          @redisObjectClassDataStore.attributes.maxLengthValidation =
            dataType: 'string'
            validates:
              length:
                maximum: 9
          @redisObjectClassDataStore.create(maxLengthValidation: 'ninechars').then (testObject) =>
            expect(testObject.maxLengthValidation).toEqual 'ninechars'
            done()

        it 'should create objects that have a length that is less than the maximum length validation', (done) ->
          @redisObjectClassDataStore.attributes.maxLengthValidation =
            dataType: 'string'
            validates:
              length:
                maximum: 9
          @redisObjectClassDataStore.create(maxLengthValidation: 'sixchr').then (testObject) =>
            expect(testObject.maxLengthValidation).toEqual 'sixchr'
            done()

        it 'should not create objects that fail validation', (done) ->
          @redisObjectClassDataStore.attributes.maxLengthValidation =
            dataType: 'string'
            validates:
              length:
                maximum: 9
          @redisObjectClassDataStore.create(maxLengthValidation: 'elevenchars').catch (error) =>
            expect(error).toContain(new Error 'maxLengthValidation should have a maximum length of 9')
            done()


    describe 'greaterThan validation', ->
      it 'should create objects that pass greaterThan validation', (done) ->
        @redisObjectClassDataStore.attributes.greaterThanValidation =
          dataType: 'integer'
          validates:
            greaterThan: 9
        @redisObjectClassDataStore.create(greaterThanValidation: 11).then (testObject) =>
          expect(testObject.greaterThanValidation).toEqual 11
          done()

      it 'should not create objects that fail greaterThan validation by being less than', (done) ->
        @redisObjectClassDataStore.attributes.greaterThanValidation =
          dataType: 'integer'
          validates:
            greaterThan: 9
        @redisObjectClassDataStore.create(greaterThanValidation: 1).catch (error) =>
          expect(error).toContain(new Error 'greaterThanValidation should be greater than 9')
          done()

      it 'should not create objects that fail greaterThan validation by being equal to', (done) ->
        @redisObjectClassDataStore.attributes.greaterThanValidation =
          dataType: 'integer'
          validates:
            greaterThan: 10
        @redisObjectClassDataStore.create(greaterThanValidation: 10).catch (error) =>
          expect(error).toContain(new Error 'greaterThanValidation should be greater than 10')
          done()

    describe 'greaterThanOrEqualTo validation', ->
      it 'should create objects that pass greaterThanOrEqualTo validation by being equal to', (done) ->
        @redisObjectClassDataStore.attributes.greaterThanOrEqualToValidation =
          dataType: 'integer'
          validates:
            greaterThanOrEqualTo: 10
        @redisObjectClassDataStore.create(greaterThanOrEqualToValidation: 10).then (testObject) =>
          expect(testObject.greaterThanOrEqualToValidation).toEqual 10
          done()

      it 'should create objects that pass greaterThanOrEqualTo validation by being greater than', (done) ->
        @redisObjectClassDataStore.attributes.greaterThanOrEqualToValidation =
          dataType: 'integer'
          validates:
            greaterThanOrEqualTo: 10
        @redisObjectClassDataStore.create(greaterThanOrEqualToValidation: 11).then (testObject) =>
          expect(testObject.greaterThanOrEqualToValidation).toEqual 11
          done()

      it 'should not create objects that fail greaterThanOrEqualTo validation', (done) ->
        @redisObjectClassDataStore.attributes.greaterThanOrEqualToValidation =
          dataType: 'integer'
          validates:
            greaterThanOrEqualTo: 10
        @redisObjectClassDataStore.create(greaterThanOrEqualToValidation: 1).catch (error) =>
          expect(error).toContain(new Error 'greaterThanOrEqualToValidation should be greater than or equal to 10')
          done()

    describe 'lessThan validation', ->
      it 'should create objects that pass lessThan validation', (done) ->
        @redisObjectClassDataStore.attributes.lessThanValidation =
          dataType: 'integer'
          validates:
            lessThan: 10
        @redisObjectClassDataStore.create(lessThanValidation: 9).then (testObject) =>
          expect(testObject.lessThanValidation).toEqual 9
          done()

      it 'should not create objects that fail lessThan validation by being more than', (done) ->
        @redisObjectClassDataStore.attributes.lessThanValidation =
          dataType: 'integer'
          validates:
            lessThan: 10
        @redisObjectClassDataStore.create(lessThanValidation: 11).catch (error) =>
          expect(error).toContain(new Error 'lessThanValidation should be less than 10')
          done()

      it 'should not create objects that fail lessThan validation by being equal to', (done) ->
        @redisObjectClassDataStore.attributes.lessThanValidation =
          dataType: 'integer'
          validates:
            lessThan: 10
        @redisObjectClassDataStore.create(lessThanValidation: 10).catch (error) =>
          expect(error).toContain(new Error 'lessThanValidation should be less than 10')
          done()

    describe 'lessThanOrEqualTo validation', ->
      it 'should create objects that pass lessThanOrEqualTo validation by being less than', (done) ->
        @redisObjectClassDataStore.attributes.lessThanOrEqualToValidation =
          dataType: 'integer'
          validates:
            lessThanOrEqualTo: 10
        @redisObjectClassDataStore.create(lessThanOrEqualToValidation: 9).then (testObject) =>
          expect(testObject.lessThanOrEqualToValidation).toEqual 9
          done()

      it 'should create objects that pass lessThanOrEqualTo validation by being equal to', (done) ->
        @redisObjectClassDataStore.attributes.lessThanOrEqualToValidation =
          dataType: 'integer'
          validates:
            lessThanOrEqualTo: 10
        @redisObjectClassDataStore.create(lessThanOrEqualToValidation: 10).then (testObject) =>
          expect(testObject.lessThanOrEqualToValidation).toEqual 10
          done()

      it 'should not create objects that fail lessThanOrEqualTo validation', (done) ->
        @redisObjectClassDataStore.attributes.lessThanOrEqualToValidation =
          dataType: 'integer'
          validates:
            lessThanOrEqualTo: 10
        @redisObjectClassDataStore.create(lessThanOrEqualToValidation: 11).catch (error) =>
          expect(error).toContain(new Error 'lessThanOrEqualToValidation should be less than or equal to 10')
          done()

    describe 'equalTo validation', ->
      it 'should create objects that pass equalTo validation', (done) ->
        @redisObjectClassDataStore.attributes.equalToValidation =
          dataType: 'integer'
          validates:
            equalTo: 10
        @redisObjectClassDataStore.create(equalToValidation: 10).then (testObject) =>
          expect(testObject.equalToValidation).toEqual 10
          done()

      it 'should not create objects that fail equalTo validation by being more than', (done) ->
        @redisObjectClassDataStore.attributes.equalToValidation =
          dataType: 'integer'
          validates:
            equalTo: 10
        @redisObjectClassDataStore.create(equalToValidation: 11).catch (error) =>
          expect(error).toContain(new Error 'equalToValidation should equal 10')
          done()

      it 'should not create objects that fail equalTo validation by being less than', (done) ->
        @redisObjectClassDataStore.attributes.equalToValidation =
          dataType: 'integer'
          validates:
            equalTo: 10
        @redisObjectClassDataStore.create(equalToValidation: 9).catch (error) =>
          expect(error).toContain(new Error 'equalToValidation should equal 10')
          done()

    describe 'format validation', ->
      describe "'with'", ->
        it 'should not fail when the attribute is not present', (done) ->
          pending()

        it "should create objects that pass format validation 'with' a regular expression that accounts for all of the data", (done) ->
          @redisObjectClassDataStore.attributes.formatValidation =
            dataType: 'string'
            validates:
              format:
                with: /[a-zA-Z]+/
          @redisObjectClassDataStore.create(formatValidation: 'abcd').then (testObject) =>
            expect(testObject.formatValidation).toEqual 'abcd'
            done()

        it "should create objects that pass format validation 'with' a regular expression that only accounts for some of the data", (done) ->
          @redisObjectClassDataStore.attributes.formatValidation =
            dataType: 'string'
            validates:
              format:
                with: /[a-zA-Z]+/
          @redisObjectClassDataStore.create(formatValidation: 'ab123cd').then (testObject) =>
            expect(testObject.formatValidation).toEqual 'ab123cd'
            done()

        it "should not create objects that fail format validation 'with' a regular expression", (done) ->
          @redisObjectClassDataStore.attributes.formatValidation =
            dataType: 'string'
            validates:
              format:
                with: /[a-zA-Z]+/
          @redisObjectClassDataStore.create(formatValidation: '123').catch (error) =>
            expect(error).toContain(new Error 'formatValidation should meet the format requirements')
            done()

        it 'should perform the validation only when the property is present', (done) ->
          @redisObjectClassDataStore.attributes.formatValidation =
            dataType: 'string'
            validates:
              format:
                with: /[a-zA-Z]+/
          @redisObjectClassDataStore.create(one: 1, formatValidation: null).then (testObject) =>
            expect(testObject.formatValidation).toEqual undefined
            done()

      describe "'without'", ->
        it "should not create objects that fail validation", (done) ->
          @redisObjectClassDataStore.attributes.formatValidation =
            dataType: 'string'
            validates:
              format:
                without: /[a-zA-Z]+/
          @redisObjectClassDataStore.create(formatValidation: 'abcd').catch (error) ->
            expect(error).toContain(new Error 'formatValidation should meet the format requirements')
            done()

        it "should create objects that pass format validation", (done) ->
          @redisObjectClassDataStore.attributes.formatValidation =
            dataType: 'string'
            validates:
              format:
                without: /[a-zA-Z]+/
          @redisObjectClassDataStore.create(formatValidation: '123').then (testObject) =>
            expect(testObject.formatValidation).toEqual '123'
            done()

    describe 'inclusionIn validation', ->
      it 'should create objects that pass inclusionIn validation', (done) ->
        @redisObjectClassDataStore.attributes.inclusionInValidation =
          dataType: 'string'
          validates:
            inclusionIn: ['one', 'two', 'three']
        @redisObjectClassDataStore.create(inclusionInValidation: 'one').then (testObject) =>
          expect(testObject.inclusionInValidation).toEqual 'one'
          done()

      it 'should not create objects that fail inclusionIn validation', (done) ->
        @redisObjectClassDataStore.attributes.inclusionInValidation =
          dataType: 'string'
          validates:
            inclusionIn: ['one', 'two', 'three']
        @redisObjectClassDataStore.create(inclusionInValidation: 'four').catch (error) =>
          expect(error).toContain(new Error 'inclusionInValidation must be one of the accepted values')
          done()

    describe 'exclusionIn validation', ->
      it 'should create objects that pass exclusionIn validation', (done) ->
        @redisObjectClassDataStore.attributes.exclusionInValidation =
          dataType: 'string'
          validates:
            exclusionIn: ['one', 'two', 'three']
        @redisObjectClassDataStore.create(exclusionInValidation: 'four').then (testObject) =>
          expect(testObject.exclusionInValidation).toEqual 'four'
          done()

      it 'should not create objects that fail exclusionIn validation', (done) ->
        @redisObjectClassDataStore.attributes.exclusionInValidation =
          dataType: 'string'
          validates:
            exclusionIn: ['one', 'two', 'three']
        @redisObjectClassDataStore.create(exclusionInValidation: 'one').catch (error) =>
          expect(error).toContain(new Error 'exclusionInValidation must not be one of the forbidden values')
          done()

    describe 'uniqueness validation', ->
      it 'should not create objects that fail validation', (done) ->
        @redisObjectClassDataStore.attributes.uniquenessValidation =
          dataType: 'string'
          identifiable: true
          validates:
            uniqueness: true
        @redisObjectClassDataStore.redis.set 'RedisObjectClassDataStore#uniquenessValidation:notUnique', 'test', () =>
          @redisObjectClassDataStore.create(uniquenessValidation: 'notUnique').catch (errors) =>
            expect(errors).toContain(new Error 'uniquenessValidation should be a unique value')
            done()

  describe '#update', ->
    beforeEach (done) ->
      ref1 = @referenceModel.create(secondId: 'ida')
      ref2 = @referenceModel.create(secondId: 'idb')
      ref3 = @referenceModel.create(secondId: 'idc')
      Promise.all([ref1,ref2,ref3]).done (refs) =>
        @ref1Id = refs[0].id
        @ref2Id = refs[1].id
        @ref3Id = refs[2].id
        testProps =
          one: '0'
          integer: 1
          identifier: "identifier"
          boolean: true
          reference: "reference"
          manyReferences: [@ref1Id, @ref2Id, @ref3Id]
          searchableText: "Search this"
          sortableString: "first"
          sortableInteger: 1
        @redisObjectClassDataStore.create(testProps).done (testObject) =>
          @testObj = testObject
          done()

    it 'should return a promise', ->
      testObjectPromise = @redisObjectClassDataStore.update @testObj.id, url: 'uniqueValue'
      expect(testObjectPromise).toEqual jasmine.any(Promise)

    it 'should throw an error when the id is not found', (done) ->
      testObjectPromise = @redisObjectClassDataStore.update 'invalidID', url: 'takenURL'
      testObjectPromise.catch (error) ->
        expect(error).toEqual new Error "Not Found"
        done()

    it 'should update the object when a change is made', (done) ->
      testObjectPromise = @redisObjectClassDataStore.update @testObj.id, one: 111
      testObjectPromise.done (obj) ->
        expect(obj.one).toEqual 111
        done()

    it 'should update the relevant sorted set when an integer field is updated', (done) ->
      testObjectPromise = @redisObjectClassDataStore.update @testObj.id, integer: 9
      testObjectPromise.done (obj) =>
        @redisObjectClassDataStore.redis.zrangebyscore 'RedisObjectClassDataStore>integer', 0, 10, 'withscores', (err, res) =>
          expect(res).toEqual [@testObj.id, '9']
          done()

    it 'should update the relevant key-value pair when an identifier field is updated', (done) ->
      testObjectPromise = @redisObjectClassDataStore.update @testObj.id, identifier: 'edited'
      testObjectPromise.done (obj) =>
        multi = @redisObjectClassDataStore.redis.multi()
        multi.get 'RedisObjectClassDataStore#identifier:edited'
        multi.get 'RedisObjectClassDataStore#identifier:identifier'
        multi.exec (err, res) =>
          expect(res[0]).toEqual @testObj.id
          expect(res[1]).toEqual null
          expect(res.length).toEqual 2
          done()

    it 'should add to a set when an reference field is updated', (done) ->
      pending()
      testObjectPromise = @redisObjectClassDataStore.update(@testObj.id, manyReferences: ['editedId1'])
      testObjectPromise.done (obj) =>
        @redisObjectClassDataStore.redis.smembers 'RedisObjectClassDataStore:' + @testObj.id + '#manyReferences:ReferenceRefs', (err, members) ->
          expect(members).toContain 'editedId1'
          expect(members.length).toEqual 4
          done()

    it 'removes from a set', (done) ->
      @redisObjectClassDataStore.update(@testObj.id, remove_manyReferences: [@ref1Id]).then (createdObject) =>
        @redis.smembers 'Reference:' + @ref1Id + '#manyReferences:RedisObjectClassDataStoreRefs' , (err, obj) =>
          expect(obj).not.toContain @testObj.id
          done()

    it 'removes from a set', (done) ->
      @redisObjectClassDataStore.attributes.linkedModel = 
        dataType: 'reference'
        many: true
        referenceModelName: 'LinkedModel'
      @redisObjectClassDataStore.create(url: 'one', linkedModel: [@ref1Id, @ref2Id, @ref3Id]).done (testObject) =>
        multi = @redisObjectClassDataStore.redis.multi()
        spyOn(@redisObjectClassDataStore.redis, 'multi').and.returnValue(multi)
        spyOn(multi, 'srem')
        @redisObjectClassDataStore.update(testObject.id, remove_linkedModel: [@ref1Id, @ref3Id]).then (createdObject) =>
          expect(multi.srem).toHaveBeenCalledWith('RedisObjectClassDataStore:' + createdObject.id + '#linkedModel:LinkedModelRefs', @ref1Id, @ref3Id  )
          expect(multi.srem).toHaveBeenCalledWith('LinkedModel:' + @ref1Id + '#linkedModel:RedisObjectClassDataStoreRefs', createdObject.id)
          expect(multi.srem).toHaveBeenCalledWith('LinkedModel:' + @ref3Id + '#linkedModel:RedisObjectClassDataStoreRefs', createdObject.id)
          done()

    it 'should update the relevant set when a boolean field is updated', (done) ->
      testObjectPromise = @redisObjectClassDataStore.update @testObj.id, boolean: false
      testObjectPromise.done (obj) =>
        multi = @redisObjectClassDataStore.redis.multi()
        multi.zrange 'RedisObjectClassDataStore#boolean:false', 0, -1
        multi.zrange 'RedisObjectClassDataStore#boolean:true', 0, -1
        multi.exec (err, res) =>
          expect(res[0]).toEqual [@testObj.id]
          expect(res[1]).toEqual []
          expect(res.length).toEqual 2
          done()

    it 'should remove partial words sets when there is a searchable field', (done) ->
      spyOn(@redisObjectClassDataStore.redis, 'zrem').and.callThrough()
      @redisObjectClassDataStore.update(@testObj.id, searchableText: null).then (createdObject) =>
        calledArgs = @redisObjectClassDataStore.redis.zrem.calls.allArgs()
        keysCalled = []
        for call in calledArgs
          keysCalled.push call[0]
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/s')
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/se')
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/sea')
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/sear')
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/search')
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/t')
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/th')
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/thi')
        expect(keysCalled).toContain('RedisObjectClassDataStore#searchableText/this')
        done()

    it 'should update the relevant sorted set when a sortable string is updated', (done) ->
      testObjectPromise = @redisObjectClassDataStore.update @testObj.id, sortableString: 'second'
      testObjectPromise.done (obj) =>
        @redis.zrange "RedisObjectClassDataStore>sortableString", 0, -1, (error, list) =>
          expect(list).toEqual [@testObj.id]
          done()

    it 'should update the object', (done) ->
      updateProps = { one: 1, integer: 2, identifier: 'newidentifier', sortableString: 'second', sortableInteger: 2, searchableText: 'new Search this', boolean: false }
      _.assign(@testObj, updateProps)
      testObjectPromise = @redisObjectClassDataStore.update @testObj.id, updateProps
      testObjectPromise.done (obj) =>
        @redisObjectClassDataStore.find(@testObj.id).done (returnValue) =>
          expect(returnValue).toEqual @testObj
          done()

    describe '"remove_" prefix', ->
      it 'should remove values from a set when an reference is updated', (done) ->
        testObjectPromise = @redisObjectClassDataStore.update @testObj.id, remove_manyReferences: [@ref2Id, '2']
        testObjectPromise.done (obj) =>
          @redisObjectClassDataStore.redis.smembers 'RedisObjectClassDataStore:' + @testObj.id + '#manyReferences:ReferenceRefs', (err, members) =>
            expect(members).toContain @ref1Id 
            expect(members).toContain @ref3Id
            expect(members.length).toEqual 2
            done()
