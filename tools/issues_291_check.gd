extends SceneTree
## Regression check for #291: a declared attacker with regeneration that takes
## lethal damage in the defence phase and regenerates walks back to its home
## (rear-line) slot in both games. The first game's rules keep it declared (it
## no longer fights); the second game withdraws it. A declared attacker that
## did not regenerate stays on the front line, and after combat both figures
## stand at home.
##
##   godot --headless --path game --script ../tools/issues_291_check.gd
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. Settings are never written.

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		await _edition(edition)
	print("ISSUE 291: %d failure(s)" % failures)
	quit(int(failures > 0))

func _idle(view: Node) -> void:
	for i in 900:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() \
				and view._effect_cast.is_empty() and not view._shown_held() and not view.figures_turning(): return

## Waits until the figures have finished walking.
func _settle(view: Node, ids: Array) -> void:
	await _idle(view)
	for i in 900:
		await process_frame
		if not view.melee.busy() and not ids.any(func(id: int) -> bool: return view.melee.moving(id)): return

func _card(view: Node) -> String:
	var duel: ELDuel = view.duel
	var table: Dictionary = view.profile.table("CombatCreatures")
	for card: String in ["ORSH", "GRSN"]:
		if table.has(card) and duel.is_summon(card): return card
	for card: String in table:
		if duel.is_summon(card) and ELCatalog.rule(view.profile, card).get("effect") == "summon" and table[card].get("Model", "") != "": return card
	return ""

func _creature(view: Node, side: int, card: String, power: int, toughness: int, flags: Array = []) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 40)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	for id: int in duel.creatures:
		if before.has(id): continue
		var c: Dictionary = duel.creatures[id]
		c.base = [power, toughness]
		for flag: String in flags:
			if not c.flags.has(flag): c.flags.append(flag)
		c.sick = false
		c.resting = false
		duel._refresh_stats(c)
		await _idle(view)
		return id
	return -1

func _edition(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		print("SKIP: %s files could not be mounted" % edition)
		view.queue_free()
		await process_frame
		return
	view._start(edition)
	await _idle(view)
	var duel: ELDuel = view.duel
	for id: int in duel.creatures.keys():
		duel.creatures.erase(id)
		view._remove_model(id)
	for side in 2:
		duel.heroes[side].health = 30
		duel.heroes[side].mana = 40
	await _idle(view)
	for i in 6:
		if duel.attacker == 1 and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
		await _idle(view)
	var card := _card(view)
	var regen := await _creature(view, 1, card, 2, 3, ["Regen(1)"])
	var plain := await _creature(view, 1, card, 2, 3)
	if regen < 2 or plain < 2 or not duel.toggle_attack(regen) or not duel.toggle_attack(plain):
		check(false, "%s: two attackers declared (%s)" % [edition, duel.error])
		view.queue_free()
		await process_frame
		return
	duel.end_phase()
	await _settle(view, [regen, plain])
	check(duel.phase == ELDuel.Phase.DEFENCE, "%s: the defence phase begins" % edition)
	check(view.melee.away(regen) and view.melee.away(plain), "%s: both attackers stand on the front line" % edition)
	# Lethal damage in the defence phase; the attacker's owner pays to regenerate.
	duel._damage(regen, 10)
	await _settle(view, [regen, plain])
	check(duel.creatures.has(regen) and duel.creatures[regen].regenerated, "%s: the rules regenerate the attacker" % edition)
	check(duel.attacks.has(regen) == (edition == "el1"), "%s: the rules %s the regenerated attacker" % [edition, "keep declared" if edition == "el1" else "withdraw"])
	check(not view.melee.away(regen), "%s: the regenerated attacker's figure is back at its home slot" % edition)
	check(view.melee.away(plain), "%s: the other attacker stays on the front line" % edition)
	duel.end_phase()
	await _settle(view, [regen, plain])
	check(duel.attacks.is_empty(), "%s: combat is over" % edition)
	check(not view.melee.away(regen) and not view.melee.away(plain), "%s: both figures stand at home after combat" % edition)
	check(view.regenerated_home.is_empty(), "%s: nothing is held home once the attack is over" % edition)
	view.queue_free()
	await process_frame
	await process_frame
