# static/coffee/issues.coffee — bug 62 consistency issues page.

SEVERITY_ORDER = { error: 0, warning: 1 }

openListEl         = document.getElementById 'open-list'
acknowledgedListEl = document.getElementById 'acknowledged-list'
lastRunEl          = document.getElementById 'last-run'
runChecksBtn       = document.getElementById 'run-checks-btn'

escapeHtml = (text) -> window.SharedUtils.escapeHtml String(text ? '')


renderMonth = (finding) ->
  return '' unless finding.month
  "<div class=\"finding-month\">Month: <a href=\"/rent\">#{escapeHtml finding.month}</a></div>"


renderDetail = (finding) ->
  return '' unless finding.detail and Object.keys(finding.detail).length > 0
  "<pre class=\"finding-detail\">#{escapeHtml JSON.stringify finding.detail, null, 2}</pre>"


renderOpenCard = (finding) ->
  """
  <div class="finding-card severity-#{finding.severity}" data-key="#{escapeHtml finding.key}">
    <div class="finding-header">
      <span class="finding-kind">#{escapeHtml finding.kind} · #{escapeHtml finding.severity}</span>
    </div>
    <p class="finding-message">#{escapeHtml finding.message}</p>
    #{renderMonth finding}
    #{renderDetail finding}
    <div class="finding-ack">
      <textarea placeholder="Note (required to acknowledge)"></textarea>
      <button class="btn btn-secondary ack-btn">Acknowledge</button>
    </div>
  </div>
  """


renderAcknowledgedCard = (finding) ->
  ack = finding.acknowledgment
  """
  <div class="finding-card acknowledged" data-key="#{escapeHtml finding.key}">
    <div class="finding-header">
      <span class="finding-kind">#{escapeHtml finding.kind} · #{escapeHtml finding.severity}</span>
    </div>
    <p class="finding-message">#{escapeHtml finding.message}</p>
    #{renderMonth finding}
    <p class="finding-ack-note">#{escapeHtml ack.note}</p>
    <div class="finding-ack-meta">
      Acknowledged by #{escapeHtml ack.acknowledged_by or 'unknown'} on
      #{window.SharedUtils.formatDate ack.acknowledged_at}
    </div>
    <button class="btn btn-secondary unack-btn">Un-acknowledge</button>
  </div>
  """


# An acknowledgment the latest run didn't report: all that's stored is the
# finding's key and the note.
renderUnreportedCard = (ack) ->
  """
  <div class="finding-card acknowledged" data-key="#{escapeHtml ack.finding_key}">
    <div class="finding-header">
      <span class="finding-kind">not in the latest run</span>
    </div>
    <p class="finding-message"><code>#{escapeHtml ack.finding_key}</code></p>
    <p class="finding-ack-note">#{escapeHtml ack.note}</p>
    <div class="finding-ack-meta">
      Acknowledged by #{escapeHtml ack.acknowledged_by or 'unknown'} on
      #{window.SharedUtils.formatDate ack.acknowledged_at}
    </div>
    <button class="btn btn-secondary unack-btn">Un-acknowledge</button>
  </div>
  """


sortFindings = (findings) ->
  findings.slice().sort (a, b) -> (SEVERITY_ORDER[a.severity] ? 9) - (SEVERITY_ORDER[b.severity] ? 9)


render = (payload) ->
  { ran_at, findings, unreported_acknowledgments } = payload

  lastRunEl.textContent = if ran_at
    "Last run: #{window.SharedUtils.formatDateTime new Date ran_at}"
  else
    'Last run: never'

  open          = sortFindings (f for f in findings when not f.acknowledgment)
  acknowledged  = sortFindings (f for f in findings when f.acknowledgment)

  openListEl.innerHTML = if open.length > 0
    (renderOpenCard f for f in open).join ''
  else
    '<p class="no-findings">No open findings.</p>'

  cards = (renderAcknowledgedCard f for f in acknowledged)
    .concat (renderUnreportedCard a for a in unreported_acknowledgments ? [])
  acknowledgedListEl.innerHTML = if cards.length > 0
    cards.join ''
  else
    '<p class="no-findings">Nothing acknowledged.</p>'


loadIssues = ->
  { ok, data, error } = await window.SharedUtils.fetchJSON '/admin/consistency'
  unless ok
    openListEl.innerHTML = "<p class=\"no-findings\">Failed to load: #{escapeHtml error}</p>"
    return
  render data


acknowledgeFinding = (key, note) ->
  { ok, error } = await window.SharedUtils.fetchJSON '/admin/consistency/ack',
    method:  'POST'
    headers: 'Content-Type': 'application/json'
    body:    JSON.stringify { key, note }
  unless ok
    alert "Could not acknowledge: #{error}"
    return
  await loadIssues()


unacknowledgeFinding = (key) ->
  { ok, error } = await window.SharedUtils.fetchJSON "/admin/consistency/ack/#{encodeURIComponent key}",
    method: 'DELETE'
  unless ok
    alert "Could not un-acknowledge: #{error}"
    return
  await loadIssues()


openListEl.addEventListener 'click', (e) ->
  return unless e.target.classList.contains 'ack-btn'
  card = e.target.closest '.finding-card'
  note = card.querySelector('textarea').value.trim()
  unless note
    alert 'A note is required to acknowledge a finding.'
    return
  acknowledgeFinding card.dataset.key, note


acknowledgedListEl.addEventListener 'click', (e) ->
  return unless e.target.classList.contains 'unack-btn'
  card = e.target.closest '.finding-card'
  unacknowledgeFinding card.dataset.key


runChecksBtn.addEventListener 'click', ->
  window.SharedUtils.setButtonLoading runChecksBtn, true
  { ok, data, error } = await window.SharedUtils.fetchJSON '/admin/consistency/run', method: 'POST'
  window.SharedUtils.setButtonLoading runChecksBtn, false
  unless ok
    alert "Run failed: #{error}"
    return
  render data


window.addEventListener 'load', loadIssues
