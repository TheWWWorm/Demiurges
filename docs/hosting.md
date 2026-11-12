# Hosting the browser version

The browser version is a static site: the files in `public/` (or in the `…-web.zip` release). It needs:

- **HTTPS**, or `localhost` for testing. The page uses a service worker, which browsers only allow in a secure context.
- **Cross-origin isolation.** Every response must carry `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`. The page reads the player's stored game files through a `SharedArrayBuffer`, which browsers only provide on isolated pages. The included `_headers` file sets these headers on hosts that read it (Cloudflare, Netlify).
- **The WebAssembly type** for `index.wasm` (`application/wasm`).

## Cloudflare Workers

This repository deploys with `wrangler.toml`: Workers static assets serve `public/`, and `worker.js` adds the isolation headers. Cloudflare rejects single files over 25 MiB, so the engine binary is stored as `index.wasm.part0`, `index.wasm.part1`, … and listed in `parts.json`; `worker.js` streams the parts back together as `index.wasm` with its full size.

`worker.js` also runs the online play relay at `/relay`. A host opens a room with a six-letter code and guests join it by that code, so nobody has to open a port and the browser build can play online. Each room is a Durable Object (`RelayRoom`, bound as `RELAY` with a SQLite-backed migration in `wrangler.toml`) that only passes messages between the players in it. A self-hosted copy of the game can point at another relay with the `DEMIURGES_RELAY` environment variable, for example `ws://127.0.0.1:8787/relay` while `npx wrangler dev` runs. `tools/network_check.gd -- --relay=ws://127.0.0.1:8787/relay` tests every online mode through such a relay.

## Testing on your computer

```sh
python3 tools/serve_web.py public
```

Then open `http://localhost:8060/`. The script adds the isolation headers and joins split files using `parts.json`.

## Building it

```sh
python3 tools/export_mobile.py web --output build/web
python3 tools/prepare_web_host.py --source build/web --output public
```

The first command exports the engine with the Web preset and adds the page's local-file support, icons, the service worker and `_headers`. The second splits files over 25 MiB and writes `parts.json` next to `public/`.

The wiki at `/wiki/` is a separate static site in `public/wiki`, built by `python3 tools/build_wiki.py` and kept when `prepare_web_host.py` replaces the export; see [the wiki guide](wiki.md).

Players' game files never reach the server: they are imported and stored in the player's own browser.
