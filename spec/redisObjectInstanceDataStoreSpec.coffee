redisObjectInstanceDataStore = require '../../lib/privateModules/redisObjectInstanceDataStore'

describe 'redisObjectInstanceDataStore', ->
  it 'should be an Object', ->
    expect(redisObjectInstanceDataStore).toEqual jasmine.any(Object)
