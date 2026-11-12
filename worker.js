// Serves the exported Web build from the static asset store.
//
// Assets above Cloudflare's 25 MiB limit are stored as sequential .part0,
// .part1, ... files and listed in parts.json with their total size. This
// streams them back together under the original name with a Content-Length,
// so the loading bar can show progress, and a missing part fails instead of
// ending in a short file. The parts are stored uncompressed: Cloudflare
// negotiates its own Content-Encoding and strips one set here.
//
// The game reads your own game files through SharedArrayBuffer, which needs a
// cross-origin isolated page, so every response gets the isolation headers.
import { DurableObject } from 'cloudflare:workers';
import parts from './parts.json';

// Online play relay: /relay?room=CODE&role=host|guest lets players meet
// without opening ports. One Durable Object per room passes binary frames
// between the host (peer 1) and its guests (peers 2 and up). Each frame
// starts with a little-endian u32 peer id: the target when sent, replaced by
// the sender's id when delivered. Guests may only reach the host; the host
// reaches one guest, or all of them with id 0. Text frames are control
// messages: welcome/join/leave from the relay, refuse/kick from the host.
const ROOM_CODE = /^[A-Z2-9]{6}$/;
const RELAY_VERSION = '1';
const MAX_GUESTS = 8;

export class RelayRoom extends DurableObject {
  async fetch(request) {
    const url = new URL(request.url);
    const role = url.searchParams.get('role');
    const sockets = this.ctx.getWebSockets();
    const host = sockets.find((ws) => ws.deserializeAttachment()?.id === 1);
    let id;
    if (role === 'host') {
      if (host) return new Response('This room is already hosted.', { status: 409 });
      const max = Number(url.searchParams.get('max') || '1');
      await this.ctx.storage.put({ max: Math.max(1, Math.min(MAX_GUESTS, Math.floor(max) || 1)), refuse: false, next: 2 });
      id = 1;
    } else {
      if (!host) return new Response('No game is hosted in this room.', { status: 404 });
      const settings = await this.ctx.storage.get(['max', 'refuse', 'next']);
      const guests = sockets.length - 1;
      if (settings.get('refuse') || guests >= (settings.get('max') || 1)) return new Response('This room is full.', { status: 403 });
      id = settings.get('next') || 2;
      await this.ctx.storage.put('next', id + 1);
    }
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ id });
    server.send(JSON.stringify({ t: 'welcome', id }));
    if (id !== 1) host.send(JSON.stringify({ t: 'join', id }));
    return new Response(null, { status: 101, webSocket: client });
  }

  _peer(id) {
    return this.ctx.getWebSockets().find((ws) => ws.deserializeAttachment()?.id === id);
  }

  async webSocketMessage(ws, message) {
    const from = ws.deserializeAttachment()?.id;
    if (!from) return;
    if (typeof message === 'string') {
      if (from !== 1) return;
      let control;
      try { control = JSON.parse(message); } catch { return; }
      if (control?.t === 'refuse') await this.ctx.storage.put('refuse', Boolean(control.on));
      else if (control?.t === 'kick' && Number.isInteger(control.id) && control.id > 1) this._peer(control.id)?.close(4000, 'Removed by the host.');
      return;
    }
    if (!(message instanceof ArrayBuffer) || message.byteLength < 6) return;
    const view = new DataView(message);
    const target = view.getUint32(0, true);
    view.setUint32(0, from, true);
    if (from !== 1) {
      if (target === 1) this._peer(1)?.send(message);
    } else if (target === 0) {
      for (const peer of this.ctx.getWebSockets()) if (peer !== ws) peer.send(message);
    } else {
      this._peer(target)?.send(message);
    }
  }

  async webSocketClose(ws) {
    this._left(ws);
  }

  async webSocketError(ws) {
    this._left(ws);
  }

  _left(ws) {
    const id = ws.deserializeAttachment()?.id;
    if (!id) return;
    ws.serializeAttachment({ id: 0 });
    for (const peer of this.ctx.getWebSockets()) {
      if (peer === ws) continue;
      if (id === 1) peer.close(4001, 'The host left.');
      else if (peer.deserializeAttachment()?.id === 1) peer.send(JSON.stringify({ t: 'leave', id }));
    }
  }
}

const CONTENT_TYPES = {
  wasm: 'application/wasm',
  js: 'text/javascript; charset=utf-8',
  json: 'application/json; charset=utf-8',
  pck: 'application/octet-stream',
};

const WIKI_POLICY = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

function isolate(headers) {
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  headers.set('X-Content-Type-Options', 'nosniff');
  return headers;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/relay') {
      const room = (url.searchParams.get('room') || '').toUpperCase();
      const role = url.searchParams.get('role');
      if (request.headers.get('Upgrade') !== 'websocket') return new Response('Expected a WebSocket.', { status: 426 });
      if (!ROOM_CODE.test(room) || (role !== 'host' && role !== 'guest') || url.searchParams.get('v') !== RELAY_VERSION) {
        return new Response('Invalid room.', { status: 400 });
      }
      return env.RELAY.get(env.RELAY.idFromName(room)).fetch(request);
    }
    if (url.protocol === 'http:' && url.hostname !== 'localhost' && url.hostname !== '127.0.0.1') {
      url.protocol = 'https:';
      return Response.redirect(url.href, 308);
    }
    // The wiki (public/wiki, built by tools/build_wiki.py) is a static site of
    // its own: it never needs the engine and allows nothing but its own files.
    if (url.pathname === '/wiki') {
      url.pathname = '/wiki/';
      return Response.redirect(url.href, 308);
    }
    const entry = parts[url.pathname];
    if (!entry) {
      const response = await env.ASSETS.fetch(request);
      const headers = isolate(new Headers(response.headers));
      if (url.pathname.startsWith('/wiki/')) {
        headers.set('Cache-Control', 'no-cache');
        headers.set('Content-Security-Policy', WIKI_POLICY);
      }
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    }
    const headers = isolate(new Headers());
    headers.set('Content-Type', CONTENT_TYPES[url.pathname.split('.').pop().toLowerCase()] || 'application/octet-stream');
    headers.set('Content-Length', String(entry.size));
    // index.wasm keeps its name across exports; the service worker's install
    // must not pick up a stale copy from the HTTP cache.
    headers.set('Cache-Control', 'no-cache');
    if (request.method === 'HEAD') return new Response(null, { headers });
    if (request.method !== 'GET') return new Response('Method not allowed', { status: 405, headers });
    let index = 0;
    let reader = null;
    const body = new ReadableStream({
      async pull(controller) {
        try {
          while (true) {
            if (!reader) {
              if (index === entry.count) {
                controller.close();
                return;
              }
              const response = await env.ASSETS.fetch(new URL(`${url.pathname}.part${index++}`, url.origin));
              if (!response.ok) throw new Error('Incomplete engine export');
              reader = response.body.getReader();
            }
            const chunk = await reader.read();
            if (!chunk.done) {
              controller.enqueue(chunk.value);
              return;
            }
            reader.releaseLock();
            reader = null;
          }
        } catch (error) {
          controller.error(error);
        }
      },
      async cancel() {
        if (reader) await reader.cancel();
      },
    });
    return new Response(body, { headers });
  },
};
