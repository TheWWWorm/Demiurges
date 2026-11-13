extends SceneTree
## Renders battles with the effect look preferences off and on, and compares
## the two pictures for the marks of a broken effect.
##
## The preferences (ELEffectLook: bloom, soft particles, spell light) switch
## on code that nothing else runs, and what they do depends on the renderer.
## Spell light drew the glowing sprites as opaque white squares in the
## Compatibility renderer, because an omni light casting a shadow beside them
## does that there, and nothing caught it: the headless checks do not render,
## and the one renderer that was tried by hand was the other one. So this
## renders, in whichever renderer it is started with, and asks of each arena:
## - the preferences do not fill the picture with flat white (a sprite drawn
##   with no transparency, the fault above);
## - they do not darken or blow out the scene as a whole;
## - the glowing effects of the arena are still there with them on.
##
##   godot --path game --rendering-method gl_compatibility --resolution 1280x720 \
##       --script ../tools/effect_render_check.gd
##   godot --path game --rendering-method forward_plus --rendering-driver vulkan ... (the same)
##
## Options: --game=el2 --arenas=Green.001,Ether.001 --shots=<folder> to keep
## the frames. Needs the games' files; it renders, so not --headless.

## More near-white pixels than this coming from the glow is a sprite that
## has lost its transparency, not a brighter picture: a glow fades, and does
## not cover hundreds of pixels at full white. Across the arenas the honest
## readings reach 112; the fault this was written for reaches 960.
const WHITE_ALLOWANCE := 300
## What the preferences may do to the brightness of the whole picture. They
## add a glow to what is bright, not light to the scene, so the room here is
## narrow: taking bloom for a pass it is not once brightened the sunlit
## arenas by a third in the Compatibility renderer, and a bound of 1.6 let
## that through. The widest honest reading now is the Dungeon dimming by a
## tenth with bloom in that renderer, which is itself a difference worth
## closing one day.
const DIMMEST := 0.85
const BRIGHTEST := 1.15

var failures: Array[String] = []
var game := "el2"
var arenas := PackedStringArray(["Green.001", "Ether.001", "White.001"])
var shots := ""

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="): game = arg.get_slice("=", 1)
		elif arg.begins_with("--arenas="): arenas = arg.get_slice("=", 1).split(",", false)
		elif arg.begins_with("--shots="): shots = arg.get_slice("=", 1)
	_run.call_deferred()

## Near-white pixels, and the mean brightness, of the picture now.
func _measure(image: Image) -> Array:
	var small := image.duplicate() as Image
	small.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	var white := 0
	var sum := 0.0
	# The lower strip is the heads-up display, which never changes.
	for y in 128:
		for x in 320:
			var c := small.get_pixel(x, y)
			sum += c.r * 0.3 + c.g * 0.6 + c.b * 0.1
			if c.r > 0.96 and c.g > 0.96 and c.b > 0.96: white += 1
	return [white * (1280 * 720) / (320 * 180), sum / (320.0 * 128.0) * 255.0]

func _settle(view: Node, seconds: float) -> void:
	var clock := 0.0
	while clock < seconds:
		view.ai_clock = -1000.0
		await process_frame
		clock += root.get_process_delta_time()

func _run() -> void:
	var method := RenderingServer.get_current_rendering_method()
	print("Renderer: ", method, " / ", RenderingServer.get_current_rendering_driver_name())
	for arena_id: String in arenas:
		var measured := {}
		# Two runs, and the glow weighed inside the second one. Switching a
		# scene to the buffer that can glow is not the glow: the Compatibility
		# renderer lifts the brightest scenery towards white by that alone
		# (the second game's Blue arena gains 1,700 near-white pixels whatever
		# the glow is set to). Turning the glow off and on again within one
		# held frame tells the two apart exactly; measuring it across separate
		# runs instead gave readings that swung by a thousand pixels either
		# way, because an arena of falling snow is never twice in one state.
		var glowless := []
		for on: int in [0, 1]:
			# On from the start, as the game runs them: the fault above
			# showed while the sprites were first drawn, not once settled.
			var view: Node = load("res://scenes/duel.tscn").instantiate()
			view.demo = true
			root.add_child(view)
			await process_frame
			view.settings.values.auto_camera = false
			view.settings.values.path_tracing = false
			for key: String in ELCrashReport.EFFECT_EXTRAS: view.settings.values[key] = on > 0
			if is_instance_valid(view.path_tracing): view.path_tracing.set_enabled(false)
			ELEffectLook.use(view.settings.values)
			view._start(game, {"arena": arena_id})
			var samples := []
			for seconds: float in [0.4, 2.5]:
				await _settle(view, seconds)
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				samples.append(_measure(image))
				if on == 1:
					# The same frame again with the glow turned down to nothing.
					var environment: Environment = view.arena.environment_settings
					var strength := environment.glow_intensity
					paused = true
					environment.glow_intensity = 0.0
					for i in 3: await process_frame
					await RenderingServer.frame_post_draw
					glowless.append(_measure(root.get_texture().get_image()))
					environment.glow_intensity = strength
					paused = false
				if not shots.is_empty():
					DirAccess.make_dir_recursive_absolute(shots)
					image.save_png("%s/%s_%s_%s_%.1f.png" % [shots, method, arena_id.get_slice(".", 0), "on" if on else "off", seconds])
			measured[on] = samples
			if on == 1: check(not view.effects.glow_sources().is_empty(), "%s %s: its glowing effects still give light" % [game, arena_id])
			view.queue_free()
			await process_frame
		var where := "%s %s" % [game, arena_id]
		for at in 2:
			var off: Array = measured[0][at]
			var plain: Array = glowless[at]
			var lit: Array = measured[1][at]
			var when := "early" if at == 0 else "settled"
			print("   %s %s: white %d -> %d (the glow itself %+d), brightness %.1f -> %.1f" % [where, when, off[0], lit[0], lit[0] - plain[0], off[1], lit[1]])
			# Each state is its own battle, and a moment after one starts they
			# are not at quite the same point; in an arena of snow, where tens
			# of thousands of pixels sit on the edge of white, that shows up as
			# thousands either way. The settled frame is the one to count on,
			# and it caught the fault this test was written for on its own.
			if at > 0: check(lit[0] - plain[0] <= WHITE_ALLOWANCE, "%s: the glow adds no flat white to the picture" % where)
			check(lit[1] >= off[1] * DIMMEST and lit[1] <= off[1] * BRIGHTEST, "%s (%s): the preferences keep the scene's brightness" % [where, when])
	print("EFFECT RENDER (%s): %d failure(s)" % [method, failures.size()])
	quit(0 if failures.is_empty() else 1)
