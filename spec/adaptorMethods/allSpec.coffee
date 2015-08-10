all = require '../../src/adaptorMethods/all'
Promise = require 'promise'
_ = require 'lodash'

describe 'oomphRedisAdaptor#all', ->

  beforeAll ->
    parentObject = 
      classAttributes: {}
    @all = all.bind(parentObject)

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

