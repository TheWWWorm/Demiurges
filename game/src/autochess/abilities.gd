class_name ELAutochessAbilities
extends RefCounted
## Etherlords II creature abilities adapted to real-time autochess battles.
## Activated abilities ("forced rest: ...") become actions with a recharge;
## static abilities become auras, on-hit effects or triggers. Strength is a
## multiple of the creature's ability budget (ELAutochessRules.ABILITY_BUDGET).
##
## Kinds:
##   bolt     damage one enemy (target: current/farthest/attacker)
##   nova     damage every enemy matching "filter" (ground/flying/all)
##   execute  finish an enemy below a health share, otherwise damage it
##   stun     stop enemies acting (target/frontline/race)
##   silence  delay an enemy's abilities and damage it
##   rally    hasten allies of a race
##   drain    damage an enemy and heal the caster
##   dispel   damage an enemy and remove its bonuses
##   revive   return a fallen ally (optional race/maximum price) once
## Passive "kind"s: aura (race bonus at the bell), poison, venom, weaken, burn,
## grow, silence_hit, corpse_eater, rise, death_aura, parasite, fatalist.

const RANGED := ["AVSC", "AVMK", "AVEL", "RVHL", "SEHL", "SWHL", "PTRS", "RFPT", "BEHD", "BHWR", "BHMO",
	"GRDG", "BUDG", "RDDG", "BLDG", "CCLP", "KBSH", "LMWK"]

const ABILITIES := {
	"KBWR": {"kind": "aura", "race": "Kobold", "attack": 0.15},
	"KBEL": {"kind": "rally", "race": "Kobold", "haste": 0.4, "seconds": 4.0, "cooldown": 8.0, "start": 2.0},
	"KBSH": {"kind": "bolt", "scale": 0.6, "cooldown": 4.0, "start": 1.5},
	"DRAT": {"kind": "corpse_eater", "heal": 0.08, "radius": 6.0},
	"PRAT": {"kind": "corpse_eater", "heal": 0.14, "radius": 7.0},
	"DMRT": {"kind": "revive", "race": "Rat", "health": 0.5, "cooldown": 6.0, "start": 3.0},
	"GRSN": {"kind": "grow", "attack": 0.05, "limit": 8},
	"LASN": {"kind": "weaken", "attack": 0.15, "seconds": 4.0},
	"SWSN": {"kind": "poison", "share": 0.3, "seconds": 3.0},
	"TRSN": {"kind": "poison", "share": 0.3, "seconds": 3.0},
	"GBGN": {"kind": "silence_hit", "seconds": 2.0},
	"BEWK": {"kind": "aura", "race": "Bee", "attack": 0.2},
	"BEQN": {"kind": "aura", "race": "Bee", "attack": 0.15, "health": 0.15},
	"ORWR": {"kind": "aura", "race": "Orc", "attack": 0.1, "health": 0.1},
	"OREL": {"kind": "aura", "race": "Orc", "haste": 0.15},
	"VBAT": {"kind": "drain", "scale": 0.55, "per_race": "Bat", "cooldown": 7.0, "start": 3.0},
	"AVMK": {"kind": "bolt", "scale": 0.9, "target": "attacker", "cooldown": 5.0, "start": 2.0},
	"AVEL": {"kind": "aura", "race": "Aviak", "attack": 0.12, "health": 0.12},
	"RVHL": {"kind": "silence", "scale": 0.4, "seconds": 2.0, "cooldown": 7.0, "start": 2.0},
	"SEHL": {"kind": "silence", "scale": 0.5, "seconds": 3.0, "cooldown": 7.0, "start": 2.0},
	"SWHL": {"kind": "silence", "scale": 0.6, "seconds": 4.0, "cooldown": 7.0, "start": 2.0},
	"MNHP": {"kind": "rise", "deaths": 3, "health": 0.4},
	"HOPR": {"kind": "rise", "deaths": 3, "health": 0.5},
	"MXHP": {"kind": "rise", "deaths": 3, "health": 0.6},
	"MAHO": {"kind": "venom", "share": 0.15, "seconds": 4.0, "threshold": 0.2},
	"MYHO": {"kind": "venom", "share": 0.15, "seconds": 4.0, "threshold": 0.25},
	"SHSP": {"kind": "rally", "race": "Spirit", "haste": 0.35, "seconds": 4.0, "health": 0.15, "cooldown": 9.0, "start": 2.5},
	"WZSP": {"kind": "aura", "race": "Spirit", "attack": 0.2, "health": 0.0},
	"CLSP": {"kind": "revive", "race": "Spirit", "health": 0.5, "aura": 0.1, "cooldown": 8.0, "start": 3.0},
	"PTRS": {"kind": "dispel", "scale": 0.7, "cooldown": 6.0, "start": 2.0},
	"RFPT": {"kind": "dispel", "scale": 0.8, "cooldown": 6.0, "start": 2.0},
	"BRMC": {"kind": "venom", "share": 0.1, "seconds": 4.0, "threshold": 0.12},
	"IRMC": {"kind": "venom", "share": 0.1, "seconds": 4.0, "threshold": 0.15},
	"STMC": {"kind": "venom", "share": 0.1, "seconds": 4.0, "threshold": 0.18},
	"MNTS": {"kind": "stun", "mode": "target", "seconds": 1.6, "scale": 0.3, "cooldown": 8.0, "start": 3.0},
	"MTSC": {"kind": "stun", "mode": "frontline", "seconds": 1.3, "scale": 0.25, "cooldown": 10.0, "start": 3.0},
	"MTPT": {"kind": "stun", "mode": "race", "seconds": 1.6, "scale": 0.3, "cooldown": 11.0, "start": 3.0},
	"LMMN": {"kind": "revive", "race": "Lamia", "health": 0.6, "cooldown": 6.0, "start": 3.0},
	"LMWD": {"kind": "aura", "race": "Lamia", "attack": 0.15},
	"LMWK": {"kind": "bolt", "scale": 1.0, "cooldown": 5.0, "start": 2.0},
	"BEHD": {"kind": "execute", "threshold": 0.12, "per_race": "Beholder", "per": 0.04, "scale": 0.8, "cooldown": 9.0, "start": 3.0},
	"BHWR": {"kind": "execute", "threshold": 0.15, "per_race": "Beholder", "per": 0.04, "scale": 1.0, "pick": "weakest_attack", "cooldown": 9.0, "start": 3.0},
	"BHMO": {"kind": "aura", "race": "Beholder", "attack": 0.15, "elusive": true},
	"FREL": {"kind": "burn", "seconds": 4.0},
	"BRMZ": {"kind": "parasite", "share": 0.008},
	"IRMZ": {"kind": "parasite", "share": 0.008},
	"STMZ": {"kind": "parasite", "share": 0.008},
	"GRDG": {"kind": "bolt", "scale": 1.6, "target": "toughest", "cooldown": 10.0, "start": 3.0},
	"BUDG": {"kind": "nova", "filter": "flying", "scale": 1.0, "fallback": 0.6, "cooldown": 9.0, "start": 3.0},
	"RDDG": {"kind": "nova", "filter": "ground", "scale": 0.85, "cooldown": 9.0, "start": 3.0},
	"BLDG": {"kind": "execute", "threshold": 0.25, "scale": 1.0, "cooldown": 9.0, "start": 3.0},
	"CCLP": {"kind": "bolt", "scale": 1.3, "target": "farthest", "cooldown": 6.0, "start": 2.5},
	"WKHR": {"kind": "death_aura", "scale": 0.45},
	"FMFI": {"kind": "revive", "max_tier": 3, "health": 0.5, "cooldown": 8.0, "start": 3.0},
	"MLFI": {"kind": "revive", "max_tier": 5, "health": 0.5, "cooldown": 8.0, "start": 3.0},
	"TIWK": {"kind": "aura", "race": "Tick", "attack": 0.2},
	"TIQN": {"kind": "aura", "race": "Tick", "attack": 0.2, "health": 0.2},
	"SMVL": {"kind": "fatalist", "seconds": 6.0},
	"BGVL": {"kind": "fatalist", "seconds": 8.0},
	"WNHR": {"kind": "bolt", "scale": 1.3, "target": "toughest", "cooldown": 8.0, "start": 3.0},
	"EHUN": {"kind": "bolt", "scale": 1.6, "target": "toughest", "cooldown": 7.0, "start": 2.5},
}

const ACTIVE := ["bolt", "nova", "execute", "stun", "silence", "rally", "drain", "dispel", "revive"]

static var _clips: Dictionary = {}

static func ability(code: String) -> Dictionary:
	return ABILITIES.get(code, {})

static func active(code: String) -> bool:
	return String(ability(code).get("kind", "")) in ACTIVE

static func ranged_code(code: String) -> bool:
	return code in RANGED

## Attack and ability clip lengths (frames at 30 fps) and impact frames from
## the creature's animation table, without building its model.
static func clip_info(profile: ELProfile, code: String) -> Dictionary:
	var key := profile.root + "|" + code
	if _clips.has(key): return _clips[key]
	var row: Dictionary = profile.table("CombatCreatures").get(code, {})
	var info := {}
	var model := ELArchive.key(String(row.get("Model", "")))
	if not model.is_empty():
		var table := ELModel.animation_table(profile.read("animdb", model + ".adb"))
		if table.has("uattack"):
			info["attack"] = int(table.uattack.frames)
			info["attack_impact"] = int(table.uattack.impact) if int(table.uattack.impact) > 0 else int(table.uattack.frames) / 2
		if table.has("uinstant"):
			info["cast"] = int(table.uinstant.frames)
			info["cast_impact"] = int(table.uinstant.impact) if int(table.uinstant.impact) > 0 else int(table.uinstant.frames) / 2
		if table.has("udeath"): info["death"] = int(table.udeath.frames)
	_clips[key] = info
	return info

## A short description of the ability for the inspector, in English (the
## screen translates it).
static func describe(code: String, power: float) -> String:
	var a := ability(code)
	var value := roundi(power * float(a.get("scale", 1.0)))
	match String(a.get("kind", "")):
		"aura":
			var parts: Array[String] = []
			if a.has("attack") and float(a.attack) > 0: parts.append("+%d%% attack" % roundi(float(a.attack) * 100))
			if a.has("health") and float(a.health) > 0: parts.append("+%d%% health" % roundi(float(a.health) * 100))
			if a.has("haste"): parts.append("+%d%% attack speed" % roundi(float(a.haste) * 100))
			if a.get("elusive", false): parts.append("reach the back line")
			return "Aura: %s to allied %s." % [", ".join(parts), race_title(String(a.race))]
		"rally": return "Rally: allied %s attack %d%% faster for %d s." % [race_title(String(a.race)), roundi(float(a.haste) * 100), roundi(float(a.seconds))]
		"bolt": return "Strike: %d damage to %s." % [value, {"farthest": "the farthest enemy", "toughest": "the toughest enemy", "attacker": "an attacking enemy"}.get(String(a.get("target", "")), "its target")]
		"nova": return "Breath: %d damage to every %s enemy." % [value, {"flying": "flying", "ground": "ground"}.get(String(a.filter), "")]
		"execute": return "Destroys an enemy below %d%% health, otherwise deals %d damage." % [roundi(float(a.threshold) * 100), value]
		"stun": return "Fright: stops %s for %.1f s." % [{"target": "its target", "frontline": "enemies fighting in melee", "race": "enemies of the target's race"}.get(String(a.mode), ""), float(a.seconds)]
		"silence": return "Ether thief: %d damage; the target cannot use abilities for %d s." % [value, roundi(float(a.seconds))]
		"drain": return "Taste of blood: drains %d health per allied bat." % value
		"dispel": return "Piercing gaze: %d damage and removes the target's bonuses." % value
		"revive": return "Returns a fallen ally%s with %d%% health." % [(" (" + race_title(String(a.race)) + ")") if a.has("race") else "", roundi(float(a.health) * 100)]
		"poison": return "Snake venom: hits deal %d%% more damage over %d s." % [roundi(float(a.share) * 100), roundi(float(a.seconds))]
		"venom": return "Venom: a struck enemy still below %d%% health %d s later dies (not 3-star or 5-cost creatures)." % [roundi(float(a.threshold) * 100), roundi(float(a.seconds))]
		"weaken": return "Poisonous bite: hits reduce the target's attack by %d%%." % roundi(float(a.attack) * 100)
		"burn": return "Burn: wounded enemies cannot regenerate for %d s." % roundi(float(a.seconds))
		"grow": return "Bloodsucker: each hit adds %d%% attack." % roundi(float(a.attack) * 100)
		"silence_hit": return "Robber: hits stop the target's abilities for %d s." % roundi(float(a.seconds))
		"corpse_eater": return "Corpse eater: heals %d%% when a creature dies nearby." % roundi(float(a.heal) * 100)
		"rise": return "Rises from the dead once after %d creatures fall." % int(a.deaths)
		"death_aura": return "Aura of death: %d damage to every creature when it enters and when it dies." % value
		"parasite": return "Parasite: loses health over time."
		"fatalist": return "Fatalist: falls if no enemy wounds it for %d s." % roundi(float(a.seconds))
	return ""

static func race_title(race: String) -> String:
	return {"Kobold": "kobolds", "Rat": "rats", "Bee": "bees", "Orc": "orcs", "Bat": "bats", "Aviak": "aviaks",
		"Spirit": "spirits", "Lamia": "lamias", "Beholder": "beholders", "Tick": "ticks"}.get(race, race.to_lower())
