import Foundation

// swiftlint:disable line_length
enum MobileWebClient {

    // MARK: - Resource Loading

    private static func loadResource(_ name: String, ext: String) -> String {
        // Try Sources/Zion/Resources/Web/ (SPM flattens subdirectories)
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return ""
    }

    private static var xtermJS: String { loadResource("xterm.min", ext: "js") }
    private static var addonFitJS: String { loadResource("addon-fit.min", ext: "js") }
    private static var xtermCSS: String { loadResource("xterm.min", ext: "css") }

    // MARK: - Zion custom CSS

    private static let customCSS: String = #"""
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

/* -- Header -- */
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

/* -- Drawer -- */
#drawer-overlay{position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:20;opacity:0;pointer-events:none;transition:opacity .25s ease;-webkit-backdrop-filter:blur(2px);backdrop-filter:blur(2px)}
#drawer-overlay.open{opacity:1;pointer-events:auto}
#drawer{position:fixed;top:0;left:0;bottom:0;width:min(300px,80vw);background:var(--surface);border-right:1px solid var(--border);z-index:21;transform:translateX(-100%);transition:transform .25s cubic-bezier(.4,0,.2,1);overflow-y:auto;-webkit-overflow-scrolling:touch;display:flex;flex-direction:column}
#drawer.open{transform:translateX(0)}
#drawer-header{padding:20px 16px 16px;border-bottom:1px solid var(--border);position:relative}
#drawer-header::after{content:'';position:absolute;bottom:0;left:0;right:0;height:2px;background:linear-gradient(90deg,#36f9f6,#ff7edb);opacity:0.35}
#drawer-brand{display:flex;align-items:center;gap:10px}
#drawer-logo{width:28px;height:28px;border-radius:var(--radius-sm)}
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

/* -- xterm container -- */
#terminal-wrap{flex:1;overflow:hidden;position:relative}
#xterm-container{height:100%;width:100%}
.xterm{height:100%!important}
#loading-overlay{display:none;position:absolute;inset:0;z-index:5;background:var(--bg);align-items:center;justify-content:center;flex-direction:column;gap:12px}
#loading-overlay.visible{display:flex}
#loading-overlay .spinner{width:24px;height:24px;border-width:2px}
#loading-label{font-size:12px;color:var(--text3);letter-spacing:0.3px}

/* -- Quick actions -- */
#quick-actions{display:none;padding:8px 16px;background:var(--surface);border-top:1px solid var(--border);overflow-x:auto;-webkit-overflow-scrolling:touch;white-space:nowrap}
#quick-actions.visible{display:flex;gap:6px}
.qa-btn{min-width:44px;min-height:44px;padding:8px 12px;border-radius:var(--radius-sm);border:1px solid var(--border);background:var(--surface2);color:var(--text);font-family:var(--mono);font-size:14px;font-weight:500;cursor:pointer;-webkit-tap-highlight-color:transparent;flex-shrink:0;display:flex;align-items:center;justify-content:center;transition:all .12s}
.qa-btn:active{background:var(--accent);border-color:var(--accent);color:#fff;transform:scale(0.95)}

/* -- Prompt banner -- */
#prompt-banner{display:none;padding:12px 16px;background:var(--accent-subtle);border-top:1px solid rgba(124,58,237,0.3)}
#prompt-banner.visible{display:block}
#prompt-text{font-size:13px;color:var(--accent2);margin-bottom:10px;font-family:var(--mono)}
#prompt-actions{display:flex;gap:8px}
#prompt-actions button{flex:1;padding:10px;border-radius:var(--radius);border:none;font-size:14px;font-weight:600;cursor:pointer;-webkit-tap-highlight-color:transparent;transition:transform .1s}
#prompt-actions button:active{transform:scale(0.97)}
#btn-approve{background:var(--success);color:#fff}
#btn-deny{background:var(--surface2);color:var(--text);border:1px solid var(--border)}
#btn-abort{background:var(--error);color:#fff}

/* -- Input bar -- */
#input-bar{display:flex;gap:8px;padding:10px 16px;background:var(--surface);border-top:1px solid var(--border);padding-bottom:max(10px,env(safe-area-inset-bottom))}
#cmd-input{flex:1;padding:10px 14px;border-radius:var(--radius);border:1px solid var(--border);background:var(--bg);color:var(--text);font-family:var(--mono);font-size:14px;outline:none;-webkit-appearance:none;transition:border-color .15s}
#cmd-input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-subtle)}
#btn-send{padding:10px 18px;border-radius:var(--radius);border:none;background:var(--accent);color:#fff;font-weight:600;font-size:14px;cursor:pointer;-webkit-tap-highlight-color:transparent;transition:transform .1s}
#btn-send:active{transform:scale(0.95)}

/* -- Pairing screen -- */
#pairing{display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;gap:16px;padding:32px}
#pairing h2{font-size:20px;font-weight:700}
#pairing p{color:var(--text2);font-size:14px;text-align:center;max-width:280px;line-height:1.5}
.spinner{width:32px;height:32px;border:3px solid var(--border);border-top-color:var(--accent);border-radius:50%;animation:spin .8s linear infinite}
.spinner.hidden{display:none}
@keyframes spin{to{transform:rotate(360deg)}}
#btn-retry{display:none;padding:12px 24px;border-radius:var(--radius);border:none;background:var(--accent);color:#fff;font-weight:600;font-size:15px;cursor:pointer;-webkit-tap-highlight-color:transparent;margin-top:8px;transition:transform .1s}
#btn-retry:active{transform:scale(0.95)}
#pair-brand{display:flex;align-items:center;gap:10px;margin-bottom:8px}
#pair-logo{width:40px;height:40px;border-radius:12px}
#pair-brand-name{font-size:22px;font-weight:700;background:linear-gradient(135deg,var(--accent2),#36f9f6);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
"""#

    // MARK: - Zion custom JS

    private static let customJS: String = #"""

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

let cryptoKey, sessions = [];
let activeSession = null, activeProject = null;
try { activeSession = sessionStorage.getItem('zion_activeSession'); activeProject = sessionStorage.getItem('zion_activeProject'); } catch(e) {}
let polling = false, pollErrors = 0, maxPollErrors = 15, _retryCount = 0;
let drawerOpen = false, wasDisconnected = false;

// -- xterm.js --
let term = null, fitAddon = null;
const sessionBuffers = {};
let pendingScreenUpdate = null;

function initTerminal() {
    if (typeof Terminal === 'undefined') return;
    term = new Terminal({
        cursorBlink: true,
        fontSize: 13,
        fontFamily: "'SF Mono', SFMono-Regular, Menlo, monospace",
        scrollback: 1000,
        theme: {
            background: '#110b1f',
            foreground: '#e8e4f0',
            cursor: '#7c3aed',
            selectionBackground: 'rgba(124,58,237,0.35)',
            black: '#1a1229', red: '#e05252', green: '#4dcc7a',
            yellow: '#e6a23c', blue: '#7c3aed', magenta: '#a78bfa',
            cyan: '#36f9f6', white: '#e8e4f0',
            brightBlack: '#6b5f80', brightRed: '#ff7edb',
            brightGreen: '#4dcc7a', brightYellow: '#e6a23c',
            brightBlue: '#a78bfa', brightMagenta: '#ff7edb',
            brightCyan: '#36f9f6', brightWhite: '#ffffff'
        }
    });
    fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);
    term.open($('#xterm-container'));
    fitAddon.fit();
    new ResizeObserver(() => fitAddon && fitAddon.fit())
        .observe($('#xterm-container'));

    // Flush deferred screen update when user scrolls back to bottom (DOM event = touch/swipe)
    const viewport = term.element.querySelector('.xterm-viewport');
    if (viewport) {
        viewport.addEventListener('scroll', () => {
            const buf = term.buffer.active;
            const atBottom = (buf.baseY === 0) || (buf.viewportY >= buf.baseY);
            if (atBottom && pendingScreenUpdate) {
                const raw = pendingScreenUpdate;
                pendingScreenUpdate = null;
                term.scrollToBottom();
                term.write('\n'.repeat(term.rows));
                term.write('\x1b[H\x1b[2J');
                term.write(raw);
            }
        });
    }
}

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
  pollErrors = 0;
  polling = false;
  wasDisconnected = false;
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
      _retryCount = 0;
      setStatus('connected', 'Connected');
      $('#pairing').style.display = 'none';
      $('#xterm-container').style.display = '';
      $('#input-bar').style.display = '';
      $('#quick-actions').classList.add('visible');
      initTerminal();
      startPolling();
    } else {
      showRetry('Pairing Failed', (data.error || 'Unknown error') + '. Tap to retry.');
    }
  } catch(e) {
    showRetry('Connection Failed', e.message + '. Tap to retry.');
    _retryCount = (_retryCount || 0) + 1;
    if (_retryCount < 5) {
      setTimeout(connect, 3000);
    }
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

const TUNNEL_DEAD_CODES = new Set([502, 503, 530, 539]);

async function poll() {
  if (!polling) return;
  try {
    const res = await fetch(BASE + '/poll?t=' + TOKEN);
    if (!res.ok) {
      if (TUNNEL_DEAD_CODES.has(res.status)) {
        polling = false;
        showTunnelExpired();
        return;
      }
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
  wasDisconnected = true;
  // If page is hidden (phone sleep / background tab), don't nuke the UI —
  // visibilitychange will auto-reconnect when the user comes back.
  if (document.hidden) {
    setStatus('connecting', 'Reconnecting\u2026');
    return;
  }
  // Page is visible and we still lost connection — try auto-reconnect once
  setStatus('connecting', 'Reconnecting\u2026');
  silentReconnect();
}

function silentReconnect() {
  pollErrors = 0;
  polling = false;
  fetch(BASE + '/pair?t=' + TOKEN)
    .then(r => {
      if (TUNNEL_DEAD_CODES.has(r.status)) { showTunnelExpired(); throw null; }
      return r.json();
    })
    .then(data => {
      if (!data) return;
      if (data.status === 'paired') {
        wasDisconnected = false;
        setStatus('connected', 'Connected');
        startPolling();
      } else {
        showFullDisconnect();
      }
    })
    .catch(e => { if (e !== null) showFullDisconnect(); });
}

function showFullDisconnect() {
  setStatus('error', 'Disconnected');
  $('#xterm-container').style.display = 'none';
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

function showTunnelExpired() {
  wasDisconnected = false;
  polling = false;
  setStatus('error', 'Tunnel Expired');
  $('#xterm-container').style.display = 'none';
  $('#input-bar').style.display = 'none';
  $('#quick-actions').classList.remove('visible');
  $('#pairing').style.display = '';
  $('#pair-spinner').classList.add('hidden');
  $('#pair-title').textContent = 'Tunnel Expired';
  $('#pair-desc').textContent = 'The Cloudflare tunnel is no longer active. Open Zion Settings on your Mac and re-scan the QR code to reconnect.';
  $('#btn-retry').textContent = 'Retry';
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
      } else {
        selectSession(activeSession);
      }
      updateHeaderContext();
      break;
    case 'screenUpdate': {
      const sid = p.sessionID;
      const raw = p.data ? Uint8Array.from(atob(p.data), c => c.charCodeAt(0))
                         : new Uint8Array(0);

      if (raw.length > 0) {
        // Store latest snapshot for session switching
        sessionBuffers[sid] = [raw];
        if (sid === activeSession) $('#loading-overlay').classList.remove('visible');

        if (sid === activeSession && term) {
          const buf = term.buffer.active;
          const atBottom = (buf.baseY === 0) || (buf.viewportY >= buf.baseY);

          if (!atBottom) {
            // User is reading scrollback — defer the update
            pendingScreenUpdate = raw;
          } else {
            pendingScreenUpdate = null;
            // Push current visible content into scrollback
            term.scrollToBottom();
            term.write('\n'.repeat(term.rows));
            // Clear visible area, cursor home, write new snapshot
            term.write('\x1b[H\x1b[2J');
            term.write(raw);
          }
        }
      }
      if (p.hasPrompt && p.promptText) showPrompt(p.promptText);
      break;
    }
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
    const label = s.branchName || s.label || s.title || 'Terminal';
    const repo = s.repoName || '';
    ctx.textContent = repo ? repo + ' \u2022 ' + label : label;
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
    icon.textContent = '\u{1F4C1}';
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
      sIcon.textContent = '\u276F';
      item.appendChild(sIcon);

      const label = document.createElement('span');
      label.className = 'drawer-session-label';
      label.textContent = s.branchName || s.label || s.title || 'Terminal';
      item.appendChild(label);
      item.onclick = () => { selectSession(s.id, true); closeDrawer(); };
      group.appendChild(item);
    });

    el.appendChild(group);
  });
}

function selectSession(id, userInitiated) {
  activeSession = id;
  const s = sessions.find(s => s.id === id);
  if (s) activeProject = s.repoName || 'Unknown';
  try { sessionStorage.setItem('zion_activeSession', id); sessionStorage.setItem('zion_activeProject', activeProject); } catch(e) {}
  renderDrawerList();
  updateHeaderContext();
  if (term) {
    term.reset();
    const chunks = sessionBuffers[id] || [];
    for (const chunk of chunks) term.write(chunk);
    if (chunks.length === 0 && userInitiated) {
      $('#loading-overlay').classList.add('visible');
      sendAction('refreshScreen');
    }
  }
  hidePrompt();
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
  const b64 = btoa(String.fromCharCode(...encrypted));
  const endpoint = msg.type === 'sendAction' ? '/action' : '/input';
  await fetch(BASE + endpoint + '?t=' + TOKEN, {method:'POST', body: b64});
}

async function sendInput() {
  const input = $('#cmd-input');
  const text = input.value;
  if (!text || !activeSession) return;
  input.value = '';

  const payload = btoa(JSON.stringify({text: text + '\r'}));
  await sendEncrypted({
    type: 'sendInput',
    sessionID: activeSession,
    payload: payload,
    timestamp: new Date().toISOString()
  });
  // Trigger immediate poll so the user sees their input echo without waiting 500ms
  scheduleEagerPoll();
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
  scheduleEagerPoll();
}

// After user input, poll aggressively for a short burst to pick up the echo quickly.
// Fires 3 rapid polls (150ms apart) then falls back to normal 500ms cadence.
let eagerPollTimer = null;
function scheduleEagerPoll() {
  if (eagerPollTimer) return; // already in eager mode
  let remaining = 3;
  eagerPollTimer = setInterval(() => {
    if (--remaining <= 0 || !polling) {
      clearInterval(eagerPollTimer);
      eagerPollTimer = null;
      return;
    }
    poll();
  }, 150);
}

$('#cmd-input').addEventListener('keydown', e => {
  if (e.key === 'Enter') { e.preventDefault(); sendInput(); }
});

// Auto-reconnect when phone wakes up or tab becomes visible again
document.addEventListener('visibilitychange', () => {
  if (document.hidden || !wasDisconnected) return;
  silentReconnect();
});

connect();
"""#

    // MARK: - HTML body

    private static let htmlBody: String = #"""

<div id="app">
<header>
<button id="menu-btn" onclick="toggleDrawer()" aria-label="Menu">&#9776;</button>
<div id="header-info">
<div id="header-title">Zion Remote</div>
<div id="header-context">No session</div>
</div>
<span id="status" class="connecting" aria-live="polite">Connecting</span>
</header>

<div id="drawer-overlay" onclick="closeDrawer()"></div>
<nav id="drawer" role="navigation">
<div id="drawer-header">
<div id="drawer-brand"><img id="drawer-logo" src="data:image/png;base64,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" alt="Zion" width="28" height="28"><h2>Zion</h2></div>
<div id="drawer-subtitle">Remote Terminal Access</div>
</div>
<div id="drawer-list"></div>
</nav>

<div id="terminal-wrap">
<div id="pairing">
<div id="pair-brand"><img id="pair-logo" src="data:image/png;base64,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" alt="Zion" width="40" height="40" style="border-radius:12px"><span id="pair-brand-name">Zion</span></div>
<div class="spinner" id="pair-spinner"></div>
<h2 id="pair-title">Connecting...</h2>
<p id="pair-desc">Establishing secure connection to your Mac</p>
<button id="btn-retry" onclick="retryConnect()">Refresh</button>
</div>
<div id="loading-overlay"><div class="spinner"></div><span id="loading-label">Loading terminal…</span></div>
<div id="xterm-container" style="display:none"></div>
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
<button class="qa-btn" onclick="sendAction('ctrlc')" aria-label="Control C">&#x2303;C</button>
<button class="qa-btn" onclick="sendAction('ctrld')" aria-label="Control D">&#x2303;D</button>
<button class="qa-btn" onclick="sendAction('escape')" aria-label="Escape">Esc</button>
<button class="qa-btn" onclick="sendAction('tab')" aria-label="Tab">Tab</button>
<button class="qa-btn" onclick="sendAction('arrowUp')" aria-label="Arrow Up">&#x2191;</button>
<button class="qa-btn" onclick="sendAction('arrowDown')" aria-label="Arrow Down">&#x2193;</button>
</div>
<div id="input-bar" style="display:none">
<input id="cmd-input" type="text" placeholder="Type command..." autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">
<button id="btn-send" onclick="sendInput()">Send</button>
</div>
</div>
"""#

    // MARK: - Composed HTML page

    static var html: String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <title>Zion Remote</title>
        <style>\(xtermCSS)</style>
        <style>\(customCSS)</style>
        </head>
        <body>
        \(htmlBody)
        <script>\(xtermJS)</script>
        <script>\(addonFitJS)</script>
        <script>\(customJS)</script>
        </body>
        </html>
        """
    }
}
// swiftlint:enable line_length
