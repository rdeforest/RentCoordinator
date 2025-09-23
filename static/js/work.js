// static/coffee/work.coffee
var addWorkBtn, allWorkLogs, applyFilters, cancelWorkBtn, deleteModal, escapeHtml, filteredLogs, formatCurrency, loadWorkLogs, updateDisplay, updateStats, workForm, workModal;

allWorkLogs = [];

filteredLogs = [];

// Load work logs on page load
window.addEventListener('load', function() {
  loadWorkLogs();
  // Set default date to today
  return document.getElementById('work-date').value = new Date().toISOString().split('T')[0];
});

// Load and display work logs
loadWorkLogs = async function() {
  var err, response;
  try {
    response = (await fetch('/work-logs?limit=1000'));
    allWorkLogs = (await response.json());
    return applyFilters();
  } catch (error1) {
    err = error1;
    console.error('Error loading work logs:', err);
    return document.getElementById('work-table-body').innerHTML = '<tr><td colspan="5" style="text-align: center;">Error loading work logs</td></tr>';
  }
};

// Apply filters and update display
applyFilters = function() {
  var monthFilter, workerFilter;
  workerFilter = document.getElementById('worker-filter').value;
  monthFilter = document.getElementById('month-filter').value;
  filteredLogs = allWorkLogs.filter(function(log) {
    var logDate, logMonth;
    if (workerFilter && log.worker !== workerFilter) {
      // Worker filter
      return false;
    }
    // Month filter
    if (monthFilter) {
      logDate = new Date(log.start_time);
      logMonth = `${logDate.getFullYear()}-${String(logDate.getMonth() + 1).padStart(2, '0')}`;
      if (logMonth !== monthFilter) {
        return false;
      }
    }
    return true;
  });
  updateDisplay();
  return updateStats();
};

// Update the work logs table
updateDisplay = function() {
  var tbody;
  tbody = document.getElementById('work-table-body');
  if (filteredLogs.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" style="text-align: center;">No work entries found</td></tr>';
    return;
  }
  return tbody.innerHTML = filteredLogs.map(function(log) {
    var date, hours, startTime, time;
    startTime = new Date(log.start_time);
    date = startTime.toLocaleDateString();
    time = startTime.toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit'
    });
    hours = (log.duration / 60).toFixed(2);
    return `<tr>
  <td>${date} ${time}</td>
  <td>${log.worker}</td>
  <td>${hours} hours</td>
  <td>${escapeHtml(log.description)}</td>
  <td class="actions">
    <button class="btn btn-secondary" onclick="editWork('${log.id}')">Edit</button>
    <button class="btn btn-danger" onclick="deleteWork('${log.id}')">Delete</button>
  </td>
</tr>`;
  }).join('');
};

// Update statistics
updateStats = function() {
  var totalCredit, totalEntries, totalHours, totalMinutes;
  totalEntries = filteredLogs.length;
  totalMinutes = filteredLogs.reduce((function(sum, log) {
    return sum + log.duration;
  }), 0);
  totalHours = totalMinutes / 60;
  totalCredit = filteredLogs.filter(function(log) {
    return log.billable && log.worker === 'lyndzie';
  }).reduce((function(sum, log) {
    return sum + (log.duration / 60 * 50);
  }), 0);
  document.getElementById('total-entries').textContent = totalEntries;
  document.getElementById('total-hours').textContent = totalHours.toFixed(2);
  return document.getElementById('total-credit').textContent = formatCurrency(totalCredit);
};

// Filter event listeners
document.getElementById('worker-filter').addEventListener('change', applyFilters);

document.getElementById('month-filter').addEventListener('change', applyFilters);

document.getElementById('clear-filters').addEventListener('click', function() {
  document.getElementById('worker-filter').value = '';
  document.getElementById('month-filter').value = '';
  return applyFilters();
});

// Modal handling
workModal = document.getElementById('work-modal');

deleteModal = document.getElementById('delete-modal');

addWorkBtn = document.getElementById('add-work-btn');

cancelWorkBtn = document.getElementById('cancel-work');

workForm = document.getElementById('work-form');

// Add work button
addWorkBtn.addEventListener('click', function() {
  document.getElementById('modal-title').textContent = 'Add Work Entry';
  document.getElementById('work-form').reset();
  document.getElementById('work-id').value = '';
  document.getElementById('work-date').value = new Date().toISOString().split('T')[0];
  document.getElementById('work-billable').checked = true;
  return workModal.style.display = 'block';
});

// Cancel button
cancelWorkBtn.addEventListener('click', function() {
  return workModal.style.display = 'none';
});

// Edit work function
window.editWork = function(id) {
  var endDate, log, startDate;
  log = allWorkLogs.find(function(l) {
    return l.id === id;
  });
  if (!log) {
    return;
  }
  document.getElementById('modal-title').textContent = 'Edit Work Entry';
  document.getElementById('work-id').value = log.id;
  document.getElementById('work-worker').value = log.worker;
  startDate = new Date(log.start_time);
  document.getElementById('work-date').value = startDate.toISOString().split('T')[0];
  document.getElementById('work-start-time').value = startDate.toTimeString().slice(0, 5);
  endDate = new Date(log.end_time);
  document.getElementById('work-end-time').value = endDate.toTimeString().slice(0, 5);
  document.getElementById('work-description').value = log.description;
  document.getElementById('work-billable').checked = log.billable !== false;
  return workModal.style.display = 'block';
};

// Delete work function
window.deleteWork = function(id) {
  document.getElementById('delete-work-id').value = id;
  return deleteModal.style.display = 'block';
};

// Work form submission
workForm.addEventListener('submit', async function(e) {
  var billable, data, date, description, duration, endDateTime, endTime, err, error, id, response, startDateTime, startTime, worker;
  e.preventDefault();
  id = document.getElementById('work-id').value;
  worker = document.getElementById('work-worker').value;
  date = document.getElementById('work-date').value;
  startTime = document.getElementById('work-start-time').value;
  endTime = document.getElementById('work-end-time').value;
  description = document.getElementById('work-description').value;
  billable = document.getElementById('work-billable').checked;
  // Calculate start and end timestamps
  startDateTime = new Date(`${date}T${startTime}`);
  endDateTime = new Date(`${date}T${endTime}`);
  // Handle end time on next day
  if (endDateTime < startDateTime) {
    endDateTime.setDate(endDateTime.getDate() + 1);
  }
  duration = Math.round((endDateTime - startDateTime) / 1000 / 60); // minutes
  data = {
    worker: worker,
    start_time: startDateTime.toISOString(),
    end_time: endDateTime.toISOString(),
    duration: duration,
    description: description.trim(),
    billable: billable
  };
  try {
    if (id) {
      // Update existing
      response = (await fetch(`/work-logs/${id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
      }));
    } else {
      // Create new
      response = (await fetch('/work-logs', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
      }));
    }
    if (response.ok) {
      workModal.style.display = 'none';
      return loadWorkLogs(); // Reload data
    } else {
      error = (await response.json());
      return alert(`Error saving work entry: ${error.error}`);
    }
  } catch (error1) {
    err = error1;
    return alert(`Error saving work entry: ${err.message}`);
  }
});

// Delete confirmation
document.getElementById('confirm-delete').addEventListener('click', async function() {
  var err, error, id, response;
  id = document.getElementById('delete-work-id').value;
  try {
    response = (await fetch(`/work-logs/${id}`, {
      method: 'DELETE'
    }));
    if (response.ok) {
      deleteModal.style.display = 'none';
      return loadWorkLogs(); // Reload data
    } else {
      error = (await response.json());
      return alert(`Error deleting work entry: ${error.error}`);
    }
  } catch (error1) {
    err = error1;
    return alert(`Error deleting work entry: ${err.message}`);
  }
});

document.getElementById('cancel-delete').addEventListener('click', function() {
  return deleteModal.style.display = 'none';
});

// Helper functions
escapeHtml = function(text) {
  var div;
  div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
};

formatCurrency = function(amount) {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD'
  }).format(amount);
};
