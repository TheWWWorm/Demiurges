class_name ELAutochessBot
extends RefCounted
## Computer players spend the same ether on the same offers, levels and
## refreshes as people; they get no free creatures or combat bonuses. Each
## seat keeps a spending personality (Cursed Lands values): economy,
## expansion, evolution and tempo.

const PROFILES := [
	{"bank": 50, "level": 0, "rolls": 2, "upgrades": 1.0},
	{"bank": 30, "level": 1, "rolls": 2, "upgrades": 0.85},
	{"bank": 40, "level": -1, "rolls": 7, "upgrades": 1.5},
	{"bank": 20, "level": 0, "rolls": 4, "upgrades": 1.15},
]
const STYLES := ["chaots", "kinets", "vitals", "synthets", "flyers", "strikers"]

static var _powers := {}

static func strategy(player: int) -> int:
	return posmod(player - 1, PROFILES.size())

## A planning estimate of sustained damage times survival, never a combat stat.
static func power(profile: ELProfile, line: int, rank: int) -> float:
	var key := Vector3i(line, rank, profile.root.hash())
	if _powers.has(key): return _powers[key]
	var values := ELAutochessRules.stats(profile, ELAutochessRules.form(line, rank), ELAutochessRules.tier(line), rank, line)
	var enemy_defense := (1.5 + (ELAutochessRules.tier(line) - 1) * 1.25) * (1.0 + rank * 0.2)
	var hit := maxf(float(values.damage) * 0.2, float(values.damage) - enemy_defense)
	var rate := hit / maxf(0.6, float(values.interval))
	if ELAutochessAbilities.active(String(values.code)):
		var a: Dictionary = values.ability
		rate += float(values.ability_power) * float(a.get("scale", 0.6)) / maxf(3.0, float(a.get("cooldown", 8.0)))
	var survival := float(values.health) + float(values.defense) * 12.0
	var value := sqrt(survival * rate) * 10.0
	if String(values.role) == "Ranged": value *= 1.15
	_powers[key] = value
	return value

static func entry_power(profile: ELProfile, entry: Dictionary) -> float:
	return power(profile, int(entry.family), int(entry.rank))

static func reserve(bot: ELAutochessCompany, round_number: int, hp: int, plan: Dictionary) -> int:
	if hp <= 30 or round_number >= 28: return 0
	var target := mini(int(plan.bank), maxi(0, round_number - 3) * 10)
	if hp <= 50: target = mini(target, 10)
	elif bot.history.size() >= 3 and bot.history.slice(-3).all(func(r: Dictionary) -> bool: return int(r.winner) != 0): target = mini(target, 20)
	return target

static func evolution_value(bot: ELAutochessCompany, line: int, rank: int, weakest: float) -> Dictionary:
	var result := {"score": 0.0, "completes": false}
	var owned := bot.army.filter(func(e: Dictionary) -> bool: return int(e.family) == line)
	if owned.is_empty() or owned.any(func(e: Dictionary) -> bool: return int(e.rank) == 2): return result
	var required := 1
	for target in range(rank + 1, 3):
		required *= 3
		var progress := 0
		for entry: Dictionary in owned:
			if int(entry.rank) < rank or int(entry.rank) >= target: continue
			progress += int(pow(3, int(entry.rank) - rank))
		var missing := maxi(1, required - progress)
		var gain := maxf(0.0, power(bot.profile, line, target) - maxf(weakest, power(bot.profile, line, rank)))
		var score := gain / missing * (2.5 if missing == 1 else 0.6)
		result.score = maxf(float(result.score), score)
		if missing == 1 and gain > 0: result.completes = true
	return result

static func new_plan(index: int) -> Dictionary:
	return {"actions": 0, "rerolls": 0, "wait": 0.4 + index * 0.13, "done": false}

## One visible shopping step: sell, buy, level, refresh, or finish.
static func step(bot: ELAutochessCompany, player: int, round_number: int, plan: Dictionary) -> void:
	if plan.done: return
	plan.actions = int(plan.actions) + 1
	var hp := bot.health
	if int(plan.actions) >= 40:
		equip(bot)
		plan.done = true
		return
	var personality: Dictionary = PROFILES[strategy(player)]
	var bank := reserve(bot, round_number, hp, personality)
	var style: String = STYLES[posmod(player - 1, STYLES.size())]
	arrange(bot, style)
	equip(bot)
	var weakest := INF
	for entry: Dictionary in bot.army:
		if entry.deployed: weakest = minf(weakest, entry_power(bot.profile, entry))
	if weakest == INF: weakest = 0.0
	var empty := bot.deployed_count() < bot.capacity()
	var best := -1
	var best_score := 0.0
	for index in bot.shop.size():
		if not bot.purchase_error(index).is_empty(): continue
		var offer: Dictionary = bot.shop[index]
		var line := int(offer.family)
		var rank := int(offer.get("rank", 0))
		var value := power(bot.profile, line, rank)
		var improvement := maxf(0.0, value - weakest) if not empty else value
		var future := evolution_value(bot, line, rank, weakest)
		var score := improvement + float(future.score) * float(personality.upgrades)
		if style in ELAutochessAlliances.traits(bot.profile, line): score *= 1.12
		var cost := bot.offer_cost(offer)
		if bot.ether - cost < bank and not empty and not (future.completes and hp < 65): continue
		if score < maxf(6.0, weakest * 0.04): continue
		score /= sqrt(float(cost))
		if score > best_score:
			best = index
			best_score = score
	# Sell obsolete reserves first, keeping real upgrade pairs.
	for entry: Dictionary in bot.army.duplicate():
		if entry.deployed: continue
		var peers := bot.army.filter(func(o: Dictionary) -> bool: return o.family == entry.family and o.rank == entry.rank).size()
		var potential := 0.0
		for rank in range(int(entry.rank) + 1, 3): potential = maxf(potential, power(bot.profile, int(entry.family), rank))
		var obsolete := potential < weakest * 1.05
		var higher := bot.army.any(func(o: Dictionary) -> bool: return o.family == entry.family and int(o.rank) > int(entry.rank))
		if obsolete or (peers == 1 and not higher and bot.bench_count() >= 4 and entry_power(bot.profile, entry) < weakest * 0.65):
			bot.sell(int(entry.uid))
			bot.clear_undo()
			return
	if best >= 0:
		bot.buy(best)
		arrange(bot, style)
		bot.clear_undo()
		return
	var desired := clampi(3 + round_number / 2 + int(personality.level), 3, ELAutochessRules.MAX_ARMY)
	if strategy(player) == 2: desired = clampi(3 + round_number / 4, 3, 7 if round_number < 24 else 9)
	if bot.capacity() < desired and bot.ether - ELAutochessRules.TRAINING_COST >= bank:
		if bot.train().is_empty():
			bot.clear_undo()
			return
	var rolls := int(personality.rolls) if round_number > 3 else 1
	if hp <= 30: rolls = 12
	if int(plan.rerolls) < rolls and bot.ether - bot.refresh_cost() >= bank + 3 and bot.refresh().is_empty():
		plan.rerolls = int(plan.rerolls) + 1
	else: plan.done = true
	bot.clear_undo()

## Deploys the strongest creatures, favouring alliance thresholds; melee in
## front, ranged behind, spread over the deployment area.
static func arrange(bot: ELAutochessCompany, style: String) -> void:
	if bot.stage != "prepare": return
	var remaining := bot.army.duplicate()
	var chosen: Array = []
	var lines := {}
	var counts := {}
	while chosen.size() < bot.capacity() and not remaining.is_empty():
		var best: Dictionary = {}
		var value := -INF
		for entry: Dictionary in remaining:
			var score := entry_power(bot.profile, entry)
			if not lines.has(entry.family):
				for key: String in ELAutochessAlliances.traits(bot.profile, int(entry.family)):
					var count := int(counts.get(key, 0))
					if ELAutochessAlliances.rank(key, count + 1) > ELAutochessAlliances.rank(key, count): score *= 1.18
					if key == style: score *= 1.08
			else: score *= 0.9
			if score > value:
				best = entry
				value = score
		chosen.append(best)
		remaining.erase(best)
		if not lines.has(best.family):
			lines[best.family] = true
			for key: String in ELAutochessAlliances.traits(bot.profile, int(best.family)): counts[key] = int(counts.get(key, 0)) + 1
	var front := 0
	var back := 0
	for entry: Dictionary in bot.army: entry.deployed = false
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := entry_power(bot.profile, a)
		var pb := entry_power(bot.profile, b)
		return pa > pb if not is_equal_approx(pa, pb) else int(a.uid) < int(b.uid))
	for entry: Dictionary in chosen:
		var ranged := String(ELAutochessRules.family(int(entry.family)).get("role", "Melee")) == "Ranged"
		var number := back if ranged else front
		entry.deployed = true
		entry.point = [(-10.5 if ranged else -5.0) - (2.5 if number >= 5 else 0.0), [0.0, -3.5, 3.5, -7.0, 7.0][number % 5]]
		if ranged: back += 1
		else: front += 1
	bot.reserve_slots()

static func equip(bot: ELAutochessCompany) -> void:
	if bot.stage != "prepare": return
	var deployed := bot.army.filter(func(e: Dictionary) -> bool: return e.deployed)
	if not bot.item_offers.is_empty():
		var choice := 0
		var best := -INF
		for index in bot.item_offers.size():
			var value := 0.0
			for entry: Dictionary in deployed: value = maxf(value, item_value(bot.profile, bot.item_offers[index], entry))
			if value > best:
				best = value
				choice = index
		bot.choose_item(choice)
	var remaining := bot.items.duplicate()
	var assignments := {}
	while not remaining.is_empty() and not deployed.is_empty():
		var best := -INF
		var item: Dictionary = {}
		var carrier: Dictionary = {}
		for candidate: Dictionary in remaining:
			for entry: Dictionary in deployed:
				var value := item_value(bot.profile, String(candidate.kind), entry)
				if value > best:
					best = value
					item = candidate
					carrier = entry
		if best <= 0.0: break
		assignments[int(item.uid)] = int(carrier.uid)
		remaining.erase(item)
		deployed.erase(carrier)
	for item: Dictionary in bot.items:
		if int(item.unit_uid) != int(assignments.get(int(item.uid), 0)): bot.equip_item(int(item.uid), 0)
	for item_uid: int in assignments: bot.equip_item(item_uid, int(assignments[item_uid]))
	bot.clear_undo()

static func item_value(profile: ELProfile, kind: String, entry: Dictionary) -> float:
	var g: Dictionary = ELAutochessArtifacts.RULES.get(kind, {})
	if g.is_empty(): return 0.0
	var line := int(entry.family)
	var melee := String(ELAutochessRules.family(line).get("role", "Melee")) == "Melee"
	var caster := ELAutochessAbilities.active(String(entry.code))
	var weight := 0.1 + power(profile, line, int(entry.rank)) / 400.0
	weight += float(g.get("health", 0)) / 160.0 * (1.2 if melee else 0.8)
	weight += float(g.get("damage", 0)) / 25.0 * 1.3
	weight += float(g.get("defense", 0)) / 6.0 * (0.8 if melee else 0.4)
	weight += float(g.get("haste", 0.0)) * 6.0
	weight += float(g.get("regen", 0.0)) * 40.0
	weight += float(g.get("lifesteal", 0.0)) * 5.0 * (1.5 if melee else 1.0)
	weight += float(g.get("poison", 0.0)) * 2.5
	weight += float(g.get("thorns", 0)) / 15.0 * (1.5 if melee else 0.3)
	weight += float(g.get("storm", 0)) / 40.0 * 2.0
	weight += float(g.get("rod", 0)) / 50.0 * 2.0
	weight += float(g.get("fury_attack", 0.0)) * 3.0
	weight += float(g.get("unity", 0.0)) * 4.0
	weight += float(g.get("dominance", 0.0)) * 12.0
	weight += float(g.get("aura_attack", 0.0)) * 8.0
	weight += float(g.get("shield_aura", 0)) / 40.0
	weight += float(g.get("bless_attack", 0.0)) * 2.0
	if g.has("ward") or g.has("revive") or g.has("knight"): weight += 1.6 if melee else 1.0
	if g.has("command") or g.has("dust") or g.has("paralyze"): weight += 1.5
	if g.get("ether_shield", false) or g.has("spell_guard"): weight += 0.8
	if g.get("first_strike", false): weight += 0.6
	if g.get("elusive", false): weight += 0.5 if melee else 0.0
	if caster and g.has("haste"): weight += 0.3
	return weight
