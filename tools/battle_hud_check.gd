extends SceneTree
## Headless check of the battle panel's size choice and of the figures' hurt
## and death sounds:
## - each battle interface size (and Automatic) gives a clean scale for common
##   screens, never too big for the panel to fit, never too small to tap on a
##   touch screen; whole sizes are drawn with nearest sampling;
## - the card rail keeps the original six slots at every size; the extra
##   width, from the rail's arrow housing to the caption, is the readout
##   panel's (ELCombatGapPanel), whose spellbook icons fill a rail item's
##   height on a 16:9 screen and whose slide is a stored setting;
## - #164 (with the game's files): at every common screen and size the extra
##   width is either a readout panel wide enough for its arrows and a
##   readout, or none, the phase caption's oval widened by it instead of an
##   empty strip;
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
	_gap()
	_narrow_gaps()
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

func _gap() -> void:
	# 1920x1080 at the automatic 1.5: a 1280 panel, 256 past the wide layout.
	var gap := ELHudFrame.gap_rect(null, Vector2(1280, 720))
	check(gap == Rect2(ELHudFrame.RAIL_CLOSE + 480.0 - 480.0, 720.0 - 61.0, 480.0, 61.0), "a 1280 panel without the wide layout leaves 480 px from the rail's end")
	check(is_zero_approx(ELHudFrame.gap_rect(null, Vector2(800, 600)).size.x), "the 800 panel has no extra width")
	var panel := ELCombatGapPanel.new()
	panel.size = Vector2(256, 61)
	var room := panel.area()
	var fit := ELCombatGapPanel.cell_size(16, room.size, 2)
	check(fit.x == 24 and fit.y == 2 and is_equal_approx(room.size.y, ELListLook.ITEM_SIZE), "sixteen spellbook slots in a 256 px gap: two rows of 24 px icons, a rail item high (%s in %s)" % [fit, room.size])
	check(ELCombatGapPanel.cell_size(16, Vector2(641, 50), 2).y == 1, "a wide gap shows the spellbook in one row")
	check(panel.roomy() and ELCombatGapPanel.MIN_WIDTH > ELCombatGapPanel.LEFT_END.size.x + ELCombatGapPanel.RIGHT_END.size.x, "256 px holds the arrows and a readout")
	panel.size.x = 43
	check(not panel.roomy(), "a 43 px gap shows the plain strip")
	panel.size.x = 256
	panel.readouts = false
	check(not panel.roomy(), "with the readouts setting off a wide gap shows the plain strip")
	panel.free()
	var settings := ELSettings.new()
	check(int(settings.values.get("battle_gap", -1)) == 0 and ELSettings.SHARED.has("battle_gap"), "the slide is a shared remake setting, the spellbook by default")
	check(ELSettings._clean("battle_gap", 9, 0) == ELCombatGapPanel.SLIDES.size() - 1 and ELSettings._clean("battle_gap", -3, 0) == 0, "a stored slide is kept in range")
	check(bool(settings.values.get("battle_readouts", false)) and ELSettings.SHARED.has("battle_readouts"), "the readouts are a shared remake setting, on by default")

func _narrow_gaps() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files for the narrow gaps" % edition)
			continue
		var profile := ELProfile.new()
		if not profile.mount(edition, str(paths[edition])): continue
		var strips: Array[String] = []
		var widened: Array[String] = []
		var narrow_800: Array[String] = []
		for screen: Vector2 in [Vector2(1024, 768), Vector2(1152, 864), Vector2(1280, 720), Vector2(1280, 800), Vector2(1280, 1024), Vector2(1360, 768), Vector2(1366, 768),
				Vector2(1440, 900), Vector2(1536, 864), Vector2(1600, 900), Vector2(1600, 1200), Vector2(1680, 1050), Vector2(1920, 1080), Vector2(1920, 1200), Vector2(2048, 1152),
				Vector2(2560, 1080), Vector2(2560, 1440), Vector2(2560, 1600), Vector2(3440, 1440), Vector2(3840, 2160)]:
			for choice in ELHudFrame.SIZES.size() + 1:
				var width := ceilf(screen.x / ELHudFrame.interface_scale(choice, screen))
				var gap := ELHudFrame.gap_rect(profile, Vector2(width, 600))
				var stretch := ELHudFrame.caption_stretch(profile, width)
				var name := "%dx%d/%d" % [screen.x, screen.y, choice]
				# A chosen size that drops the panel below 1024 keeps the 800
				# layout, whose caption box stands over the buttons: its narrow
				# strip stays (noted, not held).
				if gap.size.x > 0.0 and gap.size.x < ELCombatGapPanel.MIN_WIDTH:
					if choice == 0 or ELHudFrame.wide_layout(profile, width): strips.append(name)
					else: narrow_800.append(name)
				if stretch > 0.0:
					widened.append("%s +%d" % [name, stretch])
					if not is_equal_approx(stretch, ELHudFrame.rail_trim(profile, width)): strips.append(name + " (part)")
		check(strips.is_empty(), "%s: no screen at the automatic size, and no wide panel at any size, leaves an empty strip beside the rail (%s)" % [edition, ", ".join(strips)])
		print("NOTE: %s: chosen sizes in the 800 layout with a narrow strip: %s" % [edition, ", ".join(narrow_800)])
		check(widened.has("1600x900/0 +43"), "%s: at 1600x900 the caption's oval takes the 43 px (%s)" % [edition, ", ".join(widened)])

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
