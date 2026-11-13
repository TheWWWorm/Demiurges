extends SceneTree
## Headless check of the battle panel's size choice and of the figures' hurt
## and death sounds:
## - each battle interface size (and Automatic) gives a clean scale for common
##   screens, never too big for the panel to fit, never too small to tap on a
##   touch screen; whole sizes are drawn with nearest sampling;
## - the card rail keeps the original six slots at every size; the extra
##   width is left as an empty gap;
## - the setting is stored with the shared remake settings and kept in range;
## - a lethal hit plays only the figure's death sound, a non-lethal hit its
##   hurt sound (in the battle audio and through the battle view).
##
##   godot --headless --path game --script ../tools/battle_hud_check.gd
##
## Needs no game files. Settings are never written.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_sizes()
	_slots()
	_setting()
	await _sounds()
	await _view_sounds()
	print("BATTLE HUD: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _sizes() -> void:
	var scale := ELHudFrame.interface_scale
	# Automatic: the sharpest listed size near the former panel size.
	var expected := {Vector2(1280, 720): 1.0, Vector2(1366, 768): 1.0, Vector2(1600, 900): 1.5, Vector2(1920, 1080): 1.5,
		Vector2(1920, 1200): 1.5, Vector2(2560, 1440): 2.0, Vector2(3440, 1440): 2.0, Vector2(3840, 2160): 3.0, Vector2(1024, 768): 1.0, Vector2(800, 600): 1.0}
	for screen: Vector2 in expected:
		check(is_equal_approx(scale.call(0, screen), expected[screen]), "automatic size on %dx%d is %s×" % [screen.x, screen.y, expected[screen]])
	# A chosen size, unless the panel would no longer fit across.
	for choice in ELHudFrame.SIZES.size():
		var wanted: float = ELHudFrame.SIZES[choice]
		for screen: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440)]:
			var got: float = scale.call(choice + 1, screen)
			var fits := screen.x / wanted >= ELHudFrame.NARROWEST
			check(is_equal_approx(got, wanted) if fits else (got < wanted and screen.x / got >= ELHudFrame.NARROWEST), "size %s× on %dx%d gives %s×" % [wanted, screen.x, screen.y, got])
	# Touch screens: a card slot at least about 7 mm wide.
	var phone := Vector2(2400, 1080)
	for dpi: float in [160.0, 400.0, 480.0]:
		var got: float = scale.call(1, phone, dpi)
		var slot_mm := ELListLook.PITCH * got / dpi * 25.4
		check(slot_mm >= ELHudFrame.TOUCH_SLOT_MM * 0.95 and phone.x / got >= ELHudFrame.NARROWEST, "small size on a %d dpi phone keeps %.1f mm slots (%s×)" % [dpi, slot_mm, got])
	check(ELHudFrame.interface_filter(1.0) == CanvasItem.TEXTURE_FILTER_NEAREST and ELHudFrame.interface_filter(2.0) == CanvasItem.TEXTURE_FILTER_NEAREST
		and ELHudFrame.interface_filter(3.0) == CanvasItem.TEXTURE_FILTER_NEAREST, "whole sizes use nearest sampling")
	check(ELHudFrame.interface_filter(1.5) == CanvasItem.TEXTURE_FILTER_LINEAR, "1.5× uses linear filtering")

func _slots() -> void:
	for screen: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440)]:
		for choice in range(ELHudFrame.SIZES.size(), 0, -1):
			var size := ELHudFrame.interface_scale(choice, screen)
			var width := ceilf(screen.x / size)
			check(ELHudFrame.rail_slots(null, width) == 6, "%dx%d at %s× shows the original six slots" % [screen.x, screen.y, size])
			check(is_equal_approx(ELHudFrame.rail_trim(null, width), maxf(0.0, width - 800.0)), "%dx%d at %s× leaves the extra width as a gap" % [screen.x, screen.y, size])
	check(ELHudFrame.rail_slots(null, 800) == 6 and is_zero_approx(ELHudFrame.rail_trim(null, 800)), "the 800 panel's rail holds its original six slots with no gap")

func _setting() -> void:
	var settings := ELSettings.new()
	check(int(settings.values.get("battle_interface", -1)) == 0 and ELSettings.SHARED.has("battle_interface"), "the size is a shared remake setting, Automatic by default")
	check(ELSettings._clean("battle_interface", 9, 0) == 4 and ELSettings._clean("battle_interface", -3, 0) == 0 and ELSettings._clean("battle_interface", "x", 0) == 0, "stored values are kept in range")

## A test figure with its own sound folder.
func _figure(directory: String) -> ELModel:
	var model := ELModel.new()
	model.set_meta("sound_directory", directory)
	return model

func _audio() -> ELBattleAudio:
	var audio := ELBattleAudio.new()
	root.add_child(audio)
	# Paused: the requests are recorded, nothing is decoded or heard.
	audio.paused = true
	return audio

func _sounds() -> void:
	var audio := _audio()
	var rat := _figure("Rat")
	var wolf := _figure("Wolf")
	audio.hurt(rat)
	audio.unit(rat, "death")
	audio.hurt(wolf)
	await process_frame
	await process_frame
	check(audio.requested.has("Creatures/Rat/death.wav") and not audio.requested.has("Creatures/Rat/hit.wav"), "a lethal hit plays only the death sound")
	check(audio.requested.has("Creatures/Wolf/hit.wav") and not audio.requested.has("Creatures/Wolf/death.wav"), "a hit that does not kill plays the hurt sound")
	audio.requested.clear()
	audio.hurt(rat)
	audio.hurt(rat)
	await process_frame
	check(audio.requested.count("Creatures/Rat/hit.wav") == 1, "two blows in one frame play one hurt sound")
	audio.queue_free()
	rat.free()
	wolf.free()

## The battle view's own hit presentation (_show_hit): damage then death of
## the same creature in one frame, as the rules report a lethal blow.
func _view_sounds() -> void:
	var view: Node = load("res://src/duel/view.gd").new()
	var audio := _audio()
	view.battle_audio = audio
	var rat := _figure("Rat")
	var wolf := _figure("Wolf")
	view.models = {5: rat, 6: wolf}
	view.labels = {5: Label3D.new(), 6: Label3D.new()}
	view._show_hit({"kind": "damage", "target": 5, "amount": 3})
	view._show_hit({"kind": "death", "target": 5})
	view._show_hit({"kind": "damage", "target": 6, "amount": 1})
	await process_frame
	await process_frame
	check(audio.requested == ["Creatures/Rat/death.wav", "Creatures/Wolf/hit.wav"], "the battle view plays the death alone for a lethal blow and the hurt sound for the other (%s)" % [audio.requested])
	audio.queue_free()
	if is_instance_valid(wolf): wolf.free()
	for label: Node in view.labels.values(): label.free()
	view.free()
	await process_frame
