extends SceneTree
## Headless check that every hero, creature and map object figure of the
## second game (and the first, where its folder is known) is dressed in real
## skins, as the battle and map build them:
##
## - every hero row (HeroTemplates, Shapes) finds its battle skins under
##   Heroes/ and its map skins in either figure folder (the Konung of Fire
##   and the elemental and spirit heroes wear creature skins; drawn white
##   when they were looked for under Heroes/ only);
## - every part of every map object model (AdditionalBuildings, Buildings,
##   TerrObj, mines, mana nodes, artefacts, shops) wears a decoded texture,
##   never the untextured white material, and does not sample mostly empty
##   texels of it (the second game's posts stand on their AnimTexture pedestal
##   sheet: on the row's statue sheet the Bridge Restorer and Teleport Kit
##   bases were black and the Toxin Dump a stretched metal stripe);
## - map objects made wholly of the Magic material keep the original's full
##   brightness (only the colourless creatures are shaded), and no map object
##   part turns to metal (rock "plates", shop "chains").
##
##   godot --headless --path game --script ../tools/model_texture_check.gd -- [--el1=DIR] [--el2=DIR] [--verbose]
##
## Without folders it uses the ones in user://profiles.json.

const OBJECT_TABLES := ["AdditionalBuildings", "Buildings", "TerrObj", "ResourceMine", "ResourceCut", "ManaNodes", "Artefacts", "GlobalSpellCut", "NewBuildings"]
## Parts with at least this many vertices are tested for empty texels.
const SAMPLED_VERTICES := 30
## A part whose texel samples are this empty wears the wrong sheet. Correct
## sheets leave at most about half of a thin part (leaves, chains) on their
## cut-out alpha; the black pedestal bases sampled 72-100%.
const EMPTY_LIMIT := 0.7
## Rows of the original tables naming skins the game never shipped.
const SHIPPED_WITHOUT := {"el2": ["GlobalSpellCut/PartSpell", "GlobalSpellCut/FullSpell"]}

var failures: Array[String] = []
var verbose := false
var _images := {}

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FAIL: ", what)
	elif verbose: print("PASS: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.trim_prefix("--" + name + "=")
	return fallback

func _run() -> void:
	verbose = "--verbose" in OS.get_cmdline_user_args()
	var saved: Variant = {}
	if FileAccess.file_exists("user://profiles.json"):
		saved = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	if not saved is Dictionary: saved = {}
	var tested := 0
	for edition: String in ["el1", "el2"]:
		var folder := _arg(edition, String(saved.get(edition, "")))
		if folder.is_empty(): continue
		var profile := ELProfile.new()
		if not profile.mount(edition, folder):
			check(false, "%s mounts: %s" % [edition, profile.error])
			continue
		tested += 1
		var before := failures.size()
		var counts := [_heroes(profile), _objects(profile), _creatures(profile)]
		print("%s: %d hero skins, %d map object figures, %d creature figures checked, %d failures" % [edition, counts[0], counts[1], counts[2], failures.size() - before])
		if profile.metal_masks != null: profile.metal_masks.stop()
	check(tested > 0, "at least one edition's folder is given")
	check(not ELModel.has_metal("tebuad26") and not ELModel.has_metal("telabkhi1") and ELModel.has_metal("he105") and ELModel.has_metal("cr501"), "only hero and creature figures turn to metal")
	# Plated figures with plain part names learn their metal from the parts
	# listed for them (ELFigure.METAL_FIGURE_PARTS), their map figure too;
	# flesh, fur and coats painted in their metal's colour stay matte.
	check(ELFigure.is_metal_part("l_circular", "cr103") and ELFigure.is_metal_part("wheel", "cr109") and ELFigure.is_metal_part("l_leg3", "ad104"), "the Synthets' machines name their metal (saws, wheels, legs; battle and map figures)")
	check(ELFigure.is_metal_part("l_hand1", "he205") and ELFigure.is_metal_part("mace") and ELFigure.is_metal_part("poas", "cr502"), "the ogre heroes' pauldrons, the mace and the Huntress's knives are metal")
	check(not ELFigure.is_metal_part("body", "cr109") and not ELFigure.is_metal_part("l_hand1", "cr103x"), "the listed parts belong only to their own figures")
	check(ELFigure.is_cloth("cr205", "body") and ELFigure.is_cloth("cr502", "body") and ELFigure.is_cloth("ad105", "l_leg1") and not ELFigure.is_cloth("cr105", "l_leg2"), "grey ogre skin, the Huntress's coat and the Abominations' flesh stay matte")
	check(not ELFigure.is_soft_part("polySurface29253") and ELFigure.is_soft_part("face") and ELFigure.is_metal_part("polysurface29253", "cr702") and ELFigure.is_cloth("cr707", "polysurface29344"), "Maya's polySurface parts are not faces: the colourless creatures' armour is metal, their pale skin matte")
	check(ELFigure.is_solid_metal("he207", "breast") and not ELFigure.is_solid_metal("he207", "body") and "he701" in ELFigure.SHADED_MAGIC_HEROES and ELFigure.is_metal_part("belt", "he702"), "the Chaot warriors' plates and the Red and Green main heroes' armour and gold can shine")
	check(ELFigure.is_solid_metal("ad207", "shield") and ELFigure.is_metal_part("katana", "cr208") and ELFigure.is_metal_part("hammer", "cr404") and ELFigure.is_cloth("cr206", "head") and ELFigure.MATTE_UV_RECTS.has("he704"), "kobold shields and blades and the Aviak Warlock's hammer shine; the old shaman's grey skin and the Red hero's sackcloth stay matte")
	var bronze := PackedByteArray([150, 100, 40, 255, 230, 170, 150, 255])
	var banded := ELMetalMasks.hue_band(PackedByteArray([0, 0]), bronze, ELFigure.METAL_HUE_BANDS["he716"])
	check(banded[0] == 0 and banded[1] == 0 and ELFigure.METAL_UV_RECTS.has("cr204") and ELFigure.METAL_UV_RECTS.has("ad711"), "Diamanda's bronze, the Ogre King's scale mail and the Egyptian's collar have their metal set out; a lone bronze texel is not plate")
	print("Model texture check: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

## Hero rows: battle skins under Heroes/ (as the battle builds heroes and
## shapes), map skins under either folder (ELAdventureArt picks one).
func _heroes(profile: ELProfile) -> int:
	var count := 0
	for table: String in ["HeroTemplates", "Shapes"]:
		var rows: Dictionary = profile.table(table)
		for key: String in rows:
			var row: Variant = rows[key]
			if not row is Dictionary: continue
			for column: String in ["Texture", "Texture2"]:
				var name := String(row.get(column, ""))
				if name.is_empty() or String(row.get("Model", "")).is_empty(): continue
				count += 1
				check(profile.texture("Heroes/" + name) != null, "%s %s/%s: battle skin %s" % [profile.id, table, key, name])
			for column: String in ["AdvTex1", "AdvTex2"]:
				var name := String(row.get(column, ""))
				if name.is_empty() or String(row.get("AdvMod", "")).is_empty(): continue
				for folder: String in ["Heroes/", "Creatures/"]:
					count += 1
					check(profile.texture(folder + name) != null, "%s %s/%s: map skin %s%s" % [profile.id, table, key, folder, name])
	# A hero row with a creature figure and skin (the Konung of Fire) builds
	# with its real skin, not the untextured white material.
	if profile.id == "el2" and profile.table("HeroTemplates").has("Konung of Fire I"):
		var row: Dictionary = profile.table("HeroTemplates")["Konung of Fire I"]
		var model := _build(profile, String(row.Model), "Heroes/" + String(row.Texture), "")
		if model != null:
			for part: String in model.parts:
				var node: MeshInstance3D = model.parts[part]
				if node.mesh == null: continue
				var material := node.material_override as StandardMaterial3D
				check(material != null and material.albedo_texture != null, "el2 Konung of Fire I: %s wears its skin" % part)
			model.free()
	# Creature-shaped heroes (Shapes rows: the chapter 13 dragon hero
	# "Musician" is DragonGreen, cr414 in battle with Alpha\BlueDragon00, kept
	# under Creatures/) build dressed in battle (Heroes/ + Texture, as the
	# battle view builds a shape) and on the map (AdvMod + AdvTex1), never white.
	var shapes: Dictionary = profile.table("Shapes")
	if profile.id == "el2": check(shapes.has("DragonGreen"), "el2 Shapes/DragonGreen (the Musician's figure) exists")
	for key: String in shapes:
		var row: Variant = shapes[key]
		if not row is Dictionary: continue
		for figure: Array in [["Model", "Texture", "Texture2", "battle"], ["AdvMod", "AdvTex1", "AdvTex2", "map"]]:
			if String(row.get(figure[0], "")).is_empty() or String(row.get(figure[1], "")).is_empty(): continue
			var skin := "Heroes/" + String(row[figure[1]])
			var second := "Heroes/" + String(row[figure[2]]) if not String(row.get(figure[2], "")).is_empty() else ""
			var model := _build(profile, String(row[figure[0]]), skin, second)
			if model == null:
				check(false, "%s Shapes/%s: %s figure %s builds" % [profile.id, key, figure[3], row[figure[0]]])
				continue
			count += 1
			_dressed(profile, model, "%s Shapes/%s %s figure" % [profile.id, key, figure[3]], skin, second, "", false)
			model.free()
	return count

## Battle creatures (CombatCreatures under Creatures/): every part dressed;
## the second game's colourless creatures are still shaded (#98).
func _creatures(profile: ELProfile) -> int:
	var count := 0
	var rows: Dictionary = profile.table("CombatCreatures")
	var seen := {}
	for key: String in rows:
		var row: Variant = rows[key]
		if not row is Dictionary or String(row.get("Model", "")).is_empty(): continue
		var skin := "Creatures/" + String(row.get("Texture", ""))
		var second := "Creatures/" + String(row.SecTexture) if row.has("SecTexture") else ""
		var at := "%s|%s|%s" % [row.Model, skin, second]
		if seen.has(at): continue
		seen[at] = true
		var model := _build(profile, String(row.Model), skin, second)
		if model == null:
			check(false, "%s CombatCreatures/%s: %s builds" % [profile.id, key, row.Model])
			continue
		count += 1
		_dressed(profile, model, "%s CombatCreatures/%s" % [profile.id, key], skin, second, "", false)
		if profile.id == "el2" and ELArchive.key(String(row.Model)).begins_with("cr7"):
			check(model.colourless, "el2 CombatCreatures/%s: colourless creature is shaded" % key)
		model.free()
	return count

func _objects(profile: ELProfile) -> int:
	var count := 0
	var shipped_without: Array = SHIPPED_WITHOUT.get(profile.id, [])
	for table: String in OBJECT_TABLES:
		var rows: Dictionary = profile.table(table)
		for key: String in rows:
			var row: Variant = rows[key]
			if not row is Dictionary or String(row.get("Model", "")).is_empty(): continue
			if "%s/%s" % [table, key] in shipped_without: continue
			var skin := "TerrainObjects/" + String(row.get("TextureName", row.get("Texture", "")))
			var second := "TerrainObjects/" + String(row.SecTexture) if not String(row.get("SecTexture", "")).is_empty() else ""
			# The animated sheet as the map passes it (ELAdventureArt.resolve).
			var animated := ELAdventureArt.animated_texture(row)
			if not animated.is_empty(): animated = "TerrainObjects/" + animated
			var model := _build(profile, String(row.Model), skin, second, animated)
			# A few rows name an animated sheet the game keeps elsewhere or never
			# shipped (the first game's Effects/Teleport_N shop flames, the second
			# game's Mana02): those parts keep the row's own sheet.
			if not animated.is_empty() and profile.texture(animated) == null:
				if verbose: print("%s %s/%s: no animated sheet %s" % [profile.id, table, key, animated])
				animated = ""
			if model == null:
				check(false, "%s %s/%s: %s builds" % [profile.id, table, key, row.Model])
				continue
			count += 1
			_dressed(profile, model, "%s %s/%s" % [profile.id, table, key], skin, second, animated, true)
			model.free()
	return count

func _build(profile: ELProfile, model_name: String, skin: String, second: String, animated := "") -> ELModel:
	var model := ELModel.new()
	model.idle_specials = false
	if not model.build(profile, model_name, skin, second, animated):
		model.free()
		return null
	model.set_process(false)
	return model

## Every part of a built figure wears the skin its slot names, decoded, and
## (for map objects) not mostly on empty texels; Magic parts of map objects
## are full bright and none turns to metal.
func _dressed(profile: ELProfile, model: ELModel, label: String, skin: String, second: String, animated: String, map_object: bool) -> void:
	for part: String in model.figures:
		if part in ELModel.EFFECT_ANCHORS: continue
		var node: MeshInstance3D = model.parts[part]
		var figure: Dictionary = model.figures[part]
		var slot := int(figure.texture_slot)
		var material := node.material_override as StandardMaterial3D
		if material == null:
			check(false, "%s: %s has a material" % [label, part])
			continue
		var expected := animated if slot != 2 and not animated.is_empty() else (second if slot == 2 and not second.is_empty() else skin)
		var texture := material.albedo_texture
		check(texture != null, "%s: %s (slot %d) wears %s, not untextured white" % [label, part, slot, expected])
		if texture == null: continue
		check(texture == profile.texture(expected), "%s: %s (slot %d) wears its own sheet %s" % [label, part, slot, expected])
		if not map_object: continue
		if int(figure.material_id) == ELFigure.MATERIAL_MAGIC and slot != 14:
			check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "%s: Magic part %s is full bright as the original" % [label, part])
		if int(figure.vertices) >= SAMPLED_VERTICES and slot != 14:
			var empty := _empty_share(texture, figure)
			check(empty < EMPTY_LIMIT, "%s: %s (slot %d) samples %d%% empty texels of %s" % [label, part, slot, int(empty * 100), expected])
	if map_object: check(model._metal_parts.is_empty() and model._metal_key.is_empty(), "%s: no part turns to metal" % label)

## Share of a part's texel samples (each triangle's centre and three inner
## points) that fall on transparent or black texels.
func _empty_share(texture: Texture2D, figure: Dictionary) -> float:
	var image: Image = _images.get(texture)
	if image == null:
		image = ELTexture.readable(texture.get_image()) if texture.get_image() != null else null
		if image == null: return 0.0
		_images[texture] = image
	var uvs: PackedVector2Array = figure.arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = figure.arrays[Mesh.ARRAY_INDEX]
	var width := image.get_width()
	var height := image.get_height()
	var samples := 0
	var empty := 0
	for t in range(0, indices.size() - 2, 3):
		var a := uvs[indices[t]]
		var b := uvs[indices[t + 1]]
		var c := uvs[indices[t + 2]]
		for weights: Vector3 in [Vector3(1, 1, 1) / 3.0, Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6)]:
			var at := a * weights.x + b * weights.y + c * weights.z
			var texel := image.get_pixel(posmod(int(at.x * width), width), posmod(int(at.y * height), height))
			samples += 1
			if texel.a < 0.3 or texel.r + texel.g + texel.b < 0.06: empty += 1
	return float(empty) / maxf(1, samples)
