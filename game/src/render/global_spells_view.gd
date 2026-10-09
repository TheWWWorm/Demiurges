class_name ELGlobalSpellsView
extends Control
## First-game GlobalSpells screen composed from the original CutParts (1024
## set) at the registry ShiftX/ShiftY, with the GSSelectParams prompt for a
## finished spell.
##
## Three five-cell lists: the spells the player may order (scroll pieces show
## the collected part, and stay unavailable until all four are found), the
## spells the player controls, and those acting on the player's castle. The
## selected available spell shows its resource costs (red when above the
## stock), its ether cost plus the extra ether, and its upkeep plus a tenth of
## the extra. MoreMana/LessMana change the extra, CastSpell orders the spell,
## CancelSpell stops the production, GSDispell dispels the selected controlled
## spell and GSOK (or Escape) closes. The right-hand column lists the living
## players' castles with their energy bar and ethereal defender/attacker marks.
signal closed
const PANEL := "GlobalSpells"
## Controls "GlobalSpells" ShiftX/ShiftY for 1024x768.
const ORIGIN := Vector2(70, 84)
## Controls "GSSelectParams" ShiftX/ShiftY; its CutParts carry screen positions.
const PROMPT_ORIGIN := Vector2(70, 90)
const CELL := Vector2(70, 50)
const STEP := 73.0
const VISIBLE := 5
## List origins and click areas: available, controlled, affected.
const LISTS := [Vector2(42, 63), Vector2(42, 327), Vector2(42, 472)]
const LIST_AREAS := [Rect2(17, 58, 408, 58), Rect2(17, 323, 408, 59), Rect2(17, 469, 408, 56)]
const SCROLLS := [["GSScrollL1", "GSScrollR1"], ["GSScrollL2", "GSScrollR2"], ["GSScrollL3", "GSScrollR3"]]
## Value centres: resource costs (one per resource, 38 px apart), ether and
## upkeep, the production's spent/cost/turns, the controlled spell's upkeep
## and protection.
const COST_ROW := Vector2(32, 177)
const COST_STEP := 38.0
const ETHER := Vector2(312, 177)
const UPKEEP := Vector2(350, 177)
const SPENT := Vector2(249, 239)
const TOTAL := Vector2(294, 239)
const TURNS := Vector2(294, 274)
const HELD_UPKEEP := Vector2(294, 396)
const HELD_PROTECTION := Vector2(294, 427)
const PRODUCTION := Vector2(42, 231)
const BAR := Rect2(152, 230, 71, 18)
## Castle column: the local player's castle first, then the others 54 px apart.
const OWN_CASTLE := Vector2(468, 59)
const CASTLES := Vector2(468, 132)
const CASTLE_STEP := 54.0
const CASTLE_BAR := Rect2(89, 2, 9, 47)
const CASTLE_FULL := 30.0
const TIPS := {"GSTT1": Rect2(313, 127, 33, 27), "GSTT2": Rect2(292, 166, 36, 20), "GSTT3": Rect2(331, 166, 37, 21), "GSTT4": Rect2(231, 223, 116, 31), "GSTT5": Rect2(271, 260, 78, 26)}
const WHITE := Color(1, 1, 1)
const RED := Color(1, 0, 0)
const VALUE := Color8(0xd6, 0xbb, 0x88)
const CAPTION := Color("d8c89a")
const PICK := Color("e8e0cc")
const KINDS := ["Hero", "Castle", "Building", "Resource"]
## GSSelectParams: header 104 px, one 100 px list per parameter, then the bottom.
const PROMPT_HEADER := 197.0
const PROMPT_LIST := 100.0
const PROMPT_BOTTOM := 353.0
const PROMPT_ITEMS := Vector2(160, 225)
const PROMPT_SCROLLS := [["GSScrollL_1", "GSScrollR_1"], ["GSScrollL_2", "GSScrollR_2"]]
## The created spell's picture in the prompt header.
const PROMPT_ICON := Vector2(146, 122)

var state: ELAdventureSession
var hud: ELAdventureHud
var profile: ELProfile
var player := -1
var sheet: Canvas
var buttons: Dictionary = {}
## Entries per list: availability entries, controlled spells, acting spells.
var entries: Array = [[], [], []]
var picks: Array[int] = [-1, -1, -1]
var scrolls: Array[int] = [0, 0, 0]
var extra := 0
var prompt: Canvas
var prompt_buttons: Dictionary = {}
var prompt_captions: Array[Label] = []
var prompt_picks: Array[int] = [0, 0]
var prompt_scrolls: Array[int] = [0, 0]
var _targets: Array = []
var _params: Array = []
var _pieces: Array[Dictionary] = []
var _prompt_pieces: Array[Dictionary] = []
var _states: Texture2D
var _symbols: Texture2D

func build(session: ELAdventureSession, owner: int) -> void:
	state = session
	player = owner
	profile = state.map.profile
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_states = profile.texture(str(hud._paths.get("HERO_STATES", "")))
	_symbols = profile.texture(str(hud._paths.get("SYMBOLS", "")))
	sheet = Canvas.new()
	sheet.draw_call = _draw_sheet
	sheet.press_call = _press
	sheet.tip_call = _tooltip
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	_pieces = compose(hud, [PANEL])
	_label(sheet, Rect2(50, 1, 543, 18), "CtrlGSCaption", 16)
	_label(sheet, Rect2(58, 27, 331, 17), "CtrlGlobalSpells_15", 15)
	_label(sheet, Rect2(56, 199, 334, 16), "CtrlGlobalSpells_16", 15)
	_label(sheet, Rect2(57, 295, 332, 17), "CtrlGlobalSpells_17", 15)
	_label(sheet, Rect2(57, 444, 332, 17), "CtrlGlobalSpells_18", 15)
	_label(sheet, Rect2(475, 28, 128, 15), "CtrlSelectCastle", 15)
	for line: Array in [[388, "CtrlGSUpkeep"], [419, "CtrlGSProtection"], [538, "CtrlGSProtection1"]]:
		_label(sheet, Rect2(157, line[0], 110, 16), line[1], 15, HORIZONTAL_ALIGNMENT_RIGHT)
	_button(sheet, buttons, "MoreMana").pressed.connect(func(): extra += 1; refresh())
	_button(sheet, buttons, "LessMana").pressed.connect(func(): extra = maxi(0, extra - 1); refresh())
	_button(sheet, buttons, "CastSpell").pressed.connect(_produce)
	_button(sheet, buttons, "CancelSpell").pressed.connect(func(): ELGlobalSpells.cancel(state, player); refresh())
	_button(sheet, buttons, "GSDispell").pressed.connect(_dispel)
	_button(sheet, buttons, "GSOK").pressed.connect(func(): closed.emit())
	for list in SCROLLS.size():
		_button(sheet, buttons, SCROLLS[list][0]).pressed.connect(_scroll.bind(list, -1))
		_button(sheet, buttons, SCROLLS[list][1]).pressed.connect(_scroll.bind(list, 1))
	for button: BaseButton in buttons.values(): button.focus_mode = Control.FOCUS_NONE
	_build_prompt()
	resized.connect(_layout)
	_layout()
	refresh()

## Panel art: generic pieces, the 1024 set, then the "Last" layers in order.
static func compose(panel: ELAdventureHud, controls: Array) -> Array[Dictionary]:
	var layers: Array = [[], [], [], [], []]
	for control: String in controls:
		for row: Dictionary in panel.rows(control, [], ["Res1"]):
			var piece := panel.cut(row)
			if piece.is_empty(): continue
			var masks: Array = row.masks
			var layer := 4 if masks.has("Last3") else 3 if masks.has("Last2") else 2 if masks.has("Last") else 1 if masks.has("Res2") else 0
			piece.control = control
			layers[layer].append(piece)
	var result: Array[Dictionary] = []
	for layer: Array in layers: result.append_array(layer)
	return result

## Global-spell picture: 3 x 5 cells of 70 x 50 per sheet, row-major.
static func icon(source: ELProfile, index: int) -> Texture2D:
	var texture := source.texture("Interface/GlobalSpells/icon%02d" % (index / 15 + 1))
	if texture == null or index < 0: return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2((index % 15 % 3) * 70, (index % 15 / 3) * 50, 70, 50)
	atlas.filter_clip = true
	return atlas

## Picture index of an availability entry: scroll pieces use the cells after
## the spell's own picture, one per collected part.
static func entry_icon(source: ELProfile, entry: Dictionary) -> int:
	var index := int(ELGlobalSpells.row(source, str(entry.code)).get("Icon", -1))
	if index >= 0 and entry.get("partial", false): index += int(entry.count) - 1
	return index

static func castable(entry: Dictionary) -> bool:
	return not entry.get("partial", false) or int(entry.count) == ELMapPickups.COMPLETE

func _layout() -> void:
	var factor := hud.scale_factor
	for canvas: Canvas in [sheet, prompt]:
		canvas.scale = Vector2(factor, factor)
	sheet.position = (ORIGIN + Vector2(hud.right_shift * 0.5, 0)) * factor
	sheet.size = Vector2(640, 600)
	prompt.position = (PROMPT_ORIGIN + Vector2(hud.right_shift * 0.5, 0)) * factor
	prompt.size = Vector2(660, 520)

## Lists, selections and enabled states in the original's order.
func refresh() -> void:
	entries[0] = ELMapPickups.availability(state, player)
	entries[1] = ELGlobalSpells.data(state, player).get("active", []).duplicate()
	entries[2] = ELGlobalSpells.acting_on(state, player)
	for list in 3:
		var count: int = entries[list].size()
		if count == 0: picks[list] = -1
		elif picks[list] < 0 or picks[list] >= count: picks[list] = 0
		scrolls[list] = clampi(scrolls[list], 0, maxi(0, count - VISIBLE))
		buttons[SCROLLS[list][0]].disabled = scrolls[list] <= 0
		buttons[SCROLLS[list][1]].disabled = scrolls[list] >= count - VISIBLE
	var code := selected_code()
	buttons.MoreMana.disabled = code.is_empty()
	buttons.LessMana.disabled = code.is_empty() or extra <= 0
	buttons.CastSpell.disabled = code.is_empty() or not ELGlobalSpells.produce_problem(state, player, code).is_empty()
	buttons.CancelSpell.disabled = production().is_empty()
	buttons.GSDispell.disabled = entries[1].is_empty()
	sheet.queue_redraw()

func selected_code() -> String:
	return str(entries[0][picks[0]].code) if picks[0] >= 0 else ""

func production() -> Dictionary:
	return ELGlobalSpells.data(state, player).get("production", {})

func _produce() -> void:
	var code := selected_code()
	if code.is_empty() or not ELGlobalSpells.produce(state, player, code, extra): return
	extra = 0
	refresh()
	if int(production().get("state", 0)) == 2: open_prompt()

func _dispel() -> void:
	if picks[1] < 0: return
	ELGlobalSpells.dispel(state, player, int(entries[1][picks[1]].serial))
	refresh()

func _scroll(list: int, delta: int) -> void:
	scrolls[list] += delta
	refresh()

## Cell rectangle of a visible list position.
func cell(list: int, slot: int) -> Rect2:
	return Rect2(LISTS[list] + Vector2(STEP * slot, 0), CELL)

## (list, entry) under a point, or [-1, -1].
func entry_at(point: Vector2) -> Array:
	for list in 3:
		if not LIST_AREAS[list].has_point(point): continue
		for slot in VISIBLE:
			var index: int = scrolls[list] + slot
			if index < entries[list].size() and cell(list, slot).has_point(point): return [list, index]
	return [-1, -1]

func _press(point: Vector2) -> void:
	var hit := entry_at(point)
	if int(hit[0]) < 0: return
	if int(hit[0]) == 0: extra = 0
	picks[hit[0]] = int(hit[1])
	refresh()

## Living castles in player order: the local player's first, then the others,
## then the Ancient Tomb while it is open.
func castles() -> Array:
	var result: Array = [{"player": player, "at": OWN_CASTLE}]
	var ids: Array = state.scenario.get("castles", {}).keys()
	ids.sort()
	var row := 0
	for id: int in ids:
		if id == player or not ELFirstScenario.alive(state, id) or ELFirstScenario.castle_object(state, id).is_empty(): continue
		result.append({"player": id, "at": CASTLES + Vector2(0, CASTLE_STEP * row)})
		row += 1
	if state.scenario.get("tomb_open", false):
		for item: Dictionary in state.objects.values():
			if item.get("name") == "AncientTomb":
				result.append({"player": ELGlobalSpells.TOMB_TARGET, "tomb": item, "at": CASTLES + Vector2(0, CASTLE_STEP * row)})
				break
	return result

func _castle_icon(entry: Dictionary) -> Texture2D:
	var item: Dictionary = entry.get("tomb", ELFirstScenario.castle_object(state, int(entry.player)))
	var index := int(ELAdditionalBuildings.definition(profile, item).get("Icon", -1)) if entry.has("tomb") else int(hud._art.resolve(item).get("row", {}).get("Icon", -1))
	return hud.building_icon(index) if index >= 0 else null

func _attacked(id: int) -> bool:
	for owner: int in state.players:
		for spell: Dictionary in state.players[owner].get("global_spells", {}).get("active", []):
			if spell.code == ELGlobalSpells.WARRIOR and int(spell.castle) == id: return true
	return false

func _draw_sheet() -> void:
	for piece: Dictionary in _pieces: sheet.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	for list in 3:
		for slot in VISIBLE:
			var index: int = scrolls[list] + slot
			if index >= entries[list].size(): break
			var picture := _list_icon(list, entries[list][index])
			var rect := cell(list, slot)
			var dim := list == 0 and not castable(entries[list][index])
			if picture != null: sheet.draw_texture_rect(picture, rect, false, Color(0.5, 0.5, 0.5) if dim else WHITE)
			if index == picks[list]: sheet.draw_rect(rect.grow(1), PICK, false, 2.0)
	var code := selected_code()
	var price := ELGlobalSpells.resources(profile, code) if not code.is_empty() else {}
	var wallet: Dictionary = state.players[player].resources
	var kinds := ELResources.types("el1")
	for row in kinds.size():
		var amount := int(price.get(kinds[row], 0))
		_value(COST_ROW + Vector2(COST_STEP * row, 0), "-" if code.is_empty() else str(amount), RED if amount > int(wallet.get(kinds[row], 0)) else WHITE)
	if code.is_empty():
		_value(ETHER, "-", WHITE)
		_value(UPKEEP, "-", VALUE)
	else:
		_value(ETHER, str(ELGlobalSpells.ether_cost(state, player, code, extra)), WHITE)
		_value(UPKEEP, str(ELGlobalSpells.upkeep(profile, code) + extra / 10), VALUE)
	var current := production()
	if not current.is_empty():
		var picture := icon(profile, int(ELGlobalSpells.row(profile, str(current.code)).get("Icon", -1)))
		if picture != null: sheet.draw_texture_rect(picture, Rect2(PRODUCTION, CELL), false)
		if _states != null:
			sheet.draw_texture_rect_region(_states, BAR, Rect2(113, 0, 1, 16))
			var width := floorf(BAR.size.x * mini(int(current.spent), int(current.cost)) / maxf(1, int(current.cost)))
			if width > 0: sheet.draw_texture_rect_region(_states, Rect2(BAR.position, Vector2(width, BAR.size.y)), Rect2(112, 0, 1, 16))
		_value(SPENT, str(int(current.spent)), VALUE)
		_value(TOTAL, str(int(current.cost)), VALUE)
		var turns := ELGlobalSpells.turns_left(state, player)
		_value(TURNS, "-" if turns == ELGlobalSpells.TURNS_UNKNOWN else str(turns), VALUE)
	if picks[1] >= 0:
		var held: Dictionary = entries[1][picks[1]]
		_value(HELD_UPKEEP, str(ELGlobalSpells.upkeep(profile, str(held.code))), VALUE)
		_value(HELD_PROTECTION, str(int(held.get("protection", 0))), VALUE)
	else:
		_value(HELD_UPKEEP, "-", VALUE)
		_value(HELD_PROTECTION, "-", VALUE)
	for entry: Dictionary in castles():
		var at: Vector2 = entry.at
		var picture := _castle_icon(entry)
		if picture != null: sheet.draw_texture_rect(picture, Rect2(at, CELL), false)
		if entry.has("tomb"): continue
		var id := int(entry.player)
		if id == player and _symbols != null: sheet.draw_texture_rect_region(_symbols, Rect2(at, CELL), Rect2(0, 60, 4, 4))
		if _states == null: continue
		var bar := Rect2(at + CASTLE_BAR.position, CASTLE_BAR.size)
		sheet.draw_texture_rect_region(_states, bar, Rect2(0x72, 1, 9, 1))
		var energy := clampf(int(state.scenario.castles.get(id, {}).get("health", 0)) / CASTLE_FULL, 0, 1)
		var filled := floorf((bar.size.y - 2) * energy)
		if filled > 0: sheet.draw_texture_rect_region(_states, Rect2(bar.position.x, bar.end.y - 1 - filled, bar.size.x, filled), Rect2(0x72, 0, 9, 1))
		if not ELGlobalSpells.defender(state, id).is_empty(): sheet.draw_texture_rect_region(_states, Rect2(at + Vector2(107, 7), Vector2(14, 14)), Rect2(56, 0, 14, 14))
		if _attacked(id): sheet.draw_texture_rect_region(_states, Rect2(at + Vector2(107, 30), Vector2(14, 14)), Rect2(84, 0, 14, 14))

func _list_icon(list: int, entry: Dictionary) -> Texture2D:
	match list:
		0: return icon(profile, entry_icon(profile, entry))
		1: return icon(profile, int(ELGlobalSpells.row(profile, str(entry.code)).get("Icon", -1)))
		_: return icon(profile, int(ELGlobalSpells.row(profile, str(entry.spell.code)).get("Icon", -1)))

## A value centred on its box, with a shadow.
func _value(center: Vector2, text: String, color: Color, canvas: Canvas = null) -> void:
	var target: Canvas = sheet if canvas == null else canvas
	var font: Font = hud._bold
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var at := Vector2(center.x - width * 0.5, center.y + 5)
	target.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9))
	target.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func _tooltip(point: Vector2) -> String:
	for name: String in TIPS:
		if TIPS[name].has_point(point): return profile.text("CtrlTt" + name)
	if Rect2(PRODUCTION, CELL).has_point(point) and not production().is_empty(): return ELGlobalSpells.title(profile, str(production().code))
	var hit := entry_at(point)
	if int(hit[0]) == 0:
		var entry: Dictionary = entries[0][hit[1]]
		var text := ELGlobalSpells.title(profile, str(entry.code))
		if not castable(entry): text += "\n" + profile.text("T_GLOBAL_SPELL_PART")
		return text
	if int(hit[0]) == 1: return ELGlobalSpells.title(profile, str(entries[1][hit[1]].code)) + _target_name(entries[1][hit[1]])
	if int(hit[0]) == 2: return ELGlobalSpells.title(profile, str(entries[2][hit[1]].spell.code)) + "\n" + ELFirstScenario.player_name(state, int(entries[2][hit[1]].owner))
	for entry: Dictionary in castles():
		var at: Vector2 = entry.at
		if Rect2(at, CELL).has_point(point): return _castle_label(int(entry.player))
		if entry.has("tomb"): continue
		if Rect2(at + Vector2(107, 7), Vector2(14, 14)).has_point(point) and not ELGlobalSpells.defender(state, int(entry.player)).is_empty(): return profile.text("T_GS_ETHERIAL_DEFENDER_TT")
		if Rect2(at + Vector2(107, 30), Vector2(14, 14)).has_point(point) and _attacked(int(entry.player)): return profile.text("T_GS_ETHERIAL_ATTACKER_TT")
	return ""

func _target_name(spell: Dictionary) -> String:
	if int(spell.hero) >= 0: return "\n" + str(state.object(int(spell.hero)).get("title", state.object(int(spell.hero)).get("name", "")))
	if int(spell.castle) >= 0: return "\n" + _castle_label(int(spell.castle))
	return ""

func _castle_label(id: int) -> String:
	if id == ELGlobalSpells.TOMB_TARGET:
		for item: Dictionary in state.objects.values():
			if item.get("name") == "AncientTomb": return ELAdditionalBuildings.title(profile, item)
		return "Ancient Tomb"
	return ELFirstScenario.player_name(state, id)

## Escape answers the prompt first (as SelectCancel), then closes the screen.
func cancel() -> void:
	if prompt.visible: _dismiss_prompt()
	else: closed.emit()

# --- GSSelectParams -------------------------------------------------------

func _build_prompt() -> void:
	prompt = Canvas.new()
	prompt.draw_call = _draw_prompt
	prompt.press_call = _press_prompt
	prompt.tip_call = _prompt_tooltip
	prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(prompt)
	for index in 2:
		var label := _label(prompt, Rect2(245, 128 + 20 * index, 295, 20), "", 15)
		label.add_theme_font_override("font", hud._bold)
		prompt_captions.append(label)
	_button(prompt, prompt_buttons, "SelectOK").pressed.connect(_apply)
	_button(prompt, prompt_buttons, "SelectCancel").pressed.connect(_dismiss_prompt)
	for list in 2:
		_button(prompt, prompt_buttons, PROMPT_SCROLLS[list][0]).pressed.connect(_scroll_prompt.bind(list, -1))
		_button(prompt, prompt_buttons, PROMPT_SCROLLS[list][1]).pressed.connect(_scroll_prompt.bind(list, 1))
	for button: BaseButton in prompt_buttons.values(): button.focus_mode = Control.FOCUS_NONE
	prompt.hide()

## The original "«%s» created" prompt with one choice list per parameter.
func open_prompt() -> void:
	var current := production()
	if current.is_empty() or int(current.state) != 2: return
	var params: Variant = ELGlobalSpells.row(profile, current.code).get("Params", [])
	_params = params if params is Array else ([] if str(params).is_empty() else [str(params)])
	_targets = ELGlobalSpells.targets(state, player, current.code)
	prompt_captions[0].text = _text("T_GS_PRODUSED_NO_PARAMS_1") % ELGlobalSpells.title(profile, current.code)
	if _targets.is_empty(): prompt_captions[1].text = _text("T_GS_PRODUSED_NO_PARAMS_2")
	elif _targets.size() == 1: prompt_captions[1].text = _text("T_GS_PRODUSED_ONE_PARAM_2") % _text("T_GS_PRODUSED_PARAM_" + str(_params[0]).to_upper())
	else: prompt_captions[1].text = _text("T_GS_PRODUSED_TWO_PARAMS_2")
	prompt_picks = [0, 0]
	prompt_scrolls = [0, 0]
	# The bottom panel follows the last list.
	var shift := Vector2(0, PROMPT_HEADER + PROMPT_LIST * _targets.size() - PROMPT_BOTTOM)
	var controls: Array = ["GSSelectParams", "GSBottom"]
	for list in _targets.size(): controls.append("GSList%d" % (list + 1))
	_prompt_pieces = compose(hud, controls)
	for piece: Dictionary in _prompt_pieces:
		if piece.control == "GSBottom": piece.rect.position += shift
	for name: String in ["SelectOK", "SelectCancel"]: prompt_buttons[name].place(shift)
	for list in 2:
		for name: String in PROMPT_SCROLLS[list]: prompt_buttons[name].visible = list < _targets.size()
	_refresh_prompt()
	prompt.show()

func _refresh_prompt() -> void:
	var possible := true
	for list in _targets.size():
		var count: int = _targets[list].size()
		possible = possible and count > 0
		prompt_scrolls[list] = clampi(prompt_scrolls[list], 0, maxi(0, count - VISIBLE))
		prompt_buttons[PROMPT_SCROLLS[list][0]].disabled = prompt_scrolls[list] <= 0
		prompt_buttons[PROMPT_SCROLLS[list][1]].disabled = prompt_scrolls[list] >= count - VISIBLE
	prompt_buttons.SelectOK.disabled = not possible
	prompt.queue_redraw()

func prompt_cell(list: int, slot: int) -> Rect2:
	return Rect2(PROMPT_ITEMS + Vector2(STEP * slot, PROMPT_LIST * list), CELL)

func _press_prompt(point: Vector2) -> void:
	for list in _targets.size():
		for slot in VISIBLE:
			var index: int = prompt_scrolls[list] + slot
			if index < _targets[list].size() and prompt_cell(list, slot).has_point(point):
				prompt_picks[list] = index
				_refresh_prompt()
				return

func _scroll_prompt(list: int, delta: int) -> void:
	prompt_scrolls[list] += delta
	_refresh_prompt()

func _apply() -> void:
	var chosen: Array = []
	for list in _targets.size(): chosen.append(_targets[list][prompt_picks[list]])
	prompt.hide()
	ELGlobalSpells.cast(state, player, chosen)
	refresh()

## SelectCancel: the created spell is dispelled.
func _dismiss_prompt() -> void:
	prompt.hide()
	ELGlobalSpells.cancel(state, player)
	refresh()

func target_icon(list: int, id: int) -> Texture2D:
	match str(_params[list]):
		"Hero":
			var portrait := profile.portrait(int(hud._art.resolve(state.object(id)).get("row", {}).get("Face", 0)))
			if portrait is AtlasTexture:
				var atlas := AtlasTexture.new()
				atlas.atlas = (portrait as AtlasTexture).atlas
				atlas.region = Rect2((portrait as AtlasTexture).region.position + Vector2(15, 10), CELL)
				return atlas
			return portrait
		"Castle": return _castle_icon({"player": id} if id != ELGlobalSpells.TOMB_TARGET else {"player": id, "tomb": _tomb()})
		_:
			var index := ELBuildingScreen.icon(profile, state.object(id))
			return hud.building_icon(index) if index >= 0 else null

func _tomb() -> Dictionary:
	for item: Dictionary in state.objects.values():
		if item.get("name") == "AncientTomb": return item
	return {}

func target_label(list: int, id: int) -> String:
	if str(_params[list]) == "Castle": return _castle_label(id)
	var item := state.object(id)
	if item.get("type") == "hero": return str(item.get("title", item.get("name", "")))
	return ELBuildingScreen.title(profile, item)

func _draw_prompt() -> void:
	for piece: Dictionary in _prompt_pieces: prompt.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	var current := production()
	if not current.is_empty():
		var picture := icon(profile, int(ELGlobalSpells.row(profile, str(current.code)).get("Icon", -1)))
		if picture != null: prompt.draw_texture_rect(picture, Rect2(PROMPT_ICON, CELL), false)
	for list in _targets.size():
		for slot in VISIBLE:
			var index: int = prompt_scrolls[list] + slot
			if index >= _targets[list].size(): break
			var rect := prompt_cell(list, slot)
			var picture := target_icon(list, int(_targets[list][index]))
			if picture != null: prompt.draw_texture_rect(picture, rect, false)
			if index == prompt_picks[list]: prompt.draw_rect(rect.grow(1), PICK, false, 2.0)

func _prompt_tooltip(point: Vector2) -> String:
	if Rect2(PROMPT_ICON, CELL).has_point(point) and not production().is_empty(): return ELGlobalSpells.title(profile, str(production().code))
	for list in _targets.size():
		for slot in VISIBLE:
			var index: int = prompt_scrolls[list] + slot
			if index < _targets[list].size() and prompt_cell(list, slot).has_point(point): return target_label(list, int(_targets[list][index]))
	return ""

# --- helpers --------------------------------------------------------------

func _text(key: String) -> String:
	return profile.text(key).strip_edges()

func _label(canvas: Canvas, rect: Rect2, key: String, size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = profile.text(key) if not key.is_empty() else ""
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", hud._italic)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", CAPTION)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	return label

func _button(canvas: Canvas, into: Dictionary, control: String) -> ELAdventureHud.CutButton:
	var button := ELAdventureHud.CutButton.from_rows(hud, control, Vector2.ZERO)
	var tip := profile.text("CtrlTt" + control)
	if tip != "CtrlTt" + control: button.tooltip_text = tip
	button.place(Vector2.ZERO)
	canvas.add_child(button)
	into[control] = button
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
