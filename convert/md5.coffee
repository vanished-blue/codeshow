md5 = require 'md5'

USER = 'virtual.user'
PASS = md5('virtual.pass')

create_sign = (date, path) ->
  real_sign = USER + ':' + md5(date + path + USER + PASS)
  console.log date, real_sign


create_sign +new Date, '/v1/virus/AVMwDqpaw-suNZA1rhwm'