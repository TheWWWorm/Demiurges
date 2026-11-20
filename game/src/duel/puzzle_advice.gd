class_name ELPuzzleAdvice
extends RefCounted
## Opt-in advice for the actual position of an ordinary, fixed-supply puzzle.
## A fresh adversarial proof certifies one next action. No action is applied to
## the live battle, and no hints, completion records or AI caches are changed.
## Scripted battles and custom spell artifacts are outside the proof's scope.

const DEFAULT_BUDGET := 12000

## limits supports budget and depth only. A tactical restriction would make a
## refutation misleading, so it cannot be passed through this advice boundary.
static func start(run: ELPuzzles.Run, limits: Dictionary = {}) -> Job:
	var job := Job.new()
	job._begin(run, limits)
	return job

## Include the attempt/duel identity and original deadline, not just the board.
## Hint accounting is deliberately excluded: revealing this result must not
## invalidate it. Ordered snapshots retain attack/block order and the RNG.
static func fingerprint(run: ELPuzzles.Run) -> String:
	if run == null or run.duel == null or run.duel.profile == null: return ""
	return JSON.stringify({"attempt": run.get_instance_id(), "duel": run.duel.get_instance_id(),
		"position": ELPuzzleProof._position(run.duel), "allowed": run.allowed,
		"first": run._first, "begun": run._begun, "outcome": run.outcome,
		"objective": run.entry.get("objective", {"type": "win"}),
		"expected_specs": run.duel.expected_specs, "fair_specs": run.duel.fair_specs,
		"language": ELRemakeText.language(run.duel.profile)}, "", false).sha256_text()

## A single instruction, using the current card rail and exact piece numbers.
## These numbers also appear in generated-puzzle creature tooltips/inspection.
static func describe(duel: ELDuel, raw: Dictionary) -> String:
	if duel == null: return ""
	var action := ELPuzzleProof.command(duel, raw)
	var ru := ELRemakeText.language(duel.profile) == "ru"
	var kind := String(action.get("kind", ""))
	var text := ""
	var target := int(action.get("target", -1))
	var choice := -1
	var choice_kind := ""
	var definition: Dictionary = {}
	match kind:
		"cast":
			var index := int(action.get("index", -1))
			if index < 0 or index >= duel.heroes[0].hand.size(): return ""
			var card := String(duel.heroes[0].hand[index])
			var name := duel.card_name(card)
			if duel.heroes[0].hand.count(card) > 1:
				name += (" (карта %d слева)" if ru else " (hand card %d from the left)") % (duel.hand_display(0).find(index) + 1)
			text = ("Сыграйте «%s»." if ru else "Cast %s.") % name
			definition = ELCatalog.rule(duel.profile, card)
			if duel.variable_power(card): text += " X = %d." % int(action.get("power", 0))
			choice = int(action.get("grave", -1))
			match String(definition.get("effect", "")):
				"exchange": choice_kind = "own_grave"
				"pale_revival": choice_kind = "both_graves"
				"repair", "reanimate": choice_kind = "grave"
				"dispel", "trade": choice_kind = "enchantment"
				"swap": choice_kind = "second"
		"ability":
			var id := int(action.get("id", -1))
			for ability: Dictionary in duel.abilities(id):
				if String(ability.key) == String(action.get("key", "")):
					definition = ability
					break
			if definition.is_empty(): return ""
			var name := String(definition.name)
			if definition.has("enchantment"):
				name += (" (чары #%d)" if ru else " (enchantment #%d)") % int(definition.enchantment)
			elif definition.has("artifact"):
				name += (" (артефакт %d)" if ru else " (artifact %d)") % (int(definition.artifact) + 1)
			text = ("Используйте способность «%s»: %s." if ru else "Activate %s (%s).") % [name, _piece(duel, id, ru)]
			if int(action.get("amount", -1)) >= 0: text += " X = %d." % int(action.amount)
			choice = int(action.get("choice", -1))
			if String(definition.get("target", "")) in ["grave", "enchantment"]:
				choice_kind = String(definition.target)
			elif definition.has("second") or String(definition.get("effect", definition.get("key", ""))) == "combine":
				choice_kind = "second"
		"attack":
			var id := int(action.get("id", -1))
			if not duel.creatures.has(id): return ""
			if duel.attacks.has(id):
				return ("Отзовите из атаки: %s." if ru else "Withdraw %s from the attack.") % _piece(duel, id, ru)
			return ("Объявите атакующим: %s." if ru else "Declare %s as an attacker.") % _piece(duel, id, ru)
		"block":
			var id := int(action.get("id", -1))
			if not duel.creatures.has(id) or not duel.creatures.has(target): return ""
			if int(duel.blocks.get(id, -1)) == target:
				return ("Снимите блок: %s." if ru else "Remove the block by %s.") % _piece(duel, id, ru)
			return ("Блокирующее существо: %s. Атакующий: %s." if ru else "Block with %s. Attacker to block: %s.") % [_piece(duel, id, ru), _piece(duel, target, ru)]
		"end_phase":
			if duel.phase == ELDuel.Phase.DEFENCE:
				return "Завершите защиту и разыграйте бой." if ru else "Finish assigning blockers and resolve combat."
			if duel.attacks.is_empty():
				return "Завершите фазу атаки без атакующих." if ru else "End your attack phase without attacking."
			return "Завершите выбор атакующих и начните атаку." if ru else "Commit the attack with the selected creatures."
		_: return ""
	if target >= 0 and String(definition.get("target", "none")) not in ["none", "grave"]:
		var named := _piece(duel, target, ru)
		if String(definition.get("key", "")) == "plague":
			named = ("ваше кладбище" if target == 0 else "кладбище врага") if ru else ("your graveyard" if target == 0 else "the enemy graveyard")
		text += (" Цель: %s." if ru else " Target: %s.") % named
	if choice >= 0:
		var selected := ""
		match choice_kind:
			"own_grave": selected = _grave(duel, 0, choice, ru)
			"grave": selected = _grave(duel, target, choice, ru)
			"both_graves": selected = _grave(duel, choice / ELDuel.GRAVE_SIDE, choice % ELDuel.GRAVE_SIDE, ru)
			"second": selected = _piece(duel, choice, ru)
			"enchantment":
				var holder := duel.find_enchantment(choice)
				for enchantment: Dictionary in duel.entity(holder).get("enchantments", []):
					if int(enchantment.id) == choice:
						selected = ("«%s», чары #%d (%s)" if ru else "%s, enchantment #%d on %s") % [duel.card_name(String(enchantment.card)), choice, _piece(duel, holder, ru)]
		if selected.is_empty(): return "" # Do not omit an essential secondary choice.
		text += (" Выберите: %s." if ru else " Choose: %s.") % selected
	return text

static func _piece(duel: ELDuel, id: int, ru: bool) -> String:
	if id == 0: return "ваш герой" if ru else "your hero"
	if id == 1: return "герой врага" if ru else "the enemy hero"
	if not duel.creatures.has(id): return ""
	var creature: Dictionary = duel.creatures[id]
	var owner := ("ваше существо" if int(creature.owner) == 0 else "существо врага") if ru else ("your" if int(creature.owner) == 0 else "enemy")
	var ready := ("истощено" if ru else "resting") if creature.resting else (("только призвано" if ru else "newly summoned") if creature.sick else ("готово" if ru else "ready"))
	return "%s %s (#%d, %d/%d, %s)" % [owner, duel.card_name(String(creature.card)), id,
		int(creature.power), maxi(0, int(creature.toughness) - int(creature.damage)), ready]

static func _grave(duel: ELDuel, side: int, index: int, ru: bool) -> String:
	if side not in [0, 1] or index < 0 or index >= duel.heroes[side].grave.size(): return ""
	var where := ("ваше кладбище" if side == 0 else "кладбище врага") if ru else ("your graveyard" if side == 0 else "the enemy graveyard")
	return ("%s (%s, карта %d)" if ru else "%s (%s, card %d)") % [duel.card_name(String(duel.heroes[side].grave[index])), where, index + 1]

## Prefer an immediately winning tactical command from this player prefix if
## actual execution already wins now. Otherwise remove a leading sequence only
## if its entire ordered state returns exactly to the current one. This avoids
## advice to recall and redeclare the same lone attacker. Resource-spending
## declarations and changed insertion orders cannot be omitted as pure cycles.
## No future enemy move is skipped or prescribed.
static func _next_action(duel: ELDuel, witness: Array) -> Dictionary:
	var initial := ELPuzzleProof._position(duel)
	var replay := duel.search_copy()
	var first := 0
	for index in witness.size():
		var raw: Dictionary = witness[index]
		if replay.active_side() != 0 or int(raw.get("side", -1)) != 0: break
		var usable := false
		if raw.get("kind") == "ability":
			usable = duel.can_use_ability(int(raw.id), String(raw.key))
		elif raw.get("kind") == "cast":
			var at := int(raw.get("index", -1))
			# Earlier casts can shift a witness's index. Never describe one
			# card while independently testing whichever card now occupies it.
			usable = at >= 0 and at < duel.heroes[0].hand.size() and duel.heroes[0].hand[at] == raw.get("card") and duel.can_cast_from_hand(at)
		if usable:
			var immediate := duel.search_copy()
			if ELPuzzleProof.apply(immediate, raw) and immediate.phase == ELDuel.Phase.FINISHED and immediate.winner == 0 \
					and int(immediate.heroes[0].health) > 0 and immediate.heroes[0].turns == duel.heroes[0].turns:
				return raw.duplicate(true)
		if not ELPuzzleProof.apply(replay, raw): return {}
		if ELPuzzleProof._position(replay) == initial: first = index + 1
		if replay.phase == ELDuel.Phase.FINISHED: break
	if first >= witness.size(): return {}
	var action: Dictionary = witness[first].duplicate(true)
	if int(action.get("side", -1)) != 0 or not ELPuzzleProof.apply(duel.search_copy(), action): return {}
	return action

class Job:
	extends RefCounted
	var done := false
	var result: Dictionary = {}
	var nodes := 0
	var progress_text := ""
	var state_key := ""
	var _proof: ELPuzzleProof.Job
	var _position: ELDuel
	var _remaining := -1
	var _started := 0
	var _ru := false

	func _begin(run: ELPuzzles.Run, limits: Dictionary) -> void:
		_started = Time.get_ticks_usec()
		if run == null or run.duel == null or run.duel.profile == null or run.duel.heroes.size() != 2:
			_finish("error", "No active puzzle is available.", "Нет активной задачи.")
			return
		_ru = ELRemakeText.language(run.duel.profile) == "ru"
		state_key = ELPuzzleAdvice.fingerprint(run)
		var current_turn := run._first + int(run.duel.heroes[0].turns) - run._begun
		if not run.outcome.is_empty() or run.duel.phase == ELDuel.Phase.FINISHED or int(run.duel.heroes[0].health) <= 0 or current_turn > run.allowed:
			_finish("terminal", "This puzzle attempt has ended.", "Эта попытка уже завершена.")
			return
		if run.duel.active_side() != 0:
			_finish("wrong_phase", "Wait for the opponent's reply, then ask again.", "Дождитесь ответа врага и запросите подсказку снова.")
			return
		if run.entry.get("objective", {"type": "win"}) != {"type": "win"}:
			_finish("error", "Live advice supports ordinary victory puzzles only.", "Тактические подсказки доступны только для задач с обычной победой.")
			return
		for key: Variant in limits:
			if key not in ["budget", "depth"]:
				_finish("error", "Unsupported advice limit.", "Неподдерживаемое ограничение анализа.")
				return
		# The current own attack/defence pair is still counted when attacker=0.
		# During an enemy turn, all previously counted own turns are completed.
		_remaining = run.allowed - (current_turn - (1 if run.duel.attacker == 0 else 0))
		if _remaining < 0 or current_turn < 0:
			_finish("error", "The puzzle's remaining turn allowance is invalid.", "Некорректный остаток ходов задачи.")
			return
		_position = run.duel.search_copy()
		_position.setup = run.duel.setup.duplicate(true)
		_proof = ELPuzzleProof.from_position(_position, _remaining,
			{"budget": limits.get("budget", DEFAULT_BUDGET), "depth": limits.get("depth", 44 if _remaining > 1 else 24)})
		progress_text = "Проверка текущей позиции и ответов врага…" if _ru else "Checking the current position and enemy replies…"
		if _proof.done: _complete()

	func is_current(run: ELPuzzles.Run) -> bool:
		return not state_key.is_empty() and state_key == ELPuzzleAdvice.fingerprint(run)

	## Time only controls yielding. Search completion depends on node/depth
	## bounds, so changing the frame rate cannot turn a cutoff into a proof.
	func step(node_quota: int = 32, usec_budget: int = 6000) -> void:
		if done: return
		_proof.step(node_quota, usec_budget)
		nodes = _proof.nodes
		if _proof.done: _complete()

	func cancel() -> void:
		if done: return
		_finish("cancelled", "Analysis cancelled.", "Анализ отменён.")

	func _complete() -> void:
		var proof: Dictionary = _proof.result
		nodes = int(proof.get("nodes", 0))
		match String(proof.get("status", "invalid")):
			"forced":
				var action := ELPuzzleAdvice._next_action(_position, proof.get("witness", []))
				# Execution accepts a few uses the UI disables (such as EL2's
				# Plague on empty graves). They remain important enemy replies,
				# but an unselectable player command is not usable advice.
				if action.get("kind") == "ability" and not _position.can_use_ability(int(action.id), String(action.key)):
					_finish("error", "A usable next-action hint could not be verified.", "Не удалось подтвердить доступное следующее действие.")
					return
				var text := ELPuzzleAdvice.describe(_position, action) if not action.is_empty() else ""
				if text.is_empty():
					_finish("error", "A complete next-action instruction could not be produced.", "Не удалось составить точную подсказку следующего действия.")
					return
				_finish("proven", "A win is still possible against every reply. Next action: " + text,
					"Победа возможна при любом ответе врага. Следующее действие: " + text)
				result.command = action
			"refuted":
				_finish("refuted", "No guaranteed win remains from this position within the turn limit. The opponent can prevent victory. Retry to change an earlier choice.",
					"Из этой позиции нельзя гарантировать победу за оставшиеся ходы: враг может помешать. Начните заново и измените более раннее решение.")
			"unknown":
				_finish("unknown", "The analysis limit was reached before every reply could be checked. This does not show that the position is lost.",
					"Достигнут предел анализа: не все ответы врага проверены. Это не означает, что позиция проиграна.")
			_: _finish("error", "This position cannot be analysed with live tactical advice.", "Эту позицию нельзя проверить тактической подсказкой.")

	func _finish(status: String, english: String, russian: String) -> void:
		result = {"status": status, "text": russian if _ru else english, "state_key": state_key,
			"nodes": nodes, "elapsed_ms": float(Time.get_ticks_usec() - _started) / 1000.0,
			"remaining_own_turns": _remaining}
		done = true
		progress_text = ""
		_proof = null
		_position = null
