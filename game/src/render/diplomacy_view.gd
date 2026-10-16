class_name ELDiplomacyView
extends Control
## First-game Diplomacy screen and its PeaceOffer dialog, composed from the
## original CutParts (1024 set) at the registry ShiftX/ShiftY.
##
## One 54 px row per other player in index order: blazon, race and
## human/computer pictures, name, the aspects agreed for the next day, Break,
## OfferPeace, OfferTrade, the sent (OutBox) and received (InBox) offers and
## the Bane check box. Break asks for confirmation in the MessageBox and
## clears every changeable agreed aspect of the next day's relation.
## OfferPeace, InBoxPeace and OutBoxPeace open PeaceOffer as a new, received
## or sent offer; OfferTrade, InBoxTrade and OutBoxTrade open the TradeDialog
## (ELTradeDialogView) the same way. D_OK or Escape closes the screen.
##
## PeaceOffer shows both blazons and names, the offer text and four check
## boxes (ether, land, vision, shops) enabled only where the relation allows
## the aspect to change. Its buttons are centred under the text:
## new offer: Cancel, OK (send, enabled once the offer differs); received:
## Leave, Cancel (decline), Send (revised offer, enabled once changed), OK
## (accept, enabled while unchanged); sent: Leave, Cancel (withdraw).
signal closed
const PANEL := "Diplomacy"
const DIALOG := "PeaceOffer"
## Controls "Diplomacy" and "PeaceOffer" ShiftX/ShiftY for 1024x768.
const ORIGIN := Vector2(97, 68)
const ROWS := 7
const ROW_STEP := 54.0
## Row origin of the drawn row parts.
const ROW_AT := Vector2(75, 112)
## DIPLOMACY_PANEL_7 row parts: the wide frame and the narrow frame after it.
const ROW_FRAME := [[Vector2(0, 0), Rect2(122, 50, 124, 49)], [Vector2(124, 0), Rect2(122, 99, 41, 49)]]
const BLAZON_AT := Vector2(7, 3)
const BLAZON := 41.0
const RACE_AT := Vector2(70, 3)
## MISSION_PANEL_9 race pictures in the order Red, Green, Blue, Black.
const RACE_SOURCES := [Rect2(225, 0, 31, 23), Rect2(165, 24, 31, 23), Rect2(186, 52, 31, 23), Rect2(225, 23, 31, 23)]
const RACES := ["Red", "Green", "Blue", "Black"]
const KIND_AT := Vector2(118, 3)
## MISSION_PANEL_7: computer player and human player.
const COMPUTER_SOURCE := Rect2(225, 138, 31, 23)
const HUMAN_SOURCE := Rect2(225, 23, 31, 23)
## Agreed aspects: 2x2 grid of DIPLOMACY_PANEL_7 pictures from (169, -1).
const ASPECT_AT := Vector2(169, -1)
const ASPECT_SOURCES := [Rect2(163, 99, 33, 25), Rect2(163, 124, 33, 25), Rect2(196, 99, 33, 25), Rect2(196, 124, 33, 25)]
const NAME_RECT := Rect2(133, 145, 103, 15)
const ROW_BUTTONS := ["Break", "OfferPeace", "OfferTrade", "InBoxPeace", "InBoxTrade", "OutBoxPeace", "OutBoxTrade", "Bane"]
const TIPS := {"D_CaptionTt1": Rect2(71, 64, 169, 43), "D_CaptionTt2": Rect2(244, 64, 65, 43), "D_CaptionTt3": Rect2(311, 66, 43, 43),
	"D_CaptionTt4": Rect2(371, 66, 62, 43), "D_CaptionTt5": Rect2(432, 66, 45, 43), "D_CaptionTt6": Rect2(476, 65, 44, 44), "D_CaptionTt7": Rect2(520, 65, 42, 44)}
## Tooltip keys: D_CaptionTt1 uses the registry's CtrlTtDiplomacy_12.
const TIP_KEYS := {"D_CaptionTt1": "CtrlTtDiplomacy_12"}
## PeaceOffer panel rectangle and its frame (DIPLOMACY_PANEL_18 tiles).
const DIALOG_RECT := Rect2(141, 109, 350, 300)
const BLAZON_FROM := Vector2(230, 142)
const BLAZON_TO := Vector2(353, 142)
const STATES := ["POState1", "POState2", "POState3", "POState4"]
const DIALOG_TIPS := {"POTT1": Rect2(260, 272, 40, 28), "POTT2": Rect2(260, 303, 40, 28), "POTT3": Rect2(366, 273, 40, 28), "POTT4": Rect2(366, 303, 40, 28)}
const BUTTON_WIDTH := 38.0
const BUTTON_GAP := 23.0
const NEW := 0
const RECEIVED := 1
const SENT := 2
const CAPTION := Color("d8c89a")
const TEXT := Color("f2eee4")

var state: ELAdventureSession
var hud: ELAdventureHud
var profile: ELProfile
var player := -1
var sheet: Canvas
var buttons: Dictionary = {}
## Per row: the other player's index and that row's buttons and name label.
var rows: Array[Dictionary] = []
var dialog: Canvas
var dialog_buttons: Dictionary = {}
var dialog_names: Array[Label] = []
var trade: ELTradeDialogView
## The offer being shown: {from, to, before, mask}, and the dialog mode.
var offer: Dictionary = {}
var mode := NEW
var confirm: ELFirstMessageBox
var _confirm_target := -1
var _pieces: Array[Dictionary] = []
var _dialog_pieces: Array[Dictionary] = []
var _textures: Dictionary = {}

func build(session: ELAdventureSession, owner: int) -> void:
	state = session
	player = owner
	profile = state.map.profile
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for name: String in ["DIPLOMACY_PANEL_7", "DIPLOMACY_PANEL_18", "MISSION_PANEL_7", "MISSION_PANEL_9", "SYMBOLS", "BLAZON_BACK", "BLAZON_FORE_00", "BLAZON_FORE_01"]:
		_textures[name] = profile.texture(str(hud._paths.get(name, "")))
	sheet = Canvas.new()
	sheet.draw_call = _draw_sheet
	sheet.press_call = func(_point: Vector2): pass
	sheet.tip_call = _tooltip
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	_pieces = ELGlobalSpellsView.compose(hud, [PANEL])
	_label(sheet, Rect2(165, 27, 297, 20), profile.text("CtrlDiplomacyText"), 17, CAPTION, hud._italic)
	var others := ELDiplomacy.others(state, player)
	for index in ROWS:
		var row := {"player": others[index] if index < others.size() else -1, "buttons": {}}
		var shift := Vector2(0, ROW_STEP * index)
		for control: String in ROW_BUTTONS:
			var button := _button(sheet, control, shift)
			row.buttons[control] = button
			button.visible = row.player >= 0
		row.name = _label(sheet, Rect2(NAME_RECT.position + shift, NAME_RECT.size), ELFirstScenario.player_name(state, row.player) if row.player >= 0 else "", 15, TEXT, hud._bold)
		row.name.visible = row.player >= 0
		var other: int = row.player
		row.buttons.Break.pressed.connect(func(): _ask_break(other))
		row.buttons.OfferPeace.pressed.connect(func(): open_offer(ELDiplomacy.draft(state, player, other), NEW))
		row.buttons.InBoxPeace.pressed.connect(func(): open_offer(ELDiplomacy.received(state, player, other), RECEIVED))
		row.buttons.OutBoxPeace.pressed.connect(func(): open_offer(ELDiplomacy.sent(state, player, other), SENT))
		row.buttons.OfferTrade.pressed.connect(func(): trade.open(ELDiplomacy.trade_draft(state, player, other), NEW))
		row.buttons.InBoxTrade.pressed.connect(func(): trade.open(ELDiplomacy.trade_received(state, player, other), RECEIVED))
		row.buttons.OutBoxTrade.pressed.connect(func(): trade.open(ELDiplomacy.trade_sent(state, player, other), SENT))
		row.buttons.Bane.pressed.connect(func():
			ELDiplomacy.set_bane(state, player, other, not ELDiplomacy.bane(state, player, other))
			refresh())
		rows.append(row)
	buttons.D_OK = _button(sheet, "D_OK", Vector2.ZERO)
	buttons.D_OK.pressed.connect(func(): closed.emit())
	_build_dialog()
	trade = ELTradeDialogView.new()
	add_child(trade)
	trade.build(self)
	trade.closed.connect(refresh)
	resized.connect(_layout)
	_layout()
	refresh()

func _layout() -> void:
	var factor := hud.scale_factor
	for canvas: Canvas in [sheet, dialog]:
		canvas.scale = Vector2(factor, factor)
		canvas.position = (ORIGIN + Vector2(hud.right_shift * 0.5, 0)) * factor
		canvas.size = Vector2(660, 600)
	if trade != null: trade.layout(factor, hud.right_shift)

## Enabled states: the boxes hold an offer; Bane shows its choice. OfferTrade
## is always available.
func refresh() -> void:
	for row: Dictionary in rows:
		if row.player < 0: continue
		var other: int = row.player
		row.buttons.InBoxPeace.disabled = ELDiplomacy.received(state, player, other).is_empty()
		row.buttons.OutBoxPeace.disabled = ELDiplomacy.sent(state, player, other).is_empty()
		row.buttons.InBoxTrade.disabled = ELDiplomacy.trade_received(state, player, other).is_empty()
		row.buttons.OutBoxTrade.disabled = ELDiplomacy.trade_sent(state, player, other).is_empty()
		row.buttons.Bane.active = ELDiplomacy.bane(state, player, other)
	sheet.queue_redraw()

func row_rect(index: int) -> Rect2:
	return Rect2(ROW_AT + Vector2(0, ROW_STEP * index), Vector2(165, 49))

func aspect_rect(index: int, aspect: int) -> Rect2:
	var size: Vector2 = ASPECT_SOURCES[0].size
	return Rect2(ROW_AT + ASPECT_AT + Vector2(size.x * (aspect / 2), ROW_STEP * index + size.y * (aspect % 2)), size)

func _draw_sheet() -> void:
	for piece: Dictionary in _pieces: sheet.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	var frames: Texture2D = _textures.DIPLOMACY_PANEL_7
	for index in rows.size():
		var other: int = rows[index].player
		if other < 0: continue
		var at := ROW_AT + Vector2(0, ROW_STEP * index)
		if frames != null:
			for part: Array in ROW_FRAME: sheet.draw_texture_rect_region(frames, Rect2(at + part[0], part[1].size), part[1])
		_draw_blazon(sheet, other, at + BLAZON_AT)
		var race := RACES.find(str(state.players[other].get("color", "")))
		if race >= 0 and _textures.MISSION_PANEL_9 != null: sheet.draw_texture_rect_region(_textures.MISSION_PANEL_9, Rect2(at + RACE_AT, RACE_SOURCES[race].size), RACE_SOURCES[race])
		var kind := HUMAN_SOURCE if other == state.current_player else COMPUTER_SOURCE
		if _textures.MISSION_PANEL_7 != null: sheet.draw_texture_rect_region(_textures.MISSION_PANEL_7, Rect2(at + KIND_AT, kind.size), kind)
		var value := ELDiplomacy.next_relation(state, player, other)
		for aspect in ELDiplomacy.ASPECTS:
			if ELDiplomacy.agreed(value, aspect) and frames != null: sheet.draw_texture_rect_region(frames, aspect_rect(index, aspect), ASPECT_SOURCES[aspect])

## Blazon: a BLAZON_BACK cell under a BLAZON_FORE_00/01 cell, 41 px each.
func _draw_blazon(canvas: Control, id: int, at: Vector2) -> void:
	var picture := blazon(id)
	var back: int = picture.y
	var fore: int = picture.x
	if back >= 0 and _textures.BLAZON_BACK != null:
		canvas.draw_texture_rect_region(_textures.BLAZON_BACK, Rect2(at, Vector2(BLAZON, BLAZON)), Rect2(BLAZON * (back % 6), BLAZON * (back / 6), BLAZON, BLAZON))
	if fore >= 0:
		var sheet_texture: Texture2D = _textures.get("BLAZON_FORE_%02d" % (fore / 36))
		var cell := fore % 36
		if sheet_texture != null: canvas.draw_texture_rect_region(sheet_texture, Rect2(at, Vector2(BLAZON, BLAZON)), Rect2(BLAZON * (cell % 6), BLAZON * (cell / 6), BLAZON, BLAZON))

## The map's blazon (logo) and blazon colour for a player, or -1.
func blazon(id: int) -> Vector2i:
	return ELPlayerProfile.player_blazon(state, id)

func _tooltip(point: Vector2) -> String:
	for name: String in TIPS:
		if TIPS[name].has_point(point): return profile.text(TIP_KEYS.get(name, "CtrlTt" + name))
	for index in rows.size():
		var other: int = rows[index].player
		if other < 0: continue
		var at := ROW_AT + Vector2(0, ROW_STEP * index)
		if Rect2(at + RACE_AT, RACE_SOURCES[0].size).has_point(point): return profile.text("T_PL_RACE")
		if Rect2(at + KIND_AT, COMPUTER_SOURCE.size).has_point(point): return profile.text("T_PL_CPU_HUMAN")
		var value := ELDiplomacy.next_relation(state, player, other)
		for aspect in ELDiplomacy.ASPECTS:
			if ELDiplomacy.agreed(value, aspect) and aspect_rect(index, aspect).has_point(point): return profile.text("T_ALLY_TYPE_%d" % (aspect + 1))
	return ""

## Break asks first (T_MB_BREAK_ALLY_WANNING, OK and Cancel).
func _ask_break(other: int) -> void:
	if confirm != null: return
	_confirm_target = other
	confirm = ELFirstMessageBox.new()
	add_child(confirm)
	confirm.setup(hud, profile.text("T_MB_BREAK_ALLY_WANNING"), ELFirstMessageBox.OK_CANCEL)
	confirm.answered.connect(_answer_break)

func _answer_break(accepted: bool) -> void:
	if accepted and _confirm_target >= 0: ELDiplomacy.break_alliance(state, player, _confirm_target)
	_confirm_target = -1
	if confirm != null: confirm.queue_free()
	confirm = null
	refresh()

## Escape: the message box answers itself; then the dialog, then the screen.
func cancel() -> void:
	if confirm != null: return
	if trade != null and trade.visible: trade.close()
	elif dialog.visible: close_offer()
	else: closed.emit()

func _build_dialog() -> void:
	dialog = Canvas.new()
	dialog.draw_call = _draw_dialog
	dialog.press_call = func(_point: Vector2): pass
	dialog.tip_call = _dialog_tooltip
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.visible = false
	add_child(dialog)
	_dialog_pieces = ELGlobalSpellsView.compose(hud, [DIALOG])
	dialog_names.append(_label(dialog, Rect2(203, 186, 94, 17), "", 15, TEXT, hud._bold))
	dialog_names.append(_label(dialog, Rect2(326, 186, 94, 17), "", 15, TEXT, hud._bold))
	var body := _label(dialog, Rect2(145, 215, 360, 50), profile.text("CtrlPOText1"), 15, CAPTION, hud._italic)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.clip_text = false
	# POText is 50 px high: the size steps down until the wrapped text fits.
	var font_size := 15
	while font_size > 10 and hud._italic.get_multiline_string_size(body.text, HORIZONTAL_ALIGNMENT_CENTER, body.size.x, font_size).y > body.size.y:
		font_size -= 1
	body.add_theme_font_size_override("font_size", font_size)
	for aspect in STATES.size():
		var box := _button(dialog, STATES[aspect], Vector2.ZERO, dialog_buttons)
		box.pressed.connect(func():
			offer.mask = int(offer.mask) ^ (1 << aspect)
			_refresh_dialog())
	_button(dialog, "POOK", Vector2.ZERO, dialog_buttons).pressed.connect(_offer_ok)
	_button(dialog, "POCancel", Vector2.ZERO, dialog_buttons).pressed.connect(_offer_cancel)
	_button(dialog, "POLeave", Vector2.ZERO, dialog_buttons).pressed.connect(close_offer)
	_button(dialog, "POSend", Vector2.ZERO, dialog_buttons).pressed.connect(_offer_send)

## Shows an offer: NEW drafts one, RECEIVED answers one, SENT reviews one.
func open_offer(shown: Dictionary, shown_mode: int) -> void:
	if shown.is_empty(): return
	offer = shown.duplicate()
	mode = shown_mode
	# The receiving side measures changes from the proposal itself (a received
	# offer arrives with its earlier and proposed aspects equal).
	if mode == RECEIVED: offer.before = offer.mask
	var left := int(offer.to) if mode == RECEIVED else int(offer.from)
	var right := int(offer.from) if mode == RECEIVED else int(offer.to)
	offer.left = left
	offer.right = right
	dialog_names[0].text = ELFirstScenario.player_name(state, left)
	dialog_names[1].text = ELFirstScenario.player_name(state, right)
	var shown_buttons: Array = [["POCancel", "POOK"], ["POLeave", "POCancel", "POSend", "POOK"], ["POLeave", "POCancel"]][mode]
	var tips: Dictionary = [{"POOK": "T_PO_OK_1", "POCancel": "T_PO_CANCEL_1"},
		{"POLeave": "T_PO_LEAVE_2", "POCancel": "T_PO_CANCEL_2", "POSend": "T_PO_REPLACE_2", "POOK": "T_PO_OK_2"},
		{"POLeave": "T_PO_LEAVE_3", "POCancel": "T_PO_CANCEL_3"}][mode]
	var x := DIALOG_RECT.position.x + floorf((DIALOG_RECT.size.x - shown_buttons.size() * BUTTON_WIDTH - (shown_buttons.size() - 1) * BUTTON_GAP) * 0.5)
	for control: String in ["POOK", "POCancel", "POLeave", "POSend"]:
		var button: ELAdventureHud.CutButton = dialog_buttons[control]
		button.visible = shown_buttons.has(control)
		if not button.visible: continue
		button.tooltip_text = profile.text(tips[control])
		button.position.x = x + shown_buttons.find(control) * (BUTTON_WIDTH + BUTTON_GAP)
	dialog.visible = true
	_refresh_dialog()

func _refresh_dialog() -> void:
	var value := ELDiplomacy.next_relation(state, int(offer.left), int(offer.right))
	for aspect in STATES.size():
		var box: ELAdventureHud.CutButton = dialog_buttons[STATES[aspect]]
		box.active = int(offer.mask) & (1 << aspect) != 0
		# A sent offer is shown, not edited.
		box.disabled = mode == SENT or not ELDiplomacy.changeable(value, aspect)
	var changed := ELDiplomacy.changed(offer)
	dialog_buttons.POLeave.disabled = false
	dialog_buttons.POCancel.disabled = false
	dialog_buttons.POOK.disabled = not changed if mode == NEW else changed
	dialog_buttons.POSend.disabled = not changed
	dialog.queue_redraw()

func close_offer() -> void:
	dialog.visible = false
	offer = {}
	refresh()

func _offer_ok() -> void:
	if mode == NEW: ELDiplomacy.send(state, offer)
	elif mode == RECEIVED: ELDiplomacy.accept(state, int(offer.from), int(offer.to))
	close_offer()

## Cancel drops a new offer, declines a received one, withdraws a sent one.
func _offer_cancel() -> void:
	if mode != NEW: ELDiplomacy.withdraw(state, int(offer.from), int(offer.to))
	close_offer()

## A received offer answered with a revised one goes back to its sender.
func _offer_send() -> void:
	ELDiplomacy.send(state, {"from": player, "to": int(offer.from), "before": int(offer.before), "mask": int(offer.mask)})
	close_offer()

func _draw_dialog() -> void:
	_draw_frame(dialog, DIALOG_RECT)
	for piece: Dictionary in _dialog_pieces: dialog.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	if offer.is_empty(): return
	_draw_blazon(dialog, int(offer.left), BLAZON_FROM)
	_draw_blazon(dialog, int(offer.right), BLAZON_TO)

## Dialog frame: DIPLOMACY_PANEL_18 50 px tiles over the panel grown to whole
## tiles (width + 123, height + 99, rounded up) and centred, over a half-black
## SYMBOLS shade offset by 2 px.
static func frame_rect(rect: Rect2) -> Rect2:
	var size := Vector2(ceilf((rect.size.x + 123) / 50.0) * 50, ceilf((rect.size.y + 99) / 50.0) * 50)
	return Rect2(rect.position + ((rect.size - size) * 0.5).floor(), size)

func _draw_frame(canvas: Control, rect: Rect2) -> void:
	var outer := frame_rect(rect)
	if _textures.SYMBOLS != null: canvas.draw_texture_rect_region(_textures.SYMBOLS, Rect2(outer.position + Vector2(2, 2), outer.size), Rect2(225, 45, 10, 10), Color(0, 0, 0, 0.5))
	var tiles: Texture2D = _textures.DIPLOMACY_PANEL_18
	if tiles == null: return
	var columns := int(outer.size.x / 50)
	var lines := int(outer.size.y / 50)
	for column in columns:
		for line in lines:
			var source := Vector2(0 if column == 0 else 100 if column == columns - 1 else 50, 0 if line == 0 else 100 if line == lines - 1 else 50)
			canvas.draw_texture_rect_region(tiles, Rect2(outer.position + Vector2(column, line) * 50, Vector2(50, 50)), Rect2(source, Vector2(50, 50)))

func _dialog_tooltip(point: Vector2) -> String:
	for name: String in DIALOG_TIPS:
		if DIALOG_TIPS[name].has_point(point): return profile.text("CtrlTt" + name)
	return ""

func _label(canvas: Control, rect: Rect2, text: String, size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("line_spacing", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	return label

## A CutParts button; pieces masked "Light" alone give the hover picture.
func _button(canvas: Control, control: String, shift: Vector2, into: Dictionary = {}) -> ELAdventureHud.CutButton:
	var button := ELAdventureHud.CutButton.from_rows(hud, control, shift)
	if button.parts.hover.is_empty():
		var light := hud.rows(control, ["Light"], ["Free", "Push"])
		if not light.is_empty(): button.parts.hover = hud.cut(light[0], shift)
	var tip := profile.text("CtrlTt" + control)
	if tip != "CtrlTt" + control: button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.place(Vector2.ZERO)
	canvas.add_child(button)
	if into != null: into[control] = button
	return button

## Drawing, clicks and tooltips of a composed panel.
class Canvas extends Control:
	var draw_call: Callable
	var press_call: Callable
	var tip_call: Callable

	func _draw() -> void:
		draw_call.call()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			press_call.call(event.position)
			accept_event()

	func _get_tooltip(at_position: Vector2) -> String:
		return tip_call.call(at_position)
