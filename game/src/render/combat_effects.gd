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
## and an end point the authored segment is stretched and turned onto the
## figures'; without points it sits at the arena origin. One copy is drawn per
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
## and opacity from its keys, a particle system its scale and opacity, a light
## its place, range, colour and switch, a fader its colour and strength.
##
## Emitters are pooled MultiMesh nodes; each frame's instance data is built
## once per file and edition (padded to a multiple of 64) and reused; a cyclic
## file's overlapping cycles are combined once per frame phase. Effect models,
## lights and faders are pooled too.
const Table := preload("res://src/duel/combat_sound_table.gd")
const POOL_SIZE := 48
const OBJECT_POOL := 24
const LIGHT_POOL := 4
const FADER_POOL := 2
## Floats per decoded .fx key (both kinds): models and particles keep place,
## turn (x y z w), scale and opacity; lights and faders keep place, range or
## strength, two colours and the on switch.
const KEY := 11
const MIN_BUCKET := 64
## Decoded particle files (with frame instance data) kept per edition.
const CACHE_BYTES := 96 * 1024 * 1024

## Edition id -> {effect name (lower) -> definition}.
static var _catalogues: Dictionary = {}
## "edition:file" -> {file: ELParticleFile, frames: {frame -> PackedFloat32Array}, bytes}.
static var _files: Dictionary = {}
static var _order: Array[String] = []
static var _cached_bytes := 0
static var _materials: Dictionary = {}

var profile: ELProfile
var edition := ""
var enabled := true
var catalogue: Dictionary = {}
## Pool: each emitter {node, mesh, entry, elapsed, frame, life, reverse, active}.
var emitters: Array[Dictionary] = []
## Pools: effect models {node, key, add, opaque, faded, ...}, lights, faders.
var objects: Array[Dictionary] = []
var lights: Array[Dictionary] = []
var faders: Array[Dictionary] = []
## The one scene light an effect may dim (the arena's sun and ambient light):
## {active, track, elapsed, frame, life, colour, ambient} with the arena's own
## values kept to restore.
var scene_light := {"active": false, "track": PackedFloat32Array(), "elapsed": 0.0, "frame": -1, "life": 0}
var sun: DirectionalLight3D
var sky: Environment
## Point lights can be switched off on their own (they cost a light pass).
var lights_enabled := true
var _fader_shaders: Dictionary = {}
## Figure (instance id) -> its running animation emitter.
var _figure_emitters: Dictionary = {}
## Figure animation particle files that exist ("model/clip" -> path or "").
var _animation_files: Dictionary = {}
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
	var key := model.template + "/" + clip
	if _animation_files.has(key): return _animation_files[key]
	var path := "CreaturesPFX/%s/%s.pfx" % [model.template, clip.substr(1) if clip.length() > 1 and clip[0] in ["c", "u"] else clip]
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
	var path := animation_file(model, clip)
	if path.is_empty(): return
	requested.append(path)
	if requested.size() > 80: requested.pop_front()
	var emitter := _spawn(path, false, 0, _figure_transform(model), model)
	if not emitter.is_empty(): _figure_emitters[id] = emitter

## The figure's place, facing and scale.
static func _figure_transform(model: Node3D) -> Transform3D:
	var basis := model.global_transform.basis
	return Transform3D(basis.orthonormalized().scaled(model.scale), model.global_position)

func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		for emitter in emitters: _release(emitter)
		for list: Array[Dictionary] in [objects, lights, faders]:
			for item in list: _hide(item)
		_end_scene_light()

## The arena's sun and ambient light that scene-light effects dim.
func set_scene(light: DirectionalLight3D, environment: Environment) -> void:
	_end_scene_light()
	sun = light
	sky = environment

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
		for where: Transform3D in _copies(entry, particle, bindings):
			var emitter := _spawn(String(particle.file), bool(particle.reverse), int(entry.frames), where)
			if emitter.is_empty(): continue
			count += 1
			if not track.is_empty(): _track_emitter(emitter, track)
	for object: Dictionary in entry.objects:
		var track: PackedFloat32Array = tracks.get(object.track, PackedFloat32Array())
		if track.is_empty(): continue
		for where: Transform3D in _copies(entry, object, bindings):
			if _spawn_object(object, track, where): count += 1
	if lights_enabled:
		for light: Dictionary in entry.lights:
			var track: PackedFloat32Array = tracks.get(light.track, PackedFloat32Array())
			if track.is_empty(): continue
			for where: Transform3D in _copies(entry, light, bindings):
				if _spawn_light(track, where): count += 1
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
static func _copies(entry: Dictionary, part: Dictionary, bindings: Dictionary) -> Array[Transform3D]:
	var begin := String(part.begin)
	var finish := String(part.end)
	var starts: Array = [null] if begin.is_empty() else _figures(bindings, begin)
	var ends: Array = [null] if finish.is_empty() else _figures(bindings, finish)
	var result: Array[Transform3D] = []
	for a: Variant in starts:
		for b: Variant in ends: result.append(placement(entry, begin, a, finish, b))
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
static func placement(entry: Dictionary, begin: String, a: Variant, finish: String, b: Variant) -> Transform3D:
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
	# A degenerate authored segment only moves the effect to the begin point.
	if authored.length() < 0.001 or actual.length() < 0.001: return Transform3D(Basis.IDENTITY, from)
	var turn := Basis(Quaternion(authored.normalized(), actual.normalized()))
	var basis := turn.scaled(Vector3.ONE * (actual.length() / authored.length()))
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

## Starts a pooled emitter; `follow` keeps it on a figure. A cyclic file
## repeats for the effect's length, or while its figure's clip runs.
func _spawn(path: String, reverse: bool, effect_frames: int, where: Transform3D, follow: Node3D = null) -> Dictionary:
	var cached := _file(profile, path)
	if cached.is_empty(): return {}
	var file: ELParticleFile = cached.file
	var material := _material(profile, file)
	if material == null: return {}
	var emitter := _free_emitter()
	if emitter.is_empty():
		dropped += 1
		return {}
	var node: MultiMeshInstance3D = emitter.node
	node.material_override = material
	node.transform = where
	node.visible = true
	emitter.where = where
	emitter.track = PackedFloat32Array()
	emitter.opacity = 1.0
	emitter.entry = cached
	emitter.elapsed = 0.0
	emitter.frame = -1
	emitter.reverse = reverse
	emitter.follow = follow
	emitter.following = follow != null
	emitter.life = file.frames
	if file.loop_end > 0: emitter.life = maxi(effect_frames, 1) if follow == null else 1 << 30
	emitter.active = true
	emitter.mesh.visible_instance_count = 0
	spawned += 1
	_draw(emitter, 0)
	return emitter

func _free_emitter() -> Dictionary:
	for emitter in emitters:
		if not emitter.active: return emitter
	if emitters.size() >= POOL_SIZE: return {}
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
	node.custom_aabb = AABB(Vector3(-64, -16, -64), Vector3(128, 96, 128))
	node.visible = false
	add_child(node)
	var emitter := {"node": node, "mesh": mesh, "entry": {}, "elapsed": 0.0, "frame": -1, "life": 0, "reverse": false, "active": false, "follow": null, "following": false,
		"where": Transform3D.IDENTITY, "track": PackedFloat32Array(), "opacity": 1.0, "own": null}
	emitters.append(emitter)
	return emitter

func _release(emitter: Dictionary) -> void:
	emitter.active = false
	emitter.entry = {}
	emitter.follow = null
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
	for emitter in emitters:
		if not emitter.active: continue
		emitter.elapsed += delta
		var frame := int(emitter.elapsed * ELParticleFile.FPS)
		# A freed figure compares equal to null, so the flag says whether it follows.
		if frame >= int(emitter.life) or (emitter.following and not is_instance_valid(emitter.follow)):
			_release(emitter)
			continue
		if emitter.following: emitter.node.transform = _figure_transform(emitter.follow)
		if frame != int(emitter.frame):
			if not emitter.track.is_empty(): _apply_emitter_track(emitter, frame)
			_draw(emitter, frame)
	for item in objects:
		if item.active: _step_object(item, delta)
	for item in lights:
		if item.active: _step_light(item, delta)
	for item in faders:
		if item.active: _step_fader(item, delta)
	if scene_light.active: _step_scene_light(delta)
	last_cost_usec = Time.get_ticks_usec() - clock
	peak_cost_usec = maxi(peak_cost_usec, last_cost_usec)

## A particle system with its own .fx keys: their scale and opacity apply
## each frame (the system's place is already baked into its particles).
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
		emitter.node.material_override = own
	emitter.opacity = -1.0
	_apply_emitter_track(emitter, 0)

func _apply_emitter_track(emitter: Dictionary, frame: int) -> void:
	var track: PackedFloat32Array = emitter.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var scale := Vector3(track[k + 7], track[k + 9], track[k + 8])
	emitter.node.transform = emitter.where * Transform3D(Basis.from_scale(scale), Vector3.ZERO)
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

func _spawn_object(object: Dictionary, track: PackedFloat32Array, where: Transform3D) -> bool:
	var item := _free_object(object)
	if item.is_empty():
		dropped += 1
		return false
	item.where = where
	item.track = track
	item.elapsed = 0.0
	item.frame = -1
	item.life = track.size() / KEY
	item.opacity = -1.0
	item.active = true
	var model: ELModel = item.node
	model.play("cidle")
	_apply_object(item, 0)
	return true

## A spare pooled model of the same kind, a new one while the pool has room,
## else a spare of another kind rebuilt.
func _free_object(object: Dictionary) -> Dictionary:
	var key := "%s|%s|%s" % [String(object.model).to_lower(), String(object.texture).to_lower(), object.add]
	var spare := -1
	for i in objects.size():
		if objects[i].active: continue
		if objects[i].key == key: return objects[i]
		if spare < 0: spare = i
	if objects.size() >= OBJECT_POOL and spare < 0: return {}
	var item := _build_object(object, key)
	if item.is_empty(): return {}
	if objects.size() < OBJECT_POOL:
		objects.append(item)
	else:
		var old: Node = objects[spare].node
		remove_child(old)
		old.queue_free()
		objects[spare] = item
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
	if add:
		faded.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		faded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Effect models are light and glow shapes: they cast no shadow.
	for node: MeshInstance3D in model.parts.values(): node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.visible = false
	add_child(model)
	return {"node": model, "key": key, "add": add, "opaque": ELFigure.material(texture), "faded": faded, "shown": null,
		"active": false, "elapsed": 0.0, "frame": -1, "life": 0, "where": Transform3D.IDENTITY, "track": PackedFloat32Array(), "opacity": 1.0}

func _step_object(item: Dictionary, delta: float) -> void:
	item.elapsed += delta
	var frame := int(item.elapsed * ELParticleFile.FPS)
	if frame >= int(item.life):
		_hide(item)
		return
	if frame != int(item.frame): _apply_object(item, frame)

func _apply_object(item: Dictionary, frame: int) -> void:
	item.frame = frame
	var track: PackedFloat32Array = item.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var model: Node3D = item.node
	model.transform = item.where * _key_transform(track, k)
	var opacity := clampf(track[k + 10], 0.0, 1.0)
	model.visible = opacity > 0.004
	if opacity == float(item.opacity): return
	item.opacity = opacity
	var material: StandardMaterial3D = item.faded if item.add or opacity < 0.999 else item.opaque
	material.albedo_color.a = opacity if is_same(material, item.faded) else 1.0
	if is_same(item.shown, material): return
	item.shown = material
	for node: MeshInstance3D in model.parts.values():
		if node.mesh != null: node.material_override = material

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
	_apply_light(item, 0)
	return true

func _step_light(item: Dictionary, delta: float) -> void:
	item.elapsed += delta
	var frame := int(item.elapsed * ELParticleFile.FPS)
	if frame >= int(item.life) or not lights_enabled:
		_hide(item)
		return
	if frame != int(item.frame): _apply_light(item, frame)

## Place, reach (stretched with the effect) and colour; dark or switched-off
## keys hide the light.
func _apply_light(item: Dictionary, frame: int) -> void:
	item.frame = frame
	var track: PackedFloat32Array = item.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var where: Transform3D = item.where
	var node: OmniLight3D = item.node
	node.position = where * ELFigure.vector(Vector3(track[k], track[k + 1], track[k + 2]))
	node.omni_range = maxf(track[k + 3] * where.basis.get_scale().x, 0.01)
	node.light_color = Color(track[k + 4], track[k + 5], track[k + 6])
	node.visible = track[k + 10] > 0.5 and track[k + 3] > 0.01 and track[k + 4] + track[k + 5] + track[k + 6] > 0.004

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
		var quad := QuadMesh.new()
		quad.size = Vector2(2, 2)
		var node := MeshInstance3D.new()
		node.mesh = quad
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The quad covers the whole view wherever the camera looks.
		node.extra_cull_margin = 16384.0
		node.visible = false
		var material := ShaderMaterial.new()
		material.render_priority = 100
		node.material_override = material
		add_child(node)
		item = {"node": node, "material": material, "active": false, "elapsed": 0.0, "frame": -1, "life": 0, "track": PackedFloat32Array()}
		faders.append(item)
	item.material.shader = _fader_shader(add)
	item.track = track
	item.elapsed = 0.0
	item.life = track.size() / KEY
	item.active = true
	_apply_fader(item, 0)
	return true

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

## The fader's colour at its strength: added to the view, or blended over it.
func _apply_fader(item: Dictionary, frame: int) -> void:
	item.frame = frame
	var track: PackedFloat32Array = item.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var strength := clampf(track[k + 3], 0.0, 1.0)
	item.material.set_shader_parameter("colour", Color(track[k + 4], track[k + 5], track[k + 6], strength))
	item.node.visible = track[k + 10] > 0.5 and strength > 0.004

## A scene light keys the arena's light relative to its first key: the first
## colour scales the sun, the second the ambient light; the keys' straight-down
## direction leaves the sun's own direction (and shadows) alone. A newer effect
## takes over the one slot; the arena's light returns when it ends.
func _start_scene_light(track: PackedFloat32Array) -> bool:
	if not scene_light.active:
		scene_light.colour = sun.light_color
		scene_light.ambient = sky.ambient_light_energy if sky != null else 0.0
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
	if frame >= int(scene_light.life) or not lights_enabled or not is_instance_valid(sun):
		_end_scene_light()
		return
	if frame != int(scene_light.frame): _apply_scene_light(frame)

func _apply_scene_light(frame: int) -> void:
	scene_light.frame = frame
	var track: PackedFloat32Array = scene_light.track
	var k := clampi(frame, 0, track.size() / KEY - 1) * KEY
	var on := track[k + 10] > 0.5
	var first := Vector3(track[4], track[5], track[6])
	var second := Vector3(track[7], track[8], track[9])
	var colour := Vector3(track[k + 4], track[k + 5], track[k + 6]) / first.max(Vector3.ONE / 255.0) if on else Vector3.ZERO
	var ambient := Vector3(track[k + 7], track[k + 8], track[k + 9]) / second.max(Vector3.ONE / 255.0) if on else Vector3.ONE
	var base: Color = scene_light.colour
	if is_instance_valid(sun): sun.light_color = Color(base.r * colour.x, base.g * colour.y, base.b * colour.z, base.a)
	if sky != null: sky.ambient_light_energy = float(scene_light.ambient) * (ambient.x + ambient.y + ambient.z) / 3.0

func _end_scene_light() -> void:
	if not scene_light.active: return
	scene_light.active = false
	scene_light.track = PackedFloat32Array()
	if is_instance_valid(sun): sun.light_color = scene_light.colour
	if sky != null: sky.ambient_light_energy = scene_light.ambient

func _hide(item: Dictionary) -> void:
	item.active = false
	item.track = PackedFloat32Array()
	item.node.visible = false

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
	var buffer: PackedFloat32Array
	var count := 0
	if file.loop_end > 0:
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
	else:
		var at := (file.frames - 1 - frame) if emitter.reverse else frame
		at = clampi(at, 0, file.frames - 1)
		buffer = _frame(cached, at)
		count = _count(file, at)
	var size := buffer.size() / 16
	if mesh.instance_count != size: mesh.instance_count = size
	mesh.buffer = buffer
	mesh.visible_instance_count = count

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
	var file: ELParticleFile = cached.file
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
	frames[frame] = buffer
	var bytes := buffer.size() * 4
	cached.bytes = int(cached.bytes) + bytes
	_cached_bytes += bytes
	_trim(cached)
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

static func _material(data: ELProfile, file: ELParticleFile) -> ShaderMaterial:
	var key := "%s|%s|%s" % [data.id, file.texture.to_lower(), file.additive]
	if _materials.has(key): return _materials[key]
	var name := file.texture.get_basename() if file.texture.to_lower().ends_with(".bmp") else file.texture
	var texture := data.texture("Effects/" + name)
	if texture == null:
		_materials[key] = null
		return null
	var shader := Shader.new()
	shader.code = ELParticleFile.sprite_shader(SHADER.replace("BLEND", "blend_add" if file.additive else "blend_mix"))
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", texture)
	material.set_shader_parameter("grid", Vector2(file.columns, file.rows))
	material.render_priority = 10
	_materials[key] = material
	return material

## Camera-facing quads; atlas cells and row order as ELAdventureEffects; the
## quad size follows ELParticleFile.SPRITE_SIZE_FUNCTION.
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, BLEND;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(1.0);
uniform float opacity = 1.0;
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
	ALBEDO = texel.rgb * tint.rgb;
	ALPHA = texel.a * tint.a * opacity;
}
"""

## Whole-view colour layer of a screen fader, drawn over the battle scene.
const FADER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, BLEND;
uniform vec4 colour = vec4(0.0);
void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}
void fragment() {
	ALBEDO = colour.rgb;
	ALPHA = colour.a;
}
"""
