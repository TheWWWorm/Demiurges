class_name ELBattleAudio
extends Node
## Presentation audio has its own random stream; playing sounds never changes
## card draws or AI decisions. Each battle owns and stops its playback nodes.
##
## Combat sound effects, all on the effects volume:
## - spells: each card starts its presentation effects (combat_sound_table.gd);
##   an effect's sound is the `Sound` file of that effect in the edition's
##   Resources/Effects.xml, started with the effect. An effect whose .fx sound
##   track is never switched on stays silent, as in the originals.
## - combat hits: HitTable/<attacker AttackSndType>/<target SkinSndType>/hit.wav.
## - figures: Creatures/<SndDir>/<action>.wav. Hero figures (he* models) speak
##   their hit, and with heroes' voices on their summon/instant/enchantment
##   casts, from Creatures/<SndDir>/voice/<action>01..03.wav (one at random).
## A missing file is skipped silently.
const VOICED_CASTS := ["summon", "instant", "enchantment"]
const SoundTable := preload("res://src/duel/combat_sound_table.gd")

var profile: ELProfile
var edition := ""
var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var tracks: Array[String] = []
var track_index := 0
var ambient_sounds: Array[String] = []
var ambient_clock := 4.0
var random := RandomNumberGenerator.new()
var loops: Array[AudioStreamPlayer3D] = []
## Started sound paths (latest 40) and every requested path, started or not.
var played: Array[String] = []
var requested: Array[String] = []
var settings := {"music": 0.55, "ambience": 0.55, "effects": 0.8, "heroes_voices": true, "ambient_sounds": true}
## Effect name (lower case) -> Effects.xml sound path; "" when it has none.
var effect_files := {}
var _effect_names := {}
var _audible := {}

func _exit_tree() -> void:
	set_process(false)
	for child: Node in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null

func build(data: ELProfile, arena: Dictionary, volumes: Dictionary) -> void:
	profile = data
	edition = profile.id
	random.randomize()
	settings.merge(volumes, true)
	load_effects()
	music = AudioStreamPlayer.new()
	add_child(music)
	music.finished.connect(_next_track)
	ambience = AudioStreamPlayer.new()
	add_child(ambience)
	var configured: Variant = arena.get("Music", [])
	tracks.assign(configured if configured is Array else [configured])
	_next_track()
	var ambient := "Ambient/" + String(arena.get("Ambient", "")) + "/circle.wav"
	var sound := ELAudio.sound(profile, ambient)
	if sound != null:
		# Loop points are instance settings, never mutations of a shared stream.
		sound = sound.duplicate()
		sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sound.loop_end = int(sound.get_length() * sound.mix_rate)
		ambience.stream = sound
		ambience.play()
	var directory := ELArchive.key("Ambient/" + String(arena.get("Ambient", "")) + "/")
	if profile.archives.has("sfx"):
		for name: String in profile.archives.sfx.entries:
			if name.begins_with(directory) and name.ends_with(".wav") and name != ELArchive.key(ambient):
				ambient_sounds.append(name)
	# Battlefield-specific loops (waterfall, rain) have a source and two radii.
	var configured_sounds: Variant = arena.get("Sounds", [])
	var sounds: Array = configured_sounds if configured_sounds is Array else [configured_sounds]
	var parameters: Array = arena.get("SoundsParams", [])
	for i in sounds.size():
		var loop := ELAudio.sound(profile, String(sounds[i]))
		if loop == null: continue
		loop = loop.duplicate()
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_end = int(loop.get_length() * loop.mix_rate)
		var player := AudioStreamPlayer3D.new()
		add_child(player)
		player.bus = ELAudio.positional_bus(bool(settings.get("audio_reverse", false)))
		player.stream = loop
		if parameters.size() >= (i + 1) * 5:
			var at := i * 5
			player.position = ELFigure.vector(Vector3(parameters[at], parameters[at + 1], parameters[at + 2]))
			player.unit_size = maxf(1.0, float(parameters[at + 3]))
			player.max_distance = float(parameters[at + 4])
		player.play()
		loops.append(player)
	for i in 16:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	apply_volumes(settings)

## Reads the edition's effect catalogue: <Effect name="..."> with a <Sound file="...">.
func load_effects() -> void:
	effect_files.clear()
	_effect_names.clear()
	_audible.clear()
	var path := profile.file("Resources/Effects.xml") if profile != null else ""
	if path.is_empty(): return
	var parser := XMLParser.new()
	if parser.open(path) != OK: return
	var current := ""
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT: continue
		var node := parser.get_node_name()
		if node == "Effect":
			current = parser.get_named_attribute_value_safe("name")
			if not current.is_empty():
				effect_files[current.to_lower()] = ""
				_effect_names[current.to_lower()] = current
		elif node == "Sound" and not current.is_empty() and String(effect_files.get(current.to_lower(), "")).is_empty():
			effect_files[current.to_lower()] = parser.get_named_attribute_value_safe("file").strip_edges().replace("\\", "/")

## The sound an effect starts, or "" when it has none or its sound track is
## switched off in the effect's .fx file.
func effect_sound(effect: String) -> String:
	var key := effect.to_lower()
	var file: String = effect_files.get(key, "")
	if file.is_empty(): return ""
	if not _audible.has(key): _audible[key] = _track_switched_on(String(_effect_names.get(key, effect)))
	return file if _audible[key] else ""

## The FxSound track keys one frame per entry (position, two radii, on flag).
## A missing .fx leaves the sound on.
func _track_switched_on(effect: String) -> bool:
	if not profile.archives.has("fx"): return true
	var bytes := profile.read("fx", ELArchive.key(effect + ".fx"))
	if bytes.is_empty(): return true
	var at := _find(bytes, "SOUN".to_ascii_buffer())
	if at < 0 or at + 10 > bytes.size(): return true
	var size := bytes.decode_u32(at + 4)
	var name_size := bytes.decode_u16(at + 8)
	var first := at + 10 + name_size
	var last := mini(at + 8 + size, bytes.size())
	var key := first
	while key + 21 <= last:
		if bytes[key + 20] != 0: return true
		key += 21
	return false

static func _find(bytes: PackedByteArray, pattern: PackedByteArray) -> int:
	for i in bytes.size() - pattern.size() + 1:
		var hit := true
		for j in pattern.size():
			if bytes[i + j] != pattern[j]:
				hit = false
				break
		if hit: return i
	return -1

func _next_track() -> void:
	for attempt in tracks.size():
		var path := profile.file("Resources/Music/" + tracks[track_index] + ".mp3")
		track_index = (track_index + 1) % tracks.size()
		if path.is_empty(): continue
		var stream := AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(path)
		music.stream = stream
		music.play()
		return

func apply_volumes(values: Dictionary) -> void:
	settings.merge(values, true)
	ELUiSounds.use_volumes(settings)
	if music != null: music.volume_db = linear_to_db(float(settings.music)) - 6.0
	if ambience != null: ambience.volume_db = ambience_db()
	for voice in voices: voice.volume_db = linear_to_db(float(settings.effects)) - 3.0
	for loop in loops: loop.volume_db = ambience_db()
	if not loops.is_empty(): ELAudio.positional_bus(bool(settings.get("audio_reverse", false)))

## The Options "Ambient sounds" switch silences the arena ambience.
func ambience_db() -> float:
	return linear_to_db(float(settings.ambience)) - 8.0 if bool(settings.get("ambient_sounds", true)) else -80.0

func _process(delta: float) -> void:
	if ambient_sounds.is_empty(): return
	ambient_clock -= delta
	if ambient_clock > 0: return
	ambient_clock = random.randf_range(8, 18)
	var sound := ELAudio.sound(profile, ambient_sounds[random.randi_range(0, ambient_sounds.size() - 1)])
	if sound == null: return
	var voice := AudioStreamPlayer.new()
	add_child(voice)
	voice.stream = sound
	voice.volume_db = ambience_db()
	voice.finished.connect(voice.queue_free)
	voice.play()

## Starts a sound on a free effects voice; false when the file is missing or
## every voice is busy.
func play(path: String) -> bool:
	requested.append(path)
	if requested.size() > 80: requested.pop_front()
	var stream := ELAudio.sound(profile, path)
	if stream == null: return false
	for voice in voices:
		if not voice.playing:
			voice.stream = stream
			voice.play()
			played.append(path)
			if played.size() > 40: played.pop_front()
			return true
	return false

## Sound paths of a list of effects, each file once.
func effect_paths(effects: Array) -> Array[String]:
	var paths: Array[String] = []
	for effect: Variant in effects:
		var path := effect_sound(String(effect))
		if not path.is_empty() and not paths.has(path): paths.append(path)
	return paths

## The sounds a cast of `card` starts.
func spell_paths(card: String) -> Array[String]:
	return effect_paths(SoundTable.card_effects(profile, card))

func spell(card: String) -> void:
	for path in spell_paths(card): play(path)

func trigger(card: String) -> void:
	for path in effect_paths(SoundTable.trigger_effects(edition, card)): play(path)

func effect(name: String) -> void:
	var path := effect_sound(name)
	if not path.is_empty(): play(path)

## Material hit of a combat strike: the attacker's weapon class against the
## target's skin class; nothing when either class is unknown.
func hit_path(attacker: Node, target: Node) -> String:
	if attacker == null or target == null: return ""
	var weapon := String(attacker.get_meta("attack_sound", "")).strip_edges()
	var skin := String(target.get_meta("skin_sound", "")).strip_edges()
	if weapon.is_empty() or skin.is_empty(): return ""
	return "HitTable/%s/%s/hit.wav" % [weapon, skin]

func hit(attacker: Node, target: Node) -> void:
	var path := hit_path(attacker, target)
	if not path.is_empty(): play(path)

## A figure's own sound for an action (hit, death, attack, summon, ...).
func unit_path(model: Node, action: String) -> String:
	var directory: String = model.get_meta("sound_directory", "")
	if directory.is_empty(): return ""
	if model.get_meta("voice", false) and (action == "hit" or (bool(settings.get("heroes_voices", true)) and action in VOICED_CASTS)):
		return "Creatures/%s/voice/%s%02d.wav" % [directory, action, random.randi_range(1, 3)]
	return "Creatures/" + directory + "/" + action + ".wav"

func unit(model: Node, action: String) -> void:
	var path := unit_path(model, action)
	if not path.is_empty(): play(path)
