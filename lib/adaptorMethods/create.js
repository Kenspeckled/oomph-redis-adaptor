// Generated by CoffeeScript 1.9.3
(function() {
  var Promise, create, redisFind, sendAttributesForSaving;

  Promise = require('promise');

  sendAttributesForSaving = require('./_redisObjectSave');

  redisFind = require('./find');

  create = function(props, skipValidation, skipAfterSave) {
    var self;
    self = this;
    return sendAttributesForSaving.apply(self, [props, skipValidation]).then(function(writtenObject) {
      return redisFind.apply(self, [writtenObject.id]).then(function(found) {
        var afterCreatePromise, afterSavePromise;
        afterCreatePromise = found.afterCreate != null ? found.afterCreate() : null;
        afterSavePromise = (found.afterSave != null) && !skipAfterSave ? found.afterSave() : null;
        return Promise.all([afterSavePromise, afterCreatePromise]).then(function() {
          return found;
        });
      });
    });
  };

  module.exports = create;

}).call(this);
