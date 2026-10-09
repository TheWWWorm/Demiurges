class_name ELBuildingMessageView
extends PanelContainer
## First-game map messages in the original MessageBox (build_first): building
## messages show their text alone, resource rewards an icon at each "@n"
## marker and a Master's lesson the skill icon under the text; no title and no
## building picture. Without the original art, `build` shows the same
## message in a plain panel.
## Second game: the building's message text alone in the original MessageBox
## (the message action shows only its text).
signal closed
var heading: Label
var picture: TextureRect
var body: Label
var rewards: HBoxContainer
var accept: BaseButton
var data: Dictionary = {}
## Second game: the MessageBox drawing this message.
var message_box: ELSecondDialogueBox
## First game: the MessageBox drawing a map notice (box "first").
var first_box: ELFirstMessageBox

## A first-game map notice shown in the original MessageBox. Building messages
## use it too whenever the original art is loaded.
static func first_applies(message: Dictionary) -> bool:
	return str(message.get("box", "")) == "first" or str(message.get("kind", "")) == "building_message"

func build_first(state: ELAdventureSession, hud: ELAdventureHud, message: Dictionary) -> void:
	data = message
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	first_box = ELFirstMessageBox.new()
	holder.add_child(first_box)
	first_box.setup(hud, first_text(state, message), ELFirstMessageBox.OK_ONLY, first_extras(state, hud, message))
	first_box.answered.connect(func(_accepted: bool): closed.emit())
	body = first_box.body
	accept = first_box.buttons.MBOK

## Picture, resource rows and inline icon of a first-game notice: "picture" is
## ["artifact", name], ["global_spell", code] or ["object", id]; "rows" lists
## [resource, amount]; "inline" names the resource drawn for "@1".
static func first_extras(state: ELAdventureSession, hud: ELAdventureHud, message: Dictionary) -> Dictionary:
	var profile := state.map.profile
	var extras := {}
	var picture: Array = message.get("picture", [])
	if picture.size() == 2:
		match str(picture[0]):
			"artifact":
				# An artifact shows the picture of the spell it carries.
				var spell := str(profile.table("Artefacts").get(str(picture[1]), {}).get("SpellType", ""))
				if profile.table("CombatSpells").has(spell): extras.picture = profile.card_icon(spell)
			"global_spell":
				var icon := int(ELGlobalSpells.row(profile, str(picture[1])).get("Icon", -1))
				if icon >= 0: extras.picture = ELGlobalSpellsView.icon(profile, icon)
			"object":
				var icon := object_icon(state, hud, state.object(int(picture[1])))
				if icon >= 0: extras.picture = hud.building_icon(icon)
	if message.has("rows"): extras.rows = message.rows
	if message.has("inline"): extras.inline = message.inline
	# Resource rewards: one icon per "@n" marker, in the order drawn.
	var resources: Array = message.get("resources", [])
	if not resources.is_empty() and first_text(state, message).contains("@1"):
		var kinds: Array = []
		for entry: Array in resources: kinds.append(str(entry[0]))
		extras.inline = kinds
	# A Master's lesson: the skill's icon at the hero's rank.
	var skill := str(message.get("skill", ""))
	if not skill.is_empty():
		var rank := clampi(int(state.object(int(message.get("hero", -1))).get("skills", {}).get(skill, 0)), 0, ELHeroSkills.MAX_RANK)
		var icon := skill_icon(profile, skill, rank)
		if icon != null: extras.items = [icon]
	return extras

## The message text for the MessageBox: a resource message keeps its "@n"
## markers with each amount after its icon; unused markers are trimmed.
static func first_text(state: ELAdventureSession, message: Dictionary) -> String:
	var resources: Array = message.get("resources", [])
	var key := str(message.get("key", ""))
	var raw := state.map.profile.text(key) if not key.is_empty() else ""
	if resources.is_empty() or raw == key or not raw.contains("@1"): return str(message.get("text", ""))
	raw = raw.strip_edges()
	var cut := raw.find("@%d" % (resources.size() + 1))
	if cut >= 0: raw = raw.substr(0, cut).strip_edges()
	for entry: Array in resources:
		var at := raw.find("%d")
		if at < 0: break
		raw = raw.substr(0, at) + str(int(entry[1])) + raw.substr(at + 2)
	return raw

## Picture index (BUILDINGS sheets) of a map object, or -1.
static func object_icon(state: ELAdventureSession, hud: ELAdventureHud, item: Dictionary) -> int:
	if item.is_empty(): return -1
	var icon := int(hud._art.resolve(item).get("row", {}).get("Icon", -1))
	if icon < 0 and ELResourceSites.TYPES.has(item.get("group")): icon = int(ELResourceSites.definition(state.map.profile, item).get("Icon", -1))
	if icon < 0: icon = int(ELAdditionalBuildings.definition(state.map.profile, item).get("Icon", -1))
	return icon

## A message the second game's MessageBox can show: text only.
static func second_applies(message: Dictionary) -> bool:
	return Array(message.get("resources", [])).is_empty() and str(message.get("skill", "")).is_empty()

func build_second(state: ELAdventureSession, second_hud: ELSecondAdventureHud, message: Dictionary) -> void:
	data = message
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A plain holder: the box places itself inside it.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	message_box = ELSecondDialogueBox.new()
	holder.add_child(message_box)
	message_box.setup(second_hud)
	message_box.answered.connect(func(_answer: String): closed.emit())
	message_box.present({"box": "message", "text": str(message.get("text", "")), "question": false}, state)
	body = Label.new()
	body.text = str(message.get("text", ""))
	body.hide()
	add_child(body)
	accept = message_box.accept
	holder.resized.connect(message_box.layout)

func build(state: ELAdventureSession, hud: ELAdventureHud, message: Dictionary) -> void:
	data = message
	var profile := state.map.profile
	add_theme_stylebox_override("panel", _frame())
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	add_child(rows)
	heading = Label.new()
	heading.text = str(message.get("title", ""))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("e2d29a"))
	if hud != null: heading.add_theme_font_override("font", hud._italic)
	rows.add_child(heading)
	heading.visible = not heading.text.is_empty()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	rows.add_child(columns)
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	columns.add_child(picture)
	var building := state.object(message.get("building", -1))
	var icon := int(ELAdditionalBuildings.definition(profile, building).get("Icon", -1)) if not building.is_empty() else -1
	var skill := str(message.get("skill", ""))
	if not skill.is_empty():
		var rank := clampi(int(state.object(message.get("hero", -1)).get("skills", {}).get(skill, 0)), 0, ELHeroSkills.MAX_RANK)
		picture.texture = skill_icon(profile, skill, rank)
		picture.custom_minimum_size = Vector2(50, 50)
	elif icon >= 0 and hud != null:
		picture.texture = hud.building_icon(icon)
		picture.custom_minimum_size = Vector2(70, 50)
	picture.visible = picture.texture != null
	var text_rows := VBoxContainer.new()
	text_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(text_rows)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(340, 0)
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color("e2d29a"))
	text_rows.add_child(body)
	rewards = HBoxContainer.new()
	rewards.add_theme_constant_override("separation", 16)
	text_rows.add_child(rewards)
	var resources: Array = message.get("resources", [])
	if resources.is_empty() or hud == null:
		body.text = str(message.get("text", ""))
		if not skill.is_empty(): body.text += "\n" + profile.text(str(ELHeroSkills.definition(profile, skill, 0).get("Name", skill)))
	else:
		# The original line shows a resource icon before each amount.
		var key := str(message.get("key", ""))
		body.text = profile.text(key).get_slice("@1", 0).strip_edges() if profile.text(key) != key else str(message.get("text", ""))
		for entry: Array in resources:
			var item := HBoxContainer.new()
			item.add_theme_constant_override("separation", 4)
			var image := TextureRect.new()
			image.texture = hud.resource_icon(str(entry[0]))
			image.custom_minimum_size = Vector2(28, 28)
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.tooltip_text = ELAdditionalBuildings.resource_name(profile, str(entry[0]))
			item.add_child(image)
			var amount := Label.new()
			amount.text = str(int(entry[1]))
			amount.add_theme_font_size_override("font_size", 16)
			amount.add_theme_color_override("font_color", Color("e8e4dc"))
			item.add_child(amount)
			rewards.add_child(item)
	rewards.visible = rewards.get_child_count() > 0
	var button := Button.new()
	button.text = "OK"
	button.custom_minimum_size = Vector2(96, 0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func(): closed.emit())
	rows.add_child(button)
	accept = button
	reset_size()
	var extent := get_combined_minimum_size()
	offset_left = -extent.x * 0.5
	offset_right = extent.x * 0.5
	offset_top = -extent.y * 0.5
	offset_bottom = extent.y * 0.5

static func skill_icon(profile: ELProfile, code: String, rank: int) -> Texture2D:
	var index := int(ELHeroSkills.definition(profile, code, rank).get("Icon", -1))
	if index < 0: return null
	var icon := AtlasTexture.new()
	icon.atlas = profile.texture("Interface/Skills/icon_1")
	icon.region = Rect2((index / 5) * 50, (index % 5) * 50, 50, 50)
	icon.filter_clip = true
	return icon

static func _frame() -> StyleBoxFlat:
	var style := ELAdventureHud.tooltip_style()
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 14
	return style
