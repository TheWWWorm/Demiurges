class_name ELAdventureEncounter
extends RefCounted
var state: ELAdventureSession
var hero_id := -1
var opponent_id := -1
## The duel; a second-game battle reads and writes the session's mission
## variables and difficulty through its scripts, also after a load.
var battle: ELDuel:
	set(value):
		battle = value
		if value != null and state != null: value.attach_session(state)
var error := ""
var resolved := false
var scripted_winner := -1
## Second game: a battle with no side of the local player (player 1) is never
## played; it resolves at once, possibly with no winner.
var auto := false
var winner := -1
## Side whose duel health can end the chapter mid-battle, or -1.
var watch_side := -1
## First-game victory report: experience shown and resources looted.
var report: Dictionary = {}
## The defender of an ethereal (Warrior of the Realm) battle, or -1.
var ethereal_defender := -1
## Map artifacts carried into battle that the duel cannot use yet (first game:
## unknown rows; second game: generated artifacts whose spell has no rule).
var unsupported_artifacts: Array[String] = []
## Second game: the battle was declined on the pre-battle panel.
var declined := false
## Second game: a played battle whose result is not a win of a player-one
## hero shows the LoseBattle screen afterwards.
var lose_screen := false
## First-game automatic arenas, indexed by the original terrain classification.
const FIRST_ARENAS := ["Black.002", "Green.002", "Blue.002", "Red.002", "Ether.001", "White.001", "Dungeon.001", "Fort.001"]

## `defender` is the second actor of the queued battle pair; its tile picks the arena.
func prepare(session: ELAdventureSession, first: int, second: int, defender := -1) -> bool:
	state = session
	hero_id = first
	opponent_id = second
	if state.map.profile.id == "el2":
		if int(state.object(hero_id).get("owner", -1)) == 1 or int(state.object(opponent_id).get("owner", -1)) == 1: return _prepare_duel(state, defender)
		auto = true
		scripted_winner = second_result(state, hero_id, opponent_id)
		return true
	if state.vm != null:
		var outcome := state.vm.invoke("Hook_OnBattleResult", [float(hero_id), float(opponent_id)])
		if not state.vm.error.is_empty(): return _fail(state.vm.error)
		if not outcome.is_empty() and typeof(outcome[0]) in [TYPE_INT, TYPE_FLOAT] and int(outcome[0]) in [hero_id, opponent_id]:
			scripted_winner = int(outcome[0])
			return true
	return _prepare_duel(state, defender)

## Hook_OnBattleResult for a non-local pair: a participant's id wins; −2 (no
## chapter handler) or a script error falls back to the higher level (equal:
## none); any other value means no winner.
static func second_result(state: ELAdventureSession, first: int, second: int) -> int:
	var verdict := -2
	if state.vm != null and state.vm.has_function("Hook_OnBattleResult"):
		var outcome := state.vm.invoke("Hook_OnBattleResult", [float(first), float(second)])
		if not state.vm.error.is_empty(): state.vm.error = ""
		elif not outcome.is_empty() and typeof(outcome[0]) in [TYPE_INT, TYPE_FLOAT]: verdict = int(outcome[0])
		else: verdict = -1
	if verdict == first or verdict == second: return verdict
	if verdict != -2: return -1
	var a := int(state.object(first).get("level", 0))
	var b := int(state.object(second).get("level", 0))
	return first if a > b else (second if b > a else -1)

func _prepare_duel(state: ELAdventureSession, defender: int) -> bool:
	var options := {"adventure": true, "arena": "Green.001", "players": []}
	var profile := state.map.profile
	for id: int in [hero_id, opponent_id]:
		var actor := state.object(id)
		if actor.is_empty() or not actor.alive: return _fail("The encounter character is unavailable.")
		var row: Dictionary = profile.table("Shapes").get(actor.shape, {}) if not actor.shape.is_empty() else profile.table("HeroTemplates").get(actor.name, {})
		if profile.id == "el1" and actor.type == "monster": row = ELFirstMonsters.definition(profile, actor.name, int(actor.get("monster_difficulty", state.difficulty)))
		if row.is_empty(): return _fail("The encounter appearance is missing: " + actor.name)
		var color := String(row.get("Color", ""))
		options.players.append({"faction": color, "shape": actor.shape, "kind": actor.type, "title": actor.get("title", actor.name), "level": actor.level, "health": actor.health, "cards": actor.cards.duplicate(), "skills": actor.get("skills", {}).duplicate()})
		# Dragon skin is remapped by difficulty for heroes; whether first-game
		# neutral monster rows take the same path is unknown, so they keep theirs.
		var spec := String(actor.get("specialization", "NONE"))
		if not (profile.id == "el1" and actor.type == "monster"): spec = ELSpecs.remap(spec, state.difficulty)
		options.players[-1].specialization = spec if ELSpecs.valid(profile, spec) else "NONE"
		if profile.id == "el1" and actor.type == "monster":
			options.players[-1].monster_name = actor.name
			options.players[-1].monster_difficulty = int(actor.get("monster_difficulty", state.difficulty))
		if profile.id == "el1":
			# Tier one and two forts lend the garrison a fully charged Defence rod for this battle.
			if int(ELForts.garrison_of(state, actor).get("fort_level", 0)) > 0: options.players[-1].artifacts = [{"name": "RodOfDefence"}]
			# Carried map artifacts start every battle fully charged.
			for item: Dictionary in actor.get("artifacts", []):
				var entry := {"name": str(item.name)}
				if ELDuel.artifact_entry(profile, entry).is_empty():
					if not unsupported_artifacts.has(entry.name): unsupported_artifacts.append(entry.name)
					continue
				if not options.players[-1].has("artifacts"): options.players[-1].artifacts = []
				options.players[-1].artifacts.append(entry)
			ELGlobalSpells.battle_choice(state, actor, options.players[-1])
			if not ELRunes.restore(profile, actor): return _fail("Invalid encounter rune inventory.")
			options.players[-1].rune_uses = actor.rune_uses.duplicate()
		elif actor.type == "hero":
			# Second game: artifacts enter with their current charges (generated
			# ones with their definition); a fort garrison of level one or more
			# adds a full Defence rod after them, never written back.
			var carried: Array = []
			for item: Dictionary in actor.get("artifacts", []):
				var entry := ELSecondArtifacts.battle_entry(item)
				if ELDuel.artifact_entry(profile, entry).is_empty():
					if not unsupported_artifacts.has(entry.name): unsupported_artifacts.append(entry.name)
					continue
				carried.append(entry)
			if _second_garrison_rod(state, actor): carried.append({"name": "RodOfDefence"})
			if not carried.is_empty(): options.players[-1].artifacts = carried
		if id == hero_id and profile.table("CombatSceneDB").has(color + ".001"): options.arena = color + ".001"
	if profile.id == "el1":
		# Player battle spells act only when both sides belong to players.
		var owners: Array[int] = [int(state.object(hero_id).owner), int(state.object(opponent_id).owner)]
		if owners[0] >= 1 and owners[1] >= 1 and state.players.has(owners[0]) and state.players.has(owners[1]):
			for side in 2: options.players[side].global_effects = ELGlobalSpells.battle_effects(state, owners[side])
		options.arena = FIRST_ARENAS[4] if ethereal_defender >= 0 else first_arena(state, hero_id, opponent_id, defender if defender >= 0 else opponent_id)
		var levels := first_levels(state, hero_id, opponent_id)
		for side in 2: options.players[side].level = levels[side]
	else:
		# Second-game difficulty moves only the specialisation level.
		var levels := ELSpecs.second_levels([int(options.players[0].level), int(options.players[1].level)], state.difficulty)
		# A garrison of a tier-two fort raises its side by one more.
		for side in 2:
			if int(ELForts.garrison_of(state, state.object(hero_id if side == 0 else opponent_id)).get("fort_level", 0)) == ELForts.MAX_LEVEL: levels[side] = mini(levels[side] + 1, 20)
		for side in 2: options.players[side].spec_level = levels[side]
		# Mob `Script=` chunks and battleground buildings (ELBattleScripts.select).
		var scripts := ELBattleScripts.select(state, [hero_id, opponent_id])
		if not scripts.is_empty(): options.scripts = scripts
	if state.vm != null:
		var chosen := state.vm.invoke("Hook_OnGetArena", [float(hero_id), float(opponent_id)])
		if not state.vm.error.is_empty(): return _fail(state.vm.error)
		if not chosen.is_empty() and chosen[0] is String and not chosen[0].is_empty(): options.arena = chosen[0]
	var battle_seed := state.seed_value + hero_id + opponent_id
	var colours: Array[String] = [String(options.players[0].faction), String(options.players[1].faction)]
	options.first_side = first_side(state, hero_id, opponent_id, colours, battle_seed)
	battle = ELDuel.new()
	if not battle.start(profile, battle_seed, options): return _fail(battle.error)
	watch_side = ELFirstScenario.duel_watch(state, hero_id, opponent_id)
	return true

static func _second_garrison_rod(state: ELAdventureSession, actor: Dictionary) -> bool:
	return int(ELForts.garrison_of(state, actor).get("fort_level", 0)) >= 1

static func terrain_arena(kind: int) -> int:
	if kind <= 3 or kind == 6: return 1
	if (kind >= 4 and kind <= 7) or kind == 18: return 2
	if kind >= 8 and kind <= 11: return 0
	if kind >= 12 and kind <= 15: return 3
	return 4

## The defender's tile corners choose a terrain arena: three matching corners
## win, otherwise the first corner with a terrain arena. A garrison in either
## side uses the fort arena; two late missions use the White Lord's arena.
static func first_arena(state: ELAdventureSession, first: int, second: int, defender: int) -> String:
	var map := state.map
	if map.id.contains("mission17") or map.id.contains("mission27"): return FIRST_ARENAS[5]
	# The dungeon arena comes before the fort arena (original selector order).
	if state.object(first).has("dungeon") or state.object(second).has("dungeon"): return FIRST_ARENAS[6]
	# A fortification spell also fights on the fort arena (no fort level bonus).
	if ELGlobalSpells.held_in_fort(state.object(first)) or ELGlobalSpells.held_in_fort(state.object(second)): return FIRST_ARENAS[7]
	var actor := state.object(defender)
	var at := Vector2i(int(actor.get("x", -1)), int(actor.get("y", -1)))
	if at == Vector2i(-1, -1):
		var other := state.object(first if defender == second else second)
		at = Vector2i(int(other.get("x", 0)), int(other.get("y", 0)))
	return FIRST_ARENAS[terrain_class(map, at)]

## The tile's terrain class (0 Black-arena, 1 Green, 2 Blue, 3 Red-arena land,
## 4 other): three equal corners win, otherwise the first corner with a class
## other than 4 (EL1; EL2 masks each kind with 0xbf first).
static func terrain_class(map: ELAdventureMap, at: Vector2i) -> int:
	var c: Array[int] = [map.tile(at.x, at.y), map.tile(at.x + 1, at.y), map.tile(at.x + 1, at.y + 1), map.tile(at.x, at.y + 1)]
	if map.profile.id == "el2":
		for i in 4: c[i] &= 0xbf
	if c[0] == c[1] and c[0] == c[2]: return terrain_arena(c[0])
	if c[1] == c[2] and c[1] == c[3]: return terrain_arena(c[1])
	if c[2] == c[3] and c[2] == c[0]: return terrain_arena(c[2])
	if c[3] == c[0] and c[3] == c[1]: return terrain_arena(c[3])
	for kind: int in c:
		if terrain_arena(kind) != 4: return terrain_arena(kind)
	return 4

## The original colour enum (EL1, EL2): Red 0, Green 1,
## Blue 2, Black 3; the second game adds White 4. Unknown −1.
static func colour_index(edition: String, colour: String) -> int:
	var index := ["Red", "Green", "Blue", "Black", "White"].find(colour)
	return -1 if index == 4 and edition != "el2" else index

## Home-terrain first turn (EL1, EL2 tail): the battle tile
## is the second actor's, else the first actor's when the second is unplaced,
## else (0,0), which counts as unknown. A placed side whose colour index equals
## the tile's terrain class matches; exactly one match moves first, otherwise a
## coin flip from the battle seed. Attacker/defender roles are not consulted.
## As coded, colour 0 (Red) meets class 0 (Black-arena land) and colour 3
## (Black) class 3 (Red-arena land): an original quirk kept on purpose.
static func first_side(state: ELAdventureSession, first: int, second: int, colours: Array[String], battle_seed: int) -> int:
	var actors := [state.object(first), state.object(second)]
	var placed: Array[bool] = []
	for actor: Dictionary in actors: placed.append(Vector2i(int(actor.get("x", -1)), int(actor.get("y", -1))) != Vector2i(-1, -1))
	var tile := Vector2i.ZERO
	if placed[1]: tile = Vector2i(int(actors[1].x), int(actors[1].y))
	elif placed[0]: tile = Vector2i(int(actors[0].x), int(actors[0].y))
	var matches: Array[bool] = [false, false]
	if tile != Vector2i.ZERO:
		var terrain := terrain_class(state.map, tile)
		for side in 2: matches[side] = placed[side] and colour_index(state.map.profile.id, colours[side]) == terrain
	if matches[0] != matches[1]: return 0 if matches[0] else 1
	return coin_flip(battle_seed)

## Independent 50/50 from a battle seed (stands in for the battle object's rand()).
static func coin_flip(battle_seed: int) -> int:
	var value := ((battle_seed ^ 0x2545f491) * 214013 + 2531011) & 0xffffffff
	value = (value * 214013 + 2531011) & 0xffffffff
	return (value >> 16) & 1

## Campaign difficulty adjusts temporary battle levels: the local side gains two
## (Easy) or one (Normal); the opponent loses one on Easy and gains one or two on
## Expert/Master. A garrison in a tier-two fort gains one. Results stay 1-20.
static func first_levels(state: ELAdventureSession, local: int, opponent: int) -> Array[int]:
	var levels: Array[int] = [int(state.object(local).level), int(state.object(opponent).level)]
	var change: Array = [[2, -1], [1, 0], [0, 0], [0, 1], [0, 2]][clampi(state.difficulty, 0, 4)]
	for side in 2:
		levels[side] += int(change[side])
		if int(ELForts.garrison_of(state, state.object(local if side == 0 else opponent)).get("fort_level", 0)) == ELForts.MAX_LEVEL: levels[side] += 1
		levels[side] = clampi(levels[side], 1, 20)
	return levels

func finish() -> bool:
	if not resolved and not state.outcome.is_empty():
		# A chapter outcome reached mid-duel replaces the battle's resolution.
		resolved = true
		return true
	if resolved or (not auto and scripted_winner < 0 and (battle == null or battle.phase != ELDuel.Phase.FINISHED)): return _fail("The encounter has not ended.")
	if auto and scripted_winner < 0:
		# No winner: nobody dies and no finishing hook runs.
		resolved = true
		winner = -1
		state.event.emit({"kind": "battle_finished", "hero": hero_id, "opponent": opponent_id, "winner": -1})
		return true
	var winner_id := scripted_winner
	if scripted_winner < 0 and battle != null and battle.winner >= 0: winner_id = hero_id if battle.winner == 0 else opponent_id
	var defeated: Array[int] = [hero_id, opponent_id]
	if winner_id >= 0: defeated.erase(winner_id)
	# Nobody dies in an ethereal battle and nobody gains experience.
	var kill_loser := ethereal_defender < 0
	if ethereal_defender >= 0: ELGlobalSpells.ethereal_result(state, ethereal_defender, winner_id)
	if state.map.profile.id == "el2" and battle != null:
		# An opposing specialisation that worked may be learned by a winning main hero.
		var main_side := 0 if hero_id == state.main_hero else (1 if opponent_id == state.main_hero else -1)
		if main_side >= 0:
			for entry: Dictionary in battle.history:
				if entry.get("kind") == "spec" and int(entry.side) == 1 - main_side:
					state.set_variable("IsNewSpecialization", 1.0)
					state.set_variable("NewSpecializationType", str(entry.spec))
	if state.vm != null:
		var finishing := state.vm.invoke("Hook_OnBattleFinishing", [float(hero_id), float(opponent_id), float(winner_id)])
		if not state.vm.error.is_empty(): return _fail(state.vm.error)
		kill_loser = finishing.is_empty() or finishing[0] != null
	if state.map.profile.id == "el2" and scripted_winner < 0 and battle != null and kill_loser:
		# Second game: an accepted battle writes the used charges back;
		# a cancelled finish (nil hook result, e.g. the main hero's loss) keeps them.
		for side in 2:
			var actor := state.object(hero_id if side == 0 else opponent_id)
			if actor.get("type") != "hero": continue
			var entries: Array = battle.heroes[side].get("artifacts", [])
			ELSecondArtifacts.write_back(actor, entries, entries.size() - (1 if _second_garrison_rod(state, actor) else 0))
	if state.map.profile.id == "el1" and scripted_winner < 0:
		for side in 2:
			var actor := state.object(hero_id if side == 0 else opponent_id)
			if actor.type == "hero": actor.rune_uses = battle.heroes[side].spell_uses.duplicate()
	if kill_loser:
		if winner_id >= 0:
			var reward := ELHeroProgression.battle_reward(state.map.profile, int(state.object(defeated[0]).get("level", 1)))
			if state.variables != null:
				var additional: Variant = state.variables.values.get("AdditionalExperience")
				if typeof(additional) in [TYPE_INT, TYPE_FLOAT]: reward += int(additional)
				state.variables.values.erase("AdditionalExperience")
			var loser := state.object(defeated[0])
			var victor := state.object(winner_id)
			var before := {"health": int(victor.get("health", 0)), "level": int(victor.get("level", 1))}
			# First-game neutral heroes never gain experience.
			var granted := 0 if state.map.profile.id == "el1" and int(victor.get("owner", 0)) <= 0 else state.add_experience(winner_id, maxi(0, reward))
			# Second game: the local player's won battle is journaled.
			if state.map.profile.id == "el2" and int(victor.get("owner", -1)) == state.current_player and state.players.has(state.current_player):
				ELSecondNotebook.add_battle(state, victor, loser, before, maxi(0, reward))
			if state.map.profile.id == "el1" and victor.get("type") == "hero" and state.players.has(int(victor.get("owner", -1))):
				report = {"hero": winner_id, "opponent": defeated[0], "experience": maxi(0, granted), "resources": [], "monster": loser.get("type") == "monster", "artifacts": ELFirstAI.take_artifacts(victor, loser)}
				if loser.get("type") == "monster": report.resources = loot(state, victor, loser)
		for id: int in defeated:
			state._native([float(id)], "ExKillHero")
			if not state.hook("Hook_OnHeroKill", [float(id)]): return _fail(state.error)
	# Keep encounter life separate from the map's authored starting health.
	# Scenario hooks decide whether a defeated hero dies or returns for a retry.
	if state.map.profile.id == "el2" and not auto and battle != null:
		# A refused finish leaves the battle without a winner, which the
		# player sees as a loss even when the main hero won the duel.
		var counted := winner_id >= 0 and kill_loser
		lose_screen = not (counted and int(state.object(winner_id).get("owner", -1)) == 1)
	resolved = true
	winner = winner_id
	state.event.emit({"kind": "battle_finished", "hero": hero_id, "opponent": opponent_id, "winner": winner_id})
	return true

## Second game: PreCombatCancel declines a prepared local battle.
## Both sides are marked as ended without a duel; Hook_OnBattleFinishing runs
## with the local side's opponent as the winner and its result is ignored.
## Nobody dies, no experience is given and no charges are written back. The
## shipped default hook returns the main hero to its last legal position.
func decline() -> bool:
	if resolved or auto or battle == null or state.map.profile.id != "el2": return _fail("This battle cannot be declined.")
	var local := hero_id if int(state.object(hero_id).get("owner", -1)) == 1 else opponent_id
	var other := opponent_id if local == hero_id else hero_id
	if state.vm != null:
		state.vm.invoke("Hook_OnBattleFinishing", [float(hero_id), float(opponent_id), float(other)])
		if not state.vm.error.is_empty(): return _fail(state.vm.error)
	resolved = true
	declined = true
	winner = -1
	state.event.emit({"kind": "battle_finished", "hero": hero_id, "opponent": opponent_id, "winner": -1, "declined": true})
	return true

## A neutral creature's loot goes to the winning hero's player.
static func loot(state: ELAdventureSession, hero: Dictionary, monster: Dictionary) -> Array:
	var row := ELFirstMonsters.definition(state.map.profile, str(monster.get("name", "")), int(monster.get("monster_difficulty", state.difficulty)))
	# A creature without a template (scripted or synthetic) carries no loot.
	if row.is_empty(): return []
	var draws := ELFirstMonsters.scale_loot(ELFirstMonsters.roll_loot(row, func() -> int: return ELAdditionalBuildings._random(state)), hero)
	var reward := ELResources.empty(state.map.profile.id)
	for entry: Array in draws: reward[entry[0]] += int(entry[1])
	if not draws.is_empty(): state.change_resources(int(hero.owner), reward)
	state.event.emit({"kind": "monster_loot", "hero": hero.uid, "monster": monster.uid, "resources": draws})
	return draws

func _fail(message: String) -> bool:
	error = message
	return false
