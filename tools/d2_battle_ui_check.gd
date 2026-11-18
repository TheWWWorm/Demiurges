extends SceneTree
## Headless check of second-game battle and encyclopaedia reports (0.15.0):
## - #143 the pale manifestations' variable strength reads X/X in the
##   encyclopaedia's creature list and in a card tooltip (it showed -2/-2);
## - #148 hot seat: the hero panels follow the player at the screen, the
##   acting player's portrait and values on the left, the opponent's on the
##   right (both games);
## - #144 combat tutorial: the text column stands along the right edge and
##   fills most of the screen height, with only the close cross offered; the
##   spell the script awaits blinks in the hand.
## - #212 ether disturbance, active abilities and specialisations add their
##   original icons to the same battle notice list as casts.
## - #202/#230 figure tooltips show printed stats and omit enchantments;
##   #227 played-card icons clear as the side or turn changes.
## - #225: a scripted attacker keeps its side of the authored battlefield
##   when the local defender takes the left HUD seat.
##
##   godot --headless --path game --script ../tools/d2_battle_ui_check.gd
##
## Needs the original games' files (user://profiles.json); without them a
## game is skipped.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no el2 files configured (user://profiles.json)")
	else:
		var profile := ELProfile.new()
		if profile.mount("el2", str(paths.el2)):
			_pale_strength(profile)
			_precombat_font(profile)
		else: print("SKIP: el2 files could not be mounted")
	for edition: String in ["el2", "el1"]: await _hot_seat_panels(edition)
	await _casting_and_retry()
	await _tutorial()
	print("D2 BATTLE UI CHECK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

# --- #143 ---------------------------------------------------------------------

func _pale_strength(profile: ELProfile) -> void:
	var found := 0
	for code: String in profile.table("CombatCreatures"):
		var row: Dictionary = profile.table("CombatCreatures")[code]
		if int(row.get("Power", 0)) >= 0: continue
		found += 1
		var shown := ELEncyclopaedia.strength(profile, code)
		check(shown == "X/X", "el2 #143: the encyclopaedia shows %s as X/X (%s)" % [code, shown])
		var tip := ELCombatTooltip.spell_text(profile, code)
		check(tip.contains(" X/X") and not tip.contains("-2"), "el2 #143: %s's card tooltip reads X/X" % code)
	check(found >= 2, "el2 #143: the pale manifestations with variable strength are found (%d)" % found)
	check(ELEncyclopaedia.strength(profile, "ORSH") == "%d/%d" % [int(profile.table("CombatCreatures").ORSH.Power), int(profile.table("CombatCreatures").ORSH.Toughness)], "el2 #143: a printed strength stays as it is")

func _precombat_font(profile: ELProfile) -> void:
	var hud := ELSecondAdventureHud.new()
	hud.profile = profile
	hud.face_bold = ELArtDropList.row_font()
	for row: Dictionary in profile.table("Controls").values(): hud._controls[String(row.Name)] = row
	var panel := ELSecondPrecombatView.new()
	root.add_child(panel)
	panel.build(hud)
	var state := ELAdventureSession.new()
	state.objects = {1: {"title": 'Альфа-100Ф "Сталь"'}, 2: {"title": 'Омега-300В "Безрассудный"'}}
	panel.open(state, 1, 2, [-1, -1])
	var name_label: Label = panel.labels.OpponentName
	var font_size := name_label.get_theme_font_size("font_size")
	var width := hud.face_bold.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	check(width <= name_label.size.x, "#228: the long Russian hero name fits its cell (%s/%s px)" % [width, name_label.size.x])
	check(panel.labels.caption_0_0.get_theme_font_size("font_size") == 15, "#228: the level and health captions use 15 px")
	panel.free()
	hud.free()

# --- #148 ---------------------------------------------------------------------

func _hot_seat_panels(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	var profile: ELProfile = view.profiles.get(edition)
	if profile == null:
		print("SKIP: no %s files for the hot-seat check" % edition)
		view.queue_free()
		return
	var pool := ELDuelPresets.shipped(profile)
	var first: Dictionary = pool[0]
	var second := {}
	for row: Dictionary in pool:
		if row.faction != first.faction and int(row.resource_level) == int(first.resource_level):
			second = row
			break
	var hot_match := ELDuelMatch.new()
	hot_match.begin(profile, pool, [first, second], int(first.resource_level), 1, ELDuelMatch.RANDOM, 77)
	hot_match.hot_seat = true
	hot_match.names = ["P1", "P2"]
	view._begin_duel_match(hot_match)
	await frames(5)
	var seen := {}
	for turn in 3:
		for i in 50:
			if view.hot_pending: break
			await process_frame
		var side: int = view.duel.active_side()
		view._confirm_handover()
		await frames(2)
		var own: Control = view.portraits[side]
		var other: Control = view.portraits[1 - side]
		var stats: Array = view.rail.stats
		var expected := [view.shown_health(side), view.shown_ether(side), view.shown_channels(side)]
		var left_ok: bool = own.position.x < other.position.x and view.hero_buttons[side].position.x < view.hero_buttons[1 - side].position.x
		check(left_ok and stats.size() == 2 and stats[0] == expected, "%s #148 hot seat: player %d's portrait and values are on the left on their turn" % [edition, side + 1])
		seen[side] = true
		var guard := 0
		while view.duel.active_side() == side and guard < 8 and view.duel.phase != ELDuel.Phase.FINISHED:
			view._end_phase()
			await frames(3)
			guard += 1
	check(seen.size() == 2, "%s #148 hot seat: both players took the screen" % edition)
	view.duel_match = null
	view.queue_free()
	await frames(2)

func _casting_and_retry() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	if not view.profiles.has("el2"):
		view.queue_free()
		return
	view._hide_front_menu()
	view._start("el2", {"first_side": 0}, null, 212)
	var duel: ELDuel = view.duel
	var opening: Dictionary = duel.snapshot()
	duel.heroes[0].mana = 20
	duel.heroes[0].hand = ["FRWA", "FRWA", "ZAPP", "STRT"]
	duel.heroes[0].hand_slots = [-1, -1, -1, -1]
	duel._summon(1, "STMC")
	duel._summon(1, "BATT")
	view._skip_battle_presentation()
	var target: int = duel.army(1)[0].id
	var played: Array[String] = []
	var discarded: Array[Dictionary] = []
	duel.event.connect(func(data: Dictionary):
		if data.kind == "cast": played.append(data.card)
		if data.kind == "discard": discarded.append(data))
	view._cast_card(0)
	check(played == ["FRWA"] and (view._display_lagging() or not view._hits_waiting.is_empty()), "Fire Wave starts and has a hit still being presented")
	check(view.notices.icons.size() == 1 and view.notices.icons[0].card == "FRWA", "#227: a cast appears in its own turn's notices")
	view._cast_card(0)
	check(discarded.size() == 1 and discarded[0].card == "STRT" and discarded[0].get("source_card") == "BATT", "the dying Bat discards the rat and identifies the cause")
	view._cast_card(duel.heroes[0].hand.find("ZAPP"))
	view._target(target)
	view._end_phase()
	check(played == ["FRWA", "FRWA", "ZAPP"] and duel.active_side() == 1, "two Fire Waves and Electroshock resolve before the turn passes")
	view._skip_battle_presentation()
	check(view.notices.icons.is_empty(), "#227: the previous turn's casts are gone once the next turn is shown")
	var log_key := InputEventKey.new()
	log_key.keycode = KEY_L
	log_key.physical_keycode = KEY_L
	log_key.pressed = true
	view.log_text.hide()
	root.push_input(log_key, true)
	view._show_log()
	var report: String = view.log_text.text
	var death: String = view._t("%s dies.") % duel.card_name("BATT")
	var loss: String = view._t("The dying Bat made you discard %s.") % duel.card_name("STRT")
	var damage := -1
	for event: Dictionary in duel.history:
		if event.kind != "damage" or event.get("source_card") != "FRWA" or event.get("target_card") != "BATT": continue
		var hit: String = view._t("%s takes %d damage.") % [duel.card_name("BATT"), event.amount]
		var with_source: String = view._t("%s (during %s)") % [hit, duel.card_name("FRWA")]
		damage = report.find(with_source)
		break
	check(view.log_text.visible and damage >= 0 and report.find(death) > damage and report.find(loss) > report.find(death), "L shows Fire Wave's damage, the Bat's death and the discard in order")
	duel._emit({"kind": "draw", "side": 1, "card": "PWTP"})
	var hidden_draw: String = view._t("%s draws a spell.") % view._hero_name(1)
	check(view.logs.back() == hidden_draw, "the battle log records the opponent's draw without naming the hidden card")
	view._ask_surrender()
	var retry: ELFrontMenu.CutButton = view.options_host.buttons.get("MBRetry") if view.options_host != null else null
	check(retry != null and view.options_host.buttons.has("MBOK") and view.options_host.buttons.has("MBCancel"), "the surrender box has all three choices")
	if retry != null:
		var ok: ELFrontMenu.CutButton = view.options_host.buttons.MBOK
		var cancel: ELFrontMenu.CutButton = view.options_host.buttons.MBCancel
		check(retry.size == ok.size and retry.size == cancel.size, "the three surrender buttons are the original size")
		check(retry.position - cancel.position == cancel.position - ok.position, "the three surrender buttons are evenly spaced")
		retry.pressed.emit()
		check(view.duel != duel and view.duel.turn_serial == opening.turn_serial and view.duel.setup == opening.setup, "Try again restarts the same duel setup")
		check(view.duel.rng_state != int(opening.rng), "Try again deals from a new random seed")
	_duel_match_retry(view)
	_creature_ability_buttons(view)
	_battle_notice_icons(view)
	_figure_tooltips(view)
	await _arena_orientation(view)
	view.queue_free()
	await frames(2)

func _arena_orientation(view: Node) -> void:
	await view._begin_campaign("el2", {"file_name": "Maps/e2mission13", "script": "Maps/e2mission13"}, 1)
	var campaign: ELAdventureView = view.campaign_view
	check(campaign != null, "#225: the third Vital mission loads")
	if campaign == null: return
	var state := campaign.state
	var attacker := int(state.vm.globals.ID_C_BOSS)
	var defender := state.main_hero
	var encounter := ELAdventureEncounter.new()
	var prepared := encounter.prepare(state, attacker, defender)
	check(prepared and encounter.swapped and encounter.attacker() == attacker and encounter.player_side() == 0,
		"#225: the scripted Chaot remains the attacker and the player takes the left HUD seat")
	if not prepared: return
	campaign.director.encounter = encounter
	# Use an arena with a positional waterfall to check the scenery effect too.
	encounter.battle.setup.arena = "Blue.001"
	view._begin_encounter(attacker, defender)
	var arena: ELArena = view.arena
	var local_position: Vector3 = view.models[0].position
	var authored := arena.transform.affine_inverse() * local_position
	check(is_equal_approx(authored.x, ELMeleePlayback.hero_position(1).x) and view.camera.position.x < local_position.x,
		"#225: the local defender keeps its authored battlefield position and the camera stays behind it")
	var source: Array = arena.definition.ParticlesCP
	var waterfall := ELFigure.vector(Vector3(source[0], source[1], source[2]))
	check(not view.effects.arena_emitters.is_empty() and view.effects.arena_emitters[0].node.position.is_equal_approx(arena.transform * waterfall),
		"#225: the waterfall effect follows the rotated scenery")

func _duel_match_retry(view: Node) -> void:
	var pool := ELDuelPresets.shipped(view.profile)
	var preset: Dictionary = pool[0]
	var started := ELDuelMatch.new()
	var error := started.begin(view.profile, pool, [preset, preset], int(preset.resource_level), 2, ELDuelMatch.RANDOM, 77)
	check(error.is_empty(), "the retry check starts a two-round duel match")
	if not error.is_empty(): return
	view._begin_duel_match(started)
	view._surrender_round()
	view._watch_match_round(0.0)
	view._play_match_round()
	var duel: ELDuel = view.duel
	var recording: ELDuelRecording = view.match_recording
	var first_round: Dictionary = recording.rounds[0]
	var old_seed: int = recording.rounds[1].seed
	view._ask_surrender()
	var retry: ELFrontMenu.CutButton = view.options_host.buttons.get("MBRetry")
	check(retry != null, "the second round can be retried")
	if retry == null: return
	retry.pressed.emit()
	check(view.duel != duel and view.duel.setup == duel.setup and view.duel_match == started and started.played == 1 and started.wins == [0, 1],
		"retry keeps the same round setup and match score")
	check(recording.rounds.size() == 2 and recording.rounds[0] == first_round and recording.rounds[1].seed != old_seed and recording.tracking(view.duel),
		"the recording replaces the retried round with its new seed")
	var recorded: Dictionary = recording.rounds[1]
	var replay := ELDuel.new()
	check(replay.start(view.profile, int(recorded.seed), recorded.options) and replay.snapshot() == view.duel.snapshot(),
		"the retried round's recording reconstructs the new opening")

func _creature_ability_buttons(view: Node) -> void:
	view._start("el2", {"first_side": 0}, null, 212)
	view.settings.values.helper_overlay = true
	var duel: ELDuel = view.duel
	var sources := {}
	for card: String in ["ORSH", "RFPT", "DRAT", "PRAT", "MOBE", "CLSP", "FMFI", "OUS1"]:
		var id := duel.next_id
		duel._summon(0, card)
		duel.creatures[id].sick = false
		duel.creatures[id].resting = false
		sources[card] = id
	duel.heroes[0].mana = 10
	duel.heroes[0].channels = 1
	check(_ability_buttons(view, sources.ORSH, "orc_rite", false) and _ability_buttons(view, sources.RFPT, "disenchant", false),
		"#204: enchantment removal stays disabled when there are no enchantments")
	duel._enchant("LSST", 0, sources.MOBE, ELCatalog.rule(duel.profile, "LSST"))
	duel.heroes[0].channels = 0
	check(_ability_buttons(view, sources.ORSH, "orc_rite", false) and _ability_buttons(view, sources.OUS1, "channel_ether", false),
		"#204: channel abilities stay disabled when their hero has no channels")
	duel.heroes[0].channels = 1
	check(_ability_buttons(view, sources.ORSH, "orc_rite", true) and _ability_buttons(view, sources.OUS1, "channel_ether", true),
		"#204: the rite and the Pale channel ability light up once a channel is available")
	duel.heroes[0].mana = 0
	check(_ability_buttons(view, sources.RFPT, "disenchant", false), "#204: Piercing Gaze stays disabled if removal is unaffordable")
	duel.heroes[0].mana = 10
	check(_ability_buttons(view, sources.RFPT, "disenchant", true), "#204: Piercing Gaze lights up for an affordable enchantment")
	check(_ability_buttons(view, sources.DRAT, "gnaw", false) and _ability_buttons(view, sources.PRAT, "plague", false),
		"#204: graveyard abilities stay disabled while both graveyards are empty")
	duel.heroes[1].grave.append("WRSP")
	check(_ability_buttons(view, sources.DRAT, "gnaw", true) and _ability_buttons(view, sources.PRAT, "plague", true) and _ability_buttons(view, sources.CLSP, "recall_spirit", false),
		"#204: an enemy graveyard enables Gnaw and Plague but not a friendly-only revival")
	duel.heroes[0].grave.append("WRSP")
	duel.heroes[1].grave.append("STRT")
	check(_ability_buttons(view, sources.CLSP, "recall_spirit", true) and _ability_buttons(view, sources.FMFI, "necromancy", true),
		"#204: both revivals light up when they have suitable cards and room")
	var filler := duel.next_id
	while duel.army(0).size() < 10: duel._summon(0, "STRT")
	check(_ability_buttons(view, sources.CLSP, "recall_spirit", false) and _ability_buttons(view, sources.FMFI, "necromancy", false) and _ability_buttons(view, sources.MOBE, "brood", false),
		"#204: revivals and Spawn a Bee stay disabled at the creature limit")
	view._strip_pressed(0)
	check(duel.army(0).size() == 10 and not duel.creatures[sources.MOBE].resting and duel.heroes[0].mana == 10,
		"#204: clicking a dimmed ability spends nothing and leaves the creature ready")
	duel._kill(filler)
	check(_ability_buttons(view, sources.MOBE, "brood", true), "#204: Spawn a Bee lights up again when a slot opens")
	view._strip_pressed(0)
	check(duel.army(0).size() == 10 and duel.creatures[sources.MOBE].resting, "#204: clicking the enabled ability summons a bee")

func _battle_notice_icons(view: Node) -> void:
	view._start("el2", {"first_side": 0}, null, 212)
	var duel: ELDuel = view.duel
	var profile := duel.profile
	var notices: ELCombatNotices = view.notices
	var pale := duel.next_id
	duel._summon(0, "SMWB")
	duel.heroes[0].grave.append("STRT")
	check(duel.use_ability(pale, "sinister", 0, 0), "#212: a Pale Knight can use Sinister Manifestation (%s)" % duel.error)
	view._skip_battle_presentation()
	var manifestation: Dictionary = profile.table("CombatSpells").AOUF
	var ability_icon := profile.icon_at(int(manifestation.AbilityIcon)) as AtlasTexture
	check(notices.icons.size() == 1 and notices.icons[0].card == "AOUF" and _notice_uses(notices, 0, ability_icon)
		and notices.get_tooltip(notices.icon_rect(0).get_center()) == profile.text(manifestation.AbilityText),
		"#212: the manifestation notice uses its own ability icon and description")
	duel.heroes[1].turns = int(duel.heroes[1].level) + 11
	for hero: Dictionary in duel.heroes: hero.skills.clear()
	var health := int(duel.heroes[1].health)
	duel.end_phase()
	view._skip_battle_presentation()
	notices.viewer_side = 0
	check(int(duel.heroes[1].health) < health and notices.icons.size() == 1 and _notice_uses(notices, 0, profile.icon_at(916))
		and notices.get_tooltip(notices.icon_rect(0).get_center()) == profile.text("ETHER_DISTURBANCE_ENEMY_Tt"),
		"#212: the turn change leaves the opposing hero's disturbance icon visible")
	notices.viewer_side = 1
	check(_notice_uses(notices, 0, profile.icon_at(915))
		and notices.get_tooltip(notices.icon_rect(0).get_center()) == profile.text("ETHER_DISTURBANCE_SELF_Tt"),
		"#212: the disturbance notice follows the player viewing it")
	duel.heroes[1].spec = "BMWM"
	duel.heroes[1].spec_level = 20
	check(ELSpecs.roll(duel, 1, "BMWM", 100) > 0, "#212: Destructive Mindwipe can trigger a specialisation notice")
	notices.viewer_side = 1
	check(notices.icons.size() == 2 and _notice_uses(notices, 1, profile.icon_at(918))
		and notices.get_tooltip(notices.icon_rect(1).get_center()) == profile.text(profile.table("HeroesSpecs").BMWM.Desc),
		"#212: the specialisation icon describes the effect that triggered")
	notices.viewer_side = 0
	check(_notice_uses(notices, 1, profile.icon_at(917)), "#212: the opposing specialisation uses the opposing icon")
	# The defender and the next attacker can be the same side. A new turn
	# still clears the defence's icons even when that side keeps the screen.
	var attacker := duel.next_id
	duel._summon(1, "ORSH")
	duel.creatures[attacker].sick = false
	check(duel.toggle_attack(attacker) and duel.end_phase(), "#227: an attacker is declared before passing to defence")
	view._skip_battle_presentation()
	check(duel.phase == ELDuel.Phase.DEFENCE and notices.icons.is_empty(), "#227: switching to defence clears the previous side's icons")
	duel.heroes[0].mana = 10
	duel.heroes[0].hand = ["FOGG"]
	duel.heroes[0].hand_slots = [-1]
	check(duel.cast(0), "#227: the defending side casts Fog (%s)" % duel.error)
	view._skip_battle_presentation()
	check(notices.icons.size() == 1 and notices.icons[0].card == "FOGG", "#227: the defender sees their own cast")
	duel.end_phase()
	view._skip_battle_presentation()
	check(duel.active_side() == 0 and duel.phase == ELDuel.Phase.ATTACK and notices.icons.is_empty(),
		"#227: the defender's cast disappears when their attack starts")

func _figure_tooltips(view: Node) -> void:
	view._start("el2", {"first_side": 0}, null, 230)
	var duel: ELDuel = view.duel
	var id := duel.next_id
	duel._summon(0, "ORSH")
	var printed := ELCombatTooltip.spell_text(duel.profile, "ORSH", -1, duel.card_name("ORSH"))
	duel._mark(id, "STSK", 2, 2)
	duel._damage(id, 1)
	check(view._creature_tip_text(id) == printed, "#202/#230: a wounded, enchanted creature's tooltip reads like its printed card")

func _notice_uses(notices: ELCombatNotices, index: int, expected: AtlasTexture) -> bool:
	if index >= notices.icons.size(): return false
	var texture := notices.icon_texture(index) as AtlasTexture
	return texture != null and texture.atlas != null and texture.atlas == expected.atlas and texture.region == expected.region

func _ability_buttons(view: Node, id: int, key: String, enabled: bool) -> bool:
	view.selected_creature = id
	view._refresh_inspector()
	var strip: Array = view.rail.strip.items.filter(func(item: Dictionary) -> bool: return item.meta.get("ability") == key)
	var buttons: Array = view.inspector_rows.get_children().filter(func(item: Node) -> bool: return item.get_meta("ability", "") == key)
	return strip.size() == 1 and buttons.size() == 1 and strip[0].enabled == enabled and buttons[0].disabled != enabled

# --- #144 ---------------------------------------------------------------------

func _tutorial() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	if not view.profiles.has("el2"):
		print("SKIP: no el2 files for the combat tutorial check")
		view.queue_free()
		return
	view._begin_combat_tutorial()
	await frames(4)
	var tutorial: ELCombatTutorial = view.combat_tutorial
	var panel: ELCombatTutorialPanel = view.tutorial_panel
	if tutorial == null or panel == null:
		check(false, "el2 #144: the combat tutorial starts")
		view.queue_free()
		return
	var screen: Vector2 = panel.size
	var text := Rect2(panel.text_box.position, panel.text_box.size)
	check(text.end.x > screen.x * 0.9 and text.position.x > screen.x * 0.6, "el2 #144: the tutorial text stands along the right edge (%s in %s)" % [text, screen])
	check(text.size.y > screen.y * 0.6, "el2 #144: the tutorial text fills most of the screen height (%d of %d px)" % [text.size.y, screen.y])
	check(panel.buttons.TP_Close.visible and not panel.buttons.TP_Show.visible, "el2 #144: the tutorial panel offers the close cross alone")
	# Play the script up to the first spell the player must cast.
	var guard := 0
	while tutorial.awaited_hand_index() < 0 and not tutorial.done() and tutorial.error.is_empty() and guard < 300:
		tutorial.run_current()
		guard += 1
	var awaited: int = tutorial.awaited_hand_index()
	check(awaited >= 0, "el2 #144: the script reaches a spell the player must cast")
	view._refresh()
	await frames(2)
	var blinking: Array = []
	for button: Node in view.hand.get_children():
		if button.has_meta("hand_index") and button.get_node_or_null("TutorialBlink") != null: blinking.append(int(button.get_meta("hand_index")))
	check(blinking == [awaited], "el2 #144: the awaited spell (hand %d) blinks, no other card does (%s)" % [awaited, blinking])
	view._close_combat_tutorial()
	view.queue_free()
	await frames(2)
