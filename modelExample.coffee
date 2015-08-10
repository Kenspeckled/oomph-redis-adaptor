class Engine extends ObjectOrientedModel
  @defineFields
    manufacturingId:
      dataType: 'string'
      identifiable: true
      sortable: true
      validates:
        presence: true
        uniqueness: true
    modelSpec:
      dataType: 'reference'
      referenceModelName: 'ModelSpec'
    horsePower:
      dataType: 'integer'
    parts:
      dataType: 'reference'
      many: true
      referenceModelName: 'Part'
      reverseReferenceAttribute: 'engines'
    specialPart:
      dataType: 'reference'
      referenceModelName: 'Part'
    accessories:
      dataType: 'reference'
      referenceModelName: 'Accessory'
      many: true

# This should generate the following database data:
# 'Engine:[engineId]' => { id: 'engine1', manufacturingId: 'abc', modelSpec: 'xk13ed', horsePower: 5, parts: true, accessories: true }
# 'Engine#manufacturingId:abc' => 'engine1'
# 'Engine>id' => [ 1 => 'engine1']
# 'Engine>manufacturingId' => [ 1 => 'engine1']
# 'ModelSpec:[modelSpecId]#EngineRefs' => [ 'engine1']
# 'Engine>horsePower' => [ 5 => 'engine1']
# 'Engine:[engineId]#PartRefs' => [ '12345', '123545', '351324' ]

# 'Engine:[engineId]#parts:PartRefs' => [ '12345', '123545', '351324' ]
# 'Part:[partId]#engines:EngineRefs' => [ 'engine1', 'engine2' ]

# 'Engine:[engineId]#PartRefs:specialParts' => [ '12345', '123545', '351324' ]
# 'Part:[partId]#EngineRefs:specialParts' => [ 'engine1']

# 'Accessory:[accessoryId]#EngineRefs' => [ 'engine1' ]

class Part  extends ObjectOrientedModel
  @defineFields
    engines:
      dataType: 'reference'
      referenceModelName: 'Engine'
      many: true
      reverseReferenceAttribute: 'parts' # namespace to match other model for bi-directional reference
    classification:
      dataType: 'string'
      searchable: true
      validates:
        format: /\w\w\w\d\d/

# This should generate the following database data:
# 'Part:[partId]' => { id: '12345', engines: 2, classification: 'abc12' }

# 'Part:[partId]#engines:EngineRefs' => [ 'engine1', 'engine2' ]
# 'Engine:[engineId]#parts:PartRefs' => [ '12345', '123545', '351324' ]

# 'Parts#classification/a' => ['12345', '12346', '12347']
# 'Parts#classification/ab' => ['12345', '12346']
# 'Parts#classification/abc' => ['12345']
# 'Parts#classification/abc1' => ['12345']
# 'Parts#classification/abc12' => ['12345']


#Engine.where parts: { includesAnyOf: ['12345', '351324'] }
#Engine.where parts: { includesAllOf: ['12345', '351324'] }
#Parts.where parts: { excludesAnyOf: ['12345', '351324'] }
#Parts.where parts: { excludesAllOf: ['12345', '351324'] }
