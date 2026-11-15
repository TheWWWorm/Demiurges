#!/usr/bin/env python3
"""Checks of the Web/Android release scripts that need no Godot export:

  python tools/web_release_check.py

- every export preset packs the files the game reads from res:// that are
  not resources (the puzzle catalogs): its include filter names them and
  its exclude filter leaves them;
- export_mobile.stage_project stages the puzzle catalogs (and every other
  folder the game reads), with the page's text files in LF;
- audit_pack.missing reports required files a pack lacks;
- export_mobile.write_service_worker hashes the finished files, so its
  manifest matches them (including after prepare_web_host splits a file),
  and verify_manifest reports a changed, missing or CRLF file;
- the committed public/ folder matches its service worker manifest, read as
  git publishes it.
"""
import fnmatch
import hashlib
import json
import pathlib
import re
import struct
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import audit_pack  # noqa: E402
import export_mobile  # noqa: E402
import prepare_web_host  # noqa: E402

failures = []


def check(ok, what):
    print(('PASS: ' if ok else 'FAIL: ') + what)
    if not ok:
        failures.append(what)


def pack(path, names):
    """A minimal unencrypted Godot 4 pack (format 3) holding `names`."""
    payloads = [(name, f'data of {name}'.encode()) for name in names]
    directory = bytearray()
    offset = 0
    for name, data in payloads:
        encoded = ('res://' + name).encode()
        encoded += b'\0' * (-len(encoded) % 4)
        directory += struct.pack('<I', len(encoded)) + encoded + struct.pack('<QQ', offset, len(data)) + hashlib.md5(data).digest() + struct.pack('<I', 0)
        offset += len(data)
    base = 40
    blob = b''.join(data for _, data in payloads)
    header = struct.pack('<4sIIIIIQQ', b'GDPC', 3, 4, 7, 2, 0, base, base + len(blob))
    path.write_bytes(header + blob + struct.pack('<I', len(payloads)) + directory)


def presets():
    text = (HERE.parent / 'game/export_presets.cfg').read_text(encoding='utf-8')
    blocks = re.split(r'(?=^\[preset\.\d+\]$)', text, flags=re.M)
    found = 0
    for block in blocks:
        name = re.search(r'^name="([^"]*)"$', block, re.M)
        if not re.match(r'\[preset\.\d+\]$', block.split('\n', 1)[0]) or not name:
            continue
        found += 1
        def filters(key):
            value = re.search(rf'^{key}="([^"]*)"$', block, re.M)
            return [item.strip() for item in (value[1] if value else '').split(',') if item.strip()]
        include, exclude = filters('include_filter'), filters('exclude_filter')
        for required in audit_pack.REQUIRED:
            if required == 'project.binary':
                continue
            packed = any(fnmatch.fnmatch(required, pattern) for pattern in include)
            dropped = any(fnmatch.fnmatch(required, pattern) for pattern in exclude)
            check(packed and not dropped, f'preset {name[1]}: packs {required}')
    check(found >= 5, f'presets: {found} export presets read')


def staging(temp):
    project = HERE.parent / 'game'
    stage = temp / 'stage'
    export_mobile.stage_project(project, stage)
    print('  staged:', ', '.join(sorted(p.name for p in stage.iterdir())))
    for name in audit_pack.REQUIRED:
        if name != 'project.binary':
            check((stage / name).is_file(), f'staging: {name} is staged')
    runtime = sorted({line.split('res://', 1)[1].split('/')[0].split('"')[0]
                      for path in (project / 'src').rglob('*.gd') for line in path.read_text(encoding='utf-8').splitlines()
                      if 'res://' in line and not line.lstrip().startswith('#')})
    unstaged = [name for name in runtime if name and not (stage / name).exists() and name != '.local_profiles.json']
    check(not unstaged, 'staging: every res:// folder the scripts name is staged ' + ', '.join(unstaged))
    text = [p for p in (stage / 'web').iterdir() if p.suffix in export_mobile.TEXT_SUFFIXES]
    check(text and all(b'\r' not in p.read_bytes() for p in text), 'staging: the page files are staged with LF line endings')


def packs(temp):
    complete, partial = temp / 'complete.pck', temp / 'partial.pck'
    pack(complete, ['project.binary', 'puzzles/el1.json', 'puzzles/el2.json', 'src/main.gdc'])
    pack(partial, ['project.binary', 'src/main.gdc'])
    check(audit_pack.missing(complete) == [], 'pack: a pack with the puzzle catalogs passes')
    check(audit_pack.missing(partial) == ['puzzles/el1.json', 'puzzles/el2.json'], 'pack: a pack without them is reported')
    committed = HERE.parent / 'public/index.pck'
    if committed.is_file():
        print('  public/index.pck lacks:', ', '.join(audit_pack.missing(committed)) or 'nothing')


def manifests(temp):
    export = temp / 'export'
    export.mkdir()
    (export / 'index.html').write_bytes(b'<!doctype html>\r\n<p>shell</p>\r\n')
    (export / 'files.js').write_bytes(b"'use strict';\r\nconst a = 1;\r\n")
    (export / 'index.wasm').write_bytes(bytes(range(256)) * 64)
    (export / 'index.pck').write_bytes(b'GDPC' + b'\0' * 60)
    template = (HERE.parent / 'game/web/service-worker.js').read_text()
    manifest = export_mobile.write_service_worker(template, export)
    check(set(manifest) == {'index.html', 'files.js', 'index.wasm', 'index.pck'}, 'manifest: lists every cached file')
    check(b'\r' not in (export / 'files.js').read_bytes(), 'manifest: text files are written with LF before hashing')
    check(prepare_web_host.verify_manifest(export) == [], 'manifest: matches the files it was made from')
    worker = (export / 'service-worker.js').read_text()
    check('@FILES@' not in worker and '@BUILD@' not in worker, 'manifest: the service worker template is filled in')
    host = temp / 'host'
    prepare_web_host.prepare(export, host, limit=12000, chunk=12000, manifest=temp / 'parts.json')
    check((host / 'index.wasm.part0').is_file() and prepare_web_host.verify_manifest(host) == [], 'manifest: still matches once a file is split for the host')
    (host / 'files.js').write_bytes(b"'use strict';\nconst a = 2;\n")
    (host / 'index.html').write_bytes(b'<!doctype html>\r\n<p>shell</p>\r\n')
    (host / 'index.png').write_bytes(b'png')
    (host / 'index.pck').unlink()
    problems = prepare_web_host.verify_manifest(host)
    check(any(p.startswith('files.js: content') for p in problems), 'verify: a changed file is reported')
    check(any(p.startswith('index.html: CRLF') for p in problems), 'verify: CRLF text is reported')
    check('index.pck: missing' in problems, 'verify: a missing file is reported')
    check('index.png: not in the manifest' in problems, 'verify: a file the manifest lacks is reported')


def published():
    public = HERE.parent / 'public'
    inside = subprocess.run(['git', '-C', str(public), 'rev-parse', '--is-inside-work-tree'], capture_output=True, text=True)
    if inside.returncode:
        print('SKIP: public/ (not a git checkout)')
        return
    entries = prepare_web_host.manifest_of((public / 'service-worker.js').read_text())
    problems = prepare_web_host.verify_manifest(public, prepare_web_host.git_reader(public, 'HEAD'))
    check(not problems, f'public: all {len(entries)} files match the service worker manifest ' + '; '.join(problems))


def main():
    with tempfile.TemporaryDirectory(prefix='demiurges-web-check-') as temp:
        temp = pathlib.Path(temp)
        presets()
        staging(temp)
        packs(temp)
        manifests(temp)
    published()
    print(f'WEB RELEASE CHECK: {len(failures)} failure(s)')
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()
