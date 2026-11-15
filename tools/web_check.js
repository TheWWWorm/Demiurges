'use strict';
// Checks of the browser page's own code (game/web), run with Node 20 or later:
//
//   node tools/web_check.js [--web=<folder with storage.js, files.js, service-worker.js>]
//
// - Cleanups across tabs (files.js, storage.js): a tab whose view of the
//   stored editions is out of date never deletes another tab's import, a
//   running import, or a copy another open tab still reads; with and without
//   Web Locks. The stored files run on a small in-memory IndexedDB.
// - Service worker installs: a compressed response whose Content-Length is
//   smaller than its decoded body is accepted; a body that differs from the
//   manifest, or a short one, is refused.
// - Synchronous reads: a file read front to back takes fewer blocking round
//   trips to the data worker than it has blocks.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WEB = (process.argv.find(arg => arg.startsWith('--web=')) || '').slice(6) || path.join(__dirname, '../game/web');
const failures = [];
function check(ok, what) {
  console.log((ok ? 'PASS: ' : 'FAIL: ') + what);
  if (!ok) failures.push(what);
}
const tick = () => new Promise(resolve => setTimeout(resolve, 0));

// ---- A small IndexedDB: the calls storage.js and files.js make. ----
class KeyRange {
  constructor(lower, upper) { this.lower = lower; this.upper = upper; }
  static bound(lower, upper) { return new KeyRange(lower, upper); }
  includes(key) { return key >= this.lower && key <= this.upper; }
}
function fakeIndexedDB() {
  const stores = new Map();
  // Once `allow` more puts into "files" are done, further ones wait for
  // `hold` (an import paused part-way).
  const state = {hold: null, allow: 0};
  function transaction(names, mode) {
    names = [].concat(names);
    const tx = {error: null, oncomplete: null, onabort: null, onerror: null, pending: 0, aborted: false, done: false};
    const finish = () => {
      if (tx.done || tx.pending) return;
      tx.done = true;
      setTimeout(() => (tx.aborted ? tx.onabort : tx.oncomplete)?.({target: tx}), 0);
    };
    tx.abort = () => { tx.aborted = true; tx.error = Object.assign(new Error('Aborted'), {name: 'AbortError'}); };
    const undo = [];
    const request = (run, wait) => {
      const req = {result: undefined, error: null, onsuccess: null, onerror: null};
      tx.pending++;
      const go = () => {
        if (tx.aborted) { tx.pending--; finish(); return; }
        req.result = run();
        req.onsuccess?.({target: req});
        tx.pending--;
        if (tx.aborted) for (const fn of undo.reverse()) fn();
        setTimeout(finish, 0);
      };
      if (wait) wait.then(() => setTimeout(go, 0)); else setTimeout(go, 0);
      return req;
    };
    tx.objectStore = name => {
      if (!names.includes(name)) throw new Error('Store not in transaction: ' + name);
      const store = stores.get(name);
      const matches = query => [...store.keys()].sort().filter(key => query === undefined || (query instanceof KeyRange ? query.includes(key) : key === query));
      const write = (key, fn) => {
        if (mode !== 'readwrite') throw new Error('Read-only transaction');
        const had = store.has(key), before = store.get(key);
        undo.push(() => { if (had) store.set(key, before); else store.delete(key); });
        fn();
      };
      return {
        get: key => request(() => store.get(key)),
        getAll: () => request(() => matches().map(key => store.get(key))),
        getAllKeys: () => request(() => matches()),
        put: (value, key) => request(() => { write(key, () => store.set(key, value)); return key; },
          name === 'files' && state.hold && state.allow-- <= 0 ? state.hold : null),
        delete: query => request(() => { for (const key of matches(query)) write(key, () => store.delete(key)); }),
      };
    };
    setTimeout(finish, 0);
    return tx;
  }
  const db = {
    createObjectStore: name => { stores.set(name, new Map()); },
    transaction, close() {},
  };
  return {
    stores, state,
    open() {
      const req = {result: db, onsuccess: null, onerror: null, onupgradeneeded: null};
      setTimeout(() => {
        if (!stores.size) req.onupgradeneeded?.();
        req.onsuccess?.();
      }, 0);
      return req;
    },
  };
}

// Web Locks shared by the tabs of one origin.
function fakeLocks() {
  const queues = new Map();
  return {
    request(name, task) {
      const previous = queues.get(name) || Promise.resolve();
      const run = previous.then(() => task());
      queues.set(name, run.catch(() => {}));
      return run;
    },
  };
}

function loadTab(indexedDB, locks) {
  const context = {
    console, indexedDB, IDBKeyRange: KeyRange, crypto: globalThis.crypto, File, Blob, TextDecoder,
    setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {}, performance,
    navigator: locks ? {locks} : {}, document: {getElementById: () => ({})}, structuredClone,
  };
  context.window = context;
  vm.createContext(context);
  for (const name of ['storage.js', 'files.js']) vm.runInContext(fs.readFileSync(path.join(WEB, name), 'utf8'), context, {filename: name});
  const files = context.EtherFiles;
  files.remount = () => {};
  return files;
}

function gameFiles(edition, salt) {
  const names = ['resources/figures.res', 'resources/crfigures.res', 'resources/textures.res', 'resources/regs.res',
    'resources/text.res', edition === 'el1' ? 'campaigns/good.cpg' : 'campaigns/white.cpg'];
  return names.map(name => {
    const file = new File([edition + ':' + name + ':' + salt], name.split('/').pop());
    Object.defineProperty(file, 'webkitRelativePath', {value: 'Game/' + name});
    return file;
  });
}

function importInto(files, edition, salt) {
  return new Promise(resolve => files.importFiles(gameFiles(edition, salt), (kind, message) => {
    if (kind === 'complete' || kind === 'error') resolve({kind, message});
  }));
}

// Every committed edition's index points at files that are all stored.
function intact(db) {
  const meta = db.stores.get('meta'), stored = db.stores.get('files');
  const problems = [];
  for (const [key, value] of meta) {
    if (!key.startsWith('edition:')) continue;
    for (const name of Object.keys(value.files)) if (!stored.has(value.id + '/' + name)) problems.push(key + ' lost ' + name);
  }
  return problems;
}

async function start(files) {
  if (files.startStorage) await files.startStorage(); else await files.loadEditions();
}

async function crossTab(withLocks) {
  const tag = withLocks ? 'Web Locks: ' : 'no Web Locks: ';
  const db = fakeIndexedDB(), locks = withLocks ? fakeLocks() : null;
  const seed = loadTab(db, locks);
  await start(seed);
  check((await importInto(seed, 'el1', 'first')).kind === 'complete', tag + 'the first game is imported');
  // Two tabs open with the first game stored.
  const a = loadTab(db, locks), b = loadTab(db, locks);
  await start(a); await start(b);
  check((await importInto(b, 'el2', 'b')).kind === 'complete', tag + 'tab B imports the second game');
  // Tab A has not seen B's import; it imports the first game again.
  check((await importInto(a, 'el1', 'a')).kind === 'complete', tag + 'tab A re-imports the first game');
  check(intact(db).length === 0, tag + "tab A's cleanup keeps tab B's import of the second game " + intact(db).join(', '));
  check(Object.keys(a.editions).includes('el2'), tag + 'tab A now shows the second game too');
  // Tab A removes the first game.
  await a.forget('el1');
  check(intact(db).length === 0, tag + "tab A's removal keeps tab B's import " + intact(db).join(', '));
  const meta = db.stores.get('meta');
  const firstCopy = [...db.stores.get('files').keys()].filter(key => key.startsWith(b.editions.el1?.id + '/')).length;
  check(!b.editions.el1 || firstCopy > 0, tag + 'the first-game copy tab B still has mounted stays until B lets go of it');
  // An import in progress in tab B while tab A cleans up.
  await importInto(a, 'el1', 'a2');
  db.state.allow = 3;
  db.state.hold = new Promise(resolve => { db.state.release = resolve; });
  const before = db.stores.get('files').size;
  const running = importInto(b, 'el2', 'b2');
  for (let i = 0; i < 50; i++) await tick();
  const partial = db.stores.get('files').size - before;
  await a.forget('el1');
  db.state.release(); db.state.hold = null;
  const result = await running;
  check(result.kind === 'complete', tag + 'tab B finishes its import (' + result.message + ')');
  check(intact(db).length === 0, tag + "a cleanup during tab B's import keeps its files " + intact(db).join(', '));
  check(String(meta.get('edition:el2')?.id) === String(b.editions.el2?.id), tag + 'the stored second-game index is the one tab B committed');
  check(partial > 0, tag + '(the import was paused part-way)');
}

async function staleRecords() {
  const db = fakeIndexedDB(), locks = fakeLocks();
  const a = loadTab(db, locks);
  await start(a);
  if (typeof a.cleanup !== 'function' || !a.startStorage) { check(false, 'stale records: tabs record their imports'); return; }
  // Files of an import whose tab vanished long ago, and of one still running.
  const files = db.stores.get('files'), meta = db.stores.get('meta');
  files.set('gone/resources/regs.res', 'x'); meta.set('import:gone', {owner: 'old', heartbeat: Date.now() - 3600e3});
  files.set('live/resources/regs.res', 'x'); meta.set('import:live', {owner: 'other', heartbeat: Date.now()});
  files.set('orphan/resources/regs.res', 'x');
  await a.exclusive(() => a.cleanup());
  check(!files.has('gone/resources/regs.res') && !meta.has('import:gone'), 'stale records: an abandoned import is removed with its record');
  check(files.has('live/resources/regs.res'), 'stale records: a running import of another tab is kept');
  check(!files.has('orphan/resources/regs.res'), 'stale records: files nothing refers to are removed');
}

// ---- Service worker ----
async function digest(bytes) {
  return Buffer.from(await crypto.subtle.digest('SHA-256', bytes)).toString('hex');
}
async function install(served) {
  const source = fs.readFileSync(path.join(WEB, 'service-worker.js'), 'utf8');
  const manifest = {};
  for (const [name, file] of Object.entries(served)) {
    const hash = await digest(file.expected || file.body);
    manifest[name] = source.includes('HASHES[') ? hash : {sha256: hash, size: (file.expected || file.body).length};
  }
  const listeners = {}, stored = new Map();
  const context = {
    console, URL, Headers, Response, Request, Blob, crypto: globalThis.crypto, Date, Promise,
    self: {registration: {scope: 'https://game.test/'}, location: {origin: 'https://game.test'},
      addEventListener: (type, fn) => { listeners[type] = fn; }, clients: {matchAll: async () => [], claim: async () => {}}},
    caches: {keys: async () => [], open: async () => ({put: async (key, value) => stored.set(String(key), value), match: async () => undefined})},
    fetch: async request => {
      const name = new URL(request.url).pathname.slice(1) || 'index.html';
      const file = served[name];
      return {ok: true, status: 200, type: 'basic', url: request.url, redirected: false, headers: new Headers(file.headers || {}),
        body: new Response(file.body).body};
    },
  };
  vm.createContext(context);
  vm.runInContext(source.replace('@BUILD@', 'check').replace('@FILES@', JSON.stringify(manifest)), context);
  let work;
  listeners.install({waitUntil: promise => { work = promise; }});
  try { await work; return {ok: true, stored}; } catch (error) { return {ok: false, error: error.message}; }
}

async function serviceWorker() {
  const ten = new TextEncoder().encode('0123456789');
  let result = await install({'index.html': {body: ten, headers: {'Content-Encoding': 'gzip', 'Content-Length': '5'}}});
  check(result.ok, 'service worker: a compressed file (Content-Length 5, 10 decoded bytes) is accepted ' + (result.error || ''));
  result = await install({'index.html': {body: ten, headers: {'Content-Length': '10'}}});
  check(result.ok, 'service worker: a plain file of the right size and hash is accepted ' + (result.error || ''));
  result = await install({'index.html': {body: new TextEncoder().encode('0123456780'), expected: ten, headers: {'Content-Length': '10'}}});
  check(!result.ok, 'service worker: a file whose bytes differ from the manifest is refused');
  result = await install({'index.html': {body: ten.slice(0, 6), expected: ten, headers: {'Content-Length': '10'}}});
  check(!result.ok, 'service worker: a short file is refused');
  result = await install({'index.html': {body: ten.slice(0, 6), expected: ten, headers: {'Content-Encoding': 'br'}}});
  check(!result.ok, 'service worker: a short compressed file is refused');
}

// ---- Synchronous reads ----
function readAhead() {
  const files = loadTab(fakeIndexedDB(), null);
  const BLOCK = files.BLOCK, size = 6 * BLOCK + 123;
  const content = new Uint8Array(size).map((_, i) => (i * 7) & 255);
  files.editions = {el2: {id: 'g', files: {'resources/figures.res': {size, offset: 0}}}};
  files.signal = new Int32Array(new SharedArrayBuffer(8));
  files.transfer = new Uint8Array(new SharedArrayBuffer(4 * 1024 * 1024));
  const trips = [];
  // The worker answers at once; each answer is one blocking round trip.
  files.worker = {postMessage({type, offset, length}) {
    if (type !== 'read') return;
    trips.push(length);
    files.transfer.set(content.subarray(offset, offset + length));
    Atomics.store(files.signal, 1, length); Atomics.store(files.signal, 0, 1);
  }};
  let same = true;
  for (let at = 0; at < size; at += BLOCK / 2) {
    const count = Math.min(BLOCK / 2, size - at), bytes = files.read('el2', 'resources/figures.res', at, count);
    same = same && bytes && bytes.every((value, i) => value === content[at + i]);
  }
  check(same, 'reads: a file read front to back comes back unchanged');
  check(trips.length <= 3, `reads: reading 7 blocks front to back takes ${trips.length} blocking round trips (at most 3)`);
  check(Math.max(...trips) <= files.transfer.length, 'reads: no round trip asks for more than the shared buffer holds');
  trips.length = 0; files.cache.clear(); files.cacheBytes = 0; files.lastBlock?.clear();
  files.read('el2', 'resources/figures.res', 5 * BLOCK, 10);
  files.read('el2', 'resources/figures.res', 2 * BLOCK, 10);
  check(trips.length === 2 && trips.every(length => length <= BLOCK), 'reads: scattered reads fetch single blocks');
}

(async () => {
  await crossTab(true);
  await crossTab(false);
  await staleRecords();
  await serviceWorker();
  readAhead();
  console.log(`WEB CHECK: ${failures.length} failure(s)`);
  process.exit(failures.length ? 1 : 0);
})().catch(error => { console.error(error); process.exit(2); });
