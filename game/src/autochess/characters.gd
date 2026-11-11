class_name ELAutochessCharacters
extends RefCounted
## Etherlords II heroes who lead the nine companies. The choice is cosmetic:
## a portrait in the standings and the hero's own figure beside the board.

const TEMPLATES := [
	"Hegrir", "Frotti", "Haereid", "Veldi",
	"Rinalda", "Barnard", "Agnette", "Ermelaus",
	"Aline", "Esmond", "Deavan", "Fiona",
	"Alpha-900E \"Suppressor\"", "Gamma-200F \"Tricker\"", "Delta-300B \"Perfection Priestess\"", "Alpha-200E \"Insidious\"",
]
const FACTION_ARENA := {"Red": "Red.001", "Blue": "Blue.001", "Green": "Green.001", "Black": "SynthetsCity.001"}

static func choices(profile: ELProfile) -> Array[String]:
	var found: Array[String] = []
	var table := profile.table("HeroTemplates")
	for id: String in TEMPLATES:
		var row: Dictionary = table.get(id, {})
		if row.has("Model") and row.has("Face"): found.append(id)
	return found

static func valid(profile: ELProfile, id: String) -> String:
	var list := choices(profile)
	if id in list: return id
	return list[0] if not list.is_empty() else ""

static func row(profile: ELProfile, id: String) -> Dictionary:
	return profile.table("HeroTemplates").get(id, {})

static func title(profile: ELProfile, id: String) -> String:
	var key := String(row(profile, id).get("ELKName", ""))
	var text := ELAutochessArtifacts._elk(profile, key)
	return text if not text.is_empty() else id.get_slice(" ", 0)

static func color(profile: ELProfile, id: String) -> String:
	return String(row(profile, id).get("Color", "Red"))

static func portrait(profile: ELProfile, id: String) -> Texture2D:
	var data := row(profile, id)
	return profile.portrait(int(data.get("Face", 0))) if data.has("Face") else null

static func arena(profile: ELProfile, id: String) -> String:
	var scene := String(FACTION_ARENA.get(color(profile, id), "Green.001"))
	return scene if profile.table("CombatSceneDB").has(scene) else "Green.001"

## Opponents: different heroes, starting after the human's choice.
static func opponents(profile: ELProfile, chosen: String, count: int, seed_value: int) -> Array[String]:
	var list := choices(profile).filter(func(id: String) -> bool: return id != chosen)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	for i in range(list.size() - 1, 0, -1):
		var other := random.randi_range(0, i)
		var held: String = list[i]
		list[i] = list[other]
		list[other] = held
	var result: Array[String] = []
	for i in count: result.append(list[i % maxi(1, list.size())] if not list.is_empty() else chosen)
	return result
