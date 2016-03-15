### yang-compiler
#
# The **yang-compiler** class provides support for basic set of
# YANG schema modeling language by using the built-in *extension* syntax
# to define additional schema language constructs.

# The compiler only supports bare minium set of YANG statements and
# should be used only to generate a new compiler such as [yangforge](./yangforge.coffee)
# which implements the version 1.0 of the YANG language specifications.
#
###
console.debug ?= console.log if process.env.yang_debug?

synth    = require 'data-synth'
yaml     = require 'js-yaml'
coffee   = require 'coffee-script'
parser   = require 'yang-parser'
fs       = require 'fs'
path     = require 'path'
traverse = require 'traverse'

YANG_SPEC_SCHEMA = yaml.Schema.create [

  new yaml.Type '!require',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) ->
      console.debug? "processing !require using: #{data}"
      try require data
      catch then require (path.resolve data)

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

  new yaml.Type '!yang',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) =>
      console.debug? "processing !yang using: #{data}"
      (new Compiler).parse data
]

YANG_V1_LANG = [
  fs.readFileSync (path.resolve __dirname, '../yang-v1-spec.yaml'), 'utf-8'
  fs.readFileSync (path.resolve __dirname, '../yang-v1-lang.yang'), 'utf-8'
]

class Yang extends synth.Meta
  constructor: (map) -> @attach k, v for k, v of map

Dictionary = require './dictionary'

class Compiler extends Dictionary
  constructor: ->
    super
    unless (@resolve 'extension')?
      @define 'extension',
        specification:
          argument: 'name',
          construct: (arg, params) -> params
        module:
          argument: 'name'

  #### PRIMARY API METHODS ####
  # produces new compiled object instances generated from provided
  # schema(s)
  #
  # accepts: variable arguments of YANG/YAML schema/specification string(s)
  # returns: new Yang object containing schema compiled object(s)
  load: (schemas...) -> (-> @use schemas...; new Yang @map ).call (new Compiler this)

  # TODO: converts passed in JS object back into YANG schema (if possible)
  #
  # accepts: JS object
  # returns: YANG schema text
  dump: (obj=@map) ->
    opts.space ?= 2
    o = obj.constructor.extract?()
    delete o.bindings
    return module: o

  #### SECONDARY API METHODS ####

  # process schema/spec input(s) and defines results inside current
  # Compiler
  #
  # Example = yang
  #  .use('module example { leaf test { type string; } }')
  #  .resolve('example')
  #
  # When a given YANG schema 'include' or 'import' other schemas, you
  # want to first call .use in order to make those schema definitions
  # available for processing the target schema.
  #
  # accepts: variable arguments of YANG/YAML schema/specification string(s)
  # returns: current Compiler instance (with updated definitions)
  use: (schemas...) -> (schemas.forEach (x) => super @compile x); return this

  error: (msg, context) ->
    res = super
    res.name = 'CompilerError'
    return res

  normalize = (obj) -> ([ obj.prf, obj.kw ].filter (e) -> e? and !!e).join ':'

  ###
  # The `parse` function performs recursive parsing of passed in statement
  # and sub-statements and usually invoked in the context of the
  # originating `compile` function below.  It expects the `statement` as
  # an Object containing prf, kw, arg, and any substmts as an array.  It
  # currently does NOT perform semantic validations but rather simply
  # ensures syntax correctness and building the JS object tree structure.
  ###
  parse: (input) ->
    try
      input = (parser.parse input) if typeof input is 'string'
    catch e
      # try and see if it is YAML input string?
      try
        return yaml.load input, schema: YANG_SPEC_SCHEMA
      catch e
        # wasn't proper YAML either...
      e.offset = 30 unless e.offset > 30
      offender = input.slice e.offset-30, e.offset+30
      offender = offender.replace /\s\s+/g, ' '
      throw @error "invalid YANG/YAML syntax detected", offender

    unless input instanceof Object
      throw @error "must pass in proper input to parse"

    params =
      (@parse stmt for stmt in input.substmts)
      .filter (e) -> e?
      .reduce ((a, b) -> synth.copy a, b, true), {}
    params = null unless Object.keys(params).length > 0

    synth.objectify "#{normalize input}", switch
      when not params? then input.arg
      when not !!input.arg then params
      else "#{input.arg}": params

  extractKeys = (x) -> if x instanceof Object then (Object.keys x) else [x].filter (e) -> e? and !!e

  ###
  # The `preprocess` function is the intermediary method of the compiler
  # which prepares a parsed output to be ready for the `compile`
  # operation.  It deals with any `include` and `extension` statements
  # found in the parsed output in order to prepare the context for the
  # `compile` operation to proceed smoothly.
  ###
  preprocess: (schema, map, scope) ->
    schema = (@parse schema) if typeof schema is 'string'
    unless schema instanceof Object
      throw @error "must pass in proper 'schema' to preprocess"

    map   ?= new Dictionary this
    scope ?= map.resolve 'extension'

    # Here we go through each of the keys of the schema object and
    # validate the extension keywords and resolve these keywords
    # if preprocessors are associated with these extension keywords.
    for key, val of schema
      [ prf..., kw ] = key.split ':'
      unless kw of scope
        throw @error "invalid '#{kw}' extension found during preprocess operation", schema

      continue if key is 'specification'

      if key in [ 'module', 'submodule' ]
        map.name = (extractKeys val)[0]
        # TODO: what if map was supplied as an argument?
        map.use (@resolve map.name, undefined, warn: false)

      if key is 'extension'
        extensions = (extractKeys val)
        for name in extensions
          extension = if val instanceof Object then val[name] else {}
          for ext of extension when ext isnt 'argument' # TODO - should qualify better
            delete extension[ext]
          map.define 'extension', name, extension
        delete schema.extension
        console.debug? "[Compiler:preprocess:#{map.name}] found #{extensions.length} new extension(s)"
        continue

      ext = map.resolve 'extension', key
      unless (ext instanceof Object)
        throw @error "encountered unresolved extension '#{key}'", schema
      constraint = scope[kw]

      unless ext.argument?
        # TODO - should also validate constraint for input/output
        @preprocess val, map, ext
        ext.preprocess?.call? map, key, val, schema
      else
        args = (extractKeys val)
        valid = switch constraint
          when '0..1','1' then args.length <= 1
          when '1..n' then args.length > 1
          else true
        unless valid
          throw @error "constraint violation for '#{key}' (#{args.length} != #{constraint})", schema
        for arg in args
          params = if val instanceof Object then val[arg]
          argument = switch
            when typeof arg is 'string' and arg.length > 50
              ((arg.replace /\s\s+/g, ' ').slice 0, 50) + '...'
            else arg
          console.debug? "[Compiler:preprocess:#{map.name}] #{key} #{argument} " + if params? then "{ #{Object.keys params} }" else ''
          params ?= {}
          @preprocess params, map, ext
          try
            ext.preprocess?.call? map, arg, params, schema
          catch e
            console.error e
            throw @error "failed to preprocess '#{key} #{arg}'", args

    return schema: schema, map: map

  ###
  # The `compile` function is the primary method of the compiler which
  # takes in YANG schema input and produces JS output representing the
  # input schema as meta data hierarchy.

  # It accepts following forms of input
  # * YANG schema text string
  # * YAML schema text string (including specification)

  # The compilation process can compile any partials or complete
  # representation of the schema and recursively compiles the data tree to
  # return synthesized object hierarchy.
  ###
  compile: (schema, map) ->
    { schema, map } = @preprocess schema unless map?
    unless schema instanceof Object
      throw @error "must pass in proper 'schema' to compile"
    unless map instanceof Dictionary
      throw @error "unable to access Dictionary map to compile passed in schema"

    output = {}
    for key, val of schema
      continue if key is 'extension'

      ext = map.resolve 'extension', key
      unless (ext instanceof Object)
        throw @error "encountered unknown extension '#{key}'", schema

      # here we short-circuit if there is no 'construct' for this extension
      continue unless ext.construct instanceof Function

      unless ext.argument?
        console.debug? "[Compiler:compile:#{map.name}] #{key} " + if val instanceof Object then "{ #{Object.keys val} }" else val
        children = @compile val, map
        output[key] = ext.construct.call map, key, val, children, output, ext
        delete output[key] unless output[key]?
      else
        for arg in (extractKeys val)
          params = if val instanceof Object then val[arg]
          console.debug? "[Compiler:compile:#{map.name}] #{key} #{arg} " + if params? then "{ #{Object.keys params} }" else ''
          params ?= {}
          children = @compile params, map unless key is 'specification'
          try
            output[arg] = ext.construct.call map, arg, params, children, output, ext
            delete output[arg] unless output[arg]?
          catch e
            console.error e
            throw @error "failed to compile '#{key} #{arg}'", schema

    return output

#
# declare exports
#
exports = module.exports = (new Compiler).use YANG_V1_LANG...
exports.Compiler = Compiler
exports.Yang = Yang
