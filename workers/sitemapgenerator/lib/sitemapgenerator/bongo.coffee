nodePath    = require 'path'
Bongo       = require 'bongo'
Broker      = require 'broker'
{argv}      = require 'optimist'
{extend}    = require 'underscore'

KONFIG = require('koding-config-manager').load("main.#{argv.c}")
{mongo, mq, projectRoot, sitemapWorker} = KONFIG

mongo = "mongodb://#{mongo}?auto_reconnect"

mqOptions = extend {}, mq
mqOptions.login = sitemapWorker.login if sitemapWorker?.login?

module.exports = new Bongo {
  mongo
  root: projectRoot
  models: [
    'workers/social/lib/social/models'
  ]
  mq: new Broker mqOptions
  resourceName: sitemapWorker.queueName
}
