'use strict';
// The player's own game files in the browser. They are imported once (from
// the GOG installer, the installed game folder or a data pack), kept in
// IndexedDB and served to the engine as a read-only folder: /gamedata/el1 and
// /gamedata/el2 hold the editions that were imported. Nothing is uploaded.
//
// The engine reads files synchronously, so reads go through a small shared
// mailbox to data-worker.js, which owns IndexedDB access. Recently read blocks
// are kept so small sequential reads stay cheap.
// Adapted from the Cursed Lands engine (TheWWWorm, Apache-2.0).
window.EtherFiles = {
  editions: {}, busy: false, generation: 0, fs: null, FS: null,
  cache: new Map(), cacheBytes: 0,
  BLOCK: 1024 * 1024, CACHE_LIMIT: 48 * 1024 * 1024, MOUNT: '/gamedata',
  // Resolves once the service worker holds the engine (onProgress(loaded,
  // total) follows its download) and the local data store is open.
  async initialize(onProgress) {
    if (!isSecureContext || !('serviceWorker' in navigator)) throw new Error('Open the game over HTTPS or localhost.');
    if (!crossOriginIsolated || typeof SharedArrayBuffer === 'undefined')
      throw new Error('This host must send Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy: require-corp. A current browser is required.');
    const container = navigator.serviceWorker;
    container.addEventListener('message', ({data}) => {
      if (data?.type === 'progress' && onProgress) onProgress(data.loaded, data.total);
    });
    container.startMessages();
    const registration = await container.register('service-worker.js');
    if (!registration.active) {
      // First visit: the worker downloads the engine before the game can start.
      const worker = registration.installing || registration.waiting;
      if (!worker) throw new Error('The game could not be downloaded. Check your connection and retry.');
      worker.postMessage('progress');
      await new Promise((resolve, reject) => {
        const check = () => {
          if (worker.state === 'activated') resolve();
          else if (worker.state === 'redundant') reject(new Error('The game could not be downloaded. Check your connection and retry.'));
        };
        worker.addEventListener('statechange', check); check();
      });
    }
    if (!container.controller) {
      // A forced reload bypasses the worker; the page asks to be controlled
      // again, and goes on without it rather than waiting forever.
      registration.active?.postMessage('claim');
      await Promise.race([new Promise(resolve => container.addEventListener('controllerchange', resolve, {once: true})),
        new Promise(resolve => setTimeout(resolve, 3000))]);
    }
    await this.loadEditions();
    this.signal = new Int32Array(new SharedArrayBuffer(8));
    this.transfer = new Uint8Array(new SharedArrayBuffer(4 * 1024 * 1024));
    this.worker = new Worker('data-worker.js');
    await new Promise((resolve, reject) => {
      this.worker.onmessage = ({data}) => data.ready ? resolve() : reject(new Error(data.error));
      this.worker.onerror = event => reject(new Error(event.message));
      this.worker.postMessage({type: 'init', signal: this.signal.buffer, bytes: this.transfer.buffer});
    });
  },
  async loadEditions() {
    this.editions = {};
    for (const edition of EDITIONS) {
      const meta = await getMeta('edition:' + edition);
      try { if (meta) { validateIndex(meta.files); this.editions[edition] = meta; } }
      catch (error) { console.warn('Ignoring stored ' + edition + ' files: ' + error.message); }
    }
  },
  // Called with the engine's file system after Engine.init(), before start.
  mount(FS) {
    if (!FS) throw new Error('This engine build cannot read local game files.');
    this.FS = FS;
    try { FS.mkdir(this.MOUNT); } catch (error) { /* already there */ }
    FS.mount(this.fileSystem(FS), {}, this.MOUNT);
  },
  // After an import or removal: the folders show the stored editions again.
  remount() {
    this.cache.clear(); this.cacheBytes = 0;
    this.worker?.postMessage({type: 'reset'});
    if (!this.FS) return;
    try { this.FS.unmount(this.MOUNT); } catch (error) { /* not mounted */ }
    this.FS.mount(this.fileSystem(this.FS), {}, this.MOUNT);
  },
  // A read-only Emscripten file system over the stored indexes.
  fileSystem(FS) {
    const files = this, DIR = 16384 | 0o555, FILE = 32768 | 0o444;
    const denied = () => { throw new FS.ErrnoError(63); };
    const fs = {
      mount() {
        const root = fs.node(null, '/', DIR, 0, null);
        for (const [edition, meta] of Object.entries(files.editions)) {
          const top = fs.node(root, edition, DIR, 0, null);
          for (const [path, entry] of Object.entries(meta.files)) {
            const parts = path.split('/');
            let folder = top;
            for (const part of parts.slice(0, -1))
              folder = folder.contents[part] || fs.node(folder, part, DIR, 0, null);
            fs.node(folder, parts[parts.length - 1], FILE, entry.size, {edition, path});
          }
        }
        return root;
      },
      node(parent, name, mode, size, ref) {
        const node = FS.createNode(parent, name, mode, 0);
        node.node_ops = fs.node_ops; node.stream_ops = fs.stream_ops;
        node.atime = node.mtime = node.ctime = Date.now();
        node.size = size; node.ref = ref; node.contents = {};
        if (parent) parent.contents[name] = node;
        return node;
      },
      node_ops: {
        getattr(node) {
          const size = FS.isDir(node.mode) ? 4096 : node.size;
          return {dev: 1, ino: node.id, mode: node.mode, nlink: 1, uid: 0, gid: 0, rdev: 0, size,
            atime: new Date(node.atime), mtime: new Date(node.mtime), ctime: new Date(node.ctime),
            blksize: 4096, blocks: Math.ceil(size / 4096)};
        },
        setattr: denied,
        // Stored names are lower case; Windows paths are not.
        lookup(parent, name) {
          const node = parent.contents[name.toLowerCase()];
          if (node) return node;
          throw new FS.ErrnoError(44);
        },
        readdir(node) { return ['.', '..', ...Object.keys(node.contents)]; },
        mknod: denied, rename: denied, unlink: denied, rmdir: denied, symlink: denied, readlink: denied,
      },
      stream_ops: {
        read(stream, buffer, offset, length, position) {
          const node = stream.node;
          if (!node.ref || position >= node.size) return 0;
          const count = Math.min(length, node.size - position);
          const bytes = files.read(node.ref.edition, node.ref.path, position, count);
          if (!bytes) throw new FS.ErrnoError(29);
          buffer.set(bytes, offset);
          return count;
        },
        write: denied,
        llseek(stream, offset, whence) {
          let position = offset;
          if (whence === 1) position += stream.position;
          else if (whence === 2) position += stream.node.size;
          if (position < 0) throw new FS.ErrnoError(28);
          return position;
        },
      },
    };
    return fs;
  },
  // Bytes [offset, offset + length) of a stored file, or null on failure.
  read(edition, path, offset, length) {
    try {
      const size = this.editions[edition]?.files[path]?.size;
      if (size === undefined || offset < 0 || length < 0 || offset + length > size) throw new Error('Invalid range.');
      if (length >= 4 * this.BLOCK) return this.fetch(edition, path, offset, length);
      const bytes = new Uint8Array(length);
      for (let done = 0; done < length;) {
        const at = offset + done, index = Math.floor(at / this.BLOCK);
        const block = this.block(edition, path, index, size), start = at - index * this.BLOCK;
        const count = Math.min(length - done, block.length - start);
        if (count <= 0) throw new Error('Short read.');
        bytes.set(block.subarray(start, start + count), done); done += count;
      }
      return bytes;
    } catch (error) {
      document.getElementById('runtime-error').textContent = 'Local game files could not be read. Reload, and import them again if needed. ' + error.message;
      return null;
    }
  },
  block(edition, path, index, size) {
    const key = edition + '/' + path + ':' + index;
    let block = this.cache.get(key);
    if (block) { this.cache.delete(key); this.cache.set(key, block); return block; }
    const start = index * this.BLOCK;
    block = this.fetch(edition, path, start, Math.min(this.BLOCK, size - start));
    while (this.cacheBytes + block.length > this.CACHE_LIMIT && this.cache.size) {
      const oldest = this.cache.keys().next().value;
      this.cacheBytes -= this.cache.get(oldest).length; this.cache.delete(oldest);
    }
    this.cache.set(key, block); this.cacheBytes += block.length;
    return block;
  },
  fetch(edition, path, offset, length) {
    // Atomics.wait is unavailable on the browser main thread. The wait is
    // bounded: on timeout the mailbox is retired, never reused with a late answer.
    if (this.failed) throw new Error('The local data reader stopped.');
    const bytes = new Uint8Array(length);
    for (let done = 0; done < length;) {
      const count = Math.min(this.transfer.length, length - done);
      Atomics.store(this.signal, 0, 0);
      this.worker.postMessage({type: 'read', edition, path, offset: offset + done, length: count});
      const deadline = performance.now() + 20000;
      while (Atomics.load(this.signal, 0) === 0) {
        if (performance.now() > deadline) { this.failed = true; this.worker.terminate(); throw new Error('Local storage timed out.'); }
      }
      if (Atomics.load(this.signal, 0) !== 1 || Atomics.load(this.signal, 1) !== count)
        throw new Error('Local data was removed or is incomplete.');
      bytes.set(this.transfer.subarray(0, count), done); done += count;
    }
    return bytes;
  },
  choose(callback, folder) {
    if (this.busy) return;
    const input = document.createElement('input'); input.type = 'file';
    if (folder) { input.webkitdirectory = true; input.multiple = true; }
    // Phone pickers may grey out unknown extensions; the file is recognised by its contents.
    else if (!matchMedia('(pointer: coarse)').matches) input.accept = '.exe,.elpack';
    input.onchange = () => this.importFiles(Array.from(input.files), callback);
    input.click();
  },
  cancel() { this.generation++; if (this.stopUnpack) this.stopUnpack(); },
  // The GOG installer is unpacked in its own worker (installer-worker.js),
  // which reads it in bounded ranges and stores each game file under `id`.
  unpackInstaller(file, id, callback) {
    const worker = new Worker('installer-worker.js');
    return new Promise((resolve, reject) => {
      this.stopUnpack = () => reject(new Error('Import cancelled.'));
      worker.onmessage = ({data}) => {
        if (data.type === 'progress') callback('progress', data.key, data.arg);
        else if (data.type === 'done') resolve(data.files);
        else reject(Object.assign(new Error(data.key), {arg: data.arg}));
      };
      worker.onerror = event => { event.preventDefault(); reject(new Error(event.message || 'The installer could not be unpacked.')); };
      worker.postMessage({file, id});
    }).finally(() => { worker.terminate(); this.stopUnpack = null; });
  },
  // A folder pick lists every file under the chosen folder; the game's root is
  // the folder that holds Resources/figures.res.
  folderIndex(selected) {
    const paths = selected.map(file => (file.webkitRelativePath || file.name).replaceAll('\\', '/'));
    const marker = paths.map(p => p.toLowerCase()).find(p => p === 'resources/figures.res' || p.endsWith('/resources/figures.res'));
    if (!marker) throw new Error('Choose the game folder that contains Resources and Campaigns.');
    const prefix = marker.slice(0, marker.length - 'resources/figures.res'.length);
    const files = {};
    let offset = 0;
    selected.forEach((file, i) => {
      if (!paths[i].toLowerCase().startsWith(prefix)) return;
      const path = cleanPath(paths[i].slice(prefix.length));
      if (!wantedPath(path)) return;
      if (files[path]) throw new Error('Duplicate data file: ' + path);
      files[path] = {size: file.size, offset, source: file}; offset += file.size;
    });
    return files;
  },
  async importFiles(selected, callback) {
    if (!selected.length || this.busy) return;
    this.busy = true; const generation = ++this.generation;
    let committed = false;
    const id = crypto.randomUUID();
    const current = () => { if (generation !== this.generation) throw new Error('Import cancelled.'); };
    try {
      callback('progress', 'Checking your game files…');
      let files = {}, pack = false, payload = 0, unpacked = false;
      const single = selected.length === 1 ? selected[0] : null;
      const magic = single ? new TextDecoder().decode(await single.slice(0, 8).arrayBuffer()) : '';
      if (single && magic.startsWith('MZ')) {
        files = validateIndex(await this.unpackInstaller(single, id, callback)); unpacked = true;
      } else if (single && magic === 'ELPACK01') {
        const header = new Uint8Array(await single.slice(0, 12).arrayBuffer());
        const size = new DataView(header.buffer).getUint32(8, true);
        if (size < 2 || size > 4 * 1024 * 1024 || size + 12 > single.size) throw new Error('Invalid data pack header.');
        payload = 12 + size;
        files = validateIndex(JSON.parse(await single.slice(12, payload).text()), single.size - payload); pack = true;
      } else if (single && !single.webkitRelativePath) {
        throw new Error('Choose the GOG installer (.exe), a data pack (.elpack) or the game folder.');
      } else {
        files = this.folderIndex(selected);
        validateIndex(files);
      }
      const edition = detectEdition(files);
      const bytes = pack ? single.size : Object.values(files).reduce((n, f) => n + f.size, 0);
      const estimate = unpacked ? null : await navigator.storage?.estimate?.();
      if (estimate?.quota && estimate.quota - estimate.usage < bytes * 1.05) throw new Error('Not enough browser storage for this import. Free space and try again.');
      current();
      if (unpacked) { /* already stored by the installer worker */ }
      else if (pack) { callback('progress', 'Saving your data pack on this device…'); await putData('files', id + '/pack', single); }
      else {
        let done = 0;
        for (const [path, entry] of Object.entries(files)) {
          current(); callback('progress', 'Importing %s', path + ' (' + Math.round(done / bytes * 100) + '%)');
          await putData('files', id + '/' + path, entry.source); delete entry.source; done += entry.size;
        }
      }
      current();
      // Commit last. Cancelling or running out of space keeps the previous files.
      const meta = {id, edition, files, pack, payload};
      await putData('meta', 'edition:' + edition, meta);
      committed = true;
      this.editions[edition] = meta;
      this.remount();
      await Promise.resolve(navigator.storage?.persist?.()).catch(() => false);
      // Cleanup is best effort after commit.
      await this.cleanup().catch(() => {});
      callback('complete', edition);
    } catch (error) {
      if (!committed) await this.removeGeneration(id).catch(() => {});
      callback('error', error.name === 'QuotaExceededError' ? 'Browser storage is full. Free space and try again.' : String(error.message || error), error.arg);
    } finally { this.busy = false; }
  },
  // Removes one edition's stored files. Saves live in the engine's own
  // storage and are kept.
  async forget(edition) {
    if (this.busy || !EDITIONS.includes(edition)) return;
    this.busy = true;
    // The folder disappears at once; the stored copy is deleted afterwards.
    delete this.editions[edition];
    this.remount();
    try {
      const db = await openData();
      await new Promise((resolve, reject) => {
        const tx = db.transaction('meta', 'readwrite');
        tx.objectStore('meta').delete('edition:' + edition);
        tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
      }); db.close();
      await this.cleanup();
    } finally { this.busy = false; }
  },
  async removeGeneration(id) {
    const db = await openData();
    await new Promise((resolve, reject) => {
      const tx = db.transaction('files', 'readwrite');
      tx.objectStore('files').delete(IDBKeyRange.bound(id + '/', id + '/￿'));
      tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
    }); db.close();
  },
  // Drops stored files that no edition's index refers to any more.
  async cleanup() {
    const keep = new Set(Object.values(this.editions).map(meta => meta.id));
    const db = await openData();
    const keys = await requestResult(db.transaction('files').objectStore('files').getAllKeys()); db.close();
    for (const id of new Set(keys.map(key => key.split('/')[0]))) if (!keep.has(id)) await this.removeGeneration(id);
  },
  fullscreen() {
    const page = document.documentElement;
    if (document.fullscreenElement) document.exitFullscreen();
    else if (page.requestFullscreen) page.requestFullscreen().catch(() => {});
    else alert('In Safari, use Share → Add to Home Screen → Open as Web App for a full-screen launch.');
  },
};
