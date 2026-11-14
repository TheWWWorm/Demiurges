extends SceneTree
## Plays a first-game single map with the local player standing still and
## prints what the computer players do with their days: tasks, purchases at
## spell shops and component portals, skills, recruits and global spells.
##
##   godot --headless --path game --script ../tools/first_ai_sim.gd -- [--map=<id>|all] [--days=40]
##         [--campaign=Good|Evil] [--smart=true] [--free=true] [--difficulty=1]
##         [--list] [--quiet] [--dump]
##
## `--list` prints the single map ids. Without `--map` the first catalogue map
## with a spell shop is played; `--campaign` plays that campaign's chapters
## (all of them, or the one named by `--map`) from the human's seat. `--dump`
## adds each player's ether, global spells, books and known shops at the end.
## The run ends with a summary per computer player and exits 1 when a map
## stops with an error or a turn never settles.
##
## It needs the first game's files (user://profiles.json, as set up by the
## game); without them it is skipped. Nothing is saved.

var director: ELAdventureDirector
var state: ELAdventureSession
var quiet := false
var stats := {}
var stuck := false

func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.trim_prefix("--%s=" % name)
		if arg == "--" + name: return "true"
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no first-game files configured (user://profiles.json)")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: the first game's files could not be mounted")
		quit(0)
		return
	quiet = _arg("quiet", "false") == "true"
	var catalog := ELSingleScenario.catalog(profile)
	if _arg("list", "false") == "true":
		for entry: Dictionary in catalog: print("%s  %s  players=%s" % [entry.id, ELSingleScenario.title(profile, entry), str(entry.get("players", []).size())])
		quit(0)
		return
	var wanted := _arg("map", "")
	var failed := false
	var chapters := _arg("campaign", "")
	if not chapters.is_empty():
		# Campaign chapters ("Good", "Evil"...): the human's seat and the chapter rules.
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, chapters):
			print("SKIP: " + campaign.error)
			quit(0)
			return
		for row: Dictionary in campaign.scenarios:
			if not wanted.is_empty() and wanted != "all" and str(row.file_name) != wanted: continue
			var entry := {"id": str(row.file_name), "title": str(row.get("header", "")), "script": str(row.get("script", "")), "player": int(str(row.get("player", "1"))), "campaign": row.has("number")}
			if _play(profile, entry, int(_arg("days", "40")), false) == "fail": failed = true
		quit(1 if failed else 0)
		return
	for entry: Dictionary in catalog:
		if not wanted.is_empty() and wanted != "all" and str(entry.id) != wanted: continue
		var result := _play(profile, entry, int(_arg("days", "40")), wanted.is_empty())
		if result == "skip": continue
		if result == "fail": failed = true
		if wanted != "all": break
	quit(1 if failed else 0)

func _stat(player: int) -> Dictionary:
	if not stats.has(player): stats[player] = {"spells": 0, "runes": 0, "skills": 0, "recruits": 0, "globals": 0, "visits": 0, "idle": 0, "hero_days": 0, "kills": 0}
	return stats[player]

func _play(profile: ELProfile, entry: Dictionary, days: int, need_shop: bool) -> String:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, str(entry.id)):
		print("SKIP %s: %s" % [entry.id, map.error])
		return "skip"
	state = ELAdventureSession.new()
	if not state.start(map, int(_arg("difficulty", "1")), 212, str(entry.get("script", "")), int(entry.get("player", 1)), bool(entry.get("campaign", false))):
		print("SKIP %s: %s" % [entry.id, state.error])
		return "skip"
	director = ELAdventureDirector.new()
	if not director.build(state):
		print("SKIP %s: %s" % [entry.id, director.error])
		return "skip"
	var shops := 0
	var portals := 0
	for item: Dictionary in state.objects.values():
		if item.get("type") == "el1_spell_shop": shops += 1
		if item.get("type") == "rune_shop": portals += 1
	if need_shop and shops == 0: return "skip"
	director.smart_ai = _arg("smart", "true") == "true"
	director.free_movement = _arg("free", "true") == "true"
	director.fast_mode = true
	stats = {}
	stuck = false
	var books := {}
	state.event.connect(func(data: Dictionary):
		match data.get("kind"):
			"skill_learned":
				var hero := state.object(data.id)
				if int(hero.owner) != state.current_player: _stat(int(hero.owner)).skills += 1
			"hero_placed":
				var hero := state.object(data.id)
				if data.get("recruited", false) and int(hero.owner) != state.current_player:
					_stat(int(hero.owner)).recruits += 1
					_say("day %d  P%d recruits %s (level %d)" % [state.day, hero.owner, hero.name, hero.level])
			"inventory_changed":
				var hero := state.object(data.id)
				if int(hero.get("owner", 0)) == state.current_player: return
				var before: Dictionary = books.get(int(hero.uid), {"cards": [], "uses": []})
				var gained: Array = []
				var runes := 0
				for slot in hero.cards.size():
					if slot >= before.cards.size() or before.cards[slot] != hero.cards[slot]: gained.append("%s for %s" % [hero.cards[slot], before.cards[slot] if slot < before.cards.size() else "-"])
					elif int(hero.rune_uses[slot]) > int(before.uses[slot]): runes += int(hero.rune_uses[slot]) - int(before.uses[slot])
				if not gained.is_empty():
					_stat(int(hero.owner)).spells += gained.size()
					_say("day %d  P%d %s buys %s" % [state.day, hero.owner, hero.name, ", ".join(gained)])
				if runes > 0:
					_stat(int(hero.owner)).runes += runes
					_say("day %d  P%d %s buys %d runes" % [state.day, hero.owner, hero.name, runes])
				books[int(hero.uid)] = {"cards": hero.cards.duplicate(), "uses": hero.rune_uses.duplicate()}
	)
	print("=== %s (%s): %d spell shops, %d component portals, smart=%s free=%s, human P%d" % [entry.id, ELSingleScenario.title(profile, entry), shops, portals, director.smart_ai, director.free_movement, state.current_player])
	for player: int in state.players:
		if player == state.current_player: continue
		var castle := ELFirstScenario.castle_object(state, player)
		var own := 0
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and int(item.get("owner", -1)) == player and item.get("alive", false): own += 1
		print("    P%d %s: castle %s, heroes at start %d, relation to human %s, computer %s" % [player, state.players[player].color, "none" if castle.is_empty() else "(%d,%d)" % [castle.x, castle.y], own, str(state.players[player].get("relations", {}).get(state.current_player, "-")), ELFirstAI.computer_players(state).has(player)])
	var last_globals := {}
	for day in days:
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and item.get("alive", false) and item.has("cards") and item.has("rune_uses"): books[int(item.uid)] = {"cards": item.cards.duplicate(), "uses": item.rune_uses.duplicate()}
		if not _settle(): break
		if not director.end_day():
			print("day %d: the day cannot end: %s %s" % [state.day, director.notice, director.error])
			break
		if not _settle(): break
		for player: int in ELFirstAI.computer_players(state):
			var record := ELGlobalSpells.data(state, player)
			var active: Array = []
			for spell: Dictionary in record.get("active", []): active.append(str(spell.code))
			var seen: Array = last_globals.get(player, [])
			for code: String in active:
				if not seen.has(code):
					_stat(player).globals += 1
					_say("day %d  P%d casts %s" % [state.day, player, code])
			last_globals[player] = active
			var tasks := {}
			for pair: Array in ELFirstAI.data(state, player).assigned: tasks[int(pair[0])] = pair[1]
			var lines: Array = []
			for hero: Dictionary in ELFirstAI.heroes_of(state, player):
				var task: Dictionary = tasks.get(int(hero.uid), {})
				_stat(player).hero_days += 1
				if task.is_empty(): _stat(player).idle += 1
				var target := state.object(int(task.get("target", -1)))
				lines.append("%s L%d (%d,%d) %s%s runes %d%%" % [hero.name, hero.level, hero.x, hero.y, task.get("kind", "idle"), (":" + str(target.get("name", ""))) if not target.is_empty() else "", int(ELFirstAIEconomy.rune_health(state, hero) * 100)])
			if not quiet: print("day %d  P%d %s | %s | making %s" % [state.day, player, _resources(player), "; ".join(lines), str(record.get("production", {}).get("code", "-"))])
		if not state.outcome.is_empty():
			print("day %d: outcome %s" % [state.day, state.outcome])
			break
	var failed := false
	for player: int in ELFirstAI.computer_players(state):
		var s := _stat(player)
		var known := 0
		for item: Dictionary in state.objects.values():
			if ELFirstAIEconomy.is_shop(item) and ELFog.explored(state, player, Vector2i(item.x, item.y)): known += 1
		var levels: Array = []
		for hero: Dictionary in ELFirstAI.heroes_of(state, player): levels.append(int(hero.level))
		print("SUMMARY P%d: heroes %s, spells bought %d, runes bought %d, skills %d, recruits %d, global spells %d, idle hero-days %d/%d, shops known %d, %s" % [player, str(levels), s.spells, s.runes, s.skills, s.recruits, s.globals, s.idle, s.hero_days, known, _resources(player)])
	if not director.error.is_empty():
		print("ERROR: " + director.error)
		failed = true
	if stuck: failed = true
	if _arg("dump", "false") == "true": _dump(profile)
	return "fail" if failed else "ok"

## Books, known shops with their stock and prices, and the global spells on offer.
func _dump(profile: ELProfile) -> void:
	for player: int in ELFirstAI.computer_players(state):
		var budget := ELStrategy.mana_budget(state, player)
		print("--- P%d (%s): ether income %d, hero upkeep %d, spell upkeep %d, summons %d" % [player, state.players[player].color, budget.income, budget.spent, ELGlobalSpells.spell_upkeep(state, player), int(ELGlobalSpells.data(state, player).get("summons", 0))])
		for code: String in ELMapPickups.available_codes(state, player):
			print("    global %s: ether %d, upkeep %d, %s, problem '%s'" % [code, ELGlobalSpells.ether_cost(state, player, code), ELGlobalSpells.upkeep(profile, code), str(ELGlobalSpells.resources(profile, code)), ELGlobalSpells.produce_problem(state, player, code)])
		for hero: Dictionary in ELFirstAI.heroes_of(state, player):
			var book: Array = []
			for slot in hero.cards.size():
				var row: Dictionary = profile.table("CombatSpells").get(hero.cards[slot], {})
				book.append("%s(%s%s c%s)x%d" % [hero.cards[slot], str(row.get("Rarity", "?")).left(2), "", str(row.get("Cost", "?")), int(hero.rune_uses[slot])])
			print("    %s L%d skills %s: %s" % [hero.name, hero.level, str(hero.get("skills", {})), " ".join(book)])
			for item: Dictionary in state.objects.values():
				if not ELFirstAIEconomy.is_shop(item) or not ELFog.explored(state, player, Vector2i(item.x, item.y)): continue
				if item.type == "el1_spell_shop":
					var stock: Array = []
					for card: String in ELFirstSpellShop.authored_stock(profile, item, ELFirstSpellShop.hero_color(profile, hero)):
						var row: Dictionary = profile.table("CombatSpells").get(card, {})
						var price := ELFirstSpellShop.price(profile, hero, hero.cards, card, -1)
						var bill: Array = []
						for kind: String in price: if int(price[kind]) > 0: bill.append("%s %d" % [kind.left(2), price[kind]])
						stock.append("%s(%s c%s: %s)" % [card, str(row.get("Rarity", "?")).left(2), str(row.get("Cost", "?")), " ".join(bill)])
					print("      shop %s L%d at (%d,%d) wants %d: %s" % [item.name, item.level, item.x, item.y, ELFirstAIEconomy.wants(director, hero, item), " ".join(stock)])
				else:
					print("      portal %s L%d (%s) at (%d,%d) wants %d" % [item.name, item.level, str(ELRuneShop.definition(profile, item).get("Rarity", "")), item.x, item.y, ELFirstAIEconomy.wants(director, hero, item)])
			break

func _say(text: String) -> void:
	print("  * " + text)

func _resources(player: int) -> String:
	var parts: Array = []
	var stock: Dictionary = state.players[player].resources
	for kind: String in stock:
		if int(stock[kind]) != 0: parts.append("%s %d" % [kind.left(2), stock[kind]])
	return " ".join(parts)

## Runs the director until the local player may plan again.
func _settle() -> bool:
	for step in 200000:
		if not director.error.is_empty() or not state.outcome.is_empty(): return director.error.is_empty()
		if not director.dialogue.is_empty():
			director.acknowledge("OK")
			continue
		if director.encounter != null:
			# The local player's heroes never fight here: the attacker wins.
			var first := state.object(director.encounter.attacker())
			var second := state.object(director.encounter.target())
			director.encounter = null
			var mine := first if int(first.owner) == state.current_player else second
			var other := second if mine == first else first
			ELFirstAI.resolve(director, first, second, int(other.uid))
			continue
		if director._shopping():
			if director.first_shop != null: director.first_shop.cancel()
			if director.rune_shop != null: director.rune_shop.cancel()
			director.first_shop = null
			director.rune_shop = null
			continue
		if director.strategy.is_empty() and director.movement.is_empty() and director.travel.is_empty() and director.free_queue.is_empty() and state.commands.is_empty() and director.can_move(): return true
		director.advance(0.1)
	print("day %d: the turn did not settle" % state.day)
	stuck = true
	return false
