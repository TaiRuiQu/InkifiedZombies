'use strict';

(() => {
  const canvas = document.getElementById('canvas');
  const loading = document.getElementById('loading');
  const message = document.getElementById('message');
  const progress = document.getElementById('progress');
  const start = document.getElementById('start');
  const toolbar = document.getElementById('toolbar');
  const config = JSON.parse(document.getElementById('godot-config').textContent);
  const engineUrl = document.querySelector('script[data-engine-url]').dataset.engineUrl;
  const diagnostics = new URLSearchParams(location.search).has('diagnostics');
  const samples = [];
  const errors = [];
  const account = { state: 'loading', signedIn: false, name: '', id: '' };
  let listener;
  let engine;
  let loginPopup = null;

  function notify(event) { if (listener) listener(event); }

  // Center keeps the session in an httpOnly cookie. Only this same-origin page
  // can read it, and the game receives a name plus a short-lived ticket — never
  // the cookie, the CSRF token or any account secret.
  async function readSession() {
    const response = await fetch('/api/auth/session', {
      credentials: 'same-origin',
      cache: 'no-store',
      headers: { Accept: 'application/json' },
    });
    if (response.status === 401) return { user: null, csrf: '' };
    if (!response.ok) throw new Error('session_unavailable');
    const data = await response.json();
    return { user: data && data.user ? data.user : null, csrf: (data && data.csrf_token) || '' };
  }

  function applyAccount(user) {
    const next = user
      ? { state: 'signed-in', signedIn: true, name: String(user.name || ''), id: String(user.id || '') }
      : { state: 'guest', signedIn: false, name: '', id: '' };
    const changed =
      next.state !== account.state || next.name !== account.name || next.id !== account.id;
    Object.assign(account, next);
    if (changed) notify('account');
    return changed;
  }

  async function refreshAccount() {
    try {
      const session = await readSession();
      applyAccount(session.user);
    } catch {
      const changed =
        account.state !== 'unavailable' || account.signedIn || account.name !== '' || account.id !== '';
      Object.assign(account, { state: 'unavailable', signedIn: false, name: '', id: '' });
      if (changed) notify('account');
    }
    return JSON.stringify(account);
  }

  window.InkTideShell = Object.freeze({
    attach(callback) { listener = callback; },
    record(value) { samples.push(JSON.parse(value)); if (samples.length > 120) samples.shift(); },
    getDiagnostics() { return { state: document.body.dataset.state, samples: samples.slice(), errors: errors.slice() }; },
    // Serialised so the engine never depends on JavaScript object layouts.
    getAccount() { return JSON.stringify(account); },
    refreshAccount() { return refreshAccount(); },
    // Opens Center in a popup; the game keeps running and is told when the
    // window closes so it can re-read the session without a reload.
    openLogin() {
      if (loginPopup && !loginPopup.closed) { loginPopup.focus(); return; }
      loginPopup = window.open('/', 'paper-login', 'width=560,height=760');
      if (!loginPopup) { location.assign('/'); return; }
      const timer = setInterval(async () => {
        if (loginPopup && !loginPopup.closed) return;
        clearInterval(timer);
        await refreshAccount();
      }, 1200);
    },
    // Resolves through the engine's JavaScriptBridge callback with a JSON
    // string: {ok, ticket, expires_at, name} or {ok:false, error}.
    requestTicket(callback) {
      (async () => {
        let result;
        try {
          const session = await readSession();
          if (!session.user) result = { ok: false, error: 'login_required' };
          else {
            const response = await fetch('/api/ink-tide/ticket', {
              method: 'POST',
              credentials: 'same-origin',
              cache: 'no-store',
              headers: {
                Accept: 'application/json',
                'Content-Type': 'application/json',
                'X-CSRF-Token': session.csrf,
              },
              body: '{}',
            });
            const data = await response.json().catch(() => ({}));
            result = response.ok && data && data.ticket
              ? {
                  ok: true,
                  ticket: String(data.ticket),
                  expires_at: Number(data.expires_at) || 0,
                  name: String(data.name || ''),
                }
              : { ok: false, error: String((data && data.error) || 'ticket_failed') };
          }
        } catch { result = { ok: false, error: 'network' }; }
        applyAccount(sessionUserFromResult(result, account));
        try { callback(JSON.stringify(result)); } catch { /* bridge already gone */ }
      })();
    },
  });

  function sessionUserFromResult(result, current) {
    // A successful ticket proves a live session; a login_required answer clears it.
    if (result.ok) return { name: result.name || current.name, id: current.id };
    if (result.error === 'login_required') return null;
    return current.signedIn ? { name: current.name, id: current.id } : null;
  }

  refreshAccount();

  function resize() {
    const width = Math.min(innerWidth, innerHeight * 16 / 9);
    const height = width * 9 / 16;
    const scale = Math.min(devicePixelRatio || 1, 1, 1600 / width, 900 / height);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    const targetWidth = Math.max(1, Math.round(width * scale));
    const targetHeight = Math.max(1, Math.round(height * scale));
    if (canvas.width !== targetWidth) canvas.width = targetWidth;
    if (canvas.height !== targetHeight) canvas.height = targetHeight;
  }
  resize();
  addEventListener('resize', resize);
  document.addEventListener('visibilitychange', () => { if (document.hidden) notify('hidden'); });
  document.addEventListener('pointerlockchange', () => {
    document.body.classList.toggle('pointer-locked', !!document.pointerLockElement);
    if (!document.pointerLockElement) notify('pointerlost');
  });
  document.addEventListener('pointerlockerror', () => notify('pointerlost'));
  document.getElementById('fullscreen').addEventListener('click', async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await document.getElementById('stage').requestFullscreen();
      canvas.focus();
    } catch { document.getElementById('fullscreen').textContent = '请使用浏览器全屏'; }
  });
  addEventListener('pagehide', () => { if (engine) engine.requestQuit(); });

  function fail(error) {
    console.error(error);
    document.body.dataset.state = 'failed';
    loading.hidden = false;
    progress.hidden = true;
    message.textContent = error instanceof Error ? error.message : String(error);
    start.disabled = false;
    start.textContent = '重新载入';
    start.onclick = () => location.reload();
  }

  start.onclick = async () => {
    start.disabled = true;
    progress.hidden = false;
    document.body.dataset.state = 'loading';
    message.textContent = '正在铺纸研墨，首次载入稍需片刻…';
    try {
      await new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = engineUrl;
        script.onload = resolve;
        script.onerror = () => reject(new Error('游戏文件未能载入，请检查网络后重试。'));
        document.head.appendChild(script);
      });
      const missing = Engine.getMissingFeatures({ threads: false });
      if (missing.length) throw new Error('当前浏览器缺少 WebGL 2 或 WebAssembly 支持，请使用支持硬件加速的桌面浏览器。');
      const args = diagnostics ? [...(config.args || []), '--', '--web-diagnostics'] : (config.args || []);
      engine = new Engine({ ...config, args, canvas, canvasResizePolicy: 0 });
      await engine.startGame({
        onProgress(current, total) {
          if (total > 0) { progress.max = total; progress.value = current; }
          else progress.removeAttribute('value');
        },
        onPrintError(...parts) {
          const text = parts.join(' ');
          errors.push(text);
          if (errors.length > 50) errors.shift();
          console.error(text);
        },
        onExit(code) { if (code !== 0) fail(new Error('墨境意外结束，请重新载入。')); },
      });
      resize();
      document.body.dataset.state = 'ready';
      loading.hidden = true;
      toolbar.hidden = false;
      canvas.focus();
    } catch (error) { fail(error); }
  };
})();
