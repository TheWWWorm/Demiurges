'use strict';
// Filled in with content hashes and the engine files by the Web build tool.
const ENGINE_CACHE = 'demiurges-engine-86559d309ec62ac4610b';
// Hosts may redirect /index.html to / (Cloudflare Workers assets do). A
// redirected response must never answer a navigation (the browser fails it
// with ERR_FAILED), so the shell is fetched and stored as "./".
const SHELL = new URL('./', self.registration.scope).href;
const HASHES = {
"data-worker.js": "12d7e9d71fb7aac25c4bd9979ec5be964a62367254a9165d95c9faf1177a7210",
"files.js": "24beb83161a5a2579d031b630e6bcf5a9942054e0fae0eca3db17a4598c5d44e",
"icon-192.png": "fba2a1638683eb6eb1d50d749d66b6979284bc20f1717d89e938b20425b94faa",
"icon-512.png": "ee1cb3780be7c116240b4325c217be6e8b2364d99b14625a0aabbdd2ca237199",
"index.apple-touch-icon.png": "669e2e128a64840b0239fec21a5bf56a4eb08c4b2249434b11cded2cc19e5c7d",
"index.audio.position.worklet.js": "be33985bc7160d6bf9646f259cd86b259cd67b02ccb297ee5c44f8ac84327bc8",
"index.audio.worklet.js": "5b476a9c9ce642c0ee4256436d1bc31d9c38f868aca0f9a8e2a57c18d2dec2a3",
"index.html": "09b9b34654afe45328a8f32a7aec452c1b1e2326905db3f85857c070fa0523e3",
"index.icon.png": "547dcc86d6ab20ea575d034b766e551d32962b0698ac099526f8ce21e67ffd0e",
"index.js": "63795a00d4edd57a3896618ade5b12d063684a41c1e39ee3ade00de7362d9da5",
"index.pck": "6fdb195cdde321fb0b930372b9770b89483f6d8c8ffc1198e7ec5e517b6cb8ac",
"index.png": "40daf98dde7cd683876b417ef12e3adcf5cb19ad95c531a6cee5714387d27673",
"index.wasm": "7eda98958eb09135a1acb54a4323a00b1a55af1997f15fa1cdc2b93e3df46656",
"installer-worker.js": "8bc8a5ab27aaa5389bfc9dc83484c5e7682ddf4e693aac23836f0689f35783f6",
"manifest.webmanifest": "91bb1425a9391403fbded910f0f2899bd8e440a804e14590775a806235093b01",
"storage.js": "8998b34b6e0544c99a6f72eb54b90aaea94a4f219ec43d28520cb391fff57446"
};   // file name → SHA-256
const ENGINE_FILES = Object.keys(HASHES).map(name => name === 'index.html' ? SHELL : new URL(name, SHELL).href);
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
  const kept = await reuse(url, HASHES[Object.keys(HASHES)[i]]).catch(() => null);
  if (kept) return {kept};
  const response = await fetch(new Request(url, {cache: 'no-cache', credentials: 'same-origin'}));
  if (!response.ok || response.type !== 'basic') throw new Error('Could not download ' + url + ' (' + response.status + ')');
  return {response, length: Number(response.headers.get('Content-Length')) || 0};
}
async function receive({kept, response, length}) {
  if (kept) return kept;
  const reader = response.body.getReader(), parts = [];
  let size = 0;
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    parts.push(value); size += value.length; progress.loaded += value.length;
    if (!length) progress.total += value.length;
    broadcast(false);
  }
  if (length && size !== length) throw new Error('Incomplete download: ' + response.url);
  const headers = new Headers(response.headers);
  headers.delete('Content-Encoding');
  headers.set('Content-Length', String(size));
  return new Response(new Blob(parts), {status: 200, statusText: 'OK', headers});
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
