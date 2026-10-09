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
## Emitters are pooled MultiMesh nodes; each frame's instance data is built
## once per file and edition (padded to a multiple of 64) and reused; a cyclic
## file's overlapping cycles are combined once per frame phase.
const Table := preload("res://src/duel/combat_sound_table.gd")
const POOL_SIZE := 48
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
			current = {"name": name, "particles": [], "points": {}, "frames": 0}
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
				"begin": parser.get_named_attribute_value_safe("begin_point"),
				"end": parser.get_named_attribute_value_safe("end_point")})
	for key: String in result: result[key].frames = fx_frames(data, String(result[key].name))
	_catalogues[data.id] = result
	return result

## Length of an effect in frames: the longest key track of its .fx file
## (point lights 23 bytes a key, sounds 21, objects 44). 0 when absent.
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
		var key := {"PLIT": 23, "SOUN": 21, "OBJC": 44}.get(tag, 0) as int
		if key > 0: frames = maxi(frames, (size - name_size) / key)
		at += 10 + size
	return frames

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

## Starts the effects a cast of `card` names (summons: the colour's effect).
## `bindings`: point name -> figures (ELModel), see the class description.
func cast(card: String, bindings: Dictionary) -> void:
	for effect: Variant in Table.card_effects(profile, card): play(String(effect), bindings)

func trigger(card: String, bindings: Dictionary) -> void:
	for effect: Variant in Table.trigger_effects(edition, card): play(String(effect), bindings)

## Starts one named effect; returns the number of particle copies started.
func play(effect: String, bindings: Dictionary) -> int:
	requested.append(effect)
	if requested.size() > 80: requested.pop_front()
	if not enabled: return 0
	var entry := definition(effect)
	if entry.is_empty(): return 0
	var count := 0
	for particle: Dictionary in entry.particles:
		var begin := String(particle.begin)
		var finish := String(particle.end)
		var starts: Array = [null] if begin.is_empty() else _figures(bindings, begin)
		var ends: Array = [null] if finish.is_empty() else _figures(bindings, finish)
		for a: Variant in starts:
			for b: Variant in ends:
				var where := placement(entry, begin, a, finish, b)
				if not _spawn(String(particle.file), bool(particle.reverse), int(entry.frames), where).is_empty(): count += 1
	if count > 0:
		started.append(entry.name)
		if started.size() > 40: started.pop_front()
	return count

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
	var emitter := {"node": node, "mesh": mesh, "entry": {}, "elapsed": 0.0, "frame": -1, "life": 0, "reverse": false, "active": false, "follow": null, "following": false}
	emitters.append(emitter)
	return emitter

func _release(emitter: Dictionary) -> void:
	emitter.active = false
	emitter.entry = {}
	emitter.follow = null
	emitter.following = false
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
		if frame != int(emitter.frame): _draw(emitter, frame)
	last_cost_usec = Time.get_ticks_usec() - clock
	peak_cost_usec = maxi(peak_cost_usec, last_cost_usec)

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
	ALPHA = texel.a * tint.a;
}
"""
