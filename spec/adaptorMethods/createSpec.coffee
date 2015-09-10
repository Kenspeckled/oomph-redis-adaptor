create = require '../../src/adaptorMethods/create'
Promise = require 'promise'
ValidationError = require 'oomph/lib/ValidationError'
_ = require 'lodash'
redis = require 'redis'

describe 'oomphRedisAdaptor#create', ->

  beforeAll (done) ->
    @redis = redis.createClient(1111, 'localhost')
    done()

  beforeEach ->
    @parentObject = 
      className: 'TestCreateClass'
      redis: @redis 
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
    @create = create.bind(@parentObject)
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
  
  it 'should return a promise', ->
    createPromise = @create(integer: 1)
    expect(createPromise).toEqual jasmine.any(Promise)

  describe 'stored data types', ->
    describe 'for string attributes', ->

      describe 'where identifiable is true', ->
        it 'adds to a key-value pair', (done) ->
          multi = @redis.multi()
          spyOn(@redis, 'multi').and.returnValue(multi)
          spyOn(multi, 'set')
          @create(identifier: 'identifierValue').then (createdObject) ->
            expect(multi.set).toHaveBeenCalledWith('TestCreateClass#identifier:identifierValue', createdObject.id)
            done()

      describe 'where url is true', ->
        it 'stores the generated url string in the object hash ', (done) ->
          @create(name: "Héllo & gøød nîght").then (createdObject) ->
            expect(createdObject.url).toEqual 'hello-and-good-night' 
            done()

        it 'adds to a key-value pair with a generated url string', (done) ->
          multi = @redis.multi()
          spyOn(@redis, 'multi').and.returnValue(multi)
          spyOn(multi, 'set')
          @create(name: "Héllo & gøød nîght").then (createdObject) ->
            expect(multi.set).toHaveBeenCalledWith('TestCreateClass#url:hello-and-good-night', createdObject.id)
            done()

        it "appends a sequential number for duplicate generated url string", (done) ->
          @create(name: "Héllo & gøød nîght").then (obj1) =>
            @create(name: "Héllo & good night").then (obj2) =>
              @create(name: "Hello & good night").then (obj3) ->
                expect(obj1.url).toEqual 'hello-and-good-night' 
                expect(obj2.url).toEqual 'hello-and-good-night-1' 
                expect(obj3.url).toEqual 'hello-and-good-night-2' 
                done()

      describe 'where sortable is true', ->
        it 'adds to an ordered list', (done) ->
          testPromise1 = @create( sortableString: 'd' )
          testPromise2 = @create( sortableString: 'a' )
          testPromise3 = @create( sortableString: 'c' )
          testPromise4 = @create( sortableString: 'b' )
          Promise.all([testPromise1,testPromise2,testPromise3,testPromise4]).done (testObjectArray) =>
            test1Id = testObjectArray[0].id
            test2Id = testObjectArray[1].id
            test3Id = testObjectArray[2].id
            test4Id = testObjectArray[3].id
            @redis.zrange "TestCreateClass>sortableString", 0, -1, (error, list) ->
              expect(list).toEqual [test1Id, test3Id, test4Id, test2Id]
              done()

      describe 'where searchable is true', ->
        it 'adds to partial words sets when the modules class has attributes with the field type of "string" and is searchable', (done) ->
          spyOn(@redis, 'zadd').and.callThrough()
          @create(searchableText: 'Search This <div>funny</div>').then (createdObject) =>
            calledArgs = @redis.zadd.calls.allArgs()
            keysCalled = []
            for call in calledArgs
              keysCalled.push call[0]
            expect(keysCalled).toContain('TestCreateClass#searchableText/s')
            expect(keysCalled).toContain('TestCreateClass#searchableText/se')
            expect(keysCalled).toContain('TestCreateClass#searchableText/sea')
            expect(keysCalled).toContain('TestCreateClass#searchableText/sear')
            expect(keysCalled).toContain('TestCreateClass#searchableText/search')
            expect(keysCalled).toContain('TestCreateClass#searchableText/t')
            expect(keysCalled).toContain('TestCreateClass#searchableText/th')
            expect(keysCalled).toContain('TestCreateClass#searchableText/thi')
            expect(keysCalled).toContain('TestCreateClass#searchableText/this')
            expect(keysCalled).toContain('TestCreateClass#searchableText/funny')
            expect(keysCalled).not.toContain('TestCreateClass#searchableText/<div>')
            done()

    describe 'for integer attributes', ->

      # Integers are always sortable
      it 'adds to a sorted set', (done) ->
        testPromise1 = @create( integer: 11 )
        testPromise2 = @create( integer: 8 )
        testPromise3 = @create( integer: 10 )
        testPromise4 = @create( integer: 9 )
        Promise.all([testPromise1,testPromise2,testPromise3,testPromise4]).done (testObjectArray) =>
          [test1, test2, test3, test4] = testObjectArray
          @redis.zrange "TestCreateClass>integer", 0, -1, (error, list) ->
            expect(list).toEqual [test2.id, test4.id, test3.id, test1.id]
            done()

      it 'adds to a sorted set with values', (done) ->
        multi = @redis.multi()
        spyOn(@redis, 'multi').and.returnValue(multi)
        spyOn(multi, 'zadd')
        @create(integer: 1).then (createdObject) ->
          expect(multi.zadd).toHaveBeenCalledWith('TestCreateClass>integer', 1, createdObject.id)
          done()


    describe 'for boolean attributes', ->
      it 'adds to a zset', (done) ->
        multi = @redis.multi()
        spyOn(@redis, 'multi').and.returnValue(multi)
        spyOn(multi, 'zadd')
        @create(boolean: true).then (createdObject) ->
          expect(multi.zadd).toHaveBeenCalledWith('TestCreateClass#boolean:true', 1, createdObject.id)
          done()

    describe 'for reference attributes', ->

      describe 'when many is true', ->

        it "sets the reference to true", (done) ->
          createReference = @referenceModelCreate(secondId: 'id1')
          createTestObj = createReference.then (ref1) => @create(manyReferences: [ref1.id])
          createTestObj.then (createdObject) =>
            @redis.hgetall 'TestCreateClass:' + createdObject.id, (err, obj) ->
              expect(obj.manyReferences).toEqual 'true'
              done()

        it "sets the reference to even when empty", (done) ->
          @referenceModelCreate(secondId: 'id1').then (ref1) =>
            @create(url: 'one').then (createdObject) =>
              @redis.hgetall 'TestCreateClass:' + createdObject.id, (err, obj) ->
                expect(obj.manyReferences).toEqual 'true'
                done()

        it 'adds to a set', (done) ->
          @parentObject.classAttributes =
            linkedModel:
              dataType: 'reference'
              many: true
              referenceModelName: 'LinkedModel'
          @create = create.bind(@parentObject)
          multi = @redis.multi()
          spyOn(@redis, 'multi').and.returnValue(multi)
          spyOn(multi, 'sadd')
          @create(linkedModel: ['linkedModelId1', 'linkedModelId2']).then (createdObject) ->
            expect(multi.sadd).toHaveBeenCalledWith('TestCreateClass:' + createdObject.id + '#linkedModel:LinkedModelRefs', 'linkedModelId1', 'linkedModelId2')
            expect(multi.sadd).toHaveBeenCalledWith('LinkedModel:linkedModelId1#linkedModel:TestCreateClassRefs', createdObject.id)
            expect(multi.sadd).toHaveBeenCalledWith('LinkedModel:linkedModelId2#linkedModel:TestCreateClassRefs', createdObject.id)
            done()

        it 'adds to a set with a reverseReferenceAttribute', (done) ->
          @parentObject.classAttributes =
            linkedModel:
              dataType: 'reference'
              many: true
              referenceModelName: 'LinkedModel'
              reverseReferenceAttribute: 'namespaced'
          multi = @redis.multi()
          spyOn(@redis, 'multi').and.returnValue(multi)
          spyOn(multi, 'sadd')
          @create = create.bind(@parentObject)
          @create(linkedModel: ['linkedModelId1', 'linkedModelId2']).then (createdObject) ->
            expect(multi.sadd).toHaveBeenCalledWith('TestCreateClass:' + createdObject.id + '#linkedModel:LinkedModelRefs', 'linkedModelId1', 'linkedModelId2')
            expect(multi.sadd).toHaveBeenCalledWith('LinkedModel:linkedModelId1#namespaced:TestCreateClassRefs', createdObject.id)
            expect(multi.sadd).toHaveBeenCalledWith('LinkedModel:linkedModelId2#namespaced:TestCreateClassRefs', createdObject.id)
            done()

      describe 'when many is not true', ->
        it 'stores the reference id', (done) ->
          @referenceModelCreate(secondId: 'id1').done (ref1) =>
            @create(reference: ref1.id).then (createdObject) =>
              @redis.hgetall 'TestCreateClass:' + createdObject.id, (err, obj) ->
                expect(obj.reference).toEqual ref1.id 
                done()

  it 'should return a promise', ->
    testObjectPromise = @create(url: 'uniqueValue')
    expect(testObjectPromise).toEqual jasmine.any(Promise)

  it 'should resolve an object with a 10 character id', (done) ->
    # This test will fail from Sun May 25 2059 18:38:27 BST (2821109907456 unix time)
    # and the number of characters will increase by 1
    testObjectPromise = @create(url: 'uniqueValue')
    testObjectPromise.done (testObject) ->
      expect(testObject.id.length).toEqual 10
      done()

  it "should create an object with properties that are defined in the class' attributes", (done) ->
    testObjectPromise = @create(boolean: false)
    testObjectPromise.then (testObject) ->
      expect(testObject.boolean).toBe false
      done()

  it "should create an object and ignore properties that are not defined in the class' attributes", (done) ->
    @create(notAnAttribute: 'value').catch (error) =>
      expect(error).toEqual(new Error "No valid fields given")
      done()

  describe 'presence validation', ->
    it 'should create objects that pass validation', (done) ->
      @parentObject.classAttributes.presenceValidation =
        dataType: 'string'
        validates:
          presence: true
      @create = create.bind(@parentObject)
      @create(presenceValidation: 'value').then (testObject) =>
        expect(testObject.presenceValidation).toEqual 'value'
        done()

    it 'should not create objects that fail validation', (done) ->
      @parentObject.classAttributes.presenceValidation =
        dataType: 'string'
        identifiable: true
        validates:
          presence: true
      @create = create.bind(@parentObject)
      @create(one: 1, presenceValidation: null).catch (errors) ->
        expect(errors).toContain(new Error 'presenceValidation must be present')
        done()

  describe 'length validation', ->

    it 'should not create objects that fail length validation by having a length that is greater than', (done) ->
      @parentObject.classAttributes.lengthValidation =
        dataType: 'string'
        validates:
          length:
            is: 9
      @create = create.bind(@parentObject)
      @create(one: 1, lengthValidation: 'elevenchars').catch (errors) ->
        expect(errors.length).toEqual 1
        expect(errors).toContain jasmine.any ValidationError
        expect(errors).toContain jasmine.objectContaining message: 'lengthValidation should have a length of 9'
        done()

    it 'should not create objects that fail length validation by having a length that is less than', (done) ->
      @parentObject.classAttributes.lengthValidation =
        dataType: 'string'
        validates:
          length:
            is: 9
      @create = create.bind(@parentObject)
      @create(lengthValidation: 'sixchr').catch (errors) ->
        expect(errors.length).toEqual 1
        expect(errors).toContain jasmine.any ValidationError
        expect(errors).toContain jasmine.objectContaining message: 'lengthValidation should have a length of 9'
        done()

    it 'should create objects that have a length that is equal to the length validation', (done) ->
      @parentObject.classAttributes.lengthValidation =
        dataType: 'string'
        validates:
          length:
            is: 9
      @create = create.bind(@parentObject)
      @create(lengthValidation: 'ninechars').then (testObject) ->
        expect(testObject.lengthValidation).toEqual 'ninechars'
        done()

    it 'should perform the validation only when the property is present', (done) ->
      @parentObject.classAttributes.lengthValidation =
        dataType: 'string'
        validates:
          length:
            is: 9
      @create = create.bind(@parentObject)
      @create(one: 1, lengthValidation: null).then (testObject) =>
        expect(testObject.lengthValidation).toEqual undefined
        done()


    describe 'minimum length', ->
      it 'should create objects that have a length that is equal to the minimum length validation', (done) ->
        @parentObject.classAttributes.minLengthValidation =
          dataType: 'string'
          validates:
            length:
              minimum: 9
        @create = create.bind(@parentObject)
        @create(minLengthValidation: 'ninechars').then (testObject) =>
          expect(testObject.minLengthValidation).toEqual 'ninechars'
          done()

      it 'should create objects that have a length that is greater than the minimum length validation', (done) ->
        @parentObject.classAttributes.minLengthValidation =
          dataType: 'string'
          validates:
            length:
              minimum: 9
        @create = create.bind(@parentObject)
        @create(minLengthValidation: 'elevenchars').then (testObject) =>
          expect(testObject.minLengthValidation).toEqual 'elevenchars'
          done()

      it 'should not create objects that fail minLength validation', (done) ->
        @parentObject.classAttributes.minLengthValidation =
          dataType: 'string'
          validates:
            length:
              minimum: 9
        @create = create.bind(@parentObject)
        @create(minLengthValidation: 'sixchr').catch (error) =>
          expect(error).toContain(new Error 'minLengthValidation should have a minimum length of 9')
          done()

    describe 'maximum length', ->
      it 'should create objects that have a length that is equal to the maximum length validation', (done) ->
        @parentObject.classAttributes.maxLengthValidation =
          dataType: 'string'
          validates:
            length:
              maximum: 9
        @create = create.bind(@parentObject)
        @create(maxLengthValidation: 'ninechars').then (testObject) =>
          expect(testObject.maxLengthValidation).toEqual 'ninechars'
          done()

      it 'should create objects that have a length that is less than the maximum length validation', (done) ->
        @parentObject.classAttributes.maxLengthValidation =
          dataType: 'string'
          validates:
            length:
              maximum: 9
        @create = create.bind(@parentObject)
        @create(maxLengthValidation: 'sixchr').then (testObject) =>
          expect(testObject.maxLengthValidation).toEqual 'sixchr'
          done()

      it 'should not create objects that fail validation', (done) ->
        @parentObject.classAttributes.maxLengthValidation =
          dataType: 'string'
          validates:
            length:
              maximum: 9
        @create = create.bind(@parentObject)
        @create(maxLengthValidation: 'elevenchars').catch (error) =>
          expect(error).toContain(new Error 'maxLengthValidation should have a maximum length of 9')
          done()


  describe 'greaterThan validation', ->
    it 'should create objects that pass greaterThan validation', (done) ->
      @parentObject.classAttributes.greaterThanValidation =
        dataType: 'integer'
        validates:
          greaterThan: 9
      @create = create.bind(@parentObject)
      @create(greaterThanValidation: 11).then (testObject) =>
        expect(testObject.greaterThanValidation).toEqual 11
        done()

    it 'should not create objects that fail greaterThan validation by being less than', (done) ->
      @parentObject.classAttributes.greaterThanValidation =
        dataType: 'integer'
        validates:
          greaterThan: 9
      @create = create.bind(@parentObject)
      @create(greaterThanValidation: 1).catch (error) =>
        expect(error).toContain(new Error 'greaterThanValidation should be greater than 9')
        done()

    it 'should not create objects that fail greaterThan validation by being equal to', (done) ->
      @parentObject.classAttributes.greaterThanValidation =
        dataType: 'integer'
        validates:
          greaterThan: 10
      @create = create.bind(@parentObject)
      @create(greaterThanValidation: 10).catch (error) =>
        expect(error).toContain(new Error 'greaterThanValidation should be greater than 10')
        done()

  describe 'greaterThanOrEqualTo validation', ->
    it 'should create objects that pass greaterThanOrEqualTo validation by being equal to', (done) ->
      @parentObject.classAttributes.greaterThanOrEqualToValidation =
        dataType: 'integer'
        validates:
          greaterThanOrEqualTo: 10
      @create = create.bind(@parentObject)
      @create(greaterThanOrEqualToValidation: 10).then (testObject) =>
        expect(testObject.greaterThanOrEqualToValidation).toEqual 10
        done()

    it 'should create objects that pass greaterThanOrEqualTo validation by being greater than', (done) ->
      @parentObject.classAttributes.greaterThanOrEqualToValidation =
        dataType: 'integer'
        validates:
          greaterThanOrEqualTo: 10
      @create = create.bind(@parentObject)
      @create(greaterThanOrEqualToValidation: 11).then (testObject) =>
        expect(testObject.greaterThanOrEqualToValidation).toEqual 11
        done()

    it 'should not create objects that fail greaterThanOrEqualTo validation', (done) ->
      @parentObject.classAttributes.greaterThanOrEqualToValidation =
        dataType: 'integer'
        validates:
          greaterThanOrEqualTo: 10
      @create = create.bind(@parentObject)
      @create(greaterThanOrEqualToValidation: 1).catch (error) =>
        expect(error).toContain(new Error 'greaterThanOrEqualToValidation should be greater than or equal to 10')
        done()

  describe 'lessThan validation', ->
    it 'should create objects that pass lessThan validation', (done) ->
      @parentObject.classAttributes.lessThanValidation =
        dataType: 'integer'
        validates:
          lessThan: 10
      @create = create.bind(@parentObject)
      @create(lessThanValidation: 9).then (testObject) =>
        expect(testObject.lessThanValidation).toEqual 9
        done()

    it 'should not create objects that fail lessThan validation by being more than', (done) ->
      @parentObject.classAttributes.lessThanValidation =
        dataType: 'integer'
        validates:
          lessThan: 10
      @create = create.bind(@parentObject)
      @create(lessThanValidation: 11).catch (error) =>
        expect(error).toContain(new Error 'lessThanValidation should be less than 10')
        done()

    it 'should not create objects that fail lessThan validation by being equal to', (done) ->
      @parentObject.classAttributes.lessThanValidation =
        dataType: 'integer'
        validates:
          lessThan: 10
      @create = create.bind(@parentObject)
      @create(lessThanValidation: 10).catch (error) =>
        expect(error).toContain(new Error 'lessThanValidation should be less than 10')
        done()

  describe 'lessThanOrEqualTo validation', ->
    it 'should create objects that pass lessThanOrEqualTo validation by being less than', (done) ->
      @parentObject.classAttributes.lessThanOrEqualToValidation =
        dataType: 'integer'
        validates:
          lessThanOrEqualTo: 10
      @create = create.bind(@parentObject)
      @create(lessThanOrEqualToValidation: 9).then (testObject) =>
        expect(testObject.lessThanOrEqualToValidation).toEqual 9
        done()

    it 'should create objects that pass lessThanOrEqualTo validation by being equal to', (done) ->
      @parentObject.classAttributes.lessThanOrEqualToValidation =
        dataType: 'integer'
        validates:
          lessThanOrEqualTo: 10
      @create = create.bind(@parentObject)
      @create(lessThanOrEqualToValidation: 10).then (testObject) =>
        expect(testObject.lessThanOrEqualToValidation).toEqual 10
        done()

    it 'should not create objects that fail lessThanOrEqualTo validation', (done) ->
      @parentObject.classAttributes.lessThanOrEqualToValidation =
        dataType: 'integer'
        validates:
          lessThanOrEqualTo: 10
      @create = create.bind(@parentObject)
      @create(lessThanOrEqualToValidation: 11).catch (error) =>
        expect(error).toContain(new Error 'lessThanOrEqualToValidation should be less than or equal to 10')
        done()

  describe 'equalTo validation', ->
    it 'should create objects that pass equalTo validation', (done) ->
      @parentObject.classAttributes.equalToValidation =
        dataType: 'integer'
        validates:
          equalTo: 10
      @create = create.bind(@parentObject)
      @create(equalToValidation: 10).then (testObject) =>
        expect(testObject.equalToValidation).toEqual 10
        done()

    it 'should not create objects that fail equalTo validation by being more than', (done) ->
      @parentObject.classAttributes.equalToValidation =
        dataType: 'integer'
        validates:
          equalTo: 10
      @create = create.bind(@parentObject)
      @create(equalToValidation: 11).catch (error) =>
        expect(error).toContain(new Error 'equalToValidation should equal 10')
        done()

    it 'should not create objects that fail equalTo validation by being less than', (done) ->
      @parentObject.classAttributes.equalToValidation =
        dataType: 'integer'
        validates:
          equalTo: 10
      @create = create.bind(@parentObject)
      @create(equalToValidation: 9).catch (error) =>
        expect(error).toContain(new Error 'equalToValidation should equal 10')
        done()

  describe 'format validation', ->
    describe "'with'", ->
      it 'should not fail when the attribute is not present', (done) ->
        pending()

      it "should create objects that pass format validation 'with' a regular expression that accounts for all of the data", (done) ->
        @parentObject.classAttributes.formatValidation =
          dataType: 'string'
          validates:
            format:
              with: /[a-zA-Z]+/
        @create = create.bind(@parentObject)
        @create(formatValidation: 'abcd').then (testObject) =>
          expect(testObject.formatValidation).toEqual 'abcd'
          done()

      it "should create objects that pass format validation 'with' a regular expression that only accounts for some of the data", (done) ->
        @parentObject.classAttributes.formatValidation =
          dataType: 'string'
          validates:
            format:
              with: /[a-zA-Z]+/
        @create = create.bind(@parentObject)
        @create(formatValidation: 'ab123cd').then (testObject) =>
          expect(testObject.formatValidation).toEqual 'ab123cd'
          done()

      it "should not create objects that fail format validation 'with' a regular expression", (done) ->
        @parentObject.classAttributes.formatValidation =
          dataType: 'string'
          validates:
            format:
              with: /[a-zA-Z]+/
        @create = create.bind(@parentObject)
        @create(formatValidation: '123').catch (error) =>
          expect(error).toContain(new Error 'formatValidation should meet the format requirements')
          done()

      it 'should perform the validation only when the property is present', (done) ->
        @parentObject.classAttributes.formatValidation =
          dataType: 'string'
          validates:
            format:
              with: /[a-zA-Z]+/
        @create = create.bind(@parentObject)
        @create(one: 1, formatValidation: null).then (testObject) =>
          expect(testObject.formatValidation).toEqual undefined
          done()

    describe "'without'", ->
      it "should not create objects that fail validation", (done) ->
        @parentObject.classAttributes.formatValidation =
          dataType: 'string'
          validates:
            format:
              without: /[a-zA-Z]+/
        @create = create.bind(@parentObject)
        @create(formatValidation: 'abcd').catch (error) ->
          expect(error).toContain(new Error 'formatValidation should meet the format requirements')
          done()

      it "should create objects that pass format validation", (done) ->
        @parentObject.classAttributes.formatValidation =
          dataType: 'string'
          validates:
            format:
              without: /[a-zA-Z]+/
        @create = create.bind(@parentObject)
        @create(formatValidation: '123').then (testObject) =>
          expect(testObject.formatValidation).toEqual '123'
          done()

  describe 'inclusionIn validation', ->
    it 'should create objects that pass inclusionIn validation', (done) ->
      @parentObject.classAttributes.inclusionInValidation =
        dataType: 'string'
        validates:
          inclusionIn: ['one', 'two', 'three']
      @create = create.bind(@parentObject)
      @create(inclusionInValidation: 'one').then (testObject) =>
        expect(testObject.inclusionInValidation).toEqual 'one'
        done()

    it 'should not create objects that fail inclusionIn validation', (done) ->
      @parentObject.classAttributes.inclusionInValidation =
        dataType: 'string'
        validates:
          inclusionIn: ['one', 'two', 'three']
      @create = create.bind(@parentObject)
      @create(inclusionInValidation: 'four').catch (error) =>
        expect(error).toContain(new Error 'inclusionInValidation must be one of the accepted values')
        done()

  describe 'exclusionIn validation', ->
    it 'should create objects that pass exclusionIn validation', (done) ->
      @parentObject.classAttributes.exclusionInValidation =
        dataType: 'string'
        validates:
          exclusionIn: ['one', 'two', 'three']
      @create = create.bind(@parentObject)
      @create(exclusionInValidation: 'four').then (testObject) =>
        expect(testObject.exclusionInValidation).toEqual 'four'
        done()

    it 'should not create objects that fail exclusionIn validation', (done) ->
      @parentObject.classAttributes.exclusionInValidation =
        dataType: 'string'
        validates:
          exclusionIn: ['one', 'two', 'three']
      @create = create.bind(@parentObject)
      @create(exclusionInValidation: 'one').catch (error) =>
        expect(error).toContain(new Error 'exclusionInValidation must not be one of the forbidden values')
        done()

  describe 'uniqueness validation', ->
    it 'should not create objects that fail validation', (done) ->
      pending()
      @parentObject.classAttributes =
        uniquenessValidation:
          dataType: 'string'
          identifiable: true
          validates:
            uniqueness: true
      @create = create.bind(@parentObject)
      @redis.set 'TestCreateClass#uniquenessValidation:notUnique', 'test', =>
        @create(uniquenessValidation: 'notUnique').catch (errors) =>
          expect(errors).toContain(new Error 'uniquenessValidation should be a unique value')
          done()

  describe 'afterSave', ->
    it 'should perform an after save callback', (done) ->
      pending()
      @parentObject.afterSave = new Promise (resolve) ->
        console.log "hiya!!!!!!"
        resolve (4)
      @create = create.bind(@parentObject)
      @create(name: 'test').then (testObject) =>
        expect()
        done()
