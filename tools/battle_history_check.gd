extends SceneTree
## Headless check that the play history (ELBattleHistory) puts each play's
## outcomes on the right characters: every spell with a target is cast by
## the opposing hero on a small field, every hero ability is used, and the
## history card's touched characters and their health changes are compared
## with the rules' own damage, heal and death events for that play. The
## chosen target of a targeted spell must be listed, the caster's own hero
## only when the play touched it.
## Round markers follow the battle's round number and use attack-height tiles.
##
##   godot --headless --path game --script ../tools/battle_history_check.gd [-- --edition=el2] [-- --only=CARD]
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. Settings are never written.

var failures: Array[String] = []
var checked := 0
var only := ""
var editions := ["el1", "el2"]

func check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL: " + what)
		failures.append(what)

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): only = argument.substr(7)
		if argument.begins_with("--edition="): editions = [argument.substr(10)]
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in editions:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		await _edition(edition)
	print("BATTLE HISTORY: %d play(s) checked, %d failure(s)" % [checked, failures.size()])
	quit(0 if failures.is_empty() else 1)

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
	view.settings.values.hide_cast = false
	view.settings.values.battle_history = true
	view._start(edition)
	await _idle(view)
	_round_markers(view, edition)
	view._start(edition)
	await _idle(view)
	check(_round_titles(view.battle_history) == [view._t("Round %d") % 1], "%s: a new duel resets the round markers" % edition)
	var duel: ELDuel = view.duel
	var cards: Array = view.profile.table("CombatSpells").keys()
	cards.sort()
	for card: String in cards:
		if not only.is_empty() and card != only: continue
		var rule := ELCatalog.rule(view.profile, card)
		if rule.is_empty() or duel.is_summon(card) or duel.target_kind(card) == "none": continue
		if not rule.get("effect") in ["damage", "wave", "burn_mana", "heal", "drain_life", "drain_mana", "destroy", "enchant", "hero_heal", "life"] \
				and not String(rule.get("target", "")) in ["hero", "creature", "any"]: continue
		await _spell(view, edition, card)
	await _hero_abilities(view, edition)
	view.queue_free()
	await process_frame

func _round_markers(view: Node, edition: String) -> void:
	var duel: ELDuel = view.duel
	var history: ELBattleHistory = view.battle_history
	var label: String = view._t("Round %d")
	check(_round_titles(history) == [label % 1], "%s: the battle opens on round one" % edition)
	check(history._tile_height({"kind": "round"}) == history._tile_height({"kind": "attack"}), "%s: round markers keep the slim attack height" % edition)
	check(not history.has_current(), "%s: a round marker does not collect outcomes" % edition)
	check(duel.end_phase(), "%s: the opening side can pass" % edition)
	view._skip_battle_presentation()
	check(duel.round_number == 1 and _round_titles(history) == [label % 1], "%s: the opposing turn does not add a round marker" % edition)
	check(duel.end_phase(), "%s: the opposing side can pass" % edition)
	view._skip_battle_presentation()
	check(duel.round_number == 2 and _round_titles(history) == [label % 1, label % 2], "%s: the next round adds exactly one marker" % edition)
	var loaded := ELDuel.new()
	var document := {"format": "etherlords-duel", "version": 1, "state": duel.snapshot()}
	var restored := loaded.restore(duel.profile, document)
	check(restored, "%s: the second-round checkpoint loads (%s)" % [edition, loaded.error])
	if restored:
		view._start(edition, loaded.setup, loaded)
		check(_round_titles(history) == [label % 2], "%s: a freshly loaded duel opens at its saved round" % edition)

func _round_titles(history: ELBattleHistory) -> Array:
	return history.entries.filter(func(entry: Dictionary) -> bool: return entry.kind == "round").map(func(entry: Dictionary) -> String: return entry.title)

func _idle(view: Node) -> void:
	for i in 900:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() \
				and view._effect_cast.is_empty() and not view._shown_held() and not view.figures_turning(): return

## A fresh small field: two creatures a side, healthy heroes with some ether.
func _setup(view: Node) -> void:
	var duel: ELDuel = view.duel
	for id: int in duel.creatures.keys():
		duel.creatures.erase(id)
		view._remove_model(id)
	for side in 2:
		duel.heroes[side].health = 60
		duel.heroes[side].mana = 40
		duel.heroes[side].enchantments.clear()
	var summon := ""
	for card: String in view.profile.table("CombatCreatures"):
		if duel.is_summon(card) and ELCatalog.rule(view.profile, card).get("effect") == "summon" and view.profile.table("CombatCreatures")[card].get("Model", "") != "":
			summon = card
			break
	for side in 2:
		for n in 2:
			duel.cast_free(side, summon, [], false)
	for id: int in duel.creatures:
		var c: Dictionary = duel.creatures[id]
		c.base = [2, 5]
		c.sick = false
		c.resting = false
		duel._refresh_stats(c)
	for side in 2: duel.heroes[side].mana = 6
	await _idle(view)
	view.battle_history.close()

## The rules' outcomes in duel.history from `start`: {id: {delta, died}}.
func _outcomes(duel: ELDuel, start: int) -> Dictionary:
	var result := {}
	for i in range(start, duel.history.size()):
		var e: Dictionary = duel.history[i]
		var id := int(e.get("target", -1))
		if id < 0: continue
		match String(e.get("kind", "")):
			"damage":
				if not result.has(id): result[id] = {"delta": 0, "died": false}
				result[id].delta -= int(e.get("amount", 0))
			"heal":
				if not result.has(id): result[id] = {"delta": 0, "died": false}
				result[id].delta += int(e.get("amount", 0))
			"death", "exile":
				if not result.has(id): result[id] = {"delta": 0, "died": false}
				result[id].died = true
	return result

## What the history card shows: {id: {delta, died}}, the play's own
## character included.
func _shown(entry: Dictionary) -> Dictionary:
	var result := {}
	for target: Dictionary in entry.get("targets", []):
		result[int(target.id)] = {"delta": int(target.delta), "died": bool(target.died)}
	var source := int(entry.get("source", -1))
	if source >= 0 and (int(entry.get("source_delta", 0)) != 0 or entry.get("source_died", false)):
		result[source] = {"delta": int(entry.source_delta), "died": bool(entry.source_died), "on_source": true}
	return result

func _compare(what: String, expected: Dictionary, entry: Dictionary, must_list: Array) -> void:
	checked += 1
	var shown := _shown(entry)
	for id: int in expected:
		var want: Dictionary = expected[id]
		if int(want.delta) == 0 and not want.died: continue
		var got: Dictionary = shown.get(id, {})
		check(not got.is_empty(), "%s: character %d (health %+d%s) is not on the card (shown %s)" % [what, id, want.delta, ", died" if want.died else "", str(shown)])
		if got.is_empty(): continue
		check(int(got.delta) == int(want.delta), "%s: character %d shows %+d, the rules changed %+d" % [what, id, got.delta, want.delta])
		check(bool(got.died) == bool(want.died), "%s: character %d death shown %s, rules %s" % [what, id, got.died, want.died])
		check(not got.get("on_source", false) or entry.kind == "attack", "%s: character %d's change sits on the play's own picture, not as a target" % [what, id])
	for id: int in shown:
		if not expected.has(id) and (int(shown[id].delta) != 0 or shown[id].died):
			check(false, "%s: card shows %s on character %d, which the rules did not touch" % [what, str(shown[id]), id])
	for id: int in must_list:
		var listed := false
		for target: Dictionary in entry.get("targets", []): listed = listed or int(target.id) == id
		check(listed, "%s: the chosen target %d is not listed (listed %s)" % [what, id, str(entry.get("targets", []).map(func(t: Dictionary) -> int: return int(t.id)))])

func _spell(view: Node, edition: String, card: String) -> void:
	await _setup(view)
	var duel: ELDuel = view.duel
	var side := 1
	duel._acting = side
	var targets: Array[int] = duel.valid_targets(card)
	duel._acting = -1
	if targets.is_empty(): return
	# The opposing side's character first: the hero, else a creature.
	var target: int = targets[0]
	for t: int in targets:
		if t == 1 - side: target = t
	if target != 1 - side:
		for t: int in targets:
			if t >= 2 and duel.creatures.has(t) and int(duel.creatures[t].owner) != side:
				target = t
				break
	var start := duel.history.size()
	var before := _mark(view)
	if not duel.cast_free(side, card, [target], true):
		return
	await _idle(view)
	var entry := {}
	for i in range(_after(view, before), view.battle_history.entries.size()):
		var e: Dictionary = view.battle_history.entries[i]
		if e.kind == "cast" and e.get("card", "") == card: entry = e
	var what := "%s %s (%s) on %d" % [edition, card, duel.card_name(card), target]
	check(not entry.is_empty(), what + ": a history play was opened")
	if entry.is_empty(): return
	_compare(what, _outcomes(duel, start), entry, [target])

func _hero_abilities(view: Node, edition: String) -> void:
	var duel: ELDuel = view.duel
	var keys: Array = ELCatalog.HERO_ABILITIES.keys()
	keys.sort()
	for card: String in keys:
		if not only.is_empty() and card != only: continue
		if not view.profile.table("CombatSpells").has(card): continue
		var side := duel.active_side()
		await _setup(view)
		duel.cast_free(side, card, [side], false)
		await _idle(view)
		view.battle_history.close()
		for ability: Dictionary in duel.abilities(side):
			if ability.get("enchantment_card", "") != card: continue
			var key := String(ability.key)
			duel.heroes[side].mana = 6
			var start := duel.history.size()
			var before := _mark(view)
			var target := -1
			match String(ability.get("target", "none")):
				"creature":
					for id: int in duel.creatures:
						if int(duel.creatures[id].owner) == 1 - side: target = id
				"any", "hero": target = 1 - side
			if not duel.use_ability(side, key, target): continue
			await _idle(view)
			var entry := {}
			for i in range(_after(view, before), view.battle_history.entries.size()):
				if view.battle_history.entries[i].kind == "ability": entry = view.battle_history.entries[i]
			var what := "%s hero ability %s (%s)" % [edition, card, duel.card_name(card)]
			check(not entry.is_empty(), what + ": a history play was opened")
			if not entry.is_empty(): _compare(what, _outcomes(duel, start), entry, [target] if target >= 0 else [])

## The column keeps its last KEEP plays: new ones are found after the
## newest play before the action, not by count.
func _mark(view: Node) -> Dictionary:
	var entries: Array = view.battle_history.entries
	return entries.back() if not entries.is_empty() else {}

func _after(view: Node, mark: Dictionary) -> int:
	var entries: Array = view.battle_history.entries
	if mark.is_empty(): return 0
	for i in range(entries.size() - 1, -1, -1):
		if is_same(entries[i], mark): return i + 1
	return 0
