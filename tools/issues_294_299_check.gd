extends SceneTree
## Regression check for #294 and #299.
## - #294 (both games): a creature enchanted with Thief (THIF, granted
##   Discard) shows the robber icon over its figure, like a creature with its
##   own Discard(n); a plain creature does not.
## - #299 (second game): Blast (OBLS) plays Disenchant at its target only when
##   it removes an enchantment there, and OuterBlast only on a Pale target, as
##   the original's cast presentation does. A plain creature without
##   enchantments gets neither.
##
##   godot --headless --path game --script ../tools/issues_294_299_check.gd
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
	print("ISSUES 294/299: %d failure(s)" % failures)
	quit(int(failures > 0))

func _idle(view: Node) -> void:
	for i in 900:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() \
				and view._effect_cast.is_empty() and not view._shown_held() and not view.figures_turning(): return

func _card(view: Node) -> String:
	var duel: ELDuel = view.duel
	var table: Dictionary = view.profile.table("CombatCreatures")
	for card: String in ["ORSH", "GRSN"]:
		if table.has(card) and duel.is_summon(card): return card
	for card: String in table:
		if duel.is_summon(card) and ELCatalog.rule(view.profile, card).get("effect") == "summon" and table[card].get("Model", "") != "": return card
	return ""

func _creature(view: Node, side: int, card: String, flags: Array = []) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 40)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	for id: int in duel.creatures:
		if before.has(id): continue
		var c: Dictionary = duel.creatures[id]
		c.base = [2, 6]
		c.flags = c.flags.filter(func(flag: String) -> bool: return not flag.begins_with("Discard(") and flag != "Outerplanar")
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
	var card := _card(view)
	var robber: int = ELCombatSymbols.ICON_CODES[9]
	# #294: Thief's granted robbery shows its icon.
	var thief := await _creature(view, 0, card)
	var plain := await _creature(view, 0, card)
	check(thief >= 2 and plain >= 2, "%s: two creatures in play (%s)" % [edition, card])
	check(not view.creature_icons(thief).has(robber), "%s: no robber icon before Thief" % edition)
	check(duel.cast_free(0, "THIF", [thief], true), "%s: Thief is cast on the creature (%s)" % [edition, duel.error])
	await _idle(view)
	check(duel.creatures[thief].enchantments.any(func(e: Dictionary) -> bool: return e.card == "THIF"), "%s: Thief enchants the creature" % edition)
	check(view.creature_icons(thief).has(robber), "%s: the Thief creature shows the robber icon" % edition)
	var drawn: Array = []
	for figure: Dictionary in view.symbols.figures:
		if int(figure.get("id", -1)) == thief: drawn = figure.get("icons", [])
	if bool(view.settings.values.get("ability_icons", true)) and bool(view.settings.values.get("creature_numbers", true)):
		check(drawn.has(robber), "%s: the drawn icon row over the figure has the robber icon (%s)" % [edition, drawn])
	check(not view.creature_icons(plain).has(robber), "%s: a plain creature shows no robber icon" % edition)
	var own := await _creature(view, 0, card, ["Discard(1)"])
	check(view.creature_icons(own).has(robber), "%s: a creature with its own Discard(1) still shows the robber icon" % edition)
	if edition == "el2" and view.profile.table("CombatSpells").has("OBLS"):
		await _blast(view, card)
	view.queue_free()
	await process_frame
	await process_frame

## Casts Blast on `id` and returns the effect names it requested.
func _cast_blast(view: Node, id: int) -> Array:
	var duel: ELDuel = view.duel
	await _idle(view)
	view.effects.requested.clear()
	duel.heroes[1].mana = 40
	var ok := duel.cast_free(1, "OBLS", [id], true)
	check(ok, "el2: Blast is cast (%s)" % duel.error)
	await _idle(view)
	return view.effects.requested.duplicate()

func _blast(view: Node, card: String) -> void:
	var duel: ELDuel = view.duel
	# A plain creature without enchantments: neither effect.
	var bare := await _creature(view, 0, card)
	var names := await _cast_blast(view, bare)
	check(not names.has("Disenchant"), "el2: Blast on a plain creature without enchantments plays no Disenchant (%s)" % [names])
	check(not names.has("OuterBlast"), "el2: Blast on a plain creature plays no OuterBlast")
	# A plain enchanted creature: Disenchant only, and the enchantment goes.
	var enchanted := await _creature(view, 0, card)
	duel.cast_free(0, "THIF", [enchanted], true)
	await _idle(view)
	check(not duel.creatures[enchanted].enchantments.is_empty(), "el2: the second creature is enchanted")
	names = await _cast_blast(view, enchanted)
	check(duel.creatures[enchanted].enchantments.is_empty(), "el2: Blast removes the enchantment")
	check(names.has("Disenchant"), "el2: Blast on an enchanted creature plays Disenchant (%s)" % [names])
	check(not names.has("OuterBlast"), "el2: no OuterBlast on a creature that is not Pale")
	# A Pale creature without enchantments: OuterBlast only, and it takes 3.
	var pale := await _creature(view, 0, card, ["Outerplanar"])
	check(duel.pale(pale), "el2: the third creature is Pale")
	names = await _cast_blast(view, pale)
	check(not names.has("Disenchant"), "el2: no Disenchant on a Pale creature without enchantments (%s)" % [names])
	check(names.has("OuterBlast"), "el2: Blast on a Pale creature plays OuterBlast")
	check(duel.creatures.has(pale) and int(duel.creatures[pale].damage) == 3, "el2: the Pale creature takes 3 damage")
	# A Pale enchanted creature: both, Disenchant first.
	var both := await _creature(view, 0, card, ["Outerplanar"])
	duel.cast_free(0, "THIF", [both], true)
	await _idle(view)
	names = await _cast_blast(view, both)
	check(names.has("Disenchant") and names.has("OuterBlast") and names.find("Disenchant") < names.find("OuterBlast"),
		"el2: an enchanted Pale creature gets Disenchant, then OuterBlast (%s)" % [names])
