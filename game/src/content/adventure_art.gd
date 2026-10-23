class_name ELAdventureArt
extends RefCounted
var map: ELAdventureMap
var cache: Dictionary = {}

func _init(source: ELAdventureMap) -> void:
	map = source

func resolve(object: Dictionary) -> Dictionary:
	var node: Dictionary = object.node
	if not object.get("visible", ELXml.child(node, "hidden").is_empty()): return {"hidden": true}
	var corpse: bool = map.profile.id == "el2" and object.get("type") == "corpse"
	var shape := str(object.get("shape", ""))
	if corpse and shape.is_empty(): shape = ELXml.value(node, "params")
	if object.get("ship", false) or (corpse and shape.to_lower() == "ship"):
		return {"model": "tebuad552" if corpse else "he551", "texture": "Heroes/Boat00", "secondary": "", "scale": 1.0, "row": {"TileSize": [1, 1]}, "unit": true}
	var color := ELXml.value(node, "color")
	if color.is_empty():
		for player: Dictionary in map.players:
			if int(player.attrs.id) == object.owner: color = ELXml.value(player, "color")
	if color.is_empty(): color = terrain_color(map.tile(object.x, object.y))
	var level := ELXml.value(node, "level", "0")
	if map.profile.id == "el1" and object.group == "forts":
		level = str(object.fort_level) if object.has("fort_level") else str(ELXml.child(node, "upgrade").get("attrs", {}).get("level", 0))
	if object.get("type") in ["rune_shop", "el1_spell_shop", "resource_mine"]: level = str(object.level)
	# A first-game castle shows the MainTower row of its damage stage.
	if object.has("castle_stage") and ELFirstScenario.is_castle(object): level = str(object.castle_stage)
	var key := "%s/%s/%s/%s/%s/%s/%s" % [object.group, object.name, color, level, shape, object.get("monster_difficulty", 0), corpse]
	if cache.has(key): return cache[key]
	var row := {}
	var category := "TerrainObjects/"
	var adventure := false
	if corpse and object.group == "additional_buildings":
		# Authored bodies name a shape directly in their map parameters.
		adventure = true
		row = map.profile.table("Shapes").get(shape, {})
		category = "Heroes/" if str(row.get("CorpseMod", row.get("AdvMod", ""))).to_lower().begins_with("he") else "Creatures/"
	elif object.group in ["heroes", "np_heroes"]:
		adventure = true
		var hero: bool = ELXml.child(node, "monster").is_empty()
		if not String(object.get("shape", "")).is_empty():
			row = map.profile.table("Shapes").get(object.shape, {})
			hero = object.get("appearance_type", object.get("type", "hero")) == "hero"
		elif map.profile.id == "el2" and map.mobs.has(object.name):
			var variants: Dictionary = map.mobs[object.name]
			var mob: Dictionary = variants.get(0, variants.values()[0])
			row = map.profile.table("Shapes").get(mob.attrs.get("shape", ""), {})
			hero = mob.attrs.get("IsHero", "0") == "1"
		elif hero:
			row = map.profile.table("HeroTemplates").get(object.name, {})
		else:
			row = ELFirstMonsters.definition(map.profile, object.name, int(object.get("monster_difficulty", 0)))
		category = "Heroes/" if hero else "Creatures/"
	elif ELResourceSites.TYPES.has(object.group):
		var site := object.duplicate()
		site.level = int(level)
		row = ELResourceSites.definition(map.profile, site)
	elif object.group == "terrain_objects":
		row = map.profile.table("TerrObj").get(object.name, {})
	else:
		var tables := {"mines": "ResourceMine", "resource_cuts": "ResourceCut", "mana_nodes": "ManaNodes",
			"artefacts": "Artefacts", "additional_buildings": "AdditionalBuildings", "global_spells": "GlobalSpellCut", "laboratories": "NewBuildings", "factories": "NewBuildings"}
		var table_name := String(tables.get(object.group, "Buildings"))
		var wanted := "Fort" if object.group == "forts" else String(object.name)
		var table := map.profile.table(table_name)
		row = table.get(wanted, {})
		if row.is_empty():
			var best_score := -1
			for candidate: Dictionary in table.values():
				if candidate.get("Name") != wanted and candidate.get("Type") != wanted: continue
				var score := 0
				if str(candidate.get("Level", "0")) == level: score += 2
				if candidate.get("MagicColor", color) == color: score += 4
				if score > best_score:
					row = candidate
					best_score = score
	var model := String(row.get("AdvMod", row.get("Model", ""))) if adventure else String(row.get("Model", ""))
	var texture := String(row.get("AdvTex1", row.get("Texture", ""))) if adventure else String(row.get("TextureName", row.get("Texture", "")))
	var secondary := String(row.get("AdvTex2", "")) if adventure else String(row.get("SecTexture", ""))
	if corpse:
		if not str(row.get("CorpseMod", "")).is_empty(): model = str(row.CorpseMod)
		if not str(row.get("CorpseTex1", "")).is_empty(): texture = str(row.CorpseTex1)
		if not str(row.get("CorpseTex2", "")).is_empty(): secondary = str(row.CorpseTex2)
	if model.is_empty(): return {}
	# A non-hero mob may wear a hero shape (the second game's tutorial guides,
	# IsHero 0 with RedFemale-2 etc.): take the folder that holds the texture.
	if adventure and not texture.is_empty():
		var archive: ELArchive = map.profile.archives.get("textures")
		var other := "Creatures/" if category == "Heroes/" else "Heroes/"
		var found := func(folder: String) -> bool: return archive.has(ELArchive.key(folder + texture + ("" if texture.to_lower().ends_with(".mmp") else ".mmp")))
		if archive != null and not found.call(category) and found.call(other): category = other
	var result := {"model": model, "texture": category + texture, "secondary": category + secondary if not secondary.is_empty() else "",
		"scale": float(row.get("AdvScale", 1.0)) if adventure else 1.0, "row": row, "unit": adventure}
	cache[key] = result
	return result

static func terrain_color(kind: int) -> String:
	if kind >= 0 and (kind < 4 or kind == 6): return "Green"
	if kind in [4, 5, 7, 18]: return "Blue"
	if kind >= 8 and kind < 12: return "Red"
	if kind >= 12 and kind < 16: return "Black"
	return "Colorless"
