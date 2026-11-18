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
| Sharper icons | Spell icons, portraits, skills and other icons can be enlarged once on your computer by a small AI model (Real-ESRGAN realesr-general-x4v3) and drawn with more pixels at the same size. The difference shows on screens larger than 1440 × 900. On by default where the computer has at least four cores; not in the browser. The enlarging is a separate step, **Preparing sharper art**, never done during play: on the first start (or after turning a switch on, or when the game's files or the screen changed) the game asks first, with the time and disk space it needs, and starts only on **Start**; **Later** leaves it for Options. The step shows a progress bar, the sheets done and the time left, and uses Vulkan inference on supported Windows PCs and otherwise uses all processor cores but one; **Cancel** keeps what is done and the next run goes on from there. Until a sheet is ready its original is shown; finished pictures are read when a screen loads its art, never swapped while a screen is up. |
| Sharper interface | The same for the rest of the interface art: screens, panels, frames, buttons and the battle and map panels. Layout, sizes and clickable areas stay exactly as before; digits and tiny glyphs are left as they are. |
| Sharper textures | Prepares 2× color textures for opaque creatures, heroes, and battle scenery. Available at any screen size. Off by default. The game reads prepared textures when it loads scene art. |
| Prepared sharper art | How far the prepared pictures are (**Ready**, or how many sheets of how many) and the disk space they take. **Prepare now** opens the preparing step; **Clear** removes the pictures. They are kept in the game's user folder (`upscaled`) as lossless WebP, with the interface scale chosen for the screen and a fixed 2× scale for scene textures. |

The DLSS and FSR vendors set up when the game starts, so switching between NVIDIA and AMD, or switching frame generation on, may need a restart: a message says so and offers **Restart now**. The renderer they need is chosen on the Path tracing page.

## Graphics

| Setting | What it does |
|---|---|
| Shadows | Shadows of figures in battles and of trees, rocks and buildings on maps. |
| Soft shadows | Softer shadow edges. Off at first. |
| Terrain detail | Subtle texture and relief on map ground and fine grain on battle ground. Off at first. |
| Enhanced water | Reflected scenery, animated ripples, and soft shoreline foam on the adventure map. Bog water has gentler ripples. In Etherlords II, rain adds rings to the water while Map weather is enabled. Off at first. |
| Bloom | Fire, lightning, auras and other glowing effects shine with a soft halo. Only what is drawn brighter than white blooms, so daylit scenery and even snowfields are left as they were. Off at first; always on while path tracing. |
| Soft particles | Smoke, fire and magic fade where they meet the ground, walls and figures instead of ending in a hard line. Off at first. |
| Spell light | In battles, glowing effects light the figures and scenery around them, so a wall of fire or a brazier really casts light. Adventure maps have none: their ground and scenery are drawn unlit. On at first on computers, off in the browser and on phones. Path tracing traces this light itself. |
| Map weather | Rain, snow and other weather on adventure maps. |

The first start weighs this computer and switches on the Graphics settings it can hold at 60 frames a second, so a fast machine is set up without your looking for anything. A version that adds a setting of this kind weighs the computer once more, for that setting alone, and leaves everything you have chosen since as it is.

If the game closes unexpectedly while a battle or a map is on screen, the settings it was drawing with out of Bloom, Soft particles and Spell light go off at the next start, and the report box names them. A session that ends in the menus says nothing about them and leaves them on.

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
| Duel AI | How strong the computer opponent is in the battles of both games: **Easy** (the original opponent thinking less), **Original** or **Smarter** (the default). Puzzles are always defended by the smarter opponent. |
| World AI | Etherlords single player: how the computer players act on the map: **Original**, **Smarter** (the default: computer heroes also learn skills, shop for spells and runes, and computer players cast global spells) or **Living world** (smarter, and idle heroes also patrol, raid, escort and go back for runes). |
| Free movement | Etherlords single player: heroes move as soon as you confirm a route and may move several times a day; computer players move the same way when you end the day. Off: the original orders, carried out together at night. On at first. |
| Opponent's spells as icons | Etherlords battles: the opponent's spells show as icons at the top left, as in Etherlords II, instead of red messages, and your own spells are not listed. Point at an icon for the spell's description. On at first. |
| Battle dome in the first game | Etherlords: when a battle is about to start on the map, Etherlords II's ether dome rises over both sides, with its sound. Needs Etherlords II installed. On at first. |
| Discord activity | Shows in the Discord desktop app which game you play and whether you are in the menus, on a map or in a battle. Nothing else is shared. On at first. |

Each campaign and single scenario keeps its own **Duel AI** and **World AI**, saved with it and carried to the next chapter. The same two choices are shown beside the difficulty when you begin one: on the lowest difficulty (**Easy**) they start at **Original**, on the others at the choices made here outside a game, and changing the difficulty puts that difficulty's back; you can still change them before you begin. During a game, these Options change that game's choices. A save from before games kept them gets **Original** at the lowest difficulty and the choices here at the others. Standalone duels, puzzles and network games use the choices here.

New Etherlords campaigns and single scenarios start with **AI fights neutral monsters** checked. It locks **World AI** to **Living world** so computer heroes forecast and play neutral fights. Clear it on the difficulty screen for the original automatic wins. The choice is saved and carries into the next chapter.

## Hotkeys

Choose a game and select a shortcut to change it. Press a key or key combination, or press **Esc** to cancel. **Reset defaults** restores the selected game's shortcuts for battle, maps and shops.

On the remake's pages, **Export log…** saves a log with system information for a [problem report](troubleshooting), and **Game files…** adds, switches or removes a game: see [Installing the game files](installing). In builds with DLSS and FSR an **About** page lists their credits.

Choices this computer cannot use are greyed out, and the line under the setting says why. Leave the heavier settings (path tracing, soft shadows, terrain detail, spell light, 4× anti-aliasing) off on devices where they slow the game down.
