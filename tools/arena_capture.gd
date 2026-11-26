extends SceneTree
## Plays the Draft Arena's way in from the front menu with a saved run that
## has just won a match, counting the clicks from the menu button to the next
## battle, and saves a frame of each screen. Not headless: it renders. The
## player's own Arena save is put back afterwards; settings may change.
##
##   godot --path game --resolution 1440x900 --script ../tools/arena_capture.gd -- --shots=<folder> --no-movies

var view: Node
var shots := ""
var clicks := 0

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count: await process_frame

func shot(name: String) -> void:
	if shots.is_empty(): return
	await RenderingServer.frame_post_draw
	var path := shots.path_join(name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _button(name: String) -> BaseButton:
	var screen: Control = view.get("_arena_screen")
	if screen == null or not screen.is_visible_in_tree(): return null
	var button := screen.find_child(name, true, false) as BaseButton
	return button if button != null and button.is_visible_in_tree() and not button.disabled else null

func _click(button: BaseButton, what: String) -> void:
	clicks += 1
	print("CLICK %d: %s" % [clicks, what])
	button.pressed.emit()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	if not shots.is_empty(): DirAccess.make_dir_recursive_absolute(shots)
	var kept := FileAccess.get_file_as_bytes(ELArenaRun.SAVE_PATH) if ELArenaRun.has_save() else PackedByteArray()
	view = load("res://scenes/duel.tscn").instantiate()
	view.launch_as_game = true
	root.add_child(view)
	var waited := 0
	while (view.front_menu == null or not view.front_menu.is_visible_in_tree()) and waited < 600:
		await process_frame
		waited += 1
	if view.front_menu == null or not view.profiles.has("el2"):
		print("ARENA CAPTURE: the menu did not open with Etherlords II mounted")
		quit(1)
		return
	view.front_menu._choice._chosen("el2")
	await frames(5)
	# A saved run that has just won its first match.
	var run := ELArenaRun.new()
	run.create(view.profiles.el2, 20261126)
	run.auto_save = false
	run.choose_hero(run.hero_choices[0])
	while run.phase in ["spec", "artifact", "skill"]: run.choose_loadout(0)
	while run.phase == "draft": run.pick(ELArenaDraftBot.choose(run.draft))
	var duel := run.build_battle()
	duel.heroes[1].health = 0
	duel._check_winner()
	run.resolve_battle(duel)
	run.persist()
	view.arena_run = null
	await shot("arena-0-menu")
	var entry: BaseButton = view.front_menu.find_child("DraftArena", true, false)
	_click(entry, "Draft Arena on the front menu")
	await frames(30)
	if _button("ArenaResume") != null:
		await shot("arena-1-landing")
		_click(_button("ArenaResume"), "Resume saved run")
		await frames(30)
	await shot("arena-2-result")
	if _button("ArenaContinue") != null: _click(_button("ArenaContinue"), "the result's button")
	await frames(30)
	if _button("ArenaBattle") != null:
		await shot("arena-3-lobby")
		_click(_button("ArenaBattle"), "Enter the Arena")
	for second in [2, 6]:
		await frames(60 * (second if second == 2 else 4))
		await shot("arena-4-battle-%ds" % second)
	var arena_battle: ELDuel = view.get("_arena_battle")
	print("ARENA CAPTURE: %d clicks from the menu to the next battle; battle %s" % [clicks, "running" if arena_battle != null else "not started"])
	if arena_battle != null:
		for side in 2:
			var hero: Dictionary = arena_battle.heroes[side]
			print("side %d: %s, specialization %s, %d artifact(s), skills %s" % [side, arena_battle.setup.players[side].hero, hero.get("spec", "NONE"), Array(hero.get("artifacts", [])).size(), hero.get("skills", {})])
	view.set("_arena_battle", null)
	view.set("arena_run", null)
	if kept.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(ELArenaRun.SAVE_PATH))
	else:
		var file := FileAccess.open(ELArenaRun.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(kept)
		file.close()
	quit(0)
