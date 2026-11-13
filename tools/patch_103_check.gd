extends SceneTree
## Check of the Etherlords II update 1.03 rules (ELPatch103, ELDuel,
## ELCatalog): prepared battles for each changed card and rule, and the
## upgrade of release 1.01 card tables and texts. Prints one line per check
## and exits 1 when any failed.
##
##   godot --headless --path game --script ../tools/patch_103_check.gd -- [--el2=<Etherlords II folder>]
##
## Needs the player's Etherlords II files (user://profiles.json or --el2).

var failures: Array[String] = []
var profile: ELProfile

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.get_slice("=", 1)
	return fallback

func _initialize() -> void:
	_upgrade_checks()
	var folder := _arg("el2", "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get("el2", ""))
	if folder.is_empty(): folder = String(ELContentLibrary.steam_folders().get("el2", ""))
	profile = ELProfile.new()
	if folder.is_empty() or not profile.mount("el2", folder):
		printerr("Etherlords II is required: pass --el2=<folder>")
		quit(1)
		return
	print("Installed card tables: release ", "1.01 (upgraded)" if profile.release_is_old() else "1.03")
	_table_checks()
	_turn_checks()
	_spell_checks()
	_creature_checks()
	_discard_checks()
	_fix_checks()
	_pale_copy_checks()
	print("%d failed" % failures.size())
	quit(1 if not failures.is_empty() else 0)

## Release 1.01 values and texts are brought up to 1.03; 1.03 ones are kept.
func _upgrade_checks() -> void:
	var old_spells := {"MNBR": {"Class": "Sorcery", "Cost": 2}, "ETCH": {"Cost": 3}, "GIFT": {"Cost": 1}}
	check(ELPatch103.release(old_spells) == ELPatch103.RELEASE_OLD, "a sorcery Ether Breeze marks release 1.01 tables")
	ELPatch103.upgrade_table("CombatSpells", old_spells, true)
	check(old_spells.MNBR.Class == "Enchantment" and old_spells.MNBR.Cost == 3 and old_spells.MNBR.AbilityText == "Ab365" and old_spells.ETCH.Cost == 4 and old_spells.GIFT.Cost == 2, "1.01 spell table upgraded")
	var creatures := {"KBGD": {"Flags": "TeamAttack"}, "OGKN": {"Power": 8, "Toughness": 6}}
	ELPatch103.upgrade_table("CombatCreatures", creatures, true)
	check(creatures.KBGD.Flags == ["TeamAttack", "Disenchant"] and creatures.OGKN.Power == 7 and creatures.OGKN.Toughness == 8, "1.01 creature table upgraded")
	var current := {"OGKN": {"Power": 5}}
	ELPatch103.upgrade_table("CombatCreatures", current, false)
	check(current.OGKN.Power == 5, "1.03 (or modded) tables are left as they are")
	var texts := {"MNBRNm": "Эфирный Бриз", "VOLCTt": "Дает 2 эфирных канала", "WEAKTt": "Сила и здоровье уменьшаются на 4",
		"OUD1Tt": "Отдых, 2 кванта эфира: уничтожить создание в Эфирном Плане, если его сила меньше силы этого Жнеца", "T_MAIN_MENU_VERSION": "Версия 1.01"}
	ELPatch103.upgrade_texts(texts, true)
	check(texts.VOLCTt.contains("3") and texts.has("Ab365") and texts.Ab365.contains("Эфирный Бриз") and texts.WEAKTt.contains("сбрасывает 3") and texts.OUD1Tt.contains("телохранителем") and texts.T_MAIN_MENU_VERSION == "Версия 1.03",
		"1.01 Russian texts describe the 1.03 cards")
	var english := {"MNBRNm": "Ether Breeze", "KBGDTt": "Team Attacker"}
	ELPatch103.upgrade_texts(english, true)
	check(english.KBGDTt == "Team Attacker. Disenchant" and english.has("MNVRTt") and english.MNVRTt.begins_with("At the start"), "1.01 English texts describe the 1.03 cards")

func _table_checks() -> void:
	var spells := profile.table("CombatSpells")
	var creatures := profile.table("CombatCreatures")
	check(int(spells.ETCH.Cost) == 4 and int(spells.GBBR.Cost) == 1 and int(spells.GBIN.Cost) == 2 and int(spells.GIFT.Cost) == 2, "1.03 costs (resonance 4, gibberlings 1 and 2, gift 2)")
	check(spells.MNBR.Class == "Enchantment" and spells.MNST.Class == "Enchantment" and spells.MNVR.Class == "Sorcery", "breeze and storm are enchantments, vortex a sorcery")
	check(int(creatures.OGKN.Power) == 7 and int(creatures.OGKN.Toughness) == 8, "ogre king is 7/8")
	check(ELCatalog.flags(creatures.KBGD).has("Disenchant") and ELCatalog.flags(creatures.ORGD).has("Disenchant"), "kobold and orc guards disenchant")
	check(String(profile.table("HeroesSpecs").RVVE.Chance).to_lower() == "med", "rebirth has the medium chance")
	check(int(spells.VOLC.Cost) == 5 and ELCatalog.rule(profile, "VOLC").get("amount") == 3 and not ELCatalog.rule(profile, "VOLC").has("amount_el2"), "volcano costs 5 and gives 3 channels")

func _duel(seed := 212) -> ELDuel:
	var d := ELDuel.new()
	d.start(profile, seed)
	return d

## Ends phases until `side` starts its attack phase.
func _to_turn(d: ELDuel, side: int) -> void:
	for i in 8:
		d.end_phase()
		if d.attacker == side and d.phase == ELDuel.Phase.ATTACK: return

func _summon(d: ELDuel, side: int, card: String) -> int:
	d._summon(side, card)
	var id := d.next_id - 1
	if d.creatures.has(id):
		d.creatures[id].sick = false
		d.creatures[id].resting = false
	return id

func _turn_checks() -> void:
	var d := _duel()
	check(d.attacker == 0 and d.heroes[0].mana == d.heroes[0].channels, "the first side gets no extra ether")
	_to_turn(d, 1)
	check(d.heroes[1].turns == 1 and d.heroes[1].mana == d.heroes[1].channels + 1, "the second side gets 1 extra ether on its first turn")
	_to_turn(d, 1)
	check(d.heroes[1].mana == d.heroes[1].channels, "only on its first turn")
	# The combat tutorial (original flag 0xb0) gives no such bonus.
	d = ELDuel.new()
	d.start(profile, 212, {"combat_tutorial": true})
	_to_turn(d, 1)
	check(d.heroes[1].mana == d.heroes[1].channels, "no first-turn bonus in the combat tutorial")
	# Ether vortex: a hero enchantment of its caster that doubles the ether of the
	# caster's next turn and ends with that turn.
	d = _duel()
	check(d.cast_free(0, "MNVR", [], false), "vortex cast")
	check(d._enchantment_count(0, "MNVR") == 1, "vortex stays on its caster until it pays")
	_to_turn(d, 1)
	check(d.heroes[1].mana == d.heroes[1].channels + 1, "the opponent gets nothing from the vortex")
	_to_turn(d, 0)
	check(d.heroes[0].mana == 2 * d.heroes[0].channels, "vortex doubles the next turn's ether")
	_to_turn(d, 1)
	check(d._enchantment_count(0, "MNVR") == 0, "vortex ends with the caster's next turn")
	_to_turn(d, 0)
	check(d.heroes[0].mana == d.heroes[0].channels, "vortex pays once")
	# Ether breeze and storm on a creature feed their caster each turn; the new
	# channel already counts for that turn's ether.
	d = _duel()
	var carrier := _summon(d, 1, "KBGD")
	check(d.cast_free(0, "MNBR", [carrier], false) and d.cast_free(0, "MNST", [carrier], false), "breeze and storm cast on an enemy creature")
	var channels: int = d.heroes[0].channels
	_to_turn(d, 1)
	check(d.heroes[1].mana == d.heroes[1].channels + 1, "the holder's controller gains nothing")
	_to_turn(d, 0)
	var income := int(profile.table("CombatManaIncome").get(str(d.heroes[0].turns), {}).get("Level%d" % d.heroes[0].level, 0))
	check(d.heroes[0].channels == channels + income + 1 and d.heroes[0].mana == d.heroes[0].channels + 3, "the caster gains 1 channel, then 3 ether")
	d._kill(carrier)
	channels = d.heroes[0].channels
	_to_turn(d, 1)
	_to_turn(d, 0)
	income = int(profile.table("CombatManaIncome").get(str(d.heroes[0].turns), {}).get("Level%d" % d.heroes[0].level, 0))
	check(d.heroes[0].channels == channels + income and d.heroes[0].mana == d.heroes[0].channels, "nothing once the carrier is gone")
	# Under stasis the ether is not refreshed, so the breeze gives nothing.
	d = _duel()
	carrier = _summon(d, 0, "KBGD")
	d.cast_free(0, "MNBR", [carrier], false)
	d._enchant("STSI", 1, 1, {})
	_to_turn(d, 1)
	d.heroes[0].mana = 0
	_to_turn(d, 0)
	check(d.heroes[0].mana == 0, "no breeze ether under stasis")
	# Orc shaman: 1 ether at its owner's turn start, also from the plane.
	d = _duel()
	var shaman := _summon(d, 0, "ORSH")
	_summon(d, 1, "ORSH")
	_to_turn(d, 1)
	check(d.heroes[1].mana == d.heroes[1].channels + 2, "an orc shaman adds to the first-turn bonus")
	_to_turn(d, 0)
	check(d.heroes[0].mana == d.heroes[0].channels + 1, "an orc shaman gives its owner 1 ether a turn")
	d.creatures[shaman].plane = true
	_to_turn(d, 1)
	_to_turn(d, 0)
	check(d.heroes[0].mana == d.heroes[0].channels + 1, "a shaman sent to the plane still gives its ether")

func _spell_checks() -> void:
	var d := _duel()
	var channels: int = d.heroes[0].channels
	check(d.cast_free(0, "VOLC", [], false) and d.heroes[0].channels == channels + 3, "volcano gives 3 channels")
	# Ethereal resonance doubles the mirrored damage.
	d = _duel()
	d.cast_free(0, "ETCH", [], false)
	var enemy: int = d.heroes[1].health
	d._damage(0, 3)
	check(d.heroes[1].health == enemy - 6, "resonance mirrors double damage")
	# Data attraction: 2 damage that a lifeguard does not stop.
	d = _duel()
	d.cast_free(0, "TRLB", [], false)
	d.cast_free(0, "LFGR", [0], false)
	var health: int = d.heroes[0].health
	d.cast_free(0, "ZAPP", [1], false)
	check(d.heroes[0].health == health - 2 and d._enchantment_count(0, "LFGR") == 1, "attraction hurts by 2 through a lifeguard")
	# Burning graves: 3 per creature, then the graveyards are emptied.
	d = _duel()
	d.heroes[0].grave = ["KBGD", "KBGD"]
	d.heroes[1].grave = ["KBGD"]
	var before := [int(d.heroes[0].health), int(d.heroes[1].health)]
	d.cast_free(0, "BRGR", [], false)
	check(d.heroes[0].health == before[0] - 6 and d.heroes[1].health == before[1] - 3 and d.heroes[0].grave.is_empty() and d.heroes[1].grave.is_empty(), "burning graves deal 3 per creature and empty the graveyards")
	# Barbed souls count only their caster's own creatures.
	d = _duel()
	d.cast_free(0, "BASO", [], false)
	var foe := _summon(d, 1, "KBGD")
	var own := _summon(d, 0, "KBGD")
	var hands := [d.heroes[0].hand.size(), d.heroes[1].hand.size()]
	d._kill(foe)
	check(d.heroes[0].hand.size() == hands[0] and d.heroes[1].hand.size() == hands[1], "barbed souls ignore the enemy's creatures")
	d._kill(own)
	check(d.heroes[0].hand.size() == hands[0] + 1, "barbed souls draw for the caster's own creature")
	# Dissolution works with no ether.
	d = _duel()
	d.cast_free(0, "SACR", [], false)
	var victim := _summon(d, 0, "KBGD")
	d.heroes[0].mana = 0
	var key := ""
	for ability: Dictionary in d.abilities(0):
		if String(ability.key).begins_with("sacrifice"): key = ability.key
	var drawn: int = d.heroes[0].hand.size()
	check(not key.is_empty() and d.use_ability(0, key, victim) and d.heroes[0].hand.size() == drawn + 2, "dissolution works with 0 ether")
	# Blast reaches an enchantment cast before a grass snake's growth mark.
	d = _duel()
	var snake := _summon(d, 0, "GRSN")
	d.cast_free(0, "LSST", [snake], false)
	d._mark(snake, "GRSN", 1, 1, {"fixed": true})
	d.cast_free(1, "OBLS", [snake], false)
	check(d.creatures.has(snake) and d._enchantment_count(snake, "LSST") == 0 and d._enchantment_count(snake, "GRSN") == 1, "blast removes the enchantment under a growth mark")
	# Ravaging hunger does not strike a creature a water link brought back.
	d = _duel()
	var ogre := _summon(d, 0, "GROG")
	d.cast_free(1, "WTLK", [ogre], false)
	d.cast_free(0, "RVHG", [], false)
	var back := d.army(1).filter(func(c: Dictionary) -> bool: return c.card == "GROG")
	check(not d.creatures.has(ogre) and back.size() == 1, "a linked creature returns once and stays")
	# Water link takes the creature's own card from the graveyard.
	d = _duel()
	var linked := _summon(d, 1, "KBGD")
	d.cast_free(0, "WTLK", [linked], false)
	d.heroes[1].grave = ["ORSH"]
	d._kill(linked)
	check(d.heroes[1].grave == ["ORSH"] and d.army(0).any(func(c: Dictionary) -> bool: return c.card == "KBGD"), "water link leaves no copy in the graveyard")

func _creature_checks() -> void:
	var d := _duel()
	var guard := _summon(d, 0, "KBGD")
	check(d.has_flag(guard, "Disenchant"), "a kobold guard disenchants in battle")
	# Orc ritual: rest, a channel: remove an enchantment.
	var shaman := _summon(d, 0, "ORSH")
	var target := _summon(d, 1, "KBGD")
	d.cast_free(1, "LSST", [target], false)
	var e_id := -1
	for e: Dictionary in d.creatures[target].enchantments:
		if e.card == "LSST": e_id = int(e.id)
	d.heroes[0].channels = 2
	check(d.use_ability(shaman, "orc_rite", target, e_id) and d.heroes[0].channels == 1 and d._enchantment_count(target, "LSST") == 0 and d.creatures[shaman].resting, "the orc ritual trades a channel for an enchantment")
	d.creatures[shaman].resting = false
	d.heroes[0].channels = 0
	d.cast_free(1, "LSST", [target], false)
	for e: Dictionary in d.creatures[target].enchantments:
		if e.card == "LSST": e_id = int(e.id)
	check(not d.use_ability(shaman, "orc_rite", target, e_id), "the orc ritual needs a channel")
	# A dying bat makes the enemy discard.
	d = _duel()
	var bat := _summon(d, 0, "BATT")
	var hand: int = d.heroes[1].hand.size()
	d._kill(bat)
	check(d.heroes[1].hand.size() == hand - 1, "a dying bat makes the enemy discard a spell")
	# A giant bat's hit on the hero draws its owner a spell.
	d = _duel()
	var giant := _summon(d, 0, "GBAT")
	while d.heroes[0].hand.size() > 3: d._take_card(0, 0)
	var seen := d.history.size()
	d.toggle_attack(giant)
	d.end_phase()
	d.end_phase()
	var draws := d.history.slice(seen).filter(func(x: Dictionary) -> bool: return x.get("kind") == "draw" and int(x.get("side", -1)) == 0)
	check(draws.size() == 1 and d.heroes[0].hand.size() == 4, "a giant bat's hit on the hero draws a spell")
	# The Pale Scourge spares walls.
	d = _duel()
	var scourge := _summon(d, 0, "OUD1")
	var wall_card := ""
	for card: String in profile.table("CombatCreatures"):
		if str(profile.table("CombatCreatures")[card].get("Race", "")) == "Wall" and not ELCatalog.rule(profile, card).is_empty():
			wall_card = card
			break
	var wall := _summon(d, 1, wall_card)
	d.heroes[0].mana = 10
	check(not d.use_ability(scourge, "pale_devour", wall) and d.error == "Walls cannot be devoured." and d.creatures.has(wall), "the Pale Scourge cannot devour a wall (%s)" % wall_card)
	# Rebirth saves a hero only once.
	var saved := false
	var once := true
	for seed in 64:
		d = _duel(seed + 1)
		d.heroes[0].spec = "RVVE"
		d.heroes[0].spec_level = 20
		d.heroes[0].luck = 3
		d._damage(0, int(d.heroes[0].health))
		if d.heroes[0].health <= 0: continue
		saved = true
		for again in 4:
			if d.heroes[0].health > 0: d._damage(0, int(d.heroes[0].health))
		once = d.heroes[0].health <= 0
		break
	check(saved and once, "rebirth saves the hero only once")

func _discard_checks() -> void:
	# A gray ogre the opponent discards enters play; a self-discard does not.
	var d := _duel()
	while not d.heroes[1].hand.is_empty(): d._take_card(1, 0)
	d._give_card(1, "GROG")
	check(d.cast_free(0, "NOIS", [1], false), "noise cast at the enemy")
	check(d.army(1).any(func(c: Dictionary) -> bool: return c.card == "GROG") and d.heroes[1].hand.is_empty(), "a discarded gray ogre enters play")
	d = _duel()
	while not d.heroes[0].hand.is_empty(): d._take_card(0, 0)
	d._give_card(0, "OGKN")
	d.cast_free(0, "NOIS", [0], false)
	check(d.army(0).is_empty(), "a hero's own discard summons nothing")
	# A discarded weakness makes the discarding opponent drop three.
	d = _duel()
	while not d.heroes[1].hand.is_empty(): d._take_card(1, 0)
	d._give_card(1, "WEAK")
	for i in 3: d._give_card(0, "ZAPP")
	var hand: int = d.heroes[0].hand.size()
	d.cast_free(0, "NOIS", [1], false)
	check(d.heroes[0].hand.size() == hand - 3, "a discarded weakness makes the opponent discard 3")
	# The answers chain at once: the weakness's three discards hit a gray ogre,
	# which the weakness's side forced out, so it enters play for the caster.
	d = _duel()
	while not d.heroes[1].hand.is_empty(): d._take_card(1, 0)
	while not d.heroes[0].hand.is_empty(): d._take_card(0, 0)
	d._give_card(1, "WEAK")
	d._give_card(0, "GROG")
	var seen := d.history.size()
	d.cast_free(0, "NOIS", [1], false)
	var kinds := d.history.slice(seen).map(func(x: Dictionary) -> String: return "%s:%s" % [x.get("kind"), x.get("card", "")])
	check(d.army(0).any(func(c: Dictionary) -> bool: return c.card == "GROG") and kinds.find("discard_answer:WEAK") < kinds.find("discard_answer:GROG"), "discard answers chain in order")

func _fix_checks() -> void:
	# Removing quick fix kills a Pale creature instead of sending it to the plane.
	var d := _duel()
	var pale := _summon(d, 0, "OUS1")
	d.creatures[pale].plane = false
	d._enchant("QKFX", 0, pale, {})
	var e_id := -1
	for e: Dictionary in d.creatures[pale].enchantments:
		if e.card == "QKFX": e_id = int(e.id)
	d._remove_enchantment(pale, e_id)
	check(not d.creatures.has(pale), "removed quick fix kills a Pale creature")
	# Hostile ambience leaves arrivals in pale aspect ready.
	d = _duel()
	d.cast_free(1, "HOAM", [], false)
	d._summon(0, "OUS1")
	var arrival: Dictionary = d.creatures[d.next_id - 1]
	d._summon(0, "KBGD")
	check(arrival.get("plane", false) and not arrival.resting and d.creatures[d.next_id - 1].resting, "hostile ambience skips pale aspect arrivals")
	# Sacrificing men come back from a change of command ready.
	d = _duel()
	var razor := _summon(d, 1, "RZMN")
	d.cast_free(0, "CHCM", [razor], false)
	var chcm := -1
	for e: Dictionary in d.creatures[razor].enchantments:
		if e.card == "CHCM": chcm = int(e.id)
	d._remove_enchantment(razor, chcm)
	check(d.creatures[razor].owner == 1 and not d.creatures[razor].sick, "a razor man returns without summoning sickness")

## 1.03 swapped the copy prices: the Spellweaver pays 1+X, the Spellshifter 2+X.
func _pale_copy_checks() -> void:
	var printed := int(profile.table("CombatSpells").ENBR.Cost)
	for setup: Array in [["OUE2", "weave", 1], ["OUE3", "transpose", 2]]:
		for extra: int in [setup[2] - 1, setup[2]]:
			var d := _duel()
			var id := _summon(d, 0, setup[0])
			d.cast_free(1, "ENBR", [1], false)
			var e: Dictionary = d.heroes[1].enchantments.back()
			d.heroes[0].mana = printed + extra
			var hand: int = d.heroes[0].hand.size()
			var ok := d.use_ability(id, setup[1], 1, int(e.id))
			var paid: bool = ok and d.heroes[0].mana == 0 and d.heroes[0].hand.size() == hand + 1
			check(paid if extra == setup[2] else not ok, "%s copies an enchantment for %d+X ether%s" % [setup[0], setup[2], "" if extra == setup[2] else ", not less"])
