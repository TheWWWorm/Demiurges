class_name ELExpeditionRun
extends RefCounted
## Standalone Etherlords II expedition. The route and offered cards come from
## seeds. A battle checkpoint also carries the duel's last settled state.

const SAVE_PATH := "user://expedition-el2.json"
const SAVE_FORMAT := "etherlords-el2-expedition"
const SAVE_VERSION := 7
const MAX_SAVE_BYTES := 2 * 1024 * 1024
const ACTS := 3
const FLOORS := 6
const MIN_DECK := 8
const MAX_DECK := 24
const STARTING_LIFE := 24
const LIFE_PER_ACT := 4
const MAX_LIFE_BONUS := 12
const REWARD_RECOVERY := 0.2
const MIRROR_EXCHANGE_COST := 3
const KEEPSAKE_COST := 5
const TRAINING_LIMIT := 2
const TRAINABLE_SKILLS := ["PRVD", "SUPR"]
# Mounted faction spells that can remove an enemy ward. Green trades a creature.
const CAMP_STUDY := {"Blue": "CLNP", "Black": "PRFY", "Green": "ETTD", "Red": "FLIC"}
const EXPEDITION_ARTIFACTS := ["RingOfHealing", "RodOfLightning"]
const ROOM_ROWS := [
	["fight", "fight", "fight"],
	["event", "fight", "fight"],
	["fight", "elite", "event"],
	["rest", "event", "fight"],
	["elite", "rest"],
	["boss"],
]
const ROOM_TITLES := {
	"fight": "Battle", "elite": "Elite battle", "event": "Encounter",
	"rest": "Rest site", "boss": "Act boss",
}
const COMBAT_ROOMS := ["fight", "elite", "boss"]
const RELIQUARY_EVENT := 3
const WARDEN_EVENT := 4
const EVENTS := [
	["Wayside Spring", "A wayfarer rests by a clear spring. They offer to teach you a spell or lend an artifact."],
	["Spellwright's Mirror", "A copper mirror reflects the pages of your spellbook. It can erase, copy, or transform a spell."],
	["Totem of the Wilds", "The old totem promises to strengthen your life in exchange for a blood oath."],
	["The Silent Reliquary", "A ward keeps two artifacts charged. Offer life to carry one, or take a draught from the workbench."],
	["The Bridge Warden", "A warden challenges you to a duel. Win to earn an elite reward. Defeat ends the expedition."],
]

var profile: ELProfile
var preset: Dictionary = {}
var seed_value := 0
var act := 1
var health := 0
var max_health := 0
var life_bonus := 0
var deck: Array[String] = []
var current := ""
var phase := "map"
var error := ""
var visited: Array[String] = []
var pending_card := ""
var borrowed_artifact := ""
var keepsake_artifact := ""
var _route: Array[Array] = []
var _nodes: Dictionary = {}
var _battle_checkpoint: Dictionary = {}
var _final_battle := {}
var _version := SAVE_VERSION
var _opponents := {}
var _previous_paths := {}
var _training := {}

static func starters(source: ELProfile) -> Array[Dictionary]:
	if source == null or source.id != "el2": return []
	var result: Array[Dictionary] = []
	for row: Dictionary in ELDuelPresets.shipped(source):
		if row.resource_level != 1 or row.cards.size() != ELDuelCosts.EL2_DECK: continue
		if not row.cards.all(func(card: String): return _valid_card(source, card, row.faction)): continue
		result.append(row)
	return result

static func _valid_card(source: ELProfile, card: String, faction: String) -> bool:
	return ELDuelCosts.spell_allowed(source, card, faction) and not ELCatalog.rule(source, card).is_empty()

func create(source: ELProfile, preset_id: String, run_seed: int, rules_version := SAVE_VERSION) -> bool:
	if rules_version < 1 or rules_version > SAVE_VERSION: return _fail("The expedition checkpoint has an unknown format.")
	var chosen := ELDuelPresets.find(starters(source), preset_id)
	if chosen.is_empty(): return _fail("Choose an Etherlords II starter preset.")
	life_bonus = 0
	borrowed_artifact = ""
	keepsake_artifact = ""
	_previous_paths.clear()
	_training.clear()
	_final_battle.clear()
	_version = rules_version
	_reset(source, chosen, run_seed & 0xffffffff, 1)
	deck.assign(preset.cards)
	health = max_health
	return true

func finished() -> bool:
	return phase in ["won", "lost"]

func retry() -> ELExpeditionRun:
	if not finished(): return null
	var next := ELExpeditionRun.new()
	return next if next.create(profile, preset.id, seed_value, _version) else null

func final_battle() -> Dictionary:
	return _final_battle.duplicate()

func _reset(source: ELProfile, chosen: Dictionary, run_seed: int, next_act: int) -> void:
	profile = source
	preset = chosen
	seed_value = run_seed
	act = next_act
	max_health = _life_cap(profile, preset, act) + life_bonus
	current = ""
	visited.clear()
	pending_card = ""
	_battle_checkpoint = {}
	_opponents.clear()
	phase = "map"
	error = ""
	_build_route()

static func _life_cap(source: ELProfile, chosen: Dictionary, at_act: int) -> int:
	return maxi(STARTING_LIFE, ELDuelPresets.health(source, chosen)) + LIFE_PER_ACT * (at_act - 1)

func _build_route() -> void:
	_route.clear()
	_nodes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 104729 * act
	# Connections have their own stream so they never reroll room content.
	var links := RandomNumberGenerator.new()
	links.seed = seed_value ^ (104729 * act) ^ 0x3dc4f129
	for floor_index in FLOORS:
		var kinds: Array = ROOM_ROWS[floor_index].duplicate()
		for index in range(kinds.size() - 1, 0, -1):
			var other := rng.randi_range(0, index)
			var kind: String = kinds[index]
			kinds[index] = kinds[other]
			kinds[other] = kind
		var row: Array[Dictionary] = []
		for column in kinds.size():
			var id := "%d-%d-%d" % [act, floor_index + 1, column + 1]
			var kind: String = kinds[column]
			var room := {"id": id, "kind": kind, "title": _text(ROOM_TITLES[kind]),
				"floor": floor_index + 1, "column": column, "next": [] as Array[String], "seed": rng.randi()}
			row.append(room)
			_nodes[id] = room
		if floor_index > 0: _link_rows(_route.back(), row, links)
		_route.append(row)

func _link_rows(previous: Array, row: Array[Dictionary], links: RandomNumberGenerator) -> void:
	if _version < 3 or row.size() != previous.size():
		for room: Dictionary in previous:
			for next: Dictionary in row:
				if absi(room.column - next.column) <= 1 or row.size() == 1: room.next.append(next.id)
		return
	# Straight paths keep every room reachable. Each row adds a fork, with
	# at most one diagonal between neighboring lanes.
	for lane in row.size(): previous[lane].next.append(row[lane].id)
	var fork := links.randi_range(0, row.size() - 2)
	for lane in row.size() - 1:
		if lane != fork and links.randi_range(0, 1) == 0: continue
		if links.randi_range(0, 1) == 0: previous[lane].next.append(row[lane + 1].id)
		else: previous[lane + 1].next.append(row[lane].id)
	for room: Dictionary in previous: room.next.sort()

func route() -> Array[Array]:
	return _route.duplicate(true)

func journey() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chapter in range(1, act + 1):
		var path: Array = visited if chapter == act else _previous_paths.get(str(chapter), [])
		var nodes := _nodes
		if chapter != act and not path.is_empty():
			var earlier := ELExpeditionRun.new()
			earlier._version = _version
			earlier._reset(profile, preset, seed_value, chapter)
			nodes = earlier._nodes
		var rooms: Array[Dictionary] = []
		for id: String in path:
			var room: Dictionary = nodes[id]
			rooms.append({"kind": room.kind, "floor": room.floor, "column": room.column})
		result.append({"act": chapter, "rooms": rooms, "recorded": chapter == act or not path.is_empty()})
	return result

func available() -> Array[String]:
	return upcoming() if phase == "map" else []

func upcoming() -> Array[String]:
	if phase not in ["map", "reward", "rest", "event"] or _route.is_empty(): return []
	if not current.is_empty(): return _nodes[current].next.duplicate()
	var ids: Array[String] = []
	for room: Dictionary in _route[0]: ids.append(room.id)
	return ids

func choose_node(id: String) -> bool:
	error = ""
	if not available().has(id): return _fail("That expedition room is unavailable.")
	current = id
	visited.append(id)
	var kind: String = _nodes[current].kind
	if _version >= 4:
		# A different branch may change the opponent farther along the route.
		for cached: String in _opponents.keys():
			var room: Dictionary = _nodes[cached]
			if room.kind != "boss" and room.floor > _nodes[id].floor: _opponents.erase(cached)
	phase = "battle" if kind in COMBAT_ROOMS else kind
	return true

func guardian() -> Dictionary:
	return {} if _route.is_empty() else opponent_at(_route.back()[0].id)

func _combat_kind(room: Dictionary) -> String:
	var kind := str(room.get("kind", ""))
	return "elite" if kind == "event" and _event_for_seed(int(room.seed)) == WARDEN_EVENT else kind

func opponent_at(id: String) -> Dictionary:
	var room: Dictionary = _nodes.get(id, {})
	var kind := _combat_kind(room)
	if kind not in COMBAT_ROOMS or (room.kind == "event" and id not in visited): return {}
	if not _opponents.has(id):
		var floor_number := (act - 1) * FLOORS + int(room.floor)
		var met: Array[String] = []
		if _version >= 4 and kind != "boss":
			for earlier: String in visited:
				var previous: Dictionary = _nodes[earlier]
				if previous.floor >= room.floor: break
				if _combat_kind(previous) != kind: continue
				var foe := opponent_at(earlier)
				if not foe.is_empty(): met.append(foe.id)
		var opponent := ELExpeditionEncounters.build(profile, kind, floor_number, room.seed, _version >= 2, met)
		if opponent.is_empty(): return {}
		_opponents[id] = opponent
	return _opponents[id]

func build_battle() -> ELDuel:
	error = ""
	if phase != "battle":
		_fail("There is no active expedition battle.")
		return null
	if not _battle_checkpoint.is_empty(): return _restore_battle(_battle_checkpoint)
	var room: Dictionary = _nodes[current]
	var opponent := opponent_at(current).duplicate(true)
	if opponent.is_empty():
		_fail("The expedition encounter has no usable opponent.")
		return null
	var hero := ELDuelPresets.choice(profile, preset)
	hero.erase("deck")
	hero.cards = deck.duplicate()
	hero.level = mini(20, int(preset.level) + 2 * (act - 1))
	hero.health = health
	hero.title = preset.name
	if not borrowed_artifact.is_empty() or not keepsake_artifact.is_empty():
		var artifacts: Array = hero.get("artifacts", [])
		for name: String in [keepsake_artifact, borrowed_artifact]:
			if not name.is_empty(): artifacts.append({"name": name, "charges": 1})
		hero.artifacts = artifacts
	hero.skills = _starting_skills()
	hero.skills.merge(trained_skills(), true)
	var options := {"adventure": true, "players": [hero, opponent],
		"arena": str(opponent.get("arena", "Green.001")), "first_side": int(room.seed) & 1}
	for key: String in ["scripts", "script_variables", "script_difficulty"]:
		if opponent.has(key): options[key] = opponent[key]
	var duel := ELDuel.new()
	if not duel.start(profile, int(room.seed), options):
		_fail(duel.error)
		return null
	duel.heroes[0].maximum = max_health
	duel.setup.expedition_room = current
	duel.setup.expedition_seed = seed_value
	if not borrowed_artifact.is_empty(): duel.setup.expedition_artifact = borrowed_artifact
	if not keepsake_artifact.is_empty(): duel.setup.expedition_keepsake = keepsake_artifact
	return duel

func resolve_battle(duel: ELDuel) -> bool:
	error = ""
	if phase != "battle" or duel == null or duel.profile != profile or duel.phase != ELDuel.Phase.FINISHED:
		return _fail("The expedition battle has not finished.")
	if not _battle_belongs_here(duel.setup):
		return _fail("This battle belongs to a different expedition room.")
	_battle_checkpoint = {}
	borrowed_artifact = ""
	if duel.winner != 0 or int(duel.heroes[0].health) <= 0:
		health = 0
		phase = "lost"
	else:
		health = mini(max_health, int(duel.heroes[0].health))
		phase = "won" if act == ACTS and _nodes[current].kind == "boss" else "reward"
	if finished():
		_final_battle = {"round": duel.round_number, "opponent_life": maxi(0, int(duel.heroes[1].health))}
	return true

func save_battle(duel: ELDuel) -> bool:
	error = ""
	if phase != "battle" or duel == null or duel.profile != profile or not _battle_belongs_here(duel.setup):
		return _fail("This battle belongs to a different expedition room.")
	var next := duel.snapshot()
	if next == _battle_checkpoint: return true
	var previous := _battle_checkpoint
	_battle_checkpoint = next
	if persist(): return true
	_battle_checkpoint = previous
	return false

func _battle_belongs_here(setup: Dictionary) -> bool:
	return (setup.get("expedition_room") == current
		and ELLuaSave._integer(setup.get("expedition_seed"), seed_value, seed_value)
		and setup.get("expedition_artifact", "") == borrowed_artifact
		and setup.get("expedition_keepsake", "") == keepsake_artifact)

func _restore_battle(saved: Dictionary) -> ELDuel:
	var setup: Variant = saved.get("setup")
	if setup is not Dictionary or not _battle_belongs_here(setup) or setup.get("adventure") != true:
		_fail("This battle belongs to a different expedition room.")
		return null
	var duel := ELDuel.new()
	if duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": saved}):
		var trained := trained_skills()
		for code: String in trained:
			if duel.heroes[0].skills.get(code) != trained[code]:
				_fail("This battle does not match the expedition's trained skills.")
				return null
		return duel
	_fail(duel.error)
	return null

func _eligible_spells() -> Array[String]:
	var pool: Array[String] = []
	for code: String in profile.table("CombatSpells"):
		if deck.count(code) < ELDuelCosts.EL2_COPIES and _valid_card(profile, code, preset.faction): pool.append(code)
	pool.sort()
	return pool

func _offered_cards() -> Array[String]:
	var spells := profile.table("CombatSpells")
	var pool := _eligible_spells()
	var room: Dictionary = _nodes[current]
	var kind := _combat_kind(room)
	var balanced := _version >= 5 and kind in COMBAT_ROOMS
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room.seed) ^ 0x61e0a25f
	var result: Array[String] = []
	for index in mini(3, pool.size()):
		var source := pool
		if balanced and index < 2:
			var creature := index == 0
			var options := pool.filter(func(code: String) -> bool: return (spells[code].get("Class") == "Creature") == creature)
			if creature and act == 1 and room.floor <= 2:
				var cheap := options.filter(func(code: String) -> bool: return ELEncyclopaedia.cost(profile, code) <= 3)
				if not cheap.is_empty(): options = cheap
			var faction_spells := options.filter(func(code: String) -> bool: return spells[code].get("Color") == preset.faction)
			if not faction_spells.is_empty(): options = faction_spells
			if not options.is_empty(): source = options
		var card: String = source[rng.randi_range(0, source.size() - 1)]
		result.append(card)
		pool.erase(card)
	var bonus := 2 if kind == "boss" else int(kind == "elite")
	if bonus > 0:
		# Higher-risk rooms add choices from the remaining rare and unique spells.
		var rare := pool.filter(func(code: String) -> bool: return spells[code].get("Rarity") in ["Rare", "Unique"])
		for index in mini(bonus, pool.size()):
			var source := rare if not rare.is_empty() else pool
			var code: String = source[rng.randi_range(0, source.size() - 1)]
			rare.erase(code)
			pool.erase(code)
			result.append(code)
	return result

func _card_title(card: String) -> String:
	return profile.text(str(profile.table("CombatSpells").get(card, {}).get("Name", card)))

func _text(value: String) -> String:
	return ELRemakeText.t(value, profile)

func _choice(id: String, title: String, description := "", card := "") -> Dictionary:
	var row := {"id": id, "title": title, "description": description}
	if not card.is_empty(): row.card = card
	return row

func _heal_amount(percent: float) -> int:
	return mini(max_health - health, ceili(max_health * percent))

func _study_spell() -> String:
	var card: String = CAMP_STUDY.get(preset.faction, "")
	if act < 2 or card.is_empty() or deck.has(card) or not _valid_card(profile, card, preset.faction): return ""
	return card

func _starting_skills() -> Dictionary:
	var skills: Dictionary = preset.skills.duplicate()
	if not skills.has("PRVD") and not ELHeroSkills.definition(profile, "PRVD", 0).is_empty():
		skills["PRVD"] = 0
	return skills

func trained_skills() -> Dictionary:
	var result := {}
	if _training.is_empty(): return result
	var starting := _starting_skills()
	for code: String in _training:
		result[code] = int(starting.get(code, -1)) + int(_training[code])
	return result

func _training_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if act < 2: return result
	var sessions := 0
	for count: int in _training.values(): sessions += count
	if sessions >= TRAINING_LIMIT: return result
	var skills := _starting_skills()
	skills.merge(trained_skills(), true)
	for code: String in TRAINABLE_SKILLS:
		var rank := int(skills.get(code, -1)) + 1
		var definition := ELHeroSkills.definition(profile, code, rank)
		if definition.is_empty(): continue
		var title := profile.text(str(definition.Name)).strip_edges()
		var description := profile.text(str(definition.get("Description", ""))).strip_edges()
		var offer := _choice("train:" + code, _text("Train %s · Rank %d") % [title, rank + 1], description)
		offer.rank = rank
		result.append(offer)
	return result

func _expedition_artifact(name: String) -> Dictionary:
	if name not in EXPEDITION_ARTIFACTS or preset.artifacts.size() >= ELDuelCosts.EL2_ARTIFACTS: return {}
	var item := ELDuel.artifact_entry(profile, {"name": name, "charges": 1})
	return {} if item.is_empty() or item.spell in preset.artifacts else item

func _artifact_choices(keep: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if keep and (not keepsake_artifact.is_empty() or health <= KEEPSAKE_COST): return result
	if not keep and not borrowed_artifact.is_empty(): return result
	var occupied: int = preset.artifacts.size() + int(not borrowed_artifact.is_empty()) + int(not keepsake_artifact.is_empty())
	if occupied >= ELDuelCosts.EL2_ARTIFACTS: return result
	for name: String in EXPEDITION_ARTIFACTS:
		if name == borrowed_artifact or name == keepsake_artifact: continue
		var item := _expedition_artifact(name)
		if item.is_empty(): continue
		var description := _text("One charge in your next duel, ready from round %d.") % item.ready_round
		var action := "borrow"
		var title := _text("Borrow %s") % ELSecondArtifacts.title(profile, item)
		if keep:
			action = "keep"
			title = _text("Keep %s") % ELSecondArtifacts.title(profile, item)
			description = _text("Spend %d life. One charge each duel, ready from round %d.") % [KEEPSAKE_COST, item.ready_round]
		var offer := _choice(action + ":" + name, title, description + "\n" + profile.card_description(item.spell))
		offer.artifact = item
		result.append(offer)
	return result

func _event_index() -> int:
	return _event_for_seed(int(_nodes[current].seed))

func _event_for_seed(room_seed: int) -> int:
	if _version >= 6 and act >= 2 and ((room_seed >> 10) & 3) == 0: return RELIQUARY_EVENT
	if _version >= 7 and act >= 2 and ((room_seed >> 14) & 3) == 0: return WARDEN_EVENT
	return room_seed % RELIQUARY_EVENT

func _mirror_exchange() -> Dictionary:
	if health <= MIRROR_EXCHANGE_COST: return {}
	var spells := profile.table("CombatSpells")
	var by_class := {}
	for code: String in _eligible_spells():
		var spell: Dictionary = spells[code]
		if spell.get("Rarity") not in ["Rare", "Unique"]: continue
		var kind: String = spell.get("Class", "")
		if not by_class.has(kind): by_class[kind] = []
		by_class[kind].append(code)
	var outgoing: Array[String] = []
	for code: String in deck:
		var spell: Dictionary = spells[code]
		if spell.get("Rarity") in ["Cantrip", "Common"] and by_class.has(spell.get("Class", "")) and not outgoing.has(code):
			outgoing.append(code)
	if outgoing.is_empty(): return {}
	var random := RandomNumberGenerator.new()
	random.seed = int(_nodes[current].seed) ^ 0x2fe93a85
	var old := outgoing[random.randi_range(0, outgoing.size() - 1)]
	var pool: Array = by_class[spells[old].get("Class", "")]
	var next: String = pool[random.randi_range(0, pool.size() - 1)]
	var offer := _choice("transmute", _text("Transform %s") % _card_title(old),
		_text("Spend %d life to exchange it for %s, a rarer spell of the same type.") % [MIRROR_EXCHANGE_COST, _card_title(next)], old)
	offer.incoming = next
	return offer

func room_summary() -> Dictionary:
	if current.is_empty() or phase not in ["event", "rest", "reward"]: return {}
	var title: String = _nodes[current].title
	var description := ""
	var illustration := ""
	match phase:
		"event":
			var index := _event_index()
			var event: Array = EVENTS[index]
			title = _text(event[0])
			description = _text(event[1])
			if index == RELIQUARY_EVENT: illustration = "reliquary"
			elif index == WARDEN_EVENT: illustration = "warden"
		"rest":
			description = _text("Recover some life or remove a spell from your spellbook.")
			if not pending_card.is_empty():
				description = _text("Choose a spell to replace with %s.") % _card_title(pending_card)
			elif not _study_spell().is_empty():
				description = _text("Recover life, remove a spell, or study a counter to enchantments.")
			if pending_card.is_empty() and not _training_choices().is_empty():
				description += " " + _text("You can also train a skill for the rest of the expedition.")
		"reward":
			match _combat_kind(_nodes[current]):
				"elite": title = _text("Elite battle reward")
				"boss": title = _text("Guardian reward")
				_: title = _text("Battle reward")
			description = _text("Choose one spell to add or use as a replacement.") if pending_card.is_empty() else _text("Choose how to use %s.") % _card_title(pending_card)
			if pending_card.is_empty() and health < max_health:
				description = _text("Choose a spell for your spellbook or recover life.")
	var summary := {"title": title, "description": description}
	if not illustration.is_empty(): summary.illustration = illustration
	return summary

func _event_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match _event_index():
		0:
			result.append(_choice("recover", _text("Drink from the spring"), _text("Recover %d life.") % _heal_amount(0.2)))
			var offers := _offered_cards()
			if health > 3 and deck.size() < MAX_DECK and not offers.is_empty():
				result.append(_choice("trade", _text("Trade with the wayfarer"), _text("Spend 3 life to learn %s.") % _card_title(offers[0]), offers[0]))
			result.append_array(_artifact_choices(false))
		1:
			var exchange := _mirror_exchange()
			if not exchange.is_empty(): result.append(exchange)
			var listed := {}
			for index in deck.size():
				var card := deck[index]
				if listed.has(card): continue
				listed[card] = true
				if deck.size() > MIN_DECK:
					result.append(_choice("purge:%d" % index, _text("Erase %s") % _card_title(card), _text("Remove this spell and recover %d life.") % _heal_amount(0.1), card))
				if health > 4 and deck.size() < MAX_DECK and deck.count(card) < ELDuelCosts.EL2_COPIES:
					result.append(_choice("echo:%d" % index, _text("Copy %s") % _card_title(card), _text("Spend 4 life to add another copy of this spell."), card))
		2:
			if health > 5 and life_bonus < MAX_LIFE_BONUS:
				result.append(_choice("oath", _text("Swear the blood oath"), _text("Spend 5 life to gain 4 maximum life.")))
			result.append(_choice("mend", _text("Make a small offering"), _text("Recover %d life.") % mini(2, max_health - health)))
		RELIQUARY_EVENT:
			result.append_array(_artifact_choices(true))
			if health < max_health:
				result.append(_choice("mend", _text("Drink the draught"), _text("Recover %d life.") % mini(2, max_health - health)))
		WARDEN_EVENT:
			var opponent := opponent_at(current)
			if not opponent.is_empty():
				var detail := "%s\n%s" % [opponent.title, _text("%d life · Level %d") % [opponent.health, opponent.level]]
				result.append(_choice("challenge", _text("Accept the duel"), detail))
	result.append(_choice("leave", _text("Leave")))
	return result

func choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if phase in ["rest", "reward"] and not pending_card.is_empty():
		if phase == "reward" and deck.size() < MAX_DECK:
			result.append(_choice("add", _text("Add %s to the spellbook") % _card_title(pending_card), "", pending_card))
		for index in deck.size():
			result.append(_choice("replace:%d" % index, _text("Replace %s") % _card_title(deck[index]), "", deck[index]))
		result.append(_choice("back", _text("Back")))
		return result
	match phase:
		"reward":
			for card: String in _offered_cards():
				result.append(_choice("card:" + card, _card_title(card), profile.card_description(card), card))
			if health < max_health:
				result.append(_choice("recover_reward", _text("Recover life instead"), _text("Recover %d life.") % _heal_amount(REWARD_RECOVERY)))
			result.append(_choice("skip", _text("Skip reward")))
		"rest":
			result.append(_choice("heal", _text("Rest"), _text("Recover %d life.") % _heal_amount(0.3)))
			var study := _study_spell()
			if not study.is_empty():
				result.append(_choice("study", _text("Study %s") % _card_title(study), profile.card_description(study), study))
			result.append_array(_training_choices())
			if deck.size() > MIN_DECK:
				for index in deck.size():
					result.append(_choice("remove:%d" % index, _text("Remove %s") % _card_title(deck[index]), "", deck[index]))
		"event":
			return _event_choices()
	return result

func choose(id: String) -> bool:
	error = ""
	var selected := {}
	for option: Dictionary in choices():
		if option.id == id:
			selected = option
			break
	if selected.is_empty(): return _fail("That expedition choice is unavailable.")
	if id == "challenge":
		phase = "battle"
		return true
	if id.begins_with("card:"):
		pending_card = id.trim_prefix("card:")
		return true
	if id == "study":
		pending_card = selected.card
		return true
	if id == "back":
		pending_card = ""
		return true
	if id == "add": deck.append(pending_card)
	elif id.begins_with("replace:"): deck[int(id.get_slice(":", 1))] = pending_card
	elif id.begins_with("remove:"): deck.remove_at(int(id.get_slice(":", 1)))
	elif id.begins_with("train:"):
		var code := id.trim_prefix("train:")
		_training[code] = int(_training.get(code, 0)) + 1
	elif id == "heal": health += _heal_amount(0.3)
	elif id == "recover_reward": health += _heal_amount(REWARD_RECOVERY)
	elif id == "recover": health += _heal_amount(0.2)
	elif id == "mend": health += mini(2, max_health - health)
	elif id == "trade":
		deck.append(_offered_cards()[0])
		health -= 3
	elif id.begins_with("borrow:"): borrowed_artifact = selected.artifact.name
	elif id.begins_with("keep:"):
		keepsake_artifact = selected.artifact.name
		health -= KEEPSAKE_COST
	elif id == "transmute":
		deck[deck.find(selected.card)] = selected.incoming
		health -= MIRROR_EXCHANGE_COST
	elif id.begins_with("purge:"):
		deck.remove_at(int(id.get_slice(":", 1)))
		health += _heal_amount(0.1)
	elif id.begins_with("echo:"):
		deck.append(deck[int(id.get_slice(":", 1))])
		health -= 4
	elif id == "oath":
		life_bonus += 4
		max_health += 4
		health -= 5
	_complete_room()
	return true

func _complete_room() -> void:
	pending_card = ""
	if _nodes[current].kind != "boss":
		phase = "map"
	else:
		_previous_paths[str(act)] = visited.duplicate()
		_reset(profile, preset, seed_value, act + 1)
		health += _heal_amount(0.3)

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func snapshot() -> Dictionary:
	var data := {"format": SAVE_FORMAT, "version": _version, "seed": seed_value, "act": act,
		"preset": str(preset.get("id", "")), "health": health, "deck": deck.duplicate(),
		"visited": visited.duplicate(), "phase": phase, "pending_card": pending_card, "life_bonus": life_bonus}
	if not borrowed_artifact.is_empty(): data.borrowed_artifact = borrowed_artifact
	if not keepsake_artifact.is_empty(): data.keepsake_artifact = keepsake_artifact
	if not _previous_paths.is_empty(): data.previous_paths = _previous_paths.duplicate(true)
	if not _training.is_empty(): data.training = _training.duplicate()
	if not _final_battle.is_empty(): data.final_battle = _final_battle.duplicate()
	if not _battle_checkpoint.is_empty(): data.battle = _battle_checkpoint.duplicate(true)
	return data

func persist() -> bool:
	error = ""
	if profile == null or preset.is_empty(): return _fail("There is no expedition to save.")
	var bytes := JSON.stringify(snapshot(), "", true, true).to_utf8_buffer()
	if bytes.size() > MAX_SAVE_BYTES: return _fail("The expedition checkpoint is too large.")
	var temporary := SAVE_PATH + ".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("Could not write the expedition checkpoint.")
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temporary, SAVE_PATH) != OK:
		DirAccess.remove_absolute(temporary)
		return _fail("Could not replace the expedition checkpoint.")
	return true

func restore(source: ELProfile) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return _fail("No expedition checkpoint is available.")
	if file.get_length() > MAX_SAVE_BYTES: return _fail("The expedition checkpoint is too large.")
	return restore_snapshot(source, JSON.parse_string(file.get_as_text()))

func restore_snapshot(source: ELProfile, raw: Variant) -> bool:
	if raw is not Dictionary or raw.get("format") != SAVE_FORMAT:
		return _fail("The expedition checkpoint has an unknown format.")
	var version: Variant = raw.get("version")
	if not ELLuaSave._integer(version, 1, SAVE_VERSION):
		return _fail("The expedition checkpoint has an unknown format.")
	if not ELLuaSave._integer(raw.get("seed"), 0, 0xffffffff) or not ELLuaSave._integer(raw.get("act"), 1, ACTS) or raw.get("preset") is not String:
		return _fail("The expedition checkpoint has invalid run settings.")
	if not ELLuaSave._integer(raw.get("life_bonus", 0), 0, MAX_LIFE_BONUS) or int(raw.get("life_bonus", 0)) % 4 != 0:
		return _fail("The expedition checkpoint has an invalid life bonus.")
	var candidate := ELExpeditionRun.new()
	if not candidate.create(source, raw.preset, int(raw.seed), int(version)): return _fail(candidate.error)
	var loan: Variant = raw.get("borrowed_artifact", "")
	if loan is not String or (not loan.is_empty() and candidate._expedition_artifact(loan).is_empty()):
		return _fail("The expedition checkpoint has an invalid borrowed artifact.")
	candidate.borrowed_artifact = loan
	var keepsake: Variant = raw.get("keepsake_artifact", "")
	if keepsake is not String or (not keepsake.is_empty() and (int(version) < 6 or int(raw.act) < 2
		or candidate._expedition_artifact(keepsake).is_empty() or keepsake == loan)):
		return _fail("The expedition checkpoint has an invalid keepsake.")
	if candidate.preset.artifacts.size() + int(not loan.is_empty()) + int(not keepsake.is_empty()) > ELDuelCosts.EL2_ARTIFACTS:
		return _fail("The expedition checkpoint has too many artifacts.")
	candidate.keepsake_artifact = keepsake
	candidate.life_bonus = int(raw.get("life_bonus", 0))
	var previous: Variant = raw.get("previous_paths", {})
	if not candidate._restore_previous_paths(previous, int(raw.act)):
		return _fail("The expedition checkpoint has an invalid journey.")
	candidate._reset(source, candidate.preset, int(raw.seed), int(raw.act))
	if not candidate._restore_training(raw.get("training", {})):
		return _fail("The expedition checkpoint has invalid skill training.")
	if not candidate._restore_position(raw):
		return _fail(candidate.error if not candidate.error.is_empty() else "The expedition checkpoint has an invalid room or spellbook.")
	life_bonus = candidate.life_bonus
	_version = candidate._version
	_reset(source, candidate.preset, candidate.seed_value, candidate.act)
	deck.assign(candidate.deck)
	visited.assign(candidate.visited)
	current = candidate.current
	phase = candidate.phase
	pending_card = candidate.pending_card
	borrowed_artifact = candidate.borrowed_artifact
	keepsake_artifact = candidate.keepsake_artifact
	health = candidate.health
	_battle_checkpoint = candidate._battle_checkpoint
	_previous_paths = candidate._previous_paths
	_training = candidate._training
	_final_battle = candidate._final_battle
	return true

func _restore_training(raw: Variant) -> bool:
	if raw is not Dictionary or (act < 2 and not raw.is_empty()): return false
	var starting := _starting_skills()
	var sessions := 0
	for code: Variant in raw:
		if code not in TRAINABLE_SKILLS: return false
		if not ELLuaSave._integer(raw[code], 1, TRAINING_LIMIT): return false
		var count := int(raw[code])
		if ELHeroSkills.definition(profile, code, int(starting.get(code, -1)) + count).is_empty(): return false
		sessions += count
		_training[code] = count
	return sessions <= TRAINING_LIMIT

func _restore_previous_paths(previous: Variant, current_act: int) -> bool:
	if previous is not Dictionary or previous.size() >= current_act: return false
	for chapter: Variant in previous:
		if chapter is not String or chapter not in ["1", "2"] or int(chapter) >= current_act: return false
		var path: Variant = previous[chapter]
		if path is not Array or path.size() != FLOORS: return false
		_reset(profile, preset, seed_value, int(chapter))
		for id: Variant in path:
			if id is not String or not available().has(id): return false
			current = id
		_previous_paths[chapter] = path.duplicate()
	return true

func _restore_position(raw: Dictionary) -> bool:
	var cards: Variant = raw.get("deck")
	var path: Variant = raw.get("visited")
	var saved_phase: Variant = raw.get("phase")
	var pending: Variant = raw.get("pending_card", "")
	if not borrowed_artifact.is_empty() and saved_phase in ["reward", "won", "lost"]: return false
	if cards is not Array or cards.size() < MIN_DECK or cards.size() > MAX_DECK or path is not Array or path.size() > FLOORS or pending is not String:
		return false
	var counts := {}
	for card: Variant in cards:
		if card is not String or not _valid_card(profile, card, preset.faction): return false
		counts[card] = int(counts.get(card, 0)) + 1
		if int(counts[card]) > ELDuelCosts.EL2_COPIES: return false
	deck.assign(cards)
	for id: Variant in path:
		if id is not String or not available().has(id): return false
		current = id
		visited.append(id)
	var kind := str(_nodes.get(current, {}).get("kind", ""))
	match saved_phase:
		"map":
			if kind == "boss": return false
		"event", "rest":
			if kind != saved_phase: return false
		"battle", "reward", "lost":
			if _combat_kind(_nodes.get(current, {})) not in COMBAT_ROOMS: return false
		"won":
			if kind != "boss" or act != ACTS: return false
		_: return false
	if not ELLuaSave._integer(raw.get("health"), 0 if saved_phase == "lost" else 1, 0 if saved_phase == "lost" else max_health): return false
	if not pending.is_empty():
		match saved_phase:
			"reward": if pending not in _offered_cards(): return false
			"rest": if pending != _study_spell(): return false
			_: return false
	phase = saved_phase
	pending_card = pending
	health = int(raw.health)
	# Version-one runs could stop on a reward after defeating the last guardian.
	if phase == "reward" and kind == "boss" and act == ACTS:
		phase = "won"
		pending_card = ""
	var result: Variant = raw.get("final_battle", {})
	if result is not Dictionary: return false
	if not result.is_empty():
		if not finished() or not ELLuaSave._integer(result.get("round"), 1, 0x7fffffff) or not ELLuaSave._integer(result.get("opponent_life"), 0, 0x7fffffff): return false
		_final_battle = {"round": int(result.round), "opponent_life": int(result.opponent_life)}
	if raw.has("battle"):
		if phase != "battle" or raw.battle is not Dictionary or raw.battle.is_empty(): return false
		var restored := _restore_battle(raw.battle)
		if restored == null: return false
		_battle_checkpoint = restored.snapshot()
	return true

func _fail(reason: String) -> bool:
	error = reason
	return false
