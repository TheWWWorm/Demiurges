# Third-party notices

The MMP texture decoder and Nival registry reader in `src/content/` are adapted
from the Apache-2.0 licensed Cursed Lands engine by TheWWWorm. Their source is
maintained at https://github.com/TheWWWorm/CursedLands . The FIG mesh layout and
coordinate conversion also follow that engine and direct inspection of the user’s
original Etherlords files. See LICENSE.md.

The optional adventure terrain detail in `src/render/adventure_terrain.gdshader`
adapts the texture-derived relief and bounded contrast technique from the
Apache-2.0 licensed Cursed Lands engine by TheWWWorm, for Etherlords' tile atlas.

The optional shadow filtering follows the quality-setting approach of the
Apache-2.0 licensed Cursed Lands engine by TheWWWorm.

Godot is distributed under the MIT license and its own third-party notices.
Original Etherlords and Etherlords II content is supplied by the player and is
not part of this engine’s source or license.

The Lua 4.0 binary reader and virtual-machine semantics in `src/content/lua_*.gd`
are a new Godot adaptation informed by Lua 4.0's `lundump.c`, `lopcodes.h`, and
`lvm.c`, copyright (C) 1994–2000 TeCGraf, PUC-Rio. This is an altered implementation,
not the original Lua runtime. The original permission notice is included in
`licenses/Lua-4.0.txt`. Reference source: https://www.lua.org/ftp/lua-4.0.tar.gz .

The custom-map script compiler `game/native/el_lua.c` builds the unmodified Lua 4.0.1
parser and code generator in `game/native/lua40/` (copyright (C) 1994–2000 TeCGraf,
PUC-Rio; permission notice in `game/native/lua40/COPYRIGHT` and `licenses/Lua-4.0.txt`).
`src/content/lua_compiler.gd` is a GDScript adaptation of the same compiler.

## Bink movie decoder

`src/content/bink.gd` and `src/content/bink_audio.gd` are GDScript ports of the
Bink container, video and audio decoders of FFmpeg (`libavformat/bink.c`,
`libavcodec/bink.c`, `libavcodec/binkdsp.c`, `libavcodec/binkdata.h`,
`libavcodec/binkaudio.c`; Konstantin Shishkov, Peter Ross and the FFmpeg
developers), taken from the Cursed Lands engine by TheWWWorm, where they were
first ported. These two files are licensed under the
[GNU Lesser General Public License 2.1](licenses/LGPL-2.1.txt) (or later), not
under the project's Apache-2.0 license. Their FFmpeg reference source is
available at https://ffmpeg.org/download.html .

The movie cache (`src/content/movie_cache.gd`) and movie player
(`src/render/movie_player.gd`) are adapted from the Apache-2.0 licensed Cursed
Lands engine by TheWWWorm. See LICENSE.md.

## Installer decoder

The GOG installer reader (`src/content/inno_setup.gd`, `src/content/lzma.gd`) is
adapted from the Apache-2.0 licensed Cursed Lands engine by TheWWWorm. Its LZMA
decoder, and the compiled copy in `native/el_lzma.c`, follow Igor Pavlov's
public domain reference decoder (`LzmaSpec.cpp` in the LZMA SDK,
https://www.7-zip.org/sdk.html); the LZMA2 framing follows xz's public domain
`lzma2_decoder`. `native/include/gdextension_interface.h` is part of Godot and
is distributed under Godot's MIT license.

## Logs and crash reports

The crash report (`src/content/crash_report.gd`) and its box
(`src/render/crash_report_box.gd`) are adapted from the Apache-2.0 licensed
Cursed Lands engine by TheWWWorm. See LICENSE.md.

## Optional NVIDIA DLSS and Reflex

The Windows build with graphics SDKs includes NVIDIA Streamline 2.14.16 and its
signed production components for NVIDIA DLSS (Super Resolution, DLAA, Ray
Reconstruction and Frame Generation), NGX and NVIDIA Reflex, under their
respective licenses in `licenses/NVIDIA/`. They are not covered by the
project's Apache-2.0 license. Streamline's integration code is MIT licensed.
This software contains source code provided by NVIDIA Corporation. Other
builds (the Compatibility renderer, the browser, Android, Linux, macOS and the
ordinary Windows build) contain none of these components.

NVIDIA, the NVIDIA logo, GeForce RTX and DLSS are trademarks and/or registered
trademarks of NVIDIA Corporation in the U.S. and other countries. The GeForce
RTX artwork in `game/assets/branding/vendors/` and the splash variants made
from it (`game/assets/branding/splash-graphics.png`, `splash-nvidia.png`) are
excluded from the project's Apache-2.0 license; see
`game/assets/branding/vendors/NOTICE.md`. They are shown on the splash screen
and in the credits with NVIDIA's approval.

## Optional AMD FSR

The Windows build with graphics SDKs includes the signed AMD FidelityFX SDK
2.4.0 Vulkan loader, upscaler and frame-generation libraries
(`amd_fidelityfx_*_vk.dll`) for AMD FSR 3.1 and FSR 4 upscaling and frame
generation. Their license and third-party notices are supplied under
`licenses/AMD-FidelityFX/`. These binaries retain their own terms and are not
relicensed under the project's Apache-2.0 license. The SDK API headers retain
their original MIT notices.

AMD, the AMD Arrow logo, AMD FSR and combinations thereof are trademarks of
Advanced Micro Devices, Inc. The official AMD FSR Upscaling and AMD FSR Frame
Generation lockups in `game/assets/branding/vendors/` and the splash variants
made from them (`splash-graphics.png`, `splash-fsr.png`) retain AMD's
trademark rights and are not covered by the project's Apache-2.0 license.
