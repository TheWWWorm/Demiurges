extends RefCounted
## Presentation effects (names from Resources/Effects.xml) each card starts in
## combat, per edition. Identical card codes keep separate entries because the
## two games differ. The sound of an effect comes from that edition's
## Effects.xml; creature cards use their colour's summon effect instead.
##
## CAST: started when the card is cast (the spell itself and the enchantment it
## attaches). TRIGGER: started when an enchantment of that card deals its
## triggered damage.

const CAST := {
	"el1": {
		"AILK": ["PosEnchantment"], "ALST": ["Trample", "FirstStrike", "PosAttack", "NegDefence", "PosRune", "NegRune"],
		"AMNS": ["Discard"], "ANFR": ["PosEnchantment", "GreenDenceForest"], "ANHL": ["RedAnihilation"],
		"ANTN": ["GreenSummon"], "AREL": ["BlueSummon"],
		"ASLT": ["PosSorcery", "PosAttack", "PosDefence", "Trample", "Berserk", "PosRune"],
		"ASST": ["CantAttack", "NegRune"], "AVAS": ["BlueSummon"], "AVEL": ["BlueSummon"], "AVMK": ["BlueSummon"],
		"AVSC": ["BlueSummon"], "AWAK": ["Discard", "Draw"], "BANN": ["Discard"], "BASO": ["PosEnchantment"],
		"BATT": ["RedSummon"], "BDEX": ["PosSorcery", "BlackDamage"], "BEHD": ["GreenSummon"], "BEQN": ["GreenSummon"],
		"BEWK": ["GreenSummon"], "BEWR": ["GreenSummon"], "BGVL": ["BlackSummon"], "BHMO": ["GreenSummon"],
		"BHWR": ["GreenSummon"], "BLDG": ["BlueSummon"],
		"BLKD": ["PosEnchantment", "CantAttack", "PosDefence", "PosRune", "NegRune"], "BLNC": ["GainMana"],
		"BLSS": ["PosAttack", "PosDefence", "PosRune"], "BRAB": ["BlackSummon"], "BRGR": ["NegSorcery", "RedDamage"],
		"BRMC": ["BlackSummon"], "BRMZ": ["BlackSummon"], "BROT": ["PosEnchantment"], "BRRD": ["RedAnihilation"],
		"BRRL": ["LoseMana", "BlackDamage"], "BUDG": ["BlueSummon"], "CAFG": ["GreenSummon"],
		"CANV": ["GreenDamage", "GainLife"], "CCLP": ["RedSummon"], "CHCM": ["PosEnchantment"],
		"CHNL": ["LoseLife", "GainMana", "GainLife"], "CLFR": ["Ublockable", "PosRune"], "CLIG": ["RedLightning"],
		"CLNP": ["Disenchant"], "CLON": ["PosSorcery"], "CLSN": ["Disenchant"], "CLSP": ["BlueSummon"],
		"CMBN": ["PosEnchantment", "PosAttack", "PosDefence", "Trample", "PosRune"],
		# Original EL1 CondensedAirEnchantment attach@ has only
		# Target/NegEnchantment; unlike EL2 it has no separate CantUntap
		# creature-presentation callback on the cast.
		"CNAR": ["NegEnchantment", "CantUntap"], "CNBL": ["RedDamage", "GainLife"], "COMT": ["RedComet"],
		"COPL": ["PosEnchantment"], "CRBL": ["PosEnchantment", "FirstStrike"], "CRHG": ["Hunger"], "CRIV": ["GreenDamage"],
		"CTMN": ["BlackSummon"], "CTST": ["RedCatstrophe"], "CURS": ["Discard"], "DECN": ["Disenchant"],
		"DELS": ["PosEnchantment", "PosRune"], "DISM": ["NegAttack", "NegRune"],
		"DMRD": ["PosEnchantment", "PosAttack", "PosDefence", "PosRune"], "DMRT": ["RedSummon"],
		"DNFR": ["PosEnchantment", "GreenAncientForest"], "DOMN": ["PosEnchantment", "PosAttack", "PosDefence", "PosRune"],
		"DPGS": ["BlackDepressGas", "NegRune", "NegAttack"], "DRAT": ["RedSummon"],
		"DRFR": ["PosEnchantment", "GreenDarkForest"], "DRGS": ["BlackDrowsyGas", "NegRune", "NegAttack"],
		"DSIG": ["RedFireStream"], "DWND": ["NegDefence", "NegRune"], "ENAL": ["PosSorcery"], "ENFL": ["Disenchant"], "ENFR": ["Discard", "Draw"],
		"ENLH": ["PosEnchantment"], "ENRG": ["PosEnchantment"], "ENVM": ["NegEnchantment"],
		"ENWO": ["PosEnchantment", "PosDefence", "PosRune"], "ERBN": ["NegEnchantment", "CantUntap"],
		"EREL": ["BlueSummon"], "ERQA": ["Tremor"], "ETAM": ["PosEnchantment"], "ETCH": ["PosSorcery"],
		"ETTD": ["GreenDamage", "Disenchant"], "EXIL": ["BlackExile"], "FAIL": ["NegAttack", "NegRune"],
		"FDBK": ["PosSorcery"], "FLIC": ["Disenchant"], "FLOD": ["NegEnchantment", "CantUntap"], "FMFI": ["BlackSummon"],
		"FOGG": ["BlueFog", "CantAttack"], "FRBL": ["PosEnchantment"], "FREL": ["BlueSummon"],
		"FRGS": ["BlackFrenzyGas", "NegRune", "NegDefence"], "FRNT": ["GreenForceNature", "GreenDamage"],
		"FRST": ["RedFireWave", "RedDamage"], "FRWA": ["RedFireWave", "RedDamage"], "FRWN": ["Draw"],
		"FTDS": ["GreenFatalDesease"], "FURY": ["Berserk"], "GBAT": ["RedSummon"], "GBBR": ["BlueSummon"],
		"GBGN": ["BlueSummon"], "GBIN": ["BlueSummon"], "GEYS": ["GainMana"], "GIFG": ["GreenSummon"],
		"GLDT": ["NegSorcery"], "GRDG": ["BlueSummon"], "GRFG": ["GreenSummon"], "GRHE": ["GainLife"],
		"GROG": ["RedSummon"], "GRSN": ["GreenSummon"], "GRTN": ["GreenSummon"], "GRUN": ["BlueDeath", "Draw"],
		"HAST": ["PosEnchantment", "FirstStrike", "Trample", "PosRune"], "HEAL": ["GainLife"], "HOAM": ["PosEnchantment"],
		"HOPR": ["BlackSummon"], "HRCN": ["GreenHurricane"], "HUNG": ["Hunger"], "ICST": ["BlueIceStorm"],
		"IMMB": ["CantUntap", "NegRune"], "IMML": ["PosEnchantment", "PosAttack", "NegDefence", "NegRune", "PosRune"],
		"INCR": ["LoseMana"], "IRAB": ["BlackSummon"], "IRMC": ["BlackSummon"], "IRMZ": ["BlackSummon"],
		"IRRT": ["NegEnchantment"], "JRRG": ["PosSorcery", "BlackDamage"], "JUST": ["GainMana"],
		"JYHD": ["PosEnchantment", "PosAttack"], "KBEL": ["RedSummon"], "KBGD": ["RedSummon"], "KBSH": ["RedSummon"],
		"KBWR": ["RedSummon"], "LASN": ["GreenSummon"], "LGST": ["RedLightning", "PosAttack", "PosDefence", "PosRune"],
		"LMMN": ["BlueSummon"], "LMWA": ["BlueSummon"], "LMWD": ["BlueSummon"], "LMWK": ["BlueSummon"],
		"LNRD": ["PosSorcery"], "LQRL": ["DrainMana", "NegRune", "PosRune"], "LSDS": ["NegEnchantment"],
		"LSHE": ["PosEnchantment"], "LSPC": ["Draw"], "LSST": ["PosAttack", "PosDefence", "PosRune"],
		"LSUS": ["BlueDeath", "Draw"], "MAHO": ["GreenSummon"], "MALS": ["Discard"], "MCWO": ["BlackSummon"],
		"MCWU": ["BlackSummon"], "MCWY": ["BlackSummon"], "MDBL": ["BlueMindBlast"], "MDNS": ["NegEnchantment"],
		"MDWP": ["Discard"], "MGHT": ["PosAttack", "PosRune"], "MLFI": ["BlackSummon"], "MNBN": ["NegEnchantment"],
		"MNBR": ["GainMana"], "MNDP": ["GainMana"], "MNDW": ["GainMana"], "MNHP": ["BlackSummon"], "MNST": ["GainMana"],
		"MNTH": ["NegEnchantment"], "MNTP": ["GainMana"], "MNTS": ["GreenSummon"], "MNTX": ["PosEnchantment"],
		"MNVR": ["GainMana"], "MOBE": ["GreenSummon"], "MOTI": ["GreenSummon"], "MTPT": ["GreenSummon"],
		"MTSC": ["GreenSummon"], "MXHP": ["BlackSummon"], "MYHO": ["GreenSummon"], "NOIS": ["Discard"],
		"NWLF": ["RedSummon"], "OGKN": ["RedSummon"], "OREL": ["RedSummon"], "ORGD": ["RedSummon"], "ORSH": ["RedSummon"],
		"ORWR": ["RedSummon"], "OVRL": ["PosAttack", "PosDefence", "PosRune"], "PALN": ["NegEnchantment"], "PCDU": ["CantAttack", "NegRune"], "PHWL": ["BlackSummon"],
		"PLMR": ["RedDamage", "GainLife"], "PRAT": ["RedSummon"], "PRFY": ["Disenchant"], "PSBR": ["PosAttack", "PosRune"],
		"PTRS": ["BlackSummon"], "PWTP": ["DrainMana", "PosRune", "NegRune"],
		"QKFX": ["NegAttack", "NegDefence", "NegRune"], "RBRT": ["PosEnchantment"], "RDCL": ["ColosusLeg"],
		"RDCM": ["PosEnchantment"], "RDDF": ["PosSorcery", "PosDefence", "PosRune"], "RDDG": ["BlueSummon"],
		"RDHL": ["GainLife"], "RDIS": ["NegEnchantment"], "RDKN": ["BlackSummon"], "RDLG": ["RedLightning"],
		"RECL": ["Draw"], "REDR": ["PosEnchantment"], "REPR": ["PosSorcery", "BlackDamage", "Draw"],
		"RFPT": ["BlackSummon"], "RIFT": ["RedAnihilation"], "RIOT": ["Hunger", "NegRune"], "RKWL": ["RedSummon"],
		"RNST": ["PosEnchantment"], "RPST": ["PosEnchantment"], "RVHG": ["Hunger"], "RVHL": ["BlueSummon"], "RZMN": ["BlackSummon"],
		"SACR": ["PosEnchantment"], "SCBR": ["PosEnchantment"], "SCSK": ["PosDefence", "PosRune"], "SEHL": ["BlueSummon"],
		"SFGS": ["BlackSuffocationGas", "NegRune"], "SGHT": ["PosEnchantment"], "SHCL": ["PosAttack", "PosRune"],
		"SHFR": ["PosDefence", "PosRune"], "SHSK": ["PosDefence", "PosRune"], "SHSP": ["BlueSummon"],
		"SHWL": ["RedSummon"], "SLRP": ["Regeneration", "PosRune"], "SLWL": ["RedSummon"],
		"SMOK": ["NegEnchantment", "CantUntap"], "SMVL": ["BlackSummon"], "SNCR": ["GreenStoneRing", "GainMana"],
		"SNHG": ["GreenStoneRing", "GainMana"], "SNOV": ["RedSuperNova"], "SNRG": ["GreenStoneRing", "GainMana"],
		"SPBA": ["GreenBasilisk", "PosRune"], "SPBR": ["Disenchant"], "SPFG": ["GreenSummon"], "SPLK": ["PosEnchantment"],
		"SPRG": ["RedAnihilation"], "SPTR": ["NegEnchantment"], "SPWB": ["PosEnchantment"],
		"SPWR": ["Restless", "PosRune"], "STAB": ["BlackSummon"], "STAT": ["PosAttack", "PosRune"],
		"STMC": ["BlackSummon"], "STMZ": ["BlackSummon"], "STRG": ["PosAttack", "PosRune"], "STRT": ["RedSummon"],
		"STSI": ["NegEnchantment", "BlueStasis"], "STTX": ["NegEnchantment"], "STWO": ["PosEnchantment", "PosAttack", "PosRune"],
		"SWHL": ["BlueSummon"], "SWMN": ["BlackSummon"], "SWSN": ["GreenSummon"], "SYMB": ["GainLife"],
		"TANT": ["GreenSummon"], "TGSK": ["PosDefence", "PosRune"], "THIF": ["PosEnchantment", "PosRune"],
		"TIQN": ["GreenSummon"], "TIWK": ["GreenSummon"], "TIWR": ["GreenSummon"], "TNSA": ["GreenSummon"],
		"TPLF": ["DrainLife", "PosRune", "NegRune"], "TRAD": ["GreenDamage", "GainLife"], "TREM": ["Tremor"],
		"TRLB": ["PosEnchantment"], "TRSN": ["GreenSummon"], "TWEN": ["PosAttack", "PosDefence", "PosRune"],
		"TWST": ["GreenHurricane"], "UNSM": ["BlueDeath", "Draw"], "UPGD": ["PosAttack", "PosDefence", "PosRune"],
		"VBAT": ["RedSummon"], "VOLC": ["GainMana"], "VTLY": ["PosEnchantment", "Regeneration", "PosRune"],
		"WEAK": ["NegAttack", "NegDefence", "NegRune"], "WETX": ["NegEnchantment"], "WHAS": ["RedDamage", "Disenchant"],
		"WKHR": ["BlackSummon"], "WLAR": ["BlueSummon"], "WLBL": ["BlackSummon"], "WLBR": ["RedSummon"],
		"WLBZ": ["BlueSummon"], "WLDG": ["BlackSummon"], "WLDT": ["BlackSummon"], "WLFC": ["BlueSummon"],
		"WLIF": ["RedSummon"], "WLIL": ["BlackSummon"], "WLLV": ["RedSummon"], "WLMG": ["RedSummon"],
		"WLWD": ["BlueSummon"], "WNBL": ["PosAttack", "PosDefence", "PosRune"], "WNFL": ["Fireball", "FireballExpl"],
		"WNHR": ["BlackSummon"], "WNMG": ["BlackSummon"], "WNPZ": ["CantUntap", "NegRune"],
		"WRBN": ["PosEnchantment", "PosAttack", "PosDefence"], "WRSP": ["BlueSummon"], "WTEL": ["BlueSummon"],
		"WTLK": ["PosEnchantment"], "WZSP": ["BlueSummon"], "ZAPP": ["RedZap"]
	},
	"el2": {
		"AILK": ["PosEnchantment"], "ALNS": ["PosRune"],
		"ALST": ["Trample", "FirstStrike", "PosAttack", "NegDefence", "PosRune", "NegRune"], "AMNS": ["Discard", "Draw"],
		"ANFR": ["PosEnchantment", "GreenDenceForest"], "ANHL": ["RedAnihilation"], "ANTN": ["GreenSummon"],
		"AREL": ["BlueSummon"], "ASLT": ["PosSorcery", "PosAttack", "PosDefence", "Trample", "Berserk", "PosRune"],
		"ASST": ["NegEnchantment", "CantAttack", "NegRune"], "AVAS": ["BlueSummon"], "AVEL": ["BlueSummon"],
		"AVMK": ["BlueSummon"], "AVSC": ["BlueSummon"], "AWAK": ["Discard", "Draw"], "BANN": ["Discard"],
		"BASO": ["PosEnchantment"], "BATT": ["RedSummon"], "BDEX": ["PosSorcery", "BlackDamage"], "BEHD": ["GreenSummon"],
		"BEQN": ["GreenSummon"], "BEWK": ["GreenSummon"], "BEWR": ["GreenSummon"], "BGVL": ["BlackSummon"],
		"BHMO": ["GreenSummon"], "BHWR": ["GreenSummon"], "BLDG": ["BlueSummon"],
		"BLKD": ["PosEnchantment", "CantAttack", "PosDefence", "PosRune", "NegRune"], "BLNC": ["GainMana"],
		"BLSS": ["PosAttack", "PosDefence", "PosRune"], "BNSH": ["Draw"], "BRAB": ["BlackSummon"],
		"BRGR": ["NegSorcery", "RedDamage"], "BRMC": ["BlackSummon"], "BRMZ": ["BlackSummon"], "BROT": ["PosEnchantment"],
		"BRRD": ["RedAnihilation"], "BRRL": ["LoseMana", "BlackDamage"], "BUDG": ["BlueSummon"], "CAFG": ["GreenSummon"],
		"CANV": ["GreenDamage", "GainLife", "Draw"], "CCLP": ["RedSummon"], "CHCM": ["PosEnchantment"],
		"CHNL": ["LoseLife", "GainMana", "GainLife"], "CLFR": ["Ublockable", "PosRune"], "CLIG": ["RedLightning"],
		"CLNP": ["Disenchant"], "CLON": ["PosSorcery"], "CLSN": ["Disenchant"], "CLSP": ["BlueSummon"],
		"CMBN": ["PosEnchantment", "PosAttack", "PosDefence", "Trample", "PosRune"],
		"CNAR": ["NegEnchantment", "CantUntap"], "CNBL": ["RedDamage", "GainLife"], "COMT": ["RedComet"],
		"COPL": ["PosEnchantment"], "CRBL": ["PosEnchantment", "FirstStrike"], "CRHG": ["Hunger"], "CRIV": ["GreenDamage"],
		"CTMN": ["BlackSummon"], "CTST": ["RedCatstrophe"], "CURS": ["Discard"], "DECN": ["Disenchant"],
		"DELS": ["PosEnchantment", "PosRune"], "DISM": ["NegAttack", "NegRune"],
		"DMRD": ["PosEnchantment", "PosAttack", "PosDefence", "PosRune"], "DMRT": ["RedSummon"],
		"DNFR": ["PosEnchantment", "GreenAncientForest"], "DOMN": ["PosEnchantment", "PosAttack", "PosDefence", "PosRune"],
		"DPGS": ["BlackDepressGas", "NegRune", "NegAttack"], "DRAT": ["RedSummon"],
		"DRFR": ["PosEnchantment", "GreenDarkForest"], "DRGS": ["BlackDrowsyGas", "NegRune", "NegAttack"],
		"DSIG": ["RedFireStream"], "DWND": ["NegDefence", "NegRune"], "EHUN": ["OutplanarSummon"],
		"EKON": ["OutplanarSummon"], "EMAG": ["OutplanarSummon"], "ENAL": ["PosSorcery"],
		"ENBR": ["PosRune", "EnergyBarrier", "PosEnchantment"], "ENFL": ["CantUntap", "NegRune"],
		"ENLH": ["Discard", "Draw"], "ENRG": ["PosEnchantment"], "ENVM": ["NegEnchantment"],
		"ENWO": ["PosEnchantment", "PosDefence", "PosRune"], "ERBN": ["NegEnchantment", "CantUntap"],
		"EREL": ["BlueSummon"], "ERQA": ["Tremor"], "ETAM": ["PosEnchantment"], "ETCH": ["PosSorcery"],
		"ETTD": ["GreenDamage", "Disenchant"], "EWLD": ["CantAttack"], "EXIL": ["BlackExile"],
		"FAIL": ["NegAttack", "NegRune"], "FDBK": ["PosSorcery"], "FLIC": ["Disenchant"],
		"FLOD": ["NegEnchantment", "CantUntap"], "FMFI": ["BlackSummon"], "FOGG": ["BlueFog", "CantAttack"],
		"FRBL": ["PosEnchantment"], "FREL": ["BlueSummon"], "FRGS": ["BlackFrenzyGas", "NegRune", "NegDefence"],
		"FRNT": ["GreenForceNature", "Draw"], "FRST": ["RedFireWave", "RedDamage", "LoseMana"],
		"FRWA": ["RedFireWave", "RedDamage"], "FRWN": ["Draw"], "FTCH": ["Draw", "Fetch"], "FTDS": ["GreenFatalDesease"],
		"FURY": ["Berserk"], "GBAT": ["RedSummon"], "GBBR": ["BlueSummon"], "GBGN": ["BlueSummon"], "GBIN": ["BlueSummon"],
		"GCWR": ["NegEnchantment", "GreaterCreatureWarding"], "GEWR": ["NegEnchantment", "GreaterEnchantmentWarding"],
		"GEYS": ["GainMana"], "GIFG": ["GreenSummon"], "GIFT": ["NegEnchantment", "Gift"], "GLDT": ["NegSorcery"],
		"GRDG": ["BlueSummon"], "GRFG": ["GreenSummon"], "GRHE": ["GainLife"], "GROG": ["RedSummon"],
		"GRSN": ["GreenSummon"], "GRTN": ["GreenSummon"], "GRUN": ["BlueDeath", "Draw"],
		"GSWR": ["NegEnchantment", "GreaterSorceryWarding"],
		"HAST": ["PosEnchantment", "FirstStrike", "Trample", "PosRune"], "HEAL": ["GainLife"], "HOAM": ["PosEnchantment"],
		"HOPR": ["BlackSummon"], "HRCN": ["GreenHurricane"], "HUNG": ["Hunger"], "ICST": ["BlueIceStorm"],
		"IMMB": ["CantUntap", "NegRune"], "IMML": ["PosEnchantment", "PosAttack", "NegDefence", "NegRune", "PosRune"],
		"INCR": ["LoseMana"], "IRAB": ["BlackSummon"], "IRMC": ["BlackSummon"], "IRMZ": ["BlackSummon"],
		"IRRT": ["NegEnchantment"], "JRRG": ["PosSorcery", "BlackDamage"], "JUST": ["GainMana"],
		"JYHD": ["PosEnchantment", "PosAttack"], "KBEL": ["RedSummon"], "KBGD": ["RedSummon"], "KBSH": ["RedSummon"],
		"KBWR": ["RedSummon"], "LASN": ["GreenSummon"], "LCWR": ["NegEnchantment", "LesserCreatureWarding"],
		"LEWR": ["NegEnchantment", "LesserEnchantmentWarding"], "LFGR": ["PosRune", "Lifeguard", "PosEnchantment"],
		"LGST": ["RedLightning", "PosAttack", "PosDefence", "PosRune"], "LMMN": ["BlueSummon"], "LMWA": ["BlueSummon"],
		"LMWD": ["BlueSummon"], "LMWK": ["BlueSummon"], "LNRD": ["PosSorcery"],
		"LQRL": ["DrainMana", "NegRune", "PosRune"], "LSDS": ["NegEnchantment"], "LSHE": ["PosEnchantment"],
		"LSPC": ["Draw"], "LSST": ["PosAttack", "PosDefence", "PosRune"], "LSUS": ["BlueDeath", "Draw"],
		"LSWR": ["NegEnchantment", "LesserSorceryWarding"], "MAHO": ["GreenSummon"], "MALS": ["Discard"],
		"MCWO": ["BlackSummon"], "MCWU": ["BlackSummon"], "MCWY": ["BlackSummon"], "MDBL": ["BlueMindBlast"],
		"MDNS": ["NegEnchantment"], "MDWP": ["Discard"], "MGHT": ["PosAttack", "PosRune"], "MLFI": ["BlackSummon"],
		"MNBN": ["NegEnchantment"], "MNBR": ["GainMana"], "MNDP": ["GainMana"], "MNDW": ["GainMana"],
		"MNHP": ["BlackSummon"], "MNST": ["GainMana"], "MNTH": ["NegEnchantment"], "MNTP": ["GainMana"],
		"MNTS": ["GreenSummon"], "MNTX": ["PosEnchantment"], "MNVR": ["GainMana"], "MOBE": ["GreenSummon"],
		"MOTI": ["GreenSummon"], "MTPT": ["GreenSummon"], "MTSC": ["GreenSummon"], "MXHP": ["BlackSummon"],
		"MYHO": ["GreenSummon"], "NOIS": ["Discard"], "NWLF": ["RedSummon"], "OBLS": ["Disenchant", "OuterBlast"],
		"OCLV": ["OutplaneSpellDeath", "BlueDeath", "Draw"], "OCRP": ["CantUntap", "NegRune"], "OEXC": ["PosEnchantment"],
		"OFLX": ["OuterFluxStart", "OuterFluxHit"], "OGKN": ["RedSummon"], "OMSW": ["Discard", "Draw"],
		"OMWP": ["Discard"], "OREL": ["RedSummon"], "ORFT": ["OutplaneSpellDeath"], "ORGD": ["RedSummon"],
		"ORPL": ["OuterRipple", "PosAttack", "PosDefence", "PosRune"], "ORSH": ["RedSummon"], "ORWR": ["RedSummon"],
		"OSJ1": ["OutplanarSummon"], "OSJ2": ["OutplanarSummon"], "OSJ3": ["OutplanarSummon"], "OST1": ["PosEnchantment"],
		"OST2": ["PosEnchantment"], "OST3": ["PosEnchantment"], "OUD1": ["OutplanarSummon"], "OUD2": ["OutplanarSummon"],
		"OUD3": ["OutplanarSummon"], "OUE1": ["OutplanarSummon"], "OUE2": ["OutplanarSummon"], "OUE3": ["OutplanarSummon"],
		"OUS1": ["OutplanarSummon"], "OUS2": ["OutplanarSummon"], "OUS3": ["OutplanarSummon"],
		"OVRL": ["PosAttack", "PosDefence", "PosRune"], "PALN": ["NegEnchantment"], "PCDU": ["CantAttack", "NegRune"],
		"PHWL": ["BlackSummon"], "PLMR": ["RedDamage", "GainLife"], "PLSL": ["PosEnchantment", "PlanarSeal"],
		"PLWP": ["NegEnchantment"], "PRAT": ["RedSummon"], "PRBN": ["PosRune", "PrimeBind"], "PRFY": ["Disenchant"],
		"PRGD": ["PosRune", "PrimeGuide"], "PRWR": ["NegEnchantment", "PrimeWard"],
		"PRWT": ["NegEnchantment", "PrimeWatch"], "PSBR": ["PosAttack", "PosRune"], "PTRS": ["BlackSummon"],
		"PWTP": ["DrainMana", "PosRune", "NegRune"], "QKFX": ["NegAttack", "NegDefence", "NegRune"],
		"RBRT": ["PosEnchantment"], "RDCL": ["ColosusLeg"], "RDCM": ["PosEnchantment"],
		"RDDF": ["PosSorcery", "PosDefence", "PosRune"], "RDDG": ["BlueSummon"], "RDHL": ["GainLife"],
		"RDIS": ["NegEnchantment"], "RDKN": ["BlackSummon"], "RDLG": ["RedLightning"], "RECL": ["Draw"],
		"REDR": ["PosEnchantment"], "REPR": ["PosSorcery", "BlackDamage", "Draw"], "RFPT": ["BlackSummon"],
		"RIFT": ["RedAnihilation"], "RIOT": ["Hunger", "NegRune"], "RKWL": ["RedSummon"], "RNST": ["PosEnchantment"],
		"RPST": ["PosEnchantment"], "RVHG": ["Hunger"], "RVHL": ["BlueSummon"], "RZMN": ["BlackSummon"],
		"SACR": ["PosEnchantment"], "SCBR": ["PosEnchantment"], "SCSK": ["PosDefence", "PosRune"], "SEHL": ["BlueSummon"],
		"SFGS": ["BlackSuffocationGas", "NegRune"], "SGHT": ["PosEnchantment"], "SHCL": ["PosAttack", "PosRune"],
		"SHFR": ["PosDefence", "PosRune"], "SHSK": ["PosDefence", "PosRune"], "SHSP": ["BlueSummon"],
		"SHWL": ["RedSummon"], "SLRP": ["Regeneration", "PosRune"], "SLWL": ["RedSummon"], "SMFX": ["OutplanarSummon"],
		"SMOK": ["NegEnchantment", "CantUntap"], "SMTG": ["OutplanarSummon"], "SMVL": ["BlackSummon"],
		"SMWB": ["OutplanarSummon"], "SNCR": ["GreenStoneRing", "GainMana"], "SNHG": ["GreenStoneRing", "GainMana"],
		"SNOV": ["RedSuperNova", "LoseMana"], "SNRG": ["GreenStoneRing", "GainMana"], "SPBA": ["GreenBasilisk", "PosRune"],
		"SPBR": ["Disenchant"], "SPFG": ["GreenSummon"], "SPLK": ["PosEnchantment"], "SPRG": ["RedAnihilation"],
		"SPTR": ["NegEnchantment"], "SPWB": ["PosEnchantment"], "SPWR": ["Restless", "PosRune"], "STAB": ["BlackSummon"],
		"STAT": ["PosAttack", "PosRune"], "STMC": ["BlackSummon"], "STMZ": ["BlackSummon"],
		"STRG": ["PosAttack", "PosRune"], "STRT": ["RedSummon"], "STSI": ["NegEnchantment", "BlueStasis"],
		"STSK": ["PosRune", "StoneSkin", "PosEnchantment"], "STTX": ["NegEnchantment"],
		"STWO": ["PosEnchantment", "PosAttack", "PosRune"], "SWHL": ["BlueSummon"], "SWMN": ["BlackSummon"],
		"SWSN": ["GreenSummon"], "SYMB": ["GainLife"], "TANT": ["GreenSummon"], "TGSK": ["PosDefence", "PosRune"],
		"THIF": ["PosEnchantment", "PosRune"], "TIQN": ["GreenSummon"], "TIWK": ["GreenSummon"], "TIWR": ["GreenSummon"],
		"TNSA": ["GreenSummon"], "TPLF": ["DrainLife", "PosRune", "NegRune"], "TRAD": ["GreenDamage", "GainLife"], "TREM": ["Tremor"],
		"TRLB": ["PosEnchantment"], "TRSN": ["GreenSummon"], "TWEN": ["PosAttack", "PosDefence", "PosRune"],
		"TWST": ["GreenHurricane"], "UNSM": ["BlueDeath", "Draw"], "UPGD": ["PosAttack", "PosDefence", "PosRune"],
		"VBAT": ["RedSummon"], "VOLC": ["GainMana"], "VTLY": ["PosEnchantment", "Regeneration", "PosRune"],
		"WEAK": ["NegAttack", "NegDefence", "NegRune"], "WETX": ["NegEnchantment"], "WHAS": ["RedDamage", "Disenchant"],
		"WKHR": ["BlackSummon"], "WLAR": ["BlueSummon"], "WLBL": ["BlackSummon"], "WLBR": ["RedSummon"],
		"WLBZ": ["BlueSummon"], "WLDG": ["BlackSummon"], "WLDT": ["BlackSummon"], "WLFC": ["BlueSummon"],
		"WLIF": ["RedSummon"], "WLIL": ["BlackSummon"], "WLLV": ["RedSummon"], "WLMG": ["RedSummon"],
		"WLWD": ["BlueSummon"], "WNBL": ["PosAttack", "PosDefence", "PosRune"], "WNFL": ["Fireball", "FireballExpl"],
		"WNHR": ["BlackSummon"], "WNMG": ["BlackSummon"], "WNPZ": ["CantUntap", "NegRune"],
		"WRBN": ["PosEnchantment", "PosAttack", "PosDefence"], "WRSP": ["BlueSummon"], "WTEL": ["BlueSummon"],
		"WTLK": ["PosEnchantment"], "WTX2": ["NegEnchantment"], "WZSP": ["BlueSummon"], "ZAPP": ["RedZap"]
	},
}

const TRIGGER := {
	"el1": {
		"BASO": ["Draw"], "BRMZ": ["BlackRedirect"], "ENVM": ["GreenDamage"], "IRMZ": ["BlackRedirect"], "STMZ": ["BlackRedirect"],  "BROT": ["RedDamage", "Fireball", "FireballExpl"], "ENFL": ["Disenchant"],
		"ENRG": ["PosSorcery"], "FRBL": ["Fireball", "FireballExpl"], "IMMB": ["LoseLife"], "LSHE": ["GainLife"],
		"MDNS": ["BlackDamage"], "MNBN": ["RedDamage"], "SWSN": ["GreenDamage"], "TRSN": ["GreenDamage"], "MNTX": ["GainMana"], "QKFX": ["Draw"], "RBRT": ["LoseLife"], "RDIS": ["BlackDamage"], "RIOT": ["Draw"], "RNST": ["RedRainOfStones"],
		"RPST": ["PosSorcery", "BlackDamage", "Draw"], "SACR": ["GreenDamage", "GainMana"], "SCBR": ["PosSorcery"],
		"SFGS": ["BlackDamage"], "SPLK": ["GreenDamage", "GainMana"], "SPTR": ["LoseMana"], "SPWB": ["GainLife"], "STSI": ["Disenchant"],
		"STTX": ["BlackDamage"], "WETX": ["BlackDamage"],
		"TRLB": ["Draw", "BlackDamage"], "WNPZ": ["LoseLife"], "WTLK": ["GainLife"]
	},
	"el2": {
		"ALNS": ["Draw"], "BASO": ["Draw"], "BRMZ": ["BlackRedirect"], "ENVM": ["GreenDamage"], "IRMZ": ["BlackRedirect"], "STMZ": ["BlackRedirect"], "OCRP": ["Draw"], "WTX2": ["BlackDamage"],  "BROT": ["RedDamage", "Fireball", "FireballExpl"], "DELS": ["Draw"],
		"ENFL": ["Disenchant"], "ENRG": ["PosSorcery"], "FRBL": ["Fireball", "FireballExpl"], "LSHE": ["GainLife"],
		"MDNS": ["BlackDamage"], "MNBN": ["RedDamage"], "SWSN": ["GreenDamage"], "TRSN": ["GreenDamage"], "MNTX": ["GainMana"], "OEXC": ["OuterExchange"], "PLWP": ["PlaneWarp", "OutplaneSpellDeath"], "PRBN": ["Draw"], "QKFX": ["Draw"], "RBRT": ["LoseLife"],
		"IRRT": ["BlackDamage"], "RDIS": ["BlackDamage"], "RIOT": ["Draw"], "RNST": ["RedRainOfStones"], "RPST": ["PosSorcery", "BlackDamage", "Draw"],
		"SACR": ["GreenDamage", "Draw"], "SCBR": ["PosSorcery"], "SFGS": ["BlackDamage"], "SPLK": ["GreenDamage", "GainMana"], "SPTR": ["LoseMana"],
		"SPWB": ["GainLife"], "STSI": ["Disenchant"], "STTX": ["BlackDamage"],
		"TRLB": ["Draw", "BlackDamage"], "WETX": ["BlackDamage"], "WNPZ": ["LoseLife"],
		"WTLK": ["GainLife"]
	},
}

## ABILITY: effects started when an ability of that card is used (a creature's
## own ability, or one an enchantment of that card grants), each with the
## figures it is drawn between: "line" from the user to the target, "at" the
## affected figure, "start" at the user, "finish" at the target. Effects about a
## hero's life, ether or cards are drawn at the acting hero.
const ABILITY := {
	"el1": {
		# Original EL1 BlackDragonAbility binds its original
		# BlackDragonInstant Start/Finish particle to the slay target.
		"BLDG": [["BlackDragonInstant", "line"]],
		"FRBL": [["Fireball", "line"], ["FireballExpl", "finish"]],
		# Original EL1 GiantFingusAbility@ names FingusSpit and
		# binds it from the living actor to the selected hero or creature.
		"GIFG": [["FingusSpit", "line"]],
		"KBSH": [["RedZap", "line"]],
		# SACR original – queues Target/GreenDamage
		# on the creature selected for sacrifice before its removal.
		# The separate post-ether hero GainMana uses a state event.
		"SACR": [["GreenDamage", "at"]],
		"RBRT": [["LoseLife", "at"]],
		# Cutter, Sawer and Razor Man run BlackRedirect from the creature they
		# sacrifice (Start) to themselves (Finish).
		"RZMN": [["BlackRedirect", "to_user"]],
		"SCBR": [["PosSorcery", "at"]], "WLDT": [["CantAttack", "at"]],
		# Each creature's own EL1 ability code starts the named effect, with
		# Start/Finish (line) or one Target as the effect's points say; the
		# same cards use the same effects in the second game.
		"BEHD": [["GreenDamage", "at"]], "BHWR": [["GreenDamage", "at"]], "CAFG": [["FingusSpit", "line"]],
		"CCLP": [["CyclopStone", "line"]], "CTMN": [["BlackRedirect", "to_user"]], "DMRT": [["Draw", "at"]],
		"ENFL": [["Disenchant", "at"]], "ENRG": [["PosSorcery", "at"]], "GRDG": [["GreenDragonInstant", "line"]],
		"GRFG": [["FingusSpit", "line"]], "LMMN": [["Draw", "at"]], "LMWK": [["Draw", "at"]],
		"LSHE": [["GainLife", "at"]], "MNTS": [["NegSorcery", "at"]], "ORSH": [["GainMana", "at"]],
		"PHWL": [["PosAttack", "at"]], "PTRS": [["Disenchant", "at"]], "RFPT": [["Disenchant", "at"]],
		"SPFG": [["FingusSpit", "line"]], "SPLK": [["GreenDamage", "at"], ["GainMana", "at"]],
		"SWMN": [["BlackRedirect", "to_user"]], "VBAT": [["DrainLife", "line"]], "WLIF": [["PosDefence", "at"]],
		"WLLV": [["PosAttack", "at"]], "WLWD": [["PosAttack", "at"]], "WZSP": [["PosSorcery", "at"]],
		# The first game's Rain of Stone binds Start to the caster's own hero,
		# after paying, unlike the second game's opposing hero.
		# The Wand of Heroes' Hunter shoots HuntersArrow from itself to its
		# target (HeroAbility), as in the second game.
		"WNHR": [["HuntersArrow", "line"]],
		"RNST": [["RedRainOfStones", "start"]],
		"RPST": [["PosSorcery", "at"], ["BlackDamage", "at"], ["Draw", "at"]]
	},
	"el2": {
		"BEHD": [["GreenDamage", "at"]], "BHWR": [["GreenDamage", "at"]], "BLDG": [["BlackDragonInstant", "line"]],
		"BROT": [["RedDamage", "at"], ["Fireball", "line"], ["FireballExpl", "finish"]], "CAFG": [["FingusSpit", "line"]],
		"CCLP": [["CyclopStone", "line"]], "CTMN": [["BlackRedirect", "to_user"]], "DMRT": [["Draw", "at"]],
		"ENFL": [["Disenchant", "at"]], "ENRG": [["PosSorcery", "at"]], "FRBL": [["Fireball", "line"], ["FireballExpl", "finish"]],
		"GIFG": [["FingusSpit", "line"]], "GRDG": [["GreenDragonInstant", "line"]], "GRFG": [["FingusSpit", "line"]],
		"IMMB": [["LoseLife", "at"]], "KBEL": [["PosSorcery", "at"]], "KBSH": [["RedZap", "line"]], "LMMN": [["Draw", "at"]],
		"LMWK": [["Draw", "at"]], "LSHE": [["GainLife", "at"]], "MNTS": [["NegSorcery", "at"]], "MTPT": [["NegSorcery", "at"]],
		"MTSC": [["NegSorcery", "at"]], "OEXC": [["OuterExchange", "line"]], "ORSH": [["GainMana", "at"]],
		"OUD1": [["PaleDrainLife", "line"], ["GainLife", "at"]], "OUD2": [["PaleDrainLife", "line"], ["GainLife", "at"]],
		"OUD3": [["PaleDrainLife", "line"], ["GainMana", "at"]],
		"OUE1": [["PaleDrainEncantment", "to_user"], ["Disenchant", "at"], ["GainMana", "at"]],
		"OUE2": [["PaleDrainEncantment", "to_user"], ["Draw", "at"]],
		"OUE3": [["PaleDrainEncantment", "to_user"], ["Disenchant", "at"], ["Draw", "at"]],
		"OUS1": [["GainMana", "at"], ["PosRune", "at"]], "OUS2": [["NegRune", "at"], ["RedDamage", "at"]],
		"OUS3": [["GainLife", "at"], ["PosRune", "at"]], "PHWL": [["PosAttack", "at"]], "PTRS": [["Disenchant", "at"]],
		"RBRT": [["LoseLife", "at"]], "RFPT": [["Disenchant", "at"]], "RNST": [["RedRainOfStones", "enemy_start"]],
		"RPST": [["PosSorcery", "at"], ["BlackDamage", "at"], ["Draw", "at"]], "RVHL": [["DrainMana", "line"]],
		"RZMN": [["BlackRedirect", "to_user"]], "SACR": [["GreenDamage", "at"], ["Draw", "at"]], "SCBR": [["PosSorcery", "at"]],
		"SEHL": [["DrainMana", "line"]], "SPFG": [["FingusSpit", "line"]], "SPLK": [["GreenDamage", "at"], ["GainMana", "at"]],
		"SWHL": [["DrainMana", "line"]], "SWMN": [["BlackRedirect", "to_user"]], "VBAT": [["DrainLife", "line"]],
		"WLDT": [["CantAttack", "at"]], "WLIF": [["PosDefence", "at"]], "WLLV": [["PosAttack", "at"]],
		"WLWD": [["PosAttack", "at"]], "WNHR": [["HuntersArrow", "line"]], "WNPZ": [["LoseLife", "at"]],
		"WZSP": [["PosSorcery", "at"]]
	},
}
## COMBAT: effects of a creature power that acts during combat damage, keyed by
## the power (a mastery code or a strike property), each drawn at the affected
## figure ("at") or from the first figure to the second ("line"). The second
## game adds none here.
const COMBAT := {
	"el1": {
		"GBHD": [["GreenDamage", "at"]], "BWIT": [["CantUntap", "at"], ["NegRune", "at"]], "BPTD": [["Disenchant", "at"]],
		"Disenchant": [["Disenchant", "at"]], "Lifetap": [["DrainLife", "line"]], "Discard": [["Discard", "at"]],
		"ENLH": [["Draw", "at"]]
	},
	"el2": {},
}
## Effects about a hero's own life, ether or cards.
## Creature auras: the effects each original aura callback starts on a
## creature it covers (EL2 slot 13, EL1 slot 11; the same in both games).
## "MOBE:death" is Mother Bee's frenzy on every bee when she dies.
const AURA_EFFECTS := {
	"TIWK": ["PosAttack", "PosDefence"], "TIQN": ["PosDefence"], "BEWK": ["PosAttack"],
	"BEQN": ["PosAttack", "PosDefence"], "KBWR": ["PosAttack"], "MOTI": ["Restless"], "MOBE": ["FirstStrike"],
	"MOBE:death": ["Berserk"], "SHSP": ["PosDefence"], "CLSP": ["PosAttack", "PosDefence"], "OREL": ["Restless"],
	"SLWL": ["PosDefence"], "AVEL": ["PosAttack", "PosDefence"], "ORWR": ["PosAttack", "PosDefence", "Berserk"],
	"WZSP": ["PosAttack"], "GRFG": ["PosAttack", "PosDefence"],
	# Gas arrivals (the gases' per-creature callbacks).
	"DRGS": ["NegAttack", "NegRune"], "DPGS": ["NegAttack", "NegRune"], "FRGS": ["NegDefence", "NegRune"],
}
const HERO_EFFECTS := ["GainLife", "LoseLife", "GainMana", "LoseMana", "Draw", "Discard"]
## A hero's damage turned aside: redirection to its creatures (from the hero to
## each creature) and feedback (at the hero); a barrier softening it (second game).
const REDIRECT := "BlackRedirect"
const FEEDBACK := "BlueFeedback"
const BARRIER := "EnergyBarrierAbility"
## Stone skin softening a strike (second game; hero or creature).
const STONESKIN := "StoneSkinAbility"
## Wall of Illusion's ability, both games: its defence rises when the owner's
## graveyard holds a creature, else it falls.
const ILLUSION_CARD := "WLIL"

## Summon effect of a creature card's colour; colourless creatures of the second
## game use the out-of-plane summon, the first game's red one.
static func summon_effect(edition: String, color: String) -> String:
	if color in ["Red", "Green", "Blue", "Black"]: return color + "Summon"
	return "OutplanarSummon" if edition == "el2" else "RedSummon"

## Effects a cast of `card` starts in a profile's edition: the card's own
## entry, else a creature card's colour summon. Shared by the combat sounds
## (ELBattleAudio) and the combat particles (ELCombatEffects).
static func card_effects(profile: ELProfile, card: String) -> Array:
	var effects := cast_effects(profile.id, card)
	if effects.is_empty():
		var row: Dictionary = profile.table("CombatSpells").get(card, {})
		if row.get("Class", "") == "Creature": effects = [summon_effect(profile.id, String(row.get("Color", "")))]
	return effects

static func cast_effects(edition: String, card: String) -> Array:
	return CAST.get(edition, {}).get(card, [])

static func trigger_effects(edition: String, card: String) -> Array:
	return TRIGGER.get(edition, {}).get(card, [])

## [[effect, binding], ...] for an ability of `card` in `edition`.
static func ability_effects(edition: String, card: String) -> Array:
	return ABILITY.get(edition, {}).get(card, [])

## [[effect, binding], ...] for Wall of Illusion's ability with `grave` creatures
## in its owner's graveyard.
static func illusion_effects(grave: int) -> Array:
	return [["PosDefence" if grave > 0 else "NegDefence", "at"]]

## [[effect, binding], ...] for a combat power `key` in `edition`.
static func combat_effects(edition: String, key: String) -> Array:
	return COMBAT.get(edition, {}).get(key, [])
