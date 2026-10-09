class_name ELAdventureSave
extends RefCounted
## A campaign checkpoint includes the script graph, mutable world, and the
## in-flight command. Restoration creates a fresh session before it is committed.
const FORMAT := "etherlords-adventure"
const MAX_BYTES := 32 * 1024 * 1024
const STATE_FIELDS := ["main_hero", "current_player", "day", "difficulty", "seed_value", "camera_zoom", "camera_rotation", "camera_locked", "exclusive", "outcome", "colorless_level", "_next_effect", "_next_object"]
var error := ""

func encode(director: ELAdventureDirector, camera: Dictionary = {}) -> Dictionary:
	error = ""
	var state := director.state
	if director._shopping():
		error = "Close the shop or resource site before saving the campaign."
		return {}
	if not director.error.is_empty() or not state.error.is_empty():
		error = "The campaign cannot be saved after a scenario error."
		return {}
	var world := {}
	for key: String in STATE_FIELDS: world[key] = state.get(key)
	world.income_day = state.income_day
	var objects: Array[Dictionary] = []
	for item: Dictionary in state.objects.values():
		var copy := item.duplicate(true)
		copy.erase("node")
		objects.append(copy)
	var players: Array[Dictionary] = []
	for id: int in state.players:
		var player: Dictionary = state.players[id].duplicate(true)
		player.id = id
		players.append(player)
	var script := {}
	if state.vm != null:
		var codec := ELLuaSave.new()
		script = codec.encode(state.vm)
		if script.is_empty():
			error = codec.error
			return {}
	var movement := director.movement.duplicate(true)
	if not movement.is_empty():
		var points: Array = []
		for point: Vector2i in movement.path: points.append([point.x, point.y])
		movement.path = points
	var encounter := {}
	if director.encounter != null:
		encounter = {"hero": director.encounter.hero_id, "opponent": director.encounter.opponent_id, "ethereal": director.encounter.ethereal_defender, "battle": {"format": "etherlords-duel", "version": 1, "state": director.encounter.battle.snapshot()}}
	return {"format": FORMAT, "version": 1, "edition": state.map.profile.id, "map": state.map.id, "map_hash": _map_hash(state.map), "script_name": state.script_name, "encounter": encounter,
		"world": world, "scenario": state.scenario.duplicate(true), "objects": objects, "players": players, "explored": Marshalls.raw_to_base64(state.explored), "notebook": ELSecondNotebook.encode(state), "observations": state.observations.duplicate(true), "ambience": ELSecondAmbience.encode(state), "script": script,
		"commands": state.commands.duplicate(true), "director": {"movement": movement, "strategy": director.strategy.duplicate(true), "guard_zones": director.interception.snapshot(), "dialogue": director.dialogue.duplicate(true), "boxes": director.boxes.duplicate(true), "action_wait": director.action_wait, "player_round": director.player_round, "woken": director._woken, "waiting": director._waiting, "wait_remaining": director.wait_remaining, "clock": director._clock}, "camera": camera.duplicate(true)}

func write(path: String, director: ELAdventureDirector, camera: Dictionary = {}) -> bool:
	# The remake keeps fixed campaign/mission slots; the tutorial is not saved
	# into them, as the original tutorial cannot be saved.
	if director != null and director.state != null and director.state.tutorial: return _fail("The tutorial cannot be saved.")
	var document := encode(director, camera)
	if document.is_empty(): return false
	# Full precision: script numbers (e.g. EL2 battle-script weights) must
	# survive the round trip exactly.
	var text := JSON.stringify(document, "", true, true)
	if text.length() > MAX_BYTES: return _fail("Campaign save exceeds its size limit.")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("Could not write the campaign save.")
	file.store_string(text)
	file.flush()
	file.close()
	if DirAccess.rename_absolute(temporary, path) != OK: return _fail("Could not replace the campaign save.")
	return true

func read(path: String, profiles: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		_fail("No readable campaign save was found.")
		return {}
	return decode(JSON.parse_string(file.get_as_text()), profiles)

func decode(raw: Variant, profiles: Dictionary) -> Dictionary:
	error = ""
	if not raw is Dictionary or raw.get("format") != FORMAT or raw.get("version") != 1 or not profiles.has(raw.get("edition")):
		_fail("This is not a campaign save for an installed edition.")
		return {}
	if not raw.get("map") is String or not String(raw.map).is_valid_identifier() or not raw.get("script_name") is String or not raw.get("world") is Dictionary or not raw.get("objects") is Array or not raw.get("players") is Array or not raw.get("commands") is Array or not raw.get("director") is Dictionary or not raw.get("camera") is Dictionary:
		_fail("Campaign save data is incomplete.")
		return {}
	if raw.objects.size() > 100000 or not _plain(raw, 0):
		_fail("Campaign save data exceeds its limits.")
		return {}
	var map := ELAdventureMap.new()
	if not map.load_map(profiles[raw.edition], raw.map):
		_fail(map.error)
		return {}
	if raw.get("map_hash") != _map_hash(map):
		_fail("The original map has changed since this campaign was saved.")
		return {}
	var world: Dictionary = raw.world
	for key: String in STATE_FIELDS:
		if not world.has(key):
			_fail("Saved campaign world is incomplete.")
			return {}
	for key: String in ["main_hero", "current_player", "day", "difficulty", "seed_value", "colorless_level", "_next_effect", "_next_object"]:
		if not ELLuaSave._integer(world[key], -1 if key == "main_hero" else 0, 0xffffffff):
			_fail("Invalid campaign world value: " + key)
			return {}
	if world.difficulty > 4 or not world.camera_locked is bool or not world.exclusive is bool or world.outcome not in ["", "win", "lose"] or not _number(world.camera_zoom, 1, 1000) or not _number(world.camera_rotation, -100000, 100000):
		_fail("Invalid campaign options.")
		return {}
	var next := ELAdventureSession.new()
	if not next.start(map, int(world.difficulty), int(world.seed_value), raw.script_name): return _reject(next, next.error)
	if not ELLuaSave._integer(world.get("income_day", 0), 0, 0xffffffff): return _reject(next, "Invalid saved income day.")
	next.income_day = int(world.get("income_day", 0))
	# Saves from before the Notebook carry no entries.
	var notes: Variant = ELSecondNotebook.decode(raw.get("notebook", []))
	if notes == null: return _reject(next, "Invalid saved notebook.")
	next.notebook = notes
	next.notebook_next = ELSecondNotebook.next_id(notes)
	var objects := {}
	for record: Variant in raw.objects:
		if not record is Dictionary or not ELLuaSave._integer(record.get("uid"), 0, 0x7fffffff) or objects.has(int(record.uid)) or not ELLuaSave._integer(record.get("source_index"), -1, map.objects.size() - 1): return _reject(next, "Invalid saved object identity.")
		for key: String in ["name", "group", "type", "shape"]:
			if not record.get(key) is String: return _reject(next, "Invalid saved object description.")
		for key: String in ["alive", "visible", "enabled"]:
			if not record.get(key) is bool: return _reject(next, "Invalid saved object flag.")
		# Hidden authored objects use signed 32-bit off-map sentinels.
		for key: String in ["x", "y"]:
			if not ELLuaSave._integer(record.get(key), -0x80000000, 0x7fffffff): return _reject(next, "Invalid saved object position.")
		for key: String in ["rotation", "owner", "level", "health", "base_ap", "ap", "experience"]:
			if not ELLuaSave._integer(record.get(key), -100000, 10000000): return _reject(next, "Invalid saved object statistic: %s / %s = %s" % [record.uid, key, record.get(key)])
		if not record.get("cards") is Array or not record.get("orders") is Array or not record.get("inventory") is Array or not record.get("spell_stock") is Dictionary: return _reject(next, "Invalid saved inventory.")
		if record.has("stock_separate") and not record.stock_separate is bool: return _reject(next, "Invalid saved inventory version.")
		if record.has("allowed_colors"):
			if not record.allowed_colors is Dictionary: return _reject(next, "Invalid saved spell colors.")
			for color: Variant in record.allowed_colors:
				if not color is String or not record.allowed_colors[color] is bool: return _reject(next, "Invalid saved spell colors.")
		# Authored enemies can have larger books than the player's 15/16 slots.
		if record.cards.size() > 128: return _reject(next, "Saved spellbook exceeds its limit.")
		for card: Variant in record.cards:
			if not card is String or card.length() != 4: return _reject(next, "Invalid saved spellbook entry.")
		for card: Variant in record.spell_stock:
			if not card is String or card.length() != 4 or not ELLuaSave._integer(record.spell_stock[card], 0, ELSpellInventory.MAX_COPIES): return _reject(next, "Invalid saved reserve spell.")
		var item: Dictionary = record.duplicate(true)
		item.uid = int(item.uid)
		for key: String in ["source_index", "x", "y", "rotation", "owner", "level", "health", "base_ap", "ap", "experience"]: item[key] = int(item[key])
		item.node = map.objects[item.source_index].node if item.source_index >= 0 else {}
		for card: String in item.spell_stock: item.spell_stock[card] = int(item.spell_stock[card])
		if not item.get("stock_separate", false):
			# Older checkpoints counted the equipped book a second time in reserve.
			for card: String in item.cards: ELSpellInventory.remove(item, card)
		for card: String in item.spell_stock:
			if not ELSpellInventory.is_spell(map.profile, card): return _reject(next, "Unknown saved reserve spell.")
		item.stock_separate = true
		if item.group in ["factories", "laboratories"] and map.profile.id == "el1":
			if not ELBuildings.restore(map.profile, item): return _reject(next, "Invalid saved shop building.")
		if ELResourceSites.TYPES.has(item.group):
			if not ELResourceSites.restore(map.profile, item): return _reject(next, "Invalid saved resource site.")
		if item.group == "forts":
			if not ELForts.restore(map.profile, item): return _reject(next, "Invalid saved fort.")
		if item.group == "additional_buildings" and map.profile.id == "el1":
			if not ELAdditionalBuildings.restore(map.profile, item): return _reject(next, "Invalid saved map building.")
		if item.group == "laboratories" and map.profile.id == "el2":
			item.type = "spell_shop"
			if not item.has("shop_stock"): item.shop_stock = ELSpellShop.authored_stock(map.profile, item.node)
			if not item.shop_stock is Array or item.shop_stock.size() > 100000: return _reject(next, "Invalid saved shop stock.")
			for card: Variant in item.shop_stock:
				if not card is String or not ELSpellInventory.is_spell(map.profile, card): return _reject(next, "Unknown saved shop spell.")
		if map.profile.id == "el1" and item.type == "monster" and not item.has("strategy_version") and next.object(item.uid).get("type") == "hero":
			# Early saves classified every neutral actor as a monster and left
			# these authored heroes with an empty book and generic stats.
			var authored := next.object(item.uid).duplicate(true)
			for field: String in ["type", "level", "health", "experience", "experience_penalty", "level_history", "skill_points", "skill_offers", "health_growth", "health_base", "cards", "skills", "rune_uses", "rune_stock", "title", "specialization"]: item[field] = authored[field]
		if map.profile.id == "el1" and item.type == "monster":
			if not item.has("monster_version"):
				if not ELFirstMonsters.initialize(map.profile, item, int(world.difficulty)): return _reject(next, "Missing neutral creature definition.")
			if not ELLuaSave._integer(item.monster_version, 1, 1) or not ELLuaSave._integer(item.get("monster_difficulty"), 0, 4) or ELFirstMonsters.definition(map.profile, item.name, int(item.monster_difficulty)).is_empty(): return _reject(next, "Invalid neutral creature definition.")
			item.monster_difficulty = int(item.monster_difficulty)
		if item.type in ["hero", "monster"] and not _restore_progression(map.profile, item): return _reject(next, "Invalid saved hero progression.")
		if item.has("specialization") and not ELSpecs.valid(map.profile, item.specialization): return _reject(next, "Invalid saved specialization.")
		if item.has("specializations"):
			if item.specializations is not Array or item.specializations.size() > 64: return _reject(next, "Invalid saved specializations.")
			for code: Variant in item.specializations:
				if not ELSpecs.valid(map.profile, code) or code == "NONE": return _reject(next, "Invalid saved specializations.")
		if map.profile.id == "el2" and item.type in ["hero", "monster"] and not ELAdventureClock.restore(item, int(world.day)): return _reject(next, "Invalid saved travel clock.")
		if map.profile.id == "el1" and item.type in ["hero", "monster"] and not ELRunes.restore(map.profile, item): return _reject(next, "Invalid saved rune inventory.")
		if map.profile.id == "el1" and item.type in ["hero", "monster"] and not ELStrategy.restore(map.profile, item, map): return _reject(next, "Invalid saved strategic movement.")
		if map.profile.id == "el1" and item.type == "hero" and not ELAdditionalBuildings.restore_hero(item): return _reject(next, "Invalid saved building bonus.")
		if map.profile.id == "el1" and item.type == "hero" and not ELMapPickups.restore_hero(map.profile, item): return _reject(next, "Invalid saved hero items.")
		if map.profile.id == "el2" and item.type == "hero" and not ELSecondArtifacts.restore_hero(map.profile, item): return _reject(next, "Invalid saved hero artifacts.")
		objects[item.uid] = item
	for id: int in next.objects:
		# Creatures created at start (lair stock) are replaced by the saved ones.
		if not objects.has(id) and int(next.objects[id].get("source_index", -1)) >= 0: return _reject(next, "A placed map object is missing from the save.")
	if not ELForts.valid_links(objects, map): return _reject(next, "Invalid saved fort garrison.")
	if map.profile.id == "el1" and not ELAdditionalBuildings.valid_links(objects): return _reject(next, "Invalid saved lair creature.")
	for item: Dictionary in objects.values():
		var order: Dictionary = item.get("strategy_order", {})
		if not order.is_empty() and order.use >= 0 and not objects.has(order.use): return _reject(next, "Missing strategic order target.")
	if world.main_hero >= 0 and not objects.has(int(world.main_hero)): return _reject(next, "The saved hero is missing.")
	var players := {}
	for record: Variant in raw.players:
		if not record is Dictionary or not ELLuaSave._integer(record.get("id"), 0, 32) or not record.get("resources") is Dictionary or not record.get("relations") is Dictionary: return _reject(next, "Invalid player state.")
		if not ELResources.valid(map.profile.id, record.resources): return _reject(next, "Invalid saved resource balance.")
		if not ELPlayerProfile.valid_saved(record): return _reject(next, "Invalid saved player name or blazon.")
		var player: Dictionary = record.duplicate(true)
		for kind: String in player.resources: player.resources[kind] = int(player.resources[kind])
		player.relations = {}
		for key: Variant in record.relations:
			if not str(key).is_valid_int(): return _reject(next, "Invalid player relation.")
			player.relations[int(key)] = record.relations[key]
		players[int(player.id)] = player
	for item: Dictionary in objects.values():
		if (item.get("building_version") == 1 or item.get("site_version") == 1 or item.get("fort_version") == 1 or item.get("addition_version") == 1) and item.owner >= 0 and not players.has(item.owner): return _reject(next, "Missing owner of a saved building.")
	if not raw.get("explored") is String: return _reject(next, "Missing exploration state.")
	var explored := Marshalls.base64_to_raw(raw.explored)
	if explored.size() != map.width * map.height: return _reject(next, "Invalid exploration dimensions.")
	# EL2 script observations; saves from before them carry none.
	var watched: Variant = raw.get("observations", {})
	if not watched is Dictionary or watched.size() > 1000 or (map.profile.id != "el2" and not watched.is_empty()): return _reject(next, "Invalid saved observations.")
	var observations := {}
	for key: Variant in watched:
		var entry: Variant = watched[key]
		if not key is String or key.is_empty() or not entry is Array or entry.size() != 3: return _reject(next, "Invalid saved observations.")
		if not ELLuaSave._integer(entry[0], -0x80000000, 0x7fffffff) or not ELLuaSave._integer(entry[1], -0x80000000, 0x7fffffff) or not ELLuaSave._integer(entry[2], 0, 0x7fffffff): return _reject(next, "Invalid saved observations.")
		observations[key] = [int(entry[0]), int(entry[1]), int(entry[2])]
	for command: Variant in raw.commands:
		if not command is Dictionary or not command.get("kind") is String or not command.get("arguments") is Array or not next._bindings().has("ExAddCommand" + command.kind): return _reject(next, "Invalid queued campaign command.")
	if next.vm != null:
		var codec := ELLuaSave.new()
		if not codec.decode(next.vm, raw.get("script")): return _reject(next, codec.error)
		if not next.vm.globals.get("__engine_variables") is ELLuaVM.Table: return _reject(next, "Missing engine quest variables.")
		next.variables = next.vm.globals["__engine_variables"]
		# Saves from before the persistence flag carry no persistent keys.
		if not next.vm.globals.get("__engine_persistent") is ELLuaVM.Table: next.vm.globals["__engine_persistent"] = next.vm.table()
		next.persistent = next.vm.globals["__engine_persistent"]
	next.objects = objects
	if map.profile.id == "el1": ELAdditionalBuildings.sync_heroes(next)
	next.players = players
	next.explored = explored
	next.observations = observations
	next.commands.assign(raw.commands)
	for key: String in STATE_FIELDS: next.set(key, world[key])
	if map.profile.id == "el1":
		if not next.players.has(next.current_player): return _reject(next, "The saved human player is missing.")
		# Earlier checkpoints predate castles; campaign maps are recognised by their chapter row.
		if raw.get("scenario") == null: next.scenario.campaign = ELCampaign.find_scenario(map.profile, map.id).has("number")
		var problem := ELFirstScenario.restore(next, raw.get("scenario"))
		if not problem.is_empty(): return _reject(next, problem)
		problem = ELGlobalSpells.restore(next)
		if not problem.is_empty(): return _reject(next, problem)
		problem = ELFirstAI.restore(next)
		if not problem.is_empty(): return _reject(next, problem)
		problem = ELDiplomacy.restore(next)
		if not problem.is_empty(): return _reject(next, problem)
		problem = ELAdditionalBuildings.restore_scry(next)
		if not problem.is_empty(): return _reject(next, problem)
	elif not ELSecondCampaign.restore(next, raw.get("scenario")):
		return _reject(next, "Invalid saved campaign progress.")
	elif not ELSecondAmbience.restore(next, raw.get("ambience")):
		return _reject(next, "Invalid saved weather and music.")
	else:
		# Saves from before the barrier model carry no barrier state.
		for item: Dictionary in next.objects.values(): ELSecondGates.initialize(item)
		var problem := ELFog.restore_eyes(next)
		if not problem.is_empty(): return _reject(next, problem)
	next._mob_ids.clear()
	for item: Dictionary in objects.values():
		if item.alive and item.type in ["hero", "monster"]: next._mob_ids.append(int(item.uid))
	var director := ELAdventureDirector.new()
	if not director.build(next): return _reject(next, director.error)
	var playback: Dictionary = raw.director
	if playback.has("guard_zones") and not director.interception.restore(playback.guard_zones, next, director.grid): return _reject(next, "Invalid saved guard areas.")
	director.strategy = ELStrategy.restore_turn(playback.get("strategy", {}), next)
	if director.strategy.has("error"): return _reject(next, director.strategy.error)
	if not playback.get("movement") is Dictionary or not playback.get("dialogue") is Dictionary or not playback.get("waiting") is bool or not _number(playback.get("wait_remaining"), -1, 86400) or not _number(playback.get("clock"), 0, 1): return _reject(next, "Invalid campaign playback state.")
	var movement: Dictionary = playback.movement.duplicate(true)
	if not movement.is_empty():
		if not ELLuaSave._integer(movement.get("id"), 0, 0x7fffffff) or not objects.has(int(movement.id)) or not movement.get("path") is Array or movement.path.size() < 2 or movement.path.size() > map.width * map.height or not ELLuaSave._integer(movement.get("index"), 0, movement.path.size() - 2) or not _number(movement.get("progress"), 0, 1) or not movement.get("queued") is bool or not ELLuaSave._integer(movement.get("use"), -1, 0x7fffffff): return _reject(next, "Invalid active movement.")
		var points: Array[Vector2i] = []
		for point: Variant in movement.path:
			if not point is Array or point.size() != 2 or not ELLuaSave._integer(point[0], 0, map.width - 1) or not ELLuaSave._integer(point[1], 0, map.height - 1): return _reject(next, "Invalid movement point.")
			points.append(Vector2i(int(point[0]), int(point[1])))
		movement.path = points
		movement.id = int(movement.id)
		movement.index = int(movement.index)
		movement.use = int(movement.use)
		if movement.has("strategic"):
			if not movement.strategic is bool: return _reject(next, "Invalid movement mode.")
			if movement.strategic and (director.strategy.get("phase") != "movement" or director.strategy.index < 1 or director.strategy.actors[director.strategy.index - 1] != movement.id or movement.queued or movement.use != -1): return _reject(next, "Missing strategic movement phase.")
	if map.profile.id == "el1" and not movement.is_empty() and not movement.get("strategic", false):
		# Legacy EL1 saves animated orders immediately. Keep the committed tile,
		# and resume their remaining destination as a pending strategic order.
		var actor := next.object(movement.id)
		var goal: Vector2i = movement.path[-1]
		actor.strategy_order = {"destination": [goal.x, goal.y], "use": movement.use}
		actor.orders.clear()
		movement = {}
	director.movement = movement
	director.dialogue = playback.dialogue.duplicate(true)
	if not director.dialogue.is_empty() and (not director.dialogue.get("question") is bool or not director.dialogue.get("text_id") is String or not ELLuaSave._integer(director.dialogue.get("actor"), -1, 0x7fffffff)): return _reject(next, "Invalid saved conversation.")
	if not director.dialogue.is_empty(): director.dialogue.actor = int(director.dialogue.actor)
	# Older saves have no pending script boxes or action waits.
	for box: Variant in playback.get("boxes", []):
		if not box is Dictionary or not box.get("text") is String or not box.get("question") is bool or not box.get("hook") is bool or not _number(box.get("speaker"), -1, 0x7fffffff): return _reject(next, "Invalid saved message box.")
		var kept := {"speaker": int(box.speaker), "text": box.text, "question": box.question, "hook": box.hook}
		# Box style (older saves have none: a TextDialog).
		if box.get("box") in ["text", "message"]: kept.box = box.box
		if box.get("speaker_box") is bool: kept.speaker_box = box.speaker_box
		if box.get("offset") is Array and box.offset.size() == 2 and box.offset.all(func(v: Variant) -> bool: return v is float or v is int): kept.offset = box.offset
		director.boxes.append(kept)
	if not _number(playback.get("action_wait", 0.0), 0, 86400): return _reject(next, "Invalid saved script wait.")
	director.action_wait = float(playback.get("action_wait", 0.0))
	if not ELLuaSave._integer(playback.get("player_round", 0), 0, 0x7fffffff) or not ELLuaSave._integer(playback.get("woken", -1), -1, 0x7fffffff): return _reject(next, "Invalid saved player round.")
	director.player_round = int(playback.get("player_round", 0))
	director._woken = int(playback.get("woken", -1))
	director._waiting = playback.waiting
	director.wait_remaining = float(playback.wait_remaining)
	director._clock = float(playback.clock)
	if (director._waiting or not director.dialogue.is_empty() or movement.get("queued", false)) and next.commands.is_empty(): return _reject(next, "The active command is missing.")
	var combat: Variant = raw.get("encounter", {})
	if not combat is Dictionary: return _reject(next, "Invalid saved encounter.")
	if not combat.is_empty():
		for key: String in ["hero", "opponent"]:
			if not ELLuaSave._integer(combat.get(key), 0, 0x7fffffff) or not objects.has(int(combat[key])) or not objects[int(combat[key])].alive: return _reject(next, "Missing encounter participant.")
		if combat.hero == combat.opponent or not combat.get("battle") is Dictionary: return _reject(next, "Invalid encounter participants.")
		var battle := ELDuel.new()
		if not battle.restore(map.profile, combat.battle): return _reject(next, battle.error)
		if not battle.setup.get("adventure", false): return _reject(next, "This duel is not a campaign encounter.")
		for side in 2:
			var actor: Dictionary = objects[int(combat.hero if side == 0 else combat.opponent)]
			if map.profile.id == "el1" and actor.cards != battle.heroes[side].deck: return _reject(next, "Encounter spellbook differs from its owner.")
			if not combat.battle.state.heroes[side].has("skills"):
				battle.heroes[side].skills = actor.skills.duplicate()
				if not combat.battle.state.heroes[side].has("spell_uses"):
					ELSpellCharges.migrate(map.profile, battle.heroes[side], battle.setup, side)
			if map.profile.id == "el1" and not combat.battle.state.has("charge_version"):
				battle.heroes[side].spell_uses = actor.rune_uses.duplicate()
		director.encounter = ELAdventureEncounter.new()
		director.encounter.state = next
		director.encounter.hero_id = int(combat.hero)
		director.encounter.opponent_id = int(combat.opponent)
		var ethereal: Variant = combat.get("ethereal", -1)
		if not ELLuaSave._integer(ethereal, -1, 0x7fffffff) or (int(ethereal) >= 0 and int(ethereal) not in [int(combat.hero), int(combat.opponent)]): return _reject(next, "Invalid ethereal encounter.")
		director.encounter.ethereal_defender = int(ethereal)
		director.encounter.battle = battle
	return {"state": next, "director": director, "camera": raw.camera.duplicate(true)}

const EXPERIENCE_LIMIT := 1000000000

func _restore_progression(profile: ELProfile, hero: Dictionary) -> bool:
	# Authored bosses can exceed the last threshold (EL2 chapter 13's dragon has 2,000,000).
	if not ELLuaSave._integer(hero.level, 1, ELHeroProgression.MAX_LEVEL) or not ELLuaSave._integer(hero.experience, 0, EXPERIENCE_LIMIT): return false
	if not hero.has("skills"): hero.skills = {}
	if not ELHeroSkills.valid_ranks(profile, hero.skills): return false
	for skill: Variant in hero.skills:
		hero.skills[skill] = int(hero.skills[skill])
	if not hero.has("level_history"):
		var total := int(hero.experience)
		ELHeroProgression.initialize(profile, hero)
		hero.experience = maxi(total, hero.experience)
		hero.level = ELHeroProgression.level_for(profile, hero.experience)
		hero.skill_points = maxi(0, hero.level - hero.level_history)
		hero.level_history = hero.level
		ELHeroProgression.recalculate_health(hero)
		ELHeroSkills.prepare(profile, hero)
		return ELHeroSkills.restore(profile, hero)
	for key: String in ["level_history", "skill_points", "health_base", "health_growth"]:
		var low := -100000 if key == "health_base" else 0
		var high := 100000 if key in ["health_base", "health_growth"] else ELHeroProgression.MAX_LEVEL
		if not ELLuaSave._integer(hero.get(key), low, high): return false
		hero[key] = int(hero[key])
	if hero.level_history < hero.level or hero.skill_points >= ELHeroProgression.MAX_LEVEL or not _number(hero.get("experience_penalty"), 0, EXPERIENCE_LIMIT): return false
	hero.experience_penalty = float(hero.experience_penalty)
	return ELHeroSkills.restore(profile, hero)

func _reject(state: ELAdventureSession, message: String) -> Dictionary:
	state.close()
	_fail(message)
	return {}

func _map_hash(map: ELAdventureMap) -> String:
	return FileAccess.get_sha256(map.profile.file("Maps/" + map.id + ".map"))

func _plain(value: Variant, depth: int) -> bool:
	if depth > 32: return false
	if value == null or value is bool: return true
	if value is String: return value.length() <= 1024 * 1024
	if value is int or value is float: return is_finite(float(value))
	if value is Array or value is Dictionary:
		if value.size() > 100000: return false
		for child: Variant in (value.values() if value is Dictionary else value):
			if not _plain(child, depth + 1): return false
		return true
	return false

func _number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= low and value <= high

func _fail(message: String) -> bool:
	error = message
	return false
