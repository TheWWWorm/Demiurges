extends SceneTree
## The computer players' strength settings (ELAIChoice, "duel_ai" and
## "world_ai"): defaults, migration from the former "smart_ai" and
## "living_world" switches, the dropdowns, and the Easy opponent's budget.
##
##   godot --headless --path game --script ../tools/ai_choice_check.gd

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	var fresh := ELSettings.new()
	check(int(fresh.values.duel_ai) == 2 and int(fresh.values.world_ai) == 1, "defaults: the smarter duel opponent, the smarter map players without the living world")
	for case: Array in [[{"smart_ai": false}, 1, 0], [{"smart_ai": true}, 2, 1], [{"smart_ai": true, "living_world": true}, 2, 2], [{"smart_ai": false, "living_world": true}, 1, 0],
			[{"smart_ai": false, "duel_ai": 0, "world_ai": 2}, 0, 2]]:
		var path := "user://ai_choice_check.json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"version": 6, "shared": case[0]}))
		file.close()
		var loaded := ELSettings.new()
		loaded.load_file(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		check(int(loaded.values.duel_ai) == case[1] and int(loaded.values.world_ai) == case[2], "a file with %s reads as duel_ai %d, world_ai %d (got %d, %d)" % [JSON.stringify(case[0]), case[1], case[2], int(loaded.values.duel_ai), int(loaded.values.world_ai)])
	check(ELSettings._clean("duel_ai", 7, 2) == 2 and ELSettings._clean("world_ai", -1, 1) == 0, "stored levels are kept in range")
	check(ELAIChoice.applies("duel_ai", "el2") and not ELAIChoice.applies("world_ai", "el2") and ELAIChoice.applies("world_ai", "el1"), "the second game offers only the duel opponent")
	var settings := ELSettings.new()
	var pick := ELAIChoice.picker(settings, "world_ai", null)
	check(pick.item_count == ELSettings.WORLD_AI_LEVELS.size() and pick.selected == 1, "the world dropdown lists every level and shows the current one")
	pick.select(2)
	pick.item_selected.emit(2)
	check(int(settings.values.world_ai) == 2, "choosing a level stores it")
	check(ELCombatSearch.EASY_BUDGET < ELCombatSearch.BUDGET and ELCombatSearch.original_budget == ELCombatSearch.BUDGET, "the Easy opponent reads fewer positions; the original reads its own budget")
	pick.free()
	print("AI CHOICE: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
