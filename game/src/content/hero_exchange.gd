class_name ELHeroExchange
extends RefCounted
## First-game hero item bar shared by the HeroScreen and the ExchangeScreen
## (the original CBaseHeroScreen). A hero's bar lists
## its battle artifacts, then its global-spell scrolls. Dragging one entry onto a bar moves the item
## object itself, so charges stay with it; there is no capacity limit and no
## refusal. Opening the exchange costs nothing and issues no order.

## Bar entries in display order: {kind: "artifact"|"gs", index, item}.
static func bar(hero: Dictionary) -> Array:
	var entries: Array = []
	var artifacts: Array = hero.get("artifacts", [])
	for index in artifacts.size(): entries.append({"kind": "artifact", "index": index, "item": artifacts[index]})
	var scrolls: Array = hero.get("gs_items", [])
	for index in scrolls.size(): entries.append({"kind": "gs", "index": index, "item": scrolls[index]})
	return entries

static func count(hero: Dictionary) -> int:
	return hero.get("artifacts", []).size() + hero.get("gs_items", []).size()

static func applies(state: ELAdventureSession) -> bool:
	return state != null and state.map.profile.id == "el1"

## Ctrl+click exchange: the local player's planning turn, two
## different living heroes of the same owner, the selected one standing on or
## 8-adjacent to the target's footprint.
static func exchange_problem(director: ELAdventureDirector, selected_id: int, target_id: int) -> String:
	var state := director.state
	if not applies(state): return "Heroes exchange items only in the first game."
	if not director.can_move() or not director.movement.is_empty(): return "Heroes can exchange items only during your turn."
	var selected := state.object(selected_id)
	var target := state.object(target_id)
	if selected.is_empty() or target.is_empty() or selected.get("type") != "hero" or target.get("type") != "hero": return "Select one of your heroes, then Ctrl+click another."
	if not selected.get("alive", false) or not target.get("alive", false): return "Select one of your heroes, then Ctrl+click another."
	if selected_id == target_id: return "Ctrl+click a different hero to exchange items."
	if int(selected.get("owner", -1)) != state.current_player or int(target.get("owner", -1)) != int(selected.owner): return "Items can be exchanged only between your own heroes."
	if not ELStrategy.adjacent(director, selected, target): return "The heroes must stand next to each other."
	return ""

## Bar position for a drop: the slot under the cursor (absolute, scroll
## included), otherwise the front for the left half of the bar and the end
## for the right half.
static func drop_position(hero: Dictionary, slot: int, left_half: bool) -> int:
	if slot >= 0: return slot
	return 0 if left_half else count(hero)

## Moves bar entry `index` of `source` before bar position `position` of
## `target`: artifacts stay ahead of scrolls, so an artifact's
## position is clamped to the target's artifact count and a scroll's is taken
## relative to the scrolls. The source copy is erased after the insert.
static func move(source: Dictionary, index: int, target: Dictionary, position: int) -> bool:
	var entries := bar(source)
	if index < 0 or index >= entries.size() or source.is_empty() or target.is_empty(): return false
	var entry: Dictionary = entries[index]
	var key := "artifacts" if entry.kind == "artifact" else "gs_items"
	if not target.has(key): target[key] = []
	var into: Array = target[key]
	var from: Array = source[key]
	var at := mini(maxi(0, position), target.get("artifacts", []).size()) if entry.kind == "artifact" else maxi(0, position - target.get("artifacts", []).size())
	at = mini(at, into.size())
	var erase: int = entry.index
	into.insert(at, entry.item)
	if is_same(source, target) and at <= erase: erase += 1
	from.remove_at(erase)
	return true

## Bar index of an item after a move, for presentation; -1 when absent.
static func find(hero: Dictionary, item: Dictionary) -> int:
	var entries := bar(hero)
	for index in entries.size():
		if is_same(entries[index].item, item): return index
	return -1

## Applies a drag on the adventure map and announces the changed inventories.
static func transfer(state: ELAdventureSession, source_id: int, index: int, target_id: int, position: int) -> bool:
	var source := state.object(source_id)
	var target := state.object(target_id)
	if not applies(state) or int(source.get("owner", -1)) != state.current_player or int(target.get("owner", -2)) != int(source.get("owner", -1)): return false
	if not move(source, index, target, position): return false
	state.event.emit({"kind": "inventory_changed", "id": source_id})
	if target_id != source_id: state.event.emit({"kind": "inventory_changed", "id": target_id})
	return true

## DismissHero (0x631, CDismissHero): after confirmation the hero
## is lost through the same routine as a death; its items go with it.
static func dismiss_problem(director: ELAdventureDirector, hero_id: int) -> String:
	var hero := director.state.object(hero_id)
	if not applies(director.state) or hero.get("type") != "hero" or not hero.get("alive", false) or int(hero.get("owner", -1)) != director.state.current_player: return "This hero cannot be dismissed."
	if not director.can_move() or not director.movement.is_empty(): return "Heroes can be dismissed only during your turn."
	return ""

static func dismiss(director: ELAdventureDirector, hero_id: int) -> bool:
	if not dismiss_problem(director, hero_id).is_empty(): return false
	# Removed from the world rather than left as a corpse figure.
	director.state.object(hero_id).visible = false
	director.state._native([float(hero_id)], "ExKillHero")
	return not director.state.object(hero_id).get("alive", true)
