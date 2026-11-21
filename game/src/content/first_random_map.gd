class_name ELFirstRandomMap
extends RefCounted
## Public random-map API. Each recipe selects its original generation rules.
const VERSION := ELFirstRandomMapV2.LATEST_VERSION
const PREFIX := "el1_random_v"
const COLORS := ["Green", "Blue", "Red", "Black"]
const SIZES := [64, 96, 128, 160]
const LAYOUTS := ["frontier", "lakes", "crossroads", "archipelago", "inland_sea", "river_delta", "ring", "peninsulas"]
const ECONOMIES := ["scarce", "normal", "rich"]
const GUARDS := ["none", "normal", "strong"]
const GEMS := {"Green": "Emerald", "Blue": "Sapphire", "Red": "Ruby", "Black": "Diamond"}
const SUMMONS := {"Green": "SVWR", "Blue": "SKWR", "Red": "SCWR", "Black": "SSWR"}
var error := ""
var config: Dictionary = {}
var report: Dictionary = {}

static func defaults(version: int = VERSION) -> Dictionary:
	if version == 1: return ELFirstRandomMapV1.defaults()
	return ELFirstRandomMapV2.defaults(version) if version >= 2 and version <= VERSION else {}

static func normalize(options: Dictionary) -> Dictionary:
	var value: Variant = options.get("version", VERSION)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)): return {}
	if int(value) == 1: return ELFirstRandomMapV1.normalize(options)
	return ELFirstRandomMapV2.normalize(options, int(value)) if int(value) >= 2 and int(value) <= VERSION else {}

static func presets() -> Array[Dictionary]:
	return ELFirstRandomMapV2.presets()

static func is_random_id(id: String) -> bool:
	return id.begins_with(PREFIX)

static func id_for_config(options: Dictionary) -> String:
	var normalized := normalize(options)
	if normalized.is_empty(): return ""
	return ELFirstRandomMapV1.id_for_config(normalized) if int(normalized.version) == 1 else ELFirstRandomMapV2.id_for_config(normalized)

static func seed_for_config(options: Dictionary) -> int:
	var normalized := normalize(options)
	if normalized.is_empty(): return 1
	return ELFirstRandomMapV1.seed_for_config(normalized) if int(normalized.version) == 1 else ELFirstRandomMapV2.seed_for_config(normalized)

static func configuration(map: ELAdventureMap) -> Dictionary:
	return ELFirstRandomMapV1.configuration(map)

static func content_hash(map: ELAdventureMap) -> String:
	return ELFirstRandomMapV1.content_hash(map)

func generate(profile: ELProfile, options: Dictionary = {}) -> ELAdventureMap:
	error = ""
	report = {}
	config = normalize(options)
	if config.is_empty():
		error = "Invalid random-map configuration or unsupported generator version."
		return null
	var worker: RefCounted = ELFirstRandomMapV1.new() if int(config.version) == 1 else ELFirstRandomMapV2.new()
	var map: ELAdventureMap = worker.generate(profile, config)
	error = str(worker.error)
	report = worker.report.duplicate(true)
	return map

## The maps `generate_reused` made last in this run: {key, map, report}, the
## newest first. A large map takes many seconds to generate, and starting it
## from its preview, restarting it or loading its saves asks for the same one.
static var _reused: Array[Dictionary] = []
const REUSED_MAPS := 2

## As `generate`, but a recipe generated before in this run (for the same
## installed data) comes back as a fresh copy of that map instead of being
## generated again; the generator is deterministic, so the map is the same.
## Checks of the generator itself call `generate`.
func generate_reused(profile: ELProfile, options: Dictionary = {}) -> ELAdventureMap:
	var normalized := normalize(options)
	if normalized.is_empty(): return generate(profile, options)
	var key := "%d|%s" % [profile.get_instance_id(), JSON.stringify(normalized, "", true)]
	for index in _reused.size():
		var entry: Dictionary = _reused[index]
		if entry.key != key: continue
		error = ""
		config = normalized
		report = entry.report.duplicate(true)
		_reused.push_front(_reused.pop_at(index))
		return copy_map(entry.map)
	var map := generate(profile, options)
	if map == null: return null
	_reused.push_front({"key": key, "map": copy_map(map), "report": report.duplicate(true)})
	if _reused.size() > REUSED_MAPS: _reused.resize(REUSED_MAPS)
	return map

## A deep copy of a map: its fields and metadata, sharing only the profile.
static func copy_map(map: ELAdventureMap) -> ELAdventureMap:
	var copy := ELAdventureMap.new()
	for property: Dictionary in map.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var value: Variant = map.get(property.name)
		copy.set(property.name, value.duplicate(true) if value is Array or value is Dictionary else value)
	for name: StringName in map.get_meta_list():
		var value: Variant = map.get_meta(name)
		copy.set_meta(name, value.duplicate(true) if value is Array or value is Dictionary else value)
	return copy
