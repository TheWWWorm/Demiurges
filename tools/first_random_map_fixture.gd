extends RefCounted
## Hand-written, synthetic content for first_random_map_check.gd. No original
## game records, models, textures, maps or executable content are included.
## The table schemas match the engine's loaders, including non-square blocking
## footprints and five difficulty variants of each neutral creature.

const COLORS := ["Green", "Blue", "Red", "Black"]
const CREATURES := ["TIWK", "KBWR", "GBIN", "BRMC"]
const ADVANCED_CREATURES := ["TIQN", "KBEL", "GBBR", "IRMC"]
const SORCERIES := ["GEYS", "CLIG", "ZAPP", "QKFX"]
const ENCHANTMENTS := ["MGHT", "FRGS", "FURY", "SPWR"]

static func profile() -> ELProfile:
	var result := ELProfile.new()
	result.id = "el1"
	result.title = "Synthetic first-game validation content"
	result.terrain_tiles = tiles()
	for table: String in ["HeroTemplates", "CombatDecks", "CombatSpells", "CombatCreatures", "Buildings", "ManaNodes", "ResourceMine", "NewBuildings", "ResourceCut", "Monsters", "TerrObj", "HeroesStats", "HeroesSkills", "HeroesSpecs", "GlobalSpells", "GlobalSpellCut", "AdditionalBuildings", "Shapes"]:
		result.tables[table] = {}
	for index in COLORS.size():
		var color: String = COLORS[index]
		var hero: String = ELCatalog.HEROES[color]
		var deck: Array[String] = []
		for slot in 15: deck.append(CREATURES[index] + "(5)")
		result.tables.CombatDecks["Fixture" + color] = {"Spells": deck}
		result.tables.HeroTemplates[hero] = {"Name": hero, "Color": color, "Quest": "No", "Level": 1,
			"Sight": 12, "BaseHealth": 7, "HealthIncrease": 3, "StartDeck": "Fixture" + color,
			"Specialization": "NONE", "AdvMod": "fixture_hero", "AdvTex1": "fixture", "TileSize": [1, 1]}
		for kind in 3:
			var code: String = [CREATURES, SORCERIES, ENCHANTMENTS][kind][index]
			result.tables.CombatSpells[code] = {"Color": color, "Class": ["Creature", "Sorcery", "Enchantment"][kind],
				"Rarity": "Cantrip" if kind == 0 else "Common", "IsArtifact": "False", "Mana": 1, "Cost": 1,
				"CostRoot": 1, "Creature": CREATURES[index], "Target": "Any"}
		result.tables.CombatCreatures[CREATURES[index]] = {"Color": color, "Power": 1, "Toughness": 2, "Abilities": [], "Flags": []}
		var upgrade: String = ADVANCED_CREATURES[index]
		result.tables.CombatSpells[upgrade] = {"Color": color, "Class": "Creature", "Rarity": "Common",
			"IsArtifact": "False", "Mana": 2, "Cost": 2, "CostRoot": 2, "Creature": upgrade}
		result.tables.CombatCreatures[upgrade] = {"Color": color, "Power": 2, "Toughness": 3, "Abilities": [], "Flags": []}
		for suffix: String in ["WR", "CH", "HR"]:
			var code: String = {"Green": "SV", "Blue": "SK", "Red": "SC", "Black": "SS"}[color] + suffix
			result.tables.GlobalSpells[code] = {"Color": color, "Name": code, "CostMana": 50, "CostM": 1}
		for level in 3:
			result.tables.Buildings["Tower%s%d" % [color, level]] = {"Name": "MainTower", "MagicColor": color,
				"Level": level, "Model": "fixture_castle", "TextureName": "fixture", "TileSize": [4, 5]}
		result.tables.ManaNodes["ManaNode." + color] = {"Name": "ManaNode", "MagicColor": color,
			"Model": "fixture_mana", "TextureName": "fixture", "TileSize": [2, 2]}
		for type: String in ["IngredientShop", "SpellShop", "CreatureShop"]:
			for level in 3:
				var row := {"Name": "Fixture%s%s" % [color, type], "MagicColor": color, "Color": color,
					"Type": type, "Level": level, "Rarity": "Common", "Model": "fixture_shop",
					"TextureName": "fixture", "TileSize": [3, 2]}
				for faction: String in COLORS: row[faction + "UpgradeCost"] = ["Root(2)"]
				result.tables.NewBuildings[row.Name + str(level)] = row
	for kind: String in ELResources.ORIGINAL:
		for level in 3:
			result.tables.ResourceMine[kind + str(level)] = {"Name": "Fixture" + kind + "Mine", "Level": level,
				"Production": [kind + "(2)"], "UpgradeCost": ["Root(3)"], "Model": "fixture_mine",
				"TextureName": "fixture", "TileSize": [2, 3]}
		result.tables.ResourceCut[kind] = {"Name": kind, "Type": kind, "Resource": kind,
			"Model": "fixture_pile", "TextureName": "fixture", "TileSize": [1, 1]}
	for level in [1, 3, 6, 9]:
		for difficulty in 5:
			var name := "FixtureGuard%d" % level
			result.tables.Monsters["%s.%d" % [name, difficulty]] = {"Name": name, "DifficultyLevel": difficulty,
				"Level": level, "Health": 10 + level, "Deck": ["GBIN(5)", "ZAPP(5)"],
				"Specialization": "NONE", "AdvMod": "fixture_guard", "AdvTex1": "fixture", "Creature": "GBIN",
				"Loot100": ["Root(5)"], "TileSize": [1, 1]}
	result.tables.TerrObj["FixtureTree"] = {"Name": "FixtureTree", "Model": "fixture_tree", "Texture": "fixture", "TileSize": [2, 2]}
	result.tables.TerrObj["FixtureRock"] = {"Name": "FixtureRock", "Model": "fixture_rock", "Texture": "fixture", "TileSize": [3, 2]}
	result.tables.GlobalSpellCut["FullSpell"] = {"Name": "FullSpell", "Model": "fixture_scroll", "Texture": "fixture", "TileSize": [1, 1]}
	for code: String in ["DFRL", "WRRL"]:
		result.tables.GlobalSpells[code] = {"Color": "Colorless", "Name": code, "CostMana": 25}
	for statistic: String in ["ExpNeeded", "ExpForNPC", "ManaUpkeep"]:
		var row := {}
		for level in range(1, 21):
			row["Level%d" % level] = (level - 1) * 100 if statistic == "ExpNeeded" else (level * 10 if statistic == "ExpForNPC" else 1)
		result.tables.HeroesStats[statistic] = row
	return result

static func tiles() -> ELTileSet:
	var result := ELTileSet.new()
	result.side = 12
	var base := PackedByteArray()
	base.resize(result.side * result.side * 3)
	base.fill(100)
	var mask := base.duplicate()
	mask.fill(255)
	result.pixels = [base, mask]
	for kind in 32:
		result.types[kind] = {"priority": kind, "movement": -1 if kind in [16, 17, 18] else 1,
			"full": [{"ids": [0], "period": 0}],
			"masks": [[{"ids": [1], "period": 0}], [{"ids": [1], "period": 0}], [{"ids": [1], "period": 0}]],
			"overlays": [[], [], []]}
	return result
