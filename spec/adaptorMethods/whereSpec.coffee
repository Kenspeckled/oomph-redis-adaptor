where = require '../../src/adaptorMethods/where'
create = require '../../src/adaptorMethods/create'
find = require '../../src/adaptorMethods/find'
Promise = require 'promise'
_ = require 'lodash'
redis = require 'redis'

describe 'oomphRedisAdaptor#where', ->

  beforeAll (done) ->
    @redis = redis.createClient(1111, 'localhost')
    done()

  beforeEach ->
    @parentObject =
      className: 'TestWhereClass'
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
    @where = where.bind(@parentObject)
    referenceModelparentObject =
      className: 'Reference'
      redis: @redis
      classAttributes:
        secondId:
          dataType: 'string'
          identifiable: true
    @referenceModelCreate = create.bind(referenceModelparentObject)

  afterEach (done) ->
    @redis.flushdb()
    done()

  afterAll (done) ->
    @redis.flushdb()
    @redis.end()
    done()

  it 'should remove temporary sorted sets', (done) ->
    testPromise1 = @parentObject.create( url: 'uniqueValue1', integer: 1 )
    testPromise2 = @parentObject.create( url: 'uniqueValue2', integer: 1 )
    testPromise3 = @parentObject.create( url: 'uniqueValue3', integer: 2 )
    Promise.all([testPromise1,testPromise2,testPromise3]).done =>
      wherePromise = @where(integer: 1)
      wherePromise.done (returnValue) =>
        # Key expires in one second
        setTimeout =>
          @redis.keys 'temporary*', (err, keys) ->
            expect(keys).toEqual []
            done()
        , 1000

  it 'should return a promise', ->
    testObject = @where(one: '1')
    expect(testObject).toEqual jasmine.any(Promise)

  it 'should be able to return multiple test objects', (done) ->
    testPromise1 = @parentObject.create( url: 'uniqueValue1', boolean: true )
    testPromise2 = @parentObject.create( url: 'uniqueValue2', boolean: true )
    testPromise3 = @parentObject.create( url: 'uniqueValue3', boolean: false )
    testPromise4 = @parentObject.create( url: 'uniqueValue3', boolean: 'false' )
    Promise.all([testPromise1,testPromise2,testPromise3,testPromise4]).done =>
      wherePromise = @where(boolean: true)
      wherePromise.done (returnValue) =>
        expect(returnValue.total).toEqual 2
        expect(returnValue.items.length).toEqual 2
        done()

  it 'should be able to return a single test objects', (done) ->
    testPromise1 = @parentObject.create( url: 'uniqueValue1', one: 2 )
    testPromise2 = @parentObject.create( url: 'uniqueValue2', one: 1 )
    testPromise3 = @parentObject.create( url: 'uniqueValue3', one: 1 )
    Promise.all([testPromise1,testPromise2,testPromise3]).done (testObjects) =>
      [@testObject1, @testObject2, @testObject3] = testObjects
      wherePromise = @where(one: equalTo: 2)
      wherePromise.done (returnValue) =>
        expect(returnValue.total).toEqual 1
        expect(returnValue.items.length).toEqual 1
        expect(returnValue.items[0]).toEqual @testObject1
        done()

  it 'should return correct test objects when multiple properties conditions are met', (done) ->
    testPromise1 = @parentObject.create( url: 'uniqueValue1', one: 1, two: 1 )
    testPromise2 = @parentObject.create( url: 'uniqueValue2', one: 1, two: 2 )
    testPromise3 = @parentObject.create( url: 'uniqueValue3', one: 1, two: 2 )
    Promise.all([testPromise1,testPromise2,testPromise3]).then =>
      whereConditions =
        one:
          equalTo: 1
        two:
          equalTo: 1
      wherePromise = @where(whereConditions)
      wherePromise.done (returnValue) =>
        expect(returnValue.items.length).toEqual 1
        expect(returnValue.total).toEqual 1
        expect(returnValue.items[0]).toEqual jasmine.objectContaining  url: 'uniqueValue1'
        done()

  it 'should return an empty array when nothing matches the conditions', (done) ->
    testPromise1 = @parentObject.create( url: 'uniqueValue1', one: 1, two: 2, three: 3 )
    testPromise2 = @parentObject.create( url: 'uniqueValue2', one: 1, two: 2, three: 3 )
    testPromise3 = @parentObject.create( url: 'uniqueValue3', one: 1, two: 2, three: 3 )
    Promise.all([testPromise1,testPromise2,testPromise3]).then =>
      whereConditions =
        one:
          equalTo: 1
        two:
          equalTo: 2
        three:
          equalTo: 4
      wherePromise = @where(whereConditions)
      wherePromise.done (returnValue) =>
        expect(returnValue.total).toEqual 0
        expect(returnValue.items).toEqual []
        done()

  it "should resolve to an array of valid instances of the module's class", (done) ->
    testPromise1 = @parentObject.create( url: 'uniqueValue1', one: 1 )
    testPromise2 = @parentObject.create( url: 'uniqueValue2', one: 1 )
    testPromise3 = @parentObject.create( url: 'uniqueValue3', one: null )
    Promise.all([testPromise1,testPromise2,testPromise3]).then (testObjects) =>
      [@testObject1, @testObject2, @testObject3] = testObjects
      wherePromise = @where(one: 1)
      wherePromise.done (returnValue) =>
        expect(returnValue.items).toContain @testObject1
        expect(returnValue.items).toContain @testObject2
        expect(returnValue.items.length).toEqual 2
        expect(returnValue.total).toEqual 2
        done()

  it 'should return an array of objects sorted consistently (by id)', (done) ->
    integerArray = [1, 1, 1, 2, 2, 3, 4, 5, 5]
    promiseArray = _.map integerArray, (integer) =>
      @parentObject.create( integer: integer )
    Promise.all(promiseArray).then (createdObjectArray) =>
      @where(integer: equalTo: 1).done (firstResultArray) =>
        @where(integer: equalTo: 1).done (secondResultArray) =>
          expect(secondResultArray).toEqual firstResultArray
          expect(secondResultArray.items.length).toEqual 3
          expect(secondResultArray.total).toEqual 3
          done()

  it "should default to sorting by created at time (reverse alphabetically by id)", (done) ->
    createDelayedObj = (integer) ->
      new Promise (resolve) =>
        setTimeout =>
          resolve @parentObject.create(integer: integer)
        , 10
    delayedCreatePromises = []
    for i in [0..9]
      delayedCreatePromises.push createDelayedObj.apply(this, [i%2])
    Promise.all(delayedCreatePromises).then (createdObjectArray) =>
      @where(integer: {equalTo: 1}, sortDirection: 'asc').done (returnArray) ->
        returnedIds = if returnArray then _.map(returnArray.items.ids, (x) -> x.id ) else []
        sortedReturnedIds = returnedIds.sort (a,b) -> return a > b
        expect(returnArray.items.length).toEqual 5
        expect(returnedIds).toEqual sortedReturnedIds
        done()

  describe 'arguements', ->
    describe 'integers', ->
      beforeEach (done) ->
        testPromise1 = @parentObject.create( url: 'uniqueValue1', integer: 5 )
        testPromise2 = @parentObject.create( url: 'uniqueValue2', integer: 10 )
        testPromise3 = @parentObject.create( url: 'uniqueValue3', integer: 15 )
        Promise.all([testPromise1,testPromise2,testPromise3]).then (testObjects) =>
          [@testObject1, @testObject2, @testObject3] = testObjects
          done()

      it 'should return an array of objects that have an integer greater than', (done) ->
        whereConditions =
          integer:
            greaterThan: 10
        wherePromise = @where(whereConditions)
        wherePromise.done (returnValue) =>
          expect(returnValue.items.length).toEqual 1
          expect(returnValue.total).toEqual 1
          expect(returnValue.items[0]).toEqual @testObject3
          done()

      it 'should return an array of objects that have an integer greater than or equal to', (done) ->
        whereConditions =
          integer:
            greaterThanOrEqualTo: 10
        wherePromise = @where(whereConditions)
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
        wherePromise = @where(whereConditions)
        wherePromise.done (returnValue) =>
          expect(returnValue.items.length).toEqual 1
          expect(returnValue.total).toEqual 1
          expect(returnValue.items[0]).toEqual @testObject1
          done()

      it 'should return an array of objects that have an integer less than or equal to', (done) ->
        whereConditions =
          integer:
            lessThanOrEqualTo: 10
        wherePromise = @where(whereConditions)
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
        wherePromise = @where(whereConditions)
        wherePromise.done (returnValue) =>
          expect(returnValue.items.length).toEqual 1
          expect(returnValue.total).toEqual 1
          expect(returnValue.items[0]).toEqual @testObject2
          done()

    describe 'keywords', ->
      beforeEach (done) ->
        testPromise1 = @parentObject.create( url: 'uniqueValue1', searchableText: 'bananas apples throat', searchableString: 'tongue' )
        testPromise2 = @parentObject.create( url: 'uniqueValue2', searchableText: 'two one four', searchableString: 'neck apples' )
        testPromise3 = @parentObject.create( url: 'uniqueValue3', searchableText: 'One two Three throat', searchableString: 'throat two' )
        Promise.all([testPromise1,testPromise2,testPromise3]).then (testObjects) =>
          [@testObject1, @testObject2, @testObject3] = testObjects
          done()

      it 'should return an array of objects that includes case insensitive keywords', (done) ->
        whereConditions =
          includes:
            keywords: 'one'
            in: 'searchableText'
        wherePromise = @where(whereConditions)
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
        wherePromise = @where(whereConditions)
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
        wherePromise = @where(whereConditions)
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
          wherePromise = @where(whereConditions)
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
          wherePromise = @where(whereConditions)
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
          wherePromise = @where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 0
            done()

      describe 'inAnyOf', ->
        it 'should return an array of objects that includes keywords in any different attributes', (done) ->
          whereConditions =
            includes:
              keywords: 'throat'
              inAnyOf: ['searchableText', 'searchableString']
          wherePromise = @where(whereConditions)
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
            sortDirection: 'asc'
          wherePromise = @where(whereConditions)
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
            sortDirection: 'asc'
          wherePromise = @where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.items[0]).toEqual @testObject1
            expect(returnValue.items[1]).toEqual @testObject2
            done()

        it 'should return an array of objects that includes multiple keywords in any different attributes ordered by relevance by default', (done) ->
          testPromise1 = @parentObject.create( searchableText: 'bear', searchableString: 'cow cow' )
          testPromise2 = @parentObject.create( searchableText: 'cow cow', searchableString: 'bear' )
          testPromise3 = @parentObject.create( searchableText: 'cow', searchableString: 'dog' )
          whereConditions =
            includes:
              keywords: 'bear cow'
              inAnyOf: ['searchableText', 'searchableString']
              modifiedWeights: [
                attributes: 'searchableString'
                weight: 0.5
              ]
            sortDirection: 'asc'
          Promise.all([testPromise1,testPromise2,testPromise3]).done (testObjects) =>
            [@testObject1, @testObject2, @testObject3] = testObjects
            wherePromise = @where(whereConditions)
            wherePromise.done (returnValue) =>
              expect(returnValue.items.length).toEqual 2
              expect(returnValue.items).toContain @testObject2
              expect(returnValue.items).toContain @testObject1
              done()

    describe 'reference', ->
      beforeEach (done) ->
        @parentObject.classAttributes.oneRef =
          dataType: 'reference'
          referenceModelName: 'Reference'
        @manyReferences =
          dataType: 'reference'
          many: true
          referenceModelName: 'Reference'
        ref1 = @referenceModelCreate(secondId: 'id1')
        ref2 = @referenceModelCreate(secondId: 'id2')
        ref3 = @referenceModelCreate(secondId: 'id3')
        ref4 = @referenceModelCreate(secondId: 'id4')
        ref5 = @referenceModelCreate(secondId: 'id5')
        createTestObjectsPromise = Promise.all([ref1, ref2, ref3, ref4, ref5]).then (references) =>
          [@ref1, @ref2, @ref3, @ref4, @ref5] = references
          testPromise1 = @parentObject.create( url: 'uniqueValue1', manyReferences: [@ref1.id, @ref2.id], oneRef: @ref4.id )
          testPromise2 = @parentObject.create( url: 'uniqueValue2', manyReferences: [@ref2.id], oneRef: @ref4.id )
          testPromise3 = @parentObject.create( url: 'uniqueValue3', manyReferences: [@ref1.id, @ref2.id, @ref3.id], oneRef: @ref5.id )
          Promise.all([testPromise1,testPromise2,testPromise3])
        createTestObjectsPromise.then (testObjects) =>
          [@testObject1, @testObject2, @testObject3] = testObjects
          done()

      describe 'includesAllOf', ->
        it 'returns all objects when all match', (done) ->
          wherePromise = @where manyReferences: { includesAllOf: [@ref1.id, @ref2.id, @ref3.id] }
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 1
            expect(returnValue.items).toContain @testObject3
            done()

        it 'returns some objects when some match', (done) ->
          wherePromise = @where manyReferences: { includesAllOf: [@ref1.id, @ref2.id] }
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.items).toContain @testObject1
            expect(returnValue.items).toContain @testObject3
            done()

        it 'returns one object when one matches', (done) ->
          wherePromise = @where manyReferences: { includesAllOf: [@ref2.id] }
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 3
            expect(returnValue.items).toContain @testObject1
            expect(returnValue.items).toContain @testObject2
            expect(returnValue.items).toContain @testObject3
            done()

      describe 'includesAnyOf', ->
        it 'returns all objects when all match', (done) ->
          wherePromise = @where manyReferences: { includesAnyOf: [@ref3.id] }
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 1
            expect(returnValue.items).toContain @testObject3
            done()

        it 'returns some objects when some match', (done) ->
          wherePromise = @where manyReferences: { includesAnyOf: [@ref1.id, @ref3.id] }
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.items).toContain @testObject1
            expect(returnValue.items).toContain @testObject3
            done()

        it 'returns one object when one matches', (done) ->
          wherePromise = @where manyReferences: { includesAnyOf: [@ref2.id] }
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 3
            expect(returnValue.items).toContain @testObject1
            expect(returnValue.items).toContain @testObject2
            expect(returnValue.items).toContain @testObject3
            done()

      describe 'non-many', ->
        it 'returns all objects when all match', (done) ->
          wherePromise = @where oneRef: { anyOf: [@ref4.id, @ref5.id] }
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 3
            expect(returnValue.items).toContain @testObject1
            expect(returnValue.items).toContain @testObject2
            expect(returnValue.items).toContain @testObject3
            done()

        it 'returns some objects when some match', (done) ->
          wherePromise = @where oneRef: @ref4.id
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.items).toContain @testObject1
            expect(returnValue.items).toContain @testObject2
            done()

        it 'returns one object when one matches', (done) ->
          wherePromise = @where oneRef: @ref5.id
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 1
            expect(returnValue.items).toContain @testObject3
            done()

    describe 'sortBy', ->
      it 'should return an array of objects ordered by a sortable field', (done) ->
        testPromise1 = @parentObject.create( url: 'uniqueValue1', sortableString: 'alpha', boolean: true  )
        testPromise2 = @parentObject.create( url: 'uniqueValue2', sortableString: 'beta', boolean: false )
        testPromise3 = @parentObject.create( url: 'uniqueValue3', sortableString: 'charlie', boolean: true )
        whereConditions =
          boolean: true
          sortBy: 'sortableString'
          sortDirection: 'asc'
        Promise.all([testPromise1,testPromise2,testPromise3]).done (testObjects) =>
          [@testObject1, @testObject2, @testObject3] = testObjects
          wherePromise = @where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.items[0]).toEqual @testObject1
            expect(returnValue.items[1]).toEqual @testObject3
            done()

      it 'should return an array of objects that includes keywords in different attributes, ordered by a sortable field (not weight)', (done) ->
        testPromise1 = @parentObject.create( url: 'uniqueValue1', searchableText: 'bananas apples throat', searchableString: 'tongue', sortableString: 'charlie' )
        testPromise2 = @parentObject.create( url: 'uniqueValue2', searchableText: 'two one four', searchableString: 'neck', sortableString: 'beta' )
        testPromise3 = @parentObject.create( url: 'uniqueValue3', searchableText: 'One two Three', searchableString: 'throat', sortableString: 'alpha' )
        whereConditions =
          includes:
            keywords: 'throat'
            inAnyOf: ['searchableText', 'searchableString']
            modifiedWeights: [
              attributes: 'searchableText'
              weight: 2
            ]
          sortBy: 'sortableString'
          sortDirection: 'asc'
        Promise.all([testPromise1,testPromise2,testPromise3]).done (testObjects) =>
          [@testObject1, @testObject2, @testObject3] = testObjects
          wherePromise = @where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 2
            expect(returnValue.items[0]).toEqual @testObject3
            expect(returnValue.items[1]).toEqual @testObject1
            done()

      it 'should return an array of objects randomly ordered', (done) ->
        # Occassional fail expected - testing random order'
        #FIXME: shouldn't have randomly failing tests
        urlArray = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel','india', 'juliet' ]
        i = 0
        promiseArray = _.map urlArray, (url) =>
          i++
          @parentObject.create( url: url, boolean: (i <= 5) )
        whereConditions =
          sortBy: 'random'
          boolean: true
        Promise.all(promiseArray).done =>
          wherePromise = @where(whereConditions)
          wherePromise.done (returnValue) =>
            expect(returnValue.items.length).toEqual 5
            expect(returnValue[4]).not.toEqual jasmine.objectContaining  url: 'echo'
            done()

