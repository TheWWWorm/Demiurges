extends SceneTree
## Captures the developer console in a battle with card suggestions open,
## after adding cards by name, to check the add spell completion's layout.
##
##   godot --path game --resolution 1280x720 --script ../tools/console_capture.gd -- --profile=el1 --out=<folder> [--wait=4]
##
## Saves <folder>/console-suggestions.png (a Russian part of a name typed
## after a first card and a count) and <folder>/console-added.png (the reply
## of a line adding several cards). Settings and saves are never written.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var wait := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--wait="): wait = float(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out)
	var view = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await create_timer(wait).timeout
	# The battle is played from here on as a local one, so the console's
	# battle commands are offered.
	view.demo = false
	var console: ELGameConsole = view.game_console
	console._open()
	console._submit(ELGameConsole.UNLOCK)
	var russian: String = ELCardNames.NAMES.ORSH[1]
	console._submit("add spell %s x2, zap, %s" % [ELCardNames.NAMES.FRBL[0].to_lower(), russian.to_upper()])
	console.entry.text = "add creature %s x2, 3 %s" % [ELCardNames.NAMES.ORSH[0].to_lower(), russian.left(3).to_lower()]
	console.entry.caret_column = console.entry.text.length()
	console._complete()
	await _save(out.path_join("console-suggestions.png"))
	console._suggestions.hide()
	console.entry.text = ""
	await _save(out.path_join("console-added.png"))
	print(console._text)
	quit(0)

func _save(path: String) -> void:
	for i in 3: await process_frame
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("CAPTURED %s %s" % [path, image.get_size()])
