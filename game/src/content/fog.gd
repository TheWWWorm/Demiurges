class_name ELFog
extends RefCounted
## Strategic fog of war for both editions. Each tile has two masks with one
## bit per player index (1..7): explored, kept in the saved ELAdventureSession.explored bytes,
## and currently visible, rebuilt from the sight sources and never saved.
## Players whose relation byte has bit 4 (0x10) share both. The neutral player
## has no fog.
##
## Etherlords II differences: a fixed hero sight disc of radius 9 (base sight 8
## + 1, not tied to movement), every owned actor including mobs and ships is a
## source, crystal balls are ReflectingEyes scried from a Lake with equal
## params and closed again at the end of each turn, closed Runestones whose
## params carry `key x0 y0 x1 y1` keep that rectangle unseen for the local
## player's group, and script observations show discs to every player. Shipped
## EL2 relations (170/239/255) never share vision. The EL1 map specials
## (frozen chapters, mission23 neutral sight, mission24 tomb) do not apply.
##
## The visible set is recomputed from the current sources on every refresh.
## The original hides only the old square around a stepping hero, so a lost
## mine or castle can leave a stale visible patch; that quirk is not copied.
const UNEXPLORED := 0
const REMEMBERED := 1
const VISIBLE := 2
const CASTLE_RADIUS := 5
const MINE_RADIUS := 3
const TOMB_RADIUS := 6
const BOWL_RADIUS := 5
## mission23: neutral heroes of this template colour show every player their
## surroundings (colour 2 of the original enum Red/Green/Blue/Black).
const SHARED_SIGHT_MAP := "mission23"
const SHARED_SIGHT_COLOR := "Blue"
## The final chapters go straight to the laboratory and the White Lords: the
## original clears all visibility there and freezes the fog.
const FROZEN_MAPS := ["mission171", "mission172", "mission271", "mission272"]
const TOMB_MAP := "mission24"
## Etherlords II: every hero and mob is created with base and effective sight
## 8 and nothing changes it, so the disc radius is 9.
const EL2_HERO_SIGHT := 8
## Relation bit that shares vision between two players.
const SHARED_VISION := 0x10
## Etherlords II scrying: a Lake adds the ReflectingEyes with byte-equal params.
const EL2_LAKE := "Lake"
const EL2_EYE := "ReflectingEye"
## Events after which a sight source may have moved, appeared or changed size.
const REFRESH_EVENTS := ["object_changed", "object_killed", "object_created", "hero_placed", "site_captured", "building_captured", "building_used",
	"castle_changed", "castle_assaulted", "player_eliminated", "camp_entered", "camp_left", "fort_entered", "fort_left", "fort_captured",
	"tomb_opened", "day_changed", "skill_learned", "global_spells_changed"]

static func applies(state: ELAdventureSession) -> bool:
	return state != null and state.map != null and state.map.profile != null and state.map.profile.id in ["el1", "el2"]

static func second(state: ELAdventureSession) -> bool:
	return state.map.profile.id == "el2"

## The player's own bit; the neutral player (0) and indices beyond a byte have none.
static func bit(player: int) -> int:
	return 1 << player if player >= 1 and player <= 7 else 0

static func allied(state: ELAdventureSession, first: int, other: int) -> bool:
	if first == other: return true
	# EL2 reads the raw relation byte: 239 is peaceful but shares nothing.
	if second(state): return (int(state.players.get(first, {}).get("relations", {}).get(other, 0)) & SHARED_VISION) != 0
	# EL1 shares vision through the third aspect of the relation in force.
	return ELDiplomacy.allied_in(state, first, other, ELDiplomacy.VISION)

## Players whose relation byte has bit 4 set (85 or 255) see what this one sees.
static func group_mask(state: ELAdventureSession, player: int) -> int:
	var mask := bit(player)
	if mask == 0: return 0
	for other: int in state.players:
		if other >= 1 and other != player and allied(state, player, other): mask |= bit(other)
	return mask

## Rebuilds the visible masks of every player and adds them to the explored
## masks. Runs at start and load (when the director assigns its grid) and after
## any event that moves or changes a sight source.
static func refresh(state: ELAdventureSession) -> void:
	if not applies(state) or state.grid == null or state.grid.map != state.map: return
	var width := state.map.width
	var size := width * state.map.height
	if state.explored.size() != size:
		state.explored.resize(size)
		state.explored.fill(0)
	var before := state.explored.duplicate()
	var seen := PackedByteArray()
	seen.resize(size)
	seen.fill(0)
	var el2 := second(state)
	if not el2 and state.map.id in FROZEN_MAPS:
		var changed_frozen: bool = state.fog.get("visible") != seen
		state.fog.visible = seen
		state.fog.revision = int(state.fog.get("revision", 0)) + (1 if changed_frozen else 0)
		return
	var masks := {}
	var everyone := 0
	for player: int in state.players:
		if player < 1: continue
		masks[player] = group_mask(state, player)
		everyone |= bit(player)
	if el2:
		#  refreshes each player P with P's group mask over the sources
		# of every member, so a source reveals to every group it belongs to
		# (relations may be one-sided).
		var reach := {}
		for owner: int in masks:
			var mask := 0
			for player: int in masks:
				if masks[player] & bit(owner): mask |= masks[player]
			reach[owner] = mask
		masks = reach
	for item: Dictionary in state.objects.values():
		var mask: int = masks.get(int(item.get("owner", -1)), 0)
		if mask == 0 or not item.get("alive", false): continue
		if source(state, item):
			if hero_sees(state, item): _disc(state, seen, mask, Vector2i(item.x, item.y), radius(state, item))
		elif ELFirstScenario.is_castle(item):
			# An authored <hidden/> castle stands off the map and reveals nothing.
			if item.get("visible", true) and state.grid.contains(Vector2i(item.x, item.y)): _rect(state, seen, mask, _bounds(state, item), CASTLE_RADIUS, true)
		elif item.get("group") == "mines":
			_rect(state, seen, mask, _bounds(state, item), MINE_RADIUS, true)
	if not el2 and state.map.id == SHARED_SIGHT_MAP:
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and int(item.get("owner", -1)) == 0 and item.get("alive", false) and hero_sees(state, item) \
				and str(state.map.profile.table("HeroTemplates").get(str(item.name), {}).get("Color", "")) == SHARED_SIGHT_COLOR: _disc(state, seen, everyone, Vector2i(item.x, item.y), sight_radius(item))
	# Crystal balls a Seer (EL2: eyes a Lake) has shown give their player's
	# vision group live sight.
	for player: int in masks:
		for id: Variant in state.players[player].get("scry", []):
			var bowl := state.object(int(id))
			if bowl.get("alive", false): _rect(state, seen, masks[player], _bounds(state, bowl), BOWL_RADIUS, true)
	# mission24: the tomb's surroundings stay unseen until it opens, then
	# every player sees them.
	if not el2 and state.map.id == TOMB_MAP:
		for item: Dictionary in state.objects.values():
			if item.get("name") == "AncientTomb": _rect(state, seen, everyone, _bounds(state, item), TOMB_RADIUS, bool(state.scenario.get("tomb_open", false)))
	if el2:
		# Closed Runestones keep their rectangles unseen for the local
		# player's group; observations are revealed afterwards.
		var local := group_mask(state, state.current_player)
		if local != 0:
			for item: Dictionary in state.objects.values():
				if not ELSecondGates.is_gate(item) or item.get("opened", false): continue
				for area: Rect2i in ELSecondGates.hide_rects(item): _hide(state, seen, local, area)
		# Script observations show every player a disc.
		for entry: Array in state.observations.values(): _disc(state, seen, everyone, Vector2i(int(entry[0]), int(entry[1])), int(entry[2]))
	var previous: Variant = state.fog.get("visible")
	var changed: bool = previous != seen or before != state.explored
	state.fog.visible = seen
	state.fog.revision = int(state.fog.get("revision", 0)) + (1 if changed else 0)

## The sight disc radius of a source actor in this edition.
static func radius(state: ELAdventureSession, hero: Dictionary) -> int:
	return EL2_HERO_SIGHT + 1 if second(state) else sight_radius(hero)

## Actors that carry sight: EL1 heroes; EL2 heroes and mobs (ships included).
static func source(state: ELAdventureSession, item: Dictionary) -> bool:
	return item.get("type") == "hero" or (second(state) and item.get("type") == "monster")

## EL1: a hero's sight is its recalculated maximum movement plus one, so Mobility,
## Wanderers' Citadels and Spring of Dexterity widen it. Remaining points do not.
static func sight_radius(hero: Dictionary) -> int:
	return int(hero.get("strategy_capacity", hero.get("base_ap", 0))) + 1

## Heroes in a fort keep their sight; a training-camp guest keeps its tile.
static func hero_sees(state: ELAdventureSession, hero: Dictionary) -> bool:
	if not (hero.get("visible", true) or int(hero.get("camp", -1)) >= 0): return false
	return state.grid.contains(Vector2i(hero.x, hero.y))

static func moved(state: ELAdventureSession, actor: Dictionary) -> void:
	if source(state, actor) and int(actor.get("owner", 0)) >= 1: refresh(state)

static func on_event(state: ELAdventureSession, data: Dictionary) -> void:
	if REFRESH_EVENTS.has(data.get("kind")): refresh(state)

## Increments whenever any explored or visible bit changes.
static func revision(state: ELAdventureSession) -> int:
	return int(state.fog.get("revision", 0))

## Whether the fog changes what this player sees at all.
static func active(state: ELAdventureSession, player: int) -> bool:
	return applies(state) and bit(player) != 0

static func explored(state: ELAdventureSession, player: int, point: Vector2i) -> bool:
	if not active(state, player): return true
	var index := _index(state, point)
	return index >= 0 and index < state.explored.size() and (state.explored[index] & bit(player)) != 0

static func visible(state: ELAdventureSession, player: int, point: Vector2i) -> bool:
	if not active(state, player): return true
	var index := _index(state, point)
	var seen: PackedByteArray = state.fog.get("visible", PackedByteArray())
	return index >= 0 and index < seen.size() and (seen[index] & bit(player)) != 0

static func tile_state(state: ELAdventureSession, player: int, point: Vector2i) -> int:
	if visible(state, player, point): return VISIBLE
	return REMEMBERED if explored(state, player, point) else UNEXPLORED

## An object is visible when any cell it covers is visible, remembered when any
## is explored, and unexplored otherwise.
static func object_state(state: ELAdventureSession, player: int, item: Dictionary, at := Vector2i(-1, -1)) -> int:
	if not active(state, player) or item.is_empty(): return VISIBLE
	var bounds := _bounds(state, item)
	if at.x >= 0: bounds.position = at
	var result := UNEXPLORED
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var tile := tile_state(state, player, Vector2i(x, y))
			if tile == VISIBLE: return VISIBLE
			result = maxi(result, tile)
	return result

## Heroes, monsters, castles and forts fade out of remembered fog; other
## objects stay drawn there, dimmed.
static func dynamic(item: Dictionary) -> bool:
	return item.get("type") in ["hero", "monster", "corpse", "fort"] or item.get("group") == "forts" or ELFirstScenario.is_castle(item)

static func shown(state: ELAdventureSession, player: int, item: Dictionary, at := Vector2i(-1, -1)) -> bool:
	var mode := object_state(state, player, item, at)
	return mode == VISIBLE or (mode == REMEMBERED and not dynamic(item))

static func _index(state: ELAdventureSession, point: Vector2i) -> int:
	if state.map == null or point.x < 0 or point.y < 0 or point.x >= state.map.width or point.y >= state.map.height: return -1
	return point.y * state.map.width + point.x

static func _bounds(state: ELAdventureSession, item: Dictionary) -> Rect2i:
	var origin := Vector2i(int(item.get("x", -1)), int(item.get("y", -1)))
	if item.get("type") in ["hero", "monster", "corpse"]: return Rect2i(origin, Vector2i.ONE)
	var size: Vector2i
	if state.grid != null and state.grid.footprints.has(int(item.get("uid", -1))): size = state.grid.footprints[int(item.uid)].size
	else:
		# A building created after the last grid rebuild.
		if not state.fog.has("art"): state.fog.art = ELAdventureArt.new(state.map)
		size = ELAdventureGrid.footprint(state.fog.art.resolve(item).get("row", {}), int(item.get("rotation", 0))).size
	return Rect2i(origin, size)

static func _disc(state: ELAdventureSession, seen: PackedByteArray, mask: int, center: Vector2i, radius: int) -> void:
	var width := state.map.width
	var limit := radius * radius
	for y in range(maxi(0, center.y - radius), mini(state.map.height - 1, center.y + radius) + 1):
		var span := limit - (y - center.y) * (y - center.y)
		var half := int(sqrt(float(span)))
		while (half + 1) * (half + 1) <= span: half += 1
		while half * half > span: half -= 1
		var row := y * width
		for x in range(maxi(0, center.x - half), mini(width - 1, center.x + half) + 1):
			seen[row + x] |= mask
			state.explored[row + x] |= mask

## A footprint grown by a radius with rounded corners: tiles whose squared
## distance to the footprint rectangle is at most radius². Hiding clears only
## the visible bits; the tiles stay explored.
static func _rect(state: ELAdventureSession, seen: PackedByteArray, mask: int, bounds: Rect2i, radius: int, reveal: bool) -> void:
	var width := state.map.width
	var last := bounds.end - Vector2i.ONE
	for y in range(maxi(0, bounds.position.y - radius), mini(state.map.height - 1, last.y + radius) + 1):
		var dy := maxi(0, maxi(bounds.position.y - y, y - last.y))
		for x in range(maxi(0, bounds.position.x - radius), mini(width - 1, last.x + radius) + 1):
			var dx := maxi(0, maxi(bounds.position.x - x, x - last.x))
			if dx * dx + dy * dy > radius * radius: continue
			var index := y * width + x
			if reveal:
				seen[index] |= mask
				state.explored[index] |= mask
			else: seen[index] &= ~mask

## Clears visible bits over an inclusive, already ordered tile rectangle,
## clamped to the map. The tiles stay explored.
static func _hide(state: ELAdventureSession, seen: PackedByteArray, mask: int, area: Rect2i) -> void:
	var width := state.map.width
	for y in range(maxi(0, area.position.y), mini(state.map.height - 1, area.end.y - 1) + 1):
		for x in range(maxi(0, area.position.x), mini(width - 1, area.end.x - 1) + 1): seen[y * width + x] &= ~mask

## ExHideExploration: every player's explored and visible bits are cleared;
## nothing is revealed again until the next refresh.
static func hide_exploration(state: ELAdventureSession) -> void:
	state.explored.fill(0)
	var seen: PackedByteArray = state.fog.get("visible", PackedByteArray())
	seen.fill(0)
	state.fog.visible = seen
	state.fog.revision = int(state.fog.get("revision", 0)) + 1

## EL2 Lake visit: the visitor's owner scries every ReflectingEye
## whose params equal the Lake's byte for byte, until the end of the turn.
static func scry(state: ELAdventureSession, hero: Dictionary, lake: Dictionary) -> Array:
	var owner := int(hero.get("owner", -1))
	if not state.players.has(owner): return []
	var own := str(ELXml.value(lake.get("node", {}), "params"))
	var listed: Array = state.players[owner].get("scry", [])
	var ids: Array = state.objects.keys()
	ids.sort()
	var added: Array = []
	for id: int in ids:
		var eye := state.object(id)
		if eye.get("group") == "additional_buildings" and eye.get("name") == EL2_EYE and str(ELXml.value(eye.get("node", {}), "params")) == own and not listed.has(id):
			listed.append(id)
			added.append(id)
	state.players[owner].scry = listed
	refresh(state)
	return added

## CCloseBowls at every EL2 end of turn: scry sets are emptied; the areas stay
## explored and the begin-of-turn recompute leaves them remembered.
static func close_eyes(state: ELAdventureSession) -> void:
	if not applies(state) or not second(state): return
	for player: int in state.players:
		if state.players[player].has("scry"): state.players[player].scry = []

## Checks each player's saved EL2 scry set: distinct, existing ReflectingEyes.
static func restore_eyes(state: ELAdventureSession) -> String:
	for player: int in state.players:
		var raw: Variant = state.players[player].get("scry")
		if raw == null: continue
		if not raw is Array or raw.size() > 1000: return "Invalid saved scried eyes."
		var clean: Array = []
		for id: Variant in raw:
			if not ELLuaSave._integer(id, 0, 0x7fffffff) or clean.has(int(id)) or state.object(int(id)).get("name") != EL2_EYE: return "Invalid saved scried eyes."
			clean.append(int(id))
		state.players[player].scry = clean
	return ""

## Whether the local player may target this tile (EL2 local orders:
## only a currently visible tile; the route itself may cross fog).
static func targetable(state: ELAdventureSession, player: int, point: Vector2i) -> bool:
	return not active(state, player) or visible(state, player, point)
