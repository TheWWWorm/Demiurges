extends SceneTree
## Headless check of stability fixes outside the duel and world-map AI:
## - the figures' metal-mask warm-up publishes CombatCreatures through the
##   profile, so a table read after the warm-up is the normalised one (the
##   second game's 1.03 values) and equals a table read directly;
## - first game, chapter 13: the capture watch on Diamanda's duel health
##   survives an encode -> JSON -> decode of a battle checkpoint (5 health
##   wins, 0 loses);
## - a network strategic guest with free movement on: clicking the same
##   destination twice only previews the route (no movement starts), and the
##   guest can still plan and end the turn;
## - the second game's between-chapter autosave reads back what its writer
##   accepts (one size limit), an oversized write keeps the previous file, and
##   a notebook past its entry limit or with huge numbers still decodes;
## - the second game's spell shop runs Hook_OnSpellShopSpellBuyed for every
##   trade that takes a spell from the shop (paid in cash, paid by sales in
##   full or more, free) and not for a pure sale;
## - a movie cache opened without the source size reads the same metadata as
##   with it;
## - combat effect caches are kept per content generation: a replaced
##   profile's entries are not served to its successor, and its late warm-up
##   results are not kept.
##
##   godot --headless --path game --script ../tools/stability_check.gd
##
## The chapter 13, strategic and spell-shop parts need the games' files
## (user://profiles.json); without them they are skipped.

const FOLDER := "user://stability_check"

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var folders := {}
	for edition: String in ["el1", "el2"]:
		if paths is Dictionary and paths.has(edition): folders[edition] = str(paths[edition])
		else: print("SKIP: no %s files configured (user://profiles.json)" % edition)
	_metal_mask_tables(folders)
	if folders.has("el1"): _diamanda_watch(_mount("el1", folders.el1))
	if folders.has("el1"): await _strategic_guest(_mount("el1", folders.el1))
	_save_limits()
	if folders.has("el2"): _spell_shop_hook(_mount("el2", folders.el2))
	_movie_cache()
	_effect_generations()
	for file: String in DirAccess.get_files_at(FOLDER): DirAccess.remove_absolute(FOLDER.path_join(file))
	DirAccess.remove_absolute(FOLDER)
	print("%d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _mount(edition: String, folder: String) -> ELProfile:
	var profile := ELProfile.new()
	if not profile.mount(edition, folder):
		print("SKIP: %s files could not be mounted" % edition)
		return null
	return profile

# --- 1. metal masks and the card tables -------------------------------------

func _warm_rows(profile: ELProfile, rows: Dictionary) -> void:
	var masks := ELMetalMasks.new(profile.id)
	masks._list({"spec": ["CombatCreatures", "Creatures/", "SecTexture"], "profile": profile, "task": -1, "rows": rows})

func _metal_mask_tables(folders: Dictionary) -> void:
	# Release 1.01 rows as a worker thread parses them.
	var raw := func() -> Dictionary: return {"OGKN": {"Power": 8, "Toughness": 6}, "KBGD": {"Flags": "Flying"}}
	var warmed := ELProfile.new()
	warmed.id = "el2"
	warmed.second_release = ELPatch103.RELEASE_OLD
	_warm_rows(warmed, raw.call())
	var direct := ELProfile.new()
	direct.id = "el2"
	direct.second_release = ELPatch103.RELEASE_OLD
	direct.adopt_table("CombatCreatures", raw.call())
	var row: Dictionary = warmed.tables.get("CombatCreatures", {}).get("OGKN", {})
	check(int(row.get("Power", 0)) == 7 and int(row.get("Toughness", 0)) == 8, "metal masks: a warm-up's CombatCreatures has release 1.03's Ogre Knight 7/8 (%s)" % row)
	check(ELCatalog.flags(warmed.tables.get("CombatCreatures", {}).get("KBGD", {})).has("Disenchant"), "metal masks: a warm-up's CombatCreatures keeps release 1.03's Disenchant")
	check(JSON.stringify(warmed.tables.CombatCreatures, "", true) == JSON.stringify(direct.tables.CombatCreatures, "", true), "metal masks: warm-up first and direct reading give the same table")
	if not folders.has("el2"): return
	# The installed data: the warm-up's parse and a direct read agree.
	var first := _mount("el2", folders.el2)
	var second := _mount("el2", folders.el2)
	if first == null or second == null: return
	first.tables.erase("CombatCreatures")
	_warm_rows(first, ELRegistry.parse(first.read("regs", "CombatCreatures.reg")))
	second.tables.erase("CombatCreatures")
	var read := second.table("CombatCreatures")
	check(not read.is_empty() and JSON.stringify(first.tables.CombatCreatures, "", true) == JSON.stringify(read, "", true),
		"metal masks: on the installed release %s, warm-up first and direct reading give the same CombatCreatures" % ("1.01" if second.release_is_old() else "1.03"))

# --- 2. chapter 13 capture watch --------------------------------------------

func _diamanda_watch(profile: ELProfile) -> void:
	if profile == null: return
	var map := ELAdventureMap.new()
	if not map.load_map(profile, "mission13"):
		print("SKIP: chapter 13 map could not be loaded")
		return
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, true):
		check(false, "chapter 13 starts as a campaign chapter: " + state.error)
		return
	var director := ELAdventureDirector.new()
	if not director.build(state):
		check(false, "chapter 13 builds: " + director.error)
		state.close()
		return
	var diamanda := {}
	var hero := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") != "hero" or not item.get("alive", false): continue
		if item.get("name") == "Diamanda" and int(item.owner) != state.current_player: diamanda = item
		elif hero.is_empty() and int(item.owner) == state.current_player: hero = item
	if diamanda.is_empty() or hero.is_empty():
		print("SKIP: chapter 13 has no Diamanda or no hero of the player (%s, %s)" % [not diamanda.is_empty(), not hero.is_empty()])
		state.close()
		return
	director._begin_encounter(hero, diamanda)
	if director.encounter == null or director.encounter.battle == null:
		check(false, "chapter 13: a battle with Diamanda begins (%s)" % director.notice)
		state.close()
		return
	var side := director.encounter.watch_side
	check(side >= 0, "chapter 13: the battle watches Diamanda's health")
	var codec := ELAdventureSave.new()
	var document := codec.encode(director, {})
	check(not document.is_empty(), "chapter 13: the battle checkpoint encodes " + codec.error)
	var text := JSON.stringify(document, "", true, true)
	for case: Array in [[5, "win"], [0, "lose"]]:
		var restored := codec.decode(JSON.parse_string(text), {"el1": profile})
		if restored.is_empty():
			check(false, "chapter 13: the checkpoint decodes: " + codec.error)
			continue
		var next: ELAdventureDirector = restored.director
		check(next.encounter != null and next.encounter.watch_side == side, "chapter 13: the restored battle still watches Diamanda (side %d)" % (next.encounter.watch_side if next.encounter != null else -2))
		if next.encounter != null:
			next.encounter.battle.heroes[side].health = case[0]
			var outcome := next.watch_encounter()
			check(outcome == case[1] and next.state.outcome == case[1], "chapter 13: after a reload, Diamanda at %d health %s the chapter (%s)" % [case[0], "wins" if case[1] == "win" else "loses", outcome])
		restored.state.close()
	state.close()

# --- 3. network strategic guest with free movement --------------------------

func _wait(cond: Callable, seconds := 20.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while not cond.call():
		if Time.get_ticks_msec() > until: return false
		await process_frame
	return true

func _strategic_guest(profile: ELProfile) -> void:
	if profile == null: return
	var maps := ELStrategicLobby.catalogue(profile)
	if maps.is_empty():
		print("SKIP: no strategic map")
		return
	var entry: Dictionary = maps[0]
	var host := ELStrategicSession.new()
	host.profile = profile
	var guest := ELStrategicSession.new()
	guest.profile = profile
	root.add_child(host)
	root.add_child(guest)
	var worlds := {}
	host.world_ready.connect(func(_restored: Dictionary): worlds.host = true; host.view_opened())
	guest.world_ready.connect(func(_restored: Dictionary): worlds.guest = true; guest.view_opened())
	var players := Vector2i(entry.seats[0].id, entry.seats[1].id)
	var port := 27391
	check(host.link.host(profile, entry.id, port, players, 1, 4242) == OK, "strategic guest: the host opens a port")
	await _wait(func(): return host.link._peer != null and host.link._peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 10.0)
	check(guest.link.join(profile, "127.0.0.1", port) == OK, "strategic guest: the guest connects")
	# The map starts without heroes: the host places one for the guest next
	# to its castle and sends the world again.
	var placed := await _wait(func(): return worlds.has("host") and host.director != null, 20.0)
	if placed: placed = _place_guest_hero(host.director, players.y)
	check(placed, "strategic guest: the host places a hero for the guest")
	if placed: host._send_world = true
	var ready := placed and await _wait(func(): return worlds.has("guest") and guest.can_plan() and guest.director.state.objects.values().any(func(o): return o.get("type") == "hero" and int(o.owner) == players.y), 40.0)
	check(ready, "strategic guest: the guest gets its map and can plan")
	if ready:
		var director := guest.director
		director.free_movement = true
		var hero := {}
		for item: Dictionary in director.state.objects.values():
			if hero.is_empty() and item.get("type") == "hero" and item.get("alive", false) and int(item.owner) == guest.link.local_player: hero = item
		var destination := Vector2i(-1, -1)
		if not hero.is_empty():
			var at := Vector2i(int(hero.x), int(hero.y))
			for step: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, 0), Vector2i(0, 1)]:
				if destination.x >= 0: break
				var cell := at + step
				if director.grid.passability(cell) >= 0 and guest.move(int(hero.uid), cell, -1): destination = cell
		check(destination.x >= 0, "strategic guest: a route is planned (%s)" % ("no hero of player %d: %s" % [guest.link.local_player, director.state.objects.values().filter(func(o): return o.get("type") == "hero").map(func(o): return [o.get("owner"), o.get("alive"), o.get("name")])] if hero.is_empty() else director.notice))
		if destination.x >= 0:
			check(not ELStrategy.free_mode(director), "strategic guest: the guest's director never takes free movement")
			guest.move(int(hero.uid), destination, -1)
			check(director.strategy.is_empty() and director.movement.is_empty(), "strategic guest: the same destination again starts no movement on the guest")
			check(guest.can_plan(), "strategic guest: the guest can still plan")
			check(guest.end_turn(), "strategic guest: the guest can end the turn")
	guest.queue_free()
	host.queue_free()
	await process_frame
	await process_frame

func _place_guest_hero(director: ELAdventureDirector, player: int) -> bool:
	var state := director.state
	var castle := ELFirstScenario.castle_object(state, player)
	if castle.is_empty() or not state.players.has(player): return false
	var colour := str(state.players[player].get("color", ""))
	var rows: Dictionary = state.map.profile.table("HeroTemplates")
	var template := ""
	for key: String in rows:
		if template.is_empty() and str(rows[key].get("Quest", "")) != "Yes" and int(rows[key].get("Level", 1)) == 1 and str(rows[key].get("Color", "")) == colour: template = key
	if template.is_empty(): return false
	var at := Vector2i(int(castle.x), int(castle.y))
	for radius in range(2, 7):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var cell := at + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) != radius or director.grid.passability(cell) < 0: continue
				var id := ELAdditionalBuildings.spawn_hero(state, template, player, cell.x, cell.y)
				var hero := state.object(id)
				hero.ap = int(hero.get("strategy_capacity", 10))
				director.grid.update_actor(hero)
				return true
	return false

# --- 4. save size policy and notebook bounds --------------------------------

func _campaign(note_bytes: int) -> Dictionary:
	return {"version": ELSecondCampaign.VERSION, "counter": 0, "index": 0, "row": 0, "difficulty": 0, "possible": ["Green", "Red"], "current": "Green", "prev": "",
		"intermission": {"notebook": [{"id": 0, "kind": "phrase", "text": "x".repeat(note_bytes)}]}, "finished": false}

func _save_limits() -> void:
	var path := FOLDER.path_join("campaign.json")
	# Larger than the old reader's 4 MiB, within the writer's limit.
	var large := _campaign(6 * 1024 * 1024)
	check(ELSecondCampaign.write(path, large), "save limits: a 6 MiB between-chapter autosave is written")
	var back := ELSecondCampaign.read(path)
	check(not back.is_empty() and str(back.intermission.notebook[0].text).length() == 6 * 1024 * 1024, "save limits: the autosave its writer accepted reads back")
	var huge := _campaign(ELAdventureSave.MAX_BYTES + 1024)
	check(not ELSecondCampaign.write(path, huge), "save limits: an autosave over the limit is refused")
	back = ELSecondCampaign.read(path)
	check(not back.is_empty() and str(back.intermission.notebook[0].text).length() == 6 * 1024 * 1024, "save limits: the refused write keeps the previous readable autosave")
	# The notebook stays within what decode accepts.
	var state := ELAdventureSession.new()
	state.map = ELAdventureMap.new()
	state.map.profile = ELProfile.new()
	state.map.profile.id = "el2"
	state.map.id = "check"
	for i in ELSecondNotebook.MAX_ENTRIES + 3: ELSecondNotebook.add_phrase(state, "line %d" % i, null, false)
	var winner := {"name": "Hero", "health": 20000000000, "level": 9}
	var loser := {"name": "Boss", "health": -5, "level": 30}
	ELSecondNotebook.add_battle(state, winner, loser, {"health": 3, "level": 2}, 2000000000)
	var decoded: Variant = ELSecondNotebook.decode(JSON.parse_string(JSON.stringify(ELSecondNotebook.encode(state))))
	check(decoded is Array and decoded.size() == ELSecondNotebook.MAX_ENTRIES, "save limits: a notebook past its entry limit keeps the newest entries and decodes (%s)" % (decoded.size() if decoded is Array else "refused"))
	if decoded is Array: check(decoded[-1].kind == "battle" and int(decoded[-1].experience) == ELSecondNotebook.MAX_NUMBER, "save limits: a battle entry's huge numbers are kept within what decode accepts")

# --- 5. spell shop purchase hook --------------------------------------------

class HookSession extends ELAdventureSession:
	var hooks: Array[String] = []
	func hook(name: String, _arguments: Array = []) -> bool:
		hooks.append(name)
		return true

class PricedShop extends ELSpellShop:
	var prices := {}
	var kind := ""
	func quote(entry: Dictionary) -> Dictionary:
		var result := ELResources.empty(state.map.profile.id)
		var price := int(prices.get(entry.card, 0))
		result[kind] = price / 2 if entry.origin == "hero" else price
		return result

func _spell_shop_hook(profile: ELProfile) -> void:
	if profile == null: return
	var codes: Array[String] = []
	for code: String in profile.table("CombatSpells"):
		if ELSpellInventory.is_spell(profile, code) and codes.size() < 20: codes.append(code)
	if codes.size() < 20:
		print("SKIP: spell shop: too few spells")
		return
	var kind: String = ELResources.empty("el2").keys()[0]
	# card -> price: c0 sells for 10, c1 for 20; s0 costs 10, s1 nothing.
	var prices := {codes[0]: 20, codes[1]: 40, codes[16]: 10, codes[17]: 0, codes[18]: 30}
	for case: Array in [
			["cash purchase", [["shop", codes[16], "reserve"]], true],
			["purchase paid in full by a sale", [["book", codes[0], "shop"], ["shop", codes[16], "book"]], true],
			["purchase outweighed by a sale", [["book", codes[1], "shop"], ["shop", codes[16], "book"]], true],
			["free purchase", [["shop", codes[17], "reserve"]], true],
			["pure sale", [["reserve", codes[18], "shop"]], false]]:
		var state := HookSession.new()
		state.map = ELAdventureMap.new()
		state.map.profile = profile
		state.current_player = 1
		state.players = {1: {"resources": {kind: 100}}}
		var hero := {"uid": 1, "type": "hero", "alive": true, "owner": 1, "cards": codes.slice(0, 16), "spell_stock": {codes[18]: 1}}
		state.objects[1] = hero
		state.objects[2] = {"uid": 2, "type": "building", "group": "laboratories", "alive": true, "visible": true, "enabled": true, "shop_stock": [codes[16], codes[17]]}
		var trade := PricedShop.new()
		trade.prices = prices
		trade.kind = kind
		if not trade.open(state, 1, 2):
			check(false, "spell shop: %s opens (%s)" % [case[0], trade.error])
			continue
		for step: Array in case[1]:
			var index := -1
			for i in trade.zones[step[0]].size():
				if index < 0 and trade.zones[step[0]][i].card == step[1]: index = i
			trade.move(step[0], index, step[2])
		var committed := trade.commit()
		var hooked := state.hooks.has("Hook_OnSpellShopSpellBuyed")
		check(committed and hooked == case[2], "spell shop: %s (bill %d) %s the purchase hook%s" % [case[0], int(trade.bill()[kind]), "runs" if case[2] else "skips", "" if committed else " (" + trade.error + ")"])

# --- 6. movie cache metadata ------------------------------------------------

func _movie_cache() -> void:
	var path := ProjectSettings.globalize_path(FOLDER.path_join("movie.elv"))
	var writer := ELMovieCache.new()
	writer.width = 320
	writer.height = 240
	writer.frame_count = 2
	writer.fps_num = 15
	writer.fps_den = 1
	writer.audio_rate = 22050
	writer.audio_channels = 1
	writer.source_size = 123456
	var f := FileAccess.open(path, FileAccess.WRITE)
	writer._write_header(f, false, 0, 0, 0)
	var offsets := [f.get_position()]
	for frame: String in ["AAAA", "BBBBBB"]:
		f.store_buffer(frame.to_ascii_buffer())
		offsets.append(f.get_position())
	var audio_off := f.get_position()
	f.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]))
	var index_off := f.get_position()
	for offset: int in offsets: f.store_64(offset)
	writer._write_header(f, true, audio_off, 8, index_off)
	f.close()
	var plain := ELMovieCache.open_cache(path)
	var sized := ELMovieCache.open_cache(path, 123456)
	var fields := ["width", "height", "frames", "fps_num", "fps_den", "audio_rate", "audio_channels", "offsets", "pcm"]
	var same := not plain.is_empty() and not sized.is_empty()
	for key: String in fields: same = same and plain.get(key) == sized.get(key)
	check(same, "movie cache: opened without the source size, the cache reads the same metadata as with it")
	check(not plain.is_empty() and Array(plain.offsets) == offsets and plain.pcm.size() == 8, "movie cache: the frame index and sound are read where they were written")
	check(ELMovieCache.open_cache(path, 654321).is_empty(), "movie cache: a cache of a source of another size is refused")
	plain.clear()
	sized.clear()

# --- 7. combat effect caches per content generation -------------------------

func _effect_generations() -> void:
	var old := ELProfile.new()
	old.id = "el1"
	var baked := {"file": null, "frames": {}, "bytes": 16}
	ELCombatEffects.store_file(old, "Effects/check.pfx", baked)
	check(not ELCombatEffects.cached_file(old, "Effects/check.pfx").is_empty(), "effects: a profile's particle file is cached")
	var replaced := ELProfile.new()
	replaced.id = "el1"
	check(replaced.generation > old.generation, "effects: a new profile is a newer content generation")
	check(ELCombatEffects.cached_file(replaced, "Effects/check.pfx").is_empty(), "effects: replaced content's particle file is not served to the new profile")
	ELCombatEffects.store_file(old, "Effects/late.pfx", {"file": null, "frames": {}, "bytes": 16})
	check(ELCombatEffects.cached_file(replaced, "Effects/late.pfx").is_empty() and ELCombatEffects.cached_file(old, "Effects/late.pfx").is_empty(),
		"effects: a late warm-up of replaced content keeps nothing in the caches")
	ELCombatEffects.store_file(replaced, "Effects/late.pfx", {"file": null, "frames": {}, "bytes": 16})
	check(not ELCombatEffects.cached_file(replaced, "Effects/late.pfx").is_empty(), "effects: the new profile's own files are cached")
	check(ELCombatEffects.cached_files(replaced) == 1, "effects: the new generation holds only its own entries")
