// static/coffee/rent.coffee

// State
var addEventBtn, allEvents, applyFiltersBtn, autoRecalculateAndReload, cancelDeleteBtn, cancelEventBtn, cancelPaymentBtn, clearFiltersBtn, confirmDeleteBtn, confirmDeleteModal, currentFilters, currentMonth, currentYear, deleteEventDetails, escapeHtml, eventFilters, eventForm, eventModal, eventModalTitle, eventSubmitBtn, eventToDelete, eventsTable, formatCurrency, formatDate, formatEventType, formatMonthYear, getPaymentStatus, loadAllPeriods, loadCurrentMonth, loadEvents, loadRentSummary, now, paymentForm, paymentModal, populateFilterYears, recordPaymentBtn, renderEventsTable, showError, showSuccess, showingDeleted, toggleDeletedBtn, toggleFiltersBtn;

now = new Date();

currentYear = now.getFullYear();

currentMonth = now.getMonth() + 1;

currentFilters = {};

allEvents = [];

eventToDelete = null;

showingDeleted = false;

// DOM elements
eventModal = document.getElementById('event-modal');

eventForm = document.getElementById('event-form');

addEventBtn = document.getElementById('add-event-btn');

cancelEventBtn = document.getElementById('cancel-event');

eventSubmitBtn = document.getElementById('event-submit');

eventModalTitle = document.getElementById('event-modal-title');

confirmDeleteModal = document.getElementById('confirm-delete-modal');

confirmDeleteBtn = document.getElementById('confirm-delete-btn');

cancelDeleteBtn = document.getElementById('cancel-delete-btn');

deleteEventDetails = document.getElementById('delete-event-details');

toggleFiltersBtn = document.getElementById('toggle-filters-btn');

toggleDeletedBtn = document.getElementById('toggle-deleted-btn');

eventFilters = document.getElementById('event-filters');

applyFiltersBtn = document.getElementById('apply-filters-btn');

clearFiltersBtn = document.getElementById('clear-filters-btn');

eventsTable = document.getElementById('events-tbody');

paymentModal = document.getElementById('payment-modal');

recordPaymentBtn = document.getElementById('record-payment-btn');

cancelPaymentBtn = document.getElementById('cancel-payment');

paymentForm = document.getElementById('payment-form');

// Load data on page load
window.addEventListener('load', function() {
  loadRentSummary();
  loadCurrentMonth();
  loadAllPeriods();
  loadEvents();
  return populateFilterYears();
});

// Load rent summary
loadRentSummary = async function() {
  var err, response, summary;
  try {
    response = (await fetch('/rent/summary'));
    summary = (await response.json());
    document.getElementById('outstanding-balance').textContent = formatCurrency(summary.outstanding_balance);
    document.getElementById('total-credits').textContent = formatCurrency(summary.total_discount_applied);
    document.getElementById('total-paid').textContent = formatCurrency(summary.total_amount_paid);
    return document.getElementById('months-tracked').textContent = summary.total_periods;
  } catch (error1) {
    err = error1;
    console.error('Error loading rent summary:', err);
    return showError('Failed to load rent summary');
  }
};

// Load current month details
loadCurrentMonth = async function() {
  var err, outstanding, payOnlineBtn, period, response;
  try {
    response = (await fetch(`/rent/period/${currentYear}/${currentMonth}`));
    period = (await response.json());
    document.getElementById('current-month-title').textContent = formatMonthYear(currentYear, currentMonth);
    document.getElementById('hours-worked').textContent = period.hours_worked.toFixed(2);
    document.getElementById('hours-previous').textContent = (period.hours_from_previous || 0).toFixed(2);
    document.getElementById('hours-applied').textContent = Math.min(period.hours_worked + (period.hours_from_previous || 0), 8).toFixed(2);
    document.getElementById('credit-applied').textContent = formatCurrency(period.discount_applied);
    document.getElementById('amount-due').textContent = formatCurrency(period.amount_due);
    document.getElementById('amount-paid').textContent = formatCurrency(period.amount_paid || 0);
    outstanding = period.amount_due - (period.amount_paid || 0);
    document.getElementById('outstanding-balance-current').textContent = formatCurrency(outstanding);
    // Show "Pay Rent Online" button if there's an outstanding balance
    payOnlineBtn = document.getElementById('pay-rent-online-btn');
    if (outstanding > 0) {
      payOnlineBtn.style.display = 'inline-block';
      payOnlineBtn.onclick = function() {
        return window.location.href = `/payment?year=${currentYear}&month=${currentMonth}`;
      };
    } else {
      payOnlineBtn.style.display = 'none';
    }
    return document.querySelector('.current-month').style.display = 'block';
  } catch (error1) {
    err = error1;
    console.error('Error loading current month:', err);
    return showError('Failed to load current month data');
  }
};

// Load all periods
loadAllPeriods = async function() {
  var err, periods, response, tbody;
  try {
    response = (await fetch('/rent/periods'));
    periods = (await response.json());
    tbody = document.getElementById('periods-table');
    if (periods.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">No rent periods found</td></tr>';
      return;
    }
    return tbody.innerHTML = periods.map(function(period) {
      var status, statusClass;
      status = getPaymentStatus(period);
      statusClass = status.toLowerCase();
      return `<tr>
  <td>${formatMonthYear(period.year, period.month)}</td>
  <td>${period.hours_worked.toFixed(2)}</td>
  <td>${formatCurrency(period.discount_applied)}</td>
  <td>${formatCurrency(period.amount_due)}</td>
  <td>${formatCurrency(period.amount_paid || 0)}</td>
  <td class="${statusClass}">${status}</td>
</tr>`;
    }).join('');
  } catch (error1) {
    err = error1;
    console.error('Error loading periods:', err);
    return showError('Failed to load rent periods');
  }
};

// Load rent events
loadEvents = async function(filters = {}) {
  var err, events, queryParams, response, url;
  try {
    queryParams = new URLSearchParams();
    if (filters.year) {
      queryParams.append('year', filters.year);
    }
    if (filters.month) {
      queryParams.append('month', filters.month);
    }
    if (showingDeleted) {
      queryParams.append('includeDeleted', 'true');
    }
    url = '/rent/events';
    if (queryParams.toString()) {
      url += '?' + queryParams.toString();
    }
    response = (await fetch(url));
    events = (await response.json());
    // Filter out malformed events first
    events = events.filter(function(event) {
      return (event.type != null) && (event.date != null) && (event.year != null) && (event.month != null) && (event.amount != null) && (event.description != null) && (event.id != null);
    });
    // Apply client-side filters
    if (filters.type) {
      events = events.filter(function(event) {
        return event.type === filters.type;
      });
    }
    allEvents = events;
    return renderEventsTable(events);
  } catch (error1) {
    err = error1;
    console.error('Error loading events:', err);
    return showError('Failed to load rent events');
  }
};

// Render events table
renderEventsTable = function(events) {
  var tbody, validEvents;
  tbody = eventsTable;
  if (events.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">No events found</td></tr>';
    return;
  }
  // Filter out malformed events and render valid ones
  validEvents = events.filter(function(event) {
    // Check that all required fields are present
    return (event.type != null) && (event.date != null) && (event.year != null) && (event.month != null) && (event.amount != null) && (event.description != null) && (event.id != null);
  });
  if (validEvents.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">No valid events found</td></tr>';
    return;
  }
  return tbody.innerHTML = validEvents.map(function(event) {
    var actions, amountStr, dateStr, isDeleted, periodStr, rowClass, typeClass;
    dateStr = formatDate(event.date);
    periodStr = formatMonthYear(event.year, event.month);
    amountStr = formatCurrency(event.amount);
    typeClass = event.type.replace('_', '-');
    isDeleted = event.deleted;
    rowClass = isDeleted ? 'deleted-row' : '';
    actions = isDeleted ? `<button class="btn btn-small btn-success" onclick="undeleteEvent('${event.id}')">Undelete</button>
<button class="btn btn-small" onclick="viewAuditLog('${event.id}')">Audit Log</button>` : `<button class="btn btn-small" onclick="editEvent('${event.id}')">Edit</button>
<button class="btn btn-small btn-danger" onclick="deleteEvent('${event.id}')">Delete</button>`;
    return `<tr class="${rowClass}">
  <td>${dateStr}</td>
  <td class="event-type ${typeClass}">${formatEventType(event.type)}${isDeleted ? ' (DELETED)' : ''}</td>
  <td>${periodStr}</td>
  <td class="${event.amount >= 0 ? 'positive' : 'negative'}">${amountStr}</td>
  <td>${escapeHtml(event.description)}</td>
  <td class="actions">${actions}</td>
</tr>`;
  }).join('');
};

// Populate filter years from available data
populateFilterYears = function() {
  var yearSelect, years;
  currentYear = new Date().getFullYear();
  years = [currentYear - 2, currentYear - 1, currentYear, currentYear + 1];
  yearSelect = document.getElementById('filter-year');
  return yearSelect.innerHTML = '<option value="">All Years</option>' + years.map(function(year) {
    return `<option value=\"${year}\">${year}</option>`;
  }).join('');
};

// Event Management Functions
window.editEvent = function(eventId) {
  var event;
  event = allEvents.find(function(e) {
    return e.id === eventId;
  });
  if (!event) {
    showError('Event not found');
    return;
  }
  // Populate form
  document.getElementById('event-id').value = event.id;
  document.getElementById('event-type').value = event.type;
  document.getElementById('event-date').value = event.date.split('T')[0];
  document.getElementById('event-year').value = event.year;
  document.getElementById('event-month').value = event.month;
  document.getElementById('event-amount').value = event.amount;
  document.getElementById('event-description').value = event.description;
  document.getElementById('event-notes').value = event.notes || '';
  // Update modal
  eventModalTitle.textContent = 'Edit Rent Event';
  eventSubmitBtn.textContent = 'Update Event';
  return eventModal.style.display = 'block';
};

window.deleteEvent = function(eventId) {
  var event;
  event = allEvents.find(function(e) {
    return e.id === eventId;
  });
  if (!event) {
    showError('Event not found');
    return;
  }
  eventToDelete = event;
  // Show event details in delete modal
  deleteEventDetails.innerHTML = `<p><strong>Date:</strong> ${formatDate(event.date)}</p>
<p><strong>Type:</strong> ${formatEventType(event.type)}</p>
<p><strong>Period:</strong> ${formatMonthYear(event.year, event.month)}</p>
<p><strong>Amount:</strong> ${formatCurrency(event.amount)}</p>
<p><strong>Description:</strong> ${escapeHtml(event.description)}</p>`;
  return confirmDeleteModal.style.display = 'block';
};

window.undeleteEvent = async function(eventId) {
  var err, error, response;
  try {
    response = (await fetch(`/rent/events/${eventId}/undelete`, {
      method: 'POST'
    }));
    if (response.ok) {
      return autoRecalculateAndReload();
    } else {
      error = (await response.json());
      return showError(`Failed to undelete event: ${error.error}`);
    }
  } catch (error1) {
    err = error1;
    return showError(`Error undeleting event: ${err.message}`);
  }
};

window.viewAuditLog = async function(eventId) {
  var err, logContent, logs, response;
  try {
    response = (await fetch(`/rent/audit-logs?entity_type=rent_event&entity_id=${eventId}`));
    logs = (await response.json());
    if (logs.length === 0) {
      alert('No audit log entries found for this event');
      return;
    }
    // Format audit log for display
    logContent = logs.map(function(log) {
      return `Action: ${log.action}
User: ${log.user}
Time: ${formatDate(log.timestamp)}
---`;
    }).join('\n');
    return alert(`Audit Log for Event:\n\n${logContent}`);
  } catch (error1) {
    err = error1;
    return showError(`Error loading audit log: ${err.message}`);
  }
};

// Event Listeners

// Add/Edit Event Modal
addEventBtn.addEventListener('click', function() {
  // Clear form
  eventForm.reset();
  document.getElementById('event-id').value = '';
  
  // Set defaults
  document.getElementById('event-date').value = new Date().toISOString().split('T')[0];
  document.getElementById('event-year').value = currentYear;
  document.getElementById('event-month').value = currentMonth;
  // Update modal
  eventModalTitle.textContent = 'Add Rent Event';
  eventSubmitBtn.textContent = 'Add Event';
  return eventModal.style.display = 'block';
});

cancelEventBtn.addEventListener('click', function() {
  return eventModal.style.display = 'none';
});

// Event Form Submit
eventForm.addEventListener('submit', async function(e) {
  var data, err, error, eventId, isEdit, response;
  e.preventDefault();
  eventId = document.getElementById('event-id').value;
  isEdit = eventId !== '';
  data = {
    type: document.getElementById('event-type').value,
    date: document.getElementById('event-date').value,
    year: parseInt(document.getElementById('event-year').value),
    month: parseInt(document.getElementById('event-month').value),
    amount: parseFloat(document.getElementById('event-amount').value),
    description: document.getElementById('event-description').value,
    notes: document.getElementById('event-notes').value
  };
  try {
    if (isEdit) {
      // Update existing event
      response = (await fetch(`/rent/events/${eventId}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
      }));
    } else {
      // Create new event
      response = (await fetch('/rent/events', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
      }));
    }
    if (response.ok) {
      eventModal.style.display = 'none';
      return autoRecalculateAndReload();
    } else {
      error = (await response.json());
      return showError(`Failed to ${isEdit ? 'update' : 'add'} event: ${error.error}`);
    }
  } catch (error1) {
    err = error1;
    return showError(`Error ${isEdit ? 'updating' : 'adding'} event: ${err.message}`);
  }
});

// Delete Confirmation
confirmDeleteBtn.addEventListener('click', async function() {
  var err, error, response;
  if (!eventToDelete) {
    return;
  }
  try {
    response = (await fetch(`/rent/events/${eventToDelete.id}`, {
      method: 'DELETE'
    }));
    if (response.ok) {
      confirmDeleteModal.style.display = 'none';
      eventToDelete = null;
      return autoRecalculateAndReload();
    } else {
      error = (await response.json());
      return showError(`Failed to delete event: ${error.error}`);
    }
  } catch (error1) {
    err = error1;
    return showError(`Error deleting event: ${err.message}`);
  }
});

cancelDeleteBtn.addEventListener('click', function() {
  confirmDeleteModal.style.display = 'none';
  return eventToDelete = null;
});

// Filter Handling
toggleFiltersBtn.addEventListener('click', function() {
  var isVisible;
  isVisible = eventFilters.style.display !== 'none';
  eventFilters.style.display = isVisible ? 'none' : 'block';
  return toggleFiltersBtn.textContent = isVisible ? 'Filters' : 'Hide Filters';
});

// Toggle deleted events
toggleDeletedBtn.addEventListener('click', function() {
  showingDeleted = !showingDeleted;
  toggleDeletedBtn.textContent = showingDeleted ? 'Hide Deleted' : 'Show Deleted';
  toggleDeletedBtn.className = showingDeleted ? 'btn btn-warning' : 'btn btn-secondary';
  return loadEvents(currentFilters);
});

applyFiltersBtn.addEventListener('click', function() {
  var filters, month, type, year;
  filters = {};
  type = document.getElementById('filter-type').value;
  year = document.getElementById('filter-year').value;
  month = document.getElementById('filter-month').value;
  if (type) {
    filters.type = type;
  }
  if (year) {
    filters.year = year;
  }
  if (month) {
    filters.month = month;
  }
  currentFilters = filters;
  return loadEvents(filters);
});

clearFiltersBtn.addEventListener('click', function() {
  document.getElementById('filter-type').value = '';
  document.getElementById('filter-year').value = '';
  document.getElementById('filter-month').value = '';
  currentFilters = {};
  return loadEvents({});
});

// Legacy Payment Modal (keeping for compatibility)
recordPaymentBtn.addEventListener('click', function() {
  document.getElementById('payment-year').value = currentYear;
  document.getElementById('payment-month').value = currentMonth;
  document.getElementById('payment-amount').value = '';
  document.getElementById('payment-date').value = new Date().toISOString().split('T')[0];
  document.getElementById('payment-notes').value = '';
  return paymentModal.style.display = 'block';
});

cancelPaymentBtn.addEventListener('click', function() {
  return paymentModal.style.display = 'none';
});

paymentForm.addEventListener('submit', async function(e) {
  var data, err, error, response;
  e.preventDefault();
  data = {
    year: parseInt(document.getElementById('payment-year').value),
    month: parseInt(document.getElementById('payment-month').value),
    amount: parseFloat(document.getElementById('payment-amount').value),
    payment_date: document.getElementById('payment-date').value,
    payment_method: document.getElementById('payment-method').value,
    notes: document.getElementById('payment-notes').value
  };
  try {
    response = (await fetch('/rent/payment', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(data)
    }));
    if (response.ok) {
      paymentModal.style.display = 'none';
      return autoRecalculateAndReload();
    } else {
      error = (await response.json());
      return showError(`Failed to record payment: ${error.error}`);
    }
  } catch (error1) {
    err = error1;
    return showError(`Error recording payment: ${err.message}`);
  }
});

// Recalculate all periods
document.getElementById('recalculate-btn').addEventListener('click', function() {
  return autoRecalculateAndReload();
});

// Helper functions
formatCurrency = function(amount) {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD'
  }).format(amount);
};

// Auto-recalculate and reload all data
autoRecalculateAndReload = async function() {
  var err, response;
  try {
    response = (await fetch('/rent/recalculate-all', {
      method: 'POST'
    }));
    if (response.ok) {
      loadRentSummary();
      loadCurrentMonth();
      loadAllPeriods();
      return loadEvents(currentFilters);
    }
  } catch (error1) {
    err = error1;
    return console.error('Auto-recalculation failed:', err);
  }
};

formatDate = function(dateStr) {
  var date;
  date = new Date(dateStr);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric'
  });
};

formatMonthYear = function(year, month) {
  var date;
  date = new Date(year, month - 1);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long'
  });
};

formatEventType = function(type) {
  switch (type) {
    case 'payment':
      return 'Payment';
    case 'adjustment':
      return 'Rent Adjustment';
    case 'work_value_change':
      return 'Work Value Change';
    case 'manual':
      return 'Manual Entry';
    default:
      return type;
  }
};

escapeHtml = function(text) {
  var div;
  div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
};

getPaymentStatus = function(period) {
  var due, paid;
  due = period.amount_due;
  paid = period.amount_paid || 0;
  if (paid >= due) {
    return 'PAID';
  } else if (paid > 0) {
    return 'PARTIAL';
  } else {
    return 'UNPAID';
  }
};

showSuccess = function(message) {
  // Simple alert for now - could be enhanced with toast notifications
  return alert(message);
};

showError = function(message) {
  // Simple alert for now - could be enhanced with toast notifications  
  return alert(message);
};
