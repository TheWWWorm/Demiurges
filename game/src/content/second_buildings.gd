class_name ELSecondBuildings
extends RefCounted
## Second-game map buildings that a hero uses from an adjacent tile:
## - Beacon (Black/Red/Green/Blue): serves heroes of its own colour; doubles
##   the hero's daily travel while at sea for ten world days. A new beacon
##   replaces an earlier one; the building itself never waits.
## - Power node (Black/Blue/Green/Red): serves a hero that has lost
##   experience, owned by a player of the node's colour; restores all of it.
## - Specialization shrine: gives the specialization named by its map
##   parameter, once for the whole mission (the visit is spent even when the
##   hero already knew it).
## - Sign and stone sign: show their parameter text, free of charge.
## - Prison: once per mission; the cage is removed from the map and the
##   message names the prisoner given by the map parameter (an adventure
##   template). Releasing the prisoner itself is left to the chapter script.
## Using any of them costs the building's use price from the travel clock
## first (2 points, signs 0). Only the hero's local owner sees the message.

const USE_COST := 2
const BEACON_DAYS := 10
const BEACON := "Beacon"
const POWER_NODE := "PowerNode"
const SHRINE := "Specialization"
const SIGNS := ["Sign", "StoneSign"]
const PRISON := "Prison"
const COLORS := ["Black", "Red", "Green", "Blue"]
## Daily travel capacity is capped at 16.
const MAX_TRAVEL := 16

static func kind(item: Dictionary) -> String:
	if item.get("group") != "additional_buildings": return ""
	var name := str(item.get("name", ""))
	if name in SIGNS: return "sign"
	if name == SHRINE: return "specialization"
	if name == PRISON: return "prison"
	if name.begins_with(BEACON) and name.trim_prefix(BEACON) in COLORS: return "beacon"
	if name.begins_with(POWER_NODE) and name.trim_prefix(POWER_NODE) in COLORS: return "power_node"
	return ""

static func applies(state: ELAdventureSession, item: Dictionary) -> bool:
	return state != null and state.map != null and state.map.profile.id == "el2" and not kind(item).is_empty()

static func color(item: Dictionary) -> String:
	var name := str(item.get("name", ""))
	return name.trim_prefix(BEACON).trim_prefix(POWER_NODE)

static func definition(profile: ELProfile, item: Dictionary) -> Dictionary:
	return profile.table("AdditionalBuildings").get(str(item.get("name", "")), {})

static func params(item: Dictionary) -> String:
	return str(ELXml.value(item.get("node", {}), "params")).strip_edges()

## The shrine's specialization: a valid four-letter code, otherwise none.
static func shrine_code(profile: ELProfile, item: Dictionary) -> String:
	var code := params(item)
	return code if code.length() == 4 and code != "NONE" and profile.table("HeroesSpecs").has(code) else ""

static func usable(state: ELAdventureSession, actor: Dictionary, item: Dictionary) -> bool:
	if actor.get("type") not in ["hero", "monster"] or not actor.get("alive", false): return false
	match kind(item):
		"sign": return true
		"beacon": return state.hero_color(actor) == color(item)
		"power_node":
			var owner_color := str(state.players.get(int(actor.get("owner", -1)), {}).get("color", ""))
			return float(actor.get("experience_penalty", 0.0)) > 0.0 and owner_color == color(item)
		"specialization": return not shrine_code(state.map.profile, item).is_empty() and not item.get("used", false)
		"prison": return not item.get("used", false)
	return false

static func use(director: ELAdventureDirector, actor: Dictionary, item: Dictionary) -> bool:
	var state := director.state
	var profile := state.map.profile
	if not applies(state, item) or not usable(state, actor, item): return false
	var what := kind(item)
	# The use price is paid before the effect.
	if what != "sign": ELAdventureClock.use_points(state, actor, USE_COST)
	var row := definition(profile, item)
	var key := str(row.get("Message1", ""))
	var text := ""
	match what:
		"sign":
			key = params(item)
			text = profile.text(key) if not key.is_empty() else ""
		"beacon":
			if not actor.has("affects"): actor.affects = []
			# Attaching a beacon removes any earlier one.
			actor.affects = actor.affects.filter(func(entry: Variant) -> bool: return not (entry is Dictionary and entry.get("kind") == "beacon"))
			actor.affects.append({"name": BEACON, "id": "beacon", "kind": "beacon", "ticks": BEACON_DAYS})
			refresh_travel(actor)
			text = profile.text(key)
			state.event.emit({"kind": "affects_changed", "id": actor.uid})
		"power_node":
			restore_experience(profile, actor)
			key = "T_MB_RESTORE_EXP"
			text = profile.text(key)
		"specialization":
			item.used = true
			var code := shrine_code(profile, item)
			var spec_name := profile.text(str(profile.table("HeroesSpecs")[code].get("Name", code)))
			var owned := state.specializations(actor)
			if owned.has(code):
				key = str(row.get("Message2", key))
				text = profile.text(key).replace("%s", spec_name)
			else:
				text = profile.text(key).replace("%s", spec_name)
				if owned.size() == 1: text += "\n\n" + profile.text("T_MB_RECEIVE_NEW_SPEC_FIRST")
				# Added to the hero's list; as in learn_specialization
				# a hero without an active one starts using it, otherwise the
				# player picks it from the bag (the hint above).
				owned.append(code)
				actor.specializations = owned
				if str(actor.get("specialization", "NONE")) == "NONE": actor.specialization = code
				state.event.emit({"kind": "object_changed", "id": actor.uid})
			state.event.emit({"kind": "object_changed", "id": item.uid})
		"prison":
			# Freed, then taken off the map (its cells no longer block).
			item.used = true
			item.alive = false
			item.visible = false
			item.enabled = false
			state.event.emit({"kind": "object_killed", "id": item.uid})
			text = first_placeholder(profile.text(key), prisoner_name(state, item))
	state.event.emit({"kind": "building_used", "id": item.uid, "hero": actor.uid, "player": actor.owner, "message": key})
	if int(actor.owner) == state.current_player:
		director.notice = text
		director.presentation.emit({"kind": "building_message", "hero": actor.uid, "building": item.uid, "title": profile.text(str(row.get("ELKName", item.name))),
			"text": text, "resources": [], "skill": "", "key": key})
	return true

## The prisoner's display name: the text of the parameter template's
## ElkName (its Name when that is empty); an unknown or missing template
## gives an empty name.
static func prisoner_name(state: ELAdventureSession, item: Dictionary) -> String:
	var template := params(item)
	if template.is_empty() or not state.map.mobs.has(template): return ""
	var variants: Dictionary = state.map.mobs[template]
	var mob: Dictionary = variants.get(state.difficulty, variants.get(0, variants.values()[0]))
	var key := str(mob.get("attrs", {}).get("ElkName", ""))
	return state.map.profile.text(key) if not key.is_empty() else template

## Original message formatting substitutes only the first %s.
static func first_placeholder(text: String, value: String) -> String:
	var at := text.find("%s")
	return text if at < 0 else text.substr(0, at) + value + text.substr(at + 2)

## Lost experience returns in full and the level is settled again.
static func restore_experience(profile: ELProfile, hero: Dictionary) -> void:
	ELColorless.set_lost(profile, hero, 0.0)

static func has_beacon(actor: Dictionary) -> bool:
	for entry: Variant in actor.get("affects", []):
		if entry is Dictionary and entry.get("kind") == "beacon" and int(entry.get("ticks", 0)) > 0: return true
	return false

## Travel recalculation: the base daily allowance, doubled at sea
## while a beacon lasts, at most 16; today's points are capped.
static func refresh_travel(actor: Dictionary) -> void:
	if not actor.has("travel_version"): return
	var capacity := ELAdventureClock.DAILY_POINTS
	if actor.get("ship", false) and has_beacon(actor): capacity *= 2
	actor.travel_capacity = mini(capacity, MAX_TRAVEL)
	actor.ap = mini(int(actor.ap), int(actor.travel_capacity))
