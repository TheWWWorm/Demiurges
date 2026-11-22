extends SceneTree
## Regression checks for first-game adventure reports:
## - #284: the castle regains floor(sqrt(unused ether / 6)) energy at the end
##   of every day (the original table), up to its maximum, on
##   chapters, single missions, restored missions and random maps, with turns
##   or free movement (the game's default), and after a save and load; a
##   fallen castle regains nothing and energy above the maximum falls back;
## - #289: a spell that spends its last rune stays in the book with no runes
##   (after a battle and after Retaliation drains runes); in battle a random
##   cantrip of its colour and class is drawn in its place (the original
##   draw), or the cantrip it was bought over, if one waits under it.
##
##   godot --headless --path game --script ../tools/issues_284_289_check.gd
##
## Needs the first game configured in user://profiles.json; without it the
## checks are skipped. Nothing is saved.

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, caption: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + caption)
	if not ok: failures += 1

func _run() -> void:
	await process_frame
	_regeneration_table()
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no first-game files configured")
		_finish()
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: the first game's files could not be mounted")
		_finish()
		return
	_spent_spells(profile)
	_day_end(profile)
	_finish()

func _finish() -> void:
	print("ADVENTURE REPORTS 284-289: %d failure(s)" % failures)
	quit(int(failures > 0))

func _session(profile: ELProfile, source: Variant, campaign: bool, free_movement: bool) -> Array:
	var map: ELAdventureMap
	if source is Dictionary:
		var generator := ELFirstRandomMap.new()
		map = generator.generate_reused(profile, source)
		if map == null: return []
	else:
		map = ELAdventureMap.new()
		if not map.load_map(profile, str(source)): return []
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, campaign, true): return []
	var director := ELAdventureDirector.new()
	if not director.build(state): return []
	director.fast_mode = true
	director.free_movement = free_movement
	return [state, director]

func _settle(state: ELAdventureSession, director: ELAdventureDirector) -> void:
	for i in 6000:
		if director.encounter != null:
			ELFirstAI.resolve(director, state.object(director.encounter.hero_id), state.object(director.encounter.opponent_id))
			continue
		if director._shopping():
			for shop: Variant in [director.first_shop, director.rune_shop]:
				if shop != null: shop.cancel()
			director.first_shop = null
			director.rune_shop = null
			continue
		if director.strategy.is_empty() and director.movement.is_empty() and director.travel.is_empty() and director.free_queue.is_empty() and state.commands.is_empty() and director.can_move(): break
		director.advance(0.1)

# --- #284 --------------------------------------------------------------------

## Unused ether -> energy regained, from the original's end-of-day step
## (measured on the original game: energy after minus before).
const ORIGINAL_REGENERATION := {0: 0, 1: 0, 5: 0, 6: 1, 7: 1, 23: 1, 24: 2, 25: 2, 53: 2, 54: 3, 95: 3, 96: 4, 149: 4, 150: 5,
	215: 5, 216: 6, 293: 6, 294: 7, 599: 9, 600: 10, 1000: 12, 9599: 39, 9600: 40}

func _regeneration_table() -> void:
	var wrong: Array = []
	for free: int in ORIGINAL_REGENERATION:
		if ELFirstScenario.regeneration(free) != ORIGINAL_REGENERATION[free]: wrong.append(free)
	check(wrong.is_empty(), "#284: energy regained from unused ether matches the original's table (wrong at %s)" % [wrong])

func _day_end(profile: ELProfile) -> void:
	var restored: Dictionary = {}
	for entry: Dictionary in ELRestoredMissions.entries(profile):
		if restored.is_empty() and str(entry.restored) != ELRestoredMissions.EVIL_DALE: restored = entry.random_map
	var random := ELFirstRandomMap.defaults()
	random.seed = "289"
	var cases: Array = [["chapter mission10", "mission10", true], ["single mmission01", "mmission01", false], ["single pmission03", "pmission03", false],
		["restored mission", restored, false], ["random map", random, false]]
	for entry: Array in cases:
		for free_movement: bool in [false, true]:
			var caption := "%s (%s)" % [entry[0], "free movement" if free_movement else "turns"]
			var pair := _session(profile, entry[1], entry[2], free_movement)
			if pair.is_empty():
				check(false, "#284: %s loads" % caption)
				continue
			var state: ELAdventureSession = pair[0]
			var director: ELAdventureDirector = pair[1]
			var player := state.current_player
			var castle: Dictionary = state.scenario.castles[player]
			var gained: Array = []
			var expected: Array = []
			for day in 2:
				castle.health = int(castle.max) / 2
				castle.pending = 0
				expected.append(ELFirstScenario.regained(state, player, ELGlobalSpells.free_ether(state, player)))
				var before := int(castle.health)
				director.end_day()
				_settle(state, director)
				gained.append(int(castle.health) - before)
			check(expected.all(func(n: int) -> bool: return n >= 1) and gained == expected, "#284: %s: the castle regains its energy at each day's end (%s, expected %s)" % [caption, gained, expected])
			if not free_movement: _after_load(profile, state, director, caption)
			state.close()
	_limits(profile)

## A saved and loaded game keeps regenerating the castle.
func _after_load(profile: ELProfile, state: ELAdventureSession, director: ELAdventureDirector, caption: String) -> void:
	var codec := ELAdventureSave.new()
	var document := codec.encode(director)
	var raw: Variant = JSON.parse_string(JSON.stringify(document, "", true, true)) if not document.is_empty() else null
	var loaded := codec.decode(raw, {"el1": profile}) if raw != null else {}
	if loaded.is_empty():
		check(false, "#284: %s: the game saves and loads (%s)" % [caption, codec.error])
		return
	var again: ELAdventureSession = loaded.state
	var next: ELAdventureDirector = loaded.director
	next.fast_mode = true
	var player := again.current_player
	var castle: Dictionary = again.scenario.castles[player]
	castle.health = int(castle.max) / 2
	castle.pending = 0
	var expected := ELFirstScenario.regained(again, player, ELGlobalSpells.free_ether(again, player))
	var before := int(castle.health)
	next.end_day()
	_settle(again, next)
	check(expected >= 1 and int(castle.health) == before + expected, "#284: %s: after a load the castle still regains %d energy (%d -> %d)" % [caption, expected, before, int(castle.health)])
	again.close()

## The original's bounds: up to the maximum, energy above it falls back, and
## a fallen castle regains nothing.
func _limits(profile: ELProfile) -> void:
	var pair := _session(profile, "mmission01", false, false)
	if pair.is_empty(): return
	var state: ELAdventureSession = pair[0]
	var castles: Dictionary = state.scenario.castles
	var ids: Array = castles.keys()
	ids.sort()
	var full: Dictionary = castles[ids[0]]
	var above: Dictionary = castles[ids[1]]
	var fallen: Dictionary = castles[ids[2]]
	full.health = int(full.max) - 1
	above.health = int(above.max) + 6
	fallen.health = 5
	fallen.alive = false
	ELFirstScenario.regenerate(state)
	check(int(full.health) == int(full.max), "#284: regeneration stops at the castle's maximum")
	check(int(above.health) == int(above.max), "#284: energy above the maximum falls back to it at the day's end")
	check(int(fallen.health) == 5, "#284: a fallen castle regains nothing")
	check(ELGlobalSpells.free_ether(state, int(ids[0])) == 0, "#284: the unused ether is spent on the castle (none is left for the night)")
	state.close()

# --- #289 --------------------------------------------------------------------

func _spent_spells(profile: ELProfile) -> void:
	var spells := profile.table("CombatSpells")
	var pair := _session(profile, "mission10", true, false)
	if pair.is_empty():
		check(false, "#289: chapter mission10 loads")
		return
	var state: ELAdventureSession = pair[0]
	var hero := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.owner) == state.current_player and hero.is_empty(): hero = item
	var monster := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "monster" and monster.is_empty(): monster = item
	check(not hero.is_empty() and not monster.is_empty(), "#289: mission10 has a hero of the player and a creature")
	if hero.is_empty() or monster.is_empty():
		state.close()
		return
	# A rune spell of the hero's colour with a cantrip of its colour and class.
	var colour := ELFirstSpellShop.hero_color(profile, hero)
	var spell := ""
	var cantrip := ""
	for code: String in spells:
		var row: Dictionary = spells[code]
		if not spell.is_empty() or row.get("Color") != colour or row.get("Rarity") == "Cantrip" or ELCatalog.rule(profile, code).is_empty(): continue
		for other: String in spells:
			if spells[other].get("Rarity") == "Cantrip" and spells[other].get("Color") == colour and spells[other].get("Class") == row.get("Class"):
				spell = code
				cantrip = other
				break
	check(not spell.is_empty(), "#289: a %s rune spell with a cantrip of its class (%s, %s)" % [colour, spell, cantrip])
	if spell.is_empty():
		state.close()
		return
	# The book: the rune spell bought over a cantrip, and the same spell alone.
	hero.cards = [spell, spell]
	hero.rune_uses = [2, 1]
	hero.rune_stock = {}
	hero.spell_stock = {}
	ELRunes.set_under(hero, [cantrip, ""])
	var encounter := ELAdventureEncounter.new()
	var duel := ELDuel.new()
	duel.heroes.assign([{"spell_uses": [0, 0]}, {"spell_uses": []}])
	duel.setup = {"players": [{"rune_uses": [2, 1]}, {}]}
	encounter.battle = duel
	encounter.state = state
	encounter.hero_id = int(hero.uid)
	encounter.opponent_id = int(monster.uid)
	encounter.write_back_runes()
	check(hero.cards == [spell, spell] and hero.rune_uses == [0, 0], "#289: after a battle both spent spells stay in the book with no runes (%s %s)" % [hero.cards, hero.rune_uses])
	check(ELRunes.under(hero) == [cantrip, ""], "#289: the cantrip bought under the spell still waits under it")
	var copy: Variant = JSON.parse_string(JSON.stringify(hero))
	check(copy is Dictionary and ELRunes.restore(profile, copy) and copy.cards == [spell, spell] and copy.rune_uses == [0, 0], "#289: a spent spell with no runes saves and loads")
	# Retaliation's rune drain leaves the spell in the book as well.
	hero.rune_uses = [1, 3]
	ELGlobalSpells.drain_runes(state, hero, 5)
	check(hero.cards == [spell, spell] and hero.rune_uses == [0, 0], "#289: runes drained to none leave the spells in the book")
	# In battle: the spent slot draws a cantrip of its colour and class.
	var fighter := {"deck": [spell], "spell_uses": [0], "hand_slots": [], "drawn": [], "kind": "hero"}
	var drawn := ELSpellCharges.choose_el1(fighter, spells, func(n: int): return n - 1)
	var row: Dictionary = spells.get(str(drawn.get("card", "")), {})
	check(int(drawn.get("slot", 0)) == -1 and row.get("Rarity") == "Cantrip" and row.get("Color") == colour and row.get("Class") == spells[spell].get("Class"), "#289: in battle a spent spell is replaced by a random %s cantrip of its class (%s)" % [colour, drawn.get("card", "")])
	fighter = {"deck": [spell], "spell_uses": [0], "hand_slots": [], "drawn": [], "rune_under": [cantrip], "kind": "hero"}
	drawn = ELSpellCharges.choose_el1(fighter, spells, func(n: int): return 0)
	check(drawn.get("card") == cantrip and int(drawn.get("slot", 0)) == -1, "#289: a spent spell bought over a cantrip draws that cantrip")
	# Runes bought again make the same slot draw the spell itself.
	fighter = {"deck": [spell], "spell_uses": [1], "hand_slots": [], "drawn": [], "kind": "hero"}
	drawn = ELSpellCharges.choose_el1(fighter, spells, func(n: int): return 0)
	check(drawn.get("card") == spell and int(drawn.get("slot", -1)) == 0, "#289: once its runes are refilled the spell is drawn again")
	state.close()
