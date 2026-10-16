class_name ELSecondGates
extends RefCounted
## Second-game rune barriers and warding stones (the CRunestone model).
## Barriers carry a key in the first word of their parameter; groups of four
## numbers after it are fog rectangles (ELFog keeps them unseen while closed). A hero may use a barrier when one of its
## keys, without a leading "*", names the barrier's key, and the barrier is
## closed or that key starts with "*" (a toggle key). Use toggles the barrier;
## a warding stone gives its key and disappears. Script natives open, close
## and give keys silently. A fallen hero's keys return to their stones.

const GATES := ["Runestone1", "Runestone2"]
const WARDING := "WardingStone"

static func applies(state: ELAdventureSession) -> bool:
	return state != null and state.map != null and state.map.profile.id == "el2"

static func base(item: Dictionary) -> String:
	var name := str(item.get("name", ""))
	for prefix: String in GATES + [WARDING]:
		if name.begins_with(prefix): return prefix
	return ""

static func is_gate(item: Dictionary) -> bool:
	return item.get("group") == "additional_buildings" and base(item) in GATES

static func is_warding(item: Dictionary) -> bool:
	return item.get("group") == "additional_buildings" and base(item) == WARDING

static func initialize(item: Dictionary) -> void:
	if is_gate(item) and not item.has("opened"): item.opened = false
	if is_warding(item) and not item.has("used"): item.used = false

static func key(item: Dictionary) -> String:
	var params := str(ELXml.value(item.get("node", {}), "params")).strip_edges()
	return params.get_slice(" ", 0) if not params.is_empty() else ""

## The rectangles of `key x0 y0 x1 y1 [x0 y0 x1 y1...]` (constructor:
## atoi per token, groups of four), each min/max ordered and inclusive.
## Shipped: e2mission13 (two stones) and e2mission14 (one).
static func hide_rects(item: Dictionary) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	var tokens := str(ELXml.value(item.get("node", {}), "params")).split(" ", false)
	var index := 1
	while index + 3 < tokens.size():
		var a := Vector2i(tokens[index].to_int(), tokens[index + 1].to_int())
		var b := Vector2i(tokens[index + 2].to_int(), tokens[index + 3].to_int())
		var low := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
		var high := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
		result.append(Rect2i(low, high - low + Vector2i.ONE))
		index += 4
	return result

## Whether `hero` holds a key that may toggle this barrier now.
static func usable(hero: Dictionary, gate: Dictionary) -> bool:
	var wanted := key(gate)
	for held: Variant in hero.get("keys", []):
		var text := str(held)
		if text.trim_prefix("*") == wanted and (not gate.get("opened", false) or text.begins_with("*")): return true
	return false

## Use by a hero standing beside the object. Returns false when refused. An
## accepted use pays the shared 2-point use price first (runestone
## and warding constructors keep the generic price).
static func use(director: ELAdventureDirector, hero: Dictionary, item: Dictionary) -> bool:
	var state := director.state
	var local: bool = int(hero.get("owner", -1)) == state.current_player
	var row: Dictionary = state.map.profile.table("AdditionalBuildings").get(str(item.name), {})
	var message := ""
	if is_gate(item):
		if not usable(hero, item):
			if local: director.presentation.emit({"kind": "notice", "text": "This hero has no key to this barrier."})
			return false
		ELAdventureClock.use_points(state, hero, ELSecondBuildings.USE_COST)
		message = str(row.get("Message2" if item.opened else "Message1", ""))
		set_open(state, item, not item.opened)
	elif is_warding(item):
		ELAdventureClock.use_points(state, hero, ELSecondBuildings.USE_COST)
		give_key(hero, key(item))
		item.used = true
		item.visible = false
		item.enabled = false
		state.event.emit({"kind": "object_changed", "id": item.uid})
		message = str(row.get("Message1", ""))
	else: return false
	if local and not message.is_empty():
		var text := state.map.profile.text(message)
		if not key(item).is_empty(): text += ' ("%s")' % state.map.profile.text(key(item))
		director.presentation.emit({"kind": "building_message", "hero": hero.uid, "building": item.uid, "title": state.map.profile.text(str(row.get("ELKName", item.name))),
			"text": text, "resources": [], "skill": "", "key": message})
	return true

## Original open/close: no key, no message; repeating the current state does nothing.
static func set_open(state: ELAdventureSession, item: Dictionary, opened: bool) -> void:
	if bool(item.get("opened", false)) == opened: return
	item.opened = opened
	state.event.emit({"kind": "barrier_changed", "id": item.uid, "opened": opened})
	state.event.emit({"kind": "object_changed", "id": item.uid})

static func give_key(hero: Dictionary, value: String) -> void:
	if not hero.has("keys"): hero.keys = []
	if not hero.keys.has(value): hero.keys.append(value)

## A fallen hero's keys go back to the warding stones that gave them.
static func drop_keys(state: ELAdventureSession, hero: Dictionary) -> void:
	for held: Variant in hero.get("keys", []):
		for item: Dictionary in state.objects.values():
			if is_warding(item) and item.get("used", false) and key(item) == str(held):
				item.merge({"used": false, "visible": true, "enabled": true}, true)
				state.event.emit({"kind": "object_changed", "id": item.uid})
				break
	hero.keys = []
