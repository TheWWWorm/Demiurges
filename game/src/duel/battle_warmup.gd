class_name ELBattleWarmup
extends Node
## Readies a battle's first casts while it opens. Each card either side may
## play (hands first, then decks, graveyards and the creatures already in
## play) is looked up, with the creature powers and the effects any battle
## shows (hero life, ether and cards, stat changes, the colours' summons and
## deaths); the figures, clips, particle files, sprite sheets and sounds
## they need are decoded on worker threads, and the main thread only files
## the results away, a few at a time. Without it the first cast of each card
## decoded all of that in the frame it was cast (sounds, the caster's clip,
## the particle files with their frames and glow, the sprite sheets and
## their colours, the effect models), which stalled the opening turns of a
## battle while later casts were smooth.
##
## A cast that comes before its parts are ready decodes them itself, as
## before; the warm-up then keeps what the cast made.

const Table := preload("res://src/duel/combat_sound_table.gd")
## Main-thread time per frame for filing results away and starting jobs.
const BUDGET_USEC := 2500
## Worker jobs running at once (the battle's own work keeps the rest).
const MAX_RUNNING := 6
## Clips the figures of a battle play: idles, the hero gestures and the
## creature actions; missing ones are skipped.
const CLIPS := ["cidle", "uhit", "udeath", "uinstant", "usummon", "uenchantment", "uvictory", "uattack",
	"ctapidle", "utap", "uuntap", "untap", "crun", "cwalk", "cspecial1", "cspecial2", "cspecial3", "cspecial4"]
## Effects of every battle, whatever the decks hold.
const COMMON_EFFECTS := ["GainLife", "LoseLife", "GainMana", "LoseMana", "Draw", "Discard",
	"PosAttack", "PosDefence", "PosRune", "PosSorcery", "PosEnchantment", "NegAttack", "NegDefence", "NegRune",
	"NegSorcery", "NegEnchantment", "Disenchant", "Berserk", "Restless", "FirstStrike", "CantAttack", "CantUntap",
	"RedDamage", "GreenDamage", "BlueDamage", "BlackDamage", "RedDeath", "GreenDeath", "BlueDeath", "BlackDeath",
	"DrainLife", "DrainMana", Table.REDIRECT, Table.FEEDBACK, Table.BARRIER, Table.STONESKIN]
## A figure's own sounds (Creatures/<SndDir>/<action>.wav).
const UNIT_SOUNDS := ["summon", "instant", "enchantment", "attack", "hit", "death", "tap", "untap", "idle00", "idle01", "idle02", "idle03"]

var profile: ELProfile
var effects: ELCombatEffects
var audio: ELBattleAudio
## The battle's blood (ELCombatBlood): its drop and print shaders are warmed too.
var blood: Node
## The battlefield, whose floor hides the warming figures.
var arena: ELArena
## The out-of-sight figures drawing each material once, and the frames
## left to draw them; tries left to find a view down onto the arena.
var _shader_holder: Node3D
var _shader_queue: Array[Node3D] = []
var _shader_frames := -1
var _shader_tries := 600
## Main-thread steps still to run, in order.
var _steps: Array[Callable] = []
## Worker jobs: {task, done: Callable(result)}; `result` holds the job's output.
var _jobs: Array[Dictionary] = []
var _started := {}
## Steps waiting for a job to finish; they rejoin the queue next frame.
var _later: Array[Callable] = []
## Texture key -> [[ready, grid], ...] while it decodes.
var _texture_waiters := {}
## Figures whose resources or clips are still being decoded, and those
## that could not be read.
var _figures_busy := {}
var _figures_failed := {}
## Timing for checks: main-thread time spent, jobs run, and when the
## warm-up started, had everything decoded and was done (ticks, ms).
var main_usec := 0
var jobs_run := 0
var started_at := -1
var decoded_at := -1
var finished_at := -1

## Starts readying what `duel` may show; `models` are the hero figures
## already built (side -> ELModel).
func begin(data: ELProfile, duel: ELDuel, models: Dictionary, combat_effects: ELCombatEffects, battle_audio: ELBattleAudio) -> void:
	started_at = Time.get_ticks_msec()
	profile = data
	effects = combat_effects
	audio = battle_audio
	# The decoder's lookup tables are built once, before workers share them.
	ELAudio._tables()
	var cards: Array[String] = []
	for side in 2:
		for card: Variant in duel.heroes[side].get("hand", []): _add_card(cards, card)
	for side in 2:
		for list: String in ["deck", "grave"]:
			for card: Variant in duel.heroes[side].get(list, []): _add_card(cards, card)
		# Artifacts cast their spell's effects.
		for item: Variant in duel.heroes[side].get("artifacts", []):
			if item is Dictionary: _add_card(cards, item.get("spell", ""))
	for creature: Dictionary in duel.creatures.values(): _add_card(cards, creature.get("card", ""))
	var effect_names: Array[String] = []
	var sounds: Array[String] = []
	# The casters first: their gestures and voices start every cast.
	for side: int in models:
		if side in [0, 1] and is_instance_valid(models[side]): _queue_figure(models[side].template, [], models[side], sounds)
	for card in cards:
		for effect: Variant in Table.card_effects(profile, card): _add_effect(effect_names, String(effect))
		for effect: Variant in Table.trigger_effects(profile.id, card): _add_effect(effect_names, String(effect))
		for item: Array in Table.ability_effects(profile.id, card):
			if not item.is_empty(): _add_effect(effect_names, String(item[0]))
		for effect: Variant in Table.AURA_EFFECTS.get(card, []): _add_effect(effect_names, String(effect))
	for effect: String in COMMON_EFFECTS: _add_effect(effect_names, effect)
	for effect in effect_names:
		var path := String(audio.effect_files.get(effect.to_lower(), "")) if is_instance_valid(audio) else ""
		if not path.is_empty() and not sounds.has(path): sounds.append(path)
	# Each card's parts in turn, so the cards in hand are ready first.
	var creatures: Dictionary = profile.table("CombatCreatures")
	for effect in effect_names: _steps.append(_queue_effect.bind(effect))
	for card in cards:
		var row: Dictionary = creatures.get(card, {})
		if row.is_empty() or String(row.get("Model", "")).is_empty(): continue
		var skins: Array[String] = ["Creatures/" + String(row.get("Texture", ""))]
		if row.has("SecTexture"): skins.append("Creatures/" + String(row.SecTexture))
		var stand_in := Node.new()
		stand_in.set_meta("sound_directory", row.get("SndDir", ""))
		_queue_figure(String(row.Model), skins, stand_in, sounds)
		stand_in.free()
	# The phase banner's sound (ELCombatNotices).
	sounds.append("Buttons/Begin_Combat.wav")
	for path in sounds: _steps.append(_queue_sound.bind(path))
	# The battlefield's passing weather (wind gusts, falling leaves with
	# their sounds) and its random ambience come last.
	var weather := effects.arena_parts()
	for path: String in weather.particles: _steps.append(_queue_particles.bind(path, true))
	for path: String in weather.sounds: _steps.append(_queue_sound.bind(path))
	if is_instance_valid(audio):
		for path: String in audio.ambient_sounds: _steps.append(_queue_sound.bind(path))
	set_process(true)

func _add_card(cards: Array[String], entry: Variant) -> void:
	var card := str(entry.get("card", "")) if entry is Dictionary else str(entry)
	if not card.is_empty() and not cards.has(card): cards.append(card)

func _add_effect(names: Array[String], effect: String) -> void:
	if not effect.is_empty() and not names.has(effect) and not effects.definition(effect).is_empty(): names.append(effect)

## Queues a figure's resources, clips, skins and own sounds. `model` gives
## the sound folder and voice (a built hero figure or a stand-in).
func _queue_figure(model_name: String, skins: Array[String], model: Node, sounds: Array[String]) -> void:
	var template := ELArchive.key(model_name)
	if template.is_empty(): return
	_steps.append(_queue_model.bind(template))
	for skin in skins: _steps.append(_queue_texture.bind(skin, Vector2i.ZERO, Callable()))
	if not is_instance_valid(audio): return
	for action: String in UNIT_SOUNDS:
		var paths: Array[String] = []
		var plain := audio.unit_path(model, action)
		if plain.is_empty(): continue
		if model.get_meta("voice", false) and (action == "hit" or action in ELBattleAudio.VOICED_CASTS):
			# Voiced heroes say one of three takes.
			for take in 3: paths.append("Creatures/%s/voice/%s%02d.wav" % [model.get_meta("sound_directory", ""), action, take + 1])
		else: paths.append(plain)
		for path in paths:
			if not sounds.has(path): sounds.append(path)

func _process(_delta: float) -> void:
	var clock := Time.get_ticks_usec()
	_steps.append_array(_later)
	_later.clear()
	# Finished jobs first: their results unblock the next steps.
	var at := 0
	while at < _jobs.size() and Time.get_ticks_usec() - clock < BUDGET_USEC:
		var job: Dictionary = _jobs[at]
		if not WorkerThreadPool.is_task_completed(job.task):
			at += 1
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.remove_at(at)
		jobs_run += 1
		job.done.call(job.result)
	while not _steps.is_empty() and _jobs.size() < MAX_RUNNING and Time.get_ticks_usec() - clock < BUDGET_USEC:
		var step: Callable = _steps.pop_front()
		step.call()
	if _steps.is_empty() and _jobs.is_empty() and _later.is_empty():
		if decoded_at < 0: decoded_at = Time.get_ticks_msec()
		_step_shaders()
	main_usec += Time.get_ticks_usec() - clock
	if _steps.is_empty() and _jobs.is_empty() and _later.is_empty() and _shader_frames == 0:
		finished_at = Time.get_ticks_msec()
		print_verbose("Battle warm-up: decoded in %d ms (%d jobs), shaders drawn by %d ms; main thread %.1f ms" % [decoded_at - started_at, jobs_run, finished_at - started_at, main_usec / 1000.0])
		set_process(false)

## Once everything is decoded: draws each material a cast switches to (the
## particle shaders, the effect models' blended and additive looks, a
## figure fading out or flashing as it is hit, blood, the floating numbers)
## once, out of sight under the arena floor, so the renderer compiles their
## shaders now rather than in the frame a cast first shows them. One new
## material a frame: the compatibility renderer compiles as it draws, and
## all at once would be a stall of its own. The renderers keep compiled
## shaders on disk, so this matters for the first battles on a computer.
func _step_shaders() -> void:
	if _shader_frames == 0: return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	# Ten metres ahead, two under the floor, and in view.
	var spot := Vector3.ZERO
	if camera != null:
		spot = camera.global_position - camera.global_basis.z * 10.0
		var floor_height := arena.ground_height(spot.x, spot.z) if is_instance_valid(arena) else 0.0
		spot.y = minf(spot.y, floor_height - 2.0)
	var hidden := camera != null and camera.is_position_in_frustum(spot)
	if _shader_frames < 0:
		_shader_tries -= 1
		if _shader_tries <= 0: _shader_frames = 0
		if not hidden: return
		_shader_holder = Node3D.new()
		add_child(_shader_holder)
		# Effects light what they pass (ELCombatEffects point lights): the
		# lit looks of the floor and figures under such a light compile too.
		var lamp := OmniLight3D.new()
		lamp.shadow_enabled = false
		lamp.omni_range = 3.0
		lamp.light_energy = 0.01
		_shader_holder.add_child(lamp)
		lamp.set_meta("shown", -1000000)
		_shader_queue = _shader_figures()
		_shader_frames = _shader_queue.size() + 3
	if not is_instance_valid(_shader_holder):
		_shader_frames = 0
		return
	# The view turned away: wait for it to look down again.
	if not hidden and _shader_tries > 0:
		_shader_tries -= 1
		return
	_shader_holder.global_position = spot
	for node: Node in _shader_holder.get_children():
		# Each drawn a couple of frames, then dropped.
		var shown := int(node.get_meta("shown", 0)) + 1
		node.set_meta("shown", shown)
		if shown > 2 and shown < 1000: node.queue_free()
	if not _shader_queue.is_empty(): _shader_holder.add_child(_shader_queue.pop_front())
	_shader_frames -= 1
	if _shader_frames <= 0:
		_shader_frames = 0
		for node in _shader_queue: node.free()
		_shader_queue.clear()
		_shader_holder.queue_free()
		_shader_holder = null

## The figures that draw each material once (see _step_shaders).
func _shader_figures() -> Array[Node3D]:
	var blank := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var meshes: Array[Material] = []
	var particles: Array[Material] = []
	if is_instance_valid(effects):
		var found := effects.warm_materials()
		meshes.append_array(found.meshes)
		particles.append_array(found.particles)
	# A figure fading out (ELModel.set_opacity), lit and fullbright.
	for unlit: bool in [false, true]:
		var faded := ELFigure.material(blank, unlit)
		faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		meshes.append(faded)
	if is_instance_valid(blood):
		for node: Node in blood.get_children():
			if node is MultiMeshInstance3D and node.material_override != null: particles.append(node.material_override)
	var figures: Array[Node3D] = []
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	for material in meshes:
		var node := MeshInstance3D.new()
		node.mesh = quad
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		figures.append(node)
	# The hit flash (ELModel.flash) is drawn over a figure's skin.
	var flashed := MeshInstance3D.new()
	flashed.mesh = quad
	flashed.material_override = ELFigure.material(blank)
	flashed.material_overlay = StandardMaterial3D.new()
	flashed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	figures.append(flashed)
	# The numbers rising from a hurt figure (the battle view's floating
	# text): their billboard material and the font's digits at that size.
	var label := Label3D.new()
	label.text = "+-0123456789/"
	label.font_size = 52
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1, 1, 1, 0)
	figures.append(label)
	for material in particles:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = quad
		multimesh.instance_count = 1
		multimesh.set_instance_transform(0, Transform3D.IDENTITY)
		multimesh.set_instance_custom_data(0, Color(0, 0, 0, 0))
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		figures.append(node)
	return figures

func _exit_tree() -> void:
	for job: Dictionary in _jobs: WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()
	_steps.clear()
	_later.clear()
	for node in _shader_queue: node.free()
	_shader_queue.clear()

## Runs `work(result)` on a worker thread, then `done(result)` here.
func _run(work: Callable, done: Callable, what: String) -> void:
	var result := {}
	_jobs.append({"task": WorkerThreadPool.add_task(work.bind(result), false, what), "done": done, "result": result, "what": what})

func _once(key: String) -> bool:
	if _started.has(key): return false
	_started[key] = true
	return true

# Figures -------------------------------------------------------------------

func _queue_model(template: String) -> void:
	if not _once("model:" + template): return
	if profile.model_resources.has(template):
		_queue_clips(template)
		return
	var files := ELModel.read_resources(profile, template)
	_figures_busy[template] = true
	_run(func(result: Dictionary): result.resources = ELModel.parse_resources(template, files),
		func(result: Dictionary):
			_figures_busy.erase(template)
			if not profile.model_resources.has(template) and not result.resources.has("error"): profile.model_resources[template] = result.resources
			if profile.model_resources.has(template): _queue_clips(template)
			else: _figures_failed[template] = true,
		"Battle figure")

## Decodes a figure's clips and builds their meshes on a worker thread.
func _queue_clips(template: String) -> void:
	var resources: Dictionary = profile.model_resources.get(template, {})
	var animations: ELArchive = resources.get("animations")
	if animations == null: return
	var names: Array[String] = []
	for clip: String in CLIPS:
		if not animations.has(clip): continue
		if not resources.clips.has(clip): names.append(clip)
		# The figure's own particles that start with the clip.
		var particles := effects.figure_particles(template, clip) if is_instance_valid(effects) else ""
		if not particles.is_empty(): _steps.push_front(_queue_particles.bind(particles, false))
	if names.is_empty(): return
	var links: Array = resources.links
	var figures: Dictionary = resources.figures
	_figures_busy[template] = true
	_run(func(result: Dictionary):
			result.clips = {}
			result.meshes = {}
			for clip in names:
				var tracks := ELModel.decode_clip(animations, clip, links)
				result.clips[clip] = tracks
				result.meshes.merge(ELModel.clip_meshes(figures, clip, tracks)),
		func(result: Dictionary):
			_figures_busy.erase(template)
			for clip: String in result.clips:
				# A figure that played the clip meanwhile keeps its own.
				if resources.clips.has(clip): continue
				resources.clips[clip] = result.clips[clip]
				for part: String in figures:
					var key := clip + "/" + part
					if result.meshes.has(key) and not resources.meshes.has(key): resources.meshes[key] = result.meshes[key],
		"Battle clips")

# Sprite sheets and skins ---------------------------------------------------

## Decodes a texture; with a grid also its sprite cells' colours, which
## `ready(tints)` receives here (null without them, or when the texture was
## already loaded).
func _queue_texture(name: String, grid: Vector2i, ready: Callable) -> void:
	var key := ELArchive.key(name)
	if _texture_waiters.has(key):
		if ready.is_valid(): _texture_waiters[key].append([ready, grid])
		return
	var source := {} if profile._textures.has(key) else profile._texture_source(key)
	if source.is_empty() or PackedByteArray(source.bytes).is_empty():
		if ready.is_valid(): ready.call(null)
		return
	_texture_waiters[key] = [[ready, grid]] if ready.is_valid() else []
	_run(func(result: Dictionary):
			result.decoded = ELProfile._texture_decode(source)
			if grid != Vector2i.ZERO and not result.decoded.is_empty():
				result.tints = ELCombatEffects.cell_tints(result.decoded.image.duplicate(), grid),
		func(result: Dictionary):
			if not profile._textures.has(key) and not result.decoded.is_empty(): profile._texture_store(key, result.decoded)
			var waiting: Array = _texture_waiters.get(key, [])
			_texture_waiters.erase(key)
			for waiter: Array in waiting: waiter[0].call(result.get("tints") if waiter[1] == grid else null),
		"Battle texture")

func _texture_busy(name: String) -> bool:
	return _texture_waiters.has(ELArchive.key(name))

# Effects -------------------------------------------------------------------

func _queue_effect(effect: String) -> void:
	if not is_instance_valid(effects): return
	var parts := effects.effect_parts(effect)
	for path: String in parts.particles: _steps.push_front(_queue_particles.bind(path, false))
	for object: Dictionary in parts.objects:
		var key := "object:%s|%s|%s" % [String(object.model).to_lower(), String(object.texture).to_lower(), object.add]
		if not _once(key): continue
		_steps.append(_queue_model.bind(ELArchive.key(String(object.model))))
		_steps.append(_queue_texture.bind(String(object.texture), Vector2i.ZERO, Callable()))
		_steps.append(_build_object.bind(object))

## Builds an effect model once its figure, clips and skin are in.
func _build_object(object: Dictionary) -> void:
	var template := ELArchive.key(String(object.model))
	if _figures_failed.has(template) or not is_instance_valid(effects): return
	if _figures_busy.has(template) or not profile.model_resources.has(template) or _texture_busy(String(object.texture)):
		_later.append(_build_object.bind(object))
		return
	effects.prebuild_object(object)

## A particle file, its sprite sheet and its material (`ambient`: the
## battlefield's own particles, drawn with the arena's material).
func _queue_particles(path: String, ambient: bool) -> void:
	if not _once("pfx:%s:%s" % [ELArchive.key(path), ambient]): return
	var cached := ELCombatEffects.cached_file(profile, path)
	if not cached.is_empty():
		_ready_particles(cached, ambient)
		return
	var bytes := profile.read("pfx", ELArchive.key(path))
	if bytes.is_empty(): return
	_run(func(result: Dictionary): result.baked = ELCombatEffects.bake_file(bytes),
		func(result: Dictionary):
			if not result.baked.is_empty(): _ready_particles(ELCombatEffects.store_file(profile, path, result.baked), ambient),
		"Battle particles")

## The file's sprite sheet (with its cell colours when it glows), then its
## glow patches and material.
func _ready_particles(cached: Dictionary, ambient: bool) -> void:
	var file: ELParticleFile = cached.file
	var sheet := ELCombatEffects.sheet_name(file)
	var grid := Vector2i(file.columns, file.rows)
	var wants_tints := file.additive and not cached.has("glow_tints")
	_queue_texture(sheet, grid if wants_tints else Vector2i.ZERO, func(tints: Variant):
		if wants_tints and not tints is PackedVector3Array:
			var texture := profile.texture(sheet)
			tints = ELCombatEffects.known_tints(texture, grid)
			if tints == null and texture != null:
				# A sheet loaded before: its colours from a copy of its image.
				var image := texture.get_image()
				_run(func(result: Dictionary): result.tints = ELCombatEffects.cell_tints(image, grid),
					func(result: Dictionary): _bake_glows(cached, result.tints, ambient), "Battle sheet")
				return
		_bake_glows(cached, tints, ambient))

func _bake_glows(cached: Dictionary, tints: Variant, ambient: bool) -> void:
	var file: ELParticleFile = cached.file
	var frames: Dictionary = cached.frames.duplicate()
	var colours := PackedVector3Array()
	if file.additive: colours = cached.get("glow_tints", tints if tints is PackedVector3Array else PackedVector3Array())
	if frames.is_empty() or (file.additive and colours.is_empty()):
		ELCombatEffects.ready_file(profile, cached, tints, {}, ambient)
		return
	_run(func(result: Dictionary): result.glows = ELCombatEffects.bake_glows(file, frames, colours),
		func(result: Dictionary): ELCombatEffects.ready_file(profile, cached, tints, result.glows, ambient),
		"Battle glow")

# Sounds --------------------------------------------------------------------

func _queue_sound(path: String) -> void:
	var key := ELArchive.key(path)
	if profile.sound_cache.has(key) or not _once("sound:" + key): return
	var bytes := profile.read("sfx", key)
	if bytes.is_empty(): return
	_run(func(result: Dictionary): result.stream = ELAudio.decode_wav(bytes),
		func(result: Dictionary): ELAudio.store_sound(profile, key, result.stream),
		"Battle sound")
