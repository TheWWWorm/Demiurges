extends SceneTree
## Exercises the real puzzle UI with synthetic profiles. The generator itself
## is covered by puzzle_generator_check.gd; controlled jobs here exercise
## cancellation and launch races without needing a retail installation.
## Run via puzzle_generator_ui_check.py, or from an imported game project.

class ControlledJob:
	extends RefCounted
	var done := false
	var result := {}
	var progress_text := "Checking a fresh challenge…"
	var calls := 0
	var quota := 0
	var time_slice := 0
	var complete_after := 2
	func step(nodes: int, microseconds: int) -> void:
		calls += 1
		quota = nodes
		time_slice = microseconds
		done = calls >= complete_after

class ControlledAdvice:
	extends ControlledJob
	var current := true
	var cancelled := false
	func is_current(_run: ELPuzzles.Run) -> bool:
		return current and not cancelled
	func cancel() -> void:
		cancelled = true
		done = true
		result = {"status": "cancelled"}

class ControlledSession:
	extends RefCounted
	var requests: Array[Dictionary] = []
	var recorded: Array[Dictionary] = []
	var next_job: RefCounted
	func start(profile: ELProfile, difficulty: int) -> RefCounted:
		requests.append({"profile": profile, "difficulty": difficulty})
		return next_job
	func note(definition: Dictionary) -> void:
		recorded.append(definition.duplicate(true))

var checks := 0
var failures: Array[String] = []
var captures := ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="): captures = argument.trim_prefix("--screenshots=")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func frames(count := 5) -> void:
	for i in count: await process_frame

func fixture(edition: String) -> ELProfile:
	var profile := ELProfile.new()
	profile.id = edition
	profile.title = "UI fixture " + edition
	for name: String in ["InterfaceTextures", "Controls", "CutParts", "HeroTemplates", "CombatSceneDB"]:
		profile.tables[name] = {}
	profile.texts = {"STRG": "Strength", "ZAPP": "Zap", "HOPR": "Hopper", "STRT": "Sapling Treant", "KBSH": "Kobold Shaman"}
	return profile

func entry(edition: String, generated := false, difficulty := 3) -> Dictionary:
	var definition := {"id": "ui-collection-%d" % difficulty, "title": "A tactical challenge", "title_ru": "Тактическая задача",
		"category": "A test position", "category_ru": "Тестовая позиция", "level": difficulty, "turns": 2 if difficulty == 5 else 1,
		"briefing": "Find a winning combination.", "briefing_ru": "Найдите выигрышную комбинацию.",
		"hints": ["Consider the order of your actions."], "hints_ru": ["Продумайте порядок действий."],
		"objective": {"type": "win"}, "state": {"profile": edition, "heroes": [
			{"health": 20, "mana": 6, "level": 4, "template": "TestHero", "channels": 0, "turns": 0, "hand": [], "grave": [], "artifacts": []},
			{"health": 10, "mana": 0, "level": 4, "template": "TestOpponent", "channels": 1, "turns": 0, "hand": [], "grave": [], "artifacts": []}], "creatures": {},
			"setup": {"puzzle_fixed_hands": true, "puzzle_fixed_channels": true}}}
	if generated:
		definition.id = "random_v%d_ui" % ELPuzzleGenerator.VERSION
		definition.generated = {"seed": 12345, "difficulty": difficulty,
			"family": ELPuzzleGenerator.family_for_seed(edition, 12345, difficulty),
			"code": ELPuzzleGenerator.code(edition, difficulty, 12345), "version": ELPuzzleGenerator.VERSION}
	return definition

func attempt(profile: ELProfile, definition: Dictionary) -> ELPuzzles.Run:
	var result := ELPuzzles.Run.new()
	result.entry = definition.duplicate(true)
	result.edition = profile.id
	result.index = -1 if definition.has("generated") else 0
	result.allowed = int(definition.turns)
	result.turn = 1
	result.duel = ELDuel.new()
	result.duel.profile = profile
	result.duel.setup = definition.state.setup.duplicate(true)
	result.duel.heroes.assign(definition.state.heroes.duplicate(true))
	return result

func bounds(mode: ELPuzzleMode, label: String) -> void:
	var viewport := root.get_visible_rect()
	check(viewport.encloses(mode._list.get_global_rect()), label + ": dialog fits 800 by 600: " + str(mode._list.get_global_rect()))
	var controls: Array[Control] = [mode._catalog_tab, mode._random_tab]
	if mode._random_selected:
		controls.append_array([mode._random_generate, mode._random_seed, mode._random_level, mode._random_guidance, mode._random_code, mode._random_copy])
	else:
		controls.append_array([mode._search, mode._goal_choice, mode._difficulty_choice, mode._progress_choice, mode._continue, mode._list_scroll])
	for control: Control in controls:
		check(viewport.encloses(control.get_global_rect()), label + ": control visible: " + str(control.name))

func capture(name: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	check(picture != null and picture.save_png(captures.path_join(name + ".png")) == OK, "capture " + name)

func _place_advice(mode: ELPuzzleMode, job: ControlledAdvice) -> void:
	mode._advice_job = job
	mode._advice_state_key = ELPuzzleAdvice.fingerprint(mode.run)
	mode._advice_scroll.show()
	mode._update_advice_button()

func _advice_checks(mode: ELPuzzleMode, profile: ELProfile, language: String) -> void:
	var definition := entry(profile.id, true, 5)
	definition.hints = ["First clue.", "Second clue.", "Third clue."]
	definition.hints_ru = ["Первая подсказка.", "Вторая подсказка.", "Третья подсказка."]
	definition.show_supply = true
	var run := attempt(profile, definition)
	mode.begin(profile, run)
	check(mode._advice_button.visible and not mode._advice_button.disabled and not mode._advice_scroll.visible and run.hints_used == 0, language + ": tactical advice is opt-in with no initial spoiler")
	var facts := ELPuzzleViewFacts.new()
	facts.profile = profile
	facts.puzzle_mode = mode
	facts.duel = run.duel
	check(facts._puzzle_piece_reference(2) == ELRemakeText.t("Puzzle piece #%d", profile) % 2 and facts._puzzle_piece_reference(2) != facts._puzzle_piece_reference(3), language + ": generated piece references are visible and distinguish exact targets")
	check(facts._puzzle_enchantment_reference(11) == ELRemakeText.t("Puzzle enchantment #%d", profile) % 11 and facts._puzzle_enchantment_reference(11) != facts._puzzle_enchantment_reference(12), language + ": generated enchantment references identify individual same-name copies")
	check(facts._creature_damage_facts(6, 2) == ELRemakeText.t("Toughness: %d · Damage taken: %d", profile) % [6, 2] and facts._creature_damage_facts(6, 0).is_empty(), language + ": target inspection preserves factual toughness and retained damage")
	var before := JSON.stringify(run.duel.snapshot())
	var stale := ControlledAdvice.new()
	stale.result = {"status": "proven", "text": "A verified next action."}
	_place_advice(mode, stale)
	mode._process(0.016)
	check(stale.calls == 1 and stale.quota == 32 and stale.time_slice == 6000 and run.hints_used == 0, language + ": tactical analysis yields bounded slices without counting an unfinished request")
	stale.current = false
	mode._process(0.016)
	check(stale.cancelled and mode._advice_job == null and not mode._advice_scroll.visible and run.hints_used == 0, language + ": stale answer is cancelled before display or assistance count")
	var changed := ControlledAdvice.new()
	_place_advice(mode, changed)
	run.duel.changed.emit()
	check(changed.cancelled and changed.calls == 0 and mode._advice_job == null, language + ": a combat change cancels pending advice immediately")
	run.duel.attacker = 1
	run.duel.changed.emit()
	mode.show_tactical_hint()
	check(mode._advice_button.disabled and mode._advice_job == null, language + ": enemy action disables tactical advice and cannot start a job")
	run.duel.attacker = 0
	run.duel.changed.emit()
	var cancelled := ControlledAdvice.new()
	_place_advice(mode, cancelled)
	mode.show_tactical_hint()
	check(cancelled.cancelled and run.hints_used == 0 and not mode._advice_scroll.visible, language + ": Cancel analysis reveals nothing and counts nothing")
	for status: String in ["unknown", "error", "proven", "refuted"]:
		var answer := ControlledAdvice.new()
		answer.complete_after = 1
		var text := ("Проверенный следующий шаг." if language == "ru" else "A verified next action.") if status == "proven" else (("Нет гарантированного продолжения." if language == "ru" else "No guaranteed continuation remains.") if status == "refuted" else ("Анализ не дал определённого вывода." if language == "ru" else "Analysis did not reach a conclusion."))
		answer.result = {"status": status, "text": text, "command": {"kind": "cast", "card": "ZAPP", "target": 1}}
		var count_before := run.hints_used
		_place_advice(mode, answer)
		mode._process(0.016)
		var useful := status in ["proven", "refuted"]
		check(mode._advice_text.text == text and mode._advice_scroll.visible and run.hints_used == count_before + (1 if useful else 0), language + ": " + status + " is displayed with accurate assistance counting")
		mode.show_tactical_hint()
		mode.show_tactical_hint()
		check(mode._advice_scroll.visible and run.hints_used == count_before + (1 if useful else 0), language + ": reopening " + status + " does not reveal or count a second answer")
	check(JSON.stringify(run.duel.snapshot()) == before, language + ": advice never plays its suggested command or changes combat")
	mode.show_hint()
	check(run.hints_used == 3 and run.tactical_hints_used == 2, language + ": recipe hint after live guidance adds its own stage")
	mode.show_hint()
	check(run.hints_used == 4 and run.tactical_hints_used == 2, language + ": advancing recipe hints preserves live assistance count")
	mode.begin(profile, run)
	check(mode._hint_index == 1, language + ": rebuilding the strip restores recipe depth independently of tactical advice")
	mode.show_hint()
	check(run.hints_used == 4, language + ": reopening the same recipe stage does not add assistance")
	run.note_tactical_hint()
	run.note_hint(2)
	check(run.hints_used == 6 and run.tactical_hints_used == 3, language + ": mixed recipe/live hint counting is additive in both orders")
	mode._briefing_button.button_pressed = true
	mode._briefing_button.pressed.emit()
	var geometry := ControlledAdvice.new()
	geometry.complete_after = 1
	geometry.result = {"status": "unknown", "text": ("Предел анализа достигнут; гарантированный исход не установлен.\n" if language == "ru" else "The analysis limit was reached; no guaranteed outcome was established.\n").repeat(8)}
	_place_advice(mode, geometry)
	mode._process(0.016)
	await frames()
	check(root.get_visible_rect().encloses(mode._bar.get_global_rect()) and root.get_visible_rect().encloses(mode._advice_button.get_global_rect()), language + ": expanded briefing, hints and tactical analysis fit 800 by 600")
	check(mode._advice_scroll.size.y <= 90.0 and mode._advice_scroll.get_v_scroll_bar().visible, language + ": long tactical guidance uses a bounded scroll panel")
	await capture("random_puzzle_advice_" + language)
	var restart := ControlledAdvice.new()
	_place_advice(mode, restart)
	mode._restart_puzzle()
	check(restart.cancelled and mode._advice_job == null, language + ": Restart cancels tactical analysis before emitting the retry")
	var browse := ControlledAdvice.new()
	_place_advice(mode, browse)
	mode.open_list(profile)
	check(browse.cancelled and mode._advice_job == null, language + ": browsing puzzles cancels analysis without delayed guidance")
	mode._close_list()
	var leave := ControlledAdvice.new()
	_place_advice(mode, leave)
	mode.close()
	check(leave.cancelled and mode._advice_job == null and not mode._advice_scroll.visible, language + ": leaving the attempt discards tactical advice")
	check(facts._puzzle_piece_reference(2).is_empty() and facts._puzzle_enchantment_reference(11).is_empty(), language + ": exact references disappear outside a generated attempt")
	var authored := attempt(profile, entry(profile.id))
	mode.begin(profile, authored)
	facts.duel = authored.duel
	check(facts._puzzle_piece_reference(2).is_empty() and facts._puzzle_enchantment_reference(11).is_empty() and not mode._advice_button.visible, language + ": authored puzzles keep their original inspection without live advice controls")

func _rules_profile(edition: String) -> ELProfile:
	var tables: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var profile := fixture(edition)
	profile.tables.merge(tables[edition].duplicate(true), true)
	profile.texts = profile.tables.texts.duplicate()
	var levels := {}
	for level in range(1, 21): levels["Level%d" % level] = 0
	profile.tables.CombatManaIncome = {"1": levels}
	profile.tables.CombatSceneDB = {"Green.001": {}}
	profile.tables.HeroTemplates = {}
	for name: String in profile.tables.HeroTemplateSources:
		profile.tables.HeroTemplates[name] = {"BaseHealth": 20, "HealthIncrease": 0}
	return profile

func _real_advice_checks(mode: ELPuzzleMode, language: String) -> void:
	var profile := _rules_profile("el1")
	var definition := ELPuzzleRecipes.build(profile, "rising_floor", 1, 2)
	check(not definition.is_empty(), language + ": real advice fixture restores from combat rules")
	if definition.is_empty(): return
	var descriptions := ELDuel.new()
	descriptions.profile = profile
	var first_piece: Dictionary = definition.state.creatures.values()[0].duplicate(true)
	first_piece.id = 2
	first_piece.owner = 0
	first_piece.resting = false
	first_piece.sick = false
	first_piece.damage = 0
	var second_piece := first_piece.duplicate(true)
	second_piece.id = 3
	second_piece.resting = true
	second_piece.damage = 1
	descriptions.creatures = {2: first_piece, 3: second_piece}
	var first_instruction := ELPuzzleAdvice.describe(descriptions, {"kind": "attack", "id": 2})
	var second_instruction := ELPuzzleAdvice.describe(descriptions, {"kind": "attack", "id": 3})
	check(first_instruction.contains("#2") and second_instruction.contains("#3") and first_instruction.contains(descriptions.card_name(first_piece.card)) and first_instruction != second_instruction, language + ": equal-name advice targets include exact piece numbers, names and distinct current states")
	descriptions.heroes.assign(definition.state.heroes.duplicate(true))
	descriptions.heroes[0].enchantments = [{"id": 11, "card": "ENRG", "used": true}, {"id": 12, "card": "ENRG", "used": false}]
	var first_ability := ELPuzzleAdvice.describe(descriptions, {"kind": "ability", "id": 0, "key": "energize:11", "target": 3})
	var second_ability := ELPuzzleAdvice.describe(descriptions, {"kind": "ability", "id": 0, "key": "energize:12", "target": 3})
	check(first_ability.contains("#11") and second_ability.contains("#12") and first_ability != second_ability and second_ability.contains(descriptions.card_name("ENRG")), language + ": duplicate hero-granted ability sources name the exact enchantment copy")
	descriptions.heroes[0].hand = ["PRFY"]
	var first_dispel := ELPuzzleAdvice.describe(descriptions, {"kind": "cast", "card": "PRFY", "target": 0, "grave": 11})
	var second_dispel := ELPuzzleAdvice.describe(descriptions, {"kind": "cast", "card": "PRFY", "target": 0, "grave": 12})
	check(first_dispel.contains("#11") and second_dispel.contains("#12") and first_dispel != second_dispel and second_dispel.contains(descriptions.card_name("ENRG")), language + ": equal-name dispel choices name their exact enchantment and holder")
	definition.turns = 2
	definition.level = 5
	definition.solution = []
	definition.generated.version = ELPuzzleGenerator.VERSION
	definition.generated.code = ELPuzzleGenerator.code(profile.id, 5, 1)
	definition.generated.difficulty = 5
	definition.state.creatures = {}
	for side in 2:
		var hero: Dictionary = definition.state.heroes[side]
		hero.hand = ["ZAPP"] if side == 0 else []
		hero.hand_slots = [-1] if side == 0 else []
		hero.hand_ids = [1] if side == 0 else []
		hero.drawn = []
		hero.mana = 1 if side == 0 else 0
		hero.channels = 0
	definition.state.heroes[1].health = 1
	var run := ELPuzzles.Run.new()
	var started := run.begin_entry(profile, definition, false, false)
	check(started, language + ": live advice test starts a real independent attempt: " + run.error)
	if not started: return
	# We are already on the last permitted own turn, despite the definition
	# having begun with two. Advice must preserve that original deadline.
	run.duel.heroes[0].turns += 1
	run.watch()
	mode.begin(profile, run)
	var before := JSON.stringify(run.duel.snapshot())
	mode.show_tactical_hint()
	var slices := 0
	while mode._advice_job != null and slices < 1000:
		mode._process(0.016)
		slices += 1
	check(mode._advice_result.get("status") == "proven" and mode._advice_result.get("remaining_own_turns") == 1, language + ": real backend proves a live continuation within the one remaining own turn")
	check(not mode._advice_text.text.is_empty() and run.hints_used == 1 and JSON.stringify(run.duel.snapshot()) == before, language + ": real proven guidance is shown and counted without executing its move")
	check(run.begin_entry(profile, definition, false, false) and run.hints_used == 0 and run.tactical_hints_used == 0, language + ": a fresh attempt resets both assistance counters")
	run.duel.heroes[0].hand.clear()
	run.duel.heroes[0].hand_slots.clear()
	run.duel.heroes[0].hand_ids.clear()
	run.duel.heroes[0].mana = 0
	mode.begin(profile, run)
	mode.show_tactical_hint()
	slices = 0
	while mode._advice_job != null and slices < 1000:
		mode._process(0.016)
		slices += 1
	check(mode._advice_result.get("status") == "refuted" and run.hints_used == 1 and not mode._advice_result.has("command"), language + ": real completed refutation is assistance and never offers a move")

func _run() -> void:
	root.size = Vector2i(800, 600)
	root.content_scale_size = Vector2i.ZERO
	ELPuzzles.remember = false
	ELPuzzles._solved_read = true
	ELPuzzles._mastery_read = true
	ELPuzzles._solved = {}
	ELPuzzles._mastery = {}
	var first := fixture("el1")
	var second := fixture("el2")
	ELPuzzles._lists = {"el1": [entry("el1"), entry("el1", false, 5)], "el2": [entry("el2")]}
	for language: String in ["en", "ru"]:
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		ELRemakeText.use(first)
		var mode := ELPuzzleMode.new()
		var session := ControlledSession.new()
		mode._random_session = session
		mode.games = {"el1": first, "el2": second}
		root.add_child(mode)
		# Explicit frame stepping lets the checks place UI actions between
		# search slices. Geometry still settles through normal scene frames.
		mode.set_process(false)
		var authored: Array[int] = []
		var generated: Array[Dictionary] = []
		mode.play_requested.connect(func(index: int): authored.append(index))
		mode.generated_requested.connect(func(definition: Dictionary): generated.append(definition))
		mode.open_list(first)
		await frames()
		bounds(mode, language + " collection")
		check(mode._catalog.visible and not mode._random_panel.visible, language + ": opens collection")
		mode._difficulty_filter = 5
		mode._difficulty_choice.select(5)
		mode._fill_list()
		check(mode._continue_index == 1 and mode._groups.get_child_count() == 1, language + ": catalog filters imported Master puzzles separately")
		mode._difficulty_filter = 0
		mode._difficulty_choice.select(0)
		mode._fill_list()
		mode._search.text = "tactical"
		mode._search.text_changed.emit("tactical")
		mode._select_puzzle_tab(true)
		await frames()
		bounds(mode, language + " random")
		await capture("random_puzzle_" + language)
		check(mode._random_level.item_count == 4 and mode._random_level.get_selected_id() == 3, language + ": four supported difficulties default to Hard")
		mode._random_level.select(3)
		mode._random_level.item_selected.emit(3)
		check(mode._random_difficulty == 5 and not mode._random_guidance.text.is_empty(), language + ": Master selection updates its planning guidance")
		await frames()
		bounds(mode, language + " Master")
		await capture("random_puzzle_master_" + language)
		mode._random_seed.text = "999999999999999999999"
		mode._start_random()
		check(mode._generator_job == null and not mode._random_status.text.is_empty(), language + ": oversized seed rejected before generation")
		mode._random_seed.text = "ELP5:el1:1:12"
		mode._start_random()
		check(mode._generator_job == null, language + ": unsupported difficulty code rejected")
		for old_version: int in [1, 2, 3, 4]:
			mode._random_seed.text = "ELP%d:el1:3:12345" % old_version
			mode._start_random()
			check(mode._generator_job == null and mode._random_status.text.contains("ELP5"), language + ": older generator version %d clearly requests ELP5 without remapping its puzzle" % old_version)
		mode.games.erase("el2")
		mode._random_seed.text = "ELP5:el2:3:12"
		mode._start_random()
		check(mode._generator_job == null and mode.profile == first, language + ": uninstalled edition does not launch")
		mode.games.el2 = second
		mode._random_seed.text = " ELP5:EL2:5:12345 "
		mode._random_seed.text_changed.emit(mode._random_seed.text)
		mode._start_random()
		check(mode.profile == second and mode._generator_profile == second and mode._generator_seed == 12345, language + ": shared code selects exact edition and seed")
		check(mode._random_difficulty == 5 and mode._random_level.get_selected_id() == 5, language + ": shared code selects Master difficulty")
		check(session.requests.is_empty(), language + ": an explicit code bypasses session variety")
		mode._select_puzzle_tab(false)
		check(mode._generator_job == null and not mode._random_generate.disabled, language + ": collection tab cancels pending job")
		check(mode._search.text == "tactical", language + ": random pane preserves collection search")
		mode.open_list(first)
		mode._select_puzzle_tab(true)
		mode._random_seed.text = "12347"
		mode._start_random()
		check(mode._generator_seed == 12347 and mode._generator_job != null and session.requests.is_empty(), language + ": explicit numeric seed bypasses session variety too")
		mode._cancel_generation()
		mode._random_seed.text = ""
		var rejected := ControlledJob.new()
		rejected.complete_after = 1
		rejected.result = {"entry": {}, "error": "No suitable challenge was found. Try another seed."}
		mode._generator_job = rejected
		mode._generator_profile = first
		mode._set_random_busy(true)
		mode._process(0.016)
		check(mode._generator_job == null and not mode._random_generate.disabled and generated.is_empty() and session.recorded.is_empty(), language + ": failed generation remains usable and does not affect variety history")
		var controlled := ControlledJob.new()
		controlled.result = {"entry": entry("el1", true), "code": ELPuzzleGenerator.code("el1", 3, 12345)}
		mode._generator_job = controlled
		mode._generator_profile = first
		mode._set_random_busy(true)
		mode._process(0.016)
		check(controlled.calls == 1 and controlled.quota == 32 and controlled.time_slice == 6000 and generated.is_empty(), language + ": generation yields between bounded slices")
		mode._close_list()
		mode._process(0.016)
		check(controlled.calls == 1 and mode._generator_job == null and generated.is_empty() and session.recorded.is_empty(), language + ": Back cancels without a delayed launch or history entry")
		mode.open_list(first)
		mode._select_puzzle_tab(true)
		mode._generator_job = controlled
		mode._generator_profile = first
		mode._process(0.016)
		check(generated.size() == 1 and authored.is_empty() and not mode._list.visible, language + ": completion emits a generated entry exactly once")
		check(session.recorded.size() == 1 and session.recorded[0] == generated[0], language + ": accepted challenge is recorded for future session variety")
		mode._process(0.016)
		check(generated.size() == 1, language + ": completed job cannot launch twice")
		var run := attempt(first, generated[0])
		mode.begin(first, run)
		mode._restart_puzzle()
		check(generated.size() == 2 and generated[1] == run.entry and authored.is_empty(), language + ": Restart reuses exact generated snapshot")
		check(session.recorded.size() == 1, language + ": Restart does not add duplicate session history")
		generated[1].state.heroes[0].health = 1
		check(run.entry.state.heroes[0].health == 20, language + ": retry request owns an independent snapshot")
		check(mode._generated_copy.visible and mode._rules_text.text.contains("ELP5:el1:3:12345"), language + ": active challenge exposes reproducible code")
		mode.open_list(second)
		mode._close_list()
		check(mode.profile == first and mode.run == run and mode._bar.visible, language + ": Back from another edition restores active generated challenge")
		run.outcome = "failed"
		run.reason = "turns"
		mode.show_result()
		await frames()
		check(mode._result.visible and mode._next.visible and not mode._next.disabled and mode._next_index == -1, language + ": failed generated puzzle offers a new challenge without an authored index")
		check(root.get_visible_rect().encloses(mode._result.get_global_rect()), language + ": result fits minimum window")
		check(mode._result_code_row.visible and mode._result_code.text == "ELP5:el1:3:12345", language + ": result keeps exact challenge code")
		await capture("random_puzzle_result_" + language)
		session.next_job = ControlledJob.new()
		mode._next.pressed.emit()
		check(mode._generator_job == session.next_job and mode._generator_profile == first and mode._random_difficulty == 3 and mode._random_seed.text.is_empty(), language + ": New challenge keeps edition and difficulty and uses session variety")
		check(session.requests.size() == 1 and session.requests[0].profile == first and session.requests[0].difficulty == 3, language + ": session receives the exact requested edition and tier")
		mode._cancel_generation()
		mode._close_list()
		run.outcome = "solved"
		mode.show_result()
		check(not mode._result_text.text.contains("Solved:"), language + ": generated completion does not present authored collection totals")
		var master := attempt(first, entry("el1", true, 5))
		mode.begin(first, master)
		check(mode._bar_text.text.contains(ELRemakeText.t("Turn %d of %d", first) % [1, 2]) and mode._rules_text.text.contains("ELP5:el1:5:12345"), language + ": Master battle shows its two-turn objective and exact code")
		master.outcome = "failed"
		master.reason = "turns"
		mode.show_result()
		mode._next.pressed.emit()
		check(session.requests.size() == 2 and session.requests[1].difficulty == 5 and mode._random_level.get_selected_id() == 5, language + ": Master New challenge preserves two-turn tier")
		mode._cancel_generation()
		mode._close_list()
		check(session.recorded.size() == 1, language + ": cancelled fresh challenges never alter session history")
		var disclosed := entry("el1", true, 5)
		disclosed.state.heroes[0].hand = ["STRG", "STRG"]
		disclosed.state.heroes[0].grave = ["HOPR", "STRT", "KBSH"]
		disclosed.state.heroes[1].hand = ["ZAPP"]
		var supplies := attempt(first, disclosed)
		check(supplies.supply_text().is_empty(), language + ": enemy hand stays hidden without the explicit puzzle disclosure flag")
		supplies.entry.show_supply = true
		var hand_heading := "Текущая рука противника" if language == "ru" else "Opponent's current hand"
		var own_heading := "Ваша текущая рука" if language == "ru" else "Your current hand"
		var empty_hand := "пуста" if language == "ru" else "empty"
		var supply_text := supplies.supply_text()
		check(supply_text.contains(own_heading + ": Strength, Strength") and supply_text.contains(hand_heading + ": Zap"), language + ": fixed hands disclose both sides including duplicates and the conditional enemy reply")
		check(supply_text.contains("Hopper, Sapling Treant, Kobold Shaman") and supply_text.contains("от старых карт к новым" if language == "ru" else "oldest to newest"), language + ": graveyard timing is visible in explicitly labeled chronological order")
		check(supply_text.contains("Эфир сейчас: 6 · каналы: 0" if language == "ru" else "Current ether: 6 · channels: 0"), language + ": current ether and channel refill are separate visible facts")
		mode.begin(first, supplies)
		mode._briefing_button.button_pressed = true
		mode._briefing_button.pressed.emit()
		await frames()
		check(mode._supply_scroll.visible and mode._supply_text.text == supply_text, language + ": Briefing exposes live supplies without spending a hint")
		check(supplies.hints_used == 0, language + ": factual enemy cards do not count as solution hints")
		supplies.duel.heroes[0].hand.clear()
		supplies.duel.heroes[1].hand.clear()
		supplies.duel.heroes[0].mana = 0
		supplies.duel.changed.emit()
		check(mode._supply_text.text.contains(own_heading + ": " + empty_hand) and mode._supply_text.text.contains(hand_heading + ": " + empty_hand) and not mode._supply_text.text.contains("Zap"), language + ": live supply updates explicitly show both empty hands after cards are spent")
		check(mode._supply_text.text.contains("Эфир сейчас: 0 · каналы: 0" if language == "ru" else "Current ether: 0 · channels: 0"), language + ": current resources refresh after actions")
		for i in 24: supplies.duel.heroes[1].grave.append("STRT")
		supplies.duel.changed.emit()
		await frames()
		check(root.get_visible_rect().encloses(mode._bar.get_global_rect()) and root.get_visible_rect().encloses(mode._supply_scroll.get_global_rect()), language + ": expanded supply briefing fits 800 by 600")
		check(mode._supply_scroll.size.y <= 180.0 and mode._supply_scroll.get_v_scroll_bar().visible, language + ": long factual supply lists use a bounded scroll area")
		await capture("random_puzzle_supplies_" + language)
		await _advice_checks(mode, first, language)
		_real_advice_checks(mode, language)
		mode.begin(first, attempt(first, entry("el1")))
		mode._restart_puzzle()
		check(authored == [0] and not mode._generated_copy.visible and not mode._advice_button.visible, language + ": authored retry and strip remain unchanged")
		mode.close()
		mode.queue_free()
		await frames()
	OS.unset_environment("DEMIURGES_LANGUAGE")
	ELRemakeText.release()
	print("PUZZLE GENERATOR UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
