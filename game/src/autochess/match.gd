class_name ELAutochessMatch
extends RefCounted
## Nine companies on nine home boards. Opponents are announced before
## preparation; every pairing fights one battle at the shared bell, shown on
## both owners' boards. Health falls as each battle ends; income, artifacts
## and places settle once every battle of the round is over.

signal changed
signal fight_started
signal board_finished(board: int)
signal round_settled
signal player_eliminated(player: int, place: int)

const SAVE_PATH := "user://autochess-el2.json"
const SAVE_FORMAT := "etherlords-el2-autochess"
const RESULT_SECONDS := 4.0

var profile: ELProfile
var run_seed := 1
var round_number := 1
var stage := "prepare"
var prepare_left := ELAutochessRules.PREPARATION_SECONDS
var result_left := 0.0
var companies: Array[ELAutochessCompany] = []
## "human" (this machine), "computer" or "remote" (an online guest).
var controllers: Array[String] = []
var names: Array[String] = []
var placements: Array[int] = []
var pairings: Array[Dictionary] = []
var boards: Array[Dictionary] = []
var previous_opponent: Array[int] = []
var bot_plans: Array[Dictionary] = []
var round_results := {}
var round_health: Array[int] = []
var ready: Array[bool] = []
var speed := 1.0
var paused := false
var auto_save := true
var save_error := false

func begin(data: ELProfile, seed_value: int, character: String, seats: Array[String] = [], seat_names: Array[String] = [], seat_characters: Array[String] = []) -> void:
	profile = data
	run_seed = maxi(1, seed_value)
	round_number = 1
	stage = "prepare"
	companies.clear(); controllers.clear(); names.clear(); placements.clear()
	pairings.clear(); boards.clear(); bot_plans.clear(); round_results.clear()
	previous_opponent.clear(); ready.clear()
	var heroes := ELAutochessCharacters.opponents(data, character, ELAutochessRules.PLAYER_COUNT - 1, run_seed)
	for player in ELAutochessRules.PLAYER_COUNT:
		var company := ELAutochessCompany.new()
		var who := character if player == 0 else heroes[player - 1]
		if player < seat_characters.size() and not seat_characters[player].is_empty(): who = seat_characters[player]
		company.begin(data, 1 + (run_seed * 37 + player * 7919) % 99999998, ELAutochessCharacters.valid(data, who))
		company.pool_companies = _pool_holders
		companies.append(company)
		controllers.append(seats[player] if player < seats.size() else ("human" if player == 0 else "computer"))
		names.append(seat_names[player] if player < seat_names.size() and not seat_names[player].is_empty() else ELAutochessCharacters.title(data, company.character))
		placements.append(0)
		previous_opponent.append(-1)
		bot_plans.append(ELAutochessBot.new_plan(player))
		ready.append(false)
	_prepare_round()
	_touch()

func _pool_holders() -> Array[ELAutochessCompany]:
	var holders: Array[ELAutochessCompany] = []
	for company in companies:
		if company.health > 0: holders.append(company)
	return holders

func health(player: int) -> int:
	return companies[player].health

func alive_players() -> Array[int]:
	var alive: Array[int] = []
	for player in companies.size():
		if companies[player].health > 0: alive.append(player)
	return alive

func is_creep_round() -> bool:
	return ELAutochessRules.is_creep_round(round_number)

func opponent_for(player: int) -> int:
	for pair: Dictionary in pairings:
		if int(pair.a) == player: return int(pair.b)
		if int(pair.b) == player and not pair.ghost: return int(pair.a)
	return -1

func ghost_for(player: int) -> bool:
	for pair: Dictionary in pairings:
		if int(pair.a) == player: return bool(pair.ghost)
	return false

## The board a player's fight is on and the side the player holds.
func board_of(player: int) -> Dictionary:
	for index in boards.size():
		var board := boards[index]
		if int(board.home) == player: return {"index": index, "team": 0}
		if int(board.visitor) == player and not board.ghost: return {"index": index, "team": 1}
	return {}

func _prepare_round() -> void:
	stage = "prepare"
	prepare_left = ELAutochessRules.PREPARATION_SECONDS
	boards.clear()
	round_results.clear()
	round_health.clear()
	for player in companies.size():
		bot_plans[player] = ELAutochessBot.new_plan(player)
		ready[player] = controllers[player] == "computer"
	_choose_pairings()

func _choose_pairings() -> void:
	pairings.clear()
	var alive := alive_players()
	if is_creep_round():
		for player in alive: pairings.append({"a": player, "b": -1, "ghost": false})
		return
	var random := RandomNumberGenerator.new()
	random.seed = run_seed * 104729 + round_number * 7919
	for index in range(alive.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var held := alive[index]
		alive[index] = alive[other]
		alive[other] = held
	# Avoid repeating the previous opponent when another is available.
	var order := alive.duplicate()
	var used := {}
	for player: int in order:
		if used.has(player): continue
		used[player] = true
		var candidates := order.filter(func(p: int) -> bool: return not used.has(p) and p != previous_opponent[player])
		if candidates.is_empty(): candidates = order.filter(func(p: int) -> bool: return not used.has(p))
		if candidates.is_empty():
			var donors := alive_players().filter(func(p: int) -> bool: return p != player)
			if not donors.is_empty(): pairings.append({"a": player, "b": donors[random.randi_range(0, donors.size() - 1)], "ghost": true})
			continue
		var opponent: int = candidates[0]
		used[opponent] = true
		pairings.append({"a": player, "b": opponent, "ghost": false})
		previous_opponent[player] = opponent
		previous_opponent[opponent] = player

## Preparation clock, computer shopping, battles and the result pause.
func process(delta: float) -> void:
	if paused: return
	match stage:
		"prepare":
			prepare_left = maxf(0.0, prepare_left - delta)
			advance_bots(delta)
			if prepare_left <= 0.0 or _everyone_ready(): start_fight()
		"fight":
			var step := delta * speed
			for index in boards.size():
				var board := boards[index]
				if board.done: continue
				var battle: ELAutochessBattle = board.battle
				if battle.advance(step): _record_board(index)
		"result":
			result_left -= delta
			if result_left <= 0.0: next_round()

func _everyone_ready() -> bool:
	for player in alive_players():
		if controllers[player] != "computer" and not ready[player]: return false
	return true

func set_ready(player: int, value := true) -> void:
	if player >= 0 and player < ready.size():
		ready[player] = value
		_touch(false)

func advance_bots(delta: float) -> Array[int]:
	var moved: Array[int] = []
	if stage != "prepare": return moved
	for player in companies.size():
		if controllers[player] != "computer" or companies[player].health <= 0: continue
		var plan := bot_plans[player]
		if plan.done: continue
		plan.wait = float(plan.wait) - delta
		if float(plan.wait) > 0.0: continue
		plan.wait = float(plan.wait) + 0.8 + float(player % 4) * 0.18
		ELAutochessBot.step(companies[player], player, round_number, plan)
		moved.append(player)
	if not moved.is_empty(): changed.emit()
	return moved

func finish_bots() -> void:
	for player in companies.size():
		if controllers[player] != "computer" or companies[player].health <= 0: continue
		while not bot_plans[player].done: ELAutochessBot.step(companies[player], player, round_number, bot_plans[player])

func start_fight() -> void:
	if stage != "prepare": return
	finish_bots()
	round_health.clear()
	for company in companies: round_health.append(company.health)
	for player in alive_players(): companies[player].start_battle()
	boards.clear()
	for index in pairings.size():
		var pair := pairings[index]
		var a := int(pair.a)
		var b := int(pair.b)
		var battle := ELAutochessBattle.new()
		var visitor: Array = ELAutochessRules.creeps(round_number, run_seed) if b < 0 else companies[b].formation(1)
		battle.setup(profile, companies[a].formation(0), visitor, run_seed * 7919 + round_number * 104729 + index * 31, round_number)
		boards.append({"battle": battle, "home": a, "visitor": b, "ghost": bool(pair.ghost), "done": false})
	stage = "fight"
	fight_started.emit()
	for index in boards.size():
		if boards[index].battle.finished: _record_board(index)
	_touch(false)

func _record_board(index: int) -> void:
	var board := boards[index]
	if board.done: return
	board.done = true
	var battle: ELAutochessBattle = board.battle
	var a := int(board.home)
	var b := int(board.visitor)
	var winner := battle.winner
	var loss_a := 0
	var loss_b := 0
	if winner == 1: loss_a = ELAutochessRules.defeat_damage(round_number, battle.survivor_damage(1))
	elif winner == -1: loss_a = ELAutochessRules.draw_damage(round_number)
	if b >= 0 and not board.ghost:
		if winner == 0: loss_b = ELAutochessRules.defeat_damage(round_number, battle.survivor_damage(0))
		elif winner == -1: loss_b = ELAutochessRules.draw_damage(round_number)
	_apply_loss(a, loss_a)
	round_results[a] = {"winner": 0 if winner == 0 else (1 if winner == 1 else -1), "health_lost": loss_a, "opponent": b, "damage": battle.damage_by_uid(0), "seconds": battle.time}
	if b >= 0 and not board.ghost:
		_apply_loss(b, loss_b)
		round_results[b] = {"winner": 0 if winner == 1 else (1 if winner == 0 else -1), "health_lost": loss_b, "opponent": a, "damage": battle.damage_by_uid(1), "seconds": battle.time}
	board_finished.emit(index)
	if boards.all(func(x: Dictionary) -> bool: return x.done): _settle_round()
	else: _touch(false)

func _apply_loss(player: int, loss: int) -> void:
	var company := companies[player]
	company.health = maxi(0, int(round_health[player]) - loss)

func _settle_round() -> void:
	var entered: Array[int] = []
	for player in companies.size():
		if int(round_health[player]) > 0: entered.append(player)
	var remaining := {}
	for player in entered: remaining[player] = int(round_health[player]) - int(round_results.get(player, {}).get("health_lost", 0))
	var eliminated := entered.filter(func(p: int) -> bool: return companies[p].health <= 0)
	eliminated.sort_custom(func(x: int, y: int) -> bool: return remaining[x] < remaining[y] if remaining[x] != remaining[y] else x > y)
	if eliminated.size() == entered.size() and not eliminated.is_empty():
		# A final simultaneous defeat: highest remaining health, then lowest seat.
		var champion: int = eliminated.pop_back()
		companies[champion].health = 1
	for index in eliminated.size():
		var player: int = eliminated[index]
		placements[player] = entered.size() - index
		companies[player].stage = "lost"
		player_eliminated.emit(player, placements[player])
	for player in entered:
		var company := companies[player]
		var result: Dictionary = round_results.get(player, {"winner": -1, "health_lost": 0})
		var won := int(result.winner) == 0
		var income := company.income_preview(company.battle_savings, won)
		company.history.append({"round": round_number, "winner": int(result.winner), "health_lost": int(result.health_lost)})
		if company.history.size() > 40: company.history.pop_front()
		if company.health > 0:
			company.ether += int(income.total)
			company.offer_items_after(round_number)
			company.stage = "result"
		var record := result.duplicate(true)
		record["income"] = income
		record["round"] = round_number
		company.last_result = record
	var survivors := alive_players()
	if survivors.size() <= 1:
		if survivors.size() == 1:
			placements[survivors[0]] = 1
			companies[survivors[0]].stage = "won"
		stage = "over"
	else:
		stage = "result"
		result_left = RESULT_SECONDS
	round_settled.emit()
	_touch()

func next_round() -> void:
	if stage != "result": return
	round_number = mini(ELAutochessRules.MAX_ROUNDS, round_number + 1)
	for player in alive_players(): companies[player].next_round(round_number)
	_prepare_round()
	_touch()

## A company whose controller is this machine or the host's computer.
func company(player: int) -> ELAutochessCompany:
	return companies[player]

func standings() -> Array[int]:
	var order: Array[int] = []
	for player in companies.size(): order.append(player)
	order.sort_custom(func(x: int, y: int) -> bool:
		var hx := companies[x].health
		var hy := companies[y].health
		if hx != hy: return hx > hy
		if placements[x] != placements[y]: return (placements[x] if placements[x] > 0 else 99) < (placements[y] if placements[y] > 0 else 99)
		return x < y)
	return order

func snapshot() -> Dictionary:
	var rows: Array = []
	for company in companies: rows.append(company.snapshot())
	return {"format": SAVE_FORMAT, "version": ELAutochessRules.VERSION, "seed": str(run_seed), "round": round_number,
		"stage": "prepare" if stage == "fight" else stage, "prepare_left": prepare_left,
		"companies": rows, "controllers": controllers.duplicate(), "names": names.duplicate(), "placements": placements.duplicate(),
		"pairings": pairings.duplicate(true), "previous_opponent": previous_opponent.duplicate(),
		"health": round_health.duplicate() if stage == "fight" and not round_health.is_empty() else []}

func restore(data: ELProfile, saved: Dictionary) -> bool:
	if saved.get("format") != SAVE_FORMAT or not ELAutochessCompany._integer(saved.get("version"), 1, ELAutochessRules.VERSION): return false
	if not saved.get("companies") is Array or saved.companies.size() != ELAutochessRules.PLAYER_COUNT: return false
	if not saved.get("placements") is Array or saved.placements.size() != ELAutochessRules.PLAYER_COUNT: return false
	if not saved.get("pairings") is Array or not saved.get("names") is Array or not saved.get("controllers") is Array: return false
	if not String(saved.get("seed", "")).is_valid_int() or not ELAutochessCompany._integer(saved.get("round"), 1, ELAutochessRules.MAX_ROUNDS): return false
	if not saved.get("stage") in ["prepare", "result", "over"]: return false
	var loaded: Array[ELAutochessCompany] = []
	for row: Variant in saved.companies:
		if not row is Dictionary: return false
		var company := ELAutochessCompany.new()
		if not company.restore(data, row): return false
		loaded.append(company)
	profile = data
	run_seed = int(saved.seed)
	round_number = int(saved.round)
	companies = loaded
	for company in companies: company.pool_companies = _pool_holders
	controllers.clear(); names.clear(); placements.clear(); previous_opponent.clear(); bot_plans.clear(); ready.clear()
	for player in ELAutochessRules.PLAYER_COUNT:
		controllers.append("human" if player == 0 else "computer")
		names.append(String(saved.names[player]) if player < saved.names.size() else "")
		placements.append(int(saved.placements[player]))
		previous_opponent.append(int(saved.get("previous_opponent", [])[player]) if saved.get("previous_opponent", []) is Array and player < saved.previous_opponent.size() else -1)
		bot_plans.append(ELAutochessBot.new_plan(player))
		ready.append(player != 0)
	# An interrupted fight restarts from preparation with the health before it.
	var before: Variant = saved.get("health", [])
	if before is Array and before.size() == ELAutochessRules.PLAYER_COUNT:
		for player in companies.size(): companies[player].health = int(before[player])
	pairings.clear()
	for pair: Variant in saved.pairings:
		if pair is Dictionary: pairings.append({"a": int(pair.a), "b": int(pair.b), "ghost": bool(pair.ghost)})
	stage = String(saved.stage)
	prepare_left = clampf(float(saved.get("prepare_left", ELAutochessRules.PREPARATION_SECONDS)), 5.0, ELAutochessRules.PREPARATION_SECONDS)
	boards.clear()
	round_results.clear()
	round_health.clear()
	if stage == "result": result_left = 0.5
	if pairings.is_empty() and stage == "prepare": _choose_pairings()
	return true

func load_saved(data: ELProfile) -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return parsed is Dictionary and restore(data, parsed)

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(SAVE_PATH)

func save() -> bool:
	if stage == "over":
		delete_save()
		return true
	var file := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(snapshot()))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH)) == OK

func _touch(persist := true) -> void:
	if persist and auto_save and controllers.has("human") and not controllers.has("remote"): save_error = not save()
	changed.emit()
