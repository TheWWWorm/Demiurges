# Engine overview

Demiurges is a Godot 4.7 project in [`game`](../game). It uses the Compatibility renderer, so the same code runs on desktop, in the browser and on Android.

## Two games, one engine

Each game is mounted as its own profile (`ELProfile`, `src/content/profile.gd`): the installation folder, its resource archives (with numbered patch archives layered on top), game tables, texts and caches. Etherlords and Etherlords II share names for many spells and assets, but a name never resolves through the other game's profile, and each game's rules, saves and caches stay separate. A battle or campaign always uses one game's rules.

The game is recognised from its files: both need `Resources/figures.res`, `crfigures.res`, `textures.res`, `regs.res` and `text.res`; `Campaigns/good.cpg` marks Etherlords and `Campaigns/white.cpg` Etherlords II.

## Code layout

- `src/content/` reads the original formats (resource archives, textures, models, animations, sound, Bink movies, tile sets, maps, campaign files and the second game's Lua 4 scripts) and holds the campaign logic: map sessions, encounters, shops, buildings, resources, heroes and saves.
- `src/duel/` is the battle engine. `ELDuel` (`state.gd`) holds the rules and state without depending on the scene tree, so battles can be saved, replayed and checked headlessly. The computer opponent issues the same commands as the player.
- `src/render/` draws the battlefield, the adventure map, the original interface screens and menus, and plays movies.
- `web/` holds the browser page and its local-file support (see below).
- `scenes/duel.tscn` is the main scene.

## Where game files come from

- **Desktop:** the player chooses an installed game folder. Paths are kept in `profiles.json` in the user folder. `tools/import_game.py` can register a folder or unpack a GOG installer with innoextract.
- **Android:** the player picks the GOG installer or a data pack. `ELContentImport` copies it into app-private storage (`content/el1` or `content/el2` in the user folder). The installer is read with a built-in Inno Setup and LZMA reader; nothing is executed.
- **Browser:** `web/files.js` imports the installer (`web/installer-worker.js`), the game folder or a data pack into IndexedDB. Before the engine starts, the page mounts a read-only file system at `/gamedata/el1` and `/gamedata/el2`, so the engine reads the files like any folder. Reads go through a small worker (`web/data-worker.js`) and a shared buffer, which is why the page must be cross-origin isolated.

A data pack (`.elpack`) is a simple container made by `tools/prepare_game_data.py`: the magic `ELPACK01`, a 32-bit header length, a JSON index of `{path: {offset, size}}` with lower-case paths, then the file contents.

## Saves

Saves, settings, replays and converted movies live in the engine's user folder (`user://`). Their names include the game, so the two games never overwrite each other.
