extends SceneTree
## Player feedback on Evil Dale: "the mission seems too easy" and "Glazzz
## talks like a woman".
##
## - The original program gives every BLevHero hero on the mission's map the
##   guard area of a neutral creature (the ring around it), so no rival can be
##   walked past; elsewhere neutral heroes still guard nothing.
## - Every rival but Glazzz attacks the Chosen One within its sight (Glazzz
##   within his sight less three tiles, and otherwise walks his loop); none
##   is within reach of the Chosen One's glade at the start.
## - The dale's creatures keep pace with its rivals (revision 3): each
##   takes the level of the rivals around its place on the walk, so the
##   creatures by Valaddin, Tango and Warp are within three levels of them
##   (they had been four or five below with the second revision's line from
##   1 to 9), and a hero who fights his way along meets them nearer his own
##   level. A save of revision 2 keeps its creatures (and its mission:
##   earlier revisions' map ids are recognised again).
## - A creature fights with its own Monsters row for the difficulty (level,
##   health, deck) and the difficulty's level change, as in the original.
## - The guard relief of "AI fights neutral monsters" (lower level and health
##   by mines) is for computer heroes; a map with no other player keeps its
##   guards, so the option no longer weakens the dale's creatures.
## - Glazzz is a man: his figure, textures, portrait and voice are those of
##   GreenEggMale4 (only the template's unused Gender column says F), his
##   battle voice is the male Vital set, and his lines in the remake's story
##   speak of him as a man in both languages.
##
##   godot --headless --path game --script ../tools/feedback_evil_dale_check.gd
##
## Needs the first game's files (user://profiles.json); skipped without them.
## Saves and settings are not touched.

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no el1 files configured (user://profiles.json)")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths["el1"])):
		print("SKIP: el1 files could not be mounted")
		quit(0)
		return
	_glazzz_is_male(profile)
	_rivals(profile)
	_creatures(profile)
	_elsewhere(profile)
	print("FEEDBACK EVIL DALE: %d failure(s)" % failures)
	quit(int(failures > 0))

func _glazzz_is_male(profile: ELProfile) -> void:
	var templates := profile.table("HeroTemplates")
	var glazzz: Dictionary = templates.get(ELRestoredMissions.PATROLLER, {})
	var model: Dictionary = templates.get("GreenEggMale4", {})
	check(not glazzz.is_empty() and not model.is_empty(), "the files have Glazzz and GreenEggMale4")
	if glazzz.is_empty() or model.is_empty(): return
	var same := true
	for column: String in ["Model", "Texture", "Face", "SndDir", "AdvMod", "AdvTex1"]:
		if str(glazzz.get(column, "")) != str(model.get(column, "")): same = false
	check(same, "Glazzz wears GreenEggMale4's figure, textures, portrait and voice")
	check(str(glazzz.SndDir) == "GreenHeroEggMale" and str(model.get("Gender", "")) == "M", "his voice set is the male one (%s)" % glazzz.SndDir)
	check(not ELAudio.sound(profile, "Creatures/%s/voice/hit01.wav" % glazzz.SndDir) == null, "the voice set is in the files")
	var lines: Array = []
	for scenario: String in ELRestoredStory.STORY:
		for beat: Dictionary in ELRestoredStory.STORY[scenario]:
			if not str(beat.id).begins_with("glazzz"): continue
			for line: Array in beat.lines: lines.append(" ".join(line.slice(1)))
	check(lines.size() == 3, "Glazzz's meeting and defeat have their lines (%d)" % lines.size())
	var feminine := RegEx.create_from_string("(?i)\\b(sister|she|her|herself)\\b|сестр|пришла|сама\\b")
	var found := lines.filter(func(text: String) -> bool: return feminine.search(text) != null)
	check(found.is_empty(), "the lines speak of Glazzz as a man in both languages")
	check(lines.any(func(text: String) -> bool: return text.contains("пришел")) and lines.any(func(text: String) -> bool: return text.contains("Brother")), "he says he came (masculine) and is called brother")

func _dale_session(profile: ELProfile) -> Array:
	var entry := {}
	for found: Dictionary in ELSingleScenario.catalog(profile):
		if found.get("restored", "") == ELRestoredMissions.EVIL_DALE: entry = found
	if entry.is_empty(): return []
	var map := ELFirstRandomMap.new().generate(profile, entry.random_map)
	if map == null: return []
	var state := ELAdventureSession.new()
	if not state.start(map, 2, ELFirstRandomMap.seed_for_config(entry.random_map), "", 1, false, true): return []
	var director := ELAdventureDirector.new()
	if not director.build(state): return []
	return [state, director]

func _rivals(profile: ELProfile) -> void:
	var made := _dale_session(profile)
	check(not made.is_empty(), "the dale starts")
	if made.is_empty(): return
	var state: ELAdventureSession = made[0]
	var director: ELAdventureDirector = made[1]
	var chosen := ELRestoredMissions.chosen_one(state)
	var rivals := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and ELRestoredMissions.RIVALS.has(str(item.name)): rivals[str(item.name)] = item
	check(rivals.size() == 5 and not chosen.is_empty(), "the Chosen One and the five rivals are on the map")
	if rivals.size() != 5 or chosen.is_empty(): return
	var start := Vector2i(chosen.x, chosen.y)
	# Template strength, as the files give it.
	var templates := profile.table("HeroTemplates")
	for name: String in rivals:
		var rival: Dictionary = rivals[name]
		var row: Dictionary = templates[name]
		check(int(rival.level) == int(row.Level) and rival.cards == ELCatalog.deck(profile, str(row.StartDeck)) and str(rival.specialization) == str(row.Specialization) and rival.skills == ELHeroSkills.from_template(profile, row),
			"%s has his template's level %d, deck %s, specialisation and skills" % [name, int(row.Level), row.StartDeck])
	# Guard areas.
	for name: String in rivals:
		var rival: Dictionary = rivals[name]
		var zone: Dictionary = director.interception.zones.get(int(rival.uid), {})
		var ring: Array = Array(zone.get("cells", [])).filter(func(cell: Vector2i) -> bool: return cell != Vector2i(rival.x, rival.y))
		check(not zone.is_empty() and zone.origin == Vector2i(rival.x, rival.y) and ring.size() >= 3 and ring.size() <= 8, "%s guards the ring around him (%d tiles)" % [name, ring.size()])
		var beside: Vector2i = ring[0] if not ring.is_empty() else Vector2i(-1, -1)
		check(director.interception.enemies(state, chosen, beside).has(int(rival.uid)), "the Chosen One beside %s is stopped by him" % name)
	var snapshot := director.interception.snapshot()
	check(director.interception.restore(snapshot, state, director.grid) and director.interception.zones.size() == snapshot.size(), "a save keeps the rivals' guard areas")
	# No rival is within reach of the glade at the start.
	for name: String in rivals:
		var rival: Dictionary = rivals[name]
		var reach := float(ELFog.sight_radius(rival)) - (3.0 if name == ELRestoredMissions.PATROLLER else 0.0)
		check(Vector2(start).distance_to(Vector2(rival.x, rival.y)) >= reach, "%s cannot see the Chosen One's glade (%.0f tiles, sight %d)" % [name, Vector2(start).distance_to(Vector2(rival.x, rival.y)), ELFog.sight_radius(rival)])
	ELFirstAI.scripts(director)
	for name: String in rivals:
		if name == ELRestoredMissions.PATROLLER: continue
		check(rivals[name].get("strategy_order", {}).is_empty(), "%s holds his place while the Chosen One is far" % name)
	# The Chosen One comes into each rival's sight in turn.
	for name: String in ["BLevHero1", "BLevHero3", "BLevHero4", "BLevHero5"]:
		var rival: Dictionary = rivals[name]
		var spot := _spot_near(director, rival, 6)
		check(spot.x >= 0, "there is open ground six tiles from %s" % name)
		if spot.x < 0: continue
		chosen.x = spot.x
		chosen.y = spot.y
		director.grid.update_actor(chosen)
		ELFirstAI.scripts(director)
		check(int(rival.get("strategy_order", {}).get("use", -1)) == int(chosen.uid), "%s attacks the Chosen One in his sight" % name)
	# Glazzz waits until the Chosen One is three tiles inside his sight.
	var glazzz: Dictionary = rivals[ELRestoredMissions.PATROLLER]
	var sight := ELFog.sight_radius(glazzz)
	var far := _spot_near(director, glazzz, sight - 1)
	if far.x >= 0:
		chosen.x = far.x
		chosen.y = far.y
		director.grid.update_actor(chosen)
		ELFirstAI.scripts(director)
		check(int(glazzz.get("strategy_order", {}).get("use", -1)) != int(chosen.uid), "Glazzz keeps to his loop with the Chosen One %d tiles off" % (sight - 1))
	var near := _spot_near(director, glazzz, 6)
	if near.x >= 0:
		chosen.x = near.x
		chosen.y = near.y
		director.grid.update_actor(chosen)
		ELFirstAI.scripts(director)
		check(int(glazzz.get("strategy_order", {}).get("use", -1)) == int(chosen.uid), "Glazzz attacks the Chosen One six tiles off")
	# His battle figure speaks with the male voice set.
	var row := ELAdventureEncounter.combat_definition(state, glazzz, ELHeroLooks.worn(profile, glazzz))
	check(str(row.get("SndDir", "")) == "GreenHeroEggMale", "Glazzz fights with the GreenHeroEggMale voice (%s)" % row.get("SndDir", ""))
	state.close()

## An open tile about `distance` tiles from the actor (straight-line), with a
## way to it from the actor; (-1, -1) when there is none.
func _spot_near(director: ELAdventureDirector, actor: Dictionary, distance: int) -> Vector2i:
	var at := Vector2i(actor.x, actor.y)
	for turn in 32:
		var angle := TAU * turn / 32.0
		var spot := at + Vector2i(Vector2(cos(angle), sin(angle)) * distance)
		if not director.grid.contains(spot) or director.grid.passability(spot) < 0 or director.grid.land.is_point_solid(spot): continue
		if Vector2(spot).distance_to(Vector2(at)) >= distance + 0.5 or Vector2(spot).distance_to(Vector2(at)) < distance - 1.0: continue
		if director.grid.path(spot, at).is_empty() and director.grid.approach(spot, actor).is_empty(): continue
		return spot
	return Vector2i(-1, -1)

## The dale's creatures in the order of the walk from the glade:
## [[steps, creature], ...] (creatures with no way to them left out).
func _walk_order(state: ELAdventureSession, director: ELAdventureDirector) -> Array:
	var chosen := ELRestoredMissions.chosen_one(state)
	var start := Vector2i(chosen.x, chosen.y)
	var met: Array = []
	for item: Dictionary in state.objects.values():
		if item.get("type") != "monster" or not item.get("placed", true): continue
		var walk := director.grid.approach(start, item)
		if not walk.is_empty(): met.append([walk.size(), item])
	met.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return met

func _creatures(profile: ELProfile) -> void:
	var made := _dale_session(profile)
	if made.is_empty(): return
	var state: ELAdventureSession = made[0]
	var director: ELAdventureDirector = made[1]
	var chosen := ELRestoredMissions.chosen_one(state)
	var met := _walk_order(state, director)
	check(int(ELFirstRandomMap.configuration(state.map).get("revision", 0)) == 3, "a new dale is of revision 3")
	var total := 0
	for entry: Array in met: total += int(entry[1].level)
	var mean := float(total) / maxi(1, met.size())
	check(met.size() >= 60 and mean >= 6.5, "the dale's %d creatures average level %.1f (5.2 before)" % [met.size(), mean])
	check(not met.is_empty() and int(met[0][1].level) == 1 and int(met[1][1].level) == 1, "the first creatures by the glade are of the first level")
	# Near each pacing rival, the creatures are within three levels of him.
	var templates := profile.table("HeroTemplates")
	for name: String in ELRestoredMissions.DALE_PACE:
		var rival := {}
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and str(item.name) == name: rival = item
		var at := Vector2i(rival.x, rival.y)
		var near := met.filter(func(entry: Array) -> bool: return Vector2i(entry[1].x, entry[1].y).distance_to(at) <= 16.0)
		var low := 99
		var high := 0
		for entry: Array in near:
			low = mini(low, int(entry[1].level))
			high = maxi(high, int(entry[1].level))
		var level := int(templates[name].Level)
		check(not near.is_empty() and low >= level - 4 and high <= level + 1 and high >= level - 2, "creatures within 16 tiles of %s (level %d) are of levels %d-%d" % [name, level, low, high])
	# A hero who fights every creature on the way, in order, meets them
	# no further below his own level than on the second revision's line
	# (the higher creatures give more experience, so he keeps about the
	# same lead).
	_paced_gaps = _clearing_gaps(profile, met)
	# The guard relief stays off with the option on: no other player.
	director.smart_ai = true
	director.fight_neutral_monsters = true
	check(not state.balance_map_guards, "AI fights neutral monsters leaves the dale's guards as they are")
	var weakened := met.filter(func(entry: Array) -> bool: return state.combat_level(entry[1]) < int(entry[1].level) or state.combat_health(entry[1]) < int(entry[1].health))
	check(weakened.is_empty(), "no creature of the dale fights below its own level or health (%d)" % weakened.size())
	# The battle against a creature: its Monsters row of the difficulty, and
	# the difficulty's level change for the local side (Normal: none).
	var first: Dictionary = met[0][1]
	var row := ELFirstMonsters.definition(profile, str(first.name), state.difficulty)
	var levels := ELAdventureEncounter.first_levels(state, int(chosen.uid), int(first.uid))
	check(int(first.level) == int(row.Level) and int(first.health) == int(row.Health) and first.cards == ELFirstMonsters.book(row).cards and levels == [int(chosen.level), int(first.level)],
		"a creature fights with its Monsters row (level, health, deck) and no level change on Normal")
	var mismatched := met.filter(func(entry: Array) -> bool:
		var own := ELFirstMonsters.definition(profile, str(entry[1].name), state.difficulty)
		return own.is_empty() or int(entry[1].level) != int(own.Level) or int(entry[1].health) != int(own.Health) or entry[1].cards != ELFirstMonsters.book(own).cards)
	check(met.size() >= 60 and mismatched.is_empty(), "all %d creatures of the dale carry their Monsters rows (%d differ)" % [met.size(), mismatched.size()])
	state.difficulty = 0
	check(ELAdventureEncounter.first_levels(state, int(chosen.uid), int(first.uid)) == [int(chosen.level) + 2, maxi(1, int(first.level) - 1)], "on the easiest difficulty the hero fights two levels up and the creature one down")
	state.difficulty = 4
	check(ELAdventureEncounter.first_levels(state, int(chosen.uid), int(first.uid)) == [int(chosen.level), int(first.level) + 2], "on the hardest difficulty the creature fights two levels up")
	state.close()
	# A save of revision 2 regenerates the creatures it began with.
	var entry := {}
	for found: Dictionary in ELSingleScenario.catalog(profile):
		if found.get("restored", "") == ELRestoredMissions.EVIL_DALE: entry = found
	var older: Dictionary = entry.random_map.duplicate(true)
	older["revision"] = 2
	var map := ELFirstRandomMap.new().generate(profile, older)
	var again := ELFirstRandomMap.new().generate(profile, older)
	check(map != null and again != null and ELFirstRandomMap.content_hash(map) == ELFirstRandomMap.content_hash(again), "a revision 2 dale still generates, the same every time")
	if map == null: return
	var old_state := ELAdventureSession.new()
	old_state.start(map, 2, ELFirstRandomMap.seed_for_config(older), "", 1, false, true)
	var high := 0
	for item: Dictionary in old_state.objects.values():
		if item.get("type") == "monster" and item.get("placed", true): high = maxi(high, int(item.level))
	check(high <= 10 and ELRestoredMissions.scenario_of_id(map.id) == ELRestoredMissions.EVIL_DALE, "it keeps its own creatures (highest level %d) and is still Evil Dale" % high)
	var old_director := ELAdventureDirector.new()
	old_director.build(old_state)
	var old_gaps := _clearing_gaps(profile, _walk_order(old_state, old_director))
	check(_paced_gaps <= old_gaps, "a hero clearing the dale meets creatures %.1f levels below him on average (%.1f on revision 2)" % [_paced_gaps, old_gaps])
	old_state.close()

var _paced_gaps := 0.0

## How many levels below a hero who beats each in order the creatures are
## on average.
func _clearing_gaps(profile: ELProfile, met: Array) -> float:
	var experience := 0
	var gaps := 0
	for entry: Array in met:
		gaps += ELHeroProgression.level_for(profile, experience) - int(entry[1].level)
		experience += ELHeroProgression.battle_reward(profile, int(entry[1].level))
	return float(gaps) / maxi(1, met.size())

## A neutral hero named like a rival guards nothing outside the dale.
func _elsewhere(profile: ELProfile) -> void:
	var map := ELFirstRandomMap.new().generate(profile, ELRestoredMissions.recipe(ELRestoredMissions.SAVAGE_DESERT))
	if map == null:
		check(false, "Savage Desert generates")
		return
	var state := ELAdventureSession.new()
	state.start(map, 2, 1, "", 1, false, true)
	var stranger := {"type": "hero", "owner": 0, "alive": true, "visible": true, "placed": true, "name": "BLevHero1"}
	check(not ELInterception.dale_rival(state, stranger) and not ELInterception.guards_in(state, stranger), "outside the dale a BLevHero hero guards nothing")
	state.close()
