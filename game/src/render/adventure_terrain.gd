class_name ELAdventureTerrain
extends Node3D
const CELL := 2.0
const CHUNK := 16
# Four source border texels keep each tile isolated through mip level two.
# Both editions' atlas pitches are multiples of four (48 and 96).
const GUTTER := 4
## Only scenery and figures are visible to the reflected camera. The terrain,
## fog apron and selection markers all live on the main camera's layers.
const REFLECTION_LAYER := 1 << 16
var atlas: Texture2D
var material: ShaderMaterial
var errors: Array[String] = []
var combinations := 0
var animation_frames := 0
var build_usec := 0
var _tiles: ELTileSet
var _cache: Dictionary
var _water_bounds: Array[AABB] = []
var _reflection: SubViewport
var _mirror_camera: Camera3D
var _mirror_active := false

func _ready() -> void:
	set_process(false)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): _show_water_reflection(false))

func build(map: ELAdventureMap) -> bool:
	var started := Time.get_ticks_usec()
	if map.profile.terrain_tiles == null:
		var tiles := ELTileSet.new()
		if not tiles.load_file(map.profile.file("Resources/tileset.tsr")):
			errors.append(tiles.error)
			return false
		map.profile.terrain_tiles = tiles
	var tiles := map.profile.terrain_tiles
	_tiles = tiles
	var cached := map.profile.adventure_terrain_cache
	if cached.get("map") == map.id:
		_cache = cached
		atlas = cached.atlas
		material = cached.material
		animation_frames = cached.frames
		combinations = cached.combinations
		for y in range(0, map.height, CHUNK):
			for x in range(0, map.width, CHUNK): _build_chunk(map, Vector2i(x, y), cached.cells, cached.plans, cached.material)
		build_usec = Time.get_ticks_usec() - started
		return true
	var keys := {}
	var unique_plans := {}
	var compositions: Array[Dictionary] = []
	var cells := PackedInt32Array()
	cells.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			var corners: Array[int] = [map.tile(x, y), map.tile(x + 1, y), map.tile(x + 1, y + 1), map.tile(x, y + 1)]
			var original := corners.duplicate()
			var orientation := 0
			var highest := -1
			for turn in 4:
				var packed := 0
				for i in 4: packed |= original[(i + turn) % 4] << (i * 8)
				if packed > highest:
					highest = packed
					orientation = turn
			for i in 4: corners[i] = original[(i + orientation) % 4]
			# Cosmetic variation is deterministic and separate from game state.
			var seed_value := (x * 73856093 ^ y * 19349663) & 0x7fffffff
			var variation := seed_value % 3
			var key := "%s/%d" % [corners, variation]
			if not keys.has(key):
				var plan := tiles.plan(corners, variation)
				if plan.is_empty(): plan = tiles.plan(corners, 0)
				if plan.is_empty():
					errors.append("Missing terrain combination " + str(corners))
					return false
				var identity := JSON.stringify(plan.layers)
				if not unique_plans.has(identity):
					unique_plans[identity] = compositions.size()
					plan.water = plan.layers.any(func(layer: Dictionary) -> bool: return layer.water)
					plan.offset = animation_frames
					animation_frames += int(plan.frames)
					compositions.append(plan)
				keys[key] = unique_plans[identity]
			if compositions[keys[key]].frames == 1 and corners.count(corners[0]) == 4: orientation = (seed_value / 3) % 4
			cells[y * map.width + x] = keys[key] * 4 + orientation
	combinations = compositions.size()
	# Each stored tile repeats its outer ELTileSet.BORDER texels mirrored (a
	# filtering margin); a cell shows the inner square. The margin's texels
	# next to the inner square fill the atlas gutter.
	var inner := tiles.side - 2 * ELTileSet.BORDER
	var pitch := inner + 2 * GUTTER
	var columns := ceili(sqrt(animation_frames))
	var rows := ceili(animation_frames / float(columns))
	if columns * pitch > 8192 or rows * pitch > 8192:
		errors.append("Terrain atlas exceeds the texture limit.")
		return false
	var image := Image.create(columns * pitch, rows * pitch, false, Image.FORMAT_RGB8)
	var margin := ELTileSet.BORDER - GUTTER
	for plan: Dictionary in compositions:
		for frame in plan.frames:
			var tile := tiles.compose(plan, frame)
			var index: int = plan.offset + frame
			image.blit_rect(tile, Rect2i(margin, margin, pitch, pitch), Vector2i((index % columns) * pitch, (index / columns) * pitch))
	image.generate_mipmaps()
	atlas = ImageTexture.create_from_image(image)
	material = ShaderMaterial.new()
	material.shader = load("res://src/render/adventure_terrain.gdshader")
	material.set_shader_parameter("tiles", atlas)
	material.set_shader_parameter("columns", columns)
	material.set_shader_parameter("tile_side", inner)
	material.set_shader_parameter("pitch", pitch)
	material.set_shader_parameter("tile_margin", GUTTER)
	material.set_shader_parameter("atlas_size", Vector2(image.get_size()))
	# Keep only the most recently built map atlas per edition. Reloading a save
	# can reuse it without accumulating every visited chapter's textures.
	_cache = {"map": map.id, "atlas": atlas, "frames": animation_frames, "combinations": combinations, "cells": cells, "plans": compositions, "material": material,
		"water_masks_animate": map.profile.id == "el2"}
	map.profile.adventure_terrain_cache = _cache
	for y in range(0, map.height, CHUNK):
		for x in range(0, map.width, CHUNK):
			_build_chunk(map, Vector2i(x, y), cells, compositions, material)
	build_usec = Time.get_ticks_usec() - started
	return true

func set_detail(enabled: bool) -> void:
	if material != null: material.set_shader_parameter("detail_enabled", enabled)

func set_water(enabled: bool) -> void:
	if material == null: return
	if enabled and not _cache.has("water_format"):
		_cache.water_format = _water_format(_cache.plans)
	enabled = enabled and _cache.water_format != Image.FORMAT_MAX
	if enabled:
		if not _cache.has("water_weights"):
			var columns := int(material.get_shader_parameter("columns"))
			var rows := ceili(animation_frames / float(columns))
			# Red is all liquid coverage. Green is the bog share of that coverage.
			var weights := Image.create(columns * WEIGHT_PITCH, rows * WEIGHT_PITCH, false, _cache.water_format)
			for plan: Dictionary in _cache.plans:
				if not plan.layers.any(func(layer: Dictionary) -> bool: return layer.water): continue
				var has_bog: bool = plan.layers.any(func(layer: Dictionary) -> bool: return layer.bog)
				# EL1's shore overlays animate their colours with fixed coverage.
				var animated: bool = _cache.water_masks_animate and plan.layers.any(func(layer: Dictionary) -> bool:
					return layer.mask.get("ids", []).size() > 1 or layer.overlay.get("ids", []).size() > 1)
				var tile := _liquid_weight_tile(plan, has_bog, 0)
				for frame: int in plan.frames:
					if frame > 0 and animated: tile = _liquid_weight_tile(plan, has_bog, frame)
					_blit_weights(weights, tile, int(plan.offset) + frame, columns)
			_cache.water_weights = ImageTexture.create_from_image(weights)
		material.set_shader_parameter("water_weights", _cache.water_weights)
		material.set_shader_parameter("water_atlas_size", Vector2(_cache.water_weights.get_size()))
	material.set_shader_parameter("water_enabled", enabled)
	var reflect := enabled and DisplayServer.get_name() != "headless"
	set_process(reflect)
	if reflect: _update_water_reflection()
	else: _show_water_reflection(false)

func _process(_delta: float) -> void:
	_update_water_reflection()

func _update_water_reflection() -> void:
	var viewport := get_viewport()
	var source := viewport.get_camera_3d()
	var visible_water := is_visible_in_tree() and source != null and _water_in_view(source)
	if not visible_water:
		_show_water_reflection(false)
		return
	if _reflection == null:
		_reflection = SubViewport.new()
		_reflection.name = "WaterReflection"
		_reflection.transparent_bg = true
		_reflection.gui_disable_input = true
		_reflection.positional_shadow_atlas_size = 0
		_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_reflection)
		_reflection.world_3d = source.get_world_3d()
		_mirror_camera = Camera3D.new()
		_mirror_camera.cull_mask = REFLECTION_LAYER
		_reflection.add_child(_mirror_camera)
		_mirror_camera.current = true
		material.set_shader_parameter("water_reflection", _reflection.get_texture())
	var dimensions := viewport.get_texture().get_size()
	var scale_factor := minf(0.75, 1024.0 / maxf(dimensions.x, dimensions.y))
	_reflection.size = Vector2i((dimensions * scale_factor).round()).max(Vector2i(2, 2))
	_mirror_camera.keep_aspect = source.keep_aspect
	_mirror_camera.projection = source.projection
	_mirror_camera.fov = source.fov
	_mirror_camera.size = source.size
	_mirror_camera.near = source.near
	_mirror_camera.far = source.far
	var pose := source.get_camera_transform()
	var flip := Vector3(1.0, -1.0, 1.0)
	# Reflect around the map's y = 0 plane, then reverse the horizontal axis
	# to keep the camera right-handed. The water sampler flips its U back.
	_mirror_camera.global_transform = Transform3D(
		Basis(-pose.basis.x * flip, pose.basis.y * flip, pose.basis.z * flip), pose.origin * flip)
	_show_water_reflection(true)

func _show_water_reflection(on: bool) -> void:
	if on == _mirror_active: return
	_mirror_active = on
	_reflection.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	material.set_shader_parameter("water_reflection_enabled", on)

func _water_in_view(source: Camera3D) -> bool:
	var frustum := source.get_frustum()
	for bounds: AABB in _water_bounds:
		var outside := false
		for plane: Plane in frustum:
			var radius := plane.normal.abs().dot(bounds.size * 0.5)
			if plane.distance_to(bounds.get_center()) > radius:
				outside = true
				break
		if not outside: return true
	return false

func set_water_rain(areas: PackedVector4Array) -> void:
	if material == null: return
	var count := mini(areas.size(), ELSecondAmbience.MAX_ENTRIES)
	material.set_shader_parameter("water_rain_count", count)
	if count > 0:
		areas.resize(ELSecondAmbience.MAX_ENTRIES)
		material.set_shader_parameter("water_rain_areas", areas)

func _build_chunk(map: ELAdventureMap, origin: Vector2i, cells: PackedInt32Array, plans: Array[Dictionary], material: Material) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var data := PackedVector2Array()
	var indices := PackedInt32Array()
	var limit := (origin + Vector2i(CHUNK, CHUNK)).min(Vector2i(map.width, map.height))
	var contains_water := false
	for y in range(origin.y, limit.y):
		for x in range(origin.x, limit.x):
			var cell := cells[y * map.width + x]
			var plan: Dictionary = plans[cell / 4]
			contains_water = contains_water or plan.water
			var base := vertices.size()
			var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
			for i in 4:
				var corner := corners[i]
				vertices.append(Vector3((x + corner.x) * CELL, 0, -(y + corner.y) * CELL))
				uvs.append(Vector2(corners[posmod(i - cell % 4, 4)]))
				data.append(Vector2(plan.offset, plan.frames))
			indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	# Flat ground: up normals, which the sun's shadow lookup needs.
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = data
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var chunk := MeshInstance3D.new()
	chunk.mesh = mesh
	chunk.material_override = material
	chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chunk)
	if contains_water:
		_water_bounds.append(AABB(Vector3(origin.x, 0, -limit.y) * CELL,
			Vector3(limit.x - origin.x, 0, limit.y - origin.y) * CELL))

## Etherlords II colourless zones: per-level grey data for the terrain shader.
## Cells whose four corners are grey show the greyscale of their tile, cells
## with mixed corners take a grey weight from the planner composed with grey
## and coloured corner kinds (ELTileSet.GREY), so the zone edge follows the
## terrain's transition masks across the cells touching the zone. Built on a
## level switch only; weight tiles are kept per map for later switches.
const GREY_SIDE := 32
const WEIGHT_SIDE := GREY_SIDE
const WEIGHT_PITCH := WEIGHT_SIDE + 2

static func _water_format(plans: Array) -> Image.Format:
	var format := Image.FORMAT_MAX
	for plan: Dictionary in plans:
		for layer: Dictionary in plan.layers:
			if layer.bog: return Image.FORMAT_RG8
			if layer.water: format = Image.FORMAT_R8
	return format

func _liquid_weight_tile(plan: Dictionary, has_bog: bool, frame: int) -> Image:
	var liquid := _tiles.layer_weights(plan, WEIGHT_SIDE, "water", frame)
	var bog := _tiles.layer_weights(plan, WEIGHT_SIDE, "bog", frame) if has_bog else PackedByteArray()
	return _weight_tile(liquid, bog, _cache.water_format)

static func _weight_tile(bytes: PackedByteArray, second := PackedByteArray(), format := Image.FORMAT_R8) -> Image:
	# A one-texel border repeats the edge so filtering stays in the tile.
	var channels := 2 if format == Image.FORMAT_RG8 else 1
	var bordered := PackedByteArray()
	bordered.resize(WEIGHT_PITCH * WEIGHT_PITCH * channels)
	for y in WEIGHT_PITCH:
		var row := clampi(y - 1, 0, WEIGHT_SIDE - 1) * WEIGHT_SIDE
		for x in WEIGHT_PITCH:
			var source := row + clampi(x - 1, 0, WEIGHT_SIDE - 1)
			var target := (y * WEIGHT_PITCH + x) * channels
			bordered[target] = bytes[source]
			if not second.is_empty(): bordered[target + 1] = second[source]
	return Image.create_from_data(WEIGHT_PITCH, WEIGHT_PITCH, false, format, bordered)

static func _blit_weights(atlas: Image, tile: Image, index: int, columns: int) -> void:
	atlas.blit_rect(tile, Rect2i(0, 0, WEIGHT_PITCH, WEIGHT_PITCH), Vector2i((index % columns) * WEIGHT_PITCH, (index / columns) * WEIGHT_PITCH))

## Returns {"cells": Image (RGBA8, index low/high byte, quarter turns),
## "weights": Image (R8 atlas), "columns": int}. Index 0 = coloured,
## 1 = fully grey, n >= 2 = weight tile n - 2.
static func colorless_layer(map: ELAdventureMap, level: int) -> Dictionary:
	var tiles := map.profile.terrain_tiles
	var cache := map.profile.adventure_terrain_cache
	if cache.get("map") != map.id or tiles == null: return {}
	if not cache.has("grey_keys"):
		cache.grey_keys = {}
		cache.grey_tiles = []
	var keys: Dictionary = cache.grey_keys
	var weight_tiles: Array = cache.grey_tiles
	var flags := ELColorless.corner_flags(map, level)
	var stride := map.width + 1
	var data := PackedByteArray()
	data.resize(map.width * map.height * 4)
	for y in map.height:
		for x in map.width:
			var at := y * stride + x
			var grey := [flags[at], flags[at + 1], flags[at + stride + 1], flags[at + stride]]
			var count: int = grey.count(1)
			if count == 0: continue
			var index := 1
			var orientation := 0
			if count < 4:
				var original: Array[int] = [map.tile(x, y), map.tile(x + 1, y), map.tile(x + 1, y + 1), map.tile(x, y + 1)]
				for i in 4:
					if grey[i]: original[i] |= ELTileSet.GREY
				var highest := -1
				for turn in 4:
					var packed := 0
					for i in 4: packed |= original[(i + turn) % 4] << (i * 8)
					if packed > highest:
						highest = packed
						orientation = turn
				var corners: Array[int] = []
				for i in 4: corners.append(original[(i + orientation) % 4])
				var variation := ((x * 73856093 ^ y * 19349663) & 0x7fffffff) % 3
				var key := "%s/%d" % [corners, variation]
				if not keys.has(key):
					var plan := tiles.plan(corners, variation)
					if plan.is_empty(): plan = tiles.plan(corners, 0)
					keys[key] = weight_tiles.size()
					weight_tiles.append(tiles.grey_weights(plan, GREY_SIDE) if not plan.is_empty() else PackedByteArray())
				if (weight_tiles[keys[key]] as PackedByteArray).is_empty(): index = 1
				else: index = int(keys[key]) + 2
			var cell := (y * map.width + x) * 4
			data[cell] = index & 255
			data[cell + 1] = index >> 8
			data[cell + 2] = orientation
	var columns := maxi(1, ceili(sqrt(weight_tiles.size())))
	var rows := maxi(1, ceili(weight_tiles.size() / float(columns)))
	var atlas := Image.create(columns * WEIGHT_PITCH, rows * WEIGHT_PITCH, false, Image.FORMAT_R8)
	for i in weight_tiles.size():
		var bytes: PackedByteArray = weight_tiles[i]
		if bytes.is_empty(): continue
		_blit_weights(atlas, _weight_tile(bytes), i, columns)
	return {"cells": Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, data), "weights": atlas, "columns": columns}
