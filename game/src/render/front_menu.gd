class_name ELFrontMenu
extends Control
## Original front-end screens (main menu, sub-menus, campaign choice, mission
## briefing / campaign map) composed from the mounted CutParts, Controls and
## text registries. The 1024x768 design is scaled uniformly to the window and
## letterboxed, so the original 4:3 art is never stretched.
signal duel_requested
signal campaign_requested(edition: String, scenario: Dictionary, difficulty: int)
signal load_requested
## Load game -> Single (first game): resume the single-mission save.
signal single_load_requested
## A campaign save chosen on a load list (ELSaveSlots row).
signal slot_load_requested(row: Dictionary)
## Hosted over a running game: the save chosen on the load list (after the
## T_MB_LOAD_GAME question); the screen has already closed.
signal slot_chosen(row: Dictionary)
## The remake-only settings dialog (the Options screen's remake section).
signal settings_requested
## The Options screen closed: OK (true) or Cancel, and the command button
## pressed ("GOSave", "GOLoad", "GOMenu", "GOQuit", "Surrender" or "").
signal options_closed(applied: bool, command: String)
## Options volume sliders moved (or Cancel restored them): the host applies
## the music and effects volumes of `values` at once.
signal settings_previewed(values: Dictionary)
signal quit_requested
signal edition_requested(edition: String)
## Duel screen Start: the match is begun (presets resolved); the view plays its rounds.
signal duel_match_requested(match: ELDuelMatch)
## Round-result / duel-summary OK and Cancel.
signal duel_round_closed(proceed: bool)
## Tutorial -> Combat: the combat tutorial replay (second game).
signal combat_tutorial_requested
## Duel -> Replay -> Load: the chosen replay file plays back (second game).
signal replay_requested(path: String)
## A hosted screen (open_hosted) was left with OK, Close or Esc.
signal hosted_closed
## The menu's own music took over the sound (true) or gave it back (false):
## the host pauses whatever plays behind an opaque menu screen.
signal music_owner_changed(owned: bool)

const DESIGN := Vector2(1024, 768)
const INK := Color("e6dcc0")
const INK_HOVER := Color("fff4d6")
const INK_DISABLED := Color("8a8478")
const TITLE_INK := Color("d9cba6")
const BODY_INK := Color("d8d2c0")
const UNAVAILABLE := "Not available in the remake yet."
## OK action of the open inform_hosted box (none while a question is open).
var _inform_ok: Callable
## Screens built by ELMissionLoadScreen (SaveMissionScreen in its modes).
const SAVE_SCREENS := ["load_mission", "load_campaign", "save_game", "load_game"]
const NO_REPLAYS := "Replays are not supported in the remake yet."
## Network and master-server play are outside the remake; hot seat is local.
const NO_NETWORK := "Network play is not part of the remake."
const NETWORK_CONTROLS := ["MSTCPIP", "MSLAN", "MSGameSpy", "MM_MP_MasterServBtn", "MSTStrategy"]
## Screens built by ELReplayScreen (second game).
const REPLAY_SCREENS := ["replay_load", "replay_save"]
## Screen definitions per edition. "art" is the CutParts control group drawn as
## the background; "under" adds another group beneath it; "buttons" are the
## stacked text buttons in their registry order.
const SCREENS := {
	"el1": {
		"main": {"art": "MainMenu1", "buttons": ["NewGameButton", "LoadGameButton", "OptionsButton", "HallOfFameButton", "CreditsButton", "QuitButton"]},
		"new": {"art": "NewGame", "buttons": ["DuelButton", "CampaignButton", "SingleButton", "MultiplayerButton", "BackButton"], "back": "main"},
		"load": {"art": "LoadGame", "buttons": ["LGCampaign", "LGSingle", "LGBack"], "back": "main"},
		"campaigns": {"art": "SelectCampaign", "back": "new"},
		# Blazon choice over the campaign or Single panel frame.
		"blazon": {"art": "CISelectBlazon", "under": "SelectCampaign", "back": "campaigns"},
		"blazon_single": {"art": "CISelectBlazon", "under": "SelectMission", "back": "single"},
		# Campaign branch choice between chapters (no back).
		"branch": {"art": "SelectCampaignBranch"},
		"legend": {"art": "CampaignText", "under": "SelectCampaign", "back": "campaigns"},
		"mission": {"art": "CampaignInfo", "back": "campaigns"},
		"duel": {"art": "Duel", "exclude": ["Type2"], "back": "new"},
		# New game -> Multiplayer: Duel / Strategy, then the Duel connection
		# menu whose Hot seat opens the Duel screen.
		# Network play and the strategic (network-only) branch stay disabled.
		"mp_type": {"art": "MultiplayerSelectType", "buttons": ["MSTDuel", "MSTStrategy", "MSTBack"], "back": "new"},
		"mp_start": {"art": "MultiplayerStart", "buttons": ["MSTCPIP", "MSLAN", "MSGameSpy", "MSHotSeat", "MSBack"], "back": "mp_type"},
		"single": {"art": "SelectMission", "back": "new"},
		# Load game -> Campaign / Single: SaveMissionScreen in load mode.
		"load_campaign": {"art": "SaveMissionScreen", "back": "load"},
		"load_mission": {"art": "SaveMissionScreen", "back": "load"},
		# Hosted over a running game (adventure Options column Save / Load).
		"save_game": {"art": "SaveMissionScreen", "back": "main"},
		"load_game": {"art": "SaveMissionScreen", "back": "main"},
		# A message box alone over a running game (quick load question).
		"question": {"art": "", "back": "main", "overlay": true},
		"duel_editor": {"art": "EditHero", "back": "duel"},
		"duel_round": {"art": "RoundResult", "overlay": true},
		"duel_result": {"art": "", "overlay": true},
		"hall_of_fame": {"art": "HallOfFame", "back": "main"},
		"credits": {"art": "", "back": "main"},
		"options": {"art": "Options", "back": "main"},
		# Mission objectives over the map (Options GOInfo); Esc goes back.
		"objectives": {"art": "Objectives", "back": "main", "overlay": true},
	},
	"el2": {
		"main": {"art": "MM_MainMenuA6", "buttons": ["MM_SingleBtn", "MM_MultiplayerBtn", "MM_OptionsBtn", "MM_EncBtn", "MM_CreditsBtn", "MM_QuitBtn"]},
		"single": {"art": "MM_SingleGameScreenA6", "buttons": ["MM_SG_TutorialBtn", "MM_SG_DuelBtn", "MM_SG_CampaignBtn", "MM_SG_MissionBtn", "MM_SG_BackBtn"], "back": "main"},
		"campaign_menu": {"art": "MM_CampaignScreenA6", "buttons": ["MM_C_NewBtn", "MM_C_LoadBtn", "MM_C_BackBtn", "MM_C_HOFBtn"], "back": "single"},
		# CMMMissionScreen: New, Load, Back, Hall of Fame (scenario table).
		"mission_menu": {"art": "MM_MissionScreenA6", "buttons": ["MM_M_NewBtn", "MM_M_LoadBtn", "MM_M_BackBtn", "MM_M_HOFBtn"], "back": "single"},
		"hall_of_fame": {"art": "HallOfFame", "back": "mission_menu"},
		# Mission -> New: Select Mission replaces the menu screens.
		"select_mission": {"art": "SelectMission", "back": "mission_menu"},
		# Mission -> Load (mode 1): the save list over the Mission screen.
		"load_mission": {"art": "SaveMissionScreen", "under": "MM_MissionScreenA6", "back": "mission_menu"},
		# Campaign -> Load (mode 0): the campaign save list.
		"load_campaign": {"art": "SaveMissionScreen", "under": "MM_CampaignScreenA6", "back": "campaign_menu"},
		# Hosted over a running game (Esc menu Save / Load).
		"save_game": {"art": "SaveMissionScreen", "back": "main"},
		"load_game": {"art": "SaveMissionScreen", "back": "main"},
		"question": {"art": "", "back": "main", "overlay": true},
		# CMMTutorialScreen: adventure tutorial, combat tutorial replay, back.
		"tutorial": {"art": "MM_TutorialScreenA6", "buttons": ["MM_Tut_Adventure", "MM_Tut_Combat", "MM_Tut_BackBtn"], "back": "single"},
		"campaigns": {"art": "SelectCampaign", "exclude": ["Type2"], "back": "campaign_menu"},
		"legend": {"art": "CampaignText", "under": "MM_CampaignScreenA6", "back": "campaigns"},
		"map": {"art": "GlobalMapA6", "under": "MM_CampaignScreenA6", "back": "campaigns"},
		"duel_menu": {"art": "MM_DuelScreenA6", "buttons": ["MM_D_NewBtn", "MM_D_ReplayBtn", "MM_D_BackBtn"], "back": "single"},
		# Main -> Multiplayer: Master Server / Duel, then the Duel connection
		# menu whose HOTSEAT opens the Duel screen.
		"multiplayer": {"art": "MM_MultiplayerScreenA6", "buttons": ["MM_MP_MasterServBtn", "MM_MP_DuelBtn", "MM_MP_BackBtn"], "back": "main"},
		"mp_start": {"art": "MultiplayerStart", "buttons": ["MSTCPIP", "MSLAN", "MSGameSpy", "MSHotSeat", "MSBack"], "back": "multiplayer"},
		"duel": {"art": "Duel", "exclude": ["Type2"], "back": "duel_menu"},
		# CReplayScreen: Duel -> Replay (load, Type3 art) and the final round
		# result's Save duel replay (save, Type4 art, over the battle).
		"replay_load": {"art": "ReplayScreen", "exclude": ["Type4"], "under": "MM_DuelScreenA6", "back": "duel_menu"},
		"replay_save": {"art": "ReplayScreen", "exclude": ["Type3"], "back": "duel_round", "overlay": true},
		"duel_editor": {"art": "EditPresetA6", "back": "duel"},
		"duel_round": {"art": "RoundResult", "overlay": true},
		"duel_result": {"art": "", "overlay": true},
		"credits": {"art": "", "back": "main"},
		"encyclopaedia": {"art": "Encyclopaedia", "back": "main"},
		"options": {"art": "Options", "back": "main"},
	},
}
## Remake actions for each original control; "" leaves the control disabled,
## "none" keeps it enabled without an effect (as the original does).
const ACTIONS := {
	"NewGameButton": "screen:new", "LoadGameButton": "screen:load", "OptionsButton": "options", "HallOfFameButton": "hall_of_fame", "CreditsButton": "credits", "QuitButton": "quit",
	"DuelButton": "screen:duel", "CampaignButton": "screen:campaigns", "SingleButton": "screen:single", "MultiplayerButton": "screen:mp_type", "BackButton": "back",
	"MSTDuel": "screen:mp_start", "MSTStrategy": "", "MSTBack": "back",
	"MM_MP_DuelBtn": "screen:mp_start", "MM_MP_MasterServBtn": "", "MM_MP_BackBtn": "back",
	"MSTCPIP": "", "MSLAN": "", "MSGameSpy": "", "MSHotSeat": "hot_seat", "MSBack": "back",
	"LGCampaign": "screen:load_campaign", "LGSingle": "screen:load_mission", "LGBack": "back",
	"MM_SingleBtn": "screen:single", "MM_MultiplayerBtn": "screen:multiplayer", "MM_OptionsBtn": "options", "MM_EncBtn": "encyclopaedia", "MM_CreditsBtn": "credits", "MM_QuitBtn": "quit",
	"MM_SG_TutorialBtn": "screen:tutorial", "MM_SG_DuelBtn": "screen:duel_menu", "MM_SG_CampaignBtn": "screen:campaign_menu", "MM_SG_MissionBtn": "screen:mission_menu", "MM_SG_BackBtn": "back",
	# The combat tutorial is the replay Tutorial\Combat\combat_tutorial.rpl.
	"MM_Tut_Adventure": "tutorial_adventure", "MM_Tut_Combat": "tutorial_combat", "MM_Tut_BackBtn": "back",
	"MM_D_NewBtn": "screen:duel", "MM_D_ReplayBtn": "screen:replay_load", "MM_D_BackBtn": "back",
	# The campaign screen's Hall of Fame button has no command in the original.
	"MM_C_NewBtn": "screen:campaigns", "MM_C_LoadBtn": "screen:load_campaign", "MM_C_BackBtn": "back", "MM_C_HOFBtn": "none",
	# New opens Select Mission and Load the single-mission save list; both are
	# always enabled, as in the original, even when their lists are empty.
	"MM_M_NewBtn": "screen:select_mission", "MM_M_LoadBtn": "screen:load_mission", "MM_M_BackBtn": "back", "MM_M_HOFBtn": "hall_of_fame_scenario",
}
## Campaign portraits. The original stores each card picture as a 221/223 px
## wide block plus a bottom strip packed into shared textures; rectangles and
## the first game's strip order were measured from the textures by seam
## continuity.
const PORTRAITS := {
	"el1": {
		"Good": [["CAMPAIGN_PANEL_9", Rect2(0, 0, 221, 256), Vector2(0, 0)], ["CAMPAIGN_PANEL_9", Rect2(221, 0, 35, 83), Vector2(0, 256)],
			["CAMPAIGN_PANEL_9", Rect2(221, 83, 35, 83), Vector2(35, 256)], ["CAMPAIGN_PANEL_9", Rect2(221, 166, 35, 83), Vector2(70, 256)], ["CAMPAIGN_PANEL_11", Rect2(0, 0, 116, 83), Vector2(105, 256)]],
		"Evil": [["CAMPAIGN_PANEL_10", Rect2(0, 0, 221, 256), Vector2(0, 0)], ["CAMPAIGN_PANEL_10", Rect2(221, 0, 35, 83), Vector2(0, 256)],
			["CAMPAIGN_PANEL_10", Rect2(221, 83, 35, 83), Vector2(35, 256)], ["CAMPAIGN_PANEL_10", Rect2(221, 166, 35, 83), Vector2(70, 256)], ["CAMPAIGN_PANEL_11", Rect2(116, 0, 116, 83), Vector2(105, 256)]],
	},
	"el2": {
		"Green": [["CAMPAIGN_PANEL_01", Rect2(0, 0, 223, 256), Vector2(0, 0)], ["CAMPAIGN_PANEL_012", Rect2(0, 0, 223, 85), Vector2(0, 256)]],
		"Red": [["CAMPAIGN_PANEL_02", Rect2(0, 0, 223, 256), Vector2(0, 0)], ["CAMPAIGN_PANEL_012", Rect2(0, 86, 223, 85), Vector2(0, 256)]],
	},
}
## Card holes (1024 layout) and the original caption controls for each card.
const CARDS := {
	"el1": [{"id": "Good", "hole": Rect2(264, 173, 225, 341), "name": "SCGood"}, {"id": "Evil", "hole": Rect2(534, 173, 225, 341), "name": "SCEvil"}],
	"el2": [{"id": "Green", "hole": Rect2(246, 185, 223, 341), "name": "SCLeft", "title": "T_SC_CAMP_GREEN", "caption": "SCDesc1"},
		{"id": "Red", "hole": Rect2(556, 185, 223, 341), "name": "SCRight", "title": "T_SC_CAMP_RED", "caption": "SCDesc2"}],
}
## Second-game hero figures on interface/world_symbols_map, per campaign.
const MAP_FIGURES := {"Red": Rect2(10, 18, 16, 23), "Blue": Rect2(30, 20, 11, 21), "Green": Rect2(50, 19, 13, 22), "Black": Rect2(70, 17, 14, 24), "White": Rect2(90, 15, 19, 26)}

var profile: ELProfile
var profiles: Dictionary = {}
var edition := ""
var screen := ""
var canvas: Control
var art: Control
var scale_factor := 1.0
var buttons: Dictionary = {}
var labels: Dictionary = {}
var cards: Array[CardButton] = []
var text_box: RichTextLabel
var selected_campaign := ""
var difficulty := 1
var campaign_data: ELCampaign
var serif: Font
var _paths: Dictionary = {}
var _rows: Dictionary = {}
var _controls: Dictionary = {}
var _pieces: Array[Dictionary] = []
var _legend_next := ""
## Second game: the adventure tutorial returns to the Tutorial screen (
## reopens it when mission is set); the host's next "main" becomes it.
var _return_screen := ""
## The second game's adventure tutorial map and script (catalogue entry).
const TUTORIAL_ADVENTURE := "Tutorial/Adventure/e2tutorial"
var _switch: Button
## Second-game campaign progress shown on the global map (ELSecondCampaign).
var second: Dictionary = {}
## Duel screen, preset editor and round results (ELDuelScreen).
var duel_ui: ELDuelScreen
## Single mission choice of both games (ELSingleScreen) and the second game's
## single-mission save list (ELMissionLoadScreen).
var single_ui: ELSingleScreen
## First game: player name and blazon (campaign screen, blazon choice).
var blazon_ui: ELBlazonScreen
var branch_ui: ELBranchScreen
## The screen shown before the current one.
var previous_screen := ""
var mission_load_ui: ELMissionLoadScreen
## Second-game duel replay list (load) and replay saving (ELReplayScreen).
var replay_ui: ELReplayScreen
## First-game Hall of Fame, credits of both games, second-game Encyclopaedia.
var hall_ui: ELHallOfFameScreen
var credits_ui: ELCreditsScreen
var encyclopaedia_ui: ELEncyclopaediaScreen
var options_ui: ELOptionsScreen
## First game: the mission objectives panel and the running mission's texts
## (objective, win_condition, lose_condition), set by the map that hosts it.
var objectives_ui: ELFirstObjectivesScreen
var mission_texts: Dictionary = {}
## Preferences edited by the Options screen; the host sets its own, otherwise
## the menu reads and writes `settings_path`.
var settings: ELSettings
var settings_path := "user://settings.json"
## Interface music, credits music and the Hall of Fame fanfare.
var _audio: AudioStreamPlayer
## First game: the voiced briefing of the campaign text and campaign info
## screens, over the interface music.
var briefing: ELBriefingVoice
## First game: the chapter the campaign info screen shows after a chapter
## result (empty: the campaign's first chapter).
var chapter := {}
## The game's own front end (not a screen hosted over the map): its screens
## play interface.mp3. Showing the main menu or a sub-menu starts it unless it
## already plays (no restart); it repeats the whole track. Credits switch to
## the credits music and the Hall of Fame stops it for its fanfare, so the menu
## shown after them starts interface music from the beginning. Hiding the menu
## (a battle or the map takes over) cuts it. Every switch is a cut, no fade.
## Round results over the battle leave the battle's music alone.
var interface_music := false
## File playing as music ("" for none or a sound) and its volume channel.
var _music_path := ""
var _channel := ""
var _music_owned := false
## Hosted over the game: one extras screen (the second game's Encyclopaedia
## from the adventure Esc menu, the first game's Hall of Fame after a won
## mission) whose OK/Close/Esc emits hosted_closed instead of showing the main
## menu. `_over_game` keeps the map visible around the panel.
var hosted := false
var _over_game := false

## Composes the menu for one mounted edition; returns false when its original
## front-end art is not present.
func build(available: Dictionary, initial: String) -> bool:
	profiles = available
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"])
	serif = system
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = DESIGN
	add_child(canvas)
	_switch = Button.new()
	_switch.flat = true
	_switch.focus_mode = Control.FOCUS_NONE
	_switch.add_theme_color_override("font_color", Color(INK, 0.55))
	_switch.add_theme_font_size_override("font_size", 13)
	_switch.pressed.connect(func():
		var other := "el2" if edition == "el1" else "el1"
		if profiles.has(other):
			edition_requested.emit(other)
			use_edition(other))
	add_child(_switch)
	resized.connect(_layout)
	duel_ui = ELDuelScreen.new(self)
	single_ui = ELSingleScreen.new(self)
	blazon_ui = ELBlazonScreen.new(self)
	branch_ui = ELBranchScreen.new(self)
	mission_load_ui = ELMissionLoadScreen.new(self)
	replay_ui = ELReplayScreen.new(self)
	hall_ui = ELHallOfFameScreen.new(self)
	credits_ui = ELCreditsScreen.new(self)
	encyclopaedia_ui = ELEncyclopaediaScreen.new(self)
	options_ui = ELOptionsScreen.new(self)
	objectives_ui = ELFirstObjectivesScreen.new(self)
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	briefing = ELBriefingVoice.new()
	add_child(briefing)
	return use_edition(initial)

static func supports(source: ELProfile) -> bool:
	var group: String = SCREENS.get(source.id, {}).get("main", {}).get("art", "")
	if group.is_empty(): return false
	for row: Dictionary in source.table("CutParts").values():
		if row.get("Ctrl", "") == group: return true
	return false

func use_edition(id: String) -> bool:
	if not profiles.has(id) or not supports(profiles[id]): return false
	edition = id
	profile = profiles[id]
	_paths.clear()
	_rows.clear()
	_controls.clear()
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		_paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for row: Dictionary in profile.table("CutParts").values():
		var masks: Variant = row.get("Msk", [])
		var copy := row.duplicate()
		copy.masks = masks if masks is Array else [masks]
		if not _rows.has(row.get("Ctrl", "")): _rows[row.get("Ctrl", "")] = []
		_rows[row.get("Ctrl", "")].append(copy)
	for row: Dictionary in profile.table("Controls").values():
		_controls[str(row.get("Name", ""))] = row
	var other := "el2" if id == "el1" else "el1"
	_switch.visible = profiles.has(other) and supports(profiles[other])
	_switch.text = profiles[other].title if profiles.has(other) else ""
	selected_campaign = ""
	ELSingleScenario.SAVE = ELSingleScenario.save_file(id)
	if single_ui != null: single_ui.reset()
	if duel_ui != null: duel_ui.reset()
	if credits_ui != null:
		credits_ui.pages = []
		credits_ui.entries = []
	if hall_ui != null: hall_ui.tables = {}
	show_screen("main")
	return true

## Texture-backed piece in 1024-layout coordinates.
func cut(row: Dictionary, offset := Vector2.ZERO) -> Dictionary:
	var texture := texture_named(str(row.get("Txt", "")))
	if texture == null: return {}
	return {"texture": texture, "source": Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH), "rect": Rect2(Vector2(row.ScrL, row.ScrT) + offset, Vector2(row.TxtW, row.TxtH))}

func texture_named(key: String) -> Texture2D:
	return profile.texture(_paths.get(key, "")) if _paths.has(key) else null

func rows(control: String, required: Array = [], excluded: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in _rows.get(control, []):
		if required.all(func(mask: String): return row.masks.has(mask)) and not excluded.any(func(mask: String): return row.masks.has(mask)): result.append(row)
	return result

## Screen offset of a control: its own shift plus its parent panel's.
func shift(control: String) -> Vector2:
	var row: Dictionary = _controls.get(control, {})
	var result := Vector2(float(row.get("ShiftX", 0)), float(row.get("ShiftY", 0)))
	var parent: Dictionary = _controls.get(str(row.get("Parent", "")), {})
	if not parent.is_empty(): result += Vector2(float(parent.get("ShiftX", 0)), float(parent.get("ShiftY", 0)))
	return result

func text(key: String) -> String:
	return profile.text(key)

func show_screen(target: String) -> void:
	if target == "main" and not _return_screen.is_empty() and SCREENS.get(edition, {}).has(_return_screen): target = _return_screen
	_return_screen = ""
	if briefing != null: briefing.stop_voice()
	if target != "mission": chapter = {}
	previous_screen = screen
	screen = target
	buttons.clear()
	labels.clear()
	cards.clear()
	text_box = null
	for child in canvas.get_children():
		canvas.remove_child(child)
		child.queue_free()
	art = Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = DESIGN
	art.draw.connect(_draw_art)
	canvas.add_child(art)
	var definition: Dictionary = SCREENS[edition][target]
	_pieces.clear()
	if definition.has("under"): _add_group(definition.under, [])
	_add_group(definition.art, definition.get("exclude", []) + (duel_ui.art_exclude(target) if duel_ui != null else []) + (encyclopaedia_ui.art_exclude(target) if encyclopaedia_ui != null else []) + (options_ui.art_exclude(target) if options_ui != null else []))
	if not target in ["credits", "hall_of_fame"] and not playing_interface(): stop_audio()
	if definition.has("buttons"): _build_text_buttons(definition.buttons)
	match target:
		"campaigns": _build_campaigns()
		"legend": _build_legend()
		"mission": _build_mission()
		"map": _build_map()
		"duel": duel_ui.build_screen()
		"single", "select_mission": single_ui.build_screen()
		"blazon", "blazon_single": blazon_ui.build_dialog()
		"branch": branch_ui.build()
		"load_mission":
			mission_load_ui.prepare("load", ELSaveSlots.KIND_SINGLE)
			mission_load_ui.build_screen()
		"load_campaign":
			mission_load_ui.prepare("load", ELSaveSlots.KIND_CAMPAIGN)
			mission_load_ui.build_screen()
		"save_game", "load_game": mission_load_ui.build_screen()
		"replay_load", "replay_save": replay_ui.build_screen()
		"duel_editor": duel_ui.build_editor()
		"duel_round": duel_ui.build_round()
		"duel_result": duel_ui.build_result()
		"hall_of_fame": hall_ui.build_screen()
		"credits": credits_ui.build_screen()
		"encyclopaedia": encyclopaedia_ui.build_screen()
		"options": options_ui.build_screen()
		"objectives": objectives_ui.build_screen()
	_layout()
	art.queue_redraw()
	queue_redraw()
	sync_music()

## Screens drawn over the battle (round results) keep it visible around the panel.
func overlay() -> bool:
	if hosted and _over_game: return true
	return bool(SCREENS.get(edition, {}).get(screen, {}).get("overlay", false))

func _add_group(group: String, excluded: Array) -> void:
	var offset := shift(group)
	var list := rows(group, [], ["Res1"] + excluded)
	list.sort_custom(func(a: Dictionary, b: Dictionary): return _layer(a) < _layer(b))
	for row: Dictionary in list:
		var piece := cut(row, offset)
		if not piece.is_empty(): _pieces.append(piece)

static func _layer(row: Dictionary) -> int:
	for index in [3, 2, 1]:
		if row.masks.has("Last%d" % index): return index
	return 2 if row.masks.has("Last") else 0

func _draw_art() -> void:
	if overlay(): art.draw_rect(Rect2(Vector2.ZERO, DESIGN), Color(0, 0, 0, 0.35))
	else: art.draw_rect(Rect2(Vector2.ZERO, DESIGN), Color.BLACK)
	for piece: Dictionary in _pieces: art.draw_texture_rect_region(piece.texture, piece.rect, piece.source)

func _layout() -> void:
	if canvas == null or size.x <= 0 or size.y <= 0: return
	scale_factor = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	canvas.scale = Vector2(scale_factor, scale_factor)
	canvas.position = ((size - DESIGN * scale_factor) * 0.5).floor()
	if _switch != null:
		_switch.size = _switch.get_combined_minimum_size()
		_switch.position = Vector2(8, size.y - _switch.size.y - 4)

func _draw() -> void:
	if not overlay(): draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)

# --- Stacked text buttons ----------------------------------------------------

func _build_text_buttons(names: Array) -> void:
	var font_size := 24
	var widest := 0.0
	for control: String in names:
		widest = maxf(widest, serif.get_string_size(_caption(control), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	# Captions longer than the 140 px design widen the shared middle section;
	# the column stays centred on the 1024 screen as in the original.
	var width := maxf(140.0, ceilf(widest + 72.0))
	for control: String in names:
		var button := TextButton.make(self, control, width, font_size)
		if button == null: continue
		canvas.add_child(button)
		buttons[control] = button
		_wire(button, control)

func _caption(control: String) -> String:
	var row: Dictionary = _controls.get(control, {})
	return text(str(row.get("Text", "Ctrl" + control))).replace("  ", " ")

func _wire(button: BaseButton, control: String) -> void:
	var action: String = ACTIONS.get(control, "")
	# The remake keeps Load game -> Campaign / Single and Campaign -> Load
	# disabled while their list is empty (Mission -> Load always opens).
	if control in ["LGCampaign", "MM_C_LoadBtn"] and ELSaveSlots.list(profile, ELSaveSlots.KIND_CAMPAIGN).is_empty():
		button.disabled = true
		button.tooltip_text = "No saved campaign."
		return
	if control == "LGSingle" and ELSaveSlots.list(profile, ELSaveSlots.KIND_SINGLE).is_empty():
		button.disabled = true
		button.tooltip_text = "No saved mission."
		return
	if action == "tutorial_combat" and profile.file(ELCombatTutorial.PATH).is_empty():
		button.disabled = true
		button.tooltip_text = "The combat tutorial replay is missing from the game content."
		return
	if action.is_empty():
		button.disabled = true
		button.tooltip_text = NO_REPLAYS if control == "MM_D_ReplayBtn" else (NO_NETWORK if control in NETWORK_CONTROLS else UNAVAILABLE)
		return
	if action == "none": return
	button.pressed.connect(func(): _run(action))

func _run(action: String) -> void:
	if action.begins_with("screen:"):
		show_screen(action.trim_prefix("screen:"))
		return
	match action:
		"back": go_back()
		"duel": duel_requested.emit()
		"hot_seat": duel_ui.start_hot_seat()
		"settings": settings_requested.emit()
		"options": options_ui.open("menu")
		"quit": quit_requested.emit()
		"load": load_requested.emit()
		"load_single": single_load_requested.emit()
		"hall_of_fame": hall_ui.open()
		"hall_of_fame_scenario": hall_ui.open("scenario")
		"credits": credits_ui.open()
		"encyclopaedia": encyclopaedia_ui.open()
		"tutorial_adventure": start_tutorial()
		"tutorial_combat":
			_return_screen = "tutorial"
			combat_tutorial_requested.emit()

## Single game -> Tutorial -> Adventure: the tutorial map
## difficulty 0, outside any campaign; leaving it shows the Tutorial screen again.
## The Tutorial screen is shown again when the host next asks for "main".
func set_return_screen(target: String) -> void:
	_return_screen = target

func start_tutorial() -> void:
	_return_screen = "tutorial"
	campaign_requested.emit("el2", {"file_name": TUTORIAL_ADVENTURE, "script": TUTORIAL_ADVENTURE, "tutorial": true}, 0)

## Opens one extras screen for a host ("encyclopaedia" or "hall_of_fame";
## `kind` picks the Hall of Fame table).
func open_hosted(target: String, over_game: bool, kind := "") -> void:
	hosted = true
	_over_game = over_game
	_switch.hide()
	match target:
		"encyclopaedia": encyclopaedia_ui.open()
		"hall_of_fame": hall_ui.open(kind)
		"credits": credits_ui.open()
		# `kind` is the save kind of the running game; the host set
		# mission_load_ui.saver / current for the save mode.
		"save_game", "load_game":
			mission_load_ui.prepare("save" if target == "save_game" else "load", kind, true)
			show_screen(target)
		# `kind` is where it is shown: "adventure" or "combat" (combat page first).
		"options": options_ui.open(kind if not kind.is_empty() else "adventure", "combat" if kind == "combat" else "general")

## A question box alone over a running game (the quick load's
## T_MB_LOAD_GAME): OK leaves and runs `on_ok`; Cancel or Esc only leaves.
func ask_hosted(question: String, on_ok: Callable) -> void:
	_inform_ok = Callable()
	hosted = true
	_over_game = true
	_switch.hide()
	show_screen("question")
	duel_ui.show_message(question, func():
		leave_screen()
		on_ok.call(), true, 200.0, leave_screen)

## A message box with OK alone over a running game (the hot-seat hand-over
## box): OK, Enter, Space or Esc closes it and then runs `on_ok`.
func inform_hosted(message: String, on_ok: Callable) -> void:
	hosted = true
	_over_game = true
	_switch.hide()
	show_screen("question")
	_inform_ok = on_ok
	duel_ui.show_message(message, _close_inform)

func _close_inform() -> void:
	var done := _inform_ok
	_inform_ok = Callable()
	duel_ui.close_message()
	leave_screen()
	if done.is_valid(): done.call()

## Leaves an extras screen: back to the main menu, or to the host.
func leave_screen() -> void:
	if not hosted:
		show_screen("main")
		return
	hosted = false
	stop_audio()
	hosted_closed.emit()

func go_back() -> bool:
	if screen == "duel_editor":
		duel_ui.cancel_editor()
		return true
	if screen in ["duel_round", "duel_result"]: return false
	# Back from the hot-seat Duel screen returns to the connection menu.
	if screen == "duel" and duel_ui.hot_stage >= 0:
		duel_ui.leave_hot_seat()
		show_screen("mp_start")
		return true
	var target: String = SCREENS[edition][screen].get("back", "")
	# Between chapters the map steps back to the campaign menu, not the choice.
	if screen == "map" and _between_chapters(): target = "campaign_menu"
	if screen == "legend" and not _legend_next.is_empty() and _legend_next != "mission": target = _legend_next
	if target.is_empty(): return false
	if target == "main" and hosted: leave_screen()
	else: show_screen(target)
	return true

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	# Keys belong to the menu while it covers the game (Esc steps back).
	if event is InputEventKey:
		# An open message box answers its keys first.
		if event.pressed and not event.echo and duel_ui != null and duel_ui.message_key(event.keycode):
			get_viewport().set_input_as_handled()
			return
		# Text entry (the preset name) keeps its keys.
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit and focus.is_visible_in_tree() and event.keycode != KEY_ESCAPE: return
		get_viewport().set_input_as_handled()
		# Credits take every key (page turns, or any key closes).
		if screen == "credits":
			credits_ui.key(event)
			return
		if screen == "hall_of_fame":
			hall_ui.key(event)
			return
		if screen in ["blazon", "blazon_single"] and event.pressed and event.keycode != KEY_ESCAPE:
			blazon_ui.key(event.keycode)
			return
		if screen == "question" and _inform_ok.is_valid() and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			_close_inform()
			return
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			if screen == "encyclopaedia" and encyclopaedia_ui.escape(): return
			if screen == "options":
				options_ui.close()
				return
			if screen in SAVE_SCREENS and mission_load_ui.escape(): return
			if screen in REPLAY_SCREENS and replay_ui.escape(): return
			if screen == "question":
				duel_ui.close_message()
				leave_screen()
				return
			go_back()

# --- Shared panel helpers ----------------------------------------------------

func _square(control: String) -> CutButton:
	var button := CutButton.make(self, control, shift(control))
	if button == null: return null
	canvas.add_child(button)
	buttons[control] = button
	var tip: String = str(_controls.get(control, {}).get("ToolTip", ""))
	if not tip.is_empty() and text(tip) != tip: button.tooltip_text = text(tip)
	return button

func _label(key: String, value: String, rect: Rect2, size_px: int, color := TITLE_INK, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = false
	label.add_theme_font_override("font", serif)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	labels[key] = label
	return label

## Text control rectangle from the Controls registry, in the 1024 layout.
func control_rect(control: String) -> Rect2:
	var row: Dictionary = _controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + shift(control), Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

func _text_box(rect: Rect2, value: String, size_px := 17) -> RichTextLabel:
	text_box = RichTextLabel.new()
	text_box.bbcode_enabled = false
	text_box.text = value
	text_box.position = rect.position
	text_box.size = rect.size
	text_box.scroll_active = true
	text_box.add_theme_font_override("normal_font", serif)
	text_box.add_theme_font_size_override("normal_font_size", size_px)
	text_box.add_theme_color_override("default_color", BODY_INK)
	text_box.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	canvas.add_child(text_box)
	return text_box

func scroll_text(lines: int) -> void:
	if text_box == null: return
	var bar := text_box.get_v_scroll_bar()
	bar.value = clampf(bar.value + lines * 20.0, bar.min_value, bar.max_value)

## Front-end music (Resources/Music/<name>.mp3) at the music volume, repeating
## the whole track. It starts at once (a cut, no fade).
func play_music(name: String) -> bool:
	var path := profile.file("Resources/Music/" + name + ".mp3")
	if path.is_empty() or _audio == null: return false
	var stream := AudioStreamMP3.new()
	stream.data = FileAccess.get_file_as_bytes(path)
	stream.loop = true
	_play(stream, "music")
	_music_path = path
	return true

## One interface sound from the sound archive at the effects volume.
func play_sound(path: String) -> bool:
	var stream := ELAudio.sound(profile, path) if _audio != null else null
	if stream == null: return false
	_play(stream, "effects")
	return true

func _play(stream: AudioStream, channel: String) -> void:
	var preferences := option_settings() if settings != null else ELSettings.new()
	if settings == null:
		preferences.load_file(settings_path)
		preferences.use_edition(edition)
	_audio.stop()
	_music_path = ""
	_channel = channel
	_audio.stream = stream
	_audio.volume_db = _channel_db(preferences.values)
	_audio.play()

## Music sits at the level of the battle and map music.
func _channel_db(values: Dictionary) -> float:
	return linear_to_db(maxf(float(values.get(_channel, 0.0)), 0.0001)) - (6.0 if _channel == "music" else 0.0)

## Volume sliders changed while the menu plays.
func apply_volumes(values: Dictionary) -> void:
	ELUiSounds.use_volumes(values)
	if _audio != null and not _channel.is_empty(): _audio.volume_db = _channel_db(values)

## Remake setting "helper_overlay": remake-only English explanations.
func helper_overlay() -> bool:
	var values := option_settings()
	return values != null and bool(values.values.get("helper_overlay", false))

## A refusal the original has no text for: the explanation with the helper
## overlay, otherwise only the original Error sound.
func refuse(text: String, width := 300.0) -> void:
	if helper_overlay() and duel_ui != null: duel_ui.show_message(text, Callable(), false, width)
	elif profile != null: ELUiSounds.play(profile, ELUiSounds.ERROR)

## The preferences of the shown edition (the host's, or read from the file).
func option_settings() -> ELSettings:
	if settings == null:
		settings = ELSettings.new()
		settings.load_file(settings_path)
	settings.use_edition(edition)
	return settings

func preview_volumes(values: Dictionary) -> void:
	apply_volumes(values)
	settings_previewed.emit(values)

func stop_audio() -> void:
	_music_path = ""
	if _audio != null and _audio.playing: _audio.stop()

## The music file playing now ("" for none).
func music_path() -> String:
	return _music_path if _audio != null and _audio.playing else ""

func playing_interface() -> bool:
	return profile != null and not music_path().is_empty() and music_path() == profile.file("Resources/Music/interface.mp3")

## True while an opaque screen of the game's own menu holds the sound.
func music_owned() -> bool:
	return _music_owned

## Applies the interface-music contract to the screen now shown.
func sync_music() -> void:
	var owned := interface_music and not hosted and is_visible_in_tree() and not overlay()
	if owned != _music_owned:
		_music_owned = owned
		music_owner_changed.emit(owned)
	if not interface_music or hosted: return
	if not is_visible_in_tree():
		stop_audio()
		return
	if not owned:
		if playing_interface(): stop_audio()
		return
	if screen in ["credits", "hall_of_fame"] or playing_interface(): return
	play_music("interface")

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _audio != null:
		sync_music()
		if briefing != null and not is_visible_in_tree(): briefing.stop_voice()

func _campaign(id: String) -> ELCampaign:
	var data := ELCampaign.new()
	return data if data.load_campaign(profile, id) else null

# --- Campaign choice ---------------------------------------------------------

func _build_campaigns() -> void:
	if edition == "el1":
		_label("caption", text("CtrlSCCaption"), control_rect("SCCaption"), 17)
	else:
		_label("caption", text("CtrlSCHdr"), control_rect("SCHdr"), 17)
	for card: Dictionary in CARDS[edition]:
		var data := _campaign(card.id)
		if data == null: continue
		var button := CardButton.new()
		button.menu = self
		button.campaign = card.id
		button.pieces = []
		for part: Array in PORTRAITS[edition].get(card.id, []):
			var texture := texture_named(part[0])
			if texture != null: button.pieces.append({"texture": texture, "source": part[1], "at": part[2]})
		button.position = card.hole.position
		button.size = card.hole.size
		button.tooltip_text = data.title
		canvas.add_child(button)
		cards.append(button)
		button.pressed.connect(func():
			if edition == "el1" and selected_campaign != card.id: ELUiSounds.play(profile, "Buttons/swapcampaign.wav")
			select_campaign(card.id))
		button.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT: _confirm_campaign())
		var title: String = text(card.title) if card.has("title") else data.title
		_label("card_" + card.id, title, control_rect(card.name), 17)
		if card.has("caption"):
			var caption := _label("caption_" + card.id, data.title, control_rect(card.caption), 16, BODY_INK)
			caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var back := _square("SCBack")
	if back != null: back.pressed.connect(go_back)
	var start := _square("SCStart")
	if start != null:
		start.pressed.connect(_confirm_campaign)
		start.disabled = selected_campaign.is_empty()
	var info := _square("SCInfo")
	if info != null:
		info.disabled = selected_campaign.is_empty()
		info.pressed.connect(func(): _open_legend("campaigns"))
	if edition == "el1":
		# Every visit starts with no side chosen and Start disabled; coming
		# back from the blazon choice keeps the side.
		blazon_ui.build_campaign()
		if previous_screen != "blazon": selected_campaign = ""
		select_campaign(selected_campaign)
	elif selected_campaign.is_empty() and not cards.is_empty(): select_campaign(cards[0].campaign)
	else: select_campaign(selected_campaign)

func select_campaign(id: String) -> void:
	var previous := selected_campaign
	selected_campaign = id
	if edition == "el1" and blazon_ui != null: blazon_ui.side_chosen(previous, id)
	for card: CardButton in cards:
		card.chosen = card.campaign == id
		card.queue_redraw()
	for control: String in ["SCStart", "SCInfo"]:
		if buttons.has(control): buttons[control].disabled = id.is_empty()

func _confirm_campaign() -> void:
	if selected_campaign.is_empty(): return
	campaign_data = _campaign(selected_campaign)
	if campaign_data == null: return
	difficulty = 1
	if edition == "el1": _open_legend("mission")
	else:
		second = ELSecondCampaign.new_game(difficulty)
		ELSecondCampaign.begin(second, selected_campaign)
		show_screen("map")

## Second game: the global map for the chapter the progress points at, after a
## chapter result or when the between-chapter autosave is loaded.
func show_campaign_map(progress: Dictionary) -> bool:
	if not ELSecondCampaign.valid(progress) or str(progress.current).is_empty(): return false
	if edition != "el2" and not use_edition("el2"): return false
	var data := _campaign(str(progress.current))
	if data == null or int(progress.row) >= data.scenarios.size(): return false
	second = ELSecondCampaign.normalized(progress)
	campaign_data = data
	selected_campaign = data.id
	difficulty = int(second.difficulty)
	show_screen("map")
	return true

func _between_chapters() -> bool:
	return edition == "el2" and not second.is_empty() and (int(second.counter) > 0 or int(second.index) > 0 or not Dictionary(second.intermission).is_empty())

## Campaign legend: the campaign description on the CampaignText panel.
func _open_legend(next: String) -> void:
	if campaign_data == null or campaign_data.id != selected_campaign: campaign_data = _campaign(selected_campaign)
	if campaign_data == null: return
	_legend_next = next
	show_screen("legend")

func _build_legend() -> void:
	var body := campaign_data.description if campaign_data != null else ""
	if edition == "el2":
		_label("caption", text("CtrlCTHdr"), control_rect("CTHdr"), 17)
		_text_box(control_rect("CTScrollBounds"), body)
		for control: String in ["CTUp", "CTDown"]:
			var arrow := _square(control)
			if arrow != null: arrow.pressed.connect(scroll_text.bind(-3 if control == "CTUp" else 3))
	else:
		_label("caption", campaign_data.title if campaign_data != null else "", Rect2(297, 1, 435, 20), 17)
		# The first-game CTText control carries no rectangle; the text uses the
		# panel interior above the bottom bar.
		_text_box(Rect2(182, 136, 660, 470), body)
		if campaign_data != null and briefing != null:
			briefing.start(profile, ELBriefingVoice.campaign_file(campaign_data.guid), _effects_volume())
	var back := _square("CTBack")
	if back != null: back.pressed.connect(go_back)
	var ok := _square("CTOK")
	if ok != null: ok.pressed.connect(func():
		if _legend_next == "mission": show_screen("mission")
		else: show_screen(_legend_next))

# --- First game: mission description ----------------------------------------

func _build_mission() -> void:
	_label("caption", text("CtrlCICaption"), control_rect("CICaption"), 17)
	var scenario := _first_scenario()
	var header := _map_header(str(scenario.get("file_name", "")))
	var name_rect := control_rect("CIMissName")
	_label("mission_name", text(header.get("title", "")), name_rect, 18)
	var parts: Array[String] = []
	for key: String in ["description"]:
		if not header.get(key, "").is_empty(): parts.append(text(header[key]))
	for pair: Array in [["CtrlCIMissObj1", "objective"], ["CtrlCIMissWin1", "win_condition"], ["CtrlCIMissLose1", "lose_condition"]]:
		if not header.get(pair[1], "").is_empty(): parts.append(text(pair[0]) + "\n" + text(header[pair[1]]))
	_text_box(control_rect("CIMissDesc"), "\n\n".join(parts))
	for control: String in ["CIScrollRU", "CIScrollRD"]:
		var arrow := _square(control)
		if arrow != null: arrow.pressed.connect(scroll_text.bind(-3 if control == "CIScrollRU" else 3))
	for index in 5:
		var radio := _square("CIDiff%d" % (index + 1))
		if radio == null: continue
		radio.active = index == difficulty
		radio.pressed.connect(func(): set_difficulty(index))
	var start := _square("CIStart")
	if start != null: start.pressed.connect(start_campaign)
	if edition == "el1":
		_add_chapter_movie(scenario)
		if briefing != null: briefing.start(profile, ELBriefingVoice.mission_file(scenario), _effects_volume(), ELBriefingVoice.INFO_DELAY, text_box)

## First game: the chapter's own movie (`movie` of its campaign row, the
## campaign map drawing the route to it) plays once in the screen's left frame
## and stays on its last frame. Silent; no movie when the Video setting is off.
const CHAPTER_MOVIE_RECT := Rect2(163, 113, 346, 537)

func _add_chapter_movie(scenario: Dictionary) -> void:
	var movie := str(scenario.get("movie", ""))
	if movie.is_empty(): return
	var player := ELMoviePlayer.new()
	player.name = "ChapterMovie"
	player.embedded = true
	player.position = CHAPTER_MOVIE_RECT.position
	player.size = CHAPTER_MOVIE_RECT.size
	canvas.add_child(player)
	labels["chapter_movie"] = player
	player.play(ELMoviePlayer.item(profile, movie))

func _first_scenario() -> Dictionary:
	if edition == "el1" and not chapter.is_empty(): return chapter.duplicate()
	if campaign_data == null or campaign_data.scenarios.is_empty(): return {}
	if edition == "el2" and not second.is_empty() and second.current == campaign_data.id:
		second.difficulty = clampi(difficulty, 0, ELSecondCampaign.DIFFICULTIES - 1)
		return ELSecondCampaign.chapter(profile, second)
	var row: Dictionary = campaign_data.scenarios[0].duplicate()
	row.campaign = campaign_data.id
	if edition == "el1":
		# The typed name and chosen blazon go with the campaign.
		row.player_name = ELPlayerProfile.current_name(profile)
		row.logo = ELPlayerProfile.blazon.x
		row.colour = ELPlayerProfile.blazon.y
	return row

## Scenario header fields from the original map document.
func _map_header(map_id: String) -> Dictionary:
	var path := profile.file("Maps/" + map_id + ".map")
	if path.is_empty(): return {}
	var head := FileAccess.get_file_as_bytes(path).slice(0, 8192).get_string_from_ascii()
	var result := {}
	for key: String in ["title", "objective", "win_condition", "lose_condition", "description"]:
		var start := head.find("<" + key + ">")
		var stop := head.find("</" + key + ">")
		if start >= 0 and stop > start: result[key] = head.substr(start + key.length() + 2, stop - start - key.length() - 2).strip_edges()
	return result

## First game: the campaign info screen for the chapter that follows a chapter
## result (the scenario row carries its campaign), with the difficulty kept.
## A row with "branch_choices" (two candidate chapters) shows the branch
## choice first.
func show_chapter_info(scenario: Dictionary, chosen_difficulty: int) -> bool:
	if edition == "el1" and scenario.get("branch_choices", []).size() == 2:
		branch_ui.open(scenario.branch_choices, chosen_difficulty)
		return true
	if edition != "el1" or scenario.is_empty() or str(scenario.get("campaign", "")).is_empty(): return false
	campaign_data = _campaign(str(scenario.campaign))
	if campaign_data == null: return false
	selected_campaign = campaign_data.id
	difficulty = clampi(chosen_difficulty, 0, 4)
	chapter = scenario.duplicate()
	show_screen("mission")
	return true

func _effects_volume() -> float:
	var preferences := option_settings() if settings != null else ELSettings.new()
	if settings == null:
		preferences.load_file(settings_path)
		preferences.use_edition(edition)
	return float(preferences.values.get("effects", 1.0))

func set_difficulty(index: int) -> void:
	difficulty = index
	for control: String in buttons:
		if control.begins_with("CIDiff") or control.begins_with("GMA6Diff"):
			buttons[control].active = int(control.right(1)) - 1 == index

func start_campaign() -> void:
	var scenario := _first_scenario()
	if scenario.is_empty(): return
	campaign_requested.emit(edition, scenario, difficulty)

# --- Second game: campaign map -------------------------------------------------

func _build_map() -> void:
	var scenario := _first_scenario()
	_label("caption", text(str(scenario.get("header", "CtrlGMA6Header"))), control_rect("GMA6Header"), 18)
	var clip_rect := control_rect("GMA6MapClip")
	var bytes := profile.read("textures", "interface/globalmap/globalmap.mmp")
	var image := Image.new()
	# The world map is stored as a plain BMP inside the texture archive.
	if not bytes.is_empty() and image.load_bmp_from_buffer(bytes) == OK:
		var map := MapView.new()
		map.map = ImageTexture.create_from_image(image)
		map.position = clip_rect.position
		map.size = clip_rect.size
		map.clip_contents = true
		map.marker = Vector2(float(scenario.get("map_x", 0)), float(scenario.get("map_y", 0)))
		var symbols := profile.texture("Interface/world_symbols_map")
		if symbols != null and MAP_FIGURES.has(campaign_data.id):
			map.figure = symbols
			map.figure_rect = MAP_FIGURES[campaign_data.id]
		map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(map)
		labels["map"] = map
	var back := _square("GMA6Back")
	if back != null: back.pressed.connect(go_back)
	for index in 3:
		var radio := _square("GMA6Diff%d" % (index + 1))
		if radio == null: continue
		radio.active = index == difficulty
		radio.pressed.connect(func(): set_difficulty(index))
	var briefing := _square("GMA6Briefing")
	if briefing != null: briefing.pressed.connect(_open_briefing)
	var start := _square("GMA6Start")
	if start != null: start.pressed.connect(start_campaign)

func _open_briefing() -> void:
	var scenario := _first_scenario()
	show_screen("legend")
	labels.caption.text = text(str(scenario.get("header", "")))
	text_box.text = text(str(scenario.get("briefing", "")))
	_legend_next = "map"

## Original multi-part text button: left cap, stretched middle, right cap,
## pressed variant and lit overlay, with the caption from the text tables.
class TextButton extends BaseButton:
	var menu: ELFrontMenu
	var caption := ""
	var font_size := 24
	var states: Dictionary = {}
	var design_left := 375.0

	static func make(owner: ELFrontMenu, control: String, width: float, size_px: int) -> TextButton:
		var lefts := owner.rows(control, ["Free", "Type5"], ["Light"])
		if lefts.is_empty(): return null
		var button := TextButton.new()
		button.menu = owner
		button.name = control
		button.caption = owner._caption(control)
		button.font_size = size_px
		button.focus_mode = Control.FOCUS_NONE
		ELUiSounds.bind(button, owner.profile, control)
		button.design_left = float(lefts[0].ScrL)
		for state: String in ["normal", "pressed", "hover", "hover_pressed"]:
			var required: Array = {"normal": ["Free"], "pressed": ["Push"], "hover": ["Free", "Light"], "hover_pressed": ["Push", "Light"]}[state]
			var excluded: Array = [] if state.begins_with("hover") else ["Light"]
			var parts: Array[Dictionary] = []
			for type: String in ["Type5", "Type6", "Type7"]:
				var found := owner.rows(control, required + [type], excluded)
				if found.is_empty(): continue
				var piece := owner.cut(found[0])
				if piece.is_empty(): continue
				piece.type = type
				parts.append(piece)
			button.states[state] = parts
		var offset := owner.shift(control)
		button.size = Vector2(width, 57)
		button.position = Vector2(roundf((DESIGN.x - width) * 0.5), float(lefts[0].ScrT) + offset.y)
		return button

	func _draw() -> void:
		var mode := get_draw_mode()
		var pushed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var tint := Color(0.6, 0.6, 0.6) if disabled else Color.WHITE
		_draw_parts(states.get("pressed" if pushed else "normal", []), tint)
		if not disabled and (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED):
			_draw_parts(states.get("hover_pressed" if pushed else "hover", []), Color.WHITE)
		var color := INK_DISABLED if disabled else (INK_HOVER if mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED else INK)
		var text_size := menu.serif.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := (size.y - text_size.y) * 0.5 + menu.serif.get_ascent(font_size) + (1.0 if pushed else 0.0)
		var at := Vector2((size.x - text_size.x) * 0.5, baseline)
		draw_string(menu.serif, at + Vector2(1, 1), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.85))
		draw_string(menu.serif, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	## Caps keep their size and distance from the edges; the middle stretches.
	func _draw_parts(parts: Array, tint: Color) -> void:
		var right_edge := design_left + 140.0
		for part: Dictionary in parts:
			var rect: Rect2 = part.rect
			var x: float = rect.position.x - design_left
			var width: float = rect.size.x
			if part.type == "Type6": width += size.x - 140.0
			elif part.type == "Type7": x = size.x - (right_edge - rect.position.x)
			draw_texture_rect_region(part.texture, Rect2(Vector2(x, rect.position.y - position.y + _top_shift()), Vector2(width, rect.size.y)), part.source, tint)

	func _top_shift() -> float:
		return menu.shift(name).y

## Square original button (back, confirm, radio, scroll arrows).
class CutButton extends BaseButton:
	var parts: Dictionary = {}
	var active := false:
		set(value):
			active = value
			queue_redraw()
	var _origin := Vector2.ZERO

	static func make(owner: ELFrontMenu, control: String, offset: Vector2) -> CutButton:
		var free := owner.rows(control, ["Free"], ["Light"])
		var all := owner.rows(control)
		if all.is_empty(): return null
		var button := CutButton.new()
		button.name = control
		button.focus_mode = Control.FOCUS_NONE
		ELUiSounds.bind(button, owner.profile, control)
		# Some rows carry no Free/Push mask (scroll arrows list Free/Push/Light).
		# A state may be composed of several pieces with identical masks (the race
		# sort button's four quarters); pieces at the same position are alternatives.
		var pick := func(required: Array, excluded: Array) -> Dictionary:
			var found := owner.rows(control, required, excluded)
			if found.is_empty(): return {}
			var head := owner.cut(found[0], offset)
			if head.is_empty(): return {}
			var extra: Array = []
			var seen := [head.rect.position]
			for row: Dictionary in found.slice(1):
				if row.masks.size() != found[0].masks.size() or not row.masks.all(func(m: Variant): return found[0].masks.has(m)): continue
				var piece := owner.cut(row, offset)
				if piece.is_empty() or seen.has(piece.rect.position): continue
				seen.append(piece.rect.position)
				extra.append(piece)
			head.extra = extra
			return head
		button.parts = {"normal": pick.call(["Free"], ["Light"]), "pressed": pick.call(["Push"], ["Light"]),
			"hover": pick.call(["Light", "Free"], []), "hover_pressed": pick.call(["Light", "Push"], [])}
		if button.parts.hover.is_empty(): button.parts.hover = pick.call(["Light"], [])
		if button.parts.hover_pressed.is_empty(): button.parts.hover_pressed = button.parts.hover
		if free.is_empty() and button.parts.normal.is_empty(): button.parts.normal = owner.cut(all[0], offset)
		var bounds := Rect2()
		var first := true
		for part: Dictionary in button.parts.values():
			if part.is_empty(): continue
			for piece: Dictionary in [part] + part.get("extra", []):
				bounds = piece.rect if first else bounds.merge(piece.rect)
				first = false
		button._origin = bounds.position
		button.position = bounds.position
		button.size = bounds.size
		return button

	func _draw() -> void:
		var mode := get_draw_mode()
		var pushed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED or active
		var base: Dictionary = parts.get("pressed", {}) if pushed and not parts.get("pressed", {}).is_empty() else parts.get("normal", {})
		var tint := Color(0.5, 0.5, 0.5) if disabled else Color.WHITE
		_piece(base, tint)
		if not disabled and (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED):
			_piece(parts.get("hover_pressed", {}) if pushed else parts.get("hover", {}), Color.WHITE)

	func _piece(part: Dictionary, tint: Color) -> void:
		if part.is_empty(): return
		for piece: Dictionary in [part] + part.get("extra", []):
			draw_texture_rect_region(piece.texture, Rect2(piece.rect.position - _origin, piece.rect.size), piece.source, tint)

## Campaign portrait card; the chosen card is shown at full brightness.
class CardButton extends BaseButton:
	var menu: ELFrontMenu
	var campaign := ""
	var pieces: Array = []
	var chosen := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var picture := Vector2(0, 0)
		for piece: Dictionary in pieces: picture.x = maxf(picture.x, piece.at.x + piece.source.size.x)
		for piece: Dictionary in pieces: picture.y = maxf(picture.y, piece.at.y + piece.source.size.y)
		var origin := ((size - picture) * 0.5).floor()
		var hover := get_draw_mode() == DRAW_HOVER or get_draw_mode() == DRAW_HOVER_PRESSED
		var tint := Color.WHITE if chosen or hover else Color(0.55, 0.55, 0.55)
		for piece: Dictionary in pieces:
			draw_texture_rect_region(piece.texture, Rect2(origin + piece.at, piece.source.size), piece.source, tint)

## Second-game world map with the campaign hero standing at the mission.
class MapView extends Control:
	var map: Texture2D
	var figure: Texture2D
	var figure_rect := Rect2()
	var marker := Vector2.ZERO

	func _draw() -> void:
		if map == null: return
		# Keep the mission in view when the map is wider than its clip.
		var offset := clampf(marker.x - size.x * 0.5, 0, maxf(0, map.get_width() - size.x))
		draw_texture_rect_region(map, Rect2(Vector2.ZERO, size), Rect2(Vector2(offset, 0), size))
		if figure != null and figure_rect.size.x > 0:
			var at := Vector2(marker.x - offset - figure_rect.size.x * 0.5, marker.y - figure_rect.size.y)
			draw_texture_rect_region(figure, Rect2(at.round(), figure_rect.size), figure_rect)
