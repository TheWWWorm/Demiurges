class_name ELNetworkChat
extends PanelContainer
## Shared lobby and battlefield transcript. Player text is displayed literally.

var entry := LineEdit.new()
var transcript := RichTextLabel.new()
var _link: ELNetworkDuel

func build(link: ELNetworkDuel) -> void:
	_link = link
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0.09, 0.08, 0.065, 0.95)
	backing.border_color = Color("76613f")
	backing.set_border_width_all(1)
	backing.content_margin_left = 8
	backing.content_margin_right = 8
	backing.content_margin_top = 6
	backing.content_margin_bottom = 6
	add_theme_stylebox_override("panel", backing)
	var body := VBoxContainer.new()
	add_child(body)
	transcript.bbcode_enabled = false
	transcript.scroll_following = true
	transcript.custom_minimum_size.y = 82
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(transcript)
	var row := HBoxContainer.new()
	body.add_child(row)
	entry.placeholder_text = tr("Message your opponent")
	entry.max_length = ELNetworkDuel.MAX_CHAT_LENGTH
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.text_submitted.connect(_send)
	row.add_child(entry)
	var send := Button.new()
	send.text = tr("Send")
	send.pressed.connect(func(): _send(entry.text))
	row.add_child(send)
	link.chat_posted.connect(_refresh_history)
	_refresh_history(0, "")

func _refresh_history(_side: int, _line: String) -> void:
	transcript.clear()
	for message: Dictionary in _link.chat_history:
		var own: bool = message.side == _link.local_side
		transcript.push_color(Color("d6bb88") if own else Color("a8cdf2"))
		transcript.add_text(speaker(own))
		transcript.pop()
		transcript.add_text("  " + String(message.text) + "\n")
	transcript.scroll_to_line(maxi(0, transcript.get_line_count() - 1))

static func speaker(own: bool) -> String:
	return TranslationServer.translate("You" if own else "Opponent")

func _send(value: String) -> void:
	if _link.send_chat(value): entry.clear()
	entry.grab_focus()
