extends SceneTree
## Saves frames of the Expedition screens on the installed second game's art
## (ELMenuKit), for visual checks. Not headless: it renders. Battles are
## settled as wins without playing them. No checkpoint is written.
##
##   godot --path game --resolution 1280x720 --script ../tools/expedition_capture.gd -- --shots=<folder> [--el2=<folder>] [--language=en|ru]

const SHOT_SEED := 15000

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

var _folder := ""

func _shot(name: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var path := _folder.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)

func _first_enabled(run: ELExpeditionRun) -> Dictionary:
	for option: Dictionary in run.choices():
		if not bool(option.get("disabled", false)): return option
	return {}

func _path_to_kind(run: ELExpeditionRun, kind: String, event_index := -1) -> Array[String]:
	var paths := {}
	for row: Array in run.route():
		for node: Dictionary in row:
			if node.floor == 1: paths[node.id] = [node.id]
			if not paths.has(node.id): continue
			if node.kind == kind and (event_index < 0 or int(node.get("event", -1)) == event_index):
				var result: Array[String] = []
				result.assign(paths[node.id])
				return result
			for next: String in node.next:
				if not paths.has(next): paths[next] = paths[node.id] + [next]
	return []

func _win(run: ELExpeditionRun) -> bool:
	if run.phase != "battle": return false
	var duel := run.build_battle()
	if duel == null: return false
	duel.phase = ELDuel.Phase.FINISHED
	duel.winner = 0
	duel.heroes[0].health = mini(run.max_health, maxi(1, run.health))
	duel.heroes[1].health = 0
	return run.resolve_battle(duel)

func _settle_room(run: ELExpeditionRun) -> bool:
	for attempt in 8:
		if run.phase == "map": return true
		if run.phase == "battle":
			if not _win(run): return false
			continue
		var selected := _first_enabled(run)
		for option: Dictionary in run.choices():
			if option.id in ["leave", "skip", "skip_relic", "heal"] and not bool(option.get("disabled", false)):
				selected = option
				break
		if selected.is_empty() or not run.choose(selected.id): return false
	return run.phase == "map"

func _enter_kind(run: ELExpeditionRun, kind: String, event_index := -1) -> bool:
	while run.phase in ["boon", "discipline"]:
		if not run.choose(_first_enabled(run).id): return false
	var path := _path_to_kind(run, kind, event_index)
	if path.is_empty(): return false
	for id: String in path:
		if not run.choose_node(id): return false
		if id == path.back(): return true
		if not _settle_room(run): return false
	return false

func _new(profile: ELProfile, preset: String, seed_value: int) -> ELExpeditionRun:
	var run := ELExpeditionRun.new()
	if not run.create(profile, preset, seed_value):
		printerr("create: ", run.error)
		return null
	return run

## A route that reaches the wanted room in one of the three acts.
func _reach(profile: ELProfile, preset: String, kind: String, event_index := -1) -> ELExpeditionRun:
	for offset in 60:
		var run := _new(profile, preset, SHOT_SEED + offset)
		if run == null: return null
		for chapter in 3:
			if _enter_kind(run, kind, event_index): return run
			if chapter == 2 or not _enter_kind(run, "boss") or not _win(run) or not _settle_room(run): break
	return null

func _run() -> void:
	_folder = _arg("shots", "user://expedition_shots")
	DirAccess.make_dir_recursive_absolute(_folder)
	var language := _arg("language", "en")
	OS.set_environment("DEMIURGES_LANGUAGE", language)
	var profile := _profile()
	if profile == null:
		printerr("Etherlords II is required: pass --el2=<folder>")
		quit(2)
		return
	ELRemakeText.use(profile)
	var only := _arg("only", "")
	var screen := ELExpeditionScreen.new()
	root.add_child(screen)
	screen.build(profile)
	var preset: String = ELExpeditionRun.starters(profile)[0].id
	var shots := {
		"start": func(): screen.show_run(null),
		"boon": func(): screen.show_run(_new(profile, preset, SHOT_SEED)),
		"map": func():
			var run := _new(profile, preset, SHOT_SEED)
			while run.phase in ["boon", "discipline"]: run.choose(_first_enabled(run).id)
			screen.show_run(run),
		"deck": func():
			var run := _new(profile, preset, SHOT_SEED)
			while run.phase in ["boon", "discipline"]: run.choose(_first_enabled(run).id)
			run.field_artifact = "mndp"
			run.field_charges = 1
			run.artifact_project = "unsm"
			screen.show_run(run)
			screen._show_deck(true),
		"scout": func():
			var run := _new(profile, preset, SHOT_SEED)
			while run.phase in ["boon", "discipline"]: run.choose(_first_enabled(run).id)
			screen.show_run(run)
			screen._show_scout(1),
		"reward": func():
			var run := _reach(profile, preset, "fight")
			if run != null:
				_win(run)
				screen.show_run(run),
		"shop": func(): screen.show_run(_reach(profile, preset, "shop")),
		"camp": func(): screen.show_run(_reach(profile, preset, "rest")),
		"elite": func():
			var run := _reach(profile, preset, "elite")
			if run != null:
				_win(run)
				screen.show_run(run),
		"constructor": func():
			var run := _reach(profile, preset, "event", 18)
			if run != null:
				run.field_artifact = "mndp"
				run.field_charges = 1
				screen.show_run(run),
		"event": func(): screen.show_run(_reach(profile, preset, "event")),
	}
	for name: String in shots:
		if not only.is_empty() and not name in only.split(","): continue
		shots[name].call()
		await _shot("expedition-" + name + "-" + language)
		if name == "deck":
			screen._scroll.scroll_vertical = 100000
			await _shot("expedition-deck-end-" + language)
	ELRemakeText.release()
	quit(0)
