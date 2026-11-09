extends Node
## Autoload "WikiHotkey": F1 opens the in-game wiki (ELWikiScreen) from any
## screen, the battle and the map included. While the wiki is open it takes
## F1 and Esc itself to close.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if (event as InputEventKey).keycode != KEY_F1 or ELWikiScreen.is_open(): return
	get_viewport().set_input_as_handled()
	ELWikiScreen.open(self)
