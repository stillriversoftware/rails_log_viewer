(function() {
  'use strict';

  var app = document.getElementById('rlv-app');
  if (!app) return;

  var source = app.dataset.source;
  var queryUrl = app.dataset.queryUrl;
  var streamUrl = app.dataset.streamUrl;

  var output = document.getElementById('rlv-output');
  var searchInput = document.getElementById('rlv-search');
  var liveBtn = document.getElementById('rlv-live-btn');
  var copyBtn = document.getElementById('rlv-copy-btn');
  var olderBtn = document.getElementById('rlv-older-btn');
  var statusEl = document.getElementById('rlv-status');
  var jumpBtn = document.getElementById('rlv-jump-latest');
  var timeRange = document.getElementById('rlv-time-range');
  var customTime = document.getElementById('rlv-custom-time');
  var timeStart = document.getElementById('rlv-time-start');
  var timeEnd = document.getElementById('rlv-time-end');
  var timeApply = document.getElementById('rlv-time-apply');
  var streamSelect = document.getElementById('rlv-stream-select');
  var sevButtons = document.querySelectorAll('.rlv-sev-btn');

  var cursorOlder = null;
  var cursorNewer = null;
  var eventSource = null;
  var debounceTimer = null;
  var isAtBottom = true;
  var loading = false;

  function init() {
    fetchLogs();
    searchInput.addEventListener('input', onSearchInput);
    liveBtn.addEventListener('click', toggleLive);
    copyBtn.addEventListener('click', copyToClipboard);
    olderBtn.addEventListener('click', loadOlder);
    jumpBtn.addEventListener('click', jumpToLatest);
    timeRange.addEventListener('change', onTimeRangeChange);
    timeApply.addEventListener('click', function() { fetchLogs(); });
    output.addEventListener('scroll', onScroll);

    for (var i = 0; i < sevButtons.length; i++) {
      sevButtons[i].addEventListener('click', onSeverityToggle);
    }

    if (streamSelect) {
      streamSelect.addEventListener('change', function() {
        if (eventSource) stopLive();
        fetchLogs();
      });
    }
  }

  // Time range

  function getTimeRange() {
    var val = timeRange.value;
    if (val === 'custom') {
      return {
        start_time: timeStart.value ? new Date(timeStart.value).toISOString() : null,
        end_time: timeEnd.value ? new Date(timeEnd.value).toISOString() : null
      };
    }
    var ms = { '15m': 900000, '1h': 3600000, '6h': 21600000, '24h': 86400000 }[val] || 3600000;
    var now = new Date();
    return {
      start_time: new Date(now.getTime() - ms).toISOString(),
      end_time: now.toISOString()
    };
  }

  function onTimeRangeChange() {
    if (timeRange.value === 'custom') {
      customTime.hidden = false;
      var now = new Date();
      var hour_ago = new Date(now.getTime() - 3600000);
      timeEnd.value = toLocalDatetime(now);
      timeStart.value = toLocalDatetime(hour_ago);
    } else {
      customTime.hidden = true;
      fetchLogs();
    }
  }

  function toLocalDatetime(d) {
    var offset = d.getTimezoneOffset();
    var local = new Date(d.getTime() - offset * 60000);
    return local.toISOString().slice(0, 16);
  }

  // Severity filter

  function getActiveSeverities() {
    var active = [];
    for (var i = 0; i < sevButtons.length; i++) {
      if (sevButtons[i].classList.contains('rlv-sev-active')) {
        active.push(sevButtons[i].dataset.severity);
      }
    }
    return active;
  }

  function onSeverityToggle(e) {
    e.currentTarget.classList.toggle('rlv-sev-active');
    fetchLogs();
  }

  // Debounced search

  function onSearchInput() {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(function() { fetchLogs(); }, 400);
  }

  // Fetch logs

  function fetchLogs(cursor, direction) {
    if (loading) return;
    loading = true;
    showStatus('Loading...');

    var range = getTimeRange();
    var params = [];
    if (range.start_time) params.push('start_time=' + encodeURIComponent(range.start_time));
    if (range.end_time) params.push('end_time=' + encodeURIComponent(range.end_time));

    var q = searchInput.value.trim();
    if (q) params.push('q=' + encodeURIComponent(q));

    var sev = getActiveSeverities();
    if (sev.length > 0 && sev.length < 4) {
      params.push('severity=' + encodeURIComponent(sev.join(',')));
    }

    if (cursor) params.push('cursor=' + encodeURIComponent(cursor));
    if (direction) params.push('direction=' + encodeURIComponent(direction));

    if (source === 'cloudwatch' && streamSelect && streamSelect.value) {
      params.push('stream=' + encodeURIComponent(streamSelect.value));
    }

    var url = queryUrl + '?' + params.join('&');

    fetch(url, { headers: { 'Accept': 'application/json' } })
      .then(function(resp) {
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        return resp.json();
      })
      .then(function(data) {
        loading = false;
        hideStatus();

        if (direction === 'older') {
          prependLines(data.lines);
          cursorOlder = data.cursors.older;
        } else {
          output.innerHTML = '';
          renderLines(data.lines);
          cursorOlder = data.cursors.older;
          cursorNewer = data.cursors.newer;
          scrollToBottom();
        }

        olderBtn.hidden = !cursorOlder;
      })
      .catch(function(err) {
        loading = false;
        showStatus('Error: ' + err.message);
      });
  }

  // Render

  function renderLines(lines) {
    var fragment = document.createDocumentFragment();
    for (var i = 0; i < lines.length; i++) {
      fragment.appendChild(buildLineEl(lines[i]));
    }
    output.appendChild(fragment);
  }

  function prependLines(lines) {
    var fragment = document.createDocumentFragment();
    for (var i = 0; i < lines.length; i++) {
      fragment.appendChild(buildLineEl(lines[i]));
    }
    var scrollBefore = output.scrollHeight;
    output.insertBefore(fragment, output.firstChild);
    output.scrollTop += (output.scrollHeight - scrollBefore);
  }

  function buildLineEl(line) {
    var msg = line.message || '';
    var sev = (line.severity || '').toUpperCase();
    var ts = line.timestamp;

    var div = document.createElement('div');
    div.className = 'rlv-line ' + classifyLine(msg, sev);

    if (ts) {
      var tsSpan = document.createElement('span');
      tsSpan.className = 'rlv-ts';
      tsSpan.textContent = formatTimestamp(ts);
      div.appendChild(tsSpan);
    }

    if (sev) {
      var sevSpan = document.createElement('span');
      sevSpan.className = 'rlv-sev rlv-sev--' + sev.toLowerCase();
      sevSpan.textContent = sev;
      div.appendChild(sevSpan);
    }

    div.appendChild(document.createTextNode(msg));
    return div;
  }

  function classifyLine(msg, sev) {
    if (/\[REDACTED\]/.test(msg)) return 'rlv-line--redacted';
    switch (sev) {
      case 'ERROR': case 'FATAL': return 'rlv-line--error';
      case 'WARN': return 'rlv-line--warn';
      case 'DEBUG': return 'rlv-line--debug';
      default: return 'rlv-line--info';
    }
  }

  function formatTimestamp(ts) {
    var d = new Date(ts);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  // Pagination

  function loadOlder() {
    if (!cursorOlder || loading) return;
    fetchLogs(cursorOlder, 'older');
  }

  // Scroll tracking

  function onScroll() {
    var threshold = 40;
    isAtBottom = (output.scrollHeight - output.scrollTop - output.clientHeight) < threshold;
    if (isAtBottom) jumpBtn.hidden = true;
  }

  function scrollToBottom() {
    output.scrollTop = output.scrollHeight;
    isAtBottom = true;
    jumpBtn.hidden = true;
  }

  function jumpToLatest() {
    scrollToBottom();
  }

  // Live tail

  function toggleLive() {
    if (eventSource) { stopLive(); } else { startLive(); }
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
        renderLines(lines);
        if (isAtBottom) {
          scrollToBottom();
        } else {
          jumpBtn.hidden = false;
        }
      } catch (e) {}
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

  // Copy

  function copyToClipboard() {
    var lineEls = output.querySelectorAll('.rlv-line');
    var texts = [];
    for (var i = 0; i < lineEls.length; i++) {
      var clone = lineEls[i].cloneNode(true);
      var spans = clone.querySelectorAll('.rlv-ts, .rlv-sev');
      for (var j = 0; j < spans.length; j++) clone.removeChild(spans[j]);
      texts.push(clone.textContent);
    }
    var text = texts.join('\n');

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function() { flashBtn(copyBtn, 'Copied!'); });
    } else {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.cssText = 'position:fixed;opacity:0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      flashBtn(copyBtn, 'Copied!');
    }
  }

  function flashBtn(btn, msg) {
    var orig = btn.textContent;
    btn.textContent = msg;
    setTimeout(function() { btn.textContent = orig; }, 1500);
  }

  // Status

  function showStatus(msg) { statusEl.textContent = msg; statusEl.hidden = false; }
  function hideStatus() { statusEl.hidden = true; }

  // Boot

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
