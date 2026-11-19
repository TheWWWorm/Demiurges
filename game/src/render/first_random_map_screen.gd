class_name ELFirstRandomMapScreen
extends AcceptDialog
## Local first-game skirmish setup. A preview is the actual generated map;
## changing any world option invalidates it before a game can be launched.
signal requested(configuration: Dictionary, difficulty: int, ai: Dictionary)

const SETTINGS_PATH := "user://el1_random_map_setup.json"
const CODE_PREFIX := "EL1R12:"
const LEGACY_CODE_PREFIX := "EL1R1:"
const CODE_VERSIONS := {
	LEGACY_CODE_PREFIX: 1, "EL1R2:": 2, "EL1R3:": 3, "EL1R4:": 4, "EL1R5:": 5, "EL1R6:": 6,
	"EL1R7:": 7, "EL1R8:": 8, "EL1R9:": 9, "EL1R10:": 10, "EL1R11:": 11, CODE_PREFIX: ELFirstRandomMap.VERSION,
}
const MAX_CODE_LENGTH := 4096
const FACTIONS := [["Green", "Vitals"], ["Blue", "Kinets"], ["Red", "Chaots"], ["Black", "Synthets"]]
const TERRAIN_INK := {"Green": Color("546a3d"), "Blue": Color("a8ac9b"), "Red": Color("8f5a3d"), "Black": Color("69634b"), "Colorless": Color("8d8778")}
const LANDSCAPE_INK := {0: Color("49623a"), 1: Color("72844f"), 3: Color("67726a"), 4: Color("b5bfbd"), 7: Color("98aead"), 18: Color("80a4ac"), 8: Color("795040"), 10: Color("614848"), 11: Color("aa7857"), 12: Color("625654"), 13: Color("887862"), 15: Color("6c6150")}
const PLAYER_INK := [Color("f4d789"), Color("dd6459"), Color("69b4e0"), Color("a4c879")]

var profile: ELProfile
var configuration: Dictionary = {}
var preview_map: ELAdventureMap
var report: Dictionary = {}
var ai: Dictionary = {}
var _fields := {}
var _seed: LineEdit
var _presets: OptionButton
var _description: Label
var _preview: TextureRect
var _summary: Label
var _status: Label
var _difficulty: OptionButton
var _generate: Button
var _play: Button
var _code: LineEdit
var _busy := false
var _syncing := false
var _revision := 0
var _layout_ticket := 0

func build(source: ELProfile, level := 2, ai_levels: Dictionary = {}) -> void:
	profile = source
	title = _t("Random map")
	ELNetworkLobby.style_dialog(self, profile, "StrategicScreen")
	exclusive = true
	unresizable = false
	min_size = Vector2i(700, 470)
	size = Vector2i(920, 680)
	get_ok_button().hide()
	configuration = ELFirstRandomMap.defaults()
	configuration.seed = _new_seed()
	if FileAccess.file_exists(SETTINGS_PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if saved is Dictionary:
			var normalized := ELFirstRandomMap.normalize(saved.get("config", {})) if saved.get("config") is Dictionary else {}
			if not normalized.is_empty():
				configuration.merge(normalized, true)
				configuration.version = ELFirstRandomMap.VERSION
	ai = ELAIChoice.normalized(ai_levels) if ELAIChoice.valid(ai_levels) else ELAIChoice.defaults(level, null)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var heading := ELNetworkLobby.heading(_t("Random map · Etherlords I"), false)
	heading.add_theme_font_size_override("font_size", 23)
	body.add_child(heading)
	var intro := _label("Build a world, choose your faction, and defeat the rival castles.")
	intro.add_theme_font_size_override("font_size", 14)
	body.add_child(intro)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 10)
	body.add_child(preset_row)
	preset_row.add_child(_label("Preset"))
	_presets = OptionButton.new()
	_presets.name = "RandomMapPreset"
	_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_presets.add_item(_t("Custom configuration"))
	for preset: Dictionary in ELFirstRandomMap.presets():
		_presets.add_item(_t(str(preset.name)))
		_presets.set_item_metadata(_presets.item_count - 1, preset)
		_presets.set_item_tooltip(_presets.item_count - 1, _t(str(preset.description)))
	_presets.item_selected.connect(_preset_selected)
	preset_row.add_child(_presets)
	_description = _label("Every start has room to expand and a route to its rivals.")
	_description.add_theme_font_size_override("font_size", 13)
	_description.max_lines_visible = 2
	body.add_child(_description)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)
	var tabs := TabContainer.new()
	tabs.name = "RandomMapOptions"
	tabs.custom_minimum_size.x = 330
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(tabs)
	var world := _tab(tabs, "World")
	var rules := _tab(tabs, "Players and rules")
	_seed = LineEdit.new()
	_seed.name = "RandomMapSeed"
	_seed.max_length = 64
	_seed.placeholder_text = _t("Enter a seed")
	_seed.tooltip_text = _t("The same seed and settings recreate the same map.")
	_seed.text_changed.connect(func(_value: String): _changed())
	_field(world, "Seed", _seed)
	var reroll := _button("New seed", func():
		_seed.text = _new_seed()
		_changed()
		generate_preview())
	world.add_child(reroll)
	_picker(world, "size", "Map size", [[64, "Small · 64 × 64"], [96, "Medium · 96 × 96"], [128, "Large · 128 × 128"], [160, "Huge · 160 × 160"]])
	_picker(world, "layout", "Layout", [["frontier", "Frontier"], ["lakes", "Lake country"], ["crossroads", "Crossroads"], ["archipelago", "Island chains"], ["inland_sea", "Inland sea"], ["river_delta", "River delta"], ["ring", "Ring of kingdoms"], ["peninsulas", "Peninsulas"]])
	_picker(world, "water", "Water coverage", [["low", "Low"], ["normal", "Normal"], ["high", "High"]])
	_picker(world, "coast", "Coastline", [["smooth", "Smooth"], ["rugged", "Rugged"]])
	var naval := CheckBox.new()
	naval.name = "RandomMapNaval"
	naval.text = _t("Enable ships and harbors")
	naval.tooltip_text = _t("Heroes board at cyan harbors, sail, and land at another harbor. Both you and the AI use sea routes.")
	naval.toggled.connect(func(_value: bool): _changed())
	world.add_child(naval)
	_fields.naval = naval
	_picker(world, "biome", "Terrain", [["mixed", "Mixed regions"], ["Green", "Vital lands"], ["Blue", "Kinet lands"], ["Red", "Chaot lands"], ["Black", "Synthet lands"]])
	_picker(world, "resources", "Resource density", [["scarce", "Scarce"], ["normal", "Normal"], ["rich", "Rich"]])
	_picker(world, "scenery", "Scenery", [[0, "Minimal"], [1, "Normal"], [2, "Dense"]])
	var roads := CheckBox.new()
	roads.name = "RandomMapRoads"
	roads.text = _t("Connect regions with roads")
	roads.toggled.connect(func(_value: bool): _changed())
	world.add_child(roads)
	_fields.roads = roads
	_picker(rules, "players", "Players", [[2, "2 · you + 1 AI"], [3, "3 · you + 2 AI"], [4, "4 · you + 3 AI"]])
	_picker(rules, "faction", "Your faction", FACTIONS)
	_picker(rules, "starting_resources", "Starting resources", [["scarce", "Scarce"], ["normal", "Normal"], ["rich", "Rich"]])
	_picker(rules, "guards", "Neutral guards", [["none", "None"], ["normal", "Normal"], ["strong", "Strong"]])
	_picker(rules, "castle_health", "Castle energy", [[20, "20 · short sieges"], [30, "30 · normal"], [60, "60 · long sieges"]])
	_difficulty = OptionButton.new()
	_difficulty.name = "RandomMapDifficulty"
	for i in 5: _difficulty.add_item(_t("Difficulty %d") % (i + 1), i)
	_difficulty.select(clampi(level, 0, 4))
	_field(rules, "Game difficulty", _difficulty)
	for key: String in ELAIChoice.KEYS:
		var pick := ELAIChoice.values_picker(ai, key, profile)
		pick.custom_minimum_size.x = 150
		_field(rules, ELAIChoice.caption(key), pick)
		_fields[key] = pick
	var neutral_ai := ELAIChoice.monster_checkbox(ai, _fields.world_ai)
	neutral_ai.text = _t(ELAIChoice.MONSTER_LABEL)
	neutral_ai.tooltip_text = _t(ELAIChoice.MONSTER_HELP)
	rules.add_child(neutral_ai)
	ELAIChoice.display_monsters(neutral_ai, _fields.world_ai, ai)
	var ai_note := _label("Smarter or Living world is recommended, especially without neutral guards.")
	ai_note.add_theme_font_size_override("font_size", 13)
	rules.add_child(ai_note)
	var preview_side := VBoxContainer.new()
	preview_side.custom_minimum_size.x = 265
	preview_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_side.add_theme_constant_override("separation", 8)
	columns.add_child(preview_side)
	var aspect := AspectRatioContainer.new()
	aspect.custom_minimum_size = Vector2(130, 130)
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.ratio = 1.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	preview_side.add_child(aspect)
	var backing := PanelContainer.new()
	aspect.add_child(backing)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111712")
	style.border_color = Color("7a6c4d")
	style.set_border_width_all(1)
	style.set_content_margin_all(5)
	backing.add_theme_stylebox_override("panel", style)
	_preview = TextureRect.new()
	_preview.name = "RandomMapPreview"
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.tooltip_text = _t("The preview reveals the whole map. Exploration fog starts normally when you play.")
	backing.add_child(_preview)
	var legend := _label("Squares: castles · Gold: resources · Red: guards · Cyan: harbors · Violet: discoveries")
	legend.add_theme_font_size_override("font_size", 12)
	preview_side.add_child(legend)
	_summary = _label("Generate a preview to inspect your world before playing.")
	_summary.name = "RandomMapSummary"
	_summary.add_theme_font_size_override("font_size", 13)
	_summary.max_lines_visible = 3
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_side.add_child(_summary)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	body.add_child(code_row)
	_code = LineEdit.new()
	_code.name = "RandomMapCode"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.max_length = MAX_CODE_LENGTH
	_code.placeholder_text = _t("Configuration code · copy or paste to share a world")
	_code.tooltip_text = _t("Includes the seed and world settings. AI strength and game difficulty are chosen separately.")
	code_row.add_child(_code)
	code_row.add_child(_button("Copy setup", copy_setup))
	code_row.add_child(_button("Load setup", load_setup))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	actions.add_child(_button("Back", hide))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_generate = _button("Generate preview", generate_preview)
	_generate.name = "RandomMapGenerate"
	actions.add_child(_generate)
	_play = _button("Generate and play", _start)
	_play.name = "RandomMapPlay"
	actions.add_child(_play)
	_status = _label("")
	_status.name = "RandomMapStatus"
	_status.custom_minimum_size.y = 22
	body.add_child(_status)
	_sync_fields()
	close_requested.connect(hide)
	visibility_changed.connect(func():
		_layout_ticket += 1
		if visible: _fit_opened(_layout_ticket)
		# Back/close cancels a queued Generate-and-play before the next frame.
		# Reopening this window must not revive that earlier launch request.
		if not visible and _busy: _revision += 1)

## AcceptDialog grows to a transient label minimum while wrapped text and
## scroll containers receive their first widths. Once those widths settle,
## restore the intended viewport-clamped opening size; otherwise the first
## opening can retain a several-thousand-pixel height and hide the actions.
func _fit_opened(ticket: int) -> void:
	for frame in 2: await get_tree().process_frame
	if not is_inside_tree() or not visible or ticket != _layout_ticket: return
	popup_centered_clamped(Vector2i(920, 680), 0.94)

func _t(value: String) -> String:
	return ELRemakeText.t(value, profile)

func _label(value: String) -> Label:
	var label := Label.new()
	label.text = _t(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = _t(caption)
	button.pressed.connect(action)
	return button

func _tab(tabs: TabContainer, caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = _t(caption)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 8)
	scroll.add_child(margin)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 9)
	margin.add_child(fields)
	return fields

func _field(parent: VBoxContainer, caption: String, control: Control) -> void:
	var pair := VBoxContainer.new()
	pair.add_theme_constant_override("separation", 3)
	parent.add_child(pair)
	pair.add_child(_label(caption))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pair.add_child(control)

func _picker(parent: VBoxContainer, key: String, caption: String, options: Array) -> void:
	var pick := OptionButton.new()
	pick.name = "RandomMap_" + key
	pick.fit_to_longest_item = false
	pick.clip_text = true
	for option: Array in options:
		pick.add_item(_t(str(option[1])))
		pick.set_item_metadata(pick.item_count - 1, option[0])
	pick.item_selected.connect(func(_index: int): _changed())
	_fields[key] = pick
	_field(parent, caption, pick)

func _sync_fields() -> void:
	_syncing = true
	_seed.text = str(configuration.seed)
	var shown := ELFirstRandomMap.defaults()
	shown.merge(configuration, true)
	for key: String in shown:
		var control: Control = _fields.get(key)
		if control is CheckBox:
			control.set_pressed_no_signal(bool(shown[key]))
		elif control is OptionButton:
			for i in control.item_count:
				if control.get_item_metadata(i) == shown[key]:
					control.select(i)
					break
	_syncing = false
	_changed(false)

func options() -> Dictionary:
	var result := ELFirstRandomMap.defaults(int(configuration.get("version", ELFirstRandomMap.VERSION)))
	result.seed = _seed.text
	for key: String in result:
		var control: Control = _fields.get(key)
		if control is CheckBox: result[key] = control.button_pressed
		elif control is OptionButton: result[key] = control.get_item_metadata(control.selected)
	return result

func _changed(custom := true) -> void:
	if _syncing: return
	# Imported worlds keep their generator version until a setting is edited.
	if custom: configuration.version = ELFirstRandomMap.VERSION
	_revision += 1
	preview_map = null
	report.clear()
	_preview.modulate.a = 0.35
	_play.text = _t("Generate and play")
	_summary.text = _t("Settings changed. Generate a preview or start a new game.")
	_status.text = ""
	if custom: _presets.select(0)

func _preset_selected(index: int) -> void:
	if index <= 0: return
	var preset: Dictionary = _presets.get_item_metadata(index)
	var next := ELFirstRandomMap.defaults()
	next.merge(preset.options, true)
	next.seed = _seed.text
	next.faction = options().faction
	configuration = ELFirstRandomMap.normalize(next)
	_description.text = _t(str(preset.description))
	_sync_fields()

func _new_seed() -> String:
	return Crypto.new().generate_random_bytes(6).hex_encode()

func generate_preview() -> bool:
	if _busy: return false
	var wanted := ELFirstRandomMap.normalize(options())
	if wanted.is_empty():
		_status.text = _t("Enter a non-empty seed and valid world settings.")
		return false
	_busy = true
	_generate.disabled = true
	_play.disabled = true
	_status.text = _t("Generating and checking routes…")
	var revision := _revision
	await get_tree().process_frame
	if not visible or revision != _revision:
		_busy = false
		_generate.disabled = false
		_play.disabled = false
		return false
	var generator := ELFirstRandomMap.new()
	var result := generator.generate(profile, wanted)
	_busy = false
	_generate.disabled = false
	_play.disabled = false
	if revision != _revision:
		_status.text = _t("Settings changed during generation. Generate again.")
		return false
	if result == null:
		_status.text = _t(generator.error)
		return false
	configuration = generator.config.duplicate(true)
	preview_map = result
	report = generator.report.duplicate(true)
	_preview.texture = ImageTexture.create_from_image(preview_image(result))
	_preview.modulate.a = 1.0
	_summary.text = _t("%d × %d · %d players · seed %s") % [result.width, result.height, result.players.size(), str(configuration.seed)]
	if report.has("daily_travel_ap"):
		_summary.text += "\n" + _t("%d outdoor creatures · Land activities within %d AP") % [int(report.counts.get("np_heroes", 0)), int(report.daily_travel_ap)]
	else:
		_summary.text += "\n" + _t("%d placed objects · all castles connected") % result.objects.size()
	if bool(configuration.get("naval", false)):
		_summary.text += "\n" + _t("%d%% water · %d harbors · land and sea routes") % [roundi(float(report.get("water_fraction", 0.0)) * 100.0), result.get_meta("first_naval", {}).get("ports", []).size()]
	_summary.tooltip_text = _summary.text
	_status.text = _t("Ready. Defeat the rival castles while protecting your own.")
	_play.text = _t("Play this map")
	return true

func copy_setup() -> void:
	var normalized := ELFirstRandomMap.normalize(options())
	if normalized.is_empty():
		_status.text = _t("Enter a non-empty seed and valid world settings.")
		return
	var prefix := str(CODE_VERSIONS.find_key(int(normalized.version)))
	_code.text = prefix + Marshalls.utf8_to_base64(JSON.stringify(normalized))
	_code.select_all()
	DisplayServer.clipboard_set(_code.text)
	_status.text = _t("Setup copied. The same game data and generator version recreate this world.")

func load_setup() -> void:
	var encoded := _code.text.strip_edges()
	var prefix := encoded.get_slice(":", 0) + ":"
	if not CODE_VERSIONS.has(prefix) or encoded.length() > MAX_CODE_LENGTH:
		_status.text = _t("Paste a configuration code into the field first.")
		return
	var raw: Variant = JSON.parse_string(Marshalls.base64_to_utf8(encoded.trim_prefix(prefix)))
	var normalized := ELFirstRandomMap.normalize(raw) if raw is Dictionary else {}
	if not normalized.is_empty():
		if raw.size() != normalized.size() or int(normalized.version) != CODE_VERSIONS[prefix]: normalized = {}
	if normalized.is_empty():
		_status.text = _t("This configuration code is invalid or uses an unsupported version.")
		return
	configuration = normalized
	_presets.select(0)
	_sync_fields()
	_status.text = _t("Setup loaded. Generate a preview or play.")

func _start() -> void:
	if _busy or not visible: return
	if preview_map == null:
		if not await generate_preview(): return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"config": configuration}, "\t"))
		file.close()
	hide()
	requested.emit(configuration.duplicate(true), _difficulty.selected, ELAIChoice.normalized(ai))

## A schematic of the generated terrain and objects; it uses no game art.
static func preview_image(map: ELAdventureMap) -> Image:
	var scale := 3
	var result := Image.create(map.width * scale, map.height * scale, false, Image.FORMAT_RGB8)
	var landscape := int(map.get_meta("random_map", {}).get("version", 0)) >= ELFirstRandomMapV2.LANDSCAPE_VERSION
	for y in map.height:
		for x in map.width:
			var tile := map.tile(x, y)
			var ink: Color = TERRAIN_INK.get(ELAdventureArt.terrain_color(tile), Color("8d8778"))
			if landscape: ink = LANDSCAPE_INK.get(tile, ink)
			if tile in ELTileSet.WATER_KINDS: ink = Color("294f68")
			elif map.profile.terrain_tiles != null and int(map.profile.terrain_tiles.types.get(tile, {}).get("movement", 1)) < 0: ink = ink.darkened(0.5)
			if map.roads[y * map.width + x] != 0: ink = ink.lerp(Color("d2b98a"), 0.45)
			result.fill_rect(Rect2i(x * scale, (map.height - 1 - y) * scale, scale, scale), ink)
	# Keep dense terrain details below the strategic markers.
	for object: Dictionary in map.objects:
		if object.group != "terrain_objects": continue
		var point := Vector2i(int(object.x) * scale, (map.height - 1 - int(object.y)) * scale)
		result.set_pixelv(point, result.get_pixelv(point).darkened(0.44))
	for object: Dictionary in map.objects:
		if object.group in ["terrain_objects", "heroes"]: continue
		var ink := Color("cfb865")
		var radius := 2
		if ELFirstScenario.is_castle(object):
			ink = PLAYER_INK[clampi(int(object.owner) - 1, 0, 3)]
			radius = 5
		elif object.group == "np_heroes": ink = Color("d65c50")
		elif object.group == "additional_buildings": ink = Color("deb3ed")
		var point := Vector2i(int(object.x) * scale, (map.height - 1 - int(object.y)) * scale)
		var bounds := Rect2i(point - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1)).intersection(Rect2i(Vector2i.ZERO, result.get_size()))
		if radius == 5:
			result.fill_rect(bounds.grow(1).intersection(Rect2i(Vector2i.ZERO, result.get_size())), Color("171913"))
		result.fill_rect(bounds, ink)
	for port: Dictionary in map.get_meta("first_naval", {}).get("ports", []):
		for key: String in ["land", "water"]:
			var point := Vector2i(int(port[key][0]) * scale, (map.height - 1 - int(port[key][1])) * scale)
			result.fill_rect(Rect2i(point - Vector2i.ONE * 2, Vector2i.ONE * 5).intersection(Rect2i(Vector2i.ZERO, result.get_size())), Color("76e0dc"))
	return result
