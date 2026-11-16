extends SceneTree
## Headless check that a second-game hero may also go without a
## specialisation, as the original's drop-down offers:
## - a hero that knows none is offered nothing (the drop button stays off);
## - once it has learned one, the choices are "NONE" (the table's own row,
##   named in the game's text) and what it learned;
## - choosing "NONE" clears the active specialisation, also through the
##   inventory screen's OK, and its battles start with no specialisation;
## - choosing the learned one again works; one it does not know is refused.
##
##   godot --headless --path game --script ../tools/specialization_choice_check.gd
##
## It needs the second game's files (user://profiles.json); without them it is
## skipped.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
	else:
		var profile := ELProfile.new()
		if not profile.mount("el2", str(paths.el2)):
			print("SKIP: the second game's files could not be mounted")
		else:
			_map(profile)
			if profile.metal_masks != null: profile.metal_masks.stop()
	print("SPECIALIZATION CHOICE: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _map(profile: ELProfile) -> void:
	var row := _chapter(profile, "e2mission11")
	var map := ELAdventureMap.new()
	if row.is_empty() or not map.load_map(profile, "e2mission11"):
		check(false, "e2mission11 loads: %s" % map.error)
		return
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, str(row.get("script", "")), int(str(row.get("player", "1"))), true):
		check(false, "e2mission11 starts: %s" % state.error)
		return
	var hero := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player:
			hero = item
			break
	if hero.is_empty():
		check(false, "the player has a hero")
		state.close()
		return
	var id := int(hero.uid)
	hero.erase("specializations")
	hero.specialization = "NONE"
	check(state.specialization_choices(hero).is_empty(), "a hero that knows no specialisation is offered none")
	var code := ""
	for candidate: String in profile.table("HeroesSpecs"):
		if candidate != "NONE" and ELSpecs.valid(profile, candidate) and state.specialization_available(hero, candidate):
			code = candidate
			break
	check(not code.is_empty() and state.learn_specialization(id, code), "the hero learns %s" % code)
	var choices := state.specialization_choices(hero)
	check(choices.size() == 2 and choices[0] == "NONE" and choices[1] == code, "the choices are none and the learned one: %s" % [choices])
	check(profile.text(str(profile.table("HeroesSpecs").get("NONE", {}).get("Name", ""))).length() > 0, "the table names the empty choice")
	check(state.choose_specialization(id, code) and str(hero.specialization) == code, "choosing the learned one makes it active")
	check(state.choose_specialization(id, "NONE") and str(hero.specialization) == "NONE", "choosing none clears it")
	check(not state.specializations(hero).has("NONE") and state.specializations(hero).has(code), "the learned list keeps the learned one and never lists none")
	var other := ""
	for candidate: String in profile.table("HeroesSpecs"):
		if candidate != "NONE" and candidate != code:
			other = candidate
			break
	check(not state.choose_specialization(id, other), "a specialisation it does not know is refused")
	# The inventory screen stages a choice and writes it with OK.
	state.choose_specialization(id, code)
	var screen := ELSecondInventory.new()
	if screen.open(state, id):
		screen.specialization = "NONE"
		var refusal := screen.accept()
		check(refusal.is_empty() and str(hero.specialization) == "NONE", "the inventory screen's OK writes none: %s" % refusal)
	else:
		check(false, "the inventory screen opens")
	# A battle the hero starts carries no specialisation.
	var spec := "(no battle)"
	for item: Dictionary in state.objects.values():
		if int(item.uid) == id or item.get("type") not in ["hero", "monster"] or not item.get("alive", false): continue
		var encounter := ELAdventureEncounter.new()
		if not encounter.prepare(state, id, int(item.uid)) or encounter.battle == null: continue
		for fighter: Dictionary in encounter.battle.heroes:
			if str(fighter.get("shape", "")) == str(hero.get("shape", "")): spec = str(fighter.get("spec", "?"))
		break
	check(spec == "NONE", "the hero's battle starts with no specialisation (got %s)" % spec)
	state.close()

func _chapter(profile: ELProfile, map_id: String) -> Dictionary:
	for campaign_id: String in ["Green", "Red", "Blue", "Black"]:
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, campaign_id): continue
		for scenario: Dictionary in campaign.scenarios:
			if str(scenario.file_name).to_lower() == map_id:
				var row := scenario.duplicate()
				row.campaign = campaign_id
				var progress := ELSecondCampaign.for_chapter(profile, campaign_id, row, campaign.scenarios.find(scenario) + 1)
				if not progress.is_empty(): row[ELSecondCampaign.KEY] = progress
				return row
	return {}
