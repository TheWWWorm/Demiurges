# Demiurges

Play **Etherlords** («Демиурги», Nival, 2001) and **Etherlords II** («Демиурги II», 2003) on a modern engine on Windows, Linux, macOS and Android or in your browser.

Demiurges is a fan-made replacement engine built in Godot. It reads the game files you already own (models, textures, animations, sounds, music, texts, maps, campaign scripts and game tables) and plays them with newly written combat, campaign, interface and rendering systems that follow the original games' rules.

> **You need your own copy of the game you want to play.** No game content ships with this engine and nothing is downloaded for you. The GOG versions are the tested editions. Either game is enough; with both, you can switch between them. Each game keeps its own rules, files and saves.

## Play in your browser

**[Play at demiurges.wwworm.com](https://demiurges.wwworm.com/)** - nothing to install. Open the page, press **Play** and choose one of:

- the GOG offline installer (`setup_etherlords*.exe`). It is **not run**: the browser unpacks the game files from it once and checks each one. This takes a few minutes and needs about 1.5 GB (Etherlords) or 3 GB (Etherlords II) of browser storage;
- the folder of your installed game (the one containing `Resources` and `Campaigns`), in desktop browsers;
- a game data pack (`.elpack`), if you made one.

Repeat this for the other game to keep both. Your files are never uploaded: the game reads them on your own device and keeps its copy in your browser's storage, so the next start is quick.

A data pack is optional. It helps on a phone that has neither the installer nor the game folder: make the pack on your computer and copy it to the phone. You need Python 3 and the [`tools/prepare_game_data.py`](tools/prepare_game_data.py) script from this repository:

```sh
python3 prepare_game_data.py "/path/to/Etherlords II" Etherlords2.elpack
```

The installer and the pack hold your own game files, so keep them to yourself.

The browser version needs WebGL 2 and a desktop-class browser or a recent phone with plenty of memory. Unpacking a large game in the browser needs a lot of memory for a short time; if it fails on a phone, use a data pack. Intro and ending videos are not played in the browser yet. Browsers can clear their storage, so keep your installer or pack.

## Download and install

Download the package for your system from the [Releases](https://github.com/TheWWWorm/Demiurges/releases) page.

- **Windows (x86-64):** extract the ZIP and run `Demiurges.exe`. The program is not signed, so Windows SmartScreen may warn about an unrecognised app; choose **More info → Run anyway**.
- **Linux (x86-64):** extract the archive and run `Demiurges.x86_64`. If your file manager dropped the executable permission, run `chmod +x Demiurges.x86_64` first.
- **macOS (Apple silicon and Intel, one universal app):** extract the ZIP and open `Demiurges.app`. The app is not signed or notarized, so macOS may refuse the first start: right-click (or Control-click) the app and choose **Open**, or allow it under **System Settings → Privacy & Security**. You can also run `xattr -dr com.apple.quarantine Demiurges.app` in Terminal.
- **Android 7+ (ARM64 / x86-64), preview:** install the APK; allow your browser or file manager to install apps when it asks. On first start, choose a game data pack (`.elpack`, see [Play in your browser](#play-in-your-browser)) or the GOG installer (`setup_etherlords*.exe`), which is unpacked without being run. Unpacking the installer takes longer on a phone than on a computer; a data pack is quicker still.
- **Browser (WebGL 2):** nothing to download; [play the hosted version](https://demiurges.wwworm.com/), see above.
  To host the browser version yourself, use `…-web.zip`. It needs HTTPS (or `localhost`) and the `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers (included in its `_headers` file); see [hosting the browser version](docs/hosting.md).

## Getting started (desktop)

1. Start the engine.
2. When asked, choose one of:
   - **Etherlords I folder** or **Etherlords II folder**, then the folder of your installed game, the one containing `Resources` and `Campaigns`;
   - **GOG installer or data pack…**, then the GOG offline installer (`setup_etherlords*.exe`) or a data pack (`.elpack`). The installer is **not run**: the engine unpacks the game files from it once (usually well under a minute) and keeps them in its own data folder, so the installer is not needed afterwards.
3. Your choice is remembered. The original start-up videos play, then the main menu opens.

To add the other game later, start a battle, press **Esc**, choose **Remake menu…** and then **Original game content…**.

You can also unpack the installer yourself with the included Python tool (it needs [innoextract](https://constexpr.org/innoextract/)), which registers the result:

```sh
python3 tools/import_game.py el1 /path/to/setup_etherlords.exe --dest /path/to/Etherlords
python3 tools/import_game.py el2 /path/to/Etherlords2
```

## What you can play

- **Both campaigns** of each game, with the original maps, dialogue, scripted events, shops, buildings, heroes, experience and level-ups, resource sites and spellbook management. Chapters follow the original order and branches.
- **Single missions** of the first game and the second game's tutorial.
- **Duels**: the original Duel screen with its presets and hero editor, practice battles against the computer and local hot seat for two players. Etherlords II duels can be replayed.
- **Combat** with the original creatures, spells, abilities, enchantments, artifacts and battlefields of both games, including automatic combat.
- **Automatic battle camera**: spells, the first blow of a fight and the winner get close-ups along the games' own camera tracks before the view returns to yours. **Camera dynamics** in Options sets how often they happen, and the numbers over creatures can be hidden during close-ups. Moving the camera yourself ends a close-up at once.
- **Original interface**: the main menu, campaign and mission screens, Options, saving and loading, the map interface and the battle screen use the games' own art and texts.
- **Language**: texts come from your copy of the game.

## Not finished yet

The engine is still in development. Things you may notice:

- The darkening of a few large spells is an approximation, and the exact moment some ability effects start may differ slightly from the originals.
- A few rare messages are still shown in English, mostly in the Duel editor and in error messages.
- Computer opponents follow the original's approach but are not an exact copy of its decisions. As in the original, they never answer alliance or trade offers.
- Etherlords II map particle effects use approximate sizes and blending.
- The campaigns are tested screen by screen and system by system, not yet by playing every chapter from start to finish. Please report anything that blocks progress.
- There is no network multiplayer. Local hot seat duels work.
- Saves and replays of the original games cannot be loaded; the engine keeps its own.
- Touch controls have not yet been tried on real phones and tablets, only in testing. The interface keeps the original layout, so on a small phone screen text and buttons are small.

Please report problems on the [Issues](https://github.com/TheWWWorm/Demiurges/issues) page.

## Controls

The original controls work as in the games. A few useful keys:

| Key | Battle | Map |
|---|---|---|
| Left click | choose a spell, creature or target | move, talk, visit or attack |
| Space | end the current phase | continue a conversation |
| Esc | cancel targeting, or open the game menu | close a window, or open the game menu |
| F5 / F9 | quick save / quick load | quick save / quick load |
| Right drag, wheel | turn and zoom the camera | turn and zoom the camera |
| R | reset the camera | |
| W A S D, arrows | | move the camera |
| H or Home | | follow the selected hero |
| I / K | | spellbook / skills (first game) |
| N | | end the turn (first game) or the day (second game) |

**Touch screens** (phones, tablets and touch browsers) have their own controls:

| Gesture | Battle | Map |
|---|---|---|
| Tap | as a left click | as a left click |
| Touch and hold | right click; on a button, its tooltip | right click (Etherlords II: the information panel while held) |
| Drag with one finger | turn the camera | move the map |
| Drag or twist with two fingers | turn and tilt the camera | turn and tilt the camera |
| Pinch | zoom | zoom |

A small bar at the top of the screen gives **Back** (Esc) everywhere, **Camera** (reset) in battle and **Save** / **Load** (quick save and load) on the map. On Android the Back button also works as Esc.

## Saves and settings

Saves and settings are kept in the engine's user folder:

- **Linux:** `~/.local/share/godot/app_userdata/Etherlords Duel`
- **Windows:** `%APPDATA%\Godot\app_userdata\Etherlords Duel`
- **macOS:** `~/Library/Application Support/Godot/app_userdata/Etherlords Duel`
- **Browser:** in the browser's storage for this site. Clearing the site's data removes them.
- **Android:** in the app's private storage. Uninstalling the app removes them.

The folder keeps its earlier name, `Etherlords Duel`, so existing saves continue to work.

In **Remake settings**, **Terrain detail** adds subtle texture contrast and surface relief to adventure-map ground, and fine grain from the original detail textures to battle ground where available. **Soft shadows** smooths sun-shadow edges in battles and on Etherlords II maps. Both start off and can be changed during play; leave them off on devices where they reduce performance.

## Building from source

The engine source is in [`game`](game). Open it in [Godot 4.7](https://godotengine.org/) and press Play, or export it with the included presets.

- **Windows, Linux, macOS:** `godot-4 --headless --path game --export-release "Windows Desktop" ../build/windows/Demiurges.exe`, with `Linux` and `../build/linux/Demiurges.x86_64`, or `macOS` and `../build/macos/Demiurges.zip`. The output path is relative to `game`; create the folder first.
- **Browser:** `python3 tools/export_mobile.py web --output build/web`, then `python3 tools/serve_web.py build/web` and open `http://localhost:8060/`. The Web template's export alone is not enough: this tool also adds the page's local-file support, icons, offline cache and headers.
- **Android:** `python3 tools/export_mobile.py android --output build/android --sdk /path/to/android-sdk --java /path/to/jdk` (needs the Android SDK, a JDK 17 or newer and Godot's Android export templates).

The GOG installer is unpacked by a small compiled library in [`game/native`](game/native), prebuilt for every exported platform in `game/native/bin`. To rebuild it, run `python3 game/native/build.py --zig /path/to/zig --ndk /path/to/android-ndk` ([Zig](https://ziglang.org/) builds the Windows, Linux and macOS libraries, the Android NDK the Android ones). Without the library the engine still imports installers, only much more slowly.

The Godot export templates for 4.7 must be installed. See [the engine overview](docs/engine_overview.md) for how the code is organised.

## License

The engine's code is licensed under the Apache License 2.0 (see [LICENSE.md](LICENSE.md)); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components, including the movie decoder under the LGPL 2.1. Etherlords, Etherlords II and all of their content belong to their respective owners and are not part of this project. This project is not affiliated with Nival or the publishers of the games.
