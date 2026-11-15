extends SceneTree
## Headless check of later player reports (0.14.1 issue list):
## - #116 original .prs decks: the header and every entry are read from an
##   attribute or from a child element's text, in UTF-8, UTF-16 (either byte
##   order, with or without a declaration naming its encoding), and with any
##   letter case in the tags; a file whose name holds characters a preset name
##   cannot is imported under that name with `_` in their place; a file copied
##   into the game's Duel folder after the game data was indexed is found; a
##   file an earlier version failed to read is tried again.
## - #126 first game: a cantrip in the book cannot be moved to the reserve.
## - #120 second game: the Spellshifter's, Spellweaver's and Spell Eater's
##   abilities are unavailable with no enchantment in play they could take.
## - #130 the Wall of Unreality's suggestion can be bought again in the same
##   round while there is ether, each use adding 2 power.
## - in a battle: #121 a creature's tooltip has its cost line in both games;
##   #123 a spell or hero ability that takes a creature from the graveyard
##   opens the own graveyard at once; #124 first game with cast icons: the
##   player's own casts get an icon too, and an ability has one; #117 a right
##   drag turns the camera only with the automatic camera off; #128 second
##   game: Attack all stays shut when only powerless creatures could attack.
## - #133 Enter presses the check button of the duel setup (both games) and
##   of the second game's chapter map.
## - #127 the load list opens on the save last made or loaded, not the top one.
## - #77 second game, a local match between rounds: each hot-seat player (or
##   the player against the computer) can exchange a reserve spell, and the
##   next round deals the changed deck.
## - #118 a monster standing as the opposing side wears both its textures, as
##   the same creature does when summoned.
## - #97 first game: a fort garrison guards three tiles straight out from the
##   fort (open ground), two diagonally, and no further.
## - #131 path tracing: a creature's or hero's own glow lights the scene at
##   the raster lamps' share and reach, not a spell's (it whitened the snow
##   of the Kinet arenas around pale creatures in 0.14.1).
## - #61 second game, a custom map: a declined guard-zone battle leaves the
##   hero outside the zone even without the campaign's step-back hook.
## - 0.15.0 reports: #136 the opposing hero's skills stay out of its battle
##   tooltip; #142 a right click on the arena clears the selection; #141 a
##   skip drops the skipped gestures' held sounds; #140 second game: a fallen
##   hero goes up in its colour's death effect; #137 the pre-battle panel:
##   first game, the wide strip alone with the original orders, the check
##   mark and the cross with free movement; second game, no wide strip;
##   #138 the hero turns to face the creature it fights; #139 second game:
##   the defeat picture is black from its first frame, fades to black and
##   back to the map, and a surrender shows the hero's death first.
## - #152 first game: Ethereal Attack and Counterstrike add no castle damage,
##   as in the original, and their skill texts now say they have no effect.
##
##   godot --headless --path game --script ../tools/issue_reports_check.gd
##
## Needs the original games' files (user://profiles.json); without them a
## game is skipped. Files the check writes are removed afterwards.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var profiles := {}
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		var profile := ELProfile.new()
		if profile.mount(edition, str(paths[edition])): profiles[edition] = profile
		else: print("SKIP: %s files could not be mounted" % edition)
	for edition: String in profiles: _prs_variants(profiles[edition])
	for edition: String in profiles: _prs_import_routes(profiles[edition])
	if profiles.has("el1"): _cantrip_reserve(profiles.el1)
	if profiles.has("el2"): _pale_dispellers(profiles.el2)
	for edition: String in profiles: _unreality_wall(profiles[edition])
	for edition: String in profiles: await _battle_view(edition)
	for edition: String in profiles: await _enter_starts(edition, profiles[edition])
	if profiles.has("el1"): await _last_save(profiles.el1)
	if profiles.has("el2"): await _hot_seat_decks(profiles.el2)
	if profiles.has("el2"): await _custom_map_decline(profiles.el2)
	if profiles.has("el1"): await _monster_figure_textures()
	if profiles.has("el1"): _fort_zone(profiles.el1)
	if profiles.has("el1"): _castle_skills(profiles.el1)
	_figure_glow_light()
	for edition: String in profiles: await _battle_reports(edition)
	await _map_reports(profiles)
	for extra: Callable in extra_checks: await extra.call(profiles)
	print("%d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

## Further checks register here: func(profiles: Dictionary).
var extra_checks: Array[Callable] = []

# --- #116 .prs --------------------------------------------------------------

func _deck(profile: ELProfile) -> Dictionary:
	var faction := "Black" if profile.id == "el1" else "Red"
	var preset := ELDuelPresets.blank(faction, 3)
	preset.level = 5
	var cards := ELCatalog.available_cards(profile, faction).filter(func(card: String): return ELDuelCosts.spell_allowed(profile, card, faction, 3))
	var count := 15 if profile.id == "el1" else 16
	for i in count:
		preset.cards.append(cards[i % mini(cards.size(), 4)])
		preset.runes.append(2)
	return preset

func _attribute_text(preset: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("<duel_preset magic=\"%s\" resource_level=\"%d\" hero_level=\"%d\" specialization=\"NONE\">" % [preset.faction, preset.resource_level, preset.level])
	lines.append("<deck>")
	for i in preset.cards.size(): lines.append("<spell code=\"%s\" components=\"%d\"/>" % [preset.cards[i], preset.runes[i]])
	lines.append("</deck><skills/><artefacts/></duel_preset>")
	return "\r\n".join(lines)

func _element_text(preset: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("<?xml version=\"1.0\"?>")
	lines.append("<duel_preset><magic>%s</magic><resource_level>%d</resource_level><hero_level>%d</hero_level><specialization>NONE</specialization>" % [preset.faction, preset.resource_level, preset.level])
	lines.append("<deck>")
	for i in preset.cards.size(): lines.append("<spell components=\"%d\">%s</spell>" % [preset.runes[i], preset.cards[i]])
	lines.append("</deck><skills></skills><artefacts></artefacts></duel_preset>")
	return "\r\n".join(lines)

func _utf16(text: String, big_endian: bool, bom := true) -> PackedByteArray:
	var bytes := PackedByteArray()
	if bom: bytes.append_array([254, 255] if big_endian else [255, 254])
	var body := text.to_utf16_buffer()
	if big_endian:
		for i in range(0, body.size() - 1, 2):
			var low := body[i]
			body[i] = body[i + 1]
			body[i + 1] = low
	bytes.append_array(body)
	return bytes

func _same(parsed: Dictionary, preset: Dictionary) -> bool:
	return not parsed.is_empty() and parsed.get("faction") == preset.faction and parsed.get("cards", []) == preset.cards and parsed.get("runes", []) == preset.runes and int(parsed.get("level", 0)) == int(preset.level) and int(parsed.get("resource_level", 0)) == int(preset.resource_level)

func _prs_variants(profile: ELProfile) -> void:
	var preset := _deck(profile)
	var e := profile.id
	check(_same(ELDuelPresets._parse_original(profile, _attribute_text(preset).to_utf8_buffer()), preset), e + " #116: .prs with attributes reads")
	check(_same(ELDuelPresets._parse_original(profile, _element_text(preset).to_utf8_buffer()), preset), e + " #116: .prs with child elements reads")
	var declared := "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\r\n" + _attribute_text(preset)
	check(_same(ELDuelPresets._parse_original(profile, _utf16(declared, false)), preset), e + " #116: UTF-16 LE .prs with an encoding declaration reads")
	check(_same(ELDuelPresets._parse_original(profile, _utf16(declared, true)), preset), e + " #116: UTF-16 BE .prs reads")
	check(_same(ELDuelPresets._parse_original(profile, _utf16(_attribute_text(preset), false, false)), preset), e + " #116: UTF-16 .prs without a byte order mark reads")
	var bom := PackedByteArray([239, 187, 191])
	bom.append_array(("<?xml version=\"1.0\" encoding=\"windows-1251\"?>" + _element_text(preset).replace("<?xml version=\"1.0\"?>", "")).to_utf8_buffer())
	check(_same(ELDuelPresets._parse_original(profile, bom), preset), e + " #116: UTF-8 .prs with a byte order mark and a code-page declaration reads")
	var upper := _attribute_text(preset).replace("<duel_preset", "<DUEL_PRESET").replace("</duel_preset>", "</DUEL_PRESET>").replace("<deck>", "<Deck>").replace("</deck>", "</Deck>")
	check(_same(ELDuelPresets._parse_original(profile, upper.to_utf8_buffer()), preset), e + " #116: tag case does not matter")
	check(ELDuelPresets._import_name("My deck v1.2 [fire].prs") == "My deck v1_2 _fire_", e + " #116: a file name with forbidden characters becomes a valid preset name")

func _prs_import_routes(profile: ELProfile) -> void:
	var e := profile.id
	var preset := _deck(profile)
	var text := _element_text(preset)
	# Copied into the user folder under a name with forbidden characters.
	var name := "zz issue check %d" % OS.get_process_id()
	var dir := ELDuelPresets.user_dir(profile)
	DirAccess.make_dir_recursive_absolute(dir)
	var copied := dir.path_join(name + " v1.0.prs")
	var file := FileAccess.open(copied, FileAccess.WRITE)
	file.store_buffer(_utf16("<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + text.replace("<?xml version=\"1.0\"?>", ""), false))
	file.close()
	var rejected: Array = []
	var pool := ELDuelPresets.load_user(profile, rejected)
	var imported_name := name + " v1_0"
	var found := ELDuelPresets.find(pool, "user:" + imported_name)
	check(not found.is_empty() and found.cards == preset.cards, e + " #116: a UTF-16 element-layout .prs copied into the user folder imports (%s)" % ", ".join(PackedStringArray(rejected)))
	ELDuelPresets.delete_user(profile, imported_name)
	for left in DirAccess.get_files_at(dir):
		if left.begins_with(name): DirAccess.remove_absolute(dir.path_join(left))
	# Copied into the game's own Duel folder after indexing, and an earlier
	# version's stamp for a file it failed to read.
	var folder := profile.root.path_join("Duel")
	if not DirAccess.dir_exists_absolute(folder) or FileAccess.open(folder.path_join(".write_test"), FileAccess.WRITE) == null:
		print("SKIP: %s game Duel folder not writable" % e)
		return
	DirAccess.remove_absolute(folder.path_join(".write_test"))
	var source := folder.path_join(name + ".prs")
	file = FileAccess.open(source, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var index_path := dir.path_join(ELDuelPresets.IMPORTED_INDEX)
	var index_before := FileAccess.get_file_as_string(index_path) if FileAccess.file_exists(index_path) else ""
	var index: Dictionary = JSON.parse_string(index_before) if not index_before.is_empty() else {}
	index[name] = str(FileAccess.get_modified_time(source))
	var write := FileAccess.open(index_path, FileAccess.WRITE)
	write.store_string(JSON.stringify(index))
	write.close()
	pool = ELDuelPresets.load_user(profile)
	found = ELDuelPresets.find(pool, "user:" + name)
	check(not found.is_empty() and found.cards == preset.cards, e + " #116: a .prs added to the game's Duel folder after start, once failed, is read")
	ELDuelPresets.delete_user(profile, name)
	pool = ELDuelPresets.load_user(profile)
	check(ELDuelPresets.find(pool, "user:" + name).is_empty(), e + " #116: once read, a deleted preset stays deleted")
	DirAccess.remove_absolute(source)
	if index_before.is_empty(): DirAccess.remove_absolute(index_path)
	else:
		var restore := FileAccess.open(index_path, FileAccess.WRITE)
		restore.store_string(index_before)
		restore.close()

# --- #126 cantrips stay in the book -------------------------------------------

func _cantrip_reserve(profile: ELProfile) -> void:
	var cantrip := ""
	for code: String in profile.table("CombatSpells"):
		if profile.table("CombatSpells")[code].get("Rarity") == "Cantrip":
			cantrip = code
			break
	check(not cantrip.is_empty(), "el1 #126: the game has cantrips")
	var hero := {"type": "hero", "cards": [cantrip], "rune_uses": [-1], "rune_stock": {}}
	var problem := ELSpellInventory.unequip(profile, hero, 0)
	check(not problem.is_empty() and hero.cards == [cantrip] and hero.rune_stock.is_empty(), "el1 #126: a cantrip cannot be moved to the reserve (%s)" % problem)

# --- #120 pale dispellers -------------------------------------------------------

func _summon(duel: ELDuel, side: int, card: String) -> int:
	var known := duel.creatures.keys()
	duel._summon(side, card)
	for key: int in duel.creatures:
		if not known.has(key): return key
	return -1

func _pale_dispellers(profile: ELProfile) -> void:
	var duel := ELDuel.new()
	if not duel.start(profile, 11, {}):
		check(false, "el2 #120: a duel starts")
		return
	var side := duel.active_side()
	duel.heroes[side].mana = 10
	var other := _summon(duel, 1 - side, "ORSH")
	for card: String in ["OUE1", "OUE2", "OUE3"]:
		var pale := _summon(duel, side, card)
		duel.creatures[pale].sick = false
		duel.plane_change(pale, true)
		var key := ""
		for ability: Dictionary in duel.abilities(pale):
			if ability.get("pale", false) and ability.key in ["absorb", "weave", "transpose"]: key = ability.key
		check(not key.is_empty(), "el2 #120: %s has its pale ability" % card)
		for holder: int in [0, 1] + duel.creatures.keys(): duel.entity(holder).enchantments.clear()
		check(not duel.can_use_ability(pale, key), "el2 #120: %s cannot use %s with no enchantment in play" % [card, key])
		duel._enchant("ENFL", 1 - side, other, ELCatalog.rule(profile, "ENFL"))
		check(duel.can_use_ability(pale, key), "el2 #120: %s can use %s once an enchantment is in play" % [card, key])

# --- #130 Wall of Unreality ---------------------------------------------------

func _unreality_wall(profile: ELProfile) -> void:
	var e := profile.id
	var duel := ELDuel.new()
	if not duel.start(profile, 11, {}):
		check(false, e + " #130: a duel starts")
		return
	var side := duel.active_side()
	var wall := _summon(duel, side, "PHWL")
	if wall < 0:
		check(false, e + " #130: a Wall of Unreality is summoned")
		return
	duel.heroes[side].mana = 7
	var power: int = duel.creatures[wall].power
	var first := duel.use_ability(wall, "phantasm")
	var second := duel.can_use_ability(wall, "phantasm") and duel.use_ability(wall, "phantasm")
	check(first and second and duel.creatures[wall].power == power + 4 and int(duel.heroes[side].mana) == 1, e + " #130: the wall's suggestion works twice in a round, +2 power each (%s)" % duel.error)
	check(not duel.can_use_ability(wall, "phantasm"), e + " #130: a third use waits for 3 ether")

# --- Battle screen: #121 #123 #124 ------------------------------------------------

func _battle_view(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		view.queue_free()
		return
	var profile: ELProfile = view.profiles[edition]
	var players := [{"faction": "Red", "level": 5, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)},
		{"faction": "Red", "level": 5, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)}]
	view._start(edition, {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": players})
	view.demo = false
	for i in 10: await process_frame
	var duel: ELDuel = view.duel
	if duel == null or not view._human_turn():
		check(false, "%s: a battle for the battle-screen checks starts on the player's turn" % edition)
		view.queue_free()
		return
	var side := duel.active_side()
	duel.heroes[side].mana = 20
	# #121
	var shaman := _summon(duel, side, "ORSH")
	var cost := ELCombatTooltip.cost_line(profile, int(profile.table("CombatSpells").ORSH.Cost))
	check(view._creature_tip_text(shaman).contains(cost), "%s #121: a creature's tooltip shows its cost (%s)" % [edition, cost])
	# Enchantments on a figure are named with their card text in its tooltip.
	var worn := {"id": 99001, "card": "HEAL", "owner": side}
	var about := profile.card_description("HEAL")
	duel.creatures[shaman].enchantments.append(worn)
	duel.heroes[side].enchantments.append(worn)
	var hero_tip: Dictionary = view._hero_tip(side)
	check(view._creature_tip_text(shaman).contains(duel.card_name("HEAL") + ": " + about), "%s: a creature's tooltip lists its enchantments with their text" % edition)
	check(hero_tip.labels.any(func(label: Dictionary) -> bool: return str(label.text).contains(duel.card_name("HEAL"))), "%s: a hero's tooltip lists its enchantments" % edition)
	duel.creatures[shaman].enchantments.erase(worn)
	duel.heroes[side].enchantments.erase(worn)
	# #123 a spell
	duel.heroes[side].grave.append("ORSH")
	duel._give_card(side, "REPR")
	view.selected_creature = 1 - side
	view.inspect_graveyard = false
	view._cast_card(duel.heroes[side].hand.size() - 1)
	check(view.inspect_graveyard and view.selected_creature == side, "%s #123: Repair opens the own graveyard" % edition)
	view.selection = -1
	view.inspect_graveyard = false
	view.selected_creature = 1 - side
	# #123 a hero ability (the repair workshop enchantment)
	duel._enchant("RPST", side, side, ELCatalog.rule(profile, "RPST"))
	var ability := {}
	for item: Dictionary in duel.abilities(side):
		if String(item.key).begins_with("repair"): ability = item
	check(not ability.is_empty(), "%s #123: the repair workshop gives its hero an ability" % edition)
	if not ability.is_empty():
		view._select_ability(side, ability)
		check(view.inspect_graveyard and view.selected_creature == side, "%s #123: the workshop's ability opens the own graveyard" % edition)
		if edition == "el1":
			var card: String = view._ability_card_of(side, String(ability.key))
			check(card == "RPST" and view._ability_icon(card) != null, "el1 #124: a hero ability has an icon (%s)" % card)
	view.ability_selection.clear()
	# #124
	if edition == "el1":
		view.settings.values.cast_icons = true
		var before: int = view.notices.icons.size()
		view._cast_notice(side, "FRWN")
		check(view.notices.icons.size() == before + 1, "el1 #124: the player's own cast shows its icon")
		check(view._ability_icon(view._ability_card_of(shaman, String(duel.abilities(shaman)[0].key))) != null if not duel.abilities(shaman).is_empty() else false, "el1 #124: a creature ability has an icon")
	# #128 second game: creatures with no power alone leave Attack all shut.
	if edition == "el2" and duel.phase == ELDuel.Phase.ATTACK:
		for c: Dictionary in duel.army(side): duel._kill(int(c.id))
		var weak := _summon(duel, side, "ORSH")
		duel.creatures[weak].sick = false
		duel.creatures[weak].resting = false
		duel.creatures[weak].power = 0
		view._refresh_buttons()
		check(duel.can_declare_attack(weak) and view.attack_button.disabled, "el2 #128: Attack all is shut when only creatures with no power could attack")
		duel.creatures[weak].power = 2
		view._refresh_buttons()
		check(not view.attack_button.disabled, "el2 #128: a creature with power opens Attack all")
	# #117
	var kept_auto: Variant = view.settings.values.get("auto_camera")
	for automatic: bool in [true, false]:
		view.settings.values.auto_camera = automatic
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_RIGHT
		press.pressed = true
		press.position = Vector2(400, 300)
		view._right_button(press)
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(460, 300)
		view._right_button(motion)
		check(view.orbiting == not automatic, "%s #117: with the automatic camera %s a right drag %s the camera" % [edition, "on" if automatic else "off", "does not turn" if automatic else "turns"])
		var release: InputEventMouseButton = press.duplicate()
		release.pressed = false
		view._right_button(release)
	if kept_auto == null: view.settings.values.erase("auto_camera")
	else: view.settings.values.auto_camera = kept_auto
	# A selected creature stays selected when the phase changes, but a
	# selection from an earlier phase does not assign a block or an attack.
	var kept := _summon(duel, side, "ORSH")
	view.selection = -1
	view.ability_selection.clear()
	view._target(kept)
	var mark: String = view.selection_phase
	check(view.selected_creature == kept and mark == view._phase_mark(), "%s: clicking a creature selects it in this phase" % edition)
	if duel.end_phase():
		for i in 3: await process_frame
		view._refresh()
		check(view.selected_creature == kept, "%s: the selected creature stays selected after the phase changes" % edition)
		check(view.selection_phase != view._phase_mark(), "%s: a selection from the phase before is not this phase's" % edition)
	duel.creatures.erase(kept)
	view._refresh()
	check(view.selected_creature == -1, "%s: a selected creature that left play is no longer selected" % edition)
	# The battle log (L) keeps the battle's history and scrolls.
	for i in 30: view._log("line %d" % i)
	check(view.logs.size() >= 30 and view.log_text.scroll_active and view.log_text.scroll_following and view.log_text.mouse_filter == Control.MOUSE_FILTER_STOP, "%s: the battle log keeps every line and scrolls" % edition)
	# A long enchantment list on the upper strip scrolls with its arrows and
	# with the mouse wheel.
	for i in 14: duel.heroes[side].enchantments.append({"id": 99100 + i, "card": "HEAL", "owner": side})
	view.selected_creature = side
	view.inspect_graveyard = false
	view._fill_strip()
	var strip: ELCombatStrip = view.rail.strip
	# The right arrow's button lies on the arrow drawn at the end of the icon
	# row, at any row width (on wide screens it was left far to the right).
	var saved_width := strip.row_width
	for width: float in [saved_width, saved_width + 4 * ELCombatStrip.PITCH]:
		strip.row_width = width
		strip.layout()
		var cap_x := 127.0 - ELCombatStrip.CLIP.position.x + 22.0 + width + 4.0
		var button_rect := Rect2(strip.right.position, strip.right.size)
		check(button_rect.position.x <= cap_x + 21.0 and button_rect.end.x >= cap_x, "%s: the strip's right arrow button sits on its drawn arrow (row %d, button %s, cap at %d)" % [edition, width, button_rect, cap_x])
	strip.row_width = saved_width
	strip.layout()
	var start := strip.first
	strip.right.pressed.emit()
	strip.right.button_up.emit()
	check(strip.items.size() > strip.visible_count() and strip.first == start + 1, "%s: the strip's right arrow scrolls a long enchantment list (%d of %d shown, first %d)" % [edition, strip.visible_count(), strip.items.size(), strip.first])
	view._refresh()
	check(strip.first == start + 1, "%s: a refresh keeps the strip where it was scrolled" % edition)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	strip.buttons[strip.first].gui_input.emit(wheel)
	check(strip.first == start + 2, "%s: the mouse wheel over the strip scrolls it" % edition)
	duel.heroes[side].enchantments = duel.heroes[side].enchantments.filter(func(e: Dictionary) -> bool: return int(e.id) < 99100 or int(e.id) >= 99114)
	view.queue_free()
	for i in 2: await process_frame

# --- #133 Enter on the duel setup and the chapter map ---------------------------

func _enter(menu: ELFrontMenu) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	menu._input(event)

func _enter_starts(edition: String, profile: ELProfile) -> void:
	var menu := ELFrontMenu.new()
	menu.settings_path = OS.get_user_data_dir().path_join("issue_reports_check_settings.json")
	menu.settings = ELSettings.new()
	menu.settings.use_edition(edition)
	root.add_child(menu)
	if not menu.build({edition: profile}, edition):
		check(false, edition + " #133: the menu builds")
		menu.queue_free()
		return
	for i in 2: await process_frame
	menu.show_screen("duel")
	for i in 2: await process_frame
	var start: BaseButton = menu.buttons.get("DuStart")
	var pressed: Array = []
	if start != null:
		for connection: Dictionary in start.pressed.get_connections(): start.pressed.disconnect(connection.callable)
		start.pressed.connect(func(): pressed.append(true))
		start.disabled = false
	_enter(menu)
	check(start != null and pressed.size() == 1, edition + " #133: Enter presses the duel setup's check button")
	if edition == "el2":
		menu.show_screen("campaigns")
		for i in 2: await process_frame
		if not menu.cards.is_empty():
			menu.selected_campaign = menu.cards[0].campaign
			menu._confirm_campaign()
			for i in 2: await process_frame
			var go: BaseButton = menu.buttons.get("GMA6Start")
			pressed.clear()
			if go != null:
				for connection: Dictionary in go.pressed.get_connections(): go.pressed.disconnect(connection.callable)
				go.pressed.connect(func(): pressed.append(true))
			_enter(menu)
			check(menu.screen == "map" and go != null and pressed.size() == 1, "el2 #133: Enter presses the chapter map's check button (screen %s)" % menu.screen)
		else: check(false, "el2 #133: the campaign list has cards")
	menu.queue_free()
	if FileAccess.file_exists(menu.settings_path): DirAccess.remove_absolute(menu.settings_path)
	for i in 2: await process_frame

# --- #127 the load list opens on the last used save --------------------------------

func _last_save(profile: ELProfile) -> void:
	var kept := FileAccess.get_file_as_string(ELSaveSlots.LAST_USED) if FileAccess.file_exists(ELSaveSlots.LAST_USED) else ""
	var menu := ELFrontMenu.new()
	menu.settings_path = OS.get_user_data_dir().path_join("issue_reports_check_settings.json")
	menu.settings = ELSettings.new()
	menu.settings.use_edition("el1")
	root.add_child(menu)
	menu.build({"el1": profile}, "el1")
	for i in 2: await process_frame
	var ui := menu.mission_load_ui
	ui.prepare("load", ELSaveSlots.KIND_SINGLE)
	menu.show_screen("load_mission")
	for i in 2: await process_frame
	ui.entries.assign([{"name": "a", "path": "user://check_a.sav"}, {"name": "b", "path": "user://check_b.sav"}, {"name": "c", "path": "user://check_c.sav"}])
	ELSaveSlots.remember("el1", "user://check_b.sav")
	check(ui._first_selection() == 1, "el1 #127: the load list opens on the save last used")
	ui._load({"path": "user://check_c.sav", "type": ELSaveSlots.SLOT})
	check(ELSaveSlots.last_used("el1") == "user://check_c.sav" and ui._first_selection() == 2, "el1 #127: loading a save makes it the last used")
	ELSaveSlots.remember("el1", "user://gone.sav")
	check(ui._first_selection() == 0, "el1 #127: with the last used save gone the list opens on the top row")
	menu.queue_free()
	if kept.is_empty(): DirAccess.remove_absolute(ELSaveSlots.LAST_USED)
	else:
		var file := FileAccess.open(ELSaveSlots.LAST_USED, FileAccess.WRITE)
		file.store_string(kept)
	if FileAccess.file_exists(menu.settings_path): DirAccess.remove_absolute(menu.settings_path)
	for i in 2: await process_frame

# --- #77 deck change between local rounds -----------------------------------

func _hot_seat_decks(profile: ELProfile) -> void:
	var shipped := ELDuelPresets.shipped(profile)
	if shipped.is_empty():
		print("SKIP: no shipped el2 preset")
		return
	# A shipped deck with one spell of its faction put in reserve.
	var preset: Dictionary = shipped[0].duplicate(true)
	var spare := ELCatalog.available_cards(profile, String(preset.faction)).filter(func(card: String): return not preset.cards.has(card) and ELDuelCosts.spell_allowed(profile, card, String(preset.faction), int(preset.get("resource_level", 1))))
	if spare.is_empty():
		print("SKIP: no spare el2 spell for a reserve")
		return
	preset.reserve = {spare[0]: 1}
	var pool := [preset]
	var duel_match := ELDuelMatch.new()
	var failure := duel_match.begin(profile, pool, [preset, preset], int(preset.get("resource_level", 1)), 3, ELDuelMatch.RANDOM, 77)
	check(failure.is_empty(), "el2 #77: a three-round match begins (%s)" % failure)
	if not failure.is_empty(): return
	duel_match.hot_seat = true
	duel_match.names = ["Ann", "Bob"]
	var duel := duel_match.start_round(profile)
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.duel_match = duel_match
	check(view._local_deck_sides() == [0, 1], "el2 #77: in hot seat both players may change their deck")
	duel_match.hot_seat = false
	check(view._local_deck_sides() == [0], "el2 #77: against the computer only the player may")
	view.free()
	var link := ELLocalRoundDeck.new(profile, duel, duel_match, 1, "Bob")
	var before: Dictionary = link.round_preset()
	var code: String = before.reserve.keys().filter(func(c: String): return int(before.reserve[c]) > 0)[0]
	var panel := ELNetworkDeck.new()
	root.add_child(panel)
	panel.build(link)
	check(panel.title.ends_with(": Bob"), "el2 #77: the deck panel names the hot-seat player")
	var swapped := link.swap_round_spell(0, code)
	var after: Dictionary = duel_match.presets[1]
	check(swapped and after.cards[0] == code and int(after.reserve.get(before.cards[0], 0)) == int(before.reserve.get(before.cards[0], 0)) + 1, "el2 #77: a reserve spell replaces an active one in the match's preset")
	check(Dictionary(duel_match.presets[0]).cards == before.cards, "el2 #77: the other player's deck is unchanged")
	var next := duel_match.start_round(profile)
	check(next != null and (Array(next.heroes[1].deck) + Array(next.heroes[1].hand)).has(code), "el2 #77: the next round deals the changed deck")
	check(not link.swap_round_spell(0, "no such spell"), "el2 #77: a spell outside the reserve is refused")
	panel.queue_free()
	await process_frame

# --- #61 a declined battle on a custom map ----------------------------------

## A custom map's hero walks into a creature's guard zone, declines the battle
## the map's script starts and must stand outside every hostile zone after.
func _custom_map_decline(profile: ELProfile) -> void:
	var tried := 0
	for entry: Dictionary in ELSingleScenario.catalog(profile):
		if not entry.get("custom", false) or not entry.get("playable", true) or tried >= 8: continue
		tried += 1
		var map := ELAdventureMap.new()
		if not map.load_map(profile, str(entry.id)): continue
		var state := ELAdventureSession.new()
		if not state.start(map, 1, 212, "", 1, false): continue
		var director := ELAdventureDirector.new()
		if not director.build(state): continue
		for frame in 600:
			director.advance(0.05)
			if not director.dialogue.is_empty(): director.acknowledge("OK")
			elif frame > 20 and director.can_move(): break
		var hero := {}
		for item: Dictionary in state.objects.values():
			if hero.is_empty() and item.get("alive", false) and item.get("type") == "hero" and int(item.get("owner", -1)) == 1: hero = item
		var monster := {}
		var start := Vector2i.ZERO
		var enter := Vector2i.ZERO
		for id: int in director.interception.zones:
			var item := state.object(id)
			if hero.is_empty() or not monster.is_empty() or item.get("type") != "monster" or not ELInterception.hostile(state, item, hero): continue
			var at := Vector2i(int(item.x), int(item.y))
			for step: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if not monster.is_empty(): break
				for k in range(1, 7):
					var cell := at + step * k
					if director.grid.passability(cell) < 0: break
					if director.interception.enemies(state, hero, cell).is_empty():
						if k >= 2 and director.grid.passability(cell - step) >= 0:
							monster = item
							start = cell
							enter = cell - step
						break
		if monster.is_empty():
			state.close()
			continue
		hero.x = start.x
		hero.y = start.y
		director.grid.update_actor(hero)
		director.request_move(int(hero.uid), enter)
		for frame in 400:
			director.advance(0.05)
			if not director.dialogue.is_empty(): director.acknowledge("OK")
			if director.encounter != null: break
		if director.encounter == null:
			state.close()
			continue
		director.decline_encounter()
		var here := Vector2i(int(hero.x), int(hero.y))
		check(director.interception.enemies(state, hero, here).is_empty() and not hero.get("intercepted", false), "el2 #61: on %s a declined battle leaves the hero outside the guard zone (%s, entered at %s)" % [str(entry.id).get_file(), here, enter])
		state.close()
		return
	print("SKIP: el2 #61: no custom map gave a guard-zone battle to decline (%d tried)" % tried)

# --- #118 a monster's second texture as the opposing side -------------------

func _textures_of(node: Node, found: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for surface in (mesh.get_surface_count() if mesh != null else 0):
			var material: Material = node.get_active_material(surface)
			var texture: Variant = null
			if material is StandardMaterial3D: texture = material.albedo_texture
			elif material is ShaderMaterial:
				for name: String in ["albedo_texture", "texture_albedo", "albedo", "main_texture"]:
					if material.get_shader_parameter(name) is Texture2D: texture = material.get_shader_parameter(name)
			found[texture.get_rid() if texture is Texture2D else material.get_rid() if material != null else RID()] = true
	for child: Node in node.get_children(): _textures_of(child, found)

func _monster_figure_textures() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	var profile: ELProfile = view.profiles["el1"]
	var row := ELFirstMonsters.definition(profile, "Aviak Assassin", 1)
	if row.is_empty():
		print("SKIP: el1 #118: no Aviak Assassin")
		view.queue_free()
		return
	var hero := {"faction": "Blue", "level": 1, "cards": ELCatalog.available_cards(profile, "Blue").slice(0, 5)}
	var monster := {"faction": str(row.Color), "kind": "monster", "title": "Aviak", "level": int(row.Level), "health": int(row.Health),
		"cards": ELFirstMonsters.book(row).cards, "skills": {}, "monster_name": "Aviak Assassin", "monster_difficulty": 1}
	view._start("el1", {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": [hero, monster]})
	for i in 5: await process_frame
	var id := _summon(view.duel, 0, str(row.Creature))
	for i in 5: await process_frame
	var as_hero := {}
	var as_creature := {}
	_textures_of(view.models[1], as_hero)
	if view.models.has(id): _textures_of(view.models[id], as_creature)
	check(as_creature.size() >= 2 and as_hero.size() == as_creature.size(), "el1 #118: the Aviak Assassin as the opposing side wears as many textures as the creature (%d, %d)" % [as_hero.size(), as_creature.size()])
	view.queue_free()
	for i in 2: await process_frame

# --- #97 a fort guards three tiles ------------------------------------------

func _fort_zone(profile: ELProfile) -> void:
	var campaign := ELCampaign.new()
	if not campaign.load_campaign(profile, "Good"):
		print("SKIP: el1 #97: no Good campaign")
		return
	for scenario: Dictionary in campaign.scenarios:
		var map := ELAdventureMap.new()
		if not map.load_map(profile, str(scenario.file_name)): continue
		var state := ELAdventureSession.new()
		if not state.start(map, 1, 212, "", 1, false): continue
		var director := ELAdventureDirector.new()
		if not director.build(state):
			state.close()
			continue
		var grid := director.grid
		var hero := {}
		var chosen := {}
		var line := Vector2i.ZERO
		for item: Dictionary in state.objects.values():
			if hero.is_empty() and item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == 1: hero = item
		for item: Dictionary in state.objects.values():
			if item.get("type") != "fort" or not chosen.is_empty(): continue
			var at := Vector2i(int(item.x), int(item.y))
			# A straight line of open ground four tiles long beside the fort.
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var open := true
				for k in range(1, 5): if grid.passability(at + step * k, false, true) < 0: open = false
				if open and chosen.is_empty():
					chosen = item
					line = step
		if hero.is_empty() or chosen.is_empty():
			state.close()
			continue
		ELForts.occupy(state, hero, chosen)
		hero.owner = 2
		director.interception.rebuild(state, grid)
		var origin := Vector2i(int(chosen.x), int(chosen.y))
		var zone: Array = director.interception.zones.get(int(hero.uid), {}).get("cells", [])
		check(zone.has(origin + line * 3) and not zone.has(origin + line * 4),
			"el1 #97: a fort on %s guards three tiles straight out and no further (%d tiles in its zone)" % [scenario.file_name, zone.size()])
		state.close()
		return
	print("SKIP: el1 #97: no fort with open ground beside it")

# --- #131 a figure's own glow under path tracing ----------------------------

class GlowStub extends ELCombatEffects:
	var sources: Array = []
	func glow_sources() -> Array: return sources

func _figure_glow_light() -> void:
	var tracer := ELPathTracing.new()
	var stub := GlowStub.new()
	var colour := Vector3(0.8, 0.9, 1.0)
	# A spell's glow and a figure's own glow of the same colour, far apart.
	stub.sources = [[Vector3.ZERO, 0.5, colour, false, 0], [Vector3(100, 0, 0), 0.5, colour, false, 1]]
	tracer._effects = stub
	var data := tracer._effect_lights(10.0)
	var spell := {}
	var figure := {}
	for at in range(0, data.size(), 8):
		var light := {"x": data[at], "colour": Vector3(data[at + 4], data[at + 5], data[at + 6]), "reach": data[at + 7]}
		if absf(light.x) < 1.0: spell = light
		elif absf(light.x - 100.0) < 1.0: figure = light
	check(not spell.is_empty() and not figure.is_empty()
		and figure.colour.length() <= spell.colour.length() * ELGlowLights.ATTACHED_SHARE + 0.001
		and figure.reach <= spell.reach * ELGlowLights.ATTACHED_REACH + 0.001,
		"#131 path tracing: a figure's own glow lights at the raster lamps' share (%s against a spell's %s)" % [figure.get("colour", "-"), spell.get("colour", "-")])
	stub.free()
	tracer.free()

# --- 0.15.0 reports: #136 #140 #141 #142 in a battle ---------------------------

func _wait(count: int) -> void:
	for i in count: await process_frame

## #136 the opposing hero's skills stay out of its tooltip; #142 a right click
## on the arena clears the selected figure; #141 a skip drops the skipped
## sounds still held for a gesture; #140 second game: a fallen hero goes up in
## its colour's death effect, with its sound.
func _battle_reports(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		view.queue_free()
		return
	var profile: ELProfile = view.profiles[edition]
	var players := [{"faction": "Red", "level": 5, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)},
		{"faction": "Red", "level": 5, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)}]
	view._start(edition, {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": players})
	view.demo = false
	await _wait(10)
	var duel: ELDuel = view.duel
	if duel == null:
		check(false, "%s: a battle for the 0.15.0 battle checks starts" % edition)
		view.queue_free()
		return
	var own: int = view._displayed_side()
	# #136 (the first game's hero tooltip lists no skills for either side)
	if edition == "el2":
		var code: String = ELHeroSkills.available(profile)[0]
		var name: String = view._original_text(str(ELHeroSkills.definition(profile, code, 2).get("Name", "")), "")
		for side in 2: duel.heroes[side].skills = {code: 2}
		check(not name.is_empty() and str(view._hero_tip(own)).contains(name), "el2 #136: the player's own hero tooltip lists its skills (%s)" % name)
		check(not str(view._hero_tip(1 - own)).contains(name), "el2 #136: the opposing hero's tooltip hides its skills")
		view.demo = true
		check(str(view._hero_tip(1 - own)).contains(name), "el2 #136: a watched match without a player lists both heroes' skills")
		view.demo = false
	# #142
	view.selection = -1
	view.ability_selection.clear()
	for picked: int in [1 - own, own]:
		view.selected_creature = picked
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_RIGHT
		press.pressed = true
		press.position = Vector2(400, 300)
		view._right_button(press)
		var release: InputEventMouseButton = press.duplicate()
		release.pressed = false
		view._right_button(release)
		check(view.selected_creature == -1, "%s #142: a right click on the arena clears the selected %s hero" % [edition, "opposing" if picked != own else "own"])
	# #141
	var audio: ELBattleAudio = view.battle_audio
	var sound := ""
	for effect: String in ["RedDeath", "BlackDeath", "GreenDeath", "BlueDeath", "RedDamage"]:
		if sound.is_empty(): sound = audio.effect_sound(effect)
	if sound.is_empty():
		print("SKIP: %s #141: no effect sound to hold" % edition)
	else:
		audio.played.clear()
		audio.hold(0.6)
		audio.play(sound)
		view._cast_until = view.elapsed + 5.0
		view._skip_battle_presentation()
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 1200: await process_frame
		check(not audio.played.has(sound), "%s #141: a sound held for a skipped gesture does not play after the skip" % edition)
		check(audio.play(sound) and audio.played.has(sound), "%s #141: sounds play again after the skip" % edition)
	# #140
	if edition == "el2":
		audio.played.clear()
		var death := audio.effect_sound("RedDeath")
		var before: int = view.effects.active_count()
		view._show_ending({"kind": "victory", "side": own})
		check(view.effects.active_count() > before and (death.is_empty() or audio.played.has(death)), "el2 #140: a fallen hero goes up in its colour's death effect (RedDeath) with its sound")
	view.queue_free()
	await _wait(2)

# --- 0.15.0 reports: #137 #138 #139 on the map ---------------------------------

func _hostile_monster(state: ELAdventureSession, hero: Dictionary) -> Dictionary:
	var best := {}
	var best_distance := INF
	for item: Dictionary in state.objects.values():
		if item.get("type") != "monster" or not item.get("alive", false) or not item.get("visible", true) or int(item.get("x", -1)) < 0: continue
		if not state.hostile(hero, item): continue
		var distance := Vector2(float(item.x), float(item.y)).distance_to(Vector2(float(hero.x), float(hero.y)))
		if distance > 0.5 and distance < best_distance:
			best = item
			best_distance = distance
	return best

## #138: the hero turned away from the creature turns to face it as the
## battle is offered.
func _faces(map: ELAdventureView, hero: Dictionary, monster: Dictionary, label: String) -> void:
	var model: Node3D = map.world.actors.get(int(hero.uid))
	if model == null:
		print("SKIP: %s #138: the hero has no figure" % label)
		map.director._begin_encounter(hero, monster)
		return
	var toward := Vector2(float(monster.x) - float(hero.x), float(monster.y) - float(hero.y))
	var facing := atan2(toward.x, -toward.y)
	model.rotation.y = facing + PI
	map.director._begin_encounter(hero, monster)
	await _wait(3)
	check(absf(angle_difference(model.rotation.y, facing)) < 0.01, "%s #138: the hero turns to face the creature it fights" % label)

func _map_reports(profiles: Dictionary) -> void:
	if profiles.has("el1"): await _first_prompt(profiles.el1)
	if profiles.has("el2"): await _second_prompt()

## #137 first game: the original orders show the wide strip alone (no
## decline); free movement shows the check mark and the cross.
func _first_prompt(profile: ELProfile) -> void:
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	var saves := _backup(ELSaveSlots.folder("el1"))
	var settings := ELSettings.new()
	settings.use_edition("el1")
	settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(settings).persist = false
	var map := ELAdventureView.new()
	root.add_child(map)
	var built := map.build(profile, row, settings, 1)
	_restore(ELSaveSlots.folder("el1"), saves)
	if not built:
		check(false, "el1 #137: the first mission map builds: " + map.error)
		map.queue_free()
		return
	await _wait(5)
	if map.tutorial_panel != null and map.tutorial_panel.visible: map.tutorial_panel.close()
	var state := map.state
	var hero := {}
	for item: Dictionary in state.objects.values():
		if hero.is_empty() and item.get("alive", false) and item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player: hero = item
	var monster := _hostile_monster(state, hero) if not hero.is_empty() else {}
	if monster.is_empty():
		print("SKIP: el1 #137: no hero and creature on the first mission")
		map.queue_free()
		return
	var hud: ELAdventureHud = map.hud
	for free: bool in [true, false]:
		map.director.free_movement = free
		if free: await _faces(map, hero, monster, "el1")
		else: map.director._begin_encounter(hero, monster)
		await _wait(3)
		if free:
			check(hud.precombat.visible and hud.accept_button.visible and hud.cancel_button.visible and not hud.begin_button.visible, "el1 #137: with free movement the panel shows the check mark and the cross, not the wide strip")
		else:
			check(hud.precombat.visible and hud.begin_button.visible and not hud.accept_button.visible and not hud.cancel_button.visible, "el1 #137: with the original orders the panel shows the wide strip alone")
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.pressed = true
			map._unhandled_input(esc)
			await _wait(2)
			check(map.director.encounter != null and hud.precombat.visible, "el1 #137: with the original orders Esc does not decline the battle")
		map.director.decline_encounter()
		map.pending_encounter = []
		hud.hide_precombat()
		await _wait(2)
	map.queue_free()
	await _wait(2)

## #137 #138 #139 second game, chapter 11.
func _second_prompt() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await _wait(3)
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(view.profiles.el2):
		if str(found.id).to_lower().ends_with("e2mission11"): entry = found
	var saves := _backup(ELSaveSlots.folder("el2"))
	await view._begin_campaign("el2", ELSingleScenario.scenario(entry), 1)
	var map: ELAdventureView = view.campaign_view
	if map == null:
		check(false, "el2: chapter 11 opens for the map checks")
		_restore(ELSaveSlots.folder("el2"), saves)
		view.queue_free()
		return
	var state := map.state
	var director := map.director
	for i in 40:
		if director.dialogue.is_empty(): break
		director.acknowledge("OK")
		await _wait(3)
	ELFog.reveal_for_console(state, 1, true)
	ELFog.refresh(state)
	var hero := state.object(state.main_hero)
	var monster := _hostile_monster(state, hero)
	if monster.is_empty():
		print("SKIP: el2 #137 #138 #139: no creature to fight on chapter 11")
	else:
		await _faces(map, hero, monster, "el2")
		var panel := map.second_precombat
		check(panel != null and panel.visible and panel.begin_button.visible and panel.cancel_button.visible and not panel.decoration.visible,
			"el2 #137: the pre-battle panel shows the check mark and the cross, without the first game's wide strip")
		# #139 the defeat picture covers the map from its first frame.
		map._open_lose_battle()
		var lose := map.lose_battle
		var black: ColorRect = lose.get_child(0) if lose != null and lose.get_child_count() > 0 else null
		check(lose != null and lose.modulate.a > 0.99 and black != null and black.modulate.a > 0.99, "el2 #139: the defeat picture's screen is black from its first frame, so the map does not show first")
		if lose != null:
			lose._process(1.1)
			lose.dismiss()
			lose._process(1.1)
			check(map.lose_battle == null and is_instance_valid(lose) and black.modulate.a > 0.99, "el2 #139: after the click the picture fades to black and the map takes over")
			lose._process(0.5)
			check(black.modulate.a < 0.99 and black.modulate.a > 0.01, "el2 #139: the map fades in from the black")
			lose._process(0.6)
		# #139 surrender: the hero falls before the map returns.
		if map.pending_encounter.is_empty() or director.encounter == null:
			print("SKIP: el2 #139: no battle to surrender")
		else:
			map.begin_encounter()
			await _wait(10)
			if view._campaign_battle() == null or view.duel != view._campaign_battle():
				print("SKIP: el2 #139: the battle did not open")
			else:
				var side: int = view._battle_player_side(view.duel)
				view._surrender_encounter()
				await _wait(2)
				check(view.duel.phase == ELDuel.Phase.FINISHED and not map.visible and view.models[side].clip == "udeath" and not view.ending_over(),
					"el2 #139: a surrendered battle first shows the hero's death on the arena")
				var start := Time.get_ticks_msec()
				while director.encounter != null and Time.get_ticks_msec() - start < 20000: await process_frame
				check(director.encounter == null and map.visible, "el2 #139: once the hero has fallen the map returns")
	_restore(ELSaveSlots.folder("el2"), saves)
	view.queue_free()
	await _wait(3)

# --- #152 Ethereal Attack -----------------------------------------------------

## The original never reads ETAT or ETDF: castle damage is the hero's level
## (one and a half times under Castle Bane) whatever skills it has. The skill
## texts promise more, so the remake says they have no effect.
func _castle_skills(profile: ELProfile) -> void:
	for code: String in ["ETAT", "ETDF"]:
		for rank in 3:
			var row := ELHeroSkills.definition(profile, code, rank)
			var key := str(row.get("Description", ""))
			var shown := profile.text(key)
			check(not row.is_empty() and shown != key and (shown.ends_with("(This skill has no effect.)") or shown.ends_with("(Этот навык ничего не делает.)")), "el1 #152: %s %d says it has no effect: %s" % [code, rank + 1, shown])
	check(ELTextFixes.apply("el2", "SkTtETAT3", "Hero's damage to enemy castle +5") == "Hero's damage to enemy castle +5", "el1 #152: the second game's texts are left alone")
	var hero := {"level": 5, "skills": {"ETAT": 2, "ETDF": 2}}
	check(ELFirstScenario.hero_value(hero) == 5, "el1 #152: a level 5 hero with Ethereal Attack III still deals 5 to a castle, as in the original")

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
