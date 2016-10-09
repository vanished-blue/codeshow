_ = require('lodash')
Promise = require 'bluebird'
redis = require 'redis'

Promise.promisifyAll redis.RedisClient.prototype
Promise.promisifyAll redis.Multi.prototype

redis_client = redis.createClient 6379, 'cache'
EXPIRE_SEC = 60 * 3
TERMINAL_ONLINE_REDIS_DB = 1
SYNC_PERIOD = 1000 * 60 * 3


#specific functions about redis operation
selectRedisDB = ->
  redis_client.selectAsync TERMINAL_ONLINE_REDIS_DB
  
getOnlineClientIds = ->
  selectRedisDB()
  .then ->
    redis_client.keysAsync '*'

addOnlineClient = (keys, expire_time = EXPIRE_SEC) ->
  selectRedisDB()
  .then ->
    redis_client.setexAsync keys, expire_time, 1

getOnlineClientCounts = ->
  selectRedisDB()
  .then ->
    redis_client.dbsizeAsync()

emptyOnlineClients = ->
  selectRedisDB()
  .then ->
    redis_client.flushdbAsync()

