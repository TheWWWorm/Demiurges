#!/usr/bin/env python3
"""Prepare an exported Web build for a static host with a per-file size limit.

Cloudflare rejects assets larger than 25 MiB, and the Godot engine binary
(index.wasm, about 37 MiB) exceeds that. Oversized files are split into
numbered parts that publish/worker.js streams back together under the original
path. Their total size and part count go into parts.json next to worker.js, so
the rejoined response carries a Content-Length (the loading bar needs it) and a
missing part ends in an error rather than a short file. The parts stay uncompressed: Cloudflare negotiates its own
Content-Encoding for the response, so storing them pre-compressed would only
fight that and strip the encoding header.

The local-file bridge (web/files.js, web/data-worker.js) reads the player's game
files through SharedArrayBuffer, which browsers only allow on a cross-origin
isolated page. Every response therefore carries COOP/COEP; worker.js adds the
same headers to the files it rejoins, because _headers does not apply to
responses built by the Worker.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess

LIMIT = 25 * 1024 * 1024
CHUNK = 20 * 1024 * 1024
BASE_HEADERS = """# Served by static hosts that read _headers (Cloudflare Workers assets, Pages, Netlify).
# The local-file bridge needs SharedArrayBuffer, so every page must be cross-origin isolated.
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Resource-Policy: same-origin

/*.wasm
  Content-Type: application/wasm

# The shell and the service worker must be revalidated, so a new export is picked up.
/
  Cache-Control: no-cache

/index.html
  Cache-Control: no-cache

/service-worker.js
  Cache-Control: no-cache

# The wiki is plain articles: revalidated, and allowed nothing but its own files.
/wiki/*
  Cache-Control: no-cache
  Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
"""


# What service-worker.js caches (tools/export_mobile.py writes its manifest).
CACHED_SUFFIXES = {'.html', '.js', '.wasm', '.pck', '.png', '.webmanifest'}
TEXT_SUFFIXES = {'.html', '.js', '.webmanifest'}


def manifest_of(worker_text):
    """The {name: {'sha256', 'size'}} manifest in a built service-worker.js
    (older builds list bare hashes: size is then None)."""
    found = re.search(r'^const (?:FILES|HASHES) = (\{.*?\});', worker_text, re.S | re.M)
    if not found:
        raise ValueError('service-worker.js holds no file manifest')
    raw = json.loads(found.group(1))
    return {name: value if isinstance(value, dict) else {'sha256': value, 'size': None} for name, value in raw.items()}


def read_published(folder, name):
    """A file as the host serves it: split files are joined back together."""
    path = folder / name
    if path.is_file():
        return path.read_bytes()
    parts = sorted(folder.glob(name + '.part*'), key=lambda p: int(p.name.rsplit('.part', 1)[1]))
    return b''.join(p.read_bytes() for p in parts) if parts else None


def verify_manifest(folder, read=None):
    """Problems (empty when none) between service-worker.js and the files it
    caches. `read(name)` returns a file's published bytes or None; by default
    they are read from the folder."""
    folder = pathlib.Path(folder)
    read = read or (lambda name: read_published(folder, name))
    try:
        manifest = manifest_of((folder / 'service-worker.js').read_text())
    except (OSError, ValueError) as error:
        return [str(error)]
    problems = []
    for name, entry in sorted(manifest.items()):
        data = read(name)
        if data is None:
            problems.append(f'{name}: missing')
            continue
        if hashlib.sha256(data).hexdigest() != entry['sha256'] or entry['size'] not in (None, len(data)):
            problems.append(f'{name}: content differs from the manifest')
        if pathlib.PurePosixPath(name).suffix in TEXT_SUFFIXES and b'\r' in data:
            problems.append(f'{name}: CRLF line endings (git would publish other bytes)')
    listed = set(manifest)
    for path in folder.iterdir():
        name = re.sub(r'\.part\d+$', '', path.name)
        if path.is_file() and pathlib.PurePosixPath(name).suffix in CACHED_SUFFIXES and name != 'service-worker.js' and name not in listed:
            problems.append(f'{name}: not in the manifest')
    return sorted(set(problems))


def git_reader(folder, revision):
    """Reads files as committed (`revision` 'HEAD') or staged (':'), i.e. the bytes
    the host publishes, whatever line endings the checkout has."""
    folder = pathlib.Path(folder).resolve()
    top = pathlib.Path(subprocess.run(['git', '-C', str(folder), 'rev-parse', '--show-toplevel'], capture_output=True, text=True, check=True).stdout.strip())
    prefix = folder.relative_to(top).as_posix()

    def read(name):
        spec = f'{revision}:{prefix}/{name}' if revision != ':' else f':{prefix}/{name}'
        result = subprocess.run(['git', '-C', str(top), 'show', spec], capture_output=True)
        if result.returncode == 0:
            return result.stdout
        parts = []
        for index in range(1000):
            part = subprocess.run(['git', '-C', str(top), 'show', f'{spec}.part{index}'], capture_output=True)
            if part.returncode:
                break
            parts.append(part.stdout)
        return b''.join(parts) if parts else None
    return read


def split(path, chunk=CHUNK):
    """Replace a file with sequential .part0, .part1, ... siblings."""
    raw = path.read_bytes()
    parts = [raw[offset:offset + chunk] for offset in range(0, len(raw), chunk)]
    for index, payload in enumerate(parts):
        path.with_name(f'{path.name}.part{index}').write_bytes(payload)
    path.unlink()
    return len(raw), len(parts)


def prepare(source, output, limit=LIMIT, chunk=CHUNK, manifest=None):
    if chunk > limit:
        raise ValueError('Chunk size must not exceed the host limit')
    source, output = pathlib.Path(source).resolve(), pathlib.Path(output).resolve()
    if not (source / 'index.html').is_file():
        raise ValueError(f'{source} does not hold a Web export (no index.html)')
    if output == source or source.is_relative_to(output):
        raise ValueError('The output directory must not contain the source')
    # The wiki (tools/build_wiki.py) is built separately: keep it, unless the
    # export brings its own.
    kept = None
    if (output / 'wiki').is_dir() and not (source / 'wiki').exists():
        kept = output.parent / f'.{output.name}-wiki-kept'
        if kept.exists():
            shutil.rmtree(kept)
        shutil.move(output / 'wiki', kept)
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(source, output, symlinks=False)
    if kept is not None:
        shutil.move(kept, output / 'wiki')
    divided = {}
    for path in sorted(output.rglob('*')):
        if path.is_file() and path.stat().st_size > limit:
            size, count = split(path, chunk)
            name = '/' + path.relative_to(output).as_posix()
            divided[name] = {'count': count, 'size': size}
            print(f'  split {name}: {size/1048576:.1f} MiB into {count} parts')
    (output / '_headers').write_text(BASE_HEADERS)
    over = [p for p in output.rglob('*') if p.is_file() and p.stat().st_size > limit]
    if over:
        raise ValueError('Still over the host limit: ' + ', '.join(p.name for p in over))
    if manifest is None:
        manifest = output.parent / 'parts.json'
    pathlib.Path(manifest).write_text(json.dumps(divided, indent=2, sort_keys=True) + '\n')
    # The service worker refuses any file whose bytes differ from its manifest.
    problems = verify_manifest(output)
    if problems:
        raise ValueError('The service worker manifest does not match the output:\n  ' + '\n  '.join(problems))
    return {'files': sum(1 for p in output.rglob('*') if p.is_file()), 'split': len(divided)}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', type=pathlib.Path, help='Exported Web build directory')
    parser.add_argument('--output', type=pathlib.Path, help='Directory to write, replaced if present')
    parser.add_argument('--limit', type=int, default=LIMIT, help='Per-file host limit in bytes')
    parser.add_argument('--chunk', type=int, default=CHUNK, help='Maximum size of each written part')
    parser.add_argument('--verify', type=pathlib.Path, help='Only check a host folder (e.g. public) against its service worker manifest')
    parser.add_argument('--git', metavar='REV', help="With --verify: read the files as git has them (HEAD, or ':' for the staged copies)")
    args = parser.parse_args()
    if args.verify:
        problems = verify_manifest(args.verify, git_reader(args.verify, args.git) if args.git else None)
        for problem in problems:
            print(problem)
        print(f'Manifest check: {len(problems)} problems')
        raise SystemExit(bool(problems))
    if not args.source or not args.output:
        parser.error('--source and --output are required')
    print(prepare(args.source, args.output, args.limit, args.chunk))


if __name__ == '__main__':
    main()
