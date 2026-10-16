class_name ELCombatTutorial
extends RefCounted
## Second-game combat tutorial (Tutorial screen → Combat). The original plays
## the replay Tutorial\Combat\combat_tutorial.rpl in tutorial mode: the battle
## is set up from the replay and seeded with its seed; the computer side replays
## its recorded commands, and the local player must perform exactly the next
## recorded command; any other action is ignored. Each command's note is the
## tutorial text shown while that command is awaited ("#d" preselects the
## spell to cast).
##
## The remake keeps the local player on side 0, so a replay recorded with the
## local player on side 1 is mirrored: remake side = original side XOR `flip`.
## Hero ids follow their side; creature, card and enchantment ids are the
## battle's own serials and match unchanged while the battle stays identical.
## If the rules ever diverge from the recording (a recorded action the engine
## refuses or that cannot be mapped), playback stops at that command and
## `error` names it; nothing is substituted.

signal note_changed
signal diverged(message: String)

const PATH := "Tutorial/Combat/combat_tutorial.rpl"
const COLOURS := ["Red", "Green", "Blue", "Black", "White"]
## The original renames the recorded heroes.
const HERO_TEXTS := {"Vitals": "T_COMBAT_TUTORIAL_VITALS_HERO_NAME", "Chaots": "T_COMBAT_TUTORIAL_CHAOTS_HERO_NAME"}
const QUIT_TEXT := "T_COMBAT_TUTORIAL_QUIT"

var profile: ELProfile
var replay: ELDuelReplay
var duel: ELDuel
var flip := 0
## Index of the next recorded command.
var index := 0
var error := ""
## Commands accepted so far, in order: {index, kind, side, by}.
var accepted: Array[Dictionary] = []
## What a divergence message calls this playback.
var label := "Combat tutorial"
## Per remake side, the enchantment IDs of granted hero abilities in grant
## order. The original numbers each hero's abilities by a counter that starts
## at 0 and counts every grant (hero), so a recorded
## UsePlayerAbility id is a position in this list.
var granted: Array = [[], []]

func load_from(data: ELProfile, path := PATH) -> bool:
	var file := data.file(path)
	if file.is_empty():
		profile = data
		return _fail("The combat tutorial replay is missing: " + path)
	return load_file(data, file)

## Any original .rpl file (the tutorial, or a player's own Duel replay).
func load_file(data: ELProfile, file: String) -> bool:
	profile = data
	error = ""
	replay = ELDuelReplay.new()
	if not replay.decode(FileAccess.get_file_as_bytes(file)): return _fail(replay.error)
	if replay.local_side not in [0, 1]: return _fail("Invalid local side in the replay.")
	flip = replay.local_side
	return true

## Remake side of an original side or hero id.
func side_of(original: int) -> int:
	return original ^ flip

## An original entity id (heroes 0/1, creatures from 2) in remake terms.
func entity_of(original: int) -> int:
	return original ^ flip if original in [0, 1] else original

func hero_title(original_side: int) -> String:
	var recorded := String(replay.heroes[original_side].name)
	var key := String(HERO_TEXTS.get(recorded, ""))
	return profile.text(key) if not key.is_empty() and not profile.text(key).is_empty() else recorded

## Start options for ELDuel.start: the recorded heroes (template, colour,
## level, specialisation, skills, artifacts, deck), the arena, Providence
## charges (every EL2 battle refills them), the opening order and the
## first side from the seed (seed % 2 in a duel).
func start_options() -> Dictionary:
	var players: Array = []
	for side in 2:
		var hero: Dictionary = replay.heroes[side ^ flip]
		var artifacts: Array = []
		for item: Variant in hero.artifacts: artifacts.append({"name": str(item)})
		# The recorded bag, kept for the replay player's Inventory screen.
		var reserve := {}
		for entry: Variant in hero.get("bag", []):
			if entry is Array and entry.size() == 2 and int(entry[1]) > 0: reserve[str(entry[0])] = int(reserve.get(str(entry[0]), 0)) + int(entry[1])
		players.append({"faction": COLOURS[clampi(int(hero.colour), 0, 4)], "hero": hero.template, "cards": hero.deck.duplicate(),
			"level": int(hero.level), "skills": hero.skills.duplicate(), "specialization": hero.specialization,
			"artifacts": artifacts, "title": hero_title(side ^ flip), "reserve": reserve})
	return {"players": players, "arena": replay.arena, "adventure": true, "first_side": side_of(replay.seed_value & 1),
		"opening_interleave": side_of(0), "card_ids": true, "combat_tutorial": true}

func begin(target: ELDuel) -> bool:
	duel = target
	index = 0
	accepted.clear()
	if not duel.start(profile, replay.seed_value, start_options()): return _fail(duel.error)
	duel.gate = self
	granted = [[], []]
	_note_grants()
	note_changed.emit()
	return true

## Records hero-ability enchantments that appeared since the last command.
func _note_grants() -> void:
	for side in 2:
		var fresh: Array[int] = []
		for e: Dictionary in duel.heroes[side].enchantments:
			if ELCatalog.HERO_ABILITIES.has(e.card) and not (granted[side] as Array).has(int(e.id)): fresh.append(int(e.id))
		fresh.sort()
		(granted[side] as Array).append_array(fresh)

## Remake arguments for a recorded UsePlayerAbility: {key, target, second},
## or {} when the id or target list does not fit. Abilities declare their
## kinds as spells do: one entity, a first then second entity (Combine,
## Burnout, Recycle) or an own-graveyard index (Rebirth, Second Birth, Repair).
func _hero_ability_arguments(side: int, recorded_id: int, targets: Array) -> Dictionary:
	_note_grants()
	var list: Array = granted[side]
	if recorded_id < 0 or recorded_id >= list.size(): return {}
	var definition: Dictionary = {}
	for ability: Dictionary in duel.abilities(side):
		if int(ability.get("enchantment", -1)) == int(list[recorded_id]): definition = ability
	if definition.is_empty(): return {}
	var target_kind := String(definition.get("target", "none"))
	if target_kind == "grave":
		return {"key": definition.key, "target": side, "second": int(targets[0])} if targets.size() == 1 else {}
	if definition.has("second") or String(definition.effect) == "combine":
		return {"key": definition.key, "target": entity_of(int(targets[0])), "second": entity_of(int(targets[1]))} if targets.size() == 2 else {}
	if target_kind == "none":
		return {"key": definition.key, "target": -1, "second": -1} if targets.is_empty() else {}
	return {"key": definition.key, "target": entity_of(int(targets[0])), "second": -1} if targets.size() == 1 else {}

func current() -> Dictionary:
	return replay.commands[index] if replay != null and index < replay.commands.size() else {}

func done() -> bool:
	return replay != null and index >= replay.commands.size()

## Commands the player gives through the battle controls.
const PLAYER_INPUT := ["next_phase", "cast", "artifact", "hero_ability", "ability", "attack", "block", "retreat", "surrender"]

## True while the next command belongs to the computer side or is not the
## player's input.
func opponent_due() -> bool:
	var c := current()
	if c.is_empty() or not error.is_empty(): return false
	# Script casts, Test, StartGame and the cheats are never the player's input.
	return side_of(int(c.side)) != 0 or not String(c.kind) in PLAYER_INPUT

## The tutorial text for the awaited command ("" for none or a blank note).
func note_text() -> String:
	var c := current()
	if c.is_empty() or c.note == null: return ""
	var text := String(c.note.text)
	if text.length() >= 2 and text[0] == "#": text = text.substr(2)
	var shown := profile.text(text)
	return (shown if not shown.is_empty() else text).strip_edges()

## The hand slot named by "#d" (0..5, counted from the newest card), or -1.
func note_slot() -> int:
	var c := current()
	if c.is_empty() or c.note == null: return -1
	var text := String(c.note.text)
	if text.length() < 2 or text[0] != "#": return -1
	var digit := text.unicode_at(1) - 48
	return digit if digit >= 0 and digit < 6 else -1

## Hand index of the spell the note preselects, or -1.
func preselected_index() -> int:
	var c := current()
	if c.is_empty() or c.kind != "cast" or note_slot() < 0: return -1
	return (duel.heroes[side_of(int(c.side))].hand_ids as Array).find(int(c.id))

## Runs the next computer command through the rules. Returns false when none
## is due or the rules refused it (then `error` holds the divergence).
func step_opponent() -> bool:
	if not opponent_due(): return false
	return run_current()

## Executes the awaited command through the duel's public actions (also used
## by checks to stand in for the player's input).
func run_current() -> bool:
	var c := current()
	if c.is_empty() or not error.is_empty(): return false
	var at := index
	var ok := false
	var side := side_of(int(c.side))
	match String(c.kind):
		"next_phase": ok = duel.end_phase()
		"attack", "retreat":
			if duel.attacks.has(int(c.id)) == (c.kind == "attack"):
				# The original's attack handler leaves a creature that
				# is already assigned untouched; the recording keeps such repeats.
				_advance(side)
				return true
			ok = duel.toggle_attack(int(c.id))
		"block": ok = duel.assign_block(int(c.id), int(c.target))
		"cast":
			var hand := (duel.heroes[side].hand_ids as Array).find(int(c.id))
			if hand < 0: return _diverge(at, "card %d is not in the hand" % int(c.id))
			var call := _cast_arguments(duel.heroes[side].hand[hand], c.targets, side)
			if call.is_empty(): return _diverge(at, "unmapped cast targets %s" % str(c.targets))
			ok = duel.cast(hand, call.target, call.grave, call.power)
		"artifact":
			var targets: Array = c.targets
			if targets.size() != 1: return _diverge(at, "unmapped artifact targets %s" % str(targets))
			var holder := duel.find_enchantment(int(targets[0]))
			ok = duel.use_artifact(side, int(c.id), holder, int(targets[0]))
		"ability":
			var listed := duel.abilities(int(c.id)) if duel.creatures.has(int(c.id)) else []
			if int(c.ability) < 0 or int(c.ability) >= listed.size(): return _diverge(at, "creature %d has no ability %d" % [int(c.id), int(c.ability)])
			var targets: Array = c.targets
			ok = duel.use_ability(int(c.id), String(listed[int(c.ability)].key), entity_of(int(targets[0])) if targets.size() == 1 else -1)
		"hero_ability":
			var call := _hero_ability_arguments(side, int(c.id), c.targets)
			if call.is_empty(): return _diverge(at, "unmapped hero ability %d with targets %s" % [int(c.id), str(c.targets)])
			ok = duel.use_ability(side, String(call.key), int(call.target), int(call.second))
		"cheat_cast", "cheat_cast_effects":
			# ExCastSpell and ExCastSpellWithEffects: the
			# spell is created from its code, checked against the same per-kind
			# target list and resolved without a hand card. The
			# unrecorded field is only where a refused check writes its message.
			var card := ELDuelReplay.fourcc(int(c.id))
			if not profile.table("CombatSpells").has(card): return _diverge(at, "unknown spell " + card)
			var call := _cast_arguments(card, c.targets, side)
			if call.is_empty(): return _diverge(at, "unmapped cast targets %s" % str(c.targets))
			var args: Array = []
			if duel.variable_power(card):
				if duel.target_kind(card) != "none": args.append(int(call.target))
				args.append(int(call.power))
			elif int(call.target) >= 0 or int(call.grave) >= 0:
				args = [int(call.target), int(call.grave)]
			ok = duel.cast_free(side, card, args, c.kind == "cheat_cast_effects")
			if ok: _advance(side)
		"test":
			# Test only sends a debug event to the presentation.
			_advance(side)
			return true
		"cheat_add_spell":
			# the card joins the hand.
			var card := ELDuelReplay.fourcc(int(c.value))
			if not profile.table("CombatSpells").has(card): return _diverge(at, "unknown spell " + card)
			duel._give_card(side, card)
			_advance(side)
			duel.changed.emit()
			return true
		"cheat_health", "cheat_mana", "cheat_channels":
			#  set the value outright; ether and
			# channels each keep the other.
			match String(c.kind):
				"cheat_health": duel.heroes[side].health = int(c.value)
				"cheat_mana": duel.heroes[side].mana = int(c.value)
				"cheat_channels": duel.heroes[side].channels = int(c.value)
			_advance(side)
			duel._check_winner()
			duel.changed.emit()
			return true
		"cheat_win":
			#  declares the recorded side the winner.
			_advance(side)
			if duel.phase != ELDuel.Phase.FINISHED:
				duel.winner = side
				duel.phase = ELDuel.Phase.FINISHED
				duel._emit({"kind": "victory", "side": side})
			duel.changed.emit()
			return true
		"cheat_disenchant":
			# every enchantment on the creature or hero is removed.
			var holder := entity_of(int(c.target))
			if duel.entity(holder).is_empty(): return _diverge(at, "no creature or hero %d" % int(c.target))
			for e: Dictionary in (duel.entity(holder).enchantments as Array).duplicate():
				duel._remove_enchantment(holder, int(e.id))
			_advance(side)
			duel.changed.emit()
			return true
		"start_game":
			# StartGame runs the opening draws, which the remake's
			# battle start has already made.
			_advance(side)
			return true
		"surrender":
			# Surrender ends the battle against the recorded side.
			_advance(side)
			duel.heroes[side].health = 0
			duel._check_winner()
			return error.is_empty()
		_:
			return _diverge(at, "unsupported command " + String(c.kind))
	if not ok and error.is_empty(): return _diverge(at, "the rules refused it: " + duel.error)
	return ok and error.is_empty()

## Remake cast arguments for a recorded target list. The original stores one
## value per target kind the spell declares, in declaration order: X (kind 5),
## a hero or creature entity (kinds 0-4), an enchantment ID (10), the caster's
## own graveyard index (8) or a hero side then that graveyard's index (7, two
## values; indexes count from the oldest entry, as the remake's grave does).
func _cast_arguments(card: String, targets: Array, side: int) -> Dictionary:
	var kind := duel.target_kind(card)
	if duel.variable_power(card):
		if kind == "none":
			return {"target": -1, "grave": -1, "power": int(targets[0])} if targets.size() == 1 else {}
		if targets.size() != 2: return {}
		# Only Comet's class declares X before its target.
		var x_first := card == "COMT"
		var entity := int(targets[1] if x_first else targets[0])
		return {"target": entity_of(entity), "grave": -1, "power": int(targets[0] if x_first else targets[1])}
	if targets.is_empty(): return {"target": -1, "grave": -1, "power": 0}
	match kind:
		"enchantment":
			if targets.size() != 1: return {}
			var holder := duel.find_enchantment(int(targets[0]))
			return {"target": holder, "grave": int(targets[0]), "power": 0} if holder >= 0 else {}
		"grave":
			if ELCatalog.rule(duel.profile, card).get("effect") == "repair":
				return {"target": side, "grave": int(targets[0]), "power": 0} if targets.size() == 1 else {}
			return {"target": side_of(int(targets[0])), "grave": int(targets[1]), "power": 0} if targets.size() == 2 else {}
		"none": return {}
	if targets.size() == 1: return {"target": entity_of(int(targets[0])), "grave": -1, "power": 0}
	return {}

## ELDuel gate: only the awaited command may run. A cast of the same spell
## from the same charge group as the awaited card is the same click in the
## remake's grouped hand, so it is redirected to the awaited card.
func gate_check(target: ELDuel, action: Dictionary) -> bool:
	if target != duel or not error.is_empty(): return false
	var c := current()
	if c.is_empty(): return false
	if int(action.get("side", -1)) != side_of(int(c.side)): return false
	var kind := String(action.kind)
	if kind == "ability" and String(action.get("ability", "")).begins_with("artifact:"):
		action = {"kind": "artifact", "side": action.side, "index": int(String(action.ability).get_slice(":", 1)), "target": action.target, "choice": action.enchantment}
		kind = "artifact"
	match String(c.kind):
		"next_phase": return kind == "end_phase"
		"attack", "retreat":
			if int(action.id) != int(c.id): return false
			if kind != c.kind and duel.attacks.has(int(c.id)) == (c.kind == "attack"):
				# Clicking a creature already in the recorded state: the original's
				# separate Attack/Retreat commands leave it unchanged.
				_advance(int(action.side))
				return false
			return kind == c.kind
		"block": return kind == "block" and int(action.id) == int(c.id) and int(action.target) == int(c.target)
		"cast":
			if kind != "cast": return false
			var side := side_of(int(c.side))
			var hero: Dictionary = duel.heroes[side]
			var wanted := (hero.hand_ids as Array).find(int(c.id))
			var chosen := int(action.hand_index)
			if wanted < 0 or chosen < 0 or chosen >= hero.hand.size(): return false
			if chosen != wanted:
				if hero.hand[chosen] != hero.hand[wanted] or duel.hand_uses(side, chosen) != duel.hand_uses(side, wanted): return false
				action.hand_index = wanted
			var call := _cast_arguments(hero.hand[wanted], c.targets, side)
			return not call.is_empty() and int(action.target) == int(call.target) and int(action.grave) == int(call.grave) and int(action.power) == int(call.power)
		"artifact":
			var targets: Array = c.targets
			return kind == "artifact" and int(action.index) == int(c.id) and targets.size() == 1 and int(action.choice) == int(targets[0])
		"hero_ability":
			if kind != "ability" or int(action.id) != side_of(int(c.side)) or String(action.ability).begins_with("artifact:"): return false
			var call := _hero_ability_arguments(side_of(int(c.side)), int(c.id), c.targets)
			return not call.is_empty() and String(action.ability) == String(call.key) and int(action.target) == int(call.target) and int(action.enchantment) == int(call.second)
		"ability":
			var listed := duel.abilities(int(c.id)) if duel.creatures.has(int(c.id)) else []
			var targets: Array = c.targets
			if kind != "ability" or int(action.id) != int(c.id) or int(c.ability) >= listed.size(): return false
			return String(action.ability) == String(listed[int(c.ability)].key) and int(action.target) == (entity_of(int(targets[0])) if targets.size() == 1 else -1)
	return false

func gate_done(target: ELDuel, action: Dictionary, ok: bool) -> void:
	if target != duel: return
	if not ok:
		# A vetted, recorded action the rules refuse: the remake no longer matches.
		_diverge(index, "the rules refused it: " + duel.error)
		return
	_advance(int(action.side))

func _advance(side: int) -> void:
	_note_grants()
	accepted.append({"index": index, "kind": String(current().kind), "side": side})
	index += 1
	note_changed.emit()

func _diverge(at: int, reason: String) -> bool:
	if error.is_empty():
		var c: Dictionary = replay.commands[at] if at < replay.commands.size() else {}
		error = label + " diverged at command %d (%s): %s" % [at, String(c.get("kind", "?")), reason]
		diverged.emit(error)
	return false

func _fail(message: String) -> bool:
	error = message
	return false
