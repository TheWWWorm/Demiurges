extends "expedition_power_ui_check.gd"
## Focused v15 UI checks with actual run choices and synthetic tables.
## No original assets or player's checkpoints are used.
## godot --headless --path game --script ../tools/expedition_artifact_ui_check.gd

const ARTIFACT_FOLDER := "user://expedition_artifact_ui_check"
const ARTIFACT_NAMES := {
	"MNDP": ["Ether Drop", "Капля Эфира", "Green", 1, "Cantrip"],
	"UNSM": ["Unsummon", "Развоплощение", "Blue", 1, "Rare"],
	"REPR": ["Repair", "Ремонт", "Black", 1, "Common"],
	"PRFY": ["Purify", "Очистка", "Black", 2, "Common"],
	"ENLH": ["Enlightenment", "Просвещение", "Green", 3, "Unique"],
	"ASLT": ["Assault", "Штурм", "Green", 4, "Unique"],
}
var artifact_sections := 0

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	var profile := Fixture.profile_at(ARTIFACT_FOLDER)
	check(profile != null, "Synthetic artifact UI profile is available")
	if profile == null:
		_finish()
		return
	_add_power_metadata(profile)
	for language: String in ["en", "ru"]:
		_add_artifact_metadata(profile, language)
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		ELRemakeText.use(profile)
		check(ELExpeditionArtifacts.available(profile).size() == 6, language + ": all six original artifact recipes are supported")
		var screen := ELExpeditionScreen.new()
		root.add_child(screen)
		screen.build(profile)
		screen.choice_made.connect(func(id: String): captured.append(id))
		await _constructor_checks(screen, profile, language)
		await _artifact_camp_checks(screen, profile, language)
		await _artifact_merchant_checks(screen, profile, language)
		await _artifact_haven_checks(screen, profile, language)
		await _artifact_reliquary_checks(screen, profile, language)
		await _artifact_elite_checks(screen, profile, language)
		await _artifact_legacy_checks(screen, profile, language)
		screen.queue_free()
		await _frames()
		languages_completed += 1
	OS.unset_environment("DEMIURGES_LANGUAGE")
	ELRemakeText.release()
	Fixture.clean(ARTIFACT_FOLDER)
	_finish()

func _add_artifact_metadata(profile: ELProfile, language: String) -> void:
	for code: String in ARTIFACT_NAMES:
		var row: Array = ARTIFACT_NAMES[code]
		var key := "ArtifactFixture" + code
		profile.tables.CombatSpells[code] = {"Class": "Sorcery", "Color": row[2], "Cost": row[3],
			"Rarity": row[4], "Use": "+", "UseIn": "Attack", "Name": key}
		profile.texts[key] = row[int(language == "ru")]
	for rank in 3:
		profile.tables.HeroesSkills["ARTF" + str(rank + 1)] = {"Code": "ARTF", "Level": rank + 1,
			"Name": "ArtifactFixtureSkill", "Description": "ArtifactFixtureSkillRule", "Duel": "True"}
	profile.texts.ArtifactFixtureSkill = "Искусность" if language == "ru" else "Artificer"
	profile.texts.ArtifactFixtureSkillRule = "Общий лимит применений артефактов." if language == "ru" else "Shared artifact use allowance."

func _artifact_button(screen: ELExpeditionScreen, option: Dictionary) -> Button:
	if option.is_empty(): return null
	return screen._journal_panel.find_child("Compare_" + str(option.id).replace(":", "_"), true, false) as Button

func _artifact_confirm(screen: ELExpeditionScreen) -> Button:
	return screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button

func _artifact_event(profile: ELProfile, event_index: int) -> ELExpeditionRun:
	for offset in 80:
		var run := _new(profile, 15000 + offset, 15)
		if run == null: continue
		for chapter in 3:
			if _enter_kind(run, "event", event_index): return run
			if chapter == 2 or not _enter_kind(run, "boss") or not _win(run) or not _settle_room(run): break
	return null

func _artifact_haven(profile: ELProfile) -> ELExpeditionRun:
	var run := _new(profile, 15102, 15)
	for chapter in 2:
		if not _enter_kind(run, "boss") or not _win(run) or not _settle_room(run): return null
	if not _enter_kind(run, "boss") or run.phase != "haven": return null
	return run

func _review_artifact(screen: ELExpeditionScreen, run: ELExpeditionRun, option: Dictionary, label: String) -> Button:
	var button := _artifact_button(screen, option)
	check(button != null and not button.disabled, label + ": enabled artifact choice is visible")
	if button == null or button.disabled: return null
	var before := run.snapshot()
	captured.clear()
	button.pressed.emit()
	await _frames()
	check(captured.is_empty() and run.snapshot() == before, label + ": inspection spends nothing and emits no core action")
	var confirm := _artifact_confirm(screen)
	check(confirm != null and not confirm.disabled and confirm.text.begins_with(screen._change_action(option)), label + ": fixed confirmation uses the exact action verb")
	check(screen._journal.get_node_or_null("ArtifactReview") != null and screen._journal.get_node_or_null("ArtifactChangePreview") != null, label + ": comparison has a distinct artifact and consequence panel")
	var row := ELExpeditionArtifacts.find(run.profile, str(option.field_recipe))
	check(_has_text(screen._journal, str(row.title)) and _has_text(screen._journal, str(row.description)) and _has_text(screen._journal, screen._artifact_rules()), label + ": comparison shows the original effect and shared finite-charge rules")
	check(_has_text(screen._journal, screen._artifact_cast_rules()), label + ": spell traps, Data Attraction and specialization differences are explained before committing")
	check(not _has_text(screen._journal, screen._spell_stats(str(row.card))) and screen._journal.find_child("ReadArtifactSpell_" + str(row.id), true, false) != null, label + ": artifact is inspectable without presenting a spell's printed ether price as its activation cost")
	if confirm != null:
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(confirm.get_global_rect()), label + ": confirmation stays inside the 720p viewport")
	_check_dialogue(screen, label)
	return confirm

func _review_back(screen: ELExpeditionScreen, run: ELExpeditionRun, option: Dictionary, label: String) -> void:
	var before := run.snapshot()
	var back := screen._choice_footer.find_child("ReplacementBack", true, false) as Button
	check(back != null, label + ": comparison has a fixed Back")
	if back != null: back.pressed.emit()
	await _frames(10)
	check(screen._replacement.is_empty() and run.snapshot() == before and captured.is_empty(), label + ": Back cancels without spending or changing offers")
	check(root.gui_get_focus_owner() == _artifact_button(screen, option), label + ": Back restores focus to the inspected artifact offer")

func _constructor_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _artifact_event(profile, 18)
	check(run != null, language + ": a seeded route reaches the Constructor")
	if run == null: return
	run.field_artifact = "mndp"
	run.field_charges = 1
	run.artifact_project = "unsm"
	screen.show_run(run)
	await _frames()
	var selected := {}
	var count := 0
	for option: Dictionary in run.choices():
		if option.get("artifact_action") != "project": continue
		count += 1
		var button := _artifact_button(screen, option)
		check(button != null and not button.disabled and not option.has("card"), language + ": a project has its own review control rather than spell placement")
		check(button != null and _has_text(button.get_parent(), str(option.description)) and _has_text(button.get_parent(), str(option.context)), language + ": project offer shows its effect and completion destination")
		check(option.field_recipe not in [run.field_artifact, run.artifact_project], language + ": project offers exclude the carried and unfinished artifact")
		if selected.is_empty(): selected = option
	check(count == 3 and not _option(run, "constructor_salvage").is_empty(), language + ": three distinct projects compete with salvage")
	if selected.is_empty(): return
	var before := run.snapshot()
	var confirm := await _review_artifact(screen, run, selected, language + ": Constructor review")
	check(_has_text(screen._journal, screen._text("Give up the unfinished %s project.", "Прежняя заготовка «%s» будет потеряна.") % str(run.artifact_project_details().title)) and _has_text(screen._journal, screen._text("Keep %s with its %d remaining charges.", "Собранный артефакт «%s» останется с прежними зарядами: %d.") % [str(run.field_artifact_details().title), 1]), language + ": project substitution loses only the old unfinished project")
	await _review_back(screen, run, selected, language + ": Constructor review")
	confirm = await _review_artifact(screen, run, selected, language + ": Constructor commit")
	captured.clear()
	if confirm != null: confirm.pressed.emit()
	check(captured == [selected.id] and run.choose(selected.id), language + ": only confirmation takes the selected project")
	check(run.phase == "map" and run.artifact_project == selected.field_recipe and run.field_artifact == "mndp" and run.field_charges == 1 and run.gold == int(before.gold), language + ": project acquisition retains the usable artifact and gold")
	screen.show_run(run)
	await _frames()
	var readiness := screen._journal.get_node_or_null("BattleReadiness")
	check(readiness != null and _has_text(readiness, str(run.battle_preview().artifact_line)) and _has_text(readiness, str(run.battle_preview().project_line)) and _has_text(readiness, screen._text("Shared limit: %d/duel", "Общий лимит: %d/бой") % 1), language + ": route readiness distinguishes carried charges, unfinished project, and shared allowance")
	check(_has_text(screen._journal, ELExpeditionContent.outcome(profile, "18:project")), language + ": the outcome packs parts rather than claiming a completed tool")
	var resumed := ELExpeditionRun.new()
	check(resumed.restore_snapshot(profile, JSON.parse_string(JSON.stringify(run.snapshot()))) and resumed.artifact_project == run.artifact_project and resumed.field_charges == 1, language + ": the project and old charges survive a JSON reload")
	await _capture("expedition-v15-constructor-" + language)
	artifact_sections += 1

func _artifact_camp_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 15101, 15)
	check(_enter_kind(run, "rest"), language + ": artifact assembly reaches a camp")
	if run.phase != "rest": return
	run.field_artifact = "mndp"
	run.field_charges = 1
	run.artifact_project = "unsm"
	run.reserve.assign([run.deck.back()])
	screen.show_run(run)
	await _frames()
	var option := _option(run, "complete_project")
	var main := screen._journal.get_node_or_null("CampMainService")
	var offer := _artifact_button(screen, option)
	check(main != null and offer != null and main.get_index() < _journal_index(screen, offer), language + ": assembly is grouped with services that consume camp")
	var before := run.snapshot()
	var confirm := await _review_artifact(screen, run, option, language + ": camp assembly")
	check(_has_text(screen._journal, screen._text("Give up %s and its %d remaining charges. They do not transfer.", "Вы теряете артефакт «%s» и оставшиеся заряды: %d. Заряды не переносятся.") % [str(run.field_artifact_details().title), 1]) and _has_text(screen._journal, screen._text("This is your one camp service. Leave camp after confirming.", "Это ваше единственное занятие на привале. После подтверждения вы продолжите путь.")), language + ": assembly shows lost charges and its camp opportunity cost")
	captured.clear()
	if confirm != null: confirm.pressed.emit()
	check(captured == ["complete_project"] and run.choose("complete_project") and run.phase == "map" and run.artifact_project.is_empty() and run.field_artifact == "unsm" and run.field_charges == 2 and run.gold == int(before.gold), language + ": camp confirmation assembles at full capacity and ends only the visit")
	run.field_charges = 0 # Controlled depleted ownership for presentation checks.
	run.artifact_project = "aslt"
	screen.show_run(run)
	screen._show_deck(true)
	await _frames()
	var carried := screen._journal.get_node_or_null("FieldArtifactDetails")
	var project := screen._journal.get_node_or_null("ArtifactProjectDetails")
	var reserve := screen._journal.get_node_or_null("ReservePanel")
	check(carried != null and _has_text(carried, screen._text("Charges: %d / %d", "Заряды: %d / %d") % [0, 2]) and _has_text(carried, screen._text("Depleted", "Разряжен")), language + ": Deck keeps a depleted artifact visible at zero charges")
	check(project != null and _has_text(project, str(run.artifact_project_details().completion)) and _has_text(project, screen._text("UNFINISHED PROJECT · Cannot be used in battle", "ЗАГОТОВКА · Пока недоступна в бою")), language + ": Deck explains where the unfinished project can be completed")
	check(carried != null and _has_text(carried, screen._artifact_cast_rules()), language + ": Deck retains the spell-trigger warning for carried tools")
	check(reserve != null and carried != null and reserve.get_index() < carried.get_index(), language + ": artifact detail does not displace active-book and reserve preparation")
	for rank in 3:
		run.preset.skills.ARTF = rank
		screen.show_run(run)
		screen._show_deck(true)
		await _frames()
		check(run.artifact_use_limit() == [2, 4, 8][rank] and _has_text(screen._journal, screen._artifact_rules()), language + ": Deck reports the actual Artificer allowance at rank " + str(rank + 1))
	# Controlled terminal presentation; these are not simulated victories.
	for terminal: String in ["won", "lost"]:
		run.phase = terminal
		screen.show_run(run)
		screen._show_deck(true)
		await _frames()
		var terminal_project := screen._journal.get_node_or_null("ArtifactProjectDetails")
		check(terminal_project != null and _has_text(terminal_project, screen._text("Unfinished when the expedition ended.", "Заготовка осталась незавершённой к концу экспедиции.")) and not _has_text(terminal_project, screen._text("Last Haven", "Последнем привале")), language + ": " + terminal + " Deck describes the unfinished project without promising inaccessible assembly")
	screen._show_deck(false)
	var recharge := _new(profile, 15103, 15)
	check(_enter_kind(recharge, "rest"), language + ": depleted tool reaches a recharge camp")
	recharge.field_artifact = "repr"
	recharge.field_charges = 0
	screen.show_run(recharge)
	await _frames()
	option = _option(recharge, "recharge_artifact")
	confirm = await _review_artifact(screen, recharge, option, language + ": camp recharge")
	check(_has_text(screen._journal, screen._text("%s · Charges %d → %d / %d", "%s · Заряды: %d → %d / %d") % [str(recharge.field_artifact_details().title), 0, 1, 2]), language + ": camp recharge previews exactly one charge")
	var gold := recharge.gold
	captured.clear()
	if confirm != null: confirm.pressed.emit()
	check(captured == ["recharge_artifact"] and recharge.choose("recharge_artifact") and recharge.phase == "map" and recharge.field_charges == 1 and recharge.gold == gold, language + ": camp recharge consumes the main action without taking gold")
	artifact_sections += 1

func _artifact_merchant_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 15104, 15)
	check(_enter_kind(run, "shop"), language + ": artifact reaches a merchant")
	if run.phase != "shop": return
	run.field_artifact = "enlh"
	run.field_charges = 0
	run.gold = 0
	screen.show_run(run)
	await _frames()
	var option := _option(run, "recharge_artifact")
	var button := _artifact_button(screen, option)
	check(button != null and button.disabled and _caption(button).contains("20") and _has_text(button.get_parent(), str(option.reason)), language + ": unaffordable recharge stays visible with price and reason")
	captured.clear()
	if button != null: button.pressed.emit()
	check(captured.is_empty() and screen._replacement.is_empty(), language + ": disabled recharge cannot emit or open a review")
	run.gold = 100
	if "merchant_seal" not in run.relics: run.relics.append("merchant_seal")
	screen.show_run(run)
	await _frames()
	option = _option(run, "recharge_artifact")
	check(int(option.cost) == 16, language + ": the offer uses the actual merchant discount")
	var before := run.snapshot()
	var confirm := await _review_artifact(screen, run, option, language + ": merchant recharge")
	check(_has_text(screen._journal, screen._text("Gold %d → %d", "Золото: %d → %d") % [100, 84]) and not screen._merchant_footer.visible, language + ": payment is explicit and the review has no premature merchant exit")
	await _review_back(screen, run, option, language + ": merchant recharge")
	check(run.snapshot() == before and screen._merchant_footer.visible, language + ": cancelling restores the merchant and all stock")
	confirm = await _review_artifact(screen, run, option, language + ": merchant recharge commit")
	captured.clear()
	if confirm != null: confirm.pressed.emit()
	check(captured == ["recharge_artifact"] and run.choose("recharge_artifact") and run.phase == "shop" and run.field_charges == 1 and run.gold == 84 and run._shop_stock == before.shop.stock, language + ": purchase restores one charge at its shown price and keeps stock available")
	screen.show_run(run)
	await _frames()
	option = _option(run, "recharge_artifact")
	button = _artifact_button(screen, option)
	check(button != null and button.disabled and _has_text(button.get_parent(), str(option.reason)) and screen._merchant_leave.visible, language + ": spent recharge is explained while Leave stays available")
	captured.clear()
	if button != null: button.pressed.emit()
	check(captured.is_empty() and run.field_charges == 1 and run.gold == 84, language + ": a repeat click cannot buy a second charge here")
	var resumed := ELExpeditionRun.new()
	check(resumed.restore_snapshot(profile, JSON.parse_string(JSON.stringify(run.snapshot()))) and bool(_option(resumed, "recharge_artifact").disabled) and resumed.field_charges == 1, language + ": reload retains charges and the used merchant service")
	artifact_sections += 1

func _artifact_haven_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _artifact_haven(profile)
	check(run != null, language + ": unfinished project reaches the final Haven")
	if run == null: return
	run.artifact_project = "aslt"
	run.field_artifact = "mndp"
	run.field_charges = 1
	run.gold = 0
	screen.show_run(run)
	await _frames()
	var option := _option(run, "complete_project")
	var button := _artifact_button(screen, option)
	check(button != null and button.disabled and int(option.cost) == 28 and _has_text(button.get_parent(), str(option.reason)), language + ": Haven assembly shows its 28-gold cost when unaffordable")
	var extra := _option(run, "recharge_artifact")
	var extra_button := _artifact_button(screen, extra)
	check(bool(extra.get("disabled", false)) and extra_button != null and _has_text(extra_button.get_parent(), str(extra.get("reason", ""))), language + ": Haven explains why this hero cannot use an extra charge in the only remaining duel")
	run.gold = 100
	if "merchant_seal" not in run.relics: run.relics.append("merchant_seal")
	screen.show_run(run)
	await _frames()
	option = _option(run, "complete_project")
	check(int(option.cost) == 23, language + ": Haven assembly applies current merchant prices")
	var before := run.snapshot()
	var confirm := await _review_artifact(screen, run, option, language + ": Haven assembly")
	check(_has_text(screen._journal, screen._text("Gold %d → %d", "Золото: %d → %d") % [100, 77]), language + ": Haven review shows the exact rounded payment")
	await _review_back(screen, run, option, language + ": Haven assembly")
	check(run.snapshot() == before, language + ": assembly cancellation leaves the project and gold intact")
	confirm = await _review_artifact(screen, run, option, language + ": Haven assembly commit")
	captured.clear()
	if confirm != null: confirm.pressed.emit()
	check(captured == ["complete_project"] and run.choose("complete_project") and run.phase == "haven" and run.field_artifact == "aslt" and run.field_charges == 2 and run.artifact_project.is_empty() and run.gold == 77, language + ": assembly is charged only on commit and preserves final preparations")
	screen.show_run(run)
	await _frames()
	check(screen._merchant_footer.visible and screen._merchant_leave.text == screen._text("Face White Lord", "Бросить вызов Белому Лорду") and _option(run, "complete_project").is_empty(), language + ": final-battle action remains available and completed project is gone")
	artifact_sections += 1

func _artifact_reliquary_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _artifact_event(profile, 3)
	check(run != null, language + ": a seeded route reaches the Recharger")
	if run == null: return
	run.field_artifact = "prfy"
	run.field_charges = 0
	run.health = 6
	screen.show_run(run)
	await _frames()
	var one := _option(run, "recharge_artifact:1")
	var two := _option(run, "recharge_artifact:2")
	var disabled := _artifact_button(screen, two)
	check(int(one.life_cost) == 3 and int(two.life_cost) == 6 and disabled != null and disabled.disabled and _has_text(disabled.get_parent(), str(two.reason)), language + ": one and two charges show distinct life costs and a lethal payment is disabled")
	captured.clear()
	if disabled != null: disabled.pressed.emit()
	check(captured.is_empty(), language + ": disabled blood recharge cannot commit")
	run.health = 10
	screen.show_run(run)
	await _frames()
	two = _option(run, "recharge_artifact:2")
	var before := run.snapshot()
	var confirm := await _review_artifact(screen, run, two, language + ": two-charge Recharger review")
	check(confirm != null and confirm.text.contains(screen._text("%d life", "%d здоровья") % 6) and _has_text(screen._journal, screen._text("Life after confirming: %d → %d", "Здоровье после подтверждения: %d → %d") % [10, 4]), language + ": blood recharge shows six life in both payment and result")
	await _review_back(screen, run, two, language + ": Recharger review")
	check(run.snapshot() == before, language + ": cancelling spends no life or charges")
	confirm = await _review_artifact(screen, run, two, language + ": Recharger commit")
	captured.clear()
	if confirm != null: confirm.pressed.emit()
	check(captured == [two.id] and run.choose(two.id) and run.phase == "map" and run.health == 4 and run.field_charges == 2 and run.gold == int(before.gold), language + ": confirmation buys exactly two charges for six life and ends the visit")
	screen.show_run(run)
	await _frames()
	check(_has_text(screen._journal, ELExpeditionContent.outcome(profile, "3:recharge_artifact")), language + ": Recharger result has its own scene ending")
	artifact_sections += 1

func _artifact_elite_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 15105, 15)
	check(_enter_kind(run, "elite") and run.choose("elite:standard") and _win(run), language + ": an elite victory reaches the competing rewards")
	if run.phase != "relic_reward": return
	run.field_artifact = "mndp"
	run.field_charges = 1
	run.artifact_project = "unsm"
	screen.show_run(run)
	await _frames()
	var option := _v11_option_prefix(run, "claim_artifact:")
	check(not option.is_empty() and not _v11_option_prefix(run, "relic:").is_empty(), language + ": completed artifact is offered alongside relic alternatives")
	if option.is_empty(): return
	var before := run.snapshot()
	var confirm := await _review_artifact(screen, run, option, language + ": elite artifact replacement")
	check(_has_text(screen._journal, screen._text("Keep the unfinished %s project.", "Заготовка «%s» останется у вас.") % str(run.artifact_project_details().title)), language + ": finished reward preserves a different unfinished project")
	captured.clear()
	if confirm != null: confirm.pressed.emit()
	check(captured == [option.id] and run.choose(option.id) and run.phase == "reward" and run.field_artifact == option.field_recipe and run.field_charges == 2 and run.artifact_project == "unsm" and run.relics == before.relics, language + ": elite choice grants only the artifact then proceeds to the usual spell reward")
	screen.show_run(run)
	await _frames()
	check(_v11_option_prefix(run, "claim_artifact:").is_empty() and not _v11_option_prefix(run, "card:").is_empty(), language + ": no extra relic or artifact can be taken after committing")
	artifact_sections += 1

func _artifact_legacy_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 15106, 14)
	check(_enter_kind(run, "rest"), language + ": legacy v14 camp remains reachable")
	screen.show_run(run)
	await _frames()
	check(not run.implements_enabled() and not run.snapshot().has("field_artifact") and run.choices().all(func(option: Dictionary) -> bool: return not option.has("artifact_action")), language + ": v14 keeps its previous save shape and camp choices")
	screen._show_deck(true)
	await _frames()
	check(screen._journal.get_node_or_null("FieldArtifactHeading") == null and screen._journal.find_child("BattleFieldArtifact", true, false) == null, language + ": v14 has no new artifact panel or readiness rows")
	screen._show_deck(false)
	artifact_sections += 1

func _finish() -> void:
	check(languages_completed == 2 and artifact_sections == 14, "Both artifact UI language passes completed every focused section")
	var result := {"checks": checks, "failures": failures, "languages_completed": languages_completed,
		"sections_completed": artifact_sections, "headless": DisplayServer.get_name() == "headless"}
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--report="): continue
		var file := FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(result, "\t") + "\n")
	print("EXPEDITION ARTIFACT UI: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
