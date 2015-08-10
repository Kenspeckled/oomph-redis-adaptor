where = require '../../src/adaptorMethods/where'
Promise = require 'promise'
_ = require 'lodash'

describe 'oomphRedisAdaptor#where', ->

  beforeAll ->
    parentObject = 
      classAttributes: {}
    @where = where.bind(parentObject)

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

