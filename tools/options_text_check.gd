extends SceneTree
## Headless check that every remake text of the Options screen has a Russian
## translation (ELRemakeText): the remake's pages as built (both in the
## merged Options screen and in the settings dialog, with their (?) texts,
## list items and status lines), the texts of the options code itself (rows
## only an engine with DLSS / FSR shows, reasons, the restart message), the
## graphics technologies' texts (ELGraphicsSDK) and the remake menu.
##
##   godot --headless --path game --script ../tools/options_text_check.gd
##
## A text counts as untranslated when its Russian is the same English text
## and it still has English words once names (NVIDIA DLSS, Vulkan, Discord…)
## are left out. Settings are never written.

var failures: Array[String] = []

## Names kept as they are in Russian.
const NAMES := ["NVIDIA", "DLSS", "DLAA", "AMD", "FSR", "FidelityFX", "Forward+", "Vulkan", "V-Sync", "Discord",
	"Etherlords", "GeForce", "RTX", "Reflex", "Ray Reconstruction", "Streamline", "Shift", "Esc", "FPS", "GPU",
	"Windows", "MSAA", "TAA", "FXAA", "2x", "4x", "II", "F5", "F7", "F9"]
## Hard-coded texts that are not shown as they are (format pieces, keys).
const SKIP := ["?", "×", "DUEL"]

var _latin := RegEx.create_from_string("[A-Za-z]{2,}")
var _cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
var _seen := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	OS.set_environment("DEMIURGES_LANGUAGE", "ru")
	_built_pages()
	_source_texts()
	_graphics_texts()
	for text: String in _seen:
		var where: String = _seen[text]
		if _untranslated(text): failures.append("%s: \"%s\"" % [where, text])
	for failure in failures: print("FAIL: no Russian for " + failure)
	print("OPTIONS TEXT: %d texts, %d failure(s)" % [_seen.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _note(text: String, where: String) -> void:
	text = text.strip_edges()
	if text.is_empty() or text in SKIP or _seen.has(text): return
	_seen[text] = where

## English left in `text` after its Russian lookup.
func _untranslated(text: String) -> bool:
	if _cyrillic.search(text) != null: return false
	var russian := ELRemakeText.russian(text)
	if russian != text: return false
	var rest := text
	for name: String in NAMES: rest = rest.replace(name, "")
	# Placeholders and key names ("%s", "%d").
	rest = rest.replace("%s", "").replace("%d", "")
	return _latin.search(rest) != null

## The remake's pages built in Russian, merged into Options and in the dialog.
func _built_pages() -> void:
	var view: Node = load("res://src/duel/view.gd").new()
	view.settings = ELSettings.new()
	view.settings.use_edition("el1")
	var menu := ELFrontMenu.new()
	for owner: Variant in [menu, null]:
		for row: Array in view.remake_pages(owner):
			_note(str(row[1]), "page list")
			var column := VBoxContainer.new()
			view.build_remake_page(owner, str(row[0]), column, null)
			_walk(column, "page " + str(row[0]))
			column.free()
		var tools := HBoxContainer.new()
		view.build_remake_page(owner, "tools", tools, null)
		_walk(tools, "tools")
		tools.free()
	menu.free()
	view.free()

func _walk(node: Node, where: String) -> void:
	# Shortcut fields show key names.
	if node.has_method("captures_keys"): return
	if node is Control: _note(node.tooltip_text, where + " tooltip")
	# A setting's (?) keeps its explanation here.
	if node.has_meta("help_text"): _note(str(node.get_meta("help_text")), where + " help")
	if node is Label: _note(node.text, where)
	elif node is OptionButton:
		for i in node.item_count:
			_note(node.get_item_text(i), where + " list")
			_note(node.get_item_tooltip(i), where + " list tooltip")
	elif node is Button: _note(node.text, where)
	for child in node.get_children(): _walk(child, where)

## Texts written in the options code: rows, sections, list items, reasons
## and messages, the ones only some builds or computers show included; and
## the remake menu's buttons.
func _source_texts() -> void:
	var source := FileAccess.get_file_as_string("res://src/duel/view.gd")
	var start := source.find("func _open_settings_dialog")
	var end := source.find("func _settings_theme")
	_strings(source.substr(start, end - start), "options code")
	start = source.find("menu = PanelContainer.new()")
	end = source.find("log_text = RichTextLabel.new()", start)
	_strings(source.substr(start, end - start), "remake menu")

## Every quoted text in `code` shown as a caption or a sentence: texts with
## spaces that start like a sentence, and single words where a caption goes
## (translated, a section or row title, a button, a list of captions).
func _strings(code: String, where: String) -> void:
	var quoted := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var caption_place := RegEx.create_from_string("(_t\\(|_settings_box\\([^,()]*, |_settings_row\\([^,()]*, |_button\\(|_label\\(|tooltip_text = |caption: String in \\[[^\\]]*)$")
	for found: RegExMatch in quoted.search_all(code):
		var text := found.get_string(1).replace("\\n", "\n")
		if text.is_empty() or text.contains("://"): continue
		var line_start := code.rfind("\n", found.get_start()) + 1
		var before := code.substr(line_start, found.get_start() - line_start)
		var first := text.left(1)
		var sentence := text.contains(" ") and (first == "%" or first != first.to_lower())
		if sentence or caption_place.search(before) != null: _note(text, where)

## The graphics technologies' texts (help, reasons, restart messages, the
## upscaler, quality and frame generation names).
func _graphics_texts() -> void:
	var sdk := ELGraphicsSDK
	var constants: Dictionary = (sdk as Script).get_script_constant_map()
	for key: String in constants:
		var value: Variant = constants[key]
		if value is String and value.contains(" ") and not value.contains("://") and not value.begins_with("application/"):
			_note(value, "ELGraphicsSDK." + key)
	var t := func(text: String) -> String: return text
	for vendor: int in [sdk.OFF, sdk.NVIDIA, sdk.AMD]:
		_note(sdk.upscaler_name(vendor, t), "upscaler name")
		for quality in 4: _note(sdk.quality_name(quality, vendor, t), "quality name")
		for generation: bool in [false, true]:
			_note(sdk.generation_name({"upscaler": vendor, "frame_generation": generation}), "frame generation name")
