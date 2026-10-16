class_name ELSecondLoot
extends RefCounted
## Second game: resource trophies a beaten creature carries. A creature made
## from a map creature template rolls the template's <loot> list: each
## <s_loot res rmin rmax/> adds rmin plus a roll of 0..(rmax - rmin) to the
## resource with index res (Herbs, Gems, Flames). The winner's Search skill
## multiplies each total (truncating) and the winner's player is paid.
## The shipped chapters and the tutorial leave every template's list empty.

## The loser's map template (the chosen difficulty, else the first), or {}.
static func template(state: ELAdventureSession, item: Dictionary) -> Dictionary:
	if state == null or state.map == null or item.is_empty(): return {}
	var variants: Dictionary = state.map.mobs.get(str(item.get("name", "")), {})
	if variants.is_empty(): return {}
	return variants.get(state.difficulty, variants.get(0, variants.values()[0]))

## [resource index, minimum, maximum] per <s_loot>, in authored order.
static func entries(node: Dictionary) -> Array:
	var result: Array = []
	for item: Dictionary in ELXml.children(ELXml.child(node, "loot"), "s_loot"):
		var attrs: Dictionary = item.get("attrs", {})
		var values: Array[int] = []
		for key: String in ["res", "rmin", "rmax"]:
			var text := str(attrs.get(key, "0")).strip_edges()
			values.append(int(text) if text.is_valid_int() else 0)
		result.append(values)
	return result

## Totals per resource, in resource order, without empty totals. Each entry
## draws one number only when its range is not empty.
static func roll(list: Array, random: Callable) -> Array:
	var totals := [0, 0, 0]
	for entry: Array in list:
		var index := int(entry[0])
		var span := int(entry[2]) - int(entry[1]) + 1
		var amount := int(entry[1]) + (int(random.call()) % span if span != 0 else 0)
		# Indices outside the three resources are ignored.
		if index >= 0 and index < totals.size(): totals[index] += amount
	var result: Array = []
	for index in totals.size():
		if int(totals[index]) > 0: result.append([ELResources.SEQUEL[index], int(totals[index])])
	return result

## Rolls, scales and pays the loot of `loser` to `winner`'s player. Neutral
## winners take nothing; a loser without a template carries nothing.
static func take(state: ELAdventureSession, winner: Dictionary, loser: Dictionary) -> Array:
	if state == null or winner.is_empty() or loser.is_empty(): return []
	var owner := int(winner.get("owner", 0))
	if owner <= 0 or not state.players.has(owner): return []
	var node := template(state, loser)
	if node.is_empty(): return []
	var list := entries(node)
	if list.is_empty(): return []
	var draws := ELFirstMonsters.scale_loot(roll(list, func() -> int: return ELAdditionalBuildings._random(state)), winner)
	var reward := ELResources.empty("el2")
	var paid: Array = []
	for entry: Array in draws:
		if int(entry[1]) <= 0: continue
		reward[entry[0]] += int(entry[1])
		paid.append(entry)
	if not paid.is_empty(): state.change_resources(owner, reward)
	return paid

## The trophy lines under T_MB_LOOT_MONSTER_2: one resource and amount each,
## named as the map panel's resource tooltips name them.
static func lines(profile: ELProfile, draws: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in draws:
		if not entry is Array or entry.size() != 2: continue
		var kind := str(entry[0])
		var index := ELResources.SEQUEL.find(kind)
		var name := profile.text("CtrlTTAdvPanelRes%dTT" % (index + 1)).strip_edges() if profile != null and index >= 0 else ""
		if name.is_empty() or name.begins_with("CtrlTT"): name = str(ELResources.LABELS.get(kind, kind))
		result.append("%s: %d" % [name, int(entry[1])])
	return result

## Saved trophy lists: [resource, positive amount] pairs only.
static func valid(list: Variant) -> bool:
	if not list is Array: return false
	for entry: Variant in list:
		if not entry is Array or entry.size() != 2 or str(entry[0]) not in ELResources.SEQUEL: return false
		var amount: Variant = entry[1]
		if not (amount is int or (amount is float and amount == floorf(amount))) or amount < 1 or amount > ELResources.MAX_AMOUNT: return false
	return true
