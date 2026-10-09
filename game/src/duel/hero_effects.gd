class_name ELHeroEffects
extends RefCounted
## Combat skills use the affected hero's own turn count, including the first.

static func extra_draw(hero: Dictionary) -> bool:
	var rank := int(hero.get("skills", {}).get("CONC", -1))
	return rank >= 0 and rank <= 2 and int(hero.turns) % (4 - rank) == 0

static func regenerates(hero: Dictionary) -> bool:
	var rank := int(hero.get("skills", {}).get("REGN", -1))
	if rank == 2: return true
	return rank in [0, 1] and (int(hero.turns) - 1) % (3 - rank) == 1

## `extra` brings it earlier (second-game Gift: two turns per gifted creature).
static func disturbance(edition: String, hero: Dictionary, opponent: Dictionary, extra := 0) -> int:
	var own_delay := int(hero.get("skills", {}).get("CNLG", -1)) + 1
	var enemy_delay := int(opponent.get("skills", {}).get("CNLG", -1)) + 1
	var elapsed := int(hero.turns) - 1 - int(hero.level) - 10 - own_delay + enemy_delay + extra
	if elapsed <= 0: return 0
	if edition == "el1": return elapsed
	# Saturate once the result exceeds every legal hero health value.
	return int(minf(pow(1.5, mini(elapsed, 53)), 2147483647.0))
