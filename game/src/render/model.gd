class_name ELModel
extends Node3D
signal animation_finished(clip: String)
## A clip started (combat effects start the figure's own particles with it).
signal animation_started(clip: String)
## A looping clip ("c" prefix) wrapped round to its first frame.
signal animation_looped(clip: String)
const EFFECT_ANCHORS := ["cast", "dust", "numbers", "soul", "b_point"]

var profile: ELProfile
var template := ""
var parts: Dictionary = {}
var figures: Dictionary = {}
var clips: Dictionary = {}
var clip := ""
var frame := 0.0
## Both games advance figure animations by 30 frames per second.
var fps := 30.0
var speed := 1.0
var playing := false
var _faded: Dictionary = {}
var error := ""
var sample_count := 0
var _animations: ELArchive
var _mesh_cache: Dictionary = {}
var _previous_morphs: Dictionary = {}
var _clip_frames := 1
## Clip records of the figure's animation table ("name" -> record).
var timing: Dictionary = {}
## Random one-off idle variants (cspecial1..N) played from "cidle".
var idle_specials := true
var _special := false
var _rng := RandomNumberGenerator.new()

func build(data: ELProfile, model: String, texture_name: String, secondary_texture := "") -> bool:
	set_process(false)
	profile = data
	template = ELArchive.key(model)
	if not profile.model_resources.has(template):
		var package := ELArchive.from_bytes(profile.figure(template + ".mod"))
		if not package.error.is_empty():
			error = template + ": " + package.error
			return false
		var hierarchy := ELFigure.hierarchy(package.read(template))
		var parsed_figures := {}
		var meshes := {}
		for link: Array in hierarchy:
			var parsed := ELFigure.parse(package.read(link[0]))
			if not parsed.is_empty():
				parsed_figures[link[0]] = parsed
				meshes["base/" + link[0]] = ELFigure.mesh(parsed)
		var animations: ELArchive
		var animation_bytes := profile.figure(template + ".anm")
		if ELArchive.is_archive(animation_bytes):
			animations = ELArchive.from_bytes(animation_bytes)
		profile.model_resources[template] = {"links": hierarchy, "figures": parsed_figures,
			"meshes": meshes, "animations": animations, "clips": {},
			"timing": animation_table(profile.read("animdb", template + ".adb"))}
	var resources: Dictionary = profile.model_resources[template]
	var links: Array = resources.links
	figures = resources.figures
	_mesh_cache = resources.meshes
	clips = resources.clips
	_animations = resources.animations
	timing = resources.get("timing", {})
	_rng.seed = hash(template)
	var material := ELFigure.material(profile.texture(texture_name))
	var secondary := ELFigure.material(profile.texture(secondary_texture)) if not secondary_texture.is_empty() else material
	for link: Array in links:
		var name: String = link[0]
		var node := MeshInstance3D.new()
		node.name = name.replace(".", "_")
		parts[name] = node
		if figures.has(name) and name not in EFFECT_ANCHORS:
			node.mesh = _mesh_cache["base/" + name]
			node.material_override = secondary if int(figures[name].texture_slot) == 1 else material
		# Anchors may parent real geometry (the illusion wall uses "dust" as its
		# root). Omit only their helper mesh; hiding the node hides descendants too.
	for link: Array in links:
		var node: Node3D = parts[link[0]]
		var parent: Node3D = parts.get(link[1], self)
		parent.add_child(node)
	if _animations != null and _animations.has("cidle"):
		play("cidle")
	return not parts.is_empty()

## Fades the whole figure (1 = opaque); used for the pale aspect's pulse.
## Fades the whole figure. Per-figure blended copies of its materials are used
## because instance transparency does not apply to the compatibility renderer.
func set_opacity(alpha: float) -> void:
	for node: MeshInstance3D in parts.values():
		if alpha >= 1.0:
			if node.has_meta("opaque"): node.material_override = node.get_meta("opaque")
			continue
		if not node.has_meta("opaque"): node.set_meta("opaque", node.material_override)
		# Parts without an override fade a copy of their mesh surface material.
		var opaque := node.get_meta("opaque") as StandardMaterial3D
		if opaque == null: opaque = node.get_active_material(0) as StandardMaterial3D
		if opaque == null: continue
		if not _faded.has(opaque):
			var faded: StandardMaterial3D = opaque.duplicate()
			faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_faded[opaque] = faded
		var material: StandardMaterial3D = _faded[opaque]
		material.albedo_color.a = alpha
		node.material_override = material

func play(name: String) -> bool:
	if _animations == null or not _animations.has(name):
		return false
	if not clips.has(name):
		var arc := ELArchive.from_bytes(_animations.read(name))
		var tracks := {}
		for part: String in arc.entries:
			if parts.has(part):
				var decoded := ELFigure.track(arc.read(part))
				if not decoded.is_empty():
					tracks[part] = decoded
		clips[name] = tracks
	clip = name
	_special = false
	_clip_frames = 1
	if timing.has(name):
		# The clip lasts its recorded frame count; tracks hold their last key.
		_clip_frames = int(timing[name].frames) + 1
	else:
		# Without a record, use the motion keys; leftover scale tracks run longer
		# than the clip and must not stretch it.
		for track: Dictionary in clips[name].values():
			_clip_frames = maxi(_clip_frames, maxi(int(track.rotation_count), maxi(int(track.position_count), int(track.morph_frames))))
	frame = 0.0
	playing = true
	set_process(true)
	_previous_morphs.clear()
	for part: String in figures:
		if part in EFFECT_ANCHORS: continue
		var key := name + "/" + part
		if not _mesh_cache.has(key):
			_mesh_cache[key] = ELFigure.mesh(figures[part], clips[name].get(part, {}))
		parts[part].mesh = _mesh_cache[key]
	apply_frame(0.0)
	animation_started.emit(name)
	return true

func _process(delta: float) -> void:
	if not playing or clip.is_empty():
		return
	var length := clip_frames()
	frame += delta * fps * speed
	if frame >= length - 1 and _special:
		# A variant plays once, then the figure returns to its idle.
		play("cidle")
		return
	if frame >= length - 1:
		if clip.begins_with("c"):
			frame = fmod(frame, maxf(1, length - 1))
			animation_looped.emit(clip)
		else:
			frame = length - 1
			playing = false
			animation_finished.emit(clip)
	apply_frame(frame)
	set_process(playing)
	if playing and clip == "cidle" and idle_specials and _rng.randf() < 0.04 * delta:
		_play_special()

func clip_frames() -> int:
	return _clip_frames

## The clip the figure rests in: "cidle" while an idle variant plays.
func base_clip() -> String:
	return "cidle" if _special else clip

## Idle variants are numbered from 1; the first missing number ends the set.
func special_count() -> int:
	var count := 0
	while _animations != null and _animations.has("cspecial%d" % (count + 1)): count += 1
	return count

func _play_special() -> void:
	var count := special_count()
	if count == 0: return
	if play("cspecial%d" % (_rng.randi() % count + 1)): _special = true

## Seconds a clip lasts at the original rate (frames / 30).
func clip_seconds(name: String) -> float:
	if timing.has(name): return float(timing[name].frames) / 30.0
	return -1.0

## Animation table (.adb): 0x58-byte clip records after a 0x2C header. Keeps
## the frame count, loop flag, move speed, event frames and impact frame.
static func animation_table(bytes: PackedByteArray) -> Dictionary:
	var result := {}
	if bytes.size() < 0x2c or bytes.slice(0, 3).get_string_from_ascii() != "ADB": return result
	var count := bytes.decode_u32(4)
	for index: int in count:
		var at := 0x2c + index * 0x58
		if at + 0x58 > bytes.size(): break
		var name := bytes.slice(at, at + 16).get_string_from_ascii().to_lower()
		var events: Array[int] = []
		for slot: int in 4:
			var value := bytes.decode_u32(at + 0x30 + slot * 4)
			if value > 0: events.append(value)
		var flags := bytes.decode_u32(at + 0x18)
		result[name] = {"frames": bytes.decode_u32(at + 0x20), "loop": (bytes.decode_u32(at + 0x14) & 0x80000000) != 0,
			"speed": bytes.decode_float(at + 0x24), "events": events,
			"impact": bytes.decode_u32(at + 0x40) if flags & 4 else -1}
	return result

func apply_frame(at: float) -> void:
	sample_count += 1
	for name: String in clips.get(clip, {}):
		var track: Dictionary = clips[clip][name]
		var node: MeshInstance3D = parts[name]
		var bytes: PackedByteArray = track.data
		var rc: int = track.rotation_count
		if rc > 0:
			var f := clampf(at, 0, rc - 1)
			var a := int(f)
			var b := mini(a + 1, rc - 1)
			node.quaternion = ELFigure.quaternion(bytes, track.rotation_offset + a * 16).slerp(
				ELFigure.quaternion(bytes, track.rotation_offset + b * 16), f - a)
		node.position = _vec_sample(track, "position", at, Vector3.ZERO)
		node.scale = _vec_sample(track, "scale", at, Vector3.ONE, true)
		var mc: int = track.morph_frames
		if mc > 0 and node.mesh != null:
			for previous: int in _previous_morphs.get(name, []):
				node.set_blend_shape_value(previous, 0.0)
			var f := clampf(at, 0, mc - 1)
			var a := int(f)
			var b := mini(a + 1, mc - 1)
			node.set_blend_shape_value(a, 1.0 - (f - a) if a != b else 1.0)
			if a != b:
				node.set_blend_shape_value(b, f - a)
			_previous_morphs[name] = [a, b]

func _vec_sample(track: Dictionary, field: String, at: float, default: Vector3, scaling := false) -> Vector3:
	var count: int = track[field + "_count"]
	if count == 0:
		return default
	var bytes: PackedByteArray = track.data
	var f := clampf(at, 0, count - 1)
	var a := int(f)
	var b := mini(a + 1, count - 1)
	var off: int = track[field + "_offset"]
	var first := Vector3(bytes.decode_float(off + a * 12), bytes.decode_float(off + a * 12 + 4), bytes.decode_float(off + a * 12 + 8))
	var second := Vector3(bytes.decode_float(off + b * 12), bytes.decode_float(off + b * 12 + 4), bytes.decode_float(off + b * 12 + 8))
	var value := first.lerp(second, f - a)
	return Vector3(value.x, value.z, value.y) if scaling else ELFigure.vector(value)
