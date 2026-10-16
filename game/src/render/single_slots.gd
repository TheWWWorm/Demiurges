class_name ELSingleSlots
extends Control
## First game Single screen: the player-slot panel under the difficulty radios.
## Two columns of four 168x52 cells (slot = column * 4 + row), one per map
## player in header order; slots past the map's player count draw nothing.
## Each cell: the panel background, the race plate, the controller icon (a head
## for the human, a chip for the computer), the diplomacy icon towards the
## human (handshake for an ally and for the human itself, crossed swords for an
## enemy), the blazon and the player's name. The human cell has the frame and
## an editable name (12 characters plus one) with the session's player name;
## other cells show the map's player name. Clicking another cell moves the
## human there (Select1.wav); clicking the human's blazon opens the blazon
## choice. Choosing a map returns the human to the first slot. Start plays as
## the human's player with the typed name and the chosen blazon.

## Panel origin in the 1024 design (800 layout (409,320) + SelectMission shift).
const ORIGIN := Vector2(521, 404)
const CELL := Vector2(168, 52)
const ROWS := 4
const SLOTS := 8
const NAME_RECT := Rect2(58, 31, 103, 15)
const NAME_EDIT_HEIGHT := 23.0
const BLAZON_AT := Vector2(6, 4)
const BLAZON_FRAME_AT := Vector2(7, 4)
const RACE_AT := Vector2(58, 3)
const CONTROLLER_AT := Vector2(95, 3)
const DIPLOMACY_AT := Vector2(130, 3)
## MISSION_PANEL_9: cell background and the race plates (Chaos, Vital,
## Kinet, Synthet in the map colour order Red, Green, Blue, Black).
const BACKGROUND := Rect2(0, 0, 165, 49)
const RACE_PLATES := {"Red": Rect2(225, 0, 31, 23), "Green": Rect2(165, 24, 31, 23), "Blue": Rect2(186, 52, 31, 23), "Black": Rect2(225, 23, 31, 23)}
## MISSION_PANEL_7: controller and diplomacy icons.
const HUMAN_ICON := Rect2(225, 23, 31, 23)
const COMPUTER_ICON := Rect2(225, 138, 31, 23)
const ALLY_ICON := Rect2(225, 92, 31, 23)
const ENEMY_ICON := Rect2(225, 69, 31, 23)
## MISSION_SCREEN_1: the cell frame (human; half-transparent under the
## pointer on another cell) and the blazon hover frame.
const FRAME := Rect2(0, 0, 167, 51)
const BLAZON_FRAME := Rect2(126, 51, 41, 41)
const HOVER_TINT := Color(1, 1, 1, 127.0 / 255.0)
const NAME_INK := Color("d6bb88")

var menu: ELFrontMenu
var entry: Dictionary = {}
## The human's slot (0-based) in the chosen map.
var human := 0
var hovered := -1
var blazon_hovered := false
var edits: Array[LineEdit] = []

func setup(owner: ELFrontMenu) -> void:
	menu = owner
	name = "SingleSlots"
	position = ORIGIN
	size = Vector2(CELL.x * 2, CELL.y * ROWS)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for slot in SLOTS:
		var edit := LineEdit.new()
		edit.name = "SlotName%d" % slot
		# The edit is taller than the 15 px well; it is centred on it.
		edit.size = Vector2(NAME_RECT.size.x, NAME_EDIT_HEIGHT)
		edit.position = cell_origin(slot) + NAME_RECT.position - Vector2(0, (NAME_EDIT_HEIGHT - NAME_RECT.size.y) * 0.5)
		edit.flat = true
		edit.context_menu_enabled = false
		edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		edit.max_length = ELPlayerProfile.SLOT_NAME_LIMIT
		edit.add_theme_font_override("font", menu.arial)
		edit.add_theme_font_size_override("font_size", 16)
		edit.add_theme_color_override("font_color", NAME_INK)
		edit.add_theme_color_override("font_uneditable_color", NAME_INK)
		edit.add_theme_constant_override("minimum_character_width", 0)
		var empty := StyleBoxEmpty.new()
		for style: String in ["normal", "focus", "read_only"]: edit.add_theme_stylebox_override(style, empty)
		edit.text_changed.connect(func(value: String) -> void: if slot == human: ELPlayerProfile.choose_name(value))
		add_child(edit)
		edits.append(edit)

func cell_origin(slot: int) -> Vector2:
	return Vector2(float(slot / ROWS) * CELL.x, float(slot % ROWS) * CELL.y)

func count() -> int:
	return mini(entry.get("players", []).size(), SLOTS)

## The slot under a panel point, or -1.
func slot_at(point: Vector2) -> int:
	if point.x < 0 or point.y < 0: return -1
	var slot := int(point.x / CELL.x) * ROWS + int(point.y / CELL.y)
	return slot if point.x < CELL.x * 2 and point.y < CELL.y * ROWS and slot < count() else -1

func blazon_rect(slot: int) -> Rect2:
	return Rect2(cell_origin(slot) + BLAZON_AT, Vector2(ELBlazonScreen.BLAZON, ELBlazonScreen.BLAZON))

## A new map: the human returns to the first slot.
func show_entry(value: Dictionary, keep_slot := false) -> void:
	entry = value
	if not keep_slot or human >= count(): human = 0
	_sync_edits()
	queue_redraw()

func choose_slot(slot: int) -> void:
	if slot < 0 or slot >= count() or slot == human: return
	ELUiSounds.play(menu.profile, "Buttons/Select1.wav")
	human = slot
	_sync_edits()
	queue_redraw()

func player(slot: int) -> Dictionary:
	var players: Array = entry.get("players", [])
	return players[slot] if slot >= 0 and slot < players.size() else {}

## The player id the human plays (Start: slot + 1 in header order).
func human_player() -> int:
	return int(player(human).get("id", human + 1))

func human_name() -> String:
	return edits[human].text if human < edits.size() else ELPlayerProfile.current_name(menu.profile)

func ally(slot: int) -> bool:
	if slot == human: return true
	var relations: Dictionary = player(human).get("relations", {})
	return int(relations.get(int(player(slot).get("id", -1)), 0)) != 0

func _sync_edits() -> void:
	for slot in edits.size():
		var edit := edits[slot]
		edit.visible = slot < count()
		edit.editable = slot == human
		edit.focus_mode = Control.FOCUS_ALL if slot == human else Control.FOCUS_NONE
		# Other players' names are read-only; a click on them picks the cell.
		edit.mouse_filter = Control.MOUSE_FILTER_STOP if slot == human else Control.MOUSE_FILTER_IGNORE
		if slot == human: edit.text = ELPlayerProfile.current_name(menu.profile).left(ELPlayerProfile.SLOT_NAME_LIMIT)
		elif slot < count():
			var key := str(player(slot).get("name", ""))
			edit.text = menu.text(key).strip_edges() if not key.is_empty() else ""
		else: edit.text = ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var slot := slot_at(event.position)
		var over_blazon := slot == human and blazon_rect(human).has_point(event.position)
		if slot != hovered or over_blazon != blazon_hovered:
			hovered = slot
			blazon_hovered = over_blazon
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var slot := slot_at(event.position)
		if slot == human and blazon_rect(human).has_point(event.position):
			menu.single_ui.kept_slot = human
			menu.blazon_ui.open_dialog("single")
		else: choose_slot(slot)
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and (hovered >= 0 or blazon_hovered):
		hovered = -1
		blazon_hovered = false
		queue_redraw()

func _draw() -> void:
	var panel_9 := menu.texture_named("MISSION_PANEL_9")
	var panel_7 := menu.texture_named("MISSION_PANEL_7")
	var screen_1 := menu.texture_named("MISSION_SCREEN_1")
	for slot in count():
		var at := cell_origin(slot)
		var row := player(slot)
		if panel_9 != null: draw_texture_rect_region(panel_9, Rect2(at, BACKGROUND.size), BACKGROUND)
		if screen_1 != null and (slot == human or slot == hovered):
			draw_texture_rect_region(screen_1, Rect2(at - Vector2.ONE, FRAME.size), FRAME, Color.WHITE if slot == human else HOVER_TINT)
		var plate: Rect2 = RACE_PLATES.get(str(row.get("color", "")), Rect2())
		if panel_9 != null and plate.size.x > 0: draw_texture_rect_region(panel_9, Rect2(at + RACE_AT, plate.size), plate)
		if panel_7 != null:
			var controller := HUMAN_ICON if slot == human else COMPUTER_ICON
			draw_texture_rect_region(panel_7, Rect2(at + CONTROLLER_AT, controller.size), controller)
			var relation := ALLY_ICON if ally(slot) else ENEMY_ICON
			draw_texture_rect_region(panel_7, Rect2(at + DIPLOMACY_AT, relation.size), relation)
		var blazon: Vector2i = ELPlayerProfile.blazon if slot == human else row.get("blazon", Vector2i(-1, -1))
		menu.blazon_ui.draw_blazon(self, blazon, at + BLAZON_AT)
		if slot == human and blazon_hovered and screen_1 != null:
			draw_texture_rect_region(screen_1, Rect2(at + BLAZON_FRAME_AT, BLAZON_FRAME.size), BLAZON_FRAME)
