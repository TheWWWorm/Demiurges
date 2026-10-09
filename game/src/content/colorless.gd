class_name ELColorless
extends RefCounted
## Etherlords II colourless zones. Each map cell carries up to four level bits
## (the map's <clrless> grid); scripts choose the active level with
## ExSetClrlessLevel (0..3). Paying travel points on a colourless
## cell drains experience from heroes that are neither White nor tolerant
## (travel consumption): lost experience grows
## effective × spent × 0.08 / daily capacity, and the level is settled again
## . The first drain of a day plays the white-zone effect.

const RATE := 0.08

static func zone_at(state: ELAdventureSession, cell: Vector2i) -> bool:
	var map := state.map
	if map == null or map.profile.id != "el2" or cell.x < 0 or cell.y < 0 or cell.x >= map.width or cell.y >= map.height: return false
	if map.colorless.size() != map.width * map.height: return false
	var level := clampi(state.colorless_level, 0, 3)
	return ((map.colorless[cell.y * map.width + cell.x] >> level) & 1) == 1

## The hero template's colour (the original reads template +8).
static func colour(profile: ELProfile, actor: Dictionary) -> String:
	var row: Dictionary = profile.table("HeroTemplates").get(str(actor.get("name", "")), {})
	if row.is_empty() and not str(actor.get("shape", "")).is_empty(): row = profile.table("Shapes").get(str(actor.shape), {})
	return str(row.get("Color", ""))

static func exempt(state: ELAdventureSession, actor: Dictionary) -> bool:
	return actor.get("colorless_tolerant", false) or colour(state.map.profile, actor) == "White"

## Called for each paid chunk of travel points.
static func drain(state: ELAdventureSession, hero: Dictionary, spent: int) -> void:
	if spent <= 0 or not hero.has("x") or exempt(state, hero) or not zone_at(state, Vector2i(int(hero.x), int(hero.y))): return
	var effective := float(ELHeroProgression.effective(hero))
	var capacity := int(hero.get("travel_capacity", 0))
	var amount := effective * spent * RATE / capacity if capacity > 0 else effective * RATE
	var before := float(hero.get("experience_penalty", 0.0))
	set_lost(state.map.profile, hero, before + amount)
	if float(hero.experience_penalty) > before and int(hero.get("colorless_effect_day", -1)) != int(hero.get("travel_day", 0)):
		hero.colorless_effect_day = int(hero.get("travel_day", 0))
		state.event.emit({"kind": "colorless_drain", "id": int(hero.uid), "amount": float(hero.experience_penalty) - before})

## Lost experience is kept within [0, experience]; the current level follows
## the effective experience, while the highest level reached (and the skill
## points it granted) never falls.
static func set_lost(profile: ELProfile, hero: Dictionary, value: float) -> void:
	hero.experience_penalty = clampf(value, 0.0, float(hero.get("experience", 0)))
	var level := ELHeroProgression.level_for(profile, ELHeroProgression.effective(hero))
	var gained := maxi(0, level - int(hero.get("level_history", level)))
	hero.level_history = maxi(int(hero.get("level_history", level)), level)
	hero.skill_points = int(hero.get("skill_points", 0)) + gained
	hero.level = level
	ELHeroProgression.recalculate_health(hero)
	if hero.get("type") == "hero": ELHeroSkills.prepare(profile, hero)

## The map's level bits of one cell (0 outside the grid).
static func cell_bits(map: ELAdventureMap, cell: Vector2i) -> int:
	if map == null or cell.x < 0 or cell.y < 0 or cell.x >= map.width or cell.y >= map.height or map.colorless.size() != map.width * map.height: return 0
	return map.colorless[cell.y * map.width + cell.x]

## Grey terrain corners for a level, one byte per map vertex
## ((width + 1) × (height + 1)): a corner is grey when any of the up to four
## cells sharing it is colourless (flags the corners of each
## colourless cell and the touching corners of its eight neighbours). The tile
## of a cell with mixed corners blends grey and colour like a terrain border.
static func corner_flags(map: ELAdventureMap, level: int) -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize((map.width + 1) * (map.height + 1))
	if map.colorless.size() != map.width * map.height: return flags
	var bit := 1 << clampi(level, 0, 3)
	for y in map.height:
		for x in map.width:
			if (map.colorless[y * map.width + x] & bit) == 0: continue
			var at := y * (map.width + 1) + x
			flags[at] = 1
			flags[at + 1] = 1
			flags[at + map.width + 1] = 1
			flags[at + map.width + 2] = 1
	return flags

## A map object is drawn with greyscale textures while the cell under the
## centre of its footprint is colourless at the current level (the
## level switch re-checks every object).
static func object_grey(map: ELAdventureMap, level: int, cell: Vector2i) -> bool:
	return ((cell_bits(map, cell) >> clampi(level, 0, 3)) & 1) == 1

## The greyscale copy of an image:
## each texel's colour channels become their integer mean; alpha is kept.
static func grey_image(source: Image) -> Image:
	var image := source.duplicate() as Image
	if image.is_compressed(): image.decompress()
	if image.has_mipmaps(): image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	for i in range(0, data.size(), 4):
		var value := (int(data[i]) + int(data[i + 1]) + int(data[i + 2])) / 3
		data[i] = value
		data[i + 1] = value
		data[i + 2] = value
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
