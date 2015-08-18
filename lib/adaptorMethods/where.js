// Generated by CoffeeScript 1.9.3
(function() {
  var Promise, _, _utilities, createIntegerSubset, findKeywordsInAnyFields, where,
    slice = [].slice;

  Promise = require('promise');

  _ = require('lodash');

  _utilities = require('./utilities');

  findKeywordsInAnyFields = function(fields, keywords, weightOptions) {
    var unionKeyPromises, unionkeyNames;
    unionkeyNames = [];
    unionKeyPromises = _.map(keywords, (function(_this) {
      return function(keyword) {
        var field, i, keyNames, len, unionKey, unionKeyPromise, weight;
        keyNames = [];
        for (i = 0, len = fields.length; i < len; i++) {
          field = fields[i];
          weight = (weightOptions[field] && weightOptions[field].weight ? weightOptions[field].weight : 1);
          keyNames.push({
            name: _this.name + "#" + field + "/" + keyword,
            weight: weight
          });
        }
        unionKey = 'keywordUnionSet:' + _utilities.randomString(5);
        unionKeyPromise = new Promise(function(resolve) {
          var ref;
          return (ref = _this.redis).zunionstore.apply(ref, [unionKey, keyNames.length].concat(slice.call(_.map(keyNames, 'name')), ['weights'], slice.call(_.map(keyNames, 'weight')), [function() {
            return resolve(unionKey);
          }]));
        });
        return unionKeyPromise.then(function(unionKey) {
          return unionkeyNames.push(unionKey);
        });
      };
    })(this));
    return Promise.all(unionKeyPromises).then(function() {
      return unionkeyNames;
    });
  };

  createIntegerSubset = function(integerSortedSetName, tempIntegerKey, minValue, maxValue) {
    var self;
    self = this;
    return new Promise(function(resolve) {
      return self.redis.zrangebyscore(integerSortedSetName, minValue, maxValue, function(error, resultList) {
        var i, len, multi, result;
        multi = self.redis.multi();
        for (i = 0, len = resultList.length; i < len; i++) {
          result = resultList[i];
          multi.zadd(tempIntegerKey, 0, result);
          multi.expire(tempIntegerKey, 1);
        }
        return multi.exec(function() {
          return resolve();
        });
      });
    });
  };

  where = function(args) {
    var attr, end, field, fields, i, integerSortedSetName, j, k, keyword, keywordSearchPromise, keywords, l, len, len1, len2, len3, len4, m, maxValue, minValue, modifyObj, modifyObjAttrs, namespace, option, optionValue, prepareWhereConditionPromise, ref, ref1, referenceModelName, self, sortedSetKeys, start, tempIntegerKey, unionSortedSetKeys, weight, weightOptions, whereConditionPromises;
    self = this;
    args || (args = {});
    args.sortBy || (args.sortBy = (args.includes ? 'relevance' : 'id'));
    args.sortDirection || (args.sortDirection = 'asc');
    args.sortDirection.toLowerCase();
    args.limit || (args.limit = null);
    args.offset || (args.offset = null);
    if (args.sortBy === 'random') {
      start = 0;
      end = -1;
    } else {
      start = +args.offset;
      end = args.limit > 0 ? (args.limit - 1) + args.offset : -1;
    }
    if (args.sortDirection === 'desc') {
      end = args.offset > 0 ? -(args.offset + 1) : -1;
      start = args.limit > 0 ? end - (args.limit - 1) : 0;
    }
    sortedSetKeys = [];
    unionSortedSetKeys = [];
    if (args.sortBy === 'random') {
      sortedSetKeys.push({
        name: self.name + '>id'
      });
    } else if (args.sortBy !== 'relevance') {
      sortedSetKeys.push({
        name: self.name + '>' + args.sortBy
      });
    }
    weightOptions = {};
    keywordSearchPromise = new Promise(function(r) {
      return r();
    });
    if (args.includes) {
      if (args.includes.modifiedWeights) {
        ref = args.includes.modifiedWeights;
        for (i = 0, len = ref.length; i < len; i++) {
          modifyObj = ref[i];
          modifyObjAttrs = _.isArray(modifyObj.classAttributes) ? modifyObj.classAttributes : [modifyObj.classAttributes];
          for (j = 0, len1 = modifyObjAttrs.length; j < len1; j++) {
            attr = modifyObjAttrs[j];
            weightOptions[attr] = {};
            weightOptions[attr].weight = +modifyObj.weight;
          }
        }
      }
      fields = args.includes.inAllOf || args.includes.inAnyOf || [args.includes["in"]];
      keywords = args.includes.keywords.split(/\s/);
      keywords = _.reject(keywords, function(s) {
        return s === '';
      });
      if (args.includes.inAnyOf) {
        keywordSearchPromise = findKeywordsInAnyFields.apply(self, [fields, keywords, weightOptions]).then(function(keyNames) {
          return _.each(keyNames, function(key) {
            return sortedSetKeys.push({
              name: key
            });
          });
        });
      } else if (args.includes.inAllOf || args.includes["in"]) {
        for (k = 0, len2 = fields.length; k < len2; k++) {
          field = fields[k];
          weight = (weightOptions[field] && weightOptions[field].weight ? weightOptions[field].weight : 1);
          for (l = 0, len3 = keywords.length; l < len3; l++) {
            keyword = keywords[l];
            sortedSetKeys.push({
              name: self.name + "#" + field + "/" + keyword,
              weight: weight
            });
          }
        }
      }
    }
    whereConditionPromises = [];
    ref1 = Object.keys(args);
    for (m = 0, len4 = ref1.length; m < len4; m++) {
      option = ref1[m];
      optionValue = args[option];
      if (!self.classAttributes[option]) {
        continue;
      }
      switch (self.classAttributes[option].dataType) {
        case 'integer':
          tempIntegerKey = 'temporaryIntegerSet:' + _utilities.randomString(5);
          integerSortedSetName = self.name + '>' + option;
          minValue = '-inf';
          maxValue = '+inf';
          if (optionValue.greaterThan) {
            minValue = optionValue.greaterThan + 1;
          }
          if (optionValue.greaterThanOrEqualTo) {
            minValue = optionValue.greaterThanOrEqualTo;
          }
          if (optionValue.lessThan) {
            maxValue = optionValue.lessThan - 1;
          }
          if (optionValue.lessThanOrEqualTo) {
            maxValue = optionValue.lessThanOrEqualTo;
          }
          if (optionValue.equalTo) {
            minValue = optionValue.equalTo;
            maxValue = optionValue.equalTo;
          }
          whereConditionPromises.push(new Promise(function(resolve) {
            return createIntegerSubset.apply(self, [integerSortedSetName, tempIntegerKey, minValue, maxValue]).then(function() {
              return resolve();
            });
          }));
          sortedSetKeys.push({
            name: tempIntegerKey
          });
          sortedSetKeys.push({
            name: integerSortedSetName
          });
          break;
        case 'boolean':
          sortedSetKeys.push({
            name: self.name + "#" + option + ":" + optionValue
          });
          break;
        case 'reference':
          referenceModelName = self.classAttributes[option].referenceModelName;
          if (referenceModelName) {
            namespace = self.classAttributes[option].reverseReferenceAttribute || option;
            if (self.classAttributes[option].many) {
              if (optionValue.includesAllOf) {
                _.each(optionValue.includesAllOf, function(id) {
                  return sortedSetKeys.push({
                    name: referenceModelName + ':' + id + '#' + namespace + ':' + self.name + 'Refs'
                  });
                });
              }
              if (optionValue.includesAnyOf) {
                _.each(optionValue.includesAnyOf, function(id) {
                  return unionSortedSetKeys.push({
                    name: referenceModelName + ':' + id + '#' + namespace + ':' + self.name + 'Refs'
                  });
                });
              }
            } else {
              if (optionValue.anyOf) {
                _.each(optionValue.anyOf, function(id) {
                  return unionSortedSetKeys.push({
                    name: referenceModelName + ':' + id + '#' + namespace + ':' + self.name + 'Refs'
                  });
                });
              } else {
                sortedSetKeys.push({
                  name: referenceModelName + ':' + optionValue + '#' + namespace + ':' + self.name + 'Refs'
                });
              }
            }
          }
      }
    }
    prepareWhereConditionPromise = Promise.all(whereConditionPromises).then(function() {
      var unionPromise;
      if (_.isEmpty(unionSortedSetKeys)) {
        return keywordSearchPromise;
      } else {
        unionPromise = new Promise(function(resolve) {
          var ref2, unionKey, unionSortedSetKeyNames;
          unionSortedSetKeyNames = _.map(unionSortedSetKeys, 'name');
          unionKey = 'temporaryUnionSet:' + _utilities.randomString(24);
          return (ref2 = self.redis).zunionstore.apply(ref2, [unionKey, unionSortedSetKeys.length].concat(slice.call(unionSortedSetKeyNames), [function(err, numberofresults) {
            self.redis.expire(unionKey, 5);
            sortedSetKeys.push({
              name: unionKey
            });
            return resolve();
          }]));
        });
        return unionPromise.then(function() {
          return keywordSearchPromise;
        });
      }
    });
    return prepareWhereConditionPromise.then(function() {
      var idsKeyPromise, matchedIdsPromise;
      idsKeyPromise = new Promise(function(resolve) {
        var intersectKey, ref2, sortedSetKeyNames;
        intersectKey = 'temporaryIntersectSet:' + _utilities.randomString(24);
        sortedSetKeyNames = _.map(sortedSetKeys, 'name');
        return (ref2 = self.redis).zinterstore.apply(ref2, [intersectKey, sortedSetKeys.length].concat(slice.call(sortedSetKeyNames), [function(err, numberOfResults) {
          self.redis.expire(intersectKey, 5);
          return resolve({
            intersectKey: intersectKey,
            numberOfResults: numberOfResults
          });
        }]));
      });
      matchedIdsPromise = idsKeyPromise.then(function(resultObj) {
        var facetResults, facetsPromises, idKey, totalResults;
        idKey = resultObj.intersectKey;
        totalResults = resultObj.numberOfResults;
        facetResults = {};
        facetsPromises = [];
        _.each(args.facets, function(f) {
          facetResults[f] = [];
          return facetsPromises.push(new Promise(function(resolve) {
            return self.redis.sort(idKey, 'by', 'nosort', 'get', self.name + ':*->' + f, function(err, facetList) {
              var counts, len5, n, ref2, x;
              counts = _.countBy(facetList, function(p) {
                return p;
              });
              ref2 = Object.keys(counts);
              for (n = 0, len5 = ref2.length; n < len5; n++) {
                x = ref2[n];
                facetResults[f].push({
                  item: x,
                  count: counts[x]
                });
              }
              return resolve();
            });
          }));
        });
        return Promise.all(facetsPromises).then(function() {
          return new Promise(function(resolve) {
            return self.redis.zrevrange(idKey, start, end, function(error, ids) {
              if (args.sortDirection === 'desc') {
                ids.reverse();
              }
              self.redis.del(idKey, function() {});
              return resolve({
                ids: ids,
                totalResults: totalResults,
                facetResults: facetResults
              });
            });
          });
        });
      });
      return matchedIdsPromise.then(function(resultObject) {
        var ids, promises;
        ids = resultObject.ids;
        if (args.sortBy === 'random') {
          if (args.limit) {
            ids = _.sample(ids, args.limit);
          } else {
            ids = _.shuffle(ids);
          }
        }
        promises = _.map(ids, function(id) {
          return self.find(id);
        });
        return Promise.all(promises).then(function(resultItems) {
          var _resultObject;
          return _resultObject = {
            name: self.name,
            total: resultObject.totalResults,
            offset: start,
            facets: resultObject.facetResults,
            items: resultItems
          };
        });
      });
    });
  };

  module.exports = where;

}).call(this);