window.requireAuth = ->
  try
    response = await fetch '/auth/status'
    data     = await response.json()

    unless data.authenticated
      window.location.href = '/login.html'
      return false

    return true
  catch err
    console.error 'Auth check failed:', err
    window.location.href = '/login.html'
    return false


window.getCurrentUser = ->
  try
    response = await fetch '/auth/status'
    data     = await response.json()

    if data.authenticated
      return email: data.email
    else
      return null
  catch err
    console.error 'Get user failed:', err
    return null


window.logout = ->
  try
    response = await fetch '/auth/logout',
      method: 'POST'

    if response.ok
      window.location.href = '/login.html'
      return true
    else
      console.error 'Logout failed'
      return false
  catch err
    console.error 'Logout error:', err
    return false


window.addLogoutButton = (containerSelector = 'header') ->
  container = document.querySelector containerSelector
  return unless container
  return if document.getElementById 'logoutBtn'

  logoutBtn           = document.createElement 'button'
  logoutBtn.id        = 'logoutBtn'
  logoutBtn.className = 'btn btn-secondary'
  logoutBtn.textContent = 'Logout'
  logoutBtn.style.float = 'right'

  logoutBtn.addEventListener 'click', (e) ->
    e.preventDefault()
    logout() if confirm 'Are you sure you want to logout?'

  container.appendChild logoutBtn


document.addEventListener 'DOMContentLoaded', ->
  unless window.location.pathname is '/login.html'
    await requireAuth()
    addLogoutButton()
