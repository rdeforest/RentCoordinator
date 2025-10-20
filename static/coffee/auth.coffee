# static/coffee/auth.coffee
# Shared authentication utilities for frontend

# Check if user is authenticated, redirect to login if not
window.requireAuth = ->
  try
    response = await fetch('/auth/status')
    data = await response.json()

    if not data.authenticated
      window.location.href = '/login.html'
      return false

    return true
  catch err
    console.error 'Auth check failed:', err
    window.location.href = '/login.html'
    return false


# Get current user info
window.getCurrentUser = ->
  try
    response = await fetch('/auth/status')
    data = await response.json()

    if data.authenticated
      return email: data.email
    else
      return null
  catch err
    console.error 'Get user failed:', err
    return null


# Logout current user
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


# Add logout button to page
window.addLogoutButton = (containerSelector = 'header') ->
  container = document.querySelector(containerSelector)
  if not container
    return

  # Check if logout button already exists
  if document.getElementById('logoutBtn')
    return

  logoutBtn = document.createElement('button')
  logoutBtn.id = 'logoutBtn'
  logoutBtn.className = 'btn btn-secondary'
  logoutBtn.textContent = 'Logout'
  logoutBtn.style.float = 'right'
  logoutBtn.addEventListener 'click', (e) ->
    e.preventDefault()
    if confirm('Are you sure you want to logout?')
      logout()

  container.appendChild(logoutBtn)


# Auto-initialize auth check on page load
document.addEventListener 'DOMContentLoaded', ->
  # Only run on pages that are not login page
  if window.location.pathname isnt '/login.html'
    await requireAuth()
    addLogoutButton()
