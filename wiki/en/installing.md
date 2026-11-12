---
title: Installing the game files
category: start
order: 10
summary: Game folder, GOG installer or data pack
---
Demiurges reads the files of a game you own. It needs either game, or both: each game keeps its own rules, files and saves. Nothing is downloaded for you and no game content comes with the engine.

## Download the engine

Get the package for your system from the [releases page](https://github.com/TheWWWorm/Demiurges/releases), or [play in the browser](browser) without installing anything.

| System | What to do |
|---|---|
| Windows (x86-64) | Extract the ZIP and run `Demiurges.exe`. SmartScreen may warn about an unrecognised app: choose **More info → Run anyway**. |
| Linux (x86-64) | Extract the archive and run `Demiurges.x86_64`. If needed, run `chmod +x Demiurges.x86_64` first. |
| macOS | Extract the ZIP and open `Demiurges.app`. The app is not signed: right-click it and choose **Open**, or allow it under **System Settings → Privacy & Security**. |
| Android 7+ | Install the APK and allow your browser or file manager to install apps when asked. |

## Add a game

At the first start the game files screen opens. Choose **Etherlords I** or **Etherlords II** at its top, then one of:

- **the game folder**: the folder of your installed game, the one containing `Resources` and `Campaigns`;
- **the GOG offline installer** (`setup_etherlords*.exe`). It is **not run**: the engine unpacks the game files from it once and keeps them in its own data folder, so you do not need the installer afterwards;
- **a data pack** (`.elpack`, see below).

**Steam copies** are found automatically on Windows, Linux and macOS: at the first start the engine uses any it finds, and the game files screen offers **Use the Steam copy** for a game not set up yet.

Your choice is remembered. The original start-up videos play and then the [main menu](main-menu) opens. Repeat this for the other game to keep both.

## Data packs

A data pack holds the files of one game in a single file. It is useful on a phone that has neither the installer nor the game folder: make the pack on your computer with the `prepare_game_data.py` script from the project (it needs Python 3) and copy it to the phone:

`python3 prepare_game_data.py "/path/to/Etherlords II" Etherlords2.elpack`

> The installer and the data pack contain your own game files. Keep them to yourself.

## Adding, switching and removing games

**Game files…** on the remake pages of **Options** opens the same screen at any time to add a game, switch to another one or remove one. Removing a game keeps its saves and settings and never deletes an installed game folder.
