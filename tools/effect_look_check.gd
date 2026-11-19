extends SceneTree
## Headless check of the effect look preferences (ELEffectLook): bloom, soft
## particles and spell light.
## - bloom and soft particles are off by default, spell light on, all three
##   saved with the shared settings;
## - soft particles: sprite shaders read the scene depth only while the
##   preference is on, and running shaders follow the switch;
## - bloom: an environment blooms with the preference, always while its scene
##   is path traced, and glowing particles draw brighter with it; a blooming
##   whether a scene has the display-encoded sun pass follows the renderer
##   alone, and bloom does not change it;
## - spell light: close glowing patches share one lamp, at most
##   ELGlowLights.LIMIT lamps are lit, none stronger than its limit, only the
##   brightest casts a shadow, they go out when the glow ends, and a
##   path-traced scene gets none;
## - glowing particles keep their authored strength where a scene adds
##   colours as light (ELParticleFile.ADD_KNEE), and a cyclic effect does not
##   draw the frame that closes its loop over the new cycle (which put twice
##   the particles on screen for one frame, flashing the picture every time
##   round), while a longer tail still plays;
## - the light a flame casts keeps its own colour instead of turning pure red;
## - particle shadows: blended smoke, gas and water on the map and in battles
##   get a shadow-only twin with the shadows preference; glowing sprites,
##   glows drawn with plain blending, weather and short flashes get none, and
##   running twins follow the preference.
##
##   godot --headless --path game --script ../tools/effect_look_check.gd
##
## Needs no game files. Settings are never written.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var defaults := ELSettings.new().values
	check(defaults.get("bloom") == false and defaults.get("soft_particles") == false, "bloom and soft particles are off by default")
	check(defaults.get("spell_light") == true and ELEffectLook.spell_light, "spell light is on by default, so glowing effects light the scene")
	check(ELHardwareCheck.DONE > 2, "a device that finished the earlier hardware check weighs the extras once more")
	check(ELCrashReport.EFFECT_EXTRAS == ELHardwareCheck.REVISIT_KEYS, "the features a repeat hardware check settles are the ones a crash in play turns off")
	check(ELEffectLook.names(PackedStringArray(["spell_light"])) == "Spell light", "one reset preference is named on its own")
	check(ELEffectLook.names(PackedStringArray(["spell_light", "bloom"])) == "Bloom and Spell light", "two are named in the page's order")
	check(ELEffectLook.names(PackedStringArray(ELHardwareCheck.REVISIT_KEYS)) == "Bloom, Soft particles and Spell light", "all three are named in a list")
	for text: String in ["Bloom", "Soft particles", "Spell light", "Fire, lightning, auras and other glowing effects shine with a soft glow.",
			"Smoke, fire and magic fade softly where they meet the ground and figures instead of ending in a hard line.",
			"In battles, glowing effects light the figures and scenery near them. May reduce performance on slower devices."]:
		check(ELRemakeText.russian(text) != text, "Russian text for: %s" % text)

	# Soft particles.
	ELEffectLook.use({})
	var code := "shader_type spatial;\nSPRITE_SIZE_FUNCTION\nSOFT_FUNCTION\nvoid fragment() { ALPHA = sprite_soft(SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX, 1.0); }\n"
	var shader := ELParticleFile.make_sprite_shader(code)
	check(not shader.code.contains("hint_depth_texture") and shader.code.contains("sprite_soft"), "a sprite shader reads no scene depth with soft particles off")
	ELEffectLook.use({"soft_particles": true})
	check(shader.code.contains("hint_depth_texture") and not shader.code.contains("SOFT_RANGE"), "a running sprite shader fades by scene depth once soft particles are on")
	check(ELParticleFile.make_sprite_shader(code).code == shader.code, "a new sprite shader is soft while the preference is on")
	ELEffectLook.use({})
	check(not shader.code.contains("hint_depth_texture"), "the shader stops reading scene depth when soft particles go off")
	check(not ELParticleFile.sprite_shader("SPRITE_SIZE_FUNCTION").contains("SOFT"), "a shader without the soft function is left as it was")

	# Glowing sprites where colours add as light, not as displayed.
	var add_code := "shader_type spatial;
ADD_FUNCTION
void fragment() { ALPHA = sprite_add(1.0); }
"
	ELParticleFile.set_linear_blend(false)
	var plain := ELParticleFile.make_sprite_shader(add_code)
	check(plain.code.contains("return alpha;"), "a glowing sprite is drawn as authored where colours add as displayed")
	ELParticleFile.set_linear_blend(true)
	check(plain.code.contains(str(ELParticleFile.ADD_KNEE)) and not plain.code.contains("ADD_KNEE"), "a running sprite shader takes the knee where colours add as light")
	var knee := func(a: float) -> float: return a * (a + ELParticleFile.ADD_KNEE) / (1.0 + ELParticleFile.ADD_KNEE)
	check(is_equal_approx(knee.call(1.0), 1.0) and knee.call(0.8) > 0.8 * 0.8 and knee.call(0.1) < 0.1 * 0.35, "the knee leaves a flame's body and takes down the faint skirt around it")
	ELParticleFile.set_linear_blend(false)
	check(plain.code.contains("return alpha;"), "the knee goes with the renderer")

	# A cyclic effect that ends on the frame closing its loop (EtherGlows.pfx:
	# 20 frames, loop 0 to 19, every frame the same 43 sprites).
	var cyclic := ELParticleFile.new()
	cyclic.frames = 20
	cyclic.loop_end = 20
	cyclic.closing_frame = true
	var seen := {}
	var doubled := 0
	for frame in 200:
		var drawn := cyclic.visible_frames(frame)
		if drawn.size() > 1: doubled += 1
		for at: int in drawn: seen[at] = true
	check(doubled == 0 and seen.size() == 20, "a cyclic effect that closes on its loop draws one frame at a time, all of them")
	# One with a tail (WhiteFire1.pfx: 260 frames, loop 0 to 199) keeps it.
	var tailed := ELParticleFile.new()
	tailed.frames = 260
	tailed.loop_end = 200
	check(tailed.visible_frames(250).size() == 2 and tailed.visible_frames(250).has(50) and tailed.visible_frames(250).has(250), "a cycle still plays its tail while the next one runs")
	# A file ending one frame past its loop closes there
	# (whitelordportalin.pfx: 151 frames, loop 0 to 149).
	var one_frame := ELParticleFile.new()
	one_frame.frames = 151
	one_frame.loop_end = 150
	one_frame.closing_frame = true
	check(one_frame.visible_frames(150).size() == 1 and one_frame.visible_frames(150).has(0), "the frame closing a loop gives way to the new cycle")

	# The light a flame casts.
	var flame := ELCombatEffects._saturate(Vector3(2.4, 1.3, 0.1))
	check(is_equal_approx(flame.x, 2.4) and flame.y / flame.x > 0.4 and flame.y / flame.x < 0.8 and flame.z / flame.x < 0.12, "a flame lights its surroundings orange, not red")
	var deep := ELCombatEffects._saturate(Vector3(1.0, 0.1, 0.0))
	check(is_equal_approx(deep.x, 1.0) and deep.y >= 0.1 and deep.y < 0.25 and deep.z == 0.0, "a glow that is already deep is not deepened further")
	var pale := ELCombatEffects._saturate(Vector3(1.0, 0.92, 0.9))
	check(pale.y < 0.88 and pale.y > 0.7, "a glow gone nearly white from overlapping sprites is deepened to the hue it had")

	# Bloom.
	var environment := Environment.new()
	check(not ELEffectLook.sync(environment) and not environment.glow_enabled and ELCombatEffects.glow_level == 1.0 and ELAdventureEffects.glow_level == 1.0, "no bloom and plain particles with the preference off")
	ELEffectLook.use({"bloom": true})
	check(ELEffectLook.sync(environment) and environment.glow_enabled and is_equal_approx(environment.glow_hdr_threshold, ELEffectLook.BLOOM_THRESHOLD) and ELCombatEffects.glow_level == ELEffectLook.EFFECT_HDR and ELAdventureEffects.glow_level == ELEffectLook.EFFECT_HDR, "the bloom preference blooms the scene and brightens glowing particles")
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	check(ELEffectLook.encoded_sun_pass(environment) == compatibility, "the display-encoded sun pass follows the renderer")
	environment.glow_enabled = not environment.glow_enabled
	check(ELEffectLook.encoded_sun_pass(environment) == compatibility, "and bloom does not change it, as the renderer still adds that pass")
	environment.glow_enabled = not environment.glow_enabled
	ELEffectLook.use({})
	check(not ELEffectLook.sync(environment) and not environment.glow_enabled and ELCombatEffects.glow_level == 1.0, "bloom goes off with the preference")
	environment.set_meta(ELEffectLook.TRACED, true)
	check(ELEffectLook.sync(environment) and environment.glow_enabled, "a path-traced scene blooms whatever the preference")
	ELEffectLook.use({"spell_light": true})
	check(not ELEffectLook.lights(environment), "a path-traced scene gets no lamps for its glow")
	environment.remove_meta(ELEffectLook.TRACED)
	check(ELEffectLook.lights(environment) and not ELEffectLook.sync(environment), "spell light alone lights an ordinary scene without bloom")
	ELEffectLook.use({})
	check(not ELEffectLook.lights(environment), "no lamps with spell light off")

	# Spell light.
	var close := [[Vector3(0, 1, 0), 0.3, Vector3(2, 1, 0)], [Vector3(0.5, 1, 0), 0.6, Vector3(1, 1, 0)], [Vector3(9, 1, 0), 0.2, Vector3(0.2, 0.4, 0.8)]]
	var lamps := ELGlowLights.merged(close)
	check(lamps.size() == 2 and lamps[0][2].is_equal_approx(Vector3(3, 2, 0)) and is_equal_approx(lamps[0][1], 0.6) and lamps[0][0].x > 0.0 and lamps[0][0].x < 0.5, "glowing patches close together share one lamp")
	var lights := ELGlowLights.new()
	root.add_child(lights)
	var many := []
	for i in 20: many.append([Vector3(i * 10.0, 1, 0), 0.5, Vector3(100, 60, 20) * (i + 1)])
	lights.show_sources(many, 0.0)
	var strongest := 0.0
	var shadows := 0
	var brightest: OmniLight3D = null
	for lamp: OmniLight3D in lights.get_children():
		if lamp.visible and (brightest == null or lamp.light_energy > brightest.light_energy): brightest = lamp
		strongest = maxf(strongest, lamp.light_energy)
		if lamp.shadow_enabled: shadows += 1
	check(lights.lit() == ELGlowLights.LIMIT and strongest <= ELGlowLights.ENERGY_LIMIT + 0.001 and strongest > 0.5, "at most %d lamps are lit, none past its limit" % ELGlowLights.LIMIT)
	var wanted := ELGlowLights.SHADOW_LAMPS if ELGlowLights.shadows_available() else 0
	check(shadows == wanted and (wanted == 0 or (brightest != null and brightest.shadow_enabled)), "only the brightest lamp casts a shadow, and none where the renderer cannot")
	# Patches regroup from frame to frame; lamps on their way out never push
	# the lit ones past the limit.
	var moved := []
	for i in 20: moved.append([Vector3(500.0 + i * 9.0, 1, 0), 0.5, Vector3(100, 60, 20) * (i + 1)])
	var most := 0
	for step in 12:
		lights.show_sources(moved if step % 2 == 0 else many, 1.0 / 60.0)
		most = maxi(most, lights.lit())
	check(most <= ELGlowLights.LIMIT, "lamps fading out never push the lit ones past %d (most seen: %d)" % [ELGlowLights.LIMIT, most])
	for i in 120: lights.show_sources([], 1.0 / 60.0)
	check(lights.lit() == 0, "the lamps go out when the glow ends")
	for lamp: OmniLight3D in lights.get_children():
		check(not lamp.shadow_enabled, "a lamp that has gone out casts no shadow")
		break
	# A figure's own glow (a Kinet hero's blade) and the arena's standing
	# fires light, but never cast the shadow; a figure's glow lights faintly.
	var figure := [Vector3(0, 2, 0), 0.5, Vector3(20, 20, 20), false, 1]
	var spell := [figure[0], figure[1], figure[2]]
	var torch := [Vector3(30, 2, 0), 0.5, Vector3(40, 30, 10), true, false]
	lights.show_sources([figure, torch], 0.0)
	var cast := 0
	var faint := INF
	for lamp: OmniLight3D in lights.get_children():
		if not lamp.visible: continue
		if lamp.shadow_enabled: cast += 1
		if lamp.global_position.distance_to(figure[0]) < 0.1: faint = lamp.light_energy
	check(cast == 0, "neither a figure's own glow nor the arena's fires cast a shadow")
	for i in 120: lights.show_sources([], 1.0 / 60.0)
	lights.show_sources([spell], 0.0)
	var full := 0.0
	for lamp: OmniLight3D in lights.get_children():
		if lamp.visible: full = lamp.light_energy
	check(faint < full * (ELGlowLights.ATTACHED_SHARE + 0.01), "a figure's own glow lights at a share of a spell's (%.2f of %.2f)" % [faint, full])
	lights.queue_free()
	# Path tracing steadies a figure's own lights as the lamps are: one that
	# moves eases there, and one whose glow leaves a gap of a few frames
	# stays lit through it, fading only over a longer gap.
	var tracer := ELPathTracing.new()
	var wing := [Vector3(0, 2, 0), 0.5, Vector3(1, 1, 1), 4.0]
	tracer._steady_figure_lights([wing], 0.0)
	var eased: Array = tracer._steady_figure_lights([[Vector3(0.8, 2, 0), 0.5, Vector3(1, 1, 1), 4.0]], 1.0 / 60.0)
	check(eased.size() == 1 and eased[0][0].x > 0.0 and eased[0][0].x < 0.4, "a traced figure light eases towards where its glow moved")
	var through := []
	for i in 6: through = tracer._steady_figure_lights([], 1.0 / 60.0)
	check(through.size() == 1 and through[0][2].x > 0.7, "a traced figure light stays lit through a gap of a few frames")
	for i in 180: through = tracer._steady_figure_lights([], 1.0 / 60.0)
	check(through.is_empty(), "a traced figure light goes out when its glow is gone")
	tracer.free()

	# Particle shadows.
	_particle_shadows()
	print("EFFECT LOOK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## A small blended or glowing particle file: one sprite a frame.
func _particle(sheet: String, additive: bool, frames := 60) -> ELParticleFile:
	var file := ELParticleFile.new()
	file.frames = frames
	file.texture = sheet
	file.additive = additive
	file.max_count = 1
	for frame in frames + 1: file.starts.append(mini(frame, frames))
	for frame in frames:
		file.positions.append_array(PackedFloat32Array([0.0, 0.0, 1.0 + frame * 0.05]))
		file.sizes.append(1.5)
		file.cells.append_array(PackedByteArray([0, 0]))
		file.rgb.append_array(PackedByteArray([128, 128, 128]))
		file.alpha.append(200)
	return file

## Blended smoke, mist and water cast a soft shadow through a shadow-only
## twin; glowing sprites, glows drawn with plain blending, weather and short
## flashes do not, and none cast with the shadows preference off.
func _particle_shadows() -> void:
	check(ELParticleFile.shadow_strength(_particle("SmokeBlack.bmp", false)) > 0.0 and ELParticleFile.shadow_strength(_particle("water00.bmp", false)) > 0.0 and ELParticleFile.shadow_strength(_particle("BlackGas.bmp", false)) > 0.0, "blended smoke, water and gas sheets cast a shadow")
	check(ELParticleFile.shadow_strength(_particle("TendriSmoke.bmp", true)) == 0.0 and ELParticleFile.shadow_strength(_particle("Fire.bmp", true)) == 0.0, "glowing (additive) sheets cast none, smoke among them")
	check(ELParticleFile.shadow_strength(_particle("ManaRed.bmp", false)) == 0.0 and ELParticleFile.shadow_strength(_particle("LightningBallRd.bmp", false)) == 0.0 and ELParticleFile.shadow_strength(_particle("MagmaGlow.bmp", false)) == 0.0, "glows drawn with plain blending cast none")
	check(ELParticleFile.shadow_strength(_particle("BlueFX.bmp", false)) == 0.0 and ELParticleFile.shadow_strength(_particle("GreenFall.bmp", false)) == 0.0 and ELParticleFile.shadow_strength(_particle("Snow.bmp", false)) == 0.0, "rain, snow and falling leaves cast none")
	check(ELParticleFile.shadow_strength(_particle("SmokeBlack.bmp", false, ELParticleFile.SHADOW_MIN_FRAMES - 1)) == 0.0, "a flash shorter than %d frames casts none" % ELParticleFile.SHADOW_MIN_FRAMES)
	var shader := ELParticleFile.shadow_shader()
	check(shader.code.contains("discard") and not shader.code.contains("blend_") and not shader.code.contains("ALPHA"), "the twin's shader is opaque with a dithered cut-out, so the renderer draws it into the shadow map")

	ELEffectLook.use({"shadows": true})
	check(ELParticleFile.shadows, "particle shadows follow the shadows preference")
	var atlas := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	# The map's effects.
	var profile := ELProfile.new()
	profile.id = "shadow_check"
	var map := ELAdventureEffects.new()
	map.profile = profile
	map.weather_layer = Node3D.new()
	map.add_child(map.weather_layer)
	root.add_child(map)
	var sheets := {"smoke.pfx": _particle("SmokeVoulcan.bmp", false), "fire.pfx": _particle("Fire.bmp", true), "terrainpfx/ash.pfx": _particle("SmokeBlack.bmp", false)}
	for path: String in sheets:
		var file: ELParticleFile = sheets[path]
		ELAdventureEffects._kept[ELAdventureEffects.cache_space(profile) + ":" + path] = file
		var material := ShaderMaterial.new()
		material.set_shader_parameter("atlas", atlas)
		map._materials["%s#%d|%s|%d|%d|%s" % [profile.id, profile.generation, file.texture, file.columns, file.rows, file.additive]] = material
		map.start(path, {"file": path, "x": 0.0, "y": 0.0, "z": 0.0}, 0.0, true)
	var smoke := _twin(map.effects.get("smoke.pfx", {}))
	check(smoke != null and ELParticleFile.twin_casts(smoke) and smoke.visible and smoke.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "map smoke gets a shadow-only twin")
	check(smoke != null and smoke.multimesh == (map.effects["smoke.pfx"].node as MultiMeshInstance3D).multimesh, "the twin draws the effect's own quads")
	check(map.effects.has("fire.pfx") and not ELParticleFile.twin_casts(_twin(map.effects["fire.pfx"])), "a glowing map effect casts no shadow")
	check(map.effects.has("terrainpfx/ash.pfx") and not ELParticleFile.twin_casts(_twin(map.effects["terrainpfx/ash.pfx"])), "the map's weather layer casts no shadow")
	ELEffectLook.use({"shadows": false})
	check(not ELParticleFile.shadows and smoke != null and not smoke.visible, "a running twin stops casting when the shadows preference goes off")
	map.start("late.pfx", {"file": "smoke.pfx", "x": 0.0, "y": 0.0, "z": 0.0}, 0.0, true)
	var late := _twin(map.effects.get("late.pfx", {}))
	check(late == null or not late.visible, "an effect started with shadows off casts none")
	ELEffectLook.use({"shadows": true})
	check(smoke != null and smoke.visible and late != null and late.visible, "and both cast once the preference is back on")

	# Battle effects: pooled emitters change sheets, and the twin follows.
	var battle := ELCombatEffects.new()
	battle.profile = profile
	root.add_child(battle)
	var space := ELCombatEffects.cache_space(profile)
	for path: String in ["gas.pfx", "spark.pfx", "combatarenas/snow.pfx"]:
		var file: ELParticleFile = _particle("BlackGas.bmp", false) if path == "gas.pfx" else (_particle("Spark.bmp", true) if path == "spark.pfx" else _particle("BlueFX.bmp", false))
		ELCombatEffects._files[space + ":" + path] = {"file": file, "frames": {}, "bytes": 0}
		for use: String in ["effect", "arena"]:
			var material := ShaderMaterial.new()
			material.set_shader_parameter("atlas", atlas)
			ELCombatEffects._materials["%s|%s|%d|%d|%s|%s" % [space, file.texture.to_lower(), file.columns, file.rows, use, file.additive]] = material
	var gas := battle._spawn("gas.pfx", false, 30, Transform3D.IDENTITY)
	check(not gas.is_empty() and ELParticleFile.twin_casts(gas.shadow) and (gas.shadow as MultiMeshInstance3D).visible, "a battle's gas casts a shadow")
	battle._release(gas)
	var spark := battle._spawn("spark.pfx", false, 30, Transform3D.IDENTITY)
	check(not spark.is_empty() and is_same(spark.shadow, gas.shadow) and not ELParticleFile.twin_casts(spark.shadow) and not (spark.shadow as MultiMeshInstance3D).visible, "the same emitter reused for sparks casts none")
	var snow := battle._spawn("combatarenas/snow.pfx", false, 0, Transform3D.IDENTITY, null, true)
	var arena_gas := battle._spawn("gas.pfx", false, 0, Transform3D.IDENTITY, null, true)
	check(not snow.is_empty() and not ELParticleFile.twin_casts(snow.shadow) and not arena_gas.is_empty() and not ELParticleFile.twin_casts(arena_gas.shadow), "the arena's own weather casts none")
	ELEffectLook.use({"shadows": false})
	var quiet := battle._spawn("gas.pfx", false, 30, Transform3D.IDENTITY)
	check(not quiet.is_empty() and not (quiet.shadow as MultiMeshInstance3D).visible, "battle gas casts none with the shadows preference off")
	ELEffectLook.use({})
	for path: String in sheets: ELAdventureEffects._kept.erase(ELAdventureEffects.cache_space(profile) + ":" + path)
	ELCombatEffects._forget_edition(profile.id)
	map.queue_free()
	battle.queue_free()

func _twin(effect: Dictionary) -> MultiMeshInstance3D:
	if effect.is_empty(): return null
	return (effect.node as Node).get_node_or_null("Shadow") as MultiMeshInstance3D
