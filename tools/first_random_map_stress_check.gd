extends SceneTree
## Reproducible compact naval-map stress check; no proprietary game files.
## From the repository root (Godot 4.7):
##   godot --headless --path game --script ../tools/first_random_map_stress_check.gd
## Check the shipped JSON examples instead of the stress matrix:
##   godot --headless --path game --script ../tools/first_random_map_stress_check.gd -- --examples
## Every successful generation includes the generator's terrain-plan,
## footprint, important-site and exact port-only navigation validation.

const Fixture := preload("first_random_map_fixture.gd")
const EXPECTED_MAPS := 144
const EXAMPLES := ["archipelago", "crossroads", "frontier", "inland_sea", "lake_country", "peninsulas", "quick_duel", "rich_conquest", "ring", "river_delta", "scarcity"]
var generated := 0
var failures := 0

func _initialize() -> void:
	var before := Time.get_ticks_msec()
	if "--examples" in OS.get_cmdline_user_args():
		_examples()
		_finish(EXAMPLES.size(), "EXAMPLES", before)
		return
	var profile := Fixture.profile()
	for layout: String in ELFirstRandomMap.LAYOUTS:
		for players in [2, 3, 4]:
			for water: String in ["low", "normal", "high"]:
				for coast: String in ["smooth", "rugged"]:
					var options := ELFirstRandomMap.defaults()
					options.merge({"seed": "compact-%s-%d-%s-%s" % [layout, players, water, coast],
						"size": 64, "players": players, "layout": layout, "naval": true,
						"water": water, "coast": coast, "scenery": 2, "resources": "rich"}, true)
					_generate(profile, options)
		print("COMPACT %s: %d maps completed, %d failures" % [layout, generated, failures])
	_finish(EXPECTED_MAPS, "COMPACT STRESS", before)

func _generate(profile: ELProfile, options: Dictionary) -> bool:
	var generator := ELFirstRandomMap.new()
	var map := generator.generate(profile, options)
	generated += 1
	if map == null:
		failures += 1
		printerr("FAIL: %s: %s" % [JSON.stringify(options, "", true), generator.error])
		return false
	if int(generator.config.version) >= ELFirstRandomMapV2.WILDERNESS_VERSION and generator.config.guards != "none":
		for start: Dictionary in generator.report.starts:
			if start.has("opening_guard") or start.has("opening_lair"): continue
			failures += 1
			printerr("FAIL: %s: player %d has no starter encounter" % [JSON.stringify(options, "", true), start.player])
			return false
	return true

func _examples() -> void:
	var profile := Fixture.profile()
	var folder := ProjectSettings.globalize_path("res://").path_join("../examples/first_random_maps").simplify_path()
	var found := 0
	for filename: String in DirAccess.get_files_at(folder):
		if filename.ends_with(".json"): found += 1
	if found != EXAMPLES.size():
		failures += 1
		printerr("FAIL: expected %d example JSON files, found %d" % [EXAMPLES.size(), found])
	for name: String in EXAMPLES:
		var filename := name + ".json"
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(filename)))
		if parsed is not Dictionary:
			failures += 1
			printerr("FAIL: unreadable or invalid example " + filename)
			continue
		var canonical := ELFirstRandomMap.normalize(parsed)
		# JSON decodes integral numbers as floats; normalize validates their
		# values and converts them to the generator's canonical integer types.
		if canonical.is_empty() or canonical.size() != parsed.size():
			failures += 1
			printerr("FAIL: incomplete or noncanonical example " + filename)
			continue
		if _generate(profile, parsed): print("EXAMPLE %s: PASS" % filename)

func _finish(expected: int, title: String, began: int) -> void:
	# A skipped loop or missing example must never print a successful run.
	if generated != expected:
		failures += 1
		printerr("FAIL: completion guard expected %d maps, generated %d" % [expected, generated])
	print("%s: %d/%d maps, %d failures, %.2f s" % [title, generated, expected, failures, float(Time.get_ticks_msec() - began) / 1000.0])
	quit(0 if failures == 0 and generated == expected else 1)
