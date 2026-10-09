class_name ELMapPickups
extends RefCounted
## First-game map pickups: battle artifacts and global-spell scrolls. A hero
## takes one from an adjacent tile during the night's use stage; the object
## leaves the map and the item belongs to that hero. Taking costs nothing but
## the walk and ends the hero's order. Only the local human sees the message.
##
## Scrolls do not cast anything when taken. They are
## kept as owned items, and the player's availability list is derived from the
## authored base list plus every living hero's scrolls, as the original
## recomputes it on pickup, hero loss and load.
const FULL := "FullSpell"
const PART := "PartSpell"
## Parts of one spell complete it at this count.
const COMPLETE := 4

static func is_pickup(item: Dictionary) -> bool:
	return item.get("group") in ["artefacts", "global_spells"]

static func artifact_title(profile: ELProfile, name: String) -> String:
	return profile.text(str(profile.table("Artefacts").get(name, {}).get("ELKName", name)))

static func spell_title(profile: ELProfile, code: String) -> String:
	if code.is_empty(): return ""
	return profile.text(str(profile.table("GlobalSpells").get(code, {}).get("Name", code)))

## Codes a placed scroll offers; placements carry their own list.
static func scroll_spells(profile: ELProfile, item: Dictionary) -> Array[String]:
	var codes: Array[String] = []
	for spell: Dictionary in ELXml.children(ELXml.child(item.get("node", {}), "spells"), "spell"): codes.append(str(spell.attrs.get("code", "")))
	if codes.is_empty():
		var listed: Variant = profile.table("GlobalSpellCut").get(str(item.name), {}).get("Spells", [])
		for code: Variant in (listed if listed is Array else [listed]): codes.append(str(code))
	return codes

## A scroll resolves to its first spell that is colourless or of the player's
## color; none matching gives an empty entry that never becomes castable.
static func resolve(profile: ELProfile, codes: Array, color: String) -> String:
	for code: Variant in codes:
		var row: Dictionary = profile.table("GlobalSpells").get(str(code), {})
		if row.is_empty(): continue
		if row.get("Color") == "Colorless" or row.get("Color") == color: return str(code)
	return ""

static func take_problem(state: ELAdventureSession, hero: Dictionary, item: Dictionary) -> String:
	if hero.get("type") != "hero" or not hero.get("alive", false) or not state.players.has(int(hero.get("owner", -1))): return "This hero cannot take it."
	if ELGlobalSpells.held(hero): return "This hero cannot take it from inside a building."
	if not is_pickup(item) or not item.get("alive", false) or not item.get("visible", false) or not item.get("enabled", false): return "It is no longer here."
	if item.group == "artefacts" and not state.map.profile.table("Artefacts").has(str(item.name)): return "This artifact is unknown."
	if item.group == "global_spells" and str(item.name) not in [FULL, PART]: return "This scroll is unknown."
	return ""

## Called from the use stage once the hero stands beside the object.
static func take(director: ELAdventureDirector, hero: Dictionary, item: Dictionary) -> Dictionary:
	var state := director.state
	var profile := state.map.profile
	var local: bool = int(hero.get("owner", -1)) == state.current_player
	var problem := take_problem(state, hero, item)
	if problem.is_empty() and not ELStrategy.adjacent(director, hero, item): problem = "Move next to it first."
	if not problem.is_empty():
		if local: director.presentation.emit({"kind": "notice", "text": problem})
		return {}
	var message := {}
	if item.group == "artefacts":
		if not hero.has("artifacts"): hero.artifacts = []
		# Taken artifacts are fully charged; charges are spent only inside a battle.
		hero.artifacts.append({"name": str(item.name), "charges": int(profile.table("Artefacts")[item.name].get("MaxCharges", 0))})
		message = {"key": "T_MB_TAKE_ARTIFACT", "text": ELAdditionalBuildings.format(profile, "T_MB_TAKE_ARTIFACT", [artifact_title(profile, str(item.name))]), "artifact": str(item.name)}
	else:
		if not hero.has("gs_items"): hero.gs_items = []
		var codes := scroll_spells(profile, item)
		hero.gs_items.append({"kind": str(item.name), "spells": codes})
		var code := resolve(profile, codes, str(state.players[int(hero.owner)].get("color", "")))
		message = {"key": "T_MB_TAKE_GS", "text": ELAdditionalBuildings.format(profile, "T_MB_TAKE_GS", [spell_title(profile, code)]), "spell": code}
	item.alive = false
	item.visible = false
	item.enabled = false
	hero.strategy_order = {}
	state.event.emit({"kind": "object_killed", "id": item.uid})
	state.event.emit({"kind": "inventory_changed", "id": hero.uid})
	state.event.emit({"kind": "pickup_taken", "id": item.uid, "hero": hero.uid, "player": hero.owner, "message": message.key})
	if local:
		director.notice = message.text
		# The original MessageBox shows the artifact or spell picture above the text.
		var picture := ["artifact", message.artifact] if message.has("artifact") else ["global_spell", message.spell]
		director.presentation.emit({"kind": "building_message", "hero": hero.uid, "building": -1, "title": "", "text": message.text, "resources": [], "skill": "", "key": message.key, "box": "first", "picture": picture})
	return message

## Authored castle spells of a player: the <global_spells> list in its map entry.
static func base_spells(state: ELAdventureSession, player: int) -> Array[String]:
	var codes: Array[String] = []
	for node: Dictionary in state.map.players:
		if int(node.attrs.get("id", -1)) != player: continue
		for spell: Dictionary in ELXml.children(ELXml.child(node, "global_spells"), "spell"): codes.append(str(spell.attrs.get("code", "")))
	return codes

## Availability entries {code, partial, count} in the original order: the base
## list first, then each living hero's scrolls in hero order. One hero's parts
## of a spell count 1, 2, then 4 (complete); parts held by different heroes add
## up but stop at 3, so they never complete a spell. A full scroll replaces an
## incomplete entry; a full or complete entry is never changed again.
static func availability(state: ELAdventureSession, player: int) -> Array:
	var holders: Array = []
	for hero: Dictionary in state.objects.values():
		if hero.get("type") == "hero" and hero.get("alive", false) and int(hero.get("owner", -1)) == player: holders.append(hero.get("gs_items", []))
	return merge(state.map.profile, str(state.players.get(player, {}).get("color", "")), base_spells(state, player), holders)

## `holders` lists each hero's scrolls ({kind, spells}) in hero order.
static func merge(profile: ELProfile, color: String, base: Array, holders: Array) -> Array:
	var entries: Array = []
	for code: Variant in base: entries.append({"code": str(code), "partial": false, "count": 0})
	for scrolls: Array in holders:
		var own: Array = []
		for scroll: Dictionary in scrolls:
			var code := resolve(profile, scroll.spells, color)
			var partial: bool = scroll.kind == PART
			var found := false
			for entry: Dictionary in own:
				if entry.code == code and entry.partial == partial:
					found = true
					if partial and int(entry.count) in [1, 2]: entry.count += 1
					if partial and int(entry.count) == 3: entry.count = COMPLETE
					break
			if not found: own.append({"code": code, "partial": partial, "count": 1 if partial else 0})
		for entry: Dictionary in own:
			var merged := false
			for current: Dictionary in entries:
				if current.code != entry.code: continue
				merged = true
				if not current.partial or int(current.count) == COMPLETE: break
				if not entry.partial or int(entry.count) == COMPLETE:
					current.partial = entry.partial
					current.count = entry.count
				else: current.count = mini(3, int(current.count) + int(entry.count))
				break
			if not merged: entries.append(entry.duplicate())
	return entries

static func castable(entries: Array, code: String) -> bool:
	if code.is_empty(): return false
	for entry: Dictionary in entries:
		if entry.code == code: return not entry.partial or int(entry.count) == COMPLETE
	return false

## Codes a player could cast if global spells were available in the remake.
static func available_codes(state: ELAdventureSession, player: int) -> Array[String]:
	var entries := availability(state, player)
	var codes: Array[String] = []
	for entry: Dictionary in entries:
		if castable(entries, str(entry.code)) and not codes.has(str(entry.code)): codes.append(str(entry.code))
	return codes

static func restore_hero(profile: ELProfile, hero: Dictionary) -> bool:
	for key: String in ["artifacts", "gs_items", "keys"]:
		if not hero.has(key): hero[key] = []
		if not hero[key] is Array or hero[key].size() > 1000: return false
	for index in hero.artifacts.size():
		var item: Variant = hero.artifacts[index]
		if not item is Dictionary or not item.get("name") is String or not profile.table("Artefacts").has(item.name): return false
		var maximum := int(profile.table("Artefacts")[item.name].get("MaxCharges", 0))
		if not ELLuaSave._integer(item.get("charges"), 0, maximum): return false
		hero.artifacts[index] = {"name": item.name, "charges": int(item.charges)}
	for index in hero.gs_items.size():
		var item: Variant = hero.gs_items[index]
		if not item is Dictionary or item.get("kind") not in [FULL, PART] or not item.get("spells") is Array or item.spells.size() > 64: return false
		for code: Variant in item.spells:
			if not code is String or code.length() > 16: return false
	var seen := {}
	for key: Variant in hero.keys:
		if not key is String or key.length() > 256 or seen.has(key): return false
		seen[key] = true
	return true
