extends SceneTree
## Captures the battle panel at a chosen window size and battle interface
## size, to check the panel's layout on phones and odd screens.
##
##   godot --path game --resolution 2000x905 --script ../tools/battle_hud_capture.gd -- --profile=el1 --out=<png> [--interface=3] [--wait=4]
##
## --interface is the "battle_interface" setting (0 automatic, 1-4 the sizes
## 1, 1.5, 2 and 3); it is set for this run only, settings are never written.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var choice := -1
	var wait := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--interface="): choice = int(arg.get_slice("=", 1))
		elif arg.begins_with("--wait="): wait = float(arg.get_slice("=", 1))
	var view = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	if choice >= 0: view.settings.values["battle_interface"] = choice
	await create_timer(wait).timeout
	view._layout_hud()
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(out)
	print("CAPTURED %s %s" % [out, image.get_size()])
	quit(0)
