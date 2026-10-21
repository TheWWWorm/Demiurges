class_name ELSecondCampaign
extends RefCounted
## Second-game campaign shell: the campaign and chapter being played, the
## intermission block carried from one chapter to the next, and the order in
## which campaigns open. Plain JSON-safe data, kept in the chapter session's
## `scenario` and in the between-chapter autosave. The first game keeps its own
## chapter progress (ELFirstScenario); nothing here applies to it.
##
## Original behaviour (EL2 CCampaignState):
## - a new game offers Green and Red; after Green comes Black, after Red Blue,
##   then White; after White the campaign is finished;
## - a won chapter that is not the campaign's last captures the intermission,
##   advances the sequential index and picks the next row: the persistent
##   script variable NextMission when present and >= 0, else the index
## the last chapter opens the next campaign,
##   which starts without intermission data;
## - at chapter start the intermission is applied (wallet, main hero,
##   persistent variables), White row 1 first resets the hero's
##   experience and level, then PrevCampaign is set persistently

const VERSION := 1
const KEY := "el2_campaign"
const CAMPAIGNS := ["Green", "Red", "Blue", "Black", "White"]
const FIRST := ["Green", "Red"]
const SECOND := {"Green": "Black", "Red": "Blue"}
const FINAL := "White"
## Second-game maps author three difficulty variants (DifLvl 0-2, GMA6Diff1-3).
const DIFFICULTIES := 3
const MAX_ROWS := 16
const AUTOSAVE := "user://campaign-autosave.json"
const AUTOSAVE_FORMAT := "etherlords-el2-campaign"
## Main-hero fields carried in the intermission (original capture:
## exp, lost_exp, level, reach_lev, specs, hand and bag spells, artefacts and
## blank count, skills). The remake's names: experience, experience_penalty,
## level, level_history, specialization(s), cards, spell_stock, artifacts,
## artefact_blank_count, skills; pending skill choices travel with the level.
const HERO_FIELDS := ["experience", "experience_penalty", "level", "level_history", "skill_points", "skill_offers", "skill_seed", "skills",
	"specialization", "specializations", "cards", "spell_stock", "artifacts", "artefact_blank_count"]

static func new_game(difficulty := 1) -> Dictionary:
	return {"version": VERSION, "counter": 0, "possible": FIRST.duplicate(), "current": "", "prev": "", "index": 0, "row": 0,
		"difficulty": clampi(difficulty, 0, DIFFICULTIES - 1), "intermission": {}, "finished": false}

## Starts one of the offered campaigns at its first chapter with no carried data.
static func begin(data: Dictionary, campaign_id: String) -> bool:
	if bool(data.get("finished", false)) or not Array(data.get("possible", [])).has(campaign_id): return false
	data.current = campaign_id
	data.index = 0
	data.row = 0
	data.played = []
	data.intermission = {}
	return true

## Progress for a chapter chosen directly (remake chapter list): its campaign's
## place in the unlock order, the chapter's row, and no carried data.
static func for_chapter(profile: ELProfile, campaign_id: String, scenario: Dictionary, difficulty := 1) -> Dictionary:
	if not CAMPAIGNS.has(campaign_id): return {}
	var campaign := ELCampaign.new()
	if not campaign.load_campaign(profile, campaign_id): return {}
	var row := -1
	for index in campaign.scenarios.size():
		var entry: Dictionary = campaign.scenarios[index]
		if entry.get("file_name") == scenario.get("file_name") and str(entry.get("script", "")).to_lower() == str(scenario.get("script", "")).to_lower():
			row = index
			break
	if row < 0: return {}
	var data := new_game(difficulty)
	data.counter = 0 if FIRST.has(campaign_id) else (2 if campaign_id == FINAL else 1)
	data.possible = [campaign_id]
	for first: String in SECOND:
		if SECOND[first] == campaign_id: data.prev = first
	begin(data, campaign_id)
	data.index = row
	data.row = row
	return data

## Row of the chapter that follows: a persistent NextMission >= 0 carried in
## the intermission, otherwise the sequential index. A value outside the
## campaign (not authored by any script) falls back to the index.
static func next_row(data: Dictionary, count: int) -> int:
	var value: Variant = Dictionary(data.get("intermission", {})).get("variables", {}).get("NextMission")
	if (value is int or value is float) and int(value) >= 0 and int(value) < count: return int(value)
	return int(data.index)

## Records a won chapter. Returns "chapter" when the campaign continues,
## "campaign" when the next campaign opened, "finished" after the last one.
static func complete_chapter(data: Dictionary, intermission: Dictionary, count: int) -> String:
	if int(data.index) + 1 < count:
		# The rows played so far (the campaign map draws their journey).
		data.played = Array(data.get("played", [])) + [int(data.row)]
		data.intermission = intermission.duplicate(true)
		data.index = int(data.index) + 1
		data.row = next_row(data, count)
		return "chapter"
	return next_campaign(data)

static func next_campaign(data: Dictionary) -> String:
	data.counter = int(data.counter) + 1
	var possible: Array = []
	match int(data.counter):
		1: if SECOND.has(data.current): possible = [SECOND[data.current]]
		2: possible = [FINAL]
	data.prev = data.current
	data.current = ""
	data.index = 0
	data.row = 0
	data.played = []
	data.intermission = {}
	data.possible = possible
	if possible.is_empty():
		data.finished = true
		return "finished"
	# Only one campaign is offered after the first; it starts at its first chapter.
	begin(data, possible[0])
	return "campaign"

## Intermission block from a won chapter: the human player's wallet, the main
## hero's carried fields and the script variables marked persistent.
static func capture(state: ELAdventureSession) -> Dictionary:
	var result := {"wallet": {}, "hero": {}, "variables": {}, "notebook": ELSecondNotebook.carry(state)}
	if state.players.has(state.current_player): result.wallet = Dictionary(state.players[state.current_player].get("resources", {})).duplicate(true)
	var hero := state.object(state.main_hero)
	for field: String in HERO_FIELDS:
		if hero.has(field): result.hero[field] = _plain(hero[field])
	var variables := state.persistent_variables()
	for key: Variant in variables:
		var value: Variant = variables[key]
		if key is String and (value is String or value is bool or value is int or value is float): result.variables[key] = value
	return result

## Chapter start: applies the carried block, then PrevCampaign (persistent),
## and keeps the progress on the session. Runs after the chapter's script has
## loaded and before its first step.
static func start_chapter(state: ELAdventureSession, data: Dictionary) -> String:
	if not valid(data) or str(data.current).is_empty(): return "Invalid campaign progress."
	var block: Dictionary = Dictionary(data.intermission).duplicate(true)
	if not block.is_empty():
		if data.current == FINAL and int(data.row) == 1:
			# the Avatar starts White's second chapter at level one.
			var hero_block: Dictionary = block.get("hero", {})
			hero_block.merge({"experience": 0, "experience_penalty": 0.0, "level": 1, "level_history": 1}, true)
			block.hero = hero_block
		apply(state, block)
	state.set_variable("PrevCampaign", str(data.prev), true)
	state.scenario[KEY] = data.duplicate(true)
	return ""

static func apply(state: ELAdventureSession, block: Dictionary) -> void:
	var wallet: Variant = block.get("wallet", {})
	if wallet is Dictionary and not wallet.is_empty() and state.players.has(state.current_player):
		var resources: Dictionary = state.players[state.current_player].resources
		#  assigns the carried amounts; the map's starting balance is replaced.
		for key: Variant in wallet:
			if resources.has(key): resources[key] = int(wallet[key])
		state.event.emit({"kind": "resources_changed", "player": state.current_player})
	var hero := state.object(state.main_hero)
	var carried: Dictionary = block.get("hero", {})
	if not hero.is_empty() and not carried.is_empty():
		for field: String in HERO_FIELDS:
			if carried.has(field): hero[field] = _plain(carried[field])
		for field: String in ["level", "level_history", "skill_points", "artefact_blank_count"]:
			if hero.has(field): hero[field] = int(hero[field])
		if hero.has("experience"): hero.experience = int(hero.experience)
		if hero.has("experience_penalty"): hero.experience_penalty = float(hero.experience_penalty)
		for code: Variant in hero.get("skills", {}): hero.skills[code] = int(hero.skills[code])
		for code: Variant in hero.get("spell_stock", {}): hero.spell_stock[code] = int(hero.spell_stock[code])
		for item: Variant in hero.get("artifacts", []):
			if item is Dictionary and item.has("charges"): item.charges = int(item.charges)
		# Generated artifacts carry their whole definition; an invalid list is dropped.
		if not ELSecondArtifacts.restore_hero(state.map.profile, hero): hero.artifacts = []
		# Health is not carried; the new chapter's hero gets what its level gives.
		if hero.has("health_base"): ELHeroProgression.recalculate_health(hero)
		state.event.emit({"kind": "object_changed", "id": int(hero.uid)})
	var variables: Variant = block.get("variables", {})
	if variables is Dictionary:
		for key: Variant in variables: state.set_variable(key, variables[key], true)
	# the carried Notebook replaces the new chapter's (an invalid list is dropped).
	if block.has("notebook"): ELSecondNotebook.apply(state, block.notebook)

## Chapter row ready for ELAdventureView, carrying the progress.
static func chapter(profile: ELProfile, data: Dictionary) -> Dictionary:
	if not valid(data) or str(data.current).is_empty(): return {}
	var campaign := ELCampaign.new()
	if not campaign.load_campaign(profile, data.current) or int(data.row) >= campaign.scenarios.size(): return {}
	var row: Dictionary = campaign.scenarios[int(data.row)].duplicate()
	row.campaign = data.current
	row[KEY] = data.duplicate(true)
	return row

static func valid(data: Variant) -> bool:
	if not data is Dictionary or not ELLuaSave._integer(data.get("version"), VERSION, VERSION): return false
	for key: String in ["counter", "index", "row", "difficulty"]:
		if not ELLuaSave._integer(data.get(key), 0, MAX_ROWS): return false
	if int(data.counter) > 3 or int(data.difficulty) >= DIFFICULTIES: return false
	if not data.get("possible") is Array or not data.get("current") is String or not data.get("prev") is String or not data.get("intermission") is Dictionary or not data.get("finished") is bool: return false
	for id: Variant in data.possible:
		if not CAMPAIGNS.has(id): return false
	if not data.current.is_empty() and not CAMPAIGNS.has(data.current): return false
	if not data.prev.is_empty() and not CAMPAIGNS.has(data.prev): return false
	# Optional (older saves lack it): rows of the chapters already won.
	if data.has("played"):
		if not data.played is Array or data.played.size() > MAX_ROWS: return false
		for row: Variant in data.played:
			if not ELLuaSave._integer(row, 0, MAX_ROWS): return false
	return true

## Normalises JSON numbers back to integers where the format requires them.
static func normalized(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	for key: String in ["version", "counter", "index", "row", "difficulty"]: result[key] = int(result[key])
	if result.has("played"): result.played = Array(result.played).map(func(row: Variant) -> int: return int(row))
	return result

## Restores progress saved with a chapter (adventure save `scenario` field).
static func restore(state: ELAdventureSession, raw_scenario: Variant) -> bool:
	if not raw_scenario is Dictionary or not raw_scenario.has(KEY): return true
	if not valid(raw_scenario[KEY]): return false
	state.scenario[KEY] = normalized(raw_scenario[KEY])
	return true

static func progress(state: ELAdventureSession) -> Dictionary:
	return state.scenario.get(KEY, {}) if state != null and state.map != null and state.map.profile.id == "el2" else {}

# --- Between-chapter autosave ---------------------------------------------------

static func write(path: String, data: Dictionary) -> bool:
	if not valid(data): return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"format": AUTOSAVE_FORMAT, "version": 1, "edition": "el2", "campaign": data}))
	file.close()
	return DirAccess.rename_absolute(temporary, path) == OK

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4 * 1024 * 1024: return {}
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or raw.get("format") != AUTOSAVE_FORMAT or not valid(raw.get("campaign")): return {}
	return normalized(raw.campaign)

static func _plain(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value
