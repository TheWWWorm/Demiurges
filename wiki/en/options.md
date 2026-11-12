---
title: Options
category: start
order: 50
summary: The original options and the remake's settings on one screen
---
**Options** opens the Options screen of each game, from the main menu, the game menu, the Esc menus and the auto chess menu. It is the original screen with the remake's own settings joined to it: the buttons left of the frame switch between the two original pages and the remake's pages, which open inside the same frame.

On the remake's pages a **?** after each setting's name explains it: point at the **?**, or click or tap it. A short line under a setting says when it cannot be used and why.

**✓** keeps every change and **✗** (or **Esc**) cancels every change made since the screen opened, on the original pages and the remake's alike. The remake's settings show their effect at once while you try them. Each game keeps its own original options; the remake's settings are shared by both games.

## Original pages

The page buttons beside the frame take the place of the original page tabs; the page's name heads the frame. These work as in the games: autosave, faster map movement, animated objects, ambient sounds, hero voices, the tutorial, spells in [automatic combat](automatic-combat), the **Automatic camera** and **Automatic camera dynamics** (how often close-ups happen), what is shown in battle (**Combat phases**, **Power/toughness values**, **Abilities icons**, **Attacking/blocking order**, blood), camera speeds, music and effects volumes, gamma and reversed stereo. A few options are kept but have no effect yet.

## Display

The game window settings are on computers only (not the browser or phones); the picture settings are everywhere.

| Setting | What it does |
|---|---|
| Window mode | A window, borderless full screen or exclusive full screen. |
| Resolution | The window's size. Full screen always uses the display's own resolution. |
| Frame rate | The display's refresh rate with V-Sync, a frame cap, or unlimited. |
| Frame rate counter | Frames per second in the top right corner. Off at first. With frame generation running it shows the frames shown and, in brackets, the frames rendered. |
| Upscaling | Windows builds with NVIDIA DLSS and AMD FSR only. **Off**, **NVIDIA DLSS** or **AMD FSR**; the AMD entry names the FSR this graphics card gets (**FSR 4** where the AMD SDK reports it, otherwise **FSR 3.1**). The 3D scenes are rendered at a lower resolution and rebuilt, smoothing edges in place of Anti-aliasing. Entries this computer cannot use are greyed out. Needs **Forward+ (Vulkan)**. Off at first. |
| Upscale quality | With an upscaler chosen: **Native AA** (**DLAA** with DLSS) keeps the full resolution and only smooths, **Quality**, **Balanced** and **Performance** render at lower resolutions for more frames. Quality at first. |
| Frame generation | Windows builds with NVIDIA DLSS and AMD FSR only. Adds generated frames on maps and in battles: **NVIDIA DLSS Frame Generation** with DLSS upscaling (needs a GeForce RTX 40 series or newer GPU; turns on NVIDIA Reflex), otherwise **AMD FSR Frame Generation** (with FSR upscaling or without upscaling). The line under it says which one your settings use. It pauses in menus, loading screens and movies and while the window is in the background. While AMD frame generation runs, the frame rate is held just under half the display's refresh rate (or your lower **Frame rate** cap). Off at first. |
| Anti-aliasing | Smoother edges in 3D: automatic, off, 2× or 4×. |
| Sharpening | Sharpens 3D textures. Choose off (default), light, or strong. Off matches the soft textures of the original games. |

The DLSS and FSR vendors set up when the game starts, so switching between NVIDIA and AMD, or switching frame generation on, may need a restart: a message says so and offers **Restart now**. The renderer they need is chosen on the Path tracing page.

## Graphics

| Setting | What it does |
|---|---|
| Shadows | Shadows of figures in battles and of trees, rocks and buildings on maps. |
| Soft shadows | Softer shadow edges. Off at first. |
| Terrain detail | Subtle texture and relief on map ground and fine grain on battle ground. Off at first. |
| Enhanced water | Reflected scenery, animated ripples, and soft shoreline foam on the adventure map. Bog water has gentler ripples. In Etherlords II, rain adds rings to the water while Map weather is enabled. Off at first. |
| Map weather | Rain, snow and other weather on adventure maps. |

### Path tracing

**Path tracing…** on the Graphics page opens its own page (the arrow at its top goes back).

| Setting | What it does |
|---|---|
| Renderer | **Compatibility** (the default) runs on more computers. **Forward+ (Vulkan)** is needed for path tracing, DLSS and FSR (choosing DLSS or FSR on the Display page also chooses it). **Restart now** restarts the game with the chosen renderer. The line under it says whether your computer can use path tracing. |
| Path-traced lighting | Real shadows, sky light, light bounced between surfaces, and light from fire and spells, on maps and in battles. Needs Forward+ and a graphics card with ray tracing. It costs about 2–3 ms a frame on a fast card. **F7** switches it during play. |
| Sky light | How much the sky lights shade, 0–200%. Lower gives deeper, more contrasting shadows; sunlit ground stays the same. |
| Light bounces | How many times light bounces between surfaces, 1–4 (2 by default). More fills corners and shade with reflected colour and costs more time a frame. |
| DLSS Ray Reconstruction | Windows builds with NVIDIA DLSS only. With path tracing on and **NVIDIA DLSS** upscaling, the traced light goes unsmoothed to DLSS Ray Reconstruction, which removes its noise in place of the path tracer's own smoothing. Off at first. |

### Debug

At the bottom of the Path tracing page.

| Setting | What it does |
|---|---|
| Show light only | A debugging view: shows the traced light without textures, to see what the path tracer does (**Shift+F7**). Not kept after a restart. |

## Interface

| Setting | What it does |
|---|---|
| Movies | Off, original size or fit to the screen. |
| Remake helper overlay | The remake's readouts, hints and shortcut buttons over the original screens. Off at first. |
| Battle interface size | The size of the battle panel at the bottom of the screen: **Automatic**, **Small (1×)**, **Medium (1.5×)**, **Large (2×)** or **Largest (3×)**. Smaller sizes show more spell slots across the screen; 1×, 2× and 3× keep the original art sharp. |
| Ambience | The volume of the remake's own background sounds of maps and battles. |
| Smarter computer players, Free movement | Etherlords single player: the remake's computer players and hero movement. On at first. |
| Discord activity | Shows in the Discord desktop app which game you play and whether you are in the menus, on a map or in a battle. Nothing else is shared. On at first. |

## Hotkeys

Choose a game and select a shortcut to change it. Press a key or key combination, or press **Esc** to cancel. **Reset defaults** restores the selected game's shortcuts for battle, maps and shops.

On the remake's pages, **Export log…** saves a log with system information for a [problem report](troubleshooting), and **Game files…** adds, switches or removes a game: see [Installing the game files](installing). In builds with DLSS and FSR an **About** page lists their credits.

Choices this computer cannot use are greyed out, and the line under the setting says why. Leave the heavier settings (path tracing, soft shadows, terrain detail, 4× anti-aliasing) off on devices where they slow the game down.
