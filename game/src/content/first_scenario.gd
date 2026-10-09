class_name ELFirstScenario
extends RefCounted
## First-game scenario rules. A player's castle energy is its life: heroes
## ordered onto an enemy castle damage it every night they stand beside it, the
## damage lands before the next day, and a ruined castle eliminates its player.
## Campaign chapters replace "eliminate every rival" with their own goals.

const VERSION := 1
## Temple of Time chapters pair each player with the rival whose fall opens the rocks.
const RIVALS := {1: 2, 2: 1, 3: 4, 4: 3}
const BATTLE_GOALS := {"mission10": "Fire Spirit", "mission20": "Razor Beast"}
## Castles that must fall (win) or must stand (lose) in castle-war chapters.
const CASTLE_GOALS := {
	"mission11": {"win": [2], "lose": []}, "mission21": {"win": [2], "lose": []},
	"mission12": {"win": [1, 3], "lose": [4]}, "mission22": {"win": [3, 4], "lose": [2]},
}

static func applies(state: ELAdventureSession) -> bool:
	return state.map != null and state.map.profile.id == "el1"

static func initialize(state: ELAdventureSession, human: int, campaign: bool) -> void:
	var castles := {}
	for player: Dictionary in state.map.players:
		var energy := maxi(1, int(player.attrs.get("health", 30)))
		castles[int(player.attrs.id)] = {"health": energy, "max": energy, "pending": 0, "alive": true}
	if castles.has(human): state.current_player = human
	state.scenario = {"version": VERSION, "campaign": campaign, "castles": castles, "tomb_open": false, "opening": false}
	show_stages(state)

static func restore(state: ELAdventureSession, raw: Variant) -> String:
	if raw == null:
		show_stages(state)
		return ""
	if not raw is Dictionary or raw.get("version") != VERSION or not raw.get("campaign") is bool or not raw.get("tomb_open") is bool or not raw.get("opening", false) is bool or not raw.get("castles") is Dictionary: return "Invalid scenario state."
	var castles := {}
	for key: Variant in raw.castles:
		var castle: Variant = raw.castles[key]
		if not str(key).is_valid_int() or not state.scenario.castles.has(int(str(key))) or not castle is Dictionary or not castle.get("alive") is bool: return "Invalid saved castle."
		for field: String in ["health", "max", "pending"]:
			if not ELLuaSave._integer(castle.get(field), -100000, 100000): return "Invalid saved castle energy."
		if int(castle.max) < 1: return "Invalid saved castle energy."
		castles[int(str(key))] = {"health": int(castle.health), "max": int(castle.max), "pending": int(castle.pending), "alive": castle.alive}
	if castles.size() != state.scenario.castles.size(): return "Saved castles do not match the map."
	var progress: Variant = raw.get("progress", {})
	if not progress is Dictionary or (not progress.is_empty() and not valid_progress(progress)): return "Invalid saved campaign progress."
	state.scenario = {"version": VERSION, "campaign": raw.campaign, "castles": castles, "tomb_open": raw.tomb_open, "opening": raw.get("opening", false)}
	if not progress.is_empty(): track(state, progress)
	show_stages(state)
	return ""

## Chapter position and running score, carried from one chapter to the next.
static func track(state: ELAdventureSession, progress: Dictionary) -> void:
	if not applies(state) or state.scenario.is_empty() or not valid_progress(progress): return
	state.scenario.progress = {"campaign": str(progress.campaign), "number": int(progress.number), "subnumber": int(progress.get("subnumber", 1)), "branch": int(progress.get("branch", 0)), "score": int(progress.get("score", 0))}
	# The name and blazon chosen on the campaign screen go with the campaign.
	for key: String in PROFILE_KEYS:
		if progress.has(key): state.scenario.progress[key] = progress[key] if key == "player_name" else int(progress[key])

## Player profile fields a campaign carries (name, blazon logo and colour).
const PROFILE_KEYS := ["player_name", "logo", "colour"]

static func valid_progress(progress: Dictionary) -> bool:
	if progress.has("player_name") and (not progress.player_name is String or String(progress.player_name).length() > ELPlayerProfile.NAME_LIMIT): return false
	if progress.has("logo") and not ELLuaSave._integer(progress.logo, 0, ELPlayerProfile.LOGOS - 1): return false
	if progress.has("colour") and not ELLuaSave._integer(progress.colour, 0, ELPlayerProfile.COLOURS - 1): return false
	return progress.get("campaign") in ["Good", "Evil"] and ELLuaSave._integer(progress.get("number"), 1, 8) and ELLuaSave._integer(progress.get("subnumber", 1), 1, 2) and ELLuaSave._integer(progress.get("branch", 0), 0, 2) and ELLuaSave._integer(progress.get("score", 0), 0, 1000000000)

## Result of a finished campaign chapter: score and the chapters on offer.
static func chapter_result(state: ELAdventureSession) -> Dictionary:
	var progress: Dictionary = state.scenario.get("progress", {})
	if progress.is_empty() or state.outcome.is_empty(): return {}
	var campaign := ELCampaign.new()
	if not campaign.load_campaign(state.map.profile, progress.campaign): return {}
	var won := state.outcome == "win"
	var earned := ELCampaign.first_score(state.map.width, state.day, state.difficulty) if won else 0
	var branch: int = progress.subnumber if progress.number == ELCampaign.FIRST_BRANCH_NUMBER and won else progress.branch
	var next: Array[Dictionary] = []
	for row: Dictionary in campaign.first_next(progress.number, branch, won):
		var entry := row.duplicate()
		entry.merge({"campaign": progress.campaign, "score": progress.score + earned, "branch": branch}, true)
		for key: String in PROFILE_KEYS:
			if progress.has(key): entry[key] = progress[key]
		next.append(entry)
	return {"won": won, "earned": earned, "score": progress.score + earned, "next": next, "final": won and progress.number + 1 >= ELCampaign.FIRST_FINAL_NUMBER,
		"branch_text": text(state, "T_SELECT_CAMPAIGN_BRANCH_%d" % (1 if progress.campaign == "Good" else 2), "Choose which side to stand with.") if next.size() > 1 else ""}

static func is_castle(item: Dictionary) -> bool:
	return item.get("group") == "buildings" and item.get("name") == "MainTower"

static func castle_object(state: ELAdventureSession, player: int) -> Dictionary:
	for item: Dictionary in state.objects.values():
		if is_castle(item) and int(item.owner) == player: return item
	return {}

static func alive(state: ELAdventureSession, player: int) -> bool:
	return bool(state.scenario.get("castles", {}).get(player, {}).get("alive", false))

## Castle damage dealt by one hero: its level, or one and a half times it
## (rounded down) under Castle Bane. Learned skills, including Ethereal Attack
## and Counterstrike, do not change it in the original.
static func hero_value(hero: Dictionary) -> int:
	var level := maxi(0, int(hero.get("level", 1)))
	return level * 3 / 2 if ELGlobalSpells.hero_has(hero, "GRSH") else level

static func stage(castle: Dictionary) -> int:
	return clampi(int(3 * (int(castle.max) - int(castle.health)) / int(castle.max)), 0, 3)

## Damage stage shown by every castle figure: the MainTower building row of
## that level and its <Colour>Castle effect with the D1-D3 suffix. A ruined
## castle keeps the last stage on the map.
static func show_stages(state: ELAdventureSession) -> void:
	if not applies(state) or state.scenario.is_empty(): return
	for player: int in state.scenario.castles:
		show_stage(state, player)

static func show_stage(state: ELAdventureSession, player: int) -> void:
	var item := castle_object(state, player)
	var castle: Dictionary = state.scenario.get("castles", {}).get(player, {})
	if item.is_empty() or castle.is_empty(): return
	var shown := stage(castle)
	if int(item.get("castle_stage", -1)) == shown: return
	item.castle_stage = shown
	state.event.emit({"kind": "object_changed", "id": int(item.uid)})

static func assault_problem(state: ELAdventureSession, hero: Dictionary, target: Dictionary) -> String:
	if not is_castle(target) or state.scenario.is_empty(): return "This is not a castle."
	if hero.get("type") != "hero" or not hero.get("alive", false): return "Only a hero can attack a castle."
	if int(target.owner) == int(hero.owner): return "This is your own castle."
	if not alive(state, int(target.owner)): return "This castle is already ruined."
	if not state.hostile(hero, target): return "This castle belongs to an ally."
	return ""

## A hero beside an enemy castle during the night's actions adds its value to
## the castle's pending damage. The order stays, so it attacks again next night.
static func assault(director: ELAdventureDirector, hero: Dictionary, target: Dictionary) -> bool:
	var state := director.state
	if not assault_problem(state, hero, target).is_empty(): return false
	var owner := int(target.owner)
	var damage := hero_value(hero)
	state.scenario.castles[owner].pending += damage
	state.event.emit({"kind": "castle_assaulted", "hero": hero.uid, "player": owner, "damage": damage})
	if owner == state.current_player: _box(director, text(state, "T_MB_CASTLE_DAMAGED", "Your castle was attacked and lost %d energy.") % damage)
	return true

## Energy a castle regains from the ether its player left unused today:
## floor(sqrt(free / 6)), so 6 ether give 1, 24 give 2, 54 give 3.
static func regeneration(free: int) -> int:
	var amount := int(sqrt(maxi(0, free) / 6.0))
	while 6 * (amount + 1) * (amount + 1) <= free: amount += 1
	while amount > 0 and 6 * amount * amount > free: amount -= 1
	return amount

## Day end, once every player has finished and before the night: each living
## player's castle regains energy from its unused ether, up to its maximum.
## Energy that repairs pushed above the maximum falls back to it. Castle spells
## whose descriptions promise faster, slower or no regeneration, damage
## absorption or extra damage taken change none of this in the original.
static func regenerate(state: ELAdventureSession) -> void:
	if not applies(state) or state.scenario.is_empty(): return
	var ids: Array = state.scenario.castles.keys()
	ids.sort()
	for player: int in ids:
		var castle: Dictionary = state.scenario.castles[player]
		if not castle.alive or player < 1 or not state.players.has(player) or castle_object(state, player).is_empty(): continue
		var before := stage(castle)
		var amount := regeneration(ELGlobalSpells.free_ether(state, player))
		castle.health = mini(int(castle.max), int(castle.health) + amount)
		if amount > 0: state.event.emit({"kind": "castle_regenerated", "player": player, "amount": amount})
		if stage(castle) != before: state.event.emit({"kind": "castle_changed", "player": player, "stage": stage(castle)})
		show_stage(state, player)

## Night end: every living player's castle takes its pending damage at once.
static func end_night(director: ELAdventureDirector) -> void:
	var state := director.state
	if state.scenario.is_empty(): return
	var ids: Array = state.scenario.castles.keys()
	ids.sort()
	for player: int in ids:
		var castle: Dictionary = state.scenario.castles[player]
		if not castle.alive or player < 1 or castle_object(state, player).is_empty(): continue
		var before := stage(castle)
		castle.health = maxi(0, int(castle.health) - int(castle.pending))
		castle.pending = 0
		if stage(castle) != before or castle.health <= 0: state.event.emit({"kind": "castle_changed", "player": player, "stage": stage(castle)})
		show_stage(state, player)
		if castle.health <= 0: eliminate(director, player)

static func eliminate(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	var castle: Dictionary = state.scenario.castles.get(player, {})
	if castle.is_empty() or not castle.alive: return
	castle.alive = false
	castle.health = 0
	castle.pending = 0
	show_stage(state, player)
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and int(item.owner) == player and item.alive: state._native([float(item.uid)], "ExKillHero")
	state.event.emit({"kind": "player_eliminated", "player": player})
	var human := state.current_player
	var name := player_name(state, player)
	if player == human: _box(director, text(state, "T_MB_DESTROY_CASTLE_OWN", "Your castle is destroyed. You lost!"))
	elif not state.hostile({"owner": human}, {"owner": player}): _box(director, text(state, "T_MB_DESTROY_CASTLE_ALLY", "An allied castle is destroyed. Ally %s is defeated!") % name)
	else: _box(director, text(state, "T_MB_DESTROY_CASTLE_ENEMY", "An enemy castle is destroyed. Rival %s is defeated!") % name)
	if _temple(state) and RIVALS.get(human, -1) == player: open_rocks(state)

static func open_rocks(state: ELAdventureSession) -> void:
	for item: Dictionary in state.objects.values():
		if item.get("type") == "moveablerock" and item.visible:
			item.visible = false
			state.event.emit({"kind": "object_changed", "id": item.uid})

## Victory and defeat checks run at day start, after every battle and, in the
## capture chapter, while the duel is being fought. Defeat takes precedence.
static func evaluate(director: ELAdventureDirector, battle: Dictionary = {}) -> String:
	var state := director.state
	if not applies(state) or not state.outcome.is_empty() or state.scenario.is_empty(): return ""
	var human := state.current_player
	var lose := not alive(state, human)
	var win := false
	var id := state.map.id
	if not state.scenario.campaign:
		win = not lose
		for player: int in state.scenario.castles:
			if player != human and player >= 1 and alive(state, player) and state.hostile({"owner": human}, {"owner": player}): win = false
	elif not lose:
		if BATTLE_GOALS.has(id) and not battle.is_empty():
			var opponent := _opponent_of_human(state, battle)
			win = opponent.get("name") == BATTLE_GOALS[id] and (int(battle.winner) < 0 or int(battle.winner) != int(opponent.uid))
		elif CASTLE_GOALS.has(id):
			win = true
			for player: int in CASTLE_GOALS[id].win: win = win and not alive(state, player)
			for player: int in CASTLE_GOALS[id].lose: lose = lose or not alive(state, player)
		elif id == "mission14" and not battle.is_empty():
			var opponent := _opponent_of_human(state, battle)
			win = String(opponent.get("name", "")).begins_with("Konung of Fire") and int(battle.winner) >= 0 and int(battle.winner) != int(opponent.uid)
		elif id == "mission23":
			var flock := false
			for item: Dictionary in state.objects.values():
				# Creatures held off the map in lairs are not part of the flock.
				if item.alive and item.get("type") == "monster" and int(item.owner) <= 0 and String(item.name).contains("Aviak") and not item.has("dungeon"): flock = true
				if item.alive and item.get("type") == "hero" and int(item.owner) <= 0 and String(item.name).contains("Gamma-400") and Vector2i(item.x, item.y) == Vector2i(41, 33): lose = true
			win = not flock and director.encounter == null
		elif id == "mission24":
			# The tomb opens only between battles: in practice at the next dawn.
			if battle.is_empty() and director.encounter == null: _update_tomb(state)
			if state.scenario.tomb_open and not battle.is_empty() and int(battle.winner) >= 0:
				var loser := state.object(battle.opponent if int(battle.winner) == int(battle.hero) else battle.hero)
				win = loser.get("tomb_keeper", false)
		elif id in ["mission15", "mission25"]:
			lose = _heroes(state, human).is_empty()
		elif _temple(state) and battle.is_empty():
			var temple := {}
			for item: Dictionary in state.objects.values():
				if item.get("type") == "whitecastle": temple = item
			if not temple.is_empty():
				for hero: Dictionary in _heroes(state, human):
					if ELStrategy.adjacent(director, hero, temple): win = true
		elif _last_step(state) and not battle.is_empty():
			var opponent := _opponent_of_human(state, battle)
			if not opponent.is_empty():
				if int(battle.winner) < 0 or int(battle.winner) == int(opponent.uid): lose = true
				elif opponent.get("name") == "White Lord II": win = true
	if lose: return finish(director, "lose")
	if win: return finish(director, "win")
	return ""

## Last-step chapters skip the usual first day: the hero's spell lab opens with
## free exchange, then the two White Lord battles follow in order.
static func opening(director: ELAdventureDirector) -> bool:
	var state := director.state
	if not applies(state) or not _last_step(state) or not state.scenario.campaign or state.scenario.opening: return false
	var hero := state.object(state.main_hero)
	var lords: Array[int] = []
	for name: String in ["White Lord I", "White Lord II"]:
		for item: Dictionary in state.objects.values():
			if item.alive and item.get("type") == "hero" and item.name == name: lords.append(int(item.uid))
	if hero.is_empty() or lords.size() != 2: return false
	state.scenario.opening = true
	director.strategy = {"phase": "combat", "actors": [], "index": 0, "combats": [[hero.uid, lords[0]], [hero.uid, lords[1]]], "legacy_orders": false}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "el1_spell_shop" and item.alive:
			var shop := ELFirstSpellShop.new()
			if shop.open(state, hero.uid, item.uid):
				director.first_shop = shop
				director.presentation.emit({"kind": "el1_spell_shop", "hero": hero.uid, "shop": item.uid})
			break
	return true

## The Lost City bunker ends the chapter in victory when a hero activates it.
static func town_bunker(director: ELAdventureDirector, hero: Dictionary) -> void:
	if not applies(director.state) or not director.state.outcome.is_empty(): return
	# The bunker's building message (BldngMsg1TownBunker) in the MessageBox.
	_box(director, text(director.state, "BldngMsg1TownBunker", "TownBunker"))
	finish(director, "win")

static func finish(director: ELAdventureDirector, result: String) -> String:
	var state := director.state
	state.outcome = result
	var message := text(state, "T_MB_YOU_WIN", "Victory!") if result == "win" else text(state, "T_MB_YOU_LOSE", "Mission lost")
	# A won single mission or campaign final enters the Hall of Fame.
	var hall := ELHallOfFame.record_mission(state) if result == "win" else ""
	state.event.emit({"kind": "mission_finished", "outcome": result, "text": message, "hall_of_fame": hall})
	return result

## Capture chapter: the outcome appears as soon as Diamanda's duel health enters
## 1..5 (captured) or reaches zero (killed), without finishing the duel.
static func duel_watch(state: ELAdventureSession, hero_id: int, opponent_id: int) -> int:
	if not applies(state) or state.map.id != "mission13" or not state.scenario.get("campaign", false): return -1
	for side in 2:
		var actor := state.object(hero_id if side == 0 else opponent_id)
		if actor.get("type") == "hero" and actor.get("name") == "Diamanda" and int(actor.owner) != state.current_player: return side
	return -1

static func duel_check(director: ELAdventureDirector, battle: ELDuel, side: int) -> String:
	if side < 0 or battle == null or not director.state.outcome.is_empty(): return ""
	var health := int(battle.heroes[side].health)
	if health <= 0: return finish(director, "lose")
	if health <= 5: return finish(director, "win")
	return ""

static func player_name(state: ELAdventureSession, player: int) -> String:
	var chosen: Variant = state.players.get(player, {}).get("name")
	if chosen is String: return chosen
	for row: Dictionary in state.map.players:
		if int(row.attrs.id) == player: return state.map.profile.text(ELXml.value(row, "name"))
	return str(player)

static func text(state: ELAdventureSession, key: String, fallback: String) -> String:
	var value := state.map.profile.text(key)
	return fallback if value.is_empty() or value == key else value

## Castle notices appear in the original MessageBox (OK alone); the map waits
## until it is closed.
static func _box(director: ELAdventureDirector, message: String) -> void:
	director.notice = message
	director.presentation.emit({"kind": "building_message", "hero": -1, "building": -1, "title": "", "text": message, "resources": [], "skill": "", "key": "", "box": "first"})

static func _message(director: ELAdventureDirector, message: String) -> void:
	director.notice = message
	director.presentation.emit({"kind": "notice", "text": message})

static func _heroes(state: ELAdventureSession, player: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.alive and int(item.owner) == player: result.append(item)
	return result

static func _opponent_of_human(state: ELAdventureSession, battle: Dictionary) -> Dictionary:
	var first := state.object(battle.hero)
	var second := state.object(battle.opponent)
	if int(first.get("owner", -1)) == state.current_player: return second
	if int(second.get("owner", -1)) == state.current_player: return first
	return {}

static func _update_tomb(state: ELAdventureSession) -> void:
	if state.scenario.tomb_open: return
	for item: Dictionary in state.objects.values():
		if item.alive and item.get("type") == "hero" and int(item.owner) <= 0 and String(item.name).contains("Spirit X"): return
	state.scenario.tomb_open = true
	state.event.emit({"kind": "tomb_opened"})

static func _temple(state: ELAdventureSession) -> bool:
	return state.map.id in ["mission161", "mission162", "mission261", "mission262"]

static func _last_step(state: ELAdventureSession) -> bool:
	return state.map.id in ["mission171", "mission172", "mission271", "mission272"]
