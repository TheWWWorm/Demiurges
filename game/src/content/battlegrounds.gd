class_name ELBattlegrounds
extends RefCounted
## EL2 battleground buildings that a hero activates by use (CombatTime and
## CombatMission). CombatRange buildings work by distance in ELBattleScripts.
## A time building then waits ten world days before anyone may use it again
## (shared spring/teacher base); a mission building serves each hero
## once. Activation appends an affect without replacing earlier
## ones (only beacons are deduplicated) and shows the building's
## message, with the script name in place of %s for time buildings.

const WAIT := 10
## Affects that count down per world day: time battlegrounds and beacons.
const TIMED := ["time", "beacon"]

static func affect(state: ELAdventureSession, building: Dictionary) -> Dictionary:
	var result := ELBattleScripts.building_affect(state.map.profile, building)
	return result if not result.is_empty() and result.kind in ["time", "mission"] else {}

static func usable(actor: Dictionary, building: Dictionary, granted: Dictionary) -> bool:
	if granted.kind == "time": return int(building.get("wait", 0)) <= 0
	return int(actor.uid) not in building.get("visitors", []).map(func(uid: Variant) -> int: return int(uid))

static func use(director: ELAdventureDirector, actor: Dictionary, building: Dictionary) -> bool:
	var state := director.state
	var granted := affect(state, building)
	if granted.is_empty() or not usable(actor, building, granted): return false
	# The shared use action pays the building's use price first.
	ELAdventureClock.use_points(state, actor, ELSecondBuildings.USE_COST)
	if granted.kind == "time": building.wait = WAIT
	else:
		if not building.has("visitors"): building.visitors = []
		building.visitors.append(int(actor.uid))
	if not actor.has("affects"): actor.affects = []
	actor.affects.append(granted)
	if int(actor.owner) == state.current_player:
		var row: Dictionary = state.map.profile.table("AdditionalBuildings").get(str(building.name), {})
		var key := str(row.get("Message1", ""))
		var text := state.map.profile.text(key)
		if granted.kind == "time": text = text.replace("%s", str(granted.name))
		director.presentation.emit({"kind": "building_message", "hero": actor.uid, "building": building.uid, "title": state.map.profile.text(str(row.get("ELKName", building.name))),
			"text": text, "resources": [], "skill": "", "key": key})
	return true

## World day rollover: every actor's timed affects count down first
## (dropped at zero), then every building's wait.
static func new_day(state: ELAdventureSession) -> void:
	if state.map.profile.id != "el2": return
	for item: Dictionary in state.objects.values():
		if item.get("type") in ["hero", "monster"] and item.has("affects"):
			for entry: Variant in item.affects:
				if entry is Dictionary and entry.get("kind") in TIMED: entry.ticks = maxi(int(entry.get("ticks", 0)) - 1, 0)
			var before: int = item.affects.size()
			item.affects = item.affects.filter(func(entry: Variant) -> bool: return not (entry is Dictionary and entry.get("kind") in TIMED and int(entry.ticks) <= 0))
			# Travel is recalculated only when an affect ran out.
			if item.affects.size() != before: ELSecondBuildings.refresh_travel(item)
		if int(item.get("wait", 0)) > 0: item.wait = int(item.wait) - 1
