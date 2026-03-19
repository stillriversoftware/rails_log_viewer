(function() {
  'use strict';

  var app = document.getElementById('rlv-app');
  if (!app) return;

  var source = app.dataset.source;
  var logsUrl = app.dataset.logsUrl;
  var streamUrl = app.dataset.streamUrl;

  var output = document.getElementById('rlv-output');
  var searchInput = document.getElementById('rlv-search');
  var liveBtn = document.getElementById('rlv-live-btn');
  var copyBtn = document.getElementById('rlv-copy-btn');
  var olderBtn = document.getElementById('rlv-older-btn');
  var statusEl = document.getElementById('rlv-status');
  var streamSelect = document.getElementById('rlv-stream-select');

  var currentPage = 0;
  var hasMore = false;
  var eventSource = null;
  var debounceTimer = null;
  var lineCounter = 0;

  function init() {
    fetchLogs(0, '');
    searchInput.addEventListener('input', onSearchInput);
    liveBtn.addEventListener('click', toggleLive);
    copyBtn.addEventListener('click', copyToClipboard);
    olderBtn.addEventListener('click', loadOlder);
    if (streamSelect) {
      streamSelect.addEventListener('change', onStreamChange);
    }
  }

  // Debounced search

  function onSearchInput() {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(function() {
      var query = searchInput.value.trim();
      currentPage = 0;
      lineCounter = 0;
      output.innerHTML = '';
      fetchLogs(0, query);
    }, 400);
  }

  // Fetch logs from JSON endpoint

  function fetchLogs(page, query) {
    showStatus('Loading...');
    var url = logsUrl + '/show?source=' + encodeURIComponent(source) +
              '&page=' + page;
    if (query) {
      url += '&query=' + encodeURIComponent(query);
    }
    if (source === 'cloudwatch' && streamSelect && streamSelect.value) {
      url += '&stream=' + encodeURIComponent(streamSelect.value);
    }

    fetch(url, {
      headers: { 'Accept': 'application/json' }
    })
    .then(function(resp) {
      if (!resp.ok) throw new Error('HTTP ' + resp.status);
      return resp.json();
    })
    .then(function(data) {
      hideStatus();
      renderLines(data.lines, page > 0);
      currentPage = data.pagination.page;
      hasMore = data.pagination.has_more;
      olderBtn.hidden = !hasMore;
    })
    .catch(function(err) {
      showStatus('Error: ' + err.message);
    });
  }

  // Render log lines

  function renderLines(lines, append) {
    if (!append) {
      output.innerHTML = '';
      lineCounter = 0;
    }

    var fragment = document.createDocumentFragment();

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var text = typeof line === 'string' ? line : line.message || '';
      var timestamp = (typeof line === 'object' && line.timestamp) ? line.timestamp : null;

      lineCounter++;
      var div = document.createElement('div');
      div.className = 'rlv-line ' + classifyLine(text);

      var numSpan = document.createElement('span');
      numSpan.className = 'rlv-line-num';
      numSpan.textContent = lineCounter;
      div.appendChild(numSpan);

      if (timestamp) {
        var tsSpan = document.createElement('span');
        tsSpan.className = 'rlv-timestamp';
        tsSpan.textContent = formatTimestamp(timestamp);
        div.appendChild(tsSpan);
      }

      div.appendChild(document.createTextNode(text));
      fragment.appendChild(div);
    }

    if (append) {
      var firstChild = output.firstChild;
      if (firstChild) {
        output.insertBefore(fragment, firstChild);
      } else {
        output.appendChild(fragment);
      }
    } else {
      output.appendChild(fragment);
      output.scrollTop = output.scrollHeight;
    }
  }

  function classifyLine(text) {
    if (/\[REDACTED\]/.test(text)) return 'rlv-line--redacted';
    if (/\bERROR\b|\bFATAL\b/i.test(text)) return 'rlv-line--error';
    if (/\bWARN\b/i.test(text)) return 'rlv-line--warn';
    if (/\bDEBUG\b/i.test(text)) return 'rlv-line--debug';
    return 'rlv-line--info';
  }

  function formatTimestamp(ts) {
    var d = new Date(ts);
    if (isNaN(d.getTime())) return ts;
    return d.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  // Pagination

  function loadOlder() {
    if (!hasMore) return;
    currentPage++;
    fetchLogs(currentPage, searchInput.value.trim());
  }

  // Live tail via SSE

  function toggleLive() {
    if (eventSource) {
      stopLive();
    } else {
      startLive();
    }
  }

  function startLive() {
    var url = streamUrl + '?source=' + encodeURIComponent(source);
    if (source === 'cloudwatch' && streamSelect && streamSelect.value) {
      url += '&stream=' + encodeURIComponent(streamSelect.value);
    }

    eventSource = new EventSource(url);
    liveBtn.setAttribute('aria-pressed', 'true');
    liveBtn.textContent = 'Stop Tail';
    showStatus('Live tail connected');

    eventSource.onmessage = function(event) {
      try {
        var lines = JSON.parse(event.data);
        renderLines(lines, false);
        output.scrollTop = output.scrollHeight;
      } catch (e) {
        // skip malformed events
      }
    };

    eventSource.onerror = function() {
      stopLive();
      showStatus('Live tail disconnected');
    };
  }

  function stopLive() {
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }
    liveBtn.setAttribute('aria-pressed', 'false');
    liveBtn.textContent = 'Live Tail';
    hideStatus();
  }

  // Stream selector

  function onStreamChange() {
    currentPage = 0;
    lineCounter = 0;
    output.innerHTML = '';
    if (eventSource) stopLive();
    if (streamSelect.value) {
      fetchLogs(0, searchInput.value.trim());
    }
  }

  // Copy to clipboard

  function copyToClipboard() {
    var lineEls = output.querySelectorAll('.rlv-line');
    var texts = [];
    for (var i = 0; i < lineEls.length; i++) {
      var clone = lineEls[i].cloneNode(true);
      var numSpan = clone.querySelector('.rlv-line-num');
      if (numSpan) clone.removeChild(numSpan);
      texts.push(clone.textContent);
    }
    var text = texts.join('\n');

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function() {
        flashCopyBtn('Copied!');
      });
    } else {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      flashCopyBtn('Copied!');
    }
  }

  function flashCopyBtn(msg) {
    var original = copyBtn.textContent;
    copyBtn.textContent = msg;
    setTimeout(function() {
      copyBtn.textContent = original;
    }, 1500);
  }

  // Status

  function showStatus(msg) {
    statusEl.textContent = msg;
    statusEl.hidden = false;
  }

  function hideStatus() {
    statusEl.hidden = true;
  }

  // Boot

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
