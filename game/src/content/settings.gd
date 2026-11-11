class_name ELSettings
extends RefCounted
## Player preferences. Each original game keeps its own settings, so every
## original option (and the volumes and movie mode) is stored per edition;
## `values` is the view of the active edition plus the shared remake-only
## settings. Call use_edition() when the active game changes.
##
## Shared remake settings: "ambience" volume, "shadows", optional "soft_shadows",
## optional "terrain_detail" on maps and in battles, optional "enhanced_water"
## on adventure maps, second-game
## adventure "weather" particles, "helper_overlay" (remake-only English readouts,
## hints and shortcut buttons over the original screens; off by default),
## "antialiasing" (-1 automatic: 2x multisampling unless the renderer is a
## software one; 0 off; 1 2x; 2 4x multisampling of the 3D scenes);
## "discord_activity" (the game and mode shown in the Discord desktop app);
## "renderer" (0 Compatibility, 1 Forward+ on Vulkan; applied at start) and
## "path_tracing" (traced lighting where the renderer and GPU allow it) and
## "show_fps" (a frame rate counter in a corner of the screen) and
## "hardware_check" (how far the first start's ELHardwareCheck has got);
## the Display page: "window_mode" (0 window, 1 borderless full screen, 2
## exclusive full screen), "window_width"/"window_height" (the window's size,
## 0 the default) and "frame_rate" (0 the display's refresh rate with
## V-Sync, -1 unlimited, otherwise a frame cap without V-Sync).
## Per edition (original Options screen order):
## "music"/"effects" volumes 0..1; "movies" the originals' Video key (0 none,
## 1 own size, 2 fitted); "blood"; "map_tooltips" (second game
## MouseOverTooltips); "autosave" (first game end-of-turn autosave);
## "heroes_voices"; "ambient_sounds"; "adventure_fast" (map movement 4x);
## "animated_objects"; "mouse_rotation"/"keyboard_rotation"/"mouse_scroll"/
## "keyboard_scroll" camera multipliers 0..2; "invert_rotation"; "gamma"
## -1..1; "audio_reverse"; "fog_animations"; "show_blazons"; "show_tutorial";
## "show_chat"; "use_spells"; "auto_camera"; "auto_camera_dynamics" 0..100;
## "hide_motion"; "hide_cast"; "combat_phases"; "heroes_casting";
## "creature_numbers"; "ability_icons"; "numbers_on_camera"; "attack_order";
## "visual_log". Several have no remake system yet and are only stored.
## "tutorial_events": the first game's shown tutorial events, one '0'/'1'
## per event id (settings.ini TutorialEvents); "show_tutorial" gates them.
## Version 4: sharpening became Off by default (the original ground is soft);
## older files still on the former default (light) move to Off.
const SETTINGS_VERSION := 4
const SHARED := {"ambience": 0.55, "shadows": true, "soft_shadows": false, "weather": true, "helper_overlay": false, "antialiasing": -1, "sharpening": 0, "terrain_detail": false, "enhanced_water": false, "discord_activity": true, "renderer": 0, "path_tracing": false, "show_fps": false, "hardware_check": 0, "free_movement": true, "smart_ai": true,
	"window_mode": 0, "window_width": 0, "window_height": 0, "frame_rate": 0}
const EDITION := {"music": 0.55, "effects": 0.8, "movies": 2, "blood": true, "map_tooltips": true, "autosave": true,
	"heroes_voices": true, "ambient_sounds": true, "adventure_fast": false, "animated_objects": true,
	"mouse_rotation": 1.0, "keyboard_rotation": 1.0, "mouse_scroll": 1.0, "keyboard_scroll": 1.0,
	"invert_rotation": false, "gamma": 0.0, "audio_reverse": false, "fog_animations": true, "show_blazons": true,
	"show_tutorial": true, "show_chat": true, "use_spells": true, "auto_camera": true, "auto_camera_dynamics": 50,
	"hide_motion": false, "hide_cast": false, "combat_phases": true, "heroes_casting": true, "creature_numbers": true,
	"ability_icons": true, "numbers_on_camera": true, "attack_order": true, "visual_log": false, "tutorial_events": "", "hotkeys": {}}
## Shipped settings.ini values that differ from the common defaults.
const EDITION_DEFAULTS := {"el1": {}, "el2": {"auto_camera_dynamics": 96, "visual_log": true}}
## Value ranges: [min, max] for numbers; bools are checked by type.
const RANGES := {"music": [0.0, 1.0], "effects": [0.0, 1.0], "ambience": [0.0, 1.0], "mouse_rotation": [0.0, 2.0],
	"keyboard_rotation": [0.0, 2.0], "mouse_scroll": [0.0, 2.0], "keyboard_scroll": [0.0, 2.0], "gamma": [-1.0, 1.0],
	"auto_camera_dynamics": [0, 100], "movies": [0, 2], "antialiasing": [-1, 2], "sharpening": [0, 2], "renderer": [0, 1], "hardware_check": [0, 2],
	"window_mode": [0, 2], "window_width": [0, 16384], "window_height": [0, 16384], "frame_rate": [-1, 1000]}

## Context, caption, then the default keys for each edition. Empty means the
## action is unavailable in that edition.
const HOTKEYS := {
	"end_phase": ["Battle", "End phase", [KEY_MASK_CTRL | KEY_E], [KEY_TAB]],
	"attack_all": ["Battle", "Attack with all ready creatures", [KEY_MASK_ALT | KEY_A], [KEY_MASK_ALT | KEY_A]],
	"auto_combat": ["Battle", "Toggle auto combat", [KEY_MASK_ALT | KEY_C], [KEY_MASK_ALT | KEY_C]],
	"skip": ["Battle", "Skip battle animation", [KEY_SPACE], [KEY_SPACE]],
	"battle_save": ["Battle", "Quick save", [KEY_F5], [KEY_F5]],
	"battle_load": ["Battle", "Quick load", [KEY_F9], [KEY_F9]],
	"reset_camera": ["Battle", "Reset camera", [KEY_R], [KEY_R]],
	"combat_log": ["Battle", "Combat log", [KEY_L], [KEY_L]],
	"artifacts": ["Battle", "Show artifacts", [], [KEY_A]],
	"hand": ["Battle", "Show spells in hand", [], [KEY_H]],
	"enchantments": ["Battle", "Show enchantments", [], [KEY_E]],
	"graveyard": ["Battle", "Show graveyard", [], [KEY_G]],
	"battle_slot_1": ["Battle", "Spell or artifact slot 1", [], [KEY_1]],
	"battle_slot_2": ["Battle", "Spell or artifact slot 2", [], [KEY_2]],
	"battle_slot_3": ["Battle", "Spell or artifact slot 3", [], [KEY_3]],
	"battle_slot_4": ["Battle", "Spell or artifact slot 4", [], [KEY_4]],
	"battle_slot_5": ["Battle", "Spell or artifact slot 5", [], [KEY_5]],
	"battle_slot_6": ["Battle", "Spell or artifact slot 6", [], [KEY_6]],
	"end_day": ["Map", "End turn or day", [KEY_MASK_CTRL | KEY_E, KEY_N], [KEY_MASK_CTRL | KEY_E]],
	"inventory": ["Map", "Spellbook or inventory", [KEY_I], [KEY_I]],
	"skills": ["Map", "Skills", [KEY_K], [KEY_K]],
	"skill_offer_1": ["Map", "Level-up skill choice 1", [], [KEY_1]],
	"skill_offer_2": ["Map", "Level-up skill choice 2", [], [KEY_2]],
	"skill_offer_3": ["Map", "Level-up skill choice 3", [], [KEY_3]],
	"notebook": ["Map", "Notebook", [], [KEY_N]],
	"global_spells": ["Map", "Global spells", [KEY_G], []],
	"cancel_order": ["Map", "Cancel hero order", [KEY_BACKSPACE], []],
	"map_save": ["Map", "Quick save", [KEY_F5], [KEY_F5]],
	"map_load": ["Map", "Quick load", [KEY_F8, KEY_F9], [KEY_F8, KEY_F9]],
	"center_hero": ["Map", "Center on hero", [KEY_HOME], [KEY_HOME, KEY_H]],
	"shop_confirm": ["Shops", "Confirm trade", [KEY_ENTER, KEY_KP_ENTER], [KEY_ENTER, KEY_KP_ENTER]],
	"shop_buy": ["Shops", "Stage a purchase", [KEY_B], []],
	"shop_undo": ["Shops", "Undo purchase or put back spell", [KEY_U], [KEY_BACKSPACE]],
}
const HOTKEY_MODIFIERS := KEY_MASK_CTRL | KEY_MASK_ALT | KEY_MASK_SHIFT | KEY_MASK_META

var values := {}
var edition := ""
var _editions := {}

func _init() -> void:
	values = SHARED.duplicate()
	values.merge(EDITION, true)

static func defaults(id: String) -> Dictionary:
	var result := EDITION.duplicate()
	result.merge(EDITION_DEFAULTS.get(id, {}), true)
	return result

## Switches the per-edition part of `values` to `id`, keeping the current
## edition's values for later.
func use_edition(id: String) -> void:
	if id == edition or id.is_empty(): return
	if not edition.is_empty(): _editions[edition] = _edition_part()
	else:
		# Values changed before any edition was chosen belong to both editions.
		var flat := defaults("")
		for each: String in ["el1", "el2"]:
			var part: Dictionary = _editions.get(each, defaults(each))
			for key: String in EDITION:
				if key != "hotkeys" and values[key] != flat[key]: part[key] = values[key]
			_editions[each] = part
	edition = id
	var part: Dictionary = _editions.get(id, defaults(id))
	for key: String in EDITION: values[key] = part.get(key, defaults(id)[key])
	ELUiSounds.use_volumes(values)

## The stored values of one edition (the active one reads `values`).
func edition_values(id: String) -> Dictionary:
	if id == edition: return _edition_part()
	return _editions.get(id, defaults(id)).duplicate()

## The 3D multisampling the "antialiasing" preference (`choice`) asks for on
## the video adapter named `adapter`.
static func multisampling(choice: int, adapter: String) -> Viewport.MSAA:
	if choice < 0: choice = 0 if adapter.to_lower().contains("llvmpipe") or adapter.to_lower().contains("software") else 1
	return [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(choice, 0, 2)]

## Applies the display preferences to the window's viewport.
static func apply_display(viewport: Viewport, preferences: Dictionary) -> void:
	if viewport == null: return
	viewport.msaa_3d = multisampling(int(preferences.get("antialiasing", -1)), RenderingServer.get_video_adapter_name())
	# Compatibility uses the wider 13-tap filter at High; Low and Medium both
	# use the same 5-tap filter. Keep the project default when the option is off.
	var shadow_quality := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if preferences.get("soft_shadows", false) else int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW))
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_quality)

## Window mode, window size and frame rate (the remake's Display page).
static func apply_window(preferences: Dictionary) -> void:
	if OS.has_feature("web") or OS.has_feature("mobile") or DisplayServer.get_name() == "headless": return
	var screen := DisplayServer.window_get_current_screen()
	match int(preferences.get("window_mode", 0)):
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var wanted := Vector2i(int(preferences.get("window_width", 0)), int(preferences.get("window_height", 0)))
			if wanted.x > 0 and wanted.y > 0 and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
				var usable := DisplayServer.screen_get_usable_rect(screen)
				wanted = wanted.min(usable.size)
				if DisplayServer.window_get_size() != wanted:
					DisplayServer.window_set_size(wanted)
					DisplayServer.window_set_position(usable.position + (usable.size - wanted) / 2)
	var rate := int(preferences.get("frame_rate", 0))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if rate == 0 else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = maxi(0, rate)

## Window sizes offered on the Display page: common ones that fit the screen,
## and the screen's own.
static func window_sizes() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var result: Array[Vector2i] = []
	for size: Vector2i in [Vector2i(1024, 768), Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1280, 1024), Vector2i(1366, 768),
			Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200),
			Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3440, 1440), Vector2i(3840, 2160)]:
		if size.x <= screen.x and size.y <= screen.y: result.append(size)
	if screen.x > 0 and not result.has(screen): result.append(screen)
	return result

## Frame rates offered: 0 (the display's own, V-Sync), caps and -1 (none).
const FRAME_RATES := [0, 30, 60, 75, 90, 100, 120, 144, 165, 180, 240, 360, -1]

func _edition_part() -> Dictionary:
	var part := {}
	for key: String in EDITION: part[key] = values.get(key, EDITION[key])
	return part

static func _clean(key: String, value: Variant, fallback: Variant) -> Variant:
	if key == "hotkeys":
		var result := {}
		if value is Dictionary:
			for action: String in HOTKEYS:
				var code: Variant = value.get(action)
				if (code is int or code is float) and is_finite(float(code)) and float(code) == floor(float(code)) and code > 0 and code <= 0x7fffffff:
					result[action] = int(code)
		return result
	if fallback is bool: return value if value is bool else fallback
	if fallback is String: return value if value is String and value.length() <= 256 and value.replace("0", "").replace("1", "").is_empty() else fallback
	if not (value is int or value is float) or not is_finite(float(value)): return fallback
	var bounds: Array = RANGES.get(key, [])
	if fallback is int:
		var number := int(value)
		return clampi(number, int(bounds[0]), int(bounds[1])) if not bounds.is_empty() else number
	return clampf(float(value), float(bounds[0]), float(bounds[1])) if not bounds.is_empty() else float(value)

static func hotkey_defaults(id: String, action: String) -> Array:
	return HOTKEYS[action][3 if id == "el2" else 2]

func hotkey_overrides(id: String) -> Dictionary:
	return values.hotkeys if id == edition else _editions.get(id, {}).get("hotkeys", {})

static func hotkey_action(preferences: ELSettings, id: String, group: String, event: InputEventKey) -> String:
	var overrides := preferences.hotkey_overrides(id) if preferences != null and event.device != InputEvent.DEVICE_ID_EMULATION else {}
	var logical := int(event.get_keycode_with_modifiers())
	var physical := int(event.get_physical_keycode_with_modifiers())
	for action: String in HOTKEYS:
		var defaults := hotkey_defaults(id, action)
		if HOTKEYS[action][0] != group or defaults.is_empty(): continue
		var keys: Array = [overrides[action]] if overrides.has(action) else defaults
		if logical in keys or physical in keys: return action
	return ""

func set_hotkey(id: String, action: String, code: int) -> String:
	var group: String = HOTKEYS[action][0]
	var key := code & ~HOTKEY_MODIFIERS
	if key in [0, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F7, KEY_F10, KEY_QUOTELEFT,
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN] or (group == "Map" and (key in [KEY_W, KEY_A, KEY_S, KEY_D] or (id == "el1" and key == KEY_H))):
		return "This key is reserved."
	if (group != "Battle" and key == KEY_TAB) or (group == "Battle" and key in [KEY_ENTER, KEY_KP_ENTER]): return "This key is reserved."
	var overrides := hotkey_overrides(id).duplicate()
	for other: String in HOTKEYS:
		if other == action or HOTKEYS[other][0] != group: continue
		var defaults := hotkey_defaults(id, other)
		if defaults.is_empty(): continue
		if code in ([overrides[other]] if overrides.has(other) else defaults): return "This shortcut is already assigned."
	overrides[action] = code
	_set_hotkeys(id, overrides)
	return ""

func reset_hotkeys(id: String) -> void:
	_set_hotkeys(id, {})

func _set_hotkeys(id: String, overrides: Dictionary) -> void:
	if id == edition: values.hotkeys = overrides
	else:
		if not _editions.has(id): _editions[id] = defaults(id)
		_editions[id].hotkeys = overrides

## Reads the file. A file from before per-edition settings (flat keys) gives
## its values to both editions. With no active edition, the edition that was
## active when the file was saved becomes active.
func load_file(path := "user://settings.json") -> void:
	if not FileAccess.file_exists(path): return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if raw is not Dictionary: return
	var shared: Dictionary = raw.get("shared", raw) if raw.get("shared") is Dictionary else raw
	for key: String in SHARED: values[key] = _clean(key, shared.get(key), values[key])
	var current := edition
	var version: Variant = raw.get("version", 0)
	var legacy: bool = (version is int or version is float) and version < SETTINGS_VERSION
	if (version is int or version is float) and version < 4 and int(values.sharpening) == 1: values.sharpening = 0
	for id: String in ["el1", "el2"]:
		var source: Variant = raw.get(id) if raw.get(id) is Dictionary else raw
		var part := defaults(id)
		for key: String in EDITION: part[key] = _clean(key, source.get(key), part[key])
		# Older files saved EL2's bright default even when Gamma was untouched.
		# The Options slider uses steps of 0.02, so it could not set this value.
		if legacy and id == "el2" and is_equal_approx(float(part.gamma), 0.071429):
			part.gamma = EDITION.gamma
		_editions[id] = part
	# Without an active edition, the edition active when the file was saved
	# becomes the active one.
	var shown := current if not current.is_empty() else str(raw.get("edition", ""))
	if _editions.has(shown):
		edition = shown
		var part: Dictionary = _editions[shown]
		for key: String in EDITION: values[key] = part[key]
	else:
		# No edition yet: a value both editions share is shown (a file saved
		# before any edition was chosen holds the same values in both).
		var flat := defaults("")
		for key: String in EDITION:
			values[key] = _editions.el1[key] if _editions.el1[key] == _editions.el2[key] else flat[key]
	ELUiSounds.use_volumes(values)

func save_file(path := "user://settings.json") -> bool:
	ELUiSounds.use_volumes(values)
	var data := {"version": SETTINGS_VERSION, "shared": {}}
	for key: String in SHARED: data.shared[key] = values[key]
	# Values set before any edition was chosen belong to both editions.
	for id: String in ["el1", "el2"]:
		data[id] = edition_values(id) if not edition.is_empty() else _edition_part()
		if edition.is_empty() and _editions.has(id): data[id].hotkeys = hotkey_overrides(id)
	if not edition.is_empty(): data["edition"] = edition
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	return true
