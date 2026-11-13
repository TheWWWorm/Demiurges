class_name ELCampaignProbe
extends Node
## Debug: "--campaign-probe=MODE" (with "--probe-dir=DIR") drives the front
## end's campaign screens of the launched game for screenshots, then quits.
## The pointer and keys are sent as input events, so hover, clicks and sounds
## run as for a player. Voice starts and stops are printed ("[voice] ...").
## MODE:
## - "cards": the campaign choice; the pointer rests on the first card, then
##   the second card is clicked; frames are saved while the cards fade
##   (cards-fade-NN.png), then Info opens the description and its voice for 3 s.
## - "screens": one frame of each campaign screen (choice, description,
##   first game: campaign info and branch choice; second game: campaign map
##   and its briefing), at the window size, named <screen>.png.
## - "loading": the main menu and its sub-menus (menu-<screen>.png), then the
##   first campaign's first chapter started as from the menu: a frame of its
##   loading screen (loading.png) and the music heard before, during and after
##   the loading ("[probe] music ..."), then the map (loaded.png).
## - "winlose": the mission-end picture (ELWinLoseScreen) of each outcome over
##   the main menu, held at full alpha: winlose-<win|lose>-<colour>.png.
## - "legends": each campaign's description (legend-<campaign>.png); in the
##   second game also the longest chapter briefing followed by every campaign
##   description, on the same panel, at the top and scrolled to the end
##   (briefing-longest[-end].png).
## - "duel": the Duel screen (duel.png), then the preset editor on a built-in
##   preset, one frame per right-panel tab (duel-editor-<tab>.png).
## "--probe-size=WxH" sets a borderless window of that size first.

var view: Node
var mode := ""
var folder := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-dir="): folder = arg.trim_prefix("--probe-dir=")
		# "--probe-size=WxH": a borderless window of that size at the corner.
		elif arg.begins_with("--probe-size="):
			var size := arg.trim_prefix("--probe-size=").split("x")
			if size.size() == 2:
				var window := get_window()
				window.mode = Window.MODE_WINDOWED
				window.borderless = true
				window.position = Vector2i.ZERO
				window.size = Vector2i(int(size[0]), int(size[1]))
	if folder.is_empty(): folder = OS.get_user_data_dir().path_join("campaign_probe")
	DirAccess.make_dir_recursive_absolute(folder)
	ELBriefingVoice.log_events = true
	_run.call_deferred()

func log_line(text: String) -> void:
	print("[probe] %.3f %s" % [Time.get_ticks_msec() / 1000.0, text])

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(folder.path_join(name + ".png"))
	log_line("frame %s %dx%d" % [name, image.get_width(), image.get_height()])

func pointer_at(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)

func move_to(at: Vector2) -> void:
	get_viewport().warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)

func click(control: Control) -> void:
	var at := pointer_at(control)
	move_to(at)
	await get_tree().process_frame
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		button.position = at
		button.global_position = at
		get_viewport().push_input(button, true)
		await get_tree().process_frame

func card_state(menu: ELFrontMenu) -> String:
	var parts: Array[String] = []
	for card: ELFrontMenu.CardButton in menu.cards:
		parts.append("%s=%d%s" % [card.campaign, roundi(card.shown() * 255.0), "*" if card.chosen else ""])
	return " ".join(parts)

func _run() -> void:
	await wait(1.0)
	if not view.call("_show_front_menu"):
		log_line("no front end")
		get_tree().quit(1)
		return
	var menu: ELFrontMenu = view.get("front_menu")
	log_line("edition %s window %s" % [menu.edition, str(get_viewport().get_visible_rect().size)])
	match mode:
		"cards": await _cards(menu)
		"screens": await _screens(menu)
		"loading": await _loading(menu)
		"legends": await _legends(menu)
		"winlose": await _win_lose(menu)
		"duel": await _duel(menu)
		_: log_line("unknown mode " + mode)
	ELBriefingVoice.log_events = false
	log_line("done")
	ELAudio.quiet_quit(get_tree())

func _open_campaigns(menu: ELFrontMenu) -> void:
	menu.show_screen("campaign_menu" if menu.edition == "el2" else "new")
	menu.show_screen("campaigns")
	await wait(0.6)

func _cards(menu: ELFrontMenu) -> void:
	await _open_campaigns(menu)
	if menu.cards.size() < 2:
		log_line("fewer than two cards")
		return
	move_to(Vector2(4, 4))
	await wait(0.2)
	log_line("cards " + card_state(menu))
	await shot("cards-00-open")
	move_to(pointer_at(menu.cards[0]))
	await wait(0.1)
	log_line("hover first: " + card_state(menu))
	await shot("cards-01-hover-first")
	await click(menu.cards[1])
	log_line("clicked second, sound history: " + str(ELUiSounds.history.slice(-1)))
	# The fade: every frame for 0.3 s, kept in memory and saved afterwards
	# (saving takes longer than a frame).
	var images: Array[Image] = []
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 300 and images.size() < 40:
		await RenderingServer.frame_post_draw
		images.append(get_viewport().get_texture().get_image())
		log_line("fade %02d +%d ms: %s" % [images.size() - 1, Time.get_ticks_msec() - started, card_state(menu)])
	for index in images.size():
		images[index].save_png(folder.path_join("cards-fade-%02d.png" % index))
	move_to(Vector2(4, 4))
	await wait(0.1)
	log_line("pointer away: " + card_state(menu))
	await shot("cards-02-chosen")
	var info: Control = menu.buttons.get("SCInfo")
	if info == null: return
	await click(info)
	await wait(0.5)
	log_line("description open, voice: " + menu.briefing.current())
	await shot("cards-03-description")
	await wait(2.5)
	menu.go_back()
	await wait(0.2)
	log_line("back on the choice, voice: '%s', %s" % [menu.briefing.current(), card_state(menu)])
	await shot("cards-04-back")

func _screens(menu: ELFrontMenu) -> void:
	await _open_campaigns(menu)
	menu.select_campaign(menu.cards[0].campaign if not menu.cards.is_empty() else "", true)
	await wait(0.2)
	await shot("campaigns")
	if menu.edition == "el2":
		var info: Control = menu.buttons.get("SCInfo")
		if info != null:
			await click(info)
			await wait(0.5)
			log_line("description voice: " + menu.briefing.current())
			await shot("legend")
			menu.go_back()
			await wait(0.3)
		var start: Control = menu.buttons.get("SCStart")
		if start != null:
			await click(start)
			await wait(1.5)
			await shot("map")
			var briefing: Control = menu.buttons.get("GMA6Briefing")
			if briefing != null:
				await click(briefing)
				await wait(0.5)
				log_line("briefing voice: " + menu.briefing.current())
				await shot("map-briefing")
				await wait(1.5)
				menu.go_back()
				await wait(0.3)
				log_line("back on the map, voice: '%s'" % menu.briefing.current())
	else:
		menu._confirm_campaign()
		await wait(0.5)
		log_line("campaign text voice: " + menu.briefing.current())
		await shot("legend")
		menu.show_screen("mission")
		await wait(1.5)
		log_line("campaign info voice: " + menu.briefing.current())
		await shot("mission")
		menu.show_screen("blazon")
		await wait(0.3)
		await shot("blazon")
		var choices: Array = []
		var data := ELCampaign.new()
		if data.load_campaign(menu.profile, "Good"):
			for row: Dictionary in data.scenarios:
				if str(row.get("file_name", "")).to_lower() in ["mission261", "mission262"]:
					var copy := row.duplicate()
					copy.campaign = "Good"
					choices.append(copy)
		if choices.size() == 2:
			menu.branch_ui.open(choices, 1)
			await wait(0.3)
			await shot("branch")
		menu.show_screen("campaigns")
		await wait(0.2)

## Every campaign's description, one frame each (legend-<campaign>.png), with
## the text box's lines and whether it scrolls.
func _legends(menu: ELFrontMenu) -> void:
	await _open_campaigns(menu)
	var ids: Array[String] = []
	for card: ELFrontMenu.CardButton in menu.cards: ids.append(card.campaign)
	for id: String in ids:
		menu.show_screen("campaigns")
		menu.select_campaign(id, true)
		await wait(0.2)
		if menu.edition == "el2": menu._open_legend("campaigns")
		else: menu._confirm_campaign()
		await wait(0.4)
		var box := menu.text_box
		if box != null:
			log_line("legend %s box %s lines %d content %d scrolls %s" % [id, str(box.get_global_rect()), box.get_line_count(), box.get_content_height(), str(box.get_content_height() > box.size.y)])
		await shot("legend-" + id)
		menu.briefing.stop_voice()
	if menu.edition != "el2": return
	# Second game: every chapter briefing of every campaign on the same panel
	# (as the campaign map's Briefing shows it); the longest is saved.
	var longest := {}
	for id: String in ELCampaign.available(menu.profile):
		var data := ELCampaign.new()
		if not data.load_campaign(menu.profile, id): continue
		for row: Dictionary in data.scenarios:
			var body := menu.text(str(row.get("briefing", "")))
			if body.length() > str(longest.get("body", "")).length(): longest = {"id": "%s-%s" % [id, row.get("file_name", "")], "body": body, "header": menu.text(str(row.get("header", "")))}
	if longest.is_empty(): return
	# A text longer than any shipped one: every campaign description as its own
	# paragraph after the briefing, to show the paragraph gaps and the scroll.
	var paragraphs := PackedStringArray([longest.body])
	for id: String in ELCampaign.available(menu.profile):
		var data := ELCampaign.new()
		if data.load_campaign(menu.profile, id): paragraphs.append(data.description)
	longest.body = "\n\n".join(paragraphs)
	menu._open_legend("campaigns")
	await wait(0.2)
	menu.briefing.stop_voice()
	menu.labels.caption.text = longest.header
	menu.text_box.text = ELFrontMenu._story_text(longest.body)
	await wait(0.2)
	var box := menu.text_box
	log_line("longest briefing %s (%d chars) lines %d content %d scrolls %s" % [longest.id, longest.body.length(), box.get_line_count(), box.get_content_height(), str(box.get_content_height() > box.size.y)])
	await shot("briefing-longest")
	menu.scroll_text(100)
	await wait(0.2)
	await shot("briefing-longest-end")

## The mission-end picture for a win and a loss of a good and an evil colour.
func _win_lose(menu: ELFrontMenu) -> void:
	var layer := CanvasLayer.new()
	# Above the start-up movies and any message box of the launch.
	layer.layer = 100
	add_child(layer)
	for colour: String in ["Green", "Red"]:
		for victory: bool in [true, false]:
			var screen := ELWinLoseScreen.new()
			layer.add_child(screen)
			screen.setup(menu.profile, victory, colour)
			screen.set_process(false)
			screen.alpha = 1.0
			screen.queue_redraw()
			await wait(0.3)
			log_line("winlose %s %s mask %s" % ["win" if victory else "lose", colour, str(screen.mask)])
			await shot("winlose-%s-%s" % ["win" if victory else "lose", colour.to_lower()])
			screen.finish()
			screen.queue_free()
	layer.queue_free()

func music_state(menu: ELFrontMenu) -> String:
	var audio: Node = view.get("battle_audio")
	var battle := "none"
	if is_instance_valid(audio):
		battle = "paused" if audio.paused else "running"
		for player: Node in audio.get_children():
			if player is AudioStreamPlayer and player.playing and not player.stream_paused: battle += " (playing %s)" % player.name
	return "menu '%s' battle %s" % [menu.music_path().get_file(), battle]

func _loading(menu: ELFrontMenu) -> void:
	await wait(0.5)
	await shot("menu-main")
	for target: String in (["single", "campaign_menu"] if menu.edition == "el2" else ["new", "load"]):
		menu.show_screen(target)
		await wait(0.3)
		await shot("menu-" + target)
	await _open_campaigns(menu)
	menu.select_campaign(menu.cards[0].campaign if not menu.cards.is_empty() else "", true)
	await wait(0.3)
	menu._confirm_campaign()
	if menu.edition == "el1": menu.show_screen("mission")
	await wait(1.0)
	if menu._first_scenario().is_empty():
		log_line("no first chapter")
		return
	log_line("music before: " + music_state(menu))
	menu.start_campaign()
	var shown := false
	for frame in 600:
		await get_tree().process_frame
		var cover: Node = view.get_node_or_null("ChapterLoading")
		if cover != null and not shown:
			shown = true
			log_line("music during the loading: " + music_state(menu))
			await shot("loading")
		elif cover == null and view.get("campaign_view") != null:
			break
	await wait(2.0)
	var map_audio: Variant = view.get("campaign_view").get("audio")
	log_line("music after: " + music_state(menu) + ", map theme '%s' playing %s" % [map_audio.theme if map_audio != null else "", str(map_audio != null and map_audio.background != null and map_audio.background.playing)])
	await shot("loaded")

## The Duel screen and the preset editor on each of its tabs.
func _duel(menu: ELFrontMenu) -> void:
	menu.show_screen("duel")
	await wait(0.5)
	await shot("duel")
	var duel := menu.duel_ui
	var presets := duel.pool
	if presets.is_empty():
		log_line("no presets")
		return
	duel.open_editor(presets[0], String(presets[0].get("id", "")))
	var tabs := 5 if menu.edition == "el1" else 2
	for tab in tabs:
		duel.select_tab(tab)
		await wait(0.4)
		await shot("duel-editor-%d" % tab)
