class_name ELAutochessCompany
extends RefCounted
## One player's company: ether, level, shop, army, reserves and artifacts.
## The human, the computer players and online guests all use these same
## operations (ported from the Cursed Lands autochess run).

signal changed

var profile: ELProfile
var character := ""
var run_seed := 1
var round_number := 1
var ether := ELAutochessRules.OPENING_ETHER
var health := ELAutochessRules.START_HEALTH
var stage := "prepare"
var army: Array[Dictionary] = []
var shop: Array[Dictionary] = []
var items: Array[Dictionary] = []
var item_offers: Array[String] = []
var next_item_uid := 1
var item_reward_round := 0
var training := 0
var battle_savings := 0
var history: Array[Dictionary] = []
var last_result := {}
var next_uid := 1
var rng := RandomNumberGenerator.new()
var last_evolutions: Array[int] = []
## Every company of a match recruits from one pool (set by the match).
var pool_companies: Callable
var _undo: Array[Dictionary] = []

func begin(data: ELProfile, seed_value: int, who: String) -> void:
	profile = data
	run_seed = maxi(1, seed_value)
	character = who
	round_number = 1
	ether = ELAutochessRules.OPENING_ETHER
	health = ELAutochessRules.START_HEALTH
	stage = "prepare"
	army.clear(); shop.clear(); items.clear(); item_offers.clear(); history.clear(); _undo.clear()
	next_item_uid = 1; item_reward_round = 0; training = 0; battle_savings = 0; next_uid = 1
	last_result = {}
	rng.seed = run_seed
	# Six different opening offers with both melee and ranged choices.
	var lines := ELAutochessRules.recruit_pool(capacity())
	for i in range(lines.size() - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var held: int = lines[i]
		lines[i] = lines[other]
		lines[other] = held
	var opening: Array[int] = lines.slice(0, 6)
	if not opening.any(func(f: int) -> bool: return ELAutochessRules.FAMILIES[f].role == "Ranged"):
		var ranged := lines.filter(func(f: int) -> bool: return ELAutochessRules.FAMILIES[f].role == "Ranged")
		if not ranged.is_empty(): opening[5] = ranged[0]
	for index in opening: shop.append({"family": index, "rank": 0, "locked": false})
	_touch()

func capacity() -> int:
	return ELAutochessRules.level_for_xp(experience())

func experience() -> int:
	return mini(ELAutochessRules.MAX_TRAINING, round_number - 1 + training)

func level_progress() -> int:
	return experience() - int(ELAutochessRules.LEVEL_XP[capacity()])

func level_needed() -> int:
	if capacity() == ELAutochessRules.MAX_ARMY: return 0
	return int(ELAutochessRules.LEVEL_XP[capacity() + 1]) - int(ELAutochessRules.LEVEL_XP[capacity()])

func can_shop() -> bool:
	return health > 0 and stage in ["prepare", "fight", "result"]

func train() -> String:
	if not can_shop(): return "Wait for the next round."
	if experience() >= ELAutochessRules.MAX_TRAINING: return "Your army is at full strength."
	var error := spending_error(ELAutochessRules.TRAINING_COST)
	if not error.is_empty(): return error
	_checkpoint()
	ether -= ELAutochessRules.TRAINING_COST
	training += mini(ELAutochessRules.TRAINING_XP, ELAutochessRules.MAX_TRAINING - experience())
	_touch()
	return ""

func win_streak() -> int:
	var wins := 0
	for i in range(history.size() - 1, -1, -1):
		if int(history[i].winner) != 0: break
		wins += 1
	return wins

## Base income and interest every round; victory and streak need a win.
func income_preview(savings := -1, won := true) -> Dictionary:
	var bank := ether if savings < 0 else savings
	var streak := win_streak() + 1
	var bonus := (2 if streak >= 6 else 1 if streak >= 3 else 0) if won else 0
	var interest := mini(ELAutochessRules.INTEREST_CAP, maxi(0, bank) / 10)
	var victory := ELAutochessRules.WIN_INCOME if won else 0
	return {"base": ELAutochessRules.BASE_INCOME, "victory": victory, "interest": interest, "streak": bonus,
		"total": ELAutochessRules.BASE_INCOME + victory + interest + bonus}

func deployed_count() -> int:
	return army.filter(func(u: Dictionary) -> bool: return u.deployed).size()

func bench_count() -> int:
	return army.size() - deployed_count()

func bench_limit() -> int:
	return ELAutochessRules.BENCH_LIMIT

## Reserve slots keep their places through purchases, swaps and saves.
func reserve_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	slots.resize(maxi(bench_limit(), bench_count()))
	var unplaced: Array[Dictionary] = []
	for entry in army:
		if entry.deployed: continue
		var slot := int(entry.get("bench_slot", -1))
		if slot >= 0 and slot < slots.size() and slots[slot].is_empty(): slots[slot] = entry
		else: unplaced.append(entry)
	for entry in unplaced:
		for slot in slots.size():
			if not slots[slot].is_empty(): continue
			entry.bench_slot = slot
			slots[slot] = entry
			break
	return slots

func alliances() -> Dictionary:
	return ELAutochessAlliances.counts(profile, army)

func unit(uid: int) -> Dictionary:
	for entry: Dictionary in army:
		if int(entry.uid) == uid: return entry
	return {}

func offer_cost(offer: Dictionary) -> int:
	return ELAutochessRules.tier(int(offer.family)) * ELAutochessRules.rank_copies(int(offer.family), int(offer.get("rank", 0)))

func refresh_cost() -> int:
	return ELAutochessRules.REFRESH_COST

func spending_error(cost: int) -> String:
	if ether < cost: return "Not enough ether."
	if army.is_empty() and ether - cost < ELAutochessRules.MIN_RECRUIT_COST:
		return "Recruit a creature before spending the rest of your ether."
	return ""

## An offer that would complete an upgrade with owned and offered copies.
func shop_completes_upgrade(index: int) -> bool:
	if index < 0 or index >= shop.size() or int(shop[index].family) < 0: return false
	var line := int(shop[index].family)
	var rank := int(shop[index].get("rank", 0))
	if ELAutochessRules.evolution_copies(line, rank) == 0: return false
	var owned := army.filter(func(e: Dictionary) -> bool: return int(e.family) == line and int(e.rank) == rank).size()
	var offered := shop.filter(func(o: Dictionary) -> bool: return int(o.family) == line and int(o.get("rank", 0)) == rank).size()
	return owned + offered >= ELAutochessRules.evolution_copies(line, rank)

func owned_counts(line: int) -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for entry: Dictionary in army:
		if int(entry.family) == line: counts[int(entry.rank)] += 1
	return counts

func purchase_error(index: int) -> String:
	if not can_shop(): return "Wait for the next round."
	if index < 0 or index >= shop.size() or int(shop[index].family) < 0: return "This offer has already been recruited."
	var line := int(shop[index].family)
	var rank := int(shop[index].get("rank", 0))
	if ether < offer_cost(shop[index]): return "Not enough ether."
	var matching := army.filter(func(e: Dictionary) -> bool: return int(e.family) == line and int(e.rank) == rank).size()
	var needed := ELAutochessRules.evolution_copies(line, rank)
	if bench_count() >= bench_limit() and (needed == 0 or matching + 1 < needed) and recruit_point(line) == Vector2.INF:
		return "Reserves full. Deploy or sell a creature first."
	return ""

func buy(index: int) -> String:
	var error := purchase_error(index)
	if not error.is_empty(): return error
	var line := int(shop[index].family)
	var rank := int(shop[index].get("rank", 0))
	var cost := offer_cost(shop[index])
	_checkpoint()
	ether -= cost
	var recruit := _recruit(line, rank, cost)
	shop[index] = {"family": -1, "rank": 0, "locked": false}
	combine_ready()
	if not unit(int(recruit.uid)).is_empty(): _auto_deploy(recruit)
	else:
		for uid in last_evolutions:
			var evolved := unit(uid)
			if not evolved.is_empty(): _auto_deploy(evolved)
	_touch()
	return ""

func _recruit(line: int, rank: int, investment: int) -> Dictionary:
	var entry := {"uid": next_uid, "family": line, "rank": rank, "code": ELAutochessRules.form(line, rank),
		"investment": investment, "deployed": false, "point": [-6.0, 0.0]}
	next_uid += 1
	army.append(entry)
	return entry

## A free deployment point: ranged lines behind, melee lines in front.
func recruit_point(line: int) -> Vector2:
	if stage != "prepare" or deployed_count() >= capacity(): return Vector2.INF
	var ranged := String(ELAutochessRules.family(line).get("role", "Melee")) == "Ranged"
	for x: float in ([-11.0, -8.5, -6.0] if ranged else [-5.0, -7.5, -10.0]):
		for y: float in [0.0, -3.0, 3.0, -6.0, 6.0, -8.5, 8.5]:
			var point := Vector2(x, y)
			if spacing_error(-1, point).is_empty(): return point
	return Vector2.INF

func _auto_deploy(entry: Dictionary) -> void:
	if entry.deployed: return
	var point := recruit_point(int(entry.family))
	if point == Vector2.INF: return
	entry.deployed = true
	entry.point = [point.x, point.y]

## Three copies of a form combine into the next star, keeping a deployed
## copy's place. A purchase and its evolutions are one undo step.
func combine_ready() -> void:
	last_evolutions.clear()
	if not can_shop(): return
	for line in ELAutochessRules.FAMILIES.size():
		for rank in 2:
			while true:
				var matching := army.filter(func(e: Dictionary) -> bool: return int(e.family) == line and int(e.rank) == rank)
				if matching.size() < 3: break
				# Combat purchases do not change the fighting army.
				if stage == "fight" and matching.any(func(e: Dictionary) -> bool: return e.deployed): break
				var kept: Dictionary = matching[0]
				for entry: Dictionary in matching:
					if entry.deployed:
						kept = entry
						break
				_merge(kept)
				last_evolutions.append(int(kept.uid))

func _merge(entry: Dictionary) -> void:
	var consumed := 0
	for other: Dictionary in army.duplicate():
		if other.uid == entry.uid or int(other.family) != int(entry.family) or int(other.rank) != int(entry.rank): continue
		entry.investment = int(entry.investment) + int(other.investment)
		_return_item(int(other.uid))
		army.erase(other)
		consumed += 1
		if consumed == 2: break
	entry.rank = int(entry.rank) + 1
	entry.code = ELAutochessRules.form(int(entry.family), int(entry.rank))

func refresh() -> String:
	if not can_shop(): return "Wait for the next round."
	if not shop.is_empty() and shop.all(func(o: Dictionary) -> bool: return o.locked): return "Unlock an offer before refreshing."
	var error := spending_error(refresh_cost())
	if not error.is_empty(): return error
	ether -= refresh_cost()
	_undo.clear()
	roll_shop(true)
	_touch()
	return ""

func lock_offer(index: int) -> void:
	if not can_shop() or index < 0 or index >= shop.size() or int(shop[index].family) < 0: return
	shop[index].locked = not bool(shop[index].locked)
	_touch()

func roll_shop(keep_lock: bool) -> void:
	var old := shop.duplicate(true)
	var slots := ELAutochessRules.SHOP_SLOTS
	if keep_lock and old.size() > slots:
		for index in range(slots, old.size()):
			if old[index].locked: slots = index + 1
	shop.clear()
	var open: Array[int] = []
	for i in slots:
		if keep_lock and i < old.size() and old[i].locked and int(old[i].family) >= 0: shop.append(old[i])
		else:
			shop.append({"family": -1, "rank": 0, "locked": false})
			open.append(i)
	var left := pool_left()
	var odds: Array = ELAutochessRules.SHOP_ODDS[capacity()]
	for i in open:
		var roll := rng.randi_range(0, 99)
		var t := 1
		for weight: int in odds:
			if roll < weight: break
			roll -= weight
			t += 1
		var line := _draw(t, left)
		if line < 0: continue
		shop[i] = {"family": line, "rank": 0, "locked": false}
		if left.has(line): left[line] = int(left[line]) - 1
	# An empty company can always recruit again.
	if army.is_empty() and not shop.any(func(o: Dictionary) -> bool: return int(o.family) >= 0 and offer_cost(o) <= ELAutochessRules.MIN_RECRUIT_COST):
		for i in shop.size():
			if shop[i].locked: continue
			var cheap := ELAutochessRules.recruit_pool(capacity()).filter(func(f: int) -> bool: return ELAutochessRules.tier(f) <= ELAutochessRules.MIN_RECRUIT_COST and (left.is_empty() or int(left.get(f, 0)) > 0))
			if cheap.is_empty(): break
			shop[i] = {"family": cheap[rng.randi_range(0, cheap.size() - 1)], "rank": 0, "locked": false}
			break

## One ticket per remaining pool copy; an empty tier falls back to the
## nearest lower, then higher, tier.
func _draw(t: int, left: Dictionary) -> int:
	if left.is_empty():
		var candidates: Array[int] = []
		for line in ELAutochessRules.FAMILIES.size():
			if ELAutochessRules.tier(line) == t: candidates.append(line)
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var order: Array[int] = []
	for x in range(t, 0, -1): order.append(x)
	for x in range(t + 1, ELAutochessRules.POOL_COPIES.size() + 1): order.append(x)
	for x in order:
		var total := 0
		for line in ELAutochessRules.FAMILIES.size():
			if ELAutochessRules.tier(line) == x: total += maxi(0, int(left.get(line, 0)))
		if total == 0: continue
		var ticket := rng.randi_range(0, total - 1)
		for line in ELAutochessRules.FAMILIES.size():
			if ELAutochessRules.tier(line) != x: continue
			ticket -= maxi(0, int(left.get(line, 0)))
			if ticket < 0: return line
	return -1

func pool_left() -> Dictionary:
	if not pool_companies.is_valid(): return {}
	var left := {}
	for line in ELAutochessRules.FAMILIES.size(): left[line] = ELAutochessRules.pool_size(line)
	for company: ELAutochessCompany in pool_companies.call():
		for entry: Dictionary in company.army:
			var line := int(entry.family)
			if left.has(line): left[line] = int(left[line]) - ELAutochessRules.rank_copies(line, int(entry.rank))
		for offer: Dictionary in company.shop:
			var line := int(offer.family)
			if left.has(line): left[line] = int(left[line]) - ELAutochessRules.rank_copies(line, int(offer.get("rank", 0)))
	return left

func spacing_error(uid: int, point: Vector2) -> String:
	for other: Dictionary in army:
		if int(other.uid) == uid or not other.deployed: continue
		if point.distance_to(Vector2(float(other.point[0]), float(other.point[1]))) < ELAutochessRules.DEPLOY_SPACING:
			return "Leave more space between creatures."
	return ""

func deploy(uid: int, point: Vector2) -> String:
	if stage != "prepare": return "Arrange your army between battles."
	var entry := unit(uid)
	if entry.is_empty(): return "Choose a creature from your army."
	if not is_finite(point.x) or not is_finite(point.y) or not ELAutochessRules.DEPLOY.has_point(point):
		return "Deploy inside your half of the battlefield."
	if not entry.deployed and deployed_count() >= capacity(): return "Army full. Level up or withdraw a creature."
	var spacing := spacing_error(uid, point)
	if not spacing.is_empty(): return spacing
	_checkpoint()
	entry.deployed = true
	entry.point = [point.x, point.y]
	_touch()
	return ""

func bench(uid: int, slot := -1) -> String:
	if not can_shop(): return "Wait for the next round."
	var entry := unit(uid)
	if entry.is_empty(): return "Choose a creature from your army."
	if not entry.deployed:
		var reserves := reserve_slots()
		if slot == -1 or slot == int(entry.get("bench_slot", -1)): return ""
		if slot < 0 or slot >= bench_limit(): return "Choose a reserve slot."
		_checkpoint()
		if not reserves[slot].is_empty(): reserves[slot].bench_slot = entry.get("bench_slot", -1)
		entry.bench_slot = slot
		_touch()
		return ""
	if stage != "prepare": return "Arrange your army between battles."
	if bench_count() >= bench_limit(): return "Reserves full. Deploy, evolve or sell a creature first."
	var slots := reserve_slots()
	if slot < 0:
		for index in slots.size():
			if slots[index].is_empty():
				slot = index
				break
	if slot < 0 or slot >= bench_limit() or not slots[slot].is_empty(): return "Choose an empty reserve slot."
	_checkpoint()
	entry.deployed = false
	entry.bench_slot = slot
	_touch()
	return ""

func swap_from_bench(uid: int, deployed_uid: int) -> String:
	if stage != "prepare": return "Arrange your army between battles."
	var incoming := unit(uid)
	var outgoing := unit(deployed_uid)
	if incoming.is_empty() or outgoing.is_empty() or incoming.deployed or not outgoing.deployed:
		return "Select a reserve, then one of your deployed creatures to swap them."
	reserve_slots()
	_checkpoint()
	outgoing.bench_slot = incoming.get("bench_slot", -1)
	incoming.deployed = true
	incoming.point = outgoing.point.duplicate()
	outgoing.deployed = false
	_touch()
	return ""

func sell(uid: int) -> String:
	if not can_shop(): return "Wait for the next round."
	var entry := unit(uid)
	if entry.is_empty(): return "Choose a creature from your army."
	if stage != "prepare" and entry.deployed: return "Only reserves can be sold during battle."
	_checkpoint()
	ether += sale_value(entry)
	_return_item(uid)
	army.erase(entry)
	_touch()
	return ""

func sale_value(entry: Dictionary) -> int:
	if int(entry.rank) == 0: return int(entry.investment)
	return mini(offer_cost(entry), int(entry.investment) * 2 / 3)

func item_for(unit_uid: int) -> String:
	if unit_uid <= 0: return ""
	for item: Dictionary in items:
		if int(item.unit_uid) == unit_uid: return String(item.kind)
	return ""

func equip_item(item_uid: int, unit_uid: int) -> String:
	if stage != "prepare": return "Change artifacts between battles."
	var selected := {}
	for item: Dictionary in items:
		if int(item.uid) == item_uid:
			selected = item
			break
	if selected.is_empty(): return "Choose an artifact."
	if unit_uid < 0 or (unit_uid > 0 and unit(unit_uid).is_empty()): return "Choose a creature from your army."
	if int(selected.unit_uid) == unit_uid: return ""
	_checkpoint()
	if unit_uid > 0: _return_item(unit_uid)
	selected.unit_uid = unit_uid
	_touch()
	return ""

func choose_item(index: int) -> String:
	if stage != "prepare": return "Choose artifacts between battles."
	if index < 0 or index >= item_offers.size(): return "Choose one of the offered artifacts."
	_checkpoint()
	_claim_item(index)
	_touch()
	return ""

func _claim_item(index: int) -> void:
	if items.size() < ELAutochessArtifacts.MAX_ITEMS:
		items.append({"uid": next_item_uid, "kind": item_offers[index], "unit_uid": 0})
		next_item_uid += 1
	item_offers.clear()

func offer_items_after(completed_round: int) -> void:
	if completed_round <= item_reward_round or not ELAutochessArtifacts.reward_round(completed_round): return
	if not item_offers.is_empty(): _claim_item(0)
	item_reward_round = completed_round
	item_offers = ELAutochessArtifacts.offers(run_seed, completed_round)

func settle_item_choice() -> void:
	if not item_offers.is_empty(): _claim_item(0)

func _return_item(unit_uid: int) -> void:
	for item: Dictionary in items:
		if int(item.unit_uid) == unit_uid: item.unit_uid = 0

func _sync_items() -> void:
	for entry: Dictionary in army:
		var kind := item_for(int(entry.uid))
		if kind.is_empty(): entry.erase("item")
		else: entry["item"] = kind

## Fills the army automatically: strongest first, melee in front.
func arrange() -> void:
	if stage != "prepare": return
	_checkpoint()
	var ordered := army.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va := ELAutochessRules.tier(int(a.family)) * 3 + int(a.rank) * 4
		var vb := ELAutochessRules.tier(int(b.family)) * 3 + int(b.rank) * 4
		return va > vb if va != vb else int(a.uid) < int(b.uid))
	for entry: Dictionary in army: entry.deployed = false
	var front := 0
	var back := 0
	for i in mini(capacity(), ordered.size()):
		var entry: Dictionary = ordered[i]
		var ranged := String(ELAutochessRules.family(int(entry.family)).get("role", "Melee")) == "Ranged"
		var number := back if ranged else front
		entry.deployed = true
		entry.point = [(-10.5 if ranged else -5.0) - (2.5 if number >= 5 else 0.0), [0.0, -3.5, 3.5, -7.0, 7.0][number % 5]]
		if ranged: back += 1
		else: front += 1
	_touch()

func start_battle() -> void:
	settle_item_choice()
	battle_savings = ether
	stage = "fight"
	_undo.clear()
	_touch()

func formation(team: int) -> Array[Dictionary]:
	_sync_items()
	return ELAutochessRules.formation(army, team)

func next_round(number: int) -> void:
	round_number = number
	stage = "prepare"
	_undo.clear()
	roll_shop(true)
	_touch()

func _checkpoint() -> void:
	if stage != "prepare": return
	_undo.append({"army": army.duplicate(true), "shop": shop.duplicate(true), "ether": ether, "next_uid": next_uid, "training": training,
		"items": items.duplicate(true), "item_offers": item_offers.duplicate(), "next_item_uid": next_item_uid})
	if _undo.size() > 30: _undo.pop_front()

func undo() -> void:
	if stage != "prepare" or _undo.is_empty(): return
	var previous: Dictionary = _undo.pop_back()
	army.assign(previous.army); shop.assign(previous.shop)
	ether = int(previous.ether); next_uid = int(previous.next_uid); training = int(previous.training)
	items.assign(previous.items); item_offers.assign(previous.item_offers); next_item_uid = int(previous.next_item_uid)
	_touch()

func can_undo() -> bool:
	return stage == "prepare" and not _undo.is_empty()

func clear_undo() -> void:
	_undo.clear()

func snapshot() -> Dictionary:
	_sync_items()
	return {"version": ELAutochessRules.VERSION, "seed": str(run_seed), "rng": str(rng.state), "character": character,
		"round": round_number, "ether": ether, "health": health, "stage": stage, "army": army.duplicate(true),
		"shop": shop.duplicate(true), "items": items.duplicate(true), "item_offers": item_offers.duplicate(),
		"next_item_uid": next_item_uid, "item_reward_round": item_reward_round, "training": training,
		"battle_savings": battle_savings, "history": history.duplicate(true), "last_result": last_result.duplicate(true),
		"next_uid": next_uid}

## Restores a validated snapshot; false leaves the company unchanged.
func restore(data: ELProfile, saved: Dictionary) -> bool:
	if not _integer(saved.get("version"), 1, ELAutochessRules.VERSION): return false
	for key in ["army", "shop", "items", "item_offers", "history"]:
		if not saved.get(key) is Array: return false
	for key in ["seed", "rng"]:
		if not saved.get(key) is String or not String(saved[key]).is_valid_int(): return false
	if not _integer(saved.get("round"), 1, ELAutochessRules.MAX_ROUNDS) or not _integer(saved.get("ether"), 0, 100000): return false
	if not _integer(saved.get("health"), 0, ELAutochessRules.START_HEALTH) or not saved.get("stage") in ["prepare", "fight", "result", "won", "lost"]: return false
	if not _integer(saved.get("training"), 0, ELAutochessRules.MAX_TRAINING) or not _integer(saved.get("next_uid"), 1, 1000000): return false
	if saved.army.size() > ELAutochessRules.MAX_ARMY + ELAutochessRules.BENCH_LIMIT + 4 or saved.items.size() > ELAutochessArtifacts.MAX_ITEMS: return false
	var seen := {}
	for entry: Variant in saved.army:
		if not entry is Dictionary or not _integer(entry.get("uid"), 1, 1000000) or seen.has(int(entry.uid)): return false
		if not _integer(entry.get("family"), 0, ELAutochessRules.FAMILIES.size() - 1) or not _integer(entry.get("rank"), 0, 2): return false
		if String(entry.get("code", "")) != ELAutochessRules.form(int(entry.family), int(entry.rank)): return false
		if not entry.get("deployed") is bool or not entry.get("point") is Array or entry.point.size() != 2: return false
		if not _integer(entry.get("investment"), 1, 10000): return false
		seen[int(entry.uid)] = true
	for offer: Variant in saved.shop:
		if not offer is Dictionary or not _integer(offer.get("family"), -1, ELAutochessRules.FAMILIES.size() - 1) or not offer.get("locked") is bool: return false
	for item: Variant in saved.items:
		if not item is Dictionary or not ELAutochessArtifacts.RULES.has(String(item.get("kind", ""))) or not _integer(item.get("uid"), 1, 1000000): return false
		if not _integer(item.get("unit_uid"), 0, 1000000) or (int(item.unit_uid) > 0 and not seen.has(int(item.unit_uid))): return false
	for kind: Variant in saved.item_offers:
		if not ELAutochessArtifacts.RULES.has(String(kind)): return false
	profile = data
	run_seed = int(saved.seed); rng.seed = run_seed; rng.state = int(saved.rng)
	character = String(saved.get("character", ""))
	round_number = int(saved.round); ether = int(saved.ether); health = int(saved.health)
	stage = "prepare" if saved.stage == "fight" else String(saved.stage)
	army.assign(saved.army.duplicate(true))
	for entry: Dictionary in army:
		entry.uid = int(entry.uid); entry.family = int(entry.family); entry.rank = int(entry.rank); entry.investment = int(entry.investment)
		entry.point = [float(entry.point[0]), float(entry.point[1])]
		if entry.has("bench_slot"): entry.bench_slot = int(entry.bench_slot)
	shop.assign(saved.shop.duplicate(true))
	for offer: Dictionary in shop:
		offer.family = int(offer.family)
		offer.rank = int(offer.get("rank", 0))
	items.assign(saved.items.duplicate(true))
	for item: Dictionary in items:
		item.uid = int(item.uid); item.unit_uid = int(item.unit_uid)
	item_offers.assign(saved.item_offers)
	next_item_uid = int(saved.get("next_item_uid", 1)); item_reward_round = int(saved.get("item_reward_round", 0))
	training = int(saved.training); battle_savings = int(saved.get("battle_savings", 0))
	history.assign(saved.history.duplicate(true))
	last_result = saved.get("last_result", {}).duplicate(true) if saved.get("last_result", {}) is Dictionary else {}
	next_uid = int(saved.next_uid)
	for id: int in seen: next_uid = maxi(next_uid, id + 1)
	for item: Dictionary in items: next_item_uid = maxi(next_item_uid, int(item.uid) + 1)
	_undo.clear()
	reserve_slots()
	_sync_items()
	return true

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high

func _touch() -> void:
	reserve_slots()
	_sync_items()
	changed.emit()
