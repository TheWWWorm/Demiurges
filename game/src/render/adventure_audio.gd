class_name ELAdventureAudio
extends Node
## Original chapter speech and script-selected music. Voices are separate from
## quest state, so skipping speech cannot alter the simulation's random stream.
##
## Second game: the background theme cross-fades (the old theme fades out over
## its fade-out, the new one fades in over its fade-in), repeats while it is
## selected, and is not restarted when the same theme is asked for again.
## Scripted emphasis themes cross-fade with it. Script sounds (ExSoundBeginFX) are positional: the
## volume falls off linearly from the near to the far distance, measured on the
## ground from the camera's target, and looping ones (weather) repeat until
## cancelled.
##
## First game: no scripts choose music. The map plays one theme for the whole
## mission, ad_<colour>01 for the local player's colour, repeating; hero
## position, terrain and turns never change it. Opening a battle cuts it and
## returning to the map starts it again from the beginning. There is no map
## weather in the first game.
var profile: ELProfile
var voice: AudioStreamPlayer
var background: AudioStreamPlayer
var emphasis: AudioStreamPlayer
var effect: AudioStreamPlayer
## The theme fading out after a switch.
var fading: AudioStreamPlayer
var settings: ELSettings
var streams: Dictionary = {}
var played: Array[String] = []
## Current background theme name ("" none) and the one fading out.
var theme := ""
var fading_theme := ""
var _theme_fade := Vector2.ZERO
var _fade_in := 0.0
var _fade_in_time := 0.0
var _fade_out := 0.0
var _fade_out_time := 0.0
var _fade_out_gain := 1.0
var _emphasis_name := ""
var _emphasis_fade := Vector2.ZERO
var _emphasis_time := 0.0
## Script sound name -> {player, position (Vector3), near, far}.
var sounds: Dictionary = {}
## Ground point the listener hears from (the camera target).
var listener := Vector3.ZERO
## The camera's view direction; placed sounds pan by their angle to it.
var listener_forward := Vector3.FORWARD
## The map is hidden behind a battle: new sounds start paused.
var suspended := false
## Volumes being previewed on the Options screen (empty: the saved ones).
var _volumes := {}

func build(data: ELProfile, preferences: ELSettings) -> void:
	profile = data
	settings = preferences
	var path := profile.file("Resources/streamsn.reg")
	if not path.is_empty(): streams = ELRegistry.parse(FileAccess.get_file_as_bytes(path))
	voice = AudioStreamPlayer.new()
	background = AudioStreamPlayer.new()
	emphasis = AudioStreamPlayer.new()
	effect = AudioStreamPlayer.new()
	fading = AudioStreamPlayer.new()
	for player: AudioStreamPlayer in [voice, background, emphasis, effect, fading]: add_child(player)
	effect.volume_db = linear_to_db(maxf(0.0001, ELAudio.option_gain(float(settings.values.effects), profile.id)))
	voice.volume_db = linear_to_db(maxf(0.0001, ELAudio.option_gain(float(settings.values.effects), profile.id)))
	background.volume_db = music_db()
	fading.volume_db = music_db()
	emphasis.volume_db = background.volume_db

## First-game adventure theme names by player colour (track 01 is the only one).
const FIRST_COLOURS := ["Red", "Green", "Blue", "Black"]

## First game: the adventure theme of the local player's colour, "" for none.
static func first_theme(state: ELAdventureSession) -> String:
	var colour := str(state.players.get(state.current_player, {}).get("color", ""))
	return "ad_%s%02d" % [colour, 1] if colour in FIRST_COLOURS else ""

## First game: the mission theme starts at once at the music volume (no fade).
func start_first(state: ELAdventureSession) -> bool:
	var name := first_theme(state)
	if name.is_empty(): return false
	return start_theme(name, 0.0, 0.0)

## First game: a battle cuts the map theme; the map's return restarts it.
func first_battle(opened: bool, state: ELAdventureSession) -> void:
	if opened:
		_theme_fade = Vector2.ZERO
		stop_theme()
	else: start_first(state)

## Leaving the finished map for the Hall of Fame: the music stops at once.
func cut_music() -> void:
	_theme_fade = Vector2.ZERO
	background.stop()
	background.stream = null
	theme = ""
	emphasis.stop()
	emphasis.stream = null
	_emphasis_name = ""
	_clear_fading()

func music_db() -> float:
	return linear_to_db(maxf(0.0001, ELAudio.option_gain(float(_volumes.get("music", settings.values.music)), profile.id))) - 6.0

## Applies music and effect volumes (and the ambient-sound switch) at once.
func apply_volumes(values: Dictionary) -> void:
	_volumes = {} if is_same(values, settings.values) else {"music": values.get("music", settings.values.music),
		"effects": values.get("effects", settings.values.effects), "ambient_sounds": values.get("ambient_sounds", true)}
	effect.volume_db = linear_to_db(maxf(0.0001, ELAudio.option_gain(float(_volumes.get("effects", settings.values.effects)), profile.id)))
	ELUiSounds.volume = clampf(float(_volumes.get("effects", settings.values.effects)), 0.0, 1.0)
	voice.volume_db = effect.volume_db
	background.volume_db = background_volume_now()
	emphasis.volume_db = _gain_db(_fade_gain(_emphasis_time, _emphasis_fade.x))
	for name: String in sounds: sounds[name].player.volume_db = _sound_db(sounds[name])
	ELAudio.positional_bus(bool(values.get("audio_reverse", settings.values.get("audio_reverse", false))))

## Every player that pauses with the map (battles, suspended view).
func players() -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = [voice, background, emphasis, fading]
	for name: String in sounds: result.append(sounds[name].player)
	return result

## Second game: the music and sounds already running in a restored session.
func restore(state: ELAdventureSession) -> void:
	var ambience: Dictionary = state.ambience
	if not str(ambience.get("theme", "")).is_empty(): start_theme(str(ambience.theme), 0.0, float(ambience.get("fade_out", 0.0)))
	for name: String in ambience.get("sounds", {}): start_sound(name, ambience.sounds[name])

func speak(id: String) -> bool:
	voice.stop()
	voice.stream = null
	var bytes := profile.read("sfx", "MissionVoices/" + id + ".mp3")
	if bytes.is_empty(): return false
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	voice.stream = stream
	voice.play()
	played.append(id)
	return true

func script_event(data: Dictionary) -> void:
	match data.kind:
		"background_theme":
			if str(data.theme).is_empty(): stop_theme()
			else: start_theme(str(data.theme), float(data.fade_in), float(data.fade_out))
		"positional_sound":
			if data.entry.is_empty(): cancel_sound(str(data.name))
			else: start_sound(str(data.name), data.entry)
		"ExStartEmphasisTheme":
			_start_emphasis(data.arguments, data.get("theme_fade", Vector2.ONE * ELSecondAmbience.DEFAULT_FADE))
		"ExStopEmphasisTheme":
			_stop_emphasis()

func start_theme(name: String, fade_in: float, fade_out: float) -> bool:
	if name == theme and background.stream != null: return true
	var stream := _theme_stream(name)
	if stream == null: return false
	_release_background()
	stream.loop = true
	background.stream = stream
	theme = name
	_theme_fade = Vector2(fade_in, fade_out)
	_fade_in = fade_in
	_fade_in_time = 0.0
	background.volume_db = music_db() if fade_in <= 0.0 else -80.0
	background.play()
	background.stream_paused = emphasis.stream != null
	return true

func stop_theme() -> void:
	_release_background()

## The playing background theme moves to the fading player.
func _release_background() -> void:
	if background.stream != null and emphasis.stream == null:
		_fade_player(background, theme, _theme_fade.y)
	background.stop()
	background.stream = null
	theme = ""

func _start_emphasis(args: Array, defaults: Vector2) -> void:
	if args.is_empty(): return
	var name := str(args[0])
	if name == _emphasis_name: return
	var stream := _theme_stream(name)
	if stream == null: return
	var fade_in := float(args[1]) if args.size() > 1 and args[1] != null else -1.0
	var fade_out := float(args[2]) if args.size() > 2 and args[2] != null else -1.0
	if emphasis.stream != null: _fade_player(emphasis, _emphasis_name, _emphasis_fade.y)
	elif background.stream != null: _fade_player(background, theme, _theme_fade.y)
	background.stream_paused = true
	emphasis.stop()
	emphasis.stream = stream
	_emphasis_name = name
	_emphasis_fade = Vector2(fade_in if fade_in >= 0.0 else defaults.x, fade_out if fade_out >= 0.0 else defaults.y)
	_emphasis_time = 0.0
	emphasis.volume_db = _gain_db(_fade_gain(0.0, _emphasis_fade.x))
	emphasis.play()

func _stop_emphasis() -> void:
	if emphasis.stream == null: return
	_fade_player(emphasis, _emphasis_name, _emphasis_fade.y)
	emphasis.stop()
	emphasis.stream = null
	_emphasis_name = ""
	_fade_in_time = 0.0
	background.volume_db = background_volume_now()
	background.stream_paused = false

func _clear_fading() -> void:
	fading.stop()
	fading.stream = null
	fading_theme = ""

func _fade_player(player: AudioStreamPlayer, name: String, duration: float) -> void:
	_clear_fading()
	if duration <= 0.0 or not player.playing: return
	fading.stream = player.stream
	fading_theme = name
	_fade_out = duration
	_fade_out_time = 0.0
	_fade_out_gain = db_to_linear(player.volume_db - music_db())
	fading.volume_db = player.volume_db
	fading.play(player.get_playback_position())

func background_volume_now() -> float:
	return _gain_db(_fade_gain(_fade_in_time, _fade_in))

func _fade_gain(time: float, duration: float) -> float:
	return minf(1.0, time / duration) if duration > 0.0 else 1.0

func _gain_db(fraction: float) -> float:
	return music_db() + linear_to_db(clampf(fraction, 0.0001, 1.0))

func start_sound(name: String, entry: Dictionary) -> void:
	cancel_sound(name)
	var source := ELAudio.sound(profile, str(entry.file))
	if source == null: return
	var stream: AudioStreamWAV = source
	if bool(entry.get("loop", false)):
		stream = source.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / ((2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if stream.stereo else 1))
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = stream
	var sound := {"player": player, "position": Vector3(float(entry.x), float(entry.z), -float(entry.y)), "near": float(entry.get("near", 0.0)), "far": float(entry.get("far", 0.0))}
	# A sound with a fall-off is placed: it gets a free panned bus.
	if sound.far > 0.0:
		var used: Array = sounds.values().map(func(other: Dictionary) -> StringName: return other.player.bus)
		var slot := 0
		while used.has(StringName("Positional Adventure %d" % slot)): slot += 1
		player.bus = ELAudio.pan_bus("Adventure %d" % slot, bool(settings.values.get("audio_reverse", false)))
	sounds[name] = sound
	player.volume_db = _sound_db(sound)
	_place(sound)
	player.play()
	player.stream_paused = suspended
	played.append(str(entry.file))
	if not bool(entry.get("loop", false)): player.finished.connect(_sound_finished.bind(name, player))

func _sound_finished(name: String, player: AudioStreamPlayer) -> void:
	if sounds.has(name) and sounds[name].player == player: cancel_sound(name)

func cancel_sound(name: String) -> void:
	var sound: Variant = sounds.get(name)
	if sound == null: return
	sound.player.stop()
	sound.player.queue_free()
	sounds.erase(name)

## Linear fall-off on the ground plane; a far distance of 0 means no fall-off.
func _sound_db(sound: Dictionary) -> float:
	if not bool(_volumes.get("ambient_sounds", settings.values.get("ambient_sounds", true))): return -80.0
	var base := linear_to_db(float(settings.values.get("ambience", 0.55)))
	var far: float = sound.far
	if far <= 0.0: return base
	var offset: Vector3 = sound.position - listener
	var distance := Vector2(offset.x, offset.z).length()
	var near: float = sound.near
	var gain := 1.0 if distance <= near else clampf(1.0 - (distance - near) / maxf(0.001, far - near), 0.0, 1.0)
	return base + linear_to_db(maxf(ELAudio.placed_gain(gain, profile.id), 0.0001))

func _process(delta: float) -> void:
	if not suspended and background.stream != null and not background.stream_paused and _fade_in_time < _fade_in:
		_fade_in_time += delta
		background.volume_db = background_volume_now()
	if not suspended and emphasis.stream != null and _emphasis_time < _emphasis_fade.x:
		_emphasis_time += delta
		emphasis.volume_db = _gain_db(_fade_gain(_emphasis_time, _emphasis_fade.x))
	if not suspended and fading.stream != null:
		_fade_out_time += delta
		if _fade_out_time >= _fade_out: _clear_fading()
		else: fading.volume_db = _gain_db(_fade_out_gain * (1.0 - _fade_out_time / _fade_out))
	for name: String in sounds:
		sounds[name].player.volume_db = _sound_db(sounds[name])
		_place(sounds[name])

## The original's stereo placement for a sound with a fall-off.
func _place(sound: Dictionary) -> void:
	if float(sound.far) <= 0.0: return
	sound.pan = ELAudio.stereo_pan(listener, listener_forward, sound.position)
	ELAudio.set_pan(sound.player.bus, sound.pan, profile.id)

func effect_sound(path: String) -> bool:
	var stream := ELAudio.sound(profile, path)
	if stream == null: return false
	effect.stream = stream
	effect.play()
	played.append(path)
	return true

func _theme_stream(name: String) -> AudioStreamMP3:
	var path := profile.file("Resources/Music/" + name + ".mp3")
	if path.is_empty(): return null
	var stream := AudioStreamMP3.new()
	stream.data = FileAccess.get_file_as_bytes(path)
	return stream

func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
