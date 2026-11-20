// The web side of Python on phones: a small page that CodeNote keeps open
// in an invisible web view, and a worker per note that runs Pyodide (Python
// compiled to WebAssembly). Served by the app's own server on 127.0.0.1.
//
// Messages:
//   app -> page   codenote.receive({op: start|run|input|interrupt|stop, kernel, ...})
//   page -> app   CodeNoteKernel.postMessage(JSON {kernel, t: ready|line|file|died, ...})
//   worker lines use CodeNote's usual markers (count, done, image, table,
//   missing), so the app reads them like the desktop kernel's output.

/// The page in the web view: starts one worker per note and passes
/// messages. With cross-origin isolation (the server sends the headers),
/// shared memory lets Interrupt stop a block and input() wait for an
/// answer; without it, Interrupt restarts the kernel.
const pyodideHostHtml = r'''<!doctype html>
<html><head><meta charset="utf-8"><title>CodeNote Python</title></head>
<body>
<script>
(function () {
  var send = function (m) {
    try { CodeNoteKernel.postMessage(JSON.stringify(m)); } catch (e) { console.log('no channel', e); }
  };
  var isolated = !!(self.crossOriginIsolated && typeof SharedArrayBuffer !== 'undefined');
  var kernels = {};

  function start(id) {
    var w = new Worker('worker.js', { type: 'module' });
    var k = {
      w: w,
      intr: isolated ? new Int32Array(new SharedArrayBuffer(4)) : null,
      // A second flag only CodeNote reads: Pyodide clears its own one
      // while time.sleep runs.
      stop: isolated ? new Int32Array(new SharedArrayBuffer(4)) : null,
      stdin: isolated ? new SharedArrayBuffer(8 + 65536) : null
    };
    w.onmessage = function (e) {
      var m = e.data; m.kernel = id; send(m);
      if (m.t === 'died') delete kernels[id];
    };
    w.onerror = function (e) {
      send({ kernel: id, t: 'died', error: String((e && e.message) || e) });
      delete kernels[id];
    };
    w.postMessage({ op: 'init', base: new URL('./', location.href).href,
                    intr: k.intr ? k.intr.buffer : null, stop: k.stop ? k.stop.buffer : null,
                    stdin: k.stdin, isolated: isolated });
    kernels[id] = k;
  }

  window.codenote = {
    receive: function (m) {
      var k = kernels[m.kernel];
      switch (m.op) {
        case 'start': if (!k) start(m.kernel); break;
        case 'run': if (k) k.w.postMessage(m); break;
        case 'interrupt':
          if (!k) break;
          if (k.intr) { k.stop[0] = 1; k.intr[0] = 2; }
          else { k.w.terminate(); delete kernels[m.kernel]; send({ kernel: m.kernel, t: 'died', error: 'interrupted' }); }
          break;
        case 'input':
          if (!k || !k.stdin) break;
          var bytes = new TextEncoder().encode(m.text);
          var head = new Int32Array(k.stdin, 0, 2);
          var body = new Uint8Array(k.stdin, 8);
          var n = Math.min(bytes.length, body.length);
          body.set(bytes.subarray(0, n));
          head[1] = n;
          Atomics.store(head, 0, 1);
          Atomics.notify(head, 0);
          break;
        case 'stop':
          if (k) { k.w.terminate(); delete kernels[m.kernel]; }
          break;
      }
    }
  };
  send({ t: 'host', isolated: isolated });
})();
</script>
</body></html>
''';

/// One note's kernel: loads Pyodide and CodeNote's Python helpers, loads
/// the packages a block imports (only ones the person downloaded), and runs
/// blocks one at a time.
const pyodideWorkerJs = r'''
var MARK = '\x1ecodenote:';
var RICH = /^\x1ecodenote:(image|table|markdown|html):([^|]*)/;
var py = null, lock = null, importMap = {}, state = { packages: [], pypi: [] };
var loaded = new Set(), queue = [], busy = false, base = '', stdinBuf = null, intr = null, stop = null;

function post(m) { self.postMessage(m); }

// Python's patched time.sleep asks this between short naps.
self.codenoteInterrupted = function () {
  if (stop && stop[0] === 1) { stop[0] = 0; if (intr) intr[0] = 0; return true; }
  return false;
};

function b64(bytes) {
  var s = '';
  for (var i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

function out(text, isErr) {
  var m = RICH.exec(text);
  if (m && py) {
    try { post({ t: 'file', path: m[2], data: b64(py.FS.readFile(m[2])) }); } catch (e) {}
  }
  post({ t: 'line', text: (isErr ? '\u0000' : '') + text });
}

function readStdin() {
  if (!stdinBuf) throw new Error("input() needs a newer Android System WebView on this phone.");
  var head = new Int32Array(stdinBuf, 0, 2);
  Atomics.store(head, 0, 0);
  Atomics.wait(head, 0, 0);
  var n = head[1];
  var text = new TextDecoder().decode(new Uint8Array(stdinBuf, 8, n).slice());
  return text + '\n';
}

function norm(name) { return String(name).toLowerCase().replace(/[-_.]+/g, '-'); }

async function refreshState() {
  try { state = await (await fetch(base + 'state.json', { cache: 'no-store' })).json(); } catch (e) {}
}

// Lock packages a block needs (with their dependencies), plus names that
// are neither in the lock nor importable: those come from PyPI.
function closure(names) {
  var seen = new Set(), stack = names.slice();
  while (stack.length) {
    var n = stack.pop();
    if (seen.has(n) || !lock.packages[n]) continue;
    seen.add(n);
    (lock.packages[n].depends || []).forEach(function (d) { stack.push(d); });
  }
  return Array.from(seen);
}

async function ensure(code) {
  var wanted = [], unknown = [];
  var imports = [];
  try { imports = py.pyimport('pyodide.code').find_imports(code).toJs(); } catch (e) {}
  var have = new Set(state.packages);
  var pypiNames = new Set(state.pypi.map(function (p) { return norm(p.name); }));
  var finder = py.pyimport('importlib.util').find_spec;
  imports.forEach(function (imp) {
    var top = String(imp).split('.')[0];
    if (importMap[top]) { wanted.push(importMap[top]); return; }
    var found = null;
    try { found = finder(top); } catch (e) {}
    if (found === undefined || found === null) { if (!pypiNames.has(norm(top))) unknown.push(top); }
    if (found && found.destroy) found.destroy();
  });
  var pip = /^\s*%pip\s+install\s+(.+)$/gm, m;
  while ((m = pip.exec(code))) {
    m[1].split(/\s+/).forEach(function (n) {
      if (!n || n[0] === '-') return;
      n = n.split(/[<>=!~\[;]/)[0];
      var k = norm(n);
      var inLock = Object.keys(lock.packages).filter(function (x) { return norm(x) === k; })[0];
      if (inLock) wanted.push(inLock);
      else if (!pypiNames.has(k)) unknown.push(n);
    });
  }
  var all = closure(wanted);
  var missing = all.filter(function (n) { return !have.has(n); }).concat(unknown);
  if (missing.length) return { missing: Array.from(new Set(missing)) };
  var toLoad = all.filter(function (n) { return !loaded.has(n); });
  if (toLoad.length) {
    post({ t: 'line', text: '\u0001Loading ' + toLoad.join(', ') + '…' });
    await py.loadPackage(toLoad, { messageCallback: function () {}, errorCallback: function (t) { out(t, true); } });
    toLoad.forEach(function (n) { loaded.add(n); });
    post({ t: 'line', text: '\u0001' });
  }
  return {};
}

async function loadPypi() {
  var urls = state.pypi.filter(function (p) { return !loaded.has('pypi:' + p.file); })
                       .map(function (p) { return base + 'files/pypi/' + encodeURIComponent(p.file); });
  if (!urls.length) return;
  // PyPI packages may import lock packages at import time: load what they need.
  var deps = closure(state.pypi.reduce(function (a, p) { return a.concat(p.lockDeps || []); }, [])).filter(function (n) {
    return !loaded.has(n) && state.packages.indexOf(n) >= 0;
  });
  if (deps.length) { await py.loadPackage(deps, { messageCallback: function () {} }); deps.forEach(function (n) { loaded.add(n); }); }
  await py.loadPackage(urls, { messageCallback: function () {} });
  state.pypi.forEach(function (p) { loaded.add('pypi:' + p.file); });
}

async function pump() {
  if (busy || !queue.length || !py) return;
  busy = true;
  var m = queue.shift();
  try {
    await refreshState();
    var r = await ensure(m.code);
    if (r.missing) {
      post({ t: 'line', text: MARK + 'missing:' + r.missing.join(',') });
      post({ t: 'line', text: MARK + 'done:' + m.cell + ':error' });
    } else {
      await loadPypi();
      if (intr) intr[0] = 0;
      if (stop) stop[0] = 0;
      var run = py.pyimport('codenote_kernel').run_cell_async;
      await run(m.cell, m.code);
      run.destroy();
    }
  } catch (e) {
    out(String(e && e.message || e), true);
    post({ t: 'line', text: MARK + 'done:' + m.cell + ':error' });
  }
  busy = false;
  pump();
}

async function init(m) {
  base = m.base;
  stdinBuf = m.stdin;
  try {
    var mod = await import(base + 'files/pyodide.mjs');
    lock = await (await fetch(base + 'files/pyodide-lock.json')).json();
    Object.keys(lock.packages).forEach(function (name) {
      (lock.packages[name].imports || []).forEach(function (imp) { importMap[imp] = name; });
    });
    py = await mod.loadPyodide({
      indexURL: base + 'files/',
      stdout: function (t) { out(t, false); },
      stderr: function (t) { out(t, true); }
    });
    if (m.intr) { intr = new Int32Array(m.intr); py.setInterruptBuffer(intr); }
    if (m.stop) stop = new Int32Array(m.stop);
    py.setStdin({ stdin: readStdin });
    var helpers = await (await fetch(base + 'helpers.json')).json();
    py.FS.mkdirTree('/home/pyodide/.codenote/py');
    Object.keys(helpers).forEach(function (name) {
      py.FS.writeFile('/home/pyodide/.codenote/py/' + name, helpers[name]);
    });
    py.runPython([
      'import os, sys',
      "sys.path.insert(0, '/home/pyodide/.codenote/py')",
      "os.environ['CODENOTE_OUT'] = '/home/pyodide/.codenote/out'",
      "os.environ['MPLBACKEND'] = 'module://codenote_mpl'",
      'import codenote_kernel'
    ].join('\n'));
    await refreshState();
    post({ t: 'ready', version: py.runPython("import sys; sys.version.split()[0]") });
    pump();
  } catch (e) {
    post({ t: 'died', error: String(e && e.message || e) });
  }
}

self.onmessage = function (e) {
  var m = e.data;
  if (m.op === 'init') init(m);
  else if (m.op === 'run') { queue.push(m); pump(); }
};
''';
