class_name ELGameConsole
extends CanvasLayer
## The local developer console for both games. Only a playable, local game
## exposes map or battle commands.

const UNKNOWN := "Unknown command. Try: help"
const UNLOCK := "EtherRevelation"
const HISTORY_LIMIT := 80
const OUTPUT_LIMIT := 64000
const COMPLETION_LIMIT := 12
const SPELL_COLORS := ["Red", "Green", "Black", "Blue"]
const SPELL_CLASSES := ["Creature", "Sorcery", "Enchantment"]
const INK := Color("d5deed")
const ACCENT := Color("9ecfff")
const MUTED := Color("acbbd0")
const LOCKED := "Commands are locked. Choose Enable commands or enter EtherRevelation."
const NO_GAME := "Start a mission or local battle to use game commands."
const NETWORK := "Game commands are unavailable in a network duel."

## [Command to insert, arguments, description]. Commands keep their original
## spelling even when the console interface uses the game's language.
const COMMON := [
	["help", " [command]", "List commands or find help for a command."],
	["clear", "", "Clear the console output."],
	["copy", "", "Copy the console output to the clipboard."],
]
const ADVENTURE := [
	["player", "", "Show player information."],
	["view resources", " [player index, 0 = neutral]", "Show the local player's resources."],
	["view heroes", "", "List living heroes by commander, with their map coordinates."],
	["open_fog", "", "Reveal the map."],
	["hide_fog", "", "Restore the fog of war."],
	["give all", " [amount]", "Add resources to the local player. The default is 15 of each."],
	["save", "", "Quick-save the current map."],
	["load", "", "Open the quick-load prompt."],
	["win", "", "Win the current mission."],
	["lose", "", "Lose the current mission."],
]
const COMBAT := [
	["view army", "", "List your creatures."],
	["view creature", " [id]", "List battlefield creatures or inspect one by ID."],
	["view creature stats", " ID", "Show a creature's current stats and abilities."],
	["view creature basestats", " ID", "Show a creature's base stats and abilities."],
	["view creature modifiers", " ID", "Show stat changes and attached enchantments."],
	["view hand", "", "List your hand."],
	["view players", "", "Show the duelists and their stats."],
	["view spells", " [red|green|black|blue] [creature|sorcery|enchantment]", "List spell codes and names, optionally filtered by color and class."],
	["view_hand", "", "Show the opponent's hand in the card rail."],
	["hide_hand", "", "Return to your hand."],
	["swap", "", "Switch which side you control."],
	["add spell", " CODE", "Add a card to your hand."],
	["add creature", " CODE", "Summon a creature."],
	["add enemy", " CODE", "Summon a creature for the opposing hero."],
	["change health", " VALUE", "Set your hero's health."],
	["change mana", " VALUE", "Set your hero's ether."],
	["change links", " VALUE", "Set your hero's ether channels."],
	["change enemy health", " VALUE", "Set the opposing hero's health."],
	["change enemy mana", " VALUE", "Set the opposing hero's ether."],
	["change enemy links", " VALUE", "Set the opposing hero's ether channels."],
	["disenchant", " [id]", "Remove all enchantments from the selected figure or given ID."],
	["win", "", "Win the current battle."],
	["lose", "", "Lose the current battle."],
]

var game: Node
var panel: PanelContainer
var output: RichTextLabel
var entry: LineEdit
var _scroll_controls: VBoxContainer
var _scroll_profile: ELProfile
var _search: LineEdit
var _suggestions: ItemList
var _status: Label
var _hint: Label
var _enable: Button
var _expand: Button
var _full := false
var _font_size := 16
var _unlocked := {}
var _history: Array[String] = []
var _history_index := 0
var _draft := ""
var _text := ""
var _battle: WeakRef
var _local_side := 0
var _reveal_hand := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 130
	hide()
	var backdrop := Control.new()
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	panel = PanelContainer.new()
	backdrop.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("151d2af5")
	style.border_color = Color("486184")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)

	var header := HFlowContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "Developer console"
	title.add_theme_color_override("font_color", ACCENT)
	header.add_child(title)
	_enable = _button(header, "Enable commands", func(): _submit(UNLOCK))
	_button(header, "Help", func(): _submit("help"))
	_button(header, "Find", _find)
	_button(header, "Copy", _copy)
	_button(header, "A−", _resize_text.bind(-1))
	_button(header, "A+", _resize_text.bind(1))
	_expand = _button(header, "Expand", _toggle_full)
	_expand.tooltip_text = "Toggle fullscreen console"
	_button(header, "×", close).tooltip_text = "Close console"
	_status = Label.new()
	_status.add_theme_color_override("font_color", MUTED)
	header.add_child(_status)

	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Cascadia Mono", "Liberation Mono", "Courier New", "DejaVu Sans Mono"])
	_search = LineEdit.new()
	_search.placeholder_text = "Find in output…"
	_search.max_length = 256
	_search.text_changed.connect(func(_value): _render_output())
	_search.hide()
	layout.add_child(_search)

	var transcript := HBoxContainer.new()
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(transcript)
	output = RichTextLabel.new()
	output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output.scroll_following = true
	output.selection_enabled = true
	output.add_theme_font_override("normal_font", mono)
	output.add_theme_color_override("default_color", INK)
	transcript.add_child(output)
	_scroll_controls = VBoxContainer.new()
	_scroll_controls.hide()
	transcript.add_child(_scroll_controls)

	_suggestions = ItemList.new()
	_suggestions.focus_mode = Control.FOCUS_NONE
	_suggestions.item_clicked.connect(func(index: int, _at: Vector2, button: int):
		if button == MOUSE_BUTTON_LEFT: _accept(index))
	_suggestions.hide()
	layout.add_child(_suggestions)

	var row := HBoxContainer.new()
	layout.add_child(row)
	var prompt := Label.new()
	prompt.text = ">"
	prompt.add_theme_color_override("font_color", ACCENT)
	row.add_child(prompt)
	entry = LineEdit.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.placeholder_text = "Type a command or help…"
	entry.max_length = 256
	entry.keep_editing_on_text_submit = true
	entry.add_theme_font_override("font", mono)
	entry.add_theme_color_override("font_color", Color("eef3fa"))
	entry.text_submitted.connect(_submit)
	entry.text_changed.connect(func(_value): _complete())
	row.add_child(entry)
	_button(row, "Run", func(): _submit(entry.text))
	_hint = Label.new()
	_hint.clip_text = true
	_hint.add_theme_color_override("font_color", MUTED)
	layout.add_child(_hint)

	get_viewport().size_changed.connect(_layout)
	_layout()

func _button(parent: Container, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := maxf(0.01, viewport.y / 768.0)
	var size := viewport / factor
	panel.add_theme_font_size_override("font_size", _font_size)
	output.add_theme_font_size_override("normal_font_size", _font_size)
	entry.custom_minimum_size.y = _font_size * 2.5
	_suggestions.custom_minimum_size.y = _font_size * 4
	panel.size = Vector2(size.x, size.y if _full else size.y * 0.6)
	panel.scale = Vector2.ONE * factor

func _resize_text(delta: int) -> void:
	_font_size = clampi(_font_size + delta, 12, 26)
	_layout()
	entry.grab_focus()

func _toggle_full() -> void:
	_full = not _full
	_expand.text = "Collapse" if _full else "Expand"
	_layout()
	entry.grab_focus()

static func _toggle_key(event: InputEventKey) -> bool:
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed: return false
	return (event.physical_keycode in [KEY_QUOTELEFT, KEY_F10]
		or event.keycode in [KEY_QUOTELEFT, KEY_ASCIITILDE, KEY_F10]
		or event.unicode in [0x60, 0x7e, 0x401, 0x451])

## Front-end screens normally consume key events before they reach this layer.
func reserves_key(event: InputEventKey) -> bool:
	return visible or _toggle_key(event)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	if _toggle_key(event):
		if not event.echo:
			if visible: close()
			else: _open()
		get_viewport().set_input_as_handled()
		return
	if not visible: return

	var shortcut: bool = event.ctrl_pressed or event.meta_pressed
	if shortcut and _matches(event, KEY_F):
		_find()
	elif shortcut and event.shift_pressed and _matches(event, KEY_C):
		_copy()
	elif shortcut and _matches(event, KEY_L):
		_clear()
	elif shortcut and _matches(event, KEY_R):
		_history_choices()
	elif shortcut and event.keycode == KEY_SPACE:
		entry.grab_focus()
		_complete(true)
	elif event.keycode == KEY_ESCAPE:
		if _suggestions.visible: _suggestions.hide()
		elif _search.visible: _close_search()
		else: close()
	elif event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		var bar := output.get_v_scroll_bar()
		bar.value += (-1 if event.keycode == KEY_PAGEUP else 1) * bar.page
	elif entry.has_focus() and event.keycode == KEY_TAB:
		var pending: Variant = _suggestions.get_item_metadata(_suggestion_index()) if _suggestions.visible else null
		if pending == null or (pending is Dictionary and pending.from_caret != entry.caret_column): _complete(true)
		if _suggestions.visible: _accept(_suggestion_index())
	elif entry.has_focus() and event.keycode in [KEY_UP, KEY_DOWN]:
		var direction := -1 if event.keycode == KEY_UP else 1
		if _suggestions.visible:
			var index := posmod(_suggestion_index() + direction, _suggestions.item_count)
			_suggestions.select(index)
			_suggestions.ensure_current_is_visible()
		else: _history_step(direction)
	else: return
	get_viewport().set_input_as_handled()

static func _matches(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key

func _open() -> void:
	_refresh_scroll_controls()
	show()
	game._console_visibility(true)
	_update_status()
	_render_output()
	entry.grab_focus()

func _refresh_scroll_controls() -> void:
	var profile: ELProfile = game._shown_profile()
	if profile == _scroll_profile: return
	_scroll_profile = profile
	_scroll_controls.hide()
	for child: Node in _scroll_controls.get_children():
		_scroll_controls.remove_child(child)
		child.queue_free()
	if profile == null: return
	var up := _scroll_button(profile, "CoScrollU", 5, -1)
	_scroll_controls.add_spacer(false)
	var down := _scroll_button(profile, "CoScrollD", 240, 1)
	_scroll_controls.visible = up.has_art() and down.has_art()

func _scroll_button(profile: ELProfile, control: String, y: int, direction: int) -> ELCutPartButton:
	var button := ELCutPartButton.new()
	button.name = control
	# The 15×12 authored art stays centered in a larger hit area.
	button.build(profile, control, Rect2(770, y - 6, 31, 24))
	button.focus_mode = Control.FOCUS_NONE
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_scroll_controls.add_child(button)
	# A window focus change can consume the pointer release for an unfocused button.
	get_window().focus_exited.connect(button.notification.bind(Control.NOTIFICATION_FOCUS_EXIT))
	var repeat := Timer.new()
	repeat.one_shot = true
	button.add_child(repeat)
	button.pressed.connect(func():
		_scroll_line(direction)
		repeat.start(0.4))
	button.button_up.connect(repeat.stop)
	repeat.timeout.connect(func():
		if not button.is_visible_in_tree() or not button.is_pressed(): return
		_scroll_line(direction)
		repeat.start(0.07))
	return button

func _scroll_line(direction: int) -> void:
	var line_height := output.get_theme_font("normal_font").get_height(_font_size)
	var bar := output.get_v_scroll_bar()
	bar.value += direction * (line_height + output.get_theme_constant("line_separation"))

func close() -> void:
	if not visible: return
	_suggestions.hide()
	_close_search()
	entry.release_focus()
	hide()
	game._console_visibility(false)

func _find() -> void:
	_suggestions.hide()
	_search.show()
	_search.grab_focus()
	_search.select_all()

func _close_search() -> void:
	if not _search.visible: return
	_search.clear()
	_search.hide()
	_render_output()
	entry.grab_focus()

func _copy() -> void:
	var transcript := "\n".join(_chat_output())
	DisplayServer.clipboard_set((_text + transcript).strip_edges())
	entry.grab_focus()

func _clear() -> void:
	_text = ""
	_render_output()
	entry.grab_focus()

func _history_step(direction: int) -> void:
	if _history.is_empty(): return
	if _history_index == _history.size(): _draft = entry.text
	_history_index = clampi(_history_index + direction, 0, _history.size())
	_set_entry(_history[_history_index] if _history_index < _history.size() else _draft)

func _set_entry(text: String) -> void:
	entry.text = text
	entry.caret_column = text.length()
	_suggestions.hide()

func _submit(raw: String) -> void:
	var line := raw.strip_edges()
	_set_entry("")
	if line.is_empty(): return
	if _history.is_empty() or _history[-1] != line:
		_history.append(line)
		if _history.size() > HISTORY_LIMIT: _history.pop_front()
	_history_index = _history.size()
	_draft = ""
	var reply := execute(line)
	if line.to_lower() != "clear":
		_text += "> " + line + "\n"
		if not reply.is_empty(): _text += tr(reply) + "\n"
		_text = _text.right(OUTPUT_LIMIT)
		_render_output()
	if visible:
		_update_status()
		entry.grab_focus()

func _render_output() -> void:
	output.clear()
	var query := _search.text.to_lower()
	for line: String in _text.split("\n", false):
		if not query.is_empty() and not line.to_lower().contains(query): continue
		output.push_color(ACCENT if line.begins_with("> ") else INK)
		output.add_text(line + "\n")
		output.pop()
	for line: String in _chat_output():
		if not query.is_empty() and not line.to_lower().contains(query): continue
		output.push_color(ACCENT)
		output.add_text(line + "\n")
		output.pop()

func _chat_output() -> PackedStringArray:
	var lines := PackedStringArray()
	var link: ELNetworkDuel = game.get("network_duel")
	if link == null or link.profile.id != "el1" or not link.can_chat(): return lines
	for message: Dictionary in link.chat_history:
		lines.append("%s  %s" % [ELNetworkChat.speaker(message.side == link.local_side), message.text])
	return lines

func refresh_chat() -> void:
	if visible: _render_output()

func _rows() -> Array:
	match _mode():
		"map":
			var edition := _map().state.map.profile.id
			var resources := ELResources.types(edition).duplicate()
			if edition == "el2": resources.append_array(ELResources.SEQUEL_FIELDS.values())
			var rows := COMMON + ADVENTURE
			if edition == "el1": rows.append(["open_tomb", "", "Open the Ancient Tomb for ethereal attacks."])
			for resource: String in resources:
				rows.append(["give " + resource, " AMOUNT", "Add one resource to the local player."])
			return rows
		"battle": return COMMON + COMBAT
	return COMMON

func _help(query: String) -> String:
	var lines := PackedStringArray()
	for row: Array in _rows():
		if query.is_empty() or (row[0] + row[1]).to_lower().contains(query):
			lines.append(_command_description(row))
	return "\n".join(lines) if not lines.is_empty() else tr(UNKNOWN)

func _command_description(row: Array) -> String:
	return row[0] + tr(row[1]) + "  —  " + tr(row[2])

func _complete(force := false) -> void:
	var input := entry.text.strip_edges(true, false).to_lower()
	var prefix := input.strip_edges()
	_suggestions.clear()
	if not force and prefix.is_empty():
		_suggestions.hide()
		return
	if _complete_help_topic():
		_show_suggestions()
		return
	var kind := input.get_slice(" ", 1)
	var card_command := "add %s " % kind
	var battle := _mode() == "battle"
	if battle and _complete_spell_filter():
		_show_suggestions()
		return
	if battle and kind in ["spell", "creature", "enemy"] and input.begins_with(card_command):
		_complete_card(card_command, input.trim_prefix(card_command))
	else:
		for row: Array in _rows():
			if not prefix.is_empty() and not row[0].to_lower().begins_with(prefix): continue
			_add_suggestion(row[0], _command_description(row))
			if _suggestions.item_count >= COMPLETION_LIMIT: break
	_show_suggestions()

func _complete_help_topic() -> bool:
	var source := entry.text
	var command := source.strip_edges(true, false)
	if command.length() < 5 or command.left(4).to_lower() != "help" or command[4] not in [" ", "\t"]: return false
	var start := source.length() - command.length() + 5
	while start < source.length() and source[start] in [" ", "\t"]: start += 1
	var caret := entry.caret_column
	if caret < start: return false
	var end := caret
	while end < source.length() and source[end] not in [" ", "\t"]: end += 1
	var prefix := " ".join(source.substr(start, caret - start).to_lower().replace("\t", " ").split(" ", false))
	if not prefix.is_empty() and source[caret - 1] in [" ", "\t"]: prefix += " "
	for row: Array in _rows():
		if not row[0].to_lower().begins_with(prefix): continue
		_add_text_completion(row[0], start, end, _command_description(row))
		if _suggestions.item_count >= COMPLETION_LIMIT: break
	return true

func _complete_spell_filter() -> bool:
	var source := entry.text
	var caret := entry.caret_column
	var start := caret
	while start > 0 and source[start - 1] not in [" ", "\t"]: start -= 1
	var before := source.left(start)
	var words := before.to_lower().replace("\t", " ").split(" ", false)
	if words.size() < 2 or words[0] != "view" or words[1] != "spells": return false
	var end := caret
	while end < source.length() and source[end] not in [" ", "\t"]: end += 1
	var prefix := source.substr(start, caret - start).to_lower()
	for candidate: String in SPELL_COLORS + SPELL_CLASSES:
		var filter := candidate.to_lower()
		if filter.begins_with(prefix):
			_add_text_completion(filter, start, end, filter)
	return true

func _complete_card(verb: String, input: String) -> void:
	var prefix := input.strip_edges().to_upper()
	var duel: ELDuel = game.duel
	var codes := duel.profile.table("CombatSpells" if verb == "add spell " else "CombatCreatures").keys()
	codes.sort()
	for code: String in codes:
		if not prefix.is_empty() and not code.begins_with(prefix): continue
		_add_suggestion(verb + code, code + "  —  " + duel.card_name(code))
		if _suggestions.item_count >= COMPLETION_LIMIT: break

func _history_choices() -> void:
	entry.grab_focus()
	var prefix := entry.text.to_lower()
	_suggestions.clear()
	for index in range(_history.size() - 1, -1, -1):
		var line := _history[index]
		if not prefix.is_empty() and not line.to_lower().contains(prefix): continue
		_add_suggestion(line, line)
		if _suggestions.item_count >= COMPLETION_LIMIT: break
	_show_suggestions()

func _add_suggestion(insert: Variant, caption: String) -> void:
	var index := _suggestions.add_item(caption)
	_suggestions.set_item_metadata(index, insert)
	_suggestions.set_item_tooltip(index, caption)

func _add_text_completion(insert: String, start: int, end: int, caption: String) -> void:
	var source := entry.text
	_add_suggestion({"text": source.left(start) + insert + source.substr(end), "caret": start + insert.length(), "from_caret": entry.caret_column}, caption)

func _show_suggestions() -> void:
	_suggestions.visible = _suggestions.item_count > 0
	if _suggestions.visible: _suggestions.select(0)

func _suggestion_index() -> int:
	var indices := _suggestions.get_selected_items()
	return indices[0] if not indices.is_empty() else 0

func _accept(index: int) -> void:
	var choice: Variant = _suggestions.get_item_metadata(index)
	if choice is Dictionary:
		if choice.from_caret != entry.caret_column:
			_complete(true)
			return
		_set_entry(choice.text)
		entry.caret_column = choice.caret
	else: _set_entry(str(choice))
	entry.grab_focus()

func _map() -> ELAdventureView:
	var map: ELAdventureView = game.campaign_view
	return map if map != null and map.visible and map.state != null else null

func _networked() -> bool:
	return game.get("network_duel") != null or game.get("strategic_session") != null

func _mode() -> String:
	if _networked(): return ""
	var map := _map()
	if map != null: return "map" if map.state.outcome.is_empty() else ""
	if game.duel == null or game.demo or game.movie_player != null or game.replay_player != null or game.combat_tutorial != null: return ""
	if game.duel.phase == ELDuel.Phase.FINISHED: return ""
	if game.front_menu != null and game.front_menu.is_visible_in_tree(): return ""
	return "battle" if game.stage != null and game.stage.is_visible_in_tree() else ""

func _context_key() -> String:
	var kind := _mode()
	if kind == "map": return _map().state.map.profile.id + ":map"
	if kind == "battle": return game.duel.profile.id + ":battle"
	return ""

func _update_status() -> void:
	var context := _context_key()
	var unlocked := bool(_unlocked.get(context, false))
	_enable.visible = not context.is_empty() and not unlocked
	_status.text = NETWORK if _networked() else (NO_GAME if context.is_empty() else ("Commands enabled" if unlocked else "Commands locked"))
	_hint.text = "Tab: complete  ·  ↑/↓: history  ·  Ctrl+F: find  ·  Esc: close"

func player_side(duel: ELDuel) -> int:
	if _battle == null or _battle.get_ref() != duel:
		_battle = weakref(duel) if duel != null else null
		_local_side = 0
		_reveal_hand = false
	return _local_side

func enemy_hand(duel: ELDuel) -> bool:
	player_side(duel)
	return _reveal_hand and not _networked()

func execute(line: String) -> String:
	var words := line.replace("\t", " ").split(" ", false)
	if words.is_empty(): return ""
	var verb := words[0].to_lower()
	if verb == "help": return _help(" ".join(words.slice(1)).to_lower())
	if words.size() == 1 and verb == "clear":
		_clear()
		return ""
	if words.size() == 1 and verb == "copy":
		_copy()
		return ""
	if _networked(): return tr(NETWORK)
	var context := _context_key()
	if context.is_empty(): return tr(NO_GAME)
	if words.size() == 1 and verb == UNLOCK.to_lower():
		_unlocked[context] = true
		return tr("Commands enabled")
	if not _unlocked.get(context, false): return tr(LOCKED)
	var map := _map()
	if map != null: return _adventure(map, verb, words)
	return _combat(game.duel, verb, words)

func _adventure(view: ELAdventureView, verb: String, words: PackedStringArray) -> String:
	var state := view.state
	var player := state.current_player
	match verb:
		"player": return _list_adventure_players(state)
		"view":
			if words.size() >= 2 and words[1] == "resources": return _view_resources(state, words)
			if words.size() >= 2 and words[1] == "heroes": return _list_adventure_heroes(state)
		"give": return _give_resources(state, words)
		"open_fog", "hide_fog":
			ELFog.reveal_for_console(state, player, verb == "open_fog")
			return ""
		"open_tomb":
			if not ELFirstScenario.applies(state): return UNKNOWN
			if not state.scenario.tomb_open:
				state.scenario.tomb_open = true
				state.event.emit({"kind": "tomb_opened"})
			return ""
		"win", "lose":
			close()
			state._native([1.0 if verb == "win" else 0.0], "ExWinLoseMission")
			return ""
		"save":
			close()
			view.quick_save()
			return ""
		"load":
			close()
			view.ask_quick_load()
			return ""
	return UNKNOWN

func _list_adventure_heroes(state: ELAdventureSession) -> String:
	# Native commander lists begin with neutral, followed by the authored seats.
	var rosters := {0: []}
	for seat: Dictionary in state.map.players:
		rosters[int(seat.attrs.id)] = []
	for item: Dictionary in state.objects.values():
		if not item.alive or not rosters.has(item.owner): continue
		# The sequel also attaches monsters belonging to a non-neutral commander.
		var owned_monster: bool = state.map.profile.id == "el2" and item.type == "monster" and item.owner != 0
		if item.type == "hero" or owned_monster:
			rosters[item.owner].append("%d  %d  %s (%d, %d)" % [item.uid, item.owner, item.get("title", item.name), item.x, item.y])
	var lines := PackedStringArray()
	for roster: Array in rosters.values(): lines.append_array(PackedStringArray(roster))
	return "\n".join(lines)

func _list_adventure_players(state: ELAdventureSession) -> String:
	# Native commander lists begin with an unlabelled neutral commander.
	var lines := PackedStringArray(["0"])
	var local := _local_adventure_player(state)
	for seat: Dictionary in state.map.players:
		var id := int(seat.attrs.id)
		if id == 0 or not state.players.has(id): continue
		var line := str(id)
		var color := String(state.players[id].get("color", "")).to_lower()
		if color in ["red", "green", "blue", "black"]: line += " " + color.rpad(5)
		lines.append(line + (" local " if id == local else " AI    "))
	return "\n".join(lines)

func _view_resources(state: ELAdventureSession, words: PackedStringArray) -> String:
	if words.size() > 3: return UNKNOWN
	var player := _local_adventure_player(state)
	if words.size() == 3:
		var selector := words[2]
		if not selector.is_valid_int(): return UNKNOWN
		var seats := state.map.players
		# Neutral occupies index 0, followed by the authored seats. An
		# out-of-range number leaves the default local wallet selected.
		if selector.lstrip("+-0").length() <= str(seats.size()).length():
			var index := selector.to_int()
			if index >= 0 and index <= seats.size():
				player = 0 if index == 0 else int(seats[index - 1].attrs.id)
	var resources: Dictionary = state.players.get(player, {}).get("resources", {})
	return ELResources.describe(state.map.profile.id, resources)

func _local_adventure_player(state: ELAdventureSession) -> int:
	# The sequel's active script seat can temporarily be the computer's turn.
	return 1 if state.map.profile.id == "el2" else state.current_player

func _give_resources(state: ELAdventureSession, words: PackedStringArray) -> String:
	if words.size() not in [2, 3]: return UNKNOWN
	var edition := state.map.profile.id
	var resource := words[1]
	if resource != "all":
		if words.size() != 3: return UNKNOWN
		if edition == "el2":
			var alias: Variant = ELResources.SEQUEL_FIELDS.find_key(resource)
			if alias != null: resource = alias
		if resource not in ELResources.types(edition): return UNKNOWN
	var amount := 15
	if words.size() == 3:
		var number := words[2]
		if not number.is_valid_int() or number.lstrip("+-0").length() > str(ELResources.MAX_AMOUNT).length():
			return "Invalid amount."
		amount = number.to_int()
		if amount < 0 or amount > ELResources.MAX_AMOUNT: return "Invalid amount."
	var added := {resource: amount}
	if resource == "all":
		added = ELResources.empty(edition)
		for key: String in added: added[key] = amount
	var player := _local_adventure_player(state)
	if not state.change_resources(player, added): return state.error
	return ELResources.describe(edition, state.players[player].resources)

func _combat(duel: ELDuel, verb: String, words: PackedStringArray) -> String:
	var side := player_side(duel)
	if game._hot_seat() or game.mode_select.selected == 1: side = duel.active_side()
	var hero: Dictionary = duel.heroes[side]
	match verb:
		"view":
			if words.size() >= 2 and words[1].to_lower() == "creature": return _inspect_creature(duel, words.slice(2))
			if words.size() >= 2 and words[1].to_lower() == "spells": return _list_combat_spells(duel, " ".join(words.slice(2)).to_lower())
			if words.size() != 2: return UNKNOWN
			var lines := PackedStringArray()
			match words[1]:
				"army":
					for unit: Dictionary in duel.army(side):
						lines.append("%d  %s  %s" % [unit.id, unit.card, duel.card_name(unit.card)])
				"hand":
					for card: String in hero.hand: lines.append("%s  %s" % [card, duel.card_name(card)])
				"players":
					for id in 2:
						var item: Dictionary = duel.heroes[id]
						lines.append("%d  %s  health %d  mana %d  links %d" % [id + 1, item.get("title", item.faction), item.health, item.mana, item.channels])
				_: return UNKNOWN
			return "\n".join(lines) if not lines.is_empty() else "(empty)"
		"view_hand", "hide_hand":
			if game._hot_seat(): return UNKNOWN
			_reveal_hand = verb == "view_hand"
			game._console_refresh()
			return ""
		"swap":
			if game._hot_seat() or game.mode_select.selected == 1: return "Both sides are already under player control."
			_local_side = 1 - side
			game._console_refresh()
			return ""
		"add":
			if words.size() != 3 or words[1] not in ["spell", "creature", "enemy"]: return UNKNOWN
			var enemy := words[1] == "enemy"
			return _apply(duel, {"side": 1 - side if enemy else side, "op": "creature" if enemy else words[1], "card": words[2].to_upper()})
		"change":
			var enemy := words.size() > 1 and words[1] == "enemy"
			var index := 2 if enemy else 1
			if words.size() != index + 2 or words[index] not in ["health", "mana", "links", "link"] or not words[-1].is_valid_int(): return UNKNOWN
			return _apply(duel, {"side": 1 - side if enemy else side, "op": words[index], "value": words[-1].to_int()})
		"disenchant":
			if words.size() > 2 or (words.size() == 2 and not words[1].is_valid_int()): return UNKNOWN
			var target: int = words[1].to_int() if words.size() == 2 else game.selected_creature
			return _apply(duel, {"side": side, "op": verb, "target": target})
		"win", "lose":
			var reply := _apply(duel, {"side": side if verb == "win" else 1 - side, "op": "win"})
			if reply.is_empty(): close()
			return reply
	return UNKNOWN

func _list_combat_spells(duel: ELDuel, filters: String) -> String:
	var color := ""
	var kind := ""
	# The originals search the full argument string in fixed order. The last
	# recognized value in each list wins, regardless of how it was entered.
	for candidate: String in SPELL_COLORS:
		if filters.contains(candidate.to_lower()): color = candidate
	for candidate: String in SPELL_CLASSES:
		if filters.contains(candidate.to_lower()): kind = candidate
	var spells := duel.profile.table("CombatSpells")
	var codes := spells.keys()
	codes.sort()
	var lines := PackedStringArray()
	for code: String in codes:
		var spell: Dictionary = spells[code]
		if not color.is_empty() and spell.get("Color") != color: continue
		if not kind.is_empty() and spell.get("Class") != kind: continue
		lines.append("%s  %s" % [code, duel.card_name(code)])
	return "\n".join(lines) if not lines.is_empty() else "(empty)"

func _inspect_creature(duel: ELDuel, args: PackedStringArray) -> String:
	if args.is_empty():
		var lines := PackedStringArray()
		var ids := duel.creatures.keys()
		ids.sort()
		for id: int in ids:
			var unit: Dictionary = duel.creatures[id]
			lines.append("%d  P%d  %s  %s  %d/%d" % [id, int(unit.owner) + 1, unit.card, duel.card_name(unit.card), unit.power, unit.toughness])
		return "\n".join(lines) if not lines.is_empty() else tr("No creatures in play.")
	if args.size() > 2 or not args[-1].is_valid_int(): return tr(UNKNOWN)
	var mode := args[0].to_lower() if args.size() == 2 else ""
	if mode not in ["", "stats", "basestats", "modifiers"]: return tr(UNKNOWN)
	var id := args[-1].to_int()
	var unit: Dictionary = duel.creatures.get(id, {})
	if unit.is_empty(): return tr("Unknown creature ID %d. Use view creature to list IDs.") % id
	var heading := "%d  P%d  %s  %s" % [id, int(unit.owner) + 1, unit.card, duel.card_name(unit.card)]
	var printed: Dictionary = duel.profile.table("CombatCreatures")[unit.card]
	var base: Array = unit.get("base", [printed.Power, printed.Toughness])
	match mode:
		"basestats":
			return "%s\n%s  %s" % [heading, tr("Base power/toughness %d/%d") % [base[0], base[1]], _creature_flags(ELCatalog.flags(printed))]
		"stats":
			var active_flags: Array = unit.flags + unit.get("granted", [])
			return "%s\n%s  %s" % [heading, tr("Power/toughness %d/%d") % [unit.power, unit.toughness], _creature_flags(active_flags)]
		"modifiers":
			var lines := PackedStringArray([heading, tr("Net power/toughness change %+d/%+d") % [int(unit.power) - int(base[0]), int(unit.toughness) - int(base[1])]])
			for item: Dictionary in unit.enchantments:
				lines.append("%s  %s  %+d/%+d" % [item.card, duel.card_name(item.card), item.power, item.toughness])
			return "\n".join(lines)
	var status := tr("Ready")
	if id in duel.attacks: status = tr("Attacking")
	elif duel.blocks.has(id): status = tr("Blocking")
	elif unit.sick: status = tr("Summoning sickness")
	elif unit.resting: status = tr("Resting")
	return "%s\n%s  ·  %s" % [heading, status, tr("Power/toughness %d/%d · damage %d") % [unit.power, unit.toughness, unit.damage]]

func _creature_flags(flags: Array) -> String:
	var names := PackedStringArray()
	for flag: String in flags:
		var name := tr(ELCatalog.flag_name(flag))
		if not names.has(name): names.append(name)
	return ", ".join(names)

func _apply(duel: ELDuel, action: Dictionary) -> String:
	action.kind = "console"
	return "" if duel.console_action(action) else duel.error
