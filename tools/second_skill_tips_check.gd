extends SceneTree
## Headless check of the second game's skill displays (#158):
## - the inventory screen (ELSecondInventoryView): a skill row's tooltip, on a
##   rest of the pointer, gives the skill's name, its rank (T_BASIC,
##   T_ADVANCED, T_EXPERT) and its description (it read a missing column and
##   was empty), and the screen's tooltip frame (ELCombatTooltip) shows it at
##   once on a right click; a right press while a card is carried still puts
##   the card back;
## - the level-up dialog (ELSecondLevelUpView): an offer's tooltip has the
##   rank of the skill it would give, a skill row has its tooltip (the rows
##   had none), and the dialog has the same tooltip frame, shown at once by
##   a right click on either.
##
##   godot --headless --path game --script ../tools/second_skill_tips_check.gd
##
## Needs Etherlords II (user://profiles.json); skipped without it.

const Drag := preload("res://../tools/item_drag_check.gd")

var failures: Array[String] = []
var drag_check: Object

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: Etherlords II files are not configured")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el2", str(paths.el2)):
		print("SKIP: Etherlords II files could not be mounted")
		quit(0)
		return
	drag_check = Drag.new()
	drag_check.host = Control.new()
	drag_check.host.size = Vector2(1280, 800)
	root.add_child(drag_check.host)
	var session: Dictionary = drag_check._session(profile)
	check(not session.is_empty(), "a second-game chapter starts")
	if not session.is_empty():
		await _inventory(session)
		await _level_up(session)
	print("SECOND SKILL TIPS: %d failure(s)" % failures.size())
	for state: ELAdventureSession in drag_check.sessions: state.close()
	drag_check.host.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)

## The hero's skills: three registered ones at ranks 0, 1 and 2.
static func _give_skills(profile: ELProfile, hero: Dictionary) -> void:
	hero.skills = {}
	for row: Dictionary in profile.table("HeroesSkills").values():
		if hero.skills.size() >= 3 or hero.skills.has(row.Code) or str(row.get("InUse", "True")) != "True": continue
		if not ELHeroSkills.definition(profile, str(row.Code), 2).is_empty(): hero.skills[str(row.Code)] = hero.skills.size()

static func _expected(profile: ELProfile, code: String, rank: int) -> Array[String]:
	var row := ELHeroSkills.definition(profile, code, rank)
	return [profile.text(str(row.Name)), profile.text(["T_BASIC", "T_ADVANCED", "T_EXPERT"][rank]), profile.text(str(row.get("Description", "")))]

static func _right(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event

func _inventory(session: Dictionary) -> void:
	var profile: ELProfile = session.profile
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	_give_skills(profile, hero)
	check(hero.skills.size() == 3, "inventory: the hero has three skills")
	var view := ELSecondInventoryView.make(session.hud)
	drag_check.host.add_child(view)
	view.build(state, session.hero)
	await frames(3)
	var codes: Array = hero.skills.keys()
	for index in codes.size():
		var at: Vector2 = view.design("InvScrSkill%d" % (index + 1)).get_center()
		var tip: String = view.tooltip_at(at)
		var want := _expected(profile, str(codes[index]), int(hero.skills[codes[index]]))
		check(tip == "\n".join(want), "inventory: skill row %d's tooltip has its name, rank and description (%s)" % [index + 1, tip.replace("\n", " / ")])
	var badge_at: Vector2 = Vector2(view.design("InvScrSkillsBounds").position.x + 8, view.design("InvScrSkill1").get_center().y)
	check(view.tooltip_at(badge_at) == "\n".join(_expected(profile, str(codes[0]), int(hero.skills[codes[0]]))), "inventory: the rank badge of a row has the tooltip too")
	var row_at: Vector2 = view.design("InvScrSkill2").get_center()
	check(_frame(view.root_control) and view.surface._get_tooltip(row_at) == view.tooltip_at(row_at), "inventory: the screen's tooltip frame (hover or right click) gets the skill's tooltip from the row")
	# A carried card: the right press puts it back.
	view.surface_input(_left(view.cell_rect("deck", 0).get_center()))
	var carried := not view.model.carried().is_empty()
	view.surface_input(_right(row_at, true))
	view.surface_input(_right(row_at, false))
	check(carried and view.model.carried().is_empty(), "inventory: with a card carried, a right press still puts it back")
	view.queue_free()
	await frames(2)

## The screen's tooltip frame (an ELCombatTooltip under `screen`, with
## Godot's own tooltip hidden): it shows the hovered control's tooltip on a
## rest of the pointer or at once on a right click.
static func _frame(screen: Control) -> bool:
	for child in screen.get_children():
		if child is ELCombatTooltip: return screen.theme != null and screen.theme.get_color("font_color", "TooltipLabel") == Color.TRANSPARENT
	return false

static func _left(at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	event.global_position = at
	return event

func _level_up(session: Dictionary) -> void:
	var profile: ELProfile = session.profile
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	_give_skills(profile, hero)
	hero.skill_points = 1
	hero.skill_offers = []
	ELHeroSkills.prepare(profile, hero)
	var offered: Array = hero.skill_offers.duplicate()
	check(not offered.is_empty(), "level up: the hero has offers")
	if offered.is_empty(): return
	var dialog := ELSecondLevelUpView.new()
	dialog.hud = session.hud
	drag_check.host.add_child(dialog)
	dialog.build(state, session.hero)
	await frames(3)
	var strip: Control = dialog.offers
	var code := str(offered[0])
	var rank := int(hero.skills.get(code, -1)) + 1
	var tip: String = strip._get_tooltip(strip.get_item_rect(0).get_center())
	check(tip == "\n".join(_expected(profile, code, rank)), "level up: an offer's tooltip has the name, the rank it gives and the description (%s)" % tip.replace("\n", " / "))
	var codes: Array = hero.skills.keys()
	var label: Label = dialog.labels["LUSkill1"]
	check(label.tooltip_text == "\n".join(_expected(profile, str(codes[0]), int(hero.skills[codes[0]]))) and label.mouse_filter != Control.MOUSE_FILTER_IGNORE, "level up: a skill row has its tooltip (%s)" % label.tooltip_text.replace("\n", " / "))
	var empty: Label = dialog.labels["LUSkill5"]
	check(empty.tooltip_text.is_empty() and empty.mouse_filter == Control.MOUSE_FILTER_IGNORE, "level up: an empty row has none and lets the pointer through")
	check(_frame(dialog.root_control), "level up: the dialog has the original tooltip frame (hover or right click), as the inventory")
	# The rows' drop area lay over the row names and took the pointer.
	check(dialog.learned.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.mouse_filter == Control.MOUSE_FILTER_PASS and label.get_index() < dialog.learned.get_index(), "level up: the pointer reaches the row names through the rows' drop area")
	dialog.queue_free()
	await frames(2)
