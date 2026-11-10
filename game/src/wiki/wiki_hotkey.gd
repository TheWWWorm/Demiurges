extends Node
## Shift+F1 always opens the wiki. Plain F1 also opens it outside automatic
## battle camera mode. The wiki handles its own close keys.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if (event as InputEventKey).keycode != KEY_F1 or ELWikiScreen.is_open(): return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	var scene := get_tree().current_scene
	if not event.shift_pressed and scene != null and scene.has_method("battle_camera_presets_active") and scene.battle_camera_presets_active(): return
	get_viewport().set_input_as_handled()
	ELWikiScreen.open(self)
