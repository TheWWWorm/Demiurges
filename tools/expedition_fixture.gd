extends RefCounted
## Deliberately synthetic Expedition fixtures. The real map parser, roster
## builder, run rules and duel model are exercised without original game files.
## These small decks and hero numbers are not an installed-game balance test.

const DraftCheck := preload("arena_draft_check.gd")
const ROOT := "user://expedition_expansion_check"

static func profile_at(folder := ROOT) -> ELProfile:
	var profile := DraftCheck.synthetic_profile()
	profile.title = "Expedition synthetic test profile"
	profile.tables.DuelPresets = {}
	profile.tables.Shapes = {}
	profile.tables.HeroesSpecialization = {}
	profile.tables.Terrain = {}
	profile.tables.CombatScenes = {}
	for code: String in ELExpeditionRun.CAMP_STUDY.values():
		var faction := ""
		for colour: String in ELExpeditionRun.CAMP_STUDY:
			if ELExpeditionRun.CAMP_STUDY[colour] == code: faction = colour
		if profile.tables.CombatSpells.has(code): profile.tables.CombatSpells[code].Color = faction
	for code: String in ["PRVD", "SUPR", "HEAL", "CHNL", "CNTR", "SPPW"]:
		for rank in 3:
			profile.tables.HeroesSkills[code + str(rank + 1)] = {"Code": code, "Level": rank + 1, "Name": code,
				"Description": "%s synthetic rank %d" % [code, rank + 1], "Duel": "True"}
	for faction: String in ELDuelPresets.RACES:
		var pool: Array[String] = []
		for code: String in profile.tables.CombatSpells:
			if profile.tables.CombatSpells[code].get("Color") == faction and not ELCatalog.rule(profile, code).is_empty(): pool.append(code)
		pool.sort()
		var book: Array[String] = []
		for index in 16: book.append(pool[index % mini(8, pool.size())])
		var name := "ExpeditionFixture" + faction
		profile.tables.CombatDecks[name] = {"Spells": book}
		profile.tables.DuelPresets[name] = {"InGame": "True", "MagicColor": faction,
			"ResourceLevel": 1, "HeroLevel": 1, "Specialization": "NONE", "Skills": ["PRVD(1)"], "Deck": name}
		profile.tables.Shapes["Fixture" + faction] = {"Color": faction}
		profile.tables.HeroTemplates[ELCatalog.default_hero(profile, faction)] = {"BaseHealth": 7, "HealthIncrease": 3, "Level": 1, "Skills": []}
		for index in pool.size():
			profile.tables.CombatSpells[pool[index]].Rarity = ["Common", "Common", "Rare", "Unique"][index % 4]
	for entry: Array in [["RingOfHealing", "RDHL"], ["RodOfLightning", "RDLG"]]:
		profile.tables.CombatSpells[entry[1]] = {"Class": "Sorcery", "Color": "White", "Cost": 0,
			"Rarity": "Unique", "Name": entry[0], "IsArtifact": "True", "Use": "+"}
		profile.tables.Artefacts[entry[0]] = {"SpellType": entry[1], "MaxCharges": 3, "FirstUsage": 1,
			"UsageGap": 1, "Name": entry[0]}
	var maps := {}
	for value: Variant in (load("res://src/expedition/encounters.gd") as Script).get_script_constant_map().values():
		_collect_sources(value, maps)
	DirAccess.make_dir_recursive_absolute(folder)
	for map_id: String in maps:
		var mobs := ""
		var index := 0
		for mob_name: String in maps[map_id]:
			var faction: String = ELDuelPresets.RACES[index % 4]
			var book: Array = profile.tables.CombatDecks["ExpeditionFixture" + faction].Spells
			var spells := ""
			for card: String in book: spells += '<spell code="%s"/>' % card
			mobs += '<mdm_mob Name="%s" DifLvl="1" shape="Fixture%s" ElkName="%s" IsHero="0" Spec="NONE"><deck>%s</deck></mdm_mob>' % [mob_name.xml_escape(true), faction, mob_name.xml_escape(true), spells]
			index += 1
		var xml := '<scenario><map><size x="2" y="2"/><tiles><row>000000</row><row>000000</row><row>000000</row></tiles><roads><row>0000</row><row>0000</row></roads><creeks><row>0000</row><row>0000</row></creeks></map><mdm_mobs>%s</mdm_mobs></scenario>' % mobs
		var path := folder.path_join(map_id + ".map")
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: return null
		file.store_string(xml)
		file.close()
		profile._files["maps/" + map_id.to_lower() + ".map"] = path
	return profile

static func _collect_sources(value: Variant, maps: Dictionary) -> void:
	if value is not Array: return
	if value.size() == 2 and value[0] is String and value[1] is String and value[0].begins_with("e2mission"):
		if not maps.has(value[0]): maps[value[0]] = {}
		maps[value[0]][value[1]] = true
		return
	for child: Variant in value: _collect_sources(child, maps)

static func clean(folder := ROOT) -> void:
	for name: String in DirAccess.get_files_at(folder):
		if name.begins_with("e2mission") and name.ends_with(".map"): DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
