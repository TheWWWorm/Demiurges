extends RefCounted
## Small hand-made duel positions for the headless checks of the computer
## opponent (tools/duel_ai_check.gd, tools/duel_rules_check.gd).
##
## A position is written as a dictionary and restored as a real ELDuel, so
## that the game's own rules and the compiled engine both play it:
##   {"attacker": 0, "phase": "attack" | "defence", "attacks": [ids],
##    "fixed": true (no draws, no natural channels, as in a puzzle),
##    "heroes": [{health, mana, channels, hand: [cards], enchantments: [cards],
##                skills: {}, spec: "NONE", turns, maximum}, {...}],
##    "creatures": [{card, owner, power, toughness, flags: [...], resting,
##                   damage, sick, enchantments: [...]}]}
## Creatures are given ids from 2 on, in the order listed. Anything a hero or
## creature is not told keeps the value of the first packed puzzle of the
## game (game/puzzles/<game>.json), which supplies a valid hero template.

static func build(profile: ELProfile, spec: Dictionary) -> ELDuel:
	var entries := ELPuzzles.list(profile.id)
	if entries.is_empty(): return null
	var state: Dictionary = (entries[0].state as Dictionary).duplicate(true)
	state.attacker = int(spec.get("attacker", 0))
	state.phase = 1 if String(spec.get("phase", "attack")) == "defence" else 0
	state.attacks = spec.get("attacks", [])
	state.blocks = {}
	state.winner = -1
	var fixed: bool = spec.get("fixed", true)
	state.setup = {"players": state.setup.players, "puzzle_fixed_channels": fixed, "puzzle_fixed_hands": fixed}
	if spec.has("rng"): state.rng = int(spec.rng)
	var next_enchantment := 1
	for side in 2:
		var hero: Dictionary = state.heroes[side]
		var told: Dictionary = spec.get("heroes", [{}, {}])[side]
		for key: String in told:
			if key in ["hand", "enchantments"]: continue
			hero[key] = told[key]
		var hand: Array = told.get("hand", [])
		hero.hand = hand.duplicate()
		hero.hand_slots = []
		hero.hand_view = []
		# "pages": the place of each card of the hand in the hero's book (told
		# with "deck" and "spell_uses"); without it no card is of the book.
		var pages: Array = told.get("pages", [])
		hero.erase("pages")
		for i in hand.size():
			hero.hand_slots.append(int(pages[i]) if i < pages.size() else -1)
			hero.hand_view.append(i)
		hero.enchantments = []
		for card: String in told.get("enchantments", []):
			hero.enchantments.append({"born": 1, "card": card, "id": next_enchantment, "owner": side, "power": 0, "toughness": 0, "used": false})
			next_enchantment += 1
		if not told.has("maximum"): hero.maximum = maxi(int(hero.get("maximum", 20)), int(hero.health))
	var creatures := {}
	var id := 2
	for c: Dictionary in spec.get("creatures", []):
		var flags: Array = c.get("flags", ELCatalog.flags(profile.table("CombatCreatures").get(String(c.card), {})))
		var worn: Array = []
		for card: String in c.get("enchantments", []):
			worn.append({"born": 1, "card": card, "id": next_enchantment, "owner": int(c.get("caster", c.owner)), "power": 0, "toughness": 0})
			next_enchantment += 1
		var row := {"card": String(c.card), "damage": int(c.get("damage", 0)), "enchantments": worn, "flags": flags, "flying": flags.has("Fly"),
			"id": id, "owner": int(c.owner), "power": int(c.get("power", profile.table("CombatCreatures")[String(c.card)].Power)),
			"regenerated": false, "resting": bool(c.get("resting", false)), "sick": bool(c.get("sick", false)),
			"toughness": int(c.get("toughness", profile.table("CombatCreatures")[String(c.card)].Toughness))}
		# "base": the strength a creature was made with, where its card has none.
		if c.has("base"): row.base = c.base
		creatures[str(id)] = row
		id += 1
	state.creatures = creatures
	state.next_id = id
	state.next_enchantment = next_enchantment
	var duel := ELDuel.new()
	if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": state}):
		push_error("fixture: " + duel.error)
		return null
	return duel

## A duel with books that deal (no fixed hands, so no puzzle): hero 0 holds a
## Might it drew, hero 1 the cards of `other`, drawn as well unless `open`
## (then they came into its hand in the open, as a returned card does); `rng`
## sets the duel's run of chance apart. For the checks of what the smarter
## player may know.
static func drawn_hands(profile: ELProfile, other: Array, rng := 0, open := false) -> ELDuel:
	var duel := build(profile, {"fixed": false, "rng": 4711 + rng, "heroes": [{"health": 20, "mana": 3, "hand": ["MGHT"]}, {"health": 20, "mana": 3, "hand": other}],
		"creatures": [{"card": "GROG", "owner": 0}, {"card": "KBWR", "owner": 1}]})
	if duel == null: return null
	for side in 2:
		duel.heroes[side].deck = ["STRT", "KBWR", "GROG", "MGHT"]
		duel.heroes[side].spell_uses = [-1, -1, -1, -1]
	duel.heroes[0].hand_slots = [3]
	var slots: Array = []
	for card: String in other: slots.append(-1 if open else 0)
	duel.heroes[1].hand_slots = slots
	return duel

## A context for asking the compiled engine about `side`, as the tools ask it.
static func context(profile: ELProfile, side: int) -> ELCombatSearch.Context:
	var ctx := ELCombatSearch.Context.new()
	ctx.ai = side
	ctx.edition = profile.id
	ctx.second = profile.id == "el2"
	ctx.w = ELCombatSearch.chosen_weights(ctx.second)
	ctx.remember = true
	ctx.foe_health = ELCombatSearch.smart_foe_health
	return ctx

## Plays a proof's winning line through the game's own rules, answering the
## other hero's turns with its best defence as the shipped engine reads it;
## the winner, or -1 when the duel is still going after `steps` commands.
static func play_proof(profile: ELProfile, duel: ELDuel, side: int, turns: int, budget: int, steps := 60) -> int:
	var copy := duel.search_copy()
	for step in steps:
		if copy.phase == ELDuel.Phase.FINISHED: return int(copy.winner)
		var acting := copy.active_side()
		var command := {}
		if acting == side:
			var proof := ELCombatBrain.prove(context(profile, side), copy, turns, budget)
			var line: Array = proof.get("line", [])
			if line.is_empty(): return -1
			var first: Array = line[0]
			command = ELCombatBrain._command_of(copy, copy.creatures.keys(), int(first[0]), int(first[1]), int(first[2]), int(first[3]))
			if int(first[0]) == 5:
				var mask := (int(first[1]) & 0xffff) | (int(first[2]) << 16)
				var ids: Array = copy.creatures.keys()
				for k in ids.size():
					if mask & (1 << k) and not copy.attacks.has(int(ids[k])):
						command = {"kind": "attack", "id": int(ids[k])}
						break
		else:
			var smart: Array[int] = [acting]
			copy.smart_sides = smart
			command = ELCombatSearch.think(copy)
		var done: bool = copy.end_phase() if command.is_empty() or String(command.get("kind", "")) == "end_phase" else ELCombatSearch.apply(copy, command)
		if not done:
			if acting == side: return -2
			copy.end_phase()
	return int(copy.winner) if copy.phase == ELDuel.Phase.FINISHED else -1
