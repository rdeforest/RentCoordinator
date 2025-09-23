// static/coffee/timer.coffee

// State
var activeDescription, activeSection, activeTimer, cancelButton, currentSession, currentWorker, currentWorkerName, currentWorkerSection, descriptionTimeout, displaySessions, doneButton, escapeHtml, formatDateTime, formatDuration, getSessionSortValue, hideActiveSession, loadSessions, loadWorkerState, pauseButton, resumeButton, saveDescription, serverInterval, sessionStatus, sessions, sessionsSection, sessionsTable, showActiveSession, sortColumn, sortDirection, startButton, startNewButton, startSection, startUpdateTimer, stopUpdateTimer, updateActiveSession, updateInterval, updateTimerDisplay, workerButtons;

currentWorker = null;

currentSession = null;

updateInterval = null;

serverInterval = null;

sessions = [];

sortColumn = 'stopped';

sortDirection = 'desc';

descriptionTimeout = null;

// DOM elements
workerButtons = document.querySelectorAll('.worker-btn');

currentWorkerSection = document.querySelector('.current-worker');

currentWorkerName = document.getElementById('current-worker-name');

activeSection = document.getElementById('active-session');

startSection = document.getElementById('start-work');

sessionsSection = document.getElementById('work-sessions');

startButton = document.getElementById('start-timer');

pauseButton = document.getElementById('pause-btn');

resumeButton = document.getElementById('resume-btn');

doneButton = document.getElementById('done-btn');

cancelButton = document.getElementById('cancel-btn');

startNewButton = document.getElementById('start-new-btn');

activeTimer = document.getElementById('active-timer');

sessionStatus = document.getElementById('session-status');

activeDescription = document.getElementById('active-description');

sessionsTable = document.getElementById('sessions-tbody');

// Worker selection
workerButtons.forEach(function(btn) {
  return btn.addEventListener('click', function() {
    currentWorker = btn.dataset.worker;
    // Update UI
    workerButtons.forEach(function(b) {
      return b.classList.remove('active');
    });
    btn.classList.add('active');
    currentWorkerName.textContent = currentWorker.charAt(0).toUpperCase() + currentWorker.slice(1);
    currentWorkerSection.style.display = 'block';
    // Load current state
    return loadWorkerState();
  });
});

// Start new work
startButton.addEventListener('click', async function() {
  var err, error, response, result;
  try {
    response = (await fetch('/timer/start', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        worker: currentWorker
      })
    }));
    if (response.ok) {
      result = (await response.json());
      currentSession = result;
      showActiveSession();
      startUpdateTimer();
      return loadSessions();
    } else {
      error = (await response.json());
      return alert(error.error);
    }
  } catch (error1) {
    err = error1;
    return alert(`Error starting timer: ${err.message}`);
  }
});

// Pause work
pauseButton.addEventListener('click', async function() {
  var err, error, response;
  try {
    response = (await fetch('/timer/pause', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        worker: currentWorker
      })
    }));
    if (response.ok) {
      currentSession = (await response.json());
      updateActiveSession();
      return loadSessions();
    } else {
      error = (await response.json());
      return alert(error.error);
    }
  } catch (error1) {
    err = error1;
    return alert(`Error pausing timer: ${err.message}`);
  }
});

// Resume work
resumeButton.addEventListener('click', async function() {
  var err, error, response, result;
  try {
    response = (await fetch('/timer/resume', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        worker: currentWorker,
        session_id: currentSession != null ? currentSession.id : void 0
      })
    }));
    if (response.ok) {
      result = (await response.json());
      currentSession = result;
      updateActiveSession();
      return loadSessions();
    } else {
      error = (await response.json());
      return alert(error.error);
    }
  } catch (error1) {
    err = error1;
    return alert(`Error resuming timer: ${err.message}`);
  }
});

// Done with work
doneButton.addEventListener('click', async function() {
  var err, error, response, result;
  try {
    response = (await fetch('/timer/stop', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        worker: currentWorker,
        completed: true
      })
    }));
    if (response.ok) {
      result = (await response.json());
      if (result.event === 'completed_too_short') {
        alert("Work session was less than 1 minute and won't be saved");
      }
      currentSession = null;
      hideActiveSession();
      return loadSessions();
    } else {
      error = (await response.json());
      return alert(error.error);
    }
  } catch (error1) {
    err = error1;
    return alert(`Error stopping timer: ${err.message}`);
  }
});

// Cancel work
cancelButton.addEventListener('click', async function() {
  var err, error, response;
  if (confirm("Cancel this work session? It will be marked as cancelled.")) {
    try {
      response = (await fetch('/timer/stop', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          worker: currentWorker,
          completed: false
        })
      }));
      if (response.ok) {
        currentSession = null;
        hideActiveSession();
        return loadSessions();
      } else {
        error = (await response.json());
        return alert(error.error);
      }
    } catch (error1) {
      err = error1;
      return alert(`Error cancelling timer: ${err.message}`);
    }
  }
});

// Start new work (pauses current if any)
startNewButton.addEventListener('click', async function() {
  var err, error, response, result;
  // First pause current work if active
  if ((currentSession != null ? currentSession.status : void 0) === 'active') {
    try {
      await fetch('/timer/pause', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          worker: currentWorker
        })
      });
    } catch (error1) {
      err = error1;
      console.error("Error pausing current work:", err);
    }
  }
  try {
    // Now start new work
    response = (await fetch('/timer/start', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        worker: currentWorker
      })
    }));
    if (response.ok) {
      result = (await response.json());
      currentSession = result;
      showActiveSession();
      startUpdateTimer();
      return loadSessions();
    } else {
      error = (await response.json());
      return alert(error.error);
    }
  } catch (error1) {
    err = error1;
    return alert(`Error starting new timer: ${err.message}`);
  }
});

// Auto-save description
activeDescription.addEventListener('input', function() {
  if (descriptionTimeout) {
    clearTimeout(descriptionTimeout);
  }
  return descriptionTimeout = setTimeout(function() {
    return saveDescription();
  }, 1000); // Save after 1 second of no typing
});

saveDescription = async function() {
  var err, response;
  if (!currentSession) {
    return;
  }
  try {
    response = (await fetch('/timer/description', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        worker: currentWorker,
        description: activeDescription.value
      })
    }));
    if (response.ok) {
      return currentSession = (await response.json());
    }
  } catch (error1) {
    err = error1;
    return console.error("Error saving description:", err);
  }
};

// Load worker state
loadWorkerState = async function() {
  var err, response, status;
  if (!currentWorker) {
    return;
  }
  try {
    // Get current status
    response = (await fetch(`/timer/status?worker=${currentWorker}`));
    status = (await response.json());
    if (status.current_session) {
      currentSession = status.current_session;
      // Track when we got this data for client-side timer updates
      currentSession.last_server_time = new Date().toISOString();
      showActiveSession();
      startUpdateTimer();
    } else {
      currentSession = null;
      hideActiveSession();
    }
    // Load all sessions
    return loadSessions();
  } catch (error1) {
    err = error1;
    return console.error("Error loading worker state:", err);
  }
};

// Load sessions
loadSessions = async function() {
  var err, response;
  if (!currentWorker) {
    return;
  }
  try {
    response = (await fetch(`/timer/sessions?worker=${currentWorker}`));
    sessions = (await response.json());
    displaySessions();
    return sessionsSection.style.display = 'block';
  } catch (error1) {
    err = error1;
    return console.error("Error loading sessions:", err);
  }
};

// Display sessions
displaySessions = function() {
  var sortedSessions;
  if (!sessions) {
    return;
  }
  // Sort sessions
  sortedSessions = [...sessions].sort(function(a, b) {
    var aVal, bVal;
    if ((currentSession != null ? currentSession.id : void 0) === a.id) {
      // Current session always on top
      return -1;
    }
    if ((currentSession != null ? currentSession.id : void 0) === b.id) {
      return 1;
    }
    // Then by sort column
    aVal = getSessionSortValue(a, sortColumn);
    bVal = getSessionSortValue(b, sortColumn);
    if (sortDirection === 'asc') {
      if (aVal < bVal) {
        return -1;
      } else if (aVal > bVal) {
        return 1;
      } else {
        return 0;
      }
    } else {
      if (aVal > bVal) {
        return -1;
      } else if (aVal < bVal) {
        return 1;
      } else {
        return 0;
      }
    }
  });
  // Build table HTML
  if (sortedSessions.length === 0) {
    sessionsTable.innerHTML = '<tr><td colspan="6" style="text-align: center;">No work sessions yet</td></tr>';
    return;
  }
  return sessionsTable.innerHTML = sortedSessions.map(function(session) {
    var actions, durationStr, isCurrent, ref, rowClass, startStr, startTime, stopStr;
    isCurrent = (currentSession != null ? currentSession.id : void 0) === session.id;
    rowClass = isCurrent ? 'session-row current' : 'session-row';
    // Format times
    startTime = new Date(session.created_at);
    startStr = formatDateTime(startTime);
    // Stopped time (last event or current time if active)
    stopStr = (ref = session.status) === 'completed' || ref === 'cancelled' ? formatDateTime(new Date(session.updated_at)) : session.status === 'paused' ? "Paused" : "Running";
    // Duration
    durationStr = session.duration_formatted || formatDuration(session.total_duration);
    // Actions
    actions = [];
    if (session.status === 'paused' && !isCurrent) {
      actions.push(`<button class="btn btn-primary btn-sm" onclick="resumeSession('${session.id}')">Resume</button>`);
    }
    return `<tr class="${rowClass}">
  <td><span class="status-badge ${session.status}">${session.status}</span></td>
  <td>${escapeHtml(session.description || '(no description)')}</td>
  <td>${startStr}</td>
  <td>${stopStr}</td>
  <td>${durationStr}</td>
  <td class="session-actions">${actions.join(' ')}</td>
</tr>`;
  }).join('');
};

// Get sort value for session
getSessionSortValue = function(session, column) {
  var ref;
  switch (column) {
    case 'status':
      return session.status;
    case 'description':
      return session.description || '';
    case 'started':
      return session.created_at;
    case 'stopped':
      if ((ref = session.status) === 'completed' || ref === 'cancelled') {
        return session.updated_at;
      } else {
        return '9999-12-31'; // Active/paused sessions sort last
      }
      break;
    case 'duration':
      return session.total_duration;
    default:
      return session.updated_at;
  }
};

// Resume a different session
window.resumeSession = async function(sessionId) {
  var err, error, response, result;
  try {
    response = (await fetch('/timer/resume', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        worker: currentWorker,
        session_id: sessionId
      })
    }));
    if (response.ok) {
      result = (await response.json());
      currentSession = result;
      showActiveSession();
      startUpdateTimer();
      return loadSessions();
    } else {
      error = (await response.json());
      return alert(error.error);
    }
  } catch (error1) {
    err = error1;
    return alert(`Error resuming session: ${err.message}`);
  }
};

// Show active session UI
showActiveSession = function() {
  if (!currentSession) {
    return;
  }
  activeSection.style.display = 'block';
  startSection.style.display = 'none';
  // Don't overwrite description if user is typing
  if (document.activeElement !== activeDescription) {
    activeDescription.value = currentSession.description || '';
  }
  return updateActiveSession();
};

// Hide active session UI
hideActiveSession = function() {
  activeSection.style.display = 'none';
  startSection.style.display = 'block';
  return stopUpdateTimer();
};

// Update active session display
updateActiveSession = function() {
  if (!currentSession) {
    return;
  }
  // Update status
  sessionStatus.textContent = currentSession.status;
  sessionStatus.className = `session-status ${currentSession.status}`;
  // Update buttons
  if (currentSession.status === 'active') {
    pauseButton.style.display = 'inline-block';
    resumeButton.style.display = 'none';
  } else {
    pauseButton.style.display = 'none';
    resumeButton.style.display = 'inline-block';
  }
  // Update timer display
  return updateTimerDisplay();
};

// Update timer display
updateTimerDisplay = function() {
  var duration, events;
  if (!currentSession) {
    return;
  }
  if (currentSession.status === 'active') {
    // Calculate current duration
    events = []; // Would need to fetch events or track locally
    duration = currentSession.total_duration || 0;
    // Add time since last update
    // This is approximate - server has authoritative time
    return activeTimer.textContent = formatDuration(Math.round(duration));
  } else {
    return activeTimer.textContent = formatDuration(currentSession.total_duration || 0);
  }
};

// Start update timer
startUpdateTimer = function() {
  stopUpdateTimer();
  // Update display immediately
  updateTimerDisplay();
  // Update display every second (for smooth timer)
  updateInterval = setInterval(function() {
    return updateTimerDisplay();
  }, 1000);
  // Reload from server every 5 seconds (to stay in sync)
  return serverInterval = setInterval(function() {
    return loadWorkerState();
  }, 5000);
};

// Stop update timer
stopUpdateTimer = function() {
  if (updateInterval) {
    clearInterval(updateInterval);
  }
  if (serverInterval) {
    clearInterval(serverInterval);
  }
  updateInterval = null;
  return serverInterval = null;
};

// Format duration
formatDuration = function(seconds) {
  var hours, minutes, secs;
  hours = Math.floor(seconds / 3600);
  minutes = Math.floor((seconds % 3600) / 60);
  secs = seconds % 60;
  return `${hours}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
};

// Format date/time
formatDateTime = function(date) {
  return date.toLocaleString([], {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
};

// Escape HTML
escapeHtml = function(text) {
  var div;
  div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
};

// Sorting
document.querySelectorAll('.sortable').forEach(function(th) {
  return th.addEventListener('click', function() {
    var column;
    column = th.dataset.sort;
    // Update sort direction
    if (column === sortColumn) {
      sortDirection = sortDirection === 'asc' ? 'desc' : 'asc';
    } else {
      sortColumn = column;
      sortDirection = 'desc';
    }
    // Update UI
    document.querySelectorAll('.sortable').forEach(function(h) {
      return h.classList.remove('asc', 'desc');
    });
    th.classList.add(sortDirection);
    // Re-display
    return displaySessions();
  });
});

// Check for active session on page load
window.addEventListener('load', function() {
  var lastWorker, workerBtn;
  // Auto-select worker if returning to page
  lastWorker = localStorage.getItem('lastWorker');
  if (lastWorker) {
    workerBtn = document.querySelector(`[data-worker=\"${lastWorker}\"]`);
    return workerBtn != null ? workerBtn.click() : void 0;
  }
});

// Save selected worker
window.addEventListener('beforeunload', function() {
  if (currentWorker) {
    return localStorage.setItem('lastWorker', currentWorker);
  }
});
