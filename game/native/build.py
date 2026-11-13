#!/usr/bin/env python3
"""Build the native libraries for every exported platform: the installer
decoder (el_lzma.c), the asset decoders (el_assets.c), the Lua 4.0 compiler
for custom maps' scripts (el_lua.c, with the Lua 4.0.1 core in lua40/), the
computer opponent's combat lookahead (el_duel_brain.c) and, on desktop, the
local Discord activity link (el_discord.c).

  python3 native/build.py [--zig ZIG] [--ndk NDK] [linux windows macos android]

Linux, Windows and macOS are cross-compiled with Zig (zig cc); Android with
the Android NDK's clang. The libraries go to native/bin/, named as their
.gdextension files expect. The macOS libraries are universal (arm64 + x86_64).
Platforms whose compiler is missing are skipped with a message; the game then
uses its GDScript decoder there and shows no Discord activity.
"""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
BIN = HERE / "bin"
# Each library and the platforms it is built for.
LIBRARIES = {"el_lzma": ("linux", "windows", "macos", "android"), "el_assets": ("linux", "windows", "macos", "android"), "el_lua": ("linux", "windows", "macos", "android"), "el_duel_brain": ("linux", "windows", "macos", "android"), "el_discord": ("linux", "windows", "macos")}
# Paths of the build machine are kept out of the libraries.
FLAGS = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Wno-cast-function-type", "-fvisibility=hidden", "-shared",
         f"-ffile-prefix-map={HERE}=native", "-g0"]
ANDROID_API = 24


def run(cmd):
    print("  " + " ".join(str(c) for c in cmd))
    subprocess.run([str(c) for c in cmd], check=True)


def zig_cc(zig, target, output, name, extra=()):
    run([zig, "cc", "-target", target, *FLAGS, *extra, "-o", output, HERE / f"{name}.c"])


def fat_macho(slices, output):
    """Joins thin Mach-O files into one universal file (what lipo -create does)."""
    align = 14
    header = struct.pack(">II", 0xCAFEBABE, len(slices))
    entries, blobs = b"", []
    offset = 1 << align
    for path in slices:
        data = Path(path).read_bytes()
        cputype, cpusubtype = struct.unpack("<ii", data[4:12])
        entries += struct.pack(">iiIII", cputype, cpusubtype, offset, len(data), align)
        blobs.append((offset, data))
        offset = (offset + len(data) + (1 << align) - 1) & ~((1 << align) - 1)
    out = bytearray(header + entries)
    for at, data in blobs:
        out += b"\0" * (at - len(out)) + data
    Path(output).write_bytes(bytes(out))


def linux(zig, ndk, name):
    zig_cc(zig, "x86_64-linux-gnu.2.28", BIN / f"lib{name}.linux.x86_64.so", name, ["-fPIC", "-s"])


def windows(zig, ndk, name):
    with tempfile.TemporaryDirectory() as tmp:
        dll = Path(tmp) / f"{name}.dll"
        zig_cc(zig, "x86_64-windows-gnu", dll, name, ["-s"])
        shutil.copy(dll, BIN / f"{name}.windows.x86_64.dll")


def macos(zig, ndk, name):
    with tempfile.TemporaryDirectory() as tmp:
        slices = []
        for arch in ("aarch64", "x86_64"):
            thin = Path(tmp) / f"{arch}.dylib"
            zig_cc(zig, f"{arch}-macos.11.0", thin, name, ["-fPIC", "-s", f"-Wl,-install_name,@rpath/lib{name}.macos.dylib"])
            slices.append(thin)
        fat_macho(slices, BIN / f"lib{name}.macos.dylib")


def android(zig, ndk, name):
    tools = Path(ndk) / "toolchains/llvm/prebuilt/linux-x86_64/bin"
    for arch, triple in (("arm64", "aarch64-linux-android"), ("x86_64", "x86_64-linux-android")):
        clang = tools / f"{triple}{ANDROID_API}-clang"
        if not clang.exists():
            raise FileNotFoundError(clang)
        # 16 KB pages: required by recent Android devices. libm is linked
        # explicitly: Godot opens the library with every symbol resolved at
        # once, and the maths functions (sincos) are not in libc.
        run([clang, *FLAGS, "-fPIC", "-s", "-Wl,-z,max-page-size=16384", "-o", BIN / f"lib{name}.android.{arch}.so", HERE / f"{name}.c", "-lm"])


PLATFORMS = {"linux": linux, "windows": windows, "macos": macos, "android": android}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zig", default=os.environ.get("ZIG", shutil.which("zig") or "zig"))
    parser.add_argument("--ndk", default=os.environ.get("ANDROID_NDK_ROOT", ""))
    parser.add_argument("platforms", nargs="*", default=list(PLATFORMS))
    args = parser.parse_args()
    BIN.mkdir(exist_ok=True)
    skipped = []
    for name in args.platforms:
        needs = args.ndk if name == "android" else args.zig
        if not needs or (name != "android" and not shutil.which(needs)) or (name == "android" and not Path(needs).is_dir()):
            skipped.append(name)
            continue
        print(name)
        for library, platforms in LIBRARIES.items():
            if name in platforms: PLATFORMS[name](args.zig, args.ndk, library)
    for library in sorted(BIN.iterdir()):
        data = library.read_bytes()
        if str(HERE).encode() in data or b"/home/" in data or b"/tmp/" in data:
            print(f"{library.name}: contains a local path", file=sys.stderr)
            return 1
    for name in skipped:
        print(f"{name}: compiler not found, skipped", file=sys.stderr)
    return 1 if skipped and len(skipped) == len(args.platforms) else 0


if __name__ == "__main__":
    sys.exit(main())
