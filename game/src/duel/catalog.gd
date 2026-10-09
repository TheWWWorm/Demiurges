class_name ELCatalog
extends RefCounted
## Behavioral definitions; names, costs, stats and art come from the mounted game.

const FACTIONS := {"Red": "Chaots", "Green": "Vitals", "Black": "Synthets", "Blue": "Kinets"}
const STARTERS := {"Red": "STR1", "Green": "STG1", "Black": "STB1", "Blue": "STU1"}
const HEROES := {"Red": "RedMaleWarrior2", "Green": "GreenMale1", "Black": "BlackMale1", "Blue": "BlueWingedMale1"}
const EFFECTS := {
	"ZAPP": {"effect": "damage", "target": "any", "amount": 1},
	"FRWA": {"effect": "wave", "target": "none", "amount": 1},
	"CLIG": {"effect": "damage", "target": "creature", "amount": 3},
	"TREM": {"effect": "wave", "target": "none", "amount": 2},
	"COMT": {"effect": "damage", "target": "any", "variable": true},
	"FRST": {"effect": "wave", "target": "none", "variable": true, "channels_el2": 2},
	"SNOV": {"effect": "wave", "target": "none", "variable": true, "scope": "all", "channels_el2": 1},
	"ERQA": {"effect": "wave", "target": "none", "variable": true, "scope": "ground"},
	"WNFL": {"effect": "wave", "target": "none", "variable": true, "scope": "flying"},
	"CTST": {"effect": "wave", "target": "none", "variable": true, "scope": "heroes"},
	"LSST": {"effect": "enchant", "target": "creature", "power": 1, "toughness": 1},
	"TWEN": {"effect": "enchant", "target": "creature", "power": 2, "toughness": 2},
	"SHCL": {"effect": "enchant", "target": "creature", "power": 2, "toughness": 0},
	"STAT": {"effect": "enchant", "target": "creature", "power": 1, "toughness": 0},
	"TGSK": {"effect": "enchant", "target": "creature", "power": 0, "toughness": 1},
	"ENFL": {"effect": "enchant", "target": "creature"},
	"DNFR": {"effect": "enchant", "target": "hero"},
	"LSDS": {"effect": "enchant", "target": "none", "self": true},
	"MNDP": {"effect": "mana", "target": "none", "amount": 2},
	"MNTP": {"effect": "mana", "target": "none", "amount": 3},
	"MNDW": {"effect": "mana", "target": "none", "amount": 4},
	"GEYS": {"effect": "channels", "target": "none", "amount": 1},
	"VOLC": {"effect": "channels", "target": "none", "amount": 3, "amount_el2": 2},
	"MNBR": {"effect": "channels", "target": "none", "amount": 2, "scope": "both"},
	"MNST": {"effect": "channels", "target": "none", "amount": 4, "scope": "both"},
	"SNRG": {"effect": "channels", "target": "none", "amount": 1},
	"SNCR": {"effect": "channels", "target": "none", "amount": 2},
	"SNHG": {"effect": "channels", "target": "none", "amount": 3},
	"BLNC": {"effect": "channels", "target": "none", "amount": 1, "amount_el2": 2, "scope": "behind"},
	"JUST": {"effect": "channels", "target": "none", "amount": 2, "amount_el2": 3, "scope": "behind"},
	"INCR": {"effect": "channels", "target": "none", "amount": 1, "scope": "enemy"},
	"LQRL": {"effect": "channels", "target": "none", "amount": 1, "scope": "steal"},
	"PWTP": {"effect": "drain_mana", "target": "none", "amount": 5},
	"BRRL": {"effect": "burn_mana", "target": "hero"},
	"JRRG": {"effect": "revive", "target": "none"},
	"LSUS": {"effect": "unsummon", "target": "creature", "maximum": 3},
	"CURS": {"effect": "discard_creatures", "target": "hero", "amount": 3},
	"LSHE": {"effect": "enchant", "target": "none", "self": true},
	"FRBL": {"effect": "enchant", "target": "none", "self": true},
	"RNST": {"effect": "enchant", "target": "none", "self": true},
	"ENRG": {"effect": "enchant", "target": "none", "self": true},
	"MNVR": {"effect": "enchant", "target": "none", "self": true},
	"MNTX": {"effect": "enchant", "target": "none", "self": true},
	"MNTH": {"effect": "enchant", "target": "none", "self": true},
	"MNBN": {"effect": "enchant", "target": "none", "self": true},
	"STSI": {"effect": "enchant", "target": "none", "self": true},
	"SPTR": {"effect": "enchant", "target": "none", "self": true},
	"SFGS": {"effect": "enchant", "target": "none", "self": true},
	"FTDS": {"effect": "enchant", "target": "none", "self": true},
	"WETX": {"effect": "enchant", "target": "hero"},
	"STTX": {"effect": "enchant", "target": "hero"},
	"ENVM": {"effect": "enchant", "target": "hero"},
	"UPGD": {"effect": "enchant", "target": "creature", "power": 2, "toughness": 2},
	"FAIL": {"effect": "enchant", "target": "creature", "power": -2, "toughness": 0},
	"DISM": {"effect": "enchant", "target": "creature", "power": -6, "toughness": 0},
	"DRGS": {"effect": "enchant", "target": "none", "self": true},
	"IMMB": {"effect": "enchant", "target": "creature"},
	"BDEX": {"effect": "exchange", "target": "creature"},
}
const HERO_ABILITIES := {
	"LSHE": {"key": "heal", "target": "none", "cost": 1, "amount": 2},
	"CMBN": {"key": "combine", "target": "creature", "cost": 1},
	"FRBL": {"key": "fireball", "target": "any", "cost": 1, "amount": 2},
	"RNST": {"key": "stone_rain", "target": "none", "cost": 2, "amount": 2},
	"ENRG": {"key": "energize", "target": "creature", "cost": 1},
	"RBRT": {"key": "rebirth", "target": "grave", "cost": 2},
	"SCBR": {"key": "second_birth", "target": "grave", "cost": 0},
	"RPST": {"key": "repair", "target": "grave", "cost": 1},
	"SPLK": {"key": "spirit_lock", "target": "creature", "cost": 1, "amount": 1},
	"BROT": {"key": "burnout", "target": "creature", "cost": 1, "second": "any"},
	"OEXC": {"key": "recycle", "target": "creature", "cost": 1, "second": "creature"},
	# Sacrifice needs 1 ether but settles it with the gain instead of paying it.
	"SACR": {"key": "sacrifice", "target": "creature", "cost": 1, "unpaid": true},
}
## Second-game values for hero abilities.
const SECOND_HERO_ABILITIES := {"SPLK": {"cost": 2, "amount": 2}}
## Hero enchantments that modify every friendly creature, including later arrivals.
## `lethal` lowers toughness past the usual minimum of one, killing weak creatures.
const ARMY_AURAS := {"RDDF": {"toughness": 3}, "DMRD": {"power": 1, "toughness": 1}, "STWO": {"power": 2}, "ENWO": {"toughness": 2}, "DOMN": {"power": 1, "toughness": 1}, "JYHD": {"power": 1}, "CRBL": {"flags": ["FS"]},
	"IMML": {"power": 4, "lethal": 2}, "ASLT": {"power": 2, "toughness": 2, "flags": ["Trample", "Berserk"]}, "VTLY": {"regeneration": 2},
	"BLKD": {"toughness": 3, "flags": ["NoAttack"]}, "HAST": {"flags": ["FS", "Trample"]}, "ORPL": {"power": 1, "toughness": 1}}
## Hero enchantments granting flags to the caster's enemies or to every creature.
const HERO_AURAS := {"FURY": {"scope": "enemy", "flags": ["Berserk"]}, "ASST": {"scope": "all", "flags": ["NoAttack"]}, "PCDU": {"scope": "all", "flags": ["NoAttack"]}}
## First-game rules established from the original game. They are enabled
## only for Etherlords I; the second game's versions need their own evidence.
const FIRST_EFFECTS := {
	"STWO": {"effect": "enchant", "target": "none", "self": true},
	"ENWO": {"effect": "enchant", "target": "none", "self": true},
	"DOMN": {"effect": "enchant", "target": "none", "self": true},
	"JYHD": {"effect": "enchant", "target": "none", "self": true},
	"FOGG": {"effect": "enchant", "target": "none", "self": true},
	"HOAM": {"effect": "enchant", "target": "none", "self": true},
	"CRBL": {"effect": "enchant", "target": "none", "self": true},
	"DRFR": {"effect": "enchant", "target": "none", "self": true},
	"CNAR": {"effect": "enchant", "target": "none", "self": true},
	"CMBN": {"effect": "enchant", "target": "none", "self": true},
	"SCSK": {"effect": "enchant", "target": "creature", "power": 0, "toughness": 2},
	"BLSS": {"effect": "enchant", "target": "creature", "power": 4, "toughness": 4},
	"CHCM": {"effect": "enchant", "target": "creature"},
	"BRGR": {"effect": "grave_fire", "target": "none"},
	"PRFY": {"effect": "dispel", "target": "enchantment"},
	"CLSN": {"effect": "cleanse", "target": "none"},
	"ETTD": {"effect": "trade", "target": "creature"},
	"MGHT": {"effect": "enchant", "target": "creature", "power": 3, "toughness": 0},
	"SPWR": {"effect": "enchant", "target": "creature"},
	"AILK": {"effect": "enchant", "target": "creature"},
	"IRRT": {"effect": "enchant", "target": "creature"},
	"GLDT": {"effect": "rest_enemies", "target": "none"},
	"HUNG": {"effect": "hunger", "target": "creature"},
	"CLNP": {"effect": "dispel", "target": "enchantment"},
	"FLIC": {"effect": "dispel", "target": "enchantment", "priced": true},
	"DECN": {"effect": "cleanse", "target": "none"},
	"STRG": {"effect": "enchant", "target": "creature", "power": 4, "toughness": 0},
	"PSBR": {"effect": "enchant", "target": "creature", "variable": true},
	"WTLK": {"effect": "enchant", "target": "creature"},
	"COPL": {"effect": "enchant", "target": "none", "self": true},
	"FDBK": {"effect": "enchant", "target": "none", "self": true},
	"FURY": {"effect": "enchant", "target": "none", "self": true},
	"ASST": {"effect": "enchant", "target": "none", "self": true, "fixed": true},
	"FLOD": {"effect": "enchant", "target": "none", "self": true},
	"IMML": {"effect": "enchant", "target": "none", "self": true},
	"CRHG": {"effect": "hunger_all", "target": "none"},
	"ICST": {"effect": "rest_enemies", "target": "none", "scope": "not_walls"},
	"MALS": {"effect": "random_discard", "target": "hero", "amount": 3},
	"FRWN": {"effect": "draw", "target": "hero", "variable": true},
	"RIFT": {"effect": "destroy", "target": "creature"},
	"ANHL": {"effect": "annihilate", "target": "none"},
	"ALST": {"effect": "enchant", "target": "creature", "own": true},
	"CLFR": {"effect": "enchant", "target": "creature"},
	"SPBA": {"effect": "enchant", "target": "creature"},
	"SLRP": {"effect": "enchant", "target": "creature"},
	"THIF": {"effect": "enchant", "target": "creature"},
	"MDNS": {"effect": "enchant", "target": "creature"},
	"OVRL": {"effect": "enchant", "target": "creature", "power": 5, "toughness": 5},
	"VTLY": {"effect": "enchant", "target": "none", "self": true},
	"ASLT": {"effect": "enchant", "target": "none", "self": true},
	"RBRT": {"effect": "enchant", "target": "none", "self": true},
	"SCBR": {"effect": "enchant", "target": "none", "self": true},
	"ENAL": {"effect": "rally_all", "target": "none"},
	"EXIL": {"effect": "exile", "target": "creature"},
	"LSPC": {"effect": "draw", "target": "none", "self": true, "amount": 3},
	"MDWP": {"effect": "discard_all", "target": "hero"},
	"NOIS": {"effect": "random_discard", "target": "hero", "amount": 3, "any": true},
	"QKFX": {"effect": "reanimate", "target": "grave", "enchantment": true},
	"TPLF": {"effect": "drain_life", "target": "none", "variable": true},
	"CANV": {"effect": "devour", "target": "creature", "own": true},
	"CRIV": {"effect": "destroy", "target": "creature", "race": "Wall"},
	"HRCN": {"effect": "destroy", "target": "creature", "flying": true},
	"GRHE": {"effect": "full_heal", "target": "none"},
	"HEAL": {"effect": "heal", "target": "none", "variable": true},
	"RPST": {"effect": "enchant", "target": "none", "self": true},
	"REPR": {"effect": "repair", "target": "grave"},
	"DPGS": {"effect": "enchant", "target": "none", "self": true},
	"FRGS": {"effect": "enchant", "target": "none", "self": true},
	"DELS": {"effect": "enchant", "target": "creature"},
	"SHSK": {"effect": "enchant", "target": "creature", "power": 0, "toughness": 4},
	"WEAK": {"effect": "enchant", "target": "creature", "power": -4, "toughness": -4},
	"SGHT": {"effect": "enchant", "target": "creature"},
	"DSIG": {"effect": "exile", "target": "creature", "priced_target": true},
	"UNSM": {"effect": "unsummon", "target": "creature", "maximum": 999},
	"LGST": {"effect": "wave", "target": "none", "amount": 3, "scope": "all"},
	"SMOK": {"effect": "enchant", "target": "none", "self": true},
	"SYMB": {"effect": "symbiosis", "target": "none"},
	"DWND": {"effect": "enchant", "target": "creature", "power": 0, "toughness": -4},
	"BLKD": {"effect": "enchant", "target": "none", "self": true},
	"ANFR": {"effect": "enchant", "target": "none", "self": true},
	"HAST": {"effect": "enchant", "target": "none", "self": true},
	"SPWB": {"effect": "enchant", "target": "none", "self": true},
	"ETCH": {"effect": "enchant", "target": "none", "self": true},
	"TRLB": {"effect": "enchant", "target": "none", "self": true},
	"ENLH": {"effect": "enchant", "target": "none", "self": true},
	"SPLK": {"effect": "enchant", "target": "none", "self": true},
	"RIOT": {"effect": "enchant", "target": "creature"},
	"ERBN": {"effect": "enchant", "target": "creature"},
	"PALN": {"effect": "enchant", "target": "creature"},
	"REDR": {"effect": "enchant", "target": "creature"},
	"SHFR": {"effect": "enchant", "target": "creature", "variable": true, "stat": "toughness"},
	"CNBL": {"effect": "sacrifice_heal", "target": "creature", "own": true},
	"PLMR": {"effect": "polymorph", "target": "creature"},
	"TWST": {"effect": "twister", "target": "creature"},
	"FRNT": {"effect": "fury_of_nature", "target": "none"},
	"CLON": {"effect": "clone", "target": "creature"},
	"GRUN": {"effect": "bounce_all", "target": "none"},
	"AMNS": {"effect": "amnesia", "target": "none"},
	"RECL": {"effect": "draw", "target": "none", "self": true, "amount": 2},
	"MDBL": {"effect": "mind_blast", "target": "none"},
	"RVHG": {"effect": "hunger_both", "target": "none"},
	"ENFR": {"effect": "redraw", "target": "none", "scope": "both", "reject": "spells"},
	"AWAK": {"effect": "redraw", "target": "none", "scope": "self", "reject": "creatures"},
	"BANN": {"effect": "ban", "target": "none"},
	"BROT": {"effect": "enchant", "target": "none", "self": true},
	"TRAD": {"effect": "swap", "target": "creature", "own": true},
	"BASO": {"effect": "enchant", "target": "none", "self": true},
	"SACR": {"effect": "enchant", "target": "none", "self": true},
	"WHAS": {"effect": "trade", "target": "creature", "dispel": true},
	# Channel's X is paid in health, not ether.
	"CHNL": {"effect": "channel", "target": "none", "variable": true, "x_source": "health"},
}
## Creature enchantments that grant flags while attached.
const GRANTED_FLAGS := {"SPWR": ["Restless"], "AILK": ["Lifetap"], "CMBN": ["Trample"], "FREL": ["NoRegen"], "CLFR": ["UB"], "SPBA": ["Destroy"], "ALST": ["FS", "Trample"], "SGHT": ["Disenchant"], "ETAM": ["NoTarget"], "RIOT": ["NoRegen"], "TWST": ["NoRegen"], "PRGD": ["Restless"], "WNPZ": ["NoUntap"], "BWIT": ["NoUntap"], "OCRP": ["NoUntap"]}
## Creature enchantments granting regeneration (the cheapest cost applies) or
## extra robbed cards on a hit.
const GRANTED_REGENERATION := {"SLRP": 1}
const GRANTED_DISCARD := {"THIF": 3}
## Enchantments created by creatures in combat rather than cast from a card.
## Only snake venom can be dispelled (it is priced at zero ether).
const FIRST_MARKS := ["GRSN", "LASN", "TRSN", "SWSN", "FREL", "WLDT"]
## Rising creatures return from the graveyard with three newer entries above them.
const RISING := ["MNHP"]
const FIRST_RISING := ["MNHP", "HOPR", "MXHP"]
## Velos die at their owner's turn end unless combat damaged them since the last one.
const FATALISTS := ["SMVL", "BGVL"]
## Parasites cost their controller health at the end of each of its turns.
const PARASITES := {"BRMZ": 2, "IRMZ": 4, "STMZ": 5}
## Passive auras from creatures in play. `race`/`card` select affected creatures
## on both sides unless `own` limits them to the source's owner; the source
## itself is included when it matches. Removed when the source leaves play.
const CREATURE_AURAS := {
	"TIWK": {"race": "Tick", "power": 1, "toughness": 1},
	"TIQN": {"race": "Tick", "toughness": 2},
	"BEWK": {"race": "Bee", "power": 1},
	"BEQN": {"race": "Bee", "power": 1, "toughness": 1},
	"KBWR": {"race": "Kobold", "power": 1},
	"MOTI": {"race": "Tick", "flags": ["Restless"]},
	"MOBE": {"race": "Bee", "flags": ["FS"]},
	"SHSP": {"card": "WRSP", "toughness": 1},
	"CLSP": {"card": "WRSP", "power": 1, "toughness": 1},
	"OREL": {"race": "Orc", "flags": ["Restless"]},
	"SLWL": {"race": "Wall", "toughness": 1, "own": true},
	"AVEL": {"race": "Aviak", "power": 1, "toughness": 1},
	"ORWR": {"race": "Orc", "power": 1, "toughness": 1, "flags": ["Berserk"]},
	"WZSP": {"card": "WRSP", "power": 2},
	"GRFG": {"race": "Fingus", "power": 1, "toughness": 1},
}
## `Elusive` is the second game's table mark for the walls-only blocking rule.
const FIRST_FLAGS := ["Lifetap", "NoUntap", "UB", "TeamAttack", "NoTarget", "NoAffect", "Elusive"]
## First-game creature abilities. `ready` (default) needs an untapped, non-sick
## creature and taps it; `tapped` needs a resting, non-sick one; grave targets
## pass the hero side and graveyard index.
const FIRST_ABILITIES := {
	"WNHR": {"key": "hunt", "target": "creature", "cost": 0},
	"GIFG": {"key": "sting", "target": "any", "cost": 0},
	"KBEL": {"key": "rally", "target": "none", "cost": 0},
	"MNTS": {"key": "tap_target", "target": "creature", "cost": 1, "phase": "attack"},
	"MTSC": {"key": "tap_walls", "target": "none", "cost": 0, "phase": "attack"},
	"MOTI": {"key": "brood", "target": "none", "cost": 4, "summon": "TIWR"},
	"MOBE": {"key": "brood", "target": "none", "cost": 2, "summon": "BEWR"},
	"SHSP": {"key": "rouse", "target": "none", "cost": 0},
	"CLSP": {"key": "recall_spirit", "target": "grave", "cost": 2},
	"CTMN": {"key": "sacrifice", "target": "creature", "cost": 0, "ready": false, "tapped": true},
	"DRAT": {"key": "gnaw", "target": "grave", "cost": 1},
	"LMMN": {"key": "recall_lamia", "target": "grave", "cost": 0},
	"ORSH": {"key": "ether", "target": "none", "cost": 0},
	"KBSH": {"key": "sting", "target": "any", "cost": 0},
	"AVMK": {"key": "shoot", "target": "creature", "cost": 0},
	"PRAT": {"key": "plague", "target": "hero", "cost": 0, "variable": true},
	"DMRT": {"key": "recall_rat", "target": "grave", "cost": 2},
	"PTRS": {"key": "dispel", "target": "enchantment", "cost": -1},
	"WZSP": {"key": "spirit_flight", "target": "none", "cost": 0},
	"PHWL": {"key": "phantasm", "target": "none", "cost": 3, "ready": false},
	"WLLV": {"key": "lava_power", "target": "none", "cost": 0, "ready": false, "variable": true, "minimum": 1},
	"WLIF": {"key": "hellfire_health", "target": "none", "cost": 0, "ready": false, "variable": true, "minimum": 1},
	"WLWD": {"key": "lava_power", "target": "none", "cost": 0, "ready": false, "variable": true, "minimum": 1},
	"CCLP": {"key": "sting", "target": "any", "cost": 0, "amount": 3},
	"VBAT": {"key": "bat_drain", "target": "none", "cost": 3},
	"LMWK": {"key": "draw", "target": "none", "cost": 0},
	"RVHL": {"key": "siphon", "target": "none", "cost": 0, "amount": 2},
	"SEHL": {"key": "siphon", "target": "none", "cost": 0, "amount": 4},
	"SWHL": {"key": "siphon", "target": "none", "cost": 0, "amount": 6},
	"BLDG": {"key": "slay", "target": "creature", "cost": 0},
	"BUDG": {"key": "breath", "target": "none", "cost": 0, "amount": 3, "scope": "flying"},
	"RDDG": {"key": "breath", "target": "none", "cost": 0, "amount": 3, "scope": "ground"},
	"GRDG": {"key": "wall_break", "target": "creature", "cost": 0},
	"RZMN": {"key": "sacrifice", "target": "creature", "cost": 0, "ready": false, "tapped": true},
	"SWMN": {"key": "sacrifice", "target": "creature", "cost": 0, "ready": false, "tapped": true},
	"FMFI": {"key": "necromancy", "target": "grave", "cost": 0, "maximum": 3},
	"MLFI": {"key": "necromancy", "target": "grave", "cost": 0, "maximum": 5},
	"BEHD": {"key": "gaze", "target": "creature", "cost": 0, "measure": "toughness"},
	"BHWR": {"key": "gaze", "target": "creature", "cost": 0, "measure": "power"},
	"GRFG": {"key": "sting", "target": "any", "cost": 0, "amount": 2},
	"MTPT": {"key": "tap_race", "target": "creature", "cost": 0, "phase": "attack"},
	"WLDT": {"key": "distortion", "target": "none", "cost": 0, "ready": false},
}
## Creatures fully covered by first-game rules (flags, auras and combat hooks).
const FIRST_SUMMONS := ["GBIN", "GBBR", "WRSP", "AVAS", "NWLF", "SHWL", "BRMC", "IRMC", "STMC", "LMWD", "ORGD",
	"TIWK", "TIQN", "BEWK", "BEQN", "KBWR", "OREL", "SLWL",
	"GIFG", "KBEL", "MNTS", "MTSC", "MOTI", "MOBE", "SHSP", "CLSP", "CTMN", "DRAT", "LMMN",
	"ORSH", "KBSH", "AVMK", "PRAT", "DMRT", "PTRS", "WZSP", "PHWL", "WLLV", "WLIF", "AVEL", "ORWR",
	"GRSN", "LASN", "TRSN", "SWSN", "SMVL", "BGVL", "GBGN", "HOPR", "MXHP", "BRMZ", "IRMZ",
	"AREL", "KBGD", "FREL", "CCLP", "VBAT", "LMWK", "RVHL", "SEHL", "SWHL", "BLDG", "BUDG", "GRDG", "RDDG", "WLWD",
	"FMFI", "MLFI", "RZMN", "SWMN", "STAB", "STMZ", "WKHR", "WLDT", "BEHD", "BHMO", "BHWR", "GRFG", "MTPT"]
## First-game rules that the second game implements unchanged, or
## with the second-game values below. Other first-game rules stay Etherlords I only.
const SECOND_SHARED := ["WNHR", "FOGG", "MGHT", "SPWR", "JYHD", "CNAR", "IRRT", "AILK", "PRFY", "DOMN", "BLSS", "BRGR",
	"STWO", "ENWO", "CRBL", "ETTD", "HUNG", "HOAM", "DRFR", "GLDT", "CLSN", "CHCM", "CMBN", "SCSK",
	"RIFT", "EXIL", "MALS", "FDBK", "FLOD", "CLNP", "MDNS", "STRG", "IMML", "ASST", "NOIS", "CLFR", "MDWP",
	"FLIC", "ASLT", "COPL", "PSBR", "GRHE", "ICST", "TPLF", "ANHL", "ALST", "THIF", "QKFX", "RBRT", "WTLK",
	"WRSP", "SMVL", "BGVL", "ORGD", "LMMN", "LMWD", "CLSP", "ORWR", "OREL", "ORSH", "WLLV", "SHSP", "CTMN",
	"PTRS", "WZSP", "AVEL", "DRAT", "DMRT", "PRAT", "BEWK", "BEQN", "MOBE", "MNTS", "MTSC", "GIFG", "GBGN",
	"GBIN", "HOPR", "MXHP", "WLIF", "BRMC", "IRMC", "STMC", "BRMZ", "IRMZ", "LASN", "GRSN", "PHWL", "SLWL",
	"KBSH", "KBEL", "TIWK", "TIQN", "MOTI", "AVMK", "TRSN", "SWSN", "AVAS", "NWLF", "SHWL", "GBBR", "AREL",
	"BEHD", "BHWR",
	"RPST", "REPR", "DPGS", "FRGS", "DELS", "SHSK", "WEAK", "SGHT", "DSIG", "UNSM", "LGST", "SMOK",
	"LMWK", "FRWN", "LSPC", "CRHG", "FURY", "KBWR", "KBGD", "CCLP", "WLWD", "BHMO", "SCBR", "OVRL", "RZMN",
	"SWMN", "SLRP", "WKHR", "STMZ", "STAB", "VTLY", "SPBA", "HRCN", "CRIV", "GRFG", "MTPT", "RVHL", "SEHL",
	"SWHL", "DECN", "FMFI", "MLFI", "WLDT", "BUDG", "BLDG", "RDDG", "GRDG", "ENAL", "FREL", "HEAL", "VBAT", "CANV",
	"SYMB", "DWND", "BLKD", "ANFR", "HAST", "SPWB", "ETCH", "TRLB", "ENLH", "SPLK", "RIOT", "ERBN", "PALN", "REDR",
	"SHFR", "CNBL", "PLMR", "TWST", "FRNT", "CLON", "GRUN", "AMNS", "RECL", "MDBL", "RVHG", "ENFR", "AWAK", "BANN", "BROT", "TRAD",
	"BASO", "SACR", "WHAS", "CHNL"]
## Second-game rules that replace a shared card's first-game rule outright.
const SECOND_EFFECTS := {
	# Dense Forest has no target: its producer builds the spell with the
	# bare base constructor (no target kinds) and it lands on the caster's hero.
	"DNFR": {"effect": "enchant", "target": "none", "self": true},
	"HEAL": {"effect": "half_heal", "target": "none"},
	# Second-game dwindling can kill; enlightenment became a hand refresh.
	"DWND": {"effect": "enchant", "target": "creature", "power": 0, "toughness": -4, "lethal": true},
	"ENLH": {"effect": "redraw", "target": "none", "scope": "self", "reject": "", "retry": false},
	"STSK": {"effect": "enchant", "target": "any"},
	# The Ether Amulet's spell as a script cast (DragonBoss): a creature gains Magic screen.
	"ETAM": {"effect": "enchant", "target": "creature"},
	# White (Pale) cards and the Colourless Plane.
	"ENBR": {"effect": "enchant", "target": "any"},
	"LFGR": {"effect": "enchant", "target": "any"},
	"PRGD": {"effect": "enchant", "target": "creature"},
	"PRWT": {"effect": "enchant", "target": "none", "self": true},
	"PLSL": {"effect": "enchant", "target": "none", "self": true},
	"PLWP": {"effect": "enchant", "target": "none", "self": true},
	"OEXC": {"effect": "enchant", "target": "none", "self": true},
	"OST1": {"effect": "enchant", "target": "none", "self": true},
	"OST2": {"effect": "enchant", "target": "none", "self": true},
	"OST3": {"effect": "enchant", "target": "none", "self": true},
	"LCWR": {"effect": "enchant", "target": "none", "self": true},
	"GCWR": {"effect": "enchant", "target": "none", "self": true},
	"LSWR": {"effect": "enchant", "target": "none", "self": true},
	"GSWR": {"effect": "enchant", "target": "none", "self": true},
	"LEWR": {"effect": "enchant", "target": "none", "self": true},
	"GEWR": {"effect": "enchant", "target": "none", "self": true},
	"OBLS": {"effect": "pale_blast", "target": "creature"},
	"OCLV": {"effect": "pale_cleave", "target": "creature"},
	"ORPL": {"effect": "ripple", "target": "none"},
	"OMSW": {"effect": "pale_theft", "target": "none"},
	# Remaining White cards. `pale` needs a Pale target; `plane` "in" needs it in
	# pale aspect (only Outer spells may reach it there).
	"OCRP": {"effect": "enchant", "target": "creature", "pale": true, "plane": "in"},
	"OFLX": {"effect": "flux", "target": "none"},
	"OMWP": {"effect": "pale_calamity", "target": "none"},
	"BNSH": {"effect": "banish", "target": "creature", "pale": true},
	"PRBN": {"effect": "enchant", "target": "creature"},
	"ORFT": {"effect": "pale_revival", "target": "creature", "plane": "in"},
	"FTCH": {"effect": "draw", "target": "none", "self": true, "amount": 2, "channels_el2": 1},
	"GBNS": {"effect": "vaporize", "target": "none"},
	"PRWR": {"effect": "enchant", "target": "hero"},
	"ALNS": {"effect": "enchant", "target": "creature"},
	# Enemy- or battleground-scripted records (`Support=True` except GIFT). Rules
	# exist for a future battle-script layer; no shipped deck or shop holds them.
	"GIFT": {"effect": "gift", "target": "creature", "own": true, "enchantment": true},
	"DRCD": {"effect": "draw", "target": "hero", "amount": 1},
	"WTX2": {"effect": "enchant", "target": "none", "opponent": true},
	# Venom cast directly (Rod of Venom): no target; the same venom enchantment a
	# serpent's hit leaves, always on the caster's opponent (empty
	# target-kind vector in its producer).
	"ESWS": {"effect": "enchant", "target": "none", "opponent": true},
	"ELKS": {"effect": "enchant", "target": "creature", "power": -1, "toughness": -1, "fixed": true, "lethal": true},
	"GRPL": {"effect": "reanimate", "target": "grave", "plain": true, "grave_owner_cap": true},
}
## Second-game Pale creatures (summon rules; their abilities are below).
const PALE_SUMMONS := ["SMFX", "SMTG", "SMWB", "OUS1", "OUS2", "OUS3", "OUE1", "OUE2", "OUE3", "OUD1", "OUD2", "OUD3", "OSJ1", "OSJ2", "OSJ3"]
## Manifestation abilities by Pale race; the ability's text ID names it.
const PALE_RACE_ABILITIES := {"OutSamurai": {"key": "sinister", "text": "AOUF", "target": "grave"},
	"OutShifter": {"key": "cruel", "text": "AOUS", "target": "creature"},
	"OutDevourer": {"key": "fiendish", "text": "AOUD", "target": "none"},
	"OutEnchanter": {"key": "mystic", "text": "AOUE", "target": "enchantment"},
	"OutSpellJammer": {"key": "cryptic", "text": "AOUJ", "target": "none"}}
## Pale creatures' own rest abilities.
const PALE_ABILITIES := {
	"OUS1": {"key": "channel_ether", "target": "none", "cost": 0},
	"OUS2": {"key": "ether_plea", "target": "any", "cost": 0},
	"OUS3": {"key": "pale_heal", "target": "none", "cost": 0},
	"OUE1": {"key": "absorb", "target": "enchantment", "cost": 1},
	"OUE2": {"key": "weave", "target": "enchantment", "cost": 2},
	"OUE3": {"key": "transpose", "target": "enchantment", "cost": 1},
	"OUD1": {"key": "pale_devour", "target": "creature", "cost": 2, "measure": "power"},
	"OUD2": {"key": "pale_devour", "target": "creature", "cost": 2, "measure": "toughness"},
	"OUD3": {"key": "pale_devour", "target": "creature", "cost": 3, "measure": "both"},
}
## Spells that may target creatures in the Colourless Plane.
const OUTER_SPELLS := ["OFLX", "ORPL", "ORFT", "OBLS", "OCRP", "OST1", "OST2", "OST3"]
## Wardings raise the cost of one spell class for both heroes: lesser +2, greater +printed cost.
const WARDINGS := {"LCWR": ["Creature", false], "GCWR": ["Creature", true], "LSWR": ["Sorcery", false],
	"GSWR": ["Sorcery", true], "LEWR": ["Enchantment", false], "GEWR": ["Enchantment", true]}
## Second-game values that replace the first game's for shared rules.
const SECOND_ABILITIES := {"MOTI": {"cost": 2}, "AVMK": {"amount": 2}}
const SECOND_AURAS := {"TIWK": {"race": "Tick", "power": 1}, "TIQN": {"race": "Tick", "toughness": 1}}
const SECOND_DISCARD := {"THIF": 2}
## Only Wall-race creatures may block these attackers (after the flying check).
const WALL_BLOCKED := ["AVAS", "NWLF", "SHWL"]
## Creatures damaged in combat by these die at the end of combat unless they are walls.
const MECHOS := ["BRMC", "IRMC", "STMC"]
## A successful hit on the enemy hero marks these attackers to die after combat.
const STINGERS := ["BEWK", "BEQN"]
## Battle artifact spells. They are used from the hero's artifact list, never a hand.
## `phase` restricts use to the owner's own defence; expiry is handled per effect.
## `phase` is attack (default), defence or both; spiked ring needs an attacking target.
const ARTIFACT_EFFECTS := {
	"RDDF": {"effect": "enchant", "target": "none", "self": true, "phase": "defence"},
	"SPRG": {"effect": "destroy", "target": "creature", "phase": "both", "attacking": true, "no_regeneration": true},
	"RDLG": {"effect": "damage", "target": "any", "amount": 3},
	"RDCL": {"effect": "damage", "target": "any", "amount": 9},
	"SPBR": {"effect": "dispel", "target": "enchantment"},
	"ETAM": {"effect": "enchant", "target": "creature"},
	"WNMG": {"effect": "summon", "target": "none"},
	"RDKN": {"effect": "summon", "target": "none"},
	"WNBL": {"effect": "bless", "target": "creature", "power": 4, "toughness": 4},
	"RDHL": {"effect": "heal", "target": "none", "amount": 7},
	"RDRS": {"effect": "reanimate", "target": "grave"},
	"BRRD": {"effect": "destroy", "target": "creature"},
	"RDCM": {"effect": "enchant", "target": "creature", "control": true},
	"DMRD": {"effect": "enchant", "target": "none", "self": true},
	# Twins of Feedback, Madness and Ash Storm, plus three artifacts of their own.
	"LNRD": {"effect": "enchant", "target": "none", "self": true},
	"RDIS": {"effect": "enchant", "target": "creature"},
	"PCDU": {"effect": "enchant", "target": "none", "self": true, "fixed": true},
	"WNPZ": {"effect": "enchant", "target": "creature"},
	"WRBN": {"effect": "enchant", "target": "none", "self": true},
	"WNHR": {"effect": "summon", "target": "none"},
}
## Second game: battle-artifact spells some authored books list as ordinary
## cards. The book enters battle as written, so such a copy is drawn and cast
## from the hand at its printed cost with the artifact spell's effect.
const BOOK_ARTIFACTS := ["WNPZ", "RDKN"]
## Enchantments that pass control of a creature to their caster.
const CONTROL := ["CHCM", "RDCM"]
const FLAGS := ["Fly", "FS", "NSS", "Berserk", "NoAttack", "Restless", "Trample", "Destroy", "Disenchant"]
const SUMMONS := ["WTEL", "GBAT", "MAHO", "WNMG", "WNHR", "AVSC", "BEWR", "ANTN", "MCWU", "MCWY",
	"WLMG", "TIWR", "WLFC", "STRT", "WLDG", "WLBZ", "WLBR", "WLBL", "WLAR", "TNSA", "TANT",
	"SPFG", "CAFG", "RKWL", "RFPT", "OGKN", "MYHO", "MCWO", "LMWA", "IRAB", "GRTN", "GROG", "EREL", "BRAB", "BATT", "MNHP", "WLIL"]
const FLAG_NAMES := {"Fly": "Flying", "FS": "First strike", "NSS": "Haste", "Berserk": "Aggressive",
	"NoAttack": "Cannot attack", "Restless": "Restless", "Trample": "Trample", "Destroy": "Poisonous", "Disenchant": "Disenchant",
	"Lifetap": "Life drain", "NoUntap": "Does not recover", "UB": "Unblockable", "TeamAttack": "Guard",
	"NoTarget": "Magic screen", "NoAffect": "Unaffected", "Elusive": "Blocked only by walls", "NoRegen": "Cannot regenerate",
	"Outerplanar": "Pale"}

static func flag_name(flag: String) -> String:
	if flag.begins_with("Regen("): return "Regeneration " + flag.trim_prefix("Regen")
	if flag.begins_with("Discard("): return "Robber " + flag.trim_prefix("Discard")
	return String(FLAG_NAMES.get(flag, flag))

static func flags(row: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var value: Variant = row.get("Flags", [])
	if value is String:
		if not value.is_empty(): result.append(value)
	elif value is Array:
		for flag: String in value: result.append(flag)
	return result

static func rule(profile: ELProfile, card: String) -> Dictionary:
	var spell: Dictionary = profile.table("CombatSpells").get(card, {})
	if spell.is_empty(): return {}
	# Second-game rules take precedence over the shared table (DNFR).
	if profile.id == "el2" and SECOND_EFFECTS.has(card): return SECOND_EFFECTS[card]
	if profile.id == "el2" and card in BOOK_ARTIFACTS: return ARTIFACT_EFFECTS[card]
	if EFFECTS.has(card): return EFFECTS[card]
	var first := shared(profile, card)
	if first and FIRST_EFFECTS.has(card): return FIRST_EFFECTS[card]
	var creature: Dictionary = profile.table("CombatCreatures").get(card, {})
	if profile.id == "el2" and card in PALE_SUMMONS and not creature.is_empty(): return {"effect": "summon", "target": "none"}
	# Some passive effects live outside the creature table (death auras, recurring
	# summons, cost changes). Enable only creatures whose full behavior is handled.
	if card not in SUMMONS and not (first and card in FIRST_SUMMONS): return {}
	if spell.get("Class") != "Creature" or creature.is_empty(): return {}
	# A creature with an unimplemented active ability must not silently lose it.
	if spell.has("Ability") and card not in ["SPFG", "CAFG", "RFPT", "WLIL"] and not (first and (CREATURE_AURAS.has(card) or FIRST_ABILITIES.has(card) or card in ["ORGD", "AVAS", "LMWD", "WKHR", "BHMO"] + MECHOS + FIRST_MARKS)): return {}
	for flag: String in flags(creature):
		if flag not in FLAGS and not flag.begins_with("Regen(") and not (first and (flag in FIRST_FLAGS or flag.begins_with("Discard("))): return {}
	return {"effect": "summon", "target": "none"}

## Whether the mounted edition uses this card's first-game rule.
static func shared(profile: ELProfile, card: String) -> bool:
	return profile.id == "el1" or card in SECOND_SHARED

## The creature ability for this edition, or an empty dictionary.
static func first_ability(profile: ELProfile, card: String) -> Dictionary:
	if not FIRST_ABILITIES.has(card) or not shared(profile, card): return {}
	var ability: Dictionary = FIRST_ABILITIES[card].duplicate()
	if profile.id == "el2": ability.merge(SECOND_ABILITIES.get(card, {}), true)
	return ability

## The passive creature aura for this edition, or an empty dictionary.
static func creature_aura(profile: ELProfile, card: String) -> Dictionary:
	if not CREATURE_AURAS.has(card) or not shared(profile, card): return {}
	return SECOND_AURAS.get(card, CREATURE_AURAS[card]) if profile.id == "el2" else CREATURE_AURAS[card]

static func granted_discard(profile: ELProfile, card: String) -> int:
	return int(SECOND_DISCARD.get(card, GRANTED_DISCARD.get(card, 0)) if profile.id == "el2" else GRANTED_DISCARD.get(card, 0))

static func deck(profile: ELProfile, name: String) -> Array[String]:
	var result: Array[String] = []
	for entry: String in deck_entries(profile, name):
		result.append(entry.get_slice("(", 0))
	return result

static func deck_entries(profile: ELProfile, name: String) -> Array:
	var entries: Variant = profile.table("CombatDecks").get(name, {}).get("Spells", [])
	return [entries] if entries is String else entries

static func deck_uses(profile: ELProfile, name: String) -> Array[int]:
	var result: Array[int] = []
	for entry: String in deck_entries(profile, name):
		var count := entry.get_slice("(", 1).get_slice(":", 0).trim_suffix(")")
		result.append(maxi(0, int(count)))
	return result

## The second game's Colourless lords (the White campaign's own heroes and
## its enemies) fight as a fifth, "White" side; it has no starter book.
static func faction_known(profile: ELProfile, faction: String) -> bool:
	return FACTIONS.has(faction) or profile.id == "el2" and faction == "White"

static func faction_name(faction: String) -> String:
	return String(FACTIONS.get(faction, "Colourless" if faction == "White" else faction))

static func default_hero(profile: ELProfile, faction: String) -> String:
	if faction == "White" and profile.id == "el2": return "White Lord I"
	return "RedMale4" if faction == "Red" and profile.id == "el2" else String(HEROES.get(faction, ""))

static func available_cards(profile: ELProfile, faction: String) -> Array[String]:
	var result: Array[String] = []
	for card: String in profile.table("CombatSpells"):
		var row: Dictionary = profile.table("CombatSpells")[card]
		# `Support=True` rows are internal records (venoms, script-only spells, jammers).
		if row.get("Color") == faction and row.get("Use", "+") == "+" and str(row.get("Support", "False")).to_lower() != "true" and not rule(profile, card).is_empty():
			result.append(card)
	result.sort_custom(func(a: String, b: String):
		var ca := int(profile.table("CombatSpells")[a].Cost)
		var cb := int(profile.table("CombatSpells")[b].Cost)
		return a < b if ca == cb else ca < cb)
	return result
