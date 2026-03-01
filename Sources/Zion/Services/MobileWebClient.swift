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
:root{
  --bg:#110b1f;--surface:#1a1229;--surface2:#221838;--border:rgba(255,255,255,0.10);--border2:rgba(255,255,255,0.06);
  --text:#e8e4f0;--text2:#9a8fad;--text3:#6b5f80;
  --accent:#7c3aed;--accent2:#a78bfa;--accent-glow:rgba(124,58,237,0.25);--accent-subtle:rgba(124,58,237,0.10);
  --brand-dark:#1a004e;--brand-ink:#2a016c;--brand-primary:#65449b;
  --success:#4dcc7a;--warn:#e6a23c;--error:#e05252;
  --font:-apple-system,BlinkMacSystemFont,'SF Pro Text',system-ui,sans-serif;
  --mono:'SF Mono',SFMono-Regular,Menlo,monospace;
  --radius:12px;--radius-sm:8px
}
html,body{height:100%;background:var(--bg);color:var(--text);font-family:var(--font);overflow:hidden;-webkit-text-size-adjust:100%}
#app{display:flex;flex-direction:column;height:100%;height:100dvh}

/* ── Header ── */
header{display:flex;align-items:center;gap:12px;padding:14px 16px;background:var(--surface);border-bottom:1px solid var(--border);position:relative;z-index:10}
header::after{content:'';position:absolute;bottom:0;left:0;right:0;height:2px;background:linear-gradient(90deg,#36f9f6,#ff7edb);opacity:0.5}
#menu-btn{width:36px;height:36px;border:none;background:var(--accent-subtle);border-radius:var(--radius-sm);color:var(--accent2);font-size:18px;cursor:pointer;-webkit-tap-highlight-color:transparent;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:background .15s}
#menu-btn:active{background:var(--accent-glow)}
#header-info{flex:1;min-width:0}
#header-title{font-size:11px;font-weight:500;color:var(--text2);text-transform:uppercase;letter-spacing:0.5px}
#header-context{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#status{font-size:11px;padding:4px 10px;border-radius:12px;font-weight:600;flex-shrink:0;letter-spacing:0.3px}
#status.connecting{background:rgba(230,162,60,0.15);color:var(--warn)}
#status.connected{background:rgba(77,204,122,0.15);color:var(--success)}
#status.error{background:rgba(224,82,82,0.15);color:var(--error)}

/* ── Drawer overlay + panel ── */
#drawer-overlay{position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:20;opacity:0;pointer-events:none;transition:opacity .25s ease;-webkit-backdrop-filter:blur(2px);backdrop-filter:blur(2px)}
#drawer-overlay.open{opacity:1;pointer-events:auto}
#drawer{position:fixed;top:0;left:0;bottom:0;width:min(300px,80vw);background:var(--surface);border-right:1px solid var(--border);z-index:21;transform:translateX(-100%);transition:transform .25s cubic-bezier(.4,0,.2,1);overflow-y:auto;-webkit-overflow-scrolling:touch;display:flex;flex-direction:column}
#drawer.open{transform:translateX(0)}

#drawer-header{padding:20px 16px 16px;border-bottom:1px solid var(--border);position:relative}
#drawer-header::after{content:'';position:absolute;bottom:0;left:0;right:0;height:2px;background:linear-gradient(90deg,#36f9f6,#ff7edb);opacity:0.35}
#drawer-brand{display:flex;align-items:center;gap:10px}
#drawer-logo{width:28px;height:28px;border-radius:var(--radius-sm);background:linear-gradient(135deg,var(--brand-ink),var(--accent));display:flex;align-items:center;justify-content:center;font-weight:700;font-size:14px;color:#fff}
#drawer-brand h2{font-size:17px;font-weight:700;background:linear-gradient(135deg,var(--accent2),#36f9f6);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
#drawer-subtitle{font-size:12px;color:var(--text3);margin-top:4px}

#drawer-list{flex:1;padding:12px 0;overflow-y:auto}
.drawer-repo{padding:0 12px;margin-bottom:4px}
.drawer-repo-header{display:flex;align-items:center;gap:8px;padding:8px 12px;border-radius:var(--radius-sm);font-size:13px;font-weight:600;color:var(--text2);cursor:pointer;-webkit-tap-highlight-color:transparent;transition:background .15s}
.drawer-repo-header:active{background:var(--accent-subtle)}
.drawer-repo-header.active{color:var(--accent2)}
.drawer-repo-icon{font-size:14px;opacity:0.6}
.drawer-repo-count{margin-left:auto;font-size:11px;font-weight:500;background:var(--border);padding:2px 7px;border-radius:10px;color:var(--text3)}
.drawer-session{display:flex;align-items:center;gap:8px;padding:10px 12px 10px 38px;margin:2px 12px;border-radius:var(--radius-sm);font-size:14px;color:var(--text2);cursor:pointer;-webkit-tap-highlight-color:transparent;transition:all .15s;border:1px solid transparent}
.drawer-session:active{background:var(--accent-subtle)}
.drawer-session.active{background:var(--accent-subtle);border-color:var(--accent);color:var(--text);font-weight:500}
.drawer-session-icon{font-size:12px;opacity:0.5}
.drawer-session-label{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}

/* ── Terminal ── */
#terminal-wrap{flex:1;overflow:hidden;position:relative}
#terminal{height:100%;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:12px 16px;font-family:var(--mono);font-size:13px;line-height:1.5;white-space:pre-wrap;word-break:break-all;color:var(--text)}
#terminal:empty::before{content:'Waiting for terminal output...';color:var(--text3);font-family:var(--font);font-style:italic}

/* ── Quick actions ── */
#quick-actions{display:none;padding:8px 16px;background:var(--surface);border-top:1px solid var(--border);overflow-x:auto;-webkit-overflow-scrolling:touch;white-space:nowrap}
#quick-actions.visible{display:flex;gap:6px}
.qa-btn{min-width:44px;min-height:44px;padding:8px 12px;border-radius:var(--radius-sm);border:1px solid var(--border);background:var(--surface2);color:var(--text);font-family:var(--mono);font-size:14px;font-weight:500;cursor:pointer;-webkit-tap-highlight-color:transparent;flex-shrink:0;display:flex;align-items:center;justify-content:center;transition:all .12s}
.qa-btn:active{background:var(--accent);border-color:var(--accent);color:#fff;transform:scale(0.95)}

/* ── Prompt banner ── */
#prompt-banner{display:none;padding:12px 16px;background:var(--accent-subtle);border-top:1px solid rgba(124,58,237,0.3)}
#prompt-banner.visible{display:block}
#prompt-text{font-size:13px;color:var(--accent2);margin-bottom:10px;font-family:var(--mono)}
#prompt-actions{display:flex;gap:8px}
#prompt-actions button{flex:1;padding:10px;border-radius:var(--radius);border:none;font-size:14px;font-weight:600;cursor:pointer;-webkit-tap-highlight-color:transparent;transition:transform .1s}
#prompt-actions button:active{transform:scale(0.97)}
#btn-approve{background:var(--success);color:#fff}
#btn-deny{background:var(--surface2);color:var(--text);border:1px solid var(--border)}
#btn-abort{background:var(--error);color:#fff}

/* ── Input bar ── */
#input-bar{display:flex;gap:8px;padding:10px 16px;background:var(--surface);border-top:1px solid var(--border);padding-bottom:max(10px,env(safe-area-inset-bottom))}
#cmd-input{flex:1;padding:10px 14px;border-radius:var(--radius);border:1px solid var(--border);background:var(--bg);color:var(--text);font-family:var(--mono);font-size:14px;outline:none;-webkit-appearance:none;transition:border-color .15s}
#cmd-input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-subtle)}
#btn-send{padding:10px 18px;border-radius:var(--radius);border:none;background:var(--accent);color:#fff;font-weight:600;font-size:14px;cursor:pointer;-webkit-tap-highlight-color:transparent;transition:transform .1s}
#btn-send:active{transform:scale(0.95)}

/* ── Pairing screen ── */
#pairing{display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:16px;padding:32px}
#pairing h2{font-size:20px;font-weight:700}
#pairing p{color:var(--text2);font-size:14px;text-align:center;max-width:280px;line-height:1.5}
.spinner{width:32px;height:32px;border:3px solid var(--border);border-top-color:var(--accent);border-radius:50%;animation:spin .8s linear infinite}
.spinner.hidden{display:none}
@keyframes spin{to{transform:rotate(360deg)}}
#btn-retry{display:none;padding:12px 24px;border-radius:var(--radius);border:none;background:var(--accent);color:#fff;font-weight:600;font-size:15px;cursor:pointer;-webkit-tap-highlight-color:transparent;margin-top:8px;transition:transform .1s}
#btn-retry:active{transform:scale(0.95)}

/* ── Zion branding on pairing ── */
#pair-brand{display:flex;align-items:center;gap:10px;margin-bottom:8px}
#pair-logo{width:40px;height:40px;border-radius:12px;background:linear-gradient(135deg,var(--brand-ink),var(--accent));display:flex;align-items:center;justify-content:center;font-weight:700;font-size:20px;color:#fff}
#pair-brand-name{font-size:22px;font-weight:700;background:linear-gradient(135deg,var(--accent2),#36f9f6);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
</style>
</head>
<body>
<div id="app">
<header>
<button id="menu-btn" onclick="toggleDrawer()" aria-label="Menu">&#9776;</button>
<div id="header-info">
<div id="header-title">Zion Remote</div>
<div id="header-context">No session</div>
</div>
<span id="status" class="connecting">Connecting</span>
</header>

<div id="drawer-overlay" onclick="closeDrawer()"></div>
<nav id="drawer">
<div id="drawer-header">
<div id="drawer-brand"><div id="drawer-logo">Z</div><h2>Zion</h2></div>
<div id="drawer-subtitle">Remote Terminal Access</div>
</div>
<div id="drawer-list"></div>
</nav>

<div id="terminal-wrap">
<div id="pairing">
<div id="pair-brand"><div id="pair-logo">Z</div><span id="pair-brand-name">Zion</span></div>
<div class="spinner" id="pair-spinner"></div>
<h2 id="pair-title">Connecting...</h2>
<p id="pair-desc">Establishing secure connection to your Mac</p>
<button id="btn-retry" onclick="retryConnect()">Refresh</button>
</div>
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
<div id="quick-actions">
<button class="qa-btn" onclick="sendAction('ctrlc')">&#x2303;C</button>
<button class="qa-btn" onclick="sendAction('ctrld')">&#x2303;D</button>
<button class="qa-btn" onclick="sendAction('escape')">Esc</button>
<button class="qa-btn" onclick="sendAction('tab')">Tab</button>
<button class="qa-btn" onclick="sendAction('arrowUp')">&#x2191;</button>
<button class="qa-btn" onclick="sendAction('arrowDown')">&#x2193;</button>
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
let polling = false, pollErrors = 0, maxPollErrors = 5, activeProject = null;
let drawerOpen = false;

// -- Drawer --
function toggleDrawer() { drawerOpen ? closeDrawer() : openDrawer(); }
function openDrawer() {
  drawerOpen = true;
  $('#drawer').classList.add('open');
  $('#drawer-overlay').classList.add('open');
}
function closeDrawer() {
  drawerOpen = false;
  $('#drawer').classList.remove('open');
  $('#drawer-overlay').classList.remove('open');
}

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
      $('#quick-actions').classList.add('visible');
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
  $('#quick-actions').classList.remove('visible');
  $('#pairing').style.display = '';
  $('#pair-spinner').classList.add('hidden');
  $('#pair-title').textContent = 'Connection Lost';
  $('#pair-desc').textContent = 'The connection to your Mac was lost. Tap Reconnect to try again.';
  $('#btn-retry').textContent = 'Reconnect';
  $('#btn-retry').style.display = '';
  updateHeaderContext();
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
      const repos = getRepoMap();
      if (!activeProject || !repos.has(activeProject)) {
        activeProject = repos.size > 0 ? [...repos.keys()][0] : null;
      }
      renderDrawerList();
      if (!activeSession || !sessions.some(s => s.id === activeSession)) {
        const projSessions = sessions.filter(s => (s.repoName || 'Unknown') === activeProject);
        if (projSessions.length > 0) selectSession(projSessions[0].id);
      }
      updateHeaderContext();
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
function getRepoMap() {
  const repos = new Map();
  sessions.forEach(s => {
    const rn = s.repoName || 'Unknown';
    if (!repos.has(rn)) repos.set(rn, []);
    repos.get(rn).push(s);
  });
  return repos;
}

function updateHeaderContext() {
  const ctx = $('#header-context');
  if (!activeSession) { ctx.textContent = 'No session'; return; }
  const s = sessions.find(s => s.id === activeSession);
  if (s) {
    const label = s.label || s.title || 'Terminal';
    const repo = s.repoName || '';
    ctx.textContent = repo ? repo + ' \\u2022 ' + label : label;
  }
}

function renderDrawerList() {
  const el = $('#drawer-list');
  el.innerHTML = '';
  const repos = getRepoMap();
  const sorted = [...repos.entries()].sort((a, b) => {
    if (a[0] === activeProject) return -1;
    if (b[0] === activeProject) return 1;
    return a[0].localeCompare(b[0]);
  });
  sorted.forEach(([repoName, repoSessions]) => {
    const group = document.createElement('div');
    group.className = 'drawer-repo';

    const header = document.createElement('div');
    header.className = 'drawer-repo-header' + (repoName === activeProject ? ' active' : '');

    const icon = document.createElement('span');
    icon.className = 'drawer-repo-icon';
    icon.textContent = '\\u{1F4C1}';
    header.appendChild(icon);

    const nameSpan = document.createElement('span');
    nameSpan.textContent = repoName;
    header.appendChild(nameSpan);

    const count = document.createElement('span');
    count.className = 'drawer-repo-count';
    count.textContent = repoSessions.length;
    header.appendChild(count);
    group.appendChild(header);

    repoSessions.forEach(s => {
      const item = document.createElement('div');
      item.className = 'drawer-session' + (s.id === activeSession ? ' active' : '');

      const sIcon = document.createElement('span');
      sIcon.className = 'drawer-session-icon';
      sIcon.textContent = '\\u276F';
      item.appendChild(sIcon);

      const label = document.createElement('span');
      label.className = 'drawer-session-label';
      label.textContent = s.label || s.title || 'Terminal';
      item.appendChild(label);
      item.onclick = () => { selectSession(s.id); closeDrawer(); };
      group.appendChild(item);
    });

    el.appendChild(group);
  });
}

function selectSession(id) {
  activeSession = id;
  const s = sessions.find(s => s.id === id);
  if (s) activeProject = s.repoName || 'Unknown';
  renderDrawerList();
  updateHeaderContext();
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
