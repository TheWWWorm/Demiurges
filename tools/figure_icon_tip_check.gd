extends SceneTree
## Headless check of the state and ability icons over battle figures:
## - a creature given an ability by an enchantment shows that ability's icon;
## - the icon's screen square (ELCombatSymbols.icon_rects) sits in the drawn
##   icon row, and ELCombatSymbols.icon_at finds it there;
## - a right click on the icon (no drag) opens the battle tooltip with the
##   icon's own caption and description (T_CREATURE_ICON_<n>C, T_CREATURE_ICON_<n>),
##   not the creature's tooltip, and does not preview the creature's strip;
## - a right click on the creature's body still names the creature and
##   previews its strip;
## - a touch hold on the icon shows the same tooltip.
## Runs for each game whose files are configured.
##
##   godot --headless --path game --script ../tools/figure_icon_tip_check.gd
##
## Windowed with `-- --shots=<folder>` it saves each game's battle with the
## touch-held icon tooltip open (the mouse clicks are left to headless runs).
##
## Needs the original games' files (user://profiles.json, as set up by the
## game); without them a game is skipped. Settings are never written.

## Enchantments that grant a flag with an icon, tried in order.
const GRANTS := {"CLFR": "UB", "SPWR": "Restless", "AILK": "Lifetap", "CMBN": "Trample", "SGHT": "Disenchant", "PRGD": "Restless", "ALST": "FS"}
## Icon bit of each flag (T_CREATURE_ICON_<bit+1>).
const BITS := {"Restless": 6, "Lifetap": 7, "Trample": 5, "Disenchant": 10, "UB": 13, "FS": 4}

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# A common window size, so the battle panel and the glyphs have their
	# usual proportions (the headless window is otherwise 64 px square).
	root.size = Vector2i(1440, 900)
	await process_frame
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		await _edition(edition)
	print("FIGURE ICON TIPS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _edition(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		print("SKIP: %s files could not be mounted" % edition)
		view.queue_free()
		await process_frame
		return
	view._start(edition)
	await _idle(view)
	var duel: ELDuel = view.duel
	var side := duel.active_side()
	var creature := await _summoned(view, side)
	check(creature >= 2, "%s: a creature stands on the field" % edition)
	if creature < 2:
		await _close(view)
		return
	# An enchantment granting an ability with an icon.
	var bit := -1
	var card := ""
	for candidate: String in GRANTS:
		if not view.profile.table("CombatSpells").has(candidate): continue
		duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 40)
		if duel.cast_free(side, candidate, [creature], false):
			card = candidate
			bit = int(BITS[GRANTS[candidate]])
			break
	check(bit >= 0, "%s: an ability enchantment (%s) is cast on the creature" % [edition, card])
	if bit < 0:
		await _close(view)
		return
	await _idle(view)
	for i in 5: await process_frame
	var code: int = ELCombatSymbols.ICON_CODES[bit]
	check(view.creature_icons(creature).has(code), "%s: %s shows icon %d (T_CREATURE_ICON_%02d)" % [edition, card, code, bit + 1])
	var symbols: ELCombatSymbols = view.symbols
	var figure := {}
	for entry: Dictionary in symbols.figures:
		if int(entry.id) == creature: figure = entry
	check(not figure.is_empty() and (figure.icons as Array).has(code), "%s: the figure's icon row carries the icon" % edition)
	var rect := Rect2()
	for entry: Dictionary in symbols.icon_rects(figure):
		if int(entry.bit) == bit: rect = entry.rect
	var row := symbols.figure_rect(figure)
	check(rect.size.x > 0.0 and row.grow(0.01).encloses(rect), "%s: the icon's square %s lies in the figure's readout %s" % [edition, rect, row])
	var point := rect.get_center()
	var found := symbols.icon_at(point)
	check(int(found.get("id", -1)) == creature and int(found.get("bit", -1)) == bit, "%s: icon_at finds the icon at its square's centre" % edition)
	var outside := symbols.icon_at(rect.position - Vector2(40, 40))
	check(int(outside.get("id", -1)) != creature or int(outside.get("bit", -1)) != bit, "%s: the icon is not found well outside its square" % edition)
	var caption: String = view.profile.text("T_CREATURE_ICON_%02dC" % (bit + 1))
	var body: String = view.profile.text("T_CREATURE_ICON_%02d" % (bit + 1))
	print("  %s caption %s, description %s" % [edition, JSON.stringify(caption), JSON.stringify(body)])
	var expected: String = view.icon_tip_text(bit)
	check(expected.begins_with(caption.strip_edges()) and expected.ends_with(body.strip_edges()) and not caption.strip_edges().is_empty(), "%s: the icon's text is its caption then its description" % edition)
	# A right click without a drag on the icon. In a window the pointer is
	# the real cursor, so only a headless run feeds it.
	var tip: ELCombatTooltip = view.combat_tip
	if DisplayServer.get_name() != "headless":
		print("SKIP: %s mouse clicks (windowed run; the tooltip follows the real cursor)" % edition)
	else:
		_mouse_move(point)
		await process_frame
		_mouse_button(point, true)
		for i in 4: await process_frame
		check(tip.panel.visible and _shown(tip) == expected, "%s: right button on the icon shows its tooltip (%s)" % [edition, JSON.stringify(_shown(tip))])
		check(int(view.strip_preview) == -1 and not view.orbiting, "%s: the right click on the icon does not preview the creature or turn the camera" % edition)
		_mouse_button(point, false)
		for i in 3: await process_frame
		if edition == "el2":
			check(tip.panel.visible and _shown(tip) == expected, "el2: the icon's tooltip stays while the pointer rests on it")
		else:
			check(not tip.panel.visible, "el1: the tooltip shows only while the right button is held")
		# The creature's body (off its icons) still names the creature.
		var body_point := _body_point(view, creature)
		check(body_point.x > -1000.0, "%s: a point on the creature's body is found" % edition)
		if body_point.x > -1000.0:
			_mouse_move(body_point)
			await process_frame
			_mouse_button(body_point, true)
			for i in 4: await process_frame
			var creature_text := _shown(tip)
			check(tip.panel.visible and creature_text.begins_with(duel.card_name(str(duel.creatures[creature].card))), "%s: right button on the body shows the creature (%s)" % [edition, JSON.stringify(creature_text.get_slice("\n", 0))])
			check(int(view.strip_preview) == creature, "%s: right button on the body previews the creature's strip" % edition)
			_mouse_button(body_point, false)
			for i in 3: await process_frame
	# A touch hold on the icon.
	var touch: ELTouchInput = view.touch_input
	var was_enabled := ELTouchInput.enabled
	touch.set_enabled(true)
	_mouse_move(Vector2(-50, -50))
	for i in 3: await process_frame
	# The figures hold still (an idle clip moves the readout) while the
	# finger rests, so the hold stays on the icon.
	for model: Variant in view.models.values():
		if is_instance_valid(model): model.set_process(false)
	for i in 3: await process_frame
	point = _icon_point(symbols, creature, bit, point)
	touch._press(0, point)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int((ELTouchInput.HOLD_SECONDS + 0.4) * 1000.0):
		view.ai_clock = -1000.0
		await process_frame
	check(touch.holding() and tip.panel.visible and _shown(tip) == expected, "%s: a touch hold on the icon shows its tooltip" % edition)
	check(int(view.strip_preview) == -1, "%s: the touch hold on the icon does not preview the creature" % edition)
	var shots := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := shots.path_join("figure_icon_tip_%s.png" % edition)
		root.get_texture().get_image().save_png(path)
		print("SHOT: " + path)
	touch._release(0, point, false)
	touch.set_enabled(was_enabled)
	await _close(view)

## The centre of the creature's icon now, else `fallback`.
func _icon_point(symbols: ELCombatSymbols, creature: int, bit: int, fallback: Vector2) -> Vector2:
	for figure: Dictionary in symbols.figures:
		if int(figure.id) != creature: continue
		for entry: Dictionary in symbols.icon_rects(figure):
			if int(entry.bit) == bit: return (entry.rect as Rect2).get_center()
	return fallback

func _close(view: Node) -> void:
	view.queue_free()
	await process_frame
	await process_frame

## The tooltip's lines as shown.
func _shown(tip: ELCombatTooltip) -> String:
	var lines := PackedStringArray()
	for label: Label in tip.panel._labels: lines.append(label.text)
	return "\n".join(lines)

## Events go in as the window sends them: in window pixels, which the root
## viewport maps back to its own (stretched) coordinates.
func _window_point(point: Vector2) -> Vector2:
	return root.get_final_transform() * point

func _mouse_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _window_point(point)
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = _window_point(point)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

## A screen point on the creature that is not on any icon.
func _body_point(view: Node, id: int) -> Vector2:
	var model: ELModel = view.models.get(id)
	if model == null: return Vector2(-10000, -10000)
	for height: float in [0.5, 0.3, 0.8, 0.2, 1.0, 0.1]:
		var point: Vector2 = view.camera.unproject_position(model.global_position + Vector3(0, height, 0))
		if view._character_at(point) == id and view._icon_at(point).is_empty(): return point
	return Vector2(-10000, -10000)

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 600:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() and view._effect_cast.is_empty(): return

## A new creature on `side` (a free script summon of its first creature card).
func _summoned(view: Node, side: int) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	var card := ""
	for row: String in view.profile.table("CombatCreatures"):
		if duel.is_summon(row):
			card = row
			break
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 30)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	for id: int in duel.creatures:
		if not before.has(id): return id
	return -1
