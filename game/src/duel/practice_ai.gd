class_name ELPracticeAI
extends RefCounted
## The computer opponent. Each step sends one command chosen by the combat
## lookahead (ELCombatSearch) with the same legal commands as the player; a
## refused command ends the phase instead.

##
## A duel shown on screen (a scene node listens to its `changed` signal) thinks
## on a worker thread, as the original opponent did: a step that finds no
## finished think for the current position starts one and returns; a later step
## sends its command and starts thinking about the next position while the
## same side keeps acting. Other callers think and act within the call. Both
## give the same command for the same position. `restricted` is auto-combat
## without "use spells" (see ELCombatSearch.Context.restricted).
static func step(duel: ELDuel, restricted := false) -> void:
	if duel.phase == ELDuel.Phase.FINISHED:
		var job: Job = _jobs.get(duel.get_instance_id())
		if job != null:
			_jobs.erase(duel.get_instance_id())
			_stale.append(job)
		_collect(true)
		return
	var command := {}
	if _displayed(duel):
		var ready: Variant = _background(duel, restricted)
		if ready == null: return
		command = ready
	else:
		command = ELCombatSearch.think(duel, {}, restricted)
	var side := duel.active_side()
	if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	if _displayed(duel) and duel.phase != ELDuel.Phase.FINISHED and duel.active_side() == side: _background(duel, restricted)

class Job:
	var task := -1
	var key := 0
	var result := {}
	var duel: WeakRef

## Background thinks per duel instance, and superseded ones still running.
static var _jobs := {}
static var _stale: Array[Job] = []

static func _displayed(duel: ELDuel) -> bool:
	return _display(duel) != null

static func _display(duel: ELDuel) -> Node:
	for connection: Dictionary in duel.changed.get_connections():
		var node: Object = connection.callable.get_object()
		if node is Node: return node
	return null

## Waits for the duel's thinks once its display closes, releasing the copies.
static func _release(id: int) -> void:
	var job: Job = _jobs.get(id)
	if job != null:
		_jobs.erase(id)
		_stale.append(job)
	_collect(true)

## The finished think for the duel's current position, or null while it runs.
## Releases superseded thinks and those of duels no longer in use; a task
## keeps its position copy until it is awaited. `all` waits for running ones.
static func _collect(all := false) -> void:
	for id: int in _jobs.keys():
		var job: Job = _jobs[id]
		if job.duel.get_ref() == null:
			_jobs.erase(id)
			_stale.append(job)
	for old: Job in _stale.duplicate():
		if all or WorkerThreadPool.is_task_completed(old.task):
			WorkerThreadPool.wait_for_task_completion(old.task)
			_stale.erase(old)

static func _background(duel: ELDuel, restricted := false) -> Variant:
	_collect()
	var key := [duel._snapshot(), restricted].hash()
	var id := duel.get_instance_id()
	var job: Job = _jobs.get(id)
	if job != null and job.key == key:
		if not WorkerThreadPool.is_task_completed(job.task): return null
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(id)
		return job.result
	if job != null:
		_jobs.erase(id)
		if WorkerThreadPool.is_task_completed(job.task): WorkerThreadPool.wait_for_task_completion(job.task)
		else: _stale.append(job)
	# Rule tables load on first use; load them here so the worker only reads.
	for table: String in ["CombatSpells", "CombatCreatures", "HeroTemplates", "Artefacts", "HeroesSpecs", "HeroesStats", "CombatManaIncome", "CombatDecks", "GlobalSpells"]:
		duel.profile.table(table)
	job = Job.new()
	job.key = key
	job.duel = weakref(duel)
	var position := duel.search_copy()
	var think := func() -> void: job.result = ELCombatSearch.think(position, {}, restricted)
	job.task = WorkerThreadPool.add_task(think, false, "Combat opponent")
	_jobs[id] = job
	var display := _display(duel)
	var release := _release.bind(id)
	if display != null and not display.tree_exiting.is_connected(release): display.tree_exiting.connect(release, CONNECT_ONE_SHOT)
	return null

## The earlier hand-written opponent: fixed per-card scores in a fixed order
## (hero abilities, creature abilities, best cast, attacks or blocks, end).
## Kept for comparison checks; it is not used in play.
static func heuristic_step(duel: ELDuel) -> void:
	if duel.phase == ELDuel.Phase.FINISHED: return
	var side := duel.active_side()
	var hero: Dictionary = duel.heroes[side]
	var allies := duel.army(side)
	var enemies := duel.army(1 - side)
	for ability: Dictionary in duel.abilities(side):
		if not duel.can_use_ability(side, ability.key): continue
		if hero.health + (int(ability.amount) if ability.effect == "heal" else 0) <= duel.global_enchantment_count("MNTH") * int(ability.cost): continue
		match ability.effect:
			"heal":
				if hero.health < hero.maximum + 4 and duel.use_ability(side, ability.key): return
			"fireball":
				var target := 1 - side
				var score := _damage_score(duel.heroes[target], target, int(ability.amount))
				for enemy: Dictionary in enemies:
					var value := _damage_score(enemy, enemy.id, int(ability.amount))
					if value > score:
						score = value
						target = enemy.id
				if duel.use_ability(side, ability.key, target): return
			"stone_rain":
				if not enemies.is_empty() and duel.use_ability(side, ability.key): return
			"artifact":
				# Original artifact moves carry a flat positive weight whenever legal.
				if ability.card == "RDDF" and not allies.is_empty() and duel.use_ability(side, ability.key): return
				if _artifact(duel, side, ability, allies, enemies): return
			"combine":
				# Feed a creature that cannot act this turn into one that can attack.
				if duel.phase != ELDuel.Phase.ATTACK: continue
				for feed: Dictionary in allies:
					if feed.power <= 0 or duel.can_attack(feed.id) or not duel.targetable(feed.id): continue
					for receiver: Dictionary in allies:
						if receiver.id != feed.id and duel.can_attack(receiver.id) and duel.targetable(receiver.id) and duel.use_ability(side, ability.key, feed.id, receiver.id): return
			"rebirth", "second_birth":
				# Bring back the strongest affordable creature from the own graveyard.
				if allies.size() >= 10: continue
				var best := -1
				var value := 0.0
				for index in hero.grave.size():
					var card: String = hero.grave[index]
					if not duel.profile.table("CombatCreatures").has(card): continue
					var price := 2 if ability.effect == "rebirth" else int(duel.profile.table("CombatSpells")[card].Cost)
					var row: Dictionary = duel.profile.table("CombatCreatures")[card]
					var worth := float(row.Power) + float(row.Toughness) * 0.5 - float(price) * 0.5
					if price <= duel.available_mana(side) and worth > value:
						best = index
						value = worth
				if best >= 0 and (ability.effect != "rebirth" or hero.health > 4) and duel.use_ability(side, ability.key, side, best): return
			"repair":
				# Return the strongest creature card; the enemy hero takes 1.
				var best := -1
				var strongest := -1
				for index in hero.grave.size():
					var card: String = hero.grave[index]
					if duel.profile.table("CombatCreatures").has(card) and int(duel.profile.table("CombatCreatures")[card].Power) > strongest:
						best = index
						strongest = int(duel.profile.table("CombatCreatures")[card].Power)
				if best >= 0 and duel.available_mana(side) >= 1 and duel.use_ability(side, ability.key, side, best): return
			"burnout":
				# Sacrifice a creature that cannot attack: finish the hero or kill a stronger enemy.
				for feed: Dictionary in allies:
					if feed.power <= 0 or duel.can_attack(feed.id) or not duel.targetable(feed.id): continue
					if duel.heroes[1 - side].health <= feed.power and duel._enchantment_count(1 - side, "FDBK") == 0 and duel.use_ability(side, ability.key, feed.id, 1 - side): return
					for enemy: Dictionary in enemies:
						if duel.targetable(enemy.id) and enemy.toughness - enemy.damage <= feed.power and enemy.power + enemy.toughness > feed.power + feed.toughness and not duel.has_flag(enemy.id, "NoAffect") and duel.use_ability(side, ability.key, feed.id, enemy.id): return
			"sacrifice":
				# Dissolve a weak creature that cannot attack this turn.
				for ally: Dictionary in allies:
					if ally.power + ally.toughness <= 3 and not duel.can_attack(ally.id) and duel.targetable(ally.id) and not duel.attacks.has(ally.id) and not duel.blocks.has(ally.id) and duel.use_ability(side, ability.key, ally.id): return
			"spirit_lock":
				# Feed a weak creature into ether channels.
				for ally: Dictionary in allies:
					if ally.power + ally.toughness <= 3 and duel.targetable(ally.id) and not duel.attacks.has(ally.id) and not duel.blocks.has(ally.id) and duel.use_ability(side, ability.key, ally.id): return
			"energize":
				for ally: Dictionary in allies:
					if ally.resting and not ally.sick and (ally.power > 0 or not duel.attacks.is_empty()) and duel.use_ability(side, ability.key, ally.id): return
	for ally: Dictionary in allies:
		for ability: Dictionary in duel.abilities(ally.id):
			if int(ability.cost) >= 0 and hero.health <= int(ability.cost) * duel.global_enchantment_count("MNTH") + int(ability.get("health_cost", 0)): continue
			if ability.key == "wake" and duel.available_mana(side) >= 3 and duel.use_ability(ally.id, "wake"): return
			if ability.key in ["awaken", "unparalyze"] and hero.health > int(ability.health_cost) and (ally.power > 0 or not duel.attacks.is_empty()) and duel.can_use_ability(ally.id, ability.key) and duel.use_ability(ally.id, ability.key): return
			if ability.key == "illusion" and hero.grave.size() + 1 > int(duel.profile.table("CombatCreatures")[ally.card].Toughness) and duel.can_use_ability(ally.id, ability.key) and duel.use_ability(ally.id, ability.key): return
			if ability.key == "spores" and duel.ready(ally.id):
				var amount := maxi(0, int(ally.power)) if ally.card == "CAFG" else 1
				if duel.heroes[1 - side].health <= amount and duel.use_ability(ally.id, "spores", 1 - side): return
				for enemy: Dictionary in enemies:
					if enemy.toughness - enemy.damage <= amount and enemy.power > 0 and duel.use_ability(ally.id, "spores", enemy.id): return
			if ability.get("pale", false) and duel.can_use_ability(ally.id, ability.key):
				if _pale(duel, side, ally, ability, enemies): return
				continue
			if not ELCatalog.first_ability(duel.profile, ally.card).is_empty() and duel.can_use_ability(ally.id, ability.key):
				if _first_ability(duel, side, ally, ability, allies, enemies): return
			if ability.key == "disenchant" and duel.ready(ally.id):
				for id: int in [side, 1 - side] + duel.creatures.keys():
					var target := duel.entity(id)
					var friendly: bool = id == side if id < 2 else target.owner == side
					for e: Dictionary in target.enchantments:
						var harmful: bool = e.card in ["ENFL", "IMMB", "WETX", "STTX", "ENVM", "FAIL", "DISM"]
						var useful := _gas_score(duel, allies, enemies, -1) > 0 if e.card == "DRGS" else friendly == harmful
						if e.card in ["LSDS", "STSI", "MNBN", "MNTH", "SPTR", "FTDS", "SFGS"]: useful = false
						if useful and hero.health > duel.cost(e.card) * duel.global_enchantment_count("MNTH") and hero.mana >= duel.cost(e.card) and duel.use_ability(ally.id, "disenchant", id, e.id): return
	var best := {"index": -1, "target": -1, "grave": -1, "power": 0, "score": 0.0}
	for i in hero.hand.size():
		var card: String = hero.hand[i]
		if duel.cost(card) > duel.available_mana(side) or hero.channels < duel.channel_cost(card): continue
		var targets: Array = [-1] if duel.target_kind(card) == "none" else duel.valid_targets(card)
		for target: int in targets:
			var effect: String = ELCatalog.rule(duel.profile, card).get("effect", "")
			var graves: Array = duel.valid_grave_targets(card) if effect in ["exchange", "pale_revival"] else duel.valid_grave_targets(card, target) if effect in ["reanimate", "repair"] else (duel.valid_enchantment_targets(card, target) if effect in ["dispel", "trade"] else (duel.swap_targets(card, target) if effect == "swap" else [-1]))
			var follow := {}
			for grave: int in graves:
				var power := _choose_power(duel, card, i, target, side, allies, enemies, grave, follow)
				if power < 0: continue
				var score := _score(duel, card, target, side, allies, enemies, grave, power)
				if duel.variable_power(card): score -= float(duel.channel_cost(card))
				if score > best.score: best = {"index": i, "target": target, "grave": grave, "power": power, "score": score}
	if best.index >= 0 and duel.cast(best.index, best.target, best.grave, best.power): return
	if duel.phase == ELDuel.Phase.ATTACK:
		for ally: Dictionary in allies:
			if hero.health <= duel.attack_cost(ally.id) * duel.global_enchantment_count("MNTH"): continue
			# Only creatures with positive current power are ever sent in.
			if int(ally.power) <= 0: continue
			if duel.can_attack(ally.id) and not duel.attacks.has(ally.id): duel.toggle_attack(ally.id)
	else:
		# Prefer a surviving blocker, then a trade, then absorbing a lethal hero hit.
		var available := allies.duplicate()
		for target: int in duel.attacks:
			if not duel.creatures.has(target): continue
			var attack: Dictionary = duel.creatures[target]
			available.sort_custom(func(a: Dictionary, b: Dictionary):
				return _block_score(duel, a, attack) > _block_score(duel, b, attack))
			for ally: Dictionary in available:
				if duel.ready(ally.id) and not duel.blocks.has(ally.id) and duel.assign_block(ally.id, target):
					available.erase(ally)
					break
	duel.end_phase()

static func _block_score(duel: ELDuel, c: Dictionary, a: Dictionary) -> float:
	if a.flying and not c.flying: return -1000
	if c.toughness - c.damage > a.power: return 20.0 + c.power
	if duel.has_flag(c.id, "FS") and not duel.has_flag(a.id, "FS") and c.power >= a.toughness - a.damage: return 30.0
	return -float(c.power + c.toughness)

static func _gas_score(duel: ELDuel, allies: Array[Dictionary], enemies: Array[Dictionary], change := 1) -> float:
	var score := 0.0
	for enemy: Dictionary in enemies:
		score += 2.0 * (int(enemy.power) - duel.creature_stats(enemy, change).x)
	for ally: Dictionary in allies:
		score += 2.0 * (duel.creature_stats(ally, change).x - int(ally.power))
	return score

## X candidates for a variable card, in the order they are tried.
## Ether-paid X: every value from the most the remaining ether pays for down to 1.
## X = 0 only spends the card, which never beats passing.
static func _powers(d: ELDuel, card: String) -> Array[int]:
	if not d.variable_power(card): return [0]
	# Channel is paid in health: the planner never wounds its own hero for it.
	if ELCatalog.rule(d.profile, card).get("x_source") == "health": return [0]
	var result: Array[int] = []
	for power in range(d.maximum_power(card), 0, -1): result.append(power)
	return result

## Picks X for one card/target: the best-valued outcome, where ether left unspent
## counts only through another hand card it still pays for. Equal outcomes keep
## the earlier (larger) X. Returns -1 when there is no candidate.
static func _choose_power(d: ELDuel, card: String, index: int, target: int, side: int, allies: Array[Dictionary], enemies: Array[Dictionary], grave: int, follow: Dictionary) -> int:
	var chosen := -1
	var chosen_rank := -INF
	var variable := d.variable_power(card)
	for power: int in _powers(d, card):
		var rank := _score(d, card, target, side, allies, enemies, grave, power)
		if variable and rank > 0.0:
			var left := d.available_mana(side) - d.cost(card) - d.power_price(card, power)
			if not follow.has(left): follow[left] = _follow_up(d, side, index, left, allies, enemies)
			rank += float(follow[left])
		if rank > chosen_rank:
			chosen_rank = rank
			chosen = power
	return chosen

## Best immediate value of another fixed-cost hand card that `left` ether still pays for.
static func _follow_up(d: ELDuel, side: int, skip: int, left: int, allies: Array[Dictionary], enemies: Array[Dictionary]) -> float:
	var hero: Dictionary = d.heroes[side]
	var best := 0.0
	for j in hero.hand.size():
		var other: String = hero.hand[j]
		if j == skip or d.variable_power(other) or d.cost(other) > left or hero.channels < d.channel_cost(other): continue
		var targets: Array = [-1] if d.target_kind(other) == "none" else d.valid_targets(other)
		for target: int in targets:
			best = maxf(best, _score(d, other, target, side, allies, enemies))
	return best

static func _damage_score(victim: Dictionary, id: int, amount: int) -> float:
	if id < 2: return 100.0 if victim.health <= amount else float(amount) * 0.25
	return 12.0 + float(victim.power) if victim.toughness - victim.damage <= amount else float(amount) * 0.2

static func _score(d: ELDuel, card: String, target: int, side: int, allies: Array[Dictionary], enemies: Array[Dictionary], grave := -1, power := 0) -> float:
	var rule := ELCatalog.rule(d.profile, card)
	var e := d.entity(target)
	var friendly: bool = target == side if target < 2 else e.get("owner", -1) == side
	if d.heroes[side].health <= d.global_enchantment_count("MNTH") * (d.cost(card) + power): return 0.0
	if d.profile.id == "el2" and d.global_enchantment_count("STSI") > 0 and rule.effect in ["mana", "channels"]: return 0.0
	match rule.get("effect"):
		"summon":
			if allies.size() >= 10: return 0
			var c: Dictionary = d.profile.table("CombatCreatures")[card]
			return 4.0 + float(c.Power) + float(c.Toughness) * 0.5
		"damage":
			if friendly: return 0
			return _damage_score(e, target, power if d.variable_power(card) else int(rule.amount))
		"wave":
			var score := 0.0
			for id: int in d.damage_targets(card, side, target):
				var victim := d.entity(id)
				var own: bool = id == side if id < 2 else victim.owner == side
				var value := _damage_score(victim, id, power if d.variable_power(card) else int(rule.amount))
				score += -value * (2.0 if id < 2 else 1.0) if own else value
			return score
		"mana": return 2.0 if d.heroes[side].hand.size() > 1 else 0.0
		"channels":
			if not d.channel_error(card, side).is_empty(): return 0.0
			return float(d.effect_amount(rule)) * (1.0 if rule.get("scope") == "both" else 3.0)
		"drain_mana": return float(mini(d.effect_amount(rule), int(d.heroes[1 - side].mana))) * 2.0
		"burn_mana": return _damage_score(e, target, int(e.mana)) + float(e.mana) if not friendly and e.mana > 0 else 0.0
		"revive": return 6.0 if not d.heroes[side].grave.is_empty() else 0.0
		"exchange":
			if not friendly or grave < 0: return 0.0
			var returned: Dictionary = d.profile.table("CombatCreatures")[d.heroes[side].grave[grave]]
			return maxf(0.0, float(returned.Power) + float(returned.Toughness) * 0.5 - float(e.power) - float(e.toughness - e.damage) * 0.5)
		"unsummon": return float(e.power + e.toughness) + 3.0 if not friendly else 0.0
		"rest_enemies":
			var score := 0.0
			for c: Dictionary in enemies:
				var exempt: bool = d.race(c.id) == "Wall" if rule.get("scope") == "not_walls" else d.has_flag(c.id, "Restless")
				if not c.resting and not exempt: score += 1.0 + float(c.power)
			return score
		"draw":
			var count := power if d.variable_power(card) else int(rule.amount)
			var reader := side if rule.get("self", false) else target
			# Fetch trades a channel for its cards.
			return float(count) * 1.5 - float(d.channel_cost(card)) * 2.0 if reader == side and d.heroes[side].hand.size() + count <= 7 else 0.0
		"exile":
			# Disintegration also pays the target's printed cost.
			if rule.get("priced_target", false) and d.cost(card) + int(d.profile.table("CombatSpells")[e.card].Cost) > d.available_mana(side): return 0.0
			return 12.0 + float(e.power) + float(e.toughness) * 0.5 if not friendly else 0.0
		"repair":
			if grave < 0: return 0.0
			var repaired: Dictionary = d.profile.table("CombatCreatures")[d.heroes[side].grave[grave]]
			var hurt := int(repaired.Power) if d.profile.id == "el2" else 1
			return 2.0 + float(repaired.Power) * 0.3 + (_damage_score(d.heroes[1 - side], 1 - side, hurt) if d._enchantment_count(1 - side, "FDBK") == 0 else 0.0)
		"rally_all":
			var score := 0.0
			for c: Dictionary in allies:
				if c.resting and not c.sick and not d.attacks.has(c.id) and not d.blocks.has(c.id): score += 1.0 + float(c.power) * (0.5 if d.phase == ELDuel.Phase.DEFENCE else 0.2)
			return score - 2.0
		"discard_all": return float(e.hand.size()) * 2.0 - 4.0 if not friendly else 0.0
		"reanimate":
			if grave < 0 or allies.size() >= 10: return 0.0
			var row: Dictionary = d.profile.table("CombatCreatures")[d.heroes[target].grave[grave]]
			return float(row.Power) + float(row.Toughness) * 0.5 - 3.0
		"drain_life": return _damage_score(d.heroes[1 - side], 1 - side, power) + float(power) * 0.5 if d._enchantment_count(1 - side, "FDBK") == 0 else 0.0
		"devour":
			if not friendly: return 0.0
			return 100.0 if d.heroes[1 - side].health <= e.power and d._enchantment_count(1 - side, "FDBK") == 0 else 0.0
		"swap":
			# Trade an own creature for an enemy one; its controller gains its toughness.
			if grave < 0 or not friendly or not d.creatures.has(grave) or d.creatures[grave].owner == side or d.has_flag(grave, "NoAffect"): return 0.0
			var victim: Dictionary = d.creatures[grave]
			return float(victim.power) + float(victim.toughness) * 0.5 - float(e.power) - float(e.toughness) * 0.5 - float(victim.toughness) * 0.3
		"pale_blast":
			if friendly: return 0.0
			return (_damage_score(e, target, 3) if d.pale(target) else 0.0) + (2.0 if not e.enchantments.is_empty() else 0.0)
		"pale_cleave":
			if friendly or d.has_flag(target, "NoAffect"): return 0.0
			return 10.0 + float(e.power) + float(e.toughness) * 0.5
		"ripple":
			var score := 0.0
			for c: Dictionary in d.creatures.values():
				if d.in_plane(c.id): score += (_damage_score(c, c.id, 3) if c.owner != side else -_damage_score(c, c.id, 3))
			return score + float(allies.size()) * 1.5 - 2.0
		"pale_theft": return 0.0
		"flux":
			var n := 0
			for c: Dictionary in allies:
				if not d.pale(c.id): n += 1
			if n == 0: return 0.0
			var score := 0.0
			for c: Dictionary in d.creatures.values():
				if d.in_plane(c.id): score += (_damage_score(c, c.id, n) if c.owner != side else -_damage_score(c, c.id, n))
			return score - 1.0
		"pale_calamity":
			var theirs := 0
			var own := 0
			for c: Dictionary in enemies: theirs += 1 if d.in_plane(c.id) else 0
			for c: Dictionary in allies: own += 1 if d.in_plane(c.id) else 0
			return float(mini(theirs, d.heroes[1 - side].hand.size()) - mini(own, d.heroes[side].hand.size() - 1)) * 2.0 - 1.0
		"banish":
			# Sends a Pale enemy out of the fight (an attacker is withdrawn); the caster draws.
			if friendly: return 0.0
			return 1.5 + ((4.0 + float(e.power)) if d.attacks.has(target) else 0.5)
		"vaporize":
			var score := 0.0
			for c: Dictionary in enemies: score += (2.0 + float(c.power)) if d.pale(c.id) and not d.in_plane(c.id) else 0.0
			for c: Dictionary in allies: score -= (2.0 + float(c.power)) if d.pale(c.id) and not d.in_plane(c.id) else 0.0
			return score - 2.0
		"pale_revival":
			# Destroys a creature in the plane: never an own one.
			if friendly or grave < 0: return 0.0
			var score := 12.0 + float(e.power) + float(e.toughness) * 0.5
			if allies.size() < 10:
				var row: Dictionary = d.profile.table("CombatCreatures")[d.heroes[grave / ELDuel.GRAVE_SIDE].grave[grave % ELDuel.GRAVE_SIDE]]
				score += maxf(0.0, float(row.Power) + float(row.Toughness) * 0.5 - 1.0)
			return score
		# Gift is only ever cast by scripted opponents.
		"gift": return 0.0
		"symbiosis": return float(2 * d.creatures.size()) * 0.6 - 1.0
		"sacrifice_heal": return float(e.toughness) * 0.5 - float(e.power) - 2.0 if friendly else 0.0
		"polymorph":
			var value := int(e.toughness) + (maxi(0, int(e.power)) if d.profile.id == "el2" else 0)
			var removal := (12.0 + float(e.power)) if not friendly else -float(e.power + e.toughness)
			return removal + float(value - int(d.heroes[side].health)) * 0.5 if value > 0 else 0.0
		"twister":
			# The attacking hero takes the creature's power.
			if friendly or d.has_flag(target, "NoAffect"): return 0.0
			var backlash := float(e.power) if d.attacker == side else -float(e.power)
			if d.attacker == side and d.heroes[side].health <= e.power: return 0.0
			return 12.0 + float(e.power) - backlash * 0.5
		"fury_of_nature":
			var score := 0.0
			for c: Dictionary in enemies: score += float(c.power) + float(c.toughness) * 0.5 + 2.0
			for c: Dictionary in allies: score -= float(c.power) + float(c.toughness) * 0.5 + 2.0
			if d.profile.id == "el2": score -= float(allies.size() + enemies.size()) * 1.0
			elif d.attacker == side: score -= float(allies.size() + enemies.size())
			return score - 4.0
		"clone":
			if allies.size() >= 10: return 0.0
			var row: Dictionary = d.profile.table("CombatCreatures")[e.card]
			return 2.0 + float(row.Power) + float(row.Toughness) * 0.5
		"bounce_all":
			var score := 0.0
			for c: Dictionary in enemies: score += float(c.power + c.toughness) * 0.5 + 1.0 if not d.has_flag(c.id, "NoAffect") else 0.0
			for c: Dictionary in allies: score -= float(c.power + c.toughness) * 0.5 + 1.0 if not d.has_flag(c.id, "NoAffect") else 0.0
			return score - 3.0
		"amnesia": return float(d.heroes[1 - side].hand.size() - (d.heroes[side].hand.size() - 1)) * 2.0 - 2.0
		"mind_blast":
			var per_card := 3 if d.profile.id == "el2" else 2
			var theirs: int = per_card * (d.heroes[1 - side].hand.size() - 5)
			var own: int = per_card * (d.heroes[side].hand.size() - 6)
			if own >= d.heroes[side].health: return 0.0
			return (100.0 if theirs >= d.heroes[1 - side].health else float(maxi(0, theirs))) - float(maxi(0, own)) - 1.0
		"hunger_both":
			var score := 0.0
			for c: Dictionary in enemies:
				if c.power > 0 and not d.has_flag(c.id, "NoAffect"): score += _damage_score(c, c.id, int(c.power))
			for c: Dictionary in allies:
				if c.power > 0 and not d.has_flag(c.id, "NoAffect"): score -= _damage_score(c, c.id, int(c.power))
			return score
		"redraw": return 0.0
		"ban":
			if d.profile.id == "el2": return float(d.heroes[1 - side].hand.size() - (d.heroes[side].hand.size() - 1)) * 2.0 - 1.0
			return float(mini(2, d.heroes[1 - side].hand.size()) - mini(2, d.heroes[side].hand.size() - 1)) * 2.0
		"full_heal": return float(d.heroes[side].maximum - d.heroes[side].health) * 0.5 - 2.0
		"heal": return float(power) * 0.6 if d.heroes[side].health < d.heroes[side].maximum else 0.0
		"half_heal": return float(int(d.heroes[side].maximum) / 2 - int(d.heroes[side].health)) * 0.6 - 1.0
		"destroy": return 12.0 + float(e.power) + float(e.toughness) * 0.5 if not friendly and not d.has_flag(target, "NoAffect") else 0.0
		"hunger_all":
			var score := 0.0
			for c: Dictionary in enemies:
				if c.power > 0 and not d.has_flag(c.id, "NoAffect"): score += _damage_score(c, c.id, int(c.power))
			return score
		"random_discard":
			if friendly: return 0.0
			var spells := 0
			for held: String in e.hand:
				if d.profile.table("CombatSpells").get(held, {}).get("Class") != "Creature": spells += 1
			return 2.5 * float(mini(3, spells))
		"annihilate":
			var own_power := 0
			var their_power := 0
			var score := 0.0
			for c: Dictionary in allies:
				if not d.has_flag(c.id, "NoAffect"):
					own_power += maxi(0, int(c.power))
					score -= float(c.power) + float(c.toughness) * 0.5 + 2.0
			for c: Dictionary in enemies:
				if not d.has_flag(c.id, "NoAffect"):
					their_power += maxi(0, int(c.power))
					score += float(c.power) + float(c.toughness) * 0.5 + 2.0
			if d.heroes[side].health <= their_power: return 0.0
			return score + _damage_score(d.heroes[1 - side], 1 - side, own_power) - float(their_power) * 0.5
		"hunger": return _damage_score(e, target, int(e.power)) if not friendly and e.power > 0 else 0.0
		"grave_fire":
			var own: int = 2 * d.heroes[side].grave.size()
			var theirs: int = 2 * d.heroes[1 - side].grave.size()
			if d.heroes[side].health <= own: return 0.0
			return 100.0 if d.heroes[1 - side].health <= theirs else float(theirs - own) * 0.5
		"dispel":
			if grave < 0: return 0.0
			if rule.get("priced", false):
				var chosen := d._enchantment_by_id(d.find_enchantment(grave), grave)
				if d.cost(card) + d.enchantment_price(chosen) > d.available_mana(side): return 0.0
			return _enchantments_value(d, side, [grave])
		"trade":
			if grave < 0 or not friendly: return 0.0
			return _enchantments_value(d, side, [grave]) - float(e.power + e.toughness) * 0.5
		"cleanse":
			var chosen: Array[int] = []
			for id: int in [0, 1] + d.creatures.keys():
				for item: Dictionary in d.entity(id).enchantments:
					if d.dispellable(id, item): chosen.append(int(item.id))
			return _enchantments_value(d, side, chosen) - 4.0
		"discard_creatures":
			if friendly: return 0
			return 3.0 if not e.hand.is_empty() else 0.0
		"enchant":
			if ELCatalog.HERO_ABILITIES.has(card): return 4.0 if d._enchantment_count(side, card) < 2 else 0.0
			if card == "MNTX": return 4.0 if d._enchantment_count(side, card) < 2 else 0.0
			if card == "MNVR": return 3.0 if d.heroes[side].channels >= d.heroes[1 - side].channels and d._enchantment_count(side, card) < 2 else 0.0
			if card == "DRGS": return _gas_score(d, allies, enemies)
			if card == "DPGS": return _gas_score(d, allies, enemies, 2)
			if card == "FRGS":
				var score := 0.0
				for c: Dictionary in enemies: score += (4.0 + float(c.power)) if c.toughness - c.damage <= 2 and not d.has_flag(c.id, "NoAffect") else 0.5
				for c: Dictionary in allies: score -= (4.0 + float(c.power)) if c.toughness - c.damage <= 2 and not d.has_flag(c.id, "NoAffect") else 0.5
				return score
			if card == "DELS":
				# Delusion kills a powerless enemy or turns a sturdy ally into an attacker.
				if not friendly and e.power == 0: return 8.0 + float(e.toughness) * 0.5
				return float(e.toughness - e.power) if friendly and e.toughness > e.power + 1 and d.can_attack(target) else 0.0
			if card == "SGHT": return 2.0 if friendly and not d.has_flag(target, "Disenchant") else 0.0
			if card == "SMOK":
				var held := 0.0
				for c: Dictionary in enemies: held += 2.0 if c.resting and not d.has_flag(c.id, "NoAffect") else 0.0
				for c: Dictionary in allies: held -= 2.0 if c.resting and not d.has_flag(c.id, "NoAffect") else 0.0
				return held if d.global_enchantment_count(card) == 0 else 0.0
			if card == "IMML":
				var score := 0.0
				for c: Dictionary in allies: score += -4.0 - float(c.power + c.toughness) if c.toughness - c.damage <= 2 else 6.0
				return score
			if card == "BLKD":
				# Blockade only helps a defence that is already under attack.
				return float(allies.size()) * 2.0 if d.phase == ELDuel.Phase.DEFENCE and not d.attacks.is_empty() and d._enchantment_count(side, card) == 0 else 0.0
			if card == "HAST": return float(allies.size()) * 1.5 if d._enchantment_count(side, card) == 0 else 0.0
			if card == "ANFR":
				var weak := 0.0
				for c: Dictionary in enemies:
					if c.power <= (5 if d.profile.id == "el2" else 3): weak += 2.0
				return weak if d._enchantment_count(side, card) == 0 else 0.0
			if card == "SPWB": return 3.0 if d._enchantment_count(side, card) == 0 and d.creatures.size() >= 2 else 0.0
			if card == "ETCH":
				# Mirror damage while the opponent's attack is coming.
				if d.phase != ELDuel.Phase.DEFENCE or d._enchantment_count(side, card) > 0: return 0.0
				var incoming := 0.0
				for id: int in d.attacks:
					if d.creatures.has(id): incoming += float(d.creatures[id].power)
				return 100.0 if incoming >= float(d.heroes[1 - side].health) and incoming < float(d.heroes[side].health) else incoming - 2.0
			if card == "TRLB": return 2.0 if d._enchantment_count(side, card) == 0 and d.heroes[side].health > 15 else 0.0
			if card == "ENLH": return 2.0 if d._enchantment_count(side, card) == 0 else 0.0
			if card in ["ENBR", "LFGR"]:
				if target < 2: return 3.0 if friendly and d._enchantment_count(target, card) == 0 else 0.0
				return 1.5 + float(e.power) * 0.2 if friendly and d._enchantment_count(target, card) == 0 else 0.0
			if card == "PRGD": return 1.0 + float(e.power) * 0.3 if friendly and d.pale(target) else 0.0
			# Cripple: an enemy holder feeds the caster a card each enemy turn.
			if card == "OCRP": return 4.0 if not friendly and d._enchantment_count(target, card) == 0 else 0.0
			# Lock aspect: an enemy Pale creature loses its death save.
			if card == "PRBN": return 3.0 + float(e.power) * 0.3 if not friendly and d.pale(target) and d._enchantment_count(target, card) == 0 else 0.0
			if card == "ALNS":
				var marks := 0
				for c: Dictionary in enemies: marks += 1 if d.pale(c.id) else 0
				return float(marks) * 1.5 if friendly and marks > 0 else 0.0
			# Script-only records and Aspect Ward are never chosen by the planner.
			if card in ["PRWR", "WTX2", "ELKS"]: return 0.0
			if card in ["PRWT", "PLSL", "PLWP", "OEXC"] or ELCatalog.WARDINGS.has(card): return 0.0
			if card in ["OST1", "OST2", "OST3"]: return 2.0 if d._enchantment_count(side, card) == 0 and allies.size() < 9 else 0.0
			if card in ["RIOT", "DWND", "PALN"]:
				if friendly or d._enchantment_count(target, card) > 0: return 0.0
				if card == "DWND": return (12.0 + float(e.power)) if e.toughness - e.damage <= 4 and d.profile.id == "el2" else minf(4.0, float(e.toughness - 1)) * 0.8
				if card == "PALN": return 2.0 + float(e.toughness) * 0.2
				return 2.0 if d.regeneration_cost(target) > 0 else 0.0
			if card == "REDR": return 3.0 + float(e.toughness) * 0.3 if friendly and d._enchantment_count(side, card) == 0 and not d.attacks.is_empty() and d.phase == ELDuel.Phase.DEFENCE else 0.0
			if card == "ERBN": return 4.0 + float(e.power) if not friendly and d._enchantment_count(target, card) == 0 else 0.0
			if card == "SHFR": return 2.0 + float(power) if friendly and power >= 3 and d.blocks.has(target) else 0.0
			if card == "STSK":
				if target < 2: return 3.0 if friendly and d._enchantment_count(target, card) == 0 else 0.0
				return 2.0 if friendly and (d.can_attack(target) or d.blocks.has(target)) else 0.0
			if ELCatalog.ARMY_AURAS.has(card):
				var aura: Dictionary = ELCatalog.ARMY_AURAS[card]
				return float(allies.size()) * (1.5 * float(aura.get("power", 0)) + float(aura.get("toughness", 0)))
			if card == "FOGG":
				# Worth casting only to stop an attack that is already coming.
				if d.phase != ELDuel.Phase.DEFENCE: return 0.0
				var incoming := 0.0
				for id: int in d.attacks:
					if d.creatures.has(id): incoming += float(d.creatures[id].power)
				return incoming * 1.5 - 2.0
			if card == "HOAM": return 3.0 if d._enchantment_count(side, card) == 0 else 0.0
			if card == "ALST":
				var printed := int(d.profile.table("CombatCreatures")[e.card].Power)
				return float(printed) * 1.5 - float(e.toughness) * 0.8 if friendly and d.can_attack(target) else 0.0
			if card == "CLFR": return 3.0 + float(e.power) * 0.5 if friendly and e.power > 0 and not d.has_flag(target, "UB") else 0.0
			if card == "SPBA": return 3.0 if friendly and e.power > 0 and not d.has_flag(target, "Destroy") else 0.0
			if card == "SLRP": return 2.0 + float(e.power) * 0.2 if friendly and d.regeneration_cost(target) == 0 else 0.0
			if card == "THIF": return 3.0 if friendly and d.can_attack(target) else 0.0
			if card == "MDNS": return 4.0 if not friendly and d._enchantment_count(target, card) == 0 else 0.0
			if card == "OVRL": return 4.0 + float(e.power) * 0.2 if friendly and d.can_attack(target) else 0.0
			if card == "VTLY": return float(allies.size()) * 1.5 if d._enchantment_count(side, card) == 0 else 0.0
			if card == "RPST": return 3.0 if d._enchantment_count(side, card) < 2 and d.heroes[side].grave.any(func(g: String) -> bool: return d.profile.table("CombatCreatures").has(g)) else 0.0
			if card in ["RBRT", "SCBR"]: return 3.0 if d._enchantment_count(side, card) == 0 and not d.heroes[side].grave.is_empty() else 0.0
			if card == "ASLT" and d.phase != ELDuel.Phase.ATTACK: return 0.0
			if card in ["ASST", "FDBK"]:
				# Ash stops the coming attack; feedback turns it back on the attacker.
				if d.phase != ELDuel.Phase.DEFENCE or d._enchantment_count(side, card) > 0: return 0.0
				var incoming := 0.0
				for id: int in d.attacks:
					if d.creatures.has(id): incoming += float(d.creatures[id].power)
				return incoming * (1.5 if card == "ASST" else 2.0) - 2.0
			if card == "FURY": return float(allies.size() - enemies.size()) * 2.0 if d._enchantment_count(side, card) == 0 else 0.0
			if card == "COPL":
				var regenerating := 0
				for c: Dictionary in allies + enemies:
					if c.flags.any(func(f: String): return f.begins_with("Regen(")): regenerating += 1
				return float(regenerating) * 2.0
			if card == "FLOD":
				var ground := 0.0
				for c: Dictionary in enemies: ground += 2.0 if not d.has_flag(c.id, "Fly") else 0.0
				for c: Dictionary in allies: ground -= 2.0 if not d.has_flag(c.id, "Fly") else 0.0
				return ground if d.global_enchantment_count(card) == 0 else 0.0
			if card == "WTLK": return 2.0 + float(e.toughness) * 0.3 if d._enchantment_count(target, card) == 0 else 0.0
			if card == "PSBR": return 3.0 + float(power) * 1.5 if friendly and (d.can_attack(target) or d.blocks.has(target)) else 0.0
			if card == "CRBL": return float(allies.size()) * 1.5 if d._enchantment_count(side, card) == 0 else 0.0
			if card == "DRFR":
				var weak := 0.0
				for c: Dictionary in enemies:
					if c.power <= 2: weak += 2.0
				return weak if d._enchantment_count(side, card) == 0 else 0.0
			if card == "CNAR":
				var flyers := 0.0
				for c: Dictionary in enemies: flyers += 2.0 if d.has_flag(c.id, "Fly") else 0.0
				for c: Dictionary in allies: flyers -= 2.0 if d.has_flag(c.id, "Fly") else 0.0
				return flyers if d.global_enchantment_count(card) == 0 else 0.0
			if card == "CMBN": return 2.0 if allies.size() >= 2 and d._enchantment_count(side, card) == 0 else 0.0
			if card == "CHCM": return float(e.power + e.toughness) + 3.0 if not friendly else 0.0
			if card == "BLSS": return 4.0 + float(e.power) if friendly and (d.can_attack(target) or d.blocks.has(target)) else 0.0
			if card == "SPWR": return 4.0 + float(e.power) if friendly and e.resting and e.power > 0 else 0.0
			if card == "AILK": return 3.0 + float(e.power) if friendly and e.power > 0 and not d.has_flag(target, "Lifetap") else 0.0
			if card == "IRRT": return 3.0 if not friendly and d._enchantment_count(target, card) == 0 else 0.0
			if int(rule.get("power", 0)) < 0: return minf(float(e.power), -float(rule.power)) + 3.0 if not friendly and e.power > 0 else 0.0
			if card in ["ENFL", "IMMB"]: return float(e.power) + 6.0 if not friendly and not e.resting else 0.0
			if card == "DNFR": return 3.0 if friendly and d._enchantment_count(target, card) == 0 else 0.0
			if card in ["WETX", "STTX", "ENVM"]: return 4.0 if not friendly and d._enchantment_count(target, card) < 3 else 0.0
			if card in ["LSDS", "SPTR"]: return float(enemies.size() - allies.size()) * 2.0
			if card == "MNBN": return float(d.heroes[1 - side].channels - d.heroes[side].channels) * 2.0
			if card == "MNTH": return 3.0 if d.heroes[side].health > d.heroes[1 - side].health + 5 and d.global_enchantment_count(card) < 2 else 0.0
			if card == "STSI": return 3.0 if allies.size() > enemies.size() and d.heroes[side].mana >= d.cost(card) + 2 and d.global_enchantment_count(card) == 0 else 0.0
			if card == "FTDS":
				var score := 0.0
				for c: Dictionary in enemies: score += 2.0 if c.flags.any(func(f: String): return f.begins_with("Regen(")) else 0.5
				if d.profile.id == "el2":
					for c: Dictionary in allies: score -= 2.0 if c.flags.any(func(f: String): return f.begins_with("Regen(")) else 0.5
				return score if d.global_enchantment_count(card) == 0 else 0.0
			if card == "SFGS":
				var score := _damage_score(d.heroes[1 - side], 1 - side, 2) - 2.0 * _damage_score(d.heroes[side], side, 2)
				for c: Dictionary in enemies: score += _damage_score(c, c.id, 2)
				for c: Dictionary in allies: score -= _damage_score(c, c.id, 2)
				return score
			if not friendly or (e.power == 0 and int(rule.get("power", 0)) == 0): return 0
			return 5.0 + float(rule.get("power", 0)) + (1.0 if e.flying else 0.0)
	return 0.0

## Picks a target for a battle artifact; returns whether one was used.
static func _artifact(d: ELDuel, side: int, ability: Dictionary, allies: Array[Dictionary], enemies: Array[Dictionary]) -> bool:
	if not d.artifact_error(side, int(ability.artifact)).is_empty(): return false
	var key: String = ability.key
	var best := -1
	var value := 0.0
	match ability.card:
		"RDLG", "RDCL":
			var amount := 3 if ability.card == "RDLG" else 9
			value = _damage_score(d.heroes[1 - side], 1 - side, amount) if d._enchantment_count(1 - side, "FDBK") == 0 else 0.0
			best = 1 - side if value > 0 else -1
			for c: Dictionary in enemies:
				if d.targetable(c.id) and _damage_score(c, c.id, amount) > value:
					best = c.id
					value = _damage_score(c, c.id, amount)
		"SPRG", "BRRD":
			for c: Dictionary in enemies:
				var worth := float(c.power) + float(c.toughness) * 0.5
				if d.targetable(c.id) and (ability.card == "BRRD" or d.attacks.has(c.id)) and worth > value and d.artifact_target_error(side, ability.card, c.id).is_empty():
					best = c.id
					value = worth
		"RDCM":
			for c: Dictionary in enemies:
				if d.artifact_target_error(side, ability.card, c.id).is_empty() and float(c.power + c.toughness) > value:
					best = c.id
					value = float(c.power + c.toughness)
		"ETAM", "WNBL":
			for c: Dictionary in allies:
				var useful: bool = not d.has_flag(c.id, "NoTarget") if ability.card == "ETAM" else d.can_attack(c.id)
				if useful and d.targetable(c.id) and float(c.power + c.toughness) > value:
					best = c.id
					value = float(c.power + c.toughness)
		"SPBR":
			for id: int in [0, 1] + d.creatures.keys():
				for e: Dictionary in d.entity(id).enchantments:
					var friendly: bool = (id == side) if id < 2 else d.creatures[id].owner == side
					if d.dispellable(id, e) and _harmful(e.card) == friendly and d.use_ability(side, key, id, e.id): return true
			return false
		"RDRS":
			for index in d.heroes[side].grave.size():
				var card: String = d.heroes[side].grave[index]
				if d.profile.table("CombatCreatures").has(card) and float(d.profile.table("CombatCreatures")[card].Power) + 1.0 > value and allies.size() < 10:
					best = index
					value = float(d.profile.table("CombatCreatures")[card].Power) + 1.0
			return best >= 0 and d.use_ability(side, key, side, best)
		"LNRD":
			# Reflect when the enemy army threatens real damage this turn.
			var threat := 0
			for c: Dictionary in enemies: threat += maxi(0, int(c.power))
			return threat >= 4 and d._enchantment_count(side, "LNRD") + d._enchantment_count(side, "FDBK") == 0 and d.use_ability(side, key)
		"PCDU":
			# Ash storm stalls an enemy army stronger than the own one.
			var theirs := 0
			var own := 0
			for c: Dictionary in enemies: theirs += maxi(0, int(c.power))
			for c: Dictionary in allies: own += maxi(0, int(c.power))
			return theirs >= own + 4 and d.global_enchantment_count("PCDU") + d.global_enchantment_count("ASST") == 0 and d.use_ability(side, key)
		"WRBN":
			var gain := 0
			for c: Dictionary in allies: gain += d._kin(c)
			for c: Dictionary in enemies: gain -= d._kin(c)
			return gain > 0 and d.global_enchantment_count("WRBN") == 0 and d.use_ability(side, key)
		"RDIS", "WNPZ":
			for c: Dictionary in enemies:
				var worth := float(c.power) + float(c.toughness) * 0.5
				if d.artifact_target_error(side, ability.card, c.id).is_empty() and d._enchantment_count(c.id, ability.card) == 0 and worth > value and (ability.card == "RDIS" or not c.resting):
					best = c.id
					value = worth
		"WNMG", "RDKN", "DMRD", "WNHR":
			return (allies.size() < 10 if ability.card != "DMRD" else not allies.is_empty()) and d.use_ability(side, key)
		"RDHL":
			return d.heroes[side].health < d.heroes[side].maximum and d.use_ability(side, key)
	return best >= 0 and d.use_ability(side, key, best)

## Enchantments the AI treats as bad for their holder.
static func _harmful(card: String) -> bool:
	return card in ["ENFL", "IMMB", "WETX", "STTX", "ENVM", "FAIL", "DISM", "IRRT", "TRSN", "SWSN", "ESWS", "CHCM", "HUNG", "WEAK", "MDNS", "RDCM", "RDIS", "WNPZ", "DWND", "RIOT", "PALN", "ERBN", "TWST", "OCRP", "PRBN", "WTX2", "ELKS", "PRWR"]

static func _enchantments_value(d: ELDuel, side: int, chosen: Array) -> float:
	var score := 0.0
	for enchantment_id: int in chosen:
		var holder := d.find_enchantment(enchantment_id)
		if holder < 0: continue
		var e := d._enchantment_by_id(holder, enchantment_id)
		var friendly: bool = holder == side if holder < 2 else d.creatures[holder].owner == side
		score += (2.0 + float(d.cost(e.card))) * (1.0 if _harmful(e.card) == friendly else -1.0)
	return score

## Simple first-game ability use: act only when the effect clearly helps.
## Pale creatures: manifest to fight in the attack phase and use rest abilities.
static func _pale(d: ELDuel, side: int, ally: Dictionary, ability: Dictionary, enemies: Array[Dictionary]) -> bool:
	var attacking := d.phase == ELDuel.Phase.ATTACK and d.attacker == side
	match ability.key:
		"fiendish":
			return attacking and ally.power > 0 and d.heroes[side].channels >= 3 and d.use_ability(ally.id, ability.key)
		"sinister":
			if not attacking or ally.power <= 0: return false
			# Consume an enemy graveyard card when possible.
			for grave_side: int in [1 - side, side]:
				if not d.heroes[grave_side].grave.is_empty(): return d.use_ability(ally.id, ability.key, grave_side, d.heroes[grave_side].grave.size() - 1)
		"cryptic":
			return attacking and ally.power > 0 and d.heroes[side].hand.size() >= 4 and d.use_ability(ally.id, ability.key)
		"channel_ether":
			return d.heroes[side].channels >= 4 and d.use_ability(ally.id, ability.key)
		"pale_heal":
			# Free from the plane; a bright creature heals only when the hero is hurt.
			return (d.in_plane(ally.id) or d.heroes[side].health < d.heroes[side].maximum) and d.use_ability(ally.id, ability.key)
		"ether_plea":
			var drained := int(d.heroes[1 - side].mana)
			if drained < 2: return false
			var target := 1 - side
			var score := _damage_score(d.heroes[target], target, drained)
			for enemy: Dictionary in enemies:
				var value := _damage_score(enemy, enemy.id, drained)
				if d.targetable(enemy.id) and value > score:
					score = value
					target = enemy.id
			return d.use_ability(ally.id, ability.key, target)
		"absorb", "transpose":
			for id: int in [side, 1 - side] + d.creatures.keys():
				var holder := d.entity(id)
				var friendly: bool = id == side if id < 2 else holder.owner == side
				for e: Dictionary in holder.enchantments:
					if d.dispellable(id, e) and _harmful(e.card) == friendly and d.use_ability(ally.id, ability.key, id, int(e.id)): return true
		"pale_devour":
			var best := -1
			var value := 0.0
			for enemy: Dictionary in enemies:
				var worth := float(enemy.power) + float(enemy.toughness) * 0.5
				if d.targetable(enemy.id) and not d.has_flag(enemy.id, "NoAffect") and worth > value:
					var weaker: bool = enemy.power < ally.power if ability.measure == "power" else (enemy.toughness < ally.toughness if ability.measure == "toughness" else enemy.power < ally.power and enemy.toughness < ally.toughness)
					if weaker:
						best = enemy.id
						value = worth
			return best >= 0 and d.use_ability(ally.id, ability.key, best)
	return false

static func _first_ability(d: ELDuel, side: int, ally: Dictionary, ability: Dictionary, allies: Array[Dictionary], enemies: Array[Dictionary]) -> bool:
	match ability.key:
		"sting":
			var amount := int(ability.get("amount", 1))
			var target := 1 - side
			var score := _damage_score(d.heroes[target], target, amount)
			for enemy: Dictionary in enemies:
				var value := _damage_score(enemy, enemy.id, amount)
				if value > score and d.targetable(enemy.id):
					score = value
					target = enemy.id
			return d.use_ability(ally.id, ability.key, target)
		"ether":
			# Tap for ether when one more point pays for a card in hand.
			for card: String in d.heroes[side].hand:
				if d.cost(card) == d.available_mana(side) + 1: return d.use_ability(ally.id, ability.key)
		"shoot":
			var best := -1
			var value := 0.0
			for id: int in d.attacks:
				if d.creatures.has(id) and d.creatures[id].owner != side and d.targetable(id) and _damage_score(d.creatures[id], id, int(ability.get("amount", 1))) > value:
					best = id
					value = _damage_score(d.creatures[id], id, 1)
			if best >= 0: return d.use_ability(ally.id, ability.key, best)
		"plague":
			# Clear rising creatures from an enemy graveyard.
			var grave: Array = d.heroes[1 - side].grave
			for index in grave.size():
				if grave[index] in ELCatalog.FIRST_RISING and index + 1 <= d.available_mana(side): return d.use_ability(ally.id, ability.key, 1 - side, -1, index + 1)
		"recall_rat":
			var rats := d.grave_ability_targets(ally.id, ability.key, side)
			if not rats.is_empty() and d.heroes[side].hand.size() < 5: return d.use_ability(ally.id, ability.key, side, rats[-1])
		"dispel":
			for id: int in [side, 1 - side] + d.creatures.keys():
				var holder := d.entity(id)
				var friendly: bool = id == side if id < 2 else holder.owner == side
				for e: Dictionary in holder.enchantments:
					if d.dispellable(id, e) and _harmful(e.card) == friendly and d.enchantment_price(e) <= d.available_mana(side) and d.use_ability(ally.id, ability.key, id, e.id): return true
		"spirit_flight":
			if d.phase == ELDuel.Phase.ATTACK:
				for c: Dictionary in allies:
					if c.card == "WRSP" and not d.has_flag(c.id, "Fly") and d.can_attack(c.id): return d.use_ability(ally.id, ability.key)
		"phantasm", "lava_power", "hellfire_health":
			# Boost a wall that is blocking this turn.
			if d.blocks.has(ally.id):
				var amount := 0 if ability.key == "phantasm" else d.available_mana(side)
				if ability.key == "phantasm" or amount >= 1: return d.use_ability(ally.id, ability.key, -1, -1, amount)
		"draw":
			if d.heroes[side].hand.size() < 5: return d.use_ability(ally.id, ability.key)
		"siphon":
			if d.heroes[1 - side].mana > 0: return d.use_ability(ally.id, ability.key)
		"bat_drain":
			if d._enchantment_count(1 - side, "FDBK") == 0: return d.use_ability(ally.id, ability.key)
		"breath":
			for c: Dictionary in enemies:
				if d.has_flag(c.id, "Fly") == (ability.scope == "flying") and not d.has_flag(c.id, "NoAffect"): return d.use_ability(ally.id, ability.key)
		"necromancy":
			var best := Vector2i(-1, -1)
			var value := 0.0
			if allies.size() >= 10: return false
			for grave_side in [side, 1 - side]:
				for index: int in d.grave_ability_targets(ally.id, ability.key, grave_side):
					var row: Dictionary = d.profile.table("CombatCreatures")[d.heroes[grave_side].grave[index]]
					if float(row.Power) + float(row.Toughness) * 0.5 > value:
						value = float(row.Power) + float(row.Toughness) * 0.5
						best = Vector2i(grave_side, index)
			if best.x >= 0: return d.use_ability(ally.id, ability.key, best.x, best.y)
		"gaze":
			var beholders := 0
			for c: Dictionary in allies:
				if d.race(c.id) == "Beholder": beholders += 1
			var best := -1
			var value := 0
			for c: Dictionary in enemies:
				if ability.measure == "power" and d.race(c.id) == "Wall": continue
				if int(c[ability.measure]) <= beholders and d.targetable(c.id) and not d.has_flag(c.id, "NoAffect") and c.power + c.toughness > value:
					best = c.id
					value = c.power + c.toughness
			if best >= 0: return d.use_ability(ally.id, ability.key, best)
		"tap_race":
			var counts := {}
			for c: Dictionary in enemies:
				if not c.resting and (d.profile.id != "el2" or not d.in_plane(c.id)): counts[d.race(c.id)] = counts.get(d.race(c.id), []) + [c.id]
			for kind: String in counts:
				if counts[kind].size() >= 2 and counts[kind].size() <= d.available_mana(side) and d.targetable(counts[kind][0]): return d.use_ability(ally.id, ability.key, counts[kind][0])
		"distortion":
			if d.phase == ELDuel.Phase.DEFENCE:
				var incoming := 0
				for id: int in d.attacks:
					if d.creatures.has(id): incoming += int(d.creatures[id].power)
				if incoming >= 6: return d.use_ability(ally.id, ability.key)
		"hunt":
			var best := -1
			var value := 0
			for c: Dictionary in enemies:
				if c.power >= 4 and d.targetable(c.id) and not d.has_flag(c.id, "NoAffect") and c.power + c.toughness > value:
					best = c.id
					value = c.power + c.toughness
			if best >= 0: return d.use_ability(ally.id, ability.key, best)
		"slay", "wall_break":
			var best := -1
			var value := 0
			for c: Dictionary in enemies:
				var fits: bool = d.race(c.id) == "Wall" if ability.key == "wall_break" else (c.resting and not d.attacks.has(c.id) and not d.blocks.has(c.id))
				if fits and d.targetable(c.id) and not d.has_flag(c.id, "NoAffect") and c.power + c.toughness > value:
					best = c.id
					value = c.power + c.toughness
			if best >= 0: return d.use_ability(ally.id, ability.key, best)
		"rally":
			for c: Dictionary in allies:
				if c.card != "KBEL" and c.resting and d.race(c.id) == "Kobold": return d.use_ability(ally.id, ability.key)
		"brood":
			if allies.size() < 10 and d.available_mana(side) >= int(ability.cost) + 1: return d.use_ability(ally.id, ability.key)
		"rouse":
			for c: Dictionary in allies:
				if c.card == "WRSP" and c.resting: return d.use_ability(ally.id, ability.key)
		"tap_target":
			# Tap the strongest untapped enemy that could block.
			var best := -1
			var power := 0
			for enemy: Dictionary in enemies:
				if not enemy.resting and enemy.power + enemy.toughness > power:
					best = enemy.id
					power = enemy.power + enemy.toughness
			if best >= 0 and power >= 4: return d.use_ability(ally.id, ability.key, best)
		"tap_walls":
			if int(ability.cost) > 0: return d.use_ability(ally.id, ability.key)
		"recall_spirit", "recall_lamia":
			var options := d.grave_ability_targets(ally.id, ability.key, side)
			if not options.is_empty(): return d.use_ability(ally.id, ability.key, side, options[-1])
	return false
