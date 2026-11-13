extends SceneTree
## Headless check of player-reported battle, deck and map details:
## - a hand card whose cost a battle changed shows the printed cost and the
##   change ("Цена: 1 + 2 ед. эфира"), an unchanged one only its cost;
## - the second game's deck editor lists the available spells in the
##   original order: colour (own race, then neutral), rarity, class, then
##   the code read from its last letter back;
## - the first game reads the presets the original saved as Duel\*.prs:
##   from the game's own Duel folder (left untouched) and from the user
##   folder, and keeps presets that break today's spending or colour rules,
##   as the original loader does, while the second game still refuses them;
## - a first-game neutral creature fighting as the opponent hero shows its
##   own Monsters `Icon` photo on the battle panel, and its battle tooltip is
##   the name, that photo and the Level and Health lines only;
## - the first game's pre-battle map panel uses the original text sizes
##   (BattleNumText and the names 20 px cells, the stat lines 15 px cells).
##
##   godot --headless --path game --script ../tools/player_reports_check.gd
##
## Windowed with `-- --shots=<folder>` it saves the first game's battle with
## the monster's tooltip held open and the pre-battle panel.
##
## Needs the original games' files (user://profiles.json, as set up by the
## game); without them a game is skipped. Settings are never written; the
## preset files the check writes and the mission-start autosave are removed
## or put back.

var failures: Array[String] = []
var shots := ""

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440, 900)
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var profiles := {}
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		var profile := ELProfile.new()
		if profile.mount(edition, str(paths[edition])): profiles[edition] = profile
		else: print("SKIP: %s files could not be mounted" % edition)
	for edition: String in profiles: _cost_lines(profiles[edition])
	if profiles.has("el2"):
		_classic_order(profiles.el2)
		_strict_second_game(profiles.el2)
	if profiles.has("el1"):
		_original_presets(profiles.el1)
		await _monster_battle()
		await _precombat(profiles.el1)
	print("PLAYER REPORTS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

# --- Hand card cost -------------------------------------------------------------

func _cost_lines(profile: ELProfile) -> void:
	var cost := profile.text("T_COST")
	var mana := profile.text("T_MANA")
	var plain := ELCombatTooltip.cost_line(profile, 1)
	check(plain == "%s 1 %s" % [cost, mana], "%s: a card shows its cost (%s)" % [profile.id, plain])
	check(ELCombatTooltip.cost_line(profile, 4, 4) == plain.replace(" 1 ", " 4 "), "%s: an unchanged battle cost shows the cost alone" % profile.id)
	var raised := ELCombatTooltip.cost_line(profile, 1, 3)
	check(raised == "%s 1 + 2 %s" % [cost, mana], "%s: a raised cost shows the printed cost + the surcharge (%s)" % [profile.id, raised])
	var lowered := ELCombatTooltip.cost_line(profile, 5, 3)
	check(lowered == "%s 5 - 2 %s" % [cost, mana], "%s: a lowered cost shows the printed cost - the discount (%s)" % [profile.id, lowered])
	# The whole hand tooltip carries the split line.
	var card := ""
	for code: String in profile.table("CombatSpells"):
		if str(profile.table("CombatSpells")[code].get("Class", "")) == "Enchantment" and int(profile.table("CombatSpells")[code].get("Cost", 0)) == 1:
			card = code
			break
	if not card.is_empty():
		var text := ELCombatTooltip.spell_text(profile, card, 3)
		check(text.get_slice("\n", 1) == raised, "%s: the hand tooltip of %s at 3 ether reads \"%s\"" % [profile.id, card, text.get_slice("\n", 1)])

# --- Second game: available spells order ----------------------------------------

func _classic_order(profile: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var cards: Array[String] = []
		for colour: String in [faction, ELDuelCosts.EL2_NEUTRAL]:
			cards.append_array(ELCatalog.available_cards(profile, colour))
		cards.assign(cards.filter(func(card: String): return ELDuelCosts.spell_allowed(profile, card, faction, 1)))
		cards.sort_custom(ELDuelScreen.classic_less.bind(profile))
		var ordered := true
		var neutral_seen := false
		for i in cards.size():
			var row: Dictionary = profile.table("CombatSpells")[cards[i]]
			if str(row.Color) == ELDuelCosts.EL2_NEUTRAL: neutral_seen = true
			elif neutral_seen: ordered = false
			if i > 0 and ELDuelScreen.classic_less(cards[i], cards[i - 1], profile): ordered = false
		check(ordered and not cards.is_empty(), "el2 %s: %d available spells, own race first, each by rarity, class and reversed code" % [faction, cards.size()])
		if faction == "Red":
			var names := PackedStringArray()
			for card in cards.slice(0, 10): names.append("%s %s/%s/%s" % [card, profile.table("CombatSpells")[card].get("Rarity"), profile.table("CombatSpells")[card].get("Class"), profile.text(card + "Nm")])
			print("  el2 Red first ten: " + ", ".join(names))
	# The code tie-break reads the letters from the last one back.
	check(ELDuelScreen.classic_key(profile, "ABCZ")[3] > ELDuelScreen.classic_key(profile, "ZBCA")[3], "el2: codes compare from their last letter back")

func _strict_second_game(profile: ELProfile) -> void:
	var preset := _over_budget(profile, "Red", 16)
	check(not ELDuelCosts.errors(profile, preset).is_empty(), "el2: the test preset breaks the rules")
	check(not ELDuelPresets.lenient(profile), "el2: presets that break the rules are still refused on load")

# --- First game: .prs presets and lenient loading -------------------------------

## A preset of `faction` with its first `count` spells at resource level 1
## and hero level 15: well over the level-1 budget.
func _over_budget(profile: ELProfile, faction: String, count: int) -> Dictionary:
	var preset := ELDuelPresets.blank(faction, 1)
	preset.level = ELDuelCosts.hero_levels(profile).y
	var cards := ELCatalog.available_cards(profile, faction).filter(func(card: String): return ELDuelCosts.spell_allowed(profile, card, faction, 1))
	for i in mini(count, cards.size()):
		preset.cards.append(cards[i])
		preset.runes.append(1)
	return preset

func _prs_text(name: String, preset: Dictionary, extra_spell := "") -> String:
	var lines := PackedStringArray()
	lines.append("<?xml version=\"1.0\"?>")
	lines.append("<duel_preset name=\"%s\" magic=\"%s\" resource_level=\"%d\" hero_level=\"%d\">" % [name, preset.faction, preset.resource_level, preset.level])
	lines.append("<skills><skill type=\"MSTR\" level=\"2\"/></skills>")
	lines.append("<deck>")
	for i in preset.cards.size(): lines.append("<spell code=\"%s\" components=\"%d\"/>" % [preset.cards[i], preset.runes[i]])
	if not extra_spell.is_empty(): lines.append("<spell code=\"%s\" components=\"1\"/>" % extra_spell)
	lines.append("</deck></duel_preset>")
	return "\r\n".join(lines)

func _original_presets(profile: ELProfile) -> void:
	var preset := _over_budget(profile, "Black", 9)
	check(not ELDuelCosts.errors(profile, preset).is_empty(), "el1: the test preset breaks today's rules (%s)" % ", ".join(ELDuelCosts.errors(profile, preset)))
	var readable := ELDuelPresets.readable(profile, preset)
	check(not readable.is_empty() and readable.cards == preset.cards and int(readable.level) == int(preset.level), "el1: a preset over budget stays readable, as the original loads it")
	var short := ELDuelPresets.readable(profile, _over_budget(profile, "Black", 3))
	check(short.cards.size() == 3, "el1: a book of fewer than 15 spells is readable")
	var other := ELCatalog.available_cards(profile, "Red")[0]
	var mixed := preset.duplicate(true)
	mixed.cards.insert(2, other)
	mixed.runes.insert(2, 1)
	mixed.cards.append("ZZZZ")
	mixed.runes.append(1)
	mixed.cards.append(preset.cards[0])
	mixed.runes.append(1)
	var kept := ELDuelPresets.readable(profile, mixed)
	check(kept.cards == preset.cards, "el1: another race's spell is left out and the book ends at an unknown spell")
	# An original file in the game's own Duel folder.
	var folder := OS.get_user_data_dir().path_join("player_reports_check")
	DirAccess.make_dir_recursive_absolute(folder)
	var name := "zz check %d" % OS.get_process_id()
	var source := folder.path_join(name + ".prs")
	var text := _prs_text(name, preset, "ZZZZ")
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var parsed := ELDuelPresets._original_preset(profile, source)
	check(parsed.get("faction") == "Black" and parsed.get("cards", []).size() == preset.cards.size() + 1 and int(parsed.skills.get("MSTR", -1)) == 1 and int(parsed.level) == int(preset.level), "el1: the .prs layout reads (magic, levels, skills/skill@type,level, deck/spell@code,components)")
	var index_path := ELDuelPresets.user_dir(profile).path_join(ELDuelPresets.IMPORTED_INDEX)
	var index_before := FileAccess.get_file_as_string(index_path) if FileAccess.file_exists(index_path) else ""
	var key := "duel/" + name + ".prs"
	profile._files[key] = source
	var rejected: Array = []
	var pool := ELDuelPresets.load_user(profile, rejected)
	var found := ELDuelPresets.find(pool, "user:" + name)
	check(not found.is_empty() and found.cards == preset.cards, "el1: a .prs in the game's Duel folder appears among the presets (%s)" % ", ".join(PackedStringArray(rejected)))
	check(FileAccess.file_exists(source) and FileAccess.get_file_as_string(source) == text and not FileAccess.file_exists(source + ".imported"), "el1: the game folder's .prs is left untouched")
	if not found.is_empty():
		var choice := ELDuelPresets.choice(profile, found)
		var duel := ELDuel.new()
		var other_side := ELDuelPresets.choice(profile, ELDuelPresets.shipped(profile)[0])
		check(duel.start(profile, 7, {"arena": ELDuelMatch.arenas(profile)[0], "players": [choice, other_side]}), "el1: a battle starts with the imported preset: " + duel.error)
	# Deleted, it stays deleted until the file changes.
	ELDuelPresets.delete_user(profile, name)
	pool = ELDuelPresets.load_user(profile)
	check(ELDuelPresets.find(pool, "user:" + name).is_empty(), "el1: a deleted imported preset is not read again from the unchanged file")
	profile._files.erase(key)
	ELDuelPresets.delete_user(profile, name)
	DirAccess.remove_absolute(source)
	DirAccess.remove_absolute(folder)
	if index_before.is_empty(): DirAccess.remove_absolute(index_path)
	else:
		var restore := FileAccess.open(index_path, FileAccess.WRITE)
		restore.store_string(index_before)
		restore.close()
	# A .prs copied into the user folder is converted (the existing route).
	var copied := ELDuelPresets.user_dir(profile).path_join(name + ".prs")
	DirAccess.make_dir_recursive_absolute(ELDuelPresets.user_dir(profile))
	file = FileAccess.open(copied, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	pool = ELDuelPresets.load_user(profile)
	check(not ELDuelPresets.find(pool, "user:" + name).is_empty(), "el1: a .prs copied into the user folder is converted, over budget or not")
	ELDuelPresets.delete_user(profile, name)
	for leftover: String in DirAccess.get_files_at(ELDuelPresets.user_dir(profile)):
		if leftover.begins_with(name + ".prs"): DirAccess.remove_absolute(ELDuelPresets.user_dir(profile).path_join(leftover))

# --- First game: a neutral creature as the opponent hero ------------------------

func _monster_battle() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has("el1"):
		print("SKIP: el1 files could not be mounted by the battle view")
		view.queue_free()
		return
	var profile: ELProfile = view.profiles.el1
	var row := ELFirstMonsters.definition(profile, "Pteros", 1)
	check(not row.is_empty(), "el1: the Pteros monster row exists")
	if row.is_empty():
		view.queue_free()
		return
	var hero := {"faction": "Green", "level": 1, "cards": ELCatalog.available_cards(profile, "Green").slice(0, 5)}
	var monster := {"faction": str(row.Color), "kind": "monster", "title": profile.text(str(row.ELKName)), "level": int(row.Level), "health": int(row.Health),
		"cards": ELFirstMonsters.book(row).cards, "skills": {}, "monster_name": "Pteros", "monster_difficulty": 1}
	view._start("el1", {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": [hero, monster]})
	await frames(10)
	check(view.duel != null, "el1: a battle against the Pteros starts")
	var portrait: Texture2D = view.portraits[1].texture
	var expected := profile.portrait(int(row.Icon)) as AtlasTexture
	check(portrait is AtlasTexture and (portrait as AtlasTexture).atlas == expected.atlas and (portrait as AtlasTexture).region == expected.region, "el1: the monster's battle portrait is its Monsters Icon photo (%d)" % int(row.Icon))
	var tip: Dictionary = view._hero_tip(1)
	var texts := PackedStringArray()
	for label: Dictionary in tip.labels: texts.append(str(label.text))
	print("  el1 monster tooltip: " + JSON.stringify(texts))
	check(texts.size() > 0 and texts[0] == monster.title, "el1: the tooltip is headed by the creature's name")
	var level_line := "%s: %d" % [view._original_text("T_LEVEL", "Level"), int(view.duel.heroes[1].get("level", 1))]
	var health_line := "%s: %d" % [view._original_text("CtrlTtCombatTt1", "Health"), int(view.duel.heroes[1].health)]
	check(texts.size() == 3 and texts[1] == level_line and texts[2] == health_line, "el1: the monster's tooltip is its name, Level and Health only")
	check(tip.picture.texture == portrait and tip.picture.size == ELCombatTooltip.FIRST_PORTRAIT, "el1: the tooltip shows the same photo at 100 x 70")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		await _hold_on_monster(view)
	view.queue_free()
	await frames(2)

## A touch hold on the opponent's figure, saved as a picture.
func _hold_on_monster(view: Node) -> void:
	for i in 120:
		view.ai_clock = -1000.0
		await process_frame
	var model: ELModel = view.models.get(1)
	if model == null: return
	var point := Vector2(-1, -1)
	for height: float in [0.6, 0.4, 0.8, 0.2, 1.0]:
		var at: Vector2 = view.camera.unproject_position(model.global_position + Vector3(0, height, 0))
		if view._character_at(at) == 1:
			point = at
			break
	if point.x < 0: return
	var touch: ELTouchInput = view.touch_input
	var was_enabled := ELTouchInput.enabled
	touch.set_enabled(true)
	for figure: Variant in view.models.values():
		if is_instance_valid(figure): figure.set_process(false)
	touch._press(0, point)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int((ELTouchInput.HOLD_SECONDS + 0.6) * 1000.0):
		view.ai_clock = -1000.0
		await process_frame
	await RenderingServer.frame_post_draw
	var path := shots.path_join("monster_tooltip_el1.png")
	root.get_texture().get_image().save_png(path)
	print("SHOT: " + path)
	touch._release(0, point, false)
	touch.set_enabled(was_enabled)

# --- First game: the pre-battle map panel ---------------------------------------

func _precombat(profile: ELProfile) -> void:
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	var saves := _backup(ELSaveSlots.folder("el1"))
	var settings := ELSettings.new()
	settings.use_edition("el1")
	settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(settings).persist = false
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	_restore(ELSaveSlots.folder("el1"), saves)
	check(built, "el1: the first mission map builds: " + view.error)
	if not built:
		view.queue_free()
		return
	await frames(5)
	if view.tutorial_panel != null and view.tutorial_panel.visible: view.tutorial_panel.close()
	var state := view.state
	var hero := -1
	var monster := -1
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false): continue
		if item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player and hero < 0: hero = int(item.uid)
		if item.get("type") == "monster" and monster < 0: monster = int(item.uid)
	check(hero >= 0 and monster >= 0, "el1: the map has the player's hero and a neutral creature")
	if hero >= 0 and monster >= 0:
		var hud = view.hud
		# #49: a battle with a neutral creature can be left alone (remake X, Esc).
		var hero_item := state.object(hero)
		var monster_item := state.object(monster)
		var at := Vector2i(int(hero_item.x), int(hero_item.y))
		view.director._begin_encounter(hero_item, monster_item)
		await frames(3)
		var prepared: bool = view.director.encounter != null
		check(prepared and view.director.encounter.declinable(), "el1: a battle with a neutral creature can be declined")
		check(hud.precombat.visible and hud.cancel_button.visible, "el1: the pre-battle panel shows the X for a neutral creature")
		if prepared:
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.pressed = true
			view._unhandled_input(esc)
			await frames(3)
			check(view.director.encounter == null and view.pending_encounter.is_empty() and not hud.precombat.visible, "el1: Esc declines and closes the panel without a battle")
			check(hero_item.alive and monster_item.alive and Vector2i(int(hero_item.x), int(hero_item.y)) == at, "el1: after declining both sides live and the hero stays where it stood")
		hud.show_precombat(hero, monster, 1, 1, true)
		await frames(3)
		var labels: Dictionary = hud.precombat_labels
		var heading: Label = labels.heading
		var name: Label = labels.names[1]
		var value: Label = labels.values[0][0]
		var caption: Label = labels.captions[0][0]
		var size_of := func(label: Label) -> int: return label.get_theme_font_size("font_size")
		check(size_of.call(heading) == ELFrontMenu.cell_em(20) and size_of.call(name) == ELFrontMenu.cell_em(20), "el1: the panel's heading and names use 20 px cells (%d em)" % size_of.call(name))
		check(size_of.call(value) == ELFrontMenu.cell_em(15) and size_of.call(caption) == ELFrontMenu.cell_em(15), "el1: the Level/Life/Sight lines use 15 px cells (%d em)" % size_of.call(value))
		var font: Font = caption.get_theme_font("font")
		var widest := 0.0
		for side in 2:
			for line in 3:
				var shown: Label = labels.captions[side][line]
				if shown.visible: widest = maxf(widest, font.get_string_size(shown.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_of.call(shown)).x)
		check(widest <= caption.size.x, "el1: the stat captions fit their boxes (%.0f of %.0f)" % [widest, caption.size.x])
		check(font.get_string_size(name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_of.call(name)).x <= name.size.x, "el1: the opponent's name fits its box")
		if not shots.is_empty() and DisplayServer.get_name() != "headless":
			await frames(30)
			await RenderingServer.frame_post_draw
			var path := shots.path_join("precombat_el1.png")
			root.get_texture().get_image().save_png(path)
			print("SHOT: " + path)
	view.queue_free()
	await frames(2)

func _backup(folder: String) -> Dictionary:
	var files := {}
	if DirAccess.dir_exists_absolute(folder):
		for file: String in DirAccess.get_files_at(folder): files[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return files

func _restore(folder: String, files: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file: String in DirAccess.get_files_at(folder):
		if not files.has(file): DirAccess.remove_absolute(folder.path_join(file))
	for file: String in files:
		var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
		if out != null: out.store_buffer(files[file])
