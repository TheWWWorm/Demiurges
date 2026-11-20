class_name ELPuzzles
extends RefCounted
## Authored tactical studies and legacy mined battle puzzles. A study states
## its goal and fixed-supply rules explicitly. The ordinary battle engine
## still resolves every spell, ability and combat exchange.

const FOLDER := "res://puzzles/"
## Which puzzles the player has solved: {edition: {id: turns taken}}.
const SOLVED := "user://puzzles.json"
## Separate metadata keeps the legacy completion file compatible with older builds.
const MASTERY := "user://puzzle_mastery.json"

## Off for checks that play the puzzles through: what they solve is not
## written to the player's list.
static var remember := true
## Where the lists are read from: FOLDER, or another folder for checks
## (tools/puzzles_check.gd --folder=, e.g. an earlier release's puzzles).
static var folder := FOLDER
static var _lists: Dictionary = {}
static var _solved: Dictionary = {}
static var _solved_read := false
static var _mastery: Dictionary = {}
static var _mastery_read := false

## The puzzles of one game, easiest first. Version 1 entries remain valid.
static func list(edition: String) -> Array:
	if _lists.has(edition): return _lists[edition]
	var out: Array = []
	var path := folder.path_join(edition + ".json")
	if FileAccess.file_exists(path):
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if document is Dictionary and document.get("format") == "etherlords-puzzles" and document.get("puzzles") is Array:
			var ids := {}
			for entry: Variant in document.puzzles:
				if valid_entry(entry, edition) and not ids.has(entry.id):
					out.append(entry)
					ids[entry.id] = true
	_lists[edition] = out
	return out

static func valid_entry(entry: Variant, edition: String) -> bool:
	if entry is not Dictionary or entry.get("id") is not String or String(entry.id).is_empty(): return false
	if entry.get("state") is not Dictionary or entry.state.get("profile") != edition: return false
	if not _whole(entry.get("turns"), 1, 12): return false
	if entry.has("level") and not _whole(entry.level, 1, 5): return false
	var goal: Variant = entry.get("objective", {"type": "win"})
	if goal is not Dictionary or goal.get("type", "win") not in ["win", "clear", "survive", "control"]: return false
	if goal.get("type") == "survive" and not _whole(goal.get("enemy_turns"), 1, 12): return false
	if goal.get("type") == "control":
		if goal.has("enemy_turns") and not _whole(goal.enemy_turns, 1, 12): return false
		if goal.get("targets") is not Array or goal.targets.is_empty(): return false
		var seen := {}
		for id: Variant in goal.targets:
			if not _whole(id, 2, 1000000) or seen.has(int(id)): return false
			seen[int(id)] = true
			var creature: Variant = entry.state.get("creatures", {}).get(str(int(id)), {})
			if creature is not Dictionary or int(creature.get("owner", -1)) != 1: return false
	if goal.has("min_health") and not _whole(goal.min_health, 1, 1000000): return false
	if goal.has("finish_health") and not _whole(goal.finish_health, 1, 1000000): return false
	if goal.has("finish_mana") and not _whole(goal.finish_mana, 0, 1000000): return false
	if goal.has("min_allies") and not _whole(goal.min_allies, 1, 10): return false
	if goal.has("protect"):
		if goal.protect is not Array: return false
		for id: Variant in goal.protect:
			if not _whole(id, 2, 1000000): return false
			var creature: Variant = entry.state.get("creatures", {}).get(str(int(id)), {})
			if creature is not Dictionary or int(creature.get("owner", -1)) != 0: return false
	for key: String in ["hints", "hints_ru"]:
		if entry.has(key) and (entry[key] is not Array or entry[key].any(func(value: Variant) -> bool: return value is not String)): return false
	for key: String in ["hero_names", "hero_names_ru"]:
		if entry.has(key) and (entry[key] is not Array or entry[key].size() != 2 or entry[key].any(func(value: Variant) -> bool: return value is not String or String(value).strip_edges().is_empty())): return false
	return true

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

static func available(edition: String) -> bool:
	return not list(edition).is_empty()

## Presentation names are separate from the restored battle snapshot. Levels
## always come from its heroes, never from the puzzle's difficulty tier.
static func combatants(entry: Dictionary, profile: ELProfile, language := "") -> Array:
	var result: Array = []
	var locale := ELRemakeText.language(profile) if language.is_empty() else language
	var names: Variant = entry.get("hero_names_ru", entry.get("hero_names", [])) if locale == "ru" else entry.get("hero_names", [])
	var heroes: Variant = entry.get("state", {}).get("heroes", [])
	for side in 2:
		var hero: Dictionary = heroes[side] if heroes is Array and heroes.size() > side and heroes[side] is Dictionary else {}
		var name := ""
		if names is Array and names.size() > side and names[side] is String: name = String(names[side]).strip_edges()
		if name.is_empty(): name = str(hero.get("title", "")).strip_edges()
		var template := str(hero.get("template", ""))
		if name.is_empty() and profile != null:
			var key := str(profile.table("HeroTemplates").get(template, {}).get("ELKName", ""))
			if not key.is_empty():
				var translated := profile.text(key)
				if translated != key: name = translated
		if name.is_empty(): name = template
		if name.is_empty(): name = ("Ваш герой" if side == 0 else "Противник") if locale == "ru" else ("Your hero" if side == 0 else "Opponent")
		result.append({"name": name, "level": int(hero.get("level", 1))})
	return result

static func _read_solved() -> void:
	if _solved_read: return
	_solved_read = true
	if not FileAccess.file_exists(SOLVED): return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOLVED))
	if document is Dictionary:
		for edition: Variant in document:
			if document[edition] is Dictionary: _solved[str(edition)] = document[edition]

## Own turns the player took to solve `id`, or 0 while it is unsolved.
static func solved_in(edition: String, id: String) -> int:
	_read_solved()
	return int(_solved.get(edition, {}).get(id, 0))

static func solved_count(edition: String) -> int:
	var count := 0
	for entry: Dictionary in list(edition):
		if solved_in(edition, String(entry.id)) > 0: count += 1
	return count

## Remembers a solved puzzle (the fewest turns it was solved in).
static func mark(edition: String, id: String, turns: int, hints_used := -1) -> void:
	_read_solved()
	var before := solved_in(edition, id)
	if before <= 0 or before > turns:
		if not _solved.has(edition): _solved[edition] = {}
		_solved[edition][id] = maxi(turns, 1)
		if remember:
			ELSafeFile.write_text(SOLVED, JSON.stringify(_solved, "\t"))
	# A slower unassisted replay can improve mastery independently of best turns.
	# Old callers supply no hint information and cannot manufacture a badge.
	if hints_used < 0: return
	_read_mastery()
	var previous := best_hints(edition, id)
	if previous >= 0 and previous <= hints_used: return
	if not _mastery.has(edition): _mastery[edition] = {}
	_mastery[edition][id] = hints_used
	if remember:
		ELSafeFile.write_text(MASTERY, JSON.stringify(_mastery, "\t"))

static func _read_mastery() -> void:
	if _mastery_read: return
	_mastery_read = true
	if not FileAccess.file_exists(MASTERY): return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(MASTERY))
	if document is not Dictionary: return
	for edition: Variant in document:
		if document[edition] is not Dictionary: continue
		var records := {}
		for id: Variant in document[edition]:
			var value: Variant = document[edition][id]
			if _whole(value, 0, 1000): records[str(id)] = int(value)
		_mastery[str(edition)] = records

## Fewest hint stages disclosed in a completed attempt, or -1 if unknown.
static func best_hints(edition: String, id: String) -> int:
	_read_mastery()
	return int(_mastery.get(edition, {}).get(id, -1))

## A successful attempt without revealing hints. Practice replays can earn it.
static func mastered(edition: String, id: String) -> bool:
	return solved_in(edition, id) > 0 and best_hints(edition, id) == 0

## The first puzzle not solved yet (the last one when all are).
static func next_unsolved(edition: String) -> int:
	var entries := list(edition)
	for i in entries.size():
		if solved_in(edition, String(entries[i].id)) == 0: return i
	return maxi(entries.size() - 1, 0)

## One attempt at a puzzle: the duel it is played in and how it stands.
class Run:
	extends RefCounted
	const SIDE := 0
	var edition := ""
	var index := 0
	var entry: Dictionary = {}
	var duel: ELDuel
	## Own turns the puzzle allows, and the one the player is in.
	var allowed := 0
	var turn := 1
	## "" while it is played, then "solved" or "failed".
	var outcome := ""
	## Why it failed: "turns" (out of turns) or "lost".
	var reason := ""
	var failed_target := -1
	var error := ""
	var hints_used := 0
	## Live guidance is counted independently of the authored hint sequence.
	var tactical_hints_used := 0
	## Generated challenges and internal verification never change the authored
	## collection's completion files or its in-memory mastery records.
	var _record_progress := true
	## The hero's own count of turns when the puzzle began, and whether the
	## first of them was already under way.
	var _begun := 0
	var _first := 0
	var _enemy_begun := 0
	var _enemy_first := 0

	## Sets the position up as a duel of its own.
	func begin(profile: ELProfile, at: int) -> bool:
		var entries := ELPuzzles.list(profile.id)
		if at < 0 or at >= entries.size():
			error = "No such puzzle."
			return false
		return _begin_entry(profile, entries[at], at, true, true)

	## Start a self-contained challenge without inserting it into the catalog.
	## A retry restores an independent copy of exactly the same position.
	func begin_entry(profile: ELProfile, definition: Dictionary, record_progress := false, reset_search := true) -> bool:
		return _begin_entry(profile, definition, -1, record_progress, reset_search)

	func _begin_entry(profile: ELProfile, definition: Dictionary, at: int, record_progress: bool, reset_search: bool) -> bool:
		if not ELPuzzles.valid_entry(definition, profile.id):
			error = "Invalid puzzle definition."
			return false
		edition = profile.id
		index = at
		_record_progress = record_progress
		# A fresh attempt reads with no plan or proof kept from another duel
		# (the duel identity already keeps them apart; this frees them too).
		if reset_search: ELCombatSearch.reset_caches()
		entry = definition.duplicate(true)
		error = ""
		allowed = int(entry.turns)
		duel = ELDuel.new()
		if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": (entry.state as Dictionary).duplicate(true)}):
			error = duel.error
			return false
		# A battlefield of its own for each puzzle, the same on every attempt.
		var arenas := ELDuelMatch.arenas(profile)
		if not duel.setup.has("arena") and not arenas.is_empty(): duel.setup["arena"] = arenas[absi(hash(String(entry.id))) % arenas.size()]
		_first = 1 if duel.attacker == SIDE else 0
		_begun = int(duel.heroes[SIDE].turns)
		_enemy_first = 1 if duel.attacker != SIDE else 0
		_enemy_begun = int(duel.heroes[1 - SIDE].turns)
		turn = _first
		# The objective goes with the duel, so that the computer's readings
		# of it (ELCombatBrain) judge it as `watch` does: the defender plays to
		# stop it, and a solving tool to meet it.
		var goal: Dictionary = entry.get("objective", {"type": "win"})
		var told := {"type": String(goal.get("type", "win")), "side": SIDE, "allowed": allowed, "first": _first, "begun": _begun,
			"enemy_first": _enemy_first, "enemy_begun": _enemy_begun, "min_health": int(goal.get("min_health", 1)),
			"finish_health": int(goal.get("finish_health", 1)), "finish_mana": int(goal.get("finish_mana", 0)),
			"min_allies": int(goal.get("min_allies", 0)), "targets": goal.get("targets", []).map(func(id: Variant) -> int: return int(id)),
			"protect": goal.get("protect", []).map(func(id: Variant) -> int: return int(id))}
		if goal.has("enemy_turns"): told.enemy_turns = int(goal.enemy_turns)
		duel.setup["puzzle_goal"] = told
		outcome = ""
		reason = ""
		failed_target = -1
		hints_used = 0
		tactical_hints_used = 0
		# Check constraints at each settled action, including several commands
		# within a frame. A weak observer avoids a Run <-> duel reference cycle.
		var observer: WeakRef = weakref(self)
		duel.changed.connect(func():
			var attempt: RefCounted = observer.get_ref()
			if attempt != null: attempt.watch())
		return true

	## Follows the duel; true when the attempt has just ended.
	func watch() -> bool:
		if duel == null or not outcome.is_empty(): return false
		# The duel keeps the count of the hero's own turns, so none is missed
		# however much happened since this was last asked.
		turn = _first + int(duel.heroes[SIDE].turns) - _begun
		var goal: Dictionary = entry.get("objective", {"type": "win"})
		# Requirements apply to the whole attempt, including the winning move.
		# Sacrifice then resurrection must not satisfy a protection challenge.
		for id: Variant in goal.get("protect", []):
			if not duel.creatures.has(int(id)) or int(duel.creatures[int(id)].owner) != SIDE:
				return _fail("protected", int(id))
		if int(duel.heroes[SIDE].health) < int(goal.get("min_health", 1)):
			return _fail("lost" if int(duel.heroes[SIDE].health) <= 0 else "health")
		if String(goal.get("type", "win")) == "control":
			for id: Variant in goal.get("targets", []):
				if not duel.creatures.has(int(id)): return _fail("capture", int(id))
		var won := duel.phase == ELDuel.Phase.FINISHED and duel.winner == SIDE
		var primary_complete := false
		var enemy_completed := _enemy_first + int(duel.heroes[1 - SIDE].turns) - _enemy_begun - (1 if duel.attacker != SIDE else 0)
		match String(goal.get("type", "win")):
			"win": primary_complete = won
			"clear": primary_complete = duel.army(1 - SIDE).is_empty()
			"control":
				primary_complete = not goal.get("targets", []).is_empty() and enemy_completed >= int(goal.get("enemy_turns", 0))
				for id: Variant in goal.get("targets", []):
					if int(duel.creatures[int(id)].owner) != SIDE: primary_complete = false
			"survive":
				primary_complete = won or enemy_completed >= int(goal.get("enemy_turns", 1))
		var missing := _finish_requirement(goal)
		var complete := primary_complete and missing.is_empty()
		# Survival settles at the end of the enemy turn, just before the engine
		# increments our next turn. Delayed capture uses the same boundary.
		var boundary_goal: bool = goal.get("type") == "survive" or (goal.get("type") == "control" and goal.has("enemy_turns"))
		if turn > allowed and not (boundary_goal and complete):
			turn = allowed
			return _fail(missing if primary_complete and not missing.is_empty() else "turns")
		if complete:
			turn = mini(turn, allowed)
			outcome = "solved"
			if _record_progress: ELPuzzles.mark(edition, String(entry.id), maxi(turn, 1), hints_used)
			return true
		if duel.phase == ELDuel.Phase.FINISHED:
			return _fail(missing if primary_complete and not missing.is_empty() else ("objective" if won else "lost"))
		return false

	## These are completion conditions. Falling below them during preparation
	## is legal; continuous health and creature constraints are checked above.
	func _finish_requirement(goal: Dictionary) -> String:
		if int(duel.heroes[SIDE].health) < int(goal.get("finish_health", 1)): return "finish_health"
		if int(duel.heroes[SIDE].mana) < int(goal.get("finish_mana", 0)): return "finish_mana"
		if duel.army(SIDE).size() < int(goal.get("min_allies", 0)): return "min_allies"
		return ""

	func _fail(why: String, target := -1) -> bool:
		outcome = "failed"
		reason = why
		failed_target = target
		return true

	func _ru() -> bool:
		return duel != null and ELRemakeText.language(duel.profile) == "ru"

	func _localized(key: String, fallback := "") -> String:
		return String(entry.get(key + "_ru", entry.get(key, fallback))) if _ru() else String(entry.get(key, fallback))

	func title() -> String:
		return _localized("title", ("Задача %d" if _ru() else "Puzzle %d") % (index + 1))

	func category() -> String:
		return _localized("category", "Тактика" if _ru() else "Tactics")

	func briefing() -> String:
		return _localized("briefing")

	## An explicit puzzle opt-in discloses both sides' live supplies. Fixed-hand
	## challenges need the opponent's cards too: a legal reply must be foreseeable.
	func supply_text() -> String:
		if duel == null or not bool(entry.get("show_supply", false)): return ""
		var russian := _ru()
		var lines := PackedStringArray()
		var draws := not bool(duel.setup.get("puzzle_fixed_hands", false))
		for side in 2:
			var hero: Dictionary = duel.heroes[side]
			var hand := PackedStringArray()
			for card: String in hero.get("hand", []): hand.append(duel.card_name(card))
			var hand_heading := ("Ваша текущая рука" if side == SIDE else "Текущая рука противника") if russian else ("Your current hand" if side == SIDE else "Opponent's current hand")
			lines.append(hand_heading + ": " + (", ".join(hand) if not hand.is_empty() else ("пуста" if russian else "empty")))
			lines.append(("  Эфир сейчас: %d · каналы: %d" if russian else "  Current ether: %d · channels: %d") %
				[int(hero.get("mana", 0)), int(hero.get("channels", 0))])
			var grave := PackedStringArray()
			for card: String in hero.get("grave", []): grave.append(duel.card_name(card))
			if not grave.is_empty():
				var grave_heading := ("Ваше кладбище" if side == SIDE else "Кладбище противника") if russian else ("Your graveyard" if side == SIDE else "Opponent's graveyard")
				lines.append(grave_heading + (" · от старых карт к новым: " if russian else " · oldest to newest: ") + ", ".join(grave))
			if draws:
				var heading := ("Ваша книга" if side == SIDE else "Книга противника") if russian else ("Your book" if side == SIDE else "Opponent's book")
				lines.append(heading + (" · заряды / карт в руке" if russian else " · charges / copies in hand"))
				var under: Array = hero.get("rune_under", [])
				for slot in hero.deck.size():
					var charges := int(hero.spell_uses[slot])
					var row := "  %d. %s · %s / %d" % [slot + 1, duel.card_name(hero.deck[slot]),
						"∞" if charges < 0 else str(charges), hero.hand_slots.count(slot)]
					if slot < under.size() and not String(under[slot]).is_empty():
						row += (" · основа: " if russian else " · underlay: ") + duel.card_name(under[slot])
					lines.append(row)
				if duel.profile.id == "el2":
					var candidates := PackedStringArray()
					var next_draw := PackedStringArray()
					var available := ELSpellCharges.available(hero)
					for slot in available.size():
						if available[slot] <= 0: continue
						var name := duel.card_name(hero.deck[slot])
						candidates.append(name)
						if not hero.drawn.has(slot): next_draw.append(name)
					if next_draw.is_empty(): next_draw = candidates
					lines.append(("  Следующее взятие: " if russian else "  Next draw: ") +
						(", ".join(next_draw) if not next_draw.is_empty() else ("нет" if russian else "none")))
			if hero.artifacts.is_empty(): continue
			var heading := ("Ваши артефакты" if side == SIDE else "Артефакты противника") if russian else ("Your artifacts" if side == SIDE else "Opponent's artifacts")
			var remaining := maxi(0, duel.artifact_limit(side) - int(hero.artifact_uses))
			lines.append(heading + (" · осталось применений: %d · раунд %d" if russian else " · uses left: %d · round %d") % [remaining, duel.artifact_round()])
			for item: Dictionary in hero.artifacts:
				lines.append(("  %s · заряды: %d · готов с раунда %d" if russian else "  %s · charges: %d · ready from round %d") %
					[duel.artifact_title(item), item.charges, item.ready_round])
		return "\n".join(lines)

	func explanation() -> String:
		return _localized("explanation")

	func note_hint(index: int) -> void:
		if not outcome.is_empty() or index < 0: return
		hints_used = maxi(hints_used - tactical_hints_used, mini(index + 1, hint_count())) + tactical_hints_used

	## Called only when useful, verified current-position guidance is revealed.
	## Cancelled, stale and inconclusive analyses are not assistance.
	func note_tactical_hint() -> void:
		if not outcome.is_empty(): return
		tactical_hints_used += 1
		hints_used += 1

	func _creature_names(ids: Array) -> String:
		var names: Array[String] = []
		for id: Variant in ids:
			var c: Dictionary = entry.state.get("creatures", {}).get(str(int(id)), {})
			names.append(duel.card_name(String(c.get("card", ""))) if duel != null else str(id))
		return ", ".join(names)

	func objective_text() -> String:
		var goal: Dictionary = entry.get("objective", {"type": "win"})
		var text := ""
		match String(goal.get("type", "win")):
			"clear": text = ("Уберите всех вражеских существ за %d ход(а)." if _ru() else "Remove every enemy creature within %d turn(s).") % allowed
			"control":
				text = ("Захватите за %d ход(а): %s. Все цели должны остаться живы." if _ru() else "Take control within %d turn(s): %s. Keep every target alive.") % [allowed, _creature_names(goal.get("targets", []))]
				if goal.has("enemy_turns"): text += (" Завершите захват не раньше конца %d хода врага." if _ru() else " Complete the capture after at least %d enemy turn(s) have ended.") % int(goal.enemy_turns)
			"survive": text = ("Переживите %d ход(а) врага или победите раньше." if _ru() else "Survive %d enemy turn(s), or win sooner.") % int(goal.get("enemy_turns", 1))
			_: text = ("Победите за %d ход(а)." if _ru() else "Win within %d turn(s).") % allowed
		var names := _creature_names(goal.get("protect", []))
		if not names.is_empty(): text += (" Сохраните под своим контролем: " if _ru() else " Keep alive and under your control: ") + names + "."
		if goal.has("min_health"): text += (" Не опускайтесь ниже %d здоровья." if _ru() else " Keep at least %d health.") % int(goal.min_health)
		if goal.has("finish_health"): text += (" В конце нужно не меньше %d здоровья." if _ru() else " Finish with at least %d health.") % int(goal.finish_health)
		if goal.has("finish_mana"): text += (" В конце нужно не меньше %d эфира." if _ru() else " Finish with at least %d ether.") % int(goal.finish_mana)
		if goal.has("min_allies"): text += (" В конце сохраните не меньше %d союзных созданий." if _ru() else " Finish with at least %d allied creatures.") % int(goal.min_allies)
		return text

	func failure_text() -> String:
		match reason:
			"lost": return "Ваш герой погиб." if _ru() else "Your hero has fallen."
			"protected": return ("Вы потеряли защищаемое существо: %s." if _ru() else "You lost a protected creature: %s.") % _creature_names([failed_target])
			"capture": return ("Цель захвата покинула поле боя: %s." if _ru() else "A capture target left the battlefield: %s.") % _creature_names([failed_target])
			"health": return ("Здоровье: %d. Требовалось не меньше %d." if _ru() else "Health fell to %d. At least %d was required.") % [int(duel.heroes[SIDE].health), int(entry.get("objective", {}).get("min_health", 1))]
			"finish_health": return ("В конце осталось %d здоровья; нужно не меньше %d." if _ru() else "Finished with %d health; at least %d was required.") % [int(duel.heroes[SIDE].health), int(entry.get("objective", {}).get("finish_health", 1))]
			"finish_mana": return ("В конце осталось %d эфира; нужно не меньше %d." if _ru() else "Finished with %d ether; at least %d was required.") % [int(duel.heroes[SIDE].mana), int(entry.get("objective", {}).get("finish_mana", 0))]
			"min_allies": return ("В конце осталось %d союзных созданий; нужно не меньше %d." if _ru() else "Finished with %d allied creatures; at least %d was required.") % [duel.army(SIDE).size(), int(entry.get("objective", {}).get("min_allies", 0))]
			"objective": return "Бой окончен, но цель задачи не выполнена." if _ru() else "The battle ended before the stated objective was completed."
		return "Ходы закончились. Попробуйте другой порядок действий." if _ru() else "The turn limit was reached. Try a different sequence."

	func hint_count() -> int:
		var stages: Array = entry.get("hints_ru", entry.get("hints", [])) if _ru() else entry.get("hints", [])
		return stages.size() if not stages.is_empty() else 1

	## The first command of a line that wins, in the player's words.
	func hint(index := 0) -> String:
		var stages: Array = entry.get("hints_ru", entry.get("hints", [])) if _ru() else entry.get("hints", [])
		if not stages.is_empty(): return String(stages[clampi(index, 0, stages.size() - 1)])
		var step: Dictionary = entry.get("hint", {})
		var card := String(step.get("card", ""))
		var name := duel.card_name(card) if duel != null and not card.is_empty() else ""
		var onto := ""
		if step.has("target"): onto = duel.card_name(String(step.target))
		match String(step.get("kind", "")):
			"cast":
				if not onto.is_empty(): return "Start by casting %s on %s." % [name, onto]
				if step.has("target_hero"): return ("Start by casting %s on the enemy hero." if int(step.target_hero) != SIDE else "Start by casting %s on your hero.") % name
				return "Start by casting %s." % name
			"attack": return "Start by attacking with %s." % name
			"ability":
				if String(step.get("key", "")).begins_with("artifact"): return "Start with an artifact."
				return "Start with the ability of %s." % name if not name.is_empty() else "Start with your hero's ability."
			"end_phase": return "Start by ending the phase without attacking."
		return "No hint for this puzzle."
