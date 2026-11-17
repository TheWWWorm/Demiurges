'use strict';
// Filled in with content hashes and the engine files by the Web build tool.
const ENGINE_CACHE = 'demiurges-engine-c448dd736bae2c13f98f';
// Hosts may redirect /index.html to / (Cloudflare Workers assets do). A
// redirected response must never answer a navigation (the browser fails it
// with ERR_FAILED), so the shell is fetched and stored as "./".
const SHELL = new URL('./', self.registration.scope).href;
// File name → {sha256, size} of the file as served, after any Content-Encoding
// is undone. Every copy is checked against it before it is kept.
const FILES = {
"data-worker.js": {
"sha256": "62d9c0fc3917459464fab4304f6a4b5ce525011ef0afc3ed9654e13438b91af3",
"size": 1966
},
"files.js": {
"sha256": "398d2d3b94dc2b988c314b188c4bcb86ef267b8ab7964ffe7a8e9be0d8ead997",
"size": 22794
},
"icon-192.png": {
"sha256": "62440aed6b7263fa98d316db93423a69b5e3d127844872384e02925b36a801d0",
"size": 81455
},
"icon-512.png": {
"sha256": "9ffa86720b0997856478278990e0395a61b9aca5fbcf9a8402b9ed31ef25d6df",
"size": 376564
},
"index.apple-touch-icon.png": {
"sha256": "440793e743834e2364f1919a43961fd4fea426e4fa6ce83290b38394507bc9bb",
"size": 72189
},
"index.audio.position.worklet.js": {
"sha256": "be33985bc7160d6bf9646f259cd86b259cd67b02ccb297ee5c44f8ac84327bc8",
"size": 2973
},
"index.audio.worklet.js": {
"sha256": "5b476a9c9ce642c0ee4256436d1bc31d9c38f868aca0f9a8e2a57c18d2dec2a3",
"size": 7298
},
"index.html": {
"sha256": "53d3e153ab746295b4a3f21ce6f98edc26053bd94b74bcf918660ba2565ff5f0",
"size": 5716
},
"index.icon.png": {
"sha256": "06769b275998dd9bca332d7694dd8a951c8df213156af045567598f55de3b1dc",
"size": 375916
},
"index.js": {
"sha256": "63795a00d4edd57a3896618ade5b12d063684a41c1e39ee3ade00de7362d9da5",
"size": 279833
},
"index.pck": {
"sha256": "85d46074929939812415842d644a981d4c8c0cdbf605e1afc370f8d0425299cd",
"size": 17118460
},
"index.png": {
"sha256": "fe70f220ab59b7a0bbbb3128edf94d6676254762eec168899b1c4de8f6e76ea5",
"size": 474480
},
"index.wasm": {
"sha256": "7eda98958eb09135a1acb54a4323a00b1a55af1997f15fa1cdc2b93e3df46656",
"size": 39509339
},
"installer-worker.js": {
"sha256": "32abae13d4e3491ccfa627435c1bacb63f28e4422c4debe6b7097a5f3be38192",
"size": 16178
},
"manifest.webmanifest": {
"sha256": "91bb1425a9391403fbded910f0f2899bd8e440a804e14590775a806235093b01",
"size": 478
},
"storage.js": {
"sha256": "4baf8da2822b9c10af759ce5c56e7f9d6148c1d493312d15cb2eb82fac62d2a9",
"size": 5345
}
};
const NAMES = Object.keys(FILES);
const ENGINE_FILES = NAMES.map(name => name === 'index.html' ? SHELL : new URL(name, SHELL).href);
let progress = {type: 'progress', loaded: 0, total: 0};
let lastBroadcast = 0;

async function broadcast(force) {
  if (!force && Date.now() - lastBroadcast < 150) return;
  lastBroadcast = Date.now();
  for (const client of await self.clients.matchAll({type: 'window', includeUncontrolled: true}))
    client.postMessage(progress);
}

async function sha256(blob) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())),
    b => b.toString(16).padStart(2, '0')).join('');
}

// An unchanged file (same SHA-256) is taken from the previous version's cache,
// so an update only downloads what changed.
async function reuse(url, hash) {
  for (const key of await caches.keys()) {
    if (!key.startsWith('demiurges-engine-') || key === ENGINE_CACHE) continue;
    const old = await (await caches.open(key)).match(url);
    if (!old || old.redirected || old.type !== 'basic' && old.type !== 'default' || !old.ok) continue;
    const blob = await old.blob();
    if (await sha256(blob) !== hash) continue;
    const headers = new Headers(old.headers);
    headers.delete('Content-Encoding');
    headers.set('Content-Length', String(blob.size));
    return new Response(blob, {status: 200, statusText: 'OK', headers});
  }
  return null;
}

// A plain stored copy: never marked redirected, body already decoded, with
// the real Content-Length so the engine's loader shows true progress.
async function request(url, i) {
  const file = FILES[NAMES[i]];
  const kept = await reuse(url, file.sha256).catch(() => null);
  if (kept) return {kept};
  const response = await fetch(new Request(url, {cache: 'no-cache', credentials: 'same-origin'}));
  if (!response.ok || response.type !== 'basic') throw new Error('Could not download ' + url + ' (' + response.status + ')');
  return {response, file, length: file.size};
}
async function receive({kept, response, file}) {
  if (kept) return kept;
  const reader = response.body.getReader(), parts = [];
  let size = 0;
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    parts.push(value); size += value.length; progress.loaded += value.length;
    broadcast(false);
  }
  // The body arrives decoded, so a Content-Length describes it only when no
  // Content-Encoding was applied; the manifest has the decoded size and hash.
  const sent = Number(response.headers.get('Content-Length')) || 0;
  if (size !== file.size || !response.headers.has('Content-Encoding') && sent && sent !== size)
    throw new Error('Incomplete download: ' + response.url);
  const blob = new Blob(parts);
  if (await sha256(blob) !== file.sha256) throw new Error('Damaged or outdated download: ' + response.url);
  const headers = new Headers(response.headers);
  headers.delete('Content-Encoding');
  headers.set('Content-Length', String(size));
  return new Response(blob, {status: 200, statusText: 'OK', headers});
}

self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(ENGINE_CACHE);
  // All headers first, so the total (Content-Length) is known before progress is shown.
  const started = await Promise.all(ENGINE_FILES.map(request));
  for (const file of started) progress.total += file.length || 0;
  const copies = await Promise.all(started.map(receive));
  await Promise.all(copies.map((response, i) => cache.put(ENGINE_FILES[i], response)));
  progress.done = true; await broadcast(true);
  // Existing games keep their worker until all their tabs close. A page the
  // old worker failed to load is not a client, so this one then takes over.
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const key of await caches.keys())
    if (key.startsWith('demiurges-engine-') && key !== ENGINE_CACHE) await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener('message', event => {
  // A page loaded without the worker (e.g. a forced reload) asks to be controlled;
  // a page opened during the install asks for the download progress.
  if (event.data === 'claim') event.waitUntil(self.clients.claim());
  else if (event.data === 'progress' && event.source) event.source.postMessage(progress);
});
self.addEventListener('fetch', event => {
  const request = event.request, url = new URL(request.url);
  if (url.origin !== self.location.origin || request.method !== 'GET') return;
  let key = request;
  if (request.mode === 'navigate') {
    // Only the game page comes from the cache; other documents (the licence
    // files) load normally.
    const path = url.pathname, root = new URL(SHELL).pathname;
    if (path !== root && path !== root + 'index.html') return;
    key = SHELL;
  }
  // Only packaged engine files are cached. Private game files are read inside
  // data-worker.js and never requested from the network.
  event.respondWith((async () => {
    const cache = await caches.open(ENGINE_CACHE);
    const cached = await cache.match(key, {ignoreSearch: request.mode === 'navigate'});
    if (cached && !cached.redirected && cached.type !== 'opaqueredirect') return cached;
    const response = await fetch(request);
    // fetch() follows redirects for subresources; such a response is only
    // valid for them, never for a navigation.
    if (request.mode === 'navigate' && response.redirected)
      return new Response(response.body, {status: response.status, statusText: response.statusText, headers: response.headers});
    return response;
  })());
});
