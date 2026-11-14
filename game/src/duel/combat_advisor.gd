class_name ELCombatAdvisor
extends RefCounted
## The battle adviser (a remake addition, shown in the battle panel's gap on
## wide screens): the chance to win as the computer opponent's judgement
## reads the position, and a verdict on the player's last move, in the manner
## of a chess site's game review.
##
## The chance is ELCombatSearch.win_chance of the position as it stands. It
## counts what both players can see (armies, health, ether channels, the
## number of cards in each hand, enchantments), never which cards a hand holds.
##
## A move is judged against the other moves the player had: every position in
## which a local player is to act is read on a worker thread
## (ELCombatSearch.study, the original lookahead with steady weights), which
## gives each first move a worth. When the player then casts, uses an ability
## or ends the phase, the worth of that move is compared with the best one's,
## both turned into chances to win; the difference in percentage points names
## the move (GRADES). Choosing attackers and blockers is judged when the phase
## is ended with them. A cast or ability the lookahead did not try is read on
## from the position it leaves. A move made before its position was read is
## judged when the reading arrives.
##
## Nothing here changes the duel: readings use copies, keep no plans for the
## computer opponent and do not advance the battle's random sequence.

## Verdicts, best first, and the most percentage points of winning chance a
## move of that name gives away. Set from computer-vs-computer duels of both
## games (about 500 positions with a choice in each): the runner-up move
## gives away under 0.3 points in half the positions; ending the phase when
## something better was to be done gives away 2 to 3 points in the mildest
## quarter of cases, 5 to 8 in the middle one, 12 to 14 at the third quartile
## and about 20 in the worst tenth.
enum Grade { BEST, EXCELLENT, GOOD, INACCURACY, MISTAKE, BLUNDER }
const LOSS := [0.3, 1.0, 2.5, 6.0, 14.0]
## Readings running at once; a position that comes while this many run is
## not read (its move goes unjudged).
const MAX_RUNNING := 3
const TABLES := ["CombatSpells", "CombatCreatures", "HeroTemplates", "Artefacts", "HeroesSpecs", "HeroesStats", "CombatManaIncome", "CombatDecks", "GlobalSpells"]

class Study:
	var task := -1
	var side := 0
	var position: ELDuel
	var result := {}
	## The player's move from this position, once made, and its number.
	var move := {}
	var serial := 0
	## The reading of the position after a move the first reading did not try.
	var follow: Study
	var dropped := false

## The chance (0..1) that `side` of the last observed position wins.
var chance := 0.5
## The last judged move: {"grade", "loss" (percentage points), "move" and
## "best" (what was played and what the reading liked best, see `_describe`)};
## empty before the first.
var last := {}
## A move is being judged.
var pending := false

var _studies: Array[Study] = []
var _current: Study
var _key := 0
var _mark: Array = []
var _duel := 0
var _events: Array = []
var _serial := 0
var _judged := 0

## Forgets the battle. Readings still running finish unseen.
func reset() -> void:
	for study: Study in _studies: study.dropped = true
	_current = null
	_key = 0
	_duel = 0
	_events.clear()
	chance = 0.5
	last = {}
	pending = false

## Waits for every reading (before the game exits: see ELPracticeAI.finish).
func finish() -> void:
	for study: Study in _studies:
		for each: Study in [study, study.follow]:
			if each != null and each.task >= 0:
				WorkerThreadPool.wait_for_task_completion(each.task)
				each.task = -1
	_studies.clear()
	_current = null

## A duel event as it happens: the casts and abilities name the player's move.
func note(data: Dictionary) -> void:
	if data.get("kind") in ["cast", "ability"] and not data.get("script", false): _events.append(data)

## The duel after any change. `human` is whether a local player is to act
## here by hand (their move from this position will be judged); `side` is the
## side whose chance is wanted.
func observe(duel: ELDuel, human: bool, side: int) -> void:
	if duel.get_instance_id() != _duel:
		reset()
		_duel = duel.get_instance_id()
	chance = ELCombatSearch.win_chance(ELCombatSearch.plain_context(duel, side), duel, side)
	var key := ELCombatSearch._position(duel)
	var mark := [duel.phase, duel.attacker, duel.turn_serial, duel.round_number]
	if key == _key:
		# The same position, now played by hand or no longer (auto combat).
		if _current == null and human: _current = _begin(duel)
		elif _current != null and not human:
			_current.dropped = true
			_current = null
		return
	if _current != null:
		var move := _move(_current.side, mark != _mark)
		if move.is_empty(): _current.dropped = true
		else:
			_serial += 1
			_current.move = move
			_current.serial = _serial
			pending = true
		_current = null
	_events.clear()
	_key = key
	_mark = mark
	if human: _current = _begin(duel)

## Collects finished readings and judges the moves they were waited for.
## True when `last` or `pending` changed.
func tick() -> bool:
	var before := [last.hash(), pending]
	for study: Study in _studies.duplicate():
		if not _done(study): continue
		if study.dropped:
			if study.follow == null or _done(study.follow): _studies.erase(study)
			continue
		if study.move.is_empty(): continue
		if study.follow != null:
			if not _done(study.follow): continue
			_judge(study, float(study.follow.result.get("value", _standing(study.follow.position, study.side))))
		else:
			var found := _worth(study)
			if not found.is_empty(): _judge(study, float(found.value))
			elif _read_on(study): continue
		_studies.erase(study)
	pending = _studies.any(func(study: Study) -> bool: return not study.dropped and not study.move.is_empty())
	return before != [last.hash(), pending]

func _done(study: Study) -> bool:
	if study.task < 0: return true
	if not WorkerThreadPool.is_task_completed(study.task): return false
	WorkerThreadPool.wait_for_task_completion(study.task)
	study.task = -1
	return true

func _begin(duel: ELDuel) -> Study:
	if duel.phase == ELDuel.Phase.FINISHED: return null
	var running := 0
	for study: Study in _studies:
		if study.task >= 0: running += 1
	if running >= MAX_RUNNING: return null
	# Rule tables load on first use; load them here so the worker only reads.
	for table: String in TABLES: duel.profile.table(table)
	return _read(duel.search_copy())

func _read(position: ELDuel) -> Study:
	var study := Study.new()
	study.side = position.active_side()
	study.position = position
	study.task = WorkerThreadPool.add_task(func() -> void: study.result = ELCombatSearch.study(position), false, "Battle adviser")
	_studies.append(study)
	return study

## What the player did from the current position: the first cast or ability
## of their side since, else ending the phase when the turn moved on. Choosing
## an attacker or a blocker is no move of its own.
func _move(side: int, moved_on: bool) -> Dictionary:
	for data: Dictionary in _events:
		if int(data.get("side", -1)) != side: continue
		if data.kind == "cast": return {"kind": "cast", "card": String(data.card), "target": int(data.get("target", -1)), "power": int(data.get("power", 0))}
		return {"kind": "ability", "id": int(data.get("source", -1)), "key": String(data.get("ability", "")), "target": int(data.get("target", -1))}
	return {"kind": "end_phase"} if moved_on else {}

func _same(move: Dictionary, command: Dictionary, hand: Array) -> bool:
	if command.get("kind") != move.kind: return false
	match String(move.kind):
		"end_phase": return true
		"cast":
			var index := int(command.get("index", -1))
			return index >= 0 and index < hand.size() and hand[index] == move.card and int(command.get("target", -1)) == int(move.target) and int(command.get("power", 0)) == int(move.power)
		"ability": return int(command.get("id", -1)) == int(move.id) and String(command.get("key", "")) == String(move.key) and int(command.get("target", -1)) == int(move.target)
	return false

## The reading's entry for the player's move (the best, when several fit).
func _worth(study: Study) -> Dictionary:
	var hand: Array = study.position.heroes[study.side].hand
	var found := {}
	for entry: Dictionary in study.result.get("moves", []):
		if not _same(study.move, entry.command, hand): continue
		if found.is_empty() or float(entry.value) > float(found.value): found = entry
	return found

## Reads the position a move the lookahead did not try leaves. False when the
## move cannot be replayed on the copy (it goes unjudged).
func _read_on(study: Study) -> bool:
	var after := study.position.search_copy()
	var ok := false
	match String(study.move.kind):
		"cast":
			var index: int = after.heroes[study.side].hand.find(study.move.card)
			ok = index >= 0 and after.cast(index, int(study.move.target), -1, int(study.move.power))
		"ability": ok = after.use_ability(int(study.move.id), String(study.move.key), int(study.move.target))
	if not ok: return false
	if after.phase == ELDuel.Phase.FINISHED or after.active_side() != study.side:
		_judge(study, _standing(after, study.side))
		return false
	study.follow = _read(after)
	_studies.erase(study.follow)
	return true

func _standing(position: ELDuel, side: int) -> float:
	var ctx := ELCombatSearch.plain_context(position, side)
	return ELCombatSearch.side_value(ctx, position, side) - ELCombatSearch.side_value(ctx, position, 1 - side)

func _judge(study: Study, worth: float) -> void:
	if study.serial <= _judged: return
	var best := {}
	for entry: Dictionary in study.result.get("moves", []):
		if best.is_empty() or float(entry.value) > float(best.value): best = entry
	if best.is_empty(): return
	_judged = study.serial
	var edition: String = study.position.profile.id
	var top := maxf(float(best.value), worth)
	var loss := (ELCombatSearch.worth_chance(edition, top) - ELCombatSearch.worth_chance(edition, worth)) * 100.0
	var hand: Array = study.position.heroes[study.side].hand
	var grade := Grade.BLUNDER
	if _same(study.move, best.command, hand): grade = Grade.BEST
	else:
		for i in LOSS.size():
			if loss <= LOSS[i]:
				grade = i as Grade
				break
	last = {"grade": grade, "loss": loss, "move": _describe(study, study.move), "best": _describe(study, best.command)}

## A command in words' worth of data: {"kind"} with the "card" cast (and
## "power"), or the "creature" (its card) or "hero" (its side) that uses the
## "ability", attacks or blocks.
func _describe(study: Study, command: Dictionary) -> Dictionary:
	var position := study.position
	var about := {"kind": String(command.get("kind", ""))}
	match about.kind:
		"cast":
			if command.has("card"): about.card = command.card
			else:
				var hand: Array = position.heroes[study.side].hand
				var index := int(command.get("index", -1))
				about.card = hand[index] if index >= 0 and index < hand.size() else ""
		"ability", "attack", "block":
			var id := int(command.get("id", -1))
			if position.creatures.has(id): about.creature = String(position.creatures[id].card)
			elif id in [0, 1]: about.hero = id
			if about.kind == "ability": about.ability = String(command.get("key", ""))
	return about
