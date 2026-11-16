extends SceneTree
## Campaign map loading: the faster terrain atlas (worker threads, run-based
## blending, a shift for the division by 255, an RGBA atlas on the forward
## renderers), the threaded water weights and the map art read ahead give the
## same pixels as the plain one-texel-at-a-time composition, and the biggest
## chapter's terrain builds within a time budget (it took about 37 s before).
##   <godot> --headless --path game --script ../tools/campaign_load_check.gd
## Headless runs build the compatibility renderer's RGB atlas and read the
## map art one figure at a time; run it windowed (forward_plus) as well for
## the RGBA atlas and the art read on worker threads.

var failures: Array[String] = []

## Checks run and maps skipped (no game files), for the totals: skips still
## exit 0, so CI without the games passes, but are counted apart.
var checks := 0
var skipped := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _skip(reason: String) -> void:
	skipped += 1
	print("SKIP: " + reason)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	_division()
	for pair: Array in [["el1", "mission20", 1], ["el1", "mission261", 9], ["el2", "e2mission11", 11]]:
		if paths is not Dictionary or not paths.has(pair[0]):
			_skip("no %s files configured (user://profiles.json): %s" % [pair[0], pair[1]])
			continue
		var profile := ELProfile.new()
		if not profile.mount(pair[0], str(paths[pair[0]])):
			_skip("%s files could not be mounted: %s" % [pair[0], pair[1]])
			continue
		await _terrain(profile, pair[1], pair[2])
	if paths is Dictionary and paths.has("el2"):
		var profile := ELProfile.new()
		if profile.mount("el2", str(paths.el2)): await _budget(profile, "e2mission13", 12.0)
		if profile.mount("el2", str(paths.el2)): await _art(profile, "e2mission23")
	else: _skip("no el2 files: the time budget and map art are not checked")
	if paths is Dictionary and paths.has("el1"):
		var profile := ELProfile.new()
		if profile.mount("el1", str(paths.el1)): await _art(profile, "mission25")
	else: _skip("no el1 files: its map art is not checked")
	print("CAMPAIGN LOAD: %d check(s) run, %d part(s) skipped" % [checks, skipped])
	if skipped > 0: print("CAMPAIGN LOAD: SKIPPED %d part(s) for want of game files" % skipped)
	print("CAMPAIGN LOAD: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## (x + 1 + (x >> 8)) >> 8 is x / 255 for every blend sum.
func _division() -> void:
	var wrong := 0
	for x in 255 * 255 + 1:
		if (x + 1 + (x >> 8)) >> 8 != x / 255: wrong += 1
	check(wrong == 0, "the shifted division by 255 matches for every blend sum")

func _terrain(profile: ELProfile, map_id: String, stride: int) -> void:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, map_id):
		check(false, "%s loads" % map_id)
		return
	var terrain := ELAdventureTerrain.new()
	root.add_child(terrain)
	check(terrain.build(map), "%s: terrain builds" % map_id)
	var cache: Dictionary = profile.adventure_terrain_cache
	var tiles := profile.terrain_tiles
	var plans: Array = cache.plans
	# Tiles against the reference composition (every `stride`-th atlas slot).
	var slot := 0
	var compared := 0
	var differing := 0
	for plan: Dictionary in plans:
		for frame: int in plan.frames:
			if slot % stride == 0:
				compared += 1
				if tiles.compose(plan, frame).get_data() != _reference_compose(tiles, plan, frame): differing += 1
			slot += 1
	check(compared > 0 and differing == 0, "%s: %d composed terrain tiles match the reference (%d differ)" % [map_id, compared, differing])
	if stride == 1:
		# The whole atlas, mipmaps included, against a reference one in RGB.
		var columns := int(terrain.material.get_shader_parameter("columns"))
		var pitch := int(terrain.material.get_shader_parameter("pitch"))
		var size: Vector2 = terrain.material.get_shader_parameter("atlas_size")
		var reference := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGB8)
		var margin := ELTileSet.BORDER - ELAdventureTerrain.GUTTER
		for plan: Dictionary in plans:
			for frame: int in plan.frames:
				var tile := Image.create_from_data(tiles.side, tiles.side, false, Image.FORMAT_RGB8, _reference_compose(tiles, plan, frame))
				var index: int = plan.offset + frame
				reference.blit_rect(tile, Rect2i(margin, margin, pitch, pitch), Vector2i((index % columns) * pitch, (index / columns) * pitch))
		# The forward renderers' RGBA atlas: tiles widened, then mipmapped, on
		# an opaque black atlas, gives the RGB atlas widened after mipmapping.
		var wide := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
		wide.fill(Color.BLACK)
		for plan: Dictionary in plans:
			for frame: int in plan.frames:
				var tile := tiles.compose(plan, frame)
				tile.convert(Image.FORMAT_RGBA8)
				var index: int = plan.offset + frame
				wide.blit_rect(tile, Rect2i(margin, margin, pitch, pitch), Vector2i((index % columns) * pitch, (index / columns) * pitch))
		wide.generate_mipmaps()
		reference.generate_mipmaps()
		var widened: Image = reference.duplicate()
		widened.convert(Image.FORMAT_RGBA8)
		check(wide.get_data() == widened.get_data(), "%s: an RGBA atlas mipmapped equals the RGB one widened" % map_id)
		var built := (cache.atlas as ImageTexture).get_image()
		if built.get_format() != reference.get_format(): reference.convert(built.get_format())
		check(built.get_data() == reference.get_data(), "%s: the terrain atlas and its mipmaps match the reference" % map_id)
	# Water weights against the reference coverage.
	terrain.set_water(true)
	if cache.has("water_weights"):
		var weights := (cache.water_weights as ImageTexture).get_image()
		var columns := int(terrain.material.get_shader_parameter("columns"))
		var pitch := ELAdventureTerrain.WEIGHT_PITCH
		var off := 0
		var sampled := 0
		for plan: Dictionary in plans:
			if not plan.water: continue
			var has_bog: bool = plan.layers.any(func(layer: Dictionary) -> bool: return layer.bog)
			var liquid := _reference_weights(tiles, plan, ELAdventureTerrain.WEIGHT_SIDE, "water", 0)
			var bog := _reference_weights(tiles, plan, ELAdventureTerrain.WEIGHT_SIDE, "bog", 0) if has_bog else PackedByteArray()
			var expected := ELAdventureTerrain._weight_tile(liquid, bog, cache.water_format)
			var index := int(plan.offset)
			var got := weights.get_region(Rect2i((index % columns) * pitch, (index / columns) * pitch, pitch, pitch))
			sampled += 1
			if got.get_data() != expected.get_data(): off += 1
		check(off == 0, "%s: %d water weight tiles match the reference (%d differ)" % [map_id, sampled, off])
	terrain.queue_free()
	await process_frame

## The biggest second-game chapter's terrain within `seconds`.
func _budget(profile: ELProfile, map_id: String, seconds: float) -> void:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, map_id): return
	var terrain := ELAdventureTerrain.new()
	root.add_child(terrain)
	var started := Time.get_ticks_usec()
	terrain.build(map)
	terrain.set_water(true)
	var spent := (Time.get_ticks_usec() - started) / 1000000.0
	check(spent < seconds, "%s: terrain and water weights build in %.1f s (budget %.0f s)" % [map_id, spent, seconds])
	terrain.queue_free()
	await process_frame

## The art read ahead on worker threads is what each figure would read alone:
## the same figures, idle clip meshes and skins, and every object placed.
func _art(profile: ELProfile, map_id: String) -> void:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, map_id): return
	var session := ELAdventureSession.new()
	if not session.start(map, 1, 212, "", 1, false):
		check(false, "%s: session starts" % map_id)
		return
	var world := ELAdventureScene.new()
	root.add_child(world)
	check(world.build(map, session), "%s: map scene builds" % map_id)
	var placed := world.objects_loaded
	# A plain profile reads every figure one at a time, as before.
	var plain := ELProfile.new()
	plain.mount(profile.id, profile.root)
	var art := ELAdventureArt.new(map)
	var differing := 0
	var figures := 0
	for item: Dictionary in session.objects.values():
		if item.get("type") in ["hero", "monster"] and not item.get("alive", true): continue
		var definition := art.resolve(item)
		if definition.is_empty() or definition.get("hidden", false) or not item.get("visible", true): continue
		var template := ELArchive.key(str(definition.model))
		if not profile.model_resources.has(template): continue
		var one := ELModel.new()
		root.add_child(one)
		one.build(plain, definition.model, definition.texture, definition.secondary, definition.get("wave", ""))
		var ahead: Dictionary = profile.model_resources[template]
		var alone: Dictionary = plain.model_resources.get(template, {})
		figures += 1
		if alone.is_empty() or ahead.meshes.size() < alone.meshes.size() or ahead.clips.keys() != alone.clips.keys(): differing += 1
		else:
			for key: String in alone.meshes:
				var a: Mesh = ahead.meshes[key]
				var b: Mesh = alone.meshes[key]
				if a.get_surface_count() != b.get_surface_count() or (a.get_surface_count() > 0 and a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]):
					differing += 1
					break
		for name: String in [definition.texture, definition.secondary]:
			if name.is_empty(): continue
			var x := profile.texture(name)
			var y := plain.texture(name)
			if (x == null) != (y == null) or (x != null and x.get_image().get_data() != y.get_image().get_data()): differing += 1
		one.free()
		if figures >= 60: break
	check(placed > 0 and figures > 0 and differing == 0, "%s: %d objects placed; %d figures read ahead match their own reading (%d differ)" % [map_id, placed, figures, differing])
	world.queue_free()
	session.close()
	await process_frame

# The composition and coverage as they were worked out one texel at a time.

func _reference_compose(tiles: ELTileSet, composition: Dictionary, frame: int) -> PackedByteArray:
	var output := PackedByteArray()
	for layer: Dictionary in composition.layers:
		var grey: bool = layer.get("grey", false)
		var source: PackedByteArray = tiles.pixels[layer.source.ids[frame % layer.source.ids.size()]]
		if grey: source = ELTileSet._grey(source)
		if layer.mask.is_empty():
			var base := tiles._rotated(layer.source.ids[frame % layer.source.ids.size()], layer.rotation)
			output = ELTileSet._grey(base) if grey else base.duplicate()
			continue
		var mask := tiles._rotated(layer.mask.ids[frame % layer.mask.ids.size()], layer.rotation)
		for i in output.size(): output[i] = ((255 - int(mask[i])) * int(output[i]) + int(source[i]) * int(mask[i])) / 255
		if not layer.overlay.is_empty():
			var overlay := tiles._rotated(layer.overlay.ids[frame % layer.overlay.ids.size()], layer.rotation)
			for i in range(0, output.size(), 3):
				if overlay[i] != 255 or overlay[i + 1] != 0 or overlay[i + 2] != 255:
					var value := (int(overlay[i]) + int(overlay[i + 1]) + int(overlay[i + 2])) / 3 if grey else -1
					output[i] = overlay[i] if value < 0 else value
					output[i + 1] = overlay[i + 1] if value < 0 else value
					output[i + 2] = overlay[i + 2] if value < 0 else value
	for i in range(0, output.size(), 3):
		var blue := output[i]
		output[i] = output[i + 2]
		output[i + 2] = blue
	return output

func _reference_weights(tiles: ELTileSet, composition: Dictionary, out_side: int, flag: String, frame: int) -> PackedByteArray:
	var output := PackedByteArray()
	output.resize(out_side * out_side)
	var side := tiles.side
	var border := ELTileSet.BORDER
	var picks := PackedInt32Array()
	picks.resize(out_side * out_side)
	for y in out_side:
		for x in out_side:
			var inner := side - 2 * border
			picks[y * out_side + x] = ((border + (y * inner) / out_side + inner / (2 * out_side)) * side + border + (x * inner) / out_side + inner / (2 * out_side)) * 3
	for layer: Dictionary in composition.layers:
		var value := 255 if layer.get(flag, false) else 0
		if layer.mask.is_empty():
			output.fill(value)
			continue
		var mask := tiles._rotated(layer.mask.ids[frame % layer.mask.ids.size()], layer.rotation)
		var overlay := tiles._rotated(layer.overlay.ids[frame % layer.overlay.ids.size()], layer.rotation) if not layer.overlay.is_empty() else PackedByteArray()
		for i in picks.size():
			var at := picks[i]
			var m := int(mask[at])
			output[i] = ((255 - m) * int(output[i]) + value * m) / 255
			if not overlay.is_empty() and (overlay[at] != 255 or overlay[at + 1] != 0 or overlay[at + 2] != 255): output[i] = value
	return output
