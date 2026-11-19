extends SceneTree
## Headless check of Etherlords II interface reports (#240, #242, #245, #246,
## #250), driven through the viewport like real pointer input:
## - #246: the hero panel's tooltips (life, level, experience bar) appear in
##   the original frame on a right click as well as on a rest, and Godot's
##   own tooltip stays hidden;
## - #240: a global affect icon at the top right shows its tooltip in the
##   same frame on a right click, and the press asks no map object for one;
## - #245: while a character speaks the map objects keep their tooltips (a
##   right press shows one), a script message box still hides them, and a
##   spell row of a quest reward box shows the spell's tooltip;
## - #250: a click on a level-up offer plays the lists' click;
## - #242: in the inventory a reserve card dragged or clicked onto the deck
##   goes there and a deck card goes back; in the spell shop a reserve card
##   dragged onto the shop leaves the reserve. A press after the pointer
##   rested long enough for a tooltip drags as well.
##
##   godot --headless --path game --script ../tools/issues_240_250_check.gd
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
	root.size = Vector2i(1600, 900)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el2", str(paths.el2)):
		print("SKIP: the second game's files could not be mounted")
		quit(0)
		return
	var saves := _backup(ELSaveSlots.folder("el2"))
	var settings := ELSettings.new()
	settings.use_edition("el2")
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, {"file_name": "e2mission11"}, settings, 1)
	check(built, "the Vitals map builds: %s" % view.error)
	if built:
		# The chapter's own script stays idle: only the boxes the check opens show.
		for hook: String in ["Hook_Wake", "Hook_OnStep"]: view.state.vm.bind(hook, func(_args: Array) -> Array: return [])
		if view._mission_fade != null: await view._mission_fade.tree_exited
		await frames(3)
		await _answer_all(view)
		root.notify_mouse_entered()
		await _panel_tooltips(view)
		await _affect_tooltip(view)
		await _dialogue_tooltips(view)
		await _level_up_sound(view)
		await _inventory(view)
		await _shop(view)
	view.queue_free()
	await frames(2)
	_restore(ELSaveSlots.folder("el2"), saves)
	print("ISSUES 240-250 CHECK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _answer_all(view: ELAdventureView) -> void:
	for attempt in 20:
		if view.director.dialogue.is_empty(): return
		view.director.acknowledge()
		await frames(2)

## Spell codes of the profile, cantrips left out, in a stable order.
static func spell_codes(profile: ELProfile, count: int) -> Array[String]:
	var codes: Array[String] = []
	var spells: Array = profile.table("CombatSpells").keys()
	spells.sort()
	for code: String in spells:
		if not ELSpellInventory.is_spell(profile, code) or str(profile.table("CombatSpells")[code].get("Rarity", "")) == "Cantrip": continue
		codes.append(code)
		if codes.size() >= count: break
	return codes

# --- Pointer input through the viewport -------------------------------------

## Events go in as the window sends them: in window pixels, which the root
## viewport maps back to its own (stretched) coordinates.
func _send(event: InputEventMouse, at: Vector2) -> void:
	event.position = root.get_final_transform() * at
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _move(at: Vector2, held := false) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(event, at)

func _button(at: Vector2, index: MouseButton, pressed: bool, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.double_click = double
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	_send(event, at)

func _click(at: Vector2, index := MOUSE_BUTTON_LEFT) -> void:
	_move(at)
	await frames(1)
	_button(at, index, true)
	await frames(1)
	_button(at, index, false)
	await frames(1)

func _drag(from: Vector2, to: Vector2, rest := 0.0) -> void:
	_move(from)
	await frames(1)
	if rest > 0.0: await create_timer(rest).timeout
	_button(from, MOUSE_BUTTON_LEFT, true)
	await frames(1)
	for step in 4:
		_move(from.lerp(to, (step + 1) / 4.0), true)
		await frames(1)
	_button(to, MOUSE_BUTTON_LEFT, false)
	await frames(1)

## A right press held for a few frames, then released.
func _right_press(at: Vector2) -> void:
	_move(at)
	await frames(1)
	_button(at, MOUSE_BUTTON_RIGHT, true)
	await frames(3)

func _right_release(at: Vector2) -> void:
	_button(at, MOUSE_BUTTON_RIGHT, false)
	await frames(2)

## A point of a canvas item's local space on the screen.
static func screen_point(item: CanvasItem, local: Vector2) -> Vector2:
	return item.get_global_transform_with_canvas() * local

static func centre_of(control: Control) -> Vector2:
	return screen_point(control, control.size * 0.5)

static func tip_text(tips: ELCombatTooltip) -> String:
	var lines: Array[String] = []
	for label: Label in tips.panel._labels:
		if label.visible: lines.append(label.text)
	return "\n".join(lines)

# --- #246 / #240: the hero panel and the affect icons ------------------------

func _panel_tooltips(view: ELAdventureView) -> void:
	var hud := view.second_hud
	var tips := hud.panel_tips
	check(tips != null and not tips.battle_icons, "#246: the map panel has its own framed tooltip")
	if tips == null: return
	var life: Control = hud.hints.get("AdvPanelLifeTT")
	check(life != null and life.get_theme_stylebox("panel", "TooltipPanel") is StyleBoxEmpty, "#246: Godot's plain tooltip is hidden on the hero panel")
	if life == null: return
	# Parked away from the panel, the tooltip is off.
	_move(Vector2(800, 300))
	await frames(2)
	check(not tips.panel.visible, "#246: no panel tooltip over the map")
	var at := centre_of(life)
	await _right_press(at)
	check(tips.panel.visible and tip_text(tips) == hud.tooltip_of("AdvPanelLifeTT"), "#246: a right click on the life icon shows its tooltip at once")
	await _right_release(at)
	_move(Vector2(800, 300))
	await frames(2)
	check(not tips.panel.visible, "#246: the tooltip goes when the pointer leaves")
	var bar := hud.experience_bar
	at = centre_of(bar)
	await _right_press(at)
	check(tips.panel.visible and tip_text(tips) == bar.tooltip_text and not bar.tooltip_text.is_empty(), "#246: a right click on the experience bar shows the experience tooltip")
	await _right_release(at)
	_move(Vector2(800, 300))
	await frames(2)
	_move(at)
	await create_timer(ELCombatTooltip.DELAY + 0.2).timeout
	check(tips.panel.visible and tip_text(tips) == bar.tooltip_text, "#226: a rest on the experience bar still shows its tooltip")
	_move(Vector2(800, 300))
	await frames(2)

func _affect_tooltip(view: ELAdventureView) -> void:
	var hud := view.second_hud
	var state := view.state
	var profile := state.map.profile
	var hero := state.object(state.main_hero)
	var names: Array = profile.table("AffectsList").keys()
	names.sort()
	check(not names.is_empty(), "#240: the game lists affects")
	if names.is_empty(): return
	var kept: Array = hero.get("affects", []).duplicate(true)
	hero.affects = [{"name": str(names[0]), "id": "check"}]
	hud.refresh(state.main_hero, true)
	await create_timer(ELAffectStrip.ENTRANCE_SECONDS + 0.1).timeout
	var strip := hud.affect_strip
	check(strip.entries.size() == 1, "#240: the affect icon is shown")
	if strip.entries.is_empty(): return
	var at := screen_point(strip, strip.icon_rect(0).get_center())
	view.map_tip.reset()
	await _right_press(at)
	var tips := hud.panel_tips
	check(tips.panel.visible and tip_text(tips) == str(strip.entries[0].tooltip), "#240: a right click on a global affect shows its tooltip in the original frame")
	check(not hud.map_tooltip.visible and not view.dragging, "#240: the right press stays on the icon")
	await _right_release(at)
	_move(Vector2(800, 300))
	await frames(2)
	_move(at)
	await create_timer(ELCombatTooltip.DELAY + 0.2).timeout
	check(tips.panel.visible and tip_text(tips) == str(strip.entries[0].tooltip), "#240: a rest on a global affect shows the same tooltip")
	_move(Vector2(800, 300))
	await frames(2)
	hero.affects = kept
	hud.refresh(state.main_hero, true)
	await frames(2)

# --- #245: tooltips during a dialogue ----------------------------------------

func _dialogue_tooltips(view: ELAdventureView) -> void:
	var state := view.state
	var hud := view.second_hud
	var hero := state.object(state.main_hero)
	var actor: Node3D = view.world.actors.get(state.main_hero)
	check(actor != null, "#245: the hero stands on the map")
	if actor == null: return
	# A character's line (TextDialog).
	state._native([-1, "Hello"], "ExMessageBoxDialogHero")
	await frames(3)
	check(view.second_dialogue.visible and view.second_dialogue.style == "text", "#245: a character's line is shown")
	var at := view.camera.unproject_position(actor.global_position + Vector3(0, 0.6, 0))
	check(not view.second_dialogue.get_global_rect().has_point(at), "#245: the hero is clear of the dialogue box")
	view.map_tip.reset()
	await _right_press(at)
	check(hud.map_tooltip.visible and view.map_tip.subject == int(hero.uid), "#245: a map object's tooltip shows during a character's line")
	await _right_release(at)
	await _answer_all(view)
	# A script message box is modal: the map stays without tooltips.
	state._native(["Notice"], "ExMessageBoxStandard")
	await frames(3)
	check(view.second_dialogue.visible and view.second_dialogue.style == "message", "#245: a message box is shown")
	await _right_press(at)
	check(not hud.map_tooltip.visible, "#245: a script message box keeps the map tooltips off")
	await _right_release(at)
	await _answer_all(view)
	# A quest reward: spell rows with their tooltips.
	var card := spell_codes(state.map.profile, 1)[0]
	state._native([card], "ExAddLootMessageSpell")
	state._native([], "ExSendLootMessage")
	var box := view.second_dialogue
	# The reward cue plays before the box.
	for wait in 50:
		if box.visible: break
		await create_timer(0.1).timeout
	await frames(2)
	check(box.visible and box.style == "loot" and box.loot.size() == 1, "#245: the reward box lists the spell")
	if box.visible and box.style == "loot":
		var icon := Vector2(ELSecondDialogueBox.LOOT_ICON_X + ELSecondDialogueBox.LOOT_ICON * 0.5, box.loot_top + ELSecondDialogueBox.LOOT_ICON * 0.5)
		var point := screen_point(box.canvas, icon)
		check(box.get_theme_stylebox("panel", "TooltipPanel") is StyleBoxEmpty, "#245: Godot's plain tooltip is hidden on the box")
		await _right_press(point)
		var expected := ELCombatTooltip.spell_text(state.map.profile, card, -1, str(box.loot[0].name))
		check(box.tips.panel.visible and tip_text(box.tips) == expected, "#245: a right click on a reward spell shows its tooltip")
		await _right_release(point)
		_move(Vector2(20, 300))
		await frames(2)
		_move(point)
		await create_timer(ELCombatTooltip.DELAY + 0.2).timeout
		check(box.tips.panel.visible and tip_text(box.tips) == expected, "#245: a rest on a reward spell shows its tooltip")
		_move(Vector2(20, 300))
		await frames(2)
	await _answer_all(view)

# --- #250: the level-up offers' click ---------------------------------------

func _level_up_sound(view: ELAdventureView) -> void:
	var state := view.state
	var hero := state.object(state.main_hero)
	hero.skill_points = 1
	hero.skill_offers = []
	# The map opens the level-up dialog by itself once it is idle.
	for wait in 30:
		if view.skills != null: break
		await create_timer(0.1).timeout
	if view.skills == null: view._open_skills()
	await frames(3)
	var dialog := view.skills as ELSecondLevelUpView
	check(dialog != null and dialog.offers.item_count > 0, "#250: the level-up dialog offers skills")
	if dialog == null or dialog.offers.item_count == 0: return
	var before := ELUiSounds.history.size()
	await _click(screen_point(dialog.offers, dialog.offers.get_item_rect(0).get_center()))
	check(dialog.offers.get_selected_items() == PackedInt32Array([0]) and ELUiSounds.history.size() > before and ELUiSounds.history[-1] == ELSecondLevelUpView.SELECT_SOUND,
		"#250: a click on an offer selects it with the lists' click")
	hero.skill_points = 0
	view._close_skills()
	hero.skill_offers = []
	await frames(2)

# --- #242: the reserve -------------------------------------------------------

func _inventory(view: ELAdventureView) -> void:
	var state := view.state
	var hero := state.object(state.main_hero)
	var codes := spell_codes(state.map.profile, 20)
	hero.cards.clear()
	for index in 14: hero.cards.append(codes[index])
	hero.spell_stock.clear()
	for index in range(14, 20): hero.spell_stock[codes[index]] = 1
	for wait in 50:
		await _answer_all(view)
		if view.director.can_move() and view.director.movement.is_empty(): break
		await create_timer(0.1).timeout
	view._open_spellbook()
	await frames(3)
	var screen := view.spellbook as ELSecondInventoryView
	check(screen != null, "#242: the inventory opens")
	if screen == null: return
	var model := screen.model
	var at := func(zone: String, index: int) -> Vector2: return screen_point(screen.surface, screen.cell_rect(zone, index).get_center())
	var card := model.bag[0]
	var reserve := model.bag.size()
	await _drag(at.call("bag", 0), at.call("deck", 15))
	check(model.deck[15] == card and model.bag.size() == reserve - 1 and model.carried().is_empty(), "#242: a reserve card dragged onto a blank deck slot goes there")
	card = model.bag[0]
	await _click(at.call("bag", 0))
	await _click(at.call("deck", 14))
	check(model.deck[14] == card and model.carried().is_empty(), "#242: a reserve card clicked onto the deck goes there")
	card = model.deck[3]
	await _drag(at.call("deck", 3), at.call("bag", 1), ELCombatTooltip.DELAY + 0.2)
	check(model.deck[3].is_empty() and model.bag[-1] == card and model.carried().is_empty(), "#242: a deck card dragged into the reserve after a tooltip returns to it")
	card = model.bag[0]
	await _drag(at.call("bag", 0), at.call("deck", 3), ELCombatTooltip.DELAY + 0.2)
	check(model.deck[3] == card and model.carried().is_empty(), "#242: a reserve card dragged onto the deck after a tooltip goes there")
	screen.cancel()
	await frames(2)

func _shop(view: ELAdventureView) -> void:
	var state := view.state
	var hero := state.object(state.main_hero)
	var codes := spell_codes(state.map.profile, 24)
	hero.cards.clear()
	for index in 14: hero.cards.append(codes[index])
	hero.spell_stock.clear()
	for index in range(14, 16): hero.spell_stock[codes[index]] = 2
	# A stand-in laboratory: the screen only reads its stock.
	var shop_id := 987654
	state.objects[shop_id] = {"uid": shop_id, "type": "building", "group": "laboratories", "shop_stock": codes.slice(16, 24)}
	var trade := ELSpellShop.new()
	trade.state = state
	trade.hero_id = state.main_hero
	trade.shop_id = shop_id
	view.director.shop = trade
	view._open_shop()
	await frames(3)
	var screen := view.shop
	check(screen != null, "#242: the spell shop opens")
	if screen == null: return
	var model := screen.model
	var at := func(zone: String, index: int) -> Vector2: return screen_point(screen.surface, screen.cell_rect(zone, index).get_center())
	var reserve := model.bag.size()
	var stock := model.shop.size()
	var card: Dictionary = model.bag[0]
	await _drag(at.call("bag", 0), at.call("shop", 0), ELCombatTooltip.DELAY + 0.2)
	check(model.bag.size() == reserve - 1 and model.shop.size() == stock + 1 and model.shop[-1] == card, "#242: a reserve card dragged onto the shop leaves the reserve")
	card = model.bag[0]
	await _drag(at.call("bag", 0), at.call("deck", 15))
	check(model.deck[15] == card and model.bag.size() == reserve - 2, "#242: a reserve card dragged onto the shop's deck goes there")
	screen.put_back()
	view._close_shop()
	view.director.shop = null
	state.objects.erase(shop_id)
	await frames(2)

# --- Saves --------------------------------------------------------------------

func _backup(folder: String) -> Dictionary:
	var kept := {}
	if not DirAccess.dir_exists_absolute(folder): return kept
	for file in DirAccess.get_files_at(folder): kept[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return kept

func _restore(folder: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if not kept.has(file):
			DirAccess.remove_absolute(folder.path_join(file))
		elif FileAccess.get_file_as_bytes(folder.path_join(file)) != kept[file]:
			var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
			out.store_buffer(kept[file])
