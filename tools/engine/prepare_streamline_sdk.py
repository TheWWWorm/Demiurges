#!/usr/bin/env python3
"""Fetch and verify the pinned NVIDIA Streamline SDK for the Windows Vulkan build.

Installs the SDK headers into an engine tree (thirdparty/streamline/include) and
copies the signed production runtime DLLs plus their licence notices into an
output directory. Every file is checked against streamline-sdk.json.

Usage:
    prepare_streamline_sdk.py --archive CACHE/streamline-sdk-v2.14.16.zip \
        [--engine ENGINE_TREE] [--output DLL_DIR]

The archive is downloaded from the pinned URL when it does not exist yet.
Only the production DLLs from bin/x64 are used; development builds and the
withdrawn dlssg_for_sm86 package are never extracted.
"""

import argparse
import hashlib
import json
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

MANIFEST = Path(__file__).with_name("streamline-sdk.json")
NOTICES = (
    "license.txt",
    "3rd-party-licenses.md",
    "external/ngx-sdk/license.txt",
    "bin/x64/nvngx_dlss.license.txt",
    "bin/x64/reflex.license.txt",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_member(name: str) -> PurePosixPath:
    member = PurePosixPath(name)
    if member.is_absolute() or ".." in member.parts:
        raise ValueError(f"Unsafe SDK member: {name}")
    return member


def fetch(archive: Path, url: str, expected: str) -> None:
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        temporary = archive.with_suffix(".download")
        print(f"Downloading {url}")
        with urllib.request.urlopen(url) as source, temporary.open("wb") as target:
            shutil.copyfileobj(source, target)
        temporary.replace(archive)
    actual = sha256_file(archive)
    if actual != expected:
        raise ValueError(f"Streamline archive checksum mismatch: {actual} != {expected}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--archive", type=Path, required=True, help="Cached SDK zip (downloaded when missing)")
    parser.add_argument("--engine", type=Path, help="Godot source tree that receives thirdparty/streamline/include")
    parser.add_argument("--output", type=Path, help="Directory that receives the runtime DLLs and notices")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    fetch(args.archive, manifest["url"], manifest["archive_sha256"])

    with zipfile.ZipFile(args.archive) as sdk:
        names = set(sdk.namelist())
        for name, expected in manifest["files"].items():
            data = sdk.read(name)
            actual = hashlib.sha256(data).hexdigest()
            if actual != expected:
                raise ValueError(f"{name}: checksum mismatch {actual}")

        if args.engine:
            target = args.engine / "thirdparty" / "streamline"
            include = target / "include"
            if include.exists():
                shutil.rmtree(include)
            for name in sorted(names):
                if not name.startswith("include/") or name.endswith("/"):
                    continue
                member = safe_member(name)
                path = target.joinpath(*member.parts)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(sdk.read(name))
            (target / "license.txt").write_bytes(sdk.read("license.txt"))
            print(f"Installed Streamline {manifest['version']} headers into {target}")

        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            for dll in manifest["runtime"]:
                name = f"bin/x64/{dll}"
                if name not in manifest["files"]:
                    raise ValueError(f"{dll} has no pinned checksum")
                (args.output / dll).write_bytes(sdk.read(name))
            notices = args.output / "streamline-licenses"
            for name in NOTICES:
                member = safe_member(name)
                path = notices.joinpath(*member.parts)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(sdk.read(name))
            print(f"Copied {len(manifest['runtime'])} signed Streamline DLLs into {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
