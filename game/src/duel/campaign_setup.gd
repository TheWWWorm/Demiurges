class_name ELCampaignSetup
extends PanelContainer
signal begin(edition: String, scenario: Dictionary, difficulty: int)
signal closed
signal resume_requested
var profiles: Dictionary
var edition: OptionButton
var campaign: OptionButton
var chapter: OptionButton
var difficulty: OptionButton
var description: RichTextLabel
var campaign_description := ""
## The player's preferences: the computer players' strength is chosen
## beside the difficulty (ELAIChoice) for the game being begun; a difficulty
## change puts that difficulty's levels back. Begin gives them to the chapter
## row ("ai"); the Options choices are not changed here.
var settings: ELSettings
var ai_levels: Dictionary = {}
var ai_picks: Dictionary = {}
var _world_ai: Control
var _monster_row: HBoxContainer
var _fight_monsters: CheckBox
var _monster_help: Button
var entries: Array[Dictionary] = []

func build(available: Dictionary, initial: String) -> void:
	profiles = available
	custom_minimum_size.x = 560
	add_theme_stylebox_override("panel", ELAdventureView._style())
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	add_child(rows)
	var title := Label.new()
	title.text = "Campaigns"
	title.add_theme_font_size_override("font_size", 28)
	rows.add_child(title)
	edition = OptionButton.new()
	for id: String in profiles:
		edition.add_item(profiles[id].title)
		edition.set_item_metadata(edition.item_count - 1, id)
		if id == initial: edition.select(edition.item_count - 1)
	rows.add_child(edition)
	campaign = OptionButton.new()
	rows.add_child(campaign)
	chapter = OptionButton.new()
	rows.add_child(chapter)
	difficulty = OptionButton.new()
	rows.add_child(difficulty)
	if settings != null:
		var ai_row := HBoxContainer.new()
		ai_row.add_theme_constant_override("separation", 8)
		rows.add_child(ai_row)
		for key: String in ["duel_ai", "world_ai"]:
			var pair := HBoxContainer.new()
			pair.add_theme_constant_override("separation", 6)
			pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ai_row.add_child(pair)
			var caption := Label.new()
			caption.text = ELAIChoice.caption(key)
			pair.add_child(caption)
			var pick := ELAIChoice.values_picker(ai_levels, key, profiles.get(initial))
			ai_picks[key] = pick
			pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pair.add_child(pick)
			if key == "world_ai": _world_ai = pair
		_monster_row = HBoxContainer.new()
		rows.add_child(_monster_row)
		_fight_monsters = ELAIChoice.monster_checkbox(ai_levels, ai_picks.world_ai)
		_monster_row.add_child(_fight_monsters)
		_monster_help = Button.new()
		_monster_help.name = "NeutralMonsterHelp"
		_monster_help.text = "?"
		var dialog := AcceptDialog.new()
		_monster_help.pressed.connect(func():
			dialog.dialog_text = _monster_help.tooltip_text
			dialog.popup_centered(Vector2i(420, 0)))
		add_child(dialog)
		_monster_row.add_child(_monster_help)
	description = RichTextLabel.new()
	description.custom_minimum_size = Vector2(510, 230)
	rows.add_child(description)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	var start := Button.new()
	start.text = "Begin chapter"
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func():
		if chapter.selected >= 0 and not chapter.is_item_disabled(chapter.selected):
			var row: Dictionary = entries[chapter.selected].duplicate()
			row.campaign = str(campaign.get_selected_metadata())
			if not ai_levels.is_empty(): row.ai = ELAIChoice.normalized(ai_levels)
			begin.emit(str(edition.get_selected_metadata()), row, difficulty.selected))
	buttons.add_child(start)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): closed.emit())
	buttons.add_child(back)
	var resume := Button.new()
	resume.text = "Resume saved campaign"
	resume.pressed.connect(func(): resume_requested.emit())
	rows.add_child(resume)
	# Each edition keeps its own campaign save.
	var saved := func():
		resume.disabled = not FileAccess.file_exists(ELSingleScenario.campaign_file(chosen_edition()))
	saved.call()
	edition.item_selected.connect(func(_index: int):
		saved.call()
		ai_levels.clear()
		_campaigns()
		reset_ai())
	campaign.item_selected.connect(func(_index: int): _chapters())
	chapter.item_selected.connect(func(_index: int): _description())
	difficulty.item_selected.connect(func(_index: int): reset_ai())
	_campaigns()
	reset_ai()

## The chosen difficulty's computer players' strength (ELAIChoice.defaults),
## shown on the dropdowns.
func reset_ai() -> void:
	if settings == null: return
	if ai_levels.is_empty() and chosen_edition() == "el1": ai_levels[ELAIChoice.FIGHT_MONSTERS] = true
	ai_levels.merge(ELAIChoice.defaults(maxi(difficulty.selected, 0), settings), true)
	for key: String in ai_picks: ELAIChoice.display(ai_picks[key], int(ai_levels[key]))
	ELAIChoice.display_monsters(_fight_monsters, ai_picks.world_ai, ai_levels)

## Difficulty levels per edition: the first game has five, second-game maps
## author three variants (DifLvl 0-2, global-map GMA6Diff1-3).
const SECOND_LATER_CHAPTER := "Reached by winning the chapter before it."
const DIFFICULTY_NAMES := {"el1": ["Easy", "Normal", "Hard", "Expert", "Master"], "el2": ["Easy", "Normal", "Hard"]}

func chosen_edition() -> String:
	return str(edition.get_selected_metadata()) if edition != null and edition.selected >= 0 else ""

func _difficulties(id: String) -> void:
	# Normal until the player picks another, as on the front menu.
	var chosen := difficulty.selected if difficulty.selected >= 0 else 1
	difficulty.clear()
	var names: Array = DIFFICULTY_NAMES.get(id, DIFFICULTY_NAMES.el1)
	for name: String in names: difficulty.add_item(name)
	difficulty.select(mini(chosen, names.size() - 1))

func _campaigns() -> void:
	campaign.clear()
	var profile: ELProfile = profiles[edition.get_selected_metadata()]
	_difficulties(profile.id)
	# The map's computer players are the first game's only.
	if _world_ai != null:
		_world_ai.visible = ELAIChoice.applies("world_ai", profile.id)
		_monster_row.visible = _world_ai.visible
		_fight_monsters.text = ELRemakeText.t(ELAIChoice.MONSTER_LABEL, profile)
		_monster_help.tooltip_text = ELRemakeText.t(ELAIChoice.MONSTER_HELP, profile)
	for id: String in ELCampaign.available(profile):
		var data := ELCampaign.new()
		if data.load_campaign(profile, id):
			campaign.add_item(data.title)
			campaign.set_item_metadata(campaign.item_count - 1, id)
	_chapters()

func _chapters() -> void:
	chapter.clear()
	entries.clear()
	if campaign.selected < 0: return
	var profile: ELProfile = profiles[edition.get_selected_metadata()]
	var data := ELCampaign.new()
	if not data.load_campaign(profile, str(campaign.get_selected_metadata())): return
	entries.assign(data.scenarios)
	campaign_description = data.description
	for i in entries.size():
		var title := profile.text(str(entries[i].get("header", "")))
		chapter.add_item("Chapter %d%s" % [i + 1, " · " + title if not title.is_empty() else ""])
		# Second game: a later chapter's hero brings his book, level and wallet
		# from the chapter before (the map's own hero has none); the original
		# offers no chapter choice, so only a campaign's first chapter starts here.
		if profile.id == "el2" and i > 0:
			chapter.set_item_disabled(i, true)
			chapter.set_item_tooltip(i, SECOND_LATER_CHAPTER)
	if chapter.item_count > 0: chapter.select(0)
	_description()

func _description() -> void:
	var profile: ELProfile = profiles[edition.get_selected_metadata()]
	description.text = profile.text(str(entries[chapter.selected].briefing)) if chapter.selected >= 0 and entries[chapter.selected].has("briefing") else campaign_description
