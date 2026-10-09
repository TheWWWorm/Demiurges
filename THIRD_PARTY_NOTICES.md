# Third-party notices

The MMP texture decoder and Nival registry reader in `src/content/` are adapted
from the Apache-2.0 licensed Cursed Lands engine by TheWWWorm. Their source is
maintained at https://github.com/TheWWWorm/CursedLands . The FIG mesh layout and
coordinate conversion also follow that engine and direct inspection of the user’s
original Etherlords files. See LICENSE.md.

Godot is distributed under the MIT license and its own third-party notices.
Original Etherlords and Etherlords II content is supplied by the player and is
not part of this engine’s source or license.

The Lua 4.0 binary reader and virtual-machine semantics in `src/content/lua_*.gd`
are a new Godot adaptation informed by Lua 4.0's `lundump.c`, `lopcodes.h`, and
`lvm.c`, copyright (C) 1994–2000 TeCGraf, PUC-Rio. This is an altered implementation,
not the original Lua runtime. The original permission notice is included in
`licenses/Lua-4.0.txt`. Reference source: https://www.lua.org/ftp/lua-4.0.tar.gz .

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
