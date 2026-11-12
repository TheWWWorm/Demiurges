---
title: Options
category: start
order: 50
summary: The original options and the remake settings
---
**Options** opens the original Options screen of each game, from the main menu or the game menu. Each game keeps its own settings.

## Original options

These work as in the games: autosave, faster map movement, animated objects, ambient sounds, hero voices, the tutorial, spells in [automatic combat](automatic-combat), the **Automatic camera** and **Automatic camera dynamics** (how often close-ups happen), what is shown in battle (**Combat phases**, **Power/toughness values**, **Abilities icons**, **Attacking/blocking order**), camera speeds, gamma and reversed stereo. A few options are kept but have no effect yet.

## Remake settings

**Remake settings…** is available on the Options screen and in the Etherlords II Esc menus on maps and in battle.

### Graphics

| Setting | What it does |
|---|---|
| Renderer | **Compatibility** (the default) runs on more computers. **Forward+ (Vulkan)** is needed for path tracing. **Restart now** restarts the game with the chosen renderer. |
| Path-traced lighting | Real shadows, sky light, light bounced between surfaces, and light from fire and spells, on maps and in battles. Needs Forward+ and a graphics card with ray tracing. It costs about 2–3 ms a frame on a fast card. **F7** switches it during play. The line under it says whether your computer can use it. |
| Show light only | Shows the traced light without textures (**Shift+F7**). |
| Sky light | How much the sky lights shade, 0–200%. Lower gives deeper, more contrasting shadows; sunlit ground stays the same. |
| Light bounces | How many times light bounces between surfaces, 1–4 (2 by default). More fills corners and shade with reflected colour and costs more time a frame. |
| DLSS Ray Reconstruction | Windows builds with NVIDIA DLSS only. With path tracing on and **NVIDIA DLSS** upscaling, the traced light goes unsmoothed to DLSS Ray Reconstruction, which removes its noise in place of the path tracer's own smoothing. Greyed out, with the reason, where the GPU, driver or settings do not allow it. Off at first. |
| Anti-aliasing | Smoother edges in 3D: automatic, off, 2× or 4×. |
| Upscaling | Windows builds with NVIDIA DLSS and AMD FSR only. **AMD FSR Upscaling** or **NVIDIA DLSS** renders the 3D scenes at a lower resolution and rebuilds the picture, smoothing edges in place of Anti-aliasing. Needs **Forward+ (Vulkan)**. Off at first. |
| AMD FSR version | **FSR 4** (a supported Radeon GPU) or **FSR 3.1** (also other GPUs), for AMD upscaling and frame generation. A version this computer cannot use is greyed out; FSR 4 never quietly becomes FSR 3.1. |
| Upscale quality | **Native AA** keeps the full resolution (DLAA with NVIDIA DLSS); **Quality**, **Balanced** and **Performance** render fewer pixels for a higher frame rate. |
| Frame generation | **AMD FSR Frame Generation** (with or without FSR upscaling) or **NVIDIA DLSS Frame Generation** (needs DLSS upscaling and a GeForce RTX 40 series or newer GPU; turns on NVIDIA Reflex) adds generated frames on maps and in battles. It pauses in menus, loading screens and movies and while the window is in the background. While AMD frame generation runs, the frame rate is held just under half the display's refresh rate (or your lower **Frame rate** cap on the Display page). Off at first. |
| Sharpening | Sharpens 3D textures. Choose off (default), light, or strong. Off matches the soft textures of the original games. |
| Shadows | Shadows of figures in battles and of trees, rocks and buildings on maps. |
| Soft shadows | Softer shadow edges. Off at first. |
| Terrain detail | Subtle texture and relief on map ground and fine grain on battle ground. Off at first. |
| Enhanced water | Reflected scenery, animated ripples, and soft shoreline foam on the adventure map. Bog water has gentler ripples. In Etherlords II, rain adds rings to the water while Map weather is enabled. Off at first. |
| Map weather | Rain, snow and other weather on adventure maps. |
| Combat blood | Blood in battles. |

### Audio

| Setting | What it does |
|---|---|
| Music, Ambience, Effects | Volumes. Ambience is the remake's own background sound of maps and battles. |

### Interface

| Setting | What it does |
|---|---|
| Movies | Off, original size or fit to the screen. |
| Map tooltips on hover | Etherlords II map tooltips without a right click. |
| Remake helper overlay | The remake's readouts, hints and shortcut buttons over the original screens. Off at first. |
| Frame rate counter | Frames per second in the top right corner. Off at first. With frame generation running it shows the frames shown and, in brackets, the frames rendered. |
| Discord activity | Shows in the Discord desktop app which game you play and whether you are in the menus, on a map or in a battle. Nothing else is shared. On at first. |

On the **Hotkeys** tab, choose an edition and select a shortcut to change it. Press a key or key combination, or press **Esc** to cancel. **Reset defaults** restores the selected edition’s shortcuts for battle, maps and shops.

At the bottom, **Export log…** saves a log with system information for a [problem report](troubleshooting), and **Game files…** adds, switches or removes a game: see [Installing the game files](installing).

Choices this computer cannot use are greyed out, and the line under the setting says why. AMD and NVIDIA cannot be mixed: switching between them asks for a restart (**Restart now**). In builds with these technologies an **About** tab lists their credits.

Leave the heavier settings (path tracing, soft shadows, terrain detail, 4× anti-aliasing) off on devices where they slow the game down.
