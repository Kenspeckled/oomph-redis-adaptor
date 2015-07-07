gulp = require 'gulp'
jasmine = require 'gulp-jasmine'

gulp.task 'jasmine', ->
  gulp.src 'spec/**/*.coffee'
    .pipe jasmine()

gulp.task 'test', ->
  gulp.src 'spec/**/*.coffee'
    .pipe jasmine()
  gulp.watch 'spec/**/*.coffee', ['jasmine']

gulp.task 'default', ['test']
