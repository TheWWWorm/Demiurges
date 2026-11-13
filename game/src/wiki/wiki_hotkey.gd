extends Node
## F6 opens the wiki anywhere (F1-F4 belong to the battle camera views). The
## wiki handles its own close keys.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if (event as InputEventKey).keycode != KEY_F6 or ELWikiScreen.is_open(): return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return
	get_viewport().set_input_as_handled()
	ELWikiScreen.open(self)
