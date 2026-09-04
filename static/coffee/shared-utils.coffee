window.SharedUtils =
  formatCurrency: (amount) ->
    n = Number amount
    unless Number.isFinite n
      # A non-finite currency is always a bug — usually a missing or renamed
      # server field (this is what produced the "$NaN" dashboard). Report it
      # and show a clear placeholder instead of "$NaN".
      window.SharedUtils?.reportClientError? 'non-finite-currency', value: String(amount)
      return '—'
    new Intl.NumberFormat 'en-US',
      style    : 'currency'
      currency : 'USD'
    .format n

  formatDateTime: (date) ->
    date.toLocaleString [],
      month  : 'short'
      day    : 'numeric'
      hour   : '2-digit'
      minute : '2-digit'

  formatDate: (dateStr) ->
    new Date(dateStr).toLocaleDateString 'en-US',
      year  : 'numeric'
      month : 'short'
      day   : 'numeric'

  formatMonthYear: (year, month) ->
    new Date(year, month - 1).toLocaleDateString 'en-US',
      year  : 'numeric'
      month : 'long'

  formatDuration: (seconds) ->
    hours   = Math.floor seconds / 3600
    minutes = Math.floor (seconds % 3600) / 60
    secs    = seconds % 60

    if hours > 0
      "#{hours}:#{String(minutes).padStart(2, '0')}:#{String(secs).padStart(2, '0')}"
    else
      "#{minutes}:#{String(secs).padStart(2, '0')}"

  escapeHtml: (text) ->
    div = document.createElement 'div'
    div.textContent = text
    div.innerHTML

  fetchJSON: (url, options = {}) ->
    try
      response = await fetch url, options
      data     = await response.json() if response.headers.get('content-type')?.includes 'application/json'

      if response.ok
        return { ok: true, data }
      else
        return { ok: false, error: data?.error or "Request failed: #{response.status}" }
    catch err
      return { ok: false, error: err.message }

  debounce: (func, wait) ->
    timeout = null
    ->
      context = this
      args    = arguments
      clearTimeout timeout
      timeout = setTimeout ->
        func.apply context, args
      , wait

  getLastWorker: ->
    localStorage.getItem 'lastWorker'

  saveLastWorker: (worker) ->
    localStorage.setItem 'lastWorker', worker if worker

  show: (element) ->
    element.style.display = 'block' if element

  hide: (element) ->
    element.style.display = 'none' if element

  setButtonLoading: (button, isLoading) ->
    if isLoading
      button.disabled             = true
      button.dataset.originalText = button.textContent
      button.textContent          = 'Loading...'
    else
      button.disabled    = false
      button.textContent = button.dataset.originalText if button.dataset.originalText

  # Beacon a client-side error to the server (POST /client-errors → logs).
  # Best-effort and capped per page load, so a repeating error can't flood.
  reportClientError: (kind, detail = {}) ->
    window.SharedUtils._errCount ?= 0
    return if window.SharedUtils._errCount >= 10
    window.SharedUtils._errCount += 1
    try
      body = Object.assign { kind, url: location.pathname }, detail
      fetch('/client-errors',
        method:  'POST'
        headers: 'Content-Type': 'application/json'
        body:    JSON.stringify body
      ).catch -> return   # never let the reporter throw
    catch
      return


# Catch anything that actually throws (or rejects) on the page.
window.addEventListener 'error', (e) ->
  window.SharedUtils.reportClientError 'window.onerror',
    message: e.message
    source:  e.filename
    line:    e.lineno
    col:     e.colno
    stack:   e.error?.stack

window.addEventListener 'unhandledrejection', (e) ->
  window.SharedUtils.reportClientError 'unhandledrejection',
    message: String(e.reason?.message or e.reason)
    stack:   e.reason?.stack