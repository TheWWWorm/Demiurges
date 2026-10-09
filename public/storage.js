'use strict';
// Shared by the page (files.js) and its workers. The player's game files live
// in IndexedDB: "files" holds their contents under "<import id>/<path>" (or
// "<import id>/pack" for a data pack), "meta" holds one index per edition.
const DATA_DB = 'demiurges-data-v1';
const EDITIONS = ['el1', 'el2'];
// Files every edition needs; the campaign file tells the editions apart.
const REQUIRED_DATA = ['resources/figures.res', 'resources/crfigures.res', 'resources/textures.res',
  'resources/regs.res', 'resources/text.res'];
const MARKERS = {el1: 'campaigns/good.cpg', el2: 'campaigns/white.cpg'};
// What the engine reads: these folders, and archives or settings at the top.
const DATA_DIRS = ['resources', 'campaigns', 'maps', 'duel', 'tutorial', 'replays'];
const MAX_FILE = 2 * 1024 * 1024 * 1024;
function openData() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATA_DB, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore('files');
      request.result.createObjectStore('meta');
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
function requestResult(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
async function getMeta(key) {
  const db = await openData();
  try { return await requestResult(db.transaction('meta').objectStore('meta').get(key)); }
  finally { db.close(); }
}
async function putData(store, key, value) {
  const db = await openData();
  try {
    await new Promise((resolve, reject) => {
      const transaction = db.transaction(store, 'readwrite');
      transaction.objectStore(store).put(value, key);
      transaction.oncomplete = resolve;
      transaction.onabort = () => reject(transaction.error || new Error('Storage write aborted.'));
      transaction.onerror = () => reject(transaction.error);
    });
  } finally { db.close(); }
}
function cleanPath(name) {
  const path = name.replaceAll('\\', '/').toLowerCase();
  if (!path || path.startsWith('/') || path.split('/').some(p => !p || p === '.' || p === '..') || path.includes(':'))
    throw new Error('Invalid data path.');
  return path;
}
// Whether a lower-case installation path is one the engine reads.
function wantedPath(path) {
  const parts = path.split('/');
  if (parts.length > 1) return DATA_DIRS.includes(parts[0]) && !/\.(exe|dll|asi)$/.test(path);
  return /\.(res|ini|hl)$/.test(path);
}
// The edition the index holds ("el1" or "el2"), or null.
function detectEdition(files) {
  if (!REQUIRED_DATA.every(path => files[path])) return null;
  return EDITIONS.find(edition => files[MARKERS[edition]]) || null;
}
function validateIndex(files, payloadSize = Infinity) {
  if (!files || typeof files !== 'object' || Array.isArray(files)) throw new Error('Invalid data index.');
  const entries = Object.entries(files);
  if (!entries.length || entries.length > 20000) throw new Error('Invalid file count.');
  let end = 0;
  for (const [path, item] of entries.sort((a, b) => a[1].offset - b[1].offset)) {
    if (cleanPath(path) !== path || !wantedPath(path) || !Number.isSafeInteger(item.size) || item.size < 0 || item.size > MAX_FILE ||
        !Number.isSafeInteger(item.offset) || item.offset < end || item.offset + item.size > payloadSize)
      throw new Error('Invalid data range: ' + path);
    end = item.offset + item.size;
  }
  if (!detectEdition(files)) throw new Error('These files are not a complete copy of Etherlords or Etherlords II.');
  return files;
}
