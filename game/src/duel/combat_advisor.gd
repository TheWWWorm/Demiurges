class_name ELCombatAdvisor
extends RefCounted
## The battle adviser (a remake addition, shown in the battle panel's gap on
## wide screens): an estimate of the position as the computer opponent's
## judgement reads it, and a verdict on the player's last move, in the manner
## of a chess site's game review.
##
## The estimate is ELCombatSearch.win_chance of the position as it stands, a
## curve fitted to computer-vs-computer duels: a rough guide to who stands
## better, not a measured chance for the player. It counts what both players
## can see (armies, health, ether channels, the number of cards in each hand,
## enchantments), never which cards a hand holds.
##
## A move is judged against the other moves the player had: every position in
## which a local player is to act is read on a worker thread
## (ELCombatSearch.study, the original lookahead with steady weights), which
## gives each first move a worth. The move itself is the command the rules
## took, whole (ELDuel.accepted: every argument, and the position it was made
## from), and it is looked up in the reading by all of its arguments; a move
## the reading did not try, or tried more than once with different worths, is
## played on a copy with the same arguments and read on from the position it
## leaves. The worth of the move is compared with the best one's, both put on
## the estimate's curve; the difference in points names the move (GRADES). A
## move made before its position was read is judged when the reading arrives.
##
## Choosing attackers and blockers is one decision with the end of the phase:
## while the player sends or recalls creatures or assigns blockers, the
## reading of the position before the first choice is kept, and when the phase
## is ended the whole assignment is played on a copy of that position, read,
## and its end of the phase is judged against the moves of the position before
## the choices. When a spell or an ability is used while an assignment is half
## made, that cast (with the choices before it) is the move judged against the
## position before the choices; the position the spell leaves starts a new
## decision, with the creatures already chosen as its starting point.
##
## Nothing here changes the duel: readings use copies, keep no plans for the
## computer opponent and do not advance the battle's random sequence; their
## specialisation rolls keep each trial's probability (ELDuel.fair_specs).

## Verdicts, best first, and the most points of the estimate a move of that
## name gives away. Set from computer-vs-computer duels of both games (about
## 500 positions with a choice in each): the runner-up move gives away under
## 0.3 points in half the positions; ending the phase when something better
## was to be done gives away 2 to 3 points in the mildest quarter of cases, 5
## to 8 in the middle one, 12 to 14 at the third quartile and about 20 in the
## worst tenth.
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
	## ELCombatSearch._position of the position read.
	var key := 0
	var result := {}
	## The player's move from this position, once made ({"path": the commands
	## the rules took, choices of attackers or blockers first}), and its number.
	var move := {}
	var serial := 0
	## The reading of a position the move leaves on the way, or after a move
	## the first reading did not try.
	var follow: Study
	var dropped := false
	## Where the judgement stands: the position, and its reading, that the
	## commands still to look up (`rest`) are made from.
	var started := false
	var at_position: ELDuel
	var at_key := 0
	var at_result := {}
	var rest: Array = []

## The estimate (0..1) for `side` of the last observed position.
var chance := 0.5
## The last judged move: {"grade", "loss" (points of the estimate), "move" and
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
var _serial := 0
var _judged := 0
## The decision under way: the side to act and the last command the duel had
## taken (ELDuel.accepted_serial) when it began.
var _side := -1
var _from := 0

## Forgets the battle. Readings still running finish unseen.
func reset() -> void:
	for study: Study in _studies: study.dropped = true
	_current = null
	_key = 0
	_mark = []
	_duel = 0
	_side = -1
	_from = 0
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

## The duel after any change. `human` is whether a local player is to act
## here by hand (their move from this position will be judged); `side` is the
## side whose estimate is wanted.
func observe(duel: ELDuel, human: bool, side: int) -> void:
	if duel.get_instance_id() != _duel:
		reset()
		_duel = duel.get_instance_id()
		_from = duel.accepted_serial
		_side = duel.active_side()
	chance = ELCombatSearch.win_chance(ELCombatSearch.plain_context(duel, side), duel, side)
	var key := ELCombatSearch._position(duel)
	var mark := [duel.phase, duel.attacker, duel.turn_serial, duel.round_number]
	var own := _commands(duel)
	var decisive := -1
	for i in own.size():
		if String(own[i].kind) in ["cast", "ability", "end_phase"]:
			decisive = i
			break
	# Attackers or blockers being chosen: the decision is still the one begun
	# before the first choice.
	var choosing := decisive < 0 and not own.is_empty() and mark == _mark
	if key == _key or choosing:
		_key = key
		# The same decision, now played by hand or no longer (auto combat). A
		# decision first seen with its choices half made is not judged: the
		# position before them was not read.
		if _current == null and human and own.is_empty(): _current = _begin(duel)
		elif _current != null and not human:
			_current.dropped = true
			_current = null
		return
	if _current != null:
		var path: Array = []
		if decisive >= 0: path = own.slice(0, decisive + 1)
		elif mark != _mark:
			# The turn moved on without an end of the phase from the player.
			path = own.duplicate()
			path.append({"kind": "end_phase"})
		if path.is_empty(): _current.dropped = true
		else:
			_serial += 1
			_current.move = {"path": path}
			_current.serial = _serial
			pending = true
		_current = null
	_key = key
	_mark = mark
	_from = duel.accepted_serial
	_side = duel.active_side()
	if human: _current = _begin(duel)

## The commands the side of the decision under way has had taken since it
## began.
func _commands(duel: ELDuel) -> Array:
	var result: Array = []
	for command: Dictionary in duel.accepted:
		if int(command.serial) > _from and int(command.side) == _side: result.append(command)
	return result

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
			study.at_position = study.follow.position
			study.at_key = study.follow.key
			study.at_result = study.follow.result
			study.follow = null
		if _advance(study): _studies.erase(study)
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
	var position := duel.search_copy()
	position.fair_specs = true
	return _read(position)

func _read(position: ELDuel) -> Study:
	var study := Study.new()
	study.side = position.active_side()
	study.position = position
	study.key = ELCombatSearch._position(position)
	study.task = WorkerThreadPool.add_task(func() -> void: study.result = ELCombatSearch.study(position), false, "Battle adviser")
	_studies.append(study)
	return study

## Takes the judgement of a made move as far as the readings in hand allow.
## True when it is over (judged, or left unjudged: a command the copy refuses,
## or one not made from the position it is looked up in); false while a
## reading it needs runs (`follow`).
func _advance(study: Study) -> bool:
	if not study.started:
		study.started = true
		study.at_position = study.position
		study.at_key = study.key
		study.at_result = study.result
		study.rest = (study.move.path as Array).duplicate()
	while true:
		if study.rest.is_empty():
			# The reading of the position the move left is its worth.
			_judge(study, float(study.at_result.get("value", _standing(study.at_position, study.side))))
			return true
		if study.rest.size() > 1:
			# The attackers or blockers chosen before the move, played out on a
			# copy; the move is then looked up from the position they leave.
			var chosen := study.at_position.search_copy()
			for command: Dictionary in study.rest.slice(0, study.rest.size() - 1):
				if not ELCombatSearch.apply(chosen, command): return true
			study.rest = [study.rest.back()]
			if ELCombatSearch._position(chosen) == study.at_key: continue
			_follow(study, chosen)
			return false
		var move: Dictionary = study.rest[0]
		if move.has("before") and int(move.before) != study.at_key: return true
		var found := _exact(study.at_position, study.side, study.at_result, move)
		if not found.is_empty():
			_judge(study, float(found.value))
			return true
		var after := study.at_position.search_copy()
		if not ELCombatSearch.apply(after, move): return true
		study.rest = []
		if after.phase == ELDuel.Phase.FINISHED or after.active_side() != study.side:
			_judge(study, _standing(after, study.side))
			return true
		_follow(study, after)
		return false
	return true

func _follow(study: Study, position: ELDuel) -> void:
	study.follow = _read(position)
	_studies.erase(study.follow)

## The command as the rules take it, in full: a spell's hand place, card,
## target (as the spell picks it itself, when it does), graveyard or
## enchantment choice and power; an ability's user, key, target, choice and
## amount.
static func _canonical(position: ELDuel, side: int, command: Dictionary) -> Array:
	var kind := String(command.get("kind", ""))
	match kind:
		"cast":
			var index := int(command.get("index", -1))
			var hand: Array = position.heroes[side].hand
			var card := String(hand[index]) if index >= 0 and index < hand.size() else String(command.get("card", ""))
			var target := int(command.get("target", -1))
			var rule := ELCatalog.rule(position.profile, card)
			if rule.get("self", false): target = side
			elif rule.get("opponent", false): target = 1 - side
			return [kind, index, card, target, int(command.get("grave", -1)), int(command.get("power", 0))]
		"ability":
			return [kind, int(command.get("id", -1)), String(command.get("key", "")), int(command.get("target", -1)), int(command.get("choice", -1)), int(command.get("amount", -1))]
		"attack": return [kind, int(command.get("id", -1))]
		"block": return [kind, int(command.get("id", -1)), int(command.get("target", -1))]
	return [kind]

## The reading's entry for exactly this command; {} when it has none, or has
## entries for it that disagree (the move is then played on a copy instead).
static func _exact(position: ELDuel, side: int, result: Dictionary, command: Dictionary) -> Dictionary:
	var wanted := _canonical(position, side, command)
	var found := {}
	for entry: Dictionary in result.get("moves", []):
		if _canonical(position, side, entry.command) != wanted: continue
		if not found.is_empty() and float(entry.value) != float(found.value): return {}
		found = entry
	return found

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
	var path: Array = study.move.path
	var grade := Grade.BLUNDER
	if path.size() == 1 and _canonical(study.position, study.side, path[0]) == _canonical(study.position, study.side, best.command): grade = Grade.BEST
	else:
		for i in LOSS.size():
			if loss <= LOSS[i]:
				grade = i as Grade
				break
	# A phase ended after choosing attackers or blockers is named by the last
	# choice.
	var shown: Dictionary = path.back()
	if String(shown.kind) == "end_phase" and path.size() > 1: shown = path[path.size() - 2]
	last = {"grade": grade, "loss": loss, "move": _describe(study, shown), "best": _describe(study, best.command)}

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
