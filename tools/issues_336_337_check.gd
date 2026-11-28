extends SceneTree
## Regression check for #336 and #337, both games, as the originals play them:
##
## - #336 Twisted Enhancement (TWEN, +2/+2): the point of power and health it
##   wears off at each end of its holder's turn comes off the creature itself.
##   A dispel takes only the +2/+2 away, so the creature keeps what it lost:
##   a 2/2 enhanced to 4/4 and dispelled after one decay is 1/1, after two it
##   dies; a 5/4 after two decays is 3/2 once dispelled. The loss counts below
##   the floor of one: an enhanced 2/2 at 3/3 dies to Weakness (-4/-4).
## - #337 the lasting marks creatures leave (a grass snake's growth on a hit
##   hero, a lake snake's -1/-1 on a creature it strikes, a Colourless
##   Devourer's growth from its prey) change the stats and nothing removes
##   them, and the enchantment strip shows no icon for them. Spell
##   enchantments and snake venom, which a dispel can take off, are listed.
##
##   godot --headless --path game --script ../tools/issues_336_337_check.gd [-- --shots=<folder>]
##
## With --shots (and a window, not --headless) the strip of each marked
## creature is saved as a PNG. Needs the games' files (user://profiles.json);
## a game without them is skipped. Settings are never written.

var failures := 0
var shots := ""

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	root.size = Vector2i(1440, 900)
	await process_frame
	for edition: String in ["el1", "el2"]:
		await _edition(edition)
	print("ISSUES 336 337: %d failure(s)" % failures)
	quit(int(failures > 0))

func _edition(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		print("SKIP: no %s files configured" % edition)
		view.queue_free()
		await frames(2)
		return
	var profile: ELProfile = view.profiles[edition]
	_twisted(profile, edition)
	_marks(profile, edition)
	await _strip(view, profile, edition)
	view.queue_free()
	await frames(2)

# --- rules -----------------------------------------------------------------

## A duel with no creatures, side 0 in its attack phase, heroes at 30 health
## and 40 ether, without specialisations (no mastery rolls).
func _duel(profile: ELProfile) -> ELDuel:
	var duel := ELDuel.new()
	duel.start(profile, 7, {})
	for id: int in duel.creatures.keys(): duel.creatures.erase(id)
	_turn(duel, 0)
	for hero: Dictionary in duel.heroes:
		hero.hand = []
		hero.hand_slots = []
		hero.hand_view = []
		hero.enchantments = []
		hero.spec = "NONE"
		hero.skills = {}
	_refill(duel)
	return duel

func _refill(duel: ELDuel) -> void:
	for hero: Dictionary in duel.heroes:
		hero.health = 30
		hero.maximum = maxi(int(hero.get("maximum", 30)), 30)
		hero.mana = 40

## Ends phases until `side` acts in its attack phase.
func _turn(duel: ELDuel, side: int) -> void:
	for i in 8:
		if duel.active_side() == side and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
	_refill(duel)

func _summoned(duel: ELDuel, side: int, card: String) -> int:
	var known := duel.creatures.keys()
	duel._summon(side, card)
	for key: int in duel.creatures:
		if not known.has(key):
			duel.creatures[key].sick = false
			duel.creatures[key].resting = false
			return key
	return -1

func _cast(duel: ELDuel, card: String, target := -1, enchantment := -1) -> bool:
	var side := duel.active_side()
	duel._give_card(side, card)
	return duel.cast(duel.heroes[side].hand.size() - 1, target, enchantment)

func _stats(duel: ELDuel, id: int) -> String:
	return "%d/%d" % [duel.creatures[id].power, duel.creatures[id].toughness] if duel.creatures.has(id) else "dead"

func _enchantment(duel: ELDuel, id: int, card: String) -> int:
	if not duel.creatures.has(id): return -1
	for e: Dictionary in duel.creatures[id].enchantments:
		if e.card == card: return int(e.id)
	return -1

## Side 0's `card` gets Twisted Enhancement, decays `decays` times at side 0's
## turn ends, then side 0 casts `after` on it (a dispel aims at the TWEN).
func _twisted_case(profile: ELProfile, edition: String, card: String, decays: int, after: String, expect: String) -> void:
	var duel := _duel(profile)
	var id := _summoned(duel, 0, card)
	_summoned(duel, 1, "TIWR")
	if not _cast(duel, "TWEN", id):
		check(false, "%s: Twisted Enhancement is cast on %s (%s)" % [edition, card, duel.error])
		return
	var steps := PackedStringArray([_stats(duel, id)])
	for i in decays:
		_turn(duel, 1)
		_turn(duel, 0)
		steps.append(_stats(duel, id))
	var ok := true
	for spell: String in after.split(",", false):
		if not duel.creatures.has(id): break
		var dispel: bool = ELCatalog.rule(profile, spell).get("target") == "enchantment"
		ok = ok and (_cast(duel, spell, id, _enchantment(duel, id, "TWEN")) if dispel else _cast(duel, spell, id))
		steps.append(spell + " " + _stats(duel, id))
	check(ok and _stats(duel, id) == expect and _enchantment(duel, id, "TWEN") < 0 if after.contains("PRFY") else ok and _stats(duel, id) == expect,
		"%s #336: %s with Twisted Enhancement, %d decay(s), then %s: %s (expected %s; %s)" % [edition, card, decays, after, _stats(duel, id), expect, " > ".join(steps)])

func _twisted(profile: ELProfile, edition: String) -> void:
	# The same outcomes as the original games' combat code (1.01 executables).
	_twisted_case(profile, edition, "TIWR", 0, "PRFY", "2/2")
	_twisted_case(profile, edition, "TIWR", 1, "PRFY", "1/1")
	_twisted_case(profile, edition, "TIWR", 2, "PRFY", "dead")
	_twisted_case(profile, edition, "GBAT", 1, "PRFY", "4/3")
	_twisted_case(profile, edition, "GBAT", 2, "PRFY", "3/2")
	_twisted_case(profile, edition, "TIWR", 1, "WEAK", "dead")
	_twisted_case(profile, edition, "TIWR", 1, "PRFY,WEAK", "dead")
	_twisted_case(profile, edition, "TIWR", 1, "PRFY,BLSS", "5/5")
	_twisted_case(profile, edition, "TIWR", 2, "BLSS,PRFY", "4/4")
	# A saved game keeps what the enhancement wore off.
	var duel := _duel(profile)
	var id := _summoned(duel, 0, "TIWR")
	_cast(duel, "TWEN", id)
	_turn(duel, 1)
	_turn(duel, 0)
	var restored := ELDuel.new()
	var loaded := restored.restore(profile, {"format": "etherlords-duel", "version": 1, "state": duel.snapshot()})
	check(loaded and restored.creatures.has(id) and int(restored.creatures[id].get("twisted", 0)) == 1 and _stats(restored, id) == "3/3",
		"%s #336: a loaded game keeps the decay (%s)" % [edition, _stats(restored, id) if loaded else restored.error])
	if loaded:
		_cast(restored, "PRFY", id, _enchantment(restored, id, "TWEN"))
		check(_stats(restored, id) == "1/1", "%s #336: and a dispel after loading leaves 1/1 (%s)" % [edition, _stats(restored, id)])

## Side 0's attacker strikes: unblocked at the hero, or blocked by `blocker`.
func _fight(duel: ELDuel, attacker: int, blocker := -1) -> void:
	duel.toggle_attack(attacker)
	duel.end_phase()
	if blocker >= 0: duel.assign_block(blocker, attacker)
	duel.end_phase()

func _marks(profile: ELProfile, edition: String) -> void:
	var duel := _duel(profile)
	var snake := _summoned(duel, 0, "GRSN")
	_fight(duel, snake)
	var growth: Array = duel.creatures[snake].enchantments.filter(func(e: Dictionary) -> bool: return e.card == "GRSN") if duel.creatures.has(snake) else []
	check(growth.size() == 1 and _stats(duel, snake) == "2/2" and not duel.dispellable(snake, growth[0]),
		"%s #337: a grass snake that hits the hero grows to 2/2 and nothing removes it (%s)" % [edition, _stats(duel, snake)])
	duel = _duel(profile)
	var lake := _summoned(duel, 0, "LASN")
	var wall := _summoned(duel, 1, "WLDT")
	_fight(duel, lake, wall)
	var weak: Array = duel.creatures[wall].enchantments.filter(func(e: Dictionary) -> bool: return e.card == "LASN") if duel.creatures.has(wall) else []
	check(weak.size() == 1 and _stats(duel, wall) == "0/7" and not duel.dispellable(wall, weak[0]),
		"%s #337: a lake snake's strike leaves its blocker at 0/7 for good (%s)" % [edition, _stats(duel, wall)])

# --- the strip ---------------------------------------------------------------

func _listed(view: Node, subject: int) -> Array:
	view.selected_creature = subject
	view._fill_strip()
	return view.rail.strip.items.filter(func(item: Dictionary) -> bool: return item.meta.has("enchantment")).map(func(item: Dictionary) -> String: return str(item.meta.card))

func _shot(view: Node, subject: int, name: String) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless": return
	view.selected_creature = subject
	view._refresh()
	view._fill_strip()
	await frames(6)
	var path := shots.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("SHOT: " + path)

func _strip(view: Node, profile: ELProfile, edition: String) -> void:
	var players := [{"faction": "Green", "level": 3, "cards": ELCatalog.available_cards(profile, "Green").slice(0, 8)},
		{"faction": "Red", "level": 3, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)}]
	view._start(edition, {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": players})
	view.demo = false
	await frames(10)
	var duel: ELDuel = view.duel
	if duel == null or not view._human_turn():
		check(false, "%s: a battle for the strip checks starts on the player's turn" % edition)
		return
	var side := duel.active_side()
	for id: int in duel.creatures.keys(): duel._remove_creature(id, "unsummon")
	var snake := _summoned(duel, side, "GRSN")
	var wall := _summoned(duel, side, "WLDT")
	var tick := _summoned(duel, 1 - side, "TIWR")
	# The marks exactly as combat leaves them (see _marks), plus two of each
	# so a count would show.
	for i in 2:
		duel._mark(snake, "GRSN", 1, 1, {"fixed": true})
		duel._mark(wall, "LASN", -1, -1, {"fixed": true, "lethal": true})
	duel._enchant("TWEN", side, wall, ELCatalog.rule(profile, "TWEN"))
	duel._enchant("TWEN", side, tick, ELCatalog.rule(profile, "TWEN"))
	var venom := "ETRS" if edition == "el2" else "TRSN"
	duel._mark(tick, venom, 0, 0, {"owner": side, "price": 1 if edition == "el2" else 0})
	await frames(4)
	var listed := _listed(view, snake)
	check(listed.is_empty() and _stats(duel, snake) == "3/3", "%s #337: the grass snake's growth shows no icon, the snake is 3/3 (%s, %s)" % [edition, listed, _stats(duel, snake)])
	await _shot(view, snake, "%s_grass_snake" % edition)
	listed = _listed(view, wall)
	check(listed == ["TWEN"], "%s #337: the lake snake's -1/-1 shows no icon, Twisted Enhancement does (%s)" % [edition, listed])
	await _shot(view, wall, "%s_lake_snake_mark" % edition)
	listed = _listed(view, tick)
	check(listed == ["TWEN", venom], "%s #337: a spell and snake venom stay listed (%s)" % [edition, listed])
	await _shot(view, tick, "%s_venom_and_spell" % edition)
	if edition == "el2":
		for pale: String in ["OUD1", "OUD2"]:
			var devourer := _summoned(duel, side, pale)
			var prey := _summoned(duel, 1 - side, "TIWR")
			duel.heroes[side].mana = 40
			var used: bool = duel.use_ability(devourer, "pale_devour", prey)
			if not used and duel.use_ability(devourer, "fiendish"): used = duel.use_ability(devourer, "pale_devour", prey)
			var marks: Array = duel.creatures[devourer].enchantments.filter(func(e: Dictionary) -> bool: return e.card == pale) if duel.creatures.has(devourer) else []
			check(used and marks.size() == 1 and not duel.creatures.has(prey), "%s #337: %s devours its prey and grows (%s, %s)" % [edition, pale, duel.error, _stats(duel, devourer)])
			await frames(4)
			listed = _listed(view, devourer)
			check(listed.is_empty(), "%s #337: %s's growth shows no icon (%s)" % [edition, pale, listed])
			await _shot(view, devourer, "%s_%s_growth" % [edition, pale.to_lower()])
