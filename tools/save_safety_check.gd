extends SceneTree
## Headless check that saves and settings survive a failed write, and that the
## two games keep separate duel quick saves:
## - a write cut short (ELSafeFile.test_write_limit stands in for a full disk
##   or a quota) leaves the previous duel, autochess, campaign and settings
##   file unchanged, and the writer reports the failure;
## - no temporary file is left behind;
## - each edition has its own duel quick save; the old shared file moves once
##   to the edition it holds, and is kept when that edition already has one
##   or when it names no edition.
##
##   godot --headless --path game --script ../tools/save_safety_check.gd
##
## Only scratch files under user://save_safety_check are written. The duel and
## autochess parts need the games' files (user://profiles.json); without them
## they are skipped.

const FOLDER := "user://save_safety_check"
const LIMIT := 2048

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	_clear()
	_helper()
	_settings()
	_campaign()
	var profiles := _profiles()
	if profiles.has("el1") or profiles.has("el2"): _duel(profiles.get("el2", profiles.get("el1")))
	else: print("SKIP: duel save (no game files)")
	if profiles.has("el2"): _autochess(profiles.el2)
	else: print("SKIP: autochess save (no second game files)")
	_quick_saves(profiles)
	ELSafeFile.test_write_limit = -1
	_clear()
	DirAccess.remove_absolute(FOLDER)
	print("SAVE SAFETY: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _clear() -> void:
	for file in DirAccess.get_files_at(FOLDER): DirAccess.remove_absolute(FOLDER.path_join(file))

func _leftovers() -> Array:
	return Array(DirAccess.get_files_at(FOLDER)).filter(func(name: String): return name.ends_with(".tmp"))

func _profiles() -> Dictionary:
	var result := {}
	if not FileAccess.file_exists("user://profiles.json"): return result
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	if saved is not Dictionary: return result
	for id: String in ["el1", "el2"]:
		var folder := String(saved.get(id, ""))
		var profile := ELProfile.new()
		if not folder.is_empty() and profile.mount(id, folder): result[id] = profile
	return result

## The previous file is kept byte for byte when `write` (which writes new
## contents to `path`) is cut short.
func _survives(what: String, path: String, write: Callable) -> void:
	ELSafeFile.test_write_limit = -1
	check(write.call(), what + ": a normal write succeeds")
	var before := FileAccess.get_file_as_bytes(path)
	check(JSON.parse_string(before.get_string_from_utf8()) != null, what + ": the written file is valid JSON")
	ELSafeFile.test_write_limit = LIMIT if before.size() > LIMIT else maxi(before.size() / 2, 1)
	var reported: bool = write.call()
	ELSafeFile.test_write_limit = -1
	check(not reported, what + ": a write cut short is reported as failed")
	check(FileAccess.get_file_as_bytes(path) == before, what + ": the previous file is unchanged after a failed write")
	check(_leftovers().is_empty(), what + ": no temporary file is left behind")

func _helper() -> void:
	var path := FOLDER.path_join("plain.json")
	var round := [0]
	_survives("ELSafeFile", path, func():
		round[0] += 1
		return ELSafeFile.write_text(path, JSON.stringify({"round": round[0], "filler": "x".repeat(5000)})))
	check(not ELSafeFile.write_text(FOLDER.path_join("missing/inside.json"), "{}"), "ELSafeFile: a write into a missing folder fails")

func _settings() -> void:
	var path := FOLDER.path_join("settings.json")
	var settings := ELSettings.new()
	var round := [0]
	_survives("settings", path, func():
		round[0] += 1
		settings.values.music = 0.1 * (round[0] % 10)
		return settings.save_file(path))

func _campaign() -> void:
	var path := FOLDER.path_join("campaign.json")
	var saver := ELAdventureSave.new()
	var round := [0]
	_survives("campaign save", path, func():
		round[0] += 1
		return saver.write_document(path, {"format": ELAdventureSave.FORMAT, "version": 1, "edition": "el2", "round": round[0], "filler": "x".repeat(5000)}))

func _duel(profile: ELProfile) -> void:
	var duel := ELDuel.new()
	check(duel.start(profile, 212), "duel: a battle starts")
	var path := FOLDER.path_join("duel.json")
	var round := [0]
	_survives("duel save", path, func():
		round[0] += 1
		return duel.save_file(path, {"mode": 0, "camera": [round[0], 0.5, 12.0]}))
	check(not duel.error.is_empty(), "duel save: the failure has a message")

func _autochess(profile: ELProfile) -> void:
	var game_match := ELAutochessMatch.new()
	game_match.auto_save = false
	game_match.begin(profile, 77, ELAutochessCharacters.choices(profile)[0])
	var path := FOLDER.path_join("autochess.json")
	var round := [0]
	_survives("autochess save", path, func():
		round[0] += 1
		game_match.run_seed = 77 + round[0]
		# Called by name, so the check also runs against builds whose save() took no path.
		return game_match.call("save", path))

func _document(edition: String) -> String:
	return JSON.stringify({"format": "etherlords-duel", "version": 1, "state": {"profile": edition}, "session": {}})

func _quick_saves(profiles: Dictionary) -> void:
	var first := ELMatchSave.quick_save_path("el1")
	var second := ELMatchSave.quick_save_path("el2")
	check(not first.is_empty() and not second.is_empty() and first != second, "quick save: each edition has its own file")
	check(first != ELMatchSave.LEGACY_QUICK_SAVE and second != ELMatchSave.LEGACY_QUICK_SAVE, "quick save: neither edition writes the old shared file")
	var legacy := FOLDER.path_join("duel-save.json")
	var targets := {"el1": FOLDER.path_join("duel-save-el1.json"), "el2": FOLDER.path_join("duel-save-el2.json")}
	ELSafeFile.write_text(legacy, _document("el2"))
	check(ELMatchSave.migrate_quick_save(legacy, targets) == "el2", "quick save: the shared file moves to the edition it holds")
	check(not FileAccess.file_exists(legacy) and FileAccess.file_exists(targets.el2) and not FileAccess.file_exists(targets.el1), "quick save: only the second game's file exists after the move")
	check(ELMatchSave.migrate_quick_save(legacy, targets) == "", "quick save: the move happens once")
	ELSafeFile.write_text(legacy, _document("el2"))
	ELSafeFile.write_text(targets.el2, _document("el2") + " ")
	check(ELMatchSave.migrate_quick_save(legacy, targets) == "" and FileAccess.file_exists(legacy) and FileAccess.get_file_as_string(targets.el2).ends_with(" "), "quick save: an edition's own save is never replaced by the shared file")
	ELSafeFile.write_text(legacy, "not json")
	check(ELMatchSave.migrate_quick_save(legacy, targets) == "" and FileAccess.file_exists(legacy), "quick save: an unreadable shared file is kept")
	_clear()
	# A duel of each game goes to its own file and leaves the other's alone.
	var saved := {}
	for id: String in profiles:
		var duel := ELDuel.new()
		if not duel.start(profiles[id], 300): continue
		var path: String = targets[id]
		check(duel.save_file(path, {}), "quick save: a %s duel is saved" % id)
		saved[id] = path
	if saved.size() == 2:
		for id: String in saved:
			var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved[id]))
			check(document is Dictionary and document.state.profile == id, "quick save: the %s file still holds the %s duel" % [id, id])
	else: print("SKIP: both editions' duels (needs both games' files)")
