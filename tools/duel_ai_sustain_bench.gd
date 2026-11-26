extends SceneTree
## Evil Dale opening against a scripted Lesser Healing / Weird Exchange deck.
##   godot --headless --path game --script ../tools/duel_ai_sustain_bench.gd -- \
##       [--el1=<folder>] [--seed=101] [--seeds=24] [--budget=350000] [--force-summons]
## Use the same seeds and node budget to compare policies or revisions.
## Green exchanges its first creature for Blue's first, builds healing, blocks
## incoming attackers and sends its own attackers when Blue's board is empty.

const GREEN := ["SPFG", "SPFG", "SPFG", "LSHE", "TIWR", "TIWR", "TIWR", "LSHE",
	"TRAD", "TRAD", "LSHE", "LSHE", "MNTP", "MNTP", "MNTP"]
const CHARGES := [-1, -1, -1, 7, -1, -1, -1, 8, 8, 7, 8, 7, 8, 8, 8]

func _arg(name: String, fallback: String) -> String:
	var prefix := "--" + name + "="
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return arg.trim_prefix(prefix)
	return fallback

func _initialize() -> void:
	var folder := _arg("el1", "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get("el1", ""))
	var profile := ELProfile.new()
	if folder.is_empty() or not profile.mount("el1", folder):
		printerr("Pass --el1=<Etherlords folder>.")
		quit(1)
		return
	var green := {"hero": "BLevStartHero", "faction": "Green", "level": 7, "health": 27,
		"specialization": "RVVE", "skills": {"PRVD": 2}, "cards": GREEN, "rune_uses": CHARGES}
	var blue := {"hero": "BLevHero3", "faction": "Blue", "level": 8, "health": 31,
		"specialization": "MSEN", "skills": {"CONC": 0, "MSTR": 2, "SUPR": 2},
		"deck": "BLV3", "rune_uses": ELCatalog.deck_uses(profile, "BLV3")}
	var options := {"adventure": true, "arena": "Blue.002", "first_side": 1, "players": [green, blue]}
	var first := int(_arg("seed", "101"))
	var seeds := int(_arg("seeds", "24"))
	var force_summons := OS.get_cmdline_user_args().has("--force-summons")
	ELCombatSearch.smart_engine_budget = int(_arg("budget", "350000"))
	ELCombatSearch.smart_engine_ms = 0
	if seeds <= 0 or ELCombatSearch.smart_engine_budget <= 0:
		printerr("--seeds and --budget must be positive.")
		quit(1)
		return
	var wins := 0
	for seed_value in range(first, first + seeds):
		var duel := ELDuel.new()
		if not duel.start(profile, seed_value, options):
			printerr(duel.error)
			quit(1)
			return
		duel.smart_sides = [1]
		var summons := 0
		for step in 4000:
			if duel.phase == ELDuel.Phase.FINISHED: break
			if duel.active_side() == 0:
				if not _green_move(duel): duel.end_phase()
				continue
			var before := duel.army(1).size()
			var elemental: int = duel.heroes[1].hand.find("WTEL")
			if force_summons and elemental >= 0 and duel.can_cast_from_hand(elemental) and duel.cast(elemental):
				summons += 1
				continue
			ELPracticeAI.step(duel)
			if duel.army(1).size() > before: summons += 1
		if duel.phase != ELDuel.Phase.FINISHED:
			printerr("Unfinished duel at seed %d" % seed_value)
			quit(1)
			return
		if duel.winner == 1: wins += 1
		print("GAME seed=%d winner=%d round=%d summons=%d" % [seed_value, duel.winner, duel.round_number, summons])
	print("Valaddin won %d/%d" % [wins, seeds])
	quit()

func _green_move(duel: ELDuel) -> bool:
	var allies := duel.army(0)
	var enemies := duel.army(1)
	var hand: Array = duel.heroes[0].hand
	for card: String in ["TRAD", "MNTP", "LSHE", "SPFG", "TIWR"]:
		var index := hand.find(card)
		if index < 0: continue
		if card == "TRAD":
			if not allies.is_empty() and not enemies.is_empty() and duel.cast(index, allies[0].id, enemies[0].id): return true
		elif duel.can_cast_from_hand(index) and duel.cast(index): return true
	for ability: Dictionary in duel.abilities(0):
		if ability.effect == "heal" and duel.can_use_ability(0, ability.key): return duel.use_ability(0, ability.key)
	if duel.phase == ELDuel.Phase.ATTACK:
		if enemies.is_empty():
			for c: Dictionary in allies:
				if not duel.attacks.has(c.id) and duel.can_declare_attack(c.id): return duel.toggle_attack(c.id)
	else:
		for attacker: int in duel.attacks:
			if duel.blocks.values().has(attacker): continue
			for c: Dictionary in allies:
				if not duel.blocks.has(c.id) and duel.block_problem(c.id, attacker).is_empty(): return duel.assign_block(c.id, attacker)
	return false
