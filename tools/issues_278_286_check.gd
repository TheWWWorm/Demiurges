extends SceneTree
## Player reports #278 and #286 (first game map side column): the mouse wheel
## scrolls the column, and the held right button on a listed hero shows its
## map tooltip beside the column.
##
##   godot --path game --script ../tools/issues_278_286_check.gd
var fails := 0
func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: fails += 1
func frames(count: int) -> void:
	for i in count: await process_frame
func _initialize() -> void:
	_run.call_deferred()
func wheel(slot: Control, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	slot.gui_input.emit(e)
func right(slot: Control, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = pressed
	slot.gui_input.emit(e)
func _run() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	current_scene = view
	await frames(5)
	var row := {}
	var campaign := ELCampaign.new()
	if campaign.load_campaign(view.profiles.el1, "Good"):
		for scenario: Dictionary in campaign.scenarios:
			if str(scenario.get("file_name", "")).to_lower() == "mission21":
				row = scenario.duplicate()
				row.campaign = "Good"
	view.settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(view.settings).persist = false
	await view._begin_campaign("el1", row, 1)
	var map: ELAdventureView = view.campaign_view
	await frames(30)
	if map.tutorial_panel != null and map.tutorial_panel.visible: map.tutorial_panel.close()
	var hud: ELAdventureHud = map.hud
	var state := map.state
	# Enough entries to scroll: give the player extra heroes if needed.
	var heroes := 0
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.owner) == state.current_player: heroes += 1
	print("own heroes ", heroes, " roster ", hud.roster.size(), " slots ", hud.SLOT_COUNT)
	var slot: Control = hud.slots[0]
	# #286: right button on a listed hero shows its map tooltip; release hides it.
	right(slot, true)
	await frames(2)
	check(hud.tooltip.visible and hud.tooltip_subject == int(hud.slots[0].hero), "right button on a hero slot shows that hero's tooltip (%s)" % hud.tooltip_title.text)
	hud._hide_slot_tip()
	hud._show_slot_tip(slot)
	await frames(3)
	check(hud.tooltip.position.x + hud.tooltip.size.x <= slot.position.x, "the column's tooltip opens left of the slot")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(5, 5)
	hud._input(motion)
	check(hud.tooltip.visible, "it stays while the button is held")
	right(slot, false)
	await frames(2)
	check(not hud.tooltip.visible, "releasing the button hides it")
	# #278: wheel over the column scrolls it (buildings: mines list has many entries).
	for kind in ELBuildingScreen.CATEGORIES:
		hud.set_mode("buildings")
		hud.building_kind = kind
		await frames(3)
		if hud._entry_count() > hud.SLOT_COUNT: break
	var count: int = hud._entry_count()
	print("mode ", hud.mode, " kind ", hud.building_kind, " entries ", count)
	if count <= hud.SLOT_COUNT:
		hud.set_mode("heroes")
		await frames(3)
		count = hud._entry_count()
	if count <= hud.SLOT_COUNT:
		# Pad the hero list past the slots for the scroll checks (no frame runs
		# in between, so the per-frame refresh does not rebuild it).
		while hud.roster.size() < hud.SLOT_COUNT + 4: hud.roster.append(hud.roster[0])
		count = hud._entry_count()
	hud.first_entry = 0
	wheel(slot, true)
	if count > hud.SLOT_COUNT:
		check(hud.first_entry == 1, "wheel down scrolls the %s column one entry (%d entries)" % [hud.mode, count])
		wheel(slot, false)
		check(hud.first_entry == 0, "wheel up scrolls back")
		for i in count + 3: wheel(slot, true)
		check(hud.first_entry == count - hud.SLOT_COUNT, "the wheel stops at the list's end")
		var arrow: Control = hud.buttons.ScrollDown
		hud.first_entry = 0
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		arrow.gui_input.emit(e)
		check(hud.first_entry == 1, "the wheel over the arrows scrolls too")
		var tiles := []
		for sl in hud.slots: tiles.append(sl.hero)
	else:
		check(hud.first_entry == 0, "a list that fits does not scroll (%d entries)" % count)
	print("HUD COLUMN: %d failure(s)" % fails)
	quit(fails)

