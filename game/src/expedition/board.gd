class_name ELExpeditionBoard
extends Control
## A battle reward, camp or encounter of the Expedition on the second game's
## spell shop (SpellShopScreen art, through ELMenuKit). The spellbook stands
## in the hero's spells and the room's offers (spells, artifacts, skills) in
## the shop's stock; the thing under the pointer (else the chosen offer, the
## marked card or the room itself) is described over the active-deck strip,
## and the deal table holds life and the actions without an icon (rest,
## drink, swear, and the ones done to a marked spellbook card).
##
## A click on an offer chooses it; a click on a spellbook card marks it (a
## second click unmarks it) to be replaced by a chosen spell or for the
## deal table's card actions. OK takes the chosen offer (a spell that needs a
## place takes the marked card's, or a free one); with no offer chosen it
## removes the marked card at a camp. Cancel is the room's way out (skip the
## reward, leave the encounter) and is hidden where there is none; Esc does
## nothing. Double-clicking an offer takes it at once when it needs no mark.

## The run's choice ids to apply in order (ELExpeditionRun.choose).
signal chosen(ids: Array)
## A view of the journal instead ("scout" the next rooms, "inspect" the
## warden).
signal aside(kind: String)

const PANEL := "SpellShopScreen"
const DESIGN := Vector2(1024, 768)
const CELL := Vector2(53, 52)
const ICON := Vector2(50, 50)
## Icon inset inside a cell, as in the spell shop.
const INSET := Vector2(2, 1)
const BAG_COLUMNS := 8
const BAG_ROWS := 5
const SHOP_COLUMNS := 5
const SHOP_ROWS := 5
const TAN := Color8(0xd6, 0xbb, 0x88)
## The shop's tints: white over the chosen offer, blue over a marked card
## (red when the mark would take the card away).
const PICK_TINT := Color(0xf0 / 255.0, 0xf0 / 255.0, 0xf0 / 255.0, 136 / 255.0)
const MARK_TINT := Color(0x80 / 255.0, 0x80 / 255.0, 1.0, 136 / 255.0)
const DROP_TINT := Color(1.0, 0.35, 0.25, 120 / 255.0)
const HOVER_INK := Color(1, 0.96, 0.84, 0.18)
## The deal table's area (the panel's coordinates), covered by the run's life.
const DEAL := Rect2(482, 402, 296, 116)
## Choices without an icon, on the deal table.
const PLAIN := ["heal", "recover", "mend", "oath", "challenge", "recover_reward"]
const WAY_OUT := ["leave", "skip"]
## Actions on a marked spellbook card: the choice's prefix, then its button.
const CARD_ACTIONS := {
	"remove": ["Remove the marked spell", "Убрать отмеченное"],
	"purge": ["Erase the marked spell", "Стереть отмеченное"],
	"echo": ["Copy the marked spell", "Копировать отмеченное"],
}

var kit: ELMenuKit
var profile: ELProfile
var russian := false
var phase := ""
var room_title := ""
var room_text := ""
## {id, icon, name, stats, text, needs}: needs "room" (a free place or a
## marked card to replace), "mark" (a marked card to replace) or "".
var offers: Array[Dictionary] = []
## {id, title, description} on the deal table.
var plain: Array[Dictionary] = []
## {prefix, title, description, ids: {card: choice id}}.
var card_actions: Array[Dictionary] = []
var way_out := ""
var deck: Array[String] = []
var max_deck := 24
var health_text := ""
var can_scout := false
var can_inspect := false
## Index into offers / deck, or -1.
var picked := -1
var marked := -1
## ["shop" / "bag", index], or ["deal", index into plain + card_actions].
var _hover := ["", -1]
var _canvas: Control
var _surface: Surface
var _offset := Vector2.ZERO
var _ok: ELCutPartButton
var _cancel: ELCutPartButton
var _count: Label
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_stats: Label
var _detail_text: Label
var _action_buttons: Array[Button] = []

## A board for `run` at a fresh reward, a camp or an encounter, or null when
## the game lacks the art or the room is past its first choice.
static func make(menu_kit: ELMenuKit, run: ELExpeditionRun, in_russian: bool) -> ELExpeditionBoard:
	if menu_kit == null or menu_kit.theme() == null or not menu_kit.has_control(PANEL): return null
	if run == null or run.phase not in ["reward", "rest", "event"] or not run.pending_card.is_empty(): return null
	var board := ELExpeditionBoard.new()
	board.kit = menu_kit
	board.profile = menu_kit.profile
	board.russian = in_russian
	board.phase = run.phase
	board.deck.assign(run.deck)
	board.max_deck = ELExpeditionRun.MAX_DECK
	board.health_text = board._text("Life %d / %d", "Здоровье %d / %d") % [run.health, run.max_health]
	var summary := run.room_summary()
	board.room_title = str(summary.get("title", ""))
	board.room_text = str(summary.get("description", ""))
	board.can_scout = not run.upcoming().is_empty()
	board.can_inspect = str(summary.get("illustration", "")) == "warden" and not run.opponent_at(run.current).is_empty()
	for option: Dictionary in run.choices():
		board._sort(option)
	if board.phase == "reward" and board.offers.is_empty(): return null
	board._build()
	return board

func _text(en: String, ru: String) -> String:
	return ru if russian else en

## Files a run choice as an offer, a deal-table action, a card action or the
## way out.
func _sort(option: Dictionary) -> void:
	var id := str(option.id)
	var prefix := id.get_slice(":", 0)
	var title := str(option.get("title", ""))
	var description := str(option.get("description", ""))
	var card := str(option.get("card", ""))
	if id in WAY_OUT:
		way_out = id
		return
	if CARD_ACTIONS.has(prefix) and not card.is_empty():
		for action: Dictionary in card_actions:
			if action.prefix == prefix:
				if not action.ids.has(card): action.ids[card] = id
				return
		var text := description if prefix != "remove" else _text("Take a spell out of the spellbook for the rest of the expedition.", "Убрать заклинание из книги до конца похода.")
		card_actions.append({"prefix": prefix, "title": CARD_ACTIONS[prefix][int(russian)], "description": text, "ids": {card: id}})
		return
	if id in PLAIN:
		plain.append({"id": id, "title": title, "description": description})
		return
	var offer := {"id": id, "name": title, "stats": "", "text": description, "needs": "", "icon": null}
	if prefix == "card":
		offer.merge(_card_facts(card), true)
		offer.needs = "room"
	elif option.has("artifact"):
		var lines := description.split("\n", true, 1)
		offer.icon = profile.card_icon(str(option.artifact.get("spell", "")))
		offer.stats = lines[0]
		offer.text = lines[1] if lines.size() > 1 else ""
	elif option.has("incoming"):
		offer.icon = profile.card_icon(str(option.incoming))
		offer.stats = _stats(str(option.incoming))
	elif prefix == "train":
		offer.icon = _skill_icon(id.get_slice(":", 1), int(option.get("rank", 0)))
	elif not card.is_empty():
		offer.icon = profile.card_icon(card)
		offer.stats = _stats(card)
		if id == "study":
			offer.needs = "mark"
			offer.text = profile.card_description(card)
	offers.append(offer)

func _card_facts(card: String) -> Dictionary:
	var description := profile.card_description(card)
	return {"icon": profile.card_icon(card), "name": ELEncyclopaedia.name(profile, card), "stats": _stats(card), "text": description if description != card else ""}

func _skill_icon(code: String, rank: int) -> Texture2D:
	var index := int(ELHeroSkills.definition(profile, code, rank).get("Icon", -1))
	var atlas := profile.texture("Interface/Skills/icon_1") if index >= 0 else null
	if atlas == null: return null
	var icon := AtlasTexture.new()
	icon.atlas = atlas
	icon.region = Rect2((index / 5) * 50, (index % 5) * 50, 50, 50)
	icon.filter_clip = true
	return icon

func _build() -> void:
	name = "ExpeditionBoard"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = kit.theme()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas = Control.new()
	_canvas.size = DESIGN
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_offset = kit.control_shift(PANEL)
	var art := kit.compose(PANEL)
	var backdrop := TextureRect.new()
	backdrop.texture = ImageTexture.create_from_image(art.image)
	backdrop.position = Vector2(art.origin) + _offset
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(backdrop)
	_surface = Surface.new()
	_surface.board = self
	_surface.size = DESIGN
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.add_child(_surface)
	_header("SpellShopHdrBag", _text("SPELLBOOK", "КНИГА ЗАКЛИНАНИЙ"))
	_count = _header("SpellShopHdrBagSpells", "")
	match phase:
		"reward":
			_header("SpellShopHdrShop", _text("REWARD", "НАГРАДА"))
			_header("SpellShopShopHdrSpells", _text("Choose one spell", "Выберите заклинание"))
			_header("SpellShopHdrDeck", _text("Spell", "Заклинание"))
		_:
			_header("SpellShopHdrShop", _text("CAMP", "ПРИВАЛ") if phase == "rest" else _text("ENCOUNTER", "ВСТРЕЧА"))
			_header("SpellShopShopHdrSpells", room_title)
			_header("SpellShopHdrDeck", _text("Details", "Подробности"))
	_header("SpellShopHdrDeal", _text("Expedition", "Поход"))
	_build_detail()
	_build_deal()
	_ok = _art_button("SpellShopOkBtn", "")
	_ok.pressed.connect(take)
	_cancel = _art_button("SpellShopCancelBtn", _text("Skip reward", "Пропустить награду") if way_out == "skip" else _text("Leave", "Уйти"))
	_cancel.visible = not way_out.is_empty()
	_cancel.pressed.connect(func(): chosen.emit([way_out]))
	_build_asides()
	resized.connect(_layout)
	_refresh()

func _design(control: String) -> Rect2:
	var rect := kit.control_rect(control)
	rect.position += _offset
	return rect

func _header(control: String, value: String) -> Label:
	var row := kit.control_row(control)
	var label := Label.new()
	label.name = control
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", ELFrontMenu.cell_em(int(row.get("FontSize", 18))) + 1)
	label.add_theme_color_override("font_color", TAN)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := _design(control)
	label.position = rect.position
	label.size = rect.size
	_canvas.add_child(label)
	return label

func _art_button(control: String, tip: String) -> ELCutPartButton:
	var button := ELCutPartButton.new()
	button.name = control
	button.focus_mode = Control.FOCUS_NONE
	var rect := kit.control_rect(control)
	button.build(profile, control, rect)
	button.position = rect.position + _offset
	button.tooltip_text = tip
	_canvas.add_child(button)
	return button

## What is under the pointer, over the active-deck strip.
func _build_detail() -> void:
	var box := PanelContainer.new()
	box.name = "Detail"
	box.add_theme_stylebox_override("panel", kit.panel_style("box", Vector4(10, 8, 10, 8)))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := _design("SpellShopASpellsBounds1").grow(3)
	box.position = rect.position
	box.size = rect.size
	box.clip_contents = true
	_canvas.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	box.add_child(line)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = ICON
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(_detail_icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 1)
	line.add_child(words)
	_detail_name = _line(words, 17, ELMenuKit.HOVER_INK)
	_detail_stats = _line(words, 14, TAN)
	_detail_text = _line(words, 13, ELMenuKit.BODY_INK)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A clipped label keeps a zero height; this one is held by the box.
	_detail_text.clip_text = false
	_detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_text.custom_minimum_size.x = 380
	_detail_text.max_lines_visible = 3
	_detail_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _line(parent: Control, font_size: int, ink: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

## Life and the actions without an icon in place of the bill.
func _build_deal() -> void:
	var box := PanelContainer.new()
	box.name = "Deal"
	box.add_theme_stylebox_override("panel", kit.panel_style("box", Vector4(12, 8, 12, 8)))
	box.position = DEAL.position + _offset
	box.size = DEAL.size
	_canvas.add_child(box)
	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 6)
	box.add_child(rows)
	var life := _line(rows, 17, ELMenuKit.BODY_INK)
	life.text = health_text
	life.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var entries: Array[Dictionary] = []
	entries.append_array(plain)
	entries.append_array(card_actions)
	for index in entries.size():
		var entry := entries[index]
		var button := Button.new()
		button.name = "Deal_" + str(entry.get("id", entry.get("prefix", "")))
		button.text = str(entry.title)
		button.tooltip_text = str(entry.description)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.y = 28
		button.add_theme_font_size_override("font_size", 14)
		# A lone button may take two lines; a pair keeps to one each.
		if entries.size() == 1: button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else: button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.mouse_entered.connect(_hover_deal.bind(index))
		button.mouse_exited.connect(_hover_deal.bind(-1))
		if entry.has("id"):
			var id := str(entry.id)
			button.pressed.connect(func(): chosen.emit([id]))
		else:
			button.set_meta("card_action", entry)
			button.pressed.connect(_card_action.bind(entry))
		rows.add_child(button)
		_action_buttons.append(button)

func _hover_deal(index: int) -> void:
	_hover = ["deal", index] if index >= 0 else ["", -1]
	_refresh()

func _card_action(action: Dictionary) -> void:
	if marked < 0 or not action.ids.has(deck[marked]): return
	chosen.emit([action.ids[deck[marked]]])

## Journal views the old page offered beside the choices, in the bottom
## strip left of OK.
func _build_asides() -> void:
	var kinds: Array = []
	if can_inspect: kinds.append(["inspect", _text("Inspect opponent", "Посмотреть соперника")])
	if can_scout: kinds.append(["scout", _text("Scout next rooms", "Разведка комнат")])
	var ok_rect := _design("SpellShopOkBtn")
	var left := _design("SpellShopBagBounds").position.x
	for row: Array in kinds:
		var kind: String = row[0]
		var button := Button.new()
		button.name = "Aside_" + kind
		button.text = row[1]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 14)
		button.position = Vector2(left, ok_rect.position.y + 2)
		button.size = Vector2(190, ok_rect.size.y - 4)
		button.pressed.connect(func(): aside.emit(kind))
		_canvas.add_child(button)
		left += 200

func _layout() -> void:
	if size.x <= 0 or size.y <= 0: return
	var factor := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = ((size - DESIGN * factor) * 0.5).floor()

## What OK would do, as run choice ids (empty when it can do nothing).
func plan() -> Array:
	if picked >= 0:
		var offer := offers[picked]
		match str(offer.needs):
			"room":
				if marked >= 0: return [offer.id, "replace:%d" % marked]
				return [offer.id, "add"] if deck.size() < max_deck else []
			"mark":
				return [offer.id, "replace:%d" % marked] if marked >= 0 else []
		return [offer.id]
	# With no offer chosen, a camp's OK removes the marked card.
	if marked >= 0 and card_actions.size() == 1 and card_actions[0].prefix == "remove":
		var ids: Dictionary = card_actions[0].ids
		if ids.has(deck[marked]): return [ids[deck[marked]]]
	return []

func can_take() -> bool:
	return not plan().is_empty()

func take() -> void:
	var ids := plan()
	if not ids.is_empty(): chosen.emit(ids)

func _ok_tip() -> String:
	if picked >= 0:
		var offer := offers[picked]
		var what := str(offer.name)
		if offer.needs == "room" or offer.needs == "mark":
			if marked >= 0: return _text("Take %s in place of %s", "Взять «%s» вместо «%s»") % [what, ELEncyclopaedia.name(profile, deck[marked])]
			if offer.needs == "mark": return _text("Mark a spellbook card to replace", "Отметьте заклинание в книге на замену")
			if deck.size() >= max_deck: return _text("The spellbook is full: mark a spell to replace", "Книга заполнена: отметьте заклинание на замену")
			return _text("Add %s to the spellbook", "Добавить «%s» в книгу") % what
		return what
	if not plan().is_empty(): return _text("Remove %s", "Убрать «%s»") % ELEncyclopaedia.name(profile, deck[marked])
	return _text("Choose an offer", "Выберите предложение") if not offers.is_empty() else ""

func _refresh() -> void:
	_count.text = _text("%d of %d spells", "Заклинаний: %d из %d") % [deck.size(), max_deck]
	_ok.disabled = not can_take()
	_ok.tooltip_text = _ok_tip()
	for button: Button in _action_buttons:
		if not button.has_meta("card_action"): continue
		var action: Dictionary = button.get_meta("card_action")
		button.disabled = marked < 0 or not action.ids.has(deck[marked])
		button.tooltip_text = str(action.description) if not button.disabled else _text("Mark a spellbook card first", "Сначала отметьте заклинание в книге")
	var facts := _subject()
	_detail_icon.texture = facts.get("icon")
	_detail_icon.visible = facts.get("icon") != null
	_detail_name.text = str(facts.get("name", ""))
	_detail_stats.text = str(facts.get("stats", ""))
	_detail_stats.visible = not _detail_stats.text.is_empty()
	_detail_text.text = str(facts.get("text", ""))
	_detail_text.max_lines_visible = 3 if _detail_stats.visible else 4
	_surface.queue_redraw()

## {icon, name, stats, text} for the detail box.
func _subject() -> Dictionary:
	match str(_hover[0]):
		"shop": return offers[_hover[1]]
		"bag": return _card_facts(deck[_hover[1]]).merged({"stats": _stats(deck[_hover[1]])})
		"deal":
			var entries: Array[Dictionary] = []
			entries.append_array(plain)
			entries.append_array(card_actions)
			var entry := entries[_hover[1]]
			var facts := {"name": entry.title, "text": entry.description}
			if not entry.has("id") and marked >= 0: facts.stats = ELEncyclopaedia.name(profile, deck[marked])
			return facts
	if picked >= 0: return offers[picked]
	if marked >= 0: return _card_facts(deck[marked])
	if phase == "reward":
		return {"name": _text("Choose a spell from the reward", "Выберите заклинание из награды"),
			"stats": _text("Mark a spellbook card to replace it instead.", "Отметьте заклинание в книге, чтобы заменить его.")}
	return {"name": room_title, "text": room_text}

func _stats(card: String) -> String:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	var kinds := {"Creature": _text("Creature", "Создание"), "Sorcery": _text("Sorcery", "Колдовство"), "Enchantment": _text("Enchantment", "Чары")}
	var line := "%s · %s" % [kinds.get(str(row.get("Class", "")), _text("Spell", "Заклинание")), _text("%d ether", "%d ед. эфира") % ELEncyclopaedia.cost(profile, card)]
	var strength := ELEncyclopaedia.strength(profile, card)
	if not strength.is_empty(): line += " · " + strength
	match str(row.get("Rarity", "")):
		"Rare": line += " · " + _text("Rare", "Редкое")
		"Unique": line += " · " + _text("Unique", "Уникальное")
	var copies := deck.count(card)
	if copies > 0: line += " · " + _text("%d in spellbook", "в книге: %d") % copies
	return line

## ["shop", i] or ["bag", i] under a canvas point (i -1 off the cards).
func hit(at: Vector2) -> Array:
	for which: String in ["bag", "shop"]:
		var bounds := _design("SpellShopBagBounds" if which == "bag" else "SpellShopShopBounds")
		if not bounds.has_point(at): continue
		var columns := BAG_COLUMNS if which == "bag" else SHOP_COLUMNS
		var cell := Vector2i((at - bounds.position) / CELL)
		if cell.x >= columns or cell.y >= (BAG_ROWS if which == "bag" else SHOP_ROWS): return [which, -1]
		var index := cell.y * columns + cell.x
		return [which, index if index < (deck.size() if which == "bag" else offers.size()) else -1]
	return ["", -1]

func cell_rect(which: String, index: int) -> Rect2:
	var columns := BAG_COLUMNS if which == "bag" else SHOP_COLUMNS
	var bounds := _design("SpellShopBagBounds" if which == "bag" else "SpellShopShopBounds")
	return Rect2(bounds.position + INSET + Vector2(index % columns, index / columns) * CELL, ICON)

func surface_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var target := hit(event.position)
		if target != _hover:
			_hover = target
			_refresh()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var target := hit(event.position)
		if target[1] < 0: return
		if target[0] == "shop":
			picked = -1 if picked == target[1] and not event.double_click else target[1]
			if event.double_click and str(offers[picked].needs) != "mark" and can_take(): take()
		else:
			marked = -1 if marked == target[1] else target[1]
		_refresh()
		accept_event()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _hover[0] in ["shop", "bag"]:
		_hover = ["", -1]
		_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.pressed or event.echo: return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and can_take():
		take()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		# As with the journal's choices, Esc never gives a room away.
		get_viewport().set_input_as_handled()

func _mark_tint() -> Color:
	if picked >= 0 and str(offers[picked].needs) != "": return MARK_TINT
	return DROP_TINT if not card_actions.is_empty() else MARK_TINT

func draw_surface(target: Control) -> void:
	for index in deck.size():
		var rect := cell_rect("bag", index)
		var icon := profile.card_icon(deck[index])
		if icon != null: target.draw_texture_rect(icon, rect, false)
		if index == marked: target.draw_rect(rect, _mark_tint())
		if _hover[0] == "bag" and _hover[1] == index: target.draw_rect(rect, HOVER_INK)
	for index in offers.size():
		var rect := cell_rect("shop", index)
		var icon: Texture2D = offers[index].icon
		if icon != null: target.draw_texture_rect(icon, rect, false)
		if index == picked: target.draw_rect(rect, PICK_TINT)
		if _hover[0] == "shop" and _hover[1] == index: target.draw_rect(rect, HOVER_INK)

class Surface extends Control:
	var board: ELExpeditionBoard

	func _draw() -> void:
		board.draw_surface(self)

	func _gui_input(event: InputEvent) -> void:
		board.surface_input(event)
