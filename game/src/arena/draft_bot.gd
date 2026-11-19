class_name ELArenaDraftBot
extends RefCounted
## Marginal deck value, not a list of independently high-rated cards. Bots
## see their present offer and their own picks only; combat AI is unchanged.

const STYLES: Array[String] = ["balanced", "aggressive", "control", "synergy"]

static func choose(draft: ELArenaDraft, style := "balanced") -> int:
	if draft == null or draft.profile == null or draft.finished() or draft.offer.size() != 3: return -1
	if style not in STYLES: style = "balanced"
	var stats := ELArenaRules.summary(draft.profile, draft.cards)
	var best := -INF
	var selected := 0
	for i in draft.offer.size():
		var score := _score(draft, draft.offer[i], stats, style)
		# Small stable taste differences avoid identical decisions for equally
		# strong alternatives. They cannot overwhelm a missing basic role.
		var random := RandomNumberGenerator.new()
		random.seed = int((draft.seed_value * 1103515245 + draft.cards.size() * 2654435761 + i * 12345) & 0x7fffffff)
		score += random.randf_range(-0.16, 0.16)
		if score > best:
			best = score
			selected = i
	return selected

static func make(source: ELProfile, faction: String, seed: int, style := "balanced", rules := ELArenaRules.OPEN_RULES) -> ELArenaDraft:
	var draft := ELArenaDraft.new()
	if not draft.create(source, faction, seed, rules): return draft
	while not draft.finished():
		if not draft.choose(choose(draft, style)): break
	return draft

static func _score(draft: ELArenaDraft, card: String, s: Dictionary, style: String) -> float:
	var f := ELArenaRules.features(draft.profile, card)
	var score := float(f.score)
	var count := draft.cards.size()
	var remaining := ELArenaRules.DECK_SIZE - count
	var desired_bodies := 11 if style == "aggressive" else (9 if style == "control" else 10)
	var desired_early := 5 if style == "aggressive" else 4
	var copies := int(s.counts.get(card, 0))
	if f.creature:
		if int(s.creatures) < desired_bodies: score += 2.0
		else: score -= 3.5 + 1.3 * (int(s.creatures) - desired_bodies)
		if desired_bodies - int(s.creatures) >= remaining: score += 6.0
		if f.threat: score += 0.5
		elif not f.generator and not f.interaction: score -= 1.4
	if f.early and int(s.early) < desired_early:
		score += 3.0 + (1.5 if count >= 8 else 0.0)
		if desired_early - int(s.early) >= remaining: score += 5.0
	if f.interaction:
		if int(s.interaction) < 3: score += 2.1
		elif not f.creature and int(s.interaction) >= 6: score -= 2.0
	if f.removal:
		if int(s.removal) < 2: score += 1.7
		if int(s.removal) == 0 and count >= 10: score += 2.0
	if f.dispel:
		if int(s.dispel) == 0: score += 3.3 + (1.5 if count >= 8 else 0.0)
		elif not f.creature: score -= 1.5 * int(s.dispel)
	if int(f.cost) >= 6:
		score -= 0.45 * (int(f.cost) - 5)
		if int(s.expensive) >= 2: score -= 2.8 * (int(s.expensive) - 1)
		if int(s.early) < 3: score -= 1.8
	if int(f.channels) > 0 and int(s.ramp) == 0: score -= 0.7 * int(f.channels)
	if f.needs_body and int(s.creatures) < 4: score -= 2.2
	if f.generator:
		score += 0.8 if int(s.generators) < 2 else -0.8
		if style == "synergy": score += 0.7
	var payoff := String(f.tribal_payoff)
	if not payoff.is_empty():
		var support := int(s.tribes.get(payoff, 0))
		score += minf(3.0, 0.7 * support)
		if support == 0 and int(f.power) == 0 and not f.generator: score -= 1.8
		if style == "synergy" and support > 0: score += 0.6
	if f.creature and not String(f.tribe).is_empty():
		for own: String in draft.cards:
			if ELArenaRules.features(draft.profile, own).tribal_payoff == f.tribe: score += 0.45
	if f.draw:
		if int(s.draw) == 0 and int(s.creatures) >= 5: score += 0.6
		elif int(s.draw) >= 2: score -= 2.0
	if f.ramp:
		score += 1.1 if int(s.expensive) >= 2 else -0.4
		if int(s.ramp) >= 2: score -= 2.8
	if f.conditional and int(s.conditional) >= 5 and not f.creature: score -= 1.5
	# Repeated permanent engines, narrow answers, healing and curve toppers
	# have much lower marginal value than another ordinary creature/removal.
	score -= 0.55 * copies
	if copies > 0 and (f.persistent or f.dispel and not f.creature or f.effect in ["half_heal", "full_heal", "heal", "sacrifice_heal"]): score -= 2.0 * copies
	if style == "aggressive" and f.creature and f.threat and int(f.cost) <= 4: score += 0.55
	if style == "control" and (f.removal or f.generator or f.draw): score += 0.55
	return score
