import Foundation

// swiftlint:disable line_length
enum MobileWebClient {
    static let html: String = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>Zion Remote</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{--bg:#0d1117;--surface:#161b22;--border:#30363d;--text:#e6edf3;--text2:#8b949e;--accent:#7c3aed;--accent2:#a78bfa;--success:#22c55e;--warn:#f59e0b;--error:#ef4444;--font:-apple-system,BlinkMacSystemFont,'SF Pro Text',system-ui,sans-serif;--mono:'SF Mono',SFMono-Regular,Menlo,monospace}
html,body{height:100%;background:var(--bg);color:var(--text);font-family:var(--font);overflow:hidden;-webkit-text-size-adjust:100%}
#app{display:flex;flex-direction:column;height:100%;height:100dvh}

header{display:flex;align-items:center;justify-content:space-between;padding:12px 16px;background:var(--surface);border-bottom:1px solid var(--border)}
header h1{font-size:16px;font-weight:600}
#status{font-size:12px;padding:4px 10px;border-radius:12px;font-weight:500}
#status.connecting{background:#f59e0b22;color:var(--warn)}
#status.connected{background:#22c55e22;color:var(--success)}
#status.error{background:#ef444422;color:var(--error)}

#sessions{display:flex;gap:6px;padding:8px 16px;background:var(--surface);border-bottom:1px solid var(--border);overflow-x:auto;-webkit-overflow-scrolling:touch}
#sessions:empty{display:none}
.sess-tab{padding:6px 12px;border-radius:8px;font-size:13px;background:var(--bg);border:1px solid var(--border);color:var(--text2);white-space:nowrap;cursor:pointer;-webkit-tap-highlight-color:transparent}
.sess-tab.active{background:var(--accent);border-color:var(--accent);color:#fff}

#terminal-wrap{flex:1;overflow:hidden;position:relative}
#terminal{height:100%;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:12px 16px;font-family:var(--mono);font-size:13px;line-height:1.5;white-space:pre-wrap;word-break:break-all;color:var(--text)}
#terminal:empty::before{content:'Waiting for terminal output...';color:var(--text2);font-family:var(--font);font-style:italic}

#prompt-banner{display:none;padding:12px 16px;background:#7c3aed22;border-top:1px solid var(--accent)}
#prompt-banner.visible{display:block}
#prompt-text{font-size:13px;color:var(--accent2);margin-bottom:10px;font-family:var(--mono)}
#prompt-actions{display:flex;gap:8px}
#prompt-actions button{flex:1;padding:10px;border-radius:10px;border:none;font-size:14px;font-weight:600;cursor:pointer;-webkit-tap-highlight-color:transparent}
#btn-approve{background:var(--success);color:#fff}
#btn-deny{background:var(--surface);color:var(--text);border:1px solid var(--border)}
#btn-abort{background:var(--error);color:#fff}

#input-bar{display:flex;gap:8px;padding:10px 16px;background:var(--surface);border-top:1px solid var(--border);padding-bottom:max(10px,env(safe-area-inset-bottom))}
#cmd-input{flex:1;padding:10px 14px;border-radius:10px;border:1px solid var(--border);background:var(--bg);color:var(--text);font-family:var(--mono);font-size:14px;outline:none;-webkit-appearance:none}
#cmd-input:focus{border-color:var(--accent)}
#btn-send{padding:10px 16px;border-radius:10px;border:none;background:var(--accent);color:#fff;font-weight:600;font-size:14px;cursor:pointer;-webkit-tap-highlight-color:transparent}

#pairing{display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:16px;padding:32px}
#pairing h2{font-size:20px}
#pairing p{color:var(--text2);font-size:14px;text-align:center}
.spinner{width:32px;height:32px;border:3px solid var(--border);border-top-color:var(--accent);border-radius:50%;animation:spin .8s linear infinite}
.spinner.hidden{display:none}
@keyframes spin{to{transform:rotate(360deg)}}
#btn-retry{display:none;padding:12px 24px;border-radius:10px;border:none;background:var(--accent);color:#fff;font-weight:600;font-size:15px;cursor:pointer;-webkit-tap-highlight-color:transparent;margin-top:8px}
</style>
</head>
<body>
<div id="app">
<header>
<h1>Zion Remote</h1>
<span id="status" class="connecting">Connecting</span>
</header>
<div id="sessions"></div>
<div id="terminal-wrap">
<div id="pairing"><div class="spinner" id="pair-spinner"></div><h2 id="pair-title">Connecting...</h2><p id="pair-desc">Establishing secure connection to your Mac</p><button id="btn-retry" onclick="retryConnect()">Refresh</button></div>
<div id="terminal" style="display:none"></div>
</div>
<div id="prompt-banner">
<div id="prompt-text"></div>
<div id="prompt-actions">
<button id="btn-approve" onclick="sendAction('approve')">Approve</button>
<button id="btn-deny" onclick="sendAction('deny')">Deny</button>
<button id="btn-abort" onclick="sendAction('abort')">Abort</button>
</div>
</div>
<div id="input-bar" style="display:none">
<input id="cmd-input" type="text" placeholder="Type command..." autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">
<button id="btn-send" onclick="sendInput()">Send</button>
</div>
</div>
<script>
'use strict';
const $ = s => document.querySelector(s);

// Parse params: prefer query/server-injected (survives QR scanners), fallback to fragment
const qp = new URLSearchParams(location.search);
const fp = new URLSearchParams(location.hash.slice(1));
const P = window.PAIRING || {};
const KEY_B64URL = qp.get('k') || P.k || fp.get('k');
const TOKEN = qp.get('t') || P.t || fp.get('t');
const LAN_MODE = (qp.get('m') || P.m || fp.get('m')) === 'lan';
const BASE = location.origin;

let cryptoKey, activeSession = null, sessions = [];
let polling = false, pollErrors = 0, maxPollErrors = 5;

// -- Crypto (AES-256-GCM via Web Crypto API, skipped in LAN mode) --
async function importKey(b64url) {
  if (LAN_MODE) return null;
  let b64 = b64url.replace(/-/g, '+').replace(/_/g, '/');
  while (b64.length % 4) b64 += '=';
  const raw = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  return crypto.subtle.importKey('raw', raw, {name:'AES-GCM'}, false, ['encrypt','decrypt']);
}

async function encrypt(data) {
  if (LAN_MODE) return data;
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({name:'AES-GCM',iv}, cryptoKey, data);
  const combined = new Uint8Array(12 + ct.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ct), 12);
  return combined;
}

async function decrypt(combined) {
  if (LAN_MODE) return combined;
  const iv = combined.slice(0, 12);
  const ct = combined.slice(12);
  return crypto.subtle.decrypt({name:'AES-GCM',iv}, cryptoKey, ct);
}

function b64ToBytes(b64) {
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
}

// -- Connection --
function showRetry(title, desc) {
  setStatus('error', 'Error');
  $('#pair-title').textContent = title;
  $('#pair-desc').textContent = desc;
  $('#pair-spinner').classList.add('hidden');
  $('#btn-retry').style.display = '';
}

function retryConnect() {
  // Reset state and re-pair (avoids full reload which may lose server-injected PAIRING data)
  pollErrors = 0;
  polling = false;
  $('#pair-spinner').classList.remove('hidden');
  $('#btn-retry').style.display = 'none';
  $('#pair-title').textContent = 'Reconnecting...';
  $('#pair-desc').textContent = 'Establishing secure connection to your Mac';
  setStatus('connecting', 'Connecting');
  connect();
}

async function connect() {
  if (!KEY_B64URL || !TOKEN) {
    showRetry('Connection Error', 'Pairing data not found. Tap Refresh or re-scan the QR code from Zion Settings.');
    return;
  }

  try {
    cryptoKey = await importKey(KEY_B64URL);
  } catch(e) {
    showRetry('Crypto Error', 'Failed to initialize encryption. Tap to retry.');
    return;
  }
  setStatus('connecting', 'Pairing...');

  try {
    const res = await fetch(BASE + '/pair?t=' + TOKEN);
    const data = await res.json();
    if (data.status === 'paired') {
      setStatus('connected', 'Connected');
      $('#pairing').style.display = 'none';
      $('#terminal').style.display = '';
      $('#input-bar').style.display = '';
      startPolling();
    } else {
      showRetry('Pairing Failed', (data.error || 'Unknown error') + '. Tap to retry.');
    }
  } catch(e) {
    showRetry('Connection Failed', e.message + '. Tap to retry.');
    // Also auto-retry after 3 seconds
    setTimeout(connect, 3000);
  }
}

function setStatus(cls, text) {
  const el = $('#status');
  el.className = cls;
  el.textContent = text;
}

// -- Polling --
function startPolling() {
  if (polling) return;
  polling = true;
  poll();
}

async function poll() {
  if (!polling) return;
  try {
    const res = await fetch(BASE + '/poll?t=' + TOKEN);
    if (!res.ok) {
      pollErrors++;
      if (pollErrors >= maxPollErrors) {
        polling = false;
        showDisconnected();
        return;
      }
      setTimeout(poll, Math.min(1000 * pollErrors, 5000));
      return;
    }
    pollErrors = 0;
    setStatus('connected', 'Connected');
    const events = await res.json();
    for (const b64 of events) {
      try {
        const decrypted = await decrypt(b64ToBytes(b64));
        const msg = JSON.parse(new TextDecoder().decode(decrypted));
        handleMessage(msg);
      } catch(e) { console.warn('[Zion] Decrypt error:', e); }
    }
  } catch(e) {
    pollErrors++;
    console.warn('[Zion] Poll error:', e);
    if (pollErrors >= maxPollErrors) {
      polling = false;
      showDisconnected();
      return;
    }
    setTimeout(poll, Math.min(1000 * pollErrors, 5000));
    return;
  }
  setTimeout(poll, 500);
}

function showDisconnected() {
  setStatus('error', 'Disconnected');
  $('#terminal').style.display = 'none';
  $('#input-bar').style.display = 'none';
  $('#pairing').style.display = '';
  $('#pair-spinner').classList.add('hidden');
  $('#pair-title').textContent = 'Connection Lost';
  $('#pair-desc').textContent = 'The connection to your Mac was lost. Tap Reconnect to try again.';
  $('#btn-retry').textContent = 'Reconnect';
  $('#btn-retry').style.display = '';
}

// -- Helpers --
function b64DecodeUTF8(b64) {
  const raw = atob(b64);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

// -- Message handling --
function handleMessage(msg) {
  const payload = msg.payload;
  let p;
  try {
    // payload is base64-encoded JSON (from Swift JSONEncoder encoding Data)
    // Must decode via TextDecoder for proper UTF-8 handling (atob only does Latin-1)
    if (typeof payload === 'string') {
      p = JSON.parse(b64DecodeUTF8(payload));
    } else {
      const bytes = new Uint8Array(payload);
      p = JSON.parse(new TextDecoder().decode(bytes));
    }
  } catch(e) { return; }

  switch(msg.type) {
    case 'sessionList':
      sessions = p.sessions || [];
      renderSessions();
      if (!activeSession && sessions.length > 0) selectSession(sessions[0].id);
      break;
    case 'screenUpdate':
      if (p.sessionID === activeSession) {
        renderTerminal(p.lines);
        if (p.hasPrompt && p.promptText) showPrompt(p.promptText);
      }
      break;
    case 'promptDetected':
      if (p.sessionID === activeSession) showPrompt(p.promptText || 'Action required');
      break;
  }
}

// -- UI --
function renderSessions() {
  const el = $('#sessions');
  el.innerHTML = '';
  sessions.forEach(s => {
    const tab = document.createElement('div');
    tab.className = 'sess-tab' + (s.id === activeSession ? ' active' : '');
    tab.textContent = s.label || s.title || 'Terminal';
    tab.onclick = () => selectSession(s.id);
    el.appendChild(tab);
  });
}

function selectSession(id) {
  activeSession = id;
  renderSessions();
  $('#terminal').textContent = '';
  hidePrompt();
}

function renderTerminal(lines) {
  const el = $('#terminal');
  const wasAtBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
  el.textContent = lines.join('\\n');
  if (wasAtBottom) el.scrollTop = el.scrollHeight;
}

function showPrompt(text) {
  $('#prompt-text').textContent = text;
  $('#prompt-banner').classList.add('visible');
}

function hidePrompt() {
  $('#prompt-banner').classList.remove('visible');
}

// -- Sending --
async function sendEncrypted(msg) {
  const data = new TextEncoder().encode(JSON.stringify(msg));
  const encrypted = await encrypt(data);
  // Send as base64 in POST body, include auth token
  const b64 = btoa(String.fromCharCode(...encrypted));
  const endpoint = msg.type === 'sendAction' ? '/action' : '/input';
  await fetch(BASE + endpoint + '?t=' + TOKEN, {method:'POST', body: b64});
}

async function sendInput() {
  const input = $('#cmd-input');
  const text = input.value;
  if (!text || !activeSession) return;
  input.value = '';

  const payload = btoa(JSON.stringify({text: text + '\\r'}));
  await sendEncrypted({
    type: 'sendInput',
    sessionID: activeSession,
    payload: payload,
    timestamp: new Date().toISOString()
  });
}

async function sendAction(action) {
  if (!activeSession) return;
  hidePrompt();
  const payload = btoa(JSON.stringify({action}));
  await sendEncrypted({
    type: 'sendAction',
    sessionID: activeSession,
    payload: payload,
    timestamp: new Date().toISOString()
  });
}

$('#cmd-input').addEventListener('keydown', e => {
  if (e.key === 'Enter') { e.preventDefault(); sendInput(); }
});

connect();
</script>
</body>
</html>
"""
}
// swiftlint:enable line_length
