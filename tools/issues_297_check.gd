extends SceneTree
## Regression check for #297: the battle strip's enchantment order. Both
## originals list a character's enchantments in cast order (their battle keeps
## one enchantment list in cast order and the strip walks it unsorted). The
## remake sorts only the characters of the side at this screen: enchantments
## whose ability can still be used this round, then the harmful ones (cast by
## the other side), then the rest, then the abilities already used this round.
## The other side's hero and creatures keep cast order, so the strip does not
## show which of their abilities were used. In hot seat the side at this
## screen is the one whose turn the hand-over box handed to.
##
##   godot --headless --path game --script ../tools/issues_297_check.gd
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. Settings are never written.

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440, 900)
	await process_frame
	for edition: String in ["el1", "el2"]:
		await _strip_order(edition)
	print("ISSUE 297: %d failure(s)" % failures)
	quit(int(failures > 0))

func _summoned(duel: ELDuel, side: int, card: String) -> int:
	var known := duel.creatures.keys()
	duel._summon(side, card)
	for key: int in duel.creatures:
		if not known.has(key): return key
	return -1

func _cards(view: Node, subject: int) -> Array:
	view.selected_creature = subject
	view._fill_strip()
	return view.rail.strip.items.filter(func(item: Dictionary) -> bool: return item.meta.has("enchantment")).map(func(item: Dictionary) -> String: return str(item.meta.card))

## Puts on hero `holder`, in this order: a plain own enchantment, a toxin of
## the other side, an unused healing ability and a fireball used this round.
func _dress(view: Node, profile: ELProfile, holder: int) -> void:
	var duel: ELDuel = view.duel
	duel.heroes[holder].enchantments.clear()
	duel._enchant("MNVR", holder, holder, ELCatalog.rule(profile, "MNVR"))
	duel._enchant("STTX", 1 - holder, holder, ELCatalog.rule(profile, "STTX"))
	duel._enchant("LSHE", holder, holder, ELCatalog.rule(profile, "LSHE"))
	duel._enchant("FRBL", holder, holder, ELCatalog.rule(profile, "FRBL"))
	for e: Dictionary in duel.heroes[holder].enchantments:
		if e.card == "FRBL": e.used = true

func _strip_order(edition: String) -> void:
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
	var players := [{"faction": "Blue", "level": 3, "map_level": 2, "cards": ELCatalog.available_cards(profile, "Blue").slice(0, 8)},
		{"faction": "Red", "level": 5, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)}]
	view._start(edition, {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": players})
	view.demo = false
	await frames(10)
	var duel: ELDuel = view.duel
	if duel == null or not view._human_turn():
		check(false, "%s: a battle for the strip checks starts on the player's turn" % edition)
		view.queue_free()
		await frames(2)
		return
	var side := duel.active_side()
	check(view._displayed_side() == side, "%s: the player's side is the side at this screen" % edition)
	_dress(view, profile, side)
	_dress(view, profile, 1 - side)
	check(view._enchantment_ability(duel.heroes[side].enchantments[0], side).is_empty(), "%s: the plain enchantment grants no ability" % edition)
	var own := _cards(view, side)
	check(own == ["LSHE", "STTX", "MNVR", "FRBL"], "%s: own hero: usable ability, harmful, the rest, used ability last (%s)" % [edition, own])
	var theirs := _cards(view, 1 - side)
	check(theirs == ["MNVR", "STTX", "LSHE", "FRBL"], "%s: opponent's hero: cast order, used ability not moved (%s)" % [edition, theirs])
	for e: Dictionary in duel.heroes[side].enchantments: e.used = false
	own = _cards(view, side)
	check(own == ["LSHE", "FRBL", "STTX", "MNVR"], "%s: own hero, nothing used: both usable abilities first, oldest first (%s)" % [edition, own])
	# Creatures follow their owner's side.
	var ours := _summoned(duel, side, "ORSH")
	var foe := _summoned(duel, 1 - side, "ORSH")
	for id: int in [ours, foe]:
		var owner := int(duel.creatures[id].owner)
		duel._enchant("UPGD", owner, id, ELCatalog.rule(profile, "UPGD"))
		duel._enchant("FAIL", 1 - owner, id, ELCatalog.rule(profile, "FAIL"))
	var mine := _cards(view, ours)
	check(mine == ["FAIL", "UPGD"], "%s: own creature: the harmful enchantment first (%s)" % [edition, mine])
	var other := _cards(view, foe)
	check(other == ["UPGD", "FAIL"], "%s: opponent's creature: cast order (%s)" % [edition, other])
	# Hot seat: the side the hand-over gave the screen to is the sorted one.
	# A battle started straight from _start has no match; a bare one stands in.
	var was_match: Variant = view.duel_match
	if view.duel_match == null: view.duel_match = ELDuelMatch.new()
	var was_hot: bool = view.duel_match.hot_seat
	var was_side: int = view.hot_side
	view.duel_match.hot_seat = true
	view.hot_pending = false
	view.hot_side = 1 - side
	for e: Dictionary in duel.heroes[side].enchantments:
		if e.card == "FRBL": e.used = true
	check(view._displayed_side() == 1 - side, "%s: hot seat: the screen belongs to the handed-over side" % edition)
	theirs = _cards(view, 1 - side)
	check(theirs == ["LSHE", "STTX", "MNVR", "FRBL"], "%s: hot seat: the handed-over side sees its own hero sorted (%s)" % [edition, theirs])
	own = _cards(view, side)
	check(own == ["MNVR", "STTX", "LSHE", "FRBL"], "%s: hot seat: the other hero in cast order (%s)" % [edition, own])
	view.duel_match.hot_seat = was_hot
	view.hot_side = was_side
	view.duel_match = was_match
	view.queue_free()
	await frames(2)
