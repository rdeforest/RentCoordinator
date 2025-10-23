window.SharedUtils =
  formatCurrency: (amount) ->
    new Intl.NumberFormat 'en-US',
      style    : 'currency'
      currency : 'USD'
    .format amount

  formatDateTime: (date) ->
    date.toLocaleString [],
      month  : 'short'
      day    : 'numeric'
      hour   : '2-digit'
      minute : '2-digit'

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