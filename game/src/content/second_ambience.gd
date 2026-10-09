class_name ELSecondAmbience
extends RefCounted
## Second game: script-driven map presentation — music, particle effects and
## positional sounds.
##
## The shipped library (Maps/adventure_lib) runs WeatherSegment and
## MusicSegment from its Hook_OnPostStep, 15 times per second; chapters and
## their cutscenes start effects and sounds of their own, directly or through
## the command queue. This class keeps what the scripts ask the engine to
## present, so the view can draw it and a save can restore it:
## - the background theme (ExStartBackgroundTheme / ExStopBackgroundTheme),
##   with its fade-in and fade-out seconds;
## - named particle effects (ExStartEffect / ExFinishEffect and the queued
##   StartEffect / FinishEffect): file, position, loop count (-1 loops until
##   finished), the post-step tick they started on, and whether a cutscene
##   (the command queue) started it. A record stays until it is finished by
##   name, even after its animation has played out;
## - named looping positional sounds (ExSoundBeginFX / the queued StartSound
##   with the loop flag, until ExSoundCancelFX / FinishSound).
## Starting a name that is already running replaces it (is called
## first by both start routines). An effect file the game does not have starts
## nothing. Queued effect and sound commands complete at once; cutscenes time
## them with Wait commands.

## Theme fades used when a script passes none (settings.ini MusicThemeFadeIn/Out).
const DEFAULT_FADE := 0.6
## The terrain particle family (weather and scenery).
const EFFECT_FOLDER := "terrainpfx/"
const MAX_ENTRIES := 64

static func blank() -> Dictionary:
	return {"tick": 0, "theme": "", "fade_in": DEFAULT_FADE, "fade_out": DEFAULT_FADE, "effects": {}, "sounds": {}}

## settings.ini of the installation: MusicThemeFadeIn / MusicThemeFadeOut.
static func theme_fades(profile: ELProfile) -> Vector2:
	var fades := Vector2(DEFAULT_FADE, DEFAULT_FADE)
	var path := profile.file("settings.ini")
	if path.is_empty(): return fades
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var pair := line.strip_edges().split("=", true, 1)
		if pair.size() != 2 or not pair[1].is_valid_float(): continue
		if pair[0].strip_edges() == "MusicThemeFadeIn": fades.x = maxf(0.0, pair[1].to_float())
		elif pair[0].strip_edges() == "MusicThemeFadeOut": fades.y = maxf(0.0, pair[1].to_float())
	return fades

static func is_terrain_effect(file: String) -> bool:
	return ELArchive.key(file).begins_with(EFFECT_FOLDER)

## One post-step: effect clocks advance with it.
static func step(state: ELAdventureSession) -> void:
	state.ambience.tick = int(state.ambience.tick) + 1

## ExStartBackgroundTheme(theme[, fade_in[, fade_out]]); a negative or missing
## fade uses the mission default.
static func start_theme(state: ELAdventureSession, args: Array) -> void:
	var theme := str(args[0]) if not args.is_empty() and args[0] != null else ""
	if theme.is_empty(): return
	var fade_in := float(args[1]) if args.size() > 1 and (args[1] is float or args[1] is int) and float(args[1]) >= 0.0 else state.theme_fade.x
	var fade_out := float(args[2]) if args.size() > 2 and (args[2] is float or args[2] is int) and float(args[2]) >= 0.0 else state.theme_fade.y
	var ambience: Dictionary = state.ambience
	# The same theme already playing is not restarted.
	var same: bool = ambience.theme == theme
	ambience.theme = theme
	ambience.fade_in = fade_in
	ambience.fade_out = fade_out
	if not same: state.event.emit({"kind": "background_theme", "theme": theme, "fade_in": fade_in, "fade_out": fade_out})

static func stop_theme(state: ELAdventureSession) -> void:
	var ambience: Dictionary = state.ambience
	if str(ambience.theme).is_empty(): return
	ambience.theme = ""
	state.event.emit({"kind": "background_theme", "theme": "", "fade_in": 0.0, "fade_out": float(ambience.fade_out)})

## ExStartEffect(name, file, x, y, z[, loops]); world coordinates as returned by
## ExGetTilePoint (two units per cell, z up). `story` marks an effect a
## cutscene started through the command queue (which passes no loop count).
static func start_effect(state: ELAdventureSession, args: Array, story := false) -> void:
	if args.size() < 5 or args[0] == null or args[1] == null: return
	var name := str(args[0])
	var file := ELArchive.key(str(args[1]))
	finish_effect(state, name)
	if not has_effect_file(state, file):
		push_warning("Effect not found: " + str(args[1]))
		return
	var effects: Dictionary = state.ambience.effects
	if effects.size() >= MAX_ENTRIES: return
	var loops := int(args[5]) if not story and args.size() > 5 and (args[5] is float or args[5] is int) else -1
	var entry := {"file": file, "x": _number(args[2]), "y": _number(args[3]), "z": _number(args[4]), "loops": loops, "tick": int(state.ambience.tick), "story": story}
	effects[name] = entry
	state.event.emit({"kind": "script_effect", "name": name, "entry": entry.duplicate()})

static func has_effect_file(state: ELAdventureSession, file: String) -> bool:
	if file.is_empty(): return false
	var archive: Variant = state.map.profile.archives.get("pfx") if state.map != null and state.map.profile != null else null
	return archive == null or archive.has(file)

static func finish_effect(state: ELAdventureSession, name: Variant) -> void:
	if name == null: return
	var effects: Dictionary = state.ambience.effects
	if effects.erase(str(name)): state.event.emit({"kind": "script_effect", "name": str(name), "entry": {}})

## ExOrientEffectByObject(name, object) and the queued OrientEffectByObject:
## the running effect takes the object's facing at that moment (
## ). The facing is not kept with the record; a loaded save draws the
## effect unturned.
static func orient_effect(state: ELAdventureSession, name: Variant, object_id: Variant) -> void:
	if name == null or str(name).is_empty() or object_id == null: return
	var item := state.object(object_id)
	if item.is_empty() or not state.ambience.effects.has(str(name)): return
	state.event.emit({"kind": "script_effect_orient", "name": str(name), "id": int(item.uid)})

## ExSoundBeginFX(name, file, x, y, z, near, far, loop).
static func start_sound(state: ELAdventureSession, args: Array) -> void:
	if args.size() < 2 or args[0] == null or args[1] == null: return
	var name := str(args[0])
	cancel_sound(state, name)
	var entry := {"file": str(args[1]), "x": _number(args[2] if args.size() > 2 else 0), "y": _number(args[3] if args.size() > 3 else 0), "z": _number(args[4] if args.size() > 4 else 0),
		"near": _number(args[5] if args.size() > 5 else 0), "far": _number(args[6] if args.size() > 6 else 0), "loop": _flag(args[7] if args.size() > 7 else null)}
	# Only looping sounds outlive the call; one-shots are reported and forgotten.
	if entry.loop and state.ambience.sounds.size() < MAX_ENTRIES: state.ambience.sounds[name] = entry
	state.event.emit({"kind": "positional_sound", "name": name, "entry": entry.duplicate()})

static func cancel_sound(state: ELAdventureSession, name: Variant) -> void:
	if name == null: return
	state.ambience.sounds.erase(str(name))
	state.event.emit({"kind": "positional_sound", "name": str(name), "entry": {}})

## A script flag: nil is off, a number is on unless it truncates to
## 0, anything else is on.
static func _flag(value: Variant) -> bool:
	if value == null: return false
	if value is float or value is int: return int(value) != 0
	if value is bool: return value
	return true

static func _number(value: Variant) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) else 0.0

static func encode(state: ELAdventureSession) -> Dictionary:
	return state.ambience.duplicate(true)

## Saves from before this state carry none: a blank state (the library's own
## timers, saved with the script, restart the theme and effects). Saves from
## before story effects carry terrain effects only and no story flag.
static func restore(state: ELAdventureSession, raw: Variant) -> bool:
	state.ambience = blank()
	if raw == null: return true
	if not raw is Dictionary: return false
	if not ELLuaSave._integer(raw.get("tick"), 0, 0x7fffffff) or not raw.get("theme") is String: return false
	for key: String in ["fade_in", "fade_out"]:
		if not (raw.get(key) is float or raw.get(key) is int) or not is_finite(float(raw[key])) or float(raw[key]) < 0.0: return false
	if not raw.get("effects") is Dictionary or not raw.get("sounds") is Dictionary: return false
	if raw.effects.size() > MAX_ENTRIES or raw.sounds.size() > MAX_ENTRIES: return false
	var effects := {}
	for name: Variant in raw.effects:
		var entry: Variant = raw.effects[name]
		if not name is String or not entry is Dictionary or not entry.get("file") is String or str(entry.file).is_empty(): return false
		if entry.has("story") and not entry.story is bool: return false
		if not ELLuaSave._integer(entry.get("tick"), 0, int(raw.tick)) or not ELLuaSave._integer(entry.get("loops"), -1, 0x7fffffff): return false
		for key: String in ["x", "y", "z"]:
			if not (entry.get(key) is float or entry.get(key) is int) or not is_finite(float(entry[key])): return false
		effects[name] = {"file": entry.file, "x": float(entry.x), "y": float(entry.y), "z": float(entry.z), "loops": int(entry.loops), "tick": int(entry.tick), "story": bool(entry.get("story", false))}
	var sounds := {}
	for name: Variant in raw.sounds:
		var entry: Variant = raw.sounds[name]
		if not name is String or not entry is Dictionary or not entry.get("file") is String or not entry.get("loop") is bool: return false
		for key: String in ["x", "y", "z", "near", "far"]:
			if not (entry.get(key) is float or entry.get(key) is int) or not is_finite(float(entry[key])): return false
		sounds[name] = {"file": entry.file, "x": float(entry.x), "y": float(entry.y), "z": float(entry.z), "near": float(entry.near), "far": float(entry.far), "loop": entry.loop}
	state.ambience = {"tick": int(raw.tick), "theme": raw.theme, "fade_in": float(raw.fade_in), "fade_out": float(raw.fade_out), "effects": effects, "sounds": sounds}
	return true
