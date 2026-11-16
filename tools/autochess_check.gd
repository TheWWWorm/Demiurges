extends SceneTree
## Headless checks and balance report for the Etherlords II autochess mode:
## every recruit form has stats and animation timing, mirrored fights are
## fair, alliance/item effects apply, and complete nine-computer matches end
## with one winner. Pass the Etherlords II folder:
##
##   godot --headless --path game --script ../tools/autochess_check.gd -- --el2="C:/Games/Etherlords II" [--matches=4] [--report=out.json]

var failures: Array[String] = []
var report := {}

func check(condition: bool, what: String) -> void:
	if not condition:
		failures.append(what)
		printerr("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.trim_prefix("--" + name + "=")
	return fallback

func _profile() -> ELProfile:
	var folder := _arg("el2", "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get("el2", ""))
	var profile := ELProfile.new()
	if folder.is_empty() or not profile.mount("el2", folder): return null
	return profile

func _run() -> void:
	var profile := _profile()
	if profile == null:
		printerr("Etherlords II is required: pass --el2=<folder>")
		quit(2)
		return
	check(ELAutochessRules.available(profile), "every recruit form exists in this installation")
	_check_forms(profile)
	_check_mirror(profile)
	_check_lines(profile)
	_check_items(profile)
	_check_combat_purchases(profile)
	_check_undo_pool(profile)
	_check_haste(profile)
	_check_lives(profile)
	_check_command(profile)
	_check_forfeit(profile)
	_check_fight_save_pool(profile)
	_check_matches(profile, int(_arg("matches", "3")))
	_check_save(profile)
	var path := _arg("report", "")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, " "))
	print("autochess check: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _check_forms(profile: ELProfile) -> void:
	var rows := []
	for index in ELAutochessRules.FAMILIES.size():
		for rank in 3:
			var code := ELAutochessRules.form(index, rank)
			var values := ELAutochessRules.stats(profile, code, ELAutochessRules.tier(index), rank, index)
			var clips := ELAutochessAbilities.clip_info(profile, code)
			check(float(values.health) > 0 and float(values.damage) > 0, "%s has health and damage" % code)
			check(clips.has("attack") and clips.has("death"), "%s has attack and death clips" % code)
			check(not ELAutochessRules.title(profile, code).is_empty(), "%s has a name" % code)
			rows.append([code, index, rank, values.health, values.damage, values.defense, values.interval, values.role])
	report["forms"] = rows

func _fight(profile: ELProfile, home: Array, visitor: Array, seed_value: int) -> ELAutochessBattle:
	var battle := ELAutochessBattle.new()
	battle.setup(profile, home, visitor, seed_value)
	battle.run_to_end()
	return battle

func _place(index: int, rank: int, count: int, team: int, item := "") -> Array:
	var rows := []
	for i in count:
		var ranged := String(ELAutochessRules.family(index).role) == "Ranged"
		var point := Vector2(-10.5 if ranged else -5.0, [0.0, -3.5, 3.5, -7.0, 7.0][i % 5])
		if team == 1: point = -point
		rows.append({"code": ELAutochessRules.form(index, rank), "family": index, "rank": rank, "tier": ELAutochessRules.tier(index),
			"point": [point.x, point.y], "uid": 100 * team + i + 1, "item": item})
	return rows

## Identical armies on both sides must split the wins.
func _check_mirror(profile: ELProfile) -> void:
	var wins := [0, 0, 0]
	for index in ELAutochessRules.FAMILIES.size():
		for seed_value in 4:
			var battle := _fight(profile, _place(index, 0, 3, 0), _place(index, 0, 3, 1), 1000 + index * 17 + seed_value)
			wins[battle.winner + 1] += 1
			check(battle.finished, "%s mirror finishes" % ELAutochessRules.FAMILIES[index].key)
	report["mirror"] = {"draws": wins[0], "home": wins[1], "visitor": wins[2]}
	var decided: int = wins[1] + wins[2]
	check(decided == 0 or absf(float(wins[1]) / decided - 0.5) < 0.2, "mirror fights are side-neutral (%d/%d)" % [wins[1], wins[2]])

## Equal-investment round robin per price at every star level, and a
## two-star against three one-stars of the same line.
func _check_lines(profile: ELProfile) -> void:
	var table := {}
	for t in range(1, 6):
		var lines: Array[int] = []
		for index in ELAutochessRules.FAMILIES.size():
			if ELAutochessRules.tier(index) == t: lines.append(index)
		for a: int in lines:
			var score := 0.0
			var games := 0
			for b: int in lines:
				if a == b: continue
				# The same investment at every star level: three one-stars,
				# three two-stars, two three-stars.
				for rank in 3:
					var count := 2 if rank == 2 else 3
					for side in 2:
						var salt := a * 97 + b * 13 + rank * 7
						var battle := _fight(profile, _place(a, rank, count, 0), _place(b, rank, count, 1), 5000 + salt) if side == 0 else _fight(profile, _place(b, rank, count, 0), _place(a, rank, count, 1), 7000 + salt)
						var mine := 0 if side == 0 else 1
						score += 1.0 if battle.winner == mine else 0.5 if battle.winner == -1 else 0.0
						games += 1
			var star := _fight(profile, _place(a, 1, 1, 0), _place(a, 0, 3, 1), 9000 + a)
			table[ELAutochessRules.FAMILIES[a].key] = {"tier": t, "win_rate": snappedf(score / maxf(1, games), 0.01), "two_star_beats_three": star.winner == 0}
	report["lines"] = table
	for key: String in table:
		var rate := float(table[key].win_rate)
		check(rate >= 0.15 and rate <= 0.85, "%s is within its price (win rate %.2f)" % [key, rate])

func _check_items(profile: ELProfile) -> void:
	var gains := {}
	for kind: String in ELAutochessArtifacts.RULES:
		var t := ELAutochessArtifacts.tier(kind)
		var line := 8 if t <= 2 else 16
		var rank := 0 if t <= 2 else 1
		var wins := 0.0
		for seed_value in 6:
			var carriers := _place(line, rank, 3, 0)
			carriers[0].item = kind
			var battle := _fight(profile, carriers, _place(line, rank, 3, 1), 300 + seed_value)
			wins += 1.0 if battle.winner == 0 else 0.5 if battle.winner == -1 else 0.0
		gains[kind] = {"tier": t, "win_rate": snappedf(wins / 6.0, 0.01)}
		check(not ELAutochessArtifacts.title(profile, kind).is_empty(), "%s has a name" % kind)
	report["items"] = gains

func _check_matches(profile: ELProfile, count: int) -> void:
	var results := []
	var line_picks := {}
	for game in count:
		var game_match := ELAutochessMatch.new()
		game_match.auto_save = false
		var seats: Array[String] = []
		for player in ELAutochessRules.PLAYER_COUNT: seats.append("computer")
		game_match.begin(profile, 4242 + game * 101, ELAutochessCharacters.choices(profile)[0], seats)
		var guard := 0
		while game_match.stage != "over" and guard < 200000:
			guard += 1
			if game_match.stage == "prepare":
				game_match.finish_bots()
				game_match.start_fight()
			elif game_match.stage == "fight":
				game_match.process(1.0)
			elif game_match.stage == "result":
				game_match.next_round()
		check(game_match.stage == "over", "match %d ends" % game)
		var winners := game_match.placements.filter(func(p: int) -> bool: return p == 1).size()
		check(winners == 1, "match %d has one winner" % game)
		var places := game_match.placements.duplicate()
		places.sort()
		check(places == [1, 2, 3, 4, 5, 6, 7, 8, 9], "match %d assigns every place once (%s)" % [game, str(game_match.placements)])
		var winner := game_match.placements.find(1)
		var army := []
		for entry: Dictionary in game_match.companies[winner].army:
			if entry.deployed: army.append("%s*%d" % [ELAutochessRules.FAMILIES[int(entry.family)].key, int(entry.rank) + 1])
		for company in game_match.companies:
			for entry: Dictionary in company.army:
				var key: String = ELAutochessRules.FAMILIES[int(entry.family)].key
				line_picks[key] = int(line_picks.get(key, 0)) + 1
		results.append({"rounds": game_match.round_number, "winner_seat": winner, "winner_strategy": ELAutochessBot.strategy(winner), "army": army})
	report["matches"] = results
	report["line_picks"] = line_picks

func _check_save(profile: ELProfile) -> void:
	var game_match := ELAutochessMatch.new()
	game_match.auto_save = false
	game_match.begin(profile, 77, ELAutochessCharacters.choices(profile)[0])
	game_match.companies[0].buy(0)
	var saved := game_match.snapshot()
	var copy := ELAutochessMatch.new()
	check(copy.restore(profile, JSON.parse_string(JSON.stringify(saved))), "a match snapshot restores")
	check(copy.companies[0].army.size() == game_match.companies[0].army.size(), "restored army keeps its creatures")
	var again := JSON.stringify(copy.snapshot())
	var before := JSON.stringify(saved)
	if again != before:
		for i in mini(again.length(), before.length()):
			if again[i] != before[i]:
				printerr("save differs at: ", before.substr(maxi(0, i - 80), 160), "
  vs: ", again.substr(maxi(0, i - 80), 160))
				break
	check(again == before, "a restored match saves identically")

func _pool_match(profile: ELProfile, seed_value: int) -> ELAutochessMatch:
	var game_match := ELAutochessMatch.new()
	game_match.auto_save = false
	game_match.begin(profile, seed_value, ELAutochessCharacters.choices(profile)[0])
	return game_match

## Every company of a match together never holds more copies than the pool.
func _pool_ok(game_match: ELAutochessMatch) -> bool:
	var left := game_match.companies[0].pool_left()
	for line: int in left:
		if int(left[line]) < 0: return false
	return true

## A purchase during a battle never overfills the reserves, and copies that
## could not combine then (a deployed copy was fighting) combine when the
## next preparation begins.
func _check_combat_purchases(profile: ELProfile) -> void:
	var game_match := _pool_match(profile, 91)
	var company := game_match.companies[0]
	company.round_number = 3
	company.army.clear()
	for i in 2:
		var kobold := company._recruit(0, 0, 1)
		kobold.deployed = true
		kobold.point = [-5.0, -3.0 + 6.0 * i]
	for line in range(1, 9): company._recruit(line, 0, ELAutochessRules.tier(line))
	company.ether = 100
	company.start_battle()
	company.shop.clear()
	for i in 5: company.shop.append({"family": 0, "rank": 0, "locked": false})
	var bought := 0
	for i in 5:
		if company.buy(i).is_empty(): bought += 1
	check(company.bench_count() <= company.bench_limit(), "combat purchases keep the reserves within their limit (%d bought, %d reserves)" % [bought, company.bench_count()])
	# Room on the bench: two copies wait for the deployed pair.
	var other := _pool_match(profile, 92)
	company = other.companies[0]
	company.round_number = 3
	company.army.clear()
	for i in 2:
		var kobold := company._recruit(0, 0, 1)
		kobold.deployed = true
		kobold.point = [-5.0, -3.0 + 6.0 * i]
	for line in range(1, 5): company._recruit(line, 0, ELAutochessRules.tier(line))
	company.ether = 100
	company.start_battle()
	company.shop.clear()
	for i in 2: company.shop.append({"family": 0, "rank": 0, "locked": false})
	check(company.buy(0).is_empty() and company.buy(1).is_empty(), "combat purchases with room on the bench succeed")
	check(company.owned_counts(0) == [4, 0, 0], "a combat purchase does not combine with a fighting copy (%s)" % str(company.owned_counts(0)))
	company.stage = "result"
	company.next_round(4)
	check(company.owned_counts(0) == [1, 1, 0], "deferred copies combine when preparation begins (%s)" % str(company.owned_counts(0)))
	check(company.bench_count() <= company.bench_limit(), "reserves within their limit after the deferred combination")
	# Three reserve copies combine during a battle without touching the army.
	var third := _pool_match(profile, 93)
	company = third.companies[0]
	company.round_number = 3
	company.army.clear()
	for i in 2: company._recruit(0, 0, 1)
	for line in range(1, 7): company._recruit(line, 0, ELAutochessRules.tier(line))
	company.ether = 100
	company.start_battle()
	company.shop.clear()
	company.shop.append({"family": 0, "rank": 0, "locked": false})
	check(company.buy(0).is_empty() and company.owned_counts(0) == [0, 1, 0], "three reserve copies combine during a battle on a full bench")

## Undoing a sale cannot take back a copy another company has since claimed.
func _check_undo_pool(profile: ELProfile) -> void:
	var game_match := _pool_match(profile, 94)
	var line := -1
	for index in ELAutochessRules.FAMILIES.size():
		if ELAutochessRules.tier(index) == 5:
			line = index
			break
	for company in game_match.companies:
		company.army.clear()
		company.shop.clear()
		company.items.clear()
	var seller := game_match.companies[0]
	var unit := seller._recruit(line, 0, 5)
	var holder := game_match.companies[1]
	for i in ELAutochessRules.pool_size(line) - 1: holder._recruit(line, 0, 5)
	check(int(seller.pool_left()[line]) == 0, "the whole pool of the line is owned")
	check(seller.sell(int(unit.uid)).is_empty(), "the seller sells its copy")
	seller.undo()
	check(seller.owned_counts(line)[0] == 1 and _pool_ok(game_match), "undo of a sale nobody claimed restores the copy")
	seller.sell(int(seller.army[0].uid))
	game_match.companies[2].shop.append({"family": line, "rank": 0, "locked": false})
	check(_pool_ok(game_match), "another company claims the released copy")
	var error := seller.undo()
	check(_pool_ok(game_match) and seller.owned_counts(line)[0] == 0, "undo cannot duplicate a claimed copy (pool left %d)" % int(seller.pool_left()[line]))
	check(not error.is_empty() and not seller.can_undo(), "the refused undo explains itself and clears the history (%s)" % error)
	# Formation changes still undo.
	var mover := game_match.companies[3]
	mover.round_number = 3
	var piece := mover._recruit(0, 0, 1)
	check(mover.deploy(int(piece.uid), Vector2(-5.0, 0.0)).is_empty(), "a reserve deploys")
	mover.undo()
	check(not mover.unit(int(piece.uid)).deployed, "a deployment undoes")

## Temporary attack speed shortens the attack once, not twice.
func _check_haste(profile: ELProfile) -> void:
	for case: Array in [[0.35, 1.4 / 1.35], [0.4, 1.0]]:
		var battle := ELAutochessBattle.new()
		battle.setup(profile, _place(0, 0, 1, 0), _place(0, 0, 1, 1), 5)
		var u: ELAutochessBattle.Fighter = battle.units[0]
		var other: ELAutochessBattle.Fighter = battle.units[1]
		u.interval = 1.4
		u.haste = float(case[0])
		u.haste_left = 100.0
		battle._start_attack(u, other)
		var seconds := 0.0
		while u.action != "" and seconds < 5.0:
			battle._continue_action(u)
			seconds += ELAutochessBattle.TICK
		check(absf(seconds - float(case[1])) <= ELAutochessBattle.TICK + 0.001, "%d%% haste attacks every %.2f s (expected %.2f)" % [roundi(float(case[0]) * 100), seconds, float(case[1])])

func _line(key: String) -> int:
	for index in ELAutochessRules.FAMILIES.size():
		if ELAutochessRules.FAMILIES[index].key == key: return index
	return -1

func _unit_at(line: int, rank: int, point: Vector2, uid: int) -> Dictionary:
	return {"code": ELAutochessRules.form(line, rank), "family": line, "rank": rank, "tier": ELAutochessRules.tier(line), "point": [point.x, point.y], "uid": uid, "item": ""}

func _deaths_of(battle: ELAutochessBattle, u: ELAutochessBattle.Fighter) -> int:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.k == "death" and int(e.u) == u.id).size()

## One death per life: damage that sets off more damage (a reflected Rod of
## Fire killing a Walking Horror, whose dying aura kills the rod's target)
## kills each creature once, so a fallen Hopper still waits for three deaths.
## A lethal poison tick on a creature its item brings back does not kill
## the new life with the old poison.
func _check_lives(profile: ELProfile) -> void:
	var horrors := _line("horrors")
	var hoppers := _line("hoppers")
	var kobolds := 0
	var battle := ELAutochessBattle.new()
	battle.setup(profile, [_unit_at(horrors, 0, Vector2(-3, 0), 1), _unit_at(hoppers, 0, Vector2(-8, 4), 2)],
		[_unit_at(kobolds, 0, Vector2(3, 0), 101), _unit_at(kobolds, 0, Vector2(8, 4), 102)], 11)
	var horror: ELAutochessBattle.Fighter = battle.units[0]
	var hopper: ELAutochessBattle.Fighter = battle.units[1]
	var target: ELAutochessBattle.Fighter = battle.units[2]
	var other: ELAutochessBattle.Fighter = battle.units[3]
	check(String(horror.ability.get("kind", "")) == "death_aura" and String(hopper.ability.get("kind", "")) == "rise", "the test has a Walking Horror and a Hopper (%s, %s)" % [horror.code, hopper.code])
	horror.gear = ELAutochessArtifacts.RULES.RodOfFire.duplicate()
	target.gear = ELAutochessArtifacts.RULES.RodOfReflection.duplicate()
	battle._die(hopper, -1)
	var counted := battle.deaths
	for u: ELAutochessBattle.Fighter in [horror, target, other]: u.shield = 0.0
	horror.hp = 1.0
	target.hp = 0.5
	battle._harm(target, 60.0, horror.id, "rod")
	check(horror.dead and target.dead and _deaths_of(battle, target) == 1 and battle.deaths - counted == 2,
		"a rod reflected into a dying Walking Horror kills its target once (%d deaths, %d of the target)" % [battle.deaths - counted, _deaths_of(battle, target)])
	check(hopper.dead, "a Hopper does not rise after two creatures fell")
	battle._die(other, -1)
	check(not hopper.dead, "the Hopper rises after the third")
	battle._die(target, -1)
	check(_deaths_of(battle, target) == 1, "a dead creature is not killed again")
	# Poison and a revive item.
	battle = ELAutochessBattle.new()
	battle.setup(profile, [_unit_at(kobolds, 0, Vector2(-3, 0), 1)], [_unit_at(kobolds, 0, Vector2(3, 0), 101)], 12)
	var carrier: ELAutochessBattle.Fighter = battle.units[0]
	carrier.gear = ELAutochessArtifacts.RULES.RodOfRessurection.duplicate()
	carrier.shield = 0.0
	carrier.hp = 1.0
	carrier.poisons = [{"dps": 1000.0, "left": 3.0, "source": battle.units[1].id}, {"dps": 1000.0, "left": 3.0, "source": battle.units[1].id}]
	battle._status(carrier)
	check(not carrier.dead and carrier.revived and carrier.poisons.is_empty(), "a creature revived by a lethal poison tick comes back without the poison (%d left)" % carrier.poisons.size())
	for i in 10: battle._status(carrier)
	check(not carrier.dead and _deaths_of(battle, carrier) == 1, "the revived creature does not die again of the cleared poison")

## A creature that changes sides under the Ring of Command is not hit by
## a blow its new ally had already begun.
func _check_command(profile: ELProfile) -> void:
	var battle := ELAutochessBattle.new()
	battle.setup(profile, [_unit_at(0, 0, Vector2(-0.6, 0), 1), _unit_at(0, 0, Vector2(-8, 4), 2)], [_unit_at(0, 0, Vector2(0.6, 0), 101)], 13)
	var attacker: ELAutochessBattle.Fighter = battle.units[0]
	var holder: ELAutochessBattle.Fighter = battle.units[1]
	var victim: ELAutochessBattle.Fighter = battle.units[2]
	holder.gear = ELAutochessArtifacts.RULES.RingOfCommand.duplicate()
	battle._start_attack(attacker, victim)
	victim.shield = 0.0
	battle._harm(victim, victim.hp - victim.max_hp * 0.25, -1, "ability")
	check(victim.team == 0, "the Ring of Command takes the wounded enemy")
	var hp := victim.hp
	var seconds := 0.0
	while attacker.action != "" and seconds < 5.0:
		battle._continue_action(attacker)
		seconds += ELAutochessBattle.TICK
	check(victim.hp == hp, "an attack begun before the change of sides does not land on the new ally (%.1f -> %.1f)" % [hp, victim.hp])

func _finish_boards(game_match: ELAutochessMatch, losers: Array[int] = []) -> void:
	for index in game_match.boards.size():
		var board: Dictionary = game_match.boards[index]
		if board.done: continue
		var battle: ELAutochessBattle = board.battle
		battle.finished = true
		battle.winner = 1 if int(board.home) in losers else 0
		game_match._record_board(index)

## A conceded player stays out: settled during a battle, restored from a
## save made during it, and when it concedes between battles.
func _check_forfeit(profile: ELProfile) -> void:
	var game_match := _pool_match(profile, 95)
	game_match.start_fight()
	game_match.forfeit(4)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game_match.snapshot()))
	_finish_boards(game_match)
	check(game_match.companies[4].health == 0 and game_match.placements[4] == 9 and game_match.companies[4].stage == "lost",
		"a player who conceded during a battle is settled out (health %d, place %d)" % [game_match.companies[4].health, game_match.placements[4]])
	var copy := ELAutochessMatch.new()
	copy.auto_save = false
	var restored := copy.restore(profile, saved)
	var paired_after := copy.pairings.any(func(p: Dictionary) -> bool: return int(p.a) == 4 or int(p.b) == 4)
	check(restored and copy.companies[4].health == 0 and copy.companies[4].forfeited and copy.placements[4] == 9 and not paired_after,
		"a save made during that battle keeps the player out (health %d, place %d)" % [copy.companies[4].health, copy.placements[4]])
	var again := ELAutochessMatch.new()
	again.auto_save = false
	check(again.restore(profile, JSON.parse_string(JSON.stringify(game_match.snapshot()))) and again.companies[4].health == 0 and again.placements[4] == 9, "a later save keeps the place")
	game_match.next_round()
	game_match.forfeit(5)
	var paired := game_match.pairings.any(func(p: Dictionary) -> bool: return int(p.a) == 5 or int(p.b) == 5)
	check(game_match.placements[5] == 8 and not paired and game_match.alive_players().size() == 7, "a player who concedes in preparation takes the lowest open place and leaves the pairings")
	game_match.start_fight()
	_finish_boards(game_match)
	check(game_match.companies[5].health == 0 and game_match.placements[5] == 8, "the next battle does not bring it back")

## A company that falls during a battle keeps its creatures out of the pool
## until the round is settled, so a save made during the battle (which
## restarts the round from the health before it) is never short of copies.
func _check_fight_save_pool(profile: ELProfile) -> void:
	var game_match := _pool_match(profile, 96)
	var line := -1
	for index in ELAutochessRules.FAMILIES.size():
		if ELAutochessRules.tier(index) == 5:
			line = index
			break
	for company in game_match.companies:
		company.army.assign(company.army.filter(func(e: Dictionary) -> bool: return int(e.family) != line))
		company.shop.assign(company.shop.filter(func(o: Dictionary) -> bool: return int(o.family) != line))
	var fallen := game_match.companies[3]
	for i in ELAutochessRules.pool_size(line): fallen._recruit(line, 0, 5)
	fallen.health = 1
	game_match.start_fight()
	var board := game_match.board_of(3)
	var battle: ELAutochessBattle = game_match.boards[int(board.index)].battle
	battle.finished = true
	battle.winner = 1
	game_match._record_board(int(board.index))
	var human := game_match.companies[0]
	check(fallen.health == 0 and int(human.pool_left()[line]) == 0, "a company that fell during the battle keeps its creatures until the round settles (%d left)" % int(human.pool_left()[line]))
	# A top-level company whose shop could offer the released copies.
	human.training = ELAutochessRules.MAX_TRAINING
	human.ether = 5000
	for i in 300:
		if human.shop.any(func(o: Dictionary) -> bool: return int(o.family) == line): break
		human.refresh()
	var copy := ELAutochessMatch.new()
	copy.auto_save = false
	check(copy.restore(profile, JSON.parse_string(JSON.stringify(game_match.snapshot()))) and _pool_ok(copy) and copy.companies[3].health == 1,
		"a save made during the battle restores within the pool (%s left)" % str(copy.companies[0].pool_left().get(line)))
	_finish_boards(game_match)
	check(int(human.pool_left()[line]) > 0, "the fallen company's creatures return to the pool once the round settles")
