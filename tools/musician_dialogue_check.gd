extends SceneTree
## Checks the Musician's warnings using the original Vitals chapter and map figure.
## godot --headless --path game --script ../tools/musician_dialogue_check.gd

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if not paths is Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el2", str(paths.el2)):
		_check(false, "the second game mounts: " + profile.error)
		quit(1)
		return
	var settings := ELSettings.new()
	settings.use_edition("el2")
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, {"file_name": "e2mission13"}, settings, 1)
	_check(built, "#213: the Vitals chapter builds: " + view.error)
	if built:
		view.set_process(false)
		if view._mission_fade != null: await view._mission_fade.tree_exited
		_check(view.state.step(), "the chapter initializes its quest state")
		view.state.commands.clear()
		ELFog.reveal_for_console(view.state, view.state.current_player, true)
		view.world.sync_fog()
		var dragon_id := int(view.state.vm.globals.ID_GREEN_DRAGON)
		var dragon: ELModel = view.world.actors.get(dragon_id)
		_check(dragon != null and dragon.template == "ad414", "the Musician uses the original adventure figure")
		if dragon != null:
			_warn(view, dragon_id, Vector2i(1, 1), "MV_M13_S08_P02_MV_DRAGON_13")
			_warn(view, dragon_id, Vector2i(-1, -1), "MV_M13_S08_P03_MV_DRAGON_13")
	view.queue_free()
	await process_frame
	print("MUSICIAN DIALOGUE: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

func _warn(view: ELAdventureView, dragon_id: int, approach: Vector2i, line: String) -> void:
	var state := view.state
	var director := view.director
	var dragon: ELModel = view.world.actors[dragon_id]
	var where := state.object(dragon_id)
	state._native([float(state.main_hero), float(int(where.x) + approach.x), float(int(where.y) + approach.y)], "ExJumpToPos")
	director.use_object(state.main_hero, dragon_id)
	_check(director.encounter == null, "the Musician warns the hero before battle")
	var facing := atan2(float(approach.x), -float(approach.y))
	_check(is_zero_approx(angle_difference(dragon.rotation.y, facing)), "the Musician turns toward the approaching hero")
	director.advance(0.0)
	_check(director.dialogue.get("text_id", "") == line, "the authored warning is queued")
	if director.dialogue.is_empty(): return
	_check(view.second_dialogue.visible == (dragon.clip == "uattack"), "the animation is synchronized with the dialogue presentation")
	for i in 180:
		if view.second_dialogue.visible: break
		view._process(1.0 / 30.0)
	_check(view.second_dialogue.visible and dragon.clip == "uattack", "the dialogue starts the model's original Instant clip")
	if dragon.clip == "uattack":
		var jaw: Node3D = dragon.parts.jaw
		var rest := jaw.transform
		dragon._process(0.8)
		_check(dragon.frame > 0 and jaw.transform != rest, "the Musician's jaw moves as it speaks")
		dragon._process(dragon.clip_seconds("uattack"))
		_check(dragon.clip == "cidle", "the Musician returns to its idle after the clip")
	director.acknowledge()
	director.advance(0.0)
