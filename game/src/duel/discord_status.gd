class_name ELDiscordStatus
extends RefCounted
## What the Discord activity says (see ELDiscordPresence): the game and the
## mode on the first line, what is happening in it on the second, both in
## the language of the remake's own screens (ELRemakeText).
##
## Read from the battle view's own fields every couple of seconds; nothing is
## kept between calls. Shown: the menu screen; on a map the kind of game, the
## mission, the day and the hero (or the screen open over the map); in a
## battle its kind, the opponent where it is a character of the game, the
## turn and both heroes' life; the remake's modes with their progress; the
## wiki article being read. Never shown: player names (hot seat, online,
## the player profile), hero preset names and save names.
##
## Each activity also names its scene: the activity's elapsed time counts
## from the moment the scene began. A battle on a map names the map as its
## parent scene, so the map's time continues after the battle.

## Menu screens of both games (ELFrontMenu.SCREENS) and what the player does
## there; screens left out show the main menu alone.
const MENU_SCREENS := {
	"load": "Loading a saved game", "load_campaign": "Loading a saved game", "load_mission": "Loading a saved game",
	"load_strategy": "Loading a saved game", "load_game": "Loading a saved game", "save_game": "Saving the game",
	"campaigns": "Choosing a campaign", "campaign_menu": "Choosing a campaign", "legend": "Choosing a campaign",
	"map": "Choosing a campaign", "mission": "Choosing a campaign", "blazon": "Choosing a campaign",
	"branch": "Choosing a campaign branch",
	"select_mission": "Choosing a mission", "mission_menu": "Choosing a mission", "blazon_single": "Choosing a mission",
	"duel": "Setting up a duel", "duel_menu": "Setting up a duel", "duel_editor": "Editing a hero",
	"duel_round": "Duel results", "duel_result": "Duel results",
	"mp_type": "Multiplayer", "mp_start": "Multiplayer", "mp_start_strategy": "Multiplayer",
	"hall_of_fame": "Hall of Fame", "credits": "Credits", "options": "Options", "encyclopaedia": "Encyclopaedia",
	"tutorial": "Tutorial", "replay_load": "Choosing a replay", "replay_save": "Saving a replay",
	"objectives": "Mission objectives",
}
## Expedition phases (ELExpeditionRun.phase) worth a word of their own.
const EXPEDITION_PHASES := {"shop": "Shop", "won": "Victory", "lost": "Defeat"}

## The activity for `view` (ELDuelView): a dictionary from
## ELDiscordPresence.activity, or {} for none.
static func describe(view: Node) -> Dictionary:
	var shown: ELProfile = view.call("_shown_profile")
	var t := func(text: String) -> String: return ELRemakeText.t(text, shown)
	var current: ELProfile = view.get("profile")
	var game: String = t.call(ELContentLibrary.title(current.id)) if current != null else ("Демиурги" if ELRemakeText.language(shown) == "ru" else "Demiurges")
	var found := _scene(view, t, game)
	_overlays(view, t, game, found)
	var presence: ELDiscordPresence = view.get("discord")
	return presence.activity(ELDiscordPresence.fitting(found.details), ELDiscordPresence.fitting(found.state), str(found.scene), str(found.get("parent", "")))

## The screen or scene under any overlay: {details, state (Arrays of
## parts), scene, parent}.
static func _scene(view: Node, t: Callable, game: String) -> Dictionary:
	if view.get("content_setup") != null:
		return {"details": [game], "state": [t.call("Setting up game files")], "scene": "setup"}
	if view.get("movie_player") != null:
		return {"details": [game], "state": [t.call("Watching a video")], "scene": "video"}
	for child: Node in view.get_children():
		if child is CanvasLayer and child.visible and String(child.name).contains("ChapterLoading"):
			return {"details": [game], "state": [t.call("Loading…")], "scene": "loading"}
	var lobby: Window = view.get("_network_lobby")
	if lobby != null and (lobby.visible or bool(view.get("_network_editor_open"))):
		var link: ELNetworkDuel = view.get("network_duel")
		var waiting := link != null and not link.live
		return {"details": [game, t.call("Network duel")], "state": [t.call("Waiting for an opponent" if waiting else "In the lobby")], "scene": "duel-lobby"}
	var strategic_lobby: Window = view.get("_strategic_lobby")
	if strategic_lobby != null and strategic_lobby.visible:
		var waiting := bool(strategic_lobby.get("_waiting"))
		return {"details": [game, t.call("Network strategy")], "state": [t.call("Waiting for an opponent" if waiting else "In the lobby")], "scene": "strategy-lobby"}
	var autochess_layer: CanvasLayer = view.get("_autochess_layer")
	if autochess_layer != null and autochess_layer.visible: return _autochess(view, t, game)
	var arena_screen: Control = view.get("_arena_screen")
	if arena_screen != null and arena_screen.visible: return _arena(view, t, game)
	var expedition_screen: Control = view.get("_expedition_screen")
	if expedition_screen != null and expedition_screen.visible: return _expedition(view, t, game)
	var puzzles: ELPuzzleMode = view.get("puzzle_mode")
	if puzzles != null:
		var list: Control = puzzles.get("_list")
		if list != null and list.visible:
			return {"details": [game, t.call("Puzzles")], "state": [t.call("Choosing a puzzle")], "scene": "puzzles"}
	var front: ELFrontMenu = view.get("front_menu")
	if front != null and front.is_visible_in_tree() and not front.hosted:
		var screen_text := str(MENU_SCREENS.get(front.screen, ""))
		if front.screen == "single" and front.edition == "el1": screen_text = "Choosing a mission"
		return {"details": [game, t.call("Main menu")], "state": [t.call(screen_text)] if not screen_text.is_empty() else [], "scene": "menu"}
	var map: ELAdventureView = view.get("campaign_view")
	if map != null and map.visible and map.state != null and map.state.map != null: return _map(view, map, t)
	var duel: ELDuel = view.get("duel")
	var stage: Node3D = view.get("stage")
	if duel != null and stage != null and stage.visible: return _battle(view, duel, t, game)
	var setup: Control = view.get("setup_panel")
	if setup != null and setup.visible:
		return {"details": [game, t.call("Main menu")], "state": [t.call("Setting up a duel")], "scene": "menu"}
	var campaign_setup: Control = view.get("campaign_setup")
	if campaign_setup != null and campaign_setup.visible:
		return {"details": [game, t.call("Main menu")], "state": [t.call("Choosing a campaign")], "scene": "menu"}
	return {"details": [game, t.call("Main menu")], "state": [], "scene": "menu"}

## Screens over the scene change the words, not the scene (or its time).
static func _overlays(view: Node, t: Callable, game: String, found: Dictionary) -> void:
	var front: ELFrontMenu = view.get("front_menu")
	if front != null and front.is_visible_in_tree() and front.hosted:
		var screen_text := str(MENU_SCREENS.get(front.screen, ""))
		if not screen_text.is_empty(): found.state = [t.call(screen_text)]
	var options: Node = view.get("options_host")
	var dialog: Window = view.get("settings_dialog")
	if (options is CanvasItem and options.is_visible_in_tree()) or (dialog != null and dialog.visible):
		found.state = [t.call("Options")]
	if ELWikiScreen.is_open():
		var wiki := ELWikiScreen.instance
		var article := str(wiki.call("_entry", wiki.page).get("title", "")) if wiki.has_method("_entry") else ""
		found.details = [game, t.call("Wiki")]
		found.state = [article] if not article.is_empty() and wiki.page != "home" else []

## The adventure map: the kind of game and the mission, then the day and the
## hero, or the screen open over the map.
static func _map(view: Node, map: ELAdventureView, t: Callable) -> Dictionary:
	var state := map.state
	var edition := state.map.profile.id
	var game: String = t.call(ELContentLibrary.title(edition))
	var mode := "Mission"
	if map.strategic_session != null: mode = "Network strategy"
	elif state.tutorial: mode = "Tutorial"
	elif ELFirstRandomMap.is_random_id(state.map.id): mode = "Random map"
	elif _campaign(state): mode = "Campaign"
	var parts: Array = []
	var mission := state.map.title.strip_edges()
	if not mission.is_empty(): parts.append(mission)
	parts.append(t.call("Day %d") % (state.day + 1 if edition == "el2" else state.day))
	var doing := ""
	if map.win_lose != null: doing = "Mission lost" if map.result_kind == "lost" else "Mission won"
	elif map.movie != null and map.movie.playing(): doing = "Watching a video"
	elif map.hero_screen != null: doing = "Hero screen"
	elif map.building_screen != null: doing = "Managing buildings"
	elif map.shop != null or map.first_shop != null: doing = "Buying spells"
	elif map.rune_shop != null: doing = "Buying runes"
	elif map.spellbook != null: doing = "Spellbook"
	elif map.skills != null: doing = "Skills"
	elif map.global_spells != null: doing = "Global spells"
	elif map.diplomacy != null: doing = "Diplomacy"
	elif map.notebook != null: doing = "Notebook"
	if not doing.is_empty(): parts.append(t.call(doing))
	else:
		var hero := state.object(map.call("_hero_id")) if map.has_method("_hero_id") else {}
		var title := str(hero.get("title", "")).strip_edges()
		if not title.is_empty(): parts.append(t.call("%s, level %d") % [title, int(hero.get("level", 1))])
	return {"details": [game, t.call(mode)], "state": parts, "scene": "map:%d" % map.get_instance_id()}

## A battle on the battle stage: its kind (with the opponent where that is a
## character of the game), then the turn and the life of both heroes, the
## player's own first.
static func _battle(view: Node, duel: ELDuel, t: Callable, game: String) -> Dictionary:
	var details: Array = [game]
	var parts: Array = []
	var parent := ""
	# The player's side when exactly one side is the player's; both (hot seat)
	# or neither (a watched battle) show side 0 first and no winner's word.
	var mine_first: bool = view.call("_local_side", 0) if view.has_method("_local_side") else true
	var mine_second: bool = view.call("_local_side", 1) if view.has_method("_local_side") else false
	var me := 1 if mine_second and not mine_first else 0
	var decisive := mine_first != mine_second and not bool(view.get("demo"))
	var turn: String = t.call("Turn %d") % duel.round_number
	var map: ELAdventureView = view.get("campaign_view")
	var replay: ELDuelReplayPlayer = view.get("replay_player")
	var puzzles: ELPuzzleMode = view.get("puzzle_mode")
	var link: ELNetworkDuel = view.get("network_duel")
	var match_state: ELDuelMatch = null
	var arena_run: ELArenaRun = view.get("arena_run")
	var expedition_run: ELExpeditionRun = view.get("expedition_run")
	if replay != null and replay.duel == duel: details.append(t.call("Duel replay"))
	elif view.get("combat_tutorial") != null: details.append(t.call("Combat tutorial"))
	elif puzzles != null and puzzles.active() and puzzles.duel() == duel:
		details.append(t.call("Puzzle: %s") % puzzles.run.title())
		turn = t.call("Turn %d of %d") % [clampi(puzzles.run.turn, 1, maxi(1, puzzles.run.allowed)), puzzles.run.allowed]
	elif view.has_method("_strategic_battle") and view.call("_strategic_battle"):
		details.append(t.call("Strategy battle"))
		if map != null: parent = "map:%d" % map.get_instance_id()
	elif map != null and view.has_method("_campaign_battle") and view.call("_campaign_battle") == duel:
		parent = "map:%d" % map.get_instance_id()
		var encounter := map.director.encounter
		var opponent := str(duel.heroes[1 - me].get("title", "")).strip_edges()
		if encounter != null and encounter.map_ai_duel: details.append(t.call("Watching a battle"))
		elif opponent.is_empty(): details.append(t.call("Campaign battle"))
		elif _campaign(map.state): details.append(t.call("Campaign battle vs %s") % opponent)
		else: details.append(t.call("Battle vs %s") % opponent)
	elif arena_run != null and view.get("_arena_battle") == duel:
		parent = "arena"
		var opponent := str(arena_run.opponent.get("name", "")).strip_edges()
		details.append(t.call("Arena battle vs %s") % opponent if not opponent.is_empty() else t.call("Draft Arena"))
		parts.append(t.call("Wins %d · Losses %d") % [arena_run.wins, arena_run.losses])
	elif expedition_run != null and view.get("_expedition_battle") == duel:
		parent = "expedition"
		details.append(t.call("Expedition battle"))
		parts.append(t.call("Act %d") % expedition_run.act)
	elif link != null and link.live:
		details.append(t.call("Network duel"))
		match_state = link.match_state
	elif bool(view.get("demo")): details.append(t.call("Watching a battle"))
	elif view.get("duel_match") != null:
		match_state = view.get("duel_match")
		details.append(t.call("Duel (hot seat)" if match_state.hot_seat else "Duel vs AI"))
	else:
		var modes: OptionButton = view.get("mode_select")
		details.append(t.call("Duel (hot seat)" if modes != null and modes.selected == 1 else "Practice duel"))
	if match_state != null and match_state.rounds > 1:
		details.append(t.call("Round %d of %d") % [clampi(match_state.played + 1, 1, match_state.rounds), match_state.rounds])
	if duel.phase == ELDuel.Phase.FINISHED:
		parts.push_front(t.call("Battle over") if duel.winner < 0 or not decisive else t.call("Victory" if duel.winner == me else "Defeat"))
	else:
		var mine: int = view.call("shown_health", me) if view.has_method("shown_health") else int(duel.heroes[me].health)
		var theirs: int = view.call("shown_health", 1 - me) if view.has_method("shown_health") else int(duel.heroes[1 - me].health)
		parts.push_front(t.call("Life %d – %d") % [mine, theirs])
		parts.push_front(turn)
	return {"details": details, "state": parts, "scene": "battle:%d" % duel.get_instance_id(), "parent": parent}

## Autochess (Etherlords II): the landing, loading, or a match with its round
## and the heroes still in it.
static func _autochess(view: Node, t: Callable, game: String) -> Dictionary:
	var lobby: Control = view.get("_autochess_lobby")
	var screen: ELAutochessScreen = view.get("_autochess_screen")
	var online := (lobby != null and lobby.visible and bool(lobby.get("_online_page"))) or (screen != null and screen.online != null)
	var details: Array = [game, t.call("Online autochess" if online else "Autochess")]
	if lobby != null and lobby.visible: return {"details": details, "state": [t.call("In the lobby")], "scene": "autochess"}
	if screen == null or not screen.loaded_all: return {"details": details, "state": [t.call("Loading…")], "scene": "autochess"}
	if screen.game == null: return {"details": details, "state": [], "scene": "autochess"}
	var parts: Array = [t.call("Round %d") % screen.game.round_number, t.call("%d heroes left") % screen.game.alive_players().size()]
	return {"details": details, "state": parts, "scene": "autochess:%d" % screen.game.get_instance_id(), "parent": "autochess"}

## Draft Arena (Etherlords II) between its battles.
static func _arena(view: Node, t: Callable, game: String) -> Dictionary:
	var run: ELArenaRun = view.get("arena_run")
	var parts: Array = []
	if run != null:
		match run.phase:
			"hero", "spec", "artifact": parts.append(t.call("Choosing a hero"))
			"draft": parts.append(t.call("Drafting a deck"))
			_: parts.append(t.call("Wins %d · Losses %d") % [run.wins, run.losses])
	return {"details": [game, t.call("Draft Arena")], "state": parts, "scene": "arena"}

## Expedition (Etherlords II) between its battles: the act and the hero's
## life, and the shop or the run's end.
static func _expedition(view: Node, t: Callable, game: String) -> Dictionary:
	var run: ELExpeditionRun = view.get("expedition_run")
	var parts: Array = []
	if run != null:
		parts.append(t.call("Act %d") % run.act)
		if run.max_health > 0: parts.append(t.call("Life %d / %d") % [run.health, run.max_health])
		if EXPEDITION_PHASES.has(run.phase): parts.append(t.call(EXPEDITION_PHASES[run.phase]))
	return {"details": [game, t.call("Expedition")], "state": parts, "scene": "expedition"}

## Whether the map is a chapter of a campaign: the first game's campaign
## flag, or the second game's carried campaign progress.
static func _campaign(state: ELAdventureSession) -> bool:
	if state.map.profile.id == "el1": return bool(state.scenario.get("campaign", false))
	return state.scenario.has(ELSecondCampaign.KEY)
