extends SceneTree
## Headless check that the second game's campaign lords change their look with
## their level, as in the original (ELHeroLooks):
## - level steps: shape list entry 0 below level 4, 1 from 4, 2 from 8, 3 from
##   12, never past the last listed shape;
## - each lord's first shape (Green/Black/Blue/Red MainHero-1: three shapes,
##   DiamandaMainHero-1: four) wears its later shapes, each a different figure
##   or skin and portrait in the installed Shapes table; ordinary heroes
##   (RedMale-1, GreenMale-4), a lord's later shape set on its own and the
##   first game keep the shape they were given;
## - on the Green campaign's first map the lord (level 1) shows his first
##   look on the map and in battle; experience that lifts him to level 4 and
##   then 8 changes his map figure (a shape_changed event, a new figure in the
##   map scene), his portrait and his battle figure; a level lost again to a
##   colourless zone keeps the look;
## - the second chapter's lord starts at level 4 and so starts in his second
##   look.
##
##   godot --headless --path game --script ../tools/hero_looks_check.gd
##
## It needs the second game's files (user://profiles.json); without them it is
## skipped. Saves the map writes are put back as they were.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_steps()
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
	else:
		var profile := ELProfile.new()
		if not profile.mount("el2", str(paths.el2)):
			print("SKIP: the second game's files could not be mounted")
		else:
			_tables(profile)
			if paths.has("el1"):
				var first := ELProfile.new()
				if first.mount("el1", str(paths.el1)):
					check(ELHeroLooks.shape_at(first, "RedMainHero-1", 12) == "RedMainHero-1", "the first game keeps the shape it was given")
			await _first_map(profile)
			_second_map(profile)
			if profile.metal_masks != null: profile.metal_masks.stop()
	print("HERO LOOKS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _steps() -> void:
	var expected := {1: 0, 3: 0, 4: 1, 7: 1, 8: 2, 11: 2, 12: 3, 20: 3}
	var got := {}
	for level: int in expected: got[level] = ELHeroLooks.step(level)
	check(got == expected, "level steps start at levels 4, 8 and 12 (%s)" % got)
	check(ELHeroLooks.shapes("RedMainHero-1") == ["RedMainHero-1", "RedMainHero-2", "RedMainHero-3"], "a lord's list holds its three shapes")
	check(ELHeroLooks.shapes("DiamandaMainHero-1").size() == 4 and ELHeroLooks.shapes("DiamandaMainHero-1")[3] == "DiamandaMainHero-4", "Diamanda's list holds four shapes")
	check(ELHeroLooks.shapes("RedMale-1") == ["RedMale-1"], "an ordinary hero's list holds its own shape only")

func _tables(profile: ELProfile) -> void:
	var shapes := profile.table("Shapes")
	var cases := {
		"GreenMainHero-1": {1: "GreenMainHero-1", 3: "GreenMainHero-1", 4: "GreenMainHero-2", 8: "GreenMainHero-3", 12: "GreenMainHero-3", 20: "GreenMainHero-3"},
		"RedMainHero-1": {1: "RedMainHero-1", 5: "RedMainHero-2", 9: "RedMainHero-3", 15: "RedMainHero-3"},
		"BlackMainHero-1": {2: "BlackMainHero-1", 4: "BlackMainHero-2", 8: "BlackMainHero-3"},
		"BlueMainHero-1": {3: "BlueMainHero-1", 7: "BlueMainHero-2", 11: "BlueMainHero-3", 12: "BlueMainHero-3"},
		"DiamandaMainHero-1": {1: "DiamandaMainHero-1", 4: "DiamandaMainHero-2", 8: "DiamandaMainHero-3", 12: "DiamandaMainHero-4", 20: "DiamandaMainHero-4"},
		"RedMale-1": {1: "RedMale-1", 8: "RedMale-1", 12: "RedMale-1"},
		"GreenMale-4": {1: "GreenMale-4", 12: "GreenMale-4"},
		"RedMainHero-2": {1: "RedMainHero-2", 12: "RedMainHero-2"},
	}
	for shape: String in cases:
		for level: int in cases[shape]:
			var worn := ELHeroLooks.shape_at(profile, shape, level)
			check(worn == cases[shape][level], "%s at level %d wears %s (got %s)" % [shape, level, cases[shape][level], worn])
	for lord: String in ELHeroLooks.LORDS:
		var list := ELHeroLooks.shapes(lord)
		var looks := {}
		for shape: String in list:
			check(shapes.has(shape), "Shapes has %s" % shape)
			var row: Dictionary = shapes.get(shape, {})
			looks["%s/%s/%s" % [row.get("Model", ""), row.get("Texture", ""), row.get("Face", "")]] = true
			for column: String in ["Texture", "AdvTex1"]:
				if not str(row.get(column, "")).is_empty():
					check(profile.texture("Heroes/" + str(row[column]).replace("\\", "/")) != null, "%s %s skin %s is stored" % [shape, column, row[column]])
		check(looks.size() == list.size(), "%s: each level step is a different figure, skin and portrait (%s)" % [lord, looks.keys()])

## The Green campaign's first chapter: the lord levels up on the map.
func _first_map(profile: ELProfile) -> void:
	var row := _chapter(profile, "e2mission11")
	if row.is_empty():
		check(false, "the Green campaign's first chapter is found")
		return
	var saves := _backup(ELSaveSlots.folder("el2"))
	var settings := ELSettings.new()
	settings.use_edition("el2")
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	check(built, "e2mission11 builds: %s" % view.error)
	if built:
		await frames(4)
		var state := view.state
		var lord := _hero_with(state, "GreenMainHero-1")
		check(not lord.is_empty() and int(lord.level) == 1, "the lord starts at level 1 as GreenMainHero-1")
		if not lord.is_empty():
			var uid := int(lord.uid)
			# The view's own art cache, which the map scene and panels share.
			var art: ELAdventureArt = view._art
			var shapes := profile.table("Shapes")
			var first := art.resolve(lord)
			check(first.get("model") == shapes["GreenMainHero-1"].AdvMod and int(first.row.Face) == int(shapes["GreenMainHero-1"].Face), "level 1: the map figure and portrait are GreenMainHero-1's (%s)" % first.get("model"))
			check(_battle_shape(state, uid) == "GreenMainHero-1", "level 1: the battle shows GreenMainHero-1")
			var key_before := _figure_key(view, uid)
			check(not key_before.is_empty(), "the lord has a figure in the map scene (%s)" % key_before)
			var events: Array = []
			var listen := func(data: Dictionary) -> void: if data.get("kind") == "shape_changed" and int(data.get("id", -1)) == uid: events.append(data)
			state.event.connect(listen)
			state.add_experience(uid, ELHeroProgression.threshold(profile, 3) - int(lord.experience))
			check(int(lord.level) == 3 and events.is_empty(), "level 3: no new look yet")
			state.add_experience(uid, ELHeroProgression.threshold(profile, 4) - int(lord.experience))
			await frames(2)
			var second := art.resolve(lord)
			check(int(lord.level) == 4 and events.size() == 1, "level 4: the look changes (shape_changed, level %d)" % int(lord.level))
			check(second.get("model") == shapes["GreenMainHero-2"].AdvMod and second.get("texture") == "Heroes/" + str(shapes["GreenMainHero-2"].AdvTex1) and int(second.row.Face) == int(shapes["GreenMainHero-2"].Face), "level 4: the map figure, skin and portrait are GreenMainHero-2's (%s %s)" % [second.get("model"), second.get("texture")])
			var key_four := _figure_key(view, uid)
			check(key_four != key_before and key_four.begins_with(str(shapes["GreenMainHero-2"].AdvMod)), "level 4: the map scene rebuilt the lord's figure (%s)" % key_four)
			check(int(view.second_hud._art.resolve(lord).get("row", {}).get("Face", -1)) == int(shapes["GreenMainHero-2"].Face), "level 4: the hero screen and roster portrait follow")
			check(_battle_shape(state, uid) == "GreenMainHero-2", "level 4: the battle shows GreenMainHero-2")
			state.add_experience(uid, ELHeroProgression.threshold(profile, 8) - int(lord.experience))
			await frames(2)
			check(int(lord.level) == 8 and events.size() == 2 and _figure_key(view, uid).begins_with(str(shapes["GreenMainHero-3"].AdvMod)), "level 8: the third look (%s)" % _figure_key(view, uid))
			check(_battle_shape(state, uid) == "GreenMainHero-3", "level 8: the battle shows GreenMainHero-3")
			ELColorless.set_lost(profile, lord, float(lord.experience) - ELHeroProgression.threshold(profile, 6))
			check(int(lord.level) == 6 and ELHeroLooks.worn(profile, lord) == "GreenMainHero-3", "a level lost to a colourless zone keeps the look (level %d)" % int(lord.level))
			state.event.disconnect(listen)
	view.queue_free()
	await frames(2)
	_restore(ELSaveSlots.folder("el2"), saves)

## The second chapter's lord is authored at level 4 with his first shape.
func _second_map(profile: ELProfile) -> void:
	var row := _chapter(profile, "e2mission12_52")
	var map := ELAdventureMap.new()
	if row.is_empty() or not map.load_map(profile, "e2mission12_52"):
		check(false, "e2mission12_52 loads: %s" % map.error)
		return
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, str(row.get("script", "")), int(str(row.get("player", "1"))), true):
		check(false, "e2mission12_52 starts: %s" % state.error)
		return
	var lord := _hero_with(state, "GreenMainHero-1")
	var shapes := profile.table("Shapes")
	check(not lord.is_empty() and int(lord.level) == 4 and ELAdventureArt.new(map).resolve(lord).get("model") == shapes["GreenMainHero-2"].AdvMod, "a lord placed at level 4 starts in his second look")
	state.close()

func _hero_with(state: ELAdventureSession, shape: String) -> Dictionary:
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and str(item.get("shape", "")) == shape: return item
	return {}

func _figure_key(view: ELAdventureView, uid: int) -> String:
	var models: Dictionary = view.world.object_models
	return str(models[uid].get_meta("art_key", "")) if models.has(uid) else ""

## The shape the battle against any other map character dresses the hero in.
func _battle_shape(state: ELAdventureSession, uid: int) -> String:
	for item: Dictionary in state.objects.values():
		if int(item.uid) == uid or item.get("type") not in ["hero", "monster"] or not item.get("alive", false): continue
		var encounter := ELAdventureEncounter.new()
		if not encounter.prepare(state, uid, int(item.uid)) or encounter.battle == null: continue
		for hero: Dictionary in encounter.battle.heroes:
			if str(hero.get("shape", "")).begins_with("GreenMainHero"): return str(hero.shape)
		return "(no lord in battle)"
	return "(no battle)"

func _chapter(profile: ELProfile, map_id: String) -> Dictionary:
	for campaign_id: String in ["Green", "Red", "Blue", "Black"]:
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, campaign_id): continue
		for scenario: Dictionary in campaign.scenarios:
			if str(scenario.file_name).to_lower() == map_id:
				var row := scenario.duplicate()
				row.campaign = campaign_id
				var progress := ELSecondCampaign.for_chapter(profile, campaign_id, row, campaign.scenarios.find(scenario) + 1)
				if not progress.is_empty(): row[ELSecondCampaign.KEY] = progress
				return row
	return {}

func _backup(folder: String) -> Dictionary:
	var kept := {}
	if not DirAccess.dir_exists_absolute(folder): return kept
	for file in DirAccess.get_files_at(folder): kept[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return kept

func _restore(folder: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if kept.has(file):
			if FileAccess.get_file_as_bytes(folder.path_join(file)) != kept[file]:
				var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
				out.store_buffer(kept[file])
		else: DirAccess.remove_absolute(folder.path_join(file))
