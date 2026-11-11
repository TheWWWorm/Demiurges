class_name ELAutochessBattle
extends RefCounted
## One real-time autochess fight, simulated in fixed ticks without the scene
## tree, so every board of a round can run at once (and the same inputs give
## the same fight on every machine). Creatures walk to the nearest enemy,
## attack on their original attack clip's impact frame, use their adapted
## abilities on a recharge and die with their own death clip. Presentation
## reads `units` and the `events` list.

const TICK := 0.05
const QUIET_LIMIT := ELAutochessRules.QUIET_DRAW_SECONDS
const TIME_LIMIT := ELAutochessRules.BATTLE_SECONDS
const RETARGET := 0.5
const SEPARATION := 1.0
const PROJECTILE_SPEED := 22.0

class Fighter:
	var id := 0
	var team := 0
	var code := ""
	var family := -1
	var rank := 0
	var tier := 1
	var race := ""
	var uid := 0
	var item := ""
	var creep := false
	var echo := false
	var pos := Vector2.ZERO
	var facing := 0.0
	var radius := 0.7
	var hp := 1.0
	var max_hp := 1.0
	var damage := 1.0
	var defense := 0.0
	var interval := 1.35
	var speed := 3.0
	var ranged := false
	var reach := 1.5
	var flags: Array[String] = []
	var ability := {}
	var ability_power := 0.0
	var cooldown := 0.0
	var recharge := 1.0
	var regen := 0.0
	## Original Regeneration (n): recovery while out of the fight.
	var rest_regen := 0.0
	var last_hurt := -10.0
	var venoms: Array = []
	var evasion := 0.0
	var first_hit_bonus := 0.0
	var attack_frames := 40
	var attack_impact := 20
	var cast_frames := 0
	var cast_impact := 0
	# Action in progress: "", "attack", "cast".
	var action := ""
	var action_left := 0.0
	var impact_left := -1.0
	var action_target := -1
	var target := -1
	var retarget := 0.0
	var moving := false
	var dead := false
	var death_time := 0.0
	var revived := false
	var stunned := 0.0
	var silenced := 0.0
	var haste := 0.0
	var haste_left := 0.0
	var weakened := 0.0
	var weakened_left := 0.0
	var burn_left := 0.0
	var shield := 0.0
	var bless_left := 0.0
	var bless_attack := 0.0
	var poisons: Array = []
	var hits_dealt := 0
	var growth := 0
	var struck: Dictionary = {}
	var dealt := 0.0
	var gear := {}
	var ward_used := false
	var dust_used := false
	var rod_left := 0.0
	var dusted := 0.0
	var rise_used := false

var profile: ELProfile
var units: Array[Fighter] = []
var events: Array[Dictionary] = []
const ITEM_GAP := 0.8
var _item_marks := {}
var time := 0.0
var quiet := 0.0
var finished := false
var winner := -2
var round_number := 1
var rng := RandomNumberGenerator.new()
var deaths := 0
var commanded := [false, false]
var _accumulator := 0.0
var _next_id := 1
var _death_marks := {}
var _ticks := 0
var _movers: Array = []
## Ability usage counts by team, for tests and balance reports.
var casts := [0, 0]

## `home`/`visitor` are formations (ELAutochessRules.formation): `home` on
## team 0 at its own points, `visitor` already mirrored for team 1.
func setup(data: ELProfile, home: Array, visitor: Array, seed_value: int, round_index := 1) -> void:
	profile = data
	round_number = round_index
	rng.seed = seed_value
	units.clear()
	events.clear()
	_item_marks.clear()
	time = 0.0
	quiet = 0.0
	finished = false
	winner = -2
	_next_id = 1
	_death_marks.clear()
	_ticks = 0
	for placement: Dictionary in home: _add(placement, 0)
	for placement: Dictionary in visitor: _add(placement, 1)
	_apply_bell()
	if _alive(0).is_empty() or _alive(1).is_empty(): _finish()

func _add(placement: Dictionary, team: int, echo := false) -> Fighter:
	var code := String(placement.code)
	var index := int(placement.get("family", -1))
	var unit_tier := int(placement.get("tier", ELAutochessRules.tier(index) if index >= 0 else 1))
	var star := int(placement.get("rank", 0))
	var values := ELAutochessRules.stats(profile, code, unit_tier, star, index)
	var row := ELAutochessRules.original(profile, code)
	var f := Fighter.new()
	f.id = _next_id
	_next_id += 1
	f.team = team
	f.code = code
	f.family = index
	f.rank = star
	f.tier = unit_tier
	f.race = String(row.get("Race", ""))
	f.uid = int(placement.get("uid", 0))
	f.item = String(placement.get("item", "")) if not echo else ""
	f.creep = bool(placement.get("creep", false))
	f.echo = echo
	f.pos = Vector2(float(placement.point[0]), float(placement.point[1]))
	f.facing = 0.0 if team == 0 else PI
	f.radius = clampf(0.36 * float(row.get("AtRange", 1.5)) * float(row.get("Scale", 1.0)), 0.5, 1.25)
	f.max_hp = float(values.health)
	f.hp = f.max_hp
	f.damage = float(values.damage)
	f.defense = float(values.defense)
	f.interval = float(values.interval)
	f.speed = float(values.speed)
	f.ranged = String(values.role) == "Ranged"
	f.reach = float(values.reach)
	f.flags = values.flags
	f.ability = values.ability
	f.ability_power = float(values.ability_power)
	f.cooldown = float(f.ability.get("start", 2.0))
	if "NSS" in f.flags: f.cooldown *= 0.5
	f.rest_regen = float(values.regen) * 0.015
	var clips := ELAutochessAbilities.clip_info(profile, code)
	f.attack_frames = int(clips.get("attack", 40))
	f.attack_impact = int(clips.get("attack_impact", f.attack_frames / 2))
	f.cast_frames = int(clips.get("cast", 0))
	f.cast_impact = int(clips.get("cast_impact", 0))
	units.append(f)
	return f

## Alliances, auras and items are fixed at the bell.
func _apply_bell() -> void:
	for team in 2:
		var army := units.filter(func(u: Fighter) -> bool: return u.team == team and not u.creep)
		var rows: Array = []
		for u: Fighter in army: rows.append({"deployed": true, "family": u.family})
		var levels := ELAutochessAlliances.levels(profile, rows)
		for u: Fighter in army:
			var traits := ELAutochessAlliances.traits(profile, u.family)
			for key: String in levels:
				if key not in traits: continue
				var level := int(levels[key])
				match key:
					"chaots": u.damage *= 1.0 + 0.1 * level
					"kinets":
						u.recharge *= 1.0 + 0.2 * level
						u.interval /= 1.0 + 0.1 * level
					"vitals": u.regen += 0.01 * level
					"synthets": u.defense += 3.0 * level
					"flyers": u.evasion = 0.15 * level
					"strikers": u.first_hit_bonus = 0.3 * level
	# Race auras: each aura code counts once per team.
	for team in 2:
		var seen := {}
		for source: Fighter in units:
			if source.team != team or String(source.ability.get("kind", "")) not in ["aura", "rally", "revive"]: continue
			var a := source.ability
			if seen.has(source.code) or not a.has("race"): continue
			if String(a.kind) == "revive" and not a.has("aura"): continue
			seen[source.code] = true
			for u: Fighter in units:
				if u.team != team or u.race != String(a.race): continue
				var attack := float(a.get("attack", a.get("aura", 0.0)))
				var health := float(a.get("health", a.get("aura", 0.0))) if String(a.kind) != "rally" else float(a.get("health", 0.0))
				u.damage *= 1.0 + attack
				u.max_hp *= 1.0 + health
				u.hp = u.max_hp
				if String(a.kind) == "aura" and a.has("haste"): u.interval /= 1.0 + float(a.haste)
				if a.get("elusive", false) and "Elusive" not in u.flags: u.flags.append("Elusive")
	# Items: flat values after percentage bonuses.
	for u: Fighter in units:
		if u.item.is_empty(): continue
		var g: Dictionary = ELAutochessArtifacts.RULES.get(u.item, {})
		u.gear = g
		u.max_hp += float(g.get("health", 0))
		u.max_hp = maxf(1.0, u.max_hp * (1.0 + float(g.get("fury_health", 0.0))))
		u.hp = u.max_hp
		u.damage += float(g.get("damage", 0))
		u.damage *= 1.0 + float(g.get("fury_attack", 0.0))
		u.defense += float(g.get("defense", 0))
		u.interval /= 1.0 + float(g.get("haste", 0.0))
		u.regen += float(g.get("regen", 0.0))
		if g.get("elusive", false) and "Elusive" not in u.flags: u.flags.append("Elusive")
		if g.get("first_strike", false) and "FS" not in u.flags: u.flags.append("FS")
		if g.get("ether_shield", false) and "NoTarget" not in u.flags: u.flags.append("NoTarget")
		if g.has("bless_attack"):
			u.bless_left = float(g.bless_seconds)
			u.bless_attack = float(g.bless_attack)
			u.shield += float(g.bless_shield)
		if g.has("rod"): u.rod_left = float(g.rod_every)
		if g.has("unity"):
			var same := units.filter(func(o: Fighter) -> bool: return o != u and o.team == u.team and o.race == u.race).size()
			var bonus := float(g.unity) + float(g.unity_per) * same
			u.damage *= 1.0 + bonus
			u.max_hp *= 1.0 + bonus
			u.hp = u.max_hp
	for u: Fighter in units:
		if u.item.is_empty(): continue
		var g := u.gear
		if g.has("aura_attack"):
			for o: Fighter in _allies_near(u, float(g.aura_radius), true):
				o.damage *= 1.0 + float(g.aura_attack)
				o.max_hp *= 1.0 + float(g.aura_health)
				o.hp = o.max_hp
		if g.has("shield_aura"):
			for o: Fighter in _allies_near(u, float(g.aura_radius), true): o.shield += float(g.shield_aura)
		if g.has("dominance"):
			for o: Fighter in units:
				if o.team != u.team: continue
				o.damage *= 1.0 + float(g.dominance)
				o.max_hp *= 1.0 + float(g.dominance)
				o.hp = o.max_hp
	for u: Fighter in units:
		u.max_hp = ceilf(u.max_hp)
		u.hp = u.max_hp
		u.damage = snappedf(u.damage, 0.1)
	# A walking horror's aura of death strikes every creature as it enters.
	for u: Fighter in units:
		if String(u.ability.get("kind", "")) == "death_aura": _death_aura(u)

func _allies_near(source: Fighter, radius: float, include_self: bool) -> Array[Fighter]:
	var found: Array[Fighter] = []
	for o: Fighter in units:
		if o.dead or o.team != source.team: continue
		if o == source and not include_self: continue
		if o.pos.distance_to(source.pos) <= radius: found.append(o)
	return found

func unit(id: int) -> Fighter:
	for u: Fighter in units:
		if u.id == id: return u
	return null

func _alive(team: int) -> Array[Fighter]:
	var found: Array[Fighter] = []
	for u: Fighter in units:
		if not u.dead and u.team == team: found.append(u)
	return found

## Advances by `delta` real seconds of battle time; returns true once over.
func advance(delta: float) -> bool:
	if finished: return true
	_accumulator += delta
	while _accumulator >= TICK and not finished:
		_accumulator -= TICK
		_tick()
	return finished

func run_to_end() -> void:
	while not finished: _tick()

## Marks a visible item proc, at most once per ITEM_GAP per carrier.
func _item_used(u: Fighter) -> void:
	if u == null or u.item.is_empty(): return
	if time - float(_item_marks.get(u.id, -9.0)) < ITEM_GAP: return
	_item_marks[u.id] = time
	_emit("item", {"u": u.id, "g": u.item})

func _emit(kind: String, values: Dictionary) -> void:
	values["k"] = kind
	values["time"] = time
	events.append(values)

func _tick() -> void:
	time += TICK
	quiet += TICK
	for u: Fighter in units:
		if u.dead: continue
		_status(u)
	# Every creature decides from the same positions; alternating the order
	# keeps either side from acting first in a tick.
	var order := units.duplicate()
	if _ticks % 2 == 1: order.reverse()
	_ticks += 1
	_movers.clear()
	for u: Fighter in order:
		if u.dead: continue
		_think(u)
	for pair: Array in _movers:
		var mover: Fighter = pair[0]
		var goal: Fighter = pair[1]
		if not mover.dead and not goal.dead: _move_toward(mover, goal)
	_separate()
	_check_end()

func _status(u: Fighter) -> void:
	u.stunned = maxf(0.0, u.stunned - TICK)
	u.silenced = maxf(0.0, u.silenced - TICK)
	u.dusted = maxf(0.0, u.dusted - TICK)
	if u.haste_left > 0.0:
		u.haste_left -= TICK
		if u.haste_left <= 0.0: u.haste = 0.0
	if u.weakened_left > 0.0:
		u.weakened_left -= TICK
		if u.weakened_left <= 0.0: u.weakened = 0.0
	if u.bless_left > 0.0:
		u.bless_left -= TICK
		if u.bless_left <= 0.0: u.bless_attack = 0.0
	u.burn_left = maxf(0.0, u.burn_left - TICK)
	if u.burn_left <= 0.0 and u.hp < u.max_hp:
		var rate := u.regen
		# Regeneration closes wounds between blows: it works only after two
		# seconds without damage, so it decides long fights, not duels.
		if time - u.last_hurt >= 2.0: rate += u.rest_regen
		if rate > 0.0: u.hp = minf(u.max_hp, u.hp + u.max_hp * rate * TICK)
	# Item aura regeneration.
	if u.gear.has("aura_regen"):
		for o: Fighter in _allies_near(u, float(u.gear.aura_radius), false):
			if o.burn_left <= 0.0: o.hp = minf(o.max_hp, o.hp + o.max_hp * float(u.gear.aura_regen) * TICK)
	if String(u.ability.get("kind", "")) == "parasite":
		u.hp -= u.max_hp * float(u.ability.share) * TICK
		if u.hp <= 0.0:
			u.hp = 1.0
	# Original Fatalist died at the end of a turn in which it took no damage.
	if String(u.ability.get("kind", "")) == "fatalist" and time - maxf(u.last_hurt, 0.0) >= float(u.ability.seconds):
		_die(u, -1)
		return
	var kept: Array = []
	for poison: Dictionary in u.poisons:
		var amount := float(poison.dps) * TICK
		poison.left = float(poison.left) - TICK
		if amount > 0.0: _harm(u, amount, int(poison.source), "poison")
		if u.dead: return
		if float(poison.left) > 0.0: kept.append(poison)
	u.poisons = kept
	# Original venom killed a creature at the end of the combat phase. Here
	# it finishes a badly wounded creature when it runs its course.
	var venoms: Array = []
	for venom: Dictionary in u.venoms:
		venom.left = float(venom.left) - TICK
		if float(venom.left) > 0.0:
			venoms.append(venom)
			continue
		if u.tier < 5 and u.rank < 2 and u.hp <= u.max_hp * float(venom.threshold):
			_emit("ability", {"u": int(venom.source), "t": [u.id], "a": "venom"})
			_harm(u, u.hp + u.shield + 1.0, int(venom.source), "destroy")
			return
	u.venoms = venoms
	if u.cooldown > 0.0: u.cooldown -= TICK * u.recharge
	if u.rod_left > 0.0: u.rod_left -= TICK

func _think(u: Fighter) -> void:
	if u.action != "":
		_continue_action(u)
		return
	if u.stunned > 0.0:
		u.moving = false
		return
	u.retarget -= TICK
	var current := unit(u.target)
	# Bloodthirsty creatures press the attack on their enemy until it falls.
	var pressing := "Berserk" in u.flags and current != null and not current.dead and current.team != u.team and u.pos.distance_to(current.pos) <= _contact(u, current) + 0.5
	if current == null or current.dead or current.team == u.team or (u.retarget <= 0.0 and not pressing):
		_choose_target(u)
		current = unit(u.target)
	if current == null:
		u.moving = false
		return
	# Abilities first, when ready.
	if u.cooldown <= 0.0 and u.silenced <= 0.0 and ELAutochessAbilities.active(u.code) and _can_cast(u):
		_start_cast(u, current)
		return
	if u.rod_left <= 0.0 and u.gear.has("rod") and u.pos.distance_to(current.pos) <= ELAutochessRules.RANGED_REACH + 2.0:
		_rod(u, current)
	var distance := u.pos.distance_to(current.pos)
	if distance <= _contact(u, current):
		u.moving = false
		u.facing = _angle(u.pos, current.pos)
		if u.dusted <= 0.0: _start_attack(u, current)
		return
	_movers.append([u, current])

func _contact(u: Fighter, other: Fighter) -> float:
	if u.ranged: return u.reach
	return u.radius + other.radius + 0.45

func _angle(from: Vector2, to: Vector2) -> float:
	return atan2(to.x - from.x, to.y - from.y)

func _move_toward(u: Fighter, other: Fighter) -> void:
	var direction := other.pos - u.pos
	var length := direction.length()
	if length < 0.001: return
	var step := minf(u.speed * TICK, maxf(0.0, length - _contact(u, other) + 0.05))
	u.pos += direction / length * step
	u.pos.x = clampf(u.pos.x, ELAutochessRules.FIELD.position.x, ELAutochessRules.FIELD.end.x)
	u.pos.y = clampf(u.pos.y, ELAutochessRules.FIELD.position.y, ELAutochessRules.FIELD.end.y)
	u.facing = _angle(u.pos, other.pos)
	u.moving = step > 0.0001

## Bodies keep apart: ground creatures from each other, flyers from other
## flyers (they pass over the ground). Two passes, so a crowd settles too.
func _separate() -> void:
	for _pass in 2:
		for i in units.size():
			var a := units[i]
			if a.dead: continue
			var a_flies := "Fly" in a.flags
			for j in range(i + 1, units.size()):
				var b := units[j]
				if b.dead or ("Fly" in b.flags) != a_flies: continue
				var offset := b.pos - a.pos
				var distance := offset.length()
				var wanted := (a.radius + b.radius) * SEPARATION
				if distance >= wanted: continue
				var push := (offset / distance if distance > 0.001 else Vector2(0, 1 if a.id < b.id else -1)) * (wanted - distance) * 0.5
				# A creature in the middle of a blow holds its ground; two
				# of them still ease apart, slowly.
				var a_fixed := a.action != ""
				var b_fixed := b.action != ""
				if a_fixed and b_fixed:
					a.pos -= push * 0.25
					b.pos += push * 0.25
				elif a_fixed: b.pos += push * 2.0
				elif b_fixed: a.pos -= push * 2.0
				else:
					a.pos -= push
					b.pos += push
	for u: Fighter in units:
		u.pos.x = clampf(u.pos.x, ELAutochessRules.FIELD.position.x, ELAutochessRules.FIELD.end.x)
		u.pos.y = clampf(u.pos.y, ELAutochessRules.FIELD.position.y, ELAutochessRules.FIELD.end.y)

func _choose_target(u: Fighter) -> void:
	u.retarget = RETARGET
	var best: Fighter = null
	var best_score := INF
	var elusive := "Elusive" in u.flags or "UB" in u.flags
	for o: Fighter in units:
		if o.dead or o.team == u.team: continue
		var score := u.pos.distance_to(o.pos)
		if elusive:
			# Unblockable creatures slip past the front line to the casters.
			score -= (o.pos.x if u.team == 0 else -o.pos.x) * 1.5
			if o.ranged: score -= 4.0
		if o.id == u.target: score -= 1.5
		if score < best_score:
			best_score = score
			best = o
	u.target = best.id if best != null else -1

func _start_attack(u: Fighter, other: Fighter) -> void:
	var speed := (1.0 + u.haste)
	var total := u.interval / speed
	var clip := float(u.attack_frames) / 30.0
	var impact := float(u.attack_impact) / 30.0
	if clip > total: impact *= total / clip
	# First strike: the opening blow on each enemy lands at once and throws
	# that enemy's own swing off balance.
	if "FS" in u.flags and not u.struck.has(other.id):
		impact = minf(impact, 0.12)
		if other.action == "attack" and other.impact_left > 0.0 and "FS" not in other.flags:
			other.impact_left += 0.35
			other.action_left += 0.35
	u.action = "attack"
	u.action_left = total
	u.impact_left = impact
	u.action_target = other.id
	_emit("attack", {"u": u.id, "t": other.id, "d": total, "s": minf(1.0, total / clip) if clip > 0 else 1.0})

func _can_cast(u: Fighter) -> bool:
	var a := u.ability
	match String(a.kind):
		"revive": return _revive_candidate(u) != null
		"rally": return units.any(func(o: Fighter) -> bool: return not o.dead and o.team == u.team and o.race == String(a.race) and o != u) or a.has("health")
		"nova":
			return _alive(1 - u.team).any(func(o: Fighter) -> bool: return _nova_match(o, String(a.filter)) and not _immune(o)) or a.has("fallback")
		"execute", "bolt", "stun", "silence", "drain", "dispel": return _ability_target(u) != null
	return false

func _start_cast(u: Fighter, current: Fighter) -> void:
	var frames := u.cast_frames if u.cast_frames > 0 else u.attack_frames
	var impact := u.cast_impact if u.cast_frames > 0 else u.attack_impact
	var total := maxf(0.6, float(frames) / 30.0)
	var target := _ability_target(u)
	u.action = "cast"
	u.action_left = total
	u.impact_left = float(impact) / 30.0
	u.action_target = target.id if target != null else current.id
	if target != null: u.facing = _angle(u.pos, target.pos)
	u.cooldown = float(u.ability.get("cooldown", 8.0))
	# Tireless creatures use abilities without resting.
	if "Restless" in u.flags:
		u.impact_left = minf(u.impact_left, 0.2)
		u.action_left = minf(total, 0.45)
	casts[u.team] += 1
	_emit("cast", {"u": u.id, "t": u.action_target, "d": total, "clip": "uinstant" if u.cast_frames > 0 else "uattack", "a": String(u.ability.kind)})

func _continue_action(u: Fighter) -> void:
	if u.stunned > 0.0:
		# A stun interrupts the gesture before its blow lands.
		if u.impact_left > 0.0:
			u.action = ""
			u.impact_left = -1.0
			_emit("interrupt", {"u": u.id})
			return
	u.action_left -= TICK * (1.0 + u.haste)
	if u.impact_left > 0.0:
		u.impact_left -= TICK * (1.0 + u.haste)
		if u.impact_left <= 0.0:
			var target := unit(u.action_target)
			if u.action == "attack":
				if target != null and not target.dead and u.pos.distance_to(target.pos) <= _contact(u, target) + 1.2: _strike(u, target)
			else:
				_ability(u, target)
	if u.action_left <= 0.0:
		u.action = ""
		u.impact_left = -1.0

func _attack_damage(u: Fighter, target: Fighter) -> float:
	var raw := u.damage * (1.0 - u.weakened) * (1.0 + u.bless_attack)
	raw *= 1.0 + 0.05 * u.growth
	if not u.struck.has(target.id) and u.first_hit_bonus > 0.0: raw *= 1.0 + u.first_hit_bonus
	if "TeamAttack" in u.flags:
		var partners := units.filter(func(o: Fighter) -> bool: return o != u and not o.dead and o.team == u.team and o.target == target.id).size()
		raw *= 1.0 + 0.15 * mini(2, partners)
	return raw

func _strike(u: Fighter, target: Fighter) -> void:
	if target.evasion > 0.0 and "Fly" not in u.flags and rng.randf() < target.evasion:
		u.struck[target.id] = true
		_emit("hit", {"u": target.id, "s": u.id, "v": 0, "miss": true, "ranged": u.ranged})
		return
	var raw := _attack_damage(u, target)
	u.struck[target.id] = true
	u.hits_dealt += 1
	var before := target.hp
	var dealt := _harm(target, maxf(raw * 0.2, raw - target.defense), u.id, "attack", u.ranged)
	if "Lifetap" in u.flags and dealt > 0.0: _heal(u, dealt * 0.25)
	if u.gear.has("lifesteal") and dealt > 0.0:
		_heal(u, dealt * float(u.gear.lifesteal))
		_item_used(u)
	if u.gear.get("dispel_hit", false): _item_used(u)
	if "Disenchant" in u.flags or u.gear.get("dispel_hit", false): _dispel(target)
	var a := u.ability
	if not target.dead and not _immune(target):
		match String(a.get("kind", "")):
			"poison": _poison(target, raw * float(a.share), float(a.seconds), u.id)
			"venom":
				_poison(target, raw * float(a.share), float(a.seconds), u.id)
				if target.venoms.is_empty(): target.venoms.append({"left": float(a.seconds), "threshold": float(a.threshold), "source": u.id})
			"weaken":
				target.weakened = maxf(target.weakened, float(a.attack))
				target.weakened_left = float(a.seconds)
			"burn": target.burn_left = maxf(target.burn_left, float(a.seconds))
			"silence_hit": target.silenced = maxf(target.silenced, float(a.seconds))
	if String(a.get("kind", "")) == "grow": u.growth = mini(int(a.limit), u.growth + 1)
	if not target.dead and u.gear.has("poison"):
		_poison(target, raw * float(u.gear.poison), 3.0, u.id)
		_item_used(u)
	if not target.dead and u.gear.has("venom") and target.venoms.is_empty() and not _immune(target):
		target.venoms.append({"left": 4.0, "threshold": float(u.gear.venom), "source": u.id})
		_item_used(u)
	if not target.dead and u.gear.has("paralyze") and rng.randf() < float(u.gear.paralyze):
		_stun(target, float(u.gear.paralyze_seconds))
		_item_used(u)
	# Thorns: melee hits on a spiked carrier.
	if not u.ranged and target.gear.has("thorns") and not u.dead:
		_item_used(target)
		_harm(u, float(target.gear.thorns), target.id, "thorns")
	if u.gear.has("storm") and u.hits_dealt % int(u.gear.storm_every) == 0:
		var other := _nearest_enemy(target, 4.0, u.team, target)
		if other != null:
			_emit("ability", {"u": u.id, "t": [other.id], "a": "storm"})
			_item_used(u)
			_harm(other, float(u.gear.storm), u.id, "storm")
	# Trample: a killing blow carries on into the next enemy.
	if target.dead and "Trample" in u.flags:
		var excess := maxf(0.0, raw - before) + raw * 0.25
		var next := _nearest_enemy(target, 2.6, u.team, target)
		if next != null and excess > 0.0: _harm(next, maxf(excess * 0.2, excess - next.defense), u.id, "trample")

func _nearest_enemy(around: Fighter, radius: float, team: int, exclude: Fighter) -> Fighter:
	var best: Fighter = null
	var best_distance := radius
	for o: Fighter in units:
		if o.dead or o.team == team or o == exclude: continue
		var distance := o.pos.distance_to(around.pos)
		if distance <= best_distance:
			best_distance = distance
			best = o
	return best

func _immune(target: Fighter) -> bool:
	return "NoTarget" in target.flags or "NoAffect" in target.flags

func _poison(target: Fighter, total: float, seconds: float, source: int) -> void:
	if total <= 0.0 or seconds <= 0.0: return
	target.poisons.append({"dps": total / seconds, "left": seconds, "source": source})

func _stun(target: Fighter, seconds: float) -> void:
	if target.dead: return
	target.stunned = maxf(target.stunned, seconds)
	_emit("stun", {"u": target.id, "d": seconds})

func _dispel(target: Fighter) -> void:
	if target.shield <= 0.0 and target.haste <= 0.0 and target.bless_attack <= 0.0: return
	target.shield = 0.0
	target.haste = 0.0
	target.haste_left = 0.0
	target.bless_attack = 0.0
	target.bless_left = 0.0
	_emit("dispel", {"u": target.id})

func _heal(u: Fighter, amount: float) -> void:
	if u.dead or amount <= 0.0 or u.burn_left > 0.0: return
	var before := u.hp
	u.hp = minf(u.max_hp, u.hp + amount)
	if u.hp - before >= 1.0: _emit("heal", {"u": u.id, "v": roundi(u.hp - before)})

## Applies damage after shields; returns the health actually lost.
func _harm(target: Fighter, amount: float, source: int, kind: String, ranged := false) -> float:
	if target.dead or amount <= 0.0: return 0.0
	var dealer := unit(source)
	if kind in ["ability", "storm", "rod"] and "Outerplanar" in target.flags: amount *= 0.75
	if kind in ["ability", "storm", "rod"] and target.gear.has("spell_guard"):
		amount *= 1.0 - float(target.gear.spell_guard)
		_item_used(target)
	if kind in ["ability", "storm", "rod"] and target.gear.has("reflect") and dealer != null and dealer.team != target.team:
		_item_used(target)
		_harm(dealer, amount * float(target.gear.reflect), target.id, "thorns")
	var absorbed := minf(target.shield, amount)
	target.shield -= absorbed
	amount -= absorbed
	var lost := minf(target.hp, amount)
	if kind != "poison": target.last_hurt = time
	target.hp -= amount
	if dealer != null and dealer.team != target.team:
		dealer.dealt += lost + absorbed
		if lost + absorbed > 0.0: quiet = 0.0
	if kind != "poison" or target.hp <= 0.0:
		_emit("hit", {"u": target.id, "s": source, "v": roundi(lost + absorbed), "kind": kind, "ranged": ranged})
	if target.hp <= 0.0:
		_die(target, source)
	else:
		_after_wound(target)
	return lost

func _after_wound(target: Fighter) -> void:
	if target.gear.has("ward") and not target.ward_used and target.hp < target.max_hp * 0.4:
		target.ward_used = true
		_emit("ability", {"u": target.id, "t": [target.id], "a": "ward"})
		_item_used(target)
		_heal(target, target.max_hp * float(target.gear.ward))
	if target.gear.has("dust") and not target.dust_used and target.hp < target.max_hp * 0.5:
		target.dust_used = true
		var hit: Array[int] = []
		for o: Fighter in units:
			if o.dead or o.team == target.team or o.pos.distance_to(target.pos) > float(target.gear.dust_radius): continue
			o.dusted = float(target.gear.dust)
			hit.append(o.id)
		_emit("ability", {"u": target.id, "t": hit, "a": "dust"})
		_item_used(target)
	# Ring of Command: one wounded enemy changes sides.
	for holder: Fighter in units:
		if holder.dead or holder.team == target.team or not holder.gear.has("command") or commanded[holder.team]: continue
		if target.tier >= 5 or target.hp > target.max_hp * float(holder.gear.command) or _immune(target): continue
		commanded[holder.team] = true
		target.team = holder.team
		target.target = -1
		target.action = ""
		target.facing += PI
		_emit("team", {"u": target.id, "team": target.team, "s": holder.id})
		_item_used(holder)
		break

func _die(target: Fighter, source: int) -> void:
	target.dead = true
	target.hp = 0.0
	target.action = ""
	target.moving = false
	target.poisons.clear()
	target.venoms.clear()
	target.death_time = time
	deaths += 1
	_death_marks[target.id] = deaths
	_emit("death", {"u": target.id, "s": source})
	for o: Fighter in units:
		if o.dead: continue
		if String(o.ability.get("kind", "")) == "corpse_eater" and o.pos.distance_to(target.pos) <= float(o.ability.radius):
			_heal(o, o.max_hp * float(o.ability.heal))
		if o.target == target.id: o.target = -1
	if String(target.ability.get("kind", "")) == "death_aura": _death_aura(target)
	if target.gear.has("knight") and not target.echo:
		var knight := _add({"code": "RDKN", "tier": 3, "rank": mini(target.rank, 1), "point": [target.pos.x, target.pos.y], "family": -1}, target.team, true)
		knight.max_hp = ceilf(target.max_hp * float(target.gear.knight))
		knight.hp = knight.max_hp
		knight.facing = target.facing
		_emit("spawn", {"u": knight.id})
		_item_used(target)
	elif target.gear.has("revive") and not target.revived:
		target.revived = true
		_restore(target, float(target.gear.revive))
		_item_used(target)
	# Hoppers rise again after enough creatures have fallen.
	for o: Fighter in units:
		if not o.dead or o.rise_used or String(o.ability.get("kind", "")) != "rise" or o == target: continue
		if deaths - int(_death_marks.get(o.id, deaths)) >= int(o.ability.deaths):
			o.rise_used = true
			_restore(o, float(o.ability.health))

func _restore(u: Fighter, share: float) -> void:
	u.dead = false
	u.hp = maxf(1.0, ceilf(u.max_hp * share))
	u.action = ""
	u.target = -1
	u.stunned = 0.0
	u.poisons.clear()
	u.venoms.clear()
	u.revived = true
	_emit("revive", {"u": u.id})

func _death_aura(u: Fighter) -> void:
	var amount := u.ability_power * float(u.ability.scale)
	var hit: Array[int] = []
	for o: Fighter in units:
		if o.dead or o == u: continue
		hit.append(o.id)
	_emit("ability", {"u": u.id, "t": hit, "a": "death_aura"})
	for id: int in hit:
		var o := unit(id)
		if o != null and not o.dead: _harm(o, amount, u.id, "ability")

func _rod(u: Fighter, target: Fighter) -> void:
	u.rod_left = float(u.gear.rod_every)
	var hit: Array[int] = [target.id]
	if u.gear.has("rod_splash"):
		for o: Fighter in units:
			if not o.dead and o.team != u.team and o != target: hit.append(o.id)
	_emit("ability", {"u": u.id, "t": hit, "a": "rod", "item": u.item})
	_item_used(u)
	_harm(target, float(u.gear.rod), u.id, "rod")
	for i in range(1, hit.size()):
		var o := unit(hit[i])
		if o != null and not o.dead: _harm(o, float(u.gear.rod_splash), u.id, "rod")

func _nova_match(o: Fighter, filter: String) -> bool:
	match filter:
		"flying": return "Fly" in o.flags
		"ground": return "Fly" not in o.flags
	return true

func _ability_target(u: Fighter) -> Fighter:
	var a := u.ability
	var enemies := _alive(1 - u.team).filter(func(o: Fighter) -> bool: return not _immune(o))
	if enemies.is_empty(): return null
	var current := unit(u.target)
	match String(a.kind):
		"execute":
			var best: Fighter = null
			var pick := String(a.get("pick", "weakest"))
			for o: Fighter in enemies:
				if best == null: best = o
				elif pick == "weakest_attack" and o.damage < best.damage: best = o
				elif pick == "weakest" and o.hp / o.max_hp < best.hp / best.max_hp: best = o
			return best
		"bolt":
			match String(a.get("target", "")):
				"farthest":
					var best: Fighter = null
					for o: Fighter in enemies:
						if best == null or o.pos.distance_to(u.pos) > best.pos.distance_to(u.pos): best = o
					return best
				"toughest":
					var best: Fighter = null
					for o: Fighter in enemies:
						if best == null or o.hp > best.hp: best = o
					return best
				"attacker":
					for o: Fighter in enemies:
						if o.action == "attack" and o.action_target >= 0 and unit(o.action_target) != null and unit(o.action_target).team == u.team: return o
		"stun":
			if String(a.mode) == "frontline":
				for o: Fighter in enemies:
					if not o.ranged and o.action == "attack": return o
				return null
	if current != null and not current.dead and current.team != u.team and not _immune(current): return current
	var nearest: Fighter = null
	for o: Fighter in enemies:
		if nearest == null or o.pos.distance_to(u.pos) < nearest.pos.distance_to(u.pos): nearest = o
	return nearest

func _ability(u: Fighter, target: Fighter) -> void:
	if u.dead: return
	var a := u.ability
	var power := u.ability_power * float(a.get("scale", 1.0))
	match String(a.kind):
		"bolt":
			if target == null or target.dead: target = _ability_target(u)
			if target == null: return
			_emit("ability", {"u": u.id, "t": [target.id], "a": "bolt"})
			_harm(target, power, u.id, "ability")
		"nova":
			var hit: Array[int] = []
			for o: Fighter in _alive(1 - u.team):
				if _nova_match(o, String(a.filter)) and not _immune(o): hit.append(o.id)
			var amount := power
			if hit.is_empty() and a.has("fallback"):
				for o: Fighter in _alive(1 - u.team):
					if not _immune(o): hit.append(o.id)
				amount = u.ability_power * float(a.fallback)
			_emit("ability", {"u": u.id, "t": hit, "a": "nova"})
			for id: int in hit:
				var o := unit(id)
				if o != null and not o.dead: _harm(o, amount, u.id, "ability")
		"execute":
			if target == null or target.dead: target = _ability_target(u)
			if target == null: return
			var threshold := float(a.threshold)
			if a.has("per_race"):
				var same := units.filter(func(o: Fighter) -> bool: return not o.dead and o.team == u.team and o.race == String(a.per_race)).size()
				threshold += float(a.per) * maxi(0, same - 1)
			_emit("ability", {"u": u.id, "t": [target.id], "a": "execute"})
			if target.tier < 5 and target.hp <= target.max_hp * threshold: _harm(target, target.hp + target.shield + 1.0, u.id, "destroy")
			else: _harm(target, power, u.id, "ability")
		"stun":
			var hit: Array[Fighter] = []
			match String(a.mode):
				"frontline":
					for o: Fighter in _alive(1 - u.team):
						if not o.ranged and not _immune(o) and unit(o.target) != null and unit(o.target).team == u.team and o.pos.distance_to(unit(o.target).pos) < 4.0: hit.append(o)
				"race":
					if target != null:
						for o: Fighter in _alive(1 - u.team):
							if o.race == target.race and not _immune(o): hit.append(o)
				_:
					if target != null and not target.dead: hit.append(target)
			var ids: Array[int] = []
			for o: Fighter in hit: ids.append(o.id)
			_emit("ability", {"u": u.id, "t": ids, "a": "stun"})
			for o: Fighter in hit:
				_stun(o, float(a.seconds))
				_harm(o, power, u.id, "ability")
		"silence":
			if target == null or target.dead: return
			_emit("ability", {"u": u.id, "t": [target.id], "a": "silence"})
			target.silenced = maxf(target.silenced, float(a.seconds))
			target.cooldown = maxf(target.cooldown, 1.0)
			_harm(target, power, u.id, "ability")
		"rally":
			var ids: Array[int] = []
			for o: Fighter in units:
				if o.dead or o.team != u.team or o.race != String(a.race): continue
				o.haste = maxf(o.haste, float(a.haste))
				o.haste_left = float(a.seconds)
				ids.append(o.id)
			_emit("ability", {"u": u.id, "t": ids, "a": "rally"})
		"drain":
			if target == null or target.dead: return
			var bats := maxi(1, units.filter(func(o: Fighter) -> bool: return not o.dead and o.team == u.team and o.race == String(a.get("per_race", u.race))).size())
			var amount := power * (0.7 + 0.3 * bats)
			_emit("ability", {"u": u.id, "t": [target.id], "a": "drain"})
			var lost := _harm(target, amount, u.id, "ability")
			_heal(u, lost)
		"dispel":
			if target == null or target.dead: return
			_emit("ability", {"u": u.id, "t": [target.id], "a": "dispel"})
			_dispel(target)
			_harm(target, power, u.id, "ability")
		"revive":
			var fallen := _revive_candidate(u)
			if fallen == null: return
			_emit("ability", {"u": u.id, "t": [fallen.id], "a": "revive"})
			_restore(fallen, float(a.health))

func _revive_candidate(u: Fighter) -> Fighter:
	var a := u.ability
	var best: Fighter = null
	for o: Fighter in units:
		if not o.dead or o.team != u.team or o.revived or o.echo or o == u: continue
		if time - o.death_time < 1.0: continue
		if a.has("race") and o.race != String(a.race): continue
		if a.has("max_tier") and o.tier > int(a.max_tier): continue
		if best == null or o.tier * 3 + o.rank > best.tier * 3 + best.rank: best = o
	return best

func _check_end() -> void:
	var home := _alive(0).size()
	var visitor := _alive(1).size()
	if home == 0 or visitor == 0 or time >= TIME_LIMIT or quiet >= QUIET_LIMIT: _finish()

func _finish() -> void:
	finished = true
	var home := _alive(0).size()
	var visitor := _alive(1).size()
	if home > 0 and visitor == 0: winner = 0
	elif visitor > 0 and home == 0: winner = 1
	else: winner = -1
	_emit("end", {"winner": winner})

## Player damage of the surviving recruits of `team` (summons/creeps: 0).
func survivor_damage(team: int) -> int:
	var total := 0
	for u: Fighter in _alive(team):
		if u.creep or u.echo or u.family < 0: continue
		total += ELAutochessRules.survivor_damage(u.family, u.rank)
	return total

## Damage dealt by each recruit uid of `team` (the damage panel).
func damage_by_uid(team: int) -> Dictionary:
	var result := {}
	for u: Fighter in units:
		if u.team != team and not (u.echo and u.team == team): continue
		if u.uid > 0: result[u.uid] = int(result.get(u.uid, 0)) + roundi(u.dealt)
	return result

## A compact state for scouting/online replicas.
func snapshot() -> Dictionary:
	var rows: Array = []
	for u: Fighter in units:
		rows.append([u.id, u.team, u.code, u.rank, snappedf(u.pos.x, 0.01), snappedf(u.pos.y, 0.01), snappedf(u.facing, 0.01),
			roundi(u.hp), roundi(u.max_hp), u.action, 1 if u.dead else 0, 1 if u.moving else 0, roundi(u.shield), u.uid, u.family, u.item])
	return {"time": snappedf(time, 0.01), "units": rows, "finished": finished, "winner": winner}
