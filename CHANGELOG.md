# Changelog

Versions follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) from 0.3.0 on.

## 0.6.2

- Path tracing follows the hero's animated pose and visible cutout edges, removing the extra outlines around the rider and mount.
- The Ship arena supports enhanced water and preserves the planks beneath its rails. Path-traced rigging and railings flicker less.
- Ether arena vents loop without a bright flash. Bloom stays visible around bright effects with a tighter spread.
- Etherlords II battle tooltips show hero and creature details on hover or right-click.
- The battle Esc buttons have room for their labels, and the remake menu scrolls above the battle HUD.

## 0.6.1

- Path-traced lighting respects transparent cutouts when tracing shadows from foliage and figures.
- Enhanced water draws a new surface with scenery reflections, irregular ripples, and shoreline foam. The original terrain masks shape the shore.
- Remake settings are accessible from the in-game Options screen and the Etherlords II Esc menus on maps and in battle.
- Expedition encounters, camp choices, and rewards open in a dialogue. Resolve the choice to continue along the route.

## 0.6.0

- Ether Expedition is a three-act deck-building campaign for Etherlords II. Choose branching routes, draft spells, visit camps and illustrated encounters, and fight original guardians. Runs save between rooms and after settled combat actions.
- Native builds support LAN and direct-IP duels in both games, including clocks, chat, and Etherlords II reserve swaps and replay recording. The Etherlords I strategic preview adds shared nights, more original map interactions, saves, and AI takeover after a disconnect. Both players need the same build.
- The game console opens with the grave key or F10. It supports original local commands, searchable help, completion, and command history.
- Enhanced Water is optional. It adds moving shoreline detail and rain reflections. Path tracing uses more of the original arena and spell material and light data.
- Battles restore missing arena and spell effects, including Enforcements in Etherlords II. Crowded fights can display more simultaneous spell effects and lights. Space skips the current presentation and keeps the turn state. A fresh campaign battle can deal a different opening hand, while loading an active battle preserves its exact state.
- Etherlords II campaign fixes cover speaker portraits, scripted cameras and waits, boarding and landing, teleport and tunnel travel, guarded tunnel rewards, and the White Lord portal finale. The new build can recover saves stranded by the old finale order.
- The in-game wiki previews creature attacks, hit reactions, deaths, and other original animations with their available sounds.
- The Load screen recovers valid saves whose list metadata is missing or damaged. Older saves without a stored name appear under the map name and a short identifier. More console, combat, and campaign messages are shown in Russian when the interface uses Russian.

## 0.5.0

- Frame rate counter (Remake settings › Interface): frames per second in the top right corner. Off at first.
- Battles: a spell's sounds start when the caster releases it, together with its effects, instead of at the start of the gesture.
- Etherlords II map leaders and mounts that were drawn plain white now show their skins: the remake finds their textures where the originals keep them. This also fixes two of the first game's lords.
- Mines battlefield: the stream and waterfall are drawn see-through, as in the original, instead of cut out; with path tracing they no longer turn black.
- Path tracing: rune circles of buffs and debuffs no longer leave dark squares on the ground.
- Path tracing: trees, buildings and statues in parts of a map uncovered from the fog cast shadows straight away.
- Path tracing stays on after surrendering a battle or closing the original Options screen.
- The «Remake settings…» button on the Options screen is easier to see.

## 0.4.0

- Path-traced lighting (optional, Remake settings › Graphics): real shadows, sky light, light bounced between surfaces, and light from fire and spells that recolours the scene, on adventure maps and in battles. It needs the Forward+ (Vulkan) renderer and a graphics card with ray tracing, and costs about 2–3 ms a frame on a fast card. F7 switches it during play; Shift+F7 shows the light alone.
- Remake settings has a new layout with Graphics, Audio and Interface tabs. It can switch the renderer between Compatibility and Forward+ (Vulkan) and restart the game with it, and it says whether path tracing works on this computer.
- The remake's own screens are shown in the language of your game: Russian for a Russian copy, English otherwise. This covers Remake settings, the duel and campaign setup, the battle menu, the game files screen, the log export, the remake's map buttons and readouts, and its hints and messages.
- Discord activity (Remake settings › Interface): the Discord desktop app shows which game you play and whether you are in the menus, on a map or in a battle. Nothing else is shared, and switching it off clears it. Windows, Linux and macOS.
- Adventure maps: trees, rocks and buildings cast clearer shadows in both games without path tracing, as in the originals.
- Battles: spells take effect when the caster releases them, not at the start of the gesture. «Электрошок» strikes after the cast, and «Огненная волна» damages creatures when the wave reaches them.
- Battles: the camera follows a travelling spell such as «Огненная волна» over its targets instead of staying on the caster.

## 0.3.1

- Battles: a blocking creature steps out to its front line as soon as it is told to block and turns to face its attacker, as in the originals. When combat starts it runs from there, instead of from home straight through its own hero.
- Battles (Etherlords II): the opponent's spell icons at the top left show only the game's tooltip, not a second plain one.
- Battles: a summoned creature's own effects, such as the fire of «Стена магмы», appear with the creature instead of at its spot before it is summoned.

## 0.3.0

- New Demiurges logo for the app icon, the Windows program file and the start-up screen.
- Battles: when a hero's health drops to zero the battle ends there, as in the originals. Attackers still on the field run home (walk if wounded) and lie down instead of running on the spot, and the hero shows its hurt animation for every blow before the deciding one.
- Battles: a creature keeps its numbers until its death blow is shown, then loses them; a defeated hero's numbers disappear with its death.
- Battles: the summoning camera stays on the caster during the gesture and cuts to the creature as it appears, instead of showing empty ground for seconds. The next spell waits until the creature is there, and its camera shots follow the creature's close-up instead of cutting it short.
- Battles: cards entering and leaving the hand now visibly slide and drop into place (the hand was rebuilt several times per change, which cut the animation off).
- Battles (Etherlords II): the opponent's spell icons at the top left have their frame, clear at the opponent's next turn instead of piling up, and show the spell's tooltip on hover.
- Battles: the ring under creatures and heroes follows the mouse; outside your turn you can click any character to see its enchantments (such as «Дым») on the upper strip.
- Battles: hero portraits fill their window (no thin line of battlefield along their edges), and the enchantment strip reaches its right arrow on wide screens.
- Options and other screens opened over a battle dim the whole window, not only a 4:3 area.

## 0.2.15

- Battles: air walls and spirits show their see-through lower halves (a wall's wispy dress, a spirit's trailing body) instead of being cut off at the waist.
- Wiki: one encyclopedia for both games. Cards both games share have one page with the editions side by side and Etherlords II's changed values highlighted; cards found in only one game are marked I or II.

## 0.2.14

- Wiki encyclopedia: a page for every creature, sorcery, enchantment, artifact, skill and specialization of both games, in English and Russian. In the game, creatures are 3D models you can turn; on the website they are shown as pictures.
- The Windows program file, taskbar and window use the new Demiurges icon, and the start-up screen shows the name under the logo.

## 0.2.13

- New wiki in English and Russian: on the web at [demiurges.wwworm.com/wiki](https://demiurges.wwworm.com/wiki/) and inside the game (main menu **Wiki**, or F1).
- New Demiurges logo for the app icon and the start-up screen.
- Battles: quick casts are shown one after another, as in the originals, instead of starting over each other with overlapping sounds. The computer opponent also waits for each cast to be shown.
- Battles: a hero's health drops with each blow as it lands, instead of jumping to the result when the fight starts. Creature health in the figure numbers follows the blows too.
- Battles: attackers stay on their feet after striking and lie down to rest only once they have walked home, with their own rest animation.
- Battles: the defending hero can cast only the spells the originals allow in the defence phase (Polymorph, Fog and Energize All, plus «Самопожертвование» and «Телохранитель» in Etherlords II). The computer opponent no longer casts other spells while defending.
- Battles: cards entering and leaving the hand slide into place; a cast card shrinks away where it stood.
- Battles end the original way, without a Continue button: a campaign battle, a single Etherlords I duel and the Etherlords II combat tutorial close by themselves after the winner's animation.
- Closed arenas such as Etherlords I's «Круг времени» are no longer black from the standing camera: scenery is drawn one-sided, as in the originals.
- A fallen hero's glowing staff (and similar death effects) no longer replays its fall over and over.
- Duel screen: pick a spell in the list, then click a place in the spellbook to put it there (an empty place adds it, a filled slot is replaced).

## 0.2.12

- Steam copies are found automatically on Windows, Linux and macOS: on a first start the game uses any it finds, and the game files screen offers **Use the Steam copy** for a game not set up yet.
- Etherlords II from Steam in Russian (and the matching 1.03 repack): menus, cards and the encyclopedia show their text again instead of internal names such as `CtrlMM_SingleBtn` ([#6](https://github.com/TheWWWorm/Demiurges/issues/6)). That release stores its text table scrambled, which is now read.
- Etherlords II from Steam: starting a campaign no longer returns to the main menu ([#7](https://github.com/TheWWWorm/Demiurges/issues/7)). Its map scripts use a random-seed function the remake did not provide.
- Etherlords II map: heroes and monsters occupy their cells, as in the original, so heroes walk around each other instead of through.
- Battle sounds, including death and victory sounds, no longer play over the main menu or other menus.
- Duel screen: hovering a spell in the spell lists shows its type, strength and health, cost and description.

## 0.2.11

- Etherlords II from Steam: creatures and heroes no longer stand in a T-pose. The Steam release stores its animations in a compact form, which is now read alongside the GOG one.
- Battles: the end-of-phase (hourglass) button is available again as soon as a cast, summon or attack finishes, without first clicking the hero.
- Battle scenery is no longer over-bright with shadows on. Snowy arenas show their snow texture instead of plain white, and lit surfaces stay within their original colours.
- Etherlords II Vital city arena: the flat white patches at the edge of the battlefield are gone; the distant valley behind the arena stays behind the scenery.
- Etherlords I map: planned routes are marked with the original step and destination markers in the player's colour instead of thin lines.

## 0.2.10

- Corrected combat spell targets, creature abilities, enchantment removal, damage and turn effects in both games, preserving their edition-specific rules.
- Charmed and gifted creatures retain the appropriate army enchantments; returning creatures and cards go back to the correct owner. These states survive saving and loading.
- Resting a declared attacker with Mantis keeps its attack order in both games. In Etherlords I, Wall of Illusion can survive its ability's health reduction until a later spell or completed turn checks it, allowing a subsequent spell to save it.
- Corrected interactions involving unaffected creatures, the Colourless Plane, snake venom, redirected damage, trample, and specialisations. Fixed spell costs and the order of returned and discarded hand cards.
- Rod of Colossus deals its splash damage in Etherlords I too. Blessing from a wand or scroll lasts through the appropriate turn.
- Fixed a missing-camera error when opening certain Etherlords II adventure dialogs.

## 0.2.9

- Choosing a game: the main menu now shows **Etherlords I** and **Etherlords II** under its buttons, so you can switch with one click. The game you played last opens at the next start. A game you have not added yet offers to add it.
- The game files screen is the same on every platform: choose the game first, then its installed folder (on a computer), the GOG installer or a data pack. It can also play, remove an imported game, or stop using a linked game folder (the folder is kept). Open it from **Options › Remake settings › Game files…**.
- Touch screens ([#5](https://github.com/TheWWWorm/Demiurges/issues/5)): the drop-down lists in Remake settings (Movies, Anti-aliasing, Sharpening) no longer freeze the game. A tapped choice is taken and the list closes; tapping outside closes it. Sliders in dialogs can now be dragged with a finger.

## 0.2.8

- Battle terrain and small scenery remain visible when the camera moves, fixing trees appearing to float above missing hills.
- Optional Soft shadows smooths sun-shadow edges in battles and on Etherlords II maps. It starts off and can be changed during play.
- Terrain detail now also adds subtle ground texture in battles, using each arena's original detail artwork where available. It remains off by default.

## 0.2.7

- Defeated units now disappear from the Etherlords I adventure map, including in existing saves. Rewards and movement remain available as before.
- Etherlords II keeps its separate corpses and now uses their proper artwork and still death poses, including mounted heroes, boats and bodies placed in maps.
- Remake settings now includes optional Terrain detail: subtle texture contrast and surface relief on the adventure map, inspired by Cursed Lands. It starts off and can be switched on or off during play.

## 0.2.6

- Battles:
  - In both games, a battle ends by itself: the defeated hero falls, then the winner plays its victory animation to its colour's fanfare, as in the originals. The winner's camera shot follows only your own win; when the computer wins, the view stays as it is. Heroes without a victory animation of their own (the Etherlords II campaign heroes) use their casting gesture, as in the original. A campaign battle then returns to the map, and a duel shows its result after the animation.
  - In both games, Dense, Dark and Ancient Forest show their effect only on the opposing creatures they keep from attacking, with the enchantment glow on the caster; the effect was shown on the enemy hero.
  - In both games, the automatic camera's close-up on a fight starts when the blow is struck and frames the attacker and its target, including an attack on the hero, then returns to the attacker and cuts back to the normal view, as in the original. The shot of your own attack now starts when the fight begins, after your opponent's answer, as in the original; if your attackers did not survive the answer, there is no shot. The camera no longer lurches sideways during these shots.
- Maps:
  - In both games, clicking again while a hero is walking no longer makes it jump back and forth: it finishes the step it is taking and goes on from there.
  - In both games, once you move the view yourself (keys, screen edge, dragging or the minimap), the camera no longer snaps back to a walking hero. Centring on the hero makes it follow again.
- Logs and crash reports ([#2](https://github.com/TheWWWorm/Demiurges/issues/2)):
  - The game now keeps a log on every platform except the browser, including Android, where there was none. It notes each step of a session (battles starting and ending, maps, saves and loads), so the last lines show where a crash happened.
  - If the game closed unexpectedly, the next start offers a report: Save report writes it to your Download folder on Android, or Downloads on a computer, and shows where; Copy to clipboard copies it. The system closing the game in the background, or swiping it away from recent apps, does not count as a crash.
  - Remake settings › Export log… saves or copies the same report at any time, to attach to a bug report.
- Graphics:
  - A new Sharpening option (Off, Light, Strong; Light by default) makes figures and ground look less blurry. Textures are also filtered more sharply at steep angles.

## 0.2.5

- Installing:
  - Installing from the GOG installer is much faster on Windows, Linux, macOS and Android: the game files are now unpacked by a compiled decoder instead of a script, about 50–100 times faster. On a desktop computer the whole of Etherlords takes about 10 seconds and Etherlords II about 20 seconds, instead of half an hour or more ([#1](https://github.com/TheWWWorm/Demiurges/issues/1)). The browser version is unchanged.
- Battles:
  - In both games, tooltips look like the originals' (the original frame and lettering, hero cards with portraits). Etherlords II shows them when the pointer rests on a control; Etherlords I while the right mouse button is held, as in the original.
  - In both games, pressing a battle button no longer covers it with a yellow overlay, and the attack-all button stays closed when none of your creatures can attack.
  - In both games, a hero hit by a creature flashes red for a moment, as in the originals.
  - In both games, the automatic camera closes up on a fight only after your own attack declaration's shot, as in the original; the opponent's blows are shown from the normal view.
  - In both games, spell and gesture particles are drawn at the original size; a hero's casting gesture in Etherlords II was covered by an oversized yellow glow.
  - In Etherlords II, a summoned creature appears when the summoning effect reaches it, after the caster's shot; in Etherlords I, when the caster's gesture reaches its casting point, then with its colour effect, as in the original.
  - In both games, a figure's face and body shapes no longer carry over from its previous animation into the next one.
- Etherlords II map:
  - A hero ordered to move no longer draws a route line under itself, as in the original.
  - Mounted heroes' mounts walk with them instead of gliding.
  - Each step of a moving hero no longer stalls the game for a moment on large maps.

## 0.2.4

- Battles:
  - In both games, a battle saved after a Wall of Wind used its power can be loaded again (it was refused as invalid).
  - In both games, when a Mechozaurus's drain and an end-of-turn effect such as a toxin finish both heroes in the same turn end, the battle is a draw, as in the original; the winner used to be decided before the remaining end-of-turn effects.
  - In Etherlords II, Gift on a creature that its new side's Immolation destroys no longer stops the spell partway.
  - In Etherlords II, the dark stream of the Cutters', Sawers' and Razor Men's sacrifice now flows from the sacrificed creature to the user, as in the original (it ran the other way).
  - In both games, the Vampire Bats' drain flows from the opposing hero to their own hero and appears only when the bats' damage lands; in Etherlords II the River, Sea and Swamp Halos draw their ether stream between the heroes the same way and only when ether moves.
  - In Etherlords II, the Enchanters' pale stream flows from the creature or hero whose enchantment they take to the Enchanter, and Outer Exchange's stream runs from the creature leaving the Colourless Plane to the one entering it.
  - In Etherlords I, the Huntress's hunt shoots the original Hunter's Arrow at its target, as in Etherlords II.
  - In both games, creatures that strengthen their kin (worker and queen bees and ticks, Mother Bee and Mother Tick, Kobold Warriors, Orc Warriors and Elders, Aviak Elders, Silicon Walls, the Spirits and the Gargantium Fingus) show the original effect on each creature they cover when they arrive or when a new one joins, and Mother Bee's death shows the bees' frenzy.
  - In both games, Tremor and Earthquake shake the current view as in the original, even with the automatic camera off, and the automatic camera shows them like other spells instead of jumping to a fixed viewpoint.
  - In both games, the automatic camera chooses spell shots as the original does: it sometimes shows the whole battlefield instead of close-ups (and always does when a spell touches both sides or a creature at the far end of the line), closes up on a hero the spell targets, uses the original group shots for spells on several creatures, times the caster's shot to the hero's casting gesture, skips the close-up of a creature kind already summoned in the battle, and stays on the target for the whole of Powertap, Tap Life, Zap, Fire Wave and Comet.
  - In both games, artifacts, creature abilities and enchantments such as Riot, Quick Fix, Barbed Souls, Redirect, Feedback and Mana Thorns get automatic camera shots as in the original, and spells such as Feedback, Gift and Justice use the camera of their own kind.
  - In both games, a spell's close-up of the caster's own creatures now shows them from the front instead of looking at the enemy side.
  - In both games, spell, creature and blood particles are drawn at the original size; they were drawn at less than half size in battles and slightly small on the map.
  - In Etherlords II, sounds placed in the scene pan and fade with distance as the original's sound mixer does: a sound off to one side stays a little louder on its own side, and distant sounds fade out sooner. The music and sound volume sliders follow the original's curve, so lower settings are quieter than before.
  - In both games, a chosen card or artifact no longer gets a gold outline, matching the original; the target prompt shows the choice, and the outline remains with the helper overlay.
  - In Etherlords I, the Rods of Dominance and Defence show their strengthening effects on each of your creatures, and the Rod of Insanity's damage shows its effect on the hero it hurts, as in the original.
  - In both games, the damage from Madness, Mana Burn, Envenoming and the Tree and Swamp Snakes' venom at the end of a turn now shows its original effect on the hurt hero, and a Mechozaurus's drain shows its dark stream from the creature to its hero.
  - In Etherlords II, Weak Toxin's second card shows its damage effect, Outer Cripple shows the card draw it causes, and a creature dying from Alpha Strike shows the original death effect, as in Etherlords I.
  - In Etherlords I, Quick Fix returning to your hand shows its card effect on your hero, as in Etherlords II.
  - In Etherlords I, Strength of the Woods shows its strengthening effects on each of your creatures, Smoke and Condensed Air show their effect on each creature they hold down, and Polymorph shows its life effect on the changed creature, as in the original.
  - In both games, a creature losing Bless or Combine's bonus at the end of a turn shows the original weakening effects.
  - In both games, the Walking Horror's arrival shows the original damage effect on each creature it hurts.
  - In Etherlords I, casting Rain of Stone shows the original enchantment effect on your hero, as in Etherlords II.
  - In Etherlords II, the Shifters' Cruel ability shows its pale stream to the creature it destroys, the Enchanters' Mystic ability shows its stream from the dispelled enchantment, and Final Courtesy shows the card draw.
  - In Etherlords II, Devourer I and II now show their attack, defence and rune markers when they grow after devouring a creature.
  - Complicity now shows the original life gain at its hero each time a creature regenerates.
  - In both games, creatures now make their idle sounds: the bees, bats, spirits, elementals and others buzz or hum with each idle loop, and every creature's occasional idle flourish plays its own sound. A flourish now begins when the idle loop ends instead of cutting into it.
  - In both games, creatures now make footstep sounds as they run and walk across the battlefield, matched to the arena's ground (grass, snow or sand), and gliding creatures such as the Fingus make their sliding sound while they move.
  - In both games, the Spitting and Carnivorous Fingus play their spore action before they wither, and the Reinforced Pteros plays its action when it strips an enchantment. In Etherlords II, every Pale creature also plays its action when it uses Dissipation, Sinister, Cruel, Fiendish, Mystic, Cryptic Manifestation or Final Courtesy.
  - In Etherlords II, Pale Warp now shows its warp from your hero to the Pale creature it destroys at the start of your turn; the creature falls when the warp reaches it.
  - In Etherlords II, Madness and the Rod of Insanity no longer hurt the hero while the affected creature is in the Colourless Plane, as in the original (Irritation already worked this way).
  - The rune markers on creatures at the start of a turn now appear for exactly the enchantments that showed them in the originals: for example Thief, Sight, Irritation and Madness now show one, while Bless no longer does.
  - A creature that enters the battle while Drowsy, Depressing or Frenzy Gas is in play now shows that gas weakening it, once for each copy, as in the originals.
  - In both games, a window 1024 pixels wide or more now uses the original's wide combat panel: one row, with the phase caption in its oval beside the three buttons and the X-cost controls inside it, instead of the 800×600 panel stretched. An empty upper strip (enchantments or graveyard) no longer draws empty frames and arrows over the battlefield.
  - In Etherlords II, the start of each turn shows the original markers, as in Etherlords I: the ether disturbance's lightning on the hero, runes on the hero for its lasting positive and negative enchantments, the Stasis marker, and runes on strengthened or weakened creatures.
  - In Etherlords I, the rune markers at the start of a turn now appear for every lasting enchantment that shows them in the original, not just a few.
  - In both games, paying ether to send a creature into attack (under Hesitation) shows the ether-loss effect on that creature, as in the original; Etherlords I showed it on the hero and Etherlords II not at all.
  - In both games, the arena's sun now shines down onto the battlefield as in the original, so creatures and heroes cast their shadows on the ground in the original direction and the ground is lit; in most arenas the light came from below, leaving the ground dark and the shadows hidden.
  - In Etherlords II, the battle camera uses the original's narrower view angle, so the standing view frames the arena as the original does, and heroes whose figures are not the dedicated hero models are drawn at the original's larger size (in both games).
  - In both games, at 1024×768 and 800×600 the combat panel is drawn at the original's pixel size: five cards and a framed slot before the arrow, the phase oval in its place, and the heroes' life, ether and channels in the original's large gold digits.
  - The game-menu button in the battle's top-right corner shows only while the pointer is over it, as the original has no visible button there.
  - In Etherlords I, the tutorial hints use the original's layout and smaller type, so their text fits the panel without scrolling.
  - In both games, the attack, defence and order numbers over creatures grow and shrink with the creature's distance from the camera, as in the original, and sit at the original height beside their icons.
- Adventure map:
  - In Etherlords II, the map is seen through the original's perspective camera at its usual distance instead of a flat overhead view; zooming, rotating and the campaigns' camera moves work as before.
  - In Etherlords II, the ground no longer shows thin stripes and stray triangles of neighbouring ground tiles.
  - In Etherlords II, speakers' names in conversations end with a colon, as in the original.
  - In Etherlords II, the extra Next day and Skills buttons in the top corner are a remake helper and now appear only with the helper overlay; the original day counter and skills button in the corner panel are unchanged, and K still opens the skills.
  - In Etherlords II, objects, figures and the scenery cast the original's shadows on the ground, falling the way the original's do.
  - In Etherlords I, a mission opens with the original's view of the map: closer, and turned so the castle is at the top with its gate facing down.
  - In Etherlords I, the minimap shows the original markers (castles in their owner's colour, sites, visible heroes and monsters) and the original view circle with its arrow; empty hero slots have the original frame, the chosen hero a gold frame, and the date and resource figures are in the original gold type.
  - In Etherlords I, all of a day's ether income is free on the first day of a mission (it showed one less), as in the original.
  - In Etherlords I, holding the right mouse button on an object shows its information only while the button is held, in the original's larger type.
  - In Etherlords II, conversation text uses the original's bold type and size, so it wraps and fills the box as in the original.
  - In Etherlords II, starting a campaign chapter shows a loading screen instead of the previous battle.
  - In both games, figures that wear two textures (heroes on mounts, lords, mantises, aviaks and gibberlings) now have each part painted with its own texture, on the map and in battles; their bodies and mounts or gear had the textures swapped.
  - In Etherlords II, the camera closes in on whoever is speaking in a map conversation and eases back to the usual view when the conversation ends, as at the start of the original's campaign chapters.
  - In Etherlords I, the resource figures on the map bar use the original's small gold digits.
  - In Etherlords I, your own banner shows on your castle and heroes as soon as a mission starts; it showed the map's default banner until something changed.
  - In both games, ground tiles join without the thin cross-shaped seams along their edges, so paths and transitions look as in the original.
  - In Etherlords I, hiring a hero partway through the day no longer changes that day's free ether; it is set at the end of each night, as in the original.
  - In Etherlords I, the map is seen through the original's perspective camera: the view angle, the 45° tilt and the distance now match the original, so a mission opens framed as it does there, and zooming stays within the original's range.
  - In Etherlords I, the banners over castles, sites and heroes have the original size and height.
  - In Etherlords II, objects and figures on the map are no longer brighter when shadows are on.
  - In Etherlords II, when a campaign script turns the camera towards a character or place, it turns as seen from your hero, as in the original, and the view follows your hero while the script walks them somewhere.
  - In Etherlords II, the camera turns that campaign scripts make ease into place as in the original instead of jumping; turning the view yourself takes over at once.
  - In Etherlords II, scripts that format text for messages no longer fail and leave the text incomplete.
- Menus and screens:
  - In Etherlords II, the single-player menu no longer shows pieces of the mission selection page over its buttons.
  - The main and sub-menu buttons have the original widths, and their captions use the original gold colour.
  - Options opened from the main menu keeps the main-menu picture behind it.
  - The duel setup lists decks with the original race pictures, row height and grid, shows "-" for a random choice, and dims New, Edit and Delete when they are unavailable.
  - In Etherlords II, the campaign page no longer has an extra Hall of Fame button, the campaign choice opens with no campaign chosen and the original captions, and the campaign map sits where the original draws it.
  - In Etherlords I, the campaign legend keeps the original title and type, and a mission's objectives use the original headings and colours.
  - The credits' copyright lines sit where the originals place them.
  - In Etherlords I, a campaign mission's information page shows the mission's players, with your own slot marked, as the original does.
  - In Etherlords II, the campaign map shows the route already travelled as grey dots, the current chapter's route drawn dot by dot in red, and the hero at its end, as in the original; the map no longer scrolls.
  - In Etherlords II, the menu pages show the game version in their corner, as the original does.
  - In Etherlords II, Network game opens the original five-button page directly.
  - The duel deck list starts in the original order, fits the original's 14 rows on the panel's grid, and an empty side shows the original "?" portrait.
  - In Etherlords II, the credits are laid out as in the original, with gaps between entries and text fading at the top edge, and they fade back to the menu at the end. Their text is drawn crisp with a solid shadow, as in the original.
  - In Etherlords II, the Encyclopaedia sits where the original places it, over the main-menu picture with the version line, and its lists use the original gold type and layout: centred creature names, the enchantment and sorcery descriptions under their names, the scroll-bar marker and the original tooltip frames.
  - The duel deck list uses the original colours: available decks in white, decks above the resource level in grey and the random choice in gold.
  - In Etherlords II, Options opened from the main menu shows the version line, as the original does.
  - Tooltips appear beside the pointer at the original's offset instead of under it.
- Settings:
  - A new Anti-aliasing choice in the remake settings smooths the edges of the 3D map and battle scenes. Automatic uses 2× smoothing unless the graphics are rendered in software; it can be set to Off, 2× or 4×.

## 0.2.3

- Battles:
  - In Etherlords I, most creature abilities now show their original spell effects and sounds: the Beholders' gaze, the Fingus spits, the Lamias' draws, the Mantises, the walls, the Halos, the Razor Men's sacrifice, Rain of Stone, Burnout, the Repair Station and many more. River and Swamp Halo draw their ether stream from the opposing hero to their own, as Sea Halo does.

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
