extends SceneTree
## Fault-injected Expedition durability checks. Uses real run, duel and view
## transitions with an in-memory persistence sink; never opens the user's save.
## godot --headless --path game --script ../tools/expedition_save_failure_check.gd

const Fixture := preload("expedition_fixture.gd")
const FOLDER := "user://expedition_save_failure_check"
const MIN_CHECKS := 95
var checks := 0
var failures: Array[String] = []
var completed := 0

class FaultRun extends ELExpeditionRun:
	var reject_writes := false
	var rejected_calls: Array[int] = []
	var persist_calls := 0
	var build_calls := 0
	var resolve_calls := 0
	var reject_resolution := false
	var durable := {}

	func persist() -> bool:
		persist_calls += 1
		if reject_writes or persist_calls in rejected_calls:
			return _fail("Injected Expedition checkpoint write failure.")
		durable = snapshot().duplicate(true)
		error = ""
		return true

	func build_battle(fresh := false) -> ELDuel:
		build_calls += 1
		return super.build_battle(fresh)

	func resolve_battle(battle: ELDuel) -> bool:
		resolve_calls += 1
		if reject_resolution: return _fail("Injected Expedition settlement refusal.")
		return super.resolve_battle(battle)

class HeadlessMenu extends ELFrontMenu:
	var displayed := ""
	func show_screen(target: String) -> void:
		displayed = target

class HeadlessView extends "res://src/duel/view.gd":
	var notice_texts: Array[String] = []
	var test_refreshes := 0
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _input(_event: InputEvent) -> void:
		pass
	func _unhandled_input(_event: InputEvent) -> void:
		pass
	func _exit_tree() -> void:
		pass
	func _refresh() -> void:
		test_refreshes += 1
	func _notice(message: String) -> void:
		notice_texts.append(message)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: " + label)

func _run() -> void:
	var source := Fixture.profile_at(FOLDER)
	check(source != null, "Synthetic profile is available without mounted original assets")
	if source != null:
		_live_failure(source)
		_menu_failure(source)
		_close_failure(source)
		_finished_failure(source)
		_settled_failure(source)
		_resolution_failure(source)
		_legacy(source)
		Fixture.clean(FOLDER)
	check(completed == 7, "All seven fault-injection scenarios completed")
	check(checks >= MIN_CHECKS, "Minimum assertion count prevents aborted scenarios passing silently")
	ELRemakeText.release()
	print("EXPEDITION SAVE FAILURE: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _new(source: ELProfile, version := 11) -> Dictionary:
	var run := FaultRun.new()
	check(run.create(source, "ExpeditionFixtureRed", 51826, version), "Version %d creates an isolated run" % version)
	if run.profile == null: return {}
	check(run.choose("relic:amber_seed"), "Version %d selects its boon" % version)
	check(run.choose("study:none"), "Version %d selects Open Road" % version)
	check(run.choose_node(run.available()[0]), "Version %d enters the opening fight" % version)
	var battle := run.build_battle()
	check(battle != null, "Version %d creates a real duel" % version)
	if battle == null: return {}
	check(run.save_battle(battle), "Version %d has an initial durable in-memory checkpoint" % version)
	return {"run": run, "battle": battle}

func _view(source: ELProfile, run: FaultRun, battle: ELDuel) -> HeadlessView:
	# Only front-end presentation is stubbed. Production save handlers, menu
	# departure, retry signal wiring, error panel and overlay guard all run.
	source.tables.CutParts = {}
	var view := HeadlessView.new()
	view.profiles = {"el2": source}
	view.profile = source
	view.demo = false
	view.expedition_run = run
	view._expedition_battle = battle
	view.duel = battle
	view.menu = PanelContainer.new()
	view.add_child(view.menu)
	view.game_console = ELGameConsole.new()
	view.game_console.hide()
	view.add_child(view.game_console)
	view.front_layer = CanvasLayer.new()
	view.add_child(view.front_layer)
	view.front_menu = HeadlessMenu.new()
	view.front_menu.edition = "el2"
	view.front_layer.add_child(view.front_menu)
	view.front_menu.hide()
	root.add_child(view)
	view._open_expedition()
	view._expedition_screen.hide()
	source.tables.CutParts = {"TestMenu": {"Ctrl": ELFrontMenu.SCREENS.el2.main.art}}
	return view

func _change(battle: ELDuel) -> void:
	battle.heroes[0].health -= 1
	battle.random_index(97)

func _finish(battle: ELDuel) -> void:
	battle.heroes[1].health = 0
	battle._check_winner()

func _live_failure(source: ELProfile) -> void:
	var setup := _new(source)
	if setup.is_empty(): return
	var run: FaultRun = setup.run
	var battle: ELDuel = setup.battle
	var view := _view(source, run, battle)
	var durable := run.durable.duplicate(true)
	_change(battle)
	var current := battle.snapshot()
	run.reject_writes = true
	view._save_expedition_battle(battle.get_instance_id())
	check(not view._expedition_save_error.is_empty(), "Failed active save exposes a retryable error")
	check(view._expedition_screen.visible and view._overlay_open(), "Failed active save blocks combat with the Expedition error screen")
	check(not view._human_turn(), "Human actions are disabled while the checkpoint is pending")
	check(view._expedition_battle == battle and battle.snapshot() == current, "Failed active save preserves the exact duel instance and state")
	check(run.durable == durable and run._battle_checkpoint == durable.battle, "Failed write leaves the prior durable checkpoint intact")
	var before := run.snapshot()
	view._expedition_node("1-2-1")
	view._expedition_choice("skip")
	check(run.snapshot() == before, "Room and reward actions cannot advance past a failed battle save")
	view._open_duel_screen()
	check(view.setup_panel == null and view._expedition_battle == battle and view._expedition_screen.visible, "A failed menu transition cannot fall through to a replacement practice duel")
	var builds := run.build_calls
	view._start_expedition_battle()
	check(run.build_calls == builds and view._expedition_battle == battle, "A blocked start cannot rebuild or reseed the live duel")
	view._expedition_screen.save_retried.emit()
	check(view._expedition_screen.visible and battle.snapshot() == current and run.durable == durable, "Failed Retry Save retains the same live state and durable checkpoint")
	run.reject_writes = false
	view._expedition_screen.save_retried.emit()
	check(view._expedition_save_error.is_empty() and not view._expedition_screen.visible, "Successful Retry Save dismisses the checkpoint barrier")
	check(view._expedition_battle == battle and battle.snapshot() == current and run.build_calls == builds, "Successful Retry Save resumes the original duel without reconstruction")
	check(run.durable.battle == current and run._battle_checkpoint == current, "Retry writes the current duel, rather than merely persisting the old checkpoint")
	check(view.test_refreshes > 0 and not view._overlay_open(), "Successful retry refreshes and returns control to combat")
	var calls := run.persist_calls
	view._save_expedition_battle(-1)
	check(run.persist_calls == calls, "An obsolete deferred battle-save signal cannot write another duel")
	view.free()
	completed += 1

func _menu_failure(source: ELProfile) -> void:
	var setup := _new(source)
	if setup.is_empty(): return
	var run: FaultRun = setup.run
	var battle: ELDuel = setup.battle
	var view := _view(source, run, battle)
	_change(battle)
	var current := battle.snapshot()
	run.reject_writes = true
	check(not view._show_front_menu(), "Main Menu refuses departure when the active duel cannot be saved")
	check(view.expedition_run == run and view._expedition_battle == battle and battle.snapshot() == current, "Refused departure retains both run and live duel references")
	check(view._expedition_screen.visible and not view.front_menu.visible, "Failed departure leaves the retry screen visible rather than opening the main menu")
	run.reject_writes = false
	check(view._show_front_menu(), "Main Menu can retry the save and depart after storage recovers")
	check(view.expedition_run == null and view._expedition_battle == null and view.front_menu.visible, "Successful departure releases active references only after a durable save")
	check(run.durable.battle == current, "Menu departure saves the latest health and random state")
	var restored := ELExpeditionRun.new()
	check(restored.restore_snapshot(source, JSON.parse_string(JSON.stringify(run.durable))), "The saved departure checkpoint passes production JSON restore")
	var resumed := restored.build_battle()
	check(resumed != null and resumed.heroes[0].health == battle.heroes[0].health, "Resume returns to the saved damaged duel rather than room-entry life")
	check(resumed != null and resumed.rng_state == battle.rng_state and resumed.heroes[0].hand == battle.heroes[0].hand and resumed.heroes[0].spell_uses == battle.heroes[0].spell_uses, "Version 11 Resume preserves future randomness, current hand and spent charges")
	view.free()
	completed += 1

func _close_failure(source: ELProfile) -> void:
	var setup := _new(source)
	if setup.is_empty(): return
	var run: FaultRun = setup.run
	var battle: ELDuel = setup.battle
	var view := _view(source, run, battle)
	_change(battle)
	var current := battle.snapshot()
	run.reject_writes = true
	view._quit_after_expedition_save()
	check(view._expedition_battle == battle and not view._expedition_save_error.is_empty(), "Desktop Quit is refused while the checkpoint cannot be written")
	var auto_quit := auto_accept_quit
	auto_accept_quit = false
	view._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	auto_accept_quit = auto_quit
	check(view._expedition_battle == battle and battle.snapshot() == current, "Window Close is refused without changing the active duel")
	view._restart_game()
	check(view._expedition_battle == battle and battle.snapshot() == current and view._expedition_screen.visible, "Renderer restart cannot discard an unwritten Expedition action")
	view.free()
	completed += 1

func _finished_failure(source: ELProfile) -> void:
	var setup := _new(source)
	if setup.is_empty(): return
	var run: FaultRun = setup.run
	var battle: ELDuel = setup.battle
	var view := _view(source, run, battle)
	_finish(battle)
	var current := battle.snapshot()
	var gold := run.gold
	run.reject_writes = true
	view._save_expedition_battle(battle.get_instance_id())
	view._finish_expedition_battle()
	check(run.phase == "battle" and run.gold == gold and run.resolve_calls == 0, "A failed finished-duel checkpoint cannot grant or replay rewards")
	check(view._expedition_battle == battle and battle.snapshot() == current, "The unresolved finished duel remains intact while saving is blocked")
	check(not view._show_front_menu() and view._expedition_battle == battle, "Failed menu departure also preserves an unresolved victory")
	run.reject_writes = false
	check(view._show_front_menu(), "A finished duel can be durably parked before its reward is resolved")
	check(run.phase == "battle" and run.resolve_calls == 0 and run.durable.battle == current, "Parking a finished duel does not settle or duplicate victory gold")
	var restored := ELExpeditionRun.new()
	check(restored.restore_snapshot(source, JSON.parse_string(JSON.stringify(run.durable))), "The parked finished-duel checkpoint restores normally")
	var resumed := restored.build_battle()
	check(resumed != null and resumed.phase == ELDuel.Phase.FINISHED, "Resume preserves the already finished result")
	check(resumed != null and restored.resolve_battle(resumed) and restored.gold > gold, "The restored finished duel grants its reward once")
	var rewarded := restored.snapshot()
	check(not restored.resolve_battle(resumed) and restored.snapshot() == rewarded, "The restored result cannot grant the reward twice")
	view.free()
	completed += 1

func _settled_failure(source: ELProfile) -> void:
	var setup := _new(source)
	if setup.is_empty(): return
	var run: FaultRun = setup.run
	var battle: ELDuel = setup.battle
	var view := _view(source, run, battle)
	_finish(battle)
	run.reject_writes = true
	view._save_expedition_battle(battle.get_instance_id())
	run.reject_writes = false
	# Retry's first write parks the finished duel; its second writes the
	# settled reward. Fail only that second write to test the commit boundary.
	run.rejected_calls.append(run.persist_calls + 2)
	view._expedition_screen.save_retried.emit()
	check(run.phase == "reward" and run.resolve_calls == 1, "A saved finished duel resolves exactly once during Retry Save")
	check(view._expedition_battle == null and not view._expedition_save_error.is_empty(), "Failure to save the reward retains the settled run behind a barrier")
	var rewarded := run.snapshot()
	check(not run.durable.has("last_reward") and run.durable.has("battle"), "Failed reward write preserves the prior finished-duel checkpoint")
	run.reject_writes = true
	check(not view._show_front_menu() and view.expedition_run == run, "Main Menu cannot discard an unsettled-to-disk reward")
	check(run.snapshot() == rewarded and run.resolve_calls == 1, "Failed departure does not resolve or add reward a second time")
	run.reject_writes = false
	view._expedition_screen.save_retried.emit()
	check(view._expedition_save_error.is_empty() and run.durable == rewarded, "Retry writes the already settled reward without replaying combat")
	check(run.resolve_calls == 1 and view._expedition_screen.visible, "Successful reward retry returns to the reward screen once")
	view._finish_expedition_battle()
	check(run.resolve_calls == 1 and run.snapshot() == rewarded, "A stale finish callback cannot replay an already settled reward")
	view.free()
	completed += 1

func _resolution_failure(source: ELProfile) -> void:
	var setup := _new(source)
	if setup.is_empty(): return
	var run: FaultRun = setup.run
	var battle: ELDuel = setup.battle
	var view := _view(source, run, battle)
	_finish(battle)
	var current := battle.snapshot()
	run.reject_resolution = true
	view._finish_expedition_battle()
	check(view._expedition_battle == battle and battle.snapshot() == current, "A refused result settlement retains the exact finished duel")
	check(run.phase == "battle" and not view._expedition_save_error.is_empty(), "Settlement refusal blocks progression instead of dropping the result")
	run.reject_resolution = false
	view._expedition_screen.save_retried.emit()
	check(run.phase == "reward" and view._expedition_battle == null and view._expedition_save_error.is_empty(), "Retry can save and settle the retained result after the refusal clears")
	check(run.durable == run.snapshot(), "Recovered settlement is durable before further choices")
	view.free()
	completed += 1

func _legacy(source: ELProfile) -> void:
	var setup := _new(source, 10)
	if setup.is_empty(): return
	var run: FaultRun = setup.run
	var battle: ELDuel = setup.battle
	var view := _view(source, run, battle)
	_change(battle)
	run.reject_writes = true
	view._save_expedition_battle(battle.get_instance_id())
	check(view._expedition_save_error.is_empty() and not view.notice_texts.is_empty(), "Version 10 retains its original notice-only active save failure")
	check(not view._expedition_screen.visible, "Version 10 does not acquire the new pause behavior")
	var calls := run.persist_calls
	check(view._save_expedition_before_exit() and run.persist_calls == calls, "The new departure guard does not change old-rule persistence")
	check(view._show_front_menu() and view.expedition_run == null, "Version 10 retains its original menu departure behavior")
	view.free()
	completed += 1
