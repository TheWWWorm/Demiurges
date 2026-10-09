class_name ELInterception
extends RefCounted
## EL1 registered guard areas. Ordinary moving heroes do not create zones.
## Neutral creatures guard radius two; a fort garrison guards radius three
## around the fort rectangle, which stays inside its own area although blocked.
## Covered cells persist across movement; recomputing on each step would erase
## the destination zone as soon as the moving hero occupies it.
const DIRECTIONS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const ROUTE_NOTICE := "This route enters a guarded area. The hero will stop for combat."
var zones: Dictionary = {}
var cells: Dictionary = {}

static func guards(actor: Dictionary) -> bool:
	return actor.get("type") == "monster" and actor.get("owner", -1) <= 0 and actor.get("alive", false) and actor.get("visible", false) and actor.get("placed", true) and not actor.get("fortified", false)

static func spell_fort(actor: Dictionary) -> bool:
	return actor.get("type") == "hero" and actor.get("alive", false) and int(actor.get("spell_fort", 0)) > 0

static func flood(grid: ELAdventureGrid, origin: Vector2i, radius: int, allowed: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = [origin]
	var visited := {origin: true}
	var cursor := 0
	while cursor < result.size():
		var current := result[cursor]
		cursor += 1
		for direction: Vector2i in DIRECTIONS:
			var point := current + direction
			if visited.has(point) or origin.distance_squared_to(point) >= radius * radius - 1 or not grid.contains(point): continue
			# A fort zone admits its own blocked footprint cells.
			if grid.passability(point) < 0 and not allowed.has(point): continue
			visited[point] = true
			result.append(point)
	return result

func rebuild(state: ELAdventureSession, grid: ELAdventureGrid) -> void:
	if state.map.profile.id == "el2":
		_rebuild_second(state, grid)
		return
	if state.map.profile.id != "el1":
		zones.clear()
		cells.clear()
		return
	var ids := zones.keys()
	for id: int in state.objects:
		if not ids.has(id) and (guards(state.object(id)) or spell_fort(state.object(id)) or not ELForts.garrison_of(state, state.object(id)).is_empty()): ids.append(id)
	zones.clear()
	cells.clear()
	for id: int in ids:
		var actor := state.object(id)
		var fort := ELForts.garrison_of(state, actor)
		if not fort.is_empty():
			var area := fort_area(grid, fort)
			var footprint := {}
			for cell: Vector2i in grid.footprints.get(int(fort.uid), {}).get("cells", []): footprint[area.position + cell] = true
			if grid.contains(area.position): register(actor.uid, area.position, flood(grid, area.position, ELForts.RADIUS, footprint), area)
			continue
		if spell_fort(actor):
			# A fortification spell guards like a one-tile fort on the hero's tile.
			var at := Vector2i(actor.x, actor.y)
			if grid.contains(at): register(actor.uid, at, flood(grid, at, ELForts.RADIUS, {at: true}))
			continue
		if not guards(actor): continue
		var origin := Vector2i(actor.x, actor.y)
		if grid.contains(origin): register(actor.uid, origin, flood(grid, origin, 2))

static func fort_area(grid: ELAdventureGrid, fort: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(fort.x, fort.y), grid.footprints.get(int(fort.uid), {}).get("size", Vector2i.ONE))

## Squared distance to an inclusive rectangle, used for overlap priority.
static func rect_distance(area: Rect2i, point: Vector2i) -> int:
	var dx := maxi(0, maxi(area.position.x - point.x, point.x - (area.end.x - 1)))
	var dy := maxi(0, maxi(area.position.y - point.y, point.y - (area.end.y - 1)))
	return dx * dx + dy * dy

func register(id: int, origin: Vector2i, covered: Array[Vector2i], area := Rect2i()) -> void:
	if area.size == Vector2i.ZERO: area = Rect2i(origin, Vector2i.ONE)
	zones[id] = {"origin": origin, "cells": covered, "area": area}
	for point: Vector2i in covered:
		var weight := int(1024.0 / (rect_distance(area, point) + 1))
		if not cells.has(point): cells[point] = {"guards": [], "primary": id, "weight": 0}
		var tile: Dictionary = cells[point]
		tile.guards.append(id)
		# The later registered zone wins equal weights in the original.
		if weight >= tile.weight:
			tile.primary = id
			tile.weight = weight

static func hostile(state: ELAdventureSession, guardian: Dictionary, actor: Dictionary, active := true) -> bool:
	return active and not guardian.is_empty() and guardian.get("alive", false) and state.hostile(guardian, actor)

func enemies(state: ELAdventureSession, actor: Dictionary, point: Vector2i) -> Array[int]:
	var result: Array[int] = []
	var tile: Dictionary = cells.get(point, {})
	if tile.is_empty() or not hostile(state, state.object(tile.primary), actor): return result
	for id: int in tile.guards:
		if hostile(state, state.object(id), actor): result.append(id)
	return result

func can_step(state: ELAdventureSession, grid: ELAdventureGrid, actor: Dictionary, point: Vector2i) -> bool:
	if actor.get("fortified", false) or int(actor.get("spell_fort", 0)) > 0 or actor.get("intercepted", false) or not enemies(state, actor, Vector2i(actor.x, actor.y)).is_empty(): return false
	var cost := grid.passability(point)
	return cost >= 0 and cost <= int(actor.ap)

func preview(state: ELAdventureSession, actor: Dictionary, path: Array) -> Array:
	for index in path.size():
		if not enemies(state, actor, path[index]).is_empty(): return path.slice(0, index + 1)
	return path

func snapshot() -> Array:
	var result: Array = []
	for id: int in zones:
		var covered: Array = []
		for point: Vector2i in zones[id].cells: covered.append([point.x, point.y])
		result.append({"id": id, "cells": covered})
	return result

func restore(raw: Variant, state: ELAdventureSession, grid: ELAdventureGrid) -> bool:
	# Second game: zones are pure discs, so they are flooded again from the
	# actors (and their saved zone radius) instead of trusting cached cells.
	if state.map.profile.id == "el2":
		if not raw is Array: return false
		_rebuild_second(state, grid)
		return true
	if not raw is Array or raw.size() != zones.size(): return false
	var restored: Array = []
	var ids := {}
	for row: Variant in raw:
		if not row is Dictionary or not ELLuaSave._integer(row.get("id"), 0, 0x7fffffff) or not zones.has(int(row.id)) or ids.has(int(row.id)) or not row.get("cells") is Array or row.cells.is_empty(): return false
		var id := int(row.id)
		# Cached geometry must match the current guard kind: radius two for a
		# neutral creature, radius three from the fort origin for a garrison.
		var origin: Vector2i = zones[id].origin
		var area: Rect2i = zones[id].area
		var radius := 2 if area.size == Vector2i.ONE and ELForts.garrison_of(state, state.object(id)).is_empty() and not spell_fort(state.object(id)) else ELForts.RADIUS
		var limit := (2 * radius + area.size.x) * (2 * radius + area.size.y)
		if row.cells.size() > limit: return false
		var covered: Array[Vector2i] = []
		for pair: Variant in row.cells:
			if not pair is Array or pair.size() != 2 or not ELLuaSave._integer(pair[0], 0, state.map.width - 1) or not ELLuaSave._integer(pair[1], 0, state.map.height - 1): return false
			var point := Vector2i(int(pair[0]), int(pair[1]))
			if not grid.contains(point) or origin.distance_squared_to(point) >= radius * radius - 1 or covered.has(point): return false
			covered.append(point)
		if covered[0] != origin: return false
		ids[id] = true
		restored.append({"id": id, "origin": origin, "cells": covered, "area": area})
	zones.clear()
	cells.clear()
	for row: Dictionary in restored: register(row.id, row.origin, row.cells, row.area)
	return true

## Second game: every alive hero or monster not
## owned by player 1 guards a disc of radius 2 around its cell, widened to 3
## once it has moved; forts (any owner) radius 3 from the fort origin, and
## Fortify heroes radius 3. Discs ignore walls, water and occupants. All zones
## are flooded again from scratch in object order on every change.
static func second_guard(actor: Dictionary) -> bool:
	return actor.get("type") in ["hero", "monster"] and actor.get("alive", false) and actor.get("placed", true) and int(actor.get("owner", -1)) != 1 and not actor.get("fortified", false)

static func disc(grid: ELAdventureGrid, origin: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [origin]
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var point := origin + Vector2i(dx, dy)
			if point != origin and dx * dx + dy * dy < radius * radius - 1 and grid.contains(point): result.append(point)
	return result

func _rebuild_second(state: ELAdventureSession, grid: ELAdventureGrid) -> void:
	var previous := zones.duplicate()
	zones.clear()
	cells.clear()
	for id: int in state.objects:
		var actor := state.object(id)
		var fort := ELForts.garrison_of(state, actor)
		if not fort.is_empty():
			var area := fort_area(grid, fort)
			if grid.contains(area.position): register(id, area.position, disc(grid, area.position, ELForts.RADIUS), area)
			continue
		if spell_fort(actor):
			var at := Vector2i(actor.x, actor.y)
			if grid.contains(at): register(id, at, disc(grid, at, ELForts.RADIUS))
			continue
		if not second_guard(actor): continue
		var origin := Vector2i(actor.x, actor.y)
		if not grid.contains(origin): continue
		# A zoned guard that changes cell is registered again with radius 3.
		if previous.has(id) and previous[id].origin != origin: actor.zone_radius = 3
		register(id, origin, disc(grid, origin, 3 if int(actor.get("zone_radius", 2)) == 3 else 2))

## The guard that intercepts `mover` on `point`, or -1. Only player 1's heroes
## are intercepted; the cell's primary zone must be hostile, then each hostile
## guard in registration order is offered to Hook_OnIntercept (a veto passes
## to the next; a missing hook or a script error allows).
func intercept(state: ELAdventureSession, mover: Dictionary, point: Vector2i) -> int:
	if mover.is_empty() or mover.get("type") != "hero" or int(mover.get("owner", -1)) != 1: return -1
	var tile: Dictionary = cells.get(point, {})
	if tile.is_empty() or not hostile(state, state.object(tile.primary), mover): return -1
	for id: int in tile.guards:
		if not hostile(state, state.object(id), mover): continue
		if allows(state, mover.uid, id): return id
	return -1

static func allows(state: ELAdventureSession, hero: int, guard: int) -> bool:
	if state.vm == null or not state.vm.has_function("Hook_OnIntercept"): return true
	var vm := state.vm
	var arguments := [float(hero), float(guard)]
	# Usually reached from ExCheckIntercepts inside a running script: call
	# without resetting the outer call's depth and counters.
	var context := vm._context
	var result: Array = vm._invoke(vm.globals["Hook_OnIntercept"], arguments) if vm._depth > 0 else vm.invoke("Hook_OnIntercept", arguments)
	vm._context = context
	if not vm.error.is_empty():
		vm.error = ""
		return true
	# Conversion: 1 and "yes" allow; nothing, nil,
	# 0, 0.4 and "0" veto.
	var value: Variant = result[0] if not result.is_empty() else null
	if value is float or value is int: return int(value) != 0
	if value is String: return int(value) != 0 if value.is_valid_float() else not value.is_empty()
	return false

## Cells whose primary zone is hostile to `actor` (routes avoid them first).
func hostile_cells(state: ELAdventureSession, actor: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for point: Vector2i in cells:
		if hostile(state, state.object(cells[point].primary), actor): result.append(point)
	return result
