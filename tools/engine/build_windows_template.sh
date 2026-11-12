#!/usr/bin/env bash
# Builds the Windows x86_64 export templates with NVIDIA Streamline (DLSS) and
# AMD FidelityFX (FSR 3.1/4) on the Vulkan renderer.
#
# Usage: build_windows_template.sh WORK_DIR OUTPUT_DIR
#
# WORK_DIR/godot is cloned (or reset) to Godot 4.7-stable, the patch series in
# engine_patches/godot-4.7 is applied, both SDK prep scripts install their
# headers, and the templates are built with MinGW. OUTPUT_DIR receives the
# executables, the signed SDK runtime DLLs, their licences and SHA256SUMS.
#
# Environment (the first three are required):
#   MINGW_PREFIX       MinGW-w64 toolchain prefix (bin/x86_64-w64-mingw32-gcc)
#   MESA_LIBS          mesa_libs= for the OpenGL (Compatibility) driver
#   SCONS_PYTHONPATH   directory providing the SCons Python package
#   SCONS_CACHE        optional SCons cache directory
#   SDK_CACHE          SDK download cache (default WORK_DIR/sdk-cache)
#   TARGETS            default "template_release template_debug"
#   JOBS               parallel jobs (default: nproc)
set -euo pipefail

if [ $# -ne 2 ]; then
	sed -n '2,20p' "$0"
	exit 2
fi

WORK_DIR=$(mkdir -p "$1" && cd "$1" && pwd)
OUTPUT_DIR=$(mkdir -p "$2" && cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH_DIR=$(cd "$HERE/../../engine_patches/godot-4.7" && pwd)

GODOT_REPO=https://github.com/godotengine/godot.git
GODOT_TAG=4.7-stable
GODOT_COMMIT=5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88

: "${MINGW_PREFIX:?set MINGW_PREFIX to the MinGW-w64 toolchain prefix}"
: "${MESA_LIBS:?set MESA_LIBS to the mesa_libs directory}"
: "${SCONS_PYTHONPATH:?set SCONS_PYTHONPATH to the directory providing SCons}"
SDK_CACHE=${SDK_CACHE:-$WORK_DIR/sdk-cache}
TARGETS=${TARGETS:-template_release template_debug}
JOBS=${JOBS:-$(nproc)}

SRC=$WORK_DIR/godot
if [ ! -d "$SRC/.git" ]; then
	git clone --branch "$GODOT_TAG" --depth 1 "$GODOT_REPO" "$SRC"
else
	git -C "$SRC" fetch --depth 1 origin tag "$GODOT_TAG"
	git -C "$SRC" checkout -q -f --detach "$GODOT_TAG"
	git -C "$SRC" clean -q -fdx
fi
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$GODOT_COMMIT" ]; then
	echo "$GODOT_TAG is not $GODOT_COMMIT" >&2
	exit 1
fi

for patch in "$PATCH_DIR"/[0-9]*.patch; do
	echo "Applying $(basename "$patch")"
	git -C "$SRC" apply --index --whitespace=nowarn "$patch"
done

STREAMLINE_VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$HERE/streamline-sdk.json")
python3 "$HERE/prepare_streamline_sdk.py" --archive "$SDK_CACHE/streamline-sdk-v$STREAMLINE_VERSION.zip" --engine "$SRC" --output "$OUTPUT_DIR"
python3 "$HERE/prepare_fsr_sdk.py" --cache "$SDK_CACHE/fsr" --engine "$SRC" --output "$OUTPUT_DIR"

export LD_LIBRARY_PATH=$MINGW_PREFIX/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export PYTHONPATH=$SCONS_PYTHONPATH${PYTHONPATH:+:$PYTHONPATH}
CACHE_ARG=()
if [ -n "${SCONS_CACHE:-}" ]; then
	CACHE_ARG=("cache_path=$SCONS_CACHE")
fi

cd "$SRC"
for target in $TARGETS; do
	python3 -m SCons -j"$JOBS" "${CACHE_ARG[@]}" platform=windows arch=x86_64 target="$target" \
		production=yes optimize=speed lto=none debug_symbols=no \
		use_mingw=yes use_static_cpp=yes mingw_prefix="$MINGW_PREFIX" mesa_libs="$MESA_LIBS" \
		d3d12=no vulkan=yes use_streamline=yes use_fsr_sdk=yes \
		module_mono_enabled=no module_openxr_enabled=no accesskit=no
	cp "bin/godot.windows.$target.x86_64.exe" "bin/godot.windows.$target.x86_64.console.exe" "$OUTPUT_DIR/"
done

cp LICENSE.txt "$OUTPUT_DIR/GODOT_LICENSE.txt"
(cd "$OUTPUT_DIR" && find . -type f ! -name SHA256SUMS | sort | xargs sha256sum > SHA256SUMS)
echo "Templates and SDK runtime staged in $OUTPUT_DIR"
