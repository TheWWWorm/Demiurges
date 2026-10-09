class_name ELSecondArtifacts
extends RefCounted
## Second-game artifacts outside the duel: hero entries with current charges,
## generated (constructor) artifacts, recharging and the post-battle charge
## write-back. Standard entries are {name, charges}; a generated one also
## carries its definition, {name: "CustomN", charges, custom: {elk_name, spell,
## first, gap, max, icon, r_count, r_duration}}, so it survives saves and
## chapter transitions on its own. The first game keeps ELMapPickups.
const TRACKER := "ArtifactTracker.scp"
const RECHARGER := "ArtefactRecharger"
const RECIPE := "ArtefactRecipe"
const BLANK_SPELL := "BLNK"
const CUSTOM_PREFIX := "Custom"
const MAX_ITEMS := 1000

static func applies(profile: ELProfile) -> bool:
	return profile.id == "el2"

## A normalised generated-artifact definition, or {} when invalid.
static func custom_definition(profile: ELProfile, raw: Variant) -> Dictionary:
	if raw is not Dictionary or raw.get("spell") is not String or raw.get("elk_name") is not String: return {}
	if not profile.table("CombatSpells").has(raw.spell) or raw.elk_name.length() > 256: return {}
	var result := {"elk_name": raw.elk_name, "spell": raw.spell}
	for field: String in ["first", "gap", "max", "icon", "r_count", "r_duration"]:
		var value: Variant = raw.get(field, -1 if field == "icon" else 0)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or float(value) != floorf(float(value)) or float(value) < -1.0 or float(value) > 1000000.0: return {}
		result[field] = int(value)
	if result.first < 0 or result.gap < 0 or result["max"] < 0 or result.r_count < 0 or result.r_duration < 0: return {}
	return result

static func is_custom(item: Dictionary) -> bool:
	return item.get("custom") is Dictionary

## The artifact's spell code (BLNK for a Blank).
static func spell(profile: ELProfile, item: Dictionary) -> String:
	if is_custom(item): return str(item.custom.get("spell", ""))
	return str(profile.table("Artefacts").get(str(item.get("name", "")), {}).get("SpellType", ""))

static func is_blank(profile: ELProfile, item: Dictionary) -> bool:
	return not is_custom(item) and spell(profile, item) == BLANK_SPELL

static func max_charges(profile: ELProfile, item: Dictionary) -> int:
	if is_custom(item): return int(item.custom.get("max", 0))
	return int(profile.table("Artefacts").get(str(item.get("name", "")), {}).get("MaxCharges", 0))

static func title(profile: ELProfile, item: Dictionary) -> String:
	if is_custom(item): return profile.text(str(item.custom.get("elk_name", item.name)))
	return ELMapPickups.artifact_title(profile, str(item.get("name", "")))

## The template's first usable round and the gap after each use.
static func cadence(profile: ELProfile, item: Dictionary) -> Vector2i:
	if is_custom(item): return Vector2i(int(item.custom.get("first", 0)), int(item.custom.get("gap", 0)))
	var row: Dictionary = profile.table("Artefacts").get(str(item.get("name", "")), {})
	return Vector2i(int(row.get("FirstUsage", 0)), int(row.get("UsageGap", 0)))

## "Charges Left" tooltip text (T_ARTIFACT_TT: charges, first round, gap).
static func tooltip(profile: ELProfile, item: Dictionary) -> String:
	var body := profile.text("T_ARTIFACT_TT")
	var timing := cadence(profile, item)
	var values: Array = [int(item.get("charges", 0)), timing.x, timing.y]
	var details := body % values.slice(0, body.count("%d")) if body.count("%d") in [1, 2, 3] else str(int(item.get("charges", 0)))
	return title(profile, item) + "\n" + details

## Every hero artifact that carries the definition `name`, across the world.
static func template(state: ELAdventureSession, name: String) -> Dictionary:
	for actor: Dictionary in state.objects.values():
		for item: Variant in actor.get("artifacts", []):
			if item is Dictionary and is_custom(item) and str(item.get("name", "")) == name: return item.custom
	return {}

static func known(state: ELAdventureSession, name: String) -> bool:
	return state.map.profile.table("Artefacts").has(name) or not template(state, name).is_empty()

## A new full-charge copy of a table or generated artifact.
static func entry(state: ELAdventureSession, name: String) -> Dictionary:
	var definition := template(state, name)
	if not definition.is_empty(): return {"name": name, "charges": int(definition.get("max", 0)), "custom": definition.duplicate(true)}
	return {"name": name, "charges": int(state.map.profile.table("Artefacts").get(name, {}).get("MaxCharges", 0))}

## The first CustomN name used by no template, so names never collide after a load.
static func next_custom_name(state: ELAdventureSession) -> String:
	var number := 1
	while known(state, CUSTOM_PREFIX + str(number)): number += 1
	return CUSTOM_PREFIX + str(number)

## ExCreateArtifact: a new template with the given values and a full-charge
## copy for `hero`. Charges also set the maximum.
static func create(state: ELAdventureSession, hero: Dictionary, elk_name: String, code: String, charges: int, first: int, gap: int, icon: int) -> String:
	var name := next_custom_name(state)
	if not hero.has("artifacts"): hero.artifacts = []
	hero.artifacts.append({"name": name, "charges": maxi(0, charges), "custom": {"elk_name": elk_name, "spell": code, "first": maxi(0, first), "gap": maxi(0, gap), "max": maxi(0, charges), "icon": icon, "r_count": 0, "r_duration": 0}})
	state.event.emit({"kind": "inventory_changed", "id": int(hero.uid)})
	return name

## Sets every artifact to its maximum (a Blank's is zero).
static func recharge(profile: ELProfile, hero: Dictionary) -> void:
	for item: Dictionary in hero.get("artifacts", []): item.charges = max_charges(profile, item)

## After an accepted battle the hero keeps the charges its side ended with.
## Hero artifacts match side entries by name in list order with one forward
## cursor; `count` limits the entries to the hero's own (the fort
## rod is appended after them and never written back).
static func write_back(hero: Dictionary, entries: Array, count: int) -> void:
	var cursor := 0
	for item: Dictionary in hero.get("artifacts", []):
		for index in range(cursor, mini(count, entries.size())):
			if str(entries[index].get("name", "")) == str(item.get("name", "")):
				item.charges = int(entries[index].charges)
				cursor = index + 1
				break

## The duel options entry for a hero artifact: current charges, plus its definition.
static func battle_entry(item: Dictionary) -> Dictionary:
	var result := {"name": str(item.get("name", "")), "charges": int(item.get("charges", 0))}
	if is_custom(item): result.custom = item.custom.duplicate(true)
	return result

## Saved or carried hero artifacts: validates and restores integer fields.
static func restore_hero(profile: ELProfile, hero: Dictionary) -> bool:
	if not hero.has("artifacts"): return true
	if hero.artifacts is not Array or hero.artifacts.size() > MAX_ITEMS: return false
	for index in hero.artifacts.size():
		var item: Variant = hero.artifacts[index]
		if item is not Dictionary or item.get("name") is not String or item.name.length() > 64: return false
		var restored := {"name": item.name}
		if item.has("custom"):
			var definition := custom_definition(profile, item.custom)
			if definition.is_empty(): return false
			restored.custom = definition
		elif not profile.table("Artefacts").has(item.name): return false
		if not ELLuaSave._integer(item.get("charges"), 0, max_charges(profile, restored)): return false
		restored.charges = int(item.charges)
		hero.artifacts[index] = restored
	if hero.has("artefact_blank_count"):
		if not ELLuaSave._integer(hero.artefact_blank_count, -2147483648, 2147483647): return false
		hero.artefact_blank_count = int(hero.artefact_blank_count)
	return true

static func is_building(item: Dictionary) -> bool:
	return item.get("group") == "additional_buildings" and str(item.get("name", "")) in [RECHARGER, RECIPE]

## Artifact Reconstructor: usable when the hero has any artifact (a Blank
## counts); recharges them all and has no cooldown. Artifact recipe: always
## usable; shows its placement's recipe text. Only the local owner sees the box.
static func visit(director: ELAdventureDirector, hero: Dictionary, item: Dictionary) -> void:
	var state := director.state
	var profile := state.map.profile
	var local: bool = int(hero.get("owner", -1)) == state.current_player
	if not ELStrategy.adjacent(director, hero, item):
		if local: director.presentation.emit({"kind": "notice", "text": "Move next to this building first."})
		return
	var row: Dictionary = profile.table("AdditionalBuildings").get(str(item.name), {})
	var heading := profile.text(str(row.get("ELKName", item.name)))
	var key := str(row.get("Message1", ""))
	var text := profile.text(key)
	if str(item.name) == RECHARGER:
		if hero.get("artifacts", []).is_empty():
			if local: director.presentation.emit({"kind": "notice", "text": "%s: this hero has no artifacts." % heading})
			return
	# The shared use action pays the building's use price first.
	ELAdventureClock.use_points(state, hero, ELSecondBuildings.USE_COST)
	if str(item.name) == RECHARGER:
		recharge(profile, hero)
		state.event.emit({"kind": "artifacts_recharged", "id": int(hero.uid), "building": int(item.uid)})
		state.event.emit({"kind": "inventory_changed", "id": int(hero.uid)})
	else:
		key = str(ELXml.value(item.get("node", {}), "params")).strip_edges()
		text = profile.text(key) if not key.is_empty() else text
		# The recipe's use journals its text with the visiting hero.
		ELSecondNotebook.add_phrase(state, key if not key.is_empty() else str(row.get("Message1", "")), hero.uid, true)
	state.event.emit({"kind": "building_used", "id": int(item.uid), "hero": int(hero.uid), "player": int(hero.get("owner", -1)), "message": key})
	if local: director.presentation.emit({"kind": "building_message", "hero": int(hero.uid), "building": int(item.uid), "title": heading, "text": text, "resources": [], "skill": "", "key": key})
