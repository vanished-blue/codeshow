{ pipeP } = R

processMonitor = angular.module 'processMonitor', ['common']

processMonitor.service 'service', [->
  PORT = 3078
  ORIGIN = location.origin.replace(/(:\d+)?$/, ":#{PORT}")

  afterFetch = pipeP(
    (res) -> if res.status in [200...300] then Promise.resolve res else Promise.reject Error res.statusText
    (res) -> res.json()
  )

  get = (url) ->
    fetch(url).then afterFetch

  post = (url, formData) ->
    fetch(url, { method: 'POST', body: formData }).then afterFetch

  update = (what) -> get("#{ORIGIN}/update/#{what}")

  info = (what) ->　get("#{ORIGIN}/info/#{what}")

  download = (what) ->
    a = document.createElement('a')
    a.href = "#{ORIGIN}/download/#{what}"
    a.click()

  save = (what, args...) -> post("#{ORIGIN}/save/#{what}", args...)

  malice =
    info: -> info 'malice'
    save: (formData) -> save 'malice', formData

  logs =
    update: -> update 'logs'
    download: ->　download 'logs'
    info: -> info 'logs'

  samples =
    update: -> update 'samples'
    download: -> download 'samples'
    info: -> info 'samples'

  service =
    malice: malice
    logs: logs
    samples: samples
]

processMonitor.directive 'validateNoSpace', ->
  require: 'ngModel'
  scope: {}
  link: (scope, elm, attrs, ctrl) ->
    scope.checkIp = ->
      value = ctrl.$viewValue
      ctrl.$setValidity 'noSpace', not value or !/\s/.test(value)

      if (scope.$root.$$phase isnt '$apply' and scope.$root.$$phase isnt '$digest')
        scope.$apply()

    elm.bind 'input', ->
      scope.checkIp()

processMonitor.controller 'ctrl', [
  '$scope', 'service', '$localStorage', ($scope, service, $localStorage) ->

    i18n = $localStorage.i18n

    log = console.log.bind(console)

    LS =
      getResponse: (who, res) ->
        if res.ERROR_MSG?
          @notExists who
        else if res.json?
          @info who, res.json

      info: (who, json) ->
        _.extend $scope[who],
          downloadable: json.exists
          filename: json.filename
          filesize: json.filesize.val + ' ' + json.filesize.unit
          lastUpdateTime: moment(json.lastUpdateDate).format('YYYY.MM.DD HH:mm:ss')
        $scope.$apply()

      notExists: (who) ->
        _.extend $scope[who],
          downloadable: false
        $scope.$apply()

    getLogsResponse= LS.getResponse.bind(LS, 'logs')
    getSamplesResponse = LS.getResponse.bind(LS, 'samples')

    getMaliceResponse = (data) ->
      _.extend($scope, data)
      $scope.$apply()

    $scope.malice =
      info: -> service.malice.info().then(getMaliceResponse).catch(log)
      save: ->
        formData = new FormData angular.element('form[name="maliceForm"]').get(0)
        service.malice.save(formData)
        .then (bool) ->
          if bool
            alertify.success "#{i18n.save_success}"
          else
            alertify.error "#{i18n.save_unsuccess}"
        .catch(log)

    $scope.logs =
      filename: ''
      downloadable: false
      update: -> service.logs.update().then(getLogsResponse).catch(log)
      download: service.logs.download
      info: -> service.logs.info().then(getLogsResponse).catch(log)

    $scope.samples =
      filename: ''
      downloadable: false
      update: -> service.samples.update().then(getSamplesResponse).catch(log)
      download: service.samples.download
      info: -> service.samples.info().then(getSamplesResponse).catch(log)

    $scope.info = ->
      $scope.malice.info()
      $scope.logs.info()
      $scope.samples.info()
]

