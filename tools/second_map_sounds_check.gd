extends SceneTree
## Headless check of the second game's map sounds (ELFirstMapPresentation in
## its `second` mode):
## - a chapter map gets the presentation, without blazons or building
##   particles of its own;
## - buildings with a sound folder are listed; next to a Beacon its
##   Buildings/Beacon/cycle.wav loops on a placed player, louder near than at
##   the edge of hearing, silent with the effects volume at 0;
## - the terrain in view starts an Ambient/<Colour>/circle.wav loop, and
##   switching ambient sounds off stops it;
## - map figures with a SndAdvDir are walkers; a hero walking near the
##   listener plays Creatures/<SndAdvDir>/steps/sand/<n>.wav at its footfalls.
##
##   godot --headless --path game --script ../tools/second_map_sounds_check.gd
##
## It needs the second game's files (user://profiles.json, as set up by the
## game); without them it is skipped. Settings are never written, and saves
## the map writes are put back as they were.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _map_part()
	print("SECOND MAP SOUNDS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _map_part() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
		return
	var profile := ELProfile.new()
	if not profile.mount("el2", str(paths.el2)):
		print("SKIP: the second game's files could not be mounted")
		return
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Green")
	# The first Green chapter has Beacons (a looping cycle.wav) and shops.
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Green"
	var progress := ELSecondCampaign.for_chapter(profile, "Green", row, 1)
	if not progress.is_empty(): row[ELSecondCampaign.KEY] = progress
	var saves := _backup(ELSaveSlots.folder("el2"))
	var settings := ELSettings.new()
	settings.use_edition("el2")
	settings.values.effects = 0.8
	settings.values.ambient_sounds = true
	settings.values.ambience = 0.55
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	check(built, "a second-game chapter map builds: " + view.error)
	if not built:
		_restore(ELSaveSlots.folder("el2"), saves)
		return
	await frames(5)
	var sounds := view.presentation
	check(sounds != null and sounds.second, "the map has the presentation in its second-game mode")
	if sounds == null:
		_restore(ELSaveSlots.folder("el2"), saves)
		return
	check(sounds.effects == null and sounds.blazons.is_empty() and sounds.spec_effects.is_empty(), "no blazons or building particles of its own")

	# Building sounds.
	var folders := {}
	for uid: int in sounds.sounding: folders[str(sounds.sounding[uid].folder)] = uid
	check(folders.has("Beacon") and folders.has("CreatureShop1") and folders.has("BlackRoot"), "buildings carry their sound folders: %s" % ", ".join(folders.keys()))
	var sfx: ELArchive = profile.archives.sfx
	var unknown: Array = folders.keys().filter(func(folder: String) -> bool:
		return not sfx.has("Buildings/%s/cycle.wav" % folder) and not sfx.has("Buildings/%s/Idle00.wav" % folder))
	check(unknown.is_empty(), "every folder is a building's, not a creature's (bodies have none): %s" % str(unknown))
	if folders.has("Beacon"):
		var entry: Dictionary = sounds.sounding[folders.Beacon]
		_listen(view, entry.position)
		await frames(3)
		var cycle: Variant = entry.cycle
		check(cycle is AudioStreamPlayer and cycle.stream is AudioStreamWAV and cycle.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and cycle.playing,
			"next to a Beacon its cycle.wav loops")
		if cycle is AudioStreamPlayer:
			var near: float = cycle.volume_db
			check(near > -20.0, "at the Beacon it plays near the effects volume (%.1f dB)" % near)
			_listen(view, entry.position + Vector3(20.0, 0, 0))
			await frames(2)
			check(cycle.volume_db < near - 6.0, "20 units away it is quieter (%.1f dB)" % cycle.volume_db)
			check(str(cycle.bus).begins_with("Positional Map"), "it plays on a placed (panned) bus")
			_listen(view, entry.position)
			view.preview_volumes(_values(settings, {"effects": 0.0}))
			await frames(2)
			check(cycle.volume_db <= -70.0, "the effects volume at 0 silences it")
			view.preview_volumes(settings.values)
			await frames(2)
			check(cycle.volume_db > -20.0, "and the saved volume brings it back")
	check(sounds.played.any(func(path: String) -> bool: return path.begins_with("Buildings/")), "a building sound was started: %s" % str(sounds.played))

	# Terrain ambience.
	for i in 4: check(ELFirstMapPresentation.ambient_count(profile, ELFirstMapPresentation.AMBIENT_FOLDERS[i]) > 0, "Ambient/%s has numbered sounds" % ELFirstMapPresentation.AMBIENT_FOLDERS[i])
	var hero := view.state.object(view.state.main_hero)
	var at := ELAdventureScene.world_position(float(hero.x), float(hero.y))
	_listen(view, at)
	await frames(6)
	var percentages := sounds.percentages
	check(Array(percentages).reduce(func(a: int, b: int) -> int: return a + b, 0) > 0, "the view's terrain is counted: %s" % str(percentages))
	var loops: Array = sounds.ambient_loops.values()
	check(not loops.is_empty() and loops.all(func(player: AudioStreamPlayer) -> bool: return player.stream is AudioStreamWAV and player.playing),
		"a terrain loop plays: %s" % ", ".join(sounds.ambient_loops.keys()))
	view.preview_volumes(_values(settings, {"ambient_sounds": false}))
	await frames(2)
	check(sounds.ambient_loops.is_empty(), "ambient sounds off stops the terrain loops")
	view.preview_volumes(settings.values)
	await frames(3)
	check(not sounds.ambient_loops.is_empty(), "and on starts them again")

	# Footsteps.
	var uid := int(hero.uid)
	check(sounds.walkers.has(uid), "the main hero has footsteps")
	var others := 0
	for id: int in sounds.walkers:
		if id != uid: others += 1
	check(others > 0, "other map figures have footsteps too (%d)" % others)
	if sounds.walkers.has(uid):
		var walker: Dictionary = sounds.walkers[uid]
		check(str(walker.folder).ends_with("/steps/sand/") and ELAudio.sound(profile, str(walker.folder) + "1.wav") != null, "its steps are %s<n>.wav and exist" % walker.folder)
		var model: ELModel = view.world.actors[uid]
		var clip := ELAdventureScene.walk_clip(model)
		check(not model.timing.get(clip, {}).get("events", []).is_empty(), "its walk clip %s has footfall frames" % clip)
		var before := sounds.played.size()
		var start := Vector2(float(hero.x), float(hero.y))
		var heard := false
		for step in 120:
			view.world.move_actor(uid, start + Vector2(step * 0.02, 0.0), true, 1.5)
			_listen(view, model.position)
			await process_frame
			for path: String in sounds.played.slice(before):
				if path.begins_with(str(walker.folder)): heard = true
			if heard: break
		check(heard, "walking, the hero's footfalls play its steps")
		view.world.move_actor(uid, start, false)
		await frames(2)
		check(not walker.glide is AudioStreamPlayer, "a hero without walk.wav loops nothing")

	view.queue_free()
	await frames(3)
	_restore(ELSaveSlots.folder("el2"), saves)

func _listen(view: ELAdventureView, at: Vector3) -> void:
	view.following = -1
	view.target = at
	view.presentation.listener = at

func _values(settings: ELSettings, changes: Dictionary) -> Dictionary:
	var values := settings.values.duplicate()
	values.merge(changes, true)
	return values

## Every save file of the edition, to put back afterwards.
func _backup(folder: String) -> Dictionary:
	var kept := {}
	if not DirAccess.dir_exists_absolute(folder): return kept
	for file in DirAccess.get_files_at(folder): kept[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return kept

func _restore(folder: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if kept.has(file):
			if FileAccess.get_file_as_bytes(folder.path_join(file)) != kept[file]:
				var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
				out.store_buffer(kept[file])
		else: DirAccess.remove_absolute(folder.path_join(file))
