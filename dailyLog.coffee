winston = require('../../../common/log').logFactory.getLogger('dailyLog')
moment = require 'moment'
{ flatten } = require 'underscore'
{ CronJob } = require 'cron'
es_client = require '../../es_client'
{ getCurrentIndex } = require '../../common'
{ copyIndex, putAlias } = require './indexAction'
{ getLatestLogsName, distinctLog, filterUnHandledLog } = require '../../globalNetworkLog'
{ LOGS_ALIAS } = require '../../../constant/log'

INDEXER = "#{__dirname}/logs-indexer.js"
ERROR =
  INDEX_EXISTS: 'index exists'

getUnHandled = (res) ->
  res = filterUnHandledLog(res)
  aggs = res.aggregations

  ids = aggs.byClientId.buckets.reduce (acc, o) ->
    acc.push o.virus.buckets.reduce (acc, o) ->
      hit = o.top_virus_hits.hits.hits[0]
      acc.push hit._id
      return acc
    , []

    acc.push o.vul.buckets.reduce (acc, o) ->
      hit = o.top_vul_hits.hits.hits[0]
      acc.push hit._id
      return acc
    , []

    acc.push o.exception.title.buckets.reduce (acc, o) ->
      hit = o.top_exception_hits.hits.hits[0]
      acc.push hit._id
      return acc
    , []

    return acc
  , []

  flatten ids

deleteHandled = (index, ids) ->
  es_client.deleteByQuery
    index: index
    body:
      query:
        filtered:
          filter:
            not:
              terms:
                _id: ids

keepUnHandled = (index) ->
  distinctLog(index) #获取去重后的未处理+已处理log
  .then getUnHandled
  .then (ids) ->
    deleteHandled index, ids

createTodayLogs = (from, to) ->
  if from
    if moment(to).diff(moment(from), 'days') > 0
      copyIndex
        from: from
        to: to
        indexer: INDEXER
        alias: LOGS_ALIAS
      .then ->
        keepUnHandled to
    else
      return ERROR.INDEX_EXISTS
  else
    es_client.indices.create
      index: to
    .then ->
      putAlias to, LOGS_ALIAS

createLog = ->
  getLatestLogsName()
  .then (index) ->
    createTodayLogs(index, getCurrentIndex())
  .then (res) ->
    if res isnt ERROR.INDEX_EXISTS
      winston.info 'created latest log'
  .catch (err) ->
    winston.error 'creating latest log failed, err=', err

scheduleJob = ->
  new CronJob
    cronTime: '0 0 0 * * *',
    onTick: createLog
    start: true

dailyLog = ->
  createLog()
  scheduleJob()

module.exports = dailyLog
