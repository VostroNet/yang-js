Extension  = require '../extension'

module.exports =
  new Extension 'length',
    scope:
      description: '0..1'
      'error-app-tag': '0..1'
      'error-message': '0..1'
      reference: '0..1'

