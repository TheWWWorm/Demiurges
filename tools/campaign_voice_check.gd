extends SceneTree
## Headless check of the campaign screens' voices and card fades:
## - voice lookup: the first game's Briefings\campaign1/2.wav and
##   Briefings\<scenario file>.wav, the second game's MissionVoices\<text
##   key>.mp3 for each campaign's description key and each chapter's briefing
##   key (found in the installed archives);
## - the card fade (ELCardFade): 0x76 until chosen, 10 per step at 60 steps a
##   second up to 0xe6 (and back down), 0x19 brighter under the pointer;
## - the second game's campaign choice: both cards start dim, a click lights
##   the chosen card (and its caption) over a few frames, Left / Right move
##   the choice, Info speaks the description and leaving stops it, the map's
##   Briefing speaks the chapter's briefing;
## - the campaign screens of both games are drawn on the widened frame.
##
##   godot --headless --path game --script ../tools/campaign_voice_check.gd
##
## The parts that read the games' files need user://profiles.json (as set up
## by the game); without them they are skipped. Settings are never written.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_lookup()
	_fade()
	_wide_lists()
	var profiles := _profiles()
	if profiles.has("el1"): _first_voices(profiles.el1)
	else: print("SKIP: no first-game files configured")
	if profiles.has("el2"):
		_second_voices(profiles.el2)
		await _second_screen(profiles.el2)
	else: print("SKIP: no second-game files configured")
	print("CAMPAIGN VOICES: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _profiles() -> Dictionary:
	var result := {}
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if not paths is Dictionary: return result
	for edition: String in ["el1", "el2"]:
		if not paths.has(edition): continue
		var profile := ELProfile.new()
		if profile.mount(edition, str(paths[edition])): result[edition] = profile
	return result

func _lookup() -> void:
	check(ELBriefingVoice.text_file("MT_E2C_RED_DESC") == "MissionVoices/MT_E2C_RED_DESC.mp3", "a second-game text key names its MissionVoices mp3")
	check(ELBriefingVoice.text_file(" ") == "", "no key, no voice")
	check(ELBriefingVoice.campaign_file(ELBriefingVoice.EVIL_CAMPAIGN.to_lower()) == "Briefings/campaign1.wav" and ELBriefingVoice.campaign_file("{other}") == "Briefings/campaign2.wav", "first game: campaign1.wav for Evil, campaign2.wav otherwise")
	check(ELBriefingVoice.mission_file({"file_name": "Maps\\mission161.map"}) == "Briefings/mission161.wav", "first game: the scenario file's wav")

func _fade() -> void:
	var fade := ELCardFade.new()
	check(is_equal_approx(fade.shown(false), 0x76 / 255.0), "a card starts at 0x76")
	check(is_equal_approx(fade.shown(true), (0x76 + 0x19) / 255.0), "under the pointer it is 0x19 brighter at once")
	fade.choose(true)
	fade.advance(1.0 / 60.0)
	check(is_equal_approx(fade.now, 0x76 + 10), "chosen, it rises 10 per step")
	for i in 20: fade.advance(1.0 / 60.0)
	check(is_equal_approx(fade.now, 0xe6) and not fade.moving(), "and stops at 0xe6 (12 steps)")
	check(is_equal_approx(fade.shown(true), 1.0), "the pointer's lift stops at 255")
	fade.choose(false)
	fade.advance(0.1)
	check(is_equal_approx(fade.now, 0xe6 - 60), "released, it falls back at the same pace")
	fade.choose(true, true)
	check(is_equal_approx(fade.now, 0xe6), "a choice kept when the screen opens shows at once")

func _wide_lists() -> void:
	for screen: String in ["campaigns", "legend", "mission", "branch", "blazon"]:
		check(ELFrontMenu.WIDE_SCREENS.el1.has(screen), "first game: %s fills a wide window" % screen)
	for screen: String in ["campaigns", "legend", "map"]:
		check(ELFrontMenu.WIDE_SCREENS.el2.has(screen), "second game: %s fills a wide window" % screen)

func _first_voices(profile: ELProfile) -> void:
	for id: String in ELCampaign.available(profile):
		var data := ELCampaign.new()
		if not data.load_campaign(profile, id): continue
		check(ELBriefingVoice.load_stream(profile, ELBriefingVoice.campaign_file(data.guid)) != null, "first game: %s has its campaign text voice" % id)
		var found := 0
		for row: Dictionary in data.scenarios:
			if ELBriefingVoice.load_stream(profile, ELBriefingVoice.mission_file(row)) != null: found += 1
		check(found == data.scenarios.size(), "first game: every %s chapter has its briefing (%d/%d)" % [id, found, data.scenarios.size()])

func _second_voices(profile: ELProfile) -> void:
	var total := 0
	var found := 0
	var missing: Array[String] = []
	for id: String in ELCampaign.available(profile):
		var data := ELCampaign.new()
		if not data.load_campaign(profile, id): continue
		var path := ELBriefingVoice.text_file(data.description_key)
		check(path == "MissionVoices/MT_E2C_%s_DESC.mp3" % id.to_upper(), "second game: %s description key %s" % [id, data.description_key])
		check(ELBriefingVoice.load_stream(profile, path) != null, "second game: %s description voice is in the archive" % id)
		for row: Dictionary in data.scenarios:
			total += 1
			if ELBriefingVoice.load_stream(profile, ELBriefingVoice.text_file(str(row.get("briefing", "")))) != null: found += 1
			else: missing.append("%s %s" % [id, row.get("briefing", "")])
	print("second game: %d of %d chapter briefings voiced; without a voice: %s" % [found, total, ", ".join(missing)])
	# The shipped archives have no voice for the final campaign's first briefing
	# (MT_E2C_M50_DESC); nothing plays there, as in the original.
	check(found > 0 and missing.all(func(entry: String): return entry.ends_with("MT_E2C_M50_DESC")), "second game: every other chapter briefing key has its voice")
	check(ELBriefingVoice.load_stream(profile, "MissionVoices/NO_SUCH_KEY.mp3") == null, "a missing voice is no stream (nothing plays)")

func _second_screen(profile: ELProfile) -> void:
	var menu := ELFrontMenu.new()
	menu.settings = ELSettings.new()
	menu.settings_path = "user://campaign_voice_check_unused.json"
	root.add_child(menu)
	if not menu.build({"el2": profile}, "el2"):
		check(false, "the second game's front end builds")
		return
	menu.show_screen("campaign_menu")
	menu.show_screen("campaigns")
	await frames(2)
	check(menu.cards.size() == 2, "two campaign cards")
	if menu.cards.size() != 2: return
	var green: ELFrontMenu.CardButton = menu.cards[0]
	var red: ELFrontMenu.CardButton = menu.cards[1]
	var red_id := red.campaign
	check(menu.selected_campaign.is_empty() and is_equal_approx(green.shown(), 0x76 / 255.0) and is_equal_approx(red.shown(), 0x76 / 255.0), "the choice opens with both cards dim")
	check(green.caption != null and is_equal_approx(green.caption.modulate.a, green.shown()), "a caption follows its card")
	var sounds := ELUiSounds.history.size()
	red.pressed.emit()
	check(ELUiSounds.history.size() > sounds and ELUiSounds.history[-1] == "Buttons/swapcampaign.wav", "choosing a card plays swapcampaign.wav")
	check(red.chosen and red.fade.moving() and red.fade.now < 0xe6, "the chosen card fades up, not at once")
	await create_timer(0.5).timeout
	check(is_equal_approx(red.fade.now, 0xe6) and is_equal_approx(green.fade.now, 0x76), "it reaches 0xe6, the other stays dim")
	check(is_equal_approx(red.caption.modulate.a, 0xe6 / 255.0), "its caption is lit with it")
	sounds = ELUiSounds.history.size()
	red.pressed.emit()
	check(ELUiSounds.history.size() == sounds, "choosing the chosen card again is silent")
	check(menu.campaign_key(KEY_LEFT) and menu.selected_campaign == green.campaign, "Left chooses the card to the left")
	check(menu.campaign_key(KEY_LEFT) and menu.selected_campaign == green.campaign, "Left stops at the first card")
	menu.campaign_key(KEY_RIGHT)
	check(menu.selected_campaign == red.campaign, "Right chooses the card to the right")
	var info: BaseButton = menu.buttons.get("SCInfo")
	check(info != null and not info.disabled, "Info is enabled once a card is chosen")
	if info == null: return
	info.pressed.emit()
	await frames(2)
	var expected := ELBriefingVoice.text_file(menu.campaign_data.description_key)
	check(menu.screen == "legend" and menu.briefing.playing_path == expected, "Info speaks the description (%s)" % menu.briefing.playing_path)
	menu.go_back()
	await frames(1)
	check(menu.screen == "campaigns" and menu.briefing.current() == "" and ELBriefingVoice.events[-1].event == "stop", "leaving the description stops its voice")
	check(menu.selected_campaign == red_id and is_equal_approx(menu.cards[1].fade.now, 0xe6), "the choice is kept, its card lit at once")
	check(menu.campaign_key(KEY_ENTER) and menu.screen == "map", "Enter starts the chosen campaign (its map)")
	check(menu._frame_in_art, "the campaign map is drawn on the widened frame")
	var briefing: BaseButton = menu.buttons.get("GMA6Briefing")
	if briefing != null:
		briefing.pressed.emit()
		await frames(2)
		var row: Dictionary = menu._first_scenario()
		check(menu.briefing.playing_path == ELBriefingVoice.text_file(str(row.get("briefing", ""))), "the map's Briefing speaks the chapter briefing (%s)" % menu.briefing.playing_path)
		menu.go_back()
		await frames(1)
		check(menu.screen == "map" and menu.briefing.current() == "", "back on the map the voice stops")
	menu.queue_free()
	await frames(1)
