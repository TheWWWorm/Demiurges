extends SceneTree
## Headless check that the battle screen shows a delayed "displayed state":
## the rules settle a fight or a spell at once, but each shown value (hero
## health, ether and channels; creature power, toughness, damage and pale
## aspect) changes only when the event that caused it is presented, and
## matches the rules once the presentation is over:
## - a fight: a growing, life-draining attacker (Gray Snake when the game has
##   it) shows its old stats and the defending hero its old health until the
##   blow lands; the drained health reaches its hero only with the DrainLife
##   effect; the growth shows after the hit, never before it;
## - first strike: a first-striking attacker kills its blocker, which keeps
##   its numbers until that blow lands and never wounds the attacker;
## - regeneration: the ether a regenerating blocker's owner pays shows spent
##   only at the blow, and the blocker never dies on screen;
## - the end of the turn: wounds from an exchange show at its blows and clear
##   only once the turn's end is shown;
## - second game: a Pale attacker that dissipates shows in pale aspect only
##   after the blow that sends it to the Colourless Plane;
## - a creature enchantment with a hit cue changes the shown stats at its
##   hit, not at the cast;
## - tooltips and the hero panel read the displayed values while a sequence
##   plays; clicks on figures are gated meanwhile;
## - skipping (Space) jumps to the rules' values at once.
##
##   godot --headless --path game --script ../tools/battle_display_check.gd
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. Settings are never written.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		await _edition(edition)
	print("BATTLE DISPLAY: %d failure(s)" % failures.size())
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
	view._start(edition)
	await _idle(view)
	await _growth_and_drain(view, edition)
	await _first_strike(view, edition)
	await _regeneration(view, edition)
	await _turn_end(view, edition)
	if edition == "el2": await _pale(view, edition)
	await _spell_stats(view, edition)
	await _skip(view, edition)
	view.queue_free()
	await process_frame
	await process_frame

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 900:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() \
				and view._effect_cast.is_empty() and not view._shown_held(): return

func _card(view: Node, wanted: Array) -> String:
	var duel: ELDuel = view.duel
	wanted = wanted + ["GRSN"]
	var table: Dictionary = view.profile.table("CombatCreatures")
	for card: String in wanted:
		if table.has(card) and duel.is_summon(card): return card
	for card: String in table:
		if duel.is_summon(card) and ELCatalog.rule(view.profile, card).get("effect") == "summon" and table[card].get("Model", "") != "": return card
	return ""

## A fresh creature of `card` on `side`, ready to act, with the given stats
## and extra flags.
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

## Removes every creature, so each case starts on an empty field.
func _clear(view: Node) -> void:
	var duel: ELDuel = view.duel
	for id: int in duel.creatures.keys():
		duel.creatures.erase(id)
		view._remove_model(id)
	for side in 2:
		duel.heroes[side].health = 30
		duel.heroes[side].mana = 40
	await _idle(view)

## Brings `side`'s attack phase.
func _attack_turn(view: Node, side: int) -> void:
	var duel: ELDuel = view.duel
	for i in 6:
		if duel.attacker == side and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
		await _idle(view)

func _plane(view: Node, id: int) -> bool:
	if view.has_method("shown_plane"): return view.call("shown_plane", id)
	return view.duel.in_plane(id)

## Displayed and rules values of the heroes and the given creatures.
func _shown(view: Node, ids: Array) -> Dictionary:
	var out := {"heroes": [], "creatures": {}}
	# A build without the displayed ether or pale aspect shows the rules' values.
	for side in 2:
		var hero: Dictionary = view.duel.heroes[side]
		out.heroes.append([view.shown_health(side), view.call("shown_ether", side) if view.has_method("shown_ether") else int(hero.mana),
			view.call("shown_channels", side) if view.has_method("shown_channels") else int(hero.channels)])
	for id: int in ids:
		var c: Dictionary = view.duel.creatures.get(id, view._last_creature.get(id, {}))
		var stats: Dictionary = view._shown_creature_stats(id, c)
		out.creatures[id] = [int(stats.get("power", 0)), int(stats.get("toughness", 0)), view.shown_damage(id), _plane(view, id)]
	return out

func _live(view: Node, ids: Array) -> Dictionary:
	var duel: ELDuel = view.duel
	var out := {"heroes": [], "creatures": {}}
	for side in 2: out.heroes.append([int(duel.heroes[side].health), int(duel.heroes[side].mana), int(duel.heroes[side].channels)])
	for id: int in ids:
		if duel.creatures.has(id):
			var c: Dictionary = duel.creatures[id]
			out.creatures[id] = [int(c.power), int(c.toughness), int(c.damage), duel.in_plane(id)]
	return out

## Steps frames until the presentation is over, sampling the displayed values
## with the number of blows shown so far and the seconds since `start`.
func _watch(view: Node, ids: Array, start: int) -> Array:
	var samples: Array = []
	for i in 1500:
		view.ai_clock = -1000.0
		await process_frame
		samples.append({"t": (Time.get_ticks_usec() - start) / 1000000.0, "blows": int(view.melee._next_blow) if view._melee_busy() else 999,
			"shown": _shown(view, ids), "standing": ids.filter(func(id: int) -> bool:
				return view.models.has(id) and not bool(view.models[id].get_meta("dying", false)) and (not is_instance_valid(view.symbols) or not view.figure_rows(id).is_empty()))})
		if not view._shown_held() and not view._melee_busy() and view._cast_queue.is_empty() and view._hits_waiting.is_empty(): break
	await _idle(view)
	return samples

## First sample time at which `pick` (sample -> value) differs from `before`.
func _changed_at(samples: Array, before: Variant, pick: Callable) -> Dictionary:
	for sample: Dictionary in samples:
		if pick.call(sample.shown) != before: return sample
	return {}

func _growth_and_drain(view: Node, edition: String) -> void:
	await _clear(view)
	var duel: ELDuel = view.duel
	var side: int = duel.active_side()
	await _attack_turn(view, side)
	side = duel.attacker
	var foe := 1 - side
	var card := _card(view, ["GRSN"])
	var attacker := await _creature(view, side, card, 3, 4, ["Lifetap"])
	check(attacker >= 2, "%s fight: an attacker (%s) stands ready" % [edition, card])
	if attacker < 2: return
	duel.heroes[side].health = 20
	await _idle(view)
	var before := _shown(view, [attacker])
	check(duel.toggle_attack(attacker), "%s fight: the attack is declared (%s)" % [edition, duel.error])
	await _idle(view)
	before = _shown(view, [attacker])
	var start := Time.get_ticks_usec()
	duel.end_phase()
	if duel.phase == ELDuel.Phase.DEFENCE: duel.end_phase()
	var live := _live(view, [attacker])
	check(int(live.heroes[foe][0]) < int(before.heroes[foe][0]), "%s fight: the rules settle the blow on the hero at once" % edition)
	check(int(live.heroes[side][0]) > int(before.heroes[side][0]), "%s fight: the rules settle the life drain at once" % edition)
	var grows := card == "GRSN"
	if grows: check(int(live.creatures[attacker][0]) > int(before.creatures[attacker][0]), "%s fight: the rules grow the snake at once" % edition)
	var now := _shown(view, [attacker])
	check(now == before, "%s fight: right after the rules settle it the screen still shows the old values (%s, rules %s)" % [edition, now, live])
	var hero_tip := str(view._hero_tip(foe))
	check(hero_tip.contains(": %d" % before.heroes[foe][0]) and not hero_tip.contains(": %d" % live.heroes[foe][0]), "%s fight: the hero tooltip reads the shown health" % edition)
	var panel_ok := false
	view._show_hero_stats()
	panel_ok = view.hero_values.size() < 2 or String(view.hero_values[foe].text).begins_with("%d " % before.heroes[foe][0])
	check(panel_ok, "%s fight: the hero panel shows the shown health" % edition)
	var tip: String = view._creature_tip_text(attacker)
	check(tip.contains("%d/%d" % [before.creatures[attacker][0], before.creatures[attacker][1]]), "%s fight: the creature tooltip reads the shown stats (%s)" % [edition, tip.get_slice("\n", 0)])
	var samples := await _watch(view, [attacker], start)
	var hit := _changed_at(samples, before.heroes[foe][0], func(s: Dictionary) -> int: return s.heroes[foe][0])
	var heal := _changed_at(samples, before.heroes[side][0], func(s: Dictionary) -> int: return s.heroes[side][0])
	var growth := _changed_at(samples, before.creatures[attacker][0], func(s: Dictionary) -> int: return s.creatures[attacker][0])
	var early := samples.filter(func(s: Dictionary) -> bool: return int(s.blows) == 0 and s.shown != before)
	check(early.is_empty(), "%s fight: nothing shown changes before the blow lands (%d early frames)" % [edition, early.size()])
	check(not hit.is_empty() and int(hit.blows) >= 1, "%s fight: the hero's health drops when the blow lands" % edition)
	check(not heal.is_empty() and not hit.is_empty() and float(heal.t) >= float(hit.t), "%s fight: the drained health shows after the blow (%.2f s vs %.2f s)" % [edition, float(heal.get("t", -1)), float(hit.get("t", -1))])
	var drain: float = view.call("_drain_seconds") if view.has_method("_drain_seconds") else 0.0
	if drain > 0.0 and not heal.is_empty() and not hit.is_empty():
		check(float(heal.t) - float(hit.t) >= drain - 0.05, "%s fight: the drained health reaches its hero with DrainLife (%.2f s after the hit, effect %.2f s)" % [edition, float(heal.t) - float(hit.t), drain])
	if grows:
		check(not growth.is_empty() and not hit.is_empty() and float(growth.t) >= float(hit.t), "%s fight: the snake's growth shows after its hit, not before" % edition)
	check(_shown(view, [attacker]) == _live(view, [attacker]), "%s fight: the shown values match the rules afterwards" % edition)

## A blocked fight between a fresh attacker and blocker; returns the samples
## and the values shown before it, or {} when the block cannot be set.
func _blocked_fight(view: Node, what: String, attacker_stats: Array, blocker_stats: Array) -> Dictionary:
	await _clear(view)
	var duel: ELDuel = view.duel
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	var card := _card(view, [])
	var attacker := await _creature(view, side, card, int(attacker_stats[0]), int(attacker_stats[1]), attacker_stats.slice(2))
	var blocker := await _creature(view, 1 - side, card, int(blocker_stats[0]), int(blocker_stats[1]), blocker_stats.slice(2))
	if attacker < 2 or blocker < 2 or not duel.toggle_attack(attacker):
		check(false, "%s: attacker and blocker stand (%s)" % [what, duel.error])
		return {}
	duel.end_phase()
	await _idle(view)
	if not duel.assign_block(blocker, attacker):
		check(false, "%s: the block is assigned (%s)" % [what, duel.error])
		return {}
	await _idle(view)
	var ids := [attacker, blocker]
	var before := _shown(view, ids)
	var start := Time.get_ticks_usec()
	duel.end_phase()
	var settled := _live(view, ids)
	var samples := await _watch(view, ids, start)
	var early := samples.filter(func(s: Dictionary) -> bool: return int(s.blows) == 0 and s.shown != before)
	check(not samples.is_empty() and early.is_empty(), "%s: nothing shown changes before the first blow lands (%d early frames)" % [what, early.size()])
	return {"attacker": attacker, "blocker": blocker, "side": side, "before": before, "settled": settled, "samples": samples, "ids": ids}

func _first_strike(view: Node, edition: String) -> void:
	var what := "%s first strike" % edition
	var fight := await _blocked_fight(view, what, [3, 5, "FS"], [2, 2])
	if fight.is_empty(): return
	var duel: ELDuel = view.duel
	check(not duel.creatures.has(fight.blocker), "%s: the rules kill the blocker at once" % what)
	var samples: Array = fight.samples
	var blocker: int = fight.blocker
	var attacker: int = fight.attacker
	var standing := samples.filter(func(s: Dictionary) -> bool: return int(s.blows) == 0 and s.standing.has(blocker))
	var fell := samples.filter(func(s: Dictionary) -> bool: return int(s.blows) == 0 and not s.standing.has(blocker))
	check(not standing.is_empty() and fell.is_empty(), "%s: the doomed blocker stands with its numbers until the first strike lands" % what)
	var wounded := samples.filter(func(s: Dictionary) -> bool: return int(s.shown.creatures[attacker][2]) > 0)
	check(wounded.is_empty(), "%s: the first striker is never shown wounded (its victim never strikes back)" % what)

func _regeneration(view: Node, edition: String) -> void:
	var what := "%s regeneration" % edition
	var fight := await _blocked_fight(view, what, [4, 6], [1, 3, "Regen(1)"])
	if fight.is_empty(): return
	var duel: ELDuel = view.duel
	var blocker: int = fight.blocker
	var owner := 1 - int(fight.side)
	var regenerated: bool = duel.creatures.has(blocker) and duel.history.any(func(e: Dictionary) -> bool: return e.get("kind") == "regenerate" and int(e.get("target", -1)) == blocker)
	check(regenerated, "%s: the rules regenerate the blocker at once" % what)
	var paid := int(fight.before.heroes[owner][1]) > int(fight.settled.heroes[owner][1])
	check(paid, "%s: the rules charge its ether at once" % what)
	var spent := _changed_at(fight.samples, fight.before.heroes[owner][1], func(s: Dictionary) -> int: return s.heroes[owner][1])
	check(not spent.is_empty() and int(spent.blows) >= 1, "%s: the regeneration's ether shows spent only when the blow is shown" % what)
	var dead: Array = fight.samples.filter(func(s: Dictionary) -> bool: return not s.standing.has(blocker))
	check(dead.is_empty(), "%s: the regenerated blocker never dies on screen" % what)
	check(_shown(view, fight.ids) == _live(view, fight.ids), "%s: the shown values match the rules afterwards" % what)

func _turn_end(view: Node, edition: String) -> void:
	var what := "%s turn end" % edition
	var fight := await _blocked_fight(view, what, [3, 6], [2, 7])
	if fight.is_empty(): return
	var attacker: int = fight.attacker
	var blocker: int = fight.blocker
	check(int(fight.settled.creatures[attacker][2]) == 0 and int(fight.settled.creatures[blocker][2]) == 0, "%s: the turn's end has already healed both in the rules" % what)
	var hurt: Dictionary = _changed_at(fight.samples, 0, func(s: Dictionary) -> int: return s.creatures[blocker][2])
	check(not hurt.is_empty() and int(hurt.blows) >= 1, "%s: the blocker's wound shows when the blow lands" % what)
	var both: Array = fight.samples.filter(func(s: Dictionary) -> bool: return int(s.shown.creatures[attacker][2]) > 0 and int(s.shown.creatures[blocker][2]) > 0)
	check(not both.is_empty(), "%s: both wounds show after the exchange, before the turn's end heals them" % what)
	check(_shown(view, fight.ids) == _live(view, fight.ids), "%s: the wounds are gone once the turn's end is shown" % what)

func _pale(view: Node, edition: String) -> void:
	await _clear(view)
	var duel: ELDuel = view.duel
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	var card := _card(view, [])
	var attacker := await _creature(view, side, card, 1, 2, ["Outerplanar"])
	var blocker := await _creature(view, 1 - side, card, 5, 8)
	if attacker < 2 or blocker < 2:
		check(false, "%s pale: creatures stand" % edition)
		return
	duel.toggle_attack(attacker)
	duel.end_phase()
	await _idle(view)
	duel.assign_block(blocker, attacker)
	await _idle(view)
	var ids := [attacker, blocker]
	var before := _shown(view, ids)
	var start := Time.get_ticks_usec()
	duel.end_phase()
	check(duel.in_plane(attacker), "%s pale: the rules send the dissipating attacker to the Colourless Plane at once" % edition)
	check(not _plane(view, attacker), "%s pale: the screen does not show it pale yet" % edition)
	view._refresh()
	check(not bool(view.models[attacker].get_meta("pale", false)), "%s pale: its figure is not faded yet" % edition)
	var samples := await _watch(view, ids, start)
	var faded := _changed_at(samples, false, func(s: Dictionary) -> bool: return bool(s.creatures[attacker][3]))
	check(not faded.is_empty() and int(faded.blows) >= 1, "%s pale: it shows pale once the blow that dissipates it lands" % edition)
	check(_plane(view, attacker) and bool(view.models[attacker].get_meta("pale", false)), "%s pale: it stays pale afterwards" % edition)

func _spell_stats(view: Node, edition: String) -> void:
	await _clear(view)
	var duel: ELDuel = view.duel
	var side: int = duel.active_side()
	var target := await _creature(view, side, _card(view, []), 2, 2)
	if target < 2:
		check(false, "%s spell: a creature stands" % edition)
		return
	var spell := ""
	for card: String in view.profile.table("CombatSpells"):
		var rule := ELCatalog.rule(view.profile, card)
		if rule.get("effect") != "enchant" or rule.get("target") != "creature" or int(rule.get("power", 0)) == 0: continue
		if view._cast_release(side, card) + ELCombatEffects.hit_delay(view.profile, card) > 0.15:
			spell = card
			break
	check(not spell.is_empty(), "%s spell: a creature enchantment with a hit cue exists" % edition)
	if spell.is_empty(): return
	var ids := [target]
	var before := _shown(view, ids)
	var start := Time.get_ticks_usec()
	check(duel.cast_free(side, spell, [target], true), "%s spell: %s is cast (%s)" % [edition, spell, duel.error])
	var hit := float(view._effect_cast.get("hit", 0.0))
	check(int(_live(view, ids).creatures[target][0]) != int(before.creatures[target][0]), "%s spell: the rules change the stats at once" % edition)
	check(view.has_method("_display_lagging") and view.call("_display_lagging"), "%s spell: clicks on figures are held while the change waits" % edition)
	var samples := await _watch(view, ids, start)
	var shown := _changed_at(samples, before.creatures[target][0], func(s: Dictionary) -> int: return s.creatures[target][0])
	check(not shown.is_empty() and float(shown.t) >= hit - 0.03, "%s spell: %s's stats show at its hit (%.2f s), not at the cast (shown at %.2f s)" % [edition, spell, hit, float(shown.get("t", -1))])
	check(_shown(view, ids) == _live(view, ids), "%s spell: the shown stats match the rules afterwards" % edition)

func _skip(view: Node, edition: String) -> void:
	await _clear(view)
	var duel: ELDuel = view.duel
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	var card := _card(view, ["GRSN"])
	var attacker := await _creature(view, side, card, 3, 4, ["Lifetap"])
	if attacker < 2: return
	duel.toggle_attack(attacker)
	await _idle(view)
	duel.end_phase()
	if duel.phase == ELDuel.Phase.DEFENCE: duel.end_phase()
	for i in 3:
		view.ai_clock = -1000.0
		await process_frame
	check(_shown(view, [attacker]) != _live(view, [attacker]) or not view._melee_busy(), "%s skip: the fight is still being shown" % edition)
	view._skip_battle_presentation()
	check(_shown(view, [attacker]) == _live(view, [attacker]), "%s skip: Space jumps to the rules' values at once" % edition)
	await _idle(view)
