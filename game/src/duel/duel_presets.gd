class_name ELDuelPresets
extends RefCounted
## Duel-mode hero presets. Shipped rows come from the edition's own
## `DuelPresets` table (only `InGame=True` rows load in the full game); the
## deck is the referenced `CombatDecks` row.
##
## Preset dictionary: id, name, builtin, faction, resource_level, level,
## specialization, skills {code: rank 0..2}, cards, runes (EL1 per-slot rune
## count; EL2 the authored use count, kept for the record only: every battle
## sets EL2 charges from Providence), reserve {code: count} (EL2), artifacts
## [artifact spell codes, copies allowed; each starts a duel round with the
## edition's MaxCharges], deck (shipped CombatDecks name).

## `Duel\heroes.def` race index order.
const RACES: Array[String] = ["Red", "Green", "Blue", "Black"]
## Fallback when `Duel\heroes.def` is absent (identical in both editions).
const DEFAULT_HEROES := {"Red": "RedMale4", "Green": "GreenFemale2", "Blue": "BlueWingedFemale1", "Black": "StartBlackMale"}

static func shipped(profile: ELProfile) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rows := profile.table("DuelPresets")
	for key: String in rows:
		var row: Dictionary = rows[key]
		if str(row.get("InGame", "False")) != "True": continue
		result.append(from_row(profile, key, row))
	return result

static func from_row(profile: ELProfile, key: String, row: Dictionary) -> Dictionary:
	var spec := String(row.get("Specialization", "NONE"))
	# The second game keeps only four-character codes.
	if profile.id != "el1" and spec.length() != 4: spec = "NONE"
	var deck := String(row.get("Deck", ""))
	var cards: Array[String] = ELCatalog.deck(profile, deck)
	var runes: Array[int] = ELCatalog.deck_uses(profile, deck)
	var artifacts: Array[String] = []
	var authored: Variant = row.get("Artefacts", [])
	for code: Variant in ([authored] if authored is String else authored):
		# The second game names artifacts by template; presets keep the spell code.
		var name := String(code)
		if profile.table("Artefacts").has(name): name = String(profile.table("Artefacts")[name].get("SpellType", name))
		if not name.is_empty(): artifacts.append(name)
	return {"id": key, "name": profile.text(key), "builtin": true, "faction": String(row.get("MagicColor", "")),
		"resource_level": int(row.get("ResourceLevel", 1)), "level": int(row.get("HeroLevel", 1)),
		"specialization": spec, "skills": parse_skills(profile, row.get("Skills", [])),
		"cards": cards, "runes": runes, "reserve": {}, "artifacts": artifacts, "deck": deck}

## `CODE(n)` is rank n-1, capped at the highest rank.
static func parse_skills(profile: ELProfile, value: Variant) -> Dictionary:
	var entries: Array = [value] if value is String else (value if value is Array else [])
	# Guard against dumps that split one string into characters.
	if not entries.is_empty() and entries.all(func(e: Variant): return String(e).length() == 1): entries = ["".join(PackedStringArray(entries))]
	var result := {}
	for entry: Variant in entries:
		var text := String(entry)
		if not text.contains("("): continue
		var code := text.left(4)
		var rank := clampi(int(text.get_slice("(", 1).trim_suffix(")")) - 1, 0, ELHeroSkills.MAX_RANK)
		if not ELHeroSkills.definition(profile, code, rank).is_empty(): result[code] = rank
	return result

## Default portrait/template per race from `Duel\heroes.def`.
static func default_template(profile: ELProfile, faction: String) -> String:
	var path := profile.file("Duel/heroes.def")
	if not path.is_empty():
		var regex := RegEx.create_from_string("race=\"(\\d+)\"\\s+def_hero=\"([^\"]+)\"")
		for m: RegExMatch in regex.search_all(FileAccess.get_file_as_string(path)):
			var index := int(m.get_string(1))
			if index < RACES.size() and RACES[index] == faction and profile.table("HeroTemplates").has(m.get_string(2)): return m.get_string(2)
	return String(DEFAULT_HEROES.get(faction, ELCatalog.default_hero(profile, faction)))

## Starting health as the duel computes it: template base + increase x level,
## then the Health skill's bonus.
static func health(profile: ELProfile, preset: Dictionary, template := "") -> int:
	if template.is_empty(): template = default_template(profile, String(preset.faction))
	var row: Dictionary = profile.table("HeroTemplates").get(template, {})
	var value := int(row.get("BaseHealth", 7)) + int(row.get("HealthIncrease", 3)) * int(preset.level)
	var skills: Dictionary = preset.get("skills", {})
	if skills.has("HEAL"): value = int(value * [1.1, 1.2, 1.3][int(skills.HEAL)] + 0.5)
	return value

## The `players[side]` entry ELDuel.start accepts. A cosmetic template may
## replace the heroes.def default.
static func choice(profile: ELProfile, preset: Dictionary, template := "") -> Dictionary:
	var result := {"faction": String(preset.faction), "hero": template if not template.is_empty() else default_template(profile, String(preset.faction)),
		"level": int(preset.level), "skills": preset.get("skills", {}).duplicate(), "specialization": String(preset.get("specialization", "NONE")),
		"preset": String(preset.get("id", ""))}
	var deck := String(preset.get("deck", ""))
	if not deck.is_empty() and _same(ELCatalog.deck(profile, deck), preset.cards) and _same(ELCatalog.deck_uses(profile, deck), preset.get("runes", [])):
		# Unchanged shipped deck: the duel reads the authored per-slot uses itself.
		result.deck = deck
	else:
		result.cards = preset.cards.duplicate()
		if profile.id == "el1":
			var uses: Array[int] = []
			var runes: Array = preset.get("runes", [])
			for index in preset.cards.size():
				var cantrip: bool = profile.table("CombatSpells").get(preset.cards[index], {}).get("Rarity") == "Cantrip"
				uses.append(-1 if cantrip else (int(runes[index]) if index < runes.size() else 0))
			result.rune_uses = uses
	var artifacts: Array = []
	for code: String in preset.get("artifacts", []):
		var name := artifact_name(profile, code)
		if not name.is_empty(): artifacts.append({"name": name})
	if not artifacts.is_empty(): result.artifacts = artifacts
	# Kept for the record only (replays show it): a battle draws from the deck.
	if not preset.get("reserve", {}).is_empty(): result.reserve = preset.reserve.duplicate()
	return result

## The `Artefacts` row whose spell is `code`.
static func artifact_name(profile: ELProfile, code: String) -> String:
	var rows := profile.table("Artefacts")
	for name: String in rows:
		if String(rows[name].get("SpellType", "")) == code: return name
	return ""

## Full ELDuel.start options for one round.
static func options(profile: ELProfile, presets: Array, arena: String, templates: Array = ["", ""]) -> Dictionary:
	return {"players": [choice(profile, presets[0], String(templates[0])), choice(profile, presets[1], String(templates[1]))], "arena": arena}

static func find(presets: Array, id: String) -> Dictionary:
	for preset: Dictionary in presets:
		if preset.id == id: return preset
	return {}

static func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if str(a[i]) != str(b[i]): return false
	return true

## A preset read back from JSON (numbers as floats) in canonical form, or {}
## when its shape is wrong. Rules are checked separately (ELDuelCosts.errors).
static func normalize(value: Variant) -> Dictionary:
	if value is not Dictionary: return {}
	var p: Dictionary = value
	for key in ["faction", "specialization"]:
		if p.get(key) is not String: return {}
	for key in ["resource_level", "level"]:
		if not ELLuaSave._integer(p.get(key), 1, 99): return {}
	if p.get("cards") is not Array or p.get("runes", []) is not Array or p.get("skills", {}) is not Dictionary or p.get("reserve", {}) is not Dictionary or p.get("artifacts", []) is not Array: return {}
	var cards: Array[String] = []
	for card: Variant in p.cards:
		if card is not String: return {}
		cards.append(card)
	var runes: Array[int] = []
	for count: Variant in p.get("runes", []):
		if not ELLuaSave._integer(count, -1, 0x7fffffff): return {}
		runes.append(int(count))
	var skills := {}
	for code: Variant in p.get("skills", {}):
		if code is not String or not ELLuaSave._integer(p.skills[code], 0, ELHeroSkills.MAX_RANK): return {}
		skills[code] = int(p.skills[code])
	var reserve := {}
	for code: Variant in p.get("reserve", {}):
		if code is not String or not ELLuaSave._integer(p.reserve[code], 0, 0x7fffffff): return {}
		reserve[code] = int(p.reserve[code])
	var artifacts: Array[String] = []
	for code: Variant in p.get("artifacts", []):
		if code is not String: return {}
		artifacts.append(code)
	return {"id": String(p.get("id", "")), "name": String(p.get("name", "")), "builtin": bool(p.get("builtin", false)),
		"faction": p.faction, "resource_level": int(p.resource_level), "level": int(p.level), "specialization": p.specialization,
		"skills": skills, "cards": cards, "runes": runes, "reserve": reserve, "artifacts": artifacts, "deck": String(p.get("deck", ""))}

# --- User presets ------------------------------------------------------------
# The original writes `Duel\<name>.prs` (MSXML `duel_preset`) into the game
# folder. The remake never writes there: user presets are normalized JSON
# dictionaries in an edition-specific user folder, one file per preset, named
# after the preset. (The exact .prs element/attribute layout is not
# transcribed, so original .prs files are not imported yet.)

const USER_FORMAT := 1
## Characters the second game rejects in a preset name (T_MB_WRONG_PRESET_NAME);
## also applied to the first game, whose rule is unconfirmed, because the name
## becomes a file name.
const FORBIDDEN_NAME := "|\\/:*?\"<>.[],;="

static func user_dir(profile: ELProfile) -> String:
	return "user://duel/%s" % profile.id

static func valid_name(name: String) -> bool:
	if name.strip_edges().is_empty(): return false
	for c in FORBIDDEN_NAME:
		if name.contains(c): return false
	return true

static func _user_path(profile: ELProfile, name: String) -> String:
	return user_dir(profile).path_join(name.strip_edges() + ".json")

## Readable user presets of this edition, sorted by name; files that fail the
## shape check or the edition's rules (ELDuelCosts.errors) are skipped.
static func load_user(profile: ELProfile, rejected: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := user_dir(profile)
	if not DirAccess.dir_exists_absolute(dir): return result
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for file: String in files:
		if not file.ends_with(".json"): continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		var preset := normalize(data)
		var name := file.trim_suffix(".json")
		if preset.is_empty() or data.get("format") != USER_FORMAT or data.get("edition") != profile.id or not ELDuelCosts.errors(profile, preset).is_empty():
			rejected.append(file)
			continue
		preset.name = name
		preset.id = "user:" + name
		preset.builtin = false
		preset.deck = ""
		result.append(preset)
	return result

static func user_exists(profile: ELProfile, name: String) -> bool:
	return FileAccess.file_exists(_user_path(profile, name))

## Writes a user preset under `name`; returns "" or an error.
static func save_user(profile: ELProfile, preset: Dictionary, name: String) -> String:
	if not valid_name(name): return "name"
	var copy := normalize(preset)
	if copy.is_empty(): return "shape"
	if not ELDuelCosts.errors(profile, copy).is_empty(): return "rules"
	copy.name = name.strip_edges()
	copy.id = "user:" + copy.name
	copy.builtin = false
	copy.deck = ""
	copy.format = USER_FORMAT
	copy.edition = profile.id
	DirAccess.make_dir_recursive_absolute(user_dir(profile))
	var file := FileAccess.open(_user_path(profile, name), FileAccess.WRITE)
	if file == null: return "write"
	file.store_string(JSON.stringify(copy, "\t"))
	return ""

static func delete_user(profile: ELProfile, name: String) -> bool:
	return user_exists(profile, name) and DirAccess.remove_absolute(_user_path(profile, name)) == OK
