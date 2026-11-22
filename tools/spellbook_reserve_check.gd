extends SceneTree
## Headless check that an Etherlords spell bought or dropped over a cantrip
## keeps that cantrip under it on every path, and that storing the spell in the
## reserve gives the slot back to the cantrip at once, the spell keeping its
## runes:
## - the laboratory purchase over a cantrip, then the double click, the right
##   click and the "to reserve" arrow of the book screen;
## - a reserve spell dropped onto a bought spell (replacement): the bought one
##   goes to the reserve with its runes, the cantrip stays underneath;
## - a laboratory purchase over a bought spell, and a cantrip bought over one,
##   which takes the slot itself;
## - a save and load keep the cantrips underneath;
## - saves made before the book kept them (before 0.13.0 a laboratory spell
##   overwrote the cantrip) get back only the cantrips the hero began with,
##   and the book keeps its size; a hero whose starting book holds rune
##   spells gets no cantrip under them;
## - a new book (ELRunes.initialize) drops what waited under the old one;
## - #167: a hero freed from a prison (Thaereid, Chaot chapter 1) keeps the
##   chapter's book and gets his colour's basic spells under it, slot by
##   slot; storing a spell gives the slot to the basic spell, and a spell with
##   no runes left keeps its slot and draws the basic spell in battle (#289);
##   a save and load keep them, and a save made before they were given
##   gets them once.
##
##   godot --headless --path game --script ../tools/spellbook_reserve_check.gd
##
## Needs Etherlords (user://profiles.json); skipped without it. Nothing is saved.

var failures: Array[String] = []
var host: Control
var sessions: Array[ELAdventureSession] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	host = Control.new()
	host.size = Vector2(1280, 800)
	root.add_child(host)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: Etherlords files are not configured")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: Etherlords files could not be mounted")
		quit(0)
		return
	await _laboratory_and_book(profile)
	await _saves(profile)
	_starting_rune_spells(profile)
	await _prisoner(profile)
	print("SPELLBOOK RESERVE CHECK: %d failure(s)" % failures.size())
	host.queue_free()
	for state: ELAdventureSession in sessions: state.close()
	await frames(3)
	quit(0 if failures.is_empty() else 1)

## A campaign mission started without its script, with its director and the
## map panel, and the player's hero; with `laboratory` only one with a
## laboratory that sells that hero spells.
func _session(profile: ELProfile, campaign_index := 0, mission := 0, laboratory := false) -> Dictionary:
	var ids := ELCampaign.available(profile)
	var campaign := ELCampaign.new()
	if campaign_index >= ids.size() or not campaign.load_campaign(profile, ids[campaign_index]) or campaign.scenarios.size() <= mission: return {}
	var map := ELAdventureMap.new()
	if not map.load_map(profile, str(campaign.scenarios[mission].file_name)): return {}
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, false): return {}
	sessions.append(state)
	var hero_id := -1
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player:
			hero_id = int(item.uid)
			break
	if hero_id < 0: return {}
	var shop := -1
	if laboratory:
		for item: Dictionary in state.objects.values():
			if item.get("group") != "laboratories": continue
			var trade := ELFirstSpellShop.new()
			if trade.open(state, hero_id, int(item.uid), true) and trade.stock.size() >= 3:
				trade.cancel()
				shop = int(item.uid)
				break
		if shop < 0: return {}
	var director := ELAdventureDirector.new()
	if not director.build(state): return {}
	var hud := ELAdventureHud.new()
	host.add_child(hud)
	if not hud.build(state): return {}
	return {"profile": profile, "state": state, "director": director, "hero": hero_id, "hud": hud, "shop": shop, "mission": mission}

static func _cantrips(profile: ELProfile, hero: Dictionary) -> bool:
	return hero.cards.size() == ELSpellInventory.book_size(profile) and hero.cards.all(func(code: String) -> bool: return ELRunes.unlimited(profile, hero, code))

static func _rich(state: ELAdventureSession, hero: Dictionary) -> void:
	for kind: String in state.players[hero.owner].resources: state.players[hero.owner].resources[kind] = 1000000

## Buys `card` over book slot `slot` in the session's laboratory.
## With `offer` the laboratory offers the card even if its stock does not.
static func _buy(state: ELAdventureSession, hero_id: int, shop: int, slot: int, card: String, offer := false) -> bool:
	var trade := ELFirstSpellShop.new()
	if not trade.open(state, hero_id, shop, true): return false
	if offer and not trade.stock.has(card): trade.stock.append(card)
	if not trade.replace(slot, card): return false
	return trade.commit()

func _laboratory_and_book(profile: ELProfile) -> void:
	var session := {}
	for mission in 10:
		session = _session(profile, 0, mission, true)
		if not session.is_empty() and _cantrips(profile, session.state.object(session.hero)): break
		session = {}
	check(not session.is_empty(), "a campaign mission has a laboratory and a hero with a book of cantrips")
	if session.is_empty(): return
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	_rich(state, hero)
	var trade := ELFirstSpellShop.new()
	trade.open(state, session.hero, session.shop, true)
	var stock: Array[String] = []
	for card: String in trade.stock:
		if not ELRunes.unlimited(profile, hero, card) and not stock.has(card): stock.append(card)
	var cantrip_stock: Array = trade.stock.filter(func(card: String) -> bool: return ELRunes.unlimited(profile, hero, card))
	trade.cancel()
	check(stock.size() >= 2, "the laboratory sells two rune spells")
	if stock.size() < 2: return
	var size: int = hero.cards.size()
	var start: Array = hero.cards.duplicate()

	# Laboratory over a cantrip, then the three ways back to the reserve.
	var view := ELFirstBookView.new()
	host.add_child(view)
	view.build_book(session.director, session.hud, session.hero)
	await frames(3)
	var input: Callable = view.sheet._gui_input
	var ways := ["double click", "right click", "arrow"]
	for way in ways.size():
		var slot := 2 + way
		check(_buy(state, session.hero, session.shop, slot, stock[0]), "laboratory: %s bought over the cantrip of slot %d" % [stock[0], slot])
		check(hero.cards[slot] == stock[0] and ELRunes.under(hero)[slot] == start[slot], "laboratory: the cantrip waits under the bought spell (slot %d)" % slot)
		hero.rune_uses[slot] = 3 + way
		var reserve_before := int(hero.spell_stock.get(stock[0], 0))
		view.refresh()
		match way:
			0:
				item_click(input, view.book_rect(slot).get_center())
				item_click(input, view.book_rect(slot).get_center(), true)
			1: view.right_press(view.book_rect(slot).get_center())
			2:
				item_click(input, view.book_rect(slot).get_center())
				check(not view.buttons.RetrieveSpell.disabled, "book: the arrow to the reserve is offered for the bought spell")
				view.unequip()
		check(hero.cards.size() == size and hero.cards[slot] == start[slot] and int(hero.rune_uses[slot]) == -1 and ELRunes.under(hero)[slot].is_empty(), "book (%s): storing the bought spell gives the slot back to its cantrip at once" % ways[way])
		check(int(hero.spell_stock.get(stock[0], 0)) == reserve_before + 1 and hero.rune_stock[stock[0]].has(3 + way), "book (%s): the stored spell keeps its %d runes in the reserve" % [ways[way], 3 + way])
	check(hero.cards == start, "book: the book is again the starting book of cantrips")

	# Replacement: a reserve spell dropped onto a bought spell.
	check(_buy(state, session.hero, session.shop, 6, stock[0]), "laboratory: bought over slot 6")
	hero.rune_uses[6] = 7
	ELSpellInventory.add(profile, hero, stock[1])
	hero.rune_stock[stock[1]][-1] = 2
	view.refresh()
	var entry := _entry(view, stock[1], 2)
	check(entry >= 0, "book: the second spell is in the reserve")
	if entry >= 0:
		item_drag(input, view.reserve_rect(entry).get_center(), view.book_rect(6).get_center())
	check(hero.cards[6] == stock[1] and int(hero.rune_uses[6]) == 2 and ELRunes.under(hero)[6] == start[6] and hero.rune_stock.get(stock[0], []).has(7), "replacement: the bought spell goes to the reserve with its runes; the cantrip stays underneath")
	item_click(input, view.book_rect(6).get_center())
	item_click(input, view.book_rect(6).get_center(), true)
	check(hero.cards.size() == size and hero.cards[6] == start[6] and hero.rune_stock.get(stock[1], []).has(2), "replacement: storing the new spell gives the slot back to the cantrip")

	# Laboratory over a bought spell, then a cantrip over it.
	check(_buy(state, session.hero, session.shop, 8, stock[0]) and _buy(state, session.hero, session.shop, 8, stock[1]), "laboratory: two spells bought one over the other on slot 8")
	check(hero.cards[8] == stock[1] and ELRunes.under(hero)[8] == start[8] and hero.spell_stock.has(stock[0]), "laboratory: the first goes to the reserve, the cantrip stays underneath")
	# Laboratories sell few cantrips: another of the hero's own is offered.
	var other_cantrip := ""
	for card: String in cantrip_stock + start:
		if card != start[8] and other_cantrip.is_empty(): other_cantrip = card
	check(_buy(state, session.hero, session.shop, 8, other_cantrip, true), "laboratory: a cantrip bought over the spell")
	check(hero.cards[8] == other_cantrip and ELRunes.under(hero)[8].is_empty() and hero.spell_stock.has(stock[1]), "laboratory: a cantrip bought over a spell takes the slot itself, with nothing underneath; the spell goes to the reserve")
	check(_buy(state, session.hero, session.shop, 8, stock[1]), "laboratory: a spell bought over that cantrip")
	check(ELRunes.under(hero)[8] == other_cantrip, "laboratory: the new cantrip waits under it")
	view.queue_free()
	session.hud.queue_free()
	await frames(2)

func _saves(profile: ELProfile) -> void:
	var session := _session(profile)
	check(not session.is_empty() and _cantrips(profile, session.state.object(session.hero)), "the first mission's hero has a book of cantrips")
	if session.is_empty(): return
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	var size: int = hero.cards.size()
	var start: Array = hero.cards.duplicate()
	var spell := ""
	for code: String in ELCatalogSpells(profile):
		if not ELRunes.unlimited(profile, hero, code) and ELSpellInventory.allows(profile, hero, code):
			spell = code
			break
	# Stacked the current way: kept by a save and load.
	ELSpellInventory.add(profile, hero, spell)
	hero.rune_stock[spell][-1] = 5
	check(ELSpellInventory.equip(profile, hero, spell, 0, 4).is_empty(), "save: a spell goes over the cantrip of slot 4")
	var loaded := _reload(session, true)
	var again: Dictionary = loaded.get("state", ELAdventureSession.new()).object(session.hero) if not loaded.is_empty() else {}
	check(not again.is_empty() and again.cards == hero.cards and ELRunes.under(again)[4] == start[4], "save: the cantrip under the spell is kept by a save and load")
	if not again.is_empty():
		check(ELSpellInventory.unequip(profile, again, 4).is_empty() and again.cards.size() == size and again.cards[4] == start[4] and again.rune_stock[spell].has(5), "save: after loading, storing the spell gives the slot back to its cantrip; the spell keeps its runes")
		loaded.state.close()
	ELSpellInventory.unequip(profile, hero, 4)

	# A save from before the book kept its cantrips: two laboratory spells
	# simply overwrote cantrips, one of them was stored and took its slot along.
	var lost := [start[1], start[9], start[12]]
	hero.cards[1] = spell
	hero.rune_uses[1] = 4
	hero.cards[9] = spell
	hero.rune_uses[9] = 6
	hero.cards.remove_at(12)
	hero.rune_uses.remove_at(12)
	hero.erase("rune_under")
	var legacy := _reload(session, false)
	again = legacy.get("state", ELAdventureSession.new()).object(session.hero) if not legacy.is_empty() else {}
	check(not again.is_empty(), "old save: it loads")
	if again.is_empty(): return
	var under := ELRunes.under(again)
	check(again.cards.size() == size - 1 and under[1] == lost[0] and under[9] == lost[1], "old save: the spells bought over cantrips get back the cantrips of their starting slots")
	check(under.count("") == under.size() - 2, "old save: no other slot gets a cantrip, and the book keeps its %d slots" % (size - 1))
	check(ELSpellInventory.unequip(profile, again, 9).is_empty() and again.cards.size() == size - 1 and again.cards[9] == lost[1] and again.rune_stock[spell].has(6), "old save: storing the spell gives the slot back to its cantrip; the spell keeps its runes")
	var within := true
	var after_under := ELRunes.under(again)
	for card: String in start:
		if again.cards.count(card) + after_under.count(card) > start.count(card): within = false
	check(within and again.cards.size() == size - 1, "old save: no hero has more of a cantrip than it began with; the slot lost with its spell is not given back")
	legacy.state.close()
	session.hud.queue_free()
	await frames(2)

## Saves and loads the session's game (through JSON, as on disk); without
## `current` the save is written as by a version before the under mark.
func _reload(session: Dictionary, current: bool) -> Dictionary:
	var codec := ELAdventureSave.new()
	var document := codec.encode(session.director)
	check(not document.is_empty(), "save: the game encodes: %s" % codec.error)
	if document.is_empty(): return {}
	check(document.get("under_version") == ELAdventureSave.UNDER_VERSION, "save: new saves carry the under mark")
	if not current: document.erase("under_version")
	var raw: Variant = JSON.parse_string(JSON.stringify(document, "", true, true))
	var result := codec.decode(raw, {"el1": session.profile})
	check(not result.is_empty(), "save: the game decodes: %s" % codec.error)
	if not result.is_empty(): sessions.append(result.state)
	return result

## A hero whose starting book holds rune spells keeps no cantrip under them
## when an old save is loaded; ELRunes.initialize drops a stale list.
func _starting_rune_spells(profile: ELProfile) -> void:
	var template := ""
	for name: String in profile.table("HeroTemplates"):
		var deck := ELCatalog.deck(profile, str(profile.table("HeroTemplates")[name].get("StartDeck", "")))
		var hero := {"type": "hero", "name": name, "cards": deck, "spell_stock": {}}
		if deck.size() == 15 and deck.any(func(code: String) -> bool: return ELRunes.unlimited(profile, hero, code)) and deck.any(func(code: String) -> bool: return not ELRunes.unlimited(profile, hero, code)):
			template = name
			break
	check(not template.is_empty(), "a hero template starts with rune spells and cantrips")
	if template.is_empty(): return
	var start := ELCatalog.deck(profile, str(profile.table("HeroTemplates")[template].get("StartDeck", "")))
	var hero := {"type": "hero", "name": template, "cards": start.duplicate(), "spell_stock": {}}
	ELRunes.initialize(profile, hero)
	ELRunes.adopt_lost_cantrips(profile, hero, start)
	check(not hero.has("rune_under"), "old save: the starting rune spells of %s get no cantrip underneath" % template)
	var stored := -1
	for slot in hero.cards.size():
		if not ELRunes.unlimited(profile, hero, str(hero.cards[slot])): stored = slot
	ELSpellInventory.unequip(profile, hero, stored)
	ELRunes.adopt_lost_cantrips(profile, hero, start)
	check(hero.cards.size() == 14 and not hero.has("rune_under"), "old save: a starting rune spell stored in the reserve leaves no new cantrip behind")
	hero.rune_under = []
	hero.rune_under.resize(hero.cards.size())
	hero.rune_under.fill("")
	hero.rune_under[0] = str(start[0]) if ELRunes.unlimited(profile, hero, str(start[0])) else "TIWR"
	ELRunes.initialize(profile, hero)
	check(not hero.has("rune_under"), "a new book drops the cantrips that waited under the old one")

## #167: Thaereid, freed from the cage of the Chaot campaign's first chapter.
func _prisoner(profile: ELProfile) -> void:
	var session := {}
	var cage := {}
	for campaign_index in ELCampaign.available(profile).size():
		for mission in 3:
			var found := _session(profile, campaign_index, mission)
			if found.is_empty(): continue
			for item: Dictionary in found.state.objects.values():
				if item.get("name") == "Prison" and ELAdditionalBuildings.prisoner(item) == "Thaereid": cage = item
			if not cage.is_empty():
				session = found
				break
			found.hud.queue_free()
		if not session.is_empty(): break
	check(not session.is_empty(), "prisoner: a campaign chapter holds Thaereid in a cage")
	if session.is_empty(): return
	var state: ELAdventureSession = session.state
	var visitor := state.object(session.hero)
	visitor.x = int(cage.x) + 1
	visitor.y = int(cage.y)
	var message := ELAdditionalBuildings.visit(session.director, visitor, cage)
	var freed := state.object(int(message.get("freed", -1)))
	check(not freed.is_empty() and freed.get("name") == "Thaereid", "prisoner: visiting the cage frees Thaereid")
	if freed.is_empty(): return
	var template: Dictionary = profile.table("HeroTemplates").Thaereid
	var book := ELCatalog.deck(profile, str(template.StartDeck))
	var basic := ELRunes.basic_book(profile, str(template.Color))
	var red_basic := ELCatalog.deck(profile, "STR1")
	check(basic == red_basic and basic.size() == 15, "prisoner: the Chaots' basic spells are the hireable heroes' starting book STR1 (%s)" % ",".join(PackedStringArray(basic)))
	check(freed.cards == book and freed.rune_uses.all(func(n: int) -> bool: return n == 5), "prisoner: his book is still the chapter's orc book with its runes")
	check(ELRunes.under(freed) == basic, "prisoner: a basic spell waits under each of his 15 spells")
	var basics_given := ELRunes.under(freed).duplicate()
	check(ELSpellInventory.unequip(profile, freed, 0).is_empty() and freed.cards.size() == 15 and freed.cards[0] == basic[0] and int(freed.rune_uses[0]) == -1 and freed.rune_stock.get(book[0], []).has(5), "prisoner: storing a spell gives its slot to the basic spell; the book keeps 15 slots and the spell its runes")
	freed.rune_uses[3] = 0
	var fighter := {"deck": freed.cards.slice(3, 4), "spell_uses": [0], "hand_slots": [], "drawn": [], "rune_under": [basic[3]], "kind": "hero"}
	var drawn := ELSpellCharges.choose_el1(fighter, profile.table("CombatSpells"), func(n: int): return 0)
	check(freed.cards[3] == book[3] and drawn.get("card") == basic[3] and freed.cards.size() == 15, "prisoner: a spell with no runes left keeps its slot and draws the basic spell in battle")
	var loaded := _reload(session, true)
	var again: Dictionary = loaded.get("state", ELAdventureSession.new()).object(int(freed.uid)) if not loaded.is_empty() else {}
	check(not again.is_empty() and again.cards == freed.cards and ELRunes.under(again) == ELRunes.under(freed), "prisoner: a save and load keep his book and the basic spells under it")
	# Every basic spell taken back: a later load gives none again.
	var spent := freed.duplicate(true)
	freed.erase("rune_under")
	loaded = _reload(session, true)
	again = loaded.get("state", ELAdventureSession.new()).object(int(freed.uid)) if not loaded.is_empty() else {}
	check(not again.is_empty() and not again.has("rune_under"), "prisoner: once given, a load does not give the basic spells again")
	# A save made before prisoners were given them.
	freed.merge(spent, true)
	freed.cards = book.duplicate()
	freed.rune_uses = [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]
	freed.rune_stock = {}
	freed.spell_stock = {}
	freed.erase("rune_under")
	freed.erase("basic_under")
	loaded = _reload(session, true)
	again = loaded.get("state", ELAdventureSession.new()).object(int(freed.uid)) if not loaded.is_empty() else {}
	check(not again.is_empty() and again.cards == book and ELRunes.under(again) == basics_given, "prisoner: a save from before gets the basic spells under his book once loaded")
	session.hud.queue_free()
	await frames(2)

static func ELCatalogSpells(profile: ELProfile) -> Array:
	var codes: Array = profile.table("CombatSpells").keys()
	codes.sort()
	return codes.filter(func(code: String) -> bool: return ELSpellInventory.is_spell(profile, code))

static func _entry(view: ELFirstBookView, card: String, uses := -2) -> int:
	for index in view.entries.size():
		if view.entries[index].card == card and (uses == -2 or int(view.entries[index].uses) == uses): return index
	return -1

static func item_press(at: Vector2, double := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = at
	event.global_position = at
	return event

static func item_release(at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	event.global_position = at
	return event

static func item_drag(target: Callable, from: Vector2, to: Vector2) -> void:
	target.call(item_press(from))
	for step in 4:
		var event := InputEventMouseMotion.new()
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		event.position = from.lerp(to, (step + 1) / 4.0)
		event.global_position = event.position
		target.call(event)
	target.call(item_release(to))

static func item_click(target: Callable, at: Vector2, double := false) -> void:
	target.call(item_press(at, double))
	target.call(item_release(at))
