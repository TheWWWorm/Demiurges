class_name ELCombatRail
extends Control
## The original CombatScreen's radio pairs, scroll arrows and the per-side
## counters beside the hero portraits. Both editions draw the same:
## Graveyard / Enchantments choose the upper icon strip, Hand / Artifacts the
## card rail; the selected radio's pressed art, the hover art, and a count for
## each radio of the displayed hero and of the opponent's column, where the
## ToolTip controls (EnemyArtifacts, ...) explain them. SpellScrollLeft/Right
## move the card rail 15 px per press and repeat while held.
## Coordinates are the original 800x600 layout, bottom-anchored like ELHudFrame.
signal tab_selected(artifacts: bool)
signal strip_selected(graveyard: bool)
signal strip_item(index: int)

const ROWS := ["Graveyard", "Enchantments", "Hand", "Artifacts"]
const ENEMY := ["EnemyGraveyard", "EnemyEnchantments", "EnemyHand", "EnemyArtifacts"]
const COUNT_COLOR := Color("d6bb88")
## Digit centres: the left column at x 104, the opponent's at x 704, one row
## per radio; a pressed radio's count moves by one pixel right and down.
const OWN_COUNTS := [Vector2(104, 500), Vector2(104, 523), Vector2(104, 557), Vector2(104, 580)]
const ENEMY_COUNTS := [Vector2(704, 500), Vector2(704, 528), Vector2(704, 556), Vector2(704, 584)]
## Bold Arial in a 17 px cell (about 15 px em), antialiased, with the digits'
## top 10 px above the centre.
const COUNT_SIZE := 15
const SCROLL_STEP := 15
## 3 px per frame of the original's 60 Hz update.
const SCROLL_SPEED := 180.0
const REPEAT := 0.3

var artifacts_shown := false
var graveyard_shown := false
var strip: ELCombatStrip
## The card rail the spell arrows scroll; set by the combat view.
var hand_scroll: ScrollContainer
var spell_arrows: Array[ELCutPartButton] = []
var _scroll_target := 0.0
var _held := 0
var _repeat := 0.0
var _animating := false
var _font: SystemFont
var _profile: ELProfile
## Per side: [graveyard, enchantments, hand, artifacts]; side 0 is on the left.
var counts: Array = [[0, 0, 0, 0], [0, 0, 0, 0]]
var tabs: Dictionary = {}
var enemy_tips: Array[Control] = []
var _art: Dictionary = {}
var _rects: Dictionary = {}
var _enemy_rects: Array[Rect2] = []

func build(profile: ELProfile) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	tabs.clear()
	enemy_tips.clear()
	_art.clear()
	_rects.clear()
	_enemy_rects.clear()
	artifacts_shown = false
	graveyard_shown = false
	spell_arrows.clear()
	_profile = profile
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	_font.font_weight = 700
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for row: Dictionary in profile.table("CutParts").values():
		var control := str(row.get("Ctrl", ""))
		if control not in ROWS: continue
		var masks: Variant = row.get("Msk", [])
		var list: Array = masks if masks is Array else [masks]
		var state := "push" if list == ["Push"] else ("hover" if list.has("Light") and list.has("Free") else ("hover_push" if list.has("Light") and list.has("Push") else ""))
		var texture := profile.texture(paths.get(row.get("Txt", ""), ""))
		if state.is_empty() or texture == null: continue
		_art["%s:%s" % [control, state]] = {"texture": texture, "source": Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH),
			"rect": Rect2(row.ScrL, row.ScrT, row.get("ScrW", row.TxtW), row.get("ScrH", row.TxtH))}
		if state == "push": _rects[control] = _art["%s:push" % control].rect
	var controls := {}
	for row: Dictionary in profile.table("Controls").values():
		if row.get("Parent", "") == "CombatScreen": controls[str(row.get("Name", ""))] = row
	for name: String in ROWS:
		if not _rects.has(name): continue
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		for style in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		button.tooltip_text = profile.text(str(controls.get(name, {}).get("ToolTip", "")))
		button.set_meta("rail_tab", name)
		ELUiSounds.bind(button, profile, name)
		button.mouse_entered.connect(queue_redraw)
		button.mouse_exited.connect(queue_redraw)
		if name in ["Hand", "Artifacts"]: button.pressed.connect(_select.bind(name == "Artifacts"))
		else: button.pressed.connect(select_strip.bind(name == "Graveyard"))
		add_child(button)
		tabs[name] = button
	for name: String in ENEMY:
		var row: Dictionary = controls.get(name, {})
		if not row.has("Left"): continue
		_enemy_rects.append(Rect2(row.Left, row.Top, row.Width, row.Height))
		var tip := Control.new()
		tip.mouse_filter = Control.MOUSE_FILTER_PASS
		tip.tooltip_text = profile.text(str(row.get("ToolTip", "")))
		tip.set_meta("enemy_count", name)
		add_child(tip)
		enemy_tips.append(tip)
	strip = ELCombatStrip.new()
	add_child(strip)
	strip.build(profile)
	strip.item_pressed.connect(func(index: int): strip_item.emit(index))
	for control: String in ["SpellScrollLeft", "SpellScrollRight"]:
		var row: Dictionary = controls.get(control, {})
		var rect := Rect2(row.get("Left", 131 if control.ends_with("Left") else 469), row.get("Top", 542), row.get("Width", 17), row.get("Height", 48))
		var arrow := ELCutPartButton.new()
		arrow.build(profile, control, rect)
		arrow.focus_mode = Control.FOCUS_NONE
		arrow.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		arrow.dim_disabled = false
		var direction := -1 if control.ends_with("Left") else 1
		arrow.set_meta("spell_arrow", direction)
		arrow.set_meta("rect", rect)
		arrow.pressed.connect(_press_spell_arrow.bind(direction))
		arrow.button_up.connect(func(): _held = 0)
		arrow.mouse_entered.connect(arrow.queue_redraw)
		arrow.mouse_exited.connect(arrow.queue_redraw)
		add_child(arrow)
		spell_arrows.append(arrow)
	set_process(true)
	layout()

## Graveyard / Enchantments: which list the upper strip shows.
func select_strip(graveyard: bool) -> void:
	if graveyard_shown == graveyard: return
	graveyard_shown = graveyard
	queue_redraw()
	strip_selected.emit(graveyard)

## Mirrors the view's choice without announcing it.
func show_strip(graveyard: bool) -> void:
	if graveyard_shown == graveyard: return
	graveyard_shown = graveyard
	queue_redraw()

func _select(artifacts: bool) -> void:
	if artifacts_shown == artifacts: return
	artifacts_shown = artifacts
	queue_redraw()
	tab_selected.emit(artifacts)

## Places the controls for the current size: the left column stays put and the
## opponent's column follows the right edge, as the panel art does.
func layout() -> void:
	for name: String in tabs:
		var rect := _place(_rects[name])
		tabs[name].position = rect.position
		tabs[name].size = rect.size
	for i in enemy_tips.size():
		var rect := _place(_enemy_rects[i])
		enemy_tips[i].position = rect.position
		enemy_tips[i].size = rect.size
	if strip != null:
		strip.position = Vector2(ELCombatStrip.CLIP.position.x, ELCombatStrip.CLIP.position.y + size.y - 600.0)
		strip.size = Vector2(ELCombatStrip.CLIP.size.x + maxf(0.0, size.x - 800.0), ELCombatStrip.CLIP.size.y)
		strip.layout()
	for arrow in spell_arrows:
		var rect := _place(arrow.get_meta("rect"))
		arrow.position = rect.position
		arrow.size = rect.size
	queue_redraw()

## The card rail's place between its arrows: x 151 to 467 of the original
## layout, its right end following the window edge.
func hand_rect() -> Rect2:
	return Rect2(151, size.y - 56, maxf(0.0, size.x - 800.0) + 467 - 151, 54)

func _press_spell_arrow(direction: int) -> void:
	_step_hand(direction)
	_held = direction
	_repeat = REPEAT

func _step_hand(direction: int) -> void:
	if hand_scroll == null: return
	var base := _scroll_target if _animating else float(hand_scroll.scroll_horizontal)
	_scroll_target = clampf(base + direction * SCROLL_STEP, 0.0, _hand_limit())
	_animating = true

## A card joining the hand scrolls the rail like its arrows do: a drawn card
## back to the start, a returned card far enough to show the new last card
## (EL2 `` steps left to the first item, `` steps right
## the overflow).
func reveal_hand(at_end: bool) -> void:
	if hand_scroll == null: return
	_scroll_target = INF if at_end else 0.0
	_animating = true

func _hand_limit() -> float:
	if hand_scroll == null or hand_scroll.get_child_count() == 0: return 0.0
	var content := hand_scroll.get_child(0) as Control
	return maxf(0.0, content.size.x - hand_scroll.size.x)

func _process(delta: float) -> void:
	if hand_scroll == null or spell_arrows.size() < 2: return
	var current := float(hand_scroll.scroll_horizontal)
	var limit := _hand_limit()
	if _held != 0:
		var held := spell_arrows[0 if _held < 0 else 1]
		if not held.button_pressed or held.disabled: _held = 0
		else:
			_repeat -= delta
			if _repeat <= 0.0:
				_repeat = REPEAT
				ELUiSounds.play(_profile, str(held.get_meta("ui_sound", "")))
				_step_hand(_held)
	if _animating:
		current = move_toward(current, clampf(_scroll_target, 0.0, limit), SCROLL_SPEED * delta)
		hand_scroll.scroll_horizontal = int(round(current))
		_animating = absf(current - clampf(_scroll_target, 0.0, limit)) > 0.5
	# Left is offered once the cards start more than 10 px before the rail,
	# right while they run past its end.
	spell_arrows[0].disabled = current <= 10.0
	spell_arrows[1].disabled = current >= limit - 0.5

func _place(rect: Rect2) -> Rect2:
	rect.position.y += size.y - 600.0
	if rect.position.x >= 374: rect.position.x += size.x - 800.0
	return rect

func set_counts(left: Array, right: Array) -> void:
	if counts == [left, right]: return
	counts = [left.duplicate(), right.duplicate()]
	_update_tips()
	queue_redraw()

func _update_tips() -> void:
	for i in enemy_tips.size():
		enemy_tips[i].set_meta("count", int(counts[1][i]) if i < counts[1].size() else 0)

func _draw() -> void:
	var chosen := ["Graveyard" if graveyard_shown else "Enchantments", "Artifacts" if artifacts_shown else "Hand"]
	for selected: String in chosen:
		if _art.has(selected + ":push"):
			var piece: Dictionary = _art[selected + ":push"]
			draw_texture_rect_region(piece.texture, _place(piece.rect), piece.source)
	for name: String in tabs:
		if not tabs[name].is_hovered(): continue
		var key := name + (":hover_push" if name in chosen else ":hover")
		if _art.has(key): draw_texture_rect_region(_art[key].texture, _place(_art[key].rect), _art[key].source)
	for i in ROWS.size():
		var pressed := 1.0 if ROWS[i] in chosen else 0.0
		_number(str(counts[0][i]), _place(Rect2(OWN_COUNTS[i] + Vector2(pressed, pressed), Vector2.ZERO)).position)
		_number(str(counts[1][i]), _place(Rect2(ENEMY_COUNTS[i], Vector2.ZERO)).position)

## A count centred on x with the digits' top 10 px above y; no outline.
func _number(text: String, at: Vector2) -> void:
	if _font == null: return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_SIZE).x
	# Arial digits stand 0.716 em above the baseline.
	draw_string(_font, Vector2(at.x - width / 2.0, at.y - 10.0 + COUNT_SIZE * 0.716), text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_SIZE, COUNT_COLOR)

## The artifact's original tooltip body: its name, then T_ARTIFACT_TT with the
## current charges and the template's activation turn and use interval (EL1
## adds RechargeDuration as a fourth value), then the spell's description.
static func artifact_tooltip(profile: ELProfile, item: Dictionary, title: String) -> String:
	var body := profile.text("T_ARTIFACT_TT")
	var values: Array = [int(item.get("charges", 0))]
	if item.has("custom"):
		values.append_array([int(item.custom.get("first", 0)), int(item.custom.get("gap", 0)), int(item.custom.get("r_duration", 0))])
	else:
		var row: Dictionary = profile.table("Artefacts").get(str(item.get("name", "")), {})
		values.append_array([int(row.get("FirstUsage", 0)), int(row.get("UsageGap", 0)), int(row.get("RechargeDuration", 0))])
	var wanted := body.count("%d")
	var details := body % values.slice(0, wanted) if wanted >= 1 and wanted <= values.size() and body.count("%") == wanted else str(values[0])
	return "%s\n%s\n%s" % [title, details, profile.card_description(str(item.get("spell", "")))]
