class_name ELTradeDialogView
extends Control
## First-game TradeDialog over the Diplomacy screen, composed from the
## original CutParts (1024 set) at the registry ShiftX/ShiftY.
##
## The local player is always on the left, the other player on the right,
## each with name and blazon. Each side has a minus and a plus button and the
## amount for the seven resources. The left plus stops at what the local
## player holds; the right side has no limit. Under the left resources sit the
## local player's artifacts (four visible, scrolled with the arrows, charges
## in the corner) and a global spell list, with the Artifact and Global spell
## check boxes; the right side has the boxes demanding any artifact or any
## global spell. The global spell list is created empty and stays empty.
##
## A new offer (Type1): Cancel, OK (send, enabled once a resource amount
## differs). A received offer (Type2 and Type3): Leave, Send (revised offer,
## enabled once changed), OK (accept, enabled while unchanged), Cancel
## (decline). A sent offer (Type2 and Type4): Leave, Cancel (withdraw); nothing
## can be edited. Only resource amounts count as a change.
signal closed
const PANEL := "TradeDialog"
## Controls "TradeDialog" ShiftX/ShiftY for 1024x768.
const ORIGIN := Vector2(109, 84)
const SIZE := Vector2(620, 600)
const NEW := 0
const RECEIVED := 1
const SENT := 2
## Panel piece masks shown in each mode (registry Msk Type1..Type4).
const MODE_TYPES := [["Type1"], ["Type2", "Type3"], ["Type2", "Type4"]]
## Controls shown in each mode, from their registry Msk.
const MODE_CONTROLS := [["TDNeedArtifact1", "TDNeedSpell1", "TDCancel1", "TDOK1"],
	["TDNeedArtifact2", "TDNeedSpell2", "TDLeave2", "TDSend2", "TDOK2", "TDCancel2"],
	["TDNeedArtifact2", "TDNeedSpell2", "TDLeave3", "TDCancel3"]]
const MODE_BUTTONS := ["TDNeedArtifact1", "TDNeedArtifact2", "TDNeedSpell1", "TDNeedSpell2", "TDCancel1", "TDCancel2", "TDCancel3",
	"TDLeave2", "TDLeave3", "TDOK1", "TDOK2", "TDSend2"]
## The right side is the left one moved by this much.
const SIDE_SHIFT := Vector2(283, 0)
## Resource n sits in column n / 4 and row n % 4 of 125 x 37 cells.
const CELL := Vector2(125, 37)
const ROWS_PER_COLUMN := 4
## Amount centre of the first resource, between its minus and plus.
const AMOUNT_AT := Vector2(130, 157)
const BLAZONS := [Vector2(155, 33), Vector2(438, 33)]
const CAPTION_RECT := Rect2(57, 2, 516, 20)
const NAME_RECTS := [Rect2(63, 82, 223, 22), Rect2(345, 82, 223, 22)]
## Artifact list: four 50 px pictures 3 px apart from (71, 348); global
## spell list: three 70 x 50 pictures from (69, 463).
const ARTIFACT_AT := Vector2(71, 348)
const ARTIFACT_SIZE := Vector2(50, 50)
const ARTIFACTS_SHOWN := 4
const LIST_GAP := 3.0
## Pictures of the empty list cells (DIPLOMACY_PANEL_17).
const ARTIFACT_EMPTY := Rect2(70, 204, 50, 50)
const SPELL_EMPTY := Rect2(0, 204, 70, 50)
const SPELL_AT := Vector2(69, 463)
const SPELL_SIZE := Vector2(70, 50)
const SPELLS_SHOWN := 3
## Charge digits: ADV_SCREEN_2 cells of 10 x 10 from (0, 246), "-" first.
const DIGIT_ROW := 246.0
const HEADING := Color("c9b07a")
const TEXT := Color("f2eee4")

var view: ELDiplomacyView
var state: ELAdventureSession
var hud: ELAdventureHud
var profile: ELProfile
var player := -1
var other := -1
var mode := NEW
## The offer being shown (ELDiplomacy trade layout) and the two sides.
var offer: Dictionary = {}
var mine: Dictionary = {}
var theirs: Dictionary = {}
var canvas: ELDiplomacyView.Canvas
var buttons: Dictionary = {}
## Minus and plus per side and resource: [side][resource].
var minus: Array = [[], []]
var plus: Array = [[], []]
var names: Array[Label] = []
## The local player's artifacts: {hero, index, item}; the list scroll and pick.
var artifacts: Array = []
var artifact_scroll := 0
var artifact_pick := -1
var _pieces: Array[Dictionary] = []
var _textures: Dictionary = {}
var _repeat: Timer
var _repeat_call: Callable

func build(owner_view: ELDiplomacyView) -> void:
	view = owner_view
	state = view.state
	hud = view.hud
	profile = view.profile
	player = view.player
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The dialog is modal over the Diplomacy screen.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	for name: String in ["DIPLOMACY_PANEL_17", "ADV_SCREEN_2"]:
		_textures[name] = profile.texture(str(hud._paths.get(name, "")))
	canvas = ELDiplomacyView.Canvas.new()
	canvas.draw_call = _draw_dialog
	canvas.press_call = _press
	canvas.tip_call = func(_point: Vector2): return ""
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(canvas)
	view._label(canvas, CAPTION_RECT, profile.text("CtrlTDCaption"), 20, HEADING, hud._bold)
	for rect: Rect2 in NAME_RECTS: names.append(view._label(canvas, rect, "", 17, HEADING, hud._bold))
	for side in 2:
		for resource in ELDiplomacy.TRADE_RESOURCES:
			var shift := SIDE_SHIFT * side + Vector2(CELL.x * (resource / ROWS_PER_COLUMN), CELL.y * (resource % ROWS_PER_COLUMN))
			for pair: Array in [[minus, "TDMinus", -1], [plus, "TDPlus", 1]]:
				var button := _auto(view._button(canvas, pair[1], shift, {}), side, resource, pair[2])
				pair[0][side].append(button)
	for control: String in ["TDScrollLU", "TDScrollRU", "TDScrollLD", "TDScrollRD"]:
		view._button(canvas, control, Vector2.ZERO, buttons)
	buttons.TDScrollLU.pressed.connect(func(): _scroll(-1))
	buttons.TDScrollRU.pressed.connect(func(): _scroll(1))
	for control: String in ["TDSelectArtifact", "TDSelectSpell"]:
		view._button(canvas, control, Vector2.ZERO, buttons)
		var box: ELAdventureHud.CutButton = buttons[control]
		var label := view._label(canvas, Rect2(box.position + Vector2(box.size.x + 6, -1), Vector2(300, box.size.y + 2)), profile.text("Ctrl" + control), 17, TEXT, hud._bold)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	buttons.TDSelectArtifact.pressed.connect(func(): _toggle(mine, "artifact"))
	buttons.TDSelectSpell.pressed.connect(func(): _toggle(mine, "spell"))
	for control: String in MODE_BUTTONS: view._button(canvas, control, Vector2.ZERO, buttons)
	for control: String in ["TDNeedArtifact1", "TDNeedArtifact2"]: buttons[control].pressed.connect(func(): _toggle(theirs, "need_artifact"))
	for control: String in ["TDNeedSpell1", "TDNeedSpell2"]: buttons[control].pressed.connect(func(): _toggle(theirs, "need_spell"))
	buttons.TDCancel1.pressed.connect(close)
	for control: String in ["TDLeave2", "TDLeave3"]: buttons[control].pressed.connect(close)
	for control: String in ["TDCancel2", "TDCancel3"]: buttons[control].pressed.connect(_decline)
	buttons.TDOK1.pressed.connect(_send)
	buttons.TDOK2.pressed.connect(_accept)
	buttons.TDSend2.pressed.connect(_send)
	_repeat = Timer.new()
	_repeat.one_shot = false
	_repeat.timeout.connect(func():
		_repeat.wait_time = 0.06
		if _repeat_call.is_valid(): _repeat_call.call())
	add_child(_repeat)

## A minus or plus: acts on press and repeats while held (AutoButton).
func _auto(button: ELAdventureHud.CutButton, side: int, resource: int, delta: int) -> ELAdventureHud.CutButton:
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var step := func():
		if button.disabled or offer.is_empty(): return
		ELDiplomacy.trade_step(mine if side == 0 else theirs, resource, delta)
		refresh()
	button.pressed.connect(step)
	button.button_down.connect(func():
		_repeat_call = step
		_repeat.start(0.4))
	button.button_up.connect(func(): _repeat.stop())
	return button

func layout(factor: float, right_shift: float) -> void:
	canvas.scale = Vector2(factor, factor)
	canvas.position = (ORIGIN + Vector2(right_shift * 0.5, 0)) * factor
	canvas.size = SIZE

## Shows an offer: NEW drafts one, RECEIVED answers one, SENT reviews one.
func open(shown: Dictionary, shown_mode: int) -> void:
	if shown.is_empty(): return
	offer = shown
	mode = shown_mode
	other = int(offer.to) if int(offer.from) == player else int(offer.from)
	mine = ELDiplomacy.trade_side_of(offer, player)
	theirs = ELDiplomacy.trade_side_of(offer, other)
	names[0].text = ELFirstScenario.player_name(state, player)
	names[1].text = ELFirstScenario.player_name(state, other)
	_pieces = compose(hud, MODE_TYPES[mode])
	for control: String in MODE_BUTTONS: buttons[control].visible = MODE_CONTROLS[mode].has(control)
	artifacts = artifacts_of(state, player)
	artifact_scroll = 0
	artifact_pick = -1
	visible = true
	refresh()

## Panel pieces: the unmasked background first, then the "Last" pieces of
## the mode's types.
static func compose(panel: ELAdventureHud, types: Array) -> Array[Dictionary]:
	var layers: Array = [[], []]
	for row: Dictionary in panel.rows(PANEL, [], ["Res1"]):
		var masks: Array = row.masks
		var typed := masks.filter(func(mask: String): return mask.begins_with("Type"))
		if not typed.is_empty() and not typed.any(func(mask: String): return types.has(mask)): continue
		var piece := panel.cut(row)
		if not piece.is_empty(): layers[1 if masks.has("Last") else 0].append(piece)
	var result: Array[Dictionary] = []
	for layer: Array in layers: result.append_array(layer)
	return result

## The player's heroes' artifacts in hero order.
static func artifacts_of(session: ELAdventureSession, owner: int) -> Array:
	var result: Array = []
	var ids: Array = session.objects.keys()
	ids.sort()
	for id: Variant in ids:
		var hero := session.object(id)
		if hero.get("type") != "hero" or int(hero.get("owner", -1)) != owner or not hero.get("alive", true): continue
		var list: Array = hero.get("artifacts", [])
		for index in list.size(): result.append({"hero": id, "index": index, "item": list[index]})
	return result

func refresh() -> void:
	if offer.is_empty(): return
	var editable := mode != SENT
	for resource in ELDiplomacy.TRADE_RESOURCES:
		minus[0][resource].disabled = not editable or int(mine.resources[resource]) == 0
		minus[1][resource].disabled = not editable or int(theirs.resources[resource]) == 0
		plus[0][resource].disabled = not editable or not ELDiplomacy.trade_can_raise(state, player, mine, resource)
		plus[1][resource].disabled = not editable
	buttons.TDSelectArtifact.active = bool(mine.artifact)
	buttons.TDSelectSpell.active = bool(mine.spell)
	for control: String in ["TDNeedArtifact1", "TDNeedArtifact2"]: buttons[control].active = bool(theirs.need_artifact)
	for control: String in ["TDNeedSpell1", "TDNeedSpell2"]: buttons[control].active = bool(theirs.need_spell)
	for control: String in ["TDSelectArtifact", "TDSelectSpell", "TDNeedArtifact1", "TDNeedArtifact2", "TDNeedSpell1", "TDNeedSpell2"]:
		buttons[control].disabled = not editable
	buttons.TDScrollLU.disabled = not editable or artifact_scroll <= 0
	buttons.TDScrollRU.disabled = not editable or artifact_scroll + ARTIFACTS_SHOWN >= artifacts.size()
	# The global spell list never has entries.
	buttons.TDScrollLD.disabled = true
	buttons.TDScrollRD.disabled = true
	var changed := ELDiplomacy.trade_changed(offer)
	buttons.TDOK1.disabled = not changed
	buttons.TDOK2.disabled = changed
	buttons.TDSend2.disabled = not changed
	canvas.queue_redraw()

func amount_center(side: int, resource: int) -> Vector2:
	return AMOUNT_AT + SIDE_SHIFT * side + Vector2(CELL.x * (resource / ROWS_PER_COLUMN), CELL.y * (resource % ROWS_PER_COLUMN))

func artifact_rect(slot: int) -> Rect2:
	return Rect2(ARTIFACT_AT + Vector2((ARTIFACT_SIZE.x + LIST_GAP) * slot, 0), ARTIFACT_SIZE)

func _draw_dialog() -> void:
	for piece: Dictionary in _pieces: canvas.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	if offer.is_empty(): return
	view._draw_blazon(canvas, player, BLAZONS[0])
	view._draw_blazon(canvas, other, BLAZONS[1])
	var font: Font = hud._bold
	for side in 2:
		var shown: Dictionary = mine if side == 0 else theirs
		for resource in ELDiplomacy.TRADE_RESOURCES:
			var text := str(int(shown.resources[resource]))
			var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			var at := amount_center(side, resource) + Vector2(-size.x * 0.5, size.y * 0.5 - font.get_descent(16))
			canvas.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, 0.8))
			canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	var cells: Texture2D = _textures.DIPLOMACY_PANEL_17
	for slot in ARTIFACTS_SHOWN:
		var index := artifact_scroll + slot
		var rect := artifact_rect(slot)
		if index >= artifacts.size():
			if cells != null: canvas.draw_texture_rect_region(cells, rect, ARTIFACT_EMPTY)
			continue
		var item: Dictionary = artifacts[index].item
		var type := str(profile.table("Artefacts").get(str(item.get("name", "")), {}).get("SpellType", ""))
		var icon := profile.card_icon(type) if not type.is_empty() else null
		if icon != null: canvas.draw_texture_rect(icon, rect, false)
		_digits(rect, str(int(item.get("charges", 0))))
		if index == artifact_pick: canvas.draw_rect(rect.grow(-1), Color("e8e0cc"), false, 2.0)
	# The global spell list stays empty: every cell shows the empty picture.
	for slot in SPELLS_SHOWN:
		if cells != null: canvas.draw_texture_rect_region(cells, Rect2(SPELL_AT + Vector2((SPELL_SIZE.x + LIST_GAP) * slot, 0), SPELL_SIZE), SPELL_EMPTY)

## Charges: ADV_SCREEN_2 digits right-aligned in the picture's lower corner,
## a black copy one pixel lower right under the white one.
func _digits(rect: Rect2, text: String) -> void:
	var sheet: Texture2D = _textures.ADV_SCREEN_2
	if sheet == null: return
	var right := rect.size.x
	for index in range(text.length() - 1, -1, -1):
		var source := Rect2((text.unicode_at(index) - 0x2d) * 10, DIGIT_ROW, 10, 10)
		canvas.draw_texture_rect_region(sheet, Rect2(rect.position + Vector2(right - 9, 41), Vector2(10, 10)), source, Color.BLACK)
		canvas.draw_texture_rect_region(sheet, Rect2(rect.position + Vector2(right - 10, 40), Vector2(10, 10)), source)
		right -= 10

## A click on a visible artifact picks it (the offer's own artifact).
func _press(point: Vector2) -> void:
	if offer.is_empty() or mode == SENT: return
	for slot in ARTIFACTS_SHOWN:
		var index := artifact_scroll + slot
		if index < artifacts.size() and artifact_rect(slot).has_point(point):
			artifact_pick = index
			canvas.queue_redraw()
			return

func _scroll(delta: int) -> void:
	artifact_scroll = clampi(artifact_scroll + delta, 0, maxi(0, artifacts.size() - ARTIFACTS_SHOWN))
	refresh()

func _toggle(side: Dictionary, flag: String) -> void:
	if offer.is_empty() or mode == SENT: return
	side[flag] = not bool(side[flag])
	if flag == "need_artifact": side.artifact = bool(side.need_artifact)
	if flag == "need_spell": side.spell = bool(side.need_spell)
	refresh()

## OK of a new offer and Send of a received one send it from this player.
func _send() -> void:
	var sent := {"from": player, "to": other, "give": mine, "take": theirs}
	ELDiplomacy.send_trade(state, sent)
	close()

func _accept() -> void:
	if mode == RECEIVED: ELDiplomacy.accept_trade(state, other, player)
	close()

## Cancel declines a received offer or withdraws a sent one.
func _decline() -> void:
	if mode != NEW: ELDiplomacy.withdraw_trade(state, player, other)
	close()

func close() -> void:
	_repeat.stop()
	visible = false
	offer = {}
	closed.emit()
