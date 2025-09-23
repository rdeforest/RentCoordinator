// static/coffee/shared-utils.coffee

// Shared utility functions for all pages
window.SharedUtils = {
  // Format currency
  formatCurrency: function(amount) {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD'
    }).format(amount);
  },
  // Format date/time
  formatDateTime: function(date) {
    return date.toLocaleString([], {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  },
  // Format duration from seconds
  formatDuration: function(seconds) {
    var hours, minutes, secs;
    hours = Math.floor(seconds / 3600);
    minutes = Math.floor((seconds % 3600) / 60);
    secs = seconds % 60;
    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    } else {
      return `${minutes}:${String(secs).padStart(2, '0')}`;
    }
  },
  // Escape HTML to prevent XSS
  escapeHtml: function(text) {
    var div;
    div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },
  // Make async fetch with standard error handling
  fetchJSON: async function(url, options = {}) {
    var data, err, ref, response;
    try {
      response = (await fetch(url, options));
      if ((ref = response.headers.get('content-type')) != null ? ref.includes('application/json') : void 0) {
        data = (await response.json());
      }
      if (response.ok) {
        return {
          ok: true,
          data
        };
      } else {
        return {
          ok: false,
          error: (data != null ? data.error : void 0) || `Request failed: ${response.status}`
        };
      }
    } catch (error) {
      err = error;
      return {
        ok: false,
        error: err.message
      };
    }
  },
  // Debounce function calls
  debounce: function(func, wait) {
    var timeout;
    timeout = null;
    return function() {
      var args, context;
      context = this;
      args = arguments;
      clearTimeout(timeout);
      return timeout = setTimeout(function() {
        return func.apply(context, args);
      }, wait);
    };
  },
  // Get worker name from localStorage
  getLastWorker: function() {
    return localStorage.getItem('lastWorker');
  },
  // Save worker name to localStorage
  saveLastWorker: function(worker) {
    if (worker) {
      return localStorage.setItem('lastWorker', worker);
    }
  },
  // Show/hide elements
  show: function(element) {
    if (element) {
      return element.style.display = 'block';
    }
  },
  hide: function(element) {
    if (element) {
      return element.style.display = 'none';
    }
  },
  // Add loading state to button
  setButtonLoading: function(button, isLoading) {
    if (isLoading) {
      button.disabled = true;
      button.dataset.originalText = button.textContent;
      return button.textContent = 'Loading...';
    } else {
      button.disabled = false;
      if (button.dataset.originalText) {
        return button.textContent = button.dataset.originalText;
      }
    }
  }
};
