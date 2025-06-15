// static/js/work.js

let allWorkLogs = [];
let filteredLogs = [];

// Load work logs on page load
window.addEventListener('load', () => {
    loadWorkLogs();

    // Set default date to today
    document.getElementById('work-date').value = new Date().toISOString().split('T')[0];
});

// Load and display work logs
async function loadWorkLogs() {
    try {
        const response = await fetch('/work-logs?limit=1000');
        allWorkLogs = await response.json();
        applyFilters();
    } catch (err) {
        console.error('Error loading work logs:', err);
        document.getElementById('work-table-body').innerHTML =
            '<tr><td colspan="5" style="text-align: center;">Error loading work logs</td></tr>';
    }
}

// Apply filters and update display
function applyFilters() {
    const workerFilter = document.getElementById('worker-filter').value;
    const monthFilter = document.getElementById('month-filter').value;

    filteredLogs = allWorkLogs.filter(log => {
        // Worker filter
        if (workerFilter && log.worker !== workerFilter) return false;

        // Month filter
        if (monthFilter) {
            const logDate = new Date(log.start_time);
            const logMonth = `${logDate.getFullYear()}-${String(logDate.getMonth() + 1).padStart(2, '0')}`;
            if (logMonth !== monthFilter) return false;
        }

        return true;
    });

    updateDisplay();
    updateStats();
}

// Update the work logs table
function updateDisplay() {
    const tbody = document.getElementById('work-table-body');

    if (filteredLogs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center;">No work entries found</td></tr>';
        return;
    }

    tbody.innerHTML = filteredLogs.map(log => {
        const startTime = new Date(log.start_time);
        const date = startTime.toLocaleDateString();
        const time = startTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        const hours = (log.duration / 60).toFixed(2);

        return `
            <tr>
                <td>${date} ${time}</td>
                <td>${log.worker}</td>
                <td>${hours} hours</td>
                <td>${escapeHtml(log.description)}</td>
                <td class="actions">
                    <button class="btn btn-secondary" onclick="editWork('${log.id}')">Edit</button>
                    <button class="btn btn-danger" onclick="deleteWork('${log.id}')">Delete</button>
                </td>
            </tr>
        `;
    }).join('');
}

// Update statistics
function updateStats() {
    const totalEntries = filteredLogs.length;
    const totalMinutes = filteredLogs.reduce((sum, log) => sum + log.duration, 0);
    const totalHours = totalMinutes / 60;
    const totalCredit = filteredLogs
        .filter(log => log.billable && log.worker === 'lyndzie')
        .reduce((sum, log) => sum + (log.duration / 60 * 50), 0);

    document.getElementById('total-entries').textContent = totalEntries;
    document.getElementById('total-hours').textContent = totalHours.toFixed(2);
    document.getElementById('total-credit').textContent = formatCurrency(totalCredit);
}

// Filter event listeners
document.getElementById('worker-filter').addEventListener('change', applyFilters);
document.getElementById('month-filter').addEventListener('change', applyFilters);
document.getElementById('clear-filters').addEventListener('click', () => {
    document.getElementById('worker-filter').value = '';
    document.getElementById('month-filter').value = '';
    applyFilters();
});

// Modal handling
const workModal = document.getElementById('work-modal');
const deleteModal = document.getElementById('delete-modal');
const addWorkBtn = document.getElementById('add-work-btn');
const cancelWorkBtn = document.getElementById('cancel-work');
const workForm = document.getElementById('work-form');

// Add work button
addWorkBtn.addEventListener('click', () => {
    document.getElementById('modal-title').textContent = 'Add Work Entry';
    document.getElementById('work-form').reset();
    document.getElementById('work-id').value = '';
    document.getElementById('work-date').value = new Date().toISOString().split('T')[0];
    document.getElementById('work-billable').checked = true;
    workModal.style.display = 'block';
});

// Cancel button
cancelWorkBtn.addEventListener('click', () => {
    workModal.style.display = 'none';
});

// Edit work function
window.editWork = async (id) => {
    const log = allWorkLogs.find(l => l.id === id);
    if (!log) return;

    document.getElementById('modal-title').textContent = 'Edit Work Entry';
    document.getElementById('work-id').value = log.id;
    document.getElementById('work-worker').value = log.worker;

    const startDate = new Date(log.start_time);
    document.getElementById('work-date').value = startDate.toISOString().split('T')[0];
    document.getElementById('work-start-time').value =
        startDate.toTimeString().slice(0, 5);

    const endDate = new Date(log.end_time);
    document.getElementById('work-end-time').value =
        endDate.toTimeString().slice(0, 5);

    document.getElementById('work-description').value = log.description;
    document.getElementById('work-billable').checked = log.billable !== false;

    workModal.style.display = 'block';
};

// Delete work function
window.deleteWork = (id) => {
    document.getElementById('delete-work-id').value = id;
    deleteModal.style.display = 'block';
};

// Work form submission
workForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const id = document.getElementById('work-id').value;
    const worker = document.getElementById('work-worker').value;
    const date = document.getElementById('work-date').value;
    const startTime = document.getElementById('work-start-time').value;
    const endTime = document.getElementById('work-end-time').value;
    const description = document.getElementById('work-description').value;
    const billable = document.getElementById('work-billable').checked;

    // Calculate start and end timestamps
    const startDateTime = new Date(`${date}T${startTime}`);
    const endDateTime = new Date(`${date}T${endTime}`);

    // Handle end time on next day
    if (endDateTime < startDateTime) {
        endDateTime.setDate(endDateTime.getDate() + 1);
    }

    const duration = Math.round((endDateTime - startDateTime) / 1000 / 60); // minutes

    const data = {
        worker,
        start_time: startDateTime.toISOString(),
        end_time: endDateTime.toISOString(),
        duration,
        description: description.trim(),
        billable
    };

    try {
        let response;
        if (id) {
            // Update existing
            response = await fetch(`/work-logs/${id}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });
        } else {
            // Create new
            response = await fetch('/work-logs', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });
        }

        if (response.ok) {
            workModal.style.display = 'none';
            loadWorkLogs(); // Reload data
        } else {
            const error = await response.json();
            alert('Error saving work entry: ' + error.error);
        }
    } catch (err) {
        alert('Error saving work entry: ' + err.message);
    }
});

// Delete confirmation
document.getElementById('confirm-delete').addEventListener('click', async () => {
    const id = document.getElementById('delete-work-id').value;

    try {
        const response = await fetch(`/work-logs/${id}`, {
            method: 'DELETE'
        });

        if (response.ok) {
            deleteModal.style.display = 'none';
            loadWorkLogs(); // Reload data
        } else {
            const error = await response.json();
            alert('Error deleting work entry: ' + error.error);
        }
    } catch (err) {
        alert('Error deleting work entry: ' + err.message);
    }
});

document.getElementById('cancel-delete').addEventListener('click', () => {
    deleteModal.style.display = 'none';
});

// Helper functions
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function formatCurrency(amount) {
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD'
    }).format(amount);
}