extends SceneTree
## Headless check of player-reported battle, deck and map details:
## - a hand card whose cost a battle changed shows the printed cost and the
##   change ("Цена: 1 + 2 ед. эфира"), an unchanged one only its cost;
## - the second game's deck editor lists the available spells in the
##   original order: colour (own race, then neutral), rarity, class, then
##   the code read from its last letter back;
## - the first game reads the presets the original saved as Duel\*.prs:
##   from the game's own Duel folder (left untouched) and from the user
##   folder, and keeps presets that break today's spending or colour rules,
##   as the original loader does, while the second game still refuses them;
## - a first-game neutral creature fighting as the opponent hero shows its
##   own Monsters `Icon` photo on the battle panel, and its battle tooltip is
##   the name, that photo and the Level and Health lines only;
## - the first game's pre-battle map panel uses the original text sizes
##   (BattleNumText and the names 20 px cells, the stat lines 15 px cells);
## - a creature with an ability of its own breaks enfeeblement and both
##   paralyses like any other: the price is paid and it rises;
## - first game, option "cast_icons": the opponent's casts show as framed
##   spell icons with their tooltip instead of red lines, and own casts show
##   no line either;
## - first game, with the second game installed: the pre-battle panel raises
##   the borrowed battle dome, and declining the battle ends it;
## - second game: a battle between two computer figures (chapter 11's Synth
##   Soldier on its guard) is shown before it resolves: dome and Summon,
##   BattleDefeat at the loser, then the loser dies and the dome ends; the
##   map waits meanwhile, and a save made then resolves the battle first;
##   with no winner both sides take the defeat and die;
## - battle controls (reports #81 #90 #95 #96 #101 #103 #104 #108 #110):
##   Pale Revival is castable with a plane creature and a graveyard creature,
##   Mystic manifestation needs an enchantment its hero cast, second-game
##   Attack all passes over 0-power creatures, a creature's own ability sits
##   left of its enchantments (a free one's tooltip is its text alone), the X
##   choice names what it counts and repeats while + or − is held, Fresh Wind
##   takes its target before X (Comet X first), a right click drops a
##   pending spell, and a first-game map battle names the hero's own level;
## - map reports: first game, a declined creature battle puts the hero back
##   outside the guard zone so it can walk on (#62), a second F8 answers the
##   quick-load question (#67), an object on the cell behind the hero is
##   picked rather than the hero (#79), a right click on a skill holds its
##   description up (#80), and a castle assault plays the attack clip and
##   damage effect (#111); second game, a tunnel guard fights on the Dungeon
##   arena and shows its portrait (#70, #72) and a specialization shrine plays
##   the hero's change effect (#75); a save the loader refuses brings the
##   menus back with the reason (#73).
##
##   godot --headless --path game --script ../tools/player_reports_check.gd
##
## Windowed with `-- --shots=<folder>` it saves the first game's battle with
## the monster's tooltip held open and the pre-battle panel.
##
## Needs the original games' files (user://profiles.json, as set up by the
## game); without them a game is skipped. Settings are never written; the
## preset files the check writes and the mission-start autosave are removed
## or put back.

var failures: Array[String] = []
var shots := ""

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440, 900)
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var profiles := {}
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		var profile := ELProfile.new()
		if profile.mount(edition, str(paths[edition])): profiles[edition] = profile
		else: print("SKIP: %s files could not be mounted" % edition)
	for edition: String in profiles: _cost_lines(profiles[edition])
	for edition: String in profiles: _status_breaks(profiles[edition])
	if profiles.has("el2"): _pale_commands(profiles.el2)
	for edition: String in profiles: await _battle_controls(edition)
	if profiles.has("el2"):
		_classic_order(profiles.el2)
		_strict_second_game(profiles.el2)
		_second_game_prs(profiles.el2)
		_displaced_to_reserve(profiles.el2)
	for edition: String in profiles: _editor_artifact_charges(profiles[edition])
	if profiles.has("el1"):
		_original_presets(profiles.el1)
		_wrapped_shop_tooltip(profiles.el1)
		_first_shop_reserve(profiles.el1)
		await _first_rune_buying(profiles.el1)
		await _monster_battle()
		await _precombat(profiles.el1)
		await _cast_icons()
		await _camera_keys_and_hall()
	await _tooltip_width()
	for edition: String in profiles: await _fresh_draws(edition)
	_save_name_symbols()
	for edition: String in profiles: await _hot_seat_rounds(edition)
	if profiles.has("el1") and profiles.has("el2"): await _first_dome()
	if profiles.has("el2"): await _computer_fight()
	if profiles.has("el2"): _shaded_colourless(profiles.el2)
	if profiles.has("el1"): await _first_map_reports()
	if profiles.has("el2"): await _second_map_reports()
	if not profiles.is_empty(): await _refused_load()
	print("PLAYER REPORTS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

# --- Card draws differ each battle -------------------------------------------------

## Outside --demo every battle started gets its own seed, and a loaded one
## draws afresh from where it was saved.
func _fresh_draws(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(2)
	view.demo = false
	var states := []
	for i in 3:
		view._start(edition)
		states.append(view.duel.rng_state)
	check(states[0] != states[1] or states[1] != states[2], "%s: each new battle draws from its own seed" % edition)
	var saved: Dictionary = view.duel.snapshot()
	var reloaded := []
	for i in 2:
		var loaded := ELDuel.new()
		loaded.restore(view.profile, {"format": "etherlords-duel", "version": 1, "state": saved})
		loaded.reseed()
		reloaded.append(loaded.rng_state)
	check(reloaded[0] != reloaded[1], "%s: a loaded battle draws afresh" % edition)
	view.queue_free()
	await frames(2)

# --- Tooltip width ---------------------------------------------------------------

## Godot's own tooltip label wraps at ELTooltipWidth.MAX_WIDTH; short ones keep their width.
func _tooltip_width() -> void:
	var widths := []
	for text: String in ["Short tip", "A long description ".repeat(20)]:
		var popup := PopupPanel.new()
		var label := Label.new()
		label.theme_type_variation = &"TooltipLabel"
		label.text = text
		popup.add_child(label)
		root.add_child(popup)
		await frames(1)
		widths.append([label.get_combined_minimum_size().x, label.autowrap_mode])
		popup.queue_free()
	await frames(1)
	check(widths[0][1] == TextServer.AUTOWRAP_OFF and widths[0][0] < ELTooltipWidth.MAX_WIDTH, "tooltips: a short tooltip keeps its own width")
	check(widths[1][1] != TextServer.AUTOWRAP_OFF and widths[1][0] <= ELTooltipWidth.MAX_WIDTH + 0.5, "tooltips: a long tooltip wraps at the greatest width (%.0f)" % widths[1][0])

# --- Hand card cost -------------------------------------------------------------

func _cost_lines(profile: ELProfile) -> void:
	var cost := profile.text("T_COST")
	var mana := profile.text("T_MANA")
	var plain := ELCombatTooltip.cost_line(profile, 1)
	check(plain == "%s 1 %s" % [cost, mana], "%s: a card shows its cost (%s)" % [profile.id, plain])
	check(ELCombatTooltip.cost_line(profile, 4, 4) == plain.replace(" 1 ", " 4 "), "%s: an unchanged battle cost shows the cost alone" % profile.id)
	var raised := ELCombatTooltip.cost_line(profile, 1, 3)
	check(raised == "%s 1 + 2 %s" % [cost, mana], "%s: a raised cost shows the printed cost + the surcharge (%s)" % [profile.id, raised])
	var lowered := ELCombatTooltip.cost_line(profile, 5, 3)
	check(lowered == "%s 5 - 2 %s" % [cost, mana], "%s: a lowered cost shows the printed cost - the discount (%s)" % [profile.id, lowered])
	# The whole hand tooltip carries the split line.
	var card := ""
	for code: String in profile.table("CombatSpells"):
		if str(profile.table("CombatSpells")[code].get("Class", "")) == "Enchantment" and int(profile.table("CombatSpells")[code].get("Cost", 0)) == 1:
			card = code
			break
	if not card.is_empty():
		var text := ELCombatTooltip.spell_text(profile, card, 3)
		check(text.get_slice("\n", 1) == raised, "%s: the hand tooltip of %s at 3 ether reads \"%s\"" % [profile.id, card, text.get_slice("\n", 1)])

# --- Breaking a status on a creature with its own ability -----------------------

func _status_breaks(profile: ELProfile) -> void:
	var card := ""
	for code: String in profile.table("CombatCreatures"):
		if not ELCatalog.first_ability(profile, code).is_empty() and not ELCatalog.rule(profile, code).is_empty():
			card = code
			break
	var duel := ELDuel.new()
	if card.is_empty() or not duel.start(profile, 7, {}):
		check(false, "%s: a duel with a creature that has an ability starts" % profile.id)
		return
	var side := duel.active_side()
	for status: Array in [["ENFL", "wake", 0], ["IMMB", "awaken", 1], ["WNPZ", "unparalyze", 1]]:
		var known := duel.creatures.keys()
		duel._summon(side, card)
		var id := -1
		for key: int in duel.creatures:
			if not known.has(key): id = key
		duel.creatures[id].sick = false
		duel.heroes[side].mana = 10
		duel._enchant(status[0], 1 - side, id, ELCatalog.rule(profile, status[0]))
		var price := 0
		for ability: Dictionary in duel.abilities(id):
			if ability.key == status[1]: price = int(ability.cost)
		var health := int(duel.heroes[side].health)
		var held: bool = duel.creatures[id].resting and duel.can_use_ability(id, status[1])
		var used := duel.use_ability(id, status[1])
		var paid := 10 - int(duel.heroes[side].mana) == price and health - int(duel.heroes[side].health) == price * int(status[2])
		check(held and used and paid and price > 0 and not duel.creatures[id].resting and not duel.enfeebled(id),
			"%s: %s under %s pays %d and rises with \"%s\"" % [profile.id, card, status[0], price, status[1]])

# --- Second game: available spells order ----------------------------------------

func _classic_order(profile: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var cards: Array[String] = []
		for colour: String in [faction, ELDuelCosts.EL2_NEUTRAL]:
			cards.append_array(ELCatalog.available_cards(profile, colour))
		cards.assign(cards.filter(func(card: String): return ELDuelCosts.spell_allowed(profile, card, faction, 1)))
		cards.sort_custom(ELDuelScreen.classic_less.bind(profile))
		var ordered := true
		var neutral_seen := false
		for i in cards.size():
			var row: Dictionary = profile.table("CombatSpells")[cards[i]]
			if str(row.Color) == ELDuelCosts.EL2_NEUTRAL: neutral_seen = true
			elif neutral_seen: ordered = false
			if i > 0 and ELDuelScreen.classic_less(cards[i], cards[i - 1], profile): ordered = false
		check(ordered and not cards.is_empty(), "el2 %s: %d available spells, own race first, each by rarity, class and reversed code" % [faction, cards.size()])
		if faction == "Red":
			var names := PackedStringArray()
			for card in cards.slice(0, 10): names.append("%s %s/%s/%s" % [card, profile.table("CombatSpells")[card].get("Rarity"), profile.table("CombatSpells")[card].get("Class"), profile.text(card + "Nm")])
			print("  el2 Red first ten: " + ", ".join(names))
	# The code tie-break reads the letters from the last one back.
	check(ELDuelScreen.classic_key(profile, "ABCZ")[3] > ELDuelScreen.classic_key(profile, "ZBCA")[3], "el2: codes compare from their last letter back")

func _strict_second_game(profile: ELProfile) -> void:
	var preset := _over_budget(profile, "Red", 16)
	check(not ELDuelCosts.errors(profile, preset).is_empty(), "el2: the test preset breaks the rules")
	check(not ELDuelPresets.lenient(profile), "el2: presets that break the rules are still refused on load")

## The second game's writer: deck/spell@code,components,
## bag_spells/spell@type,count and artefacts/artefact@name (a template name).
func _second_game_prs(profile: ELProfile) -> void:
	var preset: Dictionary = ELDuelPresets.shipped(profile)[0]
	var template := ""
	var artifact := ""
	for key: String in profile.table("Artefacts"):
		var code := str(profile.table("Artefacts")[key].get("SpellType", ""))
		if ELDuelCosts.duel_artifacts(profile).has(code):
			template = key
			artifact = code
			break
	var reserve: String = preset.cards[0]
	var lines := PackedStringArray(["<?xml version=\"1.0\"?>", "<duel_preset name=\"x\" magic=\"%s\" resource_level=\"%d\" hero_level=\"%d\" specialization=\"NONE\">" % [preset.faction, preset.resource_level, preset.level]])
	lines.append("<artefacts><artefact name=\"%s\"/></artefacts><skills/><deck>" % template)
	for i in preset.cards.size(): lines.append("<spell code=\"%s\" components=\"%d\"/>" % [preset.cards[i], preset.runes[i] if i < preset.runes.size() else 0])
	lines.append("</deck><bag_spells><spell type=\"%s\" count=\"1\"/></bag_spells></duel_preset>" % reserve)
	var path := OS.get_user_data_dir().path_join("player_reports_check_el2.prs")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\r\n".join(lines))
	file.close()
	var parsed := ELDuelPresets._original_preset(profile, path)
	DirAccess.remove_absolute(path)
	check(not parsed.is_empty() and parsed.cards == preset.cards and parsed.reserve == {reserve: 1} and parsed.artifacts == [artifact] and not template.is_empty(), "el2: the .prs layout reads (deck, bag_spells@type,count, artefact@name -> its spell)")
	check(not ELDuelPresets.normalize(parsed).is_empty(), "el2: a read .prs is a well-formed preset")

## Deck editors, both games: a hero artifact shows its charges (the
## template's MaxCharges, each round's start) in the rail's glyph digits.
func _editor_artifact_charges(profile: ELProfile) -> void:
	var menu := ELFrontMenu.new()
	menu.edition = profile.id
	menu.profile = profile
	var screen := ELDuelScreen.new(menu)
	var code: String = ELDuelCosts.duel_artifacts(profile)[0]
	var name := ELDuelPresets.artifact_name(profile, code)
	var look := ELListLook.load(profile)
	check(not name.is_empty() and screen.artifact_charges(code) == int(profile.table("Artefacts")[name].MaxCharges) and screen.artifact_charges(code) > 0 and look.hover != null, "%s deck editor: an artifact's charge count is drawn (%s: %d)" % [profile.id, code, screen.artifact_charges(code)])
	menu.free()

## First game laboratory (#69): bought over a cantrip, the cantrip waits
## under the spell and comes back when its runes are spent in battle; bought
## over another spell, that spell goes to the reserve with its runes.
func _first_shop_reserve(profile: ELProfile) -> void:
	var ids := ELCampaign.available(profile)
	var trade := ELFirstSpellShop.new()
	var state: ELAdventureSession
	var hero := {}
	for mission in 8:
		var campaign := ELCampaign.new()
		if ids.is_empty() or not campaign.load_campaign(profile, ids[0]) or campaign.scenarios.size() <= mission: break
		var map := ELAdventureMap.new()
		if not map.load_map(profile, str(campaign.scenarios[mission].file_name)): continue
		state = ELAdventureSession.new()
		if not state.start(map, 1, 212, "", 1, false): continue
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player: hero = item
		if hero.is_empty(): continue
		var colour := ELFirstSpellShop.hero_color(profile, hero)
		var cantrip := ""
		var spell := ""
		for code: String in profile.table("CombatSpells"):
			var row: Dictionary = profile.table("CombatSpells")[code]
			if row.get("Color") != colour or not ELSpellInventory.is_spell(profile, code): continue
			if row.get("Rarity") == "Cantrip" and cantrip.is_empty(): cantrip = code
			elif row.get("Rarity") == "Common" and spell.is_empty(): spell = code
		hero.cards.assign([cantrip, spell])
		hero.rune_uses.assign([-1, 3])
		hero.erase("rune_under")
		for item: Dictionary in state.objects.values():
			if item.get("group") == "laboratories" and trade.open(state, int(hero.uid), int(item.uid), true) and trade.stock.any(func(code: String): return not ELRunes.unlimited(profile, hero, code)): break
			trade = ELFirstSpellShop.new()
		if not trade.stock.is_empty():
			# #125: a stock spell's tooltip has its type and ether cost.
			var director := ELAdventureDirector.new()
			if director.build(state):
				var hud := ELAdventureHud.new()
				root.add_child(hud)
				hud.build(state)
				var view := ELFirstSpellShopView.new()
				root.add_child(view)
				view.build_shop(director, hud, trade)
				var shown: String = trade.stock[0]
				var tip: String = view.tooltip_at(view.shop_rect(0).get_center())
				var cost := ELCombatTooltip.cost_line(profile, int(profile.table("CombatSpells")[shown].get("Cost", 0)))
				check(tip.contains(cost) and tip.contains(profile.text(str(profile.table("CombatSpells")[shown].Name))), "el1 laboratory: a spell for sale names its ether cost (#125): %s" % tip.get_slice("
", 1))
				view.free()
				hud.free()
			var bought: String = trade.stock.filter(func(code: String): return not ELRunes.unlimited(profile, hero, code))[0]
			for kind: String in state.players[hero.owner].resources: state.players[hero.owner].resources[kind] = 1000000
			var reserve_before := int(hero.spell_stock.get(spell, 0))
			check(trade.replace(0, bought) and trade.replace(1, bought) and trade.commit(), "el1 laboratory: two purchases commit (%s)" % trade.error)
			check(hero.cards == [bought, bought] and ELRunes.under(hero) == [cantrip, ""], "el1 laboratory: a spell bought over a cantrip keeps it underneath")
			check(int(hero.spell_stock.get(spell, 0)) == reserve_before + 1 and int(hero.rune_stock[spell][-1]) == 3, "el1 laboratory: a spell bought over another sends it to the reserve with its runes")
			var copy: Variant = JSON.parse_string(JSON.stringify(hero))
			check(copy is Dictionary and ELRunes.restore(profile, copy) and ELRunes.under(copy) == [cantrip, ""], "el1 laboratory: the cantrip underneath survives a save round trip")
			var old := hero.duplicate(true)
			old.erase("rune_under")
			check(ELRunes.restore(profile, old) and ELRunes.under(old) == ["", ""], "el1: a book saved without cantrips underneath still loads")
			# In battle: the spent slot draws the cantrip it was bought over.
			var fighter := {"deck": [bought], "spell_uses": [0], "hand_slots": [], "drawn": [], "rune_under": [cantrip], "kind": "hero"}
			var drawn := ELSpellCharges.choose_el1(fighter, profile.table("CombatSpells"), func(n: int): return 0)
			check(drawn.get("card") == cantrip and int(drawn.get("slot", 0)) == -1, "el1 battle: a spent bought spell draws its cantrip")
			# After the battle: spent runes give the slot back; unspent ones keep it.
			hero.rune_uses.assign([0, 0])
			ELRunes.return_cantrips(hero, [2, 0])
			check(hero.cards == [cantrip, bought] and hero.rune_uses[0] == -1 and not hero.has("rune_under"), "el1: once its runes are spent in battle, the cantrip takes its slot back")
			break
		hero = {}
	if trade.stock.is_empty(): print("NOTE: no early first-game mission has a usable laboratory; the purchase rules are not checked")

## First game component portal (#78): runes are bought as the laboratory buys
## spells. The price table's rune is picked up with a click and put on a book
## spell with a second click or a drag; a double click on a book spell or a
## right click on the rune adds one to it, a right click on the spell gives
## one back; the shop hotkeys (B, U, Enter) buy, give back and pay. The
## prices and the rune limit stay those of ELRuneShop.
func _first_rune_buying(profile: ELProfile) -> void:
	var ids := ELCampaign.available(profile)
	var trade := ELRuneShop.new()
	var state: ELAdventureSession
	var director: ELAdventureDirector
	var hero := {}
	for mission in 8:
		var campaign := ELCampaign.new()
		if ids.is_empty() or not campaign.load_campaign(profile, ids[0]) or campaign.scenarios.size() <= mission: break
		var map := ELAdventureMap.new()
		if not map.load_map(profile, str(campaign.scenarios[mission].file_name)): continue
		state = ELAdventureSession.new()
		if not state.start(map, 1, 212, "", 1, false): continue
		hero = {}
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player: hero = item
		if hero.is_empty(): continue
		var colour := ELFirstSpellShop.hero_color(profile, hero)
		var cantrip := ""
		var spell := ""
		for code: String in profile.table("CombatSpells"):
			var row: Dictionary = profile.table("CombatSpells")[code]
			if row.get("Color") != colour or not ELSpellInventory.is_spell(profile, code): continue
			if row.get("Rarity") == "Cantrip" and cantrip.is_empty(): cantrip = code
			elif row.get("Rarity") == "Common" and spell.is_empty(): spell = code
		if cantrip.is_empty() or spell.is_empty(): continue
		hero.cards.assign([cantrip, spell, spell])
		hero.rune_uses.assign([-1, 1, ELRunes.capacity(hero) - 1])
		hero.erase("rune_under")
		var found := false
		for item: Dictionary in state.objects.values():
			if item.get("group") == "factories" and trade.open(state, int(hero.uid), int(item.uid), true):
				found = true
				break
			trade = ELRuneShop.new()
		if not found: continue
		director = ELAdventureDirector.new()
		if director.build(state): break
		director = null
	if director == null:
		print("NOTE: no early first-game mission has a component portal; rune buying is not checked")
		return
	for kind: String in state.players[hero.owner].resources: state.players[hero.owner].resources[kind] = 1000000
	var hud := ELAdventureHud.new()
	root.add_child(hud)
	hud.build(state)
	var view := ELRuneShopView.new()
	root.add_child(view)
	view.build_shop(director, hud, trade)
	await frames(2)
	var input: Callable = view.sheet._gui_input
	var mouse := func(at: Vector2, button: MouseButton, pressed: bool, double := false) -> void:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.double_click = double
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
		event.position = at
		event.global_position = at
		input.call(event)
	var moving := func(at: Vector2) -> void:
		var event := InputEventMouseMotion.new()
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		event.position = at
		event.global_position = at
		input.call(event)
	var rune := view.rune_rect().get_center()
	var spell_one := view.book_rect(1).get_center()
	var spell_two := view.book_rect(2).get_center()
	# A double click on a book spell buys one rune for it.
	mouse.call(spell_one, MOUSE_BUTTON_LEFT, true)
	mouse.call(spell_one, MOUSE_BUTTON_LEFT, false)
	mouse.call(spell_one, MOUSE_BUTTON_LEFT, true, true)
	mouse.call(spell_one, MOUSE_BUTTON_LEFT, false)
	check(view.slot == 1 and trade.pending == [0, 1, 0], "el1 portal: a double click on a book spell buys one rune for it")
	# Click the rune, click a spell.
	mouse.call(rune, MOUSE_BUTTON_LEFT, true)
	mouse.call(rune, MOUSE_BUTTON_LEFT, false)
	check(view.carry, "el1 portal: a click on the price table's rune picks it up")
	mouse.call(spell_two, MOUSE_BUTTON_LEFT, true)
	mouse.call(spell_two, MOUSE_BUTTON_LEFT, false)
	check(not view.carry and view.slot == 2 and trade.pending == [0, 1, 1], "el1 portal: the second click on a book spell adds the rune there")
	# Drag the rune onto a spell; dropped elsewhere it is let go.
	mouse.call(rune, MOUSE_BUTTON_LEFT, true)
	for step in 4: moving.call(rune.lerp(spell_one, (step + 1) / 4.0))
	mouse.call(spell_one, MOUSE_BUTTON_LEFT, false)
	check(not view.carry and trade.pending == [0, 2, 1], "el1 portal: a rune dragged onto a book spell is added there")
	mouse.call(rune, MOUSE_BUTTON_LEFT, true)
	for step in 4: moving.call(rune.lerp(Vector2(200, 20), (step + 1) / 4.0))
	mouse.call(Vector2(200, 20), MOUSE_BUTTON_LEFT, false)
	check(not view.carry and trade.pending == [0, 2, 1], "el1 portal: a rune dropped away from the book is let go")
	# Right button: gives one back on a spell, buys one on the rune.
	mouse.call(spell_one, MOUSE_BUTTON_RIGHT, true)
	mouse.call(spell_one, MOUSE_BUTTON_RIGHT, false)
	check(view.slot == 1 and trade.pending == [0, 1, 1], "el1 portal: a right click on a book spell gives one rune back")
	mouse.call(rune, MOUSE_BUTTON_RIGHT, true)
	mouse.call(rune, MOUSE_BUTTON_RIGHT, false)
	check(trade.pending == [0, 2, 1], "el1 portal: a right click on the rune buys one for the selected spell")
	# The limits stay: a full spell and a cantrip take no rune.
	mouse.call(spell_two, MOUSE_BUTTON_LEFT, true, true)
	mouse.call(spell_two, MOUSE_BUTTON_LEFT, false)
	var cantrip_slot := view.book_rect(0).get_center()
	mouse.call(cantrip_slot, MOUSE_BUTTON_LEFT, true, true)
	mouse.call(cantrip_slot, MOUSE_BUTTON_LEFT, false)
	check(trade.pending == [0, 2, 1], "el1 portal: a full spell or a cantrip takes no more runes (limit %d)" % ELRunes.capacity(hero))
	check(view.tooltip_at(rune).contains(ELRemakeText.t("Click to pick a rune up, then click a spell in the book. Right click: buy one for the selected spell.", profile)), "el1 portal: the rune's tooltip says how to buy it")
	# Shop hotkeys on the map: B buys, U gives back, Enter pays.
	var map := ELAdventureView.new()
	root.add_child(map)
	map.state = state
	map.rune_shop = view
	view.slot = 1
	var key := func(code: Key) -> void:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = true
		map._shop_hotkey(event)
	key.call(KEY_B)
	key.call(KEY_B)
	check(trade.pending == [0, 4, 1], "el1 portal: the shop_buy hotkey (B) buys a rune for the selected spell")
	key.call(KEY_U)
	check(trade.pending == [0, 3, 1], "el1 portal: the shop_undo hotkey (U) gives one back")
	var expected := ELResources.empty("el1")
	for kind: String in expected: expected[kind] = int(ELRuneShop.price(profile, hero, state.object(trade.shop_id), hero.cards[1])[kind]) * 3 + int(ELRuneShop.price(profile, hero, state.object(trade.shop_id), hero.cards[2])[kind])
	check(trade.bill() == expected, "el1 portal: the bill is the portal's own rune prices")
	var reordered := [hero.cards[0], hero.cards[2], hero.cards[1]]
	mouse.call(rune, MOUSE_BUTTON_LEFT, true)
	mouse.call(rune, MOUSE_BUTTON_LEFT, false)
	mouse.call(spell_two, MOUSE_BUTTON_LEFT, true)
	for step in 4: moving.call(spell_two.lerp(spell_one, (step + 1) / 4.0))
	mouse.call(spell_one, MOUSE_BUTTON_LEFT, false)
	check(view.book_cards(0) == reordered and trade.bill() == expected and not view.carry, "el1 portal: reordering spells keeps their prices even while a rune is picked")
	var before: Dictionary = state.players[hero.owner].resources.duplicate()
	var closed := [false]
	view.closed.connect(func(): closed[0] = true)
	key.call(KEY_ENTER)
	var paid := true
	for kind: String in expected: paid = paid and int(state.players[hero.owner].resources[kind]) == int(before[kind]) - int(expected[kind])
	check(closed[0] and trade.finished and hero.cards == reordered and hero.rune_uses == [-1, ELRunes.capacity(hero), 4] and paid, "el1 portal: Enter pays and keeps the order and runes (%s)" % [hero.rune_uses])
	map.rune_shop = null
	map.queue_free()
	view.queue_free()
	hud.queue_free()
	await frames(2)

## EL2 Duel deck editor: a spell put on an occupied active-deck slot sends
## the displaced one to the reserve (manual: "the displaced spell moves to
## reserve"); the first game's book slot just takes the new spell.
func _displaced_to_reserve(profile: ELProfile) -> void:
	var screen := ELDuelScreen.new(ELFrontMenu.new())
	screen.menu.edition = "el2"
	screen.menu.profile = profile
	var preset: Dictionary = ELDuelPresets.shipped(profile)[0].duplicate(true)
	var old: String = preset.cards[3]
	var other := ""
	for card: String in preset.cards:
		if card != old: other = card
	var placed: Variant = screen.apply(preset, "place_spell", [other, 3])
	check(placed is Dictionary and placed.cards[3] == other and int(placed.reserve.get(old, 0)) == int(preset.reserve.get(old, 0)) + 1 and placed.cards.size() == preset.cards.size(), "el2 deck editor: the spell displaced from an active-deck slot goes to the reserve")
	screen.menu.free()

## EL1 laboratory: a stock spell's tooltip wraps its description instead of
## one line several screens wide (CMBN «Самопожертвование»).
func _wrapped_shop_tooltip(profile: ELProfile) -> void:
	var text := profile.text(str(profile.table("CombatSpells").get("CMBN", {}).get("Name", "CMBN"))) + "\n" + profile.card_description("CMBN")
	var label := ELHeroScreenView.wrapped_tooltip(text)
	root.add_child(label)
	var wide := Label.new()
	wide.text = text
	root.add_child(wide)
	check(wide.get_minimum_size().x > 1440.0 and label.get_combined_minimum_size().x <= ELSecondMapTooltip.MAX_LABEL_WIDTH + 1.0 and label.autowrap_mode != TextServer.AUTOWRAP_OFF, "el1 shop: a long card tooltip wraps (%d px unwrapped, %d px wrapped)" % [wide.get_minimum_size().x, label.get_combined_minimum_size().x])
	label.free()
	wide.free()

## Hot seat: each round deals each player their own preset, and the camera
## turns to the acting player's end, keeping each player's own view
## (EL1: per-side view records, default yaw 80/260 degrees).
func _hot_seat_rounds(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	var profile: ELProfile = view.profiles.get(edition)
	if profile == null:
		view.queue_free()
		return
	var pool := ELDuelPresets.shipped(profile)
	var first: Dictionary = pool[0]
	var second := {}
	for row: Dictionary in pool:
		if row.faction != first.faction and int(row.resource_level) == int(first.resource_level):
			second = row
			break
	var hot_match := ELDuelMatch.new()
	hot_match.begin(profile, pool, [first, second], int(first.resource_level), 2, ELDuelMatch.RANDOM, 77)
	hot_match.hot_seat = true
	hot_match.names = ["P1", "P2"]
	view._begin_duel_match(hot_match)
	for round in 2:
		await frames(5)
		var yaws := [INF, INF]
		var own_hands := true
		var kept_view := false
		for turn in 3:
			for i in 50:
				if view.hot_pending: break
				await process_frame
			var side: int = view.duel.active_side()
			view._confirm_handover()
			await frames(2)
			if turn == 2: kept_view = is_equal_approx(view.camera_yaw, yaws[side] + 0.25)
			else: yaws[side] = view.camera_yaw
			for button in view.hand.get_children():
				if button.has_meta("card") and str(profile.table("CombatSpells")[button.get_meta("card")].get("Color", "")) != String(hot_match.presets[side].faction): own_hands = false
			# The player turns their camera a little: it is theirs to keep.
			view.camera_yaw += 0.25
			var guard := 0
			while view.duel.active_side() == side and guard < 8 and view.duel.phase != ELDuel.Phase.FINISHED:
				view._end_phase()
				await frames(3)
				guard += 1
		check(own_hands, "%s hot seat round %d: each player's hand comes from their own preset" % [edition, round + 1])
		check(absf(absf(wrapf(yaws[1] - yaws[0], -PI, PI)) - PI) < 0.001, "%s hot seat round %d: player 2's camera looks from the other end" % [edition, round + 1])
		check(kept_view, "%s hot seat round %d: a player's own camera comes back on their next turn" % [edition, round + 1])
		view._surrender_round()
		await frames(5)
		if round == 0: view._duel_round_closed(true)
	view.duel_match = null
	view.queue_free()
	await frames(2)

# --- First game: .prs presets and lenient loading -------------------------------

## A preset of `faction` with its first `count` spells at resource level 1
## and hero level 15: well over the level-1 budget.
func _over_budget(profile: ELProfile, faction: String, count: int) -> Dictionary:
	var preset := ELDuelPresets.blank(faction, 1)
	preset.level = ELDuelCosts.hero_levels(profile).y
	var cards := ELCatalog.available_cards(profile, faction).filter(func(card: String): return ELDuelCosts.spell_allowed(profile, card, faction, 1))
	for i in mini(count, cards.size()):
		preset.cards.append(cards[i])
		preset.runes.append(1)
	return preset

func _prs_text(name: String, preset: Dictionary, extra_spell := "") -> String:
	var lines := PackedStringArray()
	lines.append("<?xml version=\"1.0\"?>")
	lines.append("<duel_preset name=\"%s\" magic=\"%s\" resource_level=\"%d\" hero_level=\"%d\">" % [name, preset.faction, preset.resource_level, preset.level])
	lines.append("<skills><skill type=\"MSTR\" level=\"2\"/></skills>")
	lines.append("<deck>")
	for i in preset.cards.size(): lines.append("<spell code=\"%s\" components=\"%d\"/>" % [preset.cards[i], preset.runes[i]])
	if not extra_spell.is_empty(): lines.append("<spell code=\"%s\" components=\"1\"/>" % extra_spell)
	lines.append("</deck></duel_preset>")
	return "\r\n".join(lines)

func _original_presets(profile: ELProfile) -> void:
	var preset := _over_budget(profile, "Black", 9)
	check(not ELDuelCosts.errors(profile, preset).is_empty(), "el1: the test preset breaks today's rules (%s)" % ", ".join(ELDuelCosts.errors(profile, preset)))
	var readable := ELDuelPresets.readable(profile, preset)
	check(not readable.is_empty() and readable.cards == preset.cards and int(readable.level) == int(preset.level), "el1: a preset over budget stays readable, as the original loads it")
	var short := ELDuelPresets.readable(profile, _over_budget(profile, "Black", 3))
	check(short.cards.size() == 3, "el1: a book of fewer than 15 spells is readable")
	var other := ELCatalog.available_cards(profile, "Red")[0]
	var mixed := preset.duplicate(true)
	mixed.cards.insert(2, other)
	mixed.runes.insert(2, 1)
	mixed.cards.append("ZZZZ")
	mixed.runes.append(1)
	mixed.cards.append(preset.cards[0])
	mixed.runes.append(1)
	var kept := ELDuelPresets.readable(profile, mixed)
	check(kept.cards == preset.cards, "el1: another race's spell is left out and the book ends at an unknown spell")
	# An original file in the game's own Duel folder.
	var folder := OS.get_user_data_dir().path_join("player_reports_check")
	DirAccess.make_dir_recursive_absolute(folder)
	var name := "zz check %d" % OS.get_process_id()
	var source := folder.path_join(name + ".prs")
	var text := _prs_text(name, preset, "ZZZZ")
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var parsed := ELDuelPresets._original_preset(profile, source)
	check(parsed.get("faction") == "Black" and parsed.get("cards", []).size() == preset.cards.size() + 1 and int(parsed.skills.get("MSTR", -1)) == 1 and int(parsed.level) == int(preset.level), "el1: the .prs layout reads (magic, levels, skills/skill@type,level, deck/spell@code,components)")
	# The first game's loader counts rank-ups: capped at rank 2, a repeat adds, 0 adds nothing.
	var odd := FileAccess.open(source, FileAccess.WRITE)
	odd.store_string(text.replace("<skill type=\"MSTR\" level=\"2\"/>", "<skill type=\"MSTR\" level=\"9\"/><skill type=\"HEAL\" level=\"1\"/><skill type=\"HEAL\" level=\"1\"/><skill type=\"BARG\" level=\"0\"/>"))
	odd.close()
	var odd_skills: Dictionary = ELDuelPresets._original_preset(profile, source).get("skills", {})
	check(odd_skills == {"MSTR": 2, "HEAL": 1}, "el1: .prs skill levels read as the original's rank-ups (%s)" % odd_skills)
	file = FileAccess.open(source, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var index_path := ELDuelPresets.user_dir(profile).path_join(ELDuelPresets.IMPORTED_INDEX)
	var index_before := FileAccess.get_file_as_string(index_path) if FileAccess.file_exists(index_path) else ""
	var key := "duel/" + name + ".prs"
	profile._files[key] = source
	var rejected: Array = []
	var pool := ELDuelPresets.load_user(profile, rejected)
	var found := ELDuelPresets.find(pool, "user:" + name)
	check(not found.is_empty() and found.cards == preset.cards, "el1: a .prs in the game's Duel folder appears among the presets (%s)" % ", ".join(PackedStringArray(rejected)))
	check(FileAccess.file_exists(source) and FileAccess.get_file_as_string(source) == text and not FileAccess.file_exists(source + ".imported"), "el1: the game folder's .prs is left untouched")
	if not found.is_empty():
		var choice := ELDuelPresets.choice(profile, found)
		var duel := ELDuel.new()
		var other_side := ELDuelPresets.choice(profile, ELDuelPresets.shipped(profile)[0])
		check(duel.start(profile, 7, {"arena": ELDuelMatch.arenas(profile)[0], "players": [choice, other_side]}), "el1: a battle starts with the imported preset: " + duel.error)
	# Deleted, it stays deleted until the file changes.
	ELDuelPresets.delete_user(profile, name)
	pool = ELDuelPresets.load_user(profile)
	check(ELDuelPresets.find(pool, "user:" + name).is_empty(), "el1: a deleted imported preset is not read again from the unchanged file")
	profile._files.erase(key)
	ELDuelPresets.delete_user(profile, name)
	DirAccess.remove_absolute(source)
	DirAccess.remove_absolute(folder)
	if index_before.is_empty(): DirAccess.remove_absolute(index_path)
	else:
		var restore := FileAccess.open(index_path, FileAccess.WRITE)
		restore.store_string(index_before)
		restore.close()
	# A .prs copied into the user folder is converted (the existing route).
	var copied := ELDuelPresets.user_dir(profile).path_join(name + ".prs")
	DirAccess.make_dir_recursive_absolute(ELDuelPresets.user_dir(profile))
	file = FileAccess.open(copied, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	pool = ELDuelPresets.load_user(profile)
	check(not ELDuelPresets.find(pool, "user:" + name).is_empty(), "el1: a .prs copied into the user folder is converted, over budget or not")
	ELDuelPresets.delete_user(profile, name)
	for leftover: String in DirAccess.get_files_at(ELDuelPresets.user_dir(profile)):
		if leftover.begins_with(name + ".prs"): DirAccess.remove_absolute(ELDuelPresets.user_dir(profile).path_join(leftover))

# --- First game: a neutral creature as the opponent hero ------------------------

func _monster_battle() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has("el1"):
		print("SKIP: el1 files could not be mounted by the battle view")
		view.queue_free()
		return
	var profile: ELProfile = view.profiles.el1
	var row := ELFirstMonsters.definition(profile, "Pteros", 1)
	check(not row.is_empty(), "el1: the Pteros monster row exists")
	if row.is_empty():
		view.queue_free()
		return
	var hero := {"faction": "Green", "level": 1, "cards": ELCatalog.available_cards(profile, "Green").slice(0, 5)}
	var monster := {"faction": str(row.Color), "kind": "monster", "title": profile.text(str(row.ELKName)), "level": int(row.Level), "health": int(row.Health),
		"cards": ELFirstMonsters.book(row).cards, "skills": {}, "monster_name": "Pteros", "monster_difficulty": 1}
	view._start("el1", {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": [hero, monster]})
	await frames(10)
	check(view.duel != null, "el1: a battle against the Pteros starts")
	var portrait: Texture2D = view.portraits[1].texture
	var expected := profile.portrait(int(row.Icon)) as AtlasTexture
	check(portrait is AtlasTexture and (portrait as AtlasTexture).atlas == expected.atlas and (portrait as AtlasTexture).region == expected.region, "el1: the monster's battle portrait is its Monsters Icon photo (%d)" % int(row.Icon))
	var tip: Dictionary = view._hero_tip(1)
	var texts := PackedStringArray()
	for label: Dictionary in tip.labels: texts.append(str(label.text))
	print("  el1 monster tooltip: " + JSON.stringify(texts))
	check(texts.size() > 0 and texts[0] == monster.title, "el1: the tooltip is headed by the creature's name")
	var level_line := "%s: %d" % [view._original_text("T_LEVEL", "Level"), int(view.duel.heroes[1].get("level", 1))]
	var health_line := "%s: %d" % [view._original_text("CtrlTtCombatTt1", "Health"), int(view.duel.heroes[1].health)]
	check(texts.size() == 3 and texts[1] == level_line and texts[2] == health_line, "el1: the monster's tooltip is its name, Level and Health only")
	check(tip.picture.texture == portrait and tip.picture.size == ELCombatTooltip.FIRST_PORTRAIT, "el1: the tooltip shows the same photo at 100 x 70")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		await _hold_on_monster(view)
	view.queue_free()
	await frames(2)

## A touch hold on the opponent's figure, saved as a picture.
func _hold_on_monster(view: Node) -> void:
	for i in 120:
		view.ai_clock = -1000.0
		await process_frame
	var model: ELModel = view.models.get(1)
	if model == null: return
	var point := Vector2(-1, -1)
	for height: float in [0.6, 0.4, 0.8, 0.2, 1.0]:
		var at: Vector2 = view.camera.unproject_position(model.global_position + Vector3(0, height, 0))
		if view._character_at(at) == 1:
			point = at
			break
	if point.x < 0: return
	var touch: ELTouchInput = view.touch_input
	var was_enabled := ELTouchInput.enabled
	touch.set_enabled(true)
	for figure: Variant in view.models.values():
		if is_instance_valid(figure): figure.set_process(false)
	touch._press(0, point)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int((ELTouchInput.HOLD_SECONDS + 0.6) * 1000.0):
		view.ai_clock = -1000.0
		await process_frame
	await RenderingServer.frame_post_draw
	var path := shots.path_join("monster_tooltip_el1.png")
	root.get_texture().get_image().save_png(path)
	print("SHOT: " + path)
	touch._release(0, point, false)
	touch.set_enabled(was_enabled)

# --- First game: the pre-battle map panel ---------------------------------------

func _precombat(profile: ELProfile) -> void:
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	var saves := _backup(ELSaveSlots.folder("el1"))
	var settings := ELSettings.new()
	settings.use_edition("el1")
	settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(settings).persist = false
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	_restore(ELSaveSlots.folder("el1"), saves)
	check(built, "el1: the first mission map builds: " + view.error)
	if not built:
		view.queue_free()
		return
	await frames(5)
	if view.tutorial_panel != null and view.tutorial_panel.visible: view.tutorial_panel.close()
	var state := view.state
	var hero := -1
	var monster := -1
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false): continue
		if item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player and hero < 0: hero = int(item.uid)
		if item.get("type") == "monster" and monster < 0: monster = int(item.uid)
	check(hero >= 0 and monster >= 0, "el1: the map has the player's hero and a neutral creature")
	if hero >= 0 and monster >= 0:
		var hud = view.hud
		# #49: a battle with a neutral creature can be left alone (remake X, Esc).
		var hero_item := state.object(hero)
		var monster_item := state.object(monster)
		var at := Vector2i(int(hero_item.x), int(hero_item.y))
		view.director._begin_encounter(hero_item, monster_item)
		await frames(3)
		var prepared: bool = view.director.encounter != null
		check(prepared and view.director.encounter.declinable(), "el1: a battle with a neutral creature can be declined")
		check(hud.precombat.visible and hud.cancel_button.visible, "el1: the pre-battle panel shows the X for a neutral creature")
		if prepared:
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.pressed = true
			view._unhandled_input(esc)
			await frames(3)
			check(view.director.encounter == null and view.pending_encounter.is_empty() and not hud.precombat.visible, "el1: Esc declines and closes the panel without a battle")
			check(hero_item.alive and monster_item.alive and Vector2i(int(hero_item.x), int(hero_item.y)) == at, "el1: after declining both sides live and the hero stays where it stood")
		hud.show_precombat(hero, monster, 1, 1, true)
		await frames(3)
		var labels: Dictionary = hud.precombat_labels
		var heading: Label = labels.heading
		var name: Label = labels.names[1]
		var value: Label = labels.values[0][0]
		var caption: Label = labels.captions[0][0]
		var size_of := func(label: Label) -> int: return label.get_theme_font_size("font_size")
		# #134: the second game's colours and sizes; the names no smaller than
		# the 20 px cells #45 enlarged them to.
		check(size_of.call(heading) == 20 and size_of.call(name) == 20 and size_of.call(name) >= ELFrontMenu.cell_em(20), "el1: the panel's heading and names are 20 px as in the second game (%d em)" % size_of.call(name))
		check(size_of.call(value) == 17 and size_of.call(caption) == 17, "el1: the Level/Life/Sight lines are 17 px as in the second game (%d em)" % size_of.call(value))
		check(name.get_theme_color("font_color") == ELSecondPrecombatView.TAN and heading.get_theme_color("font_color") == ELSecondPrecombatView.TAN and caption.get_theme_color("font_color") == ELSecondPrecombatView.TAN and value.get_theme_color("font_color") == ELSecondPrecombatView.WHITE,
			"el1: the names, question and captions are the second game's tan, the values its white (#134)")
		check(caption.get_minimum_size().y <= 23.0, "el1: a stat line stays within its 23 px row (%.0f)" % caption.get_minimum_size().y)
		var font: Font = caption.get_theme_font("font")
		var widest := 0.0
		for side in 2:
			for line in 3:
				var shown: Label = labels.captions[side][line]
				if shown.visible: widest = maxf(widest, font.get_string_size(shown.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_of.call(shown)).x)
		check(widest <= caption.size.x, "el1: the stat captions fit their boxes (%.0f of %.0f)" % [widest, caption.size.x])
		check(font.get_string_size(name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_of.call(name)).x <= name.size.x, "el1: the opponent's name fits its box")
		# The portraits sit inside the panel art's frames (94x50 at (3, 9) of
		# the photo cell), not over them.
		for side in 2:
			var shown: TextureRect = hud.precombat_portraits[side]
			var photo := shown.texture as AtlasTexture
			var actor := state.object([hero, monster][side])
			var shown_row: Dictionary = hud._art.resolve(actor).get("row", {})
			var cell := profile.portrait(int(shown_row.get("Face" if side == 0 else "Icon", 0))) as AtlasTexture
			check(Rect2(shown.position, shown.size) == ELAdventureHud.PRECOMBAT_PORTRAITS[side] and shown.size == Vector2(94, 50), "el1: portrait %d fills the frame's window, 94 x 50 (%s)" % [side, Rect2(shown.position, shown.size)])
			check(photo != null and cell != null and photo.atlas == cell.atlas and photo.region == Rect2(cell.region.position + Vector2(3, 9), Vector2(94, 50)), "el1: portrait %d is the 94 x 50 cut at (3, 9) of its photo cell" % side)
		# Free movement: the second game's question, the check mark at the
		# lower left and the cross at the lower right.
		hud.show_precombat(hero, monster, 1, 1, true, true)
		await frames(2)
		check(heading.text == ELRemakeText.t("Accept battle?", profile) and heading.text != profile.text("CtrlBattleNumText") % [1, 1], "el1: with the check mark the panel asks \"%s\"" % heading.text)
		var accept: Rect2 = hud.accept_button.get_rect()
		var cancel: Rect2 = hud.cancel_button.get_rect()
		check(accept.end.x < 160 and cancel.position.x > 460 and absf(accept.position.x + cancel.end.x - 638.0) <= 2.0 and is_equal_approx(accept.position.y, cancel.position.y), "el1: the check mark and the cross stand at the panel's two lower corners (%s, %s)" % [accept, cancel])
		hud.show_precombat(hero, monster, 1, 1, true)
		await frames(2)
		check(heading.text == profile.text("CtrlBattleNumText") % [1, 1], "el1: the original orders keep the numbered heading")
		if not shots.is_empty() and DisplayServer.get_name() != "headless":
			await frames(30)
			await RenderingServer.frame_post_draw
			var path := shots.path_join("precombat_el1.png")
			root.get_texture().get_image().save_png(path)
			print("SHOT: " + path)
	view.queue_free()
	await frames(2)

# --- First game: the opponent's casts as icons ------------------------------------

func _cast_icons() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	var profile: ELProfile = view.profiles.el1
	var cards := ELCatalog.available_cards(profile, "Red").slice(0, 6)
	view._start("el1", {"arena": ELDuelMatch.arenas(profile)[0], "players": [{"faction": "Green", "level": 1, "cards": ELCatalog.available_cards(profile, "Green").slice(0, 5)}, {"faction": "Red", "level": 1, "cards": cards}]})
	view.demo = false
	await frames(5)
	var kept: Variant = view.settings.values.get("cast_icons")
	var notices: ELCombatNotices = view.notices
	view.settings.values.cast_icons = false
	view._cast_notice(1, cards[0])
	check(notices.icons.is_empty() and notices.lines.size() == 1, "el1: with icons off the opponent's cast is a message line")
	notices.clear()
	view.settings.values.cast_icons = true
	for card: String in cards: view._cast_notice(1, card)
	view._cast_notice(0, cards[0])
	check(notices.icons.size() == cards.size() + 1 and notices.lines.is_empty(), "el1: with icons on every cast is an icon, the player's own too (#124), and no cast is a line")
	check(notices.frame != null, "el1: the cast icons have a frame (the first game's list border)")
	check(notices.icon_rect(5).position.y > notices.icon_rect(4).position.y, "el1: the icons wrap after five a row")
	var tip: String = notices._get_tooltip(notices.icon_rect(0).get_center())
	check(tip.contains(view.duel.card_name(cards[0])), "el1: an icon's tooltip describes its spell")
	view._phase_notice(1, false, 2)
	check(notices.icons.is_empty(), "el1: the icons clear when the opponent's next turn starts")
	if kept == null: view.settings.values.erase("cast_icons")
	else: view.settings.values.cast_icons = kept
	view.queue_free()
	await frames(2)

# --- Battle camera keys (#64) and the Dungeon hall (#71) ---------------------------

func _camera_keys_and_hall() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	var profile: ELProfile = view.profiles.el1
	view._start("el1", {"arena": "Dungeon.001", "players": [{"faction": "Green", "level": 1, "cards": ELCatalog.available_cards(profile, "Green").slice(0, 5)}, {"faction": "Red", "level": 1, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 5)}]})
	view.demo = false
	await frames(5)
	var kept: Variant = view.settings.values.get("auto_camera")
	view.settings.values.auto_camera = false
	check(view.battle_camera_presets_active(), "battle: F1-F4 pick a camera view with the automatic camera off")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	view._input(key)
	check(view.auto_camera.view_index == 2, "battle: F3 picks the third view with the free camera")
	view.settings.values.auto_camera = true
	var yaw: float = view.camera_yaw
	var arrow := InputEventKey.new()
	arrow.physical_keycode = KEY_LEFT
	arrow.keycode = KEY_LEFT
	arrow.pressed = true
	Input.parse_input_event(arrow)
	Input.flush_buffered_events()
	view._step_keyboard_camera(0.5)
	arrow.pressed = false
	Input.parse_input_event(arrow)
	Input.flush_buffered_events()
	check(not is_equal_approx(view.camera_yaw, yaw), "battle: the arrow keys turn the camera with the automatic camera on")
	view.camera_pitch = view.PITCH_LIMITS.x
	view.camera_distance = view.DISTANCE_LIMITS.y
	view._update_camera()
	var flat := Vector2(view.camera.position.x, view.camera.position.z).length()
	check(is_equal_approx(view.camera.position.distance_to(view.camera_target), view.DISTANCE_LIMITS.y), "Dungeon arena: the camera zooms all the way out (%.1f from the centre)" % flat)
	var shown := 0
	for arch: ELModel in view.arena._camera_obstacles:
		if not arch.visible: continue
		shown += 1
	var shell_hidden: bool = view.arena._hall_shell_models().all(func(m: ELModel) -> bool: return not m.visible)
	check(shown > 0 and shell_hidden and not view.arena._hall_shell_models().is_empty(), "Dungeon arena: beyond the arches the near side of the hall is hidden and the far arches stay (%d shown)" % shown)
	view.camera_distance = view.DISTANCE_LIMITS.x
	view._update_camera()
	check(view.arena._hall_shell_models().all(func(m: ELModel) -> bool: return m.visible), "Dungeon arena: zoomed in, the hall's walls show again")
	if kept == null: view.settings.values.erase("auto_camera")
	else: view.settings.values.auto_camera = kept
	view.queue_free()
	await frames(2)

# --- Second game: shaded colourless creatures (#98) ---------------------------------

func _unlit(model: ELModel) -> Array[int]:
	var counts: Array[int] = [0, 0]
	for part: MeshInstance3D in model.parts.values():
		var material := part.material_override as StandardMaterial3D
		if material == null: continue
		counts[1] += 1
		if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: counts[0] += 1
	return counts

func _shaded_colourless(profile: ELProfile) -> void:
	var reaper := ELModel.new()
	root.add_child(reaper)
	var hero := ELModel.new()
	root.add_child(hero)
	if not reaper.build(profile, "cr707", "Alpha\\HinduTwoHands") or not hero.build(profile, "he705", ""):
		check(false, "el2: the Reaper and hero models build")
	else:
		var shaded := _unlit(reaper)
		check(reaper.colourless and shaded[1] > 0 and shaded[0] == 0, "el2: a materialised colourless Reaper takes light and shadow (%d/%d unlit)" % shaded)
		reaper.set_opacity(0.4)
		var pale := _unlit(reaper)
		check(pale[0] == pale[1], "el2: in the pale aspect the Reaper glows, as the original draws it (%d/%d unlit)" % pale)
		reaper.set_opacity(1.0)
		var back := _unlit(reaper)
		check(back[0] == 0, "el2: materialised again it is shaded again (%d/%d unlit)" % back)
		var lit := _unlit(hero)
		check(not hero.colourless and lit[0] > 0, "el2: a hero's glowing parts still glow (%d/%d unlit)" % lit)
	reaper.free()
	hero.free()

# --- Save names keep the symbols the originals refused (#114) -------------------------

func _save_name_symbols() -> void:
	check(ELSaveSlots.clean_name("el2", " a\\b/c:d*e?f\"g<h>i|j.k[l]m,n;o= ") == "a\\b/c:d*e?f\"g<h>i|j.k[l]m,n;o=", "saves: a name may use the symbols the originals refused")
	check(ELSaveSlots.clean_name("el1", "   ").is_empty() and ELSaveSlots.clean_name("el2", "").is_empty(), "saves: a blank name is still refused")
	check(ELSaveSlots.clean_name("el1", "a\tb").is_empty(), "saves: control characters are refused")
	check(ELSaveSlots.save_path("el1", "x:y").get_file().begins_with("slot-"), "saves: the file name stays a hash of the save name")

# --- First game: the borrowed battle dome --------------------------------------------

func _first_dome() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	var campaign := ELCampaign.new()
	campaign.load_campaign(view.profiles.el1, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	var saves := _backup(ELSaveSlots.folder("el1"))
	view.settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(view.settings).persist = false
	await view._begin_campaign("el1", row, 1)
	_restore(ELSaveSlots.folder("el1"), saves)
	var map: ELAdventureView = view.campaign_view
	check(map != null and map.dome_source == view.profiles.el2, "el1: the map borrows the second game's dome")
	if map == null:
		view.queue_free()
		return
	await frames(5)
	if map.tutorial_panel != null and map.tutorial_panel.visible: map.tutorial_panel.close()
	var state := map.state
	var hero := {}
	var monster := {}
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false): continue
		if item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player and hero.is_empty(): hero = item
	# The nearest creature, as a real fight would have it.
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false) or item.get("type") != "monster" or int(item.get("x", -1)) < 0 or hero.is_empty(): continue
		var reach := Vector2(item.x, item.y).distance_to(Vector2(hero.x, hero.y))
		if monster.is_empty() or reach < Vector2(monster.x, monster.y).distance_to(Vector2(hero.x, hero.y)): monster = item
	map.director._begin_encounter(hero, monster)
	await frames(3)
	check(map.hud.precombat.visible and map.effects.effects.has(ELAdventureView.BATTLE_DOME) and map.audio.sounds.has(ELAdventureView.BATTLE_DOME), "el1: the pre-battle panel raises the dome and its sound")
	check(map.hud.precombat.position.y + map.hud.precombat.size.y <= 740 and map.hud.precombat.position.y > 400, "el1: with the dome up the panel stands at the foot of the map, clear of it")
	if not shots.is_empty():
		await frames(90)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots.path_join("dome_el1.png"))
	map.decline_encounter()
	await frames(2)
	check(not map.effects.effects.has(ELAdventureView.BATTLE_DOME) and not map.audio.sounds.has(ELAdventureView.BATTLE_DOME), "el1: declining the battle ends the dome")
	check(is_equal_approx(map.hud.precombat.position.y, 286.0), "el1: the panel goes back to its original place for the next battle")
	view.queue_free()
	await frames(2)

# --- Second game: a battle between computer figures -----------------------------------

func _computer_fight() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(view.profiles.el2):
		if str(found.id).to_lower().ends_with("e2mission11"): entry = found
	var saves := _backup(ELSaveSlots.folder("el2"))
	await view._begin_campaign("el2", ELSingleScenario.scenario(entry), 1)
	var map: ELAdventureView = view.campaign_view
	check(map != null, "el2: chapter 11 opens")
	if map == null:
		_restore(ELSaveSlots.folder("el2"), saves)
		view.queue_free()
		return
	var state := map.state
	var director := map.director
	for i in 40:
		if director.dialogue.is_empty(): break
		director.acknowledge("OK")
		await frames(3)
	ELFog.reveal_for_console(state, 1, true)
	ELFog.refresh(state)
	# The chapter's guard (its battle hook names it the winner) and a Synth
	# Soldier, as the chapter's dock attack creates one.
	var guard := state.object(int(state.vm.globals.get("ID_H_EGUARD", -1)))
	var soldier := state.object(state.create_hero(3, "m11 - Synth Soldier", int(guard.x) + 1, int(guard.y)))
	await frames(5)
	var seen: Array[String] = []
	director.presentation.connect(func(data: Dictionary): if str(data.kind).begins_with("auto_fight"): seen.append(str(data.kind)))
	director._begin_encounter(soldier, guard)
	await frames(2)
	check(director.auto_fight.get("phase") == "summon" and soldier.alive and guard.alive and not director._map_idle(), "el2: a computer battle first holds the map with both figures alive")
	check(map.effects.effects.has(ELAdventureView.BATTLE_DOME) and map.audio.sounds.has(ELAdventureView.BATTLE_DOME), "el2: the dome and its sound rise over the computer battle")
	var start := Time.get_ticks_msec()
	while not director.auto_fight.is_empty() and Time.get_ticks_msec() - start < 10000:
		if not director.dialogue.is_empty(): director.acknowledge("OK")
		await process_frame
	check(seen == ["auto_fight", "auto_fight_defeat", "auto_fight_end"], "el2: the battle shows Summon, then the loser's defeat, then ends (%s)" % ", ".join(seen))
	check(not soldier.alive and guard.alive, "el2: the chapter's hook decides it: the Synth Soldier dies, the guard lives")
	check(not map.effects.effects.has(ELAdventureView.BATTLE_DOME), "el2: the dome ends with the battle")
	# A save made during the presentation resolves the battle first.
	var second := state.object(state.create_hero(3, "m11 - Synth Soldier", int(guard.x) + 1, int(guard.y)))
	await frames(2)
	director._begin_encounter(second, guard)
	check(not director.auto_fight.is_empty(), "el2: a second computer battle is being shown")
	var codec := ELAdventureSave.new()
	var document := codec.encode(director)
	check(not document.is_empty() and director.auto_fight.is_empty() and not second.alive and guard.alive, "el2: saving meanwhile resolves the battle before writing")
	# No winner (the chapter's hook names neither side): both take the defeat
	# and both die, as in the original.
	var other := {}
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and str(item.get("name", "")) == "m11 - Guard" and int(item.uid) != int(guard.uid): other = item
	check(not other.is_empty() and ELAdventureEncounter.second_result(state, int(state.create_hero(3, "m11 - Synth Soldier", 0, 0)), int(other.uid)) == -1, "el2: chapter 11's hook names no winner against its other guard")
	var third := state.object(state.create_hero(3, "m11 - Synth Soldier", int(other.x) + 1, int(other.y)))
	await frames(2)
	var losers: Array = []
	director.presentation.connect(func(data: Dictionary): if data.kind == "auto_fight_defeat": losers.assign(data.losers))
	director._begin_encounter(third, other)
	start = Time.get_ticks_msec()
	while not director.auto_fight.is_empty() and Time.get_ticks_msec() - start < 10000:
		if not director.dialogue.is_empty(): director.acknowledge("OK")
		await process_frame
	check(losers.size() == 2, "el2: with no winner both sides take the defeat")
	check(not third.alive and not other.alive, "el2: with no winner both sides die")
	_restore(ELSaveSlots.folder("el2"), saves)
	view.queue_free()
	await frames(2)

func _backup(folder: String) -> Dictionary:
	var files := {}
	if DirAccess.dir_exists_absolute(folder):
		for file: String in DirAccess.get_files_at(folder): files[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return files

func _restore(folder: String, files: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file: String in DirAccess.get_files_at(folder):
		if not files.has(file): DirAccess.remove_absolute(folder.path_join(file))
	for file: String in files:
		var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
		if out != null: out.store_buffer(files[file])

# --- Battle rules and controls (reports #81 #90 #95 #96 #101 #103 #104 #108 #110) --

## The new creature of `side` summoned from `card`.
func _summoned(duel: ELDuel, side: int, card: String) -> int:
	var known := duel.creatures.keys()
	duel._summon(side, card)
	for key: int in duel.creatures:
		if not known.has(key): return key
	return -1

func _pale_commands(profile: ELProfile) -> void:
	var duel := ELDuel.new()
	if not duel.start(profile, 11, {}):
		check(false, "el2: a duel for the pale commands starts")
		return
	var side := duel.active_side()
	duel.heroes[side].mana = 10
	var pale := _summoned(duel, side, "OUE1")
	duel.creatures[pale].sick = false
	duel.plane_change(pale, true)
	# #96: Mystic manifestation needs an enchantment its hero cast.
	check(duel.in_plane(pale) and not duel.can_use_ability(pale, "mystic"), "el2: a Pale Enchanter cannot manifest with no enchantment of its hero in play")
	var other := _summoned(duel, 1 - side, "ORSH")
	duel._enchant("ENFL", 1 - side, other, ELCatalog.rule(profile, "ENFL"))
	check(not duel.can_use_ability(pale, "mystic"), "el2: the opponent's enchantment does not open Mystic manifestation")
	duel._enchant("ENFL", side, other, ELCatalog.rule(profile, "ENFL"))
	check(duel.can_use_ability(pale, "mystic"), "el2: an enchantment its hero cast opens Mystic manifestation")
	# #95: Pale Revival with a plane creature and a creature in a graveyard.
	duel._give_card(side, "ORFT")
	var index: int = duel.heroes[side].hand.size() - 1
	check(not duel.can_cast_from_hand(index), "el2: Pale Revival waits for a creature in a graveyard")
	duel.heroes[1 - side].grave.append("ORSH")
	check(duel.can_cast_from_hand(index), "el2: Pale Revival is castable with a plane creature and a creature in a graveyard")

func _battle_controls(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		view.queue_free()
		return
	var profile: ELProfile = view.profiles[edition]
	var players := [{"faction": "Blue", "level": 3, "map_level": 2, "cards": ELCatalog.available_cards(profile, "Blue").slice(0, 8)},
		{"faction": "Red", "level": 5, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)}]
	view._start(edition, {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": players})
	view.demo = false
	await frames(10)
	var duel: ELDuel = view.duel
	if duel == null or not view._human_turn():
		check(false, "%s: a battle for the control checks starts on the player's turn" % edition)
		view.queue_free()
		return
	var side := duel.active_side()
	duel.heroes[side].mana = 9
	# #110: the tooltip names the hero's own level.
	var level_line := "%s: %d" % [view._original_text("T_LEVEL", "Level"), 2 if side == 0 else 5]
	check(view._hero_tip(side).labels.any(func(label: Dictionary) -> bool: return str(label.text).contains(level_line)), "%s: the hero tooltip names the hero's own level (%s)" % [edition, level_line])
	# #108 / #104: Fresh Wind asks for its hero, then X; Comet X first.
	duel._give_card(side, "FRWN")
	var wind: int = duel.heroes[side].hand.size() - 1
	view._cast_card(wind)
	check(not view.power_dialog.visible and view.selection == wind, "%s: Fresh Wind first asks for its target" % edition)
	view._target(side)
	check(view.power_dialog.visible and int(view.pending_power.get("target", -1)) == side, "%s: after the hero Fresh Wind asks for X" % edition)
	var prompt: String = view.param_prompt(5, " ")
	check(not prompt.is_empty() and view.power_dialog.readout.text.begins_with(prompt), "%s: the X choice names what it counts (%s)" % [edition, view.power_dialog.readout.text])
	var before: int = view.power_dialog.value()
	view.power_dialog._hold(-1)
	view.power_dialog._process(0.6)
	view.power_dialog._hold(0)
	check(view.power_dialog.value() <= before - 2, "%s: holding Decrease repeats it (%d -> %d)" % [edition, before, view.power_dialog.value()])
	view._cancel_power()
	duel._give_card(side, "COMT")
	view._cast_card(duel.heroes[side].hand.size() - 1)
	check(view.power_dialog.visible and view.selection < 0, "%s: Comet asks for X first" % edition)
	view._cancel_power()
	# #81: a right click drops the pending target choice.
	view._cast_card(wind)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(5, 5)
	view._right_button(press)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	view._right_button(release)
	check(view.selection < 0, "%s: a right click cancels the spell waiting for its target" % edition)
	# #103 / #90: own ability first, then the enchantments.
	var shaman := _summoned(duel, side, "ORSH")
	duel._enchant("ENFL" if edition == "el2" else "IMMB", 1 - side, shaman, ELCatalog.rule(profile, "ENFL" if edition == "el2" else "IMMB"))
	view.selected_creature = shaman
	view._fill_strip()
	var items: Array = view.rail.strip.items
	check(items.size() >= 2 and items[0].meta.has("ability") and items[1].meta.has("enchantment"), "%s: a creature's own ability sits left of its enchantments" % edition)
	if edition == "el2" and not items.is_empty():
		var about := profile.text(str(profile.table("CombatSpells").ORSH.AbilityText))
		check(str(items[0].tooltip) == about, "el2: a free ability's tooltip is its text alone")
	# Player suggestion: on the strip, an enchantment whose ability was used
	# this round moves to the right end; unused ones come first.
	duel._enchant("LSHE", side, side, ELCatalog.rule(profile, "LSHE"))
	duel._enchant("FRBL", side, side, ELCatalog.rule(profile, "FRBL"))
	for e: Dictionary in duel.heroes[side].enchantments:
		if e.card == "LSHE": e.used = true
	view.selected_creature = side
	view._fill_strip()
	var cards: Array = view.rail.strip.items.map(func(item: Dictionary) -> String: return str(item.meta.get("card", "")))
	check(cards.find("FRBL") >= 0 and cards.find("LSHE") > cards.find("FRBL") and cards.find("LSHE") == cards.size() - 1, "%s: an enchantment ability used this round moves to the end of the strip (%s)" % [edition, cards])
	for e: Dictionary in duel.heroes[side].enchantments:
		if e.card == "LSHE": e.used = false
	view._fill_strip()
	cards = view.rail.strip.items.map(func(item: Dictionary) -> String: return str(item.meta.get("card", "")))
	check(cards.find("LSHE") >= 0 and cards.find("LSHE") < cards.find("FRBL"), "%s: unused, the strip keeps the oldest first" % edition)
	duel.heroes[side].enchantments = duel.heroes[side].enchantments.filter(func(e: Dictionary) -> bool: return not e.card in ["LSHE", "FRBL"])
	# #101: second-game Attack all leaves a 0-power creature home.
	var strong := _summoned(duel, side, "ORSH")
	var weak := _summoned(duel, side, "ORSH")
	for id: int in [strong, weak]:
		duel.creatures[id].sick = false
		duel.creatures[id].resting = false
	duel.creatures[weak].power = 0
	view._attack_all()
	check(duel.attacks.has(strong) and duel.attacks.has(weak) == (edition == "el1"), "%s: Attack all %s a 0-power creature" % [edition, "sends" if edition == "el1" else "leaves out"])
	view.queue_free()
	await frames(2)

# --- Map reports: zones, quick load, picking, skills, castles, tunnels --------------

## First game (#62, #67, #79, #80, #111) on the first Good mission.
func _first_map_reports() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	var campaign := ELCampaign.new()
	campaign.load_campaign(view.profiles.el1, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	var saves := _backup(ELSaveSlots.folder("el1"))
	view.settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(view.settings).persist = false
	await view._begin_campaign("el1", row, 1)
	var map: ELAdventureView = view.campaign_view
	if map == null:
		_restore(ELSaveSlots.folder("el1"), saves)
		check(false, "el1: the first mission opens for the map reports")
		view.queue_free()
		return
	await frames(5)
	if map.tutorial_panel != null and map.tutorial_panel.visible: map.tutorial_panel.close()
	var state := map.state
	var director := map.director
	var hero := {}
	var monster := {}
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player and hero.is_empty(): hero = item
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false) or item.get("type") != "monster" or not monster.is_empty(): continue
		var open := true
		for dx in [-4, -3, -2, -1]: if director.grid.passability(Vector2i(int(item.x) + dx, int(item.y))) < 0: open = false
		if open: monster = item
	# #62: a declined creature battle (free movement) puts the hero back on the
	# cell it entered the guard zone from, and it can walk on.
	if not monster.is_empty():
		director.free_movement = true
		var start := Vector2i(int(monster.x) - 4, int(monster.y))
		hero.x = start.x
		hero.y = start.y
		director.grid.update_actor(hero)
		hero.ap = 30
		var enter := start
		for dx in [1, 2, 3]:
			if not director.interception.enemies(state, hero, start + Vector2i(dx, 0)).is_empty():
				enter = start + Vector2i(dx, 0)
				break
		director.request_move(int(hero.uid), enter)
		director.request_move(int(hero.uid), enter)
		var t := Time.get_ticks_msec()
		while director.encounter == null and Time.get_ticks_msec() - t < 8000: await process_frame
		check(director.encounter != null and Vector2i(int(hero.x), int(hero.y)) == enter, "el1: stepping into a creature's zone opens its battle")
		if director.encounter != null:
			map.decline_encounter()
			await frames(3)
			var back := Vector2i(int(hero.x), int(hero.y))
			check(back == enter - Vector2i(1, 0) and not hero.intercepted and director.interception.enemies(state, hero, back).is_empty(), "el1: declining puts the hero back where it entered the zone (%s)" % back)
			director.request_move(int(hero.uid), start)
			director.request_move(int(hero.uid), start)
			t = Time.get_ticks_msec()
			while Vector2i(int(hero.x), int(hero.y)) != start and Time.get_ticks_msec() - t < 6000: await process_frame
			check(Vector2i(int(hero.x), int(hero.y)) == start and director.encounter == null, "el1: after declining the hero walks away the same day")
	# #79: an object (a pickup, site or building) on the cell behind the hero is picked,
	# not the hero.
	var pickup := {}
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("visible", false) and (ELMapPickups.is_pickup(item) or str(item.get("group", "")) in ELAdventureView.FIRST_SITE_GROUPS or (item.get("group") == "additional_buildings" and not ELAdditionalBuildings.title(state.map.profile, item).is_empty())) and director.grid.passability(Vector2i(int(item.x), int(item.y) - 1)) >= 0:
			pickup = item
			break
	if not pickup.is_empty():
		ELFog.reveal_for_console(state, state.current_player, true)
		hero.x = int(pickup.x)
		hero.y = int(pickup.y) - 1
		director.grid.update_actor(hero)
		await frames(2)
		check(map._object_at(Vector2(float(pickup.x) + 0.5, float(pickup.y) + 0.5)) == int(pickup.uid), "el1: an object on the cell behind the hero is picked, not the hero (%s)" % pickup.name)
		check(map._object_at(Vector2(float(hero.x) + 0.5, float(hero.y) + 0.5)) == int(hero.uid), "el1: the hero's own cell still picks the hero")
		# The same with the camera ray: pointing at the pickup's drawn middle.
		var drawn: AABB = map.world.object_bounds(int(pickup.uid))
		if drawn.has_volume():
			var at := map.camera.unproject_position(map.world.to_global(drawn.get_center()))
			var ground: Variant = Plane(Vector3.UP, 0).intersects_ray(map.camera.project_ray_origin(at), map.camera.project_ray_normal(at))
			check(ground != null and map._object_at(Vector2(ground.x, -ground.z) / ELAdventureTerrain.CELL, at) == int(pickup.uid), "el1: pointing at the object behind the hero picks it")
	# #80: a right press on a learned skill holds its description up.
	hero.skills = {"MOBL": 1}
	map.open_hero_screen(int(hero.uid))
	await frames(3)
	var screen: ELHeroScreenView = map.hero_screen
	if screen != null:
		var point: Vector2 = ELHeroScreenView.SKILL_BOXES[0] + Vector2(30, 6)
		var expected := screen.skill_tip_at(point)
		check(screen.right_press(point) and screen.skill_tip != null and expected.contains(screen._skill_name("MOBL", 1)) and expected.contains("\n"), "el1: right-clicking a skill shows its name and description")
		screen.right_release()
		check(screen.skill_tip == null, "el1: letting the right button go closes the skill tooltip")
		check(not screen.right_press(Vector2(200, 30)), "el1: a right click elsewhere on the hero screen shows no skill tooltip")
		# #132: the level-up offers hold their description up too.
		hero.skill_offers = ["HEAL", "BARG", "MSTR"]
		hero.skill_points = 1
		screen.refresh()
		var offer_point := Vector2(362 + ELHeroScreenView.STEP * 1 + 25, 233 + 25)
		check(screen.right_press(offer_point) and screen.skill_tip != null and screen.skill_tip_at(offer_point).contains(screen._skill_name("BARG", 0)), "el1: right-clicking a level-up offer shows its name and description (#132)")
		screen.right_release()
		hero.erase("skill_offers")
		hero.skill_points = 0
		screen.cancel()
		await frames(2)
	# #111: a castle assault turns the hero, plays its attack clip and the
	# colour's damage effect at the castle.
	var castle := ELFirstScenario.castle_object(state, state.current_player)
	if not castle.is_empty():
		map.present_castle_assault(int(hero.uid), state.current_player)
		var model: ELModel = map.world.actors.get(int(hero.uid))
		var clip := model.clip_for_code(ELAdventureView.CASTLE_ATTACK_CODE) if model != null else ""
		if model != null and clip.is_empty(): clip = model.clip_for_code(ELAdventureView.CASTLE_ATTACK_CODE | 0x80000000)
		check(model != null and not clip.is_empty() and model.clip == clip, "el1: attacking a castle plays the hero's attack clip (%s)" % clip)
		check(map.effects.effects.has("castle_assault:%d" % int(hero.uid)), "el1: attacking a castle shows the damage effect at the castle")
	# #67: a second F8 answers the quick-load question with OK.
	var written := ELSaveSlots.write(ELSaveSlots.quick_name(state.map.profile), director, map.camera_state())
	if written.is_empty():
		var resumed := [false]
		map.resume_requested.connect(func(): resumed[0] = true)
		var f8 := InputEventKey.new()
		f8.keycode = KEY_F8
		f8.pressed = true
		map.ask_quick_load()
		await frames(2)
		check(map.extras != null and map.extras.duel_ui.message_open() and not resumed[0], "el1: F8 asks before loading the quick save")
		if map.extras != null: map.extras._input(f8.duplicate())
		await frames(2)
		check(resumed[0], "el1: a second F8 confirms the quick load")
	else: check(false, "el1: the quick save is written: " + written)
	_restore(ELSaveSlots.folder("el1"), saves)
	view.queue_free()
	await frames(2)

## Second game (#70, #72, #75) on chapter 23: a tunnel guard is fought on the
## Dungeon arena and shows its portrait; a specialization shrine plays the
## hero's change effect.
func _second_map_reports() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(view.profiles.el2):
		if str(found.id).to_lower().ends_with("e2mission23"): entry = found
	var saves := _backup(ELSaveSlots.folder("el2"))
	await view._begin_campaign("el2", ELSingleScenario.scenario(entry), 1)
	var map: ELAdventureView = view.campaign_view
	if map == null:
		_restore(ELSaveSlots.folder("el2"), saves)
		check(false, "el2: chapter 23 opens for the map reports")
		view.queue_free()
		return
	var state := map.state
	var director := map.director
	for i in 40:
		if director.dialogue.is_empty(): break
		director.acknowledge("OK")
		await frames(3)
	# Light fog: a tile explored before but out of sight now takes an order;
	# never-explored ground does not.
	var bit := ELFog.bit(1)
	var sight: PackedByteArray = state.fog.get("visible", PackedByteArray())
	var light := Vector2i(-1, -1)
	var dark := Vector2i(-1, -1)
	for index in state.explored.size():
		var tile := Vector2i(index % int(state.map.width), index / int(state.map.width))
		var shown := index < sight.size() and (sight[index] & bit) != 0
		if light.x < 0 and (state.explored[index] & bit) != 0 and not shown: light = tile
		if dark.x < 0 and (state.explored[index] & bit) == 0: dark = tile
	if light.x < 0:
		# Mark a sighted tile as no longer in view.
		for index in sight.size():
			if (sight[index] & bit) != 0 and (state.explored[index] & bit) != 0:
				sight[index] &= ~bit
				state.fog.visible = sight
				light = Vector2i(index % int(state.map.width), index / int(state.map.width))
				break
	check(light.x >= 0 and ELFog.tile_state(state, 1, light) == ELFog.REMEMBERED and ELFog.targetable(state, 1, light), "el2: a tile under light fog (explored, out of sight) can be targeted")
	check(dark.x < 0 or not ELFog.targetable(state, 1, dark), "el2: never-explored ground still refuses an order")
	ELFog.reveal_for_console(state, 1, true)
	ELFog.refresh(state)
	var hero := state.object(state.main_hero)
	var guard := {}
	var mouth := {}
	for item: Dictionary in state.objects.values():
		if ELSecondBuildings.is_tunnel(item) and state.object(item.get("guard", -1)).get("alive", false):
			mouth = item
			guard = state.object(item.guard)
			break
	check(not guard.is_empty(), "el2: chapter 23 has a guarded tunnel")
	if not guard.is_empty():
		guard.tunnel_source = int(mouth.uid)
		check(ELAdventureEncounter.second_arena(state, int(hero.uid), int(guard.uid), 0) == "Dungeon.001", "el2: a tunnel guard is fought on the Dungeon arena")
		map._open_second_precombat(int(hero.uid), int(guard.uid))
		check(int(map.second_precombat._faces[1]) >= 0, "el2: the pre-battle panel shows the tunnel guard's portrait")
		map._close_second_precombat()
		guard.erase("tunnel_source")
	var shrine := {}
	for item: Dictionary in state.objects.values():
		if ELSecondBuildings.kind(item) == "specialization" and not item.get("used", false) and not ELSecondBuildings.shrine_code(state.map.profile, item).is_empty():
			shrine = item
			break
	if not shrine.is_empty():
		hero.travel_day = state.day
		var seen := [false]
		state.event.connect(func(data: Dictionary): if data.kind == "hero_change_effect" and int(data.id) == int(hero.uid): seen[0] = true)
		check(ELSecondBuildings.use(director, hero, shrine) and seen[0], "el2: using a specialization shrine plays the hero's change effect")
		check(map.effects.effects.has("hero_change:%d" % int(hero.uid)), "el2: the change effect (Bereserk.pfx) shows on the hero")
		for i in 10:
			if director.dialogue.is_empty(): break
			director.acknowledge("OK")
			await frames(2)
	_restore(ELSaveSlots.folder("el2"), saves)
	view.queue_free()
	await frames(2)

## #73: a save the codec refuses, loaded from the menus, brings the menus
## back with the reason (not the duel behind them).
func _refused_load() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(5)
	if view.front_menu == null: view._show_front_menu()
	await frames(2)
	if view.front_menu == null:
		print("SKIP: no front menu for the refused-load check")
		view.queue_free()
		return
	var path := "user://refused-load-check.json"
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify({"format": ELAdventureSave.FORMAT, "version": 1, "edition": "el1", "map": "no-such-map"}))
	out.close()
	view._hide_front_menu(true)
	view._resume_campaign(false, path, "el1")
	await frames(2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(view.campaign_view == null and view.front_layer.visible and view.front_menu.duel_ui.message_open(), "a refused save returns to the menu with its reason")
	view.queue_free()
	await frames(2)
