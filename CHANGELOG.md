# Changelog

## 0.2.2

- Interface:
  - The credits of both games use the originals' Arial lettering and sizes instead of a serif face.
  - In Etherlords II the specialisation lists' scroll thumb sits under the arrows and travels between them as in the original.
  - The ring under a selected or hovered hero on the map has the original's size in both games (it was drawn too small); in Etherlords I this also applies to roaming creatures.

## 0.2.1

- Battles:
  - In the first game, Overload, Enfeeblement and Second Birth now show their original cast effects and sounds.
  - In both games, Overload's weakening at the end of each of its holder's turns is shown on the creature.
  - Spell and hit sounds and map sounds are placed left or right by where they happen on screen, as in the originals, and follow the Reverse stereo option. In the first game, building sounds also fade with distance as in the original.
- Replays:
  - Etherlords II replays recorded by the original game play every kind of recorded action, including hero abilities, every spell target, surrender, and spells cast by battle scripts.
- Interface:
  - Interface text uses the originals' Arial lettering instead of a serif face: the Etherlords II map panel and its screens, and the shared menus, duel, options, mission, replay and encyclopaedia screens in both games. Text is sized as in the originals. The main menu buttons keep their original serif.
- Fixes:
  - Loading saves or starting chapters many times in one session no longer uses more and more memory.

## 0.2.0

- Platforms:
  - Every version, including Windows, Linux and macOS, can import the GOG installer (`setup_etherlords*.exe`) or a data pack directly; the installer is unpacked without being run.
- Battles:
  - Combat resolution plays as in the originals: attackers run to the fight one after another, blows and hits are timed like the games', and the first blow and the winner get their close-ups.
  - Many more spells, creature abilities and artifacts now show their original effects and play their original sounds, with sound fading by distance.
  - The hand rail works like the originals: one icon per card with the remaining charges (runes in the first game) in the original digits, drawn cards enter at the left and returned cards at the right, new cards drop in and the rail scrolls to show them.
  - A held right button previews a character's spells and abilities on the strip; the hand and artifact lists use the original look.
  - Computer opponents plan their turns closer to the originals, including how the second game's computer counts on specialisation.
  - The first game deals opening hands the way the original does.
- Campaigns and maps:
  - Ground shadows under buildings and terrain objects, unexplored mist closer to the originals, and opened runestone barriers sink into the ground instead of vanishing.
  - The second game's message panel, loot reports, carried-card cursor and inventory and shop tooltips follow the originals.
  - The first game's trade dialog.
  - Fixes for quest states and saves found while checking every authored quest of the second game.
- Fixes:
  - Kobold models display correctly.
  - Several options that had no effect now work as in the originals.

## 0.1.0

First public preview.

- Engine:
  - One engine plays both Etherlords and Etherlords II from your own game files. Each game keeps its own rules, files and saves; either one is enough, and both can be installed together.
  - Reads the original models, textures, animations, terrain, music, sounds, videos, texts, maps, campaign files and scripts. Nothing from the games is included.
- Campaigns:
  - Both campaigns of each game are playable, with the original maps, dialogue, scripted events, shops, buildings, resource sites, heroes, experience, level-ups and spellbooks.
  - The first game's single missions and the second game's tutorial are available.
  - Campaign and mission saves, quick save and quick load.
- Battles:
  - Original creatures, spells, abilities, enchantments, artifacts and battlefields of both games, with automatic combat and computer opponents.
  - The original Duel screen with presets and the hero editor, practice battles, local hot seat, and Etherlords II duel replays.
  - Automatic battle camera: spells, the first blow of a fight and the winner get close-ups along the games' own camera tracks. The Camera dynamics option sets how often they happen, and the numbers over creatures can be hidden during close-ups.
- Interface:
  - The original main menu, campaign, mission, save and load screens, Options, map interface and battle screen, using the games' own art and texts.
  - Reversed stereo option for speakers or headphones with swapped channels.
- Platforms:
  - Windows (x86-64), Linux (x86-64) and macOS (Apple silicon and Intel) packages.
  - Browser version: import the GOG installer, the installed game folder or a data pack once; the files stay in the browser's storage on your device.
  - Android preview: import the GOG installer or a data pack into the app.
  - `tools/prepare_game_data.py` makes a data pack from an installed game.
- Known gaps: some spell effects, several options, a few English messages, approximate computer opponents, no network multiplayer, no videos in the browser and basic touch support. See the README for details.
