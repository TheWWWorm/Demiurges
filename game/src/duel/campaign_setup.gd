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
		_campaigns())
	campaign.item_selected.connect(func(_index: int): _chapters())
	chapter.item_selected.connect(func(_index: int): _description())
	_campaigns()

## Difficulty levels per edition: the first game has five, second-game maps
## author three variants (DifLvl 0-2, global-map GMA6Diff1-3).
const SECOND_LATER_CHAPTER := "Reached by winning the chapter before it."
const DIFFICULTY_NAMES := {"el1": ["Easy", "Normal", "Hard", "Expert", "Master"], "el2": ["Easy", "Normal", "Hard"]}

func chosen_edition() -> String:
	return str(edition.get_selected_metadata()) if edition != null and edition.selected >= 0 else ""

func _difficulties(id: String) -> void:
	var chosen := maxi(difficulty.selected, 0)
	difficulty.clear()
	var names: Array = DIFFICULTY_NAMES.get(id, DIFFICULTY_NAMES.el1)
	for name: String in names: difficulty.add_item(name)
	difficulty.select(mini(chosen, names.size() - 1))

func _campaigns() -> void:
	campaign.clear()
	var profile: ELProfile = profiles[edition.get_selected_metadata()]
	_difficulties(profile.id)
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
