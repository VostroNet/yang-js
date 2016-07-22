Extension  = require '../extension'

module.exports =
  new Extension 'import',
    scope:
      prefix: '1'
      'revision-date': '0..1'

    construct: ->
      @module = @lookup 'module', @tag
      unless @module?
        throw @error "unable to resolve '#{@tag}' module"

      rev = @['revision-date']?.tag
      if rev? and not (@module.match 'revision', rev)?
        throw @error "requested #{rev} not available in #{@tag}"

      # TODO: Should be handled in extension construct
      # go through extensions from imported module and update 'scope'
      # for k, v of m.extension ? {}
      #   for pkey, scope of v.resolve 'parent-scope'
      #     target = @parent.resolve 'extension', pkey
      #     target?.scope["#{@prefix.tag}:#{k}"] = scope

