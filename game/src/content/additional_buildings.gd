class_name ELAdditionalBuildings
extends RefCounted
## First-game map buildings a hero visits from an adjacent tile during the
## night's use stage. Visiting costs nothing but the walk. Each type keeps one
## of four kinds of state:
## - a set of heroes that already visited (learning buildings forever, springs
##   until the weekly reset);
## - one used flag shared by every player (gnomes reset weekly, wagons vanish);
## - an owner (shrine and citadels give their owner a lasting bonus);
## - a guest (the training camp holds one hero off the map);
## - an opened flag (runestone barriers);
## - nothing else.
## Only the visiting hero's human owner sees the building's message.
const VERSION := 1
const VISITED := ["Teacher", "Magister", "Master", "SpringOfStrength", "SpringOfDexterity"]
const WEEKLY_VISITED := ["SpringOfStrength", "SpringOfDexterity"]
const WEEKLY_FLAG := ["GnomeMerchant", "GnomeAlchemist", "GnomeTinkerer"]
const ONE_TIME := ["TraderWagon", "MageWagon", "Prison", "AltarOfWar", "WardingStone"]
## Holds one hero off the map, who gains experience every day until leaving.
const CAMP := "TrainingCamp"
const CAMP_EXPERIENCE := 50
## Barriers open for a hero carrying the stone's key; a key containing "*"
## toggles the barrier open and closed again.
const RUNESTONES := ["Runestone1", "Runestone2"]
## Each destroyed Altar of War replaces the roaming Konung with the next weaker template.
const KONUNG := {"Konung of Fire IV": "Konung of Fire III", "Konung of Fire III": "Konung of Fire II", "Konung of Fire II": "Konung of Fire I"}
const OWNED := ["ShrineMagic", "HealersCitadel", "WanderersCitadel"]
## Lairs hold one neutral creature of these level ranges, restocked weekly.
const DUNGEONS := {"Dungeon1": [2, 4], "Dungeon2": [5, 7], "Dungeon3": [8, 10]}
const DUNGEON_ARENA := "Dungeon.001"
const MAGISTER_EXPERIENCE := 100
const WAGON_RUNES := 3
const ALCHEMIST_RUNES := 1
const WEEK := 7
## A Seer (Lake) shows its visitor's owner every crystal ball (ReflectingBowl)
## whose parameter equals its own; the owner then sees around those balls.
const LAKE := "Lake"
const BOWL := "ReflectingBowl"

static func supported(item: Dictionary) -> bool:
	var name := str(item.get("name", ""))
	return item.get("group") == "additional_buildings" and (name in VISITED + WEEKLY_FLAG + ONE_TIME + OWNED + RUNESTONES or name in [CAMP, LAKE] or DUNGEONS.has(name))

static func definition(profile: ELProfile, item: Dictionary) -> Dictionary:
	return profile.table("AdditionalBuildings").get(str(item.get("name", "")), {})

static func title(profile: ELProfile, item: Dictionary) -> String:
	return profile.text(str(definition(profile, item).get("ELKName", item.get("name", ""))))

static func initialize(profile: ELProfile, item: Dictionary) -> void:
	item.type = String(item.name).to_lower()
	if not supported(item): return
	item.addition_version = VERSION
	item.visited = []
	item.used = false
	# Shipped maps author every shrine and citadel without an owner.
	item.owner = -1
	item.monster = -1
	item.guest = -1
	item.guest_entry = []
	item.opened = false

static func restore(profile: ELProfile, item: Dictionary) -> bool:
	item.type = String(item.name).to_lower()
	if not supported(item): return true
	if definition(profile, item).is_empty(): return false
	if not item.has("addition_version"):
		# Earlier saves stored these buildings as inert objects.
		var alive: bool = item.alive
		initialize(profile, item)
		item.alive = alive
	if not ELLuaSave._integer(item.addition_version, VERSION, VERSION) or not item.get("used") is bool or not item.get("visited") is Array or item.visited.size() > 100000: return false
	if not ELLuaSave._integer(item.get("owner"), -1, 32): return false
	if item.owner >= 0 and item.name not in OWNED: return false
	var seen := {}
	for id: Variant in item.visited:
		if not ELLuaSave._integer(id, 0, 0x7fffffff) or seen.has(int(id)): return false
		seen[int(id)] = true
	if item.name not in VISITED and not item.visited.is_empty(): return false
	if item.used and item.name not in WEEKLY_FLAG + ONE_TIME: return false
	# A spent wagon is removed from the map.
	if item.name in ONE_TIME and item.used == (item.alive and item.visible): return false
	item.visited = seen.keys()
	if not item.has("monster"): item.monster = -1
	if not ELLuaSave._integer(item.monster, -1, 0x7fffffff) or (item.monster >= 0 and not DUNGEONS.has(item.name)): return false
	item.monster = int(item.monster)
	if not item.has("guest"): item.guest = -1
	if not item.has("guest_entry"): item.guest_entry = []
	if not item.has("opened"): item.opened = false
	if not ELLuaSave._integer(item.guest, -1, 0x7fffffff) or not item.guest_entry is Array or not item.opened is bool: return false
	item.guest = int(item.guest)
	if item.guest >= 0 and (item.name != CAMP or item.guest_entry.size() != 2 or not ELLuaSave._integer(item.guest_entry[0], 0, 0x7fff) or not ELLuaSave._integer(item.guest_entry[1], 0, 0x7fff)): return false
	if item.guest < 0 and not item.guest_entry.is_empty(): return false
	item.guest_entry = item.guest_entry.map(func(value: Variant): return int(value))
	if item.opened and item.name not in RUNESTONES: return false
	return true

## Barrier key from the authored parameter; empty when none is authored.
static func barrier_key(item: Dictionary) -> String:
	return str(ELXml.value(item.get("node", {}), "params")).strip_edges()

## A lair and its creature name each other; a held creature stays off the map.
static func valid_links(objects: Dictionary) -> bool:
	for item: Dictionary in objects.values():
		if item.get("addition_version") == VERSION and int(item.get("monster", -1)) >= 0:
			var monster: Dictionary = objects.get(int(item.monster), {})
			if monster.get("type") != "monster" or int(monster.get("dungeon", -1)) != int(item.uid) or monster.get("visible", true): return false
		elif item.get("addition_version") == VERSION and int(item.get("guest", -1)) >= 0:
			var guest: Dictionary = objects.get(int(item.guest), {})
			if guest.get("type") != "hero" or int(guest.get("camp", -1)) != int(item.uid) or guest.get("placed", true): return false
		elif item.get("type") == "hero" and item.has("camp"):
			if not ELLuaSave._integer(item.camp, -1, 0x7fffffff) or not item.get("placed", true) is bool: return false
			item.camp = int(item.camp)
			if item.camp >= 0 and (int(objects.get(item.camp, {}).get("guest", -1)) != int(item.uid) or item.placed): return false
			if item.camp < 0 and not item.placed: return false
		elif item.has("dungeon"):
			if not ELLuaSave._integer(item.dungeon, 0, 0x7fffffff) or int(objects.get(int(item.dungeon), {}).get("monster", -1)) != int(item.uid): return false
			item.dungeon = int(item.dungeon)
	return true

static func restore_hero(hero: Dictionary) -> bool:
	if not hero.has("temp_buffs"): hero.temp_buffs = []
	var bonus: Variant = hero.get("citadel_bonus", [0, 0])
	if not bonus is Array or bonus.size() != 2 or not ELLuaSave._integer(bonus[0], 0, 100000) or not ELLuaSave._integer(bonus[1], 0, 100000): return false
	if not hero.temp_buffs is Array or hero.temp_buffs.size() > 1000: return false
	for index in hero.temp_buffs.size():
		var buff: Variant = hero.temp_buffs[index]
		if not buff is Array or buff.size() != 2 or not ELLuaSave._integer(buff[0], 0, 100000) or not ELLuaSave._integer(buff[1], 0, 100000): return false
		hero.temp_buffs[index] = [int(buff[0]), int(buff[1])]
	return true

## Temporary spring bonuses as [health, movement].
static func buffs(hero: Dictionary) -> Vector2i:
	var total := Vector2i.ZERO
	for buff: Array in hero.get("temp_buffs", []): total += Vector2i(int(buff[0]), int(buff[1]))
	return total

static func owned(state: ELAdventureSession, player: int, name: String) -> int:
	var count := 0
	for item: Dictionary in state.objects.values():
		if item.get("group") == "additional_buildings" and item.get("name") == name and item.get("addition_version") == VERSION and int(item.owner) == player and player >= 0: count += 1
	return count

## Citadel counts belong to the player; every hero of that player carries the
## current counts so health and movement can be recalculated locally.
static func refresh_heroes(state: ELAdventureSession, player := -1) -> void:
	var counts := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") != "hero" or (player >= 0 and int(item.owner) != player): continue
		var owner := int(item.owner)
		if not counts.has(owner): counts[owner] = [owned(state, owner, "HealersCitadel"), owned(state, owner, "WanderersCitadel")]
		recalculate(state.map.profile, item, counts[owner])

## Checks each player's saved crystal-ball list: distinct, existing bowls.
static func restore_scry(state: ELAdventureSession) -> String:
	for player: int in state.players:
		var raw: Variant = state.players[player].get("scry")
		if raw == null: continue
		if not raw is Array or raw.size() > 1000: return "Invalid saved crystal balls."
		var clean: Array = []
		for id: Variant in raw:
			if not ELLuaSave._integer(id, 0, 0x7fffffff) or clean.has(int(id)) or state.object(int(id)).get("name") != BOWL: return "Invalid saved crystal balls."
			clean.append(int(id))
		state.players[player].scry = clean
	return ""

## After loading, citadel counts are derived from building ownership again.
static func sync_heroes(state: ELAdventureSession) -> void:
	for hero: Dictionary in state.objects.values():
		if hero.get("type") != "hero": continue
		var counts := [owned(state, int(hero.owner), "HealersCitadel"), owned(state, int(hero.owner), "WanderersCitadel")]
		var saved: Variant = hero.get("citadel_bonus", [0, 0])
		var same: bool = saved is Array and saved.size() == 2 and int(saved[0]) == counts[0] and int(saved[1]) == counts[1]
		hero.citadel_bonus = counts
		if not same: recalculate(state.map.profile, hero)

static func recalculate(profile: ELProfile, hero: Dictionary, citadels: Array = []) -> void:
	if not citadels.is_empty(): hero.citadel_bonus = citadels.duplicate()
	ELHeroProgression.recalculate_health(hero)
	if profile.id == "el1" and hero.has("strategy_version"): ELStrategy.recalculate(hero)

## Ether income bonus: a quarter of the base income per shrine, rounded down.
static func shrine_income(base: int, shrines: int) -> int:
	return base + int(floor(base * shrines / 4.0))

static func visit_problem(state: ELAdventureSession, hero: Dictionary, item: Dictionary) -> String:
	if hero.get("type") != "hero" or not hero.get("alive", false) or not state.players.has(int(hero.get("owner", -1))): return "This hero cannot use the building."
	if not supported(item) or not item.get("alive", false) or not item.get("visible", false) or not item.get("enabled", false): return "This building is unavailable."
	if item.name in VISITED and item.visited.has(int(hero.uid)):
		return "This hero has already visited this place this week." if item.name in WEEKLY_VISITED else "This hero has already visited this place."
	if item.name in WEEKLY_FLAG and item.used: return "This building has already been used this week."
	if item.name in ONE_TIME and item.used: return "This building is unavailable."
	if item.name == "Prison" and not state.map.profile.table("HeroTemplates").has(prisoner(item)): return "The cage is empty."
	if item.name in OWNED and int(item.owner) == int(hero.owner): return "This building is already yours."
	if DUNGEONS.has(item.name) and not state.object(item.monster).get("alive", false): return "Nobody lives here now."
	if item.name == CAMP:
		if int(item.guest) >= 0: return "Another hero is training here."
		if ELGlobalSpells.held(hero): return "This hero cannot use the building."
	if item.name in RUNESTONES:
		var needed := barrier_key(item)
		var held: bool = hero.get("keys", []).has(needed)
		if not needed.contains("*") and item.opened: return "This barrier is already open."
		if not held: return "This hero has no key to this barrier."
	return ""

## The director calls this from the use stage once the hero stands beside the
## building. Returns the shown message, or an empty dictionary when refused.
static func visit(director: ELAdventureDirector, hero: Dictionary, item: Dictionary) -> Dictionary:
	var state := director.state
	var local: bool = int(hero.get("owner", -1)) == state.current_player
	var problem := visit_problem(state, hero, item)
	if problem.is_empty() and not ELStrategy.adjacent(director, hero, item): problem = "Move next to this building first."
	if not problem.is_empty():
		if local: director.presentation.emit({"kind": "notice", "text": problem})
		return {}
	if DUNGEONS.has(item.name): return precombat(director, hero, item)
	var message := activate(state, hero, item)
	state.event.emit({"kind": "building_used", "id": item.uid, "hero": hero.uid, "player": hero.owner, "message": message.key})
	if local:
		director.notice = message.text
		director.presentation.emit({"kind": "building_message", "hero": hero.uid, "building": item.uid, "title": title(state.map.profile, item),
			"text": message.text, "resources": message.get("resources", []), "skill": message.get("skill", ""), "key": message.key})
	return message

## Lair visit, resolved in the movement pass once the hero stands beside it:
## the held creature is queued for the combat phase and the order ends. A won
## battle empties the lair until the next weekly restock.
static func precombat(director: ELAdventureDirector, hero: Dictionary, item: Dictionary) -> Dictionary:
	var state := director.state
	if not visit_problem(state, hero, item).is_empty() or not ELStrategy.adjacent(director, hero, item) or director.strategy.get("phase") != "movement": return {}
	var monster := state.object(item.monster)
	ELStrategy.queue_combat(director, int(hero.uid), int(monster.uid))
	hero.strategy_order = {}
	var key := str(definition(state.map.profile, item).get("Message1", "BldngMsg1" + item.name))
	var message := {"key": key, "text": format(state.map.profile, key, [str(monster.get("title", monster.name))])}
	state.event.emit({"kind": "building_used", "id": item.uid, "hero": hero.uid, "player": hero.owner, "message": key})
	if int(hero.owner) == state.current_player:
		director.notice = message.text
		director.presentation.emit({"kind": "building_message", "hero": hero.uid, "building": item.uid, "title": title(state.map.profile, item), "text": message.text, "resources": [], "skill": "", "key": key, "monster": monster.uid})
	return message

## Weekly restock: a uniform draw over every neutral creature whose template
## at the current difficulty has a level inside the lair's range.
static func restock(state: ELAdventureSession, item: Dictionary) -> int:
	var levels: Array = DUNGEONS[item.name]
	var pool: Array[String] = []
	var rows: Dictionary = state.map.profile.table("Monsters")
	# One name per creature, in registry order (its difficulty-3 row).
	for row: Dictionary in rows.values():
		if int(row.get("DifficultyLevel", -1)) != 3: continue
		var template := ELFirstMonsters.definition(state.map.profile, str(row.Name), state.difficulty)
		if not template.is_empty() and int(template.Level) >= int(levels[0]) and int(template.Level) <= int(levels[1]): pool.append(str(row.Name))
	if pool.is_empty(): return -1
	var name := pool[_random(state) % pool.size()]
	var id := state._next_object
	state._next_object += 1
	var monster := {"uid": id, "permanent_id": id, "source_index": -1, "id": id, "name": name, "owner": 0, "group": "np_heroes", "x": -1, "y": -1, "rotation": 0, "type": "monster",
		"alive": true, "visible": false, "enabled": true, "placed": false, "shape": "", "level": 1, "health": 10, "base_ap": 0, "ap": 0, "experience": 0,
		"cards": [], "spell_stock": {}, "stock_separate": true, "skills": {}, "inventory": [], "orders": [], "node": {}, "dungeon": int(item.uid)}
	if not ELFirstMonsters.initialize(state.map.profile, monster, state.difficulty): return -1
	ELStrategy.initialize(state.map.profile, monster)
	state.objects[id] = monster
	state._mob_ids.append(id)
	item.monster = id
	state.event.emit({"kind": "object_created", "id": id})
	return id

static func activate(state: ELAdventureSession, hero: Dictionary, item: Dictionary) -> Dictionary:
	var profile := state.map.profile
	var name: String = item.name
	# The visit is recorded before the effect, so a refused Master lesson still
	# uses up this hero's visit.
	if name in VISITED: item.visited.append(int(hero.uid))
	var row := definition(profile, item)
	var key := str(row.get("Message1", "BldngMsg1" + name))
	var values: Array = []
	var result := {}
	match name:
		"TraderWagon", "GnomeMerchant":
			var draws: Array = []
			for draw in (3 if name == "TraderWagon" else 1):
				var kind: String = ELResources.ORIGINAL[_random(state) % 7]
				var amount := 6 * (_random(state) % 6 + 1)
				var merged := false
				for entry: Array in draws:
					if entry[0] == kind:
						entry[1] += amount
						merged = true
				if not merged: draws.append([kind, amount])
			var reward := ELResources.empty(profile.id)
			for entry: Array in draws: reward[entry[0]] += entry[1]
			state.change_resources(int(hero.owner), reward)
			result.resources = draws
		"MageWagon", "GnomeAlchemist":
			add_runes(hero, WAGON_RUNES if name == "MageWagon" else ALCHEMIST_RUNES)
			state.event.emit({"kind": "inventory_changed", "id": hero.uid})
		"Teacher", "Magister":
			var level := int(hero.level)
			var amount := MAGISTER_EXPERIENCE if name == "Magister" else (ELHeroProgression.threshold(profile, level + 1) / 2 if level < ELHeroProgression.MAX_LEVEL else 0)
			# The message shows the amount before the Learning bonus.
			values.append(amount)
			if level < ELHeroProgression.MAX_LEVEL: state.add_experience(int(hero.uid), amount)
		"Master":
			var code := str(ELXml.value(item.node, "params")).strip_edges()
			var pool := ELHeroSkills.available(profile)
			if code.is_empty() or not pool.has(code): code = pool[_random(state) % pool.size()] if not pool.is_empty() else ""
			result.skill = code
			var skills: Dictionary = hero.skills
			if skills.has(code) and int(skills[code]) >= ELHeroSkills.MAX_RANK: key = str(row.get("Message2", "BldngMsg2Master"))
			elif not skills.has(code) and skills.size() >= ELHeroSkills.MAX_SKILLS: key = str(row.get("Message3", "BldngMsg3Master"))
			elif not code.is_empty():
				skills[code] = int(skills.get(code, -1)) + 1
				_refresh_offers(profile, hero)
				recalculate(profile, hero)
				state.event.emit({"kind": "skill_learned", "id": hero.uid, "code": code, "rank": skills[code]})
		"SpringOfStrength", "SpringOfDexterity":
			var strength := name == "SpringOfStrength"
			if not hero.has("temp_buffs"): hero.temp_buffs = []
			var amount := (int(hero.health) if strength else int(hero.get("strategy_capacity", 0))) >> 2
			hero.temp_buffs.append([amount, 0] if strength else [0, amount])
			recalculate(profile, hero)
			values.append(amount)
		"Prison":
			var freed := spawn_hero(state, prisoner(item), int(hero.owner), int(item.x), int(item.y))
			values.append(str(state.object(freed).get("title", prisoner(item))))
			result.freed = freed
		"AltarOfWar":
			weaken_konung(state)
		"GnomeTinkerer":
			# The original shows its recharge message but changes no artifact.
			pass
		"TrainingCamp":
			# The hero leaves the map; the tile it stood on is kept for leaving.
			item.guest = int(hero.uid)
			item.guest_entry = [int(hero.x), int(hero.y)]
			hero.camp = int(item.uid)
			hero.placed = false
			hero.strategy_order = {}
			hero.orders.clear()
			state.event.emit({"kind": "camp_entered", "id": item.uid, "hero": hero.uid})
			state.event.emit({"kind": "object_changed", "id": hero.uid})
		"Runestone1", "Runestone2":
			# Opening needs the key; a "*" key closes an open barrier again.
			if item.opened:
				key = str(row.get("Message2", "BldngMsg2" + name))
				item.opened = false
			else: item.opened = true
			state.event.emit({"kind": "barrier_changed", "id": item.uid, "opened": item.opened})
			state.event.emit({"kind": "object_changed", "id": item.uid})
		"WardingStone":
			if not hero.has("keys"): hero.keys = []
			if not hero.keys.has(barrier_key(item)): hero.keys.append(barrier_key(item))
		"ShrineMagic", "HealersCitadel", "WanderersCitadel":
			var previous := int(item.owner)
			item.owner = int(hero.owner)
			if previous >= 0: refresh_heroes(state, previous)
			refresh_heroes(state, int(hero.owner))
			state.event.emit({"kind": "building_captured", "id": item.uid, "player": item.owner, "previous": previous})
			state.event.emit({"kind": "object_changed", "id": item.uid})
		LAKE:
			# Always usable; the message shows even when nothing new is added.
			var scry: Array = state.players[int(hero.owner)].get("scry", [])
			var own := barrier_key(item)
			var ids: Array = state.objects.keys()
			ids.sort()
			for id: int in ids:
				var bowl := state.object(id)
				if bowl.get("group") == "additional_buildings" and bowl.get("name") == BOWL and barrier_key(bowl) == own and not scry.has(id): scry.append(id)
			state.players[int(hero.owner)].scry = scry
	if name in WEEKLY_FLAG: item.used = true
	if name in ONE_TIME:
		item.used = true
		item.alive = false
		item.visible = false
		item.enabled = false
		state.event.emit({"kind": "object_killed", "id": item.uid})
	result.key = key
	result.text = format(profile, key, values, result.get("resources", []))
	# Key messages name the key: «message ("key")».
	if (name in RUNESTONES or name == "WardingStone") and not barrier_key(item).is_empty(): result.text += ' ("%s")' % profile.text(barrier_key(item))
	return result

## A fallen hero's keys go back to the warding stones they came from.
static func drop_keys(state: ELAdventureSession, hero: Dictionary) -> void:
	for key: Variant in hero.get("keys", []):
		for item: Dictionary in state.objects.values():
			if item.get("name") == "WardingStone" and item.get("used", false) and barrier_key(item) == str(key):
				item.merge({"used": false, "alive": true, "visible": true, "enabled": true}, true)
				state.event.emit({"kind": "object_created", "id": item.uid})
				break
	hero.keys = []

## The leave control puts the guest back on the tile it entered from.
static func leave_camp(state: ELAdventureSession, hero_id: int) -> bool:
	var hero := state.object(hero_id)
	var camp := state.object(hero.get("camp", -1))
	if camp.get("name") != CAMP or int(camp.get("guest", -1)) != hero_id or camp.guest_entry.size() != 2: return false
	hero.x = int(camp.guest_entry[0])
	hero.y = int(camp.guest_entry[1])
	release_camp(state, hero)
	hero.placed = true
	state.event.emit({"kind": "camp_left", "id": camp.uid, "hero": hero_id})
	state.event.emit({"kind": "object_changed", "id": hero_id})
	return true

static func release_camp(state: ELAdventureSession, hero: Dictionary) -> void:
	var camp := state.object(hero.get("camp", -1))
	if int(camp.get("guest", -1)) == int(hero.uid):
		camp.guest = -1
		camp.guest_entry = []
	hero.camp = -1

static func prisoner(item: Dictionary) -> String:
	return str(ELXml.value(item.get("node", {}), "params")).strip_edges()

## Gives an actor a hero template's level, health, book, runes and skills.
static func apply_template(profile: ELProfile, actor: Dictionary, name: String) -> void:
	var template: Dictionary = profile.table("HeroTemplates").get(name, {})
	actor.name = name
	actor.level = int(template.get("Level", 1))
	var growth := int(template.get("HealthIncrease", 3))
	actor.health = int(template.get("BaseHealth", 7)) + actor.level * growth
	actor.title = profile.text(str(template.get("ELKName", name)))
	actor.specialization = template.get("Specialization", "NONE")
	actor.cards = ELCatalog.deck(profile, str(template.get("StartDeck", "")))
	actor.spell_stock = {}
	actor.skills = ELHeroSkills.from_template(profile, template)
	ELHeroProgression.initialize(profile, actor, growth)
	ELRunes.initialize(profile, actor)
	ELStrategy.initialize(profile, actor)

## A freed prisoner joins the visitor's player on the cage's tile.
static func spawn_hero(state: ELAdventureSession, name: String, owner: int, x: int, y: int) -> int:
	var id := state._next_object
	state._next_object += 1
	var actor := {"uid": id, "permanent_id": id, "source_index": -1, "id": id, "name": name, "owner": owner, "group": "heroes", "x": x, "y": y, "rotation": 0, "type": "hero",
		"alive": true, "visible": true, "enabled": true, "shape": "", "level": 1, "health": 10, "base_ap": 0, "ap": 0, "experience": 0,
		"cards": [], "spell_stock": {}, "stock_separate": true, "skills": {}, "inventory": [], "orders": [], "node": {}, "fortified": false, "fort": -1, "temp_buffs": []}
	apply_template(state.map.profile, actor, name)
	state.objects[id] = actor
	state._mob_ids.append(id)
	refresh_heroes(state, owner)
	state.event.emit({"kind": "object_created", "id": id})
	return id

## The roaming Konung keeps its place and identity, one template weaker.
static func weaken_konung(state: ELAdventureSession) -> void:
	for actor: Dictionary in state.objects.values():
		if actor.get("type") == "hero" and actor.get("alive", false) and KONUNG.has(actor.get("name")):
			apply_template(state.map.profile, actor, KONUNG[actor.name])
			state.event.emit({"kind": "object_changed", "id": actor.uid})
			return

## Adds runes to every finite spell in the equipped book. Cantrips are
## unlimited and unchanged; there is no capacity cap.
static func add_runes(hero: Dictionary, amount: int) -> void:
	for index in hero.get("rune_uses", []).size():
		if int(hero.rune_uses[index]) >= 0: hero.rune_uses[index] = mini(ELResources.MAX_AMOUNT, int(hero.rune_uses[index]) + amount)

## Original message text: %d/%s values in order; each @n resource marker is
## followed by its amount, and markers without a reward are dropped.
static func format(profile: ELProfile, key: String, values: Array, resources: Array = []) -> String:
	var text := profile.text(key)
	if text == key: text = ""
	text = text.strip_edges()
	if text.contains("@1"):
		var head := text.get_slice("@1", 0).strip_edges()
		var parts: Array[String] = []
		for entry: Array in resources: parts.append("%d %s" % [int(entry[1]), resource_name(profile, str(entry[0]))])
		return (head + " " + ", ".join(parts)).strip_edges()
	for value: Variant in values:
		var at := text.find("%")
		if at < 0 or at + 1 >= text.length(): break
		text = text.substr(0, at) + str(value) + text.substr(at + 2)
	return text

static func resource_name(profile: ELProfile, kind: String) -> String:
	var index := ELResources.ORIGINAL.find(kind)
	var name := profile.text("T_RESOURCE_NAME_%d" % (index + 1)) if index >= 0 else kind
	return ELResources.LABELS.get(kind, kind) if name.begins_with("T_RESOURCE_NAME") else name

## Day hook, run once at mission start (day 0) and after each night. Weekly
## resets happen when the elapsed-day counter is a multiple of seven.
static func new_day(state: ELAdventureSession, counter: int) -> void:
	# Training camps teach every day, without a message.
	for item: Dictionary in state.objects.values():
		if item.get("name") != CAMP or not supported(item) or item.get("addition_version") != VERSION or int(item.guest) < 0: continue
		var guest := state.object(item.guest)
		if guest.get("alive", false) and int(guest.get("level", 1)) < ELHeroProgression.MAX_LEVEL: state.add_experience(int(guest.uid), CAMP_EXPERIENCE)
	if counter % WEEK != 0: return
	for item: Dictionary in state.objects.values():
		if not supported(item) or item.get("addition_version") != VERSION: continue
		if item.name in WEEKLY_VISITED: item.visited.clear()
		if item.name in WEEKLY_FLAG: item.used = false
		if DUNGEONS.has(item.name) and not state.object(item.monster).get("alive", false):
			item.monster = -1
			restock(state, item)

## Night-end hero refresh: on a weekly night spring bonuses expire before
## movement is restored to the recalculated maximum.
static func end_night(state: ELAdventureSession, counter: int) -> void:
	if counter % WEEK != 0: return
	for hero: Dictionary in state.objects.values():
		if hero.get("type") == "hero" and not hero.get("temp_buffs", []).is_empty():
			hero.temp_buffs.clear()
			recalculate(state.map.profile, hero)

## Skill offers already shown for a level-up stay valid unless the lesson made
## one of them impossible; then a fresh offer is drawn.
static func _refresh_offers(profile: ELProfile, hero: Dictionary) -> void:
	if int(hero.get("skill_points", 0)) <= 0: return
	var pool := ELHeroSkills.candidates(profile, hero)
	var offers: Array = hero.get("skill_offers", [])
	var valid := offers.size() == mini(3, pool.size())
	for code: Variant in offers: valid = valid and pool.has(code)
	if not valid:
		hero.skill_offers = []
		ELHeroSkills.prepare(profile, hero)

static func _random(state: ELAdventureSession) -> int:
	state.seed_value = (state.seed_value * 0x343fd + 0x269ec3) & 0xffffffff
	return (state.seed_value >> 16) & 0x7fff
