class_name ELAutochessArtifacts
extends RefCounted
## Forty rewards in five tiers of eight: the Etherlords II artifacts and
## creature enchantments, each adapted to one carrier in a real-time battle.
## "source" is an Artefacts.reg row (artifact) or a CombatSpells code
## (enchantment); its name and icon come from the installed game. Flat
## values are independent of the carrier's stars.

const MAX_ITEMS := 32
const RULES := {
	# Tier 1
	"LSST": {"tier": 1, "spell": "LSST", "health": 25, "damage": 3},
	"TGSK": {"tier": 1, "spell": "TGSK", "health": 40},
	"STAT": {"tier": 1, "spell": "STAT", "damage": 5},
	"SCSK": {"tier": 1, "spell": "SCSK", "health": 25, "defense": 2},
	"SHCL": {"tier": 1, "spell": "SHCL", "haste": 0.15, "health": 15},
	"SLRP": {"tier": 1, "spell": "SLRP", "regen": 0.015, "health": 20},
	"SPWR": {"tier": 1, "spell": "SPWR", "haste": 0.06, "damage": 2},
	"ESWS": {"tier": 1, "spell": "ESWS", "poison": 0.25},
	# Tier 2
	"MGHT": {"tier": 2, "spell": "MGHT", "damage": 10},
	"SHSK": {"tier": 2, "spell": "SHSK", "health": 80},
	"AILK": {"tier": 2, "spell": "AILK", "lifesteal": 0.3, "damage": 4},
	"SGHT": {"tier": 2, "spell": "SGHT", "dispel_hit": true, "damage": 4},
	"SPBA": {"tier": 2, "spell": "SPBA", "venom": 0.15, "damage": 3},
	"UPGD": {"tier": 2, "spell": "UPGD", "health": 50, "damage": 5},
	"RingOfHealing": {"tier": 2, "artifact": "RingOfHealing", "ward": 0.35},
	"STSK": {"tier": 2, "spell": "STSK", "defense": 5},
	# Tier 3
	"STRG": {"tier": 3, "spell": "STRG", "damage": 18},
	"RodOfLightning": {"tier": 3, "artifact": "RodOfLightning", "storm": 25, "storm_every": 3},
	"EtherAmulet": {"tier": 3, "artifact": "EtherAmulet", "ether_shield": true, "health": 60},
	"CLFR": {"tier": 3, "spell": "CLFR", "elusive": true, "damage": 8},
	"ScrollOfBless": {"tier": 3, "artifact": "ScrollOfBless", "bless_attack": 0.3, "bless_shield": 80, "bless_seconds": 6.0},
	"AmuletOfHeroes": {"tier": 3, "artifact": "AmuletOfHeroes", "first_strike": true, "damage": 8},
	"ENBR": {"tier": 3, "spell": "ENBR", "spell_guard": 0.4, "health": 60},
	"SpikedRing": {"tier": 3, "artifact": "SpikedRing", "thorns": 10, "health": 40},
	# Tier 4
	"RodOfFire": {"tier": 4, "artifact": "RodOfFire", "rod": 60, "rod_every": 8.0},
	"RodofColossus": {"tier": 4, "artifact": "RodofColossus", "rod": 70, "rod_every": 10.0, "rod_splash": 15},
	"HAST": {"tier": 4, "spell": "HAST", "haste": 0.25, "first_strike": true},
	"VTLY": {"tier": 4, "spell": "VTLY", "regen": 0.02, "aura_regen": 0.01, "aura_radius": 5.0},
	"OVRL": {"tier": 4, "spell": "OVRL", "health": 160, "damage": 16},
	"RodOfReflection": {"tier": 4, "artifact": "RodOfReflection", "thorns": 20, "reflect": 0.3},
	"DOMN": {"tier": 4, "spell": "DOMN", "aura_attack": 0.1, "aura_health": 0.1, "aura_radius": 5.0},
	"RodOfDefence": {"tier": 4, "artifact": "RodOfDefence", "shield_aura": 45, "aura_radius": 5.0, "health": 60},
	# Tier 5
	"RodofKnights": {"tier": 5, "artifact": "RodofKnights", "knight": 0.6, "health": 80},
	"RodOfRessurection": {"tier": 5, "artifact": "RodOfRessurection", "revive": 0.6, "health": 60},
	"ScrollOfAshStorm": {"tier": 5, "artifact": "ScrollOfAshStorm", "dust": 2.5, "dust_radius": 7.0, "health": 100},
	"AmuletOfWar": {"tier": 5, "artifact": "AmuletOfWar", "unity": 0.2, "unity_per": 0.1},
	"IMML": {"tier": 5, "spell": "IMML", "fury_attack": 0.45, "fury_health": -0.1, "damage": 10},
	"RingOfCommand": {"tier": 5, "artifact": "RingOfCommand", "command": 0.3, "health": 80},
	"RingOfParalyzation": {"tier": 5, "artifact": "RingOfParalyzation", "paralyze": 0.15, "paralyze_seconds": 1.5, "damage": 20},
	"RodOfDominance": {"tier": 5, "artifact": "RodOfDominance", "dominance": 0.08, "health": 60},
}

static func tier(kind: String) -> int:
	return int(RULES.get(kind, {}).get("tier", 0))

static func reward_round(completed_round: int) -> bool:
	return completed_round == 3 or (completed_round >= 5 and completed_round % 5 == 0)

static func offer_tier(completed_round: int) -> int:
	return clampi(completed_round / 5 + 1, 1, 5)

## Three different items of the milestone's tier from their own random
## stream, so rewards never change the shop.
static func offers(seed_value: int, completed_round: int) -> Array[String]:
	var choices: Array[String] = []
	for kind: String in RULES:
		if tier(kind) == offer_tier(completed_round): choices.append(kind)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value * 15485863 + completed_round * 32452843 + 49979687
	for index in range(choices.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var held := choices[index]
		choices[index] = choices[other]
		choices[other] = held
	return choices.slice(0, 3)

static func title(profile: ELProfile, kind: String) -> String:
	var rule: Dictionary = RULES.get(kind, {})
	if rule.has("artifact"):
		var row: Dictionary = profile.table("Artefacts").get(String(rule.artifact), {})
		var key := String(row.get("ELKName", ""))
		var text := _elk(profile, key)
		if not text.is_empty(): return text
		var spell: Dictionary = profile.table("CombatSpells").get(String(row.get("SpellType", "")), {})
		return profile.text(String(spell.get("Name", kind)))
	var spell: Dictionary = profile.table("CombatSpells").get(String(rule.get("spell", kind)), {})
	var name := profile.text(String(spell.get("Name", "")))
	return name if not name.is_empty() and name != "None" else kind

static func _elk(profile: ELProfile, key: String) -> String:
	if key.is_empty(): return ""
	var text := profile.text(key)
	if text != key and not text.is_empty(): return text
	var row: Dictionary = profile.table("ElkTexts").get(key, {})
	var value: Variant = row.get("Translate", "")
	if value is Array:
		var languages: Variant = row.get("Language", [])
		if languages is Array and ELRemakeText.language(profile) == "ru" and "Russian" in languages:
			return String(value[languages.find("Russian")])
		return String(value[0]) if not value.is_empty() else ""
	return String(value)

static var _sized := {}

## The icon resampled once to `pixels` on screen (Lanczos), so a badge
## smaller or larger than the original 50-pixel cell stays sharp instead of
## being filtered on every draw. `round` cuts it to a soft-edged circle inside
## the cell's painted frame.
static func sized_icon(profile: ELProfile, kind: String, pixels: int, round := false) -> Texture2D:
	pixels = clampi(pixels, 8, 256)
	var key := "%s|%s|%d|%s" % [profile.root, kind, pixels, round]
	if _sized.has(key): return _sized[key]
	var source := icon(profile, kind)
	var image: Image = null
	if source is AtlasTexture and (source as AtlasTexture).atlas != null:
		var whole := (source as AtlasTexture).atlas.get_image()
		if whole != null: image = whole.get_region(Rect2i((source as AtlasTexture).region))
	elif source != null: image = source.get_image()
	if image == null: return source
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if round:
		# The frame's inner 80%, as the circles have always sampled it.
		var side := image.get_width()
		var inset := roundi(side * 0.1)
		image = image.get_region(Rect2i(inset, inset, side - inset * 2, side - inset * 2))
	image.resize(pixels, pixels, Image.INTERPOLATE_LANCZOS)
	if round:
		var centre := (pixels - 1) * 0.5
		for y in pixels:
			for x in pixels:
				var edge := clampf(pixels * 0.5 - Vector2(x - centre, y - centre).length(), 0.0, 1.0)
				var colour := image.get_pixel(x, y)
				colour.a *= edge
				image.set_pixel(x, y, colour)
	var result := ImageTexture.create_from_image(image)
	_sized[key] = result
	return result

static func icon(profile: ELProfile, kind: String) -> Texture2D:
	var rule: Dictionary = RULES.get(kind, {})
	if rule.has("artifact"):
		var row: Dictionary = profile.table("Artefacts").get(String(rule.artifact), {})
		return profile.card_icon(String(row.get("SpellType", "")))
	return profile.card_icon(String(rule.get("spell", kind)))

## English description lines; the screen translates them.
static func describe(kind: String) -> Array[String]:
	var r: Dictionary = RULES.get(kind, {})
	var lines: Array[String] = []
	if r.has("health"): lines.append(("+%d health." if int(r.health) > 0 else "%d health.") % int(r.health))
	if r.has("damage"): lines.append("+%d attack damage." % int(r.damage))
	if r.has("defense"): lines.append("+%d defense." % int(r.defense))
	if r.has("haste"): lines.append("+%d%% attack speed." % roundi(float(r.haste) * 100))
	if r.has("regen"): lines.append("Regenerates %d%% health per second." % roundi(float(r.regen) * 100))
	if r.has("poison"): lines.append("Poison: hits deal %d%% more damage over 3 s." % roundi(float(r.poison) * 100))
	if r.has("venom"): lines.append("Venom: a struck enemy still below %d%% health 4 s later dies (not 3-star or 5-cost)." % roundi(float(r.venom) * 100))
	if r.has("lifesteal"): lines.append("Vampire: attacks restore %d%% of the damage dealt." % roundi(float(r.lifesteal) * 100))
	if r.get("dispel_hit", false): lines.append("Breaks enchantments: hits remove the target's bonuses.")
	if r.has("ward"): lines.append("Below 40%% health: heals %d%% of its health once." % roundi(float(r.ward) * 100))
	if r.has("storm"): lines.append("Every %d hits: %d damage to another enemy within 4 m." % [int(r.storm_every), int(r.storm)])
	if r.get("ether_shield", false): lines.append("Ether protection: enemy abilities cannot target it.")
	if r.get("elusive", false): lines.append("Unblockable: goes for the enemy back line.")
	if r.has("bless_attack"): lines.append("For the first %d s: +%d%% attack and a %d-point shield." % [roundi(float(r.bless_seconds)), roundi(float(r.bless_attack) * 100), int(r.bless_shield)])
	if r.get("first_strike", false): lines.append("First strike.")
	if r.has("spell_guard"): lines.append("Takes %d%% less damage from abilities." % roundi(float(r.spell_guard) * 100))
	if r.has("thorns"): lines.append("Melee attackers take %d damage." % int(r.thorns))
	if r.has("reflect"): lines.append("Reflects %d%% of ability damage." % roundi(float(r.reflect) * 100))
	if r.has("rod"):
		if r.has("rod_splash"): lines.append("Every %d s: %d damage to its target and %d to every other enemy." % [roundi(float(r.rod_every)), int(r.rod), int(r.rod_splash)])
		else: lines.append("Every %d s: %d fire damage to its target." % [roundi(float(r.rod_every)), int(r.rod)])
	if r.has("aura_regen"): lines.append("Allies within %d m regenerate %d%% health per second." % [roundi(float(r.aura_radius)), roundi(float(r.aura_regen) * 100)])
	if r.has("aura_attack"): lines.append("At the bell, allies within %d m gain %d%% attack and health." % [roundi(float(r.aura_radius)), roundi(float(r.aura_attack) * 100)])
	if r.has("shield_aura"): lines.append("At the bell, it and allies within %d m gain a %d-point shield." % [roundi(float(r.aura_radius)), int(r.shield_aura)])
	if r.has("knight"): lines.append("On death, a Konung rises with %d%% of its health." % roundi(float(r.knight) * 100))
	if r.has("revive"): lines.append("Returns once after death with %d%% health." % roundi(float(r.revive) * 100))
	if r.has("dust"): lines.append("Below half health: enemies within %d m cannot attack for %.1f s. Once." % [roundi(float(r.dust_radius)), float(r.dust)])
	if r.has("unity"): lines.append("+%d%% attack and health, +%d%% more per ally of the same race." % [roundi(float(r.unity) * 100), roundi(float(r.unity_per) * 100)])
	if r.has("fury_attack"): lines.append("Fury: +%d%% attack, %d%% health." % [roundi(float(r.fury_attack) * 100), roundi(float(r.fury_health) * 100)])
	if r.has("command"): lines.append("Once: takes control of an enemy below %d%% health." % roundi(float(r.command) * 100))
	if r.has("paralyze"): lines.append("Hits have a %d%% chance to paralyse for %.1f s." % [roundi(float(r.paralyze) * 100), float(r.paralyze_seconds)])
	if r.has("dominance"): lines.append("At the bell, every ally gains %d%% attack and health." % roundi(float(r.dominance) * 100))
	return lines
