class_name ELModel
extends Node3D
signal animation_finished(clip: String)
## A clip started (combat effects start the figure's own particles with it).
signal animation_started(clip: String)
## A looping clip ("c" prefix) wrapped round to its first frame.
signal animation_looped(clip: String)
## The clip passed one of its recorded event frames (footfalls of walk/run).
signal frame_event(clip: String)
const EFFECT_ANCHORS := ["cast", "dust", "numbers", "soul", "b_point"]
const HIT_FLASH := preload("res://src/render/model_hit_flash.gdshader")

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
## Adventure fog can hide a figure without stopping its animation clock or cues.
var skip_hidden_pose := false
var _pose_stale := false
var _faded: Dictionary = {}
## Made wholly of the Magic material: the second game's colourless creatures.
var colourless := false
var error := ""
var sample_count := 0
var _animations: ELArchive
var _mesh_cache: Dictionary = {}
var _clip_prefetch_task := -1
var _clip_prefetch_name := ""
var _clip_prefetch_tracks: Dictionary = {}
var _clip_prefetch_parts: Array[Dictionary] = []
var _previous_morphs: Dictionary = {}
var _clip_frames := 1
## Clip records of the figure's animation table ("name" -> record).
var timing: Dictionary = {}
## Random one-off idle variants (cspecial1..N) played from "cidle".
var idle_specials := true
var _special := false
## An idle variant was chosen and waits for the idle cycle to end.
var _special_waiting := false
var _rng := RandomNumberGenerator.new()
## Parts that turn to metal where their skin's mask says: name ->
## [material, "main" or "second" skin], and the masks' key (ELMetalMasks).
var _metal_parts := {}
var _metal_key := ""
## Temporary hit tints keep the underlying cutout and any previous overlay.
var _flash_overlays: Dictionary = {}
var _flash_tween: Tween

## Reads and parses a model's figures and animation archive once per
## profile (shared by every figure of it). Returns "" or the error.
static func prepare(profile: ELProfile, model: String) -> String:
	var template := ELArchive.key(model)
	if profile.model_resources.has(template): return ""
	var resources := parse_resources(template, read_resources(profile, template))
	if resources.has("error"): return String(resources.error)
	profile.model_resources[template] = resources
	return ""

## The stored files of a model (figures, animations, clip table), read on
## the main thread for parse_resources.
static func read_resources(profile: ELProfile, template: String) -> Dictionary:
	return {"figures": profile.figure(template + ".mod"), "animations": profile.figure(template + ".anm"),
		"timing": profile.read("animdb", template + ".adb"), "edition": profile.id}

## Parses a model's files (read_resources) into its shared resources, or
## {"error": ...}. Touches nothing shared, so worker threads may run it.
static func parse_resources(template: String, files: Dictionary) -> Dictionary:
	var package := ELArchive.from_bytes(files.figures)
	if not package.error.is_empty(): return {"error": template + ": " + package.error}
	var hierarchy := ELFigure.hierarchy(package.read(template))
	var parsed_figures := {}
	var meshes := {}
	for link: Array in hierarchy:
		var parsed := ELFigure.parse(package.read(link[0]))
		if not parsed.is_empty():
			ELFigure.one_sided_faces(parsed, template, link[0], String(files.get("edition", "")))
			parsed_figures[link[0]] = parsed
			meshes["base/" + link[0]] = ELFigure.mesh(parsed)
	var animations: ELArchive
	if ELArchive.is_archive(files.animations):
		animations = ELArchive.from_bytes(files.animations)
	return {"links": hierarchy, "figures": parsed_figures,
		"meshes": meshes, "animations": animations, "clips": {},
		"timing": animation_table(files.timing)}

## A decoded clip's deforming part meshes (keys as the figure's mesh cache),
## for worker threads like decode_clip. Rigid parts use the shared base mesh:
## another copy for every idle, attack and movement clip wastes GPU buffers.
static func clip_meshes(figures: Dictionary, name: String, tracks: Dictionary) -> Dictionary:
	var meshes := {}
	for part: String in figures:
		if part in EFFECT_ANCHORS: continue
		var track: Dictionary = tracks.get(part, {})
		if int(track.get("morph_frames", 0)) > 0 and int(track.get("morph_vertices", 0)) > 0:
			meshes[name + "/" + part] = ELFigure.mesh(figures[part], track)
	return meshes

## Decodes a clip's tracks for the parts named in `links` (pure data work:
## a loading screen runs it on worker threads).
static func decode_clip(animations: ELArchive, name: String, links: Array) -> Dictionary:
	var names := {}
	for link: Array in links: names[link[0]] = true
	var arc := ELArchive.from_bytes(animations.read(name))
	var tracks := {}
	for part: String in arc.entries:
		if names.has(part):
			var decoded := ELFigure.track(arc.read(part))
			if not decoded.is_empty():
				tracks[part] = decoded
	return tracks

func build(data: ELProfile, model: String, texture_name: String, secondary_texture := "", wave_texture := "") -> bool:
	_finish_clip_prefetch()
	set_process(false)
	profile = data
	template = ELArchive.key(model)
	error = prepare(profile, model)
	if not error.is_empty(): return false
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
	var wave := profile.texture(wave_texture) if not wave_texture.is_empty() else null
	var wave_material: StandardMaterial3D
	if wave != null:
		wave_material = ELFigure.material(wave, true)
		wave_material.set_meta("water_surface", true)
	# A map object's animated texture (AnimTexture, AnimatedTexture) dresses its
	# parts outside slot 2, which wear the row's Texture: the second game's
	# posts stand on the race pedestal sheet (S_VPedestal, C_KPedestal) and the
	# mana nodes' flames are the Mana sheets. Slot 14 is the water collar.
	var animated := ELFigure.material(wave) if wave != null else null
	# Alpha32 skins (air walls, spirits) fade out in soft alpha, such as a wall's
	# wispy lower dress: blend them instead of the half-alpha cut-off.
	for pair: Array in [[material, texture_name], [secondary, secondary_texture]]:
		var skin := pair[0].albedo_texture as Texture2D
		if String(pair[1]).to_lower().contains("alpha32") or (skin != null and skin.has_meta("alpha32")):
			pair[0].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	var authored_materials := {}
	_metal_parts.clear()
	var separate_second := not secondary_texture.is_empty() and ELArchive.key(secondary_texture) != ELArchive.key(texture_name)
	# The original lights Magic parts at full brightness (emissive 1.0). The
	# colourless creatures are made wholly of them, and drawn so they looked
	# overlit beside shaded figures (player report #98): the remake shades
	# them once materialised and keeps the glow for their pale aspect
	# (set_opacity). Glowing parts of other figures stay as the original.
	# Only creature figures (cr battle, ad map models) count: map objects (the
	# second game's posts, rocks, beacons, shrines) and the Green Lord are made
	# wholly of Magic too and keep the original's full brightness, else their
	# faceted shapes broke into dark stripes.
	colourless = false
	for link: Array in (links if is_creature_template(template) else []):
		if figures.has(link[0]) and link[0] not in EFFECT_ANCHORS:
			if int(figures[link[0]].material_id) != ELFigure.MATERIAL_MAGIC:
				colourless = false
				break
			colourless = true
	var figure_metal := has_metal(template)
	for link: Array in links:
		var name: String = link[0]
		var node := MeshInstance3D.new()
		node.name = name.replace(".", "_")
		parts[name] = node
		if figures.has(name) and name not in EFFECT_ANCHORS:
			node.mesh = _mesh_cache["base/" + name]
			# Slot 2 parts wear the second texture (mounts, staffs, wings: the
			# Add/Transport sheets); slot 1 and 8 parts the first.
			var slot := int(figures[name].texture_slot)
			var part_material := secondary if slot == 2 else material
			# The FIG's animated texture slot carries the wave collar at the waterline.
			if slot == 14 and wave_material != null:
				node.material_override = wave_material
				continue
			if slot != 2 and animated != null: part_material = animated
			var material_id := int(figures[name].material_id)
			var fullbright := material_id == ELFigure.MATERIAL_MAGIC and not colourless
			var diffuse := profile.figure_diffuse(material_id)
			if fullbright or diffuse != Color.WHITE:
				var key := [part_material, material_id]
				if not authored_materials.has(key):
					var authored := part_material.duplicate() as StandardMaterial3D
					authored.albedo_color = diffuse
					if fullbright:
						authored.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						authored.set_meta(ELFigure.AUTHORED_FULLBRIGHT, true)
					authored_materials[key] = authored
				part_material = authored_materials[key]
			# Armour and weapons, which the originals light as matte as cloth.
			# Figures only: map objects' "plate" and "chain" parts are rock slabs
			# and shop signs, which turned to shiny metal.
			if figure_metal and material_id != ELFigure.MATERIAL_MAGIC and part_material.albedo_texture != null and not ELFigure.is_cloth(template, name):
				_metal_parts[name] = [part_material, "second" if slot == 2 and separate_second else "main"]
			node.material_override = part_material
		# Anchors may parent real geometry (the illusion wall uses "dust" as its
		# root). Omit only their helper mesh; hiding the node hides descendants too.
	var culled := {}
	for name: String in parts:
		var node: MeshInstance3D = parts[name]
		var one_sided_part: bool = figures.has(name) and figures[name].get("one_sided", false)
		if not (one_sided_part or ELFigure.is_back_culled(template, name)) or not node.material_override is BaseMaterial3D: continue
		if not culled.has(node.material_override):
			var one_sided := node.material_override.duplicate() as BaseMaterial3D
			one_sided.cull_mode = BaseMaterial3D.CULL_BACK
			culled[node.material_override] = one_sided
		node.material_override = culled[node.material_override]
		# Its metal is made from the one-sided copy, so armour drawn one-sided
		# (helmets, shoulder plates) still turns to metal.
		if _metal_parts.has(name): _metal_parts[name][0] = node.material_override
	# Track keys are model-space transforms, so every part hangs from the
	# model itself. The .lnk tree only names the parts: nested under their
	# parents, the kobolds' five-deep limbs (cr206-cr209) drifted metres above
	# the body, and "head"/"dust" roots offset the other parts.
	for link: Array in links:
		add_child(parts[link[0]])
	_dress_metal(texture_name, secondary_texture)
	if _animations != null and _animations.has("cidle"):
		play("cidle")
	return not parts.is_empty()

## A creature figure: a battle (cr) or map (ad) model.
static func is_creature_template(name: String) -> bool:
	var key := ELArchive.key(name)
	return key.begins_with("cr") or key.begins_with("ad")

## A hero or creature figure, whose armour and weapons may turn to metal.
static func has_metal(name: String) -> bool:
	return is_creature_template(name) or ELArchive.key(name).begins_with("he")

## Dresses the armour and weapons in metal where their skins' masks
## (ELMetalMasks) say: now when the masks are ready, else as soon as they are
## worked out (the figure is drawn without metal until then).
func _dress_metal(texture_name: String, secondary_texture: String) -> void:
	if _metal_parts.is_empty(): return
	if profile.metal_masks == null: profile.metal_masks = ELMetalMasks.new(profile.id)
	var masks: ELMetalMasks = profile.metal_masks
	_metal_key = ELMetalMasks.key(template, texture_name, secondary_texture)
	var found: Variant = masks.lookup(profile, template, texture_name, secondary_texture)
	if found != null: _wear_metal(found)
	elif not masks.finished.is_connected(_metal_ready): masks.finished.connect(_metal_ready)

func _metal_ready(key: String) -> void:
	if key != _metal_key: return
	profile.metal_masks.finished.disconnect(_metal_ready)
	var started := Time.get_ticks_usec()
	var found: Variant = profile.metal_masks.ready_masks(key)
	if found != null: _wear_metal(found)
	ELMetalMasks.spent(Time.get_ticks_usec() - started)

## Swaps the parts' materials for metal ones; parts showing another look (a
## fade, an effect's override) get theirs when they return to their own.
func _wear_metal(masks: Dictionary) -> void:
	var made := {}
	for name: String in _metal_parts:
		var base: StandardMaterial3D = _metal_parts[name][0]
		var mask: Texture2D = masks.get(_metal_parts[name][1])
		if mask == null: continue
		if not made.has(base): made[base] = ELFigure.metal_material(base, mask)
		var node: MeshInstance3D = parts[name]
		if node.material_override == base: node.material_override = made[base]
		if node.has_meta("opaque") and node.get_meta("opaque") == base: node.set_meta("opaque", made[base])
	_metal_parts.clear()

## Fades the whole figure (1 = opaque); used for the pale aspect's pulse.
## A colourless creature's faded copies glow at full brightness, as the
## original draws its Magic material; opaque, it is shaded (#98).
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
			if colourless:
				faded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				faded.set_meta(ELFigure.AUTHORED_FULLBRIGHT, true)
			_faded[opaque] = faded
		var material: StandardMaterial3D = _faded[opaque]
		material.albedo_color.a = alpha
		node.material_override = material

## A brief, smoothly fading hit tint, carried weapons included. Preserve
## cutout silhouettes, soft-alpha/fading figures and other overlays. A
## repeated hit restarts the pulse rather than letting an older timer end it.
func flash(color: Color, seconds: float) -> void:
	if not is_inside_tree() or seconds <= 0.0: return
	if _flash_tween != null and _flash_tween.is_valid(): _flash_tween.kill()
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null or part.mesh.get_surface_count() == 0: continue
		var base := part.get_active_material(0) as BaseMaterial3D
		# Particle sprites and additive weapon glows keep their own effects.
		if base == null or base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX: continue
		var entry: Dictionary = _flash_overlays.get(part, {})
		if entry.is_empty() or part.material_overlay != entry.material:
			var material := ShaderMaterial.new()
			material.shader = HIT_FLASH
			entry = {"material": material, "previous": part.material_overlay, "base": null}
			_flash_overlays[part] = entry
			part.material_overlay = material
		(entry.material as ShaderMaterial).set_shader_parameter("flash_colour", color)
	_set_flash_strength(1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash_strength, 1.0, 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_callback(_finish_flash)

func _set_flash_strength(strength: float) -> void:
	for key: Variant in _flash_overlays:
		if not is_instance_valid(key): continue
		var part := key as MeshInstance3D
		var entry: Dictionary = _flash_overlays[part]
		if part.material_overlay != entry.material: continue
		var material := entry.material as ShaderMaterial
		var base := part.get_active_material(0) as BaseMaterial3D
		var eligible := base != null and base.blend_mode == BaseMaterial3D.BLEND_MODE_MIX
		material.set_shader_parameter("strength", strength if eligible else 0.0)
		if not eligible: continue
		# Opacity can change during a hit (a pale aspect or departure fade).
		material.set_shader_parameter("figure_opacity", clampf(base.albedo_color.a, 0.0, 1.0))
		# Animated skins can move their atlas window without replacing the material.
		material.set_shader_parameter("skin_uv", Vector4(base.uv1_scale.x, base.uv1_scale.y, base.uv1_offset.x, base.uv1_offset.y))
		if entry.base == base: continue
		entry.base = base
		material.set_shader_parameter("skin", base.albedo_texture)
		material.set_shader_parameter("repeat_skin", base.texture_repeat)
		material.set_shader_parameter("alpha_enabled", base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
		material.set_shader_parameter("cutout", base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
		material.set_shader_parameter("alpha_cutoff", base.alpha_scissor_threshold)

func _finish_flash() -> void:
	for key: Variant in _flash_overlays:
		if not is_instance_valid(key): continue
		var part := key as MeshInstance3D
		var entry: Dictionary = _flash_overlays[part]
		if part.material_overlay == entry.material: part.material_overlay = entry.previous
	_flash_overlays.clear()
	_flash_tween = null

## Prepare an upcoming clip while the camera moves to the speaker. Each
## deforming part is independent, so a long clip can use several workers.
func prefetch_clip(name: String) -> void:
	if not is_inside_tree() or not has_clip(name) or _clip_prefetch_name == name: return
	# The dummy renderer cannot create mesh resources concurrently.
	if DisplayServer.get_name() == "headless": return
	if OS.has_feature("web") and not OS.has_feature("threads"): return
	_finish_clip_prefetch()
	var resources: Dictionary = profile.model_resources[template]
	var tracks: Dictionary = clips[name] if clips.has(name) else decode_clip(_animations, name, resources.links)
	var jobs: Array[Dictionary] = []
	for part: String in tracks:
		if part in EFFECT_ANCHORS or not figures.has(part): continue
		var key := name + "/" + part
		if _mesh_cache.has(key): continue
		var track: Dictionary = tracks[part]
		if int(track.get("morph_frames", 0)) > 0 and int(track.get("morph_vertices", 0)) > 0:
			jobs.append({"key": key, "figure": figures[part], "track": track})
	if jobs.is_empty():
		clips[name] = tracks
		return
	_clip_prefetch_name = name
	_clip_prefetch_tracks = tracks
	_clip_prefetch_parts = jobs
	_clip_prefetch_task = WorkerThreadPool.add_group_task(func(index: int) -> void:
		var job := jobs[index]
		job.mesh = ELFigure.mesh(job.figure, job.track), jobs.size(), -1, false, "Map speech animation")

func _finish_clip_prefetch() -> void:
	if _clip_prefetch_task < 0: return
	WorkerThreadPool.wait_for_group_task_completion(_clip_prefetch_task)
	if not clips.has(_clip_prefetch_name): clips[_clip_prefetch_name] = _clip_prefetch_tracks
	for job: Dictionary in _clip_prefetch_parts:
		if not _mesh_cache.has(job.key): _mesh_cache[job.key] = job.mesh
	_clip_prefetch_task = -1
	_clip_prefetch_name = ""
	_clip_prefetch_tracks = {}
	_clip_prefetch_parts = []

func _exit_tree() -> void:
	_finish_clip_prefetch()

func play(name: String) -> bool:
	if _animations == null or not _animations.has(name):
		return false
	if _clip_prefetch_name == name: _finish_clip_prefetch()
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
	if name != "cidle": _special_waiting = false
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
	# A part keeps its blend shape weights when its mesh changes, so the last
	# clip's morph frames would add to the new clip's.
	for part: String in _previous_morphs:
		for previous: int in _previous_morphs[part]:
			parts[part].set_blend_shape_value(previous, 0.0)
	_previous_morphs.clear()
	for part: String in figures:
		if part in EFFECT_ANCHORS: continue
		var track: Dictionary = clips[name].get(part, {})
		if int(track.get("morph_frames", 0)) == 0 or int(track.get("morph_vertices", 0)) == 0:
			parts[part].mesh = _mesh_cache["base/" + part]
			continue
		var key := name + "/" + part
		if not _mesh_cache.has(key):
			_mesh_cache[key] = ELFigure.mesh(figures[part], track)
		parts[part].mesh = _mesh_cache[key]
	apply_frame(0.0)
	animation_started.emit(name)
	return true

func _process(delta: float) -> void:
	if not playing or clip.is_empty():
		return
	var length := clip_frames()
	var before := frame
	frame += delta * fps * speed
	_frame_events(before, frame, length)
	if frame >= length - 1 and _special:
		# A variant plays once, then the figure returns to its idle.
		play("cidle")
		return
	if frame >= length - 1:
		if clip == "cidle" and _special_waiting:
			# The variant chosen during the cycle starts as the cycle ends
			# (original EL1/EL2 idle cycle callback, EL2).
			_special_waiting = false
			_play_special()
			return
		if clip.begins_with("c"):
			frame = fmod(frame, maxf(1, length - 1))
			animation_looped.emit(clip)
		else:
			frame = length - 1
			playing = false
			animation_finished.emit(clip)
	if skip_hidden_pose and not is_visible_in_tree(): _pose_stale = true
	else: apply_frame(frame)
	set_process(playing)
	if playing and clip == "cidle" and idle_specials and not _special_waiting and _rng.randf() < 0.04 * delta:
		_special_waiting = special_count() > 0

## Emits frame_event for each recorded event frame in (from, to], also
## across a looping clip's wrap (original EL1 / EL2).
func _frame_events(from: float, to: float, length: int) -> void:
	var events: Array = timing.get(clip, {}).get("events", [])
	if events.is_empty(): return
	var span := maxf(1.0, length - 1)
	for e: int in events:
		var at := float(e)
		if (at > from and at <= to) or (clip.begins_with("c") and to >= span and at <= to - span):
			frame_event.emit(clip)

func clip_frames() -> int:
	return _clip_frames

## The clip the figure rests in: "cidle" while an idle variant plays.
func has_clip(name: String) -> bool:
	return _animations != null and _animations.has(name)

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

## The clip recorded under an original clip code (the record's with
## its low bits cleared), or "". The originals pick movement clips by code:
## many second-game models store their run clip under the walk code.
func clip_for_code(code: int) -> String:
	for name: String in timing:
		if int(timing[name].get("code", 0)) == code and has_clip(name): return name
	return ""

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
			"code": bytes.decode_u32(at + 0x14) & 0xffff8000,
			"speed": bytes.decode_float(at + 0x24), "events": events,
			"impact": bytes.decode_u32(at + 0x40) if flags & 4 else -1, "mark": bytes.decode_u32(at + 0x40)}
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _pose_stale and is_visible_in_tree():
		apply_frame(frame)

func apply_frame(at: float) -> void:
	_pose_stale = false
	sample_count += 1
	for name: String in clips.get(clip, {}):
		var track: Dictionary = clips[clip][name]
		var node: MeshInstance3D = parts[name]
		var rotations: Array[Quaternion] = track.rotation_keys
		var rc := rotations.size()
		if rc > 0:
			var f := clampf(at, 0, rc - 1)
			var a := int(f)
			var b := mini(a + 1, rc - 1)
			node.quaternion = rotations[a] if a == b else rotations[a].slerp(rotations[b], f - a)
		node.position = _vec_sample(track.position_keys, at, Vector3.ZERO)
		node.scale = _vec_sample(track.scale_keys, at, Vector3.ONE)
		var mc: int = track.morph_frames
		if mc > 0 and node.mesh != null:
			var f := clampf(at, 0, mc - 1)
			var a := int(f)
			var b := mini(a + 1, mc - 1)
			var previous: Array = _previous_morphs.get(name, [])
			if previous.is_empty():
				previous = [-1, -1]
				_previous_morphs[name] = previous
			# Keep the two still-active shapes; zero only those we left. Reuse
			# the pair instead of allocating an Array for each part every frame.
			if previous[0] >= 0 and previous[0] != a and previous[0] != b:
				node.set_blend_shape_value(previous[0], 0.0)
			if previous[1] >= 0 and previous[1] != previous[0] and previous[1] != a and previous[1] != b:
				node.set_blend_shape_value(previous[1], 0.0)
			node.set_blend_shape_value(a, 1.0 - (f - a) if a != b else 1.0)
			if a != b:
				node.set_blend_shape_value(b, f - a)
			previous[0] = a
			previous[1] = b

## Local bounds of a rendered mesh part at its current pose. The mesh's
## culling box spans the whole clip, including space the pose does not occupy.
func posed_part_bounds(name: String) -> AABB:
	var part: MeshInstance3D = parts[name]
	var frames: Array = _previous_morphs.get(name, [])
	if frames.is_empty(): return part.get_aabb()
	var bounds: Array = part.mesh.get_meta("morph_bounds", [])
	if bounds.is_empty(): return part.get_aabb()
	var first: AABB = bounds[frames[0]]
	if frames[0] == frames[1]: return first
	var next: AABB = bounds[frames[1]]
	var weight := part.get_blend_shape_value(frames[1])
	return AABB(first.position.lerp(next.position, weight), first.size.lerp(next.size, weight))

func _vec_sample(keys: PackedVector3Array, at: float, default: Vector3) -> Vector3:
	var count := keys.size()
	if count == 0:
		return default
	var f := clampf(at, 0, count - 1)
	var a := int(f)
	var b := mini(a + 1, count - 1)
	return keys[a] if a == b else keys[a].lerp(keys[b], f - a)
