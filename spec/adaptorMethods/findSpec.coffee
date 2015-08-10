find = require '../../src/adaptorMethods/find'
Promise = require 'promise'
_ = require 'lodash'

describe 'oomphRedisAdaptor#find', ->
  
  beforeAll ->
    parentObject = 
      classAttributes: {}
    @find = find.bind(parentObject)

  it 'should return a promise', ->
    testObject = @find('test1')
    expect(testObject).toEqual jasmine.any(Promise)

  it 'should resolve to a valid instance of the modules class when given an id', (done) ->
    pending()
    #redisObjectClassDataStoreClass = @redisObjectClassDataStoreClass
    #testProps = { one: 1, two: 2, three: 3 }
    #test1Object = new redisObjectClassDataStoreClass(testProps)
    #create(testProps).then (returnObject) =>
    #  id = returnObject.id
    #  findPromise = find(id)
    #  findPromise.done (returnValue) ->
    #    # remove generated props for the test
    #    delete returnValue.id
    #    delete returnValue.createdAt
    #    expect(returnValue).toEqual test1Object
    #    done()

  it 'should reject if no object is found', (done) ->
    findPromise = @find('nonExistentObjectID')
    findPromise.catch (error) ->
      expect(error).toEqual new Error "Not Found"
      done()

  it 'should create an object of the same class as the module owner', (done) ->
    pending()

  it 'should return an integer correctly', (done) ->
    testProps = { integer: '1'}
    create(testProps).then (createdObject) =>
      findPromise = @find(createdObject.id)
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
      create(singleReference: ref1.id).then (createdObject) =>
        findPromise = @find(createdObject.id)
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
      create(testProps).then (createdObject) =>
        findPromise = @find(createdObject.id)
        findPromise.done (foundObj) ->
          expect(foundObj.manyReferences).toContain referencesObjects[0]
          expect(foundObj.manyReferences).toContain referencesObjects[1]
          expect(foundObj.manyReferences).toContain referencesObjects[2]
          expect(foundObj.manyReferences.length).toEqual 3
          done()

