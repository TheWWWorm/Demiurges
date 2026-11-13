class_name ELCombatEffects
extends Node3D
## Combat particle effects, both games. Each named effect of the edition's
## Resources/Effects.xml lists particle systems (a baked .pfx from pfx.res)
## and named points. A point is bound to figures when the effect starts:
## "Target"/"Finish" to the spell's target (or the figures it affected),
## "Start" to the caster. A point's tag picks where on the figure: none = the
## figure's ground position, "cast" = its casting anchor, "soul" = its body
## anchor; the figure's facing turns the effect. A particle with one point
## is drawn about that point (its authored position subtracted); with a begin
## and an end point the native span matrix places the particle centres;
## without points it sits at the arena origin. One copy is drawn per
## bound figure (per pair for two points). The pfx positions are already
## baked in effect space. "reverse" plays the frames backwards. Effects do not
## follow figures after they start and never change the battle.
##
## Figures also have their own particles per animation:
## CreaturesPFX/<model>/<animation>.pfx starts with the clip, sits at the figure
## with its facing and scale, follows it, and stops when the figure's next clip
## starts (heroes use the same folder for their cast animations).
##
## An effect may also name effect models (small animated figures such as rune
## discs or falling rocks), point lights and screen faders. The effect's .fx
## file holds one key per 1/30 s for each named part: a model gets its place
## and opacity from its keys, a particle system its opacity, a light
## its place, range, colour and switch, a fader its colour and strength.
##
## Emitters are pooled MultiMesh nodes; each frame's instance data is built
## once per file and edition (padded to a multiple of 64) and reused; a cyclic
## file's overlapping cycles are combined once per frame phase. Effect models,
## lights and faders are pooled too.
const Table := preload("res://src/duel/combat_sound_table.gd")
## Lazy pools allow whole-board and overlapping cues while bounding malformed input.
const PARTICLE_POOL := 192
const ARENA_PARTICLE_POOL := 48
const OBJECT_CACHE := 24
const OBJECT_POOL := 96
const LIGHT_POOL := 96
const FADER_POOL := 16
## Faders composite over the rendered scene, below sharpening and the HUD.
const FADER_LAYER := -11
## Authored lamps still light these late transparent draws during path tracing.
const LIT_ADDITIVE_LAYER := 1 << 19
## Arena weather rolls once per original scene update (64 ms).
const ARENA_TICK := 0.064
## Floats per decoded .fx key (both kinds): models and particles keep place,
## turn (x y z w), scale and opacity; lights and faders keep place, range or
## strength, two colours and the on switch.
const KEY := 11
const MIN_BUCKET := 64
const PARTICLE_BOUNDS := AABB(Vector3(-64, -16, -64), Vector3(128, 96, 128))
## Decoded particle files (with frame instance data) kept per edition.
const CACHE_BYTES := 96 * 1024 * 1024

## Edition id -> {effect name (lower) -> definition}.
static var _catalogues: Dictionary = {}
## "edition:file" -> {file: ELParticleFile, frames: {frame -> PackedFloat32Array}, bytes}.
static var _files: Dictionary = {}
static var _order: Array[String] = []
static var _cached_bytes := 0
static var _materials: Dictionary = {}
## The two particle shaders (blended, additive) every particle material
## shares: one compile each, instead of one per sprite sheet.
static var _shaders: Dictionary = {}
## Brightness of glowing (additive) particles: above 1 they reach past white,
## for bloom to pick up (path-traced lighting turns this on).
static var glow_level := 1.0
const ARENA_HDR_LIMIT := 1.12

var profile: ELProfile
var edition := ""
var enabled := true
var catalogue: Dictionary = {}
## Pool: each emitter {node, mesh, entry, elapsed, frame, life, reverse, active}.
var emitters: Array[Dictionary] = []
var arena_emitters: Array[Dictionary] = []
## Pools: effect models {node, key, add, opaque, faded, ...}, lights, faders.
var objects: Array[Dictionary] = []
var arena_objects: Array[Dictionary] = []
var lights: Array[Dictionary] = []
var faders: Array[Dictionary] = []
## The one scene light an effect may dim (the arena's sun and ambient light):
## {active, track, elapsed, frame, life, colour, ambient} with the arena's own
## values kept to restore.
var scene_light := {"active": false, "track": PackedFloat32Array(), "elapsed": 0.0, "frame": -1, "life": 0}
var sun: DirectionalLight3D
var sky: Environment
## Point lights can be switched off on their own (they cost a light pass).
var lights_enabled := true:
	set(value):
		if lights_enabled == value: return
		lights_enabled = value
		_sync_arena_secondary()
var _fader_shaders: Dictionary = {}
var _fader_layer: CanvasLayer
## Figure (instance id) -> its running animation emitter.
var _figure_emitters: Dictionary = {}
## Figure animation particle files that exist ("model/clip" -> path or "").
var _animation_files: Dictionary = {}
var _arena: ELArena
var _arena_sound: Callable
var _arena_tick := 0.0
var _arena_chance := RandomNumberGenerator.new()
var _arena_random: Array[Dictionary] = []
## Started effect names (latest 40) and every request (latest 80), for checks.
var started: Array[String] = []
var requested: Array[String] = []
var spawned := 0
var dropped := 0
## Cost of the last _process call and the largest one seen (microseconds).
var last_cost_usec := 0
var peak_cost_usec := 0

func build(data: ELProfile) -> void:
	profile = data
	edition = profile.id
	# Sample attached particles after the figures advance their animations.
	process_priority = 1
	catalogue = load_catalogue(profile)

## Effects.xml of the edition: per effect its particles, points and length.
static func load_catalogue(data: ELProfile) -> Dictionary:
	if _catalogues.has(data.id): return _catalogues[data.id]
	var result := {}
	var path := data.file("Resources/Effects.xml")
	var parser := XMLParser.new()
	if path.is_empty() or parser.open(path) != OK:
		_catalogues[data.id] = result
		return result
	var current: Dictionary = {}
	var point := ""
	while parser.read() == OK:
		var type := parser.get_node_type()
		if type == XMLParser.NODE_TEXT:
			if not point.is_empty() and not current.is_empty():
				var values := parser.get_node_data().strip_edges().split_floats(" ", false)
				if values.size() >= 3: current.points[point].position = Vector3(values[0], values[1], values[2])
			continue
		if type == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "point": point = ""
			continue
		if type != XMLParser.NODE_ELEMENT: continue
		var node := parser.get_node_name()
		if node == "Effect":
			var name := parser.get_named_attribute_value_safe("name")
			current = {"name": name, "particles": [], "objects": [], "lights": [], "faders": [], "scene_lights": [], "points": {}, "frames": 0, "tracks": {}, "events": [], "hit_events": [], "summon_events": []}
			if not name.is_empty(): result[name.to_lower()] = current
		elif current.is_empty():
			continue
		elif node == "point":
			point = parser.get_named_attribute_value_safe("name")
			current.points[point] = {"tag": parser.get_named_attribute_value_safe("teg_name").strip_edges().to_lower(), "position": Vector3.ZERO}
			if parser.is_empty(): point = ""
		elif node == "particle":
			current.particles.append({"file": parser.get_named_attribute_value_safe("file").strip_edges().replace("\\", "/"),
				"reverse": parser.get_named_attribute_value_safe("reverse").strip_edges() == "1",
				"track": parser.get_named_attribute_value_safe("name"),
				"begin": parser.get_named_attribute_value_safe("begin_point"),
				"end": parser.get_named_attribute_value_safe("end_point")})
		elif node == "object":
			var model := parser.get_named_attribute_value_safe("model").strip_edges()
			# Some effects list an empty placeholder object; it draws nothing.
			if not model.is_empty():
				current.objects.append({"model": model,
					"texture": parser.get_named_attribute_value_safe("primaryTexture").strip_edges().replace("\\", "/"),
					"add": parser.get_named_attribute_value_safe("use_add").strip_edges().to_lower() == "yes",
					"track": parser.get_named_attribute_value_safe("name"),
					"begin": parser.get_named_attribute_value_safe("begin_point"),
					"end": parser.get_named_attribute_value_safe("end_point")})
		elif node == "PointLight":
			current.lights.append({"track": parser.get_named_attribute_value_safe("name"),
				"begin": parser.get_named_attribute_value_safe("begin_point"),
				"end": parser.get_named_attribute_value_safe("end_point")})
		elif node == "event":
			# Not every cue deals damage: summons, taps, shifts and KeyFrame
			# use other callbacks. Hit names vary across the authored effects.
			var phase := parser.get_named_attribute_value_safe("phase").strip_edges()
			if phase.is_valid_int():
				current.events.append(int(phase))
				var cue := parser.get_named_attribute_value_safe("name").strip_edges().to_lower().replace(" ", "")
				if cue in ["monstershit", "monsterhit", "hit", "popadanie"]:
					current.hit_events.append(int(phase))
				elif cue in ["monstersummon", "keyframe"]:
					current.summon_events.append(int(phase))
		elif node == "DirectLight":
			current.scene_lights.append({"track": parser.get_named_attribute_value_safe("name")})
		elif node == "ScreenFader":
			current.faders.append({"track": parser.get_named_attribute_value_safe("name"),
				"add": parser.get_named_attribute_value_safe("use_add").strip_edges().to_lower() == "yes"})
	for key: String in result:
		result[key].tracks = fx_tracks(data, String(result[key].name))
		result[key].frames = fx_frames(data, String(result[key].name))
	_catalogues[data.id] = result
	return result

## Delay of a named effect's authored MonstersHit/Popadanie callback. This
## also covers effects triggered directly by damage, not by a cast/ability.
static func effect_hit_delay(data: ELProfile, effect: String) -> float:
	var events: Array = load_catalogue(data).get(effect.to_lower(), {}).get("hit_events", [])
	return float(events.min()) / ELParticleFile.FPS if not events.is_empty() else 0.0

## Seconds from the start of a cast's effects to the moment the figures it
## hits react: the first effect of the card that marks a hit cue (not a summon,
## tap, shift or keyframe). 0 when none does.
static func hit_delay(data: ELProfile, card: String) -> float:
	var known := load_catalogue(data)
	for effect: Variant in Table.card_effects(data, card):
		var events: Array = known.get(String(effect).to_lower(), {}).get("hit_events", [])
		if not events.is_empty(): return float(events.min()) / ELParticleFile.FPS
	return 0.0

## Seconds from the start of a summon's effects to the moment its creature
## appears: the first MonsterSummon or KeyFrame cue of the card's effects.
static func summon_delay(data: ELProfile, card: String) -> float:
	var known := load_catalogue(data)
	for effect: Variant in Table.card_effects(data, card):
		var events: Array = known.get(String(effect).to_lower(), {}).get("summon_events", [])
		if not events.is_empty(): return float(events.min()) / ELParticleFile.FPS
	return 0.0

## Creature/enchantment ability animations can also have their own hit cue
## (EL2 FingusSpit MonstersHit at frame 10). Only the hit presentation waits;
## rules continue resolving synchronously in ELDuel.
static func ability_hit_delay(data: ELProfile, card: String) -> float:
	var known := load_catalogue(data)
	for item: Array in Table.ability_effects(data.id, card):
		if item.is_empty(): continue
		var events: Array = known.get(String(item[0]).to_lower(), {}).get("hit_events", [])
		if not events.is_empty(): return float(events.min()) / ELParticleFile.FPS
	return 0.0

## Length of an effect in frames: the longest key track of its .fx file
## (point lights 23 bytes a key, scene lights 19, sounds 21, objects 44). 0 when absent.
static func fx_frames(data: ELProfile, effect: String) -> int:
	if not data.archives.has("fx"): return 0
	var bytes := data.read("fx", ELArchive.key(effect + ".fx"))
	if bytes.size() < 12: return 0
	var at := 4
	var frames := 0
	while at + 10 <= bytes.size() - 8:
		var tag := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		var name_size := bytes.decode_u16(at + 8)
		var key := {"PLIT": 23, "DLIT": 19, "SOUN": 21, "OBJC": 44}.get(tag, 0) as int
		if key > 0: frames = maxi(frames, (size - name_size) / key)
		at += 10 + size
	return frames

## Decoded key tracks of an effect's .fx file: track name -> KEY floats per
## frame. Object/particle keys (44 bytes): place, turn stored x y z w, scale,
## transparency (kept as opacity = 1 - value). Light/fader keys (23 bytes):
## place, range (a fader's strength), two RGB byte colours, on byte.
static func fx_tracks(data: ELProfile, effect: String) -> Dictionary:
	var result := {}
	if not data.archives.has("fx"): return result
	var bytes := data.read("fx", ELArchive.key(effect + ".fx"))
	if bytes.size() < 12: return result
	var at := 4
	while at + 10 <= bytes.size() - 8:
		var tag := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		var name_size := bytes.decode_u16(at + 8)
		if name_size > size or at + 10 + size > bytes.size(): break
		var name := bytes.slice(at + 10, at + 10 + name_size).get_string_from_ascii()
		var body := at + 10 + name_size
		var count := 0
		var track := PackedFloat32Array()
		if tag == "OBJC":
			count = (size - name_size) / 44
			track.resize(count * KEY)
			for k in count:
				var o := body + k * 44
				for f in 10: track[k * KEY + f] = bytes.decode_float(o + f * 4)
				track[k * KEY + 10] = 1.0 - bytes.decode_float(o + 40)
		elif tag == "PLIT":
			count = (size - name_size) / 23
			track.resize(count * KEY)
			for k in count:
				var o := body + k * 23
				for f in 4: track[k * KEY + f] = bytes.decode_float(o + f * 4)
				for c in 6: track[k * KEY + 4 + c] = bytes[o + 16 + c] / 255.0
				track[k * KEY + 10] = float(bytes[o + 22])
		elif tag == "DLIT":
			# Scene light keys (19 bytes): direction, two RGB byte colours, on byte.
			count = (size - name_size) / 19
			track.resize(count * KEY)
			for k in count:
				var o := body + k * 19
				for f in 3: track[k * KEY + f] = bytes.decode_float(o + f * 4)
				for c in 6: track[k * KEY + 4 + c] = bytes[o + 12 + c] / 255.0
				track[k * KEY + 10] = float(bytes[o + 18])
		if count > 0 and not name.is_empty(): result[name] = track
		at += 10 + size
	return result

func definition(effect: String) -> Dictionary:
	return catalogue.get(effect.to_lower(), {})

## Starts a figure's own particles with each of its clips from now on.
func attach(model: ELModel) -> void:
	if not model.animation_started.is_connected(_figure_animation):
		model.animation_started.connect(_figure_animation.bind(model))
	if not model.clip.is_empty(): _figure_animation(model.clip, model)

## Path of a figure's particles for a clip ("cidle" -> CreaturesPFX/<model>/idle.pfx), or "".
func animation_file(model: ELModel, clip: String) -> String:
	return figure_particles(model.template, clip)

## Path of a figure model's particles for a clip (see animation_file), or "".
func figure_particles(template: String, clip: String) -> String:
	var key := template + "/" + clip
	if _animation_files.has(key): return _animation_files[key]
	var path := "CreaturesPFX/%s/%s.pfx" % [template, clip.substr(1) if clip.length() > 1 and clip[0] in ["c", "u"] else clip]
	var archive: ELArchive = profile.archives.get("pfx")
	var found := path if archive != null and archive.has(ELArchive.key(path)) else ""
	_animation_files[key] = found
	return found

func _figure_animation(clip: String, model: ELModel) -> void:
	var id := model.get_instance_id()
	var previous: Variant = _figure_emitters.get(id)
	if previous != null:
		_figure_emitters.erase(id)
		if previous.following and is_same(previous.follow, model): _release(previous)
	if not enabled or not is_instance_valid(model): return
	# A summoned figure waits hidden for its summoning effect; its own
	# particles start when it appears (see attach), not at its home before.
	if not model.is_visible_in_tree(): return
	var path := animation_file(model, clip)
	if path.is_empty(): return
	requested.append(path)
	if requested.size() > 80: requested.pop_front()
	var emitter := _spawn(path, false, 0, _figure_transform(model), model)
	if emitter.is_empty(): return
	_figure_emitters[id] = emitter

## The figure's place, facing and scale.
static func _figure_transform(model: Node3D) -> Transform3D:
	var basis := model.global_transform.basis
	return Transform3D(basis.orthonormalized().scaled(model.scale), model.global_position)

func set_enabled(value: bool) -> void:
	if enabled == value: return
	enabled = value
	if value:
		if is_instance_valid(_arena): _start_arena()
	else:
		for emitter in emitters: _release(emitter)
		for emitter in arena_emitters: _release(emitter)
		_arena_random.clear()
		for list: Array[Dictionary] in [objects, arena_objects, lights, faders]:
			for item in list: _hide(item, false)
		_sync_arena_secondary()
		_end_scene_light()

## Space finishes spell and trigger effects. The arena and the particles
## attached to figure clips are exempt in both original games.
func finish_transients() -> void:
	for emitter in emitters:
		if emitter.active and not emitter.following: _release(emitter)
	for pool: Array[Dictionary] in [objects, lights, faders]:
		for item in pool:
			if item.active: _hide(item, false)
	_sync_arena_secondary()
	_end_scene_light(lights_enabled)

## The arena's sun and ambient light that scene-light effects dim.
func set_scene(light: DirectionalLight3D, environment: Environment) -> void:
	_end_scene_light()
	sun = light
	sky = environment

## Scenery FX and spell FX have separate pools. ParticlesCP gives their world
## origins. A linked particle follows its prop's visibility, with that same
## authored origin.
func set_arena(arena: ELArena, sound: Callable) -> void:
	if is_instance_valid(_arena) and _arena != arena: _arena.set_secondary_lights(PackedFloat32Array())
	for emitter in arena_emitters: _release(emitter)
	for item in arena_objects: _hide(item)
	_arena_random.clear()
	_arena_tick = 0.0
	_arena = arena
	_arena_sound = sound
	set_scene(arena.light, arena.environment_settings)
	_sync_arena_secondary()
	if enabled: _start_arena()

func _start_arena() -> void:
	var row := _arena.definition
	var particles: Variant = row.get("Particles", [])
	var paths: Array = particles if particles is Array else [particles]
	var positions: Array = row.get("ParticlesCP", [])
	var links: Array = row.get("ParticlesObjectLinks", [])
	var times: Array = row.get("ParticlesRandomPlayTime", [])
	var sounds: Array = row.get("ParticlesSnd", [])
	var looped := 0
	for i in paths.size():
		var path := ELArchive.key(String(paths[i]))
		var where := Transform3D.IDENTITY
		var at := i * 3
		if at + 2 < positions.size():
			where.origin = ELFigure.vector(Vector3(positions[at], positions[at + 1], positions[at + 2]))
		if path.ends_with(".fx"):
			var name := path.get_file().get_basename()
			var entry := definition(name)
			for object: Dictionary in entry.get("objects", []):
				var track: PackedFloat32Array = entry.tracks.get(object.track, PackedFloat32Array())
				if not track.is_empty(): _spawn_object(object, track, where, true, name == "etherarena")
		elif i < times.size() and float(times[i]) > 0.0:
			_arena_random.append({"path": path, "where": where, "chance": ARENA_TICK / float(times[i]),
				"sound": String(sounds[i]) if i < sounds.size() else ""})
		else:
			var emitter := _spawn(path, false, 0, where, null, true)
			if emitter.is_empty(): continue
			emitter.loop = true
			_stagger_arena_loop(emitter, looped)
			looped += 1
			if i < links.size() and int(links[i]) >= 0:
				emitter.visibility_link = _arena.scenery(int(links[i]))

## An arena's looping scenery particles (the Circle of Time's five fires,
## the Dungeon's torches) share a few files and so one cycle. Started in the
## same frame, they breathe in step and all restart at once: their large glow
## cores shrink together at each cycle's start, so the whole battlefield's
## glow dimmed and flared every few seconds. Each starts at its own point of
## the cycle instead (golden-ratio steps spread any number evenly), a cyclic
## file already past its first pass so the earlier cycle's tail is drawn too.
func _stagger_arena_loop(emitter: Dictionary, index: int) -> void:
	var file: ELParticleFile = emitter.entry.file
	var period := file.loop_end if file.loop_end > 0 else file.frames
	var start := (file.loop_end if file.loop_end > 0 else 0) + int(fposmod(index * 0.618034, 1.0) * period)
	emitter.elapsed = (start + 0.5) / ELParticleFile.FPS
	_draw(emitter, start)

func _step_arena_weather(delta: float) -> void:
	if _arena_random.is_empty(): return
	_arena_tick += delta
	while _arena_tick >= ARENA_TICK:
		_arena_tick -= ARENA_TICK
		for cue in _arena_random:
			if _arena_chance.randf() >= float(cue.chance): continue
			if _spawn(cue.path, false, 0, cue.where, null, true).is_empty(): continue
			if _arena_sound.is_valid() and not String(cue.sound).is_empty(): _arena_sound.call(cue.sound)

## Starts the effects a cast of `card` names (summons: the colour's effect).
## `bindings`: point name -> figures (ELModel), see the class description.
func cast(card: String, bindings: Dictionary) -> void:
	for effect: Variant in Table.card_effects(profile, card): play(String(effect), bindings)

func trigger(card: String, bindings: Dictionary) -> void:
	for effect: Variant in Table.trigger_effects(edition, card): play(String(effect), bindings)

## Starts one named effect; returns the number of parts started (particle
## copies, effect models, lights and faders).
func play(effect: String, bindings: Dictionary) -> int:
	requested.append(effect)
	if requested.size() > 80: requested.pop_front()
	if not enabled: return 0
	var entry := definition(effect)
	if entry.is_empty(): return 0
	var count := 0
	var tracks: Dictionary = entry.tracks
	for particle: Dictionary in entry.particles:
		var track: PackedFloat32Array = tracks.get(particle.track, PackedFloat32Array())
		var particle_span := not String(particle.begin).is_empty() and not String(particle.end).is_empty()
		for where: Transform3D in _copies(entry, particle, bindings, particle_span):
			var emitter := _spawn(String(particle.file), bool(particle.reverse), int(entry.frames), where, null, false, particle_span)
			if emitter.is_empty(): continue
			count += 1
			if not track.is_empty(): _track_emitter(emitter, track)
	for object: Dictionary in entry.objects:
		var track: PackedFloat32Array = tracks.get(object.track, PackedFloat32Array())
		if track.is_empty(): continue
		for where: Transform3D in _copies(entry, object, bindings):
			if _spawn_object(object, track, where): count += 1
	if lights_enabled:
		var lights_started := false
		for light: Dictionary in entry.lights:
			var track: PackedFloat32Array = tracks.get(light.track, PackedFloat32Array())
			if track.is_empty(): continue
			for where: Transform3D in _copies(entry, light, bindings, true):
				if _spawn_light(track, where):
					count += 1
					lights_started = true
		if lights_started: _sync_arena_secondary()
	if lights_enabled and is_instance_valid(sun):
		for light: Dictionary in entry.scene_lights:
			var track: PackedFloat32Array = tracks.get(light.track, PackedFloat32Array())
			if track.size() >= KEY and _start_scene_light(track): count += 1
	for fader: Dictionary in entry.faders:
		var track: PackedFloat32Array = tracks.get(fader.track, PackedFloat32Array())
		if not track.is_empty() and _spawn_fader(track, bool(fader.add)): count += 1
	if count > 0:
		started.append(entry.name)
		if started.size() > 40: started.pop_front()
	return count

## One placement per bound figure (per pair for two points) of an effect part.
static func _copies(entry: Dictionary, part: Dictionary, bindings: Dictionary, native_span := false) -> Array[Transform3D]:
	var begin := String(part.begin)
	var finish := String(part.end)
	var starts: Array = [null] if begin.is_empty() else _figures(bindings, begin)
	var ends: Array = [null] if finish.is_empty() else _figures(bindings, finish)
	var result: Array[Transform3D] = []
	for a: Variant in starts:
		for b: Variant in ends: result.append(placement(entry, begin, a, finish, b, native_span))
	return result

## Figures bound to a point; "Finish" and "Target" share the target binding.
static func _figures(bindings: Dictionary, point: String) -> Array:
	var list: Array = bindings.get(point, [])
	if list.is_empty() and point in ["Finish", "Target"]: list = bindings.get("Target" if point == "Finish" else "Finish", [])
	var result: Array = []
	for figure: Variant in list:
		if figure is Node3D and is_instance_valid(figure): result.append(figure)
	return result

## Effect-space to world transform for one copy.
static func placement(entry: Dictionary, begin: String, a: Variant, finish: String, b: Variant, native_span := false) -> Transform3D:
	var points: Dictionary = entry.points
	if a == null and b == null: return Transform3D.IDENTITY
	if a == null or b == null:
		var name := begin if a != null else finish
		var figure: Node3D = a if a != null else b
		var point: Dictionary = points.get(name, {"tag": "", "position": Vector3.ZERO})
		var basis := figure.global_transform.basis.orthonormalized()
		var origin := anchor(figure, String(point.tag))
		return Transform3D(basis, origin - basis * ELFigure.vector(point.position))
	var p: Dictionary = points.get(begin, {"tag": "", "position": Vector3.ZERO})
	var q: Dictionary = points.get(finish, {"tag": "", "position": Vector3.ZERO})
	var authored_from := ELFigure.vector(p.position)
	var authored := ELFigure.vector(q.position) - authored_from
	var from := anchor(a, String(p.tag))
	var actual := anchor(b, String(q.tag)) - from
	if native_span: return _spell_span_placement(authored_from, authored, from, actual)
	# A degenerate authored segment only moves the effect to the begin point.
	if authored.length() < 0.001 or actual.length() < 0.001: return Transform3D(Basis.IDENTITY, from)
	var turn := Basis(Quaternion(authored.normalized(), actual.normalized()))
	var basis := turn.scaled(Vector3.ONE * (actual.length() / authored.length()))
	return Transform3D(basis, from - basis * authored_from)

## Native two-point spell matrix (EL1 0x453b70, EL2 0x45b37f).
static func _spell_span_placement(authored_from: Vector3, authored: Vector3, from: Vector3, actual: Vector3) -> Transform3D:
	var authored_length := authored.length()
	var actual_length := actual.length()
	if authored_length < 0.001 or actual_length == 0.0:
		return Transform3D(Basis.IDENTITY, from - authored_from)
	var authored_flat := Vector2(authored.x, authored.z)
	var actual_flat := Vector2(actual.x, actual.z)
	var source_yaw := authored_flat.normalized() if authored_flat != Vector2.ZERO else Vector2.RIGHT
	var to_x := Basis(Vector3(source_yaw.x, 0, -source_yaw.y), Vector3.UP, Vector3(source_yaw.y, 0, source_yaw.x))
	var authored_height := authored.y
	var actual_height := actual.y
	var authored_run := authored_flat.length()
	var actual_run := actual_flat.length()
	var pitch_cos := (authored_run * actual_run + authored_height * actual_height) / (authored_length * actual_length)
	var pitch_sin_sq := 1.0 - pitch_cos * pitch_cos
	var pitch_sin := sqrt(pitch_sin_sq) if pitch_sin_sq >= 0.001 else 0.0
	if authored_height * actual_run > actual_height * authored_run: pitch_sin = -pitch_sin
	var pitch := Basis(Vector3(pitch_cos, pitch_sin, 0), Vector3(-pitch_sin, pitch_cos, 0), Vector3.BACK)
	# The native final yaw divides by the full span, even on a steep shot.
	var target_yaw := actual_flat / actual_length
	var from_x := Basis(Vector3(target_yaw.x, 0, target_yaw.y), Vector3.UP, Vector3(-target_yaw.y, 0, target_yaw.x))
	var basis := (from_x * pitch * to_x).scaled(Vector3.ONE * (actual_length / authored_length))
	return Transform3D(basis, from - basis * authored_from)

## World position of a figure's point: ground position, or its "cast"/"soul"
## anchor where the figure's current animation places it. A figure whose clip
## leaves the anchor at its feet (or does not move it) gets an estimate from
## its height: the soul at 60 %, the casting point at 75 % and a little in front.
static func anchor(figure: Node3D, tag: String) -> Vector3:
	if tag.is_empty() or not (figure is ELModel): return figure.global_position
	var model: ELModel = figure
	var part: Node3D = model.parts.get(tag)
	if part != null and model.clips.get(model.clip, {}).has(tag):
		var mesh: Mesh = model._mesh_cache.get("base/" + tag)
		var at := part.global_transform * mesh.get_aabb().get_center() if mesh != null else part.global_position
		# Some figures keep the anchor at their feet in this clip.
		if at.y - model.global_position.y > 0.15: return at
	var top := model.global_position.y
	for node: MeshInstance3D in model.parts.values():
		if node.mesh != null and node.visible and not (String(node.name) in ELModel.EFFECT_ANCHORS): top = maxf(top, (node.global_transform * node.mesh.get_aabb()).end.y)
	var height := top - model.global_position.y
	if tag == "soul": return model.global_position + Vector3(0, height * 0.6, 0)
	var forward := model.global_transform.basis.z.normalized()
	return model.global_position + Vector3(0, height * 0.75, 0) + forward * 0.5

## Starts a pooled emitter. Attached particles use the figure's animation frame.
func _spawn(path: String, reverse: bool, effect_frames: int, where: Transform3D, follow: ELModel = null, ambient := false, particle_span := false) -> Dictionary:
	var cached := _file(profile, path)
	if cached.is_empty(): return {}
	var file: ELParticleFile = cached.file
	var material := _material(profile, file, ambient)
	if material == null: return {}
	if file.additive and not cached.has("glow_tints"):
		var atlas := material.get_shader_parameter("atlas") as Texture2D
		cached.glow_tints = _atlas_cell_tints(atlas, Vector2i(file.columns, file.rows))
	var emitter := _free_emitter(ambient)
	if emitter.is_empty():
		if not ambient: dropped += 1
		return {}
	var node: MultiMeshInstance3D = emitter.node
	node.material_override = material
	node.transform = Transform3D(Basis.IDENTITY, where.origin) if particle_span else where
	emitter.centre_basis = where.basis if particle_span else Basis.IDENTITY
	node.custom_aabb = PARTICLE_BOUNDS
	if particle_span:
		node.custom_aabb = PARTICLE_BOUNDS.merge(Transform3D(where.basis, Vector3.ZERO) * PARTICLE_BOUNDS)
	node.visible = true
	emitter.track = PackedFloat32Array()
	emitter.opacity = 1.0
	emitter.entry = cached
	emitter.elapsed = 0.0
	emitter.frame = -1
	emitter.reverse = reverse
	emitter.follow = follow
	emitter.following = follow != null
	emitter.visibility_link = null
	emitter.loop = false
	emitter.life = file.frames
	if file.loop_end > 0 and follow == null: emitter.life = maxi(effect_frames, 1)
	emitter.active = true
	emitter.mesh.visible_instance_count = 0
	if not ambient: spawned += 1
	_draw(emitter, roundi(follow.frame) if follow != null else 0)
	return emitter

func _free_emitter(ambient: bool) -> Dictionary:
	var pool := arena_emitters if ambient else emitters
	for emitter in pool:
		if not emitter.active: return emitter
	if pool.size() >= (ARENA_PARTICLE_POOL if ambient else PARTICLE_POOL): return {}
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh.mesh = quad
	mesh.instance_count = MIN_BUCKET
	mesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	var emitter := {"node": node, "mesh": mesh, "entry": {}, "elapsed": 0.0, "frame": -1, "life": 0, "reverse": false, "active": false, "follow": null, "following": false,
		"track": PackedFloat32Array(), "opacity": 1.0, "own": null, "glow": []}
	pool.append(emitter)
	return emitter

func _release(emitter: Dictionary) -> void:
	emitter.active = false
	emitter.entry = {}
	emitter.follow = null
	emitter.visibility_link = null
	emitter.following = false
	emitter.track = PackedFloat32Array()
	emitter.node.visible = false
	emitter.mesh.visible_instance_count = 0

func active_count() -> int:
	var count := 0
	for emitter in emitters:
		if emitter.active: count += 1
	return count

func _process(delta: float) -> void:
	var clock := Time.get_ticks_usec()
	_step_arena_weather(delta)
	for pool: Array[Dictionary] in [emitters, arena_emitters]:
		for emitter in pool:
			if emitter.active: _step_emitter(emitter, delta)
	for item in objects:
		if item.active: _step_object(item, delta)
	for item in arena_objects:
		if item.active: _step_object(item, delta)
	var lights_changed := false
	for item in lights:
		if item.active and _step_light(item, delta): lights_changed = true
	if lights_changed: _sync_arena_secondary()
	for item in faders:
		if item.active: _step_fader(item, delta)
	if scene_light.active: _step_scene_light(delta)
	last_cost_usec = Time.get_ticks_usec() - clock
	peak_cost_usec = maxi(peak_cost_usec, last_cost_usec)

func _step_emitter(emitter: Dictionary, delta: float) -> void:
	# A freed figure compares equal to null, so the flag says whether it follows.
	if emitter.following:
		if not is_instance_valid(emitter.follow):
			_release(emitter)
			return
		var model: ELModel = emitter.follow
		emitter.node.transform = _figure_transform(model)
		emitter.node.visible = model.is_visible_in_tree()
		var animation_frame := roundi(model.frame)
		if animation_frame != int(emitter.frame): _draw(emitter, animation_frame)
		return
	emitter.elapsed += delta
	var frame := int(emitter.elapsed * ELParticleFile.FPS)
	if not emitter.loop and frame >= int(emitter.life):
		_release(emitter)
		return
	if is_instance_valid(emitter.visibility_link): emitter.node.visible = emitter.visibility_link.is_visible_in_tree()
	if emitter.loop and emitter.entry.file.loop_end == 0: frame %= int(emitter.life)
	if frame != int(emitter.frame):
		if not emitter.track.is_empty(): _apply_emitter_track(emitter, frame)
		_draw(emitter, frame)

## Spell particles keep their placement matrix. The native matrix draw reads
## billboard size from the particle file and opacity from the .fx track.
func _track_emitter(emitter: Dictionary, track: PackedFloat32Array) -> void:
	emitter.track = track
	var fades := false
	for k in track.size() / KEY:
		if track[k * KEY + 10] < 0.999: fades = true
	if fades:
		var shared: ShaderMaterial = emitter.node.material_override
		var own: ShaderMaterial = emitter.own
		if own == null:
			own = ShaderMaterial.new()
			emitter.own = own
		own.shader = shared.shader
		own.render_priority = shared.render_priority
		own.set_shader_parameter("atlas", shared.get_shader_parameter("atlas"))
		own.set_shader_parameter("grid", shared.get_shader_parameter("grid"))
		own.set_shader_parameter("glow", shared.get_shader_parameter("glow"))
		emitter.node.material_override = own
	emitter.opacity = -1.0
	_apply_emitter_track(emitter, 0)

func _apply_emitter_track(emitter: Dictionary, frame: int) -> void:
	var track: PackedFloat32Array = emitter.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var opacity := clampf(track[k + 10], 0.0, 1.0)
	if opacity != float(emitter.opacity):
		emitter.opacity = opacity
		var own: ShaderMaterial = emitter.own
		if own != null and is_same(emitter.node.material_override, own): own.set_shader_parameter("opacity", opacity)
	emitter.node.visible = opacity > 0.004

## Effect-space key transform: place, turn and scale (z up -> y up).
static func _key_transform(track: PackedFloat32Array, k: int) -> Transform3D:
	var axis := ELFigure.vector(Vector3(track[k + 3], track[k + 4], track[k + 5]))
	var turn := Quaternion(axis.x, axis.y, axis.z, track[k + 6])
	var basis := Basis.IDENTITY if turn.length_squared() < 0.0001 else Basis(turn.normalized())
	var scale := Vector3(track[k + 7], track[k + 9], track[k + 8])
	return Transform3D(basis.scaled_local(scale), ELFigure.vector(Vector3(track[k], track[k + 1], track[k + 2])))

func _spawn_object(object: Dictionary, track: PackedFloat32Array, where: Transform3D, ambient := false, ether_vent := false) -> bool:
	var item := _free_object(object, arena_objects if ambient else objects, OBJECT_CACHE if ambient else OBJECT_POOL)
	if item.is_empty():
		if not ambient: dropped += 1
		return false
	item.where = where
	item.track = track
	item.elapsed = 0.0
	item.frame = -1
	item.life = track.size() / KEY
	item.loop = ambient
	item.ether_vent = ether_vent
	item.opacity = -1.0
	item.active = true
	var model: ELModel = item.node
	model.play("cidle")
	_apply_object(item, 0)
	if ether_vent: _set_vent_glow(item)
	return true

## Cache common models and reuse spare entries before growing to the burst limit.
func _free_object(object: Dictionary, pool: Array[Dictionary], limit: int) -> Dictionary:
	var key := "%s|%s|%s" % [String(object.model).to_lower(), String(object.texture).to_lower(), object.add]
	var spare := -1
	for i in pool.size():
		if pool[i].active: continue
		if pool[i].key == key: return pool[i]
		if spare < 0: spare = i
	if pool.size() >= limit and spare < 0: return {}
	var item := _build_object(object, key)
	if item.is_empty(): return {}
	if spare < 0 or pool.size() < OBJECT_CACHE:
		pool.append(item)
	else:
		var old: Node = pool[spare].node
		remove_child(old)
		old.queue_free()
		pool[spare] = item
	return item

func _build_object(object: Dictionary, key: String) -> Dictionary:
	var model := ELModel.new()
	model.idle_specials = false
	if not model.build(profile, String(object.model), String(object.texture)):
		model.free()
		return {}
	var texture := profile.texture(String(object.texture))
	var add := bool(object.add)
	var faded := StandardMaterial3D.new()
	faded.albedo_texture = texture
	faded.cull_mode = BaseMaterial3D.CULL_DISABLED
	faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	faded.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var additive_materials := {}
	var magic_materials := {}
	# Effect models are light and glow shapes: they cast no shadow.
	for node: MeshInstance3D in model.parts.values():
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := node.material_override as StandardMaterial3D
		if material == null: continue
		if add:
			# The native additive pass changes the destination blend only.
			if not additive_materials.has(material):
				var blend := material.duplicate() as StandardMaterial3D
				blend.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				blend.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				blend.texture_filter = faded.texture_filter
				additive_materials[material] = blend
			node.material_override = additive_materials[material]
			if material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				node.layers |= LIT_ADDITIVE_LAYER
		elif material.has_meta(ELFigure.AUTHORED_FULLBRIGHT):
			var blend := material.duplicate() as StandardMaterial3D
			blend.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			magic_materials[node] = [material, blend]
	model.visible = false
	add_child(model)
	return {"node": model, "key": key, "add": add, "opaque": ELFigure.material(texture), "faded": faded, "shown": null,
		"magic_materials": magic_materials, "additive_materials": additive_materials.values(),
		"active": false, "elapsed": 0.0, "frame": -1, "life": 0, "where": Transform3D.IDENTITY, "track": PackedFloat32Array(), "opacity": 1.0}

func _step_object(item: Dictionary, delta: float) -> void:
	item.elapsed += delta
	var frame := int(item.elapsed * ELParticleFile.FPS)
	if frame >= int(item.life):
		if not item.loop:
			_hide(item)
			return
		frame %= int(item.life)
	if frame != int(item.frame): _apply_object(item, frame)

func _apply_object(item: Dictionary, frame: int) -> void:
	item.frame = frame
	var track: PackedFloat32Array = item.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var model: Node3D = item.node
	model.transform = item.where * _key_transform(track, k)
	var opacity := clampf(track[k + 10], 0.0, 1.0)
	# Stay in the blended pass through the brightest key and across the loop.
	if item.ether_vent: opacity = lerpf(0.24, 0.44, opacity)
	model.visible = opacity > 0.004
	if opacity == float(item.opacity): return
	item.opacity = opacity
	if item.add:
		for material: StandardMaterial3D in item.additive_materials: material.albedo_color.a = opacity
		return
	var blend := opacity < 0.999
	var material: StandardMaterial3D = item.faded if blend else item.opaque
	material.albedo_color.a = opacity if blend else 1.0
	for variants: Array in item.magic_materials.values(): variants[1].albedo_color.a = opacity
	if is_same(item.shown, material): return
	item.shown = material
	for node: MeshInstance3D in model.parts.values():
		if node.mesh == null: continue
		var variants: Array = item.magic_materials.get(node, [])
		node.material_override = material if variants.is_empty() else variants[int(blend)]

func _spawn_light(track: PackedFloat32Array, where: Transform3D) -> bool:
	var item: Dictionary = {}
	for light in lights:
		if not light.active:
			item = light
			break
	if item.is_empty():
		if lights.size() >= LIGHT_POOL:
			dropped += 1
			return false
		var node := OmniLight3D.new()
		node.shadow_enabled = false
		node.visible = false
		add_child(node)
		item = {"node": node, "active": false, "elapsed": 0.0, "frame": -1, "life": 0, "where": Transform3D.IDENTITY, "track": PackedFloat32Array()}
		lights.append(item)
	item.where = where
	item.track = track
	item.elapsed = 0.0
	item.life = track.size() / KEY
	item.active = true
	_apply_light(item, 0, false)
	return true

func _step_light(item: Dictionary, delta: float) -> bool:
	item.elapsed += delta
	var frame := int(item.elapsed * ELParticleFile.FPS)
	if frame >= int(item.life) or not lights_enabled:
		_hide(item, false)
		return true
	if frame == int(item.frame): return false
	_apply_light(item, frame, false)
	return true

## The spell matrix moves the light center. The key's radius stays in world units.
func _apply_light(item: Dictionary, frame: int, sync_secondary := true) -> void:
	item.frame = frame
	var track: PackedFloat32Array = item.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var where: Transform3D = item.where
	var node: OmniLight3D = item.node
	node.position = where * ELFigure.vector(Vector3(track[k], track[k + 1], track[k + 2]))
	var reach := track[k + 3]
	node.omni_range = maxf(reach, 0.01)
	# Native secondary vertex light stays independent of the diffuse OmniLight.
	item.secondary = Vector4(track[k + 7], track[k + 8], track[k + 9], reach) if track[k + 10] > 0.5 and reach > 0.0 else Vector4.ZERO
	node.light_color = Color(track[k + 4], track[k + 5], track[k + 6])
	node.visible = track[k + 10] > 0.5 and track[k + 3] > 0.01 and track[k + 4] + track[k + 5] + track[k + 6] > 0.004
	if sync_secondary: _sync_arena_secondary()

## Separate original vertex-light colour and reach, independent of OmniLight visibility.
func secondary_light_sources() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	if not lights_enabled or not is_visible_in_tree(): return data
	for item: Dictionary in lights:
		if not item.active: continue
		var colour: Vector4 = item.get("secondary", Vector4.ZERO)
		if colour.x + colour.y + colour.z <= 0.0: continue
		var p: Vector3 = item.node.global_position
		data.append_array([p.x, p.y, p.z, 0.0, colour.x, colour.y, colour.z, colour.w])
	return data

func _sync_arena_secondary() -> void:
	if is_instance_valid(_arena): _arena.set_secondary_lights(secondary_light_sources())

func _spawn_fader(track: PackedFloat32Array, add: bool) -> bool:
	var item: Dictionary = {}
	for fader in faders:
		if not fader.active:
			item = fader
			break
	if item.is_empty():
		if faders.size() >= FADER_POOL:
			dropped += 1
			return false
		if _fader_layer == null:
			_fader_layer = CanvasLayer.new()
			_fader_layer.layer = FADER_LAYER
			_fader_layer.visible = is_visible_in_tree()
			add_child(_fader_layer)
		var node := ColorRect.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.set_anchors_preset(Control.PRESET_FULL_RECT)
		node.visible = false
		var material := ShaderMaterial.new()
		node.material = material
		_fader_layer.add_child(node)
		item = {"node": node, "material": material, "active": false, "elapsed": 0.0, "frame": -1, "life": 0, "track": PackedFloat32Array()}
		faders.append(item)
	item.material.shader = _fader_shader(add)
	item.track = track
	item.elapsed = 0.0
	item.life = track.size() / KEY
	item.active = true
	_apply_fader(item, 0)
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_instance_valid(_fader_layer):
		_fader_layer.visible = is_visible_in_tree()

func _fader_shader(add: bool) -> Shader:
	var key := "add" if add else "mix"
	if not _fader_shaders.has(key):
		var shader := Shader.new()
		shader.code = FADER_SHADER.replace("BLEND", "blend_" + key)
		_fader_shaders[key] = shader
	return _fader_shaders[key]

func _step_fader(item: Dictionary, delta: float) -> void:
	item.elapsed += delta
	var frame := int(item.elapsed * ELParticleFile.FPS)
	if frame >= int(item.life):
		_hide(item)
		return
	if frame != int(item.frame): _apply_fader(item, frame)

## The native fader packs the second RGB and the range as an ARGB vertex.
func _apply_fader(item: Dictionary, frame: int) -> void:
	item.frame = frame
	var track: PackedFloat32Array = item.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var alpha := int(clampf(track[k + 3], 0.0, 1.0) * 255.0)
	var red := int(track[k + 7] * 255.0)
	var green := int(track[k + 8] * 255.0)
	var blue := int(track[k + 9] * 255.0)
	item.material.set_shader_parameter("colour", Color8(red, green, blue, alpha))
	item.node.visible = track[k + 10] > 0.5 and alpha > 0

## The first DLIT colour multiplies the arena's sun colour. The second replaces
## its ambient colour. The sun keeps its arena direction and shadows.
func _start_scene_light(track: PackedFloat32Array) -> bool:
	if not scene_light.active:
		scene_light.colour = sun.light_color
		scene_light.ambient = sky.ambient_light_color if sky != null else Color.BLACK
	scene_light.active = true
	scene_light.track = track
	scene_light.elapsed = 0.0
	scene_light.frame = -1
	scene_light.life = track.size() / KEY
	_apply_scene_light(0)
	return true

func _step_scene_light(delta: float) -> void:
	scene_light.elapsed += delta
	var frame := int(scene_light.elapsed * ELParticleFile.FPS)
	if not lights_enabled or not is_instance_valid(sun):
		_end_scene_light()
		return
	if frame >= int(scene_light.life):
		_end_scene_light(true)
		return
	if frame != int(scene_light.frame): _apply_scene_light(frame)

func _apply_scene_light(frame: int) -> void:
	scene_light.frame = frame
	var track: PackedFloat32Array = scene_light.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var on := track[k + 10] > 0.5
	var base: Color = scene_light.colour
	if is_instance_valid(sun):
		sun.light_color = Color(base.r * track[k + 4], base.g * track[k + 5], base.b * track[k + 6], base.a) if on else base
	if sky != null:
		sky.ambient_light_color = Color(track[k + 7], track[k + 8], track[k + 9]) if on else scene_light.ambient

func _end_scene_light(completed := false) -> void:
	if not scene_light.active: return
	scene_light.active = false
	scene_light.track = PackedFloat32Array()
	if is_instance_valid(sun):
		var base: Color = scene_light.colour
		# Native completion reapplies the saved RGB as a multiplier on itself.
		sun.light_color = Color(base.r * base.r, base.g * base.g, base.b * base.b, base.a) if completed else base
	if sky != null: sky.ambient_light_color = scene_light.ambient

func _hide(item: Dictionary, sync_secondary := true) -> void:
	item.active = false
	item.track = PackedFloat32Array()
	item.node.visible = false
	if sync_secondary and item.has("secondary"): _sync_arena_secondary()

## Running effect models, lights and faders.
func part_count() -> int:
	var count := 0
	for list: Array[Dictionary] in [objects, lights, faders]:
		for item in list:
			if item.active: count += 1
	return count + (1 if scene_light.active else 0)

func _draw(emitter: Dictionary, frame: int) -> void:
	emitter.frame = frame
	var cached: Dictionary = emitter.entry
	var file: ELParticleFile = cached.file
	var mesh: MultiMesh = emitter.mesh
	if emitter.following and frame >= file.frames:
		mesh.visible_instance_count = 0
		emitter.glow = []
		return
	var buffer: PackedFloat32Array
	var count := 0
	if file.loop_end > 0 and not emitter.following:
		# Every running cycle shows at once. Past the first pass the set of
		# frames depends only on the phase, so combined buffers are cached.
		var key := frame if frame < file.frames else file.frames + (frame - file.frames) % file.loop_end
		var combined: Dictionary = cached.get("cycles", {})
		cached.cycles = combined
		var stored: Variant = combined.get(key)
		if stored == null:
			var joined := PackedFloat32Array()
			var total := 0
			for at: int in file.visible_frames(key):
				joined.append_array(_frame(cached, at).slice(0, _count(file, at) * 16))
				total += _count(file, at)
			joined.resize(_bucket(total) * 16)
			stored = [joined, total]
			combined[key] = stored
			cached.bytes = int(cached.bytes) + joined.size() * 4
			_cached_bytes += joined.size() * 4
		buffer = stored[0]
		count = stored[1]
		emitter.glow = _glow(cached, "c%d" % key, buffer, count)
	else:
		var at := (file.frames - 1 - frame) if emitter.reverse else frame
		at = clampi(at, 0, file.frames - 1)
		buffer = _frame(cached, at)
		count = _count(file, at)
		emitter.glow = _glow(cached, "f%d" % at, buffer, count)
	# The span matrix changes centres. Keep the instance axes that encode
	# billboard size and atlas index, even when a vertical span collapses.
	var centre_basis: Basis = emitter.centre_basis
	if centre_basis != Basis.IDENTITY:
		buffer = buffer.duplicate()
		for i in count:
			var o := i * 16
			var p := centre_basis * Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11])
			buffer[o + 3] = p.x
			buffer[o + 7] = p.y
			buffer[o + 11] = p.z
	var size := buffer.size() / 16
	if mesh.instance_count != size: mesh.instance_count = size
	mesh.buffer = buffer
	mesh.visible_instance_count = count

## Patch size and most patches a glowing frame is split into for lighting.
const GLOW_PATCH := 1.5
const GLOW_PATCHES := 6
## Most light (brightest channel) one glowing system or effect model gives.
const EMITTER_GLOW := 12.0

## The light a glowing (additive) frame gives off, for traced lighting: a
## soft source per patch of its particles, so a wall of fire lights along
## its length: [[centre, extent, summed colour], ...], brightest first.
## Kept per frame.
static func _glow(cached: Dictionary, key: String, buffer: PackedFloat32Array, count: int) -> Array:
	if count == 0: return []
	var glows: Dictionary = cached.get("glows", {})
	cached.glows = glows
	if glows.has(key): return glows[key]
	var patches := {}
	var glow_tints: PackedVector3Array = cached.get("glow_tints", PackedVector3Array())
	for n in count:
		var o := n * 16
		# Some authored tails keep particle colour after the billboard collapses.
		if buffer[o + 10] == 0.0: continue
		var atlas_cell := int(buffer[o + 5]) - 1
		var rgb := Vector3(buffer[o + 12], buffer[o + 13], buffer[o + 14]) * buffer[o + 15]
		if atlas_cell >= 0 and atlas_cell < glow_tints.size(): rgb *= glow_tints[atlas_cell]
		var w := rgb.x + rgb.y + rgb.z
		if w <= 0.0001: continue
		var p := Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11])
		var cell := Vector3i((p / GLOW_PATCH).floor())
		var patch: Array = patches.get(cell, [Vector3.ZERO, Vector3.ZERO, 0.0, 0.0])
		patch[0] += p * w
		patch[1] += rgb
		patch[2] += w
		patch[3] += p.length_squared() * w
		patches[cell] = patch
	var result := []
	for patch: Array in patches.values():
		var centre: Vector3 = patch[0] / patch[2]
		var spread := sqrt(maxf(patch[3] / patch[2] - centre.length_squared(), 0.0))
		result.append([centre, spread, patch[1]])
	result.sort_custom(func(a, b): return a[2].length_squared() > b[2].length_squared())
	if result.size() > GLOW_PATCHES:
		# Light of the patches left out goes to the ones kept, nearest first.
		for extra: Array in result.slice(GLOW_PATCHES):
			var best := 0
			for i in GLOW_PATCHES:
				if result[i][0].distance_squared_to(extra[0]) < result[best][0].distance_squared_to(extra[0]): best = i
			result[best][2] += extra[2]
		result.resize(GLOW_PATCHES)
	glows[key] = result
	return result

## Glowing particle systems now showing, for traced lighting:
## [world centre, extent, summed colour times opacity] per patch.
func glow_sources() -> Array:
	var result := []
	for emitter: Dictionary in emitters + arena_emitters:
		if not emitter.active or not emitter.node.is_visible_in_tree(): continue
		var glow: Array = emitter.glow
		if glow.is_empty(): continue
		var node: MultiMeshInstance3D = emitter.node
		var placement := node.global_transform
		var centre_basis: Basis = emitter.centre_basis
		if centre_basis != Basis.IDENTITY: placement.basis *= centre_basis
		var basis := placement.basis
		var size := (basis.x.length() + basis.y.length() + basis.z.length()) / 3.0
		var tint := Vector3.ONE
		if not emitter.entry.file.additive:
			# Only bright, strongly coloured alpha-blended sheets act as flames.
			var atlas := (node.material_override as ShaderMaterial).get_shader_parameter("atlas") as Texture2D
			tint = _flame_colour(atlas)
			if tint == Vector3.ZERO: continue
		var opacity := clampf(float(emitter.opacity), 0.0, 1.0)
		# However many patches it splits into, one system gives at most
		# EMITTER_GLOW in all.
		var lit := []
		var total := 0.0
		for patch: Array in glow:
			var colour := _saturate(patch[2] * tint) * opacity
			total += maxf(colour.x, maxf(colour.y, colour.z))
			lit.append([placement * patch[0], patch[1] * size, colour])
		var share := minf(1.0, EMITTER_GLOW / maxf(total, 0.0001))
		for light: Array in lit:
			light[2] *= share
			result.append(light)
	# Transparent additive emitters stay outside the traced mesh pass. Use
	# their bounds only when the active material actually emits light.
	for item: Dictionary in objects + arena_objects:
		if not item.active or not item.add: continue
		var model: ELModel = item.node
		if not model.is_visible_in_tree(): continue
		for part: MeshInstance3D in model.parts.values():
			if part.mesh == null or not part.visible: continue
			var colour := _additive_model_glow(part.material_override as StandardMaterial3D)
			if colour.length_squared() < 1e-6: continue
			var box := part.global_transform * part.get_aabb()
			var s := box.size
			var axis := 0 if s.x >= s.y and s.x >= s.z else (1 if s.y >= s.z else 2)
			var pieces := clampi(ceili(s[axis] / 2.0), 1, 4)
			var area := (s.x * s.y + s.y * s.z + s.x * s.z) * OBJECT_GLOW / pieces
			var step := Vector3.ZERO
			step[axis] = s[axis] / pieces
			var other := s
			other[axis] = step[axis]
			var extent := other.length() * 0.35
			var piece := colour * area
			var peak := maxf(piece.x, maxf(piece.y, piece.z)) * pieces
			if peak > EMITTER_GLOW: piece *= EMITTER_GLOW / peak
			for i in pieces:
				result.append([box.position + step * (i + 0.5) + Vector3(s.x if axis != 0 else 0.0, s.y if axis != 1 else 0.0, s.z if axis != 2 else 0.0) * 0.5, extent, piece])
	return result

static func _additive_model_glow(material: StandardMaterial3D) -> Vector3:
	if material == null or material.blend_mode != BaseMaterial3D.BLEND_MODE_ADD or material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		return Vector3.ZERO
	var fullbright := material.has_meta(ELFigure.AUTHORED_FULLBRIGHT)
	var emissive := material.emission_enabled and material.emission_energy_multiplier > 0.0
	if not fullbright and not emissive: return Vector3.ZERO
	var albedo := _texture_glow(material.albedo_texture) if material.albedo_texture != null else Vector4.ONE
	var colour := Vector3.ZERO
	if fullbright:
		var tint := material.albedo_color.srgb_to_linear()
		colour = Vector3(albedo.x * tint.r, albedo.y * tint.g, albedo.z * tint.b)
	if emissive:
		var tint := material.emission.srgb_to_linear()
		var emission := Vector3(tint.r, tint.g, tint.b)
		var tex := _texture_glow(material.emission_texture, false)
		var rgb := Vector3(tex.x, tex.y, tex.z)
		emission = emission * rgb if material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY else emission + rgb
		colour += emission * (material.emission_energy_multiplier * albedo.w)
	return _saturate(colour) * material.albedo_color.a

static var _flames: Dictionary = {}

## The colour a blended sprite sheet glows with, or zero when it does not
## look like flame (dim, or grey like smoke and dust): its average colour
## where it is opaque.
static func _flame_colour(atlas: Texture2D) -> Vector3:
	if atlas == null: return Vector3.ZERO
	if _flames.has(atlas): return _flames[atlas]
	var result := Vector3.ZERO
	var image := atlas.get_image()
	if image != null:
		image = image.duplicate()
		if image.is_compressed(): image.decompress()
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
		image.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		var sum := Vector3.ZERO
		var cover := 0.0
		for y in 32:
			for x in 32:
				var c := image.get_pixel(x, y)
				sum += Vector3(c.r, c.g, c.b) * c.a
				cover += c.a
		if cover > 0.0:
			var average := sum / cover
			var peak := maxf(average.x, maxf(average.y, average.z))
			var low := minf(average.x, minf(average.y, average.z))
			if peak > 0.45 and (peak - low) / peak > 0.4:
				var linear := Color(average.x, average.y, average.z).srgb_to_linear()
				result = Vector3(linear.r, linear.g, linear.b)
	_flames[atlas] = result
	return result

## Light per square metre of a glowing effect model's surface, before the
## texture's average colour.
const OBJECT_GLOW := 2.0
static var _texture_glows: Dictionary = {}

## Approximate average linear colour and coverage for a model's light proxy.
static func _texture_glow(texture: Texture2D, weight_alpha := true) -> Vector4:
	if texture == null: return Vector4.ZERO
	var key := [texture, weight_alpha]
	if _texture_glows.has(key): return _texture_glows[key]
	var image := texture.get_image()
	var sum := Vector4.ZERO
	if image != null:
		image = image.duplicate()
		if image.is_compressed(): image.decompress()
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
		image.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		for y in 32:
			for x in 32:
				var c := image.get_pixel(x, y).srgb_to_linear()
				var weight := c.a if weight_alpha else 1.0
				sum += Vector4(c.r * weight, c.g * weight, c.b * weight, c.a)
		sum /= 1024.0
	_texture_glows[key] = sum
	return sum

## Glow colours lean towards white where many bright sprites overlap; the
## light they cast reads as the flame's colour, so its hue is deepened
## (keeping its brightest channel).
static func _saturate(colour: Vector3) -> Vector3:
	var peak := maxf(colour.x, maxf(colour.y, colour.z))
	if peak <= 0.0: return colour
	var hue := colour / peak
	return Vector3(hue.x * hue.x, hue.y * hue.y, hue.z * hue.z) * peak

static var _atlas_tints: Dictionary = {}

## Alpha-weighted linear hue per additive cell. Particle alpha and the emitter
## budget control strength. Black or transparent cells have no colour to add.
static func _atlas_cell_tints(atlas: Texture2D, grid: Vector2i) -> PackedVector3Array:
	if atlas == null: return PackedVector3Array()
	var key := [atlas, grid]
	if _atlas_tints.has(key): return _atlas_tints[key]
	var tints := cell_tints(atlas.get_image(), grid)
	_atlas_tints[key] = tints
	return tints

## The cell tints of a sprite sheet's image (see _atlas_cell_tints). Changes
## only `image` (pass a copy), so worker threads may run it.
static func cell_tints(image: Image, grid: Vector2i) -> PackedVector3Array:
	var tints := PackedVector3Array()
	if image != null and grid.x <= image.get_width() and grid.y <= image.get_height():
		if image.is_compressed(): image.decompress()
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
		var pixels := image.get_data()
		var width := image.get_width()
		var height := image.get_height()
		var linear := PackedFloat32Array()
		linear.resize(256)
		for value in 256:
			linear[value] = Color(value / 255.0, 0, 0).srgb_to_linear().r
		tints.resize(grid.x * grid.y)
		for cell in tints.size():
			var column := cell % grid.x
			# Sprite indices count upward from the texture's bottom row.
			var row := grid.y - 1 - cell / grid.x
			var sum := Vector3.ZERO
			for y in range(row * height / grid.y, (row + 1) * height / grid.y):
				for x in range(column * width / grid.x, (column + 1) * width / grid.x):
					var i := (y * width + x) * 4
					sum += Vector3(linear[pixels[i]], linear[pixels[i + 1]], linear[pixels[i + 2]]) * pixels[i + 3]
			var peak := maxf(sum.x, maxf(sum.y, sum.z))
			if peak > 0.0: tints[cell] = sum / peak
	return tints

static func _count(file: ELParticleFile, frame: int) -> int:
	return file.starts[frame + 1] - file.starts[frame]

## Instance count of a frame's buffer: the particle count rounded up to 64.
static func _bucket(count: int) -> int:
	return maxi(MIN_BUCKET, (count + MIN_BUCKET - 1) / MIN_BUCKET * MIN_BUCKET)

## One frame's instance data: basis x carries the copy's scale (unit length),
## basis y the atlas cell + 1, basis z the particle size; the custom data is RGBA.
static func _frame(cached: Dictionary, frame: int) -> PackedFloat32Array:
	var frames: Dictionary = cached.frames
	var stored: Variant = frames.get(frame)
	if stored != null: return stored
	var buffer := _frame_buffer(cached.file, frame)
	frames[frame] = buffer
	var bytes := buffer.size() * 4
	cached.bytes = int(cached.bytes) + bytes
	_cached_bytes += bytes
	_trim(cached)
	return buffer

## A frame's instance data (see _frame). Pure: worker threads may run it.
static func _frame_buffer(file: ELParticleFile, frame: int) -> PackedFloat32Array:
	var first: int = file.starts[frame]
	var count := _count(file, frame)
	var buffer := PackedFloat32Array()
	buffer.resize(_bucket(count) * 16)
	buffer.fill(0.0)
	for n in count:
		var i := first + n
		var o := n * 16
		buffer[o] = 1.0
		buffer[o + 3] = file.positions[i * 3]
		buffer[o + 5] = float(file.cells.decode_u16(i * 2) + 1)
		buffer[o + 7] = file.positions[i * 3 + 2]
		buffer[o + 10] = file.sizes[i]
		buffer[o + 11] = -file.positions[i * 3 + 1]
		buffer[o + 12] = file.rgb[i * 3] / 255.0
		buffer[o + 13] = file.rgb[i * 3 + 1] / 255.0
		buffer[o + 14] = file.rgb[i * 3 + 2] / 255.0
		buffer[o + 15] = file.alpha[i] / 255.0
	return buffer

## Decoded file of an edition (shared by every battle of that edition).
static func _file(data: ELProfile, path: String) -> Dictionary:
	var key := data.id + ":" + ELArchive.key(path)
	if _files.has(key):
		_order.erase(key)
		_order.append(key)
		return _files[key]
	var bytes := data.read("pfx", ELArchive.key(path))
	var file := ELParticleFile.decode(bytes)
	if not file.error.is_empty() or file.frames < 1:
		push_warning("Combat effect particles unreadable: " + path)
		return {}
	var cached := {"file": file, "frames": {}, "bytes": bytes.size()}
	_files[key] = cached
	_order.append(key)
	_cached_bytes += bytes.size()
	_trim(cached)
	return cached

## The battlefield's weather that comes and goes (ELBattleWarmup):
## {"particles": [path, ...], "sounds": [path, ...]}.
func arena_parts() -> Dictionary:
	var paths: Array[String] = []
	var sounds: Array[String] = []
	for cue: Dictionary in _arena_random:
		if not paths.has(String(cue.path)): paths.append(String(cue.path))
		if not String(cue.sound).is_empty() and not sounds.has(String(cue.sound)): sounds.append(String(cue.sound))
	return {"particles": paths, "sounds": sounds}

## Battle warm-up (ELBattleWarmup): the particle files and effect models
## an effect starts, without starting it: {"particles": [path, ...],
## "objects": [object entry, ...]}.
func effect_parts(effect: String) -> Dictionary:
	var entry := definition(effect)
	var paths: Array[String] = []
	for particle: Dictionary in entry.get("particles", []):
		if not paths.has(String(particle.file)): paths.append(String(particle.file))
	return {"particles": paths, "objects": entry.get("objects", [])}

## Largest instance data baked ahead for one file; longer effects build
## their frames as they play, as before.
const BAKE_BYTES := 8 * 1024 * 1024

## Decodes a particle file and builds every frame's instance data (a cache
## entry as _file makes, frames filled). Touches nothing shared, so worker
## threads run it. {} when unreadable.
static func bake_file(bytes: PackedByteArray) -> Dictionary:
	var file := ELParticleFile.decode(bytes)
	if not file.error.is_empty() or file.frames < 1: return {}
	var baked := {"file": file, "frames": {}, "bytes": bytes.size()}
	var size := 0
	for frame in file.frames: size += _bucket(_count(file, frame)) * 64
	if size > BAKE_BYTES: return baked
	for frame in file.frames: baked.frames[frame] = _frame_buffer(file, frame)
	baked.bytes = bytes.size() + size
	return baked

## Glow patches of every baked frame (see _glow), for worker threads.
static func bake_glows(file: ELParticleFile, frames: Dictionary, tints: PackedVector3Array) -> Dictionary:
	var scratch := {"glow_tints": tints, "glows": {}}
	for frame: int in frames:
		_glow(scratch, "f%d" % frame, frames[frame], _count(file, frame))
	return scratch.glows

## Files a baked particle file (unless a cast decoded it meanwhile) and
## returns its cache entry.
static func store_file(data: ELProfile, path: String, baked: Dictionary) -> Dictionary:
	var key := data.id + ":" + ELArchive.key(path)
	if _files.has(key): return _files[key]
	_files[key] = baked
	_order.append(key)
	_cached_bytes += int(baked.bytes)
	_trim(baked)
	return baked

## The cache entry of a particle file, or {} (no decoding).
static func cached_file(data: ELProfile, path: String) -> Dictionary:
	return _files.get(data.id + ":" + ELArchive.key(path), {})

## The sprite sheet a particle file draws with (a ELProfile.texture name).
static func sheet_name(file: ELParticleFile) -> String:
	return "Effects/" + (file.texture.get_basename() if file.texture.to_lower().ends_with(".bmp") else file.texture)

## Readies a cached particle file to draw: its material, and for a glowing
## file its sheet's cell colours (`tints`, worked out by a warm-up) and the
## glow patches baked with them.
static func ready_file(data: ELProfile, cached: Dictionary, tints: Variant, glows: Dictionary, ambient := false) -> void:
	var file: ELParticleFile = cached.file
	var material := _material(data, file, ambient)
	if material == null: return
	if file.additive and not cached.has("glow_tints") and tints is PackedVector3Array:
		var atlas := material.get_shader_parameter("atlas") as Texture2D
		var key := [atlas, Vector2i(file.columns, file.rows)]
		if not _atlas_tints.has(key): _atlas_tints[key] = tints
		cached.glow_tints = _atlas_tints[key]
	if not glows.is_empty() and (not file.additive or cached.has("glow_tints")):
		var kept: Dictionary = cached.get("glows", {})
		for key: String in glows:
			if not kept.has(key): kept[key] = glows[key]
		cached.glows = kept

## A sprite sheet's cell colours when already worked out, else null.
static func known_tints(atlas: Texture2D, grid: Vector2i) -> Variant:
	return _atlas_tints.get([atlas, grid])

## Every look the pooled effect models and the particle shaders draw with
## (ELBattleWarmup draws each once, out of sight, so their shaders compile
## before the first cast shows them): materials for plain meshes, and for
## particle-style MultiMeshes.
func warm_materials() -> Dictionary:
	var meshes: Array[Material] = []
	for item: Dictionary in objects:
		for material: Variant in [item.opaque, item.faded] + Array(item.additive_materials):
			if material is Material and not meshes.has(material): meshes.append(material)
		for variants: Array in item.magic_materials.values():
			for material: Material in variants:
				if not meshes.has(material): meshes.append(material)
	var particles: Array[Material] = []
	for additive: bool in [false, true]:
		var material := ShaderMaterial.new()
		material.shader = _shader(additive)
		material.render_priority = 10
		particles.append(material)
	return {"meshes": meshes, "particles": particles}

## Builds an effect model ahead of its first use and keeps it in the pool.
func prebuild_object(object: Dictionary) -> void:
	_free_object(object, objects, OBJECT_POOL)

## Drops the least recently used files over the budget (never `keep`; a
## running emitter keeps its own reference).
static func _trim(keep: Dictionary) -> void:
	var at := 0
	while _cached_bytes > CACHE_BYTES and at < _order.size():
		var key: String = _order[at]
		if is_same(_files[key], keep):
			at += 1
			continue
		_cached_bytes -= int(_files[key].bytes)
		_files.erase(key)
		_order.remove_at(at)

## Cached decoded files of an edition, for checks.
static func cached_files(data: ELProfile) -> int:
	var count := 0
	for key: String in _files:
		if key.begins_with(data.id + ":"): count += 1
	return count

static func _material(data: ELProfile, file: ELParticleFile, ambient: bool) -> ShaderMaterial:
	var capped := ambient and file.additive
	var key := "%s|%s|%s|%s" % [data.id, file.texture.to_lower(), "arena" if capped else "effect", file.additive]
	if _materials.has(key): return _materials[key]
	var name := file.texture.get_basename() if file.texture.to_lower().ends_with(".bmp") else file.texture
	var texture := data.texture("Effects/" + name)
	if texture == null:
		_materials[key] = null
		return null
	var material := ShaderMaterial.new()
	material.shader = _shader(file.additive)
	material.set_shader_parameter("atlas", texture)
	material.set_shader_parameter("grid", Vector2(file.columns, file.rows))
	material.render_priority = 10
	var glow := minf(glow_level, ARENA_HDR_LIMIT) if capped else glow_level
	material.set_shader_parameter("glow", glow if file.additive else 1.0)
	_materials[key] = material
	return material

static func _shader(additive: bool) -> Shader:
	if not _shaders.has(additive):
		var shader := Shader.new()
		shader.code = ELParticleFile.sprite_shader(SHADER.replace("BLEND", "blend_add" if additive else "blend_mix"))
		_shaders[additive] = shader
	return _shaders[additive]

## Sets how bright glowing particles draw (see glow_level), running ones too.
func set_glow(value: float) -> void:
	glow_level = value
	for key: String in _materials:
		var material: ShaderMaterial = _materials[key]
		if material != null and key.ends_with("|true"):
			material.set_shader_parameter("glow", minf(value, ARENA_HDR_LIMIT) if key.ends_with("|arena|true") else value)
	for emitter in emitters:
		var own: ShaderMaterial = emitter.own
		if own != null and not emitter.entry.is_empty() and emitter.entry.file.additive: own.set_shader_parameter("glow", value)
	for item: Dictionary in arena_objects:
		if item.active and item.ether_vent: _set_vent_glow(item)

## Only the hottest part of the flame crosses the bloom threshold.
func _set_vent_glow(item: Dictionary) -> void:
	var gain := 1.0 + (glow_level - 1.0) * 0.62
	for variants: Array in item.magic_materials.values():
		var source: Color = variants[0].albedo_color
		var blend: StandardMaterial3D = variants[1]
		blend.albedo_color = Color(source.r * gain, source.g * gain, source.b * gain, blend.albedo_color.a)

## Camera-facing quads; atlas cells and row order as ELAdventureEffects; the
## quad size follows ELParticleFile.SPRITE_SIZE_FUNCTION.
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, BLEND;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(1.0);
uniform float opacity = 1.0;
uniform float glow = 1.0;
varying vec4 tint;
SPRITE_SIZE_FUNCTION
void vertex() {
	float stretch = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	float cell = floor(length(MODEL_MATRIX[1].xyz) / stretch - 0.5);
	float size = sprite_half_extent(length(MODEL_MATRIX[2].xyz), PROJECTION_MATRIX);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vec2 slot = vec2(mod(cell, grid.x), floor(cell / grid.x));
	UV = (UV + slot) / grid;
	UV.y = 1.0 - UV.y;
	tint = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 texel = texture(atlas, UV);
	ALBEDO = texel.rgb * tint.rgb * glow;
	ALPHA = texel.a * tint.a * opacity;
}
"""

## Composite the packed fader in the same display space as the original.
const FADER_SHADER := """
shader_type canvas_item;
render_mode unshaded, BLEND;
uniform vec4 colour = vec4(0.0);
void fragment() {
	COLOR = colour;
}
"""
