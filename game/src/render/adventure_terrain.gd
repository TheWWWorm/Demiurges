class_name ELAdventureTerrain
extends Node3D
const CELL := 2.0
const CHUNK := 16
const GUTTER := 2
var atlas: Texture2D
var errors: Array[String] = []
var combinations := 0
var animation_frames := 0
var build_usec := 0

func build(map: ELAdventureMap) -> bool:
	var started := Time.get_ticks_usec()
	if map.profile.terrain_tiles == null:
		var tiles := ELTileSet.new()
		if not tiles.load_file(map.profile.file("Resources/tileset.tsr")):
			errors.append(tiles.error)
			return false
		map.profile.terrain_tiles = tiles
	var tiles := map.profile.terrain_tiles
	var cached := map.profile.adventure_terrain_cache
	if cached.get("map") == map.id:
		atlas = cached.atlas
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
	atlas = ImageTexture.create_from_image(image)
	var material := ShaderMaterial.new()
	material.shader = load("res://src/render/adventure_terrain.gdshader")
	material.set_shader_parameter("tiles", atlas)
	material.set_shader_parameter("columns", columns)
	material.set_shader_parameter("tile_side", inner)
	material.set_shader_parameter("pitch", pitch)
	material.set_shader_parameter("atlas_size", Vector2(image.get_size()))
	# Keep only the most recently built map atlas per edition. Reloading a save
	# can reuse it without accumulating every visited chapter's textures.
	map.profile.adventure_terrain_cache = {"map": map.id, "atlas": atlas, "frames": animation_frames, "combinations": combinations, "cells": cells, "plans": compositions, "material": material}
	for y in range(0, map.height, CHUNK):
		for x in range(0, map.width, CHUNK):
			_build_chunk(map, Vector2i(x, y), cells, compositions, material)
	build_usec = Time.get_ticks_usec() - started
	return true

func _build_chunk(map: ELAdventureMap, origin: Vector2i, cells: PackedInt32Array, plans: Array[Dictionary], material: Material) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var data := PackedVector2Array()
	var indices := PackedInt32Array()
	for y in range(origin.y, mini(origin.y + CHUNK, map.height)):
		for x in range(origin.x, mini(origin.x + CHUNK, map.width)):
			var cell := cells[y * map.width + x]
			var plan: Dictionary = plans[cell / 4]
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

## Etherlords II colourless zones: per-level grey data for the terrain shader.
## Cells whose four corners are grey show the greyscale of their tile, cells
## with mixed corners take a grey weight from the planner composed with grey
## and coloured corner kinds (ELTileSet.GREY), so the zone edge follows the
## terrain's transition masks across the cells touching the zone. Built on a
## level switch only; weight tiles are kept per map for later switches.
const GREY_SIDE := 32
const GREY_PITCH := GREY_SIDE + 2

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
	var atlas := Image.create(columns * GREY_PITCH, rows * GREY_PITCH, false, Image.FORMAT_R8)
	for i in weight_tiles.size():
		var bytes: PackedByteArray = weight_tiles[i]
		if bytes.is_empty(): continue
		# A one-texel border repeats the edge so filtering stays in the tile.
		var bordered := PackedByteArray()
		bordered.resize(GREY_PITCH * GREY_PITCH)
		for y in GREY_PITCH:
			var row := clampi(y - 1, 0, GREY_SIDE - 1) * GREY_SIDE
			for x in GREY_PITCH: bordered[y * GREY_PITCH + x] = bytes[row + clampi(x - 1, 0, GREY_SIDE - 1)]
		atlas.blit_rect(Image.create_from_data(GREY_PITCH, GREY_PITCH, false, Image.FORMAT_R8, bordered), Rect2i(0, 0, GREY_PITCH, GREY_PITCH), Vector2i((i % columns) * GREY_PITCH, (i / columns) * GREY_PITCH))
	return {"cells": Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, data), "weights": atlas, "columns": columns}
