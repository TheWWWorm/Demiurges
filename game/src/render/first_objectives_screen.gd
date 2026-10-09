class_name ELFirstObjectivesScreen
extends RefCounted
## First game: the mission objectives panel ("Objectives"), opened from the
## Options screen's GOInfo button while a mission runs. Three headings
## (MOStatic1-3: mission task, victory condition, defeat condition) over the
## mission's objective, win and lose texts (MOObjectives, MOWin, MOLose), in
## the TOOLTIP window frame with a rule above the second and third headings
## and above MOOK. MOOK or Esc closes it back to the map. The second game has
## no such panel (its quests are in the Notebook).
const HEADING := Color("c9b07a")
const BODY := Color("e2d8bf")
const TEXTS := [["MOStatic1", "MOObjectives", "objective"], ["MOStatic2", "MOWin", "win_condition"], ["MOStatic3", "MOLose", "lose_condition"]]

var menu: ELFrontMenu
var panel := Rect2()
var rules: Array[float] = []
var frame: Control

func _init(owner: ELFrontMenu) -> void:
	menu = owner

static func supports(profile: ELProfile) -> bool:
	return profile != null and profile.id == "el1"

## The mission's three texts (keys objective, win_condition, lose_condition)
## from its map document.
static func mission_texts(map: ELAdventureMap) -> Dictionary:
	var result := {}
	if map == null: return result
	for key: String in ["objective", "win_condition", "lose_condition"]:
		result[key] = map.profile.text(ELXml.value(map.document, key))
	return result

func build_screen() -> void:
	panel = menu.control_rect("Objectives")
	rules.clear()
	frame = Control.new()
	frame.name = "ObjectivesFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.size = ELFrontMenu.DESIGN
	frame.draw.connect(_draw_frame)
	menu.canvas.add_child(frame)
	var texts: Dictionary = menu.mission_texts
	for index in TEXTS.size():
		var item: Array = TEXTS[index]
		var heading_row: Dictionary = menu._controls.get(item[0], {})
		var heading_rect := menu.control_rect(item[0])
		menu._label(item[0], menu._caption(item[0]), heading_rect, int(heading_row.get("FontSize", 17)), HEADING)
		if index > 0: rules.append(heading_rect.position.y - 3)
		var body_row: Dictionary = menu._controls.get(item[1], {})
		var body := menu._label(item[1], str(texts.get(item[2], "")), menu.control_rect(item[1]), int(body_row.get("FontSize", 17)), BODY)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		body.clip_text = true
	var ok := menu._square("MOOK")
	if ok != null:
		ok.tooltip_text = "OK"
		ok.pressed.connect(close)
		rules.append(ok.position.y - 5)
	frame.queue_redraw()

func close() -> void:
	menu.leave_screen()

func _draw_frame() -> void:
	var tooltip := menu.texture_named("TOOLTIP")
	ELFirstMessageBox.draw_frame(frame, tooltip, menu.texture_named("SYMBOLS"), panel)
	for y in rules: ELFirstMessageBox.draw_rule(frame, tooltip, panel, y)
