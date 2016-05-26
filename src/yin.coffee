#
# Yin - specification for YANG language extensions
#

# external dependencies
yaml    = require 'js-yaml'
coffee  = require 'coffee-script'

# local dependencies
Expression = require './expression'

YIN_SCHEMA = yaml.Schema.create [

  new yaml.Type '!coffee',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> coffee.eval? data

  new yaml.Type '!coffee/function',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> coffee.eval? data
    predicate: (obj) -> obj instanceof Function
    represent: (obj) -> obj.toString()

  new yaml.Type '!yang/extension',
    kind: 'mapping'
    resolve:   (data) -> typeof data is 'object'
    construct: (data) -> new Expression null, 'extension', undefined, data

]

# represents YIN specification
class Yin extends Expression

  constructor: (schema) ->
    try
      schema = yaml.load schema, schema: YIN_SCHEMA if typeof schema is 'string'
    catch e
      console.warn e
      throw @error "invalid YIN schema syntax detected", e
    unless schema instanceof Object
      throw @error "must pass in proper YIN schema to parse"

    v.arg = k for k, v of schema when v instanceof Expression
    super null, 'yin-specification', undefined, schema

  resolve: (kw, arg) ->
    return unless kw is 'extension'
    return @[arg]

exports = module.exports = Yin
exports.load = ->
exports.dump = ->
