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
## The combat camera supplies the original's approximate ground-plane listener.
var listener: Camera3D
## Where the next play() call's sound is placed, from the gain helper that
## computed its distance (null: not placed, centred).
var _pan_source: Variant = null
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
var _effect_scales := {}
var _redzap_sound_source := {}
var _posrune_sound_source := {}
var _bless_stat_sound_sources := {}
var _redlightning_sound_source := {}
var _greensummon_sound_source := {}
var _stasis_sound_source := {}
var _healing_sound_source := {}
var _channel_loselife_source := {}
var _hunger_sound_source := {}
var _gainmana_sound_source := {}
var _el2_losemana_sound_source := {}
var _draw_sound_source := {}
var _powertap_drain_sound_source := {}
var _tap_life_sound_source := {}
var _mind_blast_sound_source := {}
var _amnesia_discard_sound_source := {}
var _disintegrate_sound_source := {}
var _cracking_ivies_sound_source := {}
var _twister_sound_source := {}
var _firestorm_wave_sound_source := {}
var _frwa_red_damage_sound_source := {}
var _comet_sound_source := {}
var _basilisk_sound_source := {}
var _annihilation_sound_source := {}
var _wnfl_explosion_sound_source := {}
var _fog_cantattack_sound_source := {}
var _blackdamage_sound_source := {}
var _target_possorcery_sound_source := {}
var _depress_gas_sound_source := {}
var _drowsy_gas_sound_source := {}
var _frenzy_gas_sound_source := {}
var _suffocation_gas_sound_source := {}
var _self_repair_sound_source := {}
var _fury_nature_sound_source := {}
var _stone_circle_sound_source := {}

func _exit_tree() -> void:
	set_process(false)
	for child: Node in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	# Leaving the panned buses at exit: otherwise the music and ambience
	# playbacks were still held when the program quit (exit leak warning).
	for voice in voices: voice.bus = &"Master"

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
		voice.bus = ELAudio.pan_bus("Battle %d" % i, bool(settings.get("audio_reverse", false)))
		voices.append(voice)
	apply_volumes(settings)

## Reads the edition's effect catalogue: <Effect name="..."> with a <Sound file="...">.
func load_effects() -> void:
	effect_files.clear()
	_effect_names.clear()
	_audible.clear()
	_effect_scales.clear()
	_redzap_sound_source.clear()
	_posrune_sound_source.clear()
	_bless_stat_sound_sources.clear()
	_redlightning_sound_source.clear()
	_greensummon_sound_source.clear()
	_stasis_sound_source.clear()
	_healing_sound_source.clear()
	_channel_loselife_source.clear()
	_hunger_sound_source.clear()
	_gainmana_sound_source.clear()
	_el2_losemana_sound_source.clear()
	_draw_sound_source.clear()
	_powertap_drain_sound_source.clear()
	_tap_life_sound_source.clear()
	_mind_blast_sound_source.clear()
	_amnesia_discard_sound_source.clear()
	_disintegrate_sound_source.clear()
	_cracking_ivies_sound_source.clear()
	_twister_sound_source.clear()
	_firestorm_wave_sound_source.clear()
	_frwa_red_damage_sound_source.clear()
	_comet_sound_source.clear()
	_basilisk_sound_source.clear()
	_annihilation_sound_source.clear()
	_wnfl_explosion_sound_source.clear()
	_fog_cantattack_sound_source.clear()
	_blackdamage_sound_source.clear()
	_target_possorcery_sound_source.clear()
	_depress_gas_sound_source.clear()
	_drowsy_gas_sound_source.clear()
	_frenzy_gas_sound_source.clear()
	_suffocation_gas_sound_source.clear()
	_self_repair_sound_source.clear()
	_fury_nature_sound_source.clear()
	_stone_circle_sound_source.clear()
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
			_effect_scales[current.to_lower()] = parser.get_named_attribute_value_safe("scale").to_float()

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

## EL1 and EL2 original RedZap each have their own SOUN track at the authored
## Start->Finish FX point. Read edition-specific keys and Effects.xml scale.
## Original starts the first active key; applies a
## ground-plane near/far fade.
## The camera as listener and the existing remake FX transform are bounded
## approximations: the executing original's precise pan/focus is unknown.
func _redzap_gain(caster: Node3D, target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster) or not is_instance_valid(target):
		return 1.0
	if _redzap_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("RedZap.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("redzap", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_redzap_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _redzap_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("redzap", {})
	if entry.is_empty(): return 1.0
	var where := ELCombatEffects.placement(entry, "Start", caster, "Finish", target)
	var sound_world: Vector3 = where * Vector3(_redzap_sound_source.position)
	var offset: Vector3 = listener.global_position - sound_world
	_pan_source = sound_world
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_redzap_sound_source.far) - distance) /
		(float(_redzap_sound_source.far) - float(_redzap_sound_source.near)), 0.0, 1.0)

## EL1 and EL2 Bless each place an authored PosRune model at the affected
## creature, not the hero. Both originals' .fx start FxSound1 at
## (0,0,2.1532245), near1/far2 with Effects.xml scale100. Each edition reads
## its own source files; camera-XZ remains an approximate listener.
func _bless_posrune_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _posrune_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("PosRune.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("posrune", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_posrune_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _posrune_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("posrune", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", target, "", null)
	var sound_world: Vector3 = where * Vector3(_posrune_sound_source.position)
	var offset: Vector3 = listener.global_position - sound_world
	_pan_source = sound_world
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_posrune_sound_source.far) - distance) /
		(float(_posrune_sound_source.far) - float(_posrune_sound_source.near)), 0.0, 1.0)

## Original EL1 BlessEnchantment@ and EL2@ each register three creature Target
## effects. Each edition's Effects.xml scale100 maps raw near1/far2 to
## world100/200. Scope this to normal BLSS only; other stat buffs and unbound
## requests stay unchanged.
func _bless_stat_gain(effect: String, target: Node3D) -> float:
	if edition not in ["el1", "el2"] or effect not in ["PosAttack", "PosDefence"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if not _bless_stat_sound_sources.has(effect):
		var source := {}
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key(effect + ".fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at >= 0 and at + 10 <= bytes.size():
			var size := bytes.decode_u32(at + 4)
			var label_len := bytes.decode_u16(at + 8)
			var key: int = at + 10 + label_len
			var last: int = mini(at + 8 + size, bytes.size())
			while key + 21 <= last:
				if bytes[key + 20] != 0:
					var scale := float(_effect_scales.get(effect.to_lower(), 0.0))
					var near := bytes.decode_float(key + 12) * scale
					var far := bytes.decode_float(key + 16) * scale
					if near >= 0.0 and far > near:
						source = {"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
							"near": near, "far": far}
					break
				key += 21
		_bless_stat_sound_sources[effect] = source
	var data: Dictionary = _bless_stat_sound_sources.get(effect, {})
	if data.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get(effect.to_lower(), {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var point: Vector3 = ELCombatEffects.placement(entry, "Target", target, "", null) * Vector3(data.position)
	var offset: Vector3 = listener.global_position - point
	_pan_source = point
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(data.far) - distance) / (float(data.far) - float(data.near)), 0.0, 1.0)

## Original EL1 and EL2 normal Call Lightning's RedLightning Target sound
## follows the creature's authored FX point, not the casting hero. Both
## editions have 30 active SOUN keys (near1/far6), with XML scale 10.
## Use the existing FX transform and approximate combat-camera ground listener.
func _call_lightning_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _redlightning_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("RedLightning.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("redlightning", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_redlightning_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _redlightning_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("redlightning", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", target, "", null)
	var point: Vector3 = where * Vector3(_redlightning_sound_source.position)
	var offset: Vector3 = listener.global_position - point
	_pan_source = point
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_redlightning_sound_source.far) - distance) /
		(float(_redlightning_sound_source.far) - float(_redlightning_sound_source.near)), 0.0, 1.0)

## Each edition supplies its own 40 active keys, first local z=1.2657244,
## near1/far2 and XML Sound scale10.
func _tree_snake_summon_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _greensummon_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("GreenSummon.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("greensummon", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_greensummon_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _greensummon_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("greensummon", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", target, "", null)
	var point: Vector3 = where * Vector3(_greensummon_sound_source.position)
	var offset: Vector3 = listener.global_position - point
	_pan_source = point
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_greensummon_sound_source.far) - distance) /
		(float(_greensummon_sound_source.far) - float(_greensummon_sound_source.near)), 0.0, 1.0)

## Original EL1 turn-entry Stasis launches BlueStasis at the acting hero.
## The source FX has no named point: its first active SOUN is local origin,
## near1/far2; original Effects.xml scales these to 10/20. Match the existing
## original-effect placement, with the combat camera XZ as approximate listener.
func _turn_stasis_gain(hero: Node3D) -> float:
	if edition != "el1" or not is_instance_valid(listener) or not is_instance_valid(hero):
		return 1.0
	if _stasis_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("BlueStasis.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("bluestasis", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_stasis_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _stasis_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("bluestasis", {})
	if entry.is_empty(): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", hero, "", null)
	var source: Vector3 = where * Vector3(_stasis_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_stasis_sound_source.far) - distance) /
		(float(_stasis_sound_source.far) - float(_stasis_sound_source.near)), 0.0, 1.0)

## Original hero-healing effect callbacks place Target/GainLife at the
## caster: EL1 GreaterHealing@ and Symbiosis@,
## EL2 Healing@ and
## EL2 GreaterHealing@. Each
## edition's own GainLife.fx first enabled SOUN is at z2.1532, near1/far6,
## with its own Effects.xml scale10 -> world near10/far60. Use the existing
## FX Target placement and approximate combat-camera XZ listener for only
## EL1 GRHE/SYMB, EL2 HEAL and EL2 GRHE. Other GainLife sites keep prior gain.
func _healing_gain(hero: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(hero):
		return 1.0
	if _healing_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("GainLife.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("gainlife", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_healing_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _healing_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("gainlife", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", hero, "", null)
	var source: Vector3 = where * Vector3(_healing_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_healing_sound_source.far) - distance) /
		(float(_healing_sound_source.far) - float(_healing_sound_source.near)), 0.0, 1.0)

## Original EL1 Channel@ and EL2 Channel@ each separately bind Target/LoseLife
## to the casting hero (not the opponent receiving GainLife). Use this Target
## and approximate combat-camera XZ listener only for a bound Channel caster;
## unrelated/unbound LoseLife cues stay unchanged.
func _channel_loselife_gain(hero: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(hero):
		return 1.0
	if _channel_loselife_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("LoseLife.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("loselife", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_channel_loselife_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _channel_loselife_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("loselife", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", hero, "", null)
	var source: Vector3 = where * Vector3(_channel_loselife_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_channel_loselife_source.far) - distance) /
		(float(_channel_loselife_source.far) - float(_channel_loselife_source.near)), 0.0, 1.0)

## Original EL1 Hunger@ and EL2 Hunger@ register
## Target/Hunger on the victim. Each edition's original Hunger.fx has
## 90 enabled SOUN keys, first local z0.52358, near1/far2, and its own
## Effects.xml scale10 -> ground-plane near10/far20.
## The existing FX transform and camera XZ listener remain approximations.
## Both editions' CRHG/RVHG independently register the same victim
## Target/Hunger. Only explicit victim-bound effect calls use this source;
## unbound effect requests retain their original level.
func _normal_hunger_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _hunger_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("Hunger.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("hunger", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_hunger_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _hunger_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("hunger", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", target, "", null)
	var source: Vector3 = where * Vector3(_hunger_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_hunger_sound_source.far) - distance) /
		(float(_hunger_sound_source.far) - float(_hunger_sound_source.near)), 0.0, 1.0)

## EL1 Geyser@, ManaDrop@, Volcano@,
## ManaTap@, Balance@, StoneRing@ (second Target, after
## GreenStoneRing), Channel@ (caster only), and
## ManaVortexEnchantment@,
## EL2 Geyser@, Volcano@, ManaTap@,
## Justice@, Balance@, ManaDrop@ and
## Channel@ (separately from LoseLife and opposing GainLife)
## register Target/GainMana at the caster. Both editions'
## 60 enabled SOUN keys first start at local z2.1532, near1/far2, with
## Effects.xml scale100 -> near100/far200. Read this edition's own sources;
## the existing FX Target and camera-XZ listener are approximations.
## Only EL1 GEYS/MNDP/VOLC/MNTP/BLNC/SNRG/SNCR/SNHG/MNDW/MNVR/CHNL
## and EL2 GEYS/VOLC/MNTP/JUST/BLNC/MNDP/MNDW/CHNL
## use this gain. Other GainMana paths retain their prior audio level.
func _gainmana_gain(hero: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(hero):
		return 1.0
	if _gainmana_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("GainMana.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("gainmana", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_gainmana_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _gainmana_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("gainmana", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", hero, "", null)
	var source: Vector3 = where * Vector3(_gainmana_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_gainmana_sound_source.far) - distance) /
		(float(_gainmana_sound_source.far) - float(_gainmana_sound_source.near)), 0.0, 1.0)

func _el2_losemana_gain(hero: Node3D) -> float:
	if edition != "el2" or not is_instance_valid(listener) or not is_instance_valid(hero):
		return 1.0
	if _el2_losemana_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("LoseMana.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("losemana", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_el2_losemana_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _el2_losemana_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("losemana", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", hero, "", null) * Vector3(
		_el2_losemana_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_el2_losemana_sound_source.far) - distance) /
		(float(_el2_losemana_sound_source.far) - float(_el2_losemana_sound_source.near)), 0.0, 1.0)

## EL1 Recall@, LostParchment@, Repair@, EL2 Recall@, LostParchment@ and Repair@
## each register Target/Draw at the caster. Repair's third cue is separate from
## the opponent's BlackDamage; each original Draw.fx has 40 enabled SOUN frames
## starting at local origin, near1/far2; Effects.xml scales Magic/draw.wav by 10
## -> ground-plane near10/far20. Apply only to bound normal RECL/LSPC/REPR in
## either edition.
func _draw_gain(hero: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(hero):
		return 1.0
	if _draw_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("Draw.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("draw", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_draw_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _draw_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("draw", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", hero, "", null)
	var source: Vector3 = where * Vector3(_draw_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_draw_sound_source.far) - distance) /
		(float(_draw_sound_source.far) - float(_draw_sound_source.near)), 0.0, 1.0)

## Both original Amnesias register Target/Discard once per hero (EL1 EL2). Only
## EL2 adds caster Target/Draw. Both mounted Discard.fx sources have 40 active
## SOUN keys at origin, raw near1/far2, and original Effects.xml scale5 (world
## near5/far10).
func _amnesia_discard_gain(hero: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(hero):
		return 1.0
	if _amnesia_discard_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("Discard.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("discard", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_amnesia_discard_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _amnesia_discard_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("discard", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", hero, "", null)
	var source: Vector3 = where * Vector3(_amnesia_discard_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_amnesia_discard_sound_source.far) - distance) /
		(float(_amnesia_discard_sound_source.far) - float(_amnesia_discard_sound_source.near)), 0.0, 1.0)

## Read each mounted edition's own sound source.
func _mind_blast_gain(hero: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(hero):
		return 1.0
	if _mind_blast_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("BlueMindBlast.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("bluemindblast", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_mind_blast_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _mind_blast_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("bluemindblast", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", hero, "", null)
	var source: Vector3 = where * Vector3(_mind_blast_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_mind_blast_sound_source.far) - distance) /
		(float(_mind_blast_sound_source.far) - float(_mind_blast_sound_source.near)), 0.0, 1.0)

## Original EL1 Desintegrate@ and EL2@ register
## Start/Finish/RedFireStream. Both independently mounted original editions
## contain 15 active SOUN keys first at local z2.0432, raw near1/far6;
## their own Effects.xml scales the FireBeam WAV by 10 -> near10/far60.
## Sound uses the existing Start->Finish FX placement and camera-XZ listener
## approximation, not an inferred target-ground or EL2-wide adjustment.
func _disintegrate_gain(caster: Node3D, target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster) or not is_instance_valid(target):
		return 1.0
	if _disintegrate_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("RedFireStream.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("redfirestream", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_disintegrate_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _disintegrate_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("redfirestream", {})
	if entry.is_empty() or not entry.points.has("Start") or not entry.points.has("Finish"):
		return 1.0
	var where := ELCombatEffects.placement(entry, "Start", caster, "Finish", target)
	var source: Vector3 = where * Vector3(_disintegrate_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_disintegrate_sound_source.far) - distance) /
		(float(_disintegrate_sound_source.far) - float(_disintegrate_sound_source.near)), 0.0, 1.0)

## Both original Powertap callbacks (EL1@, EL2@) bind DrainMana Start to the
## opposing donor and Finish to the caster.
func _powertap_drain_gain(caster: Node3D, donor: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster) or not is_instance_valid(donor):
		return 1.0
	if _powertap_drain_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("DrainMana.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("drainmana", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_powertap_drain_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _powertap_drain_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("drainmana", {})
	if entry.is_empty() or not entry.points.has("Start") or not entry.points.has("Finish"):
		return 1.0
	var where := ELCombatEffects.placement(entry, "Start", donor, "Finish", caster)
	var source: Vector3 = where * Vector3(_powertap_drain_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_powertap_drain_sound_source.far) - distance) /
		(float(_powertap_drain_sound_source.far) - float(_powertap_drain_sound_source.near)), 0.0, 1.0)

## EL1 TapLife@ and EL2@ start DrainLife at the damaged opposing hero and finish
## at the caster. Use only successfully hit, hero-bound TPLF in each edition.
func _tap_life_gain(caster: Node3D, donor: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster) or not is_instance_valid(donor):
		return 1.0
	if _tap_life_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("DrainLife.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("drainlife", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_tap_life_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _tap_life_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("drainlife", {})
	if entry.is_empty() or not entry.get("points", {}).has("Start") or not entry.get("points", {}).has("Finish"):
		return 1.0
	var where := ELCombatEffects.placement(entry, "Start", donor, "Finish", caster)
	var source: Vector3 = where * Vector3(_tap_life_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_tap_life_sound_source.far) - distance) /
		(float(_tap_life_sound_source.far) - float(_tap_life_sound_source.near)), 0.0, 1.0)

## Original EL1 CrackingIvies@ and EL2 CrackingIvies@ attach GreenDamage to the
## affected Wall's untagged Target point. Both owned-original FX tracks have 40
## enabled SOUN frames, first local z1.1157922, raw near1/far2, Effects.xml
## scale100 -> near100/far200. Read each edition's source independently.
func _cracking_ivies_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _cracking_ivies_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("GreenDamage.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("greendamage", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_cracking_ivies_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _cracking_ivies_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("greendamage", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", target, "", null)
	var source: Vector3 = where * Vector3(_cracking_ivies_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_cracking_ivies_sound_source.far) - distance) /
		(float(_cracking_ivies_sound_source.far) - float(_cracking_ivies_sound_source.near)), 0.0, 1.0)

## Original EL1 Twister@ places GreenHurricane at the target. Its 60 active SOUN
## keys begin at local z3.196906, raw near1/far2, scaled by the EL1 Effects.xml
## Magic/GreenHurricane.wav scale10. Only the normal EL1 TWST cast uses this XZ
## source gain.
func _twister_gain(target: Node3D) -> float:
	if edition != "el1" or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _twister_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("GreenHurricane.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("greenhurricane", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_twister_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _twister_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("greenhurricane", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", target, "", null)
	var source: Vector3 = where * Vector3(_twister_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_twister_sound_source.far) - distance) /
		(float(_twister_sound_source.far) - float(_twister_sound_source.near)), 0.0, 1.0)

## EL1 Firestorm@ and EL2@ start their RedFireWave the caster when X>0; each
## registers RedDamage per enemy, and EL2 adds LoseMana on the caster. Normal
## FRST and fixed FRWA in both editions supply their original caster Start
## figure here. Truly unbound effect requests retain full gain.
func _firestorm_wave_gain(caster: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster):
		return 1.0
	if _firestorm_wave_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("RedFireWave.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("redfirewave", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_firestorm_wave_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _firestorm_wave_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("redfirewave", {})
	if entry.is_empty() or not entry.points.has("Start"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Start", caster, "", null) * Vector3(
		_firestorm_wave_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_firestorm_wave_sound_source.far) - distance) /
		(float(_firestorm_wave_sound_source.far) - float(_firestorm_wave_sound_source.near)), 0.0, 1.0)

## EL1 FireWave@ and EL2@ independently queue a separate Target/RedDamage for
## each opposing creature. Both original editions have 28 active RedDamage.fx
## SOUN keys, first local z2.297935, raw near1/far6; each original Effects.xml
## scales its own WAV by 10 => near10/far60. Both normal FRWA paths and
## separately proven EL1/EL2 FRST victim sites supply the original Target
## source. Unrelated/unbound calls stay full gain.
func _frwa_red_damage_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _frwa_red_damage_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("RedDamage.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("reddamage", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_frwa_red_damage_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _frwa_red_damage_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("reddamage", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var point: Vector3 = ELCombatEffects.placement(entry, "Target", target, "", null) * Vector3(
		_frwa_red_damage_sound_source.position)
	var offset: Vector3 = listener.global_position - point
	_pan_source = point
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_frwa_red_damage_sound_source.far) - distance) /
		(float(_frwa_red_damage_sound_source.far) - float(_frwa_red_damage_sound_source.near)), 0.0, 1.0)

## EL2 normal Comet/FireBall@ registers Target/RedComet at the affected figure.
## The player's original RedComet.fx has 70 enabled SOUN keys, first local
## z1.502384 with radii 1/2; EL2 Effects.xml scales the WAV to world
## near10/far20. Other RedComet registrations, EL1 and unbound sound remain
## unchanged.
func _comet_gain(target: Node3D) -> float:
	if edition != "el2" or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _comet_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("RedComet.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var size := bytes.decode_u32(at + 4)
		var label_len := bytes.decode_u16(at + 8)
		var key: int = at + 10 + label_len
		var last: int = mini(at + 8 + size, bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("redcomet", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_comet_sound_source = {"position": ELFigure.vector(Vector3(
						bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _comet_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("redcomet", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var where := ELCombatEffects.placement(entry, "Target", target, "", null)
	var source: Vector3 = where * Vector3(_comet_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_comet_sound_source.far) - distance) /
		(float(_comet_sound_source.far) - float(_comet_sound_source.near)), 0.0, 1.0)

## EL1 SpiritOfBasiliskEnchantment@ and independently indexed EL2 @ bind
## GreenBasilisk and PosRune to the enchanted creature Target.
func _basilisk_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _basilisk_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("GreenBasilisk.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("greenbasilisk", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_basilisk_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _basilisk_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("greenbasilisk", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", target, "", null) * Vector3(
		_basilisk_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_basilisk_sound_source.far) - distance) /
		(float(_basilisk_sound_source.far) - float(_basilisk_sound_source.near)), 0.0, 1.0)

## EL1 Annihilation@ and EL2@ each queue Target RedAnihilation per non-plane
## creature and again at the opposite hero when that side's total creature power
## is positive. Both originals have 61/61 enabled SOUN keys (first at local
## origin, radii 1/2); Effects.xml scales Magic/RedAnnihilation.wav by 10: source
## near10/far20 in world units. Only explicitly bound ANHL cast sites supply a
## model for this fade.
func _annihilation_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _annihilation_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("RedAnihilation.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("redanihilation", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_annihilation_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _annihilation_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("redanihilation", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", target, "", null) * Vector3(
		_annihilation_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_annihilation_sound_source.far) - distance) /
		(float(_annihilation_sound_source.far) - float(_annihilation_sound_source.near)), 0.0, 1.0)

## EL1 WindsOfFlame@ and EL2@ independently create a FireballExpl Finish FX for
## each flying victim.
func _wnfl_explosion_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _wnfl_explosion_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("FireballExpl.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("fireballexpl", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_wnfl_explosion_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _wnfl_explosion_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("fireballexpl", {})
	if entry.is_empty() or not entry.points.has("Finish"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Finish", target, "", null) * Vector3(
		_wnfl_explosion_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_wnfl_explosion_sound_source.far) - distance) /
		(float(_wnfl_explosion_sound_source.far) - float(_wnfl_explosion_sound_source.near)), 0.0, 1.0)

## Original EL1 DepressGasEnchantment@ and EL2@ each register caster
## Target/BlackDepressGas separately from the creature NegAttack/NegRune
## callbacks. Do not affect other gas or unbound effect requests.
func _depress_gas_gain(caster: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster):
		return 1.0
	if _depress_gas_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("BlackDepressGas.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("blackdepressgas", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_depress_gas_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _depress_gas_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("blackdepressgas", {})
	if entry.is_empty(): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", caster, "", null) * Vector3(
		_depress_gas_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_depress_gas_sound_source.far) - distance) /
		(float(_depress_gas_sound_source.far) - float(_depress_gas_sound_source.near)), 0.0, 1.0)

## EL1 DrowsyGasEnchantment@ and EL2@ register caster BlackDrowsyGas separately
## from creature NegAttack/NegRune callbacks @ and @. Both owners'
## BlackDrowsyGas.fx have 90/90 active SOUN frames, first at local origin
## near1/far2; each Effects.xml scales BlackAllGases.wav by 3 (world
## near3/far6). Unbound requests stay flat.
func _drowsy_gas_gain(caster: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster):
		return 1.0
	if _drowsy_gas_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("BlackDrowsyGas.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("blackdrowsygas", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_drowsy_gas_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _drowsy_gas_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("blackdrowsygas", {})
	if entry.is_empty(): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", caster, "", null) * Vector3(
		_drowsy_gas_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_drowsy_gas_sound_source.far) - distance) /
		(float(_drowsy_gas_sound_source.far) - float(_drowsy_gas_sound_source.near)), 0.0, 1.0)

## EL1 original FrenzyGasEnchantment@ and EL2@ queue caster
## Target/BlackFrenzyGas/NegRune, distinct from creature callbacks
## NegDefence/NegRune@ and @. Effects.xml scales its BlackAllGases.wav by 3 =>
## approximate world near3/far6.
func _frenzy_gas_gain(caster: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster):
		return 1.0
	if _frenzy_gas_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("BlackFrenzyGas.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("blackfrenzygas", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_frenzy_gas_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _frenzy_gas_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("blackfrenzygas", {})
	if entry.is_empty(): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", caster, "", null) * Vector3(
		_frenzy_gas_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_frenzy_gas_sound_source.far) - distance) /
		(float(_frenzy_gas_sound_source.far) - float(_frenzy_gas_sound_source.near)), 0.0, 1.0)

## Original EL1 SuffocationGasEnchantment@ and EL2@ register initial
## BlackSuffocationGas and NegRune at the casting hero, separately from
## owner-end-turn BlackDamage callbacks@ and @. Both owners'
## BlackSuffocationGas.fx have 90 active SOUN keys, first at local origin
## near1/far2; Effects.xml scales the original BlackAllGases.wav by 3 in each
## edition.
func _suffocation_gas_gain(caster: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster):
		return 1.0
	if _suffocation_gas_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("BlackSuffocationGas.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("blacksuffocationgas", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_suffocation_gas_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _suffocation_gas_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("blacksuffocationgas", {})
	if entry.is_empty(): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", caster, "", null) * Vector3(
		_suffocation_gas_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_suffocation_gas_sound_source.far) - distance) /
		(float(_suffocation_gas_sound_source.far) - float(_suffocation_gas_sound_source.near)), 0.0, 1.0)

## Original EL1 SelfRepairEnchantment@ and EL2@ attach Target/Regeneration and
## PosRune to the enchanted creature. Effects.xml scales Magic/Regeneration.wav
## by 10, giving an approximate world near10/far20. Only real EL1/EL2 SLRP
## creature-bound casts use this gain; other Regeneration cues stay untouched.
func _self_repair_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _self_repair_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("Regeneration.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("regeneration", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_self_repair_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _self_repair_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("regeneration", {})
	if entry.is_empty() or not entry.get("points", {}).has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", target, "", null) * Vector3(
		_self_repair_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_self_repair_sound_source.far) - distance) /
		(float(_self_repair_sound_source.far) - float(_self_repair_sound_source.near)), 0.0, 1.0)

## Original EL1 StoneRing@, StoneCircle@, StoneHenge@ and EL2 StoneRing@,
## StoneCircle@, StoneHenge@ put Target/GreenStoneRing at the caster, separately
## from Target/GainMana. Each site is independently indexed in its edition and
## verified against the respective owner's assets. Independently mounted
## originals have 60 active SOUN keys, first local origin near1/far2 and
## Effects.xml scale10 (world near10/far20). Unbound requests stay unchanged.
func _stone_circle_gain(caster: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster):
		return 1.0
	if _stone_circle_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("GreenStoneRing.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("greenstonering", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_stone_circle_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _stone_circle_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("greenstonering", {})
	if entry.is_empty() or not entry.get("points", {}).has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", caster, "", null) * Vector3(
		_stone_circle_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_stone_circle_sound_source.far) - distance) /
		(float(_stone_circle_sound_source.far) - float(_stone_circle_sound_source.near)), 0.0, 1.0)

## Original EL1 FuryOfNature@ and EL2@ both queue unconditional
## Target/GreenForceNature at the caster. Their separate conditional sites are
## EL1 attacker GreenDamage and EL2 opponent Draw. Only real caster-bound casts
## use this gain, not unbound requests. First-key placement and combat-camera XZ
## listener approximate live audio.
func _fury_nature_gain(caster: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster):
		return 1.0
	if _fury_nature_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("GreenForceNature.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("greenforcenature", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_fury_nature_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _fury_nature_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("greenforcenature", {})
	if entry.is_empty() or not entry.get("points", {}).has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", caster, "", null) * Vector3(
		_fury_nature_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_fury_nature_sound_source.far) - distance) /
		(float(_fury_nature_sound_source.far) - float(_fury_nature_sound_source.near)), 0.0, 1.0)

## EL1 Fog@ and EL2 Fog@ independently register CantAttack
## at each current creature's Target, separately from one unpositioned BlueFog.
## Each edition's own CantAttack.fx has 60 active SOUN keys, first local
## z2.153224 with raw near1/far10; each original Effects.xml scales the
## decoded CannotAttack WAV by 5 (world near5/far50). Use the actual Target
## and approximate camera XZ listener. Unbound sounds remain unchanged.
func _fog_cantattack_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _fog_cantattack_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("CantAttack.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("cantattack", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_fog_cantattack_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _fog_cantattack_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("cantattack", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", target, "", null) * Vector3(
		_fog_cantattack_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_fog_cantattack_sound_source.far) - distance) /
		(float(_fog_cantattack_sound_source.far) - float(_fog_cantattack_sound_source.near)), 0.0, 1.0)

## EL1 BrokenReality@ and EL2@ register chosen-hero Target/BlackDamage after
## positive ether. EL1 SuffocationGasEnchantment @ separately registers
## Target/BlackDamage at each end-turn victim. Each edition's original
## BlackDamage.fx has 16 active first-SOUN keys, z2.0432 near1/far6 and original
## Effects.xml scale10. Only proven, explicitly bound callers use this source;
## unrelated/unbound sounds stay flat.
func _target_blackdamage_gain(target: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(target):
		return 1.0
	if _blackdamage_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("BlackDamage.fx"))
		var at := _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("blackdamage", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_blackdamage_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _blackdamage_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("blackdamage", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", target, "", null) * Vector3(
		_blackdamage_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_blackdamage_sound_source.far) - distance) /
		(float(_blackdamage_sound_source.far) - float(_blackdamage_sound_source.near)), 0.0, 1.0)

## EL1 Repair@, EL2 Repair@ and Juryrig@ register caster Target/PosSorcery
## separately from opposing-hero BlackDamage. Each player's PosSorcery.fx has 61
## active first-SOUN keys (z1.5, near1/far6) and its original Effects.xml scale10.
## Only these proven bound callers use the caster source; unbound and other
## PosSorcery sounds retain prior gain.
func _target_possorcery_gain(caster: Node3D) -> float:
	if edition not in ["el1", "el2"] or not is_instance_valid(listener) or not is_instance_valid(caster):
		return 1.0
	if _target_possorcery_sound_source.is_empty():
		var bytes: PackedByteArray = profile.read("fx", ELArchive.key("PosSorcery.fx"))
		var at: int = _find(bytes, "SOUN".to_ascii_buffer())
		if at < 0 or at + 10 > bytes.size(): return 1.0
		var key: int = at + 10 + bytes.decode_u16(at + 8)
		var last: int = mini(at + 8 + bytes.decode_u32(at + 4), bytes.size())
		while key + 21 <= last:
			if bytes[key + 20] != 0:
				var scale := float(_effect_scales.get("possorcery", 0.0))
				var near := bytes.decode_float(key + 12) * scale
				var far := bytes.decode_float(key + 16) * scale
				if near >= 0.0 and far > near:
					_target_possorcery_sound_source = {
						"position": ELFigure.vector(Vector3(
							bytes.decode_float(key), bytes.decode_float(key + 4), bytes.decode_float(key + 8))),
						"near": near, "far": far}
				break
			key += 21
	if _target_possorcery_sound_source.is_empty(): return 1.0
	var entry: Dictionary = ELCombatEffects.load_catalogue(profile).get("possorcery", {})
	if entry.is_empty() or not entry.points.has("Target"): return 1.0
	var source: Vector3 = ELCombatEffects.placement(entry, "Target", caster, "", null) * Vector3(
		_target_possorcery_sound_source.position)
	var offset: Vector3 = listener.global_position - source
	_pan_source = source
	var distance := Vector2(offset.x, offset.z).length()
	return clampf((float(_target_possorcery_sound_source.far) - distance) /
		(float(_target_possorcery_sound_source.far) - float(_target_possorcery_sound_source.near)), 0.0, 1.0)

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
	for voice in voices:
		var level := float(settings.effects) * float(voice.get_meta("spatial_gain", 1.0))
		voice.volume_db = linear_to_db(maxf(0.0001, level)) - 3.0
	for loop in loops: loop.volume_db = ambience_db()
	# Arena loops and the panned effect voices both go through the positional bus.
	ELAudio.positional_bus(bool(settings.get("audio_reverse", false)))

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
func play(path: String, spatial_gain := 1.0) -> bool:
	var source: Variant = _pan_source
	_pan_source = null
	requested.append(path)
	if requested.size() > 80: requested.pop_front()
	var stream := ELAudio.sound(profile, path)
	if stream == null: return false
	for voice in voices:
		if not voice.playing:
			voice.stream = stream
			voice.set_meta("spatial_gain", spatial_gain)
			voice.volume_db = linear_to_db(maxf(0.0001, float(settings.effects) * spatial_gain)) - 3.0
			var pan := stereo_pan(source) if source is Vector3 else 0.0
			voice.set_meta("pan", pan)
			ELAudio.set_pan(voice.bus, pan)
			voice.play()
			played.append(path)
			if played.size() > 40: played.pop_front()
			return true
	return false

## The original's stereo placement (ELAudio.stereo_pan) heard from where the
## camera's view meets the ground, facing the camera's level direction.
func stereo_pan(source: Vector3) -> float:
	if not is_instance_valid(listener): return 0.0
	var forward := -listener.global_basis.z
	var focus := listener.global_position
	if forward.y < -0.01: focus += forward * (-focus.y / forward.y)
	return ELAudio.stereo_pan(focus, forward, source)

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

func spell(card: String, caster: Node3D = null, target: Node3D = null) -> void:
	for path in spell_paths(card):
		if edition in ["el1", "el2"] and card == "ZAPP" and path == effect_sound("RedZap"):
			play(path, _redzap_gain(caster, target))
		elif edition in ["el1", "el2"] and card == "BLSS" and path == effect_sound("PosAttack"):
			play(path, _bless_stat_gain("PosAttack", target))
		elif edition in ["el1", "el2"] and card == "BLSS" and path == effect_sound("PosDefence"):
			play(path, _bless_stat_gain("PosDefence", target))
		elif edition in ["el1", "el2"] and card == "BLSS" and path == effect_sound("PosRune"):
			play(path, _bless_posrune_gain(target))
		elif edition in ["el1", "el2"] and card == "CLIG" and path == effect_sound("RedLightning"):
			play(path, _call_lightning_gain(target))
		# Both original BodyExchange spells (EL1, EL2)
		# place BlackDamage at the sacrificed living creature, separately
		# from caster PosSorcery. Each edition reads its own FX first-SOUN
		# Target source; unbound/other effects keep their existing levels.
		elif edition in ["el1", "el2"] and card == "BDEX" and path == effect_sound("BlackDamage"):
			play(path, _target_blackdamage_gain(target))
		# Both original BodyExchange owners (EL1, EL2)
		# start caster Target/PosSorcery separately from sacrifice BlackDamage.
		# Use each edition's first active SOUN source for bound BDEX only;
		# other and unbound PosSorcery requests retain their previous levels.
		elif edition in ["el1", "el2"] and card == "BDEX" and path == effect_sound("PosSorcery"):
			play(path, _target_possorcery_gain(caster))
		elif edition in ["el1", "el2"] and card == "BRRL" and path == effect_sound("BlackDamage"):
			play(path, _target_blackdamage_gain(target))
		elif edition == "el2" and card == "INCR" and path == effect_sound("LoseMana"):
			play(path, _el2_losemana_gain(target))
		# Both Repairs bind BlackDamage to the opposing hero (EL1,
		# EL2), separate from caster PosSorcery/Draw. Read the
		# owner's first-SOUN source only for the genuinely bound hero.
		elif edition in ["el1", "el2"] and card == "REPR" and path == effect_sound("BlackDamage"):
			play(path, _target_blackdamage_gain(target))
		# Both original Repairs bind PosSorcery to the casting hero, independent
		# of the opposing-hero BlackDamage cue already handled above.
		elif edition in ["el1", "el2"] and card == "REPR" and path == effect_sound("PosSorcery"):
			play(path, _target_possorcery_gain(caster))
		# Both original Repairs (EL1, EL2) queue the
		# third Target/Draw at the caster. BlackDamage stays on the enemy.
		# Unbound and unrelated Draw requests keep their prior levels.
		elif edition in ["el1", "el2"] and card == "REPR" and path == effect_sound("Draw"):
			play(path, _draw_gain(caster))
		# Original EL2 Juryrig@ places BlackDamage on the opposing
		# hero, distinct from caster PosSorcery. Use its own original .fx
		# first-SOUN source only for this bound JRRG cast.
		elif edition == "el2" and card == "JRRG" and path == effect_sound("BlackDamage"):
			play(path, _target_blackdamage_gain(target))
		elif edition == "el2" and card == "JRRG" and path == effect_sound("PosSorcery"):
			play(path, _target_possorcery_gain(caster))
		elif edition in ["el1", "el2"] and card == "TRSN" and path == effect_sound("GreenSummon"):
			play(path, _tree_snake_summon_gain(target))
		elif ((edition == "el1" and card in ["GRHE", "SYMB"]) or (edition == "el2" and card in ["HEAL", "GRHE"])) and path == effect_sound("GainLife"):
			play(path, _healing_gain(caster))
		elif edition in ["el1", "el2"] and card == "HUNG" and path == effect_sound("Hunger"):
			play(path, _normal_hunger_gain(target))
		elif ((edition == "el1" and card in ["GEYS", "MNDP", "VOLC", "MNTP", "BLNC", "SNRG", "SNCR", "SNHG", "MNDW", "MNVR", "CHNL"]) or (edition == "el2" and card in ["GEYS", "VOLC", "MNTP", "JUST", "BLNC", "MNDP", "MNDW", "CHNL"])) and path == effect_sound("GainMana"):
			play(path, _gainmana_gain(caster))
		elif edition in ["el1", "el2"] and card in ["RECL", "LSPC"] and path == effect_sound("Draw"):
			play(path, _draw_gain(caster))
		# Original EL1 Curse@ binds one Discard Target at the
		# selected hero, unlike unbound/generic Discard. Reuse the owner's
		# first-enabled SOUN source without changing EL2 or Amnesia.
		elif edition == "el1" and card == "CURS" and path == effect_sound("Discard"):
			play(path, _amnesia_discard_gain(target))
		elif edition in ["el1", "el2"] and card == "DSIG" and path == effect_sound("RedFireStream"):
			play(path, _disintegrate_gain(caster, target))
		elif edition in ["el1", "el2"] and card == "PWTP" and path == effect_sound("DrainMana"):
			play(path, _powertap_drain_gain(caster, target))
		# Both originals' Channel heal the opposing hero, not the life-paying
		# caster (EL1, EL2). Use each edition's first
		# owner-SOUN key only when that recipient is actually bound.
		elif edition in ["el1", "el2"] and card == "CHNL" and path == effect_sound("GainLife"):
			play(path, _healing_gain(target))
		elif edition in ["el1", "el2"] and card == "CHNL" and path == effect_sound("LoseLife"):
			play(path, _channel_loselife_gain(caster))
		elif edition in ["el1", "el2"] and card == "TPLF" and path == effect_sound("DrainLife"):
			play(path, _tap_life_gain(caster, target))
		elif edition in ["el1", "el2"] and card == "CRIV" and path == effect_sound("GreenDamage"):
			play(path, _cracking_ivies_gain(target))
		elif edition == "el1" and card == "TWST" and path == effect_sound("GreenHurricane"):
			play(path, _twister_gain(target))
		elif edition == "el2" and card == "COMT" and path == effect_sound("RedComet"):
			play(path, _comet_gain(target))
		elif edition in ["el1", "el2"] and card == "SPBA" and path == effect_sound("GreenBasilisk"):
			play(path, _basilisk_gain(target))
		elif edition in ["el1", "el2"] and card == "SNRG" and path == effect_sound("GreenStoneRing"):
			play(path, _stone_circle_gain(caster))
		elif edition in ["el1", "el2"] and card == "SNCR" and path == effect_sound("GreenStoneRing"):
			play(path, _stone_circle_gain(caster))
		elif edition in ["el1", "el2"] and card == "SNHG" and path == effect_sound("GreenStoneRing"):
			play(path, _stone_circle_gain(caster))
		elif edition in ["el1", "el2"] and card == "SLRP" and path == effect_sound("Regeneration"):
			play(path, _self_repair_gain(target))
		elif edition in ["el1", "el2"] and card == "SFGS" and path == effect_sound("BlackSuffocationGas"):
			play(path, _suffocation_gas_gain(caster))
		else:
			play(path)

## Original EL2 ManaBreeze@ and @ registers a distinct
## Target/GainMana on each hero. Play both original first-SOUN instances from
## their own targets, not one generic caster or shared-center cue. Preserve
## the ordinary, unbound spell() API and EL1's separate behavior.
func mana_breeze(caster: Node3D, opponent: Node3D) -> void:
	if edition != "el2": return
	var path := effect_sound("GainMana")
	if path.is_empty(): return
	for hero: Node3D in [caster, opponent]:
		if is_instance_valid(hero):
			play(path, _gainmana_gain(hero))

## Normal EL1/EL2 Amnesia each starts two hero Discard sound instances,
## and only EL2 adds one caster Draw. Keep unrelated Discard/Draw sites
## and the generic unbound spell/effect APIs unchanged.
func amnesia(hero0: Node3D, hero1: Node3D, caster: Node3D) -> void:
	if edition not in ["el1", "el2"]: return
	var discard := effect_sound("Discard")
	if not discard.is_empty():
		for hero: Node3D in [hero0, hero1]:
			if is_instance_valid(hero): play(discard, _amnesia_discard_gain(hero))
	var draw := effect_sound("Draw")
	if edition == "el2" and not draw.is_empty() and is_instance_valid(caster):
		play(draw, _draw_gain(caster))

func trigger(card: String, target: Node3D = null) -> void:
	for path in effect_paths(SoundTable.trigger_effects(edition, card)):
		if edition in ["el1", "el2"] and card == "SFGS" and path == effect_sound("BlackDamage") and is_instance_valid(target):
			play(path, _target_blackdamage_gain(target))
		else:
			play(path)

func effect(name: String, target: Node3D = null) -> void:
	var path := effect_sound(name)
	if not path.is_empty():
		if edition in ["el1", "el2"] and name == "GreenForceNature" and is_instance_valid(target):
			play(path, _fury_nature_gain(target))
		elif edition in ["el1", "el2"] and name == "BlackDepressGas" and is_instance_valid(target):
			play(path, _depress_gas_gain(target))
		elif edition in ["el1", "el2"] and name == "BlackDrowsyGas" and is_instance_valid(target):
			play(path, _drowsy_gas_gain(target))
		elif edition in ["el1", "el2"] and name == "BlackFrenzyGas" and is_instance_valid(target):
			play(path, _frenzy_gas_gain(target))
		elif edition in ["el1", "el2"] and name == "BlueMindBlast":
			play(path, _mind_blast_gain(target))
		# Both original Lightning Storms register RedLightning at each creature
		# Target, using their edition-local normal Call Lightning first-SOUN source.
		# Unbound RedLightning stays at its prior full gain.
		elif edition in ["el1", "el2"] and name == "RedLightning" and is_instance_valid(target):
			play(path, _call_lightning_gain(target))
		elif edition in ["el1", "el2"] and name == "CantAttack" and is_instance_valid(target):
			play(path, _fog_cantattack_gain(target))
		elif edition in ["el1", "el2"] and name == "Hunger" and is_instance_valid(target):
			play(path, _normal_hunger_gain(target))
		elif edition in ["el1", "el2"] and name == "FireballExpl" and is_instance_valid(target):
			play(path, _wnfl_explosion_gain(target))
		elif edition in ["el1", "el2"] and name == "RedFireWave" and is_instance_valid(target):
			play(path, _firestorm_wave_gain(target))
		elif edition in ["el1", "el2"] and name == "RedDamage" and is_instance_valid(target):
			play(path, _frwa_red_damage_gain(target))
		elif edition in ["el1", "el2"] and name == "RedAnihilation" and is_instance_valid(target):
			play(path, _annihilation_gain(target))
		elif edition == "el2" and name == "LoseMana" and is_instance_valid(target):
			play(path, _el2_losemana_gain(target))
		# EL2 Orc Shaman's activated ether logs a separate Target/GainMana
		# at its receiving hero. Only that explicitly
		# bound ability caller supplies a GainMana target. Its own creature
		# instant.wav and unbound/EL1 GainMana retain their existing levels.
		elif edition == "el2" and name == "GainMana" and is_instance_valid(target):
			play(path, _gainmana_gain(target))
		else:
			play(path, _turn_stasis_gain(target) if name == "BlueStasis" else 1.0)

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
	if path.is_empty(): return
	var gain := 1.0
	if edition in ["el1", "el2"] and is_instance_valid(listener) and target is Node3D:
		# Original EL1 and EL2: HitTable channel 4, near 20 / far 40,
		# linear attenuation in the ground plane. The original
		# camera listener's exact focus is unknown; use its world position.
		var offset: Vector3 = listener.global_position - target.global_position
		_pan_source = target.global_position
		var distance := Vector2(offset.x, offset.z).length()
		gain = clampf((40.0 - distance) / 20.0, 0.0, 1.0)
	play(path, gain)

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
