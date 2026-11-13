extends SceneTree
## Opens a second-game autochess match with a filled army, artifacts and the
## creature card shown, and saves frames of it for visual checks. Not
## headless: it renders.
##
##   godot --path game --resolution 1600x900 --script ../tools/autochess_capture.gd -- --shots=<folder> [--el2=<folder>]
##
## planning.png: the board between battles with the first fielded creature's
## card; items.png: the same without the card (the artifacts list);
## card.png: the card with the most ability lines;
## fight.png: a moment of the battle.

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.split("=", true, 1)[1]
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _profile() -> ELProfile:
	var folder := _arg("el2", "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get("el2", ""))
	var profile := ELProfile.new()
	if folder.is_empty() or not profile.mount("el2", folder): return null
	return profile

func _shot(folder: String, name: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name))
	print("saved ", folder.path_join(name))

func _run() -> void:
	var folder := _arg("shots", "user://autochess_shots")
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := _profile()
	if profile == null:
		printerr("Etherlords II is required: pass --el2=<folder>")
		quit(2)
		return
	var screen := ELAutochessScreen.new()
	root.add_child(screen)
	screen.build(profile, ELSettings.new().values)
	var game := ELAutochessMatch.new()
	game.auto_save = false
	var seats: Array[String] = ["human"]
	for player in ELAutochessRules.PLAYER_COUNT - 1: seats.append("computer")
	game.begin(profile, 777, ELAutochessCharacters.choices(profile)[0], seats)
	screen.show_match(game, 0, null)
	for i in 5: await process_frame
	var own := screen.company()
	own.ether = 200
	own.training = 40
	# Buy until the army is full, then give the fielded creatures artifacts.
	for pass_index in 6:
		for index in own.shop.size(): own.buy(index)
		own.refresh()
	own.arrange()
	var kinds := ELAutochessArtifacts.RULES.keys()
	var fielded := own.army.filter(func(e: Dictionary) -> bool: return e.deployed)
	for index in mini(fielded.size(), ELAutochessArtifacts.MAX_ITEMS):
		own.items.append({"uid": own.next_item_uid, "kind": String(kinds[(index * 5) % kinds.size()]), "unit_uid": 0})
		own.next_item_uid += 1
	for index in mini(fielded.size(), own.items.size() - 2):
		own.equip_item(int(own.items[index].uid), int(fielded[index].uid))
	game.changed.emit()
	screen._refresh()
	for i in 90: await process_frame
	if not fielded.is_empty():
		screen._select({"kind": "field", "uid": int(fielded[0].uid)})
		screen._refresh()
	for i in 30: await process_frame
	await _shot(folder, "planning.png")
	screen._select({})
	screen._refresh()
	for i in 10: await process_frame
	await _shot(folder, "items.png")
	# The longest card: the line whose first form carries the most flags.
	var longest := 0
	var most := -1
	for line in ELAutochessRules.FAMILIES.size():
		var count := ELAutochessRules.flags(profile, ELAutochessRules.form(line, 0)).size()
		if count > most:
			most = count
			longest = line
	screen._inspect(longest, 0, {})
	for i in 10: await process_frame
	await _shot(folder, "card.png")
	screen._hide_rail()
	game.start_fight()
	for i in 240: await process_frame
	await _shot(folder, "fight.png")
	quit(0)
