#!/usr/bin/env python3
"""Make a private data pack (.elpack) from your own Etherlords installation.

A data pack is one file holding the game files the engine reads. It is the
quickest way to bring your copy to a phone or another browser:

  python3 prepare_game_data.py "/path/to/Etherlords II" Etherlords2.elpack

Then choose the pack on the game files screen. Make one pack per game. The
pack contains your own game files, so keep it to yourself.
"""
import argparse
import json
import pathlib
import shutil
import struct

REQUIRED = {'resources/figures.res', 'resources/crfigures.res', 'resources/textures.res',
            'resources/regs.res', 'resources/text.res'}
MARKERS = {'el1': 'campaigns/good.cpg', 'el2': 'campaigns/white.cpg'}
FOLDERS = {'resources', 'campaigns', 'maps', 'duel', 'tutorial', 'replays'}
TOP_FILES = {'.res', '.ini', '.hl'}
MAX_FILE = 2 * 1024 * 1024 * 1024


def wanted(name):
    parts = name.split('/')
    if len(parts) > 1:
        return parts[0] in FOLDERS and pathlib.PurePosixPath(name).suffix not in {'.exe', '.dll', '.asi'}
    return pathlib.PurePosixPath(name).suffix in TOP_FILES


def game_root(source):
    # An installed game, or innoextract's output with its app/ folder.
    for candidate in (source, source / 'app'):
        if any(p.name.lower() == 'resources' for p in candidate.iterdir() if p.is_dir()):
            return candidate
    raise ValueError('Choose the game folder that contains Resources and Campaigns.')


def prepare(source, output):
    source, output = pathlib.Path(source).resolve(), pathlib.Path(output).resolve()
    if not source.is_dir():
        raise ValueError(f'{source} is not a folder.')
    root = game_root(source)
    if output.is_relative_to(root):
        raise ValueError('Write the data pack outside the game folder.')
    files, index, offset = [], {}, 0
    for path in sorted(root.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        name = path.relative_to(root).as_posix().lower()
        if not wanted(name):
            continue
        if name in index:
            raise ValueError('Two files differ only in letter case: ' + name)
        size = path.stat().st_size
        if size > MAX_FILE:
            raise ValueError('File is larger than supported: ' + name)
        index[name] = {'offset': offset, 'size': size}
        offset += size
        files.append(path)
    missing = REQUIRED - index.keys()
    if missing:
        raise ValueError('Missing game files: ' + ', '.join(sorted(missing)))
    edition = next((e for e, marker in MARKERS.items() if marker in index), None)
    if edition is None:
        raise ValueError('This folder holds neither Etherlords nor Etherlords II.')
    header = json.dumps(index, separators=(',', ':')).encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + '.partial')
    try:
        with temporary.open('wb') as target:
            target.write(b'ELPACK01' + struct.pack('<I', len(header)) + header)
            for path in files:
                with path.open('rb') as data:
                    shutil.copyfileobj(data, target, 4 * 1024 * 1024)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    return edition, len(files), offset


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('source', help='Installed game folder (the one with Resources and Campaigns)')
    parser.add_argument('output', help='Data pack to write, for example Etherlords.elpack')
    args = parser.parse_args()
    try:
        edition, count, size = prepare(args.source, args.output)
    except (OSError, ValueError) as error:
        parser.exit(1, f'Could not make the data pack: {error}\n')
    title = 'Etherlords' if edition == 'el1' else 'Etherlords II'
    print(f'{title}: {count} files, {size / 1048576:.0f} MiB -> {args.output}')


if __name__ == '__main__':
    main()
