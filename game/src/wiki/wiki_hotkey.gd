extends Node
## F6 opens the wiki anywhere (F1-F4 belong to the battle camera views). The
## wiki handles its own close keys.
##
## The wiki screen is looked up when F6 is pressed, not named here: an
## autoload is compiled before the first frame, and naming ELWikiScreen
## compiled most of the game's scripts with it (seconds with no window
## updates). The start-up screen (scenes/boot.tscn) loads them in a thread.

const WIKI_SCREEN := "res://src/wiki/wiki_screen.gd"
const BOOT_SCENE := "res://scenes/boot.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if (event as InputEventKey).keycode != KEY_F6: return
	# Still loading: the wiki comes with the rest of the game's scripts.
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == BOOT_SCENE: return
	var wiki: GDScript = load(WIKI_SCREEN)
	if wiki == null or wiki.is_open(): return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return
	get_viewport().set_input_as_handled()
	wiki.open(self)
