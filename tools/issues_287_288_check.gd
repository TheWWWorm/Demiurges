extends SceneTree
## Player reports #287 and #288:
## - #288 (both games): the wall masteries (Wrath of Stones RWSW, Wrath of
##   Winds UWAW) only set the blocked attacker's destroy flag, so it dies after
##   the fight from lethal damage equal to its remaining health; a pain link on
##   it costs its hero that much, not a fixed million. The expected losses are
##   the original games' (measured on both): BRMC blocked by
##   WLBR loses its hero 3 (2 when already wounded by 1), GBAT blocked by WLAR
##   4 (3), nothing without the link. The compiled engine must foresee the same.
## - #287 (second game deck editor): a spell dragged from the available spells
##   shows one picture under the pointer, not the click pick on the cursor as
##   well, and still lands where it is dropped.
##
##   godot --headless --path game --script ../tools/issues_287_288_check.gd
##
## Needs the original games' files (user://profiles.json). Nothing is saved.
const Fixtures := preload("res://../tools/duel_fixtures.gd")

var fails := 0
var host: Control

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: fails += 1

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary:
		print("SKIP: no original game files configured (user://profiles.json)")
		quit(0)
		return
	var mounted := {}
	for edition: String in ["el1", "el2"]:
		var profile := ELProfile.new()
		if paths.has(edition) and profile.mount(edition, str(paths[edition])): mounted[edition] = profile
		else: print("SKIP: %s files are not available" % edition)
	for edition: String in mounted: _walls(mounted[edition])
	if mounted.has("el2"): await _deck_drag(mounted)
	print("ISSUES 287/288: %d failure(s)" % fails)
	quit(fails)

# --- #288: wall masteries ---------------------------------------------------

func _walls(profile: ELProfile) -> void:
	var cases := [["RWSW", "WLBR", "BRMC", 3], ["UWAW", "WLAR", "GBAT", 4]]
	for row: Array in cases:
		var spec: String = row[0]
		var wall: String = row[1]
		var attacker: String = row[2]
		if not profile.table("HeroesSpecs").has(spec):
			print("SKIP: %s has no %s" % [profile.id, spec])
			continue
		var health := int(profile.table("CombatCreatures")[attacker].Toughness)
		check(health == int(row[3]), "%s: %s has the original's %d health" % [profile.id, attacker, int(row[3])])
		for linked: bool in [false, true]:
			for wound in 2:
				var expected := 20 - ((health - wound) if linked else 0)
				var label := "%s %s: %s blocked by %s%s%s" % [profile.id, spec, attacker, wall, " with a pain link" if linked else "", ", wounded by 1" if wound else ""]
				_wall_case(profile, label, spec, wall, attacker, linked, wound, expected)

func _wall_case(profile: ELProfile, label: String, spec: String, wall: String, attacker: String, linked: bool, wound: int, expected: int) -> void:
	var told := {"heroes": [{"health": 20, "mana": 0, "maximum": 20}, {"health": 20, "mana": 0, "maximum": 20, "spec": spec, "spec_level": 20, "luck": 3}],
		"creatures": [{"card": attacker, "owner": 0, "damage": wound, "enchantments": ["PALN"] if linked else []}, {"card": wall, "owner": 1}]}
	var duel := Fixtures.build(profile, told)
	var start := Fixtures.build(profile, told)
	if duel == null or start == null:
		check(false, label + ": the position restores")
		return
	# The odds as a reading counts on them (level 20 and luck: the mastery holds).
	for d: ELDuel in [duel, start]:
		d.expected_specs = true
		d.fair_specs = true
	var damages: Array[int] = []
	duel.event.connect(func(data: Dictionary): if data.kind == "damage" and int(data.target) == 2: damages.append(int(data.amount)))
	var ok := duel.toggle_attack(2) and duel.end_phase() and duel.assign_block(3, 2) and duel.end_phase()
	check(ok, label + ": the attack and block are played")
	check(not duel.creatures.has(2), label + ": the attacker is destroyed")
	check(int(duel.heroes[0].health) == expected, label + ": its hero has %d health (%d)" % [expected, int(duel.heroes[0].health)])
	check(damages.all(func(amount: int) -> bool: return amount <= 20), label + ": no hit beyond its health (%s)" % str(damages))
	if not ELCombatBrain.available:
		print("SKIP: the compiled engine is not loaded")
		return
	var commands := [[1, 0, 0, 0], [0, 0, 0, 0], [2, 1, 0, 0], [0, 0, 0, 0]]
	var model := ELCombatBrain.fight(Fixtures.context(profile, 0), start, 4, commands)
	check(not model.is_empty() and int(model.health[0]) == expected and int(model.units.get(2, 0)) == -1,
		label + ": the compiled engine foresees the same (%s)" % (str(model.health) if not model.is_empty() else "no answer"))

# --- #287: second game deck editor drag -----------------------------------

func _deck_drag(mounted: Dictionary) -> void:
	root.size = Vector2i(1280, 960)
	host = Control.new()
	host.size = Vector2(1280, 960)
	root.add_child(host)
	var menu := ELFrontMenu.new()
	host.add_child(menu)
	menu.size = host.size
	if not menu.build(mounted, "el2"):
		print("SKIP: el2 has no front-end art")
		return
	await frames(2)
	var duel := menu.duel_ui
	duel.refresh_pool()
	var preset := ELDuelPresets.blank("Green", 1)
	preset.level = 10
	preset.resource_level = 3
	duel.open_editor(preset, "")
	duel.select_tab(0)
	await frames(2)
	var list := duel.right_list
	check(list != null and not duel.right_items.is_empty(), "el2 #287: the available spells are listed")
	if list == null or duel.right_items.is_empty(): return
	var cursor := ELCursorDriver.instance()
	var card: String = duel.right_items[0].value
	# The original's click pick still carries the card on the cursor.
	await click(list, list.get_item_rect(0).get_center())
	check(cursor._carry_source == menu.profile.card_icon(card), "el2 #287: a click on an available spell carries it on the cursor")
	duel.cancel_carried()
	await frames(1)
	check(cursor._carry_source == null, "el2 #287: a right click puts it back")
	# A drag: the press picks the spell, the travel turns it into a drag.
	var start := list.get_global_transform_with_canvas() * list.get_item_rect(0).get_center()
	var end := duel.book_view.get_global_transform_with_canvas() * Vector2(10, 10)
	root.push_input(motion(start, false), true)
	await frames(1)
	root.push_input(button(start, true), true)
	await frames(1)
	var last := start
	for step in 6:
		var event := motion(start.lerp(end, (step + 1) / 6.0))
		event.relative = event.position - last
		last = event.position
		root.push_input(event, true)
		await frames(1)
	check(bool(duel.carry.get("moving", false)), "el2 #287: the spell is being dragged")
	check(cursor._carry_source == null and cursor.carry_image == null, "el2 #287: while dragged the cursor carries no second picture of it")
	root.push_input(button(end, false), true)
	await frames(2)
	check(duel.editor_preset().cards == [card], "el2 #287: the dragged spell is added to the deck")
	check(cursor._carry_source == null and duel.carry.is_empty(), "el2 #287: nothing stays carried after the drop")
	menu.queue_free()
	host.queue_free()
	await frames(3)

func button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = at
	event.global_position = at
	return event

func motion(at: Vector2, held := true) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	event.position = at
	event.global_position = at
	return event

func click(control: Control, at: Vector2) -> void:
	var point := control.get_global_transform_with_canvas() * at
	root.push_input(motion(point, false), true)
	await frames(1)
	root.push_input(button(point, true), true)
	await frames(1)
	root.push_input(button(point, false), true)
	await create_timer(0.6).timeout
