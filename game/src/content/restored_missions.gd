class_name ELRestoredMissions
extends RefCounted
## Missions cut from Etherlords I, rebuilt from what the game files keep.
## Each one is a fixed random-map recipe: the generator lays out the world
## with its usual rules and the recipe's "scenario" key adds the mission's own
## ground, sites and goal. Saves regenerate the map from the recipe, as for
## every random map.
##
## Savage Desert (smission01, texts MT_S01_*): the original program still
## knows this map. It is won only when a human player's hero defeats the
## Cyclops; destroying every rival castle does not count. The English edition
## names the Cyclops's lair: the north-eastern mountains, under strong guard.
## The Chaots have just beaten the Synthets' best troops in these lands, so
## the Chaots play alone: the program's rule turns off the usual victory over
## every rival, which a map without rivals would win on its first day.
##
## Evil Dale (bmission01, texts MT_B1_*): a bonus mission for one Vital, the
## Chosen One (hero BLevStartHero). The program still knows its rules: it is
## won when the Chosen One comes within two tiles of (30, 123), after the
## area x 0-39, y 104-159 is revealed, and lost when no Chosen One is left.
## Glazzz (BLevHero2) walks a fixed loop through (55, 146), (55, 110),
## (64, 84) and (55, 104), and both he and Warp (BLevHero5) attack the
## Chosen One when he comes in sight. These points fix a 160-tile map. The
## dale's course between them, the other three rivals' places and the four
## elements' grounds along the way are the remake's reading of the briefing.
##
## Snowflake Maze (texts MT_B2_*): a yearly tournament of the Kinets in an
## ice maze, its winner allowed to talk with the Greatest Teacher. Its goal
## is the usual one, destroy the enemy castles. No map and no rule of it
## survive, only the texts and two Kinet heroes no map places, Santa Claus
## (NewYear2002Lamia) and Father Frost (NewYear2002Aviak), with their
## "New Year 2002" decks. In the remake they lead the two rival Kinet lords,
## and a six-armed maze of ice, its rings opened so the way to the heart
## winds, holds a Teacher at its heart.

const SAVAGE_DESERT := "savage_desert"
const EVIL_DALE := "evil_dale"
const SNOWFLAKE_MAZE := "snowflake_maze"
const SCENARIOS := [SAVAGE_DESERT, EVIL_DALE, SNOWFLAKE_MAZE]
## The creature the mission's goal names (Monsters table, Name column).
const GOAL_MONSTERS := {SAVAGE_DESERT: "Cyclope"}
## Generator recipes. The version is pinned so later generator versions keep
## this map as it is.
const RECIPES := {
	SAVAGE_DESERT: {"version": 14, "seed": "smission01", "size": 96, "players": 2,
		"layout": "frontier", "biome": "Black", "faction": "Red", "resources": "normal",
		"starting_resources": "normal", "guards": "normal", "roads": true, "scenery": 1,
		"castle_health": 30, "naval": false, "water": "low", "coast": "rugged", "scenario": SAVAGE_DESERT},
	EVIL_DALE: {"version": 14, "seed": "bmission01", "size": 160, "players": 2,
		"layout": "frontier", "biome": "Green", "faction": "Green", "resources": "normal",
		"starting_resources": "normal", "guards": "normal", "roads": true, "scenery": 1,
		"castle_health": 30, "naval": false, "water": "low", "coast": "rugged", "scenario": EVIL_DALE},
	SNOWFLAKE_MAZE: {"version": 14, "seed": "bmission02", "size": 96, "players": 3,
		"layout": "frontier", "biome": "Blue", "faction": "Blue", "resources": "normal",
		"starting_resources": "normal", "guards": "normal", "roads": true, "scenery": 1,
		"castle_health": 30, "naval": false, "water": "low", "coast": "rugged", "scenario": SNOWFLAKE_MAZE},
}
## Original text keys, and the remake's words where the edition left them
## empty (the Russian edition has no texts for the S series).
const TEXTS := {
	SAVAGE_DESERT: {
		"title": ["MT_S01_NAME", "Savage Desert"],
		"objective": ["MT_S01_OBJ", "Defeat the Cyclops"],
		"win_condition": ["MT_S01_WINC", "Defeat the Cyclops"],
		"lose_condition": ["MT_S01_LOSEC", "None"],
		"description": ["MT_S01_DESC", "In these sands the warriors of Chaos have broken the Synthets' finest troops, and little is left in our way. Only a renegade Cyclops still defies us. He holds the north-eastern mountains with a strong guard around him, but no barrier can stop the warriors of Great Chaos. Destroy the renegade and the victory is ours."],
	},
	EVIL_DALE: {
		"title": ["MT_B1_NAME", "Evil Dale"],
		"objective": ["MT_B1_OBJ", "Investigate the surroundings and find the way out of the dale"],
		"win_condition": ["MT_B1_WINC", "Find the way out of the dale"],
		"lose_condition": ["MT_B1_LOSEC", "Death of the Chosen One"],
		"description": ["MT_B1_DESC", "Far in lands long hidden from the Lords, a vanguard of the Vitals found an ancient scroll. Days of rituals revealed what it holds: knowledge of a power older and greater than the Lords' own, in which all four elements are one. A single Vital was chosen to walk the Way of Knowledge to the dale the scroll describes. As he entered it, the trees closed behind him and mountains rose across the way back. Only the way forward is left."],
	},
	SNOWFLAKE_MAZE: {
		"title": ["MT_B2_NAME", "Snowflake Maze"],
		"objective": ["MT_B2_OBJ", "Destroy enemy Castle"],
		"win_condition": ["MT_B2_WINC", "Destroy enemy Castle"],
		"lose_condition": ["MT_B2_LOSEC", "Lose your Castle"],
		"description": ["MT_B2_DESC", "Every year at the same time the wisest and mightiest of the Kinets meet in the ice maze to measure their strength and earn the blessing of their Lord. The winner of the tournament is granted the great honour of talking with the Greatest Teacher about the boundlessness of Knowledge. As long practice shows, after such a talk the worthiest of the Kinets enjoys rare luck and success for a whole year."],
	},
}
## The Synthets lost their elite troops and their lord: the Chaots play
## alone, and a remnant of this level holds the Synthets' old castle ground.
const REMNANT_LEVEL := 6
## Where the Synthets' homeland and castle were laid out, as a map fraction.
const SYNTHET_HOME := Vector2(0.74, 0.24)
## The Cyclops's yard, as fractions of the map (north is the high rows), and
## the guards on the way in, outermost first.
const LAIR := Vector2(0.83, 0.84)
const LAIR_GUARDS := ["OrcWarrior", "OgreChief", "RockWall"]
## The Cyclops's mountains: dark rock within this fraction of the map width.
const MOUNTAIN_RADIUS := 0.25
## The Synthets' fallen castle: [prop, offset from the old castle's middle,
## rotation]: broken walls round the yard, a toppled tower and roof, and the
## craters of the siege.
const FALLEN_CASTLE := [["Wall_dest1", Vector2i(-7, -1), 0], ["Wall_dest1", Vector2i(7, 1), 0],
	["Wall_dest0", Vector2i(-5, -6), 0], ["Wall_dest0", Vector2i(5, 6), 0], ["Wall01", Vector2i(-5, 6), 0],
	["Wall_02", Vector2i(6, -5), 0], ["Gate01", Vector2i(0, -7), 0], ["Tower03", Vector2i(-8, 7), 0],
	["Roof", Vector2i(8, -8), 0], ["BlackCrater_3", Vector2i(3, 3), 0], ["BlackCrater_4", Vector2i(-3, -3), 0],
	["BlackCrater_2", Vector2i(3, -3), 0], ["BlackCrater_1", Vector2i(-3, 3), 0]]
## Craters of the war scattered round it, within this many tiles.
const BATTLEFIELD := 18
const CRATERS := ["BlackCrater_1", "BlackCrater_2", "BlackCrater_3", "BlackCrater_4", "BlackCrater_5"]
## Vents of the Cyclops's mountains round his yard.
const LAIR_VENTS := [["Red_Voulcan_3", Vector2i(-5, -3)], ["Red_Voulcan_4", Vector2i(5, -3)], ["Red_Voulcan_5", Vector2i(-4, 5)],
	["Red_Voulcan_6", Vector2i(5, 5)], ["Red_Voulcan_1", Vector2i(0, 6)], ["Red_Voulcan_2", Vector2i(-6, 1)], ["Red_Voulcan_1", Vector2i(6, 1)]]

## Evil Dale. North is the high rows. The dale runs from the Chosen One's
## glade in the south-east, through the Chaots' rock, the Kinets' snow and
## the Synthets' sand, back to the Vitals' woods of Glazzz's loop, and out by
## a pass in the west to the ruins where the four elements meet.
const CHOSEN := "BLevStartHero"
const DALE_ROUTE: Array[Vector2i] = [Vector2i(140, 14), Vector2i(116, 22), Vector2i(90, 14), Vector2i(70, 30),
	Vector2i(92, 48), Vector2i(124, 44), Vector2i(146, 70), Vector2i(132, 102), Vector2i(144, 130),
	Vector2i(124, 150), Vector2i(96, 144), Vector2i(84, 118), Vector2i(100, 96), Vector2i(78, 80),
	Vector2i(64, 84), Vector2i(55, 104), Vector2i(55, 110), Vector2i(55, 146)]
## The ground of each stretch of the route (one per segment).
const DALE_ZONES := ["Green", "Green", "Red", "Red", "Red", "Blue", "Blue", "Blue", "Black", "Black", "Black", "Black",
	"Green", "Green", "Green", "Green", "Green"]
## The pass from Glazzz's woods to the exit.
const DALE_PASS: Array[Vector2i] = [Vector2i(55, 123), Vector2i(44, 123), Vector2i(30, 123)]
const DALE_PASS_ZONE := "Red"
## The ruins beyond: the area the program reveals at the end.
const EXIT := Vector2i(30, 123)
const EXIT_REVEAL := Rect2i(0, 104, 40, 56)
## The ruins: their heart, and the pieces around it ([prop, offset from the
## heart, rotation]): a monument, four towers and broken walls.
const RUINS_HEART := Vector2i(23, 128)
const RUINS := [["Monument01", Vector2i(0, 0), 0], ["Tower01", Vector2i(-6, 6), 0], ["Tower02", Vector2i(6, 6), 0],
	["Tower03", Vector2i(-6, -6), 0], ["Tower04", Vector2i(7, -5), 0], ["Hwall01", Vector2i(-3, 7), 0],
	["Hwall02", Vector2i(3, -7), 0], ["Hwallcorn01", Vector2i(-8, 1), 0], ["Hwall03", Vector2i(-2, -8), 0],
	["Monument02", Vector2i(-9, -3), 0], ["Hwallentr01", Vector2i(2, 8), 0], ["Hwall04", Vector2i(9, 2), 4],
	["Wall_dest0", Vector2i(-4, 3), 0], ["Wall_dest1", Vector2i(5, -1), 0], ["Wall_dest0", Vector2i(-3, -4), 0],
	["Hwallcorn03", Vector2i(-8, 6), 0], ["Hwallcorn04", Vector2i(8, -8), 0], ["Hwall03", Vector2i(-10, 4), 0],
	["Wall_dest1", Vector2i(10, -4), 0], ["Monument01", Vector2i(-2, 11), 0]]
## Glazzz's woods: the trees and bushes that line his beat.
const BEAT_GROVES := ["GreenForest03", "GreenForest04", "GreenBush07", "GreenBush08", "GreenTree01", "GreenStone_5"]
## The second homeland the generator lays out (its castle is removed), in the
## Kinets' snow.
const DALE_HOMELAND := Vector2i(132, 102)
## The Synthets' outpost where the sand begins: a spell shop, a creature
## shop and a component portal, so the book keeps up with the dale's second
## half (the two homelands lie in its first).
const OUTPOST := Vector2i(124, 150)
const OUTPOST_COLOR := "Black"
## The rivals, weakest first, at their places along the dale.
const RIVALS := {"BLevHero1": Vector2i(80, 38), "BLevHero3": Vector2i(140, 86), "BLevHero4": Vector2i(90, 132),
	"BLevHero2": Vector2i(55, 146), "BLevHero5": Vector2i(42, 123)}
## Creatures in the open stand at least this far apart, and the last of
## them, near the exit, are of this level.
const DALE_CREATURE_GAP := 7
const DALE_LAST_LEVEL := 9
const PATROLLER := "BLevHero2"
const WARDEN := "BLevHero5"
## Glazzz's loop: on reaching a point (within one tile) he heads for the next.
const PATROL: Array[Vector2i] = [Vector2i(55, 146), Vector2i(55, 110), Vector2i(64, 84), Vector2i(55, 104)]

## Snowflake Maze: the rival lords' heroes, for players 2 and 3.
const TOURNEY_HEROES := ["NewYear2002Lamia", "NewYear2002Aviak"]
## The castles: the player's in the low rows, the rivals' in the high rows
## to either side, all round the maze.
const TOURNEY_HOMES: Array[Vector2] = [Vector2(0.5, 0.19), Vector2(0.21, 0.74), Vector2(0.79, 0.74)]
## The maze at the map's middle: four rings of ice and six arms between
## them, every arm running on outside the rings as a snowflake's spike.
## Arm k points at -120 + 60k degrees; sector k runs from arm k to arm k + 1,
## and sector 0 faces the player's castle. Each ring opens in three sectors,
## [sector, place across it from 0 to 1], and between two rings three arms
## are closed (inner band first). Every way in then winds the same turn
## round the rings, about 200 degrees, before it reaches the heart.
const MAZE_RINGS := [4.0, 7.0, 10.0, 13.0]
const MAZE_GAPS := [[[3, 0.4], [5, 0.4], [1, 0.4]], [[4, 0.25], [0, 0.25], [2, 0.25]],
	[[5, 0.2], [1, 0.2], [3, 0.2]], [[0, 0.8], [2, 0.8], [4, 0.8]]]
const MAZE_ARMS := [[1, 3, 5], [0, 2, 4], [1, 3, 5]]
const MAZE_SPIKE := 16.0
## Ice for the walls (one tile each).
const MAZE_ICE := ["BlueIce_1", "BlueIce_2", "BlueIce_3", "BlueIce_5", "BlueIce_6", "BlueIce_7", "BlueIce_8", "BlueIce_9", "BlueIce_10"]
## The Greatest Teacher at the heart, and the guards in the inner ring's
## openings: creatures of the fourth level, a fair fight for a lord's hero
## of the tournament's level once he has a few wins behind him.
const MAZE_HEART := "Teacher"
const MAZE_GUARD := "Aviak Elder"
const MAZE_GUARD_LEVEL := 4
## Every lord comes to the tournament at Santa Claus's and Father Frost's
## level: a first hero below it starts with the experience for it, and its
## skill points to spend.
const TOURNEY_LEVEL := 3

static func recipe(scenario: String) -> Dictionary:
	return Dictionary(RECIPES.get(scenario, {})).duplicate(true)

static func map_id(scenario: String) -> String:
	return ELFirstRandomMap.id_for_config(recipe(scenario))

## The restored mission a map id belongs to, or "".
static func scenario_of_id(id: String) -> String:
	if not ELFirstRandomMap.is_random_id(id): return ""
	for scenario: String in SCENARIOS:
		if map_id(scenario) == id: return scenario
	return ""

static func scenario_of(map: ELAdventureMap) -> String:
	if map == null: return ""
	var scenario: Variant = ELFirstRandomMap.configuration(map).get("scenario", "")
	return str(scenario) if scenario is String and scenario in SCENARIOS else ""

## A text of the mission: the edition's own when it has one.
static func text(profile: ELProfile, scenario: String, field: String) -> String:
	var pair: Array = Dictionary(TEXTS.get(scenario, {})).get(field, ["", ""])
	if pair.is_empty(): return ""
	var original := profile.text(str(pair[0])) if profile != null and profile.texts.has(str(pair[0])) else ""
	if not original.is_empty(): return original
	return ELRemakeText.t(str(pair[1]), profile) if profile != null else str(pair[1])

static func title(profile: ELProfile, scenario: String) -> String:
	return text(profile, scenario, "title")

## Single-mission list rows for the restored missions (first game only).
static func entries(profile: ELProfile) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile == null or profile.id != "el1": return result
	for scenario: String in SCENARIOS:
		var config := recipe(scenario)
		var entry := {"id": map_id(scenario), "campaign": false, "restored": scenario, "random_map": config,
			"width": int(config.size), "size_class": int(ELSingleScenario.SIZE_CLASSES.get(int(config.size), 1 if int(config.size) < 120 else 3)), "players": [], "races": []}
		for field: String in ["title", "objective", "win_condition", "lose_condition", "description"]:
			entry[field] = text(profile, scenario, field)
		var colors: Array = [str(config.faction)]
		# The tournament: every side is a Kinet lord.
		if scenario == SNOWFLAKE_MAZE: colors = [str(config.faction), str(config.faction), str(config.faction)]
		for index in colors.size():
			var relations := {}
			for other in colors.size(): relations[other + 1] = 255 if other == index else 0
			var race_name: String = {"Red": "Chaots", "Black": "Synthets", "Blue": "Kinets", "Green": "Vitals"}[colors[index]]
			entry.players.append({"id": index + 1, "color": colors[index], "name": ELRemakeText.t(race_name, profile), "blazon": Vector2i(-1, -1), "relations": relations})
			var race: int = ELSingleScenario.RACES.get(colors[index], 0)
			if race > 0 and not entry.races.has(race): entry.races.append(race)
		result.append(entry)
	return result

## The creature only a human player's hero may defeat on this map, or "".
static func goal_monster(state: ELAdventureSession) -> String:
	if state == null or state.map == null or state.map.profile == null or state.map.profile.id != "el1": return ""
	return str(GOAL_MONSTERS.get(scenario_of(state.map), ""))

## Whether the creature is the mission's goal, which computer players leave alone.
static func reserved(state: ELAdventureSession, monster: Dictionary) -> bool:
	var goal := goal_monster(state)
	return not goal.is_empty() and str(monster.get("name", "")) == goal

## Whether the goal creature is still on the map.
static func goal_alive(state: ELAdventureSession) -> bool:
	var goal := goal_monster(state)
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("type") == "monster" and str(item.get("name", "")) == goal: return true
	return false

## Snowflake Maze, at the start of a new game: every lord's first hero
## comes at the tournament's level.
static func start(state: ELAdventureSession) -> void:
	if state.map == null or state.map.profile == null or state.map.profile.id != "el1" or scenario_of(state.map) != SNOWFLAKE_MAZE: return
	var profile := state.map.profile
	for item: Dictionary in state.objects.values():
		if item.get("type") != "hero" or int(item.get("owner", 0)) < 1 or int(item.get("level", 1)) >= TOURNEY_LEVEL: continue
		ELHeroProgression.award(profile, item, ELHeroProgression.threshold(profile, TOURNEY_LEVEL) - int(item.experience))

## Snowflake Maze: the middle of the maze, in tiles.
static func maze_middle(size: int) -> Vector2i:
	return Vector2i(size / 2, size / 2)

static func is_dale(state: ELAdventureSession) -> bool:
	return state != null and state.map != null and state.map.profile != null and state.map.profile.id == "el1" and scenario_of(state.map) == EVIL_DALE

## The human player's Chosen One, or {}.
static func chosen_one(state: ELAdventureSession) -> Dictionary:
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("type") == "hero" and str(item.get("name", "")) == CHOSEN and int(item.get("owner", 0)) == state.current_player: return item
	return {}

## The program's exit test: both coordinates within two tiles of the exit.
static func at_exit(hero: Dictionary) -> bool:
	return absi(int(hero.get("x", -99)) - EXIT.x) < 3 and absi(int(hero.get("y", -99)) - EXIT.y) < 3
