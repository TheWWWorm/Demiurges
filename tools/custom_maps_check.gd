extends SceneTree
## Checks Etherlords II custom maps headless: every map script (.scp) found
## is compiled with the Lua 4.0.1 compiler and with the GDScript fallback,
## then each custom map is listed, loaded, started and its opening played
## (dialogue answered OK, two days ended), and the battle scripts its
## creatures name are loaded and initialised. Prints one line per map and a
## summary; exits 1 when anything failed.
##
##   godot --headless --path game --script ../tools/custom_maps_check.gd -- \
##       [--el2=<Etherlords II folder>] [--seconds=60] [<maps folder> ...]
##
## Each maps folder given is read like the remake's maps folder: every
## sub-folder (or its Maps/Custom) is one map folder. Without folders, the
## installation's Maps/Custom and the remake's maps folder are checked.

const FRAME := 1.0 / 15.0

var failures := 0

func _initialize() -> void:
	var folders: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"): folders.append(arg.replace("\\", "/"))
	for folder: String in folders:
		if not DirAccess.dir_exists_absolute(folder):
			printerr("No such folder: " + folder)
			quit(1)
			return
		var any_top := false
		for file: String in DirAccess.get_files_at(folder):
			if file.get_extension().to_lower() in ["smp", "sbm"]: any_top = true
		if any_top: ELCustomMaps.extra_roots.append(folder)
		for sub: String in DirAccess.get_directories_at(folder): ELCustomMaps.extra_roots.append(folder.path_join(sub))
	var profile := _profile()
	if profile == null:
		printerr("Etherlords II is required: pass --el2=<folder>")
		quit(1)
		return
	print("Lua compiler: ", "Lua 4.0.1 (native)" if ELLuaVM.native_compiler else "GDScript only")
	var compiled: Array[String] = folders.duplicate()
	if compiled.is_empty(): compiled.append(profile.root.path_join("Maps"))
	_compile_all(compiled)
	var seconds := float(_arg("seconds", "60"))
	for entry: Dictionary in ELSingleScenario.catalog(profile):
		if entry.get("custom", false): _check_map(profile, entry, seconds)
	print("custom maps check: %d failures" % failures)
	quit(1 if failures > 0 else 0)

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.get_slice("=", 1)
	return fallback

func _profile() -> ELProfile:
	var folder := _arg("el2", "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get("el2", ""))
	if folder.is_empty(): folder = String(ELContentLibrary.steam_folders().get("el2", ""))
	var profile := ELProfile.new()
	if folder.is_empty() or not profile.mount("el2", folder): return null
	return profile

## Compiles every .scp under the folders with both compilers.
func _compile_all(folders: Array[String]) -> void:
	var scripts: Array[String] = []
	for folder: String in folders: _find(folder, scripts, 0)
	var native := ELLuaVM.native_compiler
	var bad := 0
	for path: String in scripts:
		var source := FileAccess.get_file_as_bytes(path)
		var problems: Array[String] = []
		for use_native: bool in ([true, false] if native else [false]):
			ELLuaVM.native_compiler = use_native
			var chunk := ELLuaVM.compile_source(source, path.get_file())
			if chunk.is_empty() or chunk[0] != 27:
				problems.append(("Lua 4.0.1: " if use_native else "GDScript: ") + chunk.get_string_from_utf8())
			elif ELLuaChunk.new().parse(chunk, path.get_file()).is_empty():
				problems.append(("Lua 4.0.1" if use_native else "GDScript") + ": the chunk does not read back")
		ELLuaVM.native_compiler = native
		if not problems.is_empty():
			bad += 1
			print("  SCRIPT ", path, ": ", "; ".join(problems))
	print("scripts: %d compiled, %d failed" % [scripts.size(), bad])
	failures += bad

func _find(folder: String, found: Array[String], depth: int) -> void:
	if depth > 6: return
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() == "scp": found.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder): _find(folder.path_join(sub), found, depth + 1)

func _check_map(profile: ELProfile, entry: Dictionary, seconds: float) -> void:
	var id := str(entry.id)
	var name := id.trim_prefix(ELCustomMaps.FOLDER)
	if not entry.get("playable", true):
		print("  MAP %s: listed; not playable (no scenario file)" % name)
		return
	var map := ELAdventureMap.new()
	if not map.load_map(profile, id):
		_fail_map(name, "load: " + map.error)
		return
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, false):
		_fail_map(name, "start: " + state.error)
		return
	var director := ELAdventureDirector.new()
	if not director.build(state):
		_fail_map(name, "director: " + director.error)
		return
	var battle := _battle_scripts(profile, state)
	var boxes := 0
	var days := 0
	var frames := int(seconds / FRAME)
	var problem := ""
	for frame in frames:
		director.advance(FRAME)
		if not director.error.is_empty() or not state.error.is_empty():
			problem = "script: " + (director.error if not director.error.is_empty() else state.error)
			break
		if not director.dialogue.is_empty():
			boxes += 1
			director.acknowledge("OK")
		if director.encounter != null: director.decline_encounter()
		# Two days end after the opening, at a third and two thirds of the run.
		if frame in [frames / 3, frames * 2 / 3] and director.can_move() and state.outcome.is_empty():
			director.end_day()
			days += 1
	var line := "listed, started, %d s played, %d messages, %d days ended, day %d%s; battle scripts %s" % [int(seconds), boxes, days, state.day,
		(", outcome " + state.outcome) if not state.outcome.is_empty() else "", battle]
	if not problem.is_empty(): _fail_map(name, problem + " (" + line + ")")
	else: print("  MAP %s: %s" % [name, line])
	state.close()

## The battle scripts the map's creatures name: loaded and initialised.
func _battle_scripts(profile: ELProfile, state: ELAdventureSession) -> String:
	var names := {}
	for object: Dictionary in state.objects.values():
		var script_name := str(object.get("battle_script", "")).strip_edges()
		if not script_name.is_empty(): names[script_name] = true
	for variants: Dictionary in state.map.mobs.values():
		for mob: Dictionary in variants.values():
			var script_name := str(mob.attrs.get("Script", "")).strip_edges()
			if not script_name.is_empty(): names[script_name] = true
	var missing: Array[String] = []
	var broken: Array[String] = []
	for script_name: String in names:
		var bytes := profile.script_bytes(script_name)
		if bytes.is_empty():
			missing.append(script_name)
			continue
		var vm := ELLuaVM.new()
		for native: String in ELBattleScripts.NATIVES: vm.bind(native, func(_arguments: Array) -> Array: return [])
		# In a battle the map's variables are the adventure's, as in the game.
		for native: String in ["ExGetVariable", "ExSetVariable", "ExClearVariables"]:
			vm.bind(native, func(arguments: Array) -> Array: return state._native(arguments, native))
		vm.globals["exMe"] = 0.0
		vm.globals["exEnemy"] = 1.0
		if not vm.load_script(bytes, script_name) or (vm.has_function("CHook_Init") and (vm.invoke("CHook_Init") == null or not vm.error.is_empty())):
			broken.append(script_name + " (" + vm.error + ")")
		vm.clear()
	if not broken.is_empty(): failures += 1
	var text := "%d ok" % (names.size() - missing.size() - broken.size())
	# A missing battle script is skipped, as by the original.
	if not missing.is_empty(): text += ", %d missing (%s)" % [missing.size(), ", ".join(missing)]
	if not broken.is_empty(): text += ", %d failed: %s" % [broken.size(), "; ".join(broken)]
	return text

func _fail_map(name: String, message: String) -> void:
	failures += 1
	print("  MAP %s: FAILED %s" % [name, message])
