# Changelog

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
