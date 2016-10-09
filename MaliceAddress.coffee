winston = require('../common/log').logFactory.getLogger('MaliceAddress')
TaskGenerator = require "./taskGenerator"
Promise = require 'bluebird'
fs = require 'fs-extra-promise'
{ exec } = require 'child-process-promise'
path = require 'path'
JsonDB = require 'node-json-db'
_ = require 'underscore'
{ extend, partial, compact, union, keys } = _
mkdir = require 'mkdirp'
multer = require 'multer'
fileMD5 = require('md5-file-promise')()
MD5 = require('md5')
models = require '../es/models'
moment = require 'moment'
convert = require 'convert-units'
cors = require 'cors'

ROOT_DIR = '/data/suspicionFiles/'

LOGS =
  TAR_NAME: 'logs.tar'
  RELATIVE_DIR: 'logs'

extend LOGS,
  TAR_PATH: path.resolve ROOT_DIR, LOGS.TAR_NAME
  ABSOLUTE_DIR: path.resolve ROOT_DIR, LOGS.RELATIVE_DIR
  
SAMPLES =
  TAR_NAME: 'samples.tar'
  RELATIVE_DIR: 'samples'
 
extend SAMPLES,
  TAR_PATH: path.resolve ROOT_DIR, SAMPLES.TAR_NAME
  ABSOLUTE_DIR: path.resolve ROOT_DIR, SAMPLES.RELATIVE_DIR

express = require 'express'
app = express()

PORT = 3078

ACCESS_CONTROL_ALLOW_PORT = 3000
corsOptions =
  origin: new RegExp ":#{ACCESS_CONTROL_ALLOW_PORT}$"

middleware = {}

class FileReadError extends Error
  constructor: (@message = '') ->
    this.name = @constructor.name

exports.init = () ->

  md5Db = new JsonDB(ROOT_DIR + 'samples.json', true, true)

  ipListDb = new JsonDB(ROOT_DIR + 'ipList.json', true, true)

  storage = multer.diskStorage(
    destination: (req, file, cb) ->
      cb null, '/tmp'
      return
    filename: (req, file, cb) ->
      cb null, req.headers.filename
      return
  )

  upload = multer(storage: storage)

  getLatestUpdatedDate = (path) ->
    fs.statAsync(path)
    .then (res) -> res.mtime

  getFilesize = (path) ->
    fs.statAsync(path)
    .then (res) -> convert(res.size).from('b').toBest()

  transformFilename = (name, path) ->
    getLatestUpdatedDate(path)
    .then (date) -> moment(date).format('YYYYMMDDHHmmss')
    .then (time) -> name.replace /(\.tar)$/, time + '$1'

  catchError = (err, res) ->
    winston.error err
    res.send 500

  app.use cors corsOptions

  app.get '/info/malice', (req, res) ->
    ipListDb.reload()
    ipList = ipListDb.getData('client_ip_list').ip_list ? []
    clientList = ipListDb.getData('client_ip_list').client_list ? []
    ipListStr = ipList.join(';')
    clientListStr = clientList.join(";")
    res.json
      maliceIpArray: ipListStr
      endpointIpArray: clientListStr

  app.post '/save/malice', upload.single(), (req, res) ->
    ipListStr = req.body.maliceIpArray
    clientListStr = req.body.endpointIpArray
    ipList = splitStr(ipListStr)
    clientList = splitStr(clientListStr)
    taskGenerator(ipList, clientList)
    .then (data) ->
      res.send true
    .catch (err) ->
      res.send false

  app.get /^\/(update|download|info)\/(logs|samples)$/, (req, res, next) ->
    who = req.params[1]

    if who is 'logs'
      req.CONSTANT = LOGS
    else if who is 'samples'
      req.CONSTANT = SAMPLES

    next()

  middleware.logsAndSamplesInfo = (req, res) ->
    { TAR_NAME, TAR_PATH } = req.CONSTANT

    fs.existsAsync(TAR_PATH)
    .then (exists) ->
      json = exists: exists
      if not exists
        Promise.reject new FileReadError('FILE_NOT_EXISTS')
      else json
    .then (json) ->
      Promise.join(
        transformFilename(TAR_NAME, TAR_PATH)
        getLatestUpdatedDate(TAR_PATH)
        getFilesize(TAR_PATH)
      )
      .spread (filename, lastUpdateDate, filesize) ->
        extend json, { filename, lastUpdateDate, filesize }
    .then (json) ->
      res.json json: json
    .catch FileReadError, (err) ->
      res.json ERROR_MSG: err.message
    .catch partial(catchError, _, res)

  app.get /^\/info\/(logs|samples)$/, middleware.logsAndSamplesInfo

  app.get /^\/update\/(logs|samples)$/, (req, res, next) ->
    { TAR_NAME, RELATIVE_DIR } = req.CONSTANT

    exec("cd #{ROOT_DIR} && tar cvf #{TAR_NAME} #{RELATIVE_DIR}")
    .then -> next()
    .catch partial(catchError, _, res)
  , middleware.logsAndSamplesInfo

  app.get /^\/download\/(logs|samples)$/, (req, res) ->
    { TAR_NAME, TAR_PATH } = req.CONSTANT

    transformFilename(TAR_NAME, TAR_PATH)
    .then (filename) ->
      res.download TAR_PATH, filename
    .catch partial(catchError, _, res)

  app.listen PORT
