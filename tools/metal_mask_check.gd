extends SceneTree
## Headless check of the figures' metal masks (ELMetalMasks): the compiled
## classifier (native/el_assets.c) gives exactly the GDScript classifier's
## bytes on real skins, masks are worked out on worker threads (none on the
## main thread) and later read back from their kept files instead. Also
## prints both classifiers' time per skin. Pass the game folders, or have
## them in user://profiles.json:
##
##   godot --headless --path game --script ../tools/metal_mask_check.gd -- [--el1=DIR] [--el2=DIR] [--every=N]
##
## --every=N compares every Nth armoured skin only (default: all of them).

const FOLDER := "user://metal_mask_check"

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.trim_prefix("--" + name + "=")
	return fallback

func _run() -> void:
	var saved: Variant = {}
	if FileAccess.file_exists("user://profiles.json"):
		saved = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	if not saved is Dictionary: saved = {}
	var every := maxi(1, int(_arg("every", "1")))
	var native := ClassDB.class_exists(&"ELNativeAssets")
	print("Compiled classifier: %s" % ("present" if native else "absent (GDScript only)"))
	var tested := 0
	for edition: String in ["el1", "el2"]:
		var folder := _arg(edition, String(saved.get(edition, "")))
		if folder.is_empty(): continue
		var profile := ELProfile.new()
		if not profile.mount(edition, folder):
			check(false, "%s mounts: %s" % [edition, profile.error])
			continue
		tested += 1
		var masks := ELMetalMasks.new(edition)
		masks.folder = FOLDER
		var skins := _skins(profile)
		var compared := 0
		var differing := 0
		var native_usec := 0
		var script_usec := 0
		var classified_roles := 0
		var armoured: Array = []
		for skin: Array in skins:
			var job := masks.job_for(profile, skin[0], skin[1], skin[2])
			if job.mod.is_empty() or job.main.is_empty(): continue
			var inputs := ELMetalMasks.inputs(job, ELMetalMasks.read_location(job.mod), ELMetalMasks.read_location(job.main.location),
				ELMetalMasks.read_location(job.second.location) if not job.second.is_empty() else PackedByteArray())
			if inputs.is_empty(): continue
			armoured.append(skin)
			if (armoured.size() - 1) % every != 0: continue
			for role: String in inputs:
				var pixels: PackedByteArray = inputs[role].pixels
				var parts: PackedByteArray = inputs[role].parts
				var started := Time.get_ticks_usec()
				var by_script := ELMetalMasks.classify_script(pixels, parts, ELMetalMasks.SIDE)
				script_usec += Time.get_ticks_usec() - started
				classified_roles += 1
				check(by_script.size() == ELMetalMasks.SIDE * ELMetalMasks.SIDE, "%s %s: GDScript mask has every texel" % [edition, skin[0]])
				if not native: continue
				started = Time.get_ticks_usec()
				var compiled: PackedByteArray = ClassDB.class_call_static(&"ELNativeAssets", &"metal_mask", pixels, parts, ELMetalMasks.SIDE)
				native_usec += Time.get_ticks_usec() - started
				compared += 1
				if compiled != by_script:
					differing += 1
					var worst := 0
					for i in mini(compiled.size(), by_script.size()): worst = maxi(worst, absi(compiled[i] - by_script[i]))
					check(false, "%s %s (%s): compiled mask differs (%d vs %d bytes, worst %d)" % [edition, skin[0], role, compiled.size(), by_script.size(), worst])
		print("%s: %d skins with metal of %d, %d compared, %d differ; per skin GDScript %.2f ms, compiled %.2f ms" % [
			edition, armoured.size(), skins.size(), compared, differing,
			script_usec / 1000.0 / maxi(classified_roles, 1), native_usec / 1000.0 / maxi(compared, 1)])
		check(not armoured.is_empty(), "%s has armoured figures" % edition)
		# Worker threads, then the kept files.
		var sample := armoured.slice(0, 6)
		var classified := ELMetalMasks.main_thread_classified
		var first := await _ready_all(masks, profile, sample)
		check(first.size() == sample.size(), "%s: masks worked out on worker threads" % edition)
		for found: Dictionary in first: check(not found.is_empty(), "%s: an armoured skin has a mask" % edition)
		check(ELMetalMasks.main_thread_classified == classified, "%s: nothing classified on the main thread" % edition)
		var again := ELMetalMasks.new(edition)
		again.folder = FOLDER
		var second := await _ready_all(again, profile, sample)
		for i in mini(first.size(), second.size()):
			for role: String in first[i]:
				var a: Image = (first[i][role] as Texture2D).get_image()
				var b: Image = (second[i].get(role) as Texture2D).get_image() if second[i].has(role) else null
				check(b != null and a.get_data() == b.get_data(), "%s: kept mask reads back the same" % edition)
		masks.stop()
		again.stop()
	check(tested > 0, "at least one edition's folder is given")
	_remove(ProjectSettings.globalize_path(FOLDER))
	print("Metal mask check: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

## Each hero and creature skin of the edition once: [model, skin, second].
func _skins(profile: ELProfile) -> Array:
	var out := []
	var seen := {}
	for spec: Array in [["HeroTemplates", "Heroes/", "Texture2"], ["CombatCreatures", "Creatures/", "SecTexture"]]:
		var rows: Dictionary = profile.table(spec[0])
		for row: Variant in rows.values():
			if not row is Dictionary or String(row.get("Model", "")).is_empty(): continue
			var skin: String = spec[1] + String(row.get("Texture", "")).replace("\\", "/")
			var second := String(spec[1]) + String(row[spec[2]]).replace("\\", "/") if row.has(spec[2]) else ""
			var at := ELMetalMasks.key(row.Model, skin, second)
			if seen.has(at): continue
			seen[at] = true
			out.append([String(row.Model), skin, second])
	return out

func _ready_all(masks: ELMetalMasks, profile: ELProfile, skins: Array) -> Array:
	var found := []
	for skin: Array in skins:
		var result: Variant = masks.lookup(profile, skin[0], skin[1], skin[2])
		var at := ELMetalMasks.key(skin[0], skin[1], skin[2])
		var deadline := Time.get_ticks_msec() + 20000
		while result == null and Time.get_ticks_msec() < deadline:
			await process_frame
			result = masks.ready_masks(at)
		if result != null: found.append(result)
	return found

func _remove(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for sub: String in dir.get_directories(): _remove(path.path_join(sub))
	for file: String in dir.get_files(): DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
