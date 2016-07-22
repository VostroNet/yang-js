Extension  = require '../extension'

module.exports =
  new Extension 'max-elements',
    resolve: -> @tag = (Number) @tag unless @tag is 'unbounded'
    predicate: (data) -> @tag is 'unbounded' or data not instanceof Array or data.length <= @tag
