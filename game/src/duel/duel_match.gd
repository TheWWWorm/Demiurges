class_name ELDuelMatch
extends RefCounted
## Duel-mode match bookkeeping: N rounds (1-99), all of them played (not
## best-of-N), each a fresh battle from the same presets.
##
## First attacker: every single-player round is a fresh battle object with its
## own rand(), so the first side is an independent coin flip per round (no
## level rule; the manual's alternation exists only for network duels). A
## Random arena is likewise an independent pick per round.

const MAX_ROUNDS := 99
const RANDOM := ""

var edition := ""
var resource_level := 1
var rounds := 1
## Arena id, or RANDOM for a new pick each round.
var arena := RANDOM
## The two resolved presets (full dictionaries, so a later edit or deletion
## of a user preset does not change a match in progress).
var presets: Array = [{}, {}]
## Cosmetic hero templates; "" = the heroes.def default.
var templates: Array = ["", ""]
var seed_value := 0
var played := 0
var wins: Array[int] = [0, 0]
var draws := 0
var rng_state := 0
## Hot seat (MultiplayerStart -> HotSeat): both sides are local human players
## who take the screen in turn; `names` are the two players' names.
var hot_seat := false
var names: Array = ["", ""]

## Presets the Random choice draws from: exactly the current level.
static func random_pool(pool: Array, level: int) -> Array:
	return pool.filter(func(p: Dictionary): return int(p.resource_level) == level)

## A side's choice (a preset, or {} for Random) is valid at `level`.
static func side_valid(pool: Array, pick: Dictionary, level: int) -> bool:
	if pick.is_empty(): return not random_pool(pool, level).is_empty()
	return int(pick.resource_level) <= level

static func can_start(pool: Array, picks: Array, level: int) -> bool:
	return side_valid(pool, picks[0], level) and side_valid(pool, picks[1], level)

## Arena ids in list order (the Random entry is not included).
static func arenas(profile: ELProfile) -> Array[String]:
	var result: Array[String] = []
	for id: String in profile.table("ScenesNames"):
		if profile.table("CombatSceneDB").has(id): result.append(id)
	return result

## The original CRT rand(): MSVC linear congruential generator.
func _rand() -> int:
	rng_state = (rng_state * 214013 + 2531011) & 0xffffffff
	return (rng_state >> 16) & 0x7fff

## Validates the screen state and resolves Random presets (side 0 first).
## `picks` holds a preset or {} for Random per side. Returns "" or an error.
func begin(profile: ELProfile, pool: Array, picks: Array, level: int, round_count: int, arena_id := RANDOM, seed := 0, hero_templates: Array = ["", ""]) -> String:
	var levels := ELDuelCosts.resource_levels(profile)
	if level < levels.x or level > levels.y: return "Resource level out of range."
	if round_count < 1 or round_count > MAX_ROUNDS: return "Rounds out of range."
	if arena_id != RANDOM and not arenas(profile).has(arena_id): return "Unknown arena."
	if not can_start(pool, picks, level): return "Choose a preset for each side."
	edition = profile.id
	resource_level = level
	rounds = round_count
	arena = arena_id
	templates = hero_templates.duplicate()
	rng_state = seed & 0xffffffff
	for side in 2:
		if picks[side].is_empty():
			var candidates := random_pool(pool, level)
			presets[side] = candidates[_rand() % candidates.size()].duplicate(true)
			templates[side] = ""
		else:
			presets[side] = picks[side].duplicate(true)
	# Seeds the per-round arena choice, as the original draws one rand() at duel start.
	seed_value = _rand()
	played = 0
	wins = [0, 0]
	draws = 0
	return ""

## Round `index`'s own random value number `salt`: a pure function of the
## match seed, so a round's draws repeat after save/load and do not depend on
## how often the screen asks. Stands in for the fresh rand() of each round's
## battle object (exact rand() sequences are not reproduced).
func round_random(index: int, salt: int) -> int:
	return (_mix(seed_value ^ _mix(index * 8 + salt + 1)) >> 16) & 0x7fff

## 32-bit avalanche mixer (MurmurHash3 finaliser).
static func _mix(value: int) -> int:
	var x := value & 0xffffffff
	x ^= x >> 16
	x = (x * 0x85ebca6b) & 0xffffffff
	x ^= x >> 13
	x = (x * 0xc2b2ae35) & 0xffffffff
	return x ^ (x >> 16)

## The side taking the first attack phase in the round about to be played.
func round_first_side() -> int:
	return round_random(played, 1) & 1

## The arena for the round about to be played.
func round_arena(profile: ELProfile) -> String:
	if arena != RANDOM: return arena
	var list := arenas(profile)
	return list[round_random(played, 2) % list.size()]

## Fresh ELDuel.start options for the current round.
func round_options(profile: ELProfile) -> Dictionary:
	var options := ELDuelPresets.options(profile, presets, round_arena(profile), templates)
	options.first_side = round_first_side()
	return options

## Starts the current round's battle; null with the duel's error on failure.
func start_round(profile: ELProfile, battle_seed := 212) -> ELDuel:
	var duel := ELDuel.new()
	if not duel.start(profile, battle_seed, round_options(profile)): return null
	return duel

func finished() -> bool:
	return played >= rounds

## Records a finished round: the winner's side, or -1 for a draw. Surrender
## concedes only the current round (record the opponent's win).
func record(winner: int) -> bool:
	if finished() or winner < -1 or winner > 1: return false
	if winner == -1: draws += 1
	else: wins[winner] += 1
	played += 1
	return true

## Final outcome for `side`: 1 win, -1 loss, 0 draw (equal wins).
func result(side := 0) -> int:
	return signi(wins[side] - wins[1 - side])

## A single-round duel ends like a normal battle; longer matches end on the
## duel results summary.
func shows_summary() -> bool:
	return rounds >= 2

func snapshot() -> Dictionary:
	return {"edition": edition, "resource_level": resource_level, "rounds": rounds, "arena": arena,
		"presets": presets.duplicate(true), "templates": templates.duplicate(), "seed": seed_value,
		"played": played, "wins": wins.duplicate(), "draws": draws, "rng_state": rng_state,
		"hot_seat": hot_seat, "names": names.duplicate()}

func restore(profile: ELProfile, data: Dictionary) -> bool:
	if data.get("edition") != profile.id: return false
	for key in ["resource_level", "rounds", "seed", "played", "draws", "rng_state"]:
		if not ELLuaSave._integer(data.get(key), 0, 0xffffffff): return false
	var w: Variant = data.get("wins")
	var p: Variant = data.get("presets")
	var t: Variant = data.get("templates", ["", ""])
	if w is not Array or w.size() != 2 or p is not Array or p.size() != 2 or t is not Array or t.size() != 2: return false
	if not ELLuaSave._integer(w[0], 0, MAX_ROUNDS) or not ELLuaSave._integer(w[1], 0, MAX_ROUNDS): return false
	var count := int(data.rounds)
	if count < 1 or count > MAX_ROUNDS or int(data.played) > count or int(w[0]) + int(w[1]) + int(data.draws) != int(data.played): return false
	var arena_id := String(data.get("arena", RANDOM))
	if arena_id != RANDOM and not arenas(profile).has(arena_id): return false
	# Saves from before hot seat have neither key: a single-player match.
	var hot: Variant = data.get("hot_seat", false)
	var n: Variant = data.get("names", ["", ""])
	if hot is not bool or n is not Array or n.size() != 2 or n[0] is not String or n[1] is not String: return false
	var restored: Array = []
	for side in 2:
		restored.append(ELDuelPresets.normalize(p[side]))
		if restored[side].is_empty(): return false
	edition = profile.id
	resource_level = int(data.resource_level)
	rounds = count
	arena = arena_id
	presets = restored
	templates = [String(t[0]), String(t[1])]
	seed_value = int(data.seed)
	played = int(data.played)
	wins = [int(w[0]), int(w[1])]
	draws = int(data.draws)
	rng_state = int(data.rng_state)
	hot_seat = hot
	names = [String(n[0]).left(64), String(n[1]).left(64)]
	return true
