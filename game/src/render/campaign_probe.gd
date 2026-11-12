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
