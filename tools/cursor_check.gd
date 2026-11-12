extends SceneTree
## Check of the battle cursor and the hand list sounds (both games):
## - ELCursors.combat: while a spell or ability is being aimed, the spell
##   cursor over a valid target, the default cursor over an invalid target or
##   empty ground, the default cursor again once the aiming ends;
## - ELCursors.combat_pending turns the hand pick / rail ability into the
##   aiming the rule reads;
## - ELCursorDriver shows the requested cursor and uploads a picture only when
##   the cursor or its 125 ms frame changes;
## - the hand list sounds (card turn, error) exist in each game's archive.
##
##   godot --headless --path game --script ../tools/cursor_check.gd
##
## Run with a window and `-- --view=<folder>` it also opens the battle screen
## of each game, picks a targeted spell from the hand, sends pointer moves
## over the enemy hero, an invalid target and empty ground, logs the cursor
## asked for and saves frames with the cursor picture drawn at the pointer
## (screenshots do not hold the hardware cursor). Needs the original games'
## files (user://profiles.json); without them the game parts are skipped.
## Settings are never written by the checks themselves.

var failures: Array[String] = []
var view_folder := ""
var log_lines: PackedStringArray = []

func check(ok: bool, what: String) -> void:
	var line := ("PASS: " if ok else "FAIL: ") + what
	print(line)
	log_lines.append(line)
	if not ok: failures.append(what)

func note(text: String) -> void:
	print("  " + text)
	log_lines.append("  " + text)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view="): view_folder = arg.trim_prefix("--view=")
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary:
		print("SKIP: no original game files configured (user://profiles.json)")
		paths = {}
	var mounted := {}
	for edition: String in ["el1", "el2"]:
		if not paths.has(edition): continue
		var profile := ELProfile.new()
		if not profile.mount(edition, str(paths[edition])):
			print("SKIP: %s files could not be mounted" % edition)
			continue
		mounted[edition] = profile
		_rule(profile)
		await _driver(profile)
		_sounds(profile)
	if not view_folder.is_empty() and DisplayServer.get_name() != "headless":
		for edition: String in mounted: await _view(edition)
		DirAccess.make_dir_recursive_absolute(view_folder)
		var file := FileAccess.open(view_folder.path_join("cursor_check.log"), FileAccess.WRITE)
		if file != null: file.store_string("\n".join(log_lines) + "\n")
	print("CURSOR CHECK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## A spell of the profile whose rule targets `kind` ("any", "creature", ...).
static func spell_for(profile: ELProfile, kind: String) -> String:
	var codes: Array = profile.table("CombatSpells").keys()
	codes.sort()
	for code: String in codes:
		var rule := ELCatalog.rule(profile, code)
		if rule.get("target") == kind and rule.get("effect") in ["damage", "direct_damage", "zap"]: return code
	for code: String in codes:
		if ELCatalog.rule(profile, code).get("target") == kind: return code
	return ""

func _duel(profile: ELProfile) -> ELDuel:
	var duel := ELDuel.new()
	if not duel.start(profile, 212): return null
	return duel

func _rule(profile: ELProfile) -> void:
	var tag := profile.id + ": "
	var duel := _duel(profile)
	check(duel != null, tag + "a battle starts")
	if duel == null: return
	var any := spell_for(profile, "any")
	var creature_only := spell_for(profile, "creature")
	check(not any.is_empty() and not creature_only.is_empty(), tag + "a spell on any character (%s) and a creature-only spell (%s)" % [any, creature_only])
	var side := duel.active_side()
	var enemy := 1 - side
	duel.heroes[side].hand = [any, creature_only]
	var aiming := ELCursors.combat_pending(duel, 0, {})
	check(aiming == {"card": any}, tag + "the picked hand card is the aiming")
	check(ELCursors.combat(duel, enemy, aiming, -1) == "spell", tag + "aiming: the spell cursor over a valid target (enemy hero)")
	check(ELCursors.combat(duel, side, aiming, -1) == "spell", tag + "aiming: the spell cursor over the own hero (valid for a spell on any character)")
	check(ELCursors.combat(duel, -1, aiming, -1) == "default", tag + "aiming: the default cursor over empty ground")
	check(ELCursors.combat(duel, 999, aiming, -1) == "default", tag + "aiming: the default cursor over a character that is gone")
	var narrow := ELCursors.combat_pending(duel, 1, {})
	check(ELCursors.combat(duel, enemy, narrow, -1) == "default", tag + "aiming a creature-only spell: the default cursor over a hero (invalid target)")
	check(ELCursors.combat_pending(duel, -1, {}).is_empty(), tag + "no pick, no aiming")
	check(ELCursors.combat(duel, enemy, {}, -1) == "default", tag + "aiming ended: the default cursor again")
	var ability := ELCursors.combat_pending(duel, -1, {"source": side, "key": "check", "target": "hero"})
	check(ability.has("ability") and ELCursors.combat(duel, enemy, ability, -1) == "spell", tag + "aiming a hero ability: the spell cursor over a hero")
	check(ELCursors.combat(duel, -1, ability, -1) == "default", tag + "aiming a hero ability: the default cursor over empty ground")
	var creature_ability := ELCursors.combat_pending(duel, -1, {"source": side, "key": "check", "target": "creature"})
	check(ELCursors.combat(duel, enemy, creature_ability, -1) == "default", tag + "aiming a creature ability: the default cursor over a hero")

func _driver(profile: ELProfile) -> void:
	var tag := profile.id + ": "
	for name: String in ["default", "spell", "attack"]:
		var entry := ELCursors.cursor(profile, name)
		check(not entry.is_empty() and entry.frames.size() > 1, tag + "cursor_%s has its animation (%d frames)" % [name, entry.get("frames", []).size()])
	ELCursorDriver.request(profile, "default")
	await frames(2)
	var driver := ELCursorDriver.instance()
	ELCursorDriver.request(profile, "spell")
	check(ELCursorDriver.current_name() == "spell" and driver.shown.get("name") == "spell", tag + "the driver shows the spell cursor")
	var before := driver.uploads
	var started := Time.get_ticks_msec()
	await frames(40)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var sent := driver.uploads - before
	check(sent >= 1 and sent <= int(seconds / ELCursors.FRAME_TIME) + 2, tag + "the spell cursor animates with one picture per 125 ms frame (%d pictures in %.2f s over 40 drawn frames)" % [sent, seconds])
	ELCursorDriver.request(profile, "default")
	check(driver.shown.get("name") == "default", tag + "the default cursor comes back")

func _sounds(profile: ELProfile) -> void:
	var tag := profile.id + ": "
	check(ELAudio.sound(profile, ELCombatStrip.SOUND) != null, tag + "the hand list pick sound (%s) is in the archive" % ELCombatStrip.SOUND)
	check(ELAudio.sound(profile, ELUiSounds.ERROR) != null, tag + "the greyed item sound (%s) is in the archive" % ELUiSounds.ERROR)

# --- Battle screen (with a window) --------------------------------------------

func _view(edition: String) -> void:
	var tag := edition + " screen: "
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(5)
	if not view.profiles.has(edition):
		check(false, tag + "the game is configured")
		view.queue_free()
		return
	view._start(edition)
	if view.setup_panel != null: view.setup_panel.hide()
	var started := Time.get_ticks_msec()
	while not view._human_turn() and Time.get_ticks_msec() - started < 30000:
		await process_frame
	await frames(30)
	check(view._human_turn(), tag + "the battle waits for the player")
	if not view._human_turn():
		view.queue_free()
		return
	var duel: ELDuel = view.duel
	var side := duel.active_side()
	var enemy := 1 - side
	# An enemy creature on the field, so a creature-only spell has a target.
	var summons: Array = view.profile.table("CombatCreatures").keys()
	summons.sort()
	for code: String in summons:
		if ELCatalog.rule(view.profile, code).get("effect") == "summon":
			duel._summon(enemy, code)
			break
	duel.heroes[side].mana = 99
	var any := _castable(duel, "any", enemy)
	var creature_only := _castable(duel, "creature", -1)
	duel.heroes[side].hand = [any, creature_only]
	duel.heroes[side].hand_slots = [-1, -1]
	note(tag + "hand: %s (any character), %s (creatures only)" % [any, creature_only])
	view._refresh()
	await frames(60)
	var hero_point := _point_on(view, enemy)
	check(hero_point.x >= 0, tag + "a pointer position on the enemy hero")
	var ground := _empty_point(view)
	check(ground.x >= 0, tag + "a pointer position on empty ground")
	# Pick the spell from the hand: the card-turn sound, then aiming.
	var button := _hand_button(view, 0)
	check(button != null and not button.disabled, tag + "the targeted spell %s is in the hand and can be picked" % any)
	if button == null: return
	var heard := ELUiSounds.history.size()
	button.pressed.emit()
	check(view.selection == 0, tag + "picking it starts the aiming")
	check(ELUiSounds.history.size() > heard and ELUiSounds.history[-1] == ELCombatStrip.SOUND, tag + "picking it plays %s" % ELCombatStrip.SOUND)
	await _hover(view, hero_point)
	check(view.combat_hover == enemy and ELCursorDriver.current_name() == "spell", tag + "aiming over the enemy hero: spell cursor (asked %s)" % ELCursorDriver.current_name())
	await _capture(view, hero_point, "%s-1-aim-valid.png" % edition)
	await _hover(view, ground)
	check(ELCursorDriver.current_name() == "default", tag + "aiming over empty ground: default cursor (asked %s)" % ELCursorDriver.current_name())
	await _capture(view, ground, "%s-2-aim-empty.png" % edition)
	# The creature-only spell over the hero: an invalid target.
	_hand_button(view, 0).pressed.emit()
	check(view.selection == -1 and ELUiSounds.history[-1] == ELCombatStrip.SOUND, tag + "picking the card again ends the aiming with the same sound")
	var narrow := _hand_button(view, 1)
	if narrow != null and not narrow.disabled:
		narrow.pressed.emit()
		await _hover(view, hero_point)
		check(view.selection == 1 and ELCursorDriver.current_name() == "default", tag + "aiming %s (creatures only) over a hero: default cursor (asked %s)" % [creature_only, ELCursorDriver.current_name()])
		await _capture(view, hero_point, "%s-3-aim-invalid.png" % edition)
		var creature := -1
		for id: int in view.duel.creatures:
			if view.duel.creatures[id].owner == enemy: creature = id
		var creature_point := _point_on(view, creature)
		if creature_point.x >= 0:
			await _hover(view, creature_point)
			check(view.combat_hover == creature and ELCursorDriver.current_name() == "spell", tag + "aiming %s over an enemy creature: spell cursor (asked %s)" % [creature_only, ELCursorDriver.current_name()])
			await _capture(view, creature_point, "%s-3b-aim-creature.png" % edition)
		else:
			check(false, tag + "a pointer position on the enemy creature")
	else:
		check(false, tag + "the creature-only spell can be picked")
	# Esc ends the aiming: back to the default cursor over the same hero.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	await frames(3)
	await _hover(view, hero_point)
	check(view.selection == -1 and ELCursorDriver.current_name() == "default", tag + "after Esc over the hero: default cursor (asked %s)" % ELCursorDriver.current_name())
	await _capture(view, hero_point, "%s-4-aim-ended.png" % edition)
	# A greyed hand card plays the error sound.
	var grey := _hand_button(view, 0)
	grey.disabled = true
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	grey.gui_input.emit(press)
	check(ELUiSounds.history[-1] == ELUiSounds.ERROR, tag + "a greyed hand card plays %s" % ELUiSounds.ERROR)
	note(tag + "interface sounds, newest last: " + ", ".join(ELUiSounds.history.slice(-6)))
	view.queue_free()
	await frames(5)

## A spell with target `kind` the active hero can cast now (valid on
## `target` when it is >= 0), as a generated card (no spellbook charge).
func _castable(duel: ELDuel, kind: String, target: int) -> String:
	var side := duel.active_side()
	var codes: Array = duel.profile.table("CombatSpells").keys()
	codes.sort()
	for code: String in codes:
		if ELCatalog.rule(duel.profile, code).get("target") != kind or duel.variable_power(code): continue
		duel.heroes[side].hand = [code]
		duel.heroes[side].hand_slots = [-1]
		if duel.can_cast_from_hand(0) and (target < 0 or duel._target_error(code, target).is_empty()): return code
	return ""

func _hand_button(view: Node, index: int) -> TextureButton:
	for child: Node in view.hand.get_children():
		if child is TextureButton and int(child.get_meta("hand_index", -1)) == index: return child
	return null

## A window position over character `id`, found the way the screen picks.
func _point_on(view: Node, id: int) -> Vector2:
	if not view.models.has(id): return Vector2(-1, -1)
	var model: Node3D = view.models[id]
	for height: float in [1.0, 1.4, 0.7, 1.8, 0.4, 2.2]:
		var point: Vector2 = view.camera.unproject_position(model.global_position + Vector3(0, height, 0))
		if view._character_at(point) == id and not _over_panel(point): return point
	return Vector2(-1, -1)

func _empty_point(view: Node) -> Vector2:
	var size := root.get_visible_rect().size
	for y: float in [0.35, 0.3, 0.45, 0.25, 0.55]:
		for x: float in [0.5, 0.3, 0.7, 0.2, 0.8]:
			var point := Vector2(size.x * x, size.y * y)
			if view._character_at(point) == -1 and not _over_panel(point): return point
	return Vector2(-1, -1)

func _over_panel(point: Vector2) -> bool:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	return root.gui_get_hovered_control() != null and root.gui_get_hovered_control().mouse_filter == Control.MOUSE_FILTER_STOP

## Sends a pointer move (no real mouse movement) and lets the cursor update.
func _hover(view: Node, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await frames(4)
	note("%s hover %s -> character %d, cursor %s" % [view.profile.id, point, view.combat_hover, ELCursorDriver.current_name()])

## The window picture with the cursor picture the driver sent drawn at the
## pointer (its hotspot on the point).
func _capture(view: Node, point: Vector2, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var driver := ELCursorDriver.instance()
	var picture: Texture2D = driver.shown.get("image")
	if picture != null:
		var cursor := picture.get_image()
		cursor.convert(image.get_format())
		# Window pixels: the pointer goes through the content scale; the
		# hardware cursor itself is never scaled.
		var scale := Vector2(image.get_size()) / root.get_visible_rect().size
		var at := Vector2i(point * scale - Vector2(driver.shown.get("point", Vector2.ZERO)))
		image.blend_rect(cursor, Rect2i(Vector2i.ZERO, cursor.get_size()), at)
	DirAccess.make_dir_recursive_absolute(view_folder)
	var path := view_folder.path_join(file_name)
	image.save_png(path)
	note("saved %s (cursor %s frame %d)" % [path, driver.shown.get("name", "system"), int(driver.shown.get("frame", -1))])
