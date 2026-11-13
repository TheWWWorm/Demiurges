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

static func blank(faction: String, resource_level: int) -> Dictionary:
	return {"id": "", "name": "", "builtin": false, "faction": faction, "resource_level": resource_level,
		"level": 1, "specialization": "NONE", "skills": {}, "cards": [], "runes": [], "reserve": {}, "artifacts": [], "deck": ""}

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
	var resource_level := int(preset.get("resource_level", 1))
	if ELDuelCosts.sandbox(profile, resource_level): result.resource_level = resource_level
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

## A between-round edit can only repartition this hero's owned copies.
static func with_reserve_deck(preset: Dictionary, cards: Array) -> Dictionary:
	if cards.size() != ELDuelCosts.EL2_DECK: return {}
	var reserve: Dictionary = preset.reserve.duplicate()
	for code: String in preset.cards:
		reserve[code] = int(reserve.get(code, 0)) + 1
	var active := {}
	var copy_limit := ELDuelCosts.el2_copy_limit(int(preset.get("resource_level", 1)))
	for code: Variant in cards:
		if code is not String or int(reserve.get(code, 0)) <= 0: return {}
		active[code] = int(active.get(code, 0)) + 1
		if active[code] > copy_limit: return {}
		reserve[code] -= 1
		if reserve[code] == 0: reserve.erase(code)
	var result := preset.duplicate(true)
	result.cards.assign(cards)
	result.reserve = reserve
	if result.cards != preset.cards: result.deck = ""
	return result

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

## The first game's preset loader keeps every preset it can read: the book
## stops at the first spell the game does not know, and the spending, book
## size, spell colours and runes are left to the editor (its OK checks the
## budget). Unknown skills, specialisations and artifacts are dropped and the
## levels are kept in range. Returns {} for a preset no battle can use.
static func readable(profile: ELProfile, value: Variant) -> Dictionary:
	var p := normalize(value)
	if p.is_empty() or not ELCatalog.FACTIONS.has(String(p.faction)): return {}
	var levels := ELDuelCosts.resource_levels(profile)
	p.resource_level = clampi(int(p.resource_level), levels.x, levels.y)
	var heroes := ELDuelCosts.hero_levels(profile)
	p.level = clampi(int(p.level), heroes.x, heroes.y)
	var spells := profile.table("CombatSpells")
	var cards: Array[String] = []
	var runes: Array[int] = []
	for i in p.cards.size():
		var card: String = p.cards[i]
		if not spells.has(card) or cards.size() >= ELDuelCosts.EL1_BOOK: break
		# A battle refuses another race's spell or one it cannot play.
		if ELCatalog.rule(profile, card).is_empty() or not ELDuelCosts.spell_allowed(profile, card, String(p.faction), int(p.resource_level)): continue
		cards.append(card)
		runes.append(maxi(0, int(p.runes[i])) if i < p.runes.size() else 0)
	if cards.is_empty(): return {}
	p.cards = cards
	p.runes = runes
	var skills := {}
	for code: String in p.skills:
		if skills.size() < ELDuelCosts.MAX_SKILLS and not ELHeroSkills.definition(profile, code, int(p.skills[code])).is_empty(): skills[code] = int(p.skills[code])
	p.skills = skills
	if p.specialization != "NONE" and not profile.table("HeroesSpecs").has(p.specialization): p.specialization = "NONE"
	var artifacts: Array[String] = []
	for code: String in p.artifacts:
		if ELDuelCosts.artifact(profile, code) and not artifact_name(profile, code).is_empty(): artifacts.append(code)
	p.artifacts = artifacts
	p.reserve = {}
	return p

## The first game plays any readable preset; the second checks its rules
## when it loads one.
static func lenient(profile: ELProfile) -> bool:
	return profile.id == "el1"

# --- User presets ------------------------------------------------------------
# User presets are normalized JSON in the edition's user folder. Original
# .prs files copied there are converted once and kept as backups; those in
# the game's own Duel folder are read once (and again when the file changes)
# without touching them.

const USER_FORMAT := 1
## Names and modification times of the game folder's .prs files already
## read (a name no preset can take: names have no dots).
const IMPORTED_INDEX := ".prs_imported.json"
const MAX_ORIGINAL_PRESET_BYTES := 256 * 1024
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

## MSXML writes the preset header as root attributes and preserves deck order.
static func _original_preset(profile: ELProfile, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_ORIGINAL_PRESET_BYTES: return {}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 2: return {}
	if (bytes[0] == 255 and bytes[1] == 254) or (bytes[0] == 254 and bytes[1] == 255):
		bytes = bytes.get_string_from_utf16().to_utf8_buffer()
	var root := ELXml.parse(bytes)
	if root.get("tag") != "duel_preset": return {}
	var header: Dictionary = root.attrs
	var resource := String(header.get("resource_level", ""))
	var hero := String(header.get("hero_level", ""))
	if not resource.is_valid_int() or not hero.is_valid_int(): return {}
	var preset := blank(String(header.get("magic", "")).capitalize(), int(resource))
	preset.level = int(hero)
	preset.specialization = String(header.get("specialization", "NONE"))
	if preset.specialization.is_empty(): preset.specialization = "NONE"
	var el1 := profile.id == "el1"
	var bag := ELXml.child(root, "bag_spells")
	if el1 and not bag.is_empty(): return {}
	for entry in ELXml.children(ELXml.child(root, "skills"), "skill"):
		var code := String(entry.attrs.get("type", ""))
		var level := String(entry.attrs.get("level", ""))
		if not level.is_valid_int() or preset.skills.has(code): return {}
		preset.skills[code] = int(level) - 1
	for entry in ELXml.children(ELXml.child(root, "deck"), "spell"):
		var uses := String(entry.attrs.get("components", "0"))
		if not uses.is_valid_int(): return {}
		preset.cards.append(String(entry.attrs.get("code", "")))
		preset.runes.append(int(uses))
	for entry in ELXml.children(ELXml.child(root, "artefacts"), "artefact"):
		var code := String(entry.attrs.get("code", ""))
		if not el1 and entry.attrs.has("name"):
			code = String(profile.table("Artefacts").get(entry.attrs.name, {}).get("SpellType", ""))
		preset.artifacts.append(code)
	for entry in ELXml.children(bag, "spell"):
		var code := String(entry.attrs.get("type", ""))
		var count := String(entry.attrs.get("count", ""))
		if not count.is_valid_int() or int(count) < 0 or preset.reserve.has(code): return {}
		preset.reserve[code] = int(count)
	return preset

## Converts an original .prs into a user preset named after its file;
## returns false when the file cannot be read or saved.
static func _import_preset(profile: ELProfile, source: String, name: String) -> bool:
	var preset := _original_preset(profile, source)
	if lenient(profile): preset = readable(profile, preset)
	return not preset.is_empty() and save_user(profile, preset, name, false, not lenient(profile)).is_empty()

static func _import_original(profile: ELProfile, directory: String, files: Array, rejected: Array) -> void:
	for file: String in files:
		if file.get_extension().to_lower() != "prs": continue
		var name := file.get_basename().strip_edges()
		if user_exists(profile, name): continue
		var source := directory.path_join(file)
		if not _import_preset(profile, source, name):
			rejected.append(file)
			continue
		var backup := source + ".imported"
		if FileAccess.file_exists(backup):
			backup = "%s.%d.imported" % [source, Time.get_ticks_usec()]
		DirAccess.rename_absolute(source, backup)

## The presets the original saved in its own `Duel` folder (`Duel\*.prs`).
## The game folder is never written: each file is read into a user preset
## of the same name once, and again only when the file changes, so a
## converted preset can be edited or deleted like any other. A user preset
## of the same name is kept.
static func _import_game_folder(profile: ELProfile, rejected: Array) -> void:
	var sources: Array[String] = []
	for key: String in profile.files_under("Duel/"):
		if key.get_extension().to_lower() == "prs": sources.append(profile.file(key))
	if sources.is_empty(): return
	var index_path := user_dir(profile).path_join(IMPORTED_INDEX)
	var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path)) if FileAccess.file_exists(index_path) else null
	var index: Dictionary = read if read is Dictionary else {}
	var changed := false
	for source: String in sources:
		var name := source.get_file().get_basename().strip_edges()
		var stamp := str(FileAccess.get_modified_time(source))
		if not valid_name(name) or String(index.get(name, "")) == stamp: continue
		index[name] = stamp
		changed = true
		if user_exists(profile, name): continue
		if not _import_preset(profile, source, name): rejected.append(source.get_file())
	if not changed: return
	DirAccess.make_dir_recursive_absolute(user_dir(profile))
	var file := FileAccess.open(index_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(index, "\t"))

## Readable user presets of this edition, sorted by name; files that fail the
## shape check are skipped, and in the second game also those that break its
## rules (ELDuelCosts.errors). The first game keeps every readable preset
## (`readable`), as its own loader does, so presets saved under other rules
## (earlier versions or patches) still load.
static func load_user(profile: ELProfile, rejected: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := user_dir(profile)
	_import_game_folder(profile, rejected)
	if not DirAccess.dir_exists_absolute(dir): return result
	var files := Array(DirAccess.get_files_at(dir))
	if files.any(func(file: String): return file.get_extension().to_lower() == "prs"):
		_import_original(profile, dir, files, rejected)
		files = Array(DirAccess.get_files_at(dir))
	files.sort()
	for file: String in files:
		if not file.ends_with(".json"): continue
		if file == IMPORTED_INDEX: continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		var preset := readable(profile, data) if lenient(profile) else normalize(data)
		var name := file.trim_suffix(".json")
		if preset.is_empty() or data.get("format") != USER_FORMAT or data.get("edition") != profile.id or (not lenient(profile) and not ELDuelCosts.errors(profile, preset).is_empty()):
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

## Writes a user preset under `name`; returns "" or an error. An imported
## original preset is written unchecked (`checked` false).
static func save_user(profile: ELProfile, preset: Dictionary, name: String, replace := true, checked := true) -> String:
	if not valid_name(name): return "name"
	var copy := normalize(preset)
	if copy.is_empty(): return "shape"
	if checked and not ELDuelCosts.errors(profile, copy).is_empty(): return "rules"
	copy.name = name.strip_edges()
	copy.id = "user:" + copy.name
	copy.builtin = false
	copy.deck = ""
	copy.format = USER_FORMAT
	copy.edition = profile.id
	DirAccess.make_dir_recursive_absolute(user_dir(profile))
	var path := _user_path(profile, name)
	var temporary := "%s.%d-%d.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "write"
	file.store_string(JSON.stringify(copy, "\t"))
	file.flush()
	var written := file.get_error()
	file.close()
	if written != OK or (not replace and FileAccess.file_exists(path)) or DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return "write"
	return ""

static func delete_user(profile: ELProfile, name: String) -> bool:
	return user_exists(profile, name) and DirAccess.remove_absolute(_user_path(profile, name)) == OK
