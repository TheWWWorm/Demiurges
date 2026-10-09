class_name ELDuelScreen
extends RefCounted
## Original Duel mode front end on the ELFrontMenu canvas: the Duel screen
## (CDuelScreen), the hero/preset editor (EL1 CEditHeroScreen, EL2
## CEditPresetScreenA6) and the round-result / duel-summary panel. Layout comes
## from each edition's Controls and CutParts registries in the 1024 design;
## rules come from ELDuelPresets, ELDuelCosts and ELDuelMatch, which follow the
## original tables.
##
## Approximations: sort-button
## mapping (race / level / name, default level), the list's race marker, the
## editor's right-panel interaction (select + Buy/Back or double-click), EL2
## deck/reserve moves by double-click instead of dragging, message boxes drawn
## procedurally (the MessageBox panel has no CutParts art). Artifacts follow
## the originals: EL1 Buy appends the artifact selected on the Artifacts tab
## and Back returns the one selected in the hero's strip; EL2 picks an
## artifact in one panel and drops it on the other (double-click and
## right-click are remake shortcuts).

const RANDOM_KEY := "T_RANDOM"
const GREY := Color(0.498, 0.498, 0.498)
const RED := Color("e05a48")
const RACE_COLOURS := {"Red": Color("d0503c"), "Green": Color("5aa848"), "Blue": Color("4a7ed8"), "Black": Color("9a9a9a")}
## Sort modes: 0 table order, 1 race, 2 resource level (the original default
## mode is 2; the button-to-mode mapping is an assumption).
const SORT_RACE := 1
const SORT_LEVEL := 2
const SORT_NAME := 3
## EL1 editor tabs (right panel) in EHRightCaption1..5 order.
const EL1_TABS := ["EHTabSpells", "EHTabSkills", "EHTabRunes", "EHTabArtifacts", "EHTabSpec"]

var menu: ELFrontMenu
## Duel screen settings per edition (kept while the game runs).
var settings: Dictionary = {}
var pool: Array[Dictionary] = []
var rejected: Array = []
var list: PresetList
## Editor session: {preset, source, view_only, tab, slot, item, art, owned}.
## `art` is the picked entry of the EL2 artifact list, `owned` the selected
## artifact in the hero's strip (index into preset.artifacts).
var edit: Dictionary = {}
var right_items: Array = []
var right_list: ItemList
var book_view: Control
var name_edit: LineEdit
var message: Control
## Round panel data: {match, final}.
var round_info: Dictionary = {}
## Hot seat: -1 off, 0 while player 1 chooses,
## 1 while player 2 chooses. Each player picks only their own hero, in the
## "your hero" slot; player 2 cannot change the level, rounds or arena.
var hot_stage := -1
## Player 1's stored choice: preset id ("" = Random) and portrait template.
var hot_first: Dictionary = {}

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func reset() -> void:
	edit.clear()
	leave_hot_seat()

func profile() -> ELProfile:
	return menu.profile

func el1() -> bool:
	return menu.edition == "el1"

func state() -> Dictionary:
	# The hot-seat screen keeps its own settings beside the single-player ones.
	var key := menu.edition + (":hot" if hot_stage >= 0 else "")
	if not settings.has(key):
		settings[key] = {"arena": 0, "level": 1, "rounds": 1, "picks": ["", ""], "portraits": [-1, -1], "sort": SORT_LEVEL, "filter": false, "target": 0}
	return settings[key]

# --- Hot seat --------------------------------------------------------------------

## Default player names. The originals ask for CtrlDUHotSeatPlayer1/2; the
## first game's text table has them only as T_DUHotSeatPlayer1/2, which the
## remake uses instead.
func hot_name(player: int) -> String:
	for pattern: String in ["CtrlDUHotSeatPlayer%d", "T_DUHotSeatPlayer%d"]:
		var key := pattern % (player + 1)
		var value := profile().text(key)
		if value != key and not value.is_empty(): return value
	return "Player %d" % (player + 1)

## "Ход игрока %d" / "Waiting for player %d" (T_MB_HOT_SEAT_DUEL_WAIT).
func hot_wait_text(player: int) -> String:
	return profile().text("T_MB_HOT_SEAT_DUEL_WAIT").replace("%d", str(player + 1))

## MultiplayerStart -> HotSeat (EL1, EL2), and the
## return after a hot-seat duel: the Duel screen for player 1 with both
## choices back to Random and the "player 1" box.
func start_hot_seat() -> void:
	hot_stage = 0
	hot_first = {}
	_reset_hot_picks()
	menu.show_screen("duel")
	show_message(hot_wait_text(0))

func leave_hot_seat() -> void:
	hot_stage = -1
	hot_first = {}

func _reset_hot_picks() -> void:
	var s := state()
	s.picks = ["", ""]
	s.portraits = [-1, -1]
	s.target = 0

func art_exclude(target: String) -> Array:
	if target != "duel_editor" or edit.is_empty(): return []
	var result: Array = []
	# The race picture (Phase1..4 pieces) is drawn above the frame by the editor.
	for index in 4: result.append("Phase%d" % (index + 1))
	if el1(): result.append("Type8" if edit.tab in [0, 2] else "Type7")
	else: result.append("Type1" if edit.tab == 0 else "Type2")
	return result

# --- Shared helpers -----------------------------------------------------------

## Control rectangle in the 1024 layout. Nested panels (EHSkillsView,
## EHSpecView) inherit the shifts of their whole parent chain.
func _rect(control: String) -> Rect2:
	var rect := menu.control_rect(control)
	var parent := String(menu._controls.get(control, {}).get("Parent", ""))
	var outer := String(menu._controls.get(parent, {}).get("Parent", ""))
	var guard := 0
	while not outer.is_empty() and outer != "Desktop" and menu._controls.has(outer) and guard < 8:
		var row: Dictionary = menu._controls[outer]
		rect.position += Vector2(float(row.get("ShiftX", 0)), float(row.get("ShiftY", 0)))
		outer = String(row.get("Parent", ""))
		guard += 1
	return rect

func _font_size(control: String, fallback := 17) -> int:
	var size := int(menu._controls.get(control, {}).get("FontSize", fallback))
	return size if size > 0 else fallback

func _text(control: String, value: Variant = null, color := ELFrontMenu.TITLE_INK, align := HORIZONTAL_ALIGNMENT_CENTER, rect := Rect2()) -> Label:
	if rect.size == Vector2.ZERO: rect = _rect(control)
	if rect.size == Vector2.ZERO: return null
	var shown: String = menu._caption(control) if value == null else str(value)
	var label := menu._label(control, shown, rect, mini(_font_size(control), 18), color, align)
	label.clip_text = true
	return label

func _button(control: String, action: Callable) -> ELFrontMenu.CutButton:
	var button := menu._square(control)
	if button != null: button.pressed.connect(action)
	return button

## A cut button inside a nested panel (EHEquipScrL/R in EHArtifactsView): the
## shifts of the whole parent chain apply, as for _rect.
func _nested_button(control: String, action: Callable) -> ELFrontMenu.CutButton:
	var offset := menu.shift(control)
	offset += _rect(control).position - menu.control_rect(control).position
	var button := ELFrontMenu.CutButton.make(menu, control, offset)
	if button == null: return null
	menu.canvas.add_child(button)
	menu.buttons[control] = button
	button.pressed.connect(action)
	return button

## Original auto-repeat buttons (AutoButton): repeat while held.
func _auto(control: String, action: Callable) -> ELFrontMenu.CutButton:
	var button := menu._square(control)
	if button == null: return null
	var timer := Timer.new()
	button.add_child(timer)
	button.button_down.connect(func():
		action.call()
		timer.start(0.4))
	button.button_up.connect(timer.stop)
	timer.timeout.connect(func():
		if not button.is_pressed(): timer.stop()
		elif not button.disabled:
			action.call()
			timer.start(0.07))
	return button

## A caption drawn on an original button (New/Edit/Delete, tabs).
func _caption_on(button: Control, value: String, size_px := 18, color := ELFrontMenu.INK) -> Label:
	if button == null: return null
	var label := Label.new()
	label.text = value
	label.size = button.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", menu.serif)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return label

func _between(left: Control, right: Control) -> Rect2:
	if left == null or right == null: return Rect2()
	return Rect2(Vector2(left.position.x + left.size.x, left.position.y), Vector2(right.position.x - left.position.x - left.size.x, left.size.y))

func _value(key: String, value: String, rect: Rect2, size_px := 17) -> Label:
	var label := menu._label(key, value, rect, size_px, ELFrontMenu.INK_HOVER)
	label.clip_text = true
	return label

func _art_rect(group: String, mask: String) -> Rect2:
	var found := menu.rows(group, [mask])
	if found.is_empty(): return Rect2()
	return Rect2(Vector2(found[0].ScrL, found[0].ScrT) + menu.shift(group), Vector2(found[0].TxtW, found[0].TxtH))

func _transparent(item_list: ItemList) -> void:
	for style in ["panel", "focus"]: item_list.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(0.85, 0.7, 0.4, 0.22)
	for style in ["selected", "selected_focus", "cursor", "cursor_unfocused"]: item_list.add_theme_stylebox_override(style, selected)
	var hovered := StyleBoxFlat.new()
	hovered.bg_color = Color(1, 1, 1, 0.06)
	item_list.add_theme_stylebox_override("hovered", hovered)
	item_list.add_theme_font_override("font", menu.serif)
	item_list.add_theme_font_size_override("font_size", 15)
	item_list.add_theme_color_override("font_color", ELFrontMenu.BODY_INK)
	item_list.add_theme_color_override("font_selected_color", ELFrontMenu.INK_HOVER)
	item_list.add_theme_color_override("font_hovered_color", ELFrontMenu.INK_HOVER)
	item_list.add_theme_constant_override("v_separation", 2)
	item_list.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	item_list.focus_mode = Control.FOCUS_NONE

func _scroll(item_list: ItemList, rows: int) -> void:
	if item_list == null: return
	var bar := item_list.get_v_scroll_bar()
	bar.value = clampf(bar.value + rows * 24.0, bar.min_value, bar.max_value)

func preset_name(preset: Dictionary) -> String:
	return String(preset.get("name", "")) if not preset.is_empty() else profile().text(RANDOM_KEY)

# --- Duel screen ---------------------------------------------------------------

func refresh_pool() -> void:
	rejected.clear()
	pool.assign(ELDuelPresets.shipped(profile()) + ELDuelPresets.load_user(profile(), rejected))

func pick(side: int) -> Dictionary:
	var id := String(state().picks[side])
	return {} if id.is_empty() else ELDuelPresets.find(pool, id)

func arenas() -> Array[String]:
	return ELDuelMatch.arenas(profile())

func arena_id() -> String:
	var index := int(state().arena)
	return ELDuelMatch.RANDOM if index == 0 else arenas()[index - 1]

func arena_label() -> String:
	var index := int(state().arena)
	if index == 0: return profile().text(RANDOM_KEY)
	return profile().text(String(profile().table("ScenesNames").get(arenas()[index - 1], {}).get("ELKName", arenas()[index - 1])))

## Eligible cosmetic portraits of a race: non-quest templates of that colour.
func portraits(faction: String) -> Array[String]:
	var result: Array[String] = []
	var rows := profile().table("HeroTemplates")
	for key: String in rows:
		if String(rows[key].get("Color", "")) == faction and String(rows[key].get("Quest", "")) != "Yes": result.append(key)
	return result

func template(side: int) -> String:
	var preset := pick(side)
	if preset.is_empty(): return ""
	var index := int(state().portraits[side])
	var list_of := portraits(String(preset.faction))
	return list_of[index] if index >= 0 and index < list_of.size() else ""

## Visible list rows: Random first, then the presets in the chosen order.
func rows() -> Array[Dictionary]:
	var s := state()
	var shown: Array[Dictionary] = []
	for preset: Dictionary in pool:
		if s.filter and int(preset.resource_level) != int(s.level): continue
		shown.append(preset)
	var order := {}
	for i in pool.size(): order[pool[i].id] = i
	var mode := int(s.sort)
	if mode != 0:
		shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var keys_a := _sort_key(a, mode)
			var keys_b := _sort_key(b, mode)
			for i in keys_a.size():
				if keys_a[i] != keys_b[i]: return keys_a[i] < keys_b[i]
			return order[a.id] < order[b.id])
	var result: Array[Dictionary] = [{}]
	result.append_array(shown)
	return result

func _sort_key(preset: Dictionary, mode: int) -> Array:
	var race := ELDuelPresets.RACES.find(String(preset.faction))
	var level := int(preset.resource_level)
	var name := String(preset.name).to_lower()
	match mode:
		SORT_RACE: return [race, level, name]
		SORT_LEVEL: return [level, race, name]
	return [name, race, level]

func can_start() -> bool:
	if hot_stage >= 0: return ELDuelMatch.side_valid(pool, pick(0), int(state().level))
	return ELDuelMatch.can_start(pool, [pick(0), pick(1)], int(state().level))

func build_screen() -> void:
	refresh_pool()
	var s := state()
	# Drop picks whose user preset vanished.
	for side in 2:
		if not String(s.picks[side]).is_empty() and pick(side).is_empty(): s.picks[side] = ""
	var caption := "DuCaption"
	_text(caption, null, ELFrontMenu.TITLE_INK)
	for control: String in ["DuConditions", "DuSelectPreset", "DuArenaText", "DuMyHero", "DuEnemyHero"]: _text(control)
	# Hot seat: the hero captions show the players' names; on player 2's turn
	# the names swap so the chooser's own name is in "your hero".
	if hot_stage >= 0:
		for side in 2:
			var hero_caption: Label = menu.labels.get("DuMyHero" if side == 0 else "DuEnemyHero")
			if hero_caption != null: hero_caption.text = hot_name(hot_stage if side == 0 else 1 - hot_stage)
	_text("DuResLevelText", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("DuRoundsText", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_RIGHT)
	for control: String in ["DuText1", "DuText2"]: _text(control, null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	# Side frames: a click makes that side the list's target.
	for side in 2:
		var frame := _art_rect("Duel", "Type3" if side == 0 else "Type4")
		var target := SideFrame.new()
		target.screen = self
		target.side = side
		target.position = frame.position
		target.size = frame.size
		target.tooltip_text = menu._caption("DuMyHero" if side == 0 else "DuEnemyHero")
		menu.canvas.add_child(target)
		menu.labels["frame%d" % side] = target
		target.pressed.connect(func(): set_target(side))
		# Hot seat: each player edits only their own ("your hero") slot.
		if hot_stage >= 0 and side == 1:
			target.disabled = true
			target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var res_dec := _auto("DuResDec", change_level.bind(-1))
	var res_inc := _auto("DuResInc", change_level.bind(1))
	_value("level", str(s.level), _between(res_dec, res_inc))
	var rounds_dec := _auto("DuRoundsDec", change_rounds.bind(-1))
	var rounds_inc := _auto("DuRoundsInc", change_rounds.bind(1))
	_value("rounds", str(s.rounds), _between(rounds_dec, rounds_inc))
	_auto("DuArenaDec", change_arena.bind(-1))
	_auto("DuArenaInc", change_arena.bind(1))
	_text("DuArena", arena_label(), ELFrontMenu.INK_HOVER).add_theme_font_size_override("font_size", 15)
	for side in 2:
		var left := _auto("DuHeroLeft%d" % (side + 1), change_portrait.bind(side, -1))
		var right := _auto("DuHeroRight%d" % (side + 1), change_portrait.bind(side, 1))
		var picture := TextureRect.new()
		var area := _between(left, right).grow(-2)
		picture.position = area.position
		picture.size = area.size
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu.canvas.add_child(picture)
		menu.labels["portrait%d" % side] = picture
		_text("DuPresetName%d" % (side + 1), "", ELFrontMenu.INK_HOVER)
	var by_race := _button("DuSortRace", set_sort.bind(SORT_RACE))
	var by_level := _button("DuSortLevel", set_sort.bind(SORT_LEVEL))
	var by_name := FlatText.new()
	by_name.menu = menu
	by_name.caption = menu._caption("DuSortName")
	var name_rect := _rect("DuSortName")
	by_name.position = name_rect.position
	by_name.size = name_rect.size
	var tip := String(menu._controls.get("DuSortName", {}).get("ToolTip", ""))
	if not tip.is_empty() and menu.text(tip) != tip: by_name.tooltip_text = menu.text(tip)
	menu.canvas.add_child(by_name)
	menu.buttons["DuSortName"] = by_name
	by_name.pressed.connect(set_sort.bind(SORT_NAME))
	var up := _button("DuPresetsScrollU", func(): list.scroll(-3))
	var down := _button("DuPresetsScrollD", func(): list.scroll(3))
	list = PresetList.new()
	list.screen = self
	var left_x := by_race.position.x if by_race != null else name_rect.position.x - 66
	var top := maxf(by_race.position.y + by_race.size.y if by_race != null else 0.0, name_rect.end.y) + 4
	var right_x := up.position.x - 2 if up != null else name_rect.end.x
	var bottom := down.position.y + down.size.y if down != null else top + 360
	list.position = Vector2(left_x, top)
	list.size = Vector2(right_x - left_x, bottom - top)
	list.columns = [(by_race.position.x + by_race.size.x * 0.5 if by_race != null else left_x + 15) - left_x,
		(by_level.position.x + by_level.size.x * 0.5 if by_level != null else left_x + 50) - left_x, name_rect.position.x - left_x + 4]
	menu.canvas.add_child(list)
	menu.labels["list"] = list
	var filter := _button("DuFilterLevel", toggle_filter)
	if filter != null:
		var label_rect := Rect2(filter.position + Vector2(filter.size.x + 6, 0), Vector2(250, filter.size.y))
		_text("DuFilterLevel", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT, label_rect)
	for control: String in ["DuNew", "DuEdit", "DuDelete"]:
		var button := _button(control, {"DuNew": new_preset, "DuEdit": edit_preset, "DuDelete": delete_preset}[control])
		_caption_on(button, menu._caption(control), 18)
	_button("DuBack", func(): menu.go_back())
	_button("DuStart", start)
	if not rejected.is_empty(): menu.buttons.DuNew.tooltip_text += "\n" + "Unreadable or invalid user presets were skipped: " + ", ".join(rejected)
	update_screen()

## Refreshes the dynamic parts of the Duel screen without rebuilding it.
func update_screen() -> void:
	if menu.screen != "duel": return
	var s := state()
	var levels := ELDuelCosts.resource_levels(profile())
	menu.labels.level.text = str(s.level)
	menu.labels.rounds.text = str(s.rounds)
	menu.labels.DuArena.text = arena_label()
	# Player 2's turn: player 1's level, rounds and arena stand.
	var locked := hot_stage == 1
	menu.buttons.DuResDec.disabled = locked or int(s.level) <= levels.x
	menu.buttons.DuResInc.disabled = locked or int(s.level) >= levels.y
	menu.buttons.DuRoundsDec.disabled = locked or int(s.rounds) <= 1
	menu.buttons.DuRoundsInc.disabled = locked or int(s.rounds) >= ELDuelMatch.MAX_ROUNDS
	for control: String in ["DuArenaDec", "DuArenaInc"]:
		if menu.buttons.has(control): menu.buttons[control].disabled = locked
	for side in 2:
		var preset := pick(side)
		var name_label: Label = menu.labels.get("DuPresetName%d" % (side + 1))
		if name_label != null:
			name_label.text = preset_name(preset)
			name_label.add_theme_color_override("font_color", GREY if not ELDuelMatch.side_valid(pool, preset, int(s.level)) else ELFrontMenu.INK_HOVER)
		var picture: TextureRect = menu.labels["portrait%d" % side]
		picture.texture = null
		if not preset.is_empty():
			var name := template(side)
			if name.is_empty(): name = ELDuelPresets.default_template(profile(), String(preset.faction))
			var row: Dictionary = profile().table("HeroTemplates").get(name, {})
			if not row.is_empty(): picture.texture = profile().portrait(int(row.Face))
		for control: String in ["DuHeroLeft%d" % (side + 1), "DuHeroRight%d" % (side + 1)]:
			if menu.buttons.has(control): menu.buttons[control].disabled = preset.is_empty() or portraits(String(preset.faction)).is_empty()
		menu.labels["frame%d" % side].queue_redraw()
	for pair: Array in [["DuSortRace", SORT_RACE], ["DuSortLevel", SORT_LEVEL], ["DuSortName", SORT_NAME]]:
		if menu.buttons.has(pair[0]): menu.buttons[pair[0]].active = int(s.sort) == pair[1]
	if menu.buttons.has("DuFilterLevel"): menu.buttons.DuFilterLevel.active = bool(s.filter)
	var chosen := pick(int(s.target))
	menu.buttons.DuEdit.disabled = chosen.is_empty()
	menu.buttons.DuDelete.disabled = chosen.is_empty() or bool(chosen.get("builtin", true))
	menu.buttons.DuStart.disabled = not can_start()
	list.queue_redraw()

func set_target(side: int) -> void:
	if hot_stage >= 0: side = 0
	state().target = side
	update_screen()

func change_level(step: int) -> void:
	if hot_stage == 1: return
	var levels := ELDuelCosts.resource_levels(profile())
	state().level = clampi(int(state().level) + step, levels.x, levels.y)
	update_screen()

func change_rounds(step: int) -> void:
	if hot_stage == 1: return
	state().rounds = clampi(int(state().rounds) + step, 1, ELDuelMatch.MAX_ROUNDS)
	update_screen()

func change_arena(step: int) -> void:
	if hot_stage == 1: return
	var count := arenas().size() + 1
	state().arena = posmod(int(state().arena) + step, count)
	update_screen()

func change_portrait(side: int, step: int) -> void:
	var preset := pick(side)
	if preset.is_empty(): return
	var count := portraits(String(preset.faction)).size()
	if count == 0: return
	# -1 is the heroes.def default; the arrows wrap through the race's portraits.
	state().portraits[side] = posmod(int(state().portraits[side]) + 1 + step, count + 1) - 1
	update_screen()

func set_sort(mode: int) -> void:
	state().sort = 0 if int(state().sort) == mode else mode
	update_screen()

func toggle_filter() -> void:
	state().filter = not bool(state().filter)
	list.offset = 0
	update_screen()

## A list click assigns the row (Random or a preset) to the target side.
func choose_row(index: int) -> void:
	var shown := rows()
	if index < 0 or index >= shown.size(): return
	var s := state()
	s.picks[int(s.target)] = String(shown[index].get("id", ""))
	s.portraits[int(s.target)] = -1
	update_screen()

func start() -> void:
	if not can_start(): return
	if hot_stage >= 0:
		_start_hot_stage()
		return
	var s := state()
	var duel_match := ELDuelMatch.new()
	var templates := [template(0), template(1)]
	var failure := duel_match.begin(profile(), pool, [pick(0), pick(1)], int(s.level), int(s.rounds), arena_id(), randi(), templates)
	if not failure.is_empty():
		show_message(failure)
		return
	menu.duel_match_requested.emit(duel_match)

## Hot-seat Start: player 1's Start
## stores the choice and hands the screen to player 2 ("player 2" box);
## player 2's Start begins the match, player 1 on side 0.
func _start_hot_stage() -> void:
	var s := state()
	if hot_stage == 0:
		hot_first = {"pick": String(s.picks[0]), "template": template(0)}
		hot_stage = 1
		_reset_hot_picks()
		menu.show_screen("duel")
		show_message(hot_wait_text(1))
		return
	var first: Dictionary = {} if String(hot_first.get("pick", "")).is_empty() else ELDuelPresets.find(pool, String(hot_first.pick))
	if not String(hot_first.get("pick", "")).is_empty() and first.is_empty():
		show_message("Player 1's preset is no longer available.")
		return
	var duel_match := ELDuelMatch.new()
	var failure := duel_match.begin(profile(), pool, [first, pick(0)], int(s.level), int(s.rounds), arena_id(), randi(), [String(hot_first.get("template", "")), template(0)])
	if not failure.is_empty():
		show_message(failure)
		return
	duel_match.hot_seat = true
	duel_match.names = [hot_name(0), hot_name(1)]
	leave_hot_seat()
	menu.duel_match_requested.emit(duel_match)

func new_preset() -> void:
	var s := state()
	var faction := "Red"
	var chosen := pick(int(s.target))
	if not chosen.is_empty(): faction = String(chosen.faction)
	open_editor({"id": "", "name": "", "builtin": false, "faction": faction, "resource_level": int(s.level), "level": 1, "specialization": "NONE",
		"skills": {}, "cards": [], "runes": [], "reserve": {}, "artifacts": [], "deck": ""}, "")

func edit_preset() -> void:
	var chosen := pick(int(state().target))
	if chosen.is_empty(): return
	open_editor(chosen, String(chosen.id))

func delete_preset() -> void:
	var chosen := pick(int(state().target))
	if chosen.is_empty() or bool(chosen.get("builtin", true)): return
	show_message(profile().text("T_MB_DELETE_PRESET"), func():
		ELDuelPresets.delete_user(profile(), String(chosen.name))
		for side in 2:
			if state().picks[side] == chosen.id:
				state().picks[side] = ""
				state().portraits[side] = -1
		menu.show_screen("duel"), true)

# --- Message box ---------------------------------------------------------------

## The original MessageBox over the front end (MBText/MBOK/MBCancel); its size
## follows the text, so `width` is no longer used. First game: the text
## (bold, 15) wraps at 512 px, the box is the text plus 10 px each side over
## the button row, framed from the TOOLTIP sheet; OK and Cancel sit 15 px
## either side of the centre. Second game (ExMessageBoxStandard): the
## text (17, tan) wraps at 512 px, the buttons 10 px under it, 8 px either side
## of the centre; the content grows by 15 px and takes the WORLD_SYMBOLS_MAP
## frame. Both are centred and leave the screen undimmed.
func show_message(text: String, on_ok: Callable = Callable(), ask := false, _width := 200.0, on_cancel: Callable = Callable()) -> void:
	close_message()
	var shade := MessageShade.new()
	shade.size = ELFrontMenu.DESIGN
	shade.first = el1()
	menu.canvas.add_child(shade)
	message = shade
	var body := Label.new()
	body.text = text
	# Wrapping is set before the size: an unwrapped label would first grow
	# to the width of its whole text and keep it.
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_theme_constant_override("line_spacing", 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = menu.serif
	var font_size := ELSecondDialogueBox.MESSAGE_SIZE
	if shade.first:
		var bold := FontVariation.new()
		bold.base_font = ThemeDB.fallback_font
		bold.variation_embolden = 0.6
		font = bold
		font_size = ELFirstMessageBox.FONT_SIZE
		body.add_theme_color_override("font_color", ELFirstMessageBox.TEXT)
		shade.frame = menu.texture_named("TOOLTIP")
		shade.shadow = menu.texture_named("SYMBOLS")
	else:
		body.add_theme_color_override("font_color", ELSecondDialogueBox.TAN)
		shade.frame = menu.texture_named("WORLD_SYMBOLS_MAP")
	body.add_theme_font_override("font", font)
	body.add_theme_font_size_override("font_size", font_size)
	var wrap := ELFirstMessageBox.MAX_TEXT
	var text_width := clampf(ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 2.0, 60.0, wrap)
	var text_height := ceilf(font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size).y)
	var controls := ["MBOK", "MBCancel"] if ask else ["MBOK"]
	var made: Array = []
	var button_size := Vector2.ZERO
	for control: String in controls:
		var button := ELFrontMenu.CutButton.make(menu, control, Vector2.ZERO)
		if button == null: continue
		made.append(button)
		button_size = button_size.max(button.size)
	var spread := 15.0 if shade.first else ELSecondDialogueBox.MESSAGE_SPREAD
	var inset := ELFirstMessageBox.MARGIN if shade.first else ELSecondDialogueBox.MESSAGE_GROW
	var content := Vector2(maxf(text_width, (button_size.x + spread) * 2.0 if ask else button_size.x), text_height + 10.0 + button_size.y)
	var outer := content + Vector2(inset, inset) * 2.0
	if shade.first: outer.y += ELFirstMessageBox.MARGIN
	var box := Rect2(((ELFrontMenu.DESIGN - outer) * 0.5).floor(), outer)
	shade.box = box
	body.position = box.position + Vector2(inset + floorf((content.x - text_width) * 0.5), inset)
	body.size = Vector2(text_width, text_height)
	shade.add_child(body)
	menu.labels["message"] = body
	var middle := box.position.x + inset + floorf(content.x * 0.5)
	var row := body.position.y + text_height + 10.0
	for button: ELFrontMenu.CutButton in made:
		var control := String(button.name)
		if not ask: button.position = Vector2(middle - floorf(button.size.x * 0.5), row)
		elif control == "MBOK": button.position = Vector2(middle - spread - button.size.x, row)
		else: button.position = Vector2(middle + spread, row)
		shade.add_child(button)
		menu.buttons[control] = button
		# The buttons are icon-only in both games: the art carries the tick and
		# cross; the first game's captions (CtrlMBOK / CtrlMBCancel) are empty
		# and the second game has only tooltips (CtrlTTMBOK / CtrlTTMBCancel).
		var tip := menu.text(String(menu._controls.get(control, {}).get("ToolTip", ""))).strip_edges()
		if tip.is_empty() or tip.begins_with("Ctrl"): tip = "OK" if control == "MBOK" else "Отмена"
		button.tooltip_text = tip
		button.accessibility_name = tip
		button.pressed.connect(func():
			close_message()
			if control == "MBOK" and on_ok.is_valid(): on_ok.call()
			elif control == "MBCancel" and on_cancel.is_valid(): on_cancel.call())

func close_message() -> void:
	if message != null and is_instance_valid(message):
		message.queue_free()
		menu.canvas.remove_child(message)
	message = null
	menu.buttons.erase("MBOK")
	menu.buttons.erase("MBCancel")

## Keys over the message box: Enter answers OK; Escape answers Cancel where it
## is shown, else OK; the second game's one-button box also takes Space.
func message_key(keycode: int) -> bool:
	if not message_open(): return false
	var ok: BaseButton = menu.buttons.get("MBOK")
	var cancel: BaseButton = menu.buttons.get("MBCancel")
	var answer: BaseButton = null
	if keycode in [KEY_ENTER, KEY_KP_ENTER]: answer = ok
	elif keycode == KEY_ESCAPE: answer = cancel if cancel != null else ok
	elif keycode == KEY_SPACE and not el1() and cancel == null: answer = ok
	if answer == null or not is_instance_valid(answer): return false
	answer.pressed.emit()
	return true

func message_open() -> bool:
	return message != null and is_instance_valid(message)

# --- Preset editor -------------------------------------------------------------

func open_editor(preset: Dictionary, source: String) -> void:
	var copy := ELDuelPresets.normalize(preset)
	copy.name = String(preset.get("name", ""))
	var builtin := bool(preset.get("builtin", false))
	# The first game opens a built-in preset for viewing; the second can save
	# a changed built-in preset under a new name only.
	edit = {"preset": copy, "source": source, "builtin": builtin, "view_only": builtin and el1(), "tab": 0, "slot": -1, "item": -1, "art": -1, "owned": -1}
	menu.show_screen("duel_editor")

func cancel_editor() -> void:
	if message_open():
		close_message()
		return
	edit.clear()
	menu.show_screen("duel")

func editor_preset() -> Dictionary:
	return edit.get("preset", {})

func errors() -> Array[String]:
	return ELDuelCosts.errors(profile(), editor_preset())

func build_editor() -> void:
	if edit.is_empty():
		menu.show_screen("duel")
		return
	# Race picture: the Phase<n> pieces in Duel\heroes.def race order. The first
	# game's frame pieces would cover them, so they are drawn on top.
	var group := "EditHero" if el1() else "EditPresetA6"
	var race := ELDuelPresets.RACES.find(String(editor_preset().faction))
	var picture := PieceView.new()
	for row: Dictionary in menu.rows(group, ["Phase%d" % (race + 1)]):
		var piece := menu.cut(row, menu.shift(group))
		if not piece.is_empty(): picture.pieces.append(piece)
	picture.size = ELFrontMenu.DESIGN
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.canvas.add_child(picture)
	menu.labels["race_picture"] = picture
	if el1(): _build_el1_editor()
	else: _build_el2_editor()
	name_edit = LineEdit.new()
	var name_rect := _rect("EHFileName" if el1() else "EPFileName")
	name_edit.position = name_rect.position
	name_edit.size = name_rect.size
	name_edit.text = String(editor_preset().get("name", ""))
	name_edit.max_length = 40
	name_edit.add_theme_font_override("font", menu.serif)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.add_theme_color_override("font_color", ELFrontMenu.INK_HOVER)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0, 0, 0, 0.25)
	field.content_margin_left = 4
	for style in ["normal", "focus", "read_only"]: name_edit.add_theme_stylebox_override(style, field)
	name_edit.editable = not edit.view_only
	name_edit.text_changed.connect(func(_t: String): update_editor())
	menu.canvas.add_child(name_edit)
	menu.labels["name"] = name_edit
	_text("EHSaveHero" if el1() else "EPHdrSave", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	var ok := _button("EHOK" if el1() else "EPOK", save_editor)
	if ok != null: menu.buttons["editor_ok"] = ok
	var cancel := _button("EHCancel" if el1() else "EPCancel", cancel_editor)
	if cancel != null: menu.buttons["editor_cancel"] = cancel
	# Rule errors (remake text behind the helper overlay; the original only
	# disables OK and marks short resources red).
	# EL1: under Buy/Back in the middle column; EL2: under the panels.
	var status_rect := Rect2(Vector2(330, 488) + menu.shift("EditHero"), Vector2(150, 62)) if el1() else Rect2(Vector2(20, 517) + menu.shift("EditPresetA6"), Vector2(760, 14))
	var status := menu._label("errors", "", status_rect, 12, RED, HORIZONTAL_ALIGNMENT_CENTER if el1() else HORIZONTAL_ALIGNMENT_LEFT)
	status.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if el1(): status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else: status.clip_text = true
	update_editor()

func _race_controls(left: String, right: String) -> void:
	_button(left, change_race.bind(-1))
	_button(right, change_race.bind(1))

func change_race(step: int) -> void:
	if edit.view_only: return
	var p := editor_preset()
	var index := ELDuelPresets.RACES.find(String(p.faction))
	p.faction = ELDuelPresets.RACES[posmod(index + step, ELDuelPresets.RACES.size())]
	# Own-race spells and specialisations only; skills and artifacts stay.
	var keep: Array[String] = []
	var runes: Array[int] = []
	for i in p.cards.size():
		if ELDuelCosts.spell_allowed(profile(), p.cards[i], p.faction):
			keep.append(p.cards[i])
			runes.append(int(p.runes[i]) if i < p.runes.size() else 0)
	p.cards = keep
	p.runes = runes
	for code: String in p.reserve.keys():
		if not ELDuelCosts.spell_allowed(profile(), code, p.faction): p.reserve.erase(code)
	if not ELDuelCosts.spec_allowed(profile(), String(p.specialization), String(p.faction)): p.specialization = "NONE"
	edit.slot = -1
	menu.show_screen("duel_editor")

func change_hero_level(step: int) -> void:
	if edit.view_only: return
	var levels := ELDuelCosts.hero_levels(profile())
	editor_preset().level = clampi(int(editor_preset().level) + step, levels.x, levels.y)
	update_editor()

func change_resource_level(step: int) -> void:
	if edit.view_only: return
	var levels := ELDuelCosts.resource_levels(profile())
	editor_preset().resource_level = clampi(int(editor_preset().resource_level) + step, levels.x, levels.y)
	update_editor()

## Spells the editor offers: own colour (and the second game's neutral White).
func spell_choices() -> Array[String]:
	var faction := String(editor_preset().faction)
	var result := ELCatalog.available_cards(profile(), faction)
	if not el1():
		for card: String in ELCatalog.available_cards(profile(), ELDuelCosts.EL2_NEUTRAL): result.append(card)
	return result.filter(func(card: String): return ELDuelCosts.spell_allowed(profile(), card, faction))

func spec_choices() -> Array[String]:
	var result: Array[String] = ["NONE"]
	for code: String in profile().table("HeroesSpecs"):
		if code != "NONE" and ELDuelCosts.spec_allowed(profile(), code, String(editor_preset().faction)) and ELSpecs.valid(profile(), code): result.append(code)
	return result

## Artifacts the editor sells (ELDuelCosts.duel_artifacts), in the edition's
## list order.
func artifact_choices() -> Array[String]:
	return ELDuelCosts.duel_artifacts(profile())

## Tooltip of an artifact: name, the spell's text, duel price and the charges
## it starts every duel round with.
func artifact_tooltip(code: String) -> String:
	var row: Dictionary = profile().table("CombatSpells").get(code, {})
	var price := PackedStringArray()
	var resources := ELDuelCosts.resources(profile())
	for i in resources.size():
		var amount := int(row.get("Cost" + resources[i], 0))
		if amount > 0: price.append("%s %d" % [resource_title(i), amount])
	var key := String(row.get("ToolTip", ""))
	var text := profile().text(key) if not key.is_empty() else ""
	var lines := PackedStringArray([spell_name(code)])
	if not text.is_empty() and text != key: lines.append(text)
	lines.append(", ".join(price))
	lines.append("Charges: %d" % artifact_charges(code))
	return "\n".join(lines)

## Charges an artifact starts each duel round with (the edition's MaxCharges).
func artifact_charges(code: String) -> int:
	var name := ELDuelPresets.artifact_name(profile(), code)
	return int(profile().table("Artefacts").get(name, {}).get("MaxCharges", 0))

func spell_name(code: String) -> String:
	return profile().text(String(profile().table("CombatSpells").get(code, {}).get("Name", code + "Nm")))

func skill_name(code: String, rank: int) -> String:
	var row := ELHeroSkills.definition(profile(), code, rank)
	return "%s %s" % [profile().text(str(row.get("Name", code))), ["I", "II", "III"][clampi(rank, 0, 2)]]

func spec_name(code: String) -> String:
	if code == "NONE":
		var none := profile().text("CtrlEPActiveSpec")
		return none if not none.begins_with("Ctrl") else "—"
	return profile().text(str(profile().table("HeroesSpecs").get(code, {}).get("Name", code)))

## Applies a buy/return action to a copy of the preset; null when impossible.
func apply(preset: Dictionary, action: String, value: Variant) -> Variant:
	var p := preset.duplicate(true)
	match action:
		"add_spell":
			if el1():
				if p.cards.size() >= ELDuelCosts.EL1_BOOK: return null
				p.cards.append(value)
				# Runes are bought separately on the Runes tab.
				p.runes.append(0)
			else:
				if p.cards.size() < ELDuelCosts.EL2_DECK: p.cards.append(value)
				else: p.reserve[value] = int(p.reserve.get(value, 0)) + 1
		"remove_slot":
			if int(value) < 0 or int(value) >= p.cards.size(): return null
			p.cards.remove_at(int(value))
			if int(value) < p.runes.size(): p.runes.remove_at(int(value))
		"deck_to_reserve":
			if int(value) < 0 or int(value) >= p.cards.size(): return null
			var card: String = p.cards[int(value)]
			p.cards.remove_at(int(value))
			p.reserve[card] = int(p.reserve.get(card, 0)) + 1
		"reserve_to_deck":
			if not p.reserve.has(value) or p.cards.size() >= ELDuelCosts.EL2_DECK: return null
			p.cards.append(value)
			p.reserve[value] = int(p.reserve[value]) - 1
			if int(p.reserve[value]) <= 0: p.reserve.erase(value)
		"remove_reserve":
			if not p.reserve.has(value): return null
			p.reserve[value] = int(p.reserve[value]) - 1
			if int(p.reserve[value]) <= 0: p.reserve.erase(value)
		"add_rune":
			if int(value) < 0 or int(value) >= p.cards.size() or _cantrip(p.cards[int(value)]): return null
			while p.runes.size() < p.cards.size(): p.runes.append(0)
			if int(p.runes[int(value)]) >= ELDuelCosts.rune_capacity(p.skills): return null
			p.runes[int(value)] = int(p.runes[int(value)]) + 1
		"remove_rune":
			if int(value) < 0 or int(value) >= p.runes.size() or int(p.runes[int(value)]) <= 0: return null
			p.runes[int(value)] = int(p.runes[int(value)]) - 1
		"add_skill":
			if p.skills.has(value):
				if int(p.skills[value]) >= ELHeroSkills.MAX_RANK: return null
				p.skills[value] = int(p.skills[value]) + 1
			else:
				if p.skills.size() >= ELDuelCosts.MAX_SKILLS: return null
				p.skills[value] = 0
		"remove_skill":
			if not p.skills.has(value): return null
			if int(p.skills[value]) == 0: p.skills.erase(value)
			else: p.skills[value] = int(p.skills[value]) - 1
		"set_spec":
			if p.specialization == value: return null
			p.specialization = value
		"add_artifact":
			# Copies are allowed; the second game's hero has five cells.
			var limit := ELDuelCosts.artifact_limit(profile())
			if not artifact_choices().has(value) or (limit >= 0 and p.artifacts.size() >= limit): return null
			p.artifacts.append(value)
		"remove_artifact":
			# The first copy, as the second game removes by name.
			var at: int = p.artifacts.find(value)
			if at < 0: return null
			p.artifacts.remove_at(at)
		"remove_artifact_at":
			if int(value) < 0 or int(value) >= p.artifacts.size(): return null
			p.artifacts.remove_at(int(value))
	return p

func _cantrip(card: String) -> bool:
	return profile().table("CombatSpells").get(card, {}).get("Rarity") == "Cantrip"

func act(action: String, value: Variant) -> bool:
	if edit.view_only: return false
	var next: Variant = apply(editor_preset(), action, value)
	if next == null: return false
	next.name = editor_preset().name
	edit.preset = next
	refresh_editor_lists()
	update_editor()
	return true

## Price of a pending action: the cost difference it would make.
func action_price(action: String, value: Variant) -> Dictionary:
	var next: Variant = apply(editor_preset(), action, value)
	if next == null: return {}
	var before := ELDuelCosts.cost(profile(), editor_preset())
	var after := ELDuelCosts.cost(profile(), next)
	var result := {}
	for r: String in after: result[r] = int(after[r]) - int(before[r])
	return result

func resource_title(index: int) -> String:
	return profile().text("T_RESOURCE_NAME_%d" % (index + 1))

func update_editor() -> void:
	if menu.screen != "duel_editor" or edit.is_empty(): return
	var p := editor_preset()
	var price := ELDuelCosts.cost(profile(), p)
	var limit := ELDuelCosts.budget(profile(), int(p.resource_level))
	var short := ELDuelCosts.shortfall(profile(), price, int(p.resource_level))
	var selected := selected_price()
	var resources := ELDuelCosts.resources(profile())
	for i in resources.size():
		var r: String = resources[i]
		if menu.labels.has("cost_" + r):
			menu.labels["cost_" + r].text = str(price[r])
			menu.labels["cost_" + r].add_theme_color_override("font_color", RED if short.has(r) else ELFrontMenu.INK_HOVER)
		if menu.labels.has("budget_" + r): menu.labels["budget_" + r].text = str(limit[r])
		if menu.labels.has("item_" + r): menu.labels["item_" + r].text = str(selected.get(r, 0)) if not selected.is_empty() else "-"
	menu.labels.hero_level.text = str(p.level)
	menu.labels.health.text = str(ELDuelPresets.health(profile(), p))
	menu.labels.resource_level.text = str(p.resource_level)
	var problems := errors()
	var name := name_edit.text.strip_edges() if name_edit != null else ""
	var ok: Control = menu.buttons.get("editor_ok")
	if ok != null:
		ok.disabled = edit.view_only or not problems.is_empty() or name.is_empty()
		ok.tooltip_text = "\n".join(problems.map(describe_error)) if not problems.is_empty() and menu.helper_overlay() else ""
	var status: Label = menu.labels.get("errors")
	if status != null:
		# The original only disables OK; the explanation is a helper-overlay readout.
		status.visible = menu.helper_overlay()
		status.text = "View only: built-in presets cannot be changed." if edit.view_only else ("\n" if el1() else "  ·  ").join(problems.slice(0, 2 if el1() else 4).map(describe_error))
		status.add_theme_color_override("font_color", ELFrontMenu.BODY_INK if edit.view_only else RED)
	var hero_levels := ELDuelCosts.hero_levels(profile())
	var res_levels := ELDuelCosts.resource_levels(profile())
	for pair: Array in [["DecHeroLevel", int(p.level) <= hero_levels.x], ["IncHeroLevel", int(p.level) >= hero_levels.y],
			["DecResLevel", int(p.resource_level) <= res_levels.x], ["IncResLevel", int(p.resource_level) >= res_levels.y]]:
		var control: String = ("EH" if el1() else "EP") + pair[0]
		if menu.buttons.has(control): menu.buttons[control].disabled = edit.view_only or pair[1]
	if book_view != null: book_view.queue_redraw()
	if el1(): _update_el1_left()
	else: _update_el2_misc()

## Readable rule error (remake wording; the original shows none).
func describe_error(code: String) -> String:
	var part := code.get_slice(":", 1)
	match code.get_slice(":", 0):
		"budget": return "Over budget: %s" % resource_title(ELDuelCosts.resources(profile()).find(part))
		"book_size": return "The spellbook needs 1-15 spells." if el1() else "The active deck needs exactly 16 spells."
		"copies": return "More than 4 copies: %s" % spell_name(part)
		"colour": return "Another race's spell: %s" % spell_name(part)
		"runes": return "Too many runes in slot %d" % (int(part) + 1)
		"spec": return "Specialisation not allowed for this race"
		"skills": return "At most 5 skills"
		"artifacts": return "At most %d artifacts" % ELDuelCosts.artifact_limit(profile())
		"artifact": return "Artifact not sold in duels: %s" % spell_name(part)
	return code

func selected_price() -> Dictionary:
	# An artifact selected in the hero's strip shows its own price.
	var owned := int(edit.get("owned", -1))
	var artifacts: Array = editor_preset().get("artifacts", [])
	if owned >= 0 and owned < artifacts.size():
		var result := ELDuelCosts.zero(profile())
		ELDuelCosts._add(result, profile().table("CombatSpells").get(artifacts[owned], {}), "Cost")
		return result
	var pending := selected_action()
	return {} if pending.is_empty() else action_price(pending[0], pending[1])

## The buy action for the selected right-panel item (or the picked EL2 artifact).
func selected_action() -> Array:
	var art := int(edit.get("art", -1))
	if not el1() and int(edit.tab) == 1 and art >= 0:
		var choices := artifact_choices()
		return ["add_artifact", choices[art]] if art < choices.size() else []
	var item := int(edit.get("item", -1))
	if item < 0 or item >= right_items.size(): return []
	var entry: Dictionary = right_items[item]
	return [entry.action, entry.value]

func buy() -> void:
	var pending := selected_action()
	if not pending.is_empty(): act(pending[0], pending[1])

func give_back() -> void:
	var item := int(edit.get("item", -1))
	var p := editor_preset()
	if el1() and edit.tab == 2:
		act("remove_rune", int(edit.slot))
		return
	if el1() and edit.tab == 0 and int(edit.slot) >= 0:
		act("remove_slot", int(edit.slot))
		edit.slot = -1
		return
	if el1() and edit.tab == 3:
		# Back returns the artifact selected in the hero's strip.
		return_artifact()
		return
	if item < 0 or item >= right_items.size(): return
	var entry: Dictionary = right_items[item]
	match entry.action:
		"add_spell":
			var at: int = Array(p.cards).rfind(entry.value)
			if at >= 0: act("remove_slot", at)
		"add_skill": act("remove_skill", entry.value)
		"set_spec": act("set_spec", "NONE")

## Buys an artifact (copies allowed). Returns whether it was added.
func buy_artifact(code: String) -> bool:
	return act("add_artifact", code)

## Returns the artifact selected in the hero's strip.
func return_artifact() -> bool:
	var owned := int(edit.get("owned", -1))
	if owned < 0: return false
	edit.owned = -1
	if act("remove_artifact_at", owned): return true
	update_editor()
	return false

## Click on the hero's artifact strip: in the second game a picked list
## artifact is dropped into the strip; otherwise the clicked artifact is
## selected (again: deselected).
func strip_clicked(index: int) -> void:
	if edit.view_only: return
	if not el1() and int(edit.get("art", -1)) >= 0:
		var pending := selected_action()
		edit.art = -1
		var all: ItemList = menu.labels.get("all_artifacts")
		if all != null: all.deselect_all()
		if not pending.is_empty(): act(pending[0], pending[1])
		update_editor()
		return
	var artifacts: Array = editor_preset().artifacts
	edit.owned = index if index >= 0 and index < artifacts.size() and index != int(edit.get("owned", -1)) else -1
	if int(edit.owned) >= 0 and right_list != null and is_instance_valid(right_list) and not el1():
		right_list.deselect_all()
		edit.item = -1
	update_editor()

## Second game: a click on the list while a hero artifact is selected returns
## it; otherwise it picks the clicked artifact.
func artifact_list_clicked(index: int) -> void:
	if int(edit.get("owned", -1)) >= 0:
		menu.labels.all_artifacts.deselect_all()
		edit.art = -1
		return_artifact()
		return
	edit.art = index
	edit.item = -1
	if right_list != null and is_instance_valid(right_list): right_list.deselect_all()
	update_editor()

func save_editor() -> void:
	if edit.view_only or not errors().is_empty(): return
	var name := name_edit.text.strip_edges()
	if not ELDuelPresets.valid_name(name):
		var text := profile().text("T_MB_WRONG_PRESET_NAME")
		show_message(text if not text.begins_with("T_MB") else "A preset name must not be empty or contain: | \\ / : * ? \" < > . [ ] , ; =")
		return
	for preset: Dictionary in pool:
		if bool(preset.get("builtin", false)) and String(preset.name) == name and not el1():
			show_message(profile().text("T_MB_CANT_OVERWRITE_PRESET"))
			return
	var write := func():
		var failure := ELDuelPresets.save_user(profile(), editor_preset(), name)
		if not failure.is_empty():
			show_message("The preset could not be saved (%s)." % failure)
			return
		var s := state()
		s.picks[int(s.target)] = "user:" + name
		s.portraits[int(s.target)] = -1
		edit.clear()
		menu.show_screen("duel")
	if ELDuelPresets.user_exists(profile(), name) and edit.source != "user:" + name:
		show_message(profile().text("T_MB_OVERWRITE_PRESET"), write, true)
	else: write.call()

func _resource_cell(key: String, rect: Rect2, size_px := 15) -> Label:
	var label := menu._label(key, "", rect, size_px, ELFrontMenu.INK_HOVER)
	label.clip_text = true
	return label

func _right_list(rect: Rect2, icons: bool, grid := 0) -> ItemList:
	var item_list := ItemList.new()
	item_list.position = rect.position
	item_list.size = rect.size
	_transparent(item_list)
	if icons: item_list.fixed_icon_size = Vector2i(32, 32)
	if grid > 0:
		# Icon grid over the original cells (EL2 panels).
		var cell := floorf(rect.size.x / grid)
		item_list.max_columns = grid
		item_list.icon_mode = ItemList.ICON_MODE_TOP
		item_list.same_column_width = true
		item_list.fixed_column_width = int(cell)
		item_list.fixed_icon_size = Vector2i(int(cell) - 6, int(cell) - 6)
		item_list.add_theme_constant_override("h_separation", 0)
		item_list.add_theme_constant_override("v_separation", 0)
		item_list.add_theme_constant_override("icon_margin", 0)
		item_list.add_theme_constant_override("line_separation", 0)
		var empty := StyleBoxEmpty.new()
		for style in ["selected", "selected_focus", "cursor", "cursor_unfocused", "hovered"]: item_list.add_theme_stylebox_override(style, empty)
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color(0, 0, 0, 0)
		frame.border_color = ELFrontMenu.INK_HOVER
		frame.set_border_width_all(2)
		item_list.add_theme_stylebox_override("selected", frame)
		item_list.add_theme_stylebox_override("selected_focus", frame)
	menu.canvas.add_child(item_list)
	return item_list

# --- First-game editor (EditHero) ---------------------------------------------

func _build_el1_editor() -> void:
	var p := editor_preset()
	_text("EHCaption")
	_text("EHRaceText")
	_race_controls("EHRaceLeft", "EHRaceRight")
	_text("EHBP1", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	_text("EHBP2", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	var dec := _auto("EHDecHeroLevel", change_hero_level.bind(-1))
	var inc := _auto("EHIncHeroLevel", change_hero_level.bind(1))
	var level_box := _between(dec, inc)
	_value("hero_level", "", level_box)
	_value("health", "", Rect2(level_box.position + Vector2(0, 29), level_box.size))
	_text("EHResLevel", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	var rdec := _auto("EHDecResLevel", change_resource_level.bind(-1))
	var rinc := _auto("EHIncResLevel", change_resource_level.bind(1))
	_value("resource_level", "", _between(rdec, rinc))
	# Resource table: one row per resource; columns follow the EHTt1..3 tooltip
	# cells (selected item, preset cost, budget).
	var columns := [_rect("EHTt1"), _rect("EHTt2"), _rect("EHTt3")]
	var resources := ELDuelCosts.resources(profile())
	for i in resources.size():
		var y: float = columns[0].position.y + 31 + i * 35
		var r: String = resources[i]
		# The resource icons are part of the art; their names are tooltips.
		var hint := Control.new()
		hint.position = Vector2(columns[0].position.x - 40, y - 6)
		hint.size = Vector2(30, 30)
		hint.tooltip_text = resource_title(i)
		menu.canvas.add_child(hint)
		_resource_cell("item_" + r, Rect2(Vector2(columns[0].position.x, y), Vector2(columns[0].size.x, 18)))
		_resource_cell("cost_" + r, Rect2(Vector2(columns[1].position.x, y), Vector2(columns[1].size.x, 18)))
		_resource_cell("budget_" + r, Rect2(Vector2(columns[2].position.x, y), Vector2(columns[2].size.x, 18)))
	_button("EHBuy", buy)
	_button("EHBack", give_back)
	# Left: artifacts, specialisation and skills, the spellbook.
	_text("EHArtifacts")
	_text("EHSpecAndSkills")
	_text("EHSpellsText")
	# The hero's artifacts: five cells between the strip's scroll arrows.
	var strip := _artifact_strip(_rect("EHArtifactsView").grow_individual(-24, -4, -24, -4))
	_nested_button("EHEquipScrL", func(): strip.scroll(-1))
	_nested_button("EHEquipScrR", func(): strip.scroll(1))
	_text("EHHeroSpec", "", ELFrontMenu.INK_HOVER)
	for i in 5:
		_text("EHSkill%d" % (i + 1), "", ELFrontMenu.INK_HOVER, HORIZONTAL_ALIGNMENT_LEFT)
		_skill_icon_slot("EHSkill%d" % (i + 1), Vector2(-26, -2), 21)
	book_view = BookView.new()
	book_view.screen = self
	var spells := _rect("EHSpellsView")
	book_view.position = spells.position
	book_view.size = spells.size
	book_view.columns = 5
	book_view.slots = ELDuelCosts.EL1_BOOK
	menu.canvas.add_child(book_view)
	menu.labels["book"] = book_view
	# Right: five tabs over one list.
	for index in EL1_TABS.size():
		var tab := _button(EL1_TABS[index], select_tab.bind(index))
		if tab != null:
			tab.active = index == int(edit.tab)
			_caption_on(tab, menu._caption(EL1_TABS[index]), 15)
	_text("EHRightCaption%d" % (int(edit.tab) + 1))
	var area := Rect2(Vector2(548, 143) + menu.shift("EditHero"), Vector2(210, 352))
	right_list = _right_list(area, int(edit.tab) in [0, 3])
	right_list.item_selected.connect(func(index: int):
		if int(edit.tab) == 2: edit.slot = index
		edit.item = index
		update_editor())
	right_list.item_activated.connect(func(index: int):
		edit.item = index
		if int(edit.tab) == 2: edit.slot = index
		buy())
	var up_down := [["EHScrollU1", -3], ["EHScrollD1", 3]] if int(edit.tab) in [0, 2] else [["EHScrollU3", -3], ["EHScrollD3", 3]]
	for pair: Array in up_down: _button(pair[0], func(): _scroll(right_list, pair[1]))
	refresh_editor_lists()

func select_tab(index: int) -> void:
	edit.tab = index
	edit.item = -1
	edit.art = -1
	edit.owned = -1
	menu.show_screen("duel_editor")

func refresh_editor_lists() -> void:
	if right_list == null or not is_instance_valid(right_list): return
	if not el1():
		_refresh_el2_lists()
		return
	var p := editor_preset()
	var keep := right_list.get_v_scroll_bar().value
	right_list.clear()
	right_items.clear()
	if el1():
		match int(edit.tab):
			0:
				for card: String in spell_choices():
					var copies := Array(p.cards).count(card)
					right_items.append({"action": "add_spell", "value": card, "label": "%s%s" % [spell_name(card), "  ×%d" % copies if copies > 0 else ""], "icon": profile().card_icon(card)})
			1:
				for code: String in ELDuelCosts.duel_skills(profile()):
					var rank := int(p.skills.get(code, -1))
					right_items.append({"action": "add_skill", "value": code, "label": skill_name(code, maxi(rank, 0)) if rank >= 0 else skill_name(code, 0).trim_suffix(" I"), "owned": rank >= 0})
			2:
				var capacity := ELDuelCosts.rune_capacity(p.skills)
				for i in p.cards.size():
					var runes := int(p.runes[i]) if i < p.runes.size() else 0
					right_items.append({"action": "add_rune", "value": i, "label": "%d. %s  %s" % [i + 1, spell_name(p.cards[i]), "∞" if _cantrip(p.cards[i]) else "%d/%d" % [runes, capacity]]})
			3:
				for code: String in artifact_choices():
					var count := Array(p.artifacts).count(code)
					right_items.append({"action": "add_artifact", "value": code, "label": "%s%s" % [spell_name(code), "  ×%d" % count if count > 0 else ""], "icon": profile().card_icon(code), "tooltip": artifact_tooltip(code)})
			4:
				for code: String in spec_choices():
					right_items.append({"action": "set_spec", "value": code, "label": spec_name(code), "owned": p.specialization == code})
	for entry: Dictionary in right_items:
		var index := right_list.add_item(entry.label, entry.get("icon"))
		if entry.has("tooltip"): right_list.set_item_tooltip(index, entry.tooltip)
		if entry.get("owned", false): right_list.set_item_custom_fg_color(index, ELFrontMenu.INK_HOVER)
	if int(edit.item) >= 0 and int(edit.item) < right_items.size(): right_list.select(int(edit.item))
	right_list.get_v_scroll_bar().value = keep
	if book_view != null: book_view.queue_redraw()

func _skill_icon_slot(control: String, offset: Vector2, side: float) -> void:
	var rect := _rect(control)
	var icon := TextureRect.new()
	icon.position = rect.position + offset
	icon.size = Vector2(side, side)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.canvas.add_child(icon)
	menu.labels[control + "_icon"] = icon

## Owned skills, sorted by code, on the five original skill rows.
func _show_skills(prefix: String) -> void:
	var p := editor_preset()
	var codes: Array = p.skills.keys()
	codes.sort()
	for i in 5:
		var control := "%s%d" % [prefix, i + 1]
		if menu.labels.has(control): menu.labels[control].text = skill_name(codes[i], int(p.skills[codes[i]])) if i < codes.size() else ""
		if menu.labels.has(control + "_icon"): menu.labels[control + "_icon"].texture = ELBuildingMessageView.skill_icon(profile(), codes[i], int(p.skills[codes[i]])) if i < codes.size() else null

func _update_el1_left() -> void:
	var p := editor_preset()
	menu.labels.EHHeroSpec.text = spec_name(String(p.specialization))
	_show_skills("EHSkill")
	if menu.labels.has("artifacts"): menu.labels.artifacts.queue_redraw()

func _artifact_strip(rect: Rect2) -> ArtifactStrip:
	var strip := ArtifactStrip.new()
	strip.screen = self
	strip.position = rect.position
	strip.size = rect.size
	menu.canvas.add_child(strip)
	menu.labels["artifacts"] = strip
	return strip

# --- Second-game editor (EditPresetA6) ----------------------------------------

func _build_el2_editor() -> void:
	_text("EPHdrMain")
	_race_controls("EPRaceLeft", "EPRaceRight")
	for control: String in ["EPHdrLevel", "EPHdrLife"]: _text(control)
	_auto("EPDecHeroLevel", change_hero_level.bind(-1))
	_auto("EPIncHeroLevel", change_hero_level.bind(1))
	_value("hero_level", "", _rect("EPDigLevel"))
	_value("health", "", _rect("EPDigLife"))
	_text("EPHdrResLev", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	_auto("EPDecResLevel", change_resource_level.bind(-1))
	_auto("EPIncResLevel", change_resource_level.bind(1))
	_value("resource_level", "", _rect("EPDigResLev"))
	_text("EPHdrSelectedItem", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	_text("EPHdrPresetCost", null, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	# Rows: budget (resource level), selected item, preset cost; one column per resource.
	var resources := ELDuelCosts.resources(profile())
	for i in resources.size():
		var r: String = resources[i]
		_resource_cell("budget_" + r, _rect("EPRes1%d" % (i + 1)))
		_resource_cell("item_" + r, _rect("EPRes2%d" % (i + 1)))
		_resource_cell("cost_" + r, _rect("EPRes3%d" % (i + 1)))
		var tip := _rect("EPRes%dTT" % (i + 1))
		if tip.size != Vector2.ZERO:
			var hint := Control.new()
			hint.position = tip.position
			hint.size = tip.size
			hint.tooltip_text = resource_title(i)
			menu.canvas.add_child(hint)
	for pair: Array in [["EPTabSpells", 0], ["EPTabMisc", 1]]:
		var tab := FlatText.new()
		tab.menu = menu
		tab.caption = menu._caption(pair[0])
		tab.font_size = 18
		var rect := _rect(pair[0])
		tab.position = rect.position
		tab.size = rect.size
		tab.active = int(edit.tab) == pair[1]
		menu.canvas.add_child(tab)
		menu.buttons[pair[0]] = tab
		tab.pressed.connect(select_tab.bind(pair[1]))
	if int(edit.tab) == 0: _build_el2_spells()
	else: _build_el2_misc()

func _build_el2_spells() -> void:
	for control: String in ["EPHdrReserveSpells", "EPHdrDeck", "EPHdrAllSpells"]: _text(control)
	var reserve := BookView.new()
	reserve.screen = self
	reserve.reserve = true
	var bag := _rect("EPBagBounds")
	reserve.position = bag.position
	reserve.size = bag.size
	reserve.columns = 8
	reserve.slots = 16
	menu.canvas.add_child(reserve)
	menu.labels["reserve"] = reserve
	book_view = BookView.new()
	book_view.screen = self
	var deck := _rect("EPASpellsBounds")
	book_view.position = deck.position
	book_view.size = deck.size
	book_view.columns = 8
	book_view.slots = ELDuelCosts.EL2_DECK
	menu.canvas.add_child(book_view)
	menu.labels["book"] = book_view
	right_list = _right_list(_rect("EPAllSpellsBounds"), true, 5)
	right_list.item_selected.connect(func(index: int):
		edit.item = index
		update_editor())
	right_list.item_activated.connect(func(index: int):
		edit.item = index
		buy())
	_button("EPScrollUp2", func(): _scroll(right_list, -3))
	_button("EPScrollDown2", func(): _scroll(right_list, 3))
	_button("EPScrollUp1", func(): reserve.scroll(-1))
	_button("EPScrollDown1", func(): reserve.scroll(1))
	_refresh_el2_lists()

func _build_el2_misc() -> void:
	for control: String in ["EPHdrSpec", "EPHdrSkills", "EPHdrArtifacts", "EPHdrAllSkills", "EPHdrAllArtifacts"]: _text(control)
	_text("EPActiveSpec", "", ELFrontMenu.INK_HOVER, HORIZONTAL_ALIGNMENT_LEFT)
	var drop := _button("EPDrop1Btn", open_spec_menu)
	if drop != null: menu.buttons["spec_drop"] = drop
	for i in 5:
		_text("EPSkill%d" % (i + 1), "", ELFrontMenu.INK_HOVER, HORIZONTAL_ALIGNMENT_LEFT)
		_skill_icon_slot("EPSkill%d" % (i + 1), Vector2(-36, 2), 21)
	var own := Button.new()
	own.flat = true
	var skill_rect := _rect("EPSkillsBounds")
	own.position = skill_rect.position
	own.size = skill_rect.size
	own.focus_mode = Control.FOCUS_NONE
	own.tooltip_text = "Double-click a skill to lower or remove it."
	own.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.double_click:
			var row := int((event.position.y) / 26.0)
			var codes: Array = editor_preset().skills.keys()
			codes.sort()
			if row >= 0 and row < codes.size(): act("remove_skill", codes[row]))
	menu.canvas.add_child(own)
	# Artifacts: pick one in the list and drop it on the hero's cells, or pick
	# a hero artifact and drop it back on the list (double-click buys,
	# right-click or double-click on the hero's cell returns).
	var artifacts := _right_list(_rect("EPAllArtifactsBounds"), true, 8)
	menu.labels["all_artifacts"] = artifacts
	right_list = _right_list(_rect("EPAllSkillsBounds"), true, 8)
	right_list.item_selected.connect(func(index: int):
		edit.item = index
		edit.art = -1
		edit.owned = -1
		artifacts.deselect_all()
		update_editor())
	right_list.item_activated.connect(func(index: int):
		edit.item = index
		edit.art = -1
		buy())
	artifacts.item_clicked.connect(func(index: int, _at: Vector2, mouse: int):
		if mouse == MOUSE_BUTTON_LEFT: artifact_list_clicked(index))
	artifacts.item_activated.connect(func(index: int):
		edit.owned = -1
		edit.art = -1
		artifacts.deselect_all()
		buy_artifact(artifact_choices()[index]))
	artifacts.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and artifacts.get_item_at_position(event.position, true) < 0 and int(edit.owned) >= 0:
			return_artifact())
	_button("EPScrollUp3", func(): _scroll(artifacts, -2))
	_button("EPScrollDown3", func(): _scroll(artifacts, 2))
	_artifact_strip(_rect("EPArtifactsBounds"))
	_refresh_el2_lists()

func open_spec_menu() -> void:
	var popup := PopupMenu.new()
	var choices := spec_choices()
	for code: String in choices: popup.add_item(spec_name(code))
	popup.index_pressed.connect(func(index: int):
		act("set_spec", choices[index])
		popup.queue_free())
	popup.popup_hide.connect(popup.queue_free)
	menu.add_child(popup)
	menu.labels["spec_menu"] = popup
	var rect := _rect("EPActiveSpec")
	var at := menu.canvas.get_global_transform_with_canvas() * (rect.position + Vector2(0, rect.size.y))
	popup.popup(Rect2i(Vector2i(at), Vector2i(int(rect.size.x * menu.scale_factor), 0)))

func _refresh_el2_lists() -> void:
	if right_list == null: return
	var p := editor_preset()
	var keep := right_list.get_v_scroll_bar().value
	right_list.clear()
	right_items.clear()
	if int(edit.tab) == 0:
		for card: String in spell_choices():
			var copies := Array(p.cards).count(card) + int(p.reserve.get(card, 0))
			var row: Dictionary = profile().table("CombatSpells")[card]
			var price := []
			for r: String in ELDuelCosts.EL2_RESOURCES: price.append(int(row.get("Cost" + r, 0)))
			right_items.append({"action": "add_spell", "value": card, "label": "%s\n%d / %d / %d%s" % [spell_name(card), price[0], price[1], price[2], "  ×%d" % copies if copies > 0 else ""], "icon": profile().card_icon(card)})
	else:
		for code: String in ELDuelCosts.duel_skills(profile()):
			var rank := int(p.skills.get(code, -1))
			right_items.append({"action": "add_skill", "value": code, "label": skill_name(code, mini(rank + 1, 2)), "owned": rank >= 0,
				"icon": ELBuildingMessageView.skill_icon(profile(), code, mini(rank + 1, 2))})
		var all: ItemList = menu.labels.get("all_artifacts")
		if all != null and is_instance_valid(all) and all.item_count == 0:
			for code: String in artifact_choices():
				var index := all.add_item("", profile().card_icon(code))
				all.set_item_tooltip(index, artifact_tooltip(code))
		if menu.labels.has("artifacts"): menu.labels.artifacts.queue_redraw()
	for entry: Dictionary in right_items:
		# Icon grid: the name and price are the tooltip.
		var index := right_list.add_item("", entry.get("icon"))
		right_list.set_item_tooltip(index, entry.label)
		if entry.get("owned", false) and int(p.skills.get(entry.value, -1)) >= ELHeroSkills.MAX_RANK: right_list.set_item_icon_modulate(index, Color(0.5, 0.5, 0.5))
	if int(edit.item) >= 0 and int(edit.item) < right_items.size(): right_list.select(int(edit.item))
	right_list.get_v_scroll_bar().value = keep
	if menu.labels.has("reserve"): menu.labels.reserve.queue_redraw()
	if book_view != null: book_view.queue_redraw()

func _update_el2_misc() -> void:
	if int(edit.tab) == 0:
		if menu.labels.has("reserve"): menu.labels.reserve.queue_redraw()
		return
	var p := editor_preset()
	if menu.labels.has("EPActiveSpec"): menu.labels.EPActiveSpec.text = spec_name(String(p.specialization))
	_show_skills("EPSkill")

# --- Round result / duel summary ----------------------------------------------

## Shows the RoundResult panel over the battle after a round
## (CDuelIntermediateScreen). `last` is that round from side 0's view: win 1,
## draw 0, loss -1. The second game shows it after every round: between rounds
## (header T_RR_HDR_END_OF_ROUND, verdict T_RR_ROUND_*, Surrender = RRCancel)
## and, with `final`, at the end of the match (T_RR_HDR_END_OF_DUEL, the
## match verdict T_RR_DUEL_*, and "Save duel replay" in RRCancel's place).
func show_round(duel_match: ELDuelMatch, names: Array, last := 0, final := false) -> void:
	round_info = {"match": duel_match, "names": names, "last": last, "final": final}
	menu.show_screen("duel_round")

## Final duel summary after the last round of a match of two or more rounds:
## the T_MB_DUEL_RESULT_1..3 message box.
func show_result(duel_match: ELDuelMatch, names: Array) -> void:
	round_info = {"match": duel_match, "names": names}
	menu.show_screen("duel_result")

func summary_text() -> String:
	var m: ELDuelMatch = round_info.match
	var names: Array = round_info.get("names", ["", ""])
	var lines: Array[String] = [profile().text("T_MB_DUEL_RESULT_1"), ""]
	for side in 2: lines.append(profile().text("T_MB_DUEL_RESULT_2") % [names[side], m.wins[side]])
	lines.append(profile().text("T_MB_DUEL_RESULT_3") % m.draws)
	return "\n".join(lines)

func build_result() -> void:
	if round_info.get("match") == null: return
	# Wider than the 200 px default so the two preset names fit on their lines.
	show_message(summary_text(), func(): menu.duel_round_closed.emit(true), false, 360.0)

## Hero picture boxes of the RoundResult art (measured from the panel art:
## EL1 above each score, EL2 at the outer ends).
func _round_boxes() -> Array[Rect2]:
	var offset := menu.shift("RoundResult")
	if el1():
		var a := _rect("RRNumber1")
		var b := _rect("RRNumber2")
		return [Rect2(a.position + Vector2(1, -66), Vector2(a.size.x, 54)), Rect2(b.position + Vector2(1, -66), Vector2(b.size.x, 54))]
	# Second game: two 100x50 cells.
	return [Rect2(Vector2(161, 282) + offset, Vector2(100, 50)), Rect2(Vector2(547, 282) + offset, Vector2(100, 50))]

## Second game: the hero tooltip over a round result cell (the map's
## hero tooltip): name, life and level, then the active specialisation. Life
## is the preset hero's starting health. The tooltip carries no portrait.
func round_hero_tooltip(title: String, preset: Dictionary, template: String) -> String:
	var source := profile()
	var lines := "%s\n%s: %d\n%s: %d" % [title, source.text("T_LIFE").strip_edges(), ELDuelPresets.health(source, preset, template), source.text("T_LEVEL").strip_edges(), int(preset.get("level", 1))]
	var code := String(preset.get("specialization", ""))
	var spec: Dictionary = source.table("HeroesSpecs").get(code, {})
	if code != ELSecondMapTooltips.NO_SPECIALIZATION and not spec.is_empty():
		lines += "\n" + source.text("T_TT_SPECIALIZATION_HDR").strip_edges() + " " + source.text(str(spec.get("Name", ""))).strip_edges()
		lines += "\n" + source.text(str(spec.get("Desc", ""))).strip_edges()
	return lines

func build_round() -> void:
	var m: ELDuelMatch = round_info.get("match")
	if m == null: return
	var names: Array = round_info.get("names", ["", ""])
	var final := bool(round_info.get("final", false))
	var pattern := menu._caption("RRCaption")
	if not el1(): pattern = profile().text("T_RR_HDR_END_OF_DUEL" if final else "T_RR_HDR_END_OF_ROUND").strip_edges()
	_text("RRCaption", pattern % [m.played, m.rounds] if pattern.count("%d") == 2 else pattern)
	var boxes := _round_boxes()
	for side in 2:
		var number := _text("RRNumber%d" % (side + 1), str(m.wins[side]), ELFrontMenu.INK_HOVER)
		if number != null: number.add_theme_font_size_override("font_size", 26)
		var preset: Dictionary = m.presets[side]
		var name := String(m.templates[side]) if not String(m.templates[side]).is_empty() else ELDuelPresets.default_template(profile(), String(preset.get("faction", "Red")))
		var row: Dictionary = profile().table("HeroTemplates").get(name, {})
		var picture := TextureRect.new()
		picture.position = boxes[side].position
		picture.size = boxes[side].size
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not row.is_empty(): picture.texture = profile().portrait(int(row.Face))
		picture.tooltip_text = String(names[side]) if el1() else round_hero_tooltip(String(names[side]), preset, name)
		menu.canvas.add_child(picture)
		menu.labels["round_portrait%d" % side] = picture
	# Only the second game's panel carries a round verdict (RRRoundResult).
	var last := int(round_info.get("last", 0))
	if not el1():
		var key: String = (["T_RR_DUEL_LOSE", "T_RR_DUEL_DRAW", "T_RR_DUEL_WIN"][m.result(0) + 1]) if final else (["T_RR_ROUND_LOSE", "T_RR_ROUND_DRAW", "T_RR_ROUND_WIN"][last + 1])
		var verdict := profile().text(key).strip_edges()
		_text("RRRoundResult", verdict % m.played if verdict.count("%d") == 1 else verdict, ELFrontMenu.INK_HOVER)
	var ok := _button("RROK", func(): menu.duel_round_closed.emit(true))
	if ok != null: ok.tooltip_text = "OK" if final else "Next round"
	if el1() or not final:
		var cancel := _button("RRCancel", func(): menu.duel_round_closed.emit(false))
		if cancel != null and el1(): cancel.tooltip_text = "End the duel"
	if el1():
		# The first game has no replays (and no RRSave art).
		var none := _button("RRSave", func(): pass)
		if none != null:
			none.disabled = true
			none.tooltip_text = ELFrontMenu.NO_REPLAYS
	elif final:
		# Save duel replay: the match's recorded rounds (ReplayScreen, save mode).
		var save := _button("RRSave", func(): menu.show_screen("replay_save"))
		if save != null:
			var recording: ELDuelRecording = menu.replay_ui.recording
			save.disabled = recording == null or not recording.complete()
			save.tooltip_text = menu.text("CtrlTTRRSave").strip_edges() if not save.disabled else "This duel was not recorded from its start (it was resumed from a saved game)."
			_caption_on(save, menu._caption("RRSave"), 14, ELFrontMenu.INK_DISABLED if save.disabled else ELFrontMenu.INK)

# --- Small controls --------------------------------------------------------------

## Text-only toggle drawn in the original serif (DuSortName, EL2 editor tabs).
class FlatText extends BaseButton:
	var menu: ELFrontMenu
	var caption := ""
	var font_size := 17
	var active := false:
		set(value):
			active = value
			queue_redraw()

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hover := get_draw_mode() in [DRAW_HOVER, DRAW_HOVER_PRESSED]
		var color := ELFrontMenu.INK_HOVER if active or hover else ELFrontMenu.TITLE_INK
		if active: draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.7, 0.4, 0.14))
		var text_size := menu.serif.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var at := Vector2((size.x - text_size.x) * 0.5, (size.y - text_size.y) * 0.5 + menu.serif.get_ascent(font_size))
		draw_string(menu.serif, at + Vector2(1, 1), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
		draw_string(menu.serif, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## Clickable hero frame; the list's target side is outlined.
class SideFrame extends BaseButton:
	var screen: ELDuelScreen
	var side := 0

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		if int(screen.state().target) == side:
			draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(1.0, 0.85, 0.5, 0.55), false, 1.5)

## Preset list: Random first, then race marker, resource level and name. Rows
## above the current level are grey; the rows chosen for the two
## sides carry their side number.
class PresetList extends Control:
	var screen: ELDuelScreen
	var offset := 0
	var columns: Array = [15, 50, 70]
	const ROW := 20.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func visible_rows() -> int:
		return int(size.y / ROW)

	func scroll(step: int) -> void:
		offset = clampi(offset + step, 0, maxi(0, screen.rows().size() - visible_rows()))
		queue_redraw()

	## Row rectangle (local) of a list index, or an empty rect when scrolled away.
	func row_rect(index: int) -> Rect2:
		var at := index - offset
		if at < 0 or at >= visible_rows(): return Rect2()
		return Rect2(Vector2(0, at * ROW), Vector2(size.x, ROW))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: scroll(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: scroll(1)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				screen.choose_row(offset + int(event.position.y / ROW))
			accept_event()

	func _draw() -> void:
		var shown := screen.rows()
		offset = clampi(offset, 0, maxi(0, shown.size() - visible_rows()))
		var s := screen.state()
		var font := screen.menu.serif
		for at in visible_rows():
			var index := offset + at
			if index >= shown.size(): break
			var preset: Dictionary = shown[index]
			var y := at * ROW
			var id := String(preset.get("id", ""))
			var sides: Array[int] = []
			for side in 2:
				if String(s.picks[side]) == id: sides.append(side)
			if sides.has(int(s.target)): draw_rect(Rect2(0, y, size.x, ROW), Color(0.85, 0.7, 0.4, 0.2))
			var grey := not preset.is_empty() and int(preset.resource_level) > int(s.level)
			var ink := ELDuelScreen.GREY if grey else ELFrontMenu.BODY_INK
			var baseline := y + (ROW - font.get_height(15)) * 0.5 + font.get_ascent(15)
			if preset.is_empty():
				draw_string(font, Vector2(columns[2], baseline), screen.profile().text(ELDuelScreen.RANDOM_KEY), HORIZONTAL_ALIGNMENT_LEFT, size.x - columns[2] - 20, 15, ink)
			else:
				var colour: Color = ELDuelScreen.RACE_COLOURS.get(String(preset.faction), Color.WHITE)
				if grey: colour = colour.darkened(0.45)
				var centre := Vector2(columns[0], y + ROW * 0.5)
				draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -6), centre + Vector2(6, 0), centre + Vector2(0, 6), centre + Vector2(-6, 0)]), colour)
				var level := str(int(preset.resource_level))
				draw_string(font, Vector2(columns[1] - font.get_string_size(level, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x * 0.5, baseline), level, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
				var name := String(preset.name)
				if not bool(preset.get("builtin", true)): name = "• " + name
				draw_string(font, Vector2(columns[2], baseline), name, HORIZONTAL_ALIGNMENT_LEFT, size.x - columns[2] - 22, 15, ink)
			var marks := "".join(sides.map(func(side: int): return str(side + 1)))
			if not marks.is_empty():
				draw_string(font, Vector2(size.x - 18, baseline), marks, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ELFrontMenu.INK_HOVER)

## Spellbook slots (EL1 15 with rune counts; EL2 16-spell active deck) or the
## EL2 reserve. Click selects a slot; double-click returns it (EL1) or moves it
## between deck and reserve (EL2); right-click removes a reserve copy.
class BookView extends Control:
	var screen: ELDuelScreen
	var columns := 5
	var slots := 15
	var reserve := false
	var offset := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func cell() -> Vector2:
		var w := size.x / columns
		return Vector2(w, minf(w, size.y / maxi(1, ceili(float(slots) / columns))))

	func entries() -> Array:
		var p := screen.editor_preset()
		if not reserve:
			var result: Array = []
			for i in p.cards.size(): result.append({"card": p.cards[i], "count": int(p.runes[i]) if i < p.runes.size() else 0})
			return result
		var codes: Array = p.reserve.keys()
		codes.sort()
		return codes.map(func(code: String): return {"card": code, "count": int(p.reserve[code])})

	func scroll(step: int) -> void:
		var rows := ceili(float(entries().size()) / columns)
		var shown := int(size.y / cell().y)
		offset = clampi(offset + step, 0, maxi(0, rows - shown))
		queue_redraw()

	func slot_at(point: Vector2) -> int:
		var c := cell()
		var index := (int(point.y / c.y) + offset) * columns + int(point.x / c.x)
		return index if index < entries().size() else -1

	func slot_rect(index: int) -> Rect2:
		var c := cell()
		var row := index / columns - offset
		return Rect2(Vector2((index % columns) * c.x, row * c.y), c)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed): return
		var index := slot_at(event.position)
		accept_event()
		if index < 0: return
		var entry: Dictionary = entries()[index]
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if reserve: screen.act("remove_reserve", entry.card)
			else: screen.act("remove_slot", index)
			return
		if event.button_index != MOUSE_BUTTON_LEFT: return
		if event.double_click:
			if reserve: screen.act("reserve_to_deck", entry.card)
			elif screen.el1(): screen.act("remove_slot", index)
			else: screen.act("deck_to_reserve", index)
			screen.edit.slot = -1
		elif not reserve:
			screen.edit.slot = index
			queue_redraw()

	func _draw() -> void:
		var list := entries()
		var c := cell()
		var font := screen.menu.serif
		var p := screen.editor_preset()
		for index in list.size():
			var rect := slot_rect(index)
			if rect.position.y < -1 or rect.end.y > size.y + 1: continue
			var icon_rect := Rect2(rect.position + Vector2(2, 2), Vector2(minf(c.x, c.y) - 4, minf(c.x, c.y) - 4))
			draw_texture_rect(screen.profile().card_icon(list[index].card), icon_rect, false)
			if not reserve and int(screen.edit.get("slot", -1)) == index: draw_rect(icon_rect, ELFrontMenu.INK_HOVER, false, 2)
			var count: int = list[index].count
			var label := "" if (not reserve and not screen.el1()) else (str(count) if not (screen.el1() and screen._cantrip(list[index].card)) else "∞")
			if reserve: label = "×%d" % count
			if not label.is_empty():
				draw_string_outline(font, icon_rect.position + Vector2(3, icon_rect.size.y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color.BLACK)
				draw_string(font, icon_rect.position + Vector2(3, icon_rect.size.y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9de2d8"))
		if not reserve:
			var count_text := "%d / %d" % [p.cards.size(), slots]
			draw_string(font, Vector2(size.x - font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, -4), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ELFrontMenu.BODY_INK)

## The hero's artifacts in five cells (EL1 EHArtifactsView between its scroll
## arrows, EL2 EPArtifactsBounds). Click selects (EL2: drops a picked list
## artifact); double-click or right-click returns the artifact.
class ArtifactStrip extends Control:
	var screen: ELDuelScreen
	const CELLS := 5
	var offset := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func cell() -> Vector2:
		return Vector2(size.x / CELLS, size.y)

	func scroll(step: int) -> void:
		offset = clampi(offset + step, 0, maxi(0, screen.editor_preset().artifacts.size() - CELLS))
		queue_redraw()

	## Preset index under a local point, or -1 (an empty cell).
	func index_at(point: Vector2) -> int:
		var index := offset + int(point.x / cell().x)
		return index if point.x >= 0 and index < screen.editor_preset().artifacts.size() else -1

	func cell_rect(index: int) -> Rect2:
		return Rect2(Vector2((index - offset) * cell().x, 0), cell())

	func _get_tooltip(at: Vector2) -> String:
		var index := index_at(at)
		return screen.artifact_tooltip(screen.editor_preset().artifacts[index]) if index >= 0 else ""

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed): return
		accept_event()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: scroll(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: scroll(1)
		var index := index_at(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and event.double_click):
			if index >= 0 and not screen.edit.view_only:
				screen.edit.owned = index
				screen.return_artifact()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			screen.strip_clicked(index)
		queue_redraw()

	func _draw() -> void:
		var list: Array = screen.editor_preset().get("artifacts", [])
		offset = clampi(offset, 0, maxi(0, list.size() - CELLS))
		tooltip_text = " " if not list.is_empty() else ""
		var c := cell()
		var side := minf(c.x, c.y) - 6
		for index in range(offset, mini(list.size(), offset + CELLS)):
			var rect := cell_rect(index)
			var icon := Rect2(rect.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
			draw_texture_rect(screen.profile().card_icon(list[index]), icon, false)
			if int(screen.edit.get("owned", -1)) == index: draw_rect(icon, ELFrontMenu.INK_HOVER, false, 2)
		if list.size() > CELLS:
			var count := "%d" % list.size()
			draw_string(screen.menu.serif, Vector2(size.x - 14, size.y - 3), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ELFrontMenu.BODY_INK)

## Texture pieces drawn above the panel art (the editor's race picture).
class PieceView extends Control:
	var pieces: Array = []

	func _draw() -> void:
		for piece: Dictionary in pieces: draw_texture_rect_region(piece.texture, piece.rect, piece.source)

## Input blocker under the message box, drawing the edition's original frame
## (a plain frame only when the art is missing).
class MessageShade extends Control:
	var box := Rect2()
	var first := false
	var frame: Texture2D
	var shadow: Texture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		if frame == null:
			draw_rect(box, Color("1b1712f2"))
			draw_rect(box, Color("8a6d45"), false, 2)
		elif first: ELFirstMessageBox.draw_frame(self, frame, shadow, box)
		else: ELSecondDialogueBox.draw_world_frame(self, frame, box)
