extends SceneTree
## Headless check of dragging items between lists on the hero screens:
## - second game, InventoryScreen (ELSecondInventoryView): a bag card dragged
##   onto a deck slot goes there, a deck card dragged into the bag returns to
##   it, two deck cards dragged onto each other swap; a drop on the card's own
##   list or outside the lists changes nothing and nothing stays carried; the
##   click-to-pick, click-to-place and double-click moves still work;
## - second game, SpellShopScreen (ELSpellShopView): a shop card dragged onto
##   a deck slot is bought there, a deck card dragged onto the shop is sold, a
##   shop card dropped back on the shop or outside goes back;
## - second game, LevelUpDialog (ELSecondLevelUpView): an offer dragged onto
##   the skill rows is learned, one dropped elsewhere is only chosen;
## - first game, spellbook on the laboratory panel (ELFirstBookView): a
##   reserve spell dragged onto the book is equipped, a book spell dragged
##   onto the reserve is stored, a drop elsewhere moves nothing, a full book
##   refuses the drop; the double click still moves;
## - first game, HeroScreen (ELHeroScreenView): a level-up offer dragged onto
##   the skills is learned, one dropped elsewhere is not;
## - first game, laboratory (ELFirstSpellShopView): a shop spell dragged onto
##   a book slot is staged there, one dropped elsewhere is let go;
## - the plain list screens (ELSpellbookView, ELHeroSkillsView) take a
##   dragged spell or offer through the viewport's own drag and drop.
##
##   godot --headless --path game --script ../tools/item_drag_check.gd
##
## Pointer input is sent as press, motion and release events in each
## screen's own coordinates. Needs the original games' files
## (user://profiles.json); a game without them is skipped. Nothing is saved.

var failures: Array[String] = []
var host: Control

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# The headless window is tiny; the viewport drag needs the screens inside it.
	root.size = Vector2i(1280, 800)
	host = Control.new()
	host.size = Vector2(1280, 800)
	root.add_child(host)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary:
		print("SKIP: no original game files configured (user://profiles.json)")
		paths = {}
	for edition: String in ["el2", "el1"]:
		if not paths.has(edition):
			print("SKIP: %s files are not configured" % edition)
			continue
		var profile := ELProfile.new()
		if not profile.mount(edition, str(paths[edition])):
			print("SKIP: %s files could not be mounted" % edition)
			continue
		var session := _session(profile)
		if session.is_empty(): continue
		if edition == "el2":
			await _second_inventory(session)
			await _second_shop(session)
			await _second_level_up(session)
			await _plain_lists(session)
		else:
			await _first_book(session)
			await _first_hero_screen(session)
			await _first_shop(profile)
	print("ITEM DRAG CHECK: %d failure(s)" % failures.size())
	host.queue_free()
	for state: ELAdventureSession in sessions: state.close()
	sessions.clear()
	await frames(3)
	quit(0 if failures.is_empty() else 1)

var sessions: Array[ELAdventureSession] = []

## A mission of the first campaign started without its script, a director and
## the edition's map panel, and a living hero of the player. Only the first
## mission's problems count as failures; later ones are tried for a place.
func _session(profile: ELProfile, mission := 0) -> Dictionary:
	var ids := ELCampaign.available(profile)
	var campaign := ELCampaign.new()
	if ids.is_empty() or not campaign.load_campaign(profile, ids[0]) or campaign.scenarios.size() <= mission:
		if mission == 0: check(false, "%s: a campaign mission is listed" % profile.id)
		return {}
	var map := ELAdventureMap.new()
	if not map.load_map(profile, str(campaign.scenarios[mission].file_name)):
		if mission == 0: check(false, "%s: the mission map loads: %s" % [profile.id, map.error])
		return {}
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, false):
		if mission == 0: check(false, "%s: the mission starts: %s" % [profile.id, state.error])
		return {}
	sessions.append(state)
	var director := ELAdventureDirector.new()
	if not director.build(state):
		if mission == 0: check(false, "%s: the director builds: %s" % [profile.id, director.error])
		return {}
	var hero_id := -1
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player:
			hero_id = int(item.uid)
			break
	if mission == 0: check(hero_id >= 0, "%s: the player has a hero" % profile.id)
	if hero_id < 0: return {}
	var hud: Control
	if profile.id == "el2":
		hud = ELSecondAdventureHud.new()
		host.add_child(hud)
		if not (hud as ELSecondAdventureHud).build(state): hud = null
	else:
		hud = ELAdventureHud.new()
		host.add_child(hud)
		if not (hud as ELAdventureHud).build(state): hud = null
	if mission == 0: check(hud != null, "%s: the map panel builds" % profile.id)
	if hud == null: return {}
	return {"profile": profile, "state": state, "director": director, "hero": hero_id, "hud": hud}

## Spell codes of the profile that `accept` takes, in a stable order.
static func spells(profile: ELProfile, count: int, accept: Callable = Callable()) -> Array[String]:
	var codes: Array = profile.table("CombatSpells").keys()
	codes.sort()
	var result: Array[String] = []
	for code: String in codes:
		if not ELSpellInventory.is_spell(profile, code): continue
		if str(profile.table("CombatSpells")[code].get("Rarity", "")) == "Cantrip": continue
		if accept.is_valid() and not accept.call(code): continue
		result.append(code)
		if result.size() >= count: break
	return result

static func press(at: Vector2, double := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = at
	event.global_position = at
	return event

static func release(at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	event.global_position = at
	return event

static func motion(at: Vector2, held := true) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	event.position = at
	event.global_position = at
	return event

## Press at `from`, move in steps to `to` with the button held, release.
static func drag(target: Callable, from: Vector2, to: Vector2) -> void:
	target.call(press(from))
	for step in 4: target.call(motion(from.lerp(to, (step + 1) / 4.0)))
	target.call(release(to))

static func click(target: Callable, at: Vector2, double := false) -> void:
	target.call(press(at, double))
	target.call(release(at))

# --- Second game ------------------------------------------------------------

func _second_inventory(session: Dictionary) -> void:
	var profile: ELProfile = session.profile
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	var codes := spells(profile, 20)
	check(codes.size() == 20, "second game: twenty spells to fill the bag and deck")
	if codes.size() < 20: return
	hero.cards.clear()
	for index in 14: hero.cards.append(codes[index])
	hero.spell_stock.clear()
	for index in range(14, 20): hero.spell_stock[codes[index]] = 1
	var view := ELSecondInventoryView.make(session.hud)
	host.add_child(view)
	view.build(state, session.hero)
	await frames(3)
	var model := view.model
	var input := view.surface_input
	var at := func(zone: String, index: int) -> Vector2: return view.cell_rect(zone, index).get_center()
	var outside := view.design("InventoryScreen").position + Vector2(4, 4)
	check(view.hit(outside)[0] == "", "second game: the inventory has a point outside its lists")

	var card := model.bag[0]
	var bag_size := model.bag.size()
	drag(input, at.call("bag", 0), at.call("deck", 15))
	check(model.deck[15] == card and model.bag.size() == bag_size - 1 and model.carried().is_empty(), "inventory: a bag card dragged onto a blank deck slot goes there")
	card = model.deck[3]
	drag(input, at.call("deck", 3), at.call("bag", 2))
	check(model.deck[3] == "" and model.bag[-1] == card and model.bag.size() == bag_size and model.carried().is_empty(), "inventory: a deck card dragged into the bag returns to it")
	var first := model.deck[0]
	var second := model.deck[1]
	drag(input, at.call("deck", 0), at.call("deck", 1))
	check(model.deck[0] == second and model.deck[1] == first and model.carried().is_empty(), "inventory: two deck cards dragged onto each other swap")
	var deck_before := model.deck.duplicate()
	var bag_before := model.bag.duplicate()
	drag(input, at.call("bag", 1), outside)
	check(model.deck == deck_before and model.bag == bag_before and model.carried().is_empty(), "inventory: a bag card dropped outside the lists goes back")
	drag(input, at.call("bag", 1), at.call("bag", 3))
	check(model.deck == deck_before and model.bag == bag_before and model.carried().is_empty(), "inventory: a bag card dropped on the bag goes back")
	drag(input, at.call("deck", 2), outside)
	check(model.deck == deck_before and model.bag == bag_before and model.carried().is_empty(), "inventory: a deck card dropped outside the lists goes back")
	# A short wobble is still a click: the card stays carried for a second click.
	input.call(press(at.call("bag", 0)))
	input.call(motion(at.call("bag", 0) + Vector2(2, 1)))
	input.call(release(at.call("bag", 0) + Vector2(2, 1)))
	check(model.picked_zone == "bag" and model.picked == 0, "inventory: a click without travel picks the card up")
	card = model.bag[0]
	click(input, at.call("deck", 3))
	check(model.deck[3] == card and model.carried().is_empty(), "inventory: the second click places it")
	card = model.bag[0]
	var blank := model.deck.find("")
	click(input, at.call("bag", 0))
	click(input, at.call("bag", 0), true)
	check(blank >= 0 and model.deck[blank] == card and model.carried().is_empty(), "inventory: a double click moves a bag card to the first blank slot")
	view.queue_free()
	await frames(2)

func _second_shop(session: Dictionary) -> void:
	var profile: ELProfile = session.profile
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	var codes := spells(profile, 24)
	if codes.size() < 24: return
	hero.cards.clear()
	for index in 12: hero.cards.append(codes[index])
	hero.spell_stock.clear()
	hero.spell_stock[codes[12]] = 2
	# A stand-in laboratory: the screen only reads its stock.
	var shop_id := 987654
	state.objects[shop_id] = {"uid": shop_id, "type": "building", "group": "laboratories", "shop_stock": codes.slice(16, 24)}
	var trade := ELSpellShop.new()
	trade.state = state
	trade.hero_id = session.hero
	trade.shop_id = shop_id
	var view := ELSpellShopView.new()
	view.hud = session.hud
	host.add_child(view)
	view.build(trade)
	await frames(3)
	var model := view.model
	var input := view.surface_input
	var at := func(zone: String, index: int) -> Vector2: return view.cell_rect(zone, index).get_center()
	var outside := view.design("SpellShopScreen").position + Vector2(4, 4)
	check(view.hit(outside)[0] == "", "second game: the shop has a point outside its lists")
	var bought := model.shop[0]
	var shop_size := model.shop.size()
	drag(input, at.call("shop", 0), at.call("deck", 14))
	check(model.deck[14] == bought and model.shop.size() == shop_size - 1 and model.carried().is_empty(), "spell shop: a shop card dragged onto a deck slot is bought there")
	var sold := model.deck[2]
	drag(input, at.call("deck", 2), at.call("shop", 1))
	check(model.deck[2].is_empty() and model.shop[-1] == sold and model.carried().is_empty(), "spell shop: a deck card dragged onto the shop is sold")
	var moved := model.bag[0]
	drag(input, at.call("bag", 0), at.call("deck", 2))
	check(model.deck[2] == moved and model.carried().is_empty(), "spell shop: a bag card dragged onto a deck slot goes there")
	var lists := [model.bag.duplicate(), model.deck.duplicate(), model.shop.duplicate()]
	drag(input, at.call("shop", 0), at.call("shop", 2))
	check([model.bag, model.deck, model.shop] == lists and model.carried().is_empty(), "spell shop: a shop card dropped on the shop goes back")
	drag(input, at.call("shop", 0), outside)
	check([model.bag, model.deck, model.shop] == lists and model.carried().is_empty(), "spell shop: a shop card dropped outside the lists goes back")
	bought = model.shop[0]
	var bag_size := model.bag.size()
	click(input, at.call("shop", 0))
	click(input, at.call("shop", 0), true)
	check(model.bag.size() == bag_size + 1 and model.bag[-1] == bought and model.carried().is_empty(), "spell shop: a double click still buys into the bag")
	view.queue_free()
	state.objects.erase(shop_id)
	await frames(2)

func _second_level_up(session: Dictionary) -> void:
	var profile: ELProfile = session.profile
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	hero.skill_points = 2
	hero.skill_offers = []
	ELHeroSkills.prepare(profile, hero)
	var offered: Array = hero.skill_offers.duplicate()
	check(not offered.is_empty(), "second game: the hero has level-up offers")
	if offered.is_empty(): return
	var dialog := ELSecondLevelUpView.new()
	dialog.hud = session.hud
	host.add_child(dialog)
	dialog.build(state, session.hero)
	await frames(3)
	var strip: Control = dialog.offers
	var input: Callable = strip._gui_input
	var rows: Rect2 = dialog.learned.get_rect()
	var target := rows.get_center() - strip.position
	var skills_before: Dictionary = hero.skills.duplicate()
	drag(input, strip.get_item_rect(0).get_center(), Vector2(target.x, -200))
	check(hero.skills == skills_before and int(hero.skill_points) == 2 and dialog.offers.get_selected_items() == PackedInt32Array([0]), "level up: an offer dropped away from the skill rows is only chosen")
	var code := str(offered[0])
	var rank := int(hero.skills.get(code, -1)) + 1
	drag(input, strip.get_item_rect(0).get_center(), target)
	check(int(hero.skills.get(code, -1)) == rank and int(hero.skill_points) == 1, "level up: an offer dragged onto the skill rows is learned")
	dialog.queue_free()
	await frames(2)

## The plain list screens use the viewport's drag and drop.
func _plain_lists(session: Dictionary) -> void:
	var profile: ELProfile = session.profile
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	var allowed := func(code: String) -> bool: return ELSpellInventory.allows(profile, hero, code)
	var codes := spells(profile, 4, allowed)
	if codes.size() < 4:
		print("NOTE: the hero allows too few spells for the plain spellbook part")
		return
	hero.cards.clear()
	hero.cards.append(codes[0])
	hero.cards.append(codes[1])
	hero.spell_stock.clear()
	hero.spell_stock[codes[2]] = 1
	var book := ELSpellbookView.new()
	host.add_child(book)
	book.build(state, session.hero)
	await frames(3)
	await _viewport_drag(book.reserve, book.reserve.get_item_rect(0).get_center(), book.book, book.book.size * 0.5)
	check(hero.cards.size() == 3 and hero.cards[-1] == codes[2] and not hero.spell_stock.has(codes[2]), "plain spellbook: a reserve spell dragged onto the book is equipped")
	await _viewport_drag(book.book, book.book.get_item_rect(0).get_center(), book.reserve, book.reserve.size * 0.5)
	check(hero.cards.size() == 2 and int(hero.spell_stock.get(codes[0], 0)) == 1, "plain spellbook: a book spell dragged onto the reserve is stored")
	await _viewport_drag(book.book, book.book.get_item_rect(0).get_center(), book.heading, book.heading.size * 0.5)
	check(hero.cards.size() == 2 and int(hero.spell_stock.get(codes[0], 0)) == 1, "plain spellbook: a drop away from the lists moves nothing")
	book.queue_free()
	hero.skill_points = 1
	hero.skill_offers = []
	ELHeroSkills.prepare(profile, hero)
	if hero.skill_offers.is_empty(): return
	var skills := ELHeroSkillsView.new()
	host.add_child(skills)
	skills.build(state, session.hero)
	await frames(3)
	var code := str(hero.skill_offers[0])
	var rank := int(hero.skills.get(code, -1)) + 1
	await _viewport_drag(skills.offers, skills.offers.get_item_rect(0).get_center(), skills.learned, skills.learned.size * 0.5)
	check(int(hero.skills.get(code, -1)) == rank and int(hero.skill_points) == 0, "plain skills: an offer dragged onto the learned skills is learned")
	skills.queue_free()
	await frames(2)

## A drag through the viewport from a point of one control to a point of another.
func _viewport_drag(from: Control, from_at: Vector2, to: Control, to_at: Vector2) -> void:
	var start := from.get_global_transform_with_canvas() * from_at
	var end := to.get_global_transform_with_canvas() * to_at
	root.push_input(press(start), true)
	await frames(1)
	var last := start
	for step in 6:
		# The viewport starts a drag from the motions' summed travel.
		var event := motion(start.lerp(end, (step + 1) / 6.0))
		event.relative = event.position - last
		last = event.position
		root.push_input(event, true)
		await frames(1)
	root.push_input(release(end), true)
	await frames(2)

# --- First game ------------------------------------------------------------

func _first_book(session: Dictionary) -> void:
	var profile: ELProfile = session.profile
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	var allowed := func(code: String) -> bool: return ELSpellInventory.allows(profile, hero, code)
	var codes := spells(profile, 2, allowed)
	check(codes.size() == 2, "first game: spells the hero may use")
	if codes.size() < 2: return
	while hero.cards.size() > 4: ELSpellInventory.unequip(profile, hero, hero.cards.size() - 1)
	ELSpellInventory.add(profile, hero, codes[0], 1)
	ELSpellInventory.add(profile, hero, codes[1], 20)
	var view := ELFirstBookView.new()
	host.add_child(view)
	view.build_book(session.director, session.hud, session.hero)
	await frames(3)
	var input: Callable = view.sheet._gui_input
	var book_end := view.book_rect(14).get_center()
	var index := _entry(view, codes[0])
	var size := int(hero.cards.size())
	drag(input, view.reserve_rect(index).get_center(), book_end)
	check(hero.cards.size() == size + 1 and hero.cards[-1] == codes[0] and int(hero.spell_stock.get(codes[0], 0)) == 0, "first game book: a reserve spell dragged onto the book is equipped")
	var card := str(hero.cards[0])
	var stock := int(hero.spell_stock.get(card, 0))
	drag(input, view.book_rect(0).get_center(), view.reserve_rect(0).get_center())
	check(hero.cards.size() == size and int(hero.spell_stock.get(card, 0)) == stock + 1, "first game book: a book spell dragged onto the reserve is stored")
	var cards: Array = hero.cards.duplicate()
	drag(input, view.book_rect(0).get_center(), Vector2(200, 20))
	drag(input, view.reserve_rect(0).get_center(), Vector2(200, 20))
	check(hero.cards == cards and int(hero.spell_stock.get(card, 0)) == stock + 1, "first game book: a drop away from the other side moves nothing")
	while hero.cards.size() < ELSpellInventory.book_size(profile):
		if not state.move_spell(session.hero, codes[1], -1, 0): break
	view.refresh()
	check(hero.cards.size() == ELSpellInventory.book_size(profile), "first game book: the book is filled to %d" % ELSpellInventory.book_size(profile))
	index = _entry(view, codes[1])
	var left := int(hero.spell_stock.get(codes[1], 0))
	drag(input, view.reserve_rect(index).get_center(), book_end)
	check(hero.cards.size() == ELSpellInventory.book_size(profile) and int(hero.spell_stock.get(codes[1], 0)) == left, "first game book: a full book refuses a dragged spell")
	click(input, view.book_rect(0).get_center())
	click(input, view.book_rect(0).get_center(), true)
	check(hero.cards.size() == ELSpellInventory.book_size(profile) - 1, "first game book: a double click still moves a spell")
	view.queue_free()
	await frames(2)

static func _entry(view: ELFirstBookView, card: String) -> int:
	for index in view.entries.size():
		if view.entries[index].card == card: return index
	return -1

func _first_hero_screen(session: Dictionary) -> void:
	var profile: ELProfile = session.profile
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	hero.skill_points = 1
	hero.skill_offers = []
	var view := ELHeroScreenView.new()
	host.add_child(view)
	view.build(session.director, session.hud, [session.hero] as Array[int], false)
	await frames(3)
	var offers: Array = hero.skill_offers
	check(not offers.is_empty(), "first game: the HeroScreen has level-up offers")
	if offers.is_empty(): return
	var input: Callable = view.sheet._gui_input
	var slot := Rect2(362, 233, 50, 50).get_center()
	var skills: Dictionary = hero.skills.duplicate()
	drag(input, slot, Vector2(500, 450))
	check(hero.skills == skills and int(hero.skill_points) == 1, "first game HeroScreen: an offer dropped away from the skills is not learned")
	var code := str(offers[0])
	var rank := int(hero.skills.get(code, -1)) + 1
	drag(input, slot, ELHeroScreenView.SKILLS_AREA.get_center())
	check(int(hero.skills.get(code, -1)) == rank and int(hero.skill_points) == 0, "first game HeroScreen: an offer dragged onto the skills is learned")
	view.queue_free()
	await frames(2)

## The first campaign mission with a laboratory that sells the hero spells.
func _first_shop(profile: ELProfile) -> void:
	var session := {}
	var trade := ELFirstSpellShop.new()
	var opened := false
	for mission in 8:
		session = _session(profile, mission)
		if session.is_empty(): continue
		var state: ELAdventureSession = session.state
		for item: Dictionary in state.objects.values():
			if item.get("group") != "laboratories": continue
			if trade.open(state, session.hero, int(item.uid), true) and not trade.stock.is_empty() and trade.cards.size() >= 2:
				opened = true
				break
		if opened: break
		session.hud.queue_free()
	if not opened:
		print("NOTE: no early mission has a laboratory the hero can use; the laboratory drag is not checked")
		return
	var view := ELFirstSpellShopView.new()
	host.add_child(view)
	view.build_shop(session.director, session.hud, trade)
	await frames(3)
	var input: Callable = view.sheet._gui_input
	var card := trade.stock[0]
	drag(input, view.shop_rect(0).get_center(), view.book_rect(1).get_center())
	check(trade.pending[1] == card and view.carry.is_empty(), "first game laboratory: a shop spell dragged onto a book slot is staged there")
	var pending := trade.pending.duplicate()
	drag(input, view.shop_rect(0).get_center(), Vector2(200, 20))
	check(trade.pending == pending and view.carry.is_empty(), "first game laboratory: a shop spell dropped away from the book is let go")
	click(input, view.shop_rect(0).get_center())
	check(view.carry == card, "first game laboratory: a click still picks a spell up")
	click(input, view.book_rect(0).get_center())
	check(trade.pending[0] == card and view.carry.is_empty(), "first game laboratory: the second click stages it")
	trade.cancel()
	view.queue_free()
	await frames(2)
