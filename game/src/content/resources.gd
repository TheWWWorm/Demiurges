class_name ELResources
extends RefCounted
## Edition-specific resource vectors, shared by rewards, collection and payment.
const ORIGINAL := ["Root", "Lotus", "Ruby", "Emerald", "Sapphire", "Diamond", "Stone"]
const SEQUEL := ["Herbs", "Gems", "Flames"]
const SEQUEL_FIELDS := {"Herbs": "Root", "Gems": "Ruby", "Flames": "Stone"}
const LABELS := {"Root": "Roots", "Lotus": "Lotus", "Ruby": "Rubies", "Emerald": "Emeralds", "Sapphire": "Sapphires", "Diamond": "Diamonds", "Stone": "Frozen flames", "Herbs": "Herbs", "Gems": "Gems", "Flames": "Frozen flames"}
const MAX_AMOUNT := 0x7fffffff

static func types(edition: String) -> Array:
	return SEQUEL if edition == "el2" else ORIGINAL

static func empty(edition: String) -> Dictionary:
	var result := {}
	for kind: String in types(edition): result[kind] = 0
	return result

static func read_node(edition: String, node: Dictionary) -> Dictionary:
	var result := empty(edition)
	# Starting balances use attributes; pickups use <resource> child records.
	for kind: String in result:
		if node.get("attrs", {}).has(kind): result[kind] = clampi(int(node.attrs[kind]), 0, MAX_AMOUNT)
	for item: Dictionary in ELXml.children(node, "resource"):
		var kind := String(item.attrs.get("type", ""))
		if result.has(kind): result[kind] = clampi(int(item.attrs.get("amount", 0)), 0, MAX_AMOUNT)
	return result

static func spell_price(profile: ELProfile, card: String) -> Dictionary:
	var result := empty(profile.id)
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	for kind: String in result:
		var field := String(SEQUEL_FIELDS[kind]) if profile.id == "el2" else kind
		result[kind] = maxi(0, int(row.get("Cost" + field, 0)))
	return result

static func bargain_price(amount: float, rank: int) -> int:
	if amount <= 0: return 0
	var result := int(amount * [1.0, 0.8, 0.55, 0.3][rank + 1] + 0.5)
	# Extended arithmetic keeps binary 0.3 below 3/10 at exact half ties.
	if rank == 2 and amount == floor(amount) and int(amount) % 10 == 5: result -= 1
	return maxi(1, result)

static func valid(edition: String, value: Variant) -> bool:
	if value is not Dictionary: return false
	for kind: Variant in value:
		if kind not in types(edition) or typeof(value[kind]) not in [TYPE_INT, TYPE_FLOAT]: return false
		var number := float(value[kind])
		if not is_finite(number) or number != floor(number) or number < 0 or number > MAX_AMOUNT: return false
	return true

static func can_pay(edition: String, wallet: Dictionary, price: Dictionary) -> bool:
	if not valid(edition, wallet) or not valid(edition, price): return false
	for kind: String in price:
		if int(wallet.get(kind, 0)) < int(price[kind]): return false
	return true

static func pay(edition: String, wallet: Dictionary, price: Dictionary) -> bool:
	if not can_pay(edition, wallet, price): return false
	for kind: String in price: wallet[kind] = int(wallet.get(kind, 0)) - int(price[kind])
	return true

static func change(edition: String, wallet: Dictionary, delta: Dictionary) -> bool:
	if not valid(edition, wallet): return false
	for kind: Variant in delta:
		if kind not in types(edition) or typeof(delta[kind]) not in [TYPE_INT, TYPE_FLOAT]: return false
		var number := float(delta[kind])
		if not is_finite(number) or number != floor(number) or absf(number) > MAX_AMOUNT: return false
	# Script deductions saturate each component at zero; purchases use pay().
	for kind: String in delta: wallet[kind] = clampi(int(wallet.get(kind, 0)) + int(delta[kind]), 0, MAX_AMOUNT)
	return true

static func describe(edition: String, value: Dictionary, include_zero := true) -> String:
	var parts: Array[String] = []
	for kind: String in types(edition):
		var amount := int(value.get(kind, 0))
		if include_zero or amount != 0: parts.append("%s: %d" % [LABELS[kind], amount])
	return "  ·  ".join(parts)
