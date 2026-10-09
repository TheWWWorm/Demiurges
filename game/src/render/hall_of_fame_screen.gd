class_name ELHallOfFameScreen
extends RefCounted
## Hall of Fame (HallOfFame panel, both games) on the ELFrontMenu canvas: the
## campaign or scenario table (ten rows: number, name, points, campaign or
## mission title), HFSwitch between the two tables (its art and the last
## column caption follow the mode: Type1 campaign, Type2 scenario) and
## HFClose; Esc closes, Tab/Left/Right switch. The last mode shown is
## remembered. The first game returns to the main menu; the second game opens
## it from its Mission screen in the scenario table and returns there.
## Records: ELHallOfFame.
## Approximation: the cells use the art's grid under the registry captions.

## Data rows of the table art (1024 layout).
const ROW_TOP := 257.0
const ROW := 26.0
const ROW_INK := Color("d6bb88")

var menu: ELFrontMenu
var mode := "campaign"
## Table it was opened with; the second game's Close returns to the screen of
## that table (scenario: Mission screen, campaign: Campaign screen).
var opened := ""
var tables: Dictionary = {}
var cells: Array = []

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func art_exclude(target: String) -> Array:
	return []

## Opens with the mode last shown (LastHallOfFame), or the given table after a
## won mission (: 0 scenario, 1 campaign), and plays the fanfare.
func open(kind := "") -> void:
	tables = ELHallOfFame.load_tables(menu.profile)
	mode = kind if kind in ELHallOfFame.KINDS else tables.mode
	opened = mode
	tables.mode = mode
	menu.show_screen("hall_of_fame")
	menu.play_sound("Buttons/hof.wav")

func records() -> Array:
	return tables.get(mode, [])

func build_screen() -> void:
	if tables.is_empty():
		tables = ELHallOfFame.load_tables(menu.profile)
		mode = tables.mode
	menu._label("caption", menu._caption("HFCaption").replace("  ", " "), menu.control_rect("HFCaption"), 17)
	for control: String in ["HFCaption1", "HFCaption2", "HFCaption3"]:
		menu._label(control, menu._caption(control), menu.control_rect(control), 17)
	var last := "HFCaption42" if mode == "campaign" else "HFCaption41"
	menu._label("HFCaption4", menu._caption(last), menu.control_rect(last), 17)
	_switch_button()
	var close := menu._square("HFClose")
	if close != null: close.pressed.connect(close_screen)
	cells.clear()
	var list := records()
	for row in ELHallOfFame.LIMIT:
		var record: Dictionary = list[row] if row < list.size() else {}
		var top := ROW_TOP + row * ROW
		var values := [str(row + 1) if not record.is_empty() else "", str(record.get("name", "")), str(record.get("points", "")) if not record.is_empty() else "",
			ELHallOfFame.title(menu.profile, mode, str(record.get("id", ""))) if not record.is_empty() else ""]
		var line: Array = []
		for column in 4:
			var caption := menu.control_rect(["HFCaption1", "HFCaption2", "HFCaption3", last][column])
			var align := HORIZONTAL_ALIGNMENT_LEFT if column in [1, 3] else HORIZONTAL_ALIGNMENT_CENTER
			var label := menu._label("row%d_%d" % [row, column], values[column], Rect2(caption.position.x, top, caption.size.x, ROW), 16, ROW_INK, align)
			label.clip_text = true
			line.append(label)
		cells.append(line)

## HFSwitch: the Type1 (campaign) or Type2 (scenario) picture with the shared lit overlay.
func _switch_button() -> void:
	var button := menu._square("HFSwitch")
	if button == null: return
	var type := "Type1" if mode == "campaign" else "Type2"
	var offset := menu.shift("HFSwitch")
	for state: String in ["normal", "pressed"]:
		var found := menu.rows("HFSwitch", [type, "Free" if state == "normal" else "Push"])
		if not found.is_empty():
			var piece := menu.cut(found[0], offset)
			piece.extra = []
			button.parts[state] = piece
	button.pressed.connect(toggle)

func toggle() -> void:
	set_mode("scenario" if mode == "campaign" else "campaign")

func set_mode(kind: String) -> void:
	mode = kind if kind in ELHallOfFame.KINDS else "campaign"
	tables.mode = mode
	ELHallOfFame.set_mode(menu.profile, mode)
	menu.show_screen("hall_of_fame")

func close_screen() -> void:
	menu.stop_audio()
	if menu.edition == "el2" and not menu.hosted:
		menu.show_screen("mission_menu" if opened == "scenario" else "campaign_menu")
		return
	menu.leave_screen()

## Keys bound by the panel: Esc closes, Tab/Left/Right switch the table.
func key(event: InputEventKey) -> void:
	if not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE: close_screen()
		KEY_TAB, KEY_LEFT, KEY_RIGHT: toggle()

## Visible table text, row by row (number, name, points, title).
func table_text() -> Array:
	var result: Array = []
	for line: Array in cells: result.append(line.map(func(label: Label): return label.text))
	return result
