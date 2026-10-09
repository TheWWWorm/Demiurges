#!/usr/bin/env python3
"""Check that an unencrypted Godot 4 engine pack has only allowlisted entries."""
import argparse
import hashlib
from pathlib import Path
import re
import struct
import subprocess

ALLOWED = re.compile(r"^(?:res://)?(?:src/[^\n]+\.(?:gd|gdc|gd\.remap|gdshader|gdshader\.remap)|scenes/[^\n]+\.(?:tscn|tscn\.remap)|\.godot/[^\n]+|project\.binary|icon\.svg(?:\.import)?)$")
GAME_DATA = re.compile(r"\.(res|mmp|fig|mod|anm|bon|reg|cpg|sobj|bik|wav|ogg|mp3|exe|dll|etherpack|eipack|elpack)$", re.I)
PRIVATE = re.compile(rb"/(?:home|Users)/[^/\s\x00]+/|\.local_profiles\.json\x00?\s*[:=]|(?:FUN|DAT|LAB|PTR|SUB)_[0-9a-fA-F]{6,}")


def entries(path):
    data = path.read_bytes()
    if len(data) < 40:
        raise ValueError("Truncated pack header")
    magic, version, major, minor, patch, flags, base, directory = struct.unpack_from("<4sIIIIIQQ", data)
    if magic != b"GDPC" or flags & ~2 or version not in (3, 4):
        raise ValueError("Expected an unencrypted, non-sparse Godot 4 PCK format 3 or 4")
    count = struct.unpack_from("<I", data, directory)[0]
    offset = directory + 4
    if count > 10000:
        raise ValueError("Unexpected entry count")
    for _ in range(count):
        length = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        name = data[offset:offset + length].rstrip(b"\0").decode()
        offset += length
        start, size = struct.unpack_from("<QQ", data, offset)
        checksum = data[offset + 16:offset + 32]
        entry_flags = struct.unpack_from("<I", data, offset + 32)[0]
        offset += 36
        if base + start + size > len(data):
            raise ValueError(f"Out-of-range entry: {name}")
        payload = data[base + start:base + start + size]
        if entry_flags or hashlib.md5(payload).digest() != checksum:
            raise ValueError(f"Unsupported flags or checksum mismatch: {name}")
        yield name, payload


def audit(path):
    problems, count = [], 0
    for name, payload in entries(path):
        count += 1
        if not ALLOWED.fullmatch(name) or ".." in name.split("/"):
            problems.append(f"Unexpected entry: {name}")
        if GAME_DATA.search(name) or "profiles.json" in name or "/tools/" in name:
            problems.append(f"Private/content entry: {name}")
        if payload[:4] == b"GDSC":
            size = struct.unpack_from("<I", payload, 8)[0]
            payload = payload[12:] if size == 0 else subprocess.run(
                ["zstd", "-dc"], input=payload[12:], capture_output=True, check=True).stdout
            payload = payload.replace(b"\0", b"") + bytes(b ^ 0xb6 for b in payload).replace(b"\0", b"")
        if PRIVATE.search(payload):
            problems.append(f"Private research/path marker: {name}")
    return count, problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    args = parser.parse_args()
    count, problems = audit(args.pack)
    for problem in problems:
        print(problem)
    print(f"Pack audit: {count} entries, {len(problems)} problems")
    raise SystemExit(bool(problems))


if __name__ == "__main__":
    main()
