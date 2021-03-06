// Generated by CoffeeScript 1.9.3
(function() {
  var Promise, _, redisFind, removeIndexedSearchableString, sendAttributesForSaving, update,
    slice = [].slice;

  Promise = require('promise');

  _ = require('lodash');

  sendAttributesForSaving = require('./_redisObjectSave');

  redisFind = require('./find');

  removeIndexedSearchableString = function(attr, words, id) {
    var char, i, indexPromiseFn, indexPromises, j, len, len1, ref, word, wordSegment, wordSegmentKey;
    indexPromises = [];
    ref = words.split(/\s/);
    for (i = 0, len = ref.length; i < len; i++) {
      word = ref[i];
      word = word.toLowerCase();
      wordSegment = '';
      for (j = 0, len1 = word.length; j < len1; j++) {
        char = word[j];
        wordSegment += char;
        wordSegmentKey = this.className + '#' + attr + '/' + wordSegment;
        indexPromiseFn = (function(_this) {
          return function(wordSegmentKey, id) {
            return new Promise(function(resolve) {
              return _this.redis.zrem(wordSegmentKey, id, function(res) {
                return resolve();
              });
            });
          };
        })(this);
        indexPromises.push(indexPromiseFn(wordSegmentKey, id));
      }
    }
    return Promise.all(indexPromises);
  };

  update = function(id, updateFields, skipValidation, skipAfterSave) {
    var callbackPromises, getOriginalObjPromise, multi, self;
    self = this;
    callbackPromises = [];
    multi = self.redis.multi();
    getOriginalObjPromise = redisFind.apply(self, [id]).then(function(originalObj) {
      if (!originalObj) {
        return Promise.reject(new Error("Not Found"));
      }
      return originalObj;
    });
    return getOriginalObjPromise.then(function(originalObj) {
      var attr, i, intersectingValues, len, multiPromise, namespace, newValue, obj, orderedSetName, originalIds, originalValue, ref, remove, removeValue, sortedSetName, updateFieldsDiff;
      updateFieldsDiff = {
        id: id
      };
      ref = Object.keys(updateFields);
      for (i = 0, len = ref.length; i < len; i++) {
        attr = ref[i];
        remove = false;
        if (attr.match(/^remove_/)) {
          remove = true;
          removeValue = updateFields[attr];
          attr = attr.replace(/^remove_/, '');
        }
        orderedSetName = self.className + '>' + attr;
        originalValue = originalObj[attr];
        newValue = updateFields[attr];
        updateFieldsDiff[attr] = newValue;
        if (!(newValue === void 0 || newValue === null) && (originalValue && newValue !== originalValue) || remove) {
          obj = self.classAttributes[attr];
          if (!obj) {
            return;
          }
          switch (obj.dataType) {
            case 'integer':
            case 'float':
              sortedSetName = self.className + '>' + attr;
              multi.zrem(sortedSetName, id);
              break;
            case 'text':
              if (obj.searchable) {
                callbackPromises.push(removeIndexedSearchableString.apply(self, [attr, originalValue, id]));
              }
              break;
            case 'string':
              if (obj.sortable) {
                multi.zrem(orderedSetName, id);
              }
              if (obj.searchable) {
                callbackPromises.push(removeIndexedSearchableString.apply(self, [attr, originalValue, id]));
              }
              if (obj.identifiable || obj.url) {
                multi.del(self.className + "#" + attr + ":" + originalValue);
              }
              break;
            case 'reference':
              namespace = obj.reverseReferenceAttribute || attr;
              if (obj.many) {
                if (remove && removeValue) {
                  multi.srem.apply(multi, [self.className + ":" + id + "#" + attr + ':' + obj.referenceModelName + 'Refs'].concat(slice.call(removeValue)));
                  removeValue.forEach(function(vid) {
                    return multi.srem(obj.referenceModelName + ":" + vid + "#" + namespace + ':' + self.className + 'Refs', id);
                  });
                } else {
                  originalIds = _.map(originalValue, 'id');
                  intersectingValues = _.intersection(originalIds, newValue);
                  if (!_.isEmpty(intersectingValues)) {
                    updateFieldsDiff[attr] = intersectingValues;
                  }
                }
              } else {
                multi.srem(obj.referenceModelName + ":" + originalValue.id + "#" + namespace + ':' + self.className + 'Refs', id);
              }
              break;
            case 'boolean':
              multi.zrem(self.className + "#" + attr + ":" + originalValue, id);
          }
        }
      }
      multiPromise = new Promise(function(resolve, reject) {
        return multi.exec(function() {
          return resolve();
        });
      });
      return multiPromise.then(function() {
        return sendAttributesForSaving.apply(self, [updateFieldsDiff, skipValidation]).then(function(writtenObj) {
          return Promise.all(callbackPromises).then(function() {
            return redisFind.apply(self, [writtenObj.id]).then(function(found) {
              var afterSavePromise;
              afterSavePromise = (found.afterSave != null) && !skipAfterSave ? found.afterSave() : null;
              return Promise.all([afterSavePromise]).then(function() {
                return found;
              });
            });
          });
        });
      });
    });
  };

  module.exports = update;

}).call(this);
