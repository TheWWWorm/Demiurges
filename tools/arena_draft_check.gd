extends SceneTree
## Draft rules, transcripts and composition checks. No original assets needed.
##   godot --headless --path game --script ../tools/arena_draft_check.gd -- --drafts=2048
## Optional: --el2=/installed/game or --fixture=/catalog-derived/fixture.json.
## Synthetic numbers exercise the rules; they are not a combat balance proof.

var failures := 0

func _arg(name: String, fallback := "") -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--" + name + "="): return value.substr(name.length() + 3)
	return fallback

func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

## Shared by the run checks. An optional fixture supplies printed card data
## from the checked-in wiki. Hero health/income are deliberately synthetic;
## mount a real installation to check original numeric combat balance.
static func synthetic_profile(fixture_path := "") -> ELProfile:
	var profile := ELProfile.new()
	profile.id = "el2"
	profile.title = "Arena synthetic test profile"
	profile.tables = {"CombatSpells": {}, "CombatCreatures": {}}
	if not fixture_path.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		if data is not Dictionary or data.get("el2") is not Dictionary: return null
		profile.tables = Dictionary(data.el2).duplicate(true)
		profile.texts = Dictionary(profile.tables.get("texts", {})).duplicate()
	else:
		var bodies := {
			"Red": ["STRT", "KBWR", "KBGD", "KBSH", "OREL", "ORWR", "GROG", "OGKN"],
			"Green": ["TIWR", "TIWK", "TIQN", "BEWR", "BEWK", "MOBE", "MOTI", "MAHO", "CAFG"],
			"Blue": ["AVSC", "AVMK", "AVEL", "WTEL", "WRSP", "SHSP", "CLSP", "RKWL"],
			"Black": ["BRAB", "IRAB", "STAB", "BRMC", "IRMC", "STMC", "MNHP", "WLMG", "GBAT"],
		}
		for faction: String in bodies:
			for i in bodies[faction].size():
				var code := String(bodies[faction][i])
				var cost: int = 1 + i % 6
				profile.tables.CombatSpells[code] = {"Class": "Creature", "Cost": cost, "Color": faction, "Rarity": "Common", "Use": "+", "Name": code}
				var tribe := "Tick" if code.begins_with("TI") or code == "MOTI" else ("Bee" if code.begins_with("BE") or code == "MOBE" else "Test")
				profile.tables.CombatCreatures[code] = {"Power": maxi(1, cost - 1), "Toughness": cost + 1, "Race": tribe, "Flags": []}
		var spells := {
			"Red": ["ZAPP", "FRWA", "COMT", "FRST", "TREM", "FLIC", "MGHT"],
			"Green": ["TRAD", "PRFY", "ETTD", "BLSS", "DOMN", "GRHE", "CLON"],
			"Blue": ["CLIG", "RIFT", "EXIL", "CLNP", "UNSM", "LSPC", "MALS"],
			"Black": ["WEAK", "DWND", "DECN", "NOIS", "REPR", "UPGD", "QKFX"],
			"White": ["FTCH", "LFGR", "ENBR", "OBLS", "OCLV"],
		}
		for faction: String in spells:
			for i in spells[faction].size():
				var code := String(spells[faction][i])
				profile.tables.CombatSpells[code] = {"Class": "Sorcery", "Cost": 1 + i % 4, "Color": faction, "Rarity": "Common", "Use": "+", "Name": code}
		for code: String in ELArenaRules.EXCLUDED:
			profile.tables.CombatSpells[code] = {"Class": "Enchantment", "Cost": 2, "Color": "White", "Rarity": "Unique", "Use": "+", "Name": code}
	# The older puzzle fixture omits artifact metadata. These two documented
	# artifact rows also have hand-cast implementations, so rule() alone must
	# not make their zero-cost artifact versions draftable.
	for code: String in ELCatalog.BOOK_ARTIFACTS:
		if profile.tables.CombatSpells.has(code): profile.tables.CombatSpells[code].IsArtifact = "True"
	profile.tables.HeroesSkills = {"PRVD1": {"Code": "PRVD", "Level": 1, "Name": "Providence", "Duel": "True"}}
	profile.tables.HeroesStats = {}
	profile.tables.HeroTemplates = {}
	profile.tables.CombatSceneDB = {}
	profile.tables.ScenesNames = {}
	profile.tables.CombatManaIncome = {}
	profile.tables.Artefacts = {}
	profile.tables.DuelResourceLevels = {}
	profile.tables.CombatDecks = {}
	for faction: String in ELArenaRules.FACTIONS:
		var name := String(ELDuelPresets.DEFAULT_HEROES[faction])
		profile.tables.HeroTemplates[name] = {"BaseHealth": 7, "HealthIncrease": 3, "Level": 5, "Skills": []}
		profile.tables.CombatSceneDB[faction + ".001"] = {}
		profile.tables.ScenesNames[faction + ".001"] = {"Name": faction}
	for turn in range(1, 31):
		var row := {}
		for level in range(1, 21): row["Level%d" % level] = 1 if turn <= 8 else 0
		profile.tables.CombatManaIncome[str(turn)] = row
	return profile

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile: ELProfile
	var installation := _arg("el2")
	if not installation.is_empty():
		profile = ELProfile.new()
		if not profile.mount("el2", installation):
			printerr(profile.error)
			quit(1)
			return
	else:
		profile = synthetic_profile(_arg("fixture"))
	if profile == null:
		printerr("Could not load the requested Arena fixture.")
		quit(1)
		return
	print("PROFILE: ", "installed Etherlords II" if not installation.is_empty() else ("catalog-derived cards with synthetic hero/income" if not _arg("fixture").is_empty() else "synthetic cards and heroes"))
	_pool_checks(profile)
	_transcript_checks(profile)
	_bot_checks(profile, clampi(int(_arg("drafts", "2048")), 4, 100000))
	print("ARENA DRAFT: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)

func _pool_checks(profile: ELProfile) -> void:
	var shared := ELArenaRules.pool(profile, "Red")
	var union := {}
	for faction: String in ELArenaRules.FACTIONS:
		var pool := ELArenaRules.pool(profile, faction, ELArenaRules.FACTION_RULES)
		var valid := pool.size() >= 6
		for code: String in pool:
			valid = valid and ELArenaRules.excluded_reason(profile, code).is_empty() and profile.table("CombatSpells")[code].Color == faction
		for code: String in ELArenaRules.pool(profile, faction, ELArenaRules.LEGACY_RULES): union[code] = true
		check(valid, "%s pool: %d supported spells from this faction only" % [faction, pool.size()])
		check(ELArenaRules.pool(profile, faction) == shared, "%s hero draws from the same Any faction pool" % faction)
	check(shared.size() == union.size() and shared.all(func(code: String) -> bool: return union.has(code)), "Any faction includes the full union of eligible decks")
	check(not ELArenaRules.excluded_reason(profile, "STSI").is_empty() and not ELArenaRules.excluded_reason(profile, "CHNL").is_empty(), "hard combo engines have readable exclusions")
	if profile.table("CombatSpells").has("MOTI"):
		check(ELArenaRules.excluded_reason(profile, "MOTI").is_empty() and ELArenaRules.features(profile, "MOTI").generator, "self-sufficient tribal generators remain draftable")
	if profile.table("CombatSpells").has("FTCH"):
		check(int(ELArenaRules.features(profile, "FTCH").channels) == 1, "Fetch's channel sacrifice participates in valuation")
	if profile.table("CombatSpells").has("ETTD"):
		check(ELArenaRules.features(profile, "ETTD").dispel, "Sacrificial Cleansing counts as an enchantment answer")
	if profile.table("CombatSpells").has("OBLS"):
		check(not ELArenaRules.features(profile, "OBLS").removal and not ELArenaRules.features(profile, "OBLS").dispel, "Blast is not mistaken for unrestricted removal or a hero-enchantment answer")
	for code: String in ELCatalog.BOOK_ARTIFACTS:
		if profile.table("CombatSpells").has(code): check(not ELArenaRules.excluded_reason(profile, code).is_empty(), "artifact spell %s cannot enter the draft" % code)
	var wrong := ELProfile.new()
	wrong.id = "el1"
	check(ELArenaRules.pool(wrong, "Red").is_empty(), "sixteen-pick format does not silently use EL1 rules")
	var remounted := synthetic_profile()
	var active := ELArenaDraft.new()
	active.create(remounted, "Red", 212)
	var active_before := active.snapshot()
	var old_signature := ELArenaRules.pool_signature(remounted, "Red")
	var removed := ELArenaRules.pool(remounted, "Red")[0]
	remounted.tables.CombatSpells[removed].Use = "-"
	remounted.generation += 1
	check(removed not in ELArenaRules.pool(remounted, "Red") and ELArenaRules.pool_signature(remounted, "Red") != old_signature, "remounting the same profile invalidates its pool and signature caches")
	check(not active.choose(0) and active.snapshot() == active_before, "a changed live card pool cannot silently reinterpret an offered pick")

func _transcript_checks(profile: ELProfile) -> void:
	var draft := ELArenaDraft.new()
	check(draft.create(profile, "Green", 81234), "a draft begins with three distinct choices")
	if draft.offer.size() != 3: return
	var valid := draft.offer.size() == 3
	for i in 7:
		valid = valid and draft.offer[0] != draft.offer[1] and draft.offer[0] != draft.offer[2] and draft.offer[1] != draft.offer[2]
		valid = valid and draft.choose(i % 3)
	check(valid and draft.history.size() == 7, "seven picks each select one real offered spell")
	var before := draft.snapshot()
	check(not draft.choose(-1) and not draft.choose(3) and draft.snapshot() == before, "invalid indices cannot mutate a draft")
	var resumed := ELArenaDraft.new()
	var json: Variant = JSON.parse_string(JSON.stringify(before))
	check(resumed.restore(profile, json) and resumed.snapshot() == before, "JSON checkpoint restores exact picks and next offer")
	var twins := true
	for step in range(ELArenaRules.DECK_SIZE - draft.cards.size()):
		twins = twins and draft.offer == resumed.offer
		var pick := ELArenaDraftBot.choose(draft)
		twins = twins and draft.choose(pick) and resumed.choose(pick)
	check(twins and draft.cards == resumed.cards and draft.offer.is_empty(), "resumed continuation is identical through all sixteen picks")
	check(ELArenaRules.validate_deck(profile, "Green", draft.cards).is_empty() and not draft.choose(0), "completed deck is legal and cannot take a seventeenth card")
	var finished := draft.snapshot()
	var victim := ELArenaDraft.new()
	victim.create(profile, "Red", 77)
	var untouched := victim.snapshot()
	for kind: String in ["offer", "choice", "card", "deck", "current", "missing", "seed", "pool", "fractional"]:
		var changed := before.duplicate(true)
		match kind:
			"offer": changed.history[0].offer[0] = "FAKE"
			"choice": changed.history[0].choice = (int(changed.history[0].choice) + 1) % 3
			"card": changed.history[0].card = "FAKE"
			"deck": changed.cards[0] = "FAKE"
			"current": changed.offer.reverse()
			"missing": changed.history.pop_back()
			"seed": changed.seed = int(changed.seed) + 1
			"pool": changed.pool_signature = "changed"
			"fractional": changed.history[0].choice = 0.5
		check(not victim.restore(profile, changed) and victim.snapshot() == untouched, "tampered %s is rejected without overwriting the existing draft" % kind)
	check(victim.restore(profile, JSON.parse_string(JSON.stringify(finished))) and victim.finished(), "finished transcripts also regenerate and validate")
	var overfull: Array = draft.cards.duplicate()
	for i in 5: overfull[i] = draft.cards[0]
	check(not ELArenaRules.validate_deck(profile, "Green", overfull).is_empty(), "four-copy ceiling is independently validated")
	for rules: int in [ELArenaRules.LEGACY_RULES, ELArenaRules.FACTION_RULES, ELArenaRules.OPEN_RULES]:
		var bot := ELArenaDraftBot.make(profile, "Blue", 1122, "control", rules)
		var human := ELArenaDraft.new()
		human.create(profile, "Blue", 1122, rules)
		var parity := bot.finished()
		for entry: Dictionary in bot.history:
			parity = parity and human.offer == entry.offer and human.choose(int(entry.choice))
		check(parity and bot.cards == human.cards, "Rules %d: bot's complete deck is reproducible through the human's exact 16 offers" % rules)
		var preset := ELArenaRules.hero_preset(profile, "Blue", bot.cards, rules)
		check(not preset.is_empty() and int(preset.level) == 5 and preset.skills == {"PRVD": 0} and int(preset.resource_level) == ELArenaRules.resource_level(rules) and preset.reserve.is_empty() and preset.artifacts.is_empty() and preset.specialization == "NONE", "Rules %d: battle preset freezes level, Providence, budget, specialization and artifacts" % rules)

func _bot_checks(profile: ELProfile, total: int) -> void:
	var broken := 0
	var weak := 0
	var metrics := {}
	for faction: String in ELArenaRules.FACTIONS:
		metrics[faction] = {"n": 0, "bodies": 0, "early": 0, "interaction": 0, "dispel": 0, "expensive": 0, "cost": 0,
			"min_bodies": 16, "min_early": 16, "min_interaction": 16, "no_dispel": 0, "unique": {}}
	for i in total:
		var faction: String = ELArenaRules.FACTIONS[i % 4]
		var style: String = ELArenaDraftBot.STYLES[(i / 4) % ELArenaDraftBot.STYLES.size()]
		var rules := ELArenaRules.OPEN_RULES if (i / 16) % 2 == 0 else ELArenaRules.FACTION_RULES
		var draft := ELArenaDraftBot.make(profile, faction, 1000 + i * 97, style, rules)
		if not draft.finished() or not ELArenaRules.validate_deck(profile, faction, draft.cards, rules).is_empty():
			broken += 1
			continue
		var s := ELArenaRules.summary(profile, draft.cards)
		var m: Dictionary = metrics[faction]
		m.n += 1
		m.bodies += int(s.creatures)
		m.early += int(s.early)
		m.interaction += int(s.interaction)
		m.dispel += int(s.dispel)
		m.expensive += int(s.expensive)
		m.cost += int(s.cost)
		m.min_bodies = mini(int(m.min_bodies), int(s.creatures))
		m.min_early = mini(int(m.min_early), int(s.early))
		m.min_interaction = mini(int(m.min_interaction), int(s.interaction))
		if int(s.dispel) == 0: m.no_dispel += 1
		for code: String in draft.cards: m.unique[code] = true
		if int(s.creatures) < 7 or int(s.early) < 3 or int(s.interaction) < 2 or int(s.expensive) > 5:
			weak += 1
			if weak <= 8: print("COMPOSITION WARNING %s %s seed=%d %s" % [faction, style, draft.seed_value, JSON.stringify(s)])
	check(broken == 0, "%d seeded bot drafts all contain sixteen eligible picks within the copy cap" % total)
	# Rare unfavorable offers can remain; the generator must not repair a bot's
	# deck behind the player's back. This bound catches an evaluator regression.
	check(weak <= maxi(2, total / 100), "at least 99%% meet modest playability floors (7 creatures, 3 early threats, 2 interaction, at most 5 expensive); weak=%d" % weak)
	for faction: String in ELArenaRules.FACTIONS:
		var m: Dictionary = metrics[faction]
		var n := maxf(1.0, float(m.n))
		print("DRAFT METRIC %s n=%d creatures=%.2f early=%.2f interaction=%.2f dispel=%.2f expensive=%.2f average_cost=%.2f minima=%d/%d/%d no_dispel=%d distinct_cards=%d" % [faction, m.n, float(m.bodies) / n, float(m.early) / n, float(m.interaction) / n, float(m.dispel) / n, float(m.expensive) / n, float(m.cost) / n / 16.0, m.min_bodies, m.min_early, m.min_interaction, m.no_dispel, m.unique.size()])
