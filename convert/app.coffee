os = require 'os'
URL = require 'url'
path = require 'path'
querystring = require 'querystring'

_ = require 'lodash'
md5 = require 'md5'
request = require 'request'
Promise = require 'bluebird'
express = require 'express'

request = Promise.promisify request
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'
app = express()
app.set 'port', process.env.PORT || 3000

TEN_MINUTES = 10 * 60 * 1000
USER = 'virtual.user'
PASS = md5('virtual.pass')


check_params = () ->
  if process.argv.length isnt 3
    console.log "The length of params is not correct(usage: ./convert.sh https://ip_address:port/version/token)."
    process.exit(-1)


check_params()

SERVER_URL = URL.parse process.argv[2]
SERVER_PROTOCOL = SERVER_URL.protocol
SERVER_HOSTNAME = SERVER_URL.hostname
SERVER_PORT = SERVER_URL.port
SERVER_PATHNAME_PART = SERVER_URL.pathname
TOKEN = SERVER_PATHNAME_PART.match(/\/([^\/]+)\/?$/)[1]


get_ip = () ->
  for k, eth of os.networkInterfaces()
    for v in eth
      if v.family is 'IPv4' and v.internal is false
        return v.address

  throw Error 'Can not acquire the ip address!'


fetch = (url, statusCode_middleware) ->
  request url
  .then (res) ->
    statusCode_middleware(res)


is_server_alive = () ->
  url = URL.format {
    protocol: SERVER_PROTOCOL
    hostname: SERVER_HOSTNAME
    port: SERVER_PORT
    pathname: path.join SERVER_PATHNAME_PART, 'virus'
  }

  request url
  .then (res) ->
    if res.statusCode is 200
      console.log "Converting successfully, please use http://#{get_ip()}:3000 to invoke the service!"
      return res.statusCode

    return Promise.reject(res.statusCode)


virus_handler = (req, res, statusCode_middleware) ->
  query = filter_query req.query
  if validate_params query, req.path
    fetch convert_url(req.url, query), statusCode_middleware
    .then (result) ->
      if result.statusCode is 200
        res.json convert_data JSON.parse result.body
      else
        res.sendStatus result.statusCode
    .catch () ->
      res.sendStatus 401
  else
    res.sendStatus 401


virus_list_handler = (req, res) ->
  virus_handler req, res, (res) ->
    if res.statusCode is 200
      return {
        statusCode: 200
        body: res.body
      }
    else
      return {
        statusCode: 401
      }


virus_item_handler = (req, res) ->
  virus_handler req, res, (res) ->
    if res.statusCode is 200
      return {
        statusCode: 200
        body: res.body
      }
    else if res.statusCode is 404
      return {
        statusCode: 404
      }
    else
      return {
        statusCode: 401
      }


app.get '/', (req, res) ->
  res.send("root")


start_server = () ->
  is_server_alive()
  .then () ->
    app.get '/v1/virus', virus_list_handler
    app.get '/v1/virus/:id', virus_item_handler
  .catch () ->
    console.log 'Service started failed, please try again!'


app.listen app.get('port')
.on 'listening', () ->
  console.log 'Tool started succeeded!'
  start_server()
.on 'error', (err) ->
  if err.code is 'EADDRINUSE'
    console.log 'port conflicts, please make sure 3000 port is not occupied by other service!'
  process.exit(-1)


filter_query = (params) ->
  _.pick(params, ['date', 'sign', 'from', 'size'])


validate_params = (params, path) ->
  validate_date(params.date) && validate_sign(params.sign, params.date, path)


validate_date = (date) ->
  if not date
    return false

  date = +date

  if typeof(date) isnt 'number'
    return false

  current = +new Date

  if current - date > TEN_MINUTES
    return false

  return true


validate_sign = (sign, date, path) ->
  real_sign = USER + ':' + md5(date + path + USER + PASS)
  return sign is real_sign


convert_url = (url, query) ->
  pathname = URL.parse(url).pathname
  pathname = pathname.replace /^(\/[^\/]+\/)/, '$1' + TOKEN + '/'

  o = {}
  o.from = query.from if query.from?
  o.size = query.size if query.size?

  qs = querystring.stringify o

  URL.format {
    protocol: SERVER_PROTOCOL
    hostname: SERVER_HOSTNAME
    port: SERVER_PORT
    pathname: pathname
    search: '?' + qs if qs
  }


convert_data = (json) ->
  OPERATION_MAP =
    "REMOVED": "BLOCKING"
    "UNHANDLED": "ALARM"
    "TRUSTED": "ALARM"
    "CLEANED": "BLOCKING"

  convert = (item) ->
    "id": item.id
    "name": item.virus_name
    "description": ""
    "service_type": "WEB"
    "protocol": "HTTP"
    "upload": false
    "download": false
    "operation": OPERATION_MAP[item.operation]

  virus =  json.virus

  if virus.constructor is Array
    res =
      "virus": _.map virus, convert, null
  else if virus.constructor is Object
    res =
      "virus": convert virus

  return res

