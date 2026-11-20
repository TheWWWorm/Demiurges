extends "expedition_ui_check.gd"
## Focused v13 presentation checks; inherits helpers without running the
## older UI suite. No original game installation or real checkpoint is used.
## godot --headless --path game --script ../tools/expedition_power_ui_check.gd

const POWER_FOLDER := "user://expedition_power_ui_check"

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	var profile := Fixture.profile_at(POWER_FOLDER)
	check(profile != null, "Synthetic power UI profile is available")
	if profile == null:
		_finish()
		return
	_add_power_metadata(profile)
	var previous_wiki_profiles := ELWikiScreen.profiles
	ELWikiScreen.profiles = {"el2": profile}
	for language: String in ["en", "ru"]:
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		ELRemakeText.use(profile)
		var screen := ELExpeditionScreen.new()
		root.add_child(screen)
		screen.build(profile)
		screen.choice_made.connect(func(id: String): captured.append(id))
		await _power_reward_checks(screen, profile, language)
		await _power_preparation_checks(screen, profile, language, false)
		await _power_preparation_checks(screen, profile, language, true)
		await _hero_inspection_checks(screen, profile, language)
		await _aspect_readiness_checks(screen, profile, language)
		await _power_copy_checks(screen, profile, language)
		screen.queue_free()
		await _frames()
		languages_completed += 1
	OS.unset_environment("DEMIURGES_LANGUAGE")
	ELWikiScreen.profiles = previous_wiki_profiles
	ELRemakeText.release()
	Fixture.clean(POWER_FOLDER)
	_finish()

func _add_power_metadata(profile: ELProfile) -> void:
	for definition: Dictionary in ELExpeditionAttunements.DEFINITIONS:
		var code := str(definition.get("card", ""))
		if code.is_empty(): continue
		profile.tables.CombatSpells[code] = {"Class": "Enchantment", "Color": "White" if definition.faction == "Colorless" else definition.faction,
			"Cost": 2, "Rarity": "Unique", "Use": "+", "Name": definition.title[0]}
	for rank in 3:
		profile.tables.HeroesSkills["CONC" + str(rank + 1)] = {"Code": "CONC", "Level": rank + 1,
			"Name": "FixtureConcentrationName", "Description": "FixtureConcentrationRule" + str(rank), "Duel": "True"}
		profile.texts["FixtureConcentrationRule" + str(rank)] = "Draw one additional spell every %d own turns." % (4 - rank)
	profile.texts.FixtureConcentrationName = "Concentration"
	profile.texts.FixtureDragonSkinName = "Dragon Skin"
	profile.tables.HeroesSpecs = {"DRSK": {"Name": "FixtureDragonSkinName"}}
	profile.tables.CombatSpells.STSK = {"Class": "Enchantment", "Color": "White", "Cost": 2,
		"Rarity": "Unique", "Use": "+", "Name": "Stone Skin"}

func _power_run(profile: ELProfile, faction: String, seed: int) -> ELExpeditionRun:
	var run := ELExpeditionRun.new()
	if not run.create(profile, "ExpeditionFixture" + faction, seed, 13): return null
	return run

func _power_guardian(profile: ELProfile, faction: String, wanted := "") -> ELExpeditionRun:
	for index in 20:
		var run := _power_run(profile, faction, 1301 + index)
		if run == null or not _enter_kind(run, "boss") or not _win(run): continue
		if run.phase == "keystone_reward" and (wanted.is_empty() or not _option(run, "keystone:" + wanted).is_empty()): return run
	return null

func _power_reward_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _power_guardian(profile, "Red")
	check(run != null, language + ": a v13 guardian victory reaches its power offer")
	if run == null: return
	screen.show_run(run)
	await _frames()
	_check_dialogue(screen, language + ": guardian powers at 720p")
	var selected := {}
	var offered := 0
	for option: Dictionary in run.choices():
		if not option.has("ability"): continue
		offered += 1
		var button := _choice_button(screen, option)
		check(button != null and _has_text(button, str(option.title)), language + ": a power has a distinct learning action")
		if button != null:
			check(_has_text(button.get_parent(), str(option.description)) and _has_text(button.get_parent(), str(option.context)), language + ": effect and conditions are visible beside the learning action")
		if selected.is_empty(): selected = option
	check(offered == 2 and not selected.is_empty(), language + ": guardian offers two combat powers alongside its familiar run reward")
	if selected.is_empty(): return
	captured.clear()
	_choice_button(screen, selected).pressed.emit()
	check(captured == [selected.id] and run.choose(selected.id), language + ": learning a power emits and commits the exact guardian choice")
	check(_settle_room(run) and run.act == 2, language + ": the spell reward follows learning before the next act")
	screen.show_run(run)
	await _frames()
	var readiness := screen._journal.get_node_or_null("BattleReadiness")
	var lines: Array = run.battle_preview().get("ability_lines", [])
	check(readiness != null and lines.size() == 1 and _has_text(readiness, str(lines[0])), language + ": route readiness includes the learned power's actual state")
	_check_map(screen, language + ": power-bearing route")
	var unchanged := run.snapshot()
	screen._show_deck(true)
	await _frames()
	var detail: Dictionary = run.ability_details()[0]
	var tile := screen._journal.get_node_or_null("PowerDetail_" + str(detail.id))
	check(tile != null and _has_text(tile, detail.title) and _has_text(tile, detail.description) and _has_text(tile, detail.context) and _has_text(tile, detail.status), language + ": Deck shows the power's name, exact effect, condition and state")
	check(screen._journal.get_node_or_null("HeroDetails") != null and run.snapshot() == unchanged, language + ": viewing hero skills and powers does not modify the run")
	screen._show_deck(false)
	await _frames()
	await _capture("expedition-v13-powers-" + language)

func _prepared_run(profile: ELProfile, haven: bool) -> ELExpeditionRun:
	var run := _power_guardian(profile, "Black", "power_data_attraction")
	if run == null or not run.choose("keystone:power_data_attraction") or not _settle_room(run): return null
	if not _enter_kind(run, "boss") or not _win(run): return null
	var next := {}
	for option: Dictionary in run.choices():
		if option.has("ability"):
			next = option
			break
	if next.is_empty() or not run.choose(next.id) or not _settle_room(run): return null
	if not _enter_kind(run, "boss" if haven else "rest"): return null
	return run

func _power_preparation_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String, haven: bool) -> void:
	var run := _prepared_run(profile, haven)
	var room := "Haven" if haven else "camp"
	check(run != null, language + ": two earned powers reach a real " + room)
	if run == null: return
	screen.show_run(run)
	await _frames()
	_check_dialogue(screen, language + ": " + room + " preparations")
	var id := "power_data_attraction"
	var toggle := screen._journal.get_node_or_null("PowerToggle_" + id) as Button
	check(toggle != null and not toggle.disabled and _has_text(screen._journal, _option(run, "suppress_power:" + id).context), language + ": a risky power can be set aside without spending the main service")
	if toggle == null: return
	toggle.grab_focus()
	await _frames()
	screen._scroll.scroll_vertical = maxi(0, screen._scroll.scroll_vertical - 24)
	await _frames()
	var old_scroll := screen._scroll.scroll_vertical
	var old_anchor := toggle.get_global_rect().position.y - screen._scroll.get_global_rect().position.y
	var gold := run.gold
	var life := run.health
	var outcome := run.outcome_details()
	var phase := run.phase
	screen._show_deck(true)
	await _frames()
	screen._show_deck(false)
	await _frames(10)
	var focused := root.gui_get_focus_owner()
	check(screen._scroll.scroll_vertical == old_scroll and focused != null and str(focused.name) == "PowerToggle_" + id, language + ": inspecting Deck restores preparation position and focus")
	toggle = screen._journal.get_node_or_null("PowerToggle_" + id) as Button
	captured.clear()
	toggle.pressed.emit()
	check(captured == ["suppress_power:" + id] and run.choose(captured[0]), language + ": setting aside a power emits the precise free action")
	screen.show_run(run)
	await _frames(10)
	toggle = screen._journal.get_node_or_null("PowerToggle_" + id) as Button
	focused = root.gui_get_focus_owner()
	check(toggle != null and focused == toggle and absf(toggle.get_global_rect().position.y - screen._scroll.get_global_rect().position.y - old_anchor) < 3.0, language + ": the changed preparation action keeps its position and keyboard focus")
	check(run.phase == phase and run.gold == gold and run.health == life and run.outcome_details() == outcome and id not in run.active_powers(), language + ": setting aside a power costs no resources, service or result receipt")
	if haven:
		check(screen._merchant_footer.visible and screen._merchant_leave.text == screen._text("Face White Lord", "Бросить вызов Белому Лорду"), language + ": Haven keeps the final-duel action while preparing powers")
		var readiness := screen._journal.get_node_or_null("BattleReadiness")
		check(readiness != null and _has_text(readiness, str(run.battle_preview().ability_lines[0])), language + ": Haven readiness updates the dormant power state")
	else:
		check(not _option(run, "forage").is_empty() and screen._journal.get_node_or_null("CampRemoveChoice") != null, language + ": camp still offers its main actions after a power toggle")
	captured.clear()
	if toggle != null: toggle.pressed.emit()
	check(captured == ["prepare_power:" + id] and run.choose(captured[0]) and id in run.active_powers(), language + ": the same control prepares the power again")
	screen.show_run(run)
	await _frames(10)
	check(run.phase == phase and run.gold == gold and run.health == life, language + ": repeated preparation preserves room and resources")
	await _capture("expedition-v13-" + room.to_lower() + "-" + language)

func _hero_inspection_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _power_guardian(profile, "Blue", "power_concentration")
	var learned := run != null and run.choose("keystone:power_concentration")
	check(learned, language + ": a Kinet hero learns Concentration from a guardian")
	if not learned: return
	run.preset.specialization = "DRSK"
	screen.show_run(run)
	screen._show_deck(true)
	await _frames()
	var hero := run.hero_details()
	var panel := screen._journal.get_node_or_null("HeroDetails")
	var skill := panel.find_child("HeroSkill_CONC", true, false) as LinkButton if panel != null else null
	check(skill != null and skill.text.ends_with("2") and skill.tooltip_text == ELHeroSkills.tooltip(profile, "CONC", int(hero.skills.CONC)), language + ": skill inspection shows the effective prepared rank and original description")
	check(screen._hero_skill_title("PRVD", 0) == screen._text("Resources", "Ресурсы") and screen._hero_skill_title("SUPR", 0) == screen._text("Suppression", "Сглаз"), language + ": unresolved training names fall back to their canonical localized skill names")
	var specialization := panel.find_child("HeroSpecialization", true, false) as Button if panel != null else null
	check(specialization != null and specialization.text.contains("Dragon Skin"), language + ": the current hero's specialization is inspectable")
	# The wiki catalogue requires a mounted-profile marker. This empty
	# archive contains no assets; only the isolated text/table rows above
	# provide its skill and specialization pages.
	var previous_archives := profile.archives.duplicate()
	profile.archives["fixture"] = ELArchive.new()
	if skill != null:
		skill.pressed.emit()
		await _frames()
		check(ELWikiScreen.is_open() and ELWikiScreen.instance.page == "skill-conc", language + ": skill inspection opens the correct original wiki rule")
		if ELWikiScreen.is_open(): ELWikiScreen.instance.close()
		await _frames()
		check(root.gui_get_focus_owner() == skill, language + ": closing the skill wiki restores normal keyboard focus")
	if specialization != null:
		specialization.pressed.emit()
		await _frames()
		check(ELWikiScreen.is_open() and ELWikiScreen.instance.page == "spec-drsk", language + ": specialization inspection opens its own wiki page")
		if ELWikiScreen.is_open(): ELWikiScreen.instance.close()
		await _frames()
	profile.archives = previous_archives
	run.inactive_powers.append("power_concentration")
	screen.show_run(run)
	screen._show_deck(true)
	await _frames()
	check(not run.hero_details().skills.has("CONC") and screen._journal.find_child("HeroSkill_CONC", true, false) == null, language + ": dormant skill powers are excluded from the next-duel hero inspection")
	var power := screen._journal.get_node_or_null("PowerDetail_power_concentration")
	check(power != null and _has_text(power, str(run.ability_details()[0].status)), language + ": the learned power remains visible with its dormant state")

func _aspect_readiness_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _power_run(profile, "Red", 1311)
	check(run != null and _settle_room(run), language + ": the aspect readiness fixture reaches the route")
	if run == null or run.phase != "map": return
	# Presentation-only ownership: this fixture's active book has no Pale target.
	run.keystones.assign(["power_transfer_aspects"])
	var detail: Dictionary = run.ability_details()[0]
	var warning := str(detail.get("readiness", ""))
	var unchanged := run.snapshot()
	screen.show_run(run)
	await _frames()
	var readiness := screen._journal.get_node_or_null("BattleReadiness")
	check(bool(detail.prepared) and not warning.is_empty() and readiness != null and _has_text(readiness, warning), language + ": battle readiness shows the prepared power's missing-target warning")
	var readiness_wraps: bool = readiness != null and readiness.size.x <= screen._scroll.size.x + 1.0
	if readiness != null:
		for line: Node in readiness.get_child(0).get_children():
			if line is Label and line.text.contains(warning):
				readiness_wraps = readiness_wraps and line.autowrap_mode != TextServer.AUTOWRAP_OFF and line.size.x <= readiness.size.x
	check(readiness_wraps and screen._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, language + ": the readiness warning wraps inside the 720p journal")
	screen._show_deck(true)
	await _frames()
	var tile := screen._journal.get_node_or_null("PowerDetail_power_transfer_aspects")
	check(tile != null and _has_text(tile, warning) and _has_text(tile, str(detail.context)) and run.snapshot() == unchanged, language + ": Deck shows the same target warning without changing preparation")
	var deck_wraps: bool = tile != null and tile.size.x <= screen._scroll.size.x + 1.0
	if tile != null:
		for line: Node in tile.get_child(0).get_children():
			if line is Label and line.text.contains(warning):
				deck_wraps = deck_wraps and line.autowrap_mode != TextServer.AUTOWRAP_OFF and line.size.x <= tile.size.x
	check(deck_wraps and screen._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, language + ": the full power context wraps inside the 720p Deck")
	screen._show_deck(false)
	await _frames()

func _power_copy_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1309, 12)
	while run.phase in ["boon", "discipline"]: run.choose(_first_enabled(run).id)
	run.keepsake_artifact = "RingOfHealing"
	screen.show_run(run)
	screen._show_deck(true)
	await _frames()
	check(screen._journal.get_node_or_null("HeroDetails") == null and screen._journal.find_child("PowerDetail_*", true, false) == null, language + ": v12 retains its previous Deck controls")
	check(_has_text(screen._journal, screen._text("Artifact · %s", "Артефакт · %s") % ELMapPickups.artifact_title(profile, run.keepsake_artifact)), language + ": a charged keepsake is called an artifact")
	var tip := screen._guardian_hint({"id": "m54 - White Lord"})
	check(tip.contains("2") and tip.contains(screen._text("physical", "физического")) and tip.contains(ELEncyclopaedia.name(profile, "STSK")), language + ": White Lord scouting names Stone Skin and its exact physical reduction")
	var board := ELExpeditionBoard.new()
	board.profile = profile
	board.russian = language == "ru"
	check(board._stats("ENBR").contains(screen._text("Unique", "Тайное")), language + ": native-art card rarity uses the wiki term")
	board.free()
	run.phase = "won"
	screen.show_run(run)
	await _frames()
	check(_has_text(screen._journal, screen._text("White Lord defeated", "Белый Лорд побеждён")), language + ": the ending reports the actual victory without claiming a canonical conquest")

func _finish() -> void:
	check(languages_completed == 2, "Both power UI language passes reached completion")
	print("EXPEDITION POWER UI: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
