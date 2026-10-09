class_name ELResourceSites
extends RefCounted
## Resource production is separate from movement, combat and turn scheduling.
const TYPES := {"mines": "resource_mine", "mana_nodes": "mana_node"}
const PAYMENTS := 10

static func definition(profile: ELProfile, site: Dictionary) -> Dictionary:
	if site.get("group") == "mana_nodes":
		return profile.table("ManaNodes").get("ManaNode." + ELXml.value(site.node, "color"), {})
	if site.get("group") == "mines":
		for row: Dictionary in profile.table("ResourceMine").values():
			if row.get("Name") == site.get("name") and int(row.get("Level", -1)) == int(site.get("level", -1)): return row
	return {}

static func initialize(profile: ELProfile, site: Dictionary) -> void:
	site.type = TYPES.get(site.group, "object")
	site.level = int(ELXml.value(site.node, "level", "0"))
	site.owner = -1
	site.site_version = 1
	if profile.id == "el2" and site.group == "mines": site.mine_remaining = PAYMENTS

static func restore(profile: ELProfile, site: Dictionary) -> bool:
	if not site.has("site_version"): initialize(profile, site)
	if not ELLuaSave._integer(site.site_version, 1, 1) or not ELLuaSave._integer(site.owner, -1, 32): return false
	if not TYPES.has(site.group) or definition(profile, site).is_empty(): return false
	if site.group == "mana_nodes" and site.level != 0: return false
	site.type = TYPES[site.group]
	if profile.id == "el2" and site.group == "mines":
		if not ELLuaSave._integer(site.get("mine_remaining"), 0, PAYMENTS): return false
		site.mine_remaining = int(site.mine_remaining)
	return true

static func title(profile: ELProfile, site: Dictionary) -> String:
	var row := definition(profile, site)
	return profile.text(str(row.get("ELKName", row.get("Name", site.get("name", "Resource site")))))

static func _vector(edition: String, entries: Variant) -> Dictionary:
	var result := ELResources.empty(edition)
	if entries is String: entries = [entries]
	for entry: String in entries:
		var kind := entry.get_slice("(", 0)
		if edition == "el2": kind = str(ELResources.SEQUEL_FIELDS.find_key(kind))
		if result.has(kind): result[kind] += maxi(0, int(entry.get_slice("(", 1).trim_suffix(")")))
	return result

static func production(profile: ELProfile, site: Dictionary) -> Dictionary:
	var result := ELResources.empty(profile.id)
	if site.get("group") != "mines": return result
	if profile.id == "el2":
		if int(site.get("mine_remaining", 0)) <= 0: return result
		var authored := ELXml.child(site.node, "resources")
		# An explicitly authored vector is a ten-payment total. An empty vector
		# falls back to the registry's per-payment amount, without scaling it.
		if not ELXml.children(authored, "resource").is_empty():
			result = ELResources.read_node(profile.id, authored)
			for kind: String in result: result[kind] = installment(int(result[kind]))
			return result
	return _vector(profile.id, definition(profile, site).get("Production", []))

static func installment(amount: int) -> int:
	# The original rounds the input to a float, multiplies by float(0.1),
	# then truncates. Use that arithmetic even for large authored amounts.
	return int(float(PackedFloat32Array([amount])[0]) * float(PackedFloat32Array([0.1])[0]))

static func mana_production(site: Dictionary, color: String) -> int:
	return (30 if ELXml.value(site.node, "color") == color else 15) if site.get("group") == "mana_nodes" else 0

static func income(state: ELAdventureSession, player: int) -> Dictionary:
	var result := ELResources.empty(state.map.profile.id)
	for site: Dictionary in state.objects.values():
		if site.get("group") != "mines" or not site.alive or site.owner != player: continue
		var amounts := production(state.map.profile, site)
		for kind: String in result: result[kind] = mini(ELResources.MAX_AMOUNT, int(result[kind]) + int(amounts[kind]))
	return result

static func mana_income(state: ELAdventureSession, player: int) -> int:
	var result := 0
	var color: String = state.players.get(player, {}).get("color", "")
	for site: Dictionary in state.objects.values():
		if not site.alive or site.owner != player: continue
		if site.get("group") == "mana_nodes": result += mana_production(site, color)
		elif site.get("group") == "buildings" and site.name == "MainTower": result += int(site.node.get("attrs", {}).get("mana_income", 6))
	if state.map.profile.id == "el1": result = ELAdditionalBuildings.shrine_income(result, ELAdditionalBuildings.owned(state, player, "ShrineMagic"))
	return result

static func visit_problem(state: ELAdventureSession, hero_id: int, site_id: int, nearby := true, local_player := true) -> String:
	var hero := state.object(hero_id)
	var site := state.object(site_id)
	if hero.is_empty() or hero.type != "hero" or not hero.alive or not hero.visible or not hero.enabled or (local_player and hero.owner != state.current_player) or not state.players.has(hero.owner): return "This hero cannot capture a resource site."
	if site.is_empty() or not TYPES.has(site.group) or not site.alive or not site.visible or not site.enabled: return "This resource site is unavailable."
	var row := definition(state.map.profile, site)
	if row.is_empty(): return "This resource site has no production definition."
	var size: Vector2i = ELAdventureGrid.footprint(row, int(site.rotation)).size
	if nearby and not Rect2i(int(site.x) - 1, int(site.y) - 1, size.x + 2, size.y + 2).has_point(Vector2i(hero.x, hero.y)): return "Move next to this resource site first."
	return ""

static func capture(state: ELAdventureSession, hero_id: int, site_id: int, local_player := true) -> bool:
	if not visit_problem(state, hero_id, site_id, true, local_player).is_empty(): return false
	var site := state.object(site_id)
	var owner: int = state.object(hero_id).owner
	if site.owner == owner: return true
	var previous: int = site.owner
	site.owner = owner
	state.event.emit({"kind": "site_captured", "id": site_id, "player": owner, "previous": previous})
	return true

static func upgrade_price(profile: ELProfile, site: Dictionary) -> Dictionary:
	return _vector(profile.id, definition(profile, site).get("UpgradeCost", []))

static func upgrade_problem(state: ELAdventureSession, hero_id: int, site_id: int) -> String:
	if state.map.profile.id != "el1": return "This mine cannot be upgraded."
	var problem := visit_problem(state, hero_id, site_id, false)
	if not problem.is_empty(): return problem
	var site := state.object(site_id)
	if site.group != "mines": return "Mana nodes cannot be upgraded."
	if site.owner != state.object(hero_id).owner: return "Capture this mine before upgrading."
	if site.level >= 2: return "This mine is fully upgraded."
	var next := site.duplicate()
	next.level += 1
	if definition(state.map.profile, next).is_empty() or not definition(state.map.profile, site).has("UpgradeCost"): return "No further upgrade is available."
	if not ELResources.can_pay("el1", state.players[site.owner].resources, upgrade_price(state.map.profile, site)): return "Not enough resources to upgrade this mine."
	return ""

static func upgrade(state: ELAdventureSession, hero_id: int, site_id: int) -> bool:
	if not upgrade_problem(state, hero_id, site_id).is_empty(): return false
	var site := state.object(site_id)
	if not ELResources.pay("el1", state.players[site.owner].resources, upgrade_price(state.map.profile, site)): return false
	site.level += 1
	state.event.emit({"kind": "resources_changed", "player": site.owner})
	state.event.emit({"kind": "object_changed", "id": site_id})
	return true

static func settle_income(state: ELAdventureSession, completed_day := false) -> bool:
	# A completed travel day always pays, even when a script rewound its date.
	# Other callers cannot replay a settlement for an already resolved date.
	if not completed_day and state.income_day >= state.day: return false
	state.income_day = state.day
	var rewards := {}
	var expired: Array[int] = []
	for site: Dictionary in state.objects.values():
		if site.get("group") != "mines" or not site.alive or not state.players.has(site.owner): continue
		if not rewards.has(site.owner): rewards[site.owner] = ELResources.empty(state.map.profile.id)
		var amounts := production(state.map.profile, site)
		for kind: String in amounts: rewards[site.owner][kind] = mini(ELResources.MAX_AMOUNT, int(rewards[site.owner][kind]) + int(amounts[kind]))
		if state.map.profile.id == "el2" and site.mine_remaining > 0:
			site.mine_remaining -= 1
			if site.mine_remaining == 0: expired.append(site.uid)
	for player: int in rewards:
		state.change_resources(player, rewards[player])
		state.event.emit({"kind": "site_income", "player": player, "amounts": rewards[player]})
	for id: int in expired: state.event.emit({"kind": "mine_depleted", "id": id})
	return true
