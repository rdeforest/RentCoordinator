// static/js/rent.js

// Current date
const now = new Date();
let currentYear = now.getFullYear();
let currentMonth = now.getMonth() + 1;

// Load rent summary and current month on page load
window.addEventListener('load', () => {
    loadRentSummary();
    loadCurrentMonth();
    loadAllPeriods();
});

// Load rent summary
async function loadRentSummary() {
    try {
        const response = await fetch('/rent/summary');
        const summary = await response.json();

        document.getElementById('outstanding-balance').textContent =
            formatCurrency(summary.outstanding_balance);
        document.getElementById('total-credits').textContent =
            formatCurrency(summary.total_discount_applied);
        document.getElementById('total-paid').textContent =
            formatCurrency(summary.total_amount_paid);
        document.getElementById('months-tracked').textContent =
            summary.total_periods;

    } catch (err) {
        console.error('Error loading rent summary:', err);
    }
}

// Load current month details
async function loadCurrentMonth() {
    try {
        const response = await fetch(`/rent/period/${currentYear}/${currentMonth}`);
        const period = await response.json();

        document.getElementById('current-month-title').textContent =
            formatMonthYear(currentYear, currentMonth);

        document.getElementById('hours-worked').textContent =
            period.hours_worked.toFixed(2);
        document.getElementById('hours-previous').textContent =
            (period.hours_from_previous || 0).toFixed(2);
        document.getElementById('hours-applied').textContent =
            Math.min(period.hours_worked + (period.hours_from_previous || 0), 8).toFixed(2);
        document.getElementById('credit-applied').textContent =
            formatCurrency(period.discount_applied);
        document.getElementById('amount-due').textContent =
            formatCurrency(period.amount_due);
        document.getElementById('amount-paid').textContent =
            formatCurrency(period.amount_paid || 0);

        document.querySelector('.current-month').style.display = 'block';

    } catch (err) {
        console.error('Error loading current month:', err);
    }
}

// Load all periods
async function loadAllPeriods() {
    try {
        const response = await fetch('/rent/periods');
        const periods = await response.json();

        const tbody = document.getElementById('periods-table');

        if (periods.length === 0) {
            tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">No rent periods found</td></tr>';
            return;
        }

        tbody.innerHTML = periods.map(period => {
            const status = getPaymentStatus(period);
            const statusClass = status.toLowerCase();

            return `
                <tr>
                    <td>${formatMonthYear(period.year, period.month)}</td>
                    <td>${period.hours_worked.toFixed(2)}</td>
                    <td>${formatCurrency(period.discount_applied)}</td>
                    <td>${formatCurrency(period.amount_due)}</td>
                    <td>${formatCurrency(period.amount_paid || 0)}</td>
                    <td class="${statusClass}">${status}</td>
                </tr>
            `;
        }).join('');

    } catch (err) {
        console.error('Error loading periods:', err);
    }
}

// Recalculate all periods
document.getElementById('recalculate-btn').addEventListener('click', async () => {
    if (!confirm('This will recalculate all rent periods including retroactive adjustments. Continue?')) {
        return;
    }

    try {
        const response = await fetch('/rent/recalculate-all', { method: 'POST' });
        const result = await response.json();

        if (response.ok) {
            alert(`Successfully recalculated ${result.periods_updated} periods`);
            // Reload all data
            loadRentSummary();
            loadCurrentMonth();
            loadAllPeriods();
        } else {
            alert('Error recalculating: ' + result.error);
        }

    } catch (err) {
        alert('Error recalculating periods: ' + err.message);
    }
});

// Payment modal handling
const paymentModal = document.getElementById('payment-modal');
const recordPaymentBtn = document.getElementById('record-payment-btn');
const cancelPaymentBtn = document.getElementById('cancel-payment');
const paymentForm = document.getElementById('payment-form');

recordPaymentBtn.addEventListener('click', () => {
    document.getElementById('payment-year').value = currentYear;
    document.getElementById('payment-month').value = currentMonth;
    document.getElementById('payment-amount').value = '';
    document.getElementById('payment-date').value = new Date().toISOString().split('T')[0]; // Today's date
    document.getElementById('payment-notes').value = '';
    paymentModal.style.display = 'block';
});

cancelPaymentBtn.addEventListener('click', () => {
    paymentModal.style.display = 'none';
});

paymentForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const data = {
        year: parseInt(document.getElementById('payment-year').value),
        month: parseInt(document.getElementById('payment-month').value),
        amount: parseFloat(document.getElementById('payment-amount').value),
        payment_date: document.getElementById('payment-date').value,
        payment_method: document.getElementById('payment-method').value,
        notes: document.getElementById('payment-notes').value
    };

    try {
        const response = await fetch('/rent/payment', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });

        if (response.ok) {
            paymentModal.style.display = 'none';
            // Reload data
            loadRentSummary();
            loadCurrentMonth();
            loadAllPeriods();
        } else {
            const error = await response.json();
            alert('Error recording payment: ' + error.error);
        }

    } catch (err) {
        alert('Error recording payment: ' + err.message);
    }
});

// Helper functions
function formatCurrency(amount) {
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD'
    }).format(amount);
}

function formatMonthYear(year, month) {
    const date = new Date(year, month - 1);
    return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long'
    });
}

function getPaymentStatus(period) {
    const due = period.amount_due;
    const paid = period.amount_paid || 0;

    if (paid >= due) return 'PAID';
    if (paid > 0) return 'PARTIAL';
    return 'UNPAID';
}

// Modal styles
const modalStyles = `
<style>
.modal {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
}

.modal-content {
    background: white;
    padding: 30px;
    border-radius: 8px;
    max-width: 500px;
    width: 90%;
}

.modal-content h3 {
    margin-top: 0;
}

.modal-content label {
    display: block;
    margin-top: 15px;
    margin-bottom: 5px;
    font-weight: 600;
}

.modal-content input,
.modal-content select,
.modal-content textarea {
    width: 100%;
    padding: 8px;
    border: 1px solid #ddd;
    border-radius: 4px;
}
</style>
`;

document.head.insertAdjacentHTML('beforeend', modalStyles);