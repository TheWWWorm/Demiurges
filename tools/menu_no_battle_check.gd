extends SceneTree
## The launched game opens its front end with no battle behind it, and every
## way out of the menu still works from there: a game switch, Options, a Duel
## mode match, Draft Arena, Expedition, Autochess, Puzzles, the combat
## tutorial, the network lobby, a campaign map and back. Starts the scene as
## the launched game does (launch_as_game). Needs both games mounted; may
## overwrite this computer's settings. Watch the log for SCRIPT ERROR too:
## godot --path game --resolution 1280x720 --script ../tools/menu_no_battle_check.gd -- --no-movies
## Add --shots=<folder> for a picture of each mode as it opens.

var view: Node
var failures: Array[String] = []
var checks := 0
var shots := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures.append(what)
		print("FAIL: " + what)

func frames(count: int) -> void:
	for i in count: await process_frame

func shot(name: String) -> void:
	if shots.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	view = load("res://scenes/duel.tscn").instantiate()
	view.launch_as_game = true
	root.add_child(view)
	var waited := 0
	while (view.front_menu == null or not view.front_menu.is_visible_in_tree()) and waited < 600:
		await process_frame
		waited += 1
	if view.front_menu == null or not view.profiles.has("el1") or not view.profiles.has("el2"):
		print("MENU NO BATTLE: the menu did not open with both games mounted")
		quit(1)
		return
	var menu: ELFrontMenu = view.front_menu
	await frames(10)
	check(view.duel == null and view.stage == null, "no battle stands behind the menu at start")
	check(view.profile != null and view.profile.id == menu.edition, "the game in use is the menu's")
	check(not view.hud_root.visible, "the battle panel is hidden behind the menu")
	await shot("menu")

	for target: String in ["el2", "el1", "el2"]:
		menu._choice._chosen(target)
		await frames(3)
		check(view.duel == null and view.profile.id == target and view.settings.edition == target, "switching to %s keeps no battle and uses its settings" % target)

	menu.show_screen("options")
	await frames(5)
	menu.options_closed.emit(true, "")
	await frames(5)
	menu.show_screen("main")
	check(view.duel == null, "Options from the menu build no battle")

	# A Duel mode match plays its first round, and the menu after it stands
	# alone again.
	for edition: String in ["el1", "el2"]:
		menu._choice._chosen(edition)
		await frames(3)
		menu.show_screen("duel")
		await frames(3)
		menu.duel_ui.start()
		await frames(10)
		await shot("duel_" + edition)
		check(view.duel != null and view.profile.id == edition and view.hud_root.visible and not menu.is_visible_in_tree(), "%s: a Duel mode match opens its battle" % edition)
		view._show_front_menu()
		await frames(3)
		menu._choice._chosen("el1" if edition == "el2" else "el2")
		await frames(3)
		check(view.duel == null and not view.hud_root.visible, "%s: switching games after a battle puts it away" % edition)

	await _mode("Draft Arena", view._open_arena)
	await _mode("Expedition", view._open_expedition)
	await _mode("Autochess", view._open_autochess, func(): view._close_autochess())
	await _mode("Puzzles", view._open_puzzles)
	await _mode("network lobby", func(): view._open_network_lobby(), func(): view._close_network_lobby())

	menu._choice._chosen("el2")
	await frames(3)
	view._begin_combat_tutorial()
	await frames(20)
	check(view.duel != null and view.combat_tutorial != null, "the combat tutorial opens its battle")
	view._leave_combat_tutorial()
	await frames(5)
	if not menu.is_visible_in_tree(): view._show_front_menu()
	await frames(3)
	check(menu.is_visible_in_tree(), "the menu follows the combat tutorial")

	# The second game's adventure tutorial map, and back to the menu.
	view._show_front_menu()
	await frames(3)
	menu.start_tutorial()
	waited = 0
	while view.campaign_view == null and waited < 900:
		await process_frame
		waited += 1
	await frames(30)
	await shot("map")
	check(view.campaign_view != null and view.duel == null, "a campaign map opens with no battle kept behind it")
	if view.campaign_view != null:
		await view._leave_campaign()
		await frames(5)
	check(view.campaign_view == null and menu.is_visible_in_tree() and view.duel == null, "leaving the map returns to the menu with no battle")

	print("MENU NO BATTLE: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

## Opens a menu mode, lets it run, returns to the menu: no battle is left.
func _mode(what: String, open: Callable, close := Callable()) -> void:
	view._show_front_menu()
	await frames(3)
	open.call()
	await frames(20)
	await shot(what.to_snake_case())
	if close.is_valid(): close.call()
	await frames(3)
	if not view.front_menu.is_visible_in_tree(): view._show_front_menu()
	await frames(5)
	check(view.front_menu.is_visible_in_tree(), "%s: the menu comes back" % what)
	check(view.duel == null or view.duel == view._arena_battle or view.duel == view._expedition_battle, "%s: no practice battle is built" % what)
