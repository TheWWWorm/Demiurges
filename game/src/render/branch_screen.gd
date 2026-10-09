class_name ELBranchScreen
extends RefCounted
## First game: the campaign branch choice (SelectCampaignBranch) shown when the
## next chapter has two candidates (chapter 7 of either campaign). The text is
## T_SELECT_CAMPAIGN_BRANCH_2 when the first candidate's human race is Chaos or
## Synthet, else _1; under it the two candidates' races (T_RACE_NAME_n) and
## their 223x226 race pictures, dim until one is clicked (swapcampaign.wav),
## which enables OK. OK opens the campaign info for that chapter. There is no
## cancel.

## Race pictures per map colour (Chaos, Vital, Kinet, Synthet).
const PICTURES := {"Red": "CAMPAIGN_PANEL_21", "Green": "CAMPAIGN_PANEL_19", "Blue": "CAMPAIGN_PANEL_18", "Black": "CAMPAIGN_PANEL_20"}
const RACE_NUMBER := {"Red": 1, "Green": 2, "Blue": 3, "Black": 4}
## Picture places in the 1024 design (800 layout (153,228) and (423,228) +
## the panel shift).
const PICTURE_AT := [Vector2(265, 312), Vector2(535, 312)]
const PICTURE_SIZE := Vector2(223, 226)
const DIM := 0x76 / 255.0
const LIT := 0xe6 / 255.0

var menu: ELFrontMenu
var choices: Array = []
var difficulty := 0
var picked := -1
var pictures: Array[Control] = []

func _init(owner: ELFrontMenu) -> void:
	menu = owner

## Colour of a candidate chapter's human player, from its map header.
func colour(index: int) -> String:
	if index < 0 or index >= choices.size(): return ""
	var row: Dictionary = choices[index]
	var header := ELSingleScenario.read_header(menu.profile, str(row.get("file_name", "")))
	var human := int(str(row.get("player", "1")))
	for player: Dictionary in header.get("players", []):
		if int(player.id) == human: return str(player.color)
	return ""

func caption_key() -> String:
	return "T_SELECT_CAMPAIGN_BRANCH_2" if colour(0) in ["Red", "Black"] else "T_SELECT_CAMPAIGN_BRANCH_1"

func open(next: Array, chosen_difficulty: int) -> void:
	choices = next.duplicate()
	difficulty = chosen_difficulty
	picked = -1
	menu.show_screen("branch")

func build() -> void:
	# Wrapping is set before the text so the label keeps its rectangle.
	var caption := menu._label("branch_text", "", menu.control_rect("SCBText"), 17)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	caption.text = menu.text(caption_key()).strip_edges()
	pictures.clear()
	for index in mini(choices.size(), 2):
		var race := colour(index)
		menu._label("branch_race%d" % (index + 1), menu.text("T_RACE_NAME_%d" % RACE_NUMBER.get(race, 1)).strip_edges(), menu.control_rect("SCBRace%d" % (index + 1)), 17)
		var picture := Picture.new()
		picture.texture = menu.texture_named(PICTURES.get(race, ""))
		picture.position = PICTURE_AT[index]
		picture.size = PICTURE_SIZE
		picture.lit = false
		picture.pressed_call = pick.bind(index)
		menu.canvas.add_child(picture)
		menu.labels["branch_picture%d" % (index + 1)] = picture
		pictures.append(picture)
	var ok := menu._square("SCBOK")
	if ok != null:
		ok.disabled = true
		ok.pressed.connect(accept)

func pick(index: int) -> void:
	if index < 0 or index >= pictures.size(): return
	if picked != index: ELUiSounds.play(menu.profile, "Buttons/swapcampaign.wav")
	picked = index
	for i in pictures.size():
		pictures[i].lit = i == index
		pictures[i].queue_redraw()
	if menu.buttons.has("SCBOK"): menu.buttons.SCBOK.disabled = false

func accept() -> void:
	if picked < 0 or picked >= choices.size(): return
	menu.show_chapter_info(choices[picked], difficulty)

class Picture extends Control:
	var texture: Texture2D
	var lit := false
	var pressed_call: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed_call.call()
			accept_event()

	func _draw() -> void:
		if texture == null: return
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), Rect2(Vector2.ZERO, size), Color(1, 1, 1, ELBranchScreen.LIT if lit else ELBranchScreen.DIM))
