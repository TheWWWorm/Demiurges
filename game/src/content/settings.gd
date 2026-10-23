class_name ELSettings
extends RefCounted
## Player preferences. Each original game keeps its own settings, so every
## original option (and the volumes and movie mode) is stored per edition;
## `values` is the view of the active edition plus the shared remake-only
## settings. Call use_edition() when the active game changes.
##
## Shared remake settings: "ambience" volume, "shadows", optional "soft_shadows",
## optional "terrain_detail" on maps and in battles, second-game
## adventure "weather" particles, "helper_overlay" (remake-only English readouts,
## hints and shortcut buttons over the original screens; off by default),
## "antialiasing" (-1 automatic: 2x multisampling unless the renderer is a
## software one; 0 off; 1 2x; 2 4x multisampling of the 3D scenes).
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
const SHARED := {"ambience": 0.55, "shadows": true, "soft_shadows": false, "weather": true, "helper_overlay": false, "antialiasing": -1, "sharpening": 1, "terrain_detail": false}
const EDITION := {"music": 0.55, "effects": 0.8, "movies": 2, "blood": true, "map_tooltips": true, "autosave": true,
	"heroes_voices": true, "ambient_sounds": true, "adventure_fast": false, "animated_objects": true,
	"mouse_rotation": 1.0, "keyboard_rotation": 1.0, "mouse_scroll": 1.0, "keyboard_scroll": 1.0,
	"invert_rotation": false, "gamma": 0.0, "audio_reverse": false, "fog_animations": true, "show_blazons": true,
	"show_tutorial": true, "show_chat": true, "use_spells": true, "auto_camera": true, "auto_camera_dynamics": 50,
	"hide_motion": false, "hide_cast": false, "combat_phases": true, "heroes_casting": true, "creature_numbers": true,
	"ability_icons": true, "numbers_on_camera": true, "attack_order": true, "visual_log": false, "tutorial_events": ""}
## Shipped settings.ini values that differ from the common defaults.
const EDITION_DEFAULTS := {"el1": {}, "el2": {"auto_camera_dynamics": 96, "gamma": 0.071429, "visual_log": true}}
## Value ranges: [min, max] for numbers; bools are checked by type.
const RANGES := {"music": [0.0, 1.0], "effects": [0.0, 1.0], "ambience": [0.0, 1.0], "mouse_rotation": [0.0, 2.0],
	"keyboard_rotation": [0.0, 2.0], "mouse_scroll": [0.0, 2.0], "keyboard_scroll": [0.0, 2.0], "gamma": [-1.0, 1.0],
	"auto_camera_dynamics": [0, 100], "movies": [0, 2], "antialiasing": [-1, 2], "sharpening": [0, 2]}

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
				if values[key] != flat[key]: part[key] = values[key]
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

func _edition_part() -> Dictionary:
	var part := {}
	for key: String in EDITION: part[key] = values.get(key, EDITION[key])
	return part

static func _clean(key: String, value: Variant, fallback: Variant) -> Variant:
	if fallback is bool: return value if value is bool else fallback
	if fallback is String: return value if value is String and value.length() <= 256 and value.replace("0", "").replace("1", "").is_empty() else fallback
	if not (value is int or value is float) or not is_finite(float(value)): return fallback
	var bounds: Array = RANGES.get(key, [])
	if fallback is int:
		var number := int(value)
		return clampi(number, int(bounds[0]), int(bounds[1])) if not bounds.is_empty() else number
	return clampf(float(value), float(bounds[0]), float(bounds[1])) if not bounds.is_empty() else float(value)

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
	for id: String in ["el1", "el2"]:
		var source: Variant = raw.get(id) if raw.get(id) is Dictionary else raw
		var part := defaults(id)
		for key: String in EDITION: part[key] = _clean(key, source.get(key), part[key])
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
	var data := {"version": 2, "shared": {}}
	for key: String in SHARED: data.shared[key] = values[key]
	# Values set before any edition was chosen belong to both editions.
	for id: String in ["el1", "el2"]: data[id] = edition_values(id) if not edition.is_empty() else _edition_part()
	if not edition.is_empty(): data["edition"] = edition
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	return true
