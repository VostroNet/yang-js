Extension = require '../extension'
Yang      = require '../yang'
Property  = require '../property'

module.exports =
  new Extension 'action',
    argument: 'name'
    data: true
    scope:
      description:  '0..1'
      grouping:     '0..n'
      'if-feature': '0..n'
      input:        '0..1'
      output:       '0..1'
      reference:    '0..1'
      status:       '0..1'
      typedef:      '0..n'

    construct: (data={}) ->
      return data unless data instanceof Object
      func = data[@tag] ? @binding ? (a,b,c) => throw @error "handler function undefined"
      unless func instanceof Function
        # should try to dynamically compile 'string' into a Function
        throw @error "expected a function but got a '#{typeof func}'"
      unless func.length is 3
        throw @error "cannot define without function (input, resolve, reject)"
      func = expr.eval func for expr in @elements
      func.async = true
      (new Property @tag, func, schema: this).update data

    compose: (data, opts={}) ->
      return unless data instanceof Function
      return unless Object.keys(data).length is 0
      return unless Object.keys(data.prototype).length is 0

      # TODO: should inspect function body and infer 'input'
      (new Yang @tag, opts.key, this).bind data
