class_name ELAdventureClock
extends RefCounted
## The second game has a travel clock separate from the strategic AP statistic.
const DAILY_POINTS := 8

static func initialize(hero: Dictionary) -> void:
	hero.travel_version = 1
	hero.travel_capacity = DAILY_POINTS
	hero.travel_day = 0
	hero.ap = DAILY_POINTS

static func restore(hero: Dictionary, day: int) -> bool:
	if not hero.has("travel_version"):
		# Earlier saves confused authored strategic AP with the travel clock.
		initialize(hero)
		hero.travel_day = day
	if not ELLuaSave._integer(hero.travel_version, 1, 1) or not ELLuaSave._integer(hero.get("travel_capacity"), 1, 16) or not ELLuaSave._integer(hero.get("travel_day"), 0, 0xffffffff) or not ELLuaSave._integer(hero.get("ap"), 0, 10000000): return false
	for key: String in ["travel_capacity", "travel_day", "ap"]: hero[key] = int(hero[key])
	return true

static func use_points(state: ELAdventureSession, hero: Dictionary, amount: int) -> bool:
	if state.map.profile.id != "el2" or hero.is_empty() or not hero.get("alive", false) or hero.get("type") not in ["hero", "monster"] or amount < 0: return false
	while amount > 0:
		var remaining: int = hero.ap
		# Spending from a script-forced zero starts a fresh day and consumes
		# that request. Ordinary movement rolls over on the final paid point.
		var spent := mini(remaining, amount)
		hero.ap -= spent
		ELColorless.drain(state, hero, spent)
		amount = amount - spent if remaining > 0 else 0
		if hero.ap == 0: end_day(state, hero)
	return true

static func end_day(state: ELAdventureSession, hero: Dictionary) -> bool:
	if state.map.profile.id != "el2" or hero.is_empty() or not hero.get("alive", false) or hero.get("type") not in ["hero", "monster"]: return false
	hero.ap = int(hero.travel_capacity)
	hero.travel_day += 1
	if hero.uid == state.main_hero:
		state.day += 1
		hero.travel_day = state.day
		for other: Dictionary in state.objects.values():
			if other.uid == hero.uid or not other.alive or other.get("type") not in ["hero", "monster"]: continue
			other.ap = int(other.travel_capacity)
			other.travel_day += 1
		ELBattlegrounds.new_day(state)
		ELResourceSites.settle_income(state, true)
		# CCloseBowls runs before the begin-of-turn fog recompute.
		ELFog.close_eyes(state)
		state.event.emit({"kind": "day_changed", "day": state.day})
	return true

static func end_player_day(state: ELAdventureSession, player: int) -> bool:
	for hero: Dictionary in state.objects.values():
		if hero.get("type") in ["hero", "monster"] and hero.alive and hero.owner == player: return end_day(state, hero)
	return false
