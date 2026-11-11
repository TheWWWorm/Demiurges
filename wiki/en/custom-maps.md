---
title: Custom maps
category: modes
order: 50
summary: Playing Etherlords II maps made with the map editor
---
Maps made with the Etherlords II map editor play like the shipped missions. They are listed in **Single → Mission** after the game's own maps. A chosen map shows its picture above the description and plays its own music.

## Adding a map

- On the Mission screen, **Import map…** takes a map's `.zip` archive and copies the map into the remake's maps folder. The map is chosen at once.
- **Maps folder** opens that folder. Copy a map's files into it, or into a folder of their own inside it, then open the Mission screen again.
- Maps the editor saved into the game's own `Maps\Custom` folder are listed too.

The maps folder is `maps` inside the folder where saves are kept (see [Main menu, saves and settings](main-menu)).

## What a map consists of

A map is a set of files that share its name:

| File | Content |
|---|---|
| `.sbm` | the map as the game plays it: title, description, terrain, objects, players, heroes and creatures |
| `.smp` | the map editor's copy of the same map (optional) |
| `.scp` | scripts: the map's own story and the battle scripts of its creatures |
| `.bm1` | the minimap |
| `.png`, `.bmp`, `.bm2` | pictures; the first one found is shown on the Mission screen |
| `.mp3` | music played while the map is chosen |

A map needs one of the two. Most published maps bring only the `.sbm`, which is enough: just copy the map's folder into the maps folder. When both are there, the remake plays the `.smp`; a map with only a `.smp` takes its title from it. When a map's `.smp` and `.sbm` are named differently but are the only two in their folder, they count as one map.

Scripts may sit in sub-folders: a map that names `Maps\Custom\CtT\Hero.scp` finds `CtT\Hero.scp` next to it. All custom maps share these names, so two maps with a script of the same name and folder use the same file.

An import copies only these files from the archive, keeping their sub-folders, and ignores everything else.

## Scripts

A map's scripts are plain Lua text written for the original game. The remake compiles them when the map starts and runs them with the same commands as the shipped missions. If a script stops with an error, the message names the script and the line; please report such a map together with its archive (see [Troubleshooting](troubleshooting)).

Scripts may use the original game's map commands that no shipped mission calls: scripted hero animations, point lights, camera pitch and scroll queries, and reading or removing commands in the queue. Their arguments are not documented, so they follow the related commands; a map that uses one differently may look different from the original.

## Saves

A save of a custom map records which map it belongs to. It loads only while that map is in place and unchanged: a missing map or one whose files changed since the save (an updated version, for example) is reported instead of loaded.
