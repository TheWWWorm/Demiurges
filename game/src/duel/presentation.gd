class_name ELDuelPresentation
extends RefCounted
## Schedules rule events for the duel view and publishes their display stamps
## once their animation and effect cues have landed.

const CAST_KINDS := ["cast", "artifact"]
## Starts of actions that wait for the previous cast or summon to finish.
const SEQUENCED_KINDS := ["cast", "artifact", "ability", "phase", "script_cast", "combat_start"]

var events: Array[Dictionary] = []
## View clock deadline for the cast currently being shown.
var cast_until := 0.0
var snapshot: Dictionary = {}
var dirty := false
var was_held := false
## Monotonic for the lifetime of the view, including across battle resets.
var serial := 0
var _dispatching := false
var _stamps: Array[Dictionary] = []
## Stamp serial to the number of outstanding cues.
var _waits: Dictionary = {}

func reset() -> void:
	events.clear()
	cast_until = 0.0
	snapshot = {}
	dirty = false
	was_held = false
	_stamps.clear()
	_waits.clear()

func cast_busy(elapsed: float) -> bool:
	return not events.is_empty() or elapsed < cast_until

func display_lagging() -> bool:
	return not _waits.is_empty() or not _stamps.is_empty()

## A melee exchange captures its own events. Later actions wait for it, and
## actions dispatched from either queue bypass this gate.
func hold_event(data: Dictionary, melee: ELMeleePlayback, presenting: Callable) -> bool:
	var has_melee := is_instance_valid(melee)
	if _dispatching or (has_melee and melee.dispatching()): return false
	var combat_closed := has_melee and melee.blocks_cast_queue()
	var kind := String(data.get("kind", ""))
	if not combat_closed and events.is_empty() and ((has_melee and melee.busy()) or not kind in SEQUENCED_KINDS or not presenting.call(kind)): return false
	events.append(data)
	return true

## Dispatches only the events whose prior presentation has finished.
func drain_events(melee: ELMeleePlayback, presenting: Callable, dispatch: Callable) -> bool:
	var dispatched := false
	while not events.is_empty():
		if is_instance_valid(melee) and melee.blocks_cast_queue(): break
		var kind := String(events[0].get("kind", ""))
		if kind in SEQUENCED_KINDS and presenting.call(kind): break
		var next: Dictionary = events.pop_front()
		_dispatching = true
		dispatch.call(next)
		_dispatching = false
		dispatched = true
	return dispatched

## Rebuild the screen directly from the rules when idle or skipping.
func sync(duel: ELDuel, ability_marks: Callable) -> void:
	_stamps.clear()
	_waits.clear()
	snapshot = stamp(duel, ability_marks, false)

## The rules' values now, as a display stamp. `advance` hands out a new serial
## (a rules event); without it the stamp keeps the last one (a resync).
func stamp(duel: ELDuel, ability_marks: Callable, advance := true) -> Dictionary:
	if advance: serial += 1
	var heroes: Array = []
	for hero: Dictionary in duel.heroes:
		heroes.append({"health": hero.health, "maximum": hero.get("maximum", hero.health), "mana": hero.mana, "channels": hero.channels,
			"hand": hero.hand.duplicate(), "hand_view": ELDuel._hand_view(hero).duplicate(),
			"hand_slots": hero.hand_slots.duplicate(), "spell_uses": hero.spell_uses.duplicate(),
			"deck": hero.deck.duplicate(), "grave": hero.grave.duplicate(),
			"enchantments": hero.enchantments.duplicate(), "artifacts": hero.get("artifacts", []).duplicate(true)})
	var creatures := {}
	for id: int in duel.creatures:
		var c: Dictionary = duel.creatures[id]
		creatures[id] = {"power": int(c.power), "toughness": int(c.toughness), "damage": int(c.damage),
			"owner": c.owner, "plane": duel.in_plane(id), "resting": c.resting, "sick": c.sick,
			"enchantments": c.enchantments.duplicate(), "marks": ability_marks.call(id, c)}
	return {"serial": serial, "heroes": heroes, "creatures": creatures,
		"phase": duel.phase, "active": duel.active_side(), "turn": duel.turn_serial,
		"attacks": duel.attacks.duplicate(), "blocks": duel.blocks.duplicate()}

func wait_for(serial: int) -> void:
	_waits[serial] = int(_waits.get(serial, 0)) + 1

func resolve_wait(serial: int) -> void:
	if not _waits.has(serial): return
	_waits[serial] = int(_waits[serial]) - 1
	if int(_waits[serial]) <= 0: _waits.erase(serial)

## A waiting change's cue has come.
func release(value: Dictionary, watched_creatures: Callable) -> void:
	resolve_wait(int(value.serial))
	present(value, watched_creatures)

## Shows the newest presented stamp that no earlier waiting hit or cue holds back.
func present(value: Dictionary, watched_creatures: Callable) -> void:
	_stamps.append(value)
	var bar := -1
	for serial: int in _waits: bar = serial if bar < 0 else mini(bar, serial)
	var best := {}
	var kept: Array[Dictionary] = []
	for stamp: Dictionary in _stamps:
		if bar >= 0 and int(stamp.serial) > bar: kept.append(stamp)
		elif best.is_empty() or int(stamp.serial) > int(best.serial): best = stamp
	_stamps = kept
	if best.is_empty() or (not snapshot.is_empty() and int(best.serial) <= int(snapshot.serial)): return
	# Wounds and ether are read every frame. Lists are rebuilt only when their
	# contents change, and the phase caption follows the presented boundary.
	if snapshot.is_empty() or snapshot.phase != best.phase or snapshot.active != best.active:
		dirty = true
	else:
		for side in 2:
			for field: String in ["maximum", "hand", "hand_view", "hand_slots", "spell_uses", "deck", "grave", "enchantments", "artifacts"]:
				if snapshot.heroes[side][field] != best.heroes[side][field]: dirty = true
		for id: int in watched_creatures.call():
			if id >= 2 and snapshot.creatures.get(id, {}).get("enchantments", []) != best.creatures.get(id, {}).get("enchantments", []):
				dirty = true
	snapshot = best
