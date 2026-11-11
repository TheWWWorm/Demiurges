class_name ELAutochessBoardView
extends Node3D
## The watched home board: an original Etherlords II battlefield with the
## company's creatures. During preparation it shows the deployed army;
## during a fight it follows an ELAutochessBattle, playing each creature's
## own run, attack, ability, hit and death clips, sounds and effects.

signal unit_clicked(uid: int)

const EffectTable := preload("res://src/duel/combat_sound_table.gd")
const MOVE_RATE := 0.65
const NUMBER_SECONDS := 1.1
const ABILITY_EFFECTS := {
	"bolt": "RedZap", "nova": "RedFireWave", "execute": "BlackDamage", "stun": "CantUntap", "silence": "NegEnchantment",
	"rally": "PosSorcery", "drain": "DrainLife", "dispel": "NegEnchantment", "revive": "PosSorcery", "storm": "RedZap",
	"rod": "RedDamage", "death_aura": "BlackDamage", "ward": "PosSorcery", "dust": "CantUntap",
}

var profile: ELProfile
## Creatures (by uid) the screen is about to summon onto the board.
var arriving: Dictionary = {}
var arena: ELArena
var effects: ELCombatEffects
var audio: ELBattleAudio
var settings: Dictionary = {}
var arena_id := ""
var battle: ELAutochessBattle
var flip := false
## Fighter id (or "p<uid>" in preparation) -> ELModel.
var models: Dictionary = {}
var _codes: Dictionary = {}
var _event_index := 0
## Fighter id -> seconds left of its item-use flash.
var item_pops := {}
const ITEM_POP := 1.2
var _numbers: Array[Dictionary] = []
var _pending: Array = []
var _preparation: Array = []
var _shown_dead: Dictionary = {}
## The two watching heroes on the near sideline: side 0 by the watched
## hero's half, side 1 by the other half. {side: {"id", "model"}}.
var heroes: Dictionary = {}
var fire: Node3D
## Battlefields built so far, kept to switch back without rebuilding:
## scene id -> {"arena", "effects", "audio"}.
var _arenas: Dictionary = {}

func build(data: ELProfile, scene_id: String, values: Dictionary) -> bool:
	profile = data
	settings = values
	return _build_arena(scene_id)

func _build_arena(scene_id: String) -> bool:
	if scene_id == arena_id and is_instance_valid(arena): return true
	clear_units()
	# The current battlefield waits aside; its sounds stop for good (an
	# audio host leaving the tree releases its streams), so each showing
	# gets its own music, ambience and voices.
	for node: Node in [arena, effects]:
		if is_instance_valid(node) and node.get_parent() == self: remove_child(node)
	if is_instance_valid(audio):
		if audio.get_parent() == self: remove_child(audio)
		audio.queue_free()
	arena_id = scene_id
	if _arenas.has(scene_id):
		var kept: Dictionary = _arenas[scene_id]
		arena = kept.arena
		effects = kept.effects
		add_child(arena)
		add_child(effects)
	else:
		arena = ELArena.new()
		add_child(arena)
		if not arena.build(profile, scene_id):
			push_warning("Autochess arena: " + "; ".join(arena.errors))
		arena.light.shadow_enabled = bool(settings.get("shadows", true))
		arena.set_detail(bool(settings.get("terrain_detail", true)))
		effects = ELCombatEffects.new()
		add_child(effects)
		effects.build(profile)
		_arenas[scene_id] = {"arena": arena, "effects": effects}
	audio = ELBattleAudio.new()
	add_child(audio)
	audio.build(profile, arena.definition, settings)
	audio.listener = _listener
	audio.process_mode = Node.PROCESS_MODE_DISABLED if _muted else Node.PROCESS_MODE_INHERIT
	audio.paused = _muted
	effects.set_arena(arena, audio.play)
	if not is_instance_valid(fire): _build_fire()
	_place_fire()
	for side: int in heroes:
		var model: ELModel = heroes[side].get("model")
		if is_instance_valid(model): effects.attach(model)
		_place_hero(side)
	return true

## Builds `scene_id` ahead of time (while nothing is on the board), so
## choosing a hero or meeting a rival does not stop the game to build it.
func warm_arena(scene_id: String) -> void:
	if _arenas.has(scene_id) or not models.is_empty(): return
	var current := arena_id
	_build_arena(scene_id)
	if not current.is_empty(): _build_arena(current)

func _exit_tree() -> void:
	# Battlefields waiting aside are not in the tree; free them with the board.
	for kept: Dictionary in _arenas.values():
		for node: Node in [kept.arena, kept.effects]:
			if is_instance_valid(node) and not node.is_inside_tree(): node.queue_free()

## A line of flames along the edge of the deployment area, as in the
## Cursed Lands autochess (which drew no other border): the original
## battlefield fire tongues (CombatScenes/Alpha/ArenaFire, four by two
## frames), shown while preparing.
func _build_fire() -> void:
	if is_instance_valid(fire): fire.queue_free()
	fire = Node3D.new()
	fire.name = "Fire"
	add_child(fire)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.particles_anim_h_frames = 4
	material.particles_anim_v_frames = 2
	material.particles_anim_loop = false
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = profile.texture("CombatScenes/Alpha/ArenaFire")
	# The sheet's tongues hang from the top edge: flipped to rise from the ground.
	material.uv1_scale = Vector3(1, -1, 1)
	material.uv1_offset = Vector3(0, 1, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.95)
	quad.center_offset = Vector3(0, 0.5, 0)
	quad.material = material
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 0.95, 0.85, 0.9), Color(1, 0.8, 0.6, 0.75), Color(1, 0.6, 0.4, 0)])
	_flame_material = material
	_flame_ramp = ramp
	var field := ELAutochessRules.FIELD
	var segments := 30
	for index in segments:
		var flames := CPUParticles3D.new()
		flames.mesh = quad
		flames.material_override = material
		flames.amount = 4
		flames.lifetime = 0.8
		flames.randomness = 0.5
		flames.local_coords = true
		flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		flames.emission_box_extents = Vector3(0.08, 0.0, field.size.y / segments * 0.5)
		flames.direction = Vector3.UP
		flames.spread = 0.0
		flames.initial_velocity_min = 0.0
		flames.initial_velocity_max = 0.15
		flames.gravity = Vector3.ZERO
		flames.scale_amount_min = 0.6
		flames.scale_amount_max = 1.1
		flames.color_ramp = ramp
		flames.anim_speed_min = 1.0
		flames.anim_speed_max = 1.0
		flames.preprocess = 0.9
		flames.set_meta("z", field.position.y + (index + 0.5) * field.size.y / segments)
		fire.add_child(flames)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var strip := QuadMesh.new()
	strip.size = Vector2(1.6, field.size.y)
	strip.orientation = PlaneMesh.FACE_Y
	# Brightest along the line, fading across it and toward both ends.
	var image := Image.create(32, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		var along := clampf(minf(y, 127 - y) / 14.0, 0.0, 1.0)
		for x in 32:
			var across := 1.0 - absf(x - 15.5) / 16.0
			image.set_pixel(x, y, Color(1, 0.42, 0.08, across * across * along * 0.55))
	var shine := ImageTexture.create_from_image(image)
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lit.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lit.albedo_texture = shine
	strip.material = lit
	glow.mesh = strip
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.add_child(glow)

## Puts the flames on the watched side's deployment edge, on the ground.
func _place_fire() -> void:
	if not is_instance_valid(fire): return
	var edge := ELAutochessRules.DEPLOY.end.x
	for flames: Node3D in fire.get_children():
		if flames.name == "Glow":
			flames.position = world(Vector2(edge, 0.0)) + Vector3(0, 0.06, 0)
			continue
		flames.position = world(Vector2(edge, float(flames.get_meta("z", 0.0)))) + Vector3(0, 0.02, 0)

func set_fire(on: bool) -> void:
	if not is_instance_valid(fire): return
	if on and not fire.visible: _place_fire()
	fire.visible = on

## Puts hero `id` on side `side`'s sideline (empty removes it).
func set_hero(side: int, id: String) -> void:
	var current: Dictionary = heroes.get(side, {})
	if String(current.get("id", "")) == id and is_instance_valid(current.get("model")): return
	if is_instance_valid(current.get("model")): current.model.queue_free()
	heroes.erase(side)
	if id.is_empty(): return
	var row := ELAutochessCharacters.row(profile, id)
	if row.is_empty(): return
	var model := ELModel.new()
	add_child(model)
	if not model.build(profile, String(row.get("Model", "")), "Heroes/" + String(row.get("Texture", "")).replace("\\", "/")):
		model.queue_free()
		return
	var hero_model := String(row.get("Model", "")).to_lower().begins_with("he")
	model.scale = Vector3.ONE * 1.5 * (1.0 if hero_model else 1.25)
	model.idle_specials = true
	model.play("cidle")
	model.animation_finished.connect(func(clip: String):
		if clip != "udeath" and is_instance_valid(model): model.play.call_deferred("cidle"))
	if is_instance_valid(effects): effects.attach(model)
	heroes[side] = {"id": id, "model": model}
	_fallen.erase(side)
	_place_hero(side)

func _place_hero(side: int) -> void:
	var model: ELModel = heroes.get(side, {}).get("model")
	if not is_instance_valid(model): return
	var field := ELAutochessRules.FIELD
	# On the field's own ground at its edge, beyond the deployment area,
	# moved to the nearest spot clear of the battlefield's rocks and walls.
	var spot := _hero_spot(Vector2(-10.5 if side == 0 else 4.0, field.end.y - 0.4))
	var height := arena.ground_height(spot.x, spot.y) if is_instance_valid(arena) else 0.0
	model.position = Vector3(spot.x, height, spot.y)
	# Watching the middle of the field, turned toward their own half.
	var look := Vector2(spot.x * 0.5, 0.0) - spot
	model.rotation.y = atan2(look.x, look.y)

## Free hero spots found per battlefield: "scene|x|z" -> spot.
var _hero_spots: Dictionary = {}

func _hero_spot(wanted: Vector2) -> Vector2:
	if not is_instance_valid(arena): return wanted
	var key := "%s|%.1f|%.1f" % [arena_id, wanted.x, wanted.y]
	if _hero_spots.has(key): return _hero_spots[key]
	var candidates: Array[Vector2] = []
	for across in range(-6, 7):
		for depth: float in [0.0, -0.6, 0.6, -1.2]: candidates.append(wanted + Vector2(across * 0.75, depth))
	# Nearest first; moving off the sideline counts a little more than along it.
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return absf(a.x - wanted.x) + 1.3 * absf(a.y - wanted.y) < absf(b.x - wanted.x) + 1.3 * absf(b.y - wanted.y))
	var found := wanted
	for candidate in candidates:
		if arena.clear_spot(candidate, 0.8):
			found = candidate
			break
	_hero_spots[key] = found
	return found

# --- The round's end ------------------------------------------------------------
# As in the original autochess: each surviving recruit of the winning side turns
# to the losing hero and sends it a fire bolt worth its share of the damage.

const BOLT_SECONDS := 0.75
const BOLT_STAGGER := 0.18
var _flame_material: StandardMaterial3D
var _flame_ramp: Gradient
## Battle figures turned to the losing hero (fighter id -> yaw).
var _turned: Dictionary = {}

func survivors_fire(winner: int) -> void:
	if battle == null or winner < 0 or _flame_material == null: return
	var mine := 1 if flip else 0
	var hero: ELModel = heroes.get(1 if winner == mine else 0, {}).get("model")
	if not is_instance_valid(hero): return
	var order := 0
	for u: ELAutochessBattle.Fighter in battle.units:
		if u.dead or u.team != winner or u.creep or u.echo or u.family < 0: continue
		var model: ELModel = models.get(u.id)
		if model == null or not model.visible: continue
		var look := hero.global_position - model.global_position
		_turned[u.id] = atan2(look.x, look.z)
		_send_bolt(model, hero, ELAutochessRules.survivor_damage(u.family, u.rank), 0.35 + order * BOLT_STAGGER)
		order += 1

func _send_bolt(source: ELModel, hero: ELModel, share: int, delay: float) -> void:
	var bolt := Node3D.new()
	bolt.name = "SurvivorBolt"
	add_child(bolt)
	bolt.visible = false
	var flames := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.6)
	quad.material = _flame_material
	flames.mesh = quad
	flames.material_override = _flame_material
	flames.amount = 24
	flames.lifetime = 0.35
	# A trail left in the air behind the bolt.
	flames.local_coords = false
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.08
	flames.gravity = Vector3(0, 0.6, 0)
	flames.initial_velocity_max = 0.2
	flames.scale_amount_min = 0.7
	flames.scale_amount_max = 1.2
	flames.color_ramp = _flame_ramp
	flames.anim_speed_min = 1.0
	flames.anim_speed_max = 1.0
	# No light of its own: a light appearing mid-battle recompiles shaders
	# (a hitch); the additive flames glow on their own.
	bolt.add_child(flames)
	var source_ref: WeakRef = weakref(source)
	var hero_ref: WeakRef = weakref(hero)
	var from := source.global_position + Vector3(0, box(source).end.y * 0.6, 0)
	var rise := Vector3(0, 1.0 + from.distance_to(head(hero)) * 0.12, 0)
	bolt.position = from
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func():
		bolt.visible = true
		var caster: ELModel = source_ref.get_ref()
		if caster != null and caster.has_clip("uinstant"): caster.play("uinstant"))
	tween.tween_method(func(at: float):
		var target: ELModel = hero_ref.get_ref()
		if target == null: return
		var goal := head(target) - Vector3(0, 0.35, 0)
		bolt.position = from.lerp(goal, at) + rise * 4.0 * at * (1.0 - at), 0.0, 1.0, BOLT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		flames.emitting = false
		var target: ELModel = hero_ref.get_ref()
		if target == null: return
		if share > 0: _number(target, "-%d" % share, Color(1.0, 0.45, 0.3))
		if not (target.clip == "uhit" and target.playing) and target.has_clip("uhit"): target.play("uhit")
		if is_instance_valid(effects): effects.play("RedDamage", {"Target": [target]})
		if is_instance_valid(audio): audio.effect("RedDamage", target))
	tween.tween_interval(0.6)
	tween.tween_callback(bolt.queue_free)

## The sideline heroes' head points for the overlay: [{side, at}].
func hero_rows() -> Array:
	var rows := []
	for side: int in heroes:
		var model: ELModel = heroes[side].get("model")
		if is_instance_valid(model) and model.is_visible_in_tree(): rows.append({"side": side, "at": head(model)})
	return rows

## The hero on `side` plays `clip` (victory, a flinch, a summon gesture).
func hero_react(side: int, clip: String) -> void:
	if _fallen.get(side, false): return
	var model: ELModel = heroes.get(side, {}).get("model")
	if is_instance_valid(model) and model.has_clip(clip): model.play(clip)

## Heroes out of health, by side: they fall and stay down.
var _fallen: Dictionary = {}

## A hero at 0 health falls (after `delay`, so the survivors' bolts land
## first) and lies there; `at_once` shows it already lying.
func set_fallen(side: int, fallen: bool, delay := 0.0, at_once := false) -> void:
	if bool(_fallen.get(side, false)) == fallen: return
	_fallen[side] = fallen
	var model: ELModel = heroes.get(side, {}).get("model")
	if not is_instance_valid(model): return
	if not fallen:
		model.play("cidle")
		return
	if at_once:
		if model.play("udeath"): model.frame = maxf(0, model.clip_frames() - 1)
		return
	var fall := func():
		if is_instance_valid(model) and _fallen.get(side, false) and heroes.get(side, {}).get("model") == model:
			model.play("udeath")
			if is_instance_valid(audio): audio.unit(model, "death")
	if delay > 0.0 and is_inside_tree(): get_tree().create_timer(delay).timeout.connect(fall)
	else: fall.call()

func set_arena(scene_id: String) -> void:
	if scene_id != arena_id: _build_arena(scene_id)

var _listener: Camera3D
var _muted := false

func set_listener(camera: Camera3D) -> void:
	_listener = camera
	if is_instance_valid(audio): audio.listener = camera

## Silences the battlefield (music, ambience, voices) while a menu covers it.
func set_muted(muted: bool) -> void:
	_muted = muted
	if not is_instance_valid(audio): return
	audio.process_mode = Node.PROCESS_MODE_DISABLED if muted else Node.PROCESS_MODE_INHERIT
	audio.paused = muted
	for player: Node in audio.get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D: player.stream_paused = muted

func clear_units() -> void:
	_prep_again.clear()
	for model: ELModel in models.values():
		if is_instance_valid(model): model.queue_free()
	models.clear()
	_codes.clear()
	_numbers.clear()
	_turned.clear()
	_pending.clear()
	_shown_dead.clear()
	battle = null
	_event_index = 0
	item_pops.clear()

func world(point: Vector2) -> Vector3:
	var p := -point if flip else point
	var height := arena.ground_height(p.x, p.y) if is_instance_valid(arena) else 0.0
	return Vector3(p.x, height, p.y)

func board_point(position_3d: Vector3) -> Vector2:
	var p := Vector2(position_3d.x, position_3d.z)
	return -p if flip else p

func _make_model(code: String) -> ELModel:
	var row: Dictionary = profile.table("CombatCreatures").get(code, {})
	var model := ELModel.new()
	add_child(model)
	var secondary := "Creatures/" + String(row.SecTexture) if row.has("SecTexture") else ""
	if not model.build(profile, String(row.get("Model", "")), "Creatures/" + String(row.get("Texture", "")), secondary):
		push_warning("Autochess model %s: %s" % [code, model.error])
	model.scale = Vector3.ONE * float(row.get("Scale", 1.0))
	model.set_meta("sound_directory", row.get("SndDir", ""))
	model.set_meta("attack_sound", row.get("AttackSndType", ""))
	model.set_meta("skin_sound", row.get("SkinSndType", ""))
	model.set_meta("blood", row.get("Blood", ""))
	model.set_meta("code", code)
	if is_instance_valid(effects): effects.attach(model)
	return model

## Preparation: the company's deployed creatures standing at their points.
## `rows` are army entries; models are reused by uid.
## Figures built this frame by show_preparation, and the call to finish
## next frame when more were wanted (building is spread so a new round does
## not stop the game).
var _built_frame := -1
var _built_count := 0
var _prep_again: Array = []

func _may_build() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _built_frame:
		_built_frame = frame
		_built_count = 0
	if _built_count >= 2: return false
	_built_count += 1
	return true

func show_preparation(rows: Array, opponent: Array = []) -> void:
	if battle != null: clear_units()
	_prep_again.clear()
	var keep := {}
	for entry: Dictionary in rows:
		if not entry.get("deployed", false): continue
		var key := "p%d" % int(entry.uid)
		keep[key] = true
		var code := String(entry.code)
		if models.has(key) and _codes.get(key, "") != code:
			models[key].queue_free()
			models.erase(key)
		if not models.has(key):
			if not _may_build():
				_prep_again = [rows, opponent]
				continue
			models[key] = _make_model(code)
			_codes[key] = code
			models[key].set_meta("uid", int(entry.uid))
			# A creature being summoned stays hidden until its summon cue.
			if arriving.has(int(entry.uid)): models[key].visible = false
		var model: ELModel = models[key]
		var target := world(Vector2(float(entry.point[0]), float(entry.point[1])))
		model.set_meta("goal", target)
		if not model.has_meta("placed"):
			model.position = target
			model.set_meta("placed", true)
		model.rotation.y = PI * 0.5 if not flip else -PI * 0.5
	for entry: Dictionary in opponent:
		var key := "o%d" % int(entry.get("uid", 0))
		keep[key] = true
		if not models.has(key):
			if not _may_build():
				_prep_again = [rows, opponent]
				continue
			models[key] = _make_model(String(entry.code))
			_codes[key] = String(entry.code)
		var model: ELModel = models[key]
		model.position = world(Vector2(float(entry.point[0]), float(entry.point[1])))
		model.rotation.y = -PI * 0.5 if not flip else PI * 0.5
	for key: String in models.keys():
		if not keep.has(key):
			models[key].queue_free()
			models.erase(key)
			_codes.erase(key)

## Starts following `fight` (shown from team `team`'s side).
func show_battle(fight: ELAutochessBattle, team: int) -> void:
	clear_units()
	battle = fight
	flip = team == 1
	_event_index = 0
	for u: ELAutochessBattle.Fighter in fight.units: _pending.append(u.id)
	# A board joined mid-fight skips past events and shows corpses at once.
	_event_index = fight.events.size()

func _ensure(u: ELAutochessBattle.Fighter) -> ELModel:
	if models.has(u.id): return models[u.id]
	var model := _make_model(u.code)
	models[u.id] = model
	model.set_meta("uid", u.uid)
	model.set_meta("fighter", u.id)
	model.position = world(u.pos)
	model.rotation.y = _yaw(u.facing)
	if u.dead:
		if model.play("udeath"): model.frame = maxf(0, model.clip_frames() - 1)
		_shown_dead[u.id] = true
	return model

func _yaw(facing: float) -> float:
	return facing + (PI if flip else 0.0)

func _process(delta: float) -> void:
	_step_numbers(delta)
	if battle == null and not _prep_again.is_empty():
		var again := _prep_again.duplicate()
		show_preparation(again[0], again[1])
	if battle == null:
		for model: ELModel in models.values():
			if not model.has_meta("goal"): continue
			var goal: Vector3 = model.get_meta("goal")
			var offset := goal - model.position
			offset.y = 0
			if offset.length() > 0.05:
				var step := minf(offset.length(), 9.0 * delta)
				model.position += offset.normalized() * step
				model.position.y = arena.ground_height(model.position.x, model.position.z)
				model.rotation.y = atan2(offset.x, offset.z)
				_set_clip(model, _move_clip(model))
			else:
				model.position = goal
				model.rotation.y = PI * 0.5 if not flip else -PI * 0.5
				_set_clip(model, "cidle")
		return
	# Build at most two new figures per frame.
	var built := 0
	while not _pending.is_empty() and built < 2:
		var u := battle.unit(int(_pending.pop_front()))
		if u != null: _ensure(u)
		built += 1
	for id: int in item_pops.keys():
		item_pops[id] = float(item_pops[id]) - delta
		if float(item_pops[id]) <= 0.0: item_pops.erase(id)
	var events := battle.events
	while _event_index < events.size():
		_event(events[_event_index])
		_event_index += 1
	for u: ELAutochessBattle.Fighter in battle.units:
		if not models.has(u.id): continue
		var model: ELModel = models[u.id]
		var goal := world(u.pos)
		var offset := goal - model.position
		offset.y = 0
		var distance := offset.length()
		if distance > 3.0: model.position = goal
		elif distance > 0.001:
			model.position += offset * minf(1.0, delta * 12.0)
		model.position.y = arena.ground_height(model.position.x, model.position.z)
		if not u.dead:
			var facing: float = _turned.get(u.id, _yaw(u.facing))
			model.rotation.y = lerp_angle(model.rotation.y, facing, minf(1.0, delta * 10.0))
		if u.dead or _shown_dead.has(u.id): continue
		if model.clip in ["uattack", "uinstant", "uhit", "usummon"] and model.playing: continue
		# Once the battle is decided everyone stands still where they are.
		if u.moving and not battle.finished:
			_set_clip(model, _move_clip(model))
			model.speed = clampf(u.speed / maxf(0.5, _natural_speed(model)), 0.6, 1.8)
		else:
			model.speed = 1.0
			_set_clip(model, "cidle")

func _natural_speed(model: ELModel) -> float:
	var clip := _move_clip(model)
	var recorded := float(model.timing.get(clip, {}).get("speed", 0.0))
	return 2.0 * (recorded if recorded > 0.0 else 2.0) * model.scale.x

func _move_clip(model: ELModel) -> String:
	var clip := model.clip_for_code(ELMeleePlayback.RUN_CODE)
	if clip.is_empty(): clip = model.clip_for_code(ELMeleePlayback.WALK_CODE)
	if clip.is_empty(): clip = "crun" if model.has_clip("crun") else "cwalk"
	return clip

## Clips that play out before the figure settles back to idle.
const ONE_OFF_CLIPS := ["usummon", "uinstant", "uvictory", "uattack", "uhit"]

func _set_clip(model: ELModel, clip: String) -> void:
	if model.clip == clip and model.playing: return
	if model.clip == "cidle" and clip == "cidle": return
	# An entrance (a summon, an evolution) is not cut short by standing still.
	if clip == "cidle" and model.playing and model.clip in ONE_OFF_CLIPS: return
	if model.has_clip(clip): model.play(clip)

func _model(id: int) -> ELModel:
	if not models.has(id) and battle != null:
		var u := battle.unit(id)
		if u != null: return _ensure(u)
	return models.get(id)

func _event(e: Dictionary) -> void:
	var kind := String(e.k)
	match kind:
		"item":
			item_pops[int(e.u)] = ITEM_POP
		"attack":
			var model := _model(int(e.u))
			if model == null: return
			if model.play("uattack"):
				model.speed = 1.0 / maxf(0.35, float(e.get("s", 1.0)))
				audio.unit(model, "attack")
			# A ranged creature's blow is its own original ability effect
			# (the shaman's lightning, a spitter's spit) from it to the target.
			var shooter := battle.unit(int(e.u))
			if shooter != null and shooter.ranged:
				_creature_effect(String(model.get_meta("code", "")), model, _model(int(e.get("t", -1))))
		"cast":
			var model := _model(int(e.u))
			if model == null: return
			var clip := String(e.get("clip", "uinstant"))
			if not model.play(clip): model.play("uattack")
			model.speed = 1.0
			audio.unit(model, "instant" if clip == "uinstant" else "attack")
		"hit":
			var target := _model(int(e.u))
			if target == null: return
			var source := _model(int(e.get("s", -1)))
			if bool(e.get("miss", false)):
				_number(target, "miss", Color(0.8, 0.85, 0.9))
				return
			var value := int(e.get("v", 0))
			if value <= 0: return
			_number(target, str(value), Color(1.0, 0.35, 0.25) if (battle.unit(int(e.u)) != null and battle.unit(int(e.u)).team == (1 if flip else 0)) else Color(1.0, 0.9, 0.55))
			if String(e.get("kind", "")) == "attack" and source != null: audio.hit(source, target)
			var u := battle.unit(int(e.u))
			if u != null and not u.dead and not (target.clip in ["uattack", "uinstant"] and target.playing) and target.has_clip("uhit"):
				target.play("uhit")
				target.speed = 1.0
		"heal":
			var model := _model(int(e.u))
			if model != null: _number(model, "+%d" % int(e.v), Color(0.45, 1.0, 0.5))
		"death":
			var model := _model(int(e.u))
			if model == null: return
			_shown_dead[int(e.u)] = true
			model.speed = 1.0
			model.play("udeath")
			audio.unit(model, "death")
		"revive":
			var model := _model(int(e.u))
			if model == null: return
			_shown_dead.erase(int(e.u))
			if not model.play("usummon"): model.play("cidle")
			if is_instance_valid(effects): effects.play("PosSorcery", {"Target": [model]})
			audio.unit(model, "summon")
		"spawn":
			# A summoned creature rises in its colour's summon effect and
			# appears at the effect's summon cue, as in the duel.
			var model := _model(int(e.u))
			if model == null: return
			var u := battle.unit(int(e.u))
			var code := u.code if u != null else ""
			var delay := 0.0
			if is_instance_valid(effects):
				var names := EffectTable.card_effects(profile, code)
				for effect: String in names if not names.is_empty() else ["PosSorcery"]: effects.play(effect, {"Target": [model]})
				if not names.is_empty(): delay = ELCombatEffects.summon_delay(profile, code)
			model.play("cidle")
			model.visible = delay <= 0.0
			# Held weakly: the battle may be cleared before the cue.
			var held: WeakRef = weakref(model)
			var appear := func():
				var shown: ELModel = held.get_ref()
				if shown == null: return
				shown.visible = true
				if not shown.play("usummon"): shown.play("cidle")
				audio.unit(shown, "summon")
			if delay <= 0.0: appear.call()
			else: get_tree().create_timer(delay).timeout.connect(appear)
		"ability":
			var source := _model(int(e.u))
			var targets: Array = []
			for id: Variant in e.get("t", []):
				var model := _model(int(id))
				if model != null: targets.append(model)
			_ability_effect(String(e.a), source, targets, int(e.u))
		"stun":
			var model := _model(int(e.u))
			if model != null and is_instance_valid(effects): effects.play("CantUntap", {"Target": [model]})
		"team":
			var model := _model(int(e.u))
			if model != null and is_instance_valid(effects): effects.play("NegEnchantment", {"Target": [model]})

func _ability_effect(kind: String, source: ELModel, targets: Array, source_id: int) -> void:
	if not is_instance_valid(effects): return
	var code := String(source.get_meta("code", "")) if source != null else ""
	# The creature's own original ability effect (the duel's table).
	if source != null and kind in ["bolt", "nova", "execute", "stun", "silence", "drain", "dispel", "revive", "rally"]:
		var shown := false
		for target: ELModel in (targets if not targets.is_empty() else [source]):
			if _creature_effect(code, source, target): shown = true
		if shown: return
	# The creature's own original ability effect where it has one.
	if source != null and kind in ["bolt", "nova", "execute", "stun", "silence", "drain", "dispel", "revive", "rally"] and not code.is_empty():
		var started := 0
		for target: ELModel in targets:
			effects.trigger(code, {"Start": [source], "Finish": [target], "Target": [target]})
			started += 1
		if targets.is_empty(): effects.trigger(code, {"Start": [source], "Target": [source]})
		audio.trigger(code, targets[0] if not targets.is_empty() else source)
		if started > 0 or targets.is_empty(): return
	var name := String(ABILITY_EFFECTS.get(kind, ""))
	if name.is_empty(): return
	for target: ELModel in targets:
		if source != null and kind in ["bolt", "storm", "drain"]: effects.play(name, {"Start": [source], "Finish": [target], "Target": [target]})
		else: effects.play(name, {"Target": [target]})
	audio.effect(name, targets[0] if not targets.is_empty() else source)

## Plays `code`'s original ability effects from `source` at `target` (as the
## duel binds them). False when the creature has none.
func _creature_effect(code: String, source: ELModel, target: ELModel) -> bool:
	if code.is_empty() or source == null or not is_instance_valid(effects): return false
	var items := EffectTable.ability_effects("el2", code)
	if items.is_empty(): items = EffectTable.ability_effects("el1", code)
	var started := 0
	for item: Array in items:
		if item.size() < 2: continue
		var effect := String(item[0])
		var aim: ELModel = target if target != null else source
		match String(item[1]):
			"line": started += effects.play(effect, {"Start": [source], "Finish": [aim]})
			"to_user": started += effects.play(effect, {"Start": [aim], "Finish": [source]})
			"start": started += effects.play(effect, {"Start": [source]})
			"finish": started += effects.play(effect, {"Finish": [aim]})
			"enemy_start": started += effects.play(effect, {"Start": [aim]})
			_: started += effects.play(effect, {"Target": [aim]})
		audio.effect(effect, aim)
	return started > 0

func _number(model: ELModel, text: String, color: Color) -> void:
	_numbers.append({"model": model, "text": text, "color": color, "age": 0.0, "offset": randf_range(-0.3, 0.3)})
	if _numbers.size() > 60: _numbers.pop_front()

func _step_numbers(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for n: Dictionary in _numbers:
		n.age = float(n.age) + delta
		if float(n.age) < NUMBER_SECONDS and is_instance_valid(n.model): kept.append(n)
	_numbers = kept

## Floating numbers for the overlay: [world position, text, colour, alpha].
func floating_numbers() -> Array:
	var result := []
	for n: Dictionary in _numbers:
		if not is_instance_valid(n.model): continue
		var model: ELModel = n.model
		var top := head(model) + Vector3(float(n.offset), 0.4 + float(n.age) * 1.2, 0)
		result.append([top, n.text, n.color, 1.0 - float(n.age) / NUMBER_SECONDS])
	return result

## The figure's standing box in its own space, scaled: meshes only, so
## effects and particles around it do not count.
static func box(model: ELModel) -> AABB:
	if model.has_meta("box"): return model.get_meta("box")
	var result := AABB()
	var first := true
	for node: Node in model.get_children():
		var part := node as MeshInstance3D
		if part == null or part.mesh == null or not part.visible: continue
		var local := part.transform * part.mesh.get_aabb()
		local = AABB(local.position * model.scale, local.size * model.scale)
		result = local if first else result.merge(local)
		first = false
	if first: return AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1.6, 1))
	# Hovering creatures keep their gap above the ground.
	result.size.y = clampf(result.end.y, maxf(0.6, result.position.y + 0.3), 5.0) - result.position.y
	model.set_meta("box", result)
	return result

## The top of a figure (health bars and numbers).
func head(model: ELModel) -> Vector3:
	return model.global_position + Vector3(0, box(model).end.y + 0.2, 0)

## The figure's outline on screen: its box's corners projected.
func screen_rect(camera: Camera3D, model: ELModel) -> Rect2:
	var bounds := box(model)
	var turn := Basis(Vector3.UP, model.global_rotation.y)
	var result := Rect2()
	var first := true
	for i in 8:
		var corner := bounds.get_endpoint(i)
		var point := model.global_position + turn * corner
		if camera.is_position_behind(point): continue
		var at := camera.unproject_position(point)
		result = Rect2(at, Vector2.ZERO) if first else result.expand(at)
		first = false
	return result

## Health bars for the overlay: one row per living figure.
func health_rows() -> Array:
	var rows := []
	if battle == null: return rows
	var mine := 1 if flip else 0
	for u: ELAutochessBattle.Fighter in battle.units:
		if u.dead or not models.has(u.id) or not models[u.id].visible: continue
		rows.append({"at": head(models[u.id]), "hp": u.hp, "max": u.max_hp, "shield": u.shield, "rank": u.rank, "tier": u.tier, "uid": u.uid, "friend": u.team == mine, "creep": u.creep, "pop": float(item_pops.get(u.id, 0.0)) / ITEM_POP})
	return rows

func preparation_rows(rows: Array) -> Array:
	var result := []
	for entry: Dictionary in rows:
		var key := "p%d" % int(entry.uid)
		if not models.has(key) or not entry.get("deployed", false): continue
		result.append({"at": head(models[key]), "model": models[key], "uid": int(entry.uid), "rank": int(entry.rank), "family": int(entry.family), "code": String(entry.code)})
	return result

## The figure under a screen point (nearest projected body).
func pick(camera: Camera3D, at: Vector2) -> Dictionary:
	var best := {}
	var best_distance := 60.0
	for key: Variant in models:
		var model: ELModel = models[key]
		if not is_instance_valid(model) or not model.visible: continue
		var outline := screen_rect(camera, model)
		if outline.size == Vector2.ZERO: continue
		# The body itself, not the box's projected corners around it, so a
		# click just beside a creature still reaches the ground there.
		var body := outline.grow_individual(-outline.size.x * 0.18, -outline.size.y * 0.08, -outline.size.x * 0.18, 0.0)
		if body.size.x < 18.0: body = body.grow_side(SIDE_LEFT, (18.0 - body.size.x) * 0.5).grow_side(SIDE_RIGHT, (18.0 - body.size.x) * 0.5)
		var distance := at.distance_to(body.get_center())
		if body.has_point(at) and distance < best_distance:
			best_distance = distance
			best = {"key": key, "uid": int(model.get_meta("uid", 0)), "fighter": int(model.get_meta("fighter", -1)), "code": String(model.get_meta("code", ""))}
			best.model = model
	return best

## A ground point under the cursor in board space.
func ground_point(camera: Camera3D, at: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(at)
	var direction := camera.project_ray_normal(at)
	if absf(direction.y) < 0.0001: return Vector2.INF
	var t := -origin.y / direction.y
	if t < 0.0: return Vector2.INF
	# Onto the battlefield's own ground, which rises and falls.
	if is_instance_valid(arena):
		for step in 5:
			var point := origin + direction * t
			var height := arena.ground_height(point.x, point.z)
			var next := (height - origin.y) / direction.y
			if next < 0.0 or absf(next - t) < 0.01: break
			t = next
	return board_point(origin + direction * t)
