class_name ELCursors
extends RefCounted
## Original mouse cursors of both games: the cursor set, its frames and
## hotspots, and which cursor a screen state asks for.
##
## Contract:
## - Each game registers a fixed table of `Cursors\<name>` textures (the first
##   game 16, the second 21). A texture is a strip of square frames (frame
##   size = texture height); black (RGB 0) is transparent and every other
##   texel is opaque. Frames advance every 125 ms; each cursor keeps its own
##   frame position while another cursor is shown.
## - Hotspots are authored in 48-pixel cursor space: the scroll cursors point
##   at the edge they name, the second game's default gauntlet at (2, 0), every
##   other cursor at its top-left corner.
## - Menus and windows use the default cursor. The adventure map picks an
##   action cursor for the object or cell under the pointer; the first game's
##   combat shows the spell cursor over a valid target and the attack cursor
##   where a selected creature can attack the enemy hero or block an attacker.
##   The second game's combat keeps the default cursor.

const FRAME_TIME := 0.125
## Second game: a script that has held the map this long shows the script
## camera cursor (ScriptCursorDelay, 2000 ms by default).
const SCRIPT_DELAY := 2.0

## Cursor tables in registration order: name -> hotspot.
const FIRST := [
	["default", Vector2i(0, 0)], ["attack", Vector2i(0, 0)], ["camera", Vector2i(0, 0)], ["cancel", Vector2i(0, 0)],
	["move", Vector2i(0, 0)], ["scroll_u", Vector2i(24, 0)], ["scroll_ur", Vector2i(48, 0)], ["scroll_r", Vector2i(48, 24)],
	["scroll_dr", Vector2i(48, 48)], ["scroll_d", Vector2i(24, 48)], ["scroll_dl", Vector2i(0, 48)], ["scroll_l", Vector2i(0, 24)],
	["scroll_ul", Vector2i(0, 0)], ["spell", Vector2i(0, 0)], ["use", Vector2i(0, 0)], ["wait", Vector2i(0, 0)]]
const SECOND := [
	["default", Vector2i(2, 0)], ["attack", Vector2i(0, 0)], ["camera", Vector2i(0, 0)], ["cancel", Vector2i(0, 0)],
	["move", Vector2i(0, 0)], ["scroll_u", Vector2i(24, 0)], ["scroll_ur", Vector2i(48, 0)], ["scroll_r", Vector2i(48, 24)],
	["scroll_dr", Vector2i(48, 48)], ["scroll_d", Vector2i(24, 48)], ["scroll_dl", Vector2i(0, 48)], ["scroll_l", Vector2i(0, 24)],
	["scroll_ul", Vector2i(0, 0)], ["spell", Vector2i(0, 0)], ["use", Vector2i(0, 0)], ["wait", Vector2i(0, 0)],
	["speak", Vector2i(0, 0)], ["drag", Vector2i(0, 0)], ["grap1", Vector2i(0, 0)], ["grap2", Vector2i(0, 0)],
	["script_camera", Vector2i(0, 0)]]

static func table(edition: String) -> Array:
	return SECOND if edition == "el2" else FIRST

static func names(edition: String) -> Array[String]:
	var result: Array[String] = []
	for entry: Array in table(edition): result.append(entry[0])
	return result

static func hotspot(edition: String, name: String) -> Vector2i:
	for entry: Array in table(edition):
		if entry[0] == name: return entry[1]
	return Vector2i.ZERO

## Frames of one cursor: {"frames": Array[ImageTexture], "images": Array[Image],
## "hotspot": Vector2i}, or empty when the texture is missing. Cached per
## profile, so each edition keeps its own set.
static func cursor(profile: ELProfile, name: String) -> Dictionary:
	if profile == null: return {}
	if profile.cursor_cache.has(name): return profile.cursor_cache[name]
	var entry := {}
	if names(profile.id).has(name):
		var strip := ELTexture.decode(profile.read("textures", "cursors/cursor_" + name + ".mmp"))
		# Every frame sits at the top-left of a 48-pixel cursor surface, so
		# hotspots stay in 48-pixel units whatever the frame size.
		if strip != null: entry = {"images": frames(strip), "hotspot": hotspot(profile.id, name)}
		if not entry.is_empty():
			var textures: Array[ImageTexture] = []
			for image: Image in entry.images: textures.append(ImageTexture.create_from_image(image))
			entry.frames = textures
	profile.cursor_cache[name] = entry
	return entry

## Square frames of a strip with the colour-key transparency applied.
static func frames(strip: Image) -> Array[Image]:
	var result: Array[Image] = []
	var size := strip.get_height()
	if size <= 0: return result
	for index in strip.get_width() / size:
		var frame := strip.get_region(Rect2i(index * size, 0, size, size))
		frame.convert(Image.FORMAT_RGBA8)
		var data := frame.get_data()
		for at in range(0, data.size(), 4):
			data[at + 3] = 0 if data[at] == 0 and data[at + 1] == 0 and data[at + 2] == 0 else 255
		result.append(Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data))
	return result

# --- Adventure map -----------------------------------------------------------

## Second game. `context`: hero (selected hero id or -1), picked (object id or
## -1), tile (Vector2i), on_map (pointer over the map, not a panel), in_bounds,
## modal (a window or message box is open), right_held, busy_time (seconds a
## script has held the map, < 0 when it does not), previous (current cursor).
static func second_adventure(state: ELAdventureSession, director: ELAdventureDirector, context: Dictionary) -> String:
	var busy := float(context.get("busy_time", -1.0))
	if busy >= 0.0:
		if context.get("modal", false): return "default"
		return "script_camera" if busy > SCRIPT_DELAY else str(context.get("previous", "default"))
	if context.get("modal", false) or not context.get("on_map", false): return "default"
	if context.get("right_held", false): return "grap2"
	if not context.get("in_bounds", true): return "cancel"
	var hero := state.object(int(context.get("hero", -1)))
	if hero.is_empty() or not hero.get("alive", false): hero = {}
	var picked := state.object(int(context.get("picked", -1)))
	if not picked.is_empty(): return _second_object(state, hero, picked)
	var tile: Vector2i = context.get("tile", Vector2i(-1, -1))
	if hero.is_empty(): return "default"
	if not ELFog.targetable(state, state.current_player, tile): return "cancel"
	return second_route(state, director, hero, tile)

## A free cell: reachable around hostile guard areas -> default, reachable only
## through one -> attack, unreachable -> cancel.
static func second_route(state: ELAdventureSession, director: ELAdventureDirector, hero: Dictionary, tile: Vector2i) -> String:
	if director == null or director.grid == null: return "default"
	var from := Vector2i(hero.x, hero.y)
	var ship: bool = hero.get("ship", false)
	var avoid := director.interception.hostile_cells(state, hero)
	# Ending inside a hostile guard area always meets the guard.
	if avoid.has(tile): return "attack" if not director.grid.path(from, tile, ship).is_empty() else "cancel"
	if not avoid.is_empty():
		var safe := director.grid.path(from, tile, ship, avoid)
		# path() falls back to the unrestricted route; a safe one avoids every
		# hostile cell except the destination.
		if not safe.is_empty():
			for point: Vector2i in safe.slice(1, safe.size() - 1):
				if avoid.has(point): return "attack"
			return "default"
		return "cancel"
	return "default" if not director.grid.path(from, tile, ship).is_empty() else "cancel"

static func _second_object(state: ELAdventureSession, hero: Dictionary, item: Dictionary) -> String:
	var figure: bool = item.get("type") in ["hero", "monster"]
	if hero.is_empty():
		return "default" if figure and int(item.get("owner", -1)) == state.current_player else "cancel"
	if item.uid == hero.uid: return "default"
	if figure and int(item.get("owner", -1)) == int(hero.get("owner", -2)): return "cancel"
	# A garrisoned or Fortify hero can only act on forts.
	if (hero.get("fortified", false) or int(hero.get("spell_fort", 0)) > 0) and item.get("type") != "fort": return "cancel"
	if figure:
		if state.hostile(hero, item): return "attack"
		return "speak" if item.get("enabled", true) else "cancel"
	match str(item.get("group", "")):
		"forts":
			var guard := state.object(int(item.get("garrison", -1)))
			if guard.is_empty() or guard.uid == hero.uid: return "use"
			return "attack" if state.hostile(hero, guard) else "cancel"
		"buildings":
			# The main tower restores lost experience to the main hero.
			if item.get("name") == "MainTower":
				return "use" if int(hero.uid) == state.main_hero and float(hero.get("experience_penalty", 0.0)) > 0.0 else "cancel"
			return "cancel"
		"resource_cuts", "laboratories", "factories", "artefacts": return "use"
		"global_spells": return "cancel"
		"mines", "mana_nodes": return "use" if int(item.get("owner", -1)) != int(hero.get("owner", -2)) else "cancel"
		"additional_buildings":
			if not item.get("enabled", true): return "cancel"
			if ELSecondGates.is_gate(item): return "use" if ELSecondGates.usable(hero, item) else "cancel"
			if ELSecondGates.is_warding(item): return "use" if not item.get("used", false) else "cancel"
			if ELSecondBuildings.applies(state, item): return "use" if ELSecondBuildings.usable(state, hero, item) else "cancel"
			return "use"
	if item.get("type") in ["teleport", "dock"]: return "use" if item.get("enabled", true) else "cancel"
	return "cancel"

## First game. `context`: hero, picked, tile, on_map, in_bounds, modal,
## local_turn (the local player may give orders now).
static func first_adventure(state: ELAdventureSession, director: ELAdventureDirector, context: Dictionary) -> String:
	if context.get("modal", false) or not context.get("on_map", false): return "default"
	if not context.get("local_turn", true) or not context.get("in_bounds", true): return "cancel"
	var hero := state.object(int(context.get("hero", -1)))
	if hero.is_empty() or not hero.get("alive", false): hero = {}
	var picked := state.object(int(context.get("picked", -1)))
	if not picked.is_empty(): return _first_object(state, hero, picked)
	var tile: Vector2i = context.get("tile", Vector2i(-1, -1))
	var player := state.current_player
	if ELFog.active(state, player) and not ELFog.explored(state, player, tile): return "cancel"
	# A cell inside a hostile guard area: the move ends in a battle.
	if not hero.is_empty() and director != null and not director.interception.enemies(state, hero, tile).is_empty(): return "attack"
	return "default"

static func _first_object(state: ELAdventureSession, hero: Dictionary, item: Dictionary) -> String:
	var player := state.current_player
	var figure: bool = item.get("type") in ["hero", "monster"]
	var own := int(item.get("owner", -1)) == player
	if hero.is_empty():
		return "default" if own and (figure or _first_building(item)) else "cancel"
	if figure:
		if int(item.get("owner", -1)) <= 0: return "attack"
		return "default" if not state.hostile(hero, item) else "attack"
	if ELFirstScenario.is_castle(item):
		if not state.hostile(hero, item): return "default"
		return "attack" if ELFirstScenario.alive(state, int(item.owner)) else "cancel"
	var group := str(item.get("group", ""))
	if group in ["mines", "mana_nodes"] and int(item.get("owner", -1)) != int(hero.owner): return "use"
	if group in ["laboratories", "factories", "forts", "resource_cuts"] or item.get("type") == "fort" or ELMapPickups.is_pickup(item): return "use"
	if group == "additional_buildings" and ELAdditionalBuildings.supported(item) and item.get("enabled", true): return "use"
	return "default" if own and _first_building(item) else "cancel"

## Owned objects of the first game that count as the player's buildings.
static func _first_building(item: Dictionary) -> bool:
	return str(item.get("group", "")) in ["buildings", "mines", "mana_nodes", "laboratories", "factories", "forts", "additional_buildings"]

# --- Combat (first game) -----------------------------------------------------

## The first game's combat cursor over `hovered` (-1 for none). `pending` is
## the targeting in progress: {} or {"card": code} for a hand spell,
## {"ability": definition, "source": id} for an ability or artifact. The
## second game's combat always keeps the default cursor.
static func first_combat(duel: ELDuel, hovered: int, pending: Dictionary, selected: int) -> String:
	if duel == null or hovered < 0 or duel.entity(hovered).is_empty(): return "default"
	if not pending.is_empty():
		return "spell" if _valid_target(duel, hovered, pending) else "default"
	if selected < 2 or not duel.creatures.has(selected): return "default"
	if duel.phase == ELDuel.Phase.ATTACK and hovered == 1 - duel.attacker:
		if duel.creatures[selected].owner == duel.attacker and not duel.attacks.has(selected) and duel.can_attack(selected): return "attack"
	elif duel.phase == ELDuel.Phase.DEFENCE and duel.attacks.has(hovered):
		if duel.creatures[selected].owner == 1 - duel.attacker and duel.block_problem(selected, hovered).is_empty(): return "attack"
	return "default"

static func _valid_target(duel: ELDuel, hovered: int, pending: Dictionary) -> bool:
	if pending.has("card"): return duel._target_error(str(pending.card), hovered).is_empty()
	var ability: Dictionary = pending.get("ability", {})
	if ability.get("effect") == "artifact":
		return duel.artifact_target_error(int(pending.get("source", 0)), str(ability.get("card", "")), hovered).is_empty()
	match str(ability.get("target", "")):
		"creature": return duel.creatures.has(hovered)
		"hero": return hovered < 2
		"any", "enchantment": return true
		"grave": return hovered < 2
	return false
