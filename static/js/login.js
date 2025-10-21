// static/coffee/login.coffee

// DOM elements
var checkAuthStatus, codeInput, currentEmail, emailForm, emailInput, emailStep, handleBackToEmail, handleEmailSubmit, handleVerifySubmit, messageDiv, showMessage, showVerifyStep, verifyForm, verifyStep;

emailForm = null;

verifyForm = null;

emailStep = null;

verifyStep = null;

emailInput = null;

codeInput = null;

messageDiv = null;

currentEmail = null;

// Initialize on DOM load
document.addEventListener('DOMContentLoaded', function() {
  var backLink;
  emailForm = document.getElementById('emailForm');
  verifyForm = document.getElementById('verifyForm');
  emailStep = document.getElementById('emailStep');
  verifyStep = document.getElementById('verifyStep');
  emailInput = document.getElementById('email');
  codeInput = document.getElementById('code');
  messageDiv = document.getElementById('message');
  backLink = document.getElementById('backToEmail');
  // Set up event listeners
  emailForm.addEventListener('submit', handleEmailSubmit);
  verifyForm.addEventListener('submit', handleVerifySubmit);
  backLink.addEventListener('click', handleBackToEmail);
  // Check if already authenticated
  return checkAuthStatus();
});

// Check if user is already authenticated
checkAuthStatus = async function() {
  var data, err, response;
  try {
    response = (await fetch('/auth/status'));
    data = (await response.json());
    if (data.authenticated) {
      // Already logged in, redirect to home
      return window.location.href = '/';
    }
  } catch (error) {
    err = error;
    return console.error('Auth check failed:', err);
  }
};

// Handle email form submission
handleEmailSubmit = async function(e) {
  var data, email, err, response;
  e.preventDefault();
  email = emailInput.value.trim();
  if (!email) {
    return showMessage('Please enter your email address', 'error');
  }
  currentEmail = email;
  // Disable form
  emailForm.querySelector('button').disabled = true;
  showMessage('Sending verification code...', 'success');
  try {
    response = (await fetch('/auth/send-code', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        email: email
      })
    }));
    data = (await response.json());
    if (response.ok) {
      showMessage('Verification code sent! Check your email (or console in dev mode)', 'success');
      return showVerifyStep();
    } else {
      showMessage(data.error || 'Failed to send code', 'error');
      return emailForm.querySelector('button').disabled = false;
    }
  } catch (error) {
    err = error;
    console.error('Send code error:', err);
    showMessage('Network error. Please try again.', 'error');
    return emailForm.querySelector('button').disabled = false;
  }
};

// Handle verification form submission
handleVerifySubmit = async function(e) {
  var code, data, err, response;
  e.preventDefault();
  code = codeInput.value.trim();
  if (!code || code.length !== 6) {
    return showMessage('Please enter the 6-digit code', 'error');
  }
  // Disable form
  verifyForm.querySelector('button').disabled = true;
  showMessage('Verifying code...', 'success');
  try {
    response = (await fetch('/auth/verify-code', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        email: currentEmail,
        code: code
      })
    }));
    data = (await response.json());
    if (response.ok) {
      showMessage('Success! Redirecting...', 'success');
      // Redirect to home page after a brief delay
      return setTimeout((function() {
        return window.location.href = '/';
      }), 1000);
    } else {
      showMessage(data.error || 'Invalid or expired code', 'error');
      verifyForm.querySelector('button').disabled = false;
      codeInput.value = '';
      return codeInput.focus();
    }
  } catch (error) {
    err = error;
    console.error('Verify code error:', err);
    showMessage('Network error. Please try again.', 'error');
    return verifyForm.querySelector('button').disabled = false;
  }
};

// Show verify step
showVerifyStep = function() {
  emailStep.style.display = 'none';
  verifyStep.style.display = 'block';
  codeInput.value = '';
  return codeInput.focus();
};

// Back to email entry
handleBackToEmail = function(e) {
  e.preventDefault();
  emailStep.style.display = 'block';
  verifyStep.style.display = 'none';
  emailForm.querySelector('button').disabled = false;
  emailInput.focus();
  return showMessage('', '');
};

// Show message to user
showMessage = function(text, type) {
  if (!text) {
    messageDiv.innerHTML = '';
    messageDiv.className = 'message';
    return;
  }
  messageDiv.textContent = text;
  return messageDiv.className = `message ${type}`;
};
