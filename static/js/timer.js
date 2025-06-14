// Timer state
let currentWorker = null;
let timerInterval = null;
let timerStartTime = null;

// DOM elements
const workerButtons = document.querySelectorAll('.worker-btn');
const currentWorkerSection = document.querySelector('.current-worker');
const currentWorkerName = document.getElementById('current-worker-name');
const timerSection = document.querySelector('.timer-section');
const workLogsSection = document.querySelector('.work-logs');
const timerStatus = document.getElementById('timer-status');
const timerElapsed = document.getElementById('timer-elapsed');
const startButton = document.getElementById('start-timer');
const stopButton = document.getElementById('stop-timer');
const stopForm = document.getElementById('stop-form');
const workDescription = document.getElementById('work-description');
const submitWorkButton = document.getElementById('submit-work');
const cancelStopButton = document.getElementById('cancel-stop');
const workLogsList = document.getElementById('work-logs-list');

// Worker selection
workerButtons.forEach(btn => {
    btn.addEventListener('click', () => {
        currentWorker = btn.dataset.worker;

        // Update UI
        workerButtons.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');

        currentWorkerName.textContent = currentWorker.charAt(0).toUpperCase() + currentWorker.slice(1);
        currentWorkerSection.style.display = 'block';
        timerSection.style.display = 'block';
        workLogsSection.style.display = 'block';

        // Check timer status
        checkTimerStatus();

        // Load work logs
        loadWorkLogs();
    });
});

// Start timer
startButton.addEventListener('click', async () => {
    try {
        const response = await fetch('/timer/start', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ worker: currentWorker })
        });

        if (!response.ok) {
            const error = await response.json();
            alert(error.error || 'Failed to start timer');
            return;
        }

        const data = await response.json();
        timerStartTime = new Date(data.start_time);

        // Update UI
        timerStatus.textContent = 'Active';
        startButton.style.display = 'none';
        stopButton.style.display = 'inline-block';

        // Start updating elapsed time
        startTimerDisplay();

    } catch (err) {
        alert('Error starting timer: ' + err.message);
    }
});

// Stop timer button
stopButton.addEventListener('click', () => {
    stopForm.style.display = 'block';
    workDescription.focus();
});

// Submit work log
submitWorkButton.addEventListener('click', async () => {
    const description = workDescription.value.trim();

    if (!description) {
        alert('Please describe the work completed');
        return;
    }

    try {
        const response = await fetch('/timer/stop', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                worker: currentWorker,
                description: description
            })
        });

        if (!response.ok) {
            const error = await response.json();
            alert(error.error || 'Failed to stop timer');
            return;
        }

        // Reset UI
        stopTimerDisplay();
        workDescription.value = '';
        stopForm.style.display = 'none';

        // Reload work logs
        loadWorkLogs();

    } catch (err) {
        alert('Error stopping timer: ' + err.message);
    }
});

// Cancel stop
cancelStopButton.addEventListener('click', () => {
    stopForm.style.display = 'none';
    workDescription.value = '';
});

// Check timer status
async function checkTimerStatus() {
    if (!currentWorker) return;

    try {
        const response = await fetch(`/timer/status?worker=${currentWorker}`);
        const data = await response.json();

        if (data.status === 'active') {
            timerStartTime = new Date(data.start_time);
            timerStatus.textContent = 'Active';
            startButton.style.display = 'none';
            stopButton.style.display = 'inline-block';
            startTimerDisplay();
        } else {
            timerStatus.textContent = 'Stopped';
            timerElapsed.textContent = '0:00:00';
            startButton.style.display = 'inline-block';
            stopButton.style.display = 'none';
        }
    } catch (err) {
        console.error('Error checking timer status:', err);
    }
}

// Timer display update
function startTimerDisplay() {
    // Clear any existing interval
    if (timerInterval) clearInterval(timerInterval);

    // Update immediately
    updateTimerDisplay();

    // Then update every second
    timerInterval = setInterval(updateTimerDisplay, 1000);
}

function stopTimerDisplay() {
    if (timerInterval) {
        clearInterval(timerInterval);
        timerInterval = null;
    }

    timerStatus.textContent = 'Stopped';
    timerElapsed.textContent = '0:00:00';
    startButton.style.display = 'inline-block';
    stopButton.style.display = 'none';
}

function updateTimerDisplay() {
    if (!timerStartTime) return;

    const now = new Date();
    const elapsed = Math.floor((now - timerStartTime) / 1000);

    const hours = Math.floor(elapsed / 3600);
    const minutes = Math.floor((elapsed % 3600) / 60);
    const seconds = elapsed % 60;

    timerElapsed.textContent = `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

// Load work logs
async function loadWorkLogs() {
    if (!currentWorker) return;

    try {
        const response = await fetch(`/work-logs?worker=${currentWorker}&limit=10`);
        const logs = await response.json();

        if (logs.length === 0) {
            workLogsList.innerHTML = '<p>No work logs yet.</p>';
            return;
        }

        workLogsList.innerHTML = logs.map(log => {
            const startTime = new Date(log.start_time);
            const date = startTime.toLocaleDateString();
            const time = startTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

            return `
                <div class="work-log-item">
                    <div class="work-log-header">
                        <span class="work-log-worker">${log.worker}</span>
                        <span class="work-log-time">${date} at ${time}</span>
                    </div>
                    <div>
                        <span class="work-log-duration">${log.duration} min</span>
                    </div>
                    <div class="work-log-description">${escapeHtml(log.description)}</div>
                </div>
            `;
        }).join('');

    } catch (err) {
        console.error('Error loading work logs:', err);
        workLogsList.innerHTML = '<p>Error loading work logs.</p>';
    }
}

// Helper to escape HTML
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Check for active timer on page load
window.addEventListener('load', () => {
    // Auto-select worker if returning to page
    const lastWorker = localStorage.getItem('lastWorker');
    if (lastWorker) {
        const workerBtn = document.querySelector(`[data-worker="${lastWorker}"]`);
        if (workerBtn) {
            workerBtn.click();
        }
    }
});

// Save selected worker
window.addEventListener('beforeunload', () => {
    if (currentWorker) {
        localStorage.setItem('lastWorker', currentWorker);
    }
});