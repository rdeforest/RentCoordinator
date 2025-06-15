# static/coffee/shared-utils.coffee

# Shared utility functions for all pages

window.SharedUtils =
  # Format currency
  formatCurrency: (amount) ->
    new Intl.NumberFormat('en-US',
      style: 'currency'
      currency: 'USD'
    ).format amount

  # Format date/time
  formatDateTime: (date) ->
    date.toLocaleString [],
      month: 'short'
      day: 'numeric'
      hour: '2-digit'
      minute: '2-digit'

  # Format duration from seconds
  formatDuration: (seconds) ->
    hours = Math.floor(seconds / 3600)
    minutes = Math.floor((seconds % 3600) / 60)
    secs = seconds % 60

    if hours > 0
      "#{hours}:#{String(minutes).padStart(2, '0')}:#{String(secs).padStart(2, '0')}"
    else
      "#{minutes}:#{String(secs).padStart(2, '0')}"

  # Escape HTML to prevent XSS
  escapeHtml: (text) ->
    div = document.createElement 'div'
    div.textContent = text
    div.innerHTML

  # Make async fetch with standard error handling
  fetchJSON: (url, options = {}) ->
    try
      response = await fetch url, options
      data = await response.json() if response.headers.get('content-type')?.includes('application/json')

      if response.ok
        return { ok: true, data }
      else
        return { ok: false, error: data?.error or "Request failed: #{response.status}" }
    catch err
      return { ok: false, error: err.message }

  # Debounce function calls
  debounce: (func, wait) ->
    timeout = null
    ->
      context = this
      args = arguments
      clearTimeout timeout
      timeout = setTimeout ->
        func.apply context, args
      , wait

  # Get worker name from localStorage
  getLastWorker: ->
    localStorage.getItem 'lastWorker'

  # Save worker name to localStorage
  saveLastWorker: (worker) ->
    localStorage.setItem 'lastWorker', worker if worker

  # Show/hide elements
  show: (element) ->
    element.style.display = 'block' if element

  hide: (element) ->
    element.style.display = 'none' if element

  # Add loading state to button
  setButtonLoading: (button, isLoading) ->
    if isLoading
      button.disabled = true
      button.dataset.originalText = button.textContent
      button.textContent = 'Loading...'
    else
      button.disabled = false
      button.textContent = button.dataset.originalText if button.dataset.originalText