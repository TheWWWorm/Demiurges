class_name ELAutochessRules
extends RefCounted
## Etherlords II autochess: the tables shared by the shop, the computer
## players, the battle simulation and the interface. The economy, levels,
## shop odds, recruit pool and player damage follow the Cursed Lands
## autochess mode; the recruits are Etherlords II creature lines whose stats
## come from their original Power and Toughness inside per-price budgets.

const VERSION := 1
const PLAYER_COUNT := 9
const MAX_ROUNDS := 100
const PREPARATION_SECONDS := 45.0
const BATTLE_SECONDS := 90.0
## A fight in which nobody deals damage for this long is a draw.
const QUIET_DRAW_SECONDS := 10.0
const OPENING_ETHER := 10
const MIN_RECRUIT_COST := 1
const BASE_INCOME := 5
const WIN_INCOME := 1
const INTEREST_CAP := 5
const TRAINING_COST := 5
const TRAINING_XP := 5
const REFRESH_COST := 2
const MAX_ARMY := 9
const BENCH_LIMIT := 8
const SHOP_SLOTS := 5
const START_HEALTH := 100
const DRAW_DAMAGE := 10
## Cumulative experience from the opening level 3 (Cursed Lands values).
const LEVEL_XP := [0, 0, 0, 0, 6, 18, 36, 55, 80, 110]
const MAX_TRAINING: int = LEVEL_XP[MAX_ARMY]
const SHOP_ODDS := {
	3: [55, 45, 0, 0, 0], 4: [55, 45, 0, 0, 0],
	5: [40, 40, 20, 0, 0], 6: [30, 35, 27, 8, 0],
	7: [22, 28, 28, 20, 2], 8: [15, 20, 25, 30, 10],
	9: [10, 15, 25, 35, 15],
}
## Copies of every line in the shared pool by price tier.
const POOL_COPIES := [45, 30, 25, 20, 10]
## Board space in metres. Each company deploys in the left part of its own
## board; the opponent arrives mirrored on the right.
const FIELD := Rect2(-15.0, -10.0, 30.0, 20.0)
const DEPLOY := Rect2(-13.0, -9.0, 10.5, 18.0)
const DEPLOY_SPACING := 1.4

## Recruit lines: one price, three original creature forms (one per star).
## "role": Melee fights in contact; Ranged attacks from a distance.
## "health"/"damage"/"defense" are species modifiers inside the price budget.
const FAMILIES := [
	{"key": "kobolds", "cost": 1, "color": "Red", "role": "Melee", "forms": ["KBWR", "KBGD", "KBEL"], "health": 1.08, "damage": 1.0, "defense": 1.0},
	{"key": "rats", "cost": 1, "color": "Red", "role": "Melee", "forms": ["STRT", "DRAT", "PRAT"], "health": 0.95, "damage": 1.15, "defense": 0.8},
	{"key": "snakes", "cost": 1, "color": "Green", "role": "Melee", "forms": ["GRSN", "LASN", "SWSN"], "health": 0.9, "damage": 1.1, "defense": 0.8},
	{"key": "gibberlings", "cost": 1, "color": "Blue", "role": "Melee", "forms": ["GBBR", "GBIN", "GBGN"], "health": 0.85, "damage": 1.3, "defense": 0.7},
	{"key": "mechworms", "cost": 1, "color": "Black", "role": "Melee", "forms": ["MCWO", "MCWU", "MCWY"], "health": 1.05, "damage": 1.0, "defense": 1.1},
	{"key": "treants", "cost": 1, "color": "Green", "role": "Melee", "forms": ["TNSA", "TANT", "GRTN"], "health": 1.3, "damage": 1.0, "defense": 1.2},
	{"key": "wheelers", "cost": 1, "color": "Black", "role": "Melee", "forms": ["SMVL", "BGVL", "BGVL"], "health": 0.75, "damage": 1.35, "defense": 0.85},
	{"key": "bees", "cost": 1, "color": "Green", "role": "Melee", "forms": ["BEWR", "BEWK", "BEQN"], "health": 0.85, "damage": 1.05, "defense": 0.7},
	{"key": "wolves", "cost": 2, "color": "Red", "role": "Melee", "forms": ["NWLF", "SHWL", "SHWL"], "health": 0.95, "damage": 1.2, "defense": 0.8},
	{"key": "orcs", "cost": 2, "color": "Red", "role": "Melee", "forms": ["ORGD", "ORWR", "OREL"], "health": 1.1, "damage": 1.0, "defense": 1.1},
	{"key": "bats", "cost": 2, "color": "Red", "role": "Melee", "forms": ["BATT", "GBAT", "VBAT"], "health": 0.95, "damage": 1.1, "defense": 0.8},
	{"key": "aviaks", "cost": 2, "color": "Blue", "role": "Ranged", "forms": ["AVSC", "AVMK", "AVEL"], "health": 0.85, "damage": 0.9, "defense": 0.75},
	{"key": "halos", "cost": 2, "color": "Blue", "role": "Ranged", "forms": ["RVHL", "SEHL", "SWHL"], "health": 1.05, "damage": 1.15, "defense": 0.8},
	{"key": "hoppers", "cost": 2, "color": "Black", "role": "Melee", "forms": ["MNHP", "HOPR", "MXHP"], "health": 1.06, "damage": 1.1, "defense": 1.0},
	{"key": "ticks", "cost": 2, "color": "Green", "role": "Melee", "forms": ["TIWK", "TIWR", "TIQN"], "health": 1.0, "damage": 1.05, "defense": 0.9},
	{"key": "hornets", "cost": 2, "color": "Green", "role": "Melee", "forms": ["MAHO", "MYHO", "MYHO"], "health": 0.85, "damage": 1.15, "defense": 0.75},
	{"key": "spirits", "cost": 3, "color": "Blue", "role": "Melee", "forms": ["WRSP", "SHSP", "WZSP"], "health": 0.95, "damage": 1.05, "defense": 0.85},
	{"key": "pteros", "cost": 3, "color": "Black", "role": "Ranged", "forms": ["PTRS", "RFPT", "RFPT"], "health": 0.95, "damage": 0.95, "defense": 0.88},
	{"key": "mechos", "cost": 3, "color": "Black", "role": "Melee", "forms": ["BRMC", "IRMC", "STMC"], "health": 1.02, "damage": 0.98, "defense": 1.02},
	{"key": "spawns", "cost": 3, "color": "Black", "role": "Melee", "forms": ["BRAB", "IRAB", "STAB"], "health": 1.22, "damage": 1.02, "defense": 1.05},
	{"key": "ogres", "cost": 3, "color": "Red", "role": "Melee", "forms": ["GROG", "OGKN", "OGKN"], "health": 1.22, "damage": 1.12, "defense": 1.05},
	{"key": "mantises", "cost": 3, "color": "Green", "role": "Melee", "forms": ["MNTS", "MTSC", "MTPT"], "health": 1.02, "damage": 1.0, "defense": 0.97},
	{"key": "lamias", "cost": 4, "color": "Blue", "role": "Melee", "forms": ["LMMN", "LMWA", "LMWD"], "health": 1.24, "damage": 1.28, "defense": 1.08},
	{"key": "huntresses", "cost": 4, "color": "White", "role": "Melee", "forms": ["WNHR", "WNHR", "EHUN"], "health": 1.1, "damage": 1.18, "defense": 1.0},
	{"key": "beholders", "cost": 4, "color": "Green", "role": "Ranged", "forms": ["BEHD", "BHWR", "BHMO"], "health": 0.9, "damage": 0.95, "defense": 0.8},
	{"key": "elementals", "cost": 4, "color": "Blue", "role": "Melee", "forms": ["FREL", "EREL", "WTEL"], "health": 1.3, "damage": 1.07, "defense": 1.15},
	{"key": "cutters", "cost": 4, "color": "Black", "role": "Melee", "forms": ["CTMN", "SWMN", "RZMN"], "health": 0.95, "damage": 1.2, "defense": 1.0},
	{"key": "mechozaurs", "cost": 4, "color": "Black", "role": "Melee", "forms": ["BRMZ", "IRMZ", "STMZ"], "health": 1.14, "damage": 1.12, "defense": 1.05},
	{"key": "dragons", "cost": 5, "color": "Blue", "role": "Ranged", "forms": ["GRDG", "BUDG", "RDDG"], "health": 1.05, "damage": 1.0, "defense": 1.0},
	{"key": "cyclopes", "cost": 5, "color": "Red", "role": "Ranged", "forms": ["CCLP", "CCLP", "CCLP"], "health": 1.32, "damage": 1.22, "defense": 1.08},
	{"key": "horrors", "cost": 5, "color": "Black", "role": "Melee", "forms": ["WKHR", "WKHR", "WKHR"], "health": 1.0, "damage": 0.95, "defense": 1.0},
	{"key": "necromancers", "cost": 5, "color": "Black", "role": "Melee", "forms": ["FMFI", "MLFI", "MLFI"], "health": 1.0, "damage": 1.0, "defense": 1.0},
	{"key": "colorless", "cost": 5, "color": "White", "role": "Melee", "forms": ["SMFX", "SMTG", "SMWB"], "health": 1.05, "damage": 1.1, "defense": 1.0},
]

## Per-price budgets (Cursed Lands Trials values, divided between Power and
## Toughness of the original card instead of between armor types).
const HEALTH_BUDGET := [44.0, 60.0, 78.0, 99.0, 122.0]
const DAMAGE_BUDGET := [13.0, 16.0, 20.0, 24.0, 29.0]
const STAR_HEALTH := [1.0, 2.1, 5.0]
## Every creature's health is doubled so fights last long enough to read.
const HEALTH_SCALE := 2.0
const STAR_DAMAGE := [1.0, 1.75, 4.0]
const ROLE_HEALTH := {"Melee": 1.0, "Ranged": 0.85}
const RANGED_REACH := 7.0
## Abilities spend this share of their tier's damage budget per cast.
const ABILITY_BUDGET := [16.0, 22.0, 28.0, 34.0, 40.0]

## Original creature flags kept in battle (see ELAutochessBattle).
const KEPT_FLAGS := ["Fly", "FS", "Trample", "Berserk", "Restless", "Lifetap", "Elusive", "UB", "Disenchant",
	"TeamAttack", "NoUntap", "Destroy", "NSS", "NoTarget", "NoAffect", "Outerplanar"]

## Creep rounds (1-3 and every fifth): wild Etherlords creatures at a fixed
## price/star budget. Each entry: [code, tier, star].
const CREEPS := [
	[["STRT", 1, 0], ["STRT", 1, 0]],
	[["NWLF", 2, 0], ["NWLF", 2, 0], ["KBWR", 1, 0]],
	[["ORGD", 2, 0], ["KBGD", 1, 0], ["KBGD", 1, 0], ["KBSH", 1, 0]],
	[["TIWR", 2, 1], ["TIWR", 2, 1], ["TIQN", 2, 0], ["BEWR", 1, 1], ["BEWR", 1, 1]],
	[["GROG", 3, 1], ["ORWR", 2, 1], ["ORWR", 2, 1], ["BATT", 2, 1], ["KBSH", 2, 1]],
	[["MCWY", 3, 1], ["IRMC", 3, 1], ["IRMC", 3, 1], ["PTRS", 3, 1], ["BRMZ", 4, 1], ["PTRS", 3, 1]],
	[["LMWA", 4, 1], ["LMWA", 4, 1], ["LMWK", 4, 1], ["SEHL", 3, 1], ["SEHL", 3, 1], ["AVMK", 3, 1], ["CLSP", 3, 1]],
	[["MTPT", 4, 1], ["BHMO", 4, 1], ["ANTN", 4, 1], ["ANTN", 4, 1], ["MYHO", 3, 2], ["MYHO", 3, 2], ["MTSC", 4, 1]],
	[["RDDG", 5, 1], ["GRDG", 5, 1], ["OGKN", 4, 2], ["LMWD", 4, 2], ["FREL", 4, 2], ["WTEL", 4, 2], ["VBAT", 3, 2], ["CCLP", 5, 1]],
	[["WKHR", 5, 2], ["MLFI", 5, 2], ["STMZ", 5, 2], ["RZMN", 5, 2], ["STMC", 4, 2], ["STMC", 4, 2], ["RFPT", 4, 2], ["BLDG", 5, 2], ["RDKN", 5, 2]],
]


static func family(index: int) -> Dictionary:
	return FAMILIES[index] if index >= 0 and index < FAMILIES.size() else {}

static func tier(index: int) -> int:
	return int(family(index).get("cost", 1))

static func form(index: int, rank: int) -> String:
	var row := family(index)
	if row.is_empty(): return ""
	return String(row.forms[clampi(rank, 0, 2)])

static func family_of(code: String) -> int:
	for index in FAMILIES.size():
		if code in FAMILIES[index].forms: return index
	return -1

static func evolution_copies(index: int, rank: int) -> int:
	return 3 if index >= 0 and rank < 2 else 0

static func rank_copies(_index: int, rank: int) -> int:
	return [1, 3, 9][clampi(rank, 0, 2)]

static func pool_size(index: int) -> int:
	return int(POOL_COPIES[clampi(tier(index) - 1, 0, POOL_COPIES.size() - 1)])

static func level_for_xp(xp: int) -> int:
	var level := 3
	while level < MAX_ARMY and xp >= int(LEVEL_XP[level + 1]): level += 1
	return level

static func recruit_pool(level: int) -> Array[int]:
	var pool: Array[int] = []
	var odds: Array = SHOP_ODDS[clampi(level, 3, MAX_ARMY)]
	for index in FAMILIES.size():
		if int(odds[tier(index) - 1]) > 0: pool.append(index)
	return pool

static func is_creep_round(round_number: int) -> bool:
	return round_number <= 3 or round_number % 5 == 0

## Underlords player damage: floor(round / 10) plus, per surviving recruit,
## 1 + floor((tier + 2 * zero-based star) / 3). Neutral creatures that
## survive count the same way by their tier and stars, so losing a neutral
## round costs health too.
static func survivor_damage(index: int, rank: int) -> int:
	if index < 0: return 0
	return 1 + (tier(index) + 2 * clampi(rank, 0, 2)) / 3

static func defeat_damage(round_number: int, survivors: int) -> int:
	return round_number / 10 + maxi(0, survivors)

static func draw_damage(_round_number: int) -> int:
	return DRAW_DAMAGE

static func creeps(round_number: int, seed_value: int) -> Array[Dictionary]:
	var index := 0
	if round_number > 3: index = mini(CREEPS.size() - 1, 2 + round_number / 5)
	else: index = round_number - 1
	var rows: Array = CREEPS[clampi(index, 0, CREEPS.size() - 1)]
	var flip := -1.0 if (seed_value + round_number) % 2 else 1.0
	var out: Array[Dictionary] = []
	var front := 0
	var back := 0
	for row: Array in rows:
		var ranged := ELAutochessAbilities.ranged_code(String(row[0]))
		var count := back if ranged else front
		var lane: float = [0.0, -3.5, 3.5, -7.0, 7.0][count % 5]
		var point := Vector2((9.5 if ranged else 5.5) + (2.5 if count >= 5 else 0.0), flip * lane)
		out.append({"code": String(row[0]), "tier": int(row[1]), "rank": int(row[2]), "family": -1, "point": [point.x, point.y], "creep": true})
		if ranged: back += 1
		else: front += 1
	return out

## Original Power/Toughness of a creature code (zero-power support forms
## count as one).
static func original(profile: ELProfile, code: String) -> Dictionary:
	return profile.table("CombatCreatures").get(code, {})

static func flags(profile: ELProfile, code: String) -> Array[String]:
	var raw: Variant = original(profile, code).get("Flags", [])
	var list: Array = [raw] if raw is String else raw
	var result: Array[String] = []
	for value: Variant in list:
		var name := String(value)
		var base := name.get_slice("(", 0)
		if base in KEPT_FLAGS and base not in result: result.append(base)
		elif base == "Regen" and "Regen" not in result: result.append("Regen")
	return result

static func regeneration(profile: ELProfile, code: String) -> int:
	var raw: Variant = original(profile, code).get("Flags", [])
	var list: Array = [raw] if raw is String else raw
	for value: Variant in list:
		var name := String(value)
		if name.begins_with("Regen("): return int(name.get_slice("(", 1).trim_suffix(")"))
	return 0

## Combat values of one creature at `tier` and zero-based `star`.
## Health and damage come from the budget; the original Power/Toughness
## ratio decides how the budget is split, so a 1/3 guard is sturdy and a
## 4/1 gang hits hard.
static func stats(profile: ELProfile, code: String, unit_tier: int, star: int, index := -1) -> Dictionary:
	var row := original(profile, code)
	var power := maxf(0.5, float(row.get("Power", 1)))
	var toughness := maxf(0.5, float(row.get("Toughness", 1)))
	var share := power / (power + toughness)
	var species := family(index) if index >= 0 else {}
	var role := String(species.get("role", "Ranged" if ELAutochessAbilities.ranged_code(code) else "Melee"))
	var t := clampi(unit_tier, 1, 5) - 1
	var s := clampi(star, 0, 2)
	var health: float = HEALTH_BUDGET[t] * (0.55 + 0.9 * (1.0 - share)) * float(ROLE_HEALTH.get(role, 1.0))
	health *= float(species.get("health", 1.0)) * STAR_HEALTH[s] * HEALTH_SCALE
	var damage: float = DAMAGE_BUDGET[t] * (0.55 + 0.9 * share) * float(species.get("damage", 1.0)) * STAR_DAMAGE[s]
	var list := flags(profile, code)
	# Original attack timing: the attack clip at the original 30 fps, never
	# faster than 0.9 s or slower than 2.2 s. Slow clips hit harder.
	var interval := 1.35
	var model := ELAutochessAbilities.clip_info(profile, code)
	if model.has("attack"): interval = clampf(float(model.attack) / 30.0 + 0.35, 0.9, 2.2)
	damage *= clampf(interval / 1.35, 0.85, 1.5)
	# Ranged creatures pay for their safety with health, not damage.
	if role == "Ranged": damage *= 1.3
	else: damage *= 1.1
	if "NoUntap" in list:
		interval *= 1.45
		damage *= 1.45
	if "Berserk" in list: interval *= 0.9
	if "Restless" in list: interval *= 0.95
	var defense := (1.5 + t * 1.25) * float(species.get("defense", 1.0)) * (1.0 + s * 0.2)
	var reach := RANGED_REACH if role == "Ranged" else maxf(1.5, float(row.get("AtRange", 1.5)) * float(row.get("Scale", 1.0)) * 0.9)
	var speed := 3.2
	if "Fly" in list: speed = 4.0
	if "NSS" in list: speed += 0.6
	return {"code": code, "role": role, "tier": unit_tier, "star": s,
		"health": ceilf(health), "damage": snappedf(damage, 0.1), "defense": snappedf(defense, 0.1),
		"interval": snappedf(interval, 0.01), "reach": snappedf(reach, 0.01), "speed": speed,
		"regen": regeneration(profile, code), "flags": list,
		"ability": ELAutochessAbilities.ability(code), "ability_power": ABILITY_BUDGET[t] * STAR_DAMAGE[s] * float(species.get("damage", 1.0)),
		"power": int(row.get("Power", 0)), "toughness": int(row.get("Toughness", 0))}

static func title(profile: ELProfile, code: String) -> String:
	var spell: Dictionary = profile.table("CombatSpells").get(code, {})
	var key := String(spell.get("Name", ""))
	var text := profile.text(key) if not key.is_empty() else ""
	if text.is_empty() or text == key: return code
	return text

static func family_title(profile: ELProfile, index: int) -> String:
	return title(profile, form(index, 0))

## A board formation from saved army rows; the opponent is mirrored.
static func formation(rows: Array, team: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in rows:
		if not entry.get("deployed", false): continue
		var point := Vector2(float(entry.point[0]), float(entry.point[1]))
		if team == 1: point = Vector2(-point.x, -point.y)
		result.append({"code": String(entry.code), "family": int(entry.family), "rank": int(entry.rank),
			"tier": tier(int(entry.family)), "point": [point.x, point.y], "uid": int(entry.uid), "item": String(entry.get("item", ""))})
	return result

static func available(profile: ELProfile) -> bool:
	if profile == null or profile.id != "el2": return false
	var creatures := profile.table("CombatCreatures")
	for row: Dictionary in FAMILIES:
		for code: String in row.forms:
			if not creatures.has(code): return false
	return true
