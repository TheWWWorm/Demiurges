class_name ELMeleePlayback
extends Node
## Combat resolution as the originals show it (EL1, EL2).
##
## The rules settle every blow at once; the originals play them from a graph
## of visual events instead. This node holds the battle's events from the
## first strike on and plays them back in order:
##
## - Attackers are taken one after another. A blocked attacker runs to its
##   fight point on the centre line (the mean of where its lines to the
##   blockers cross it, stopped 0.75 short on its own side) while the first
##   blocker runs to it, stopping at the larger of their contact ranges
##   (CombatCreatures AtRange, scaled by the model in the second game). An
##   unblocked attacker runs to contact range of the defending hero.
## - The two face each other; blows are struck one at a time. Each blow's
##   attack clip lands its hit sound, the damage and the victim's hit or death
##   at the clip's impact frame; the next blow waits for both clips.
## - A blocker walks home when its exchange is over and the next blocker sets
##   off at once; an attacker walks home after its last blow and the next
##   attacker sets off at the same moment. The battle goes on once everyone
##   is home.
##
## Moves use the clip found by its original code (Run, else Walk) at twice the
## clip's recorded speed (2.0 without one), the clip at its native 30 fps; the
## second game scales both by the model. Returning wounded figures walk (first
## game: a third of their toughness lost; second game: attackers with any
## wound, blockers never). HideMotion (CombatFastMode) runs every move at 20
## units/s. The hero's contact radius is unconfirmed and uses a creature's
## usual range.
##
## Layout (EL1, EL2; constants): heroes stand
## at x ±3.75; a side's creatures take the first free of ten slots on an arc
## of radius 12.75 about x = -6 (mirrored for side 0), two per angle step,
## slots 6-9 a second row 1.5 further out. Home slots sit 1.5 further from the
## centre; front-line slots 3 closer in. A declared attacker runs to its front
## line after a random 0-0.1 s stagger; a withdrawn one walks back through it.
## Every walk home passes the front line, then the figure faces the enemy hero.

const FIGHT_BACKOFF := 0.75
const HERO_X := 3.75
const ARC_CENTRE := -6.0
const ARC_RADIUS := 12.75
const SECOND_ROW := 1.5
const HOME_OUT := 1.5
const FRONT_IN := 3.0
const SLOTS := 10
enum Line { HOME, FRONT }
const HERO_RANGE := 1.5
const FAST_SPEED := 20.0
const FALLBACK_SPEED := 2.0
const WALK_CODE := 0x80140000
const RUN_CODE := 0x80100000
## Kinds that start the battle's next stage; they wait until everyone is home.
const AFTER_KINDS := ["phase", "turn_pos_rune", "turn_neg_rune", "turn_stasis"]

## The duel view (ELDuel view script): models, homes and event handling.
var view: Node
var queue: Array[Dictionary] = []
var _capturing := false
var _dispatching := false
var _running := false
var _serial := 0
## id -> {points: Array[Vector3], speed: float, finish: float (facing yaw or NAN)}
var _moves := {}
## The blows being played, the events after them, and the first blow whose
## events are not yet handled.
var _blows: Array[Dictionary] = []
var _after: Array[Dictionary] = []
var _next_blow := 0
## Damage each figure has taken in the blows shown so far (the rules clear
## combat damage before the playback ends).
var _wounds := {}

## A side's slot position in remake axes (original x, -y).
static func slot_position(side: int, index: int, line: Line) -> Vector3:
	var step := acos(11.55 / 12.75) / 4.0
	var pair := (index % SLOTS) >> 1
	var radius := ARC_RADIUS + SECOND_ROW * float(index / SLOTS)
	var first := 0
	if pair >= 3:
		radius += SECOND_ROW
		first = 1
		pair -= 3
	var angle := float(first + 2 * pair + 2) * step
	if line == Line.FRONT: radius -= FRONT_IN
	var x := cos(angle) * radius + ARC_CENTRE + (HOME_OUT if line == Line.HOME else 0.0)
	var y := sin(angle) * radius * (1.0 if index % 2 == 1 else -1.0)
	if side == 0:
		x = -x
		y = -y
	return Vector3(x, 0, -y)

static func hero_position(side: int) -> Vector3:
	return Vector3(-HERO_X if side == 0 else HERO_X, 0, 0)

## Attack declared: the creature runs to its front-line slot after a short stagger.
func step_out(id: int) -> void:
	if not _has(id) or not view.duel.creatures.has(id): return
	var c: Dictionary = view.duel.creatures[id]
	var front := slot_position(int(c.owner), int(view.models[id].get_meta("slot", 0)), Line.FRONT)
	_move(id, [front], true, _yaw_at(front, int(c.owner)), randf() * 0.1)

## Attack withdrawn: back through the front line to its home slot.
func step_back(id: int) -> void:
	if not _has(id) or not view.duel.creatures.has(id): return
	var c: Dictionary = view.duel.creatures[id]
	_move(id, _home_path(id, int(c.owner)), true, _yaw_at(view.homes[id], int(c.owner)))

func _home_path(id: int, side: int) -> Array:
	var slot := int(view.models[id].get_meta("slot", 0))
	var front := slot_position(side, slot, Line.FRONT)
	var path: Array = []
	# Only a figure that has left its front line walks back through it.
	if flat_distance(_position(id), view.homes[id]) > flat_distance(front, view.homes[id]) + 0.01: path.append(front)
	path.append(view.homes[id])
	return path

## The yaw that faces the opposing hero from where a figure stands.
func _enemy_yaw(id: int, side: int) -> float:
	return _yaw_at(_position(id), side)

func _yaw_at(at: Vector3, side: int) -> float:
	var target: Vector3 = view.models[1 - side].position if _has(1 - side) else hero_position(1 - side)
	return atan2(target.x - at.x, target.z - at.z)

static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func busy() -> bool:
	return _running or _capturing

## Whether the playback is moving this figure (its run/walk clip must stay).
func moving(id: int) -> bool:
	return _moves.has(id)

## Takes an event from the battle. Returns true when the playback holds it:
## the first strike opens playback, and every later event waits its turn.
func capture(data: Dictionary) -> bool:
	if _dispatching: return false
	if not busy() and data.get("kind") != "strike": return false
	var held := data.duplicate()
	if held.kind == "strike":
		_note_strike(held)
	queue.append(held)
	if not busy():
		_capturing = true
		call_deferred("_start")
	return true

## Records what the strike needs once the rules have moved on: the attacking
## side and each figure's contact range and wounds rule inputs.
func _note_strike(strike: Dictionary) -> void:
	var duel: ELDuel = view.duel
	strike.attacking = int(duel.attacker)
	for key: String in ["from", "to"]:
		var id := int(strike[key])
		var c: Dictionary = duel.creatures.get(id, {})
		strike[key + "_owner"] = int(c.get("owner", id)) if id >= 2 else id
		strike[key + "_range"] = float(view.profile.table("CombatCreatures").get(str(c.get("card", "")), {}).get("AtRange", HERO_RANGE)) if id >= 2 else HERO_RANGE

func _start() -> void:
	if not _capturing: return
	_capturing = false
	_running = true
	_serial += 1
	_play(_serial)

## Ends the playback at once: every held event is handled and the figures
## stand at home (a new battle, a load, or a check that needs the result).
func finish() -> void:
	if not busy(): return
	_serial += 1
	_capturing = false
	for id: int in _moves.keys(): _arrive(id)
	_moves.clear()
	var rest: Array[Dictionary] = []
	for index in range(_next_blow, _blows.size()): rest.append_array(_blows[index].events)
	rest.append_array(_after)
	rest.append_array(queue.filter(func(data: Dictionary) -> bool: return data.kind != "strike"))
	_blows.clear()
	_after.clear()
	queue.clear()
	_dispatch_all(rest)
	for id: int in view.homes:
		if view.models.has(id) and view.duel.creatures.has(id):
			view.models[id].position = view.homes[id]
			view.models[id].rotation.y = _enemy_yaw(id, int(view.duel.creatures[id].owner))
	_running = false
	view._refresh()

## Drops the playback without handling anything (the battle is being replaced).
func abort() -> void:
	_serial += 1
	_capturing = false
	_running = false
	for id: int in _moves:
		if view.models.has(id): view.battle_audio.stop_glide(view.models[id])
	_moves.clear()
	_blows.clear()
	_after.clear()
	queue.clear()

func _dispatch(data: Dictionary) -> void:
	if data.kind == "damage": _wounds[int(data.target)] = int(_wounds.get(int(data.target), 0)) + int(data.amount)
	_dispatching = true
	view._event(data)
	_dispatching = false

func _play(serial: int) -> void:
	# Split the held events: blows with what each settles, then what follows.
	_blows.clear()
	_after.clear()
	_next_blow = 0
	_wounds.clear()
	var blows := _blows
	var after := _after
	for data: Dictionary in queue:
		if data.kind == "strike" and after.is_empty(): blows.append({"strike": data, "events": []})
		elif after.is_empty() and not data.kind in AFTER_KINDS and not blows.is_empty(): blows[-1].events.append(data)
		else: after.append(data)
	queue.clear()
	# Each attacker's blockers, for its fight point.
	var blockers := {}
	for blow: Dictionary in blows:
		var pair := _pair(blow.strike)
		if pair.y >= 2:
			if not blockers.has(pair.x): blockers[pair.x] = []
			if not blockers[pair.x].has(pair.y): blockers[pair.x].append(pair.y)
	var engaged := {}
	var fight_point := {}
	for index in blows.size():
		var blow: Dictionary = blows[index]
		var strike: Dictionary = blow.strike
		var from := int(strike.from)
		var to := int(strike.to)
		var pair := _pair(strike)
		if pair.y < 2:
			# Unblocked (or trampling on): run to the defending hero.
			if engaged.has(pair.x) and engaged[pair.x] >= 2: _go_home(int(engaged[pair.x]), false, strike)
			engaged[pair.x] = pair.y
			if _has(pair.x) and _has(pair.y):
				var reach := maxf(float(strike.from_range if from == pair.x else strike.to_range), HERO_RANGE) * _scale(pair.x)
				_move(pair.x, [_contact(_position(pair.y), _position(pair.x), reach)], true)
				if not await _moved([pair.x], serial): return
		elif engaged.get(pair.x, -1) != pair.y:
			# A new blocker meets the attacker at its fight point.
			if engaged.has(pair.x) and engaged[pair.x] >= 2: _go_home(int(engaged[pair.x]), true, strike)
			engaged[pair.x] = pair.y
			if not fight_point.has(pair.x) and _has(pair.x):
				fight_point[pair.x] = _fight_point(pair.x, blockers.get(pair.x, []))
				_move(pair.x, [fight_point[pair.x]], true)
			if _has(pair.y):
				var reach := maxf(_range_of(strike, pair.x) * _scale(pair.x), _range_of(strike, pair.y) * _scale(pair.y))
				var target: Vector3 = fight_point.get(pair.x, _position(pair.x))
				_move(pair.y, [_contact(target, _position(pair.y), reach)], true)
			if not await _moved([pair.x, pair.y], serial): return
			_face(pair.x, pair.y)
			_face(pair.y, pair.x)
		# The blow: attack clip, then at impact the hit sound and its results.
		_face(from, to)
		# The fight close-up starts as the first blow is struck (the
		# original's Camera(3)), framed on the two figures.
		if not view.fight_shot and _has(from) and _has(to): view._auto_fight(from, to, (_position(from) + _position(to)) * 0.5)
		if _has(from):
			var model: ELModel = view.models[from]
			view.battle_audio.unit(model, "attack")
			model.play("uattack")
			var length := maxf(model.clip_seconds("uattack"), 0.0)
			var impact := float(model.timing.get("uattack", {}).get("impact", -1)) / 30.0
			if impact < 0.0 or impact > length: impact = length * 0.5
			if not await _wait(impact, serial): return
			if _has(to): view.battle_audio.hit(model, view.models[to])
			_next_blow = index + 1
			_dispatch_all(blow.events)
			var rest := length - impact
			if _has(to) and blow.events.any(func(e: Dictionary) -> bool: return e.kind == "damage" and int(e.get("target", -1)) == to):
				rest = maxf(rest, maxf(view.models[to].clip_seconds("uhit"), 0.0))
			if not await _wait(rest, serial): return
		else:
			_next_blow = index + 1
			_dispatch_all(blow.events)
		# The exchange is over when the next blow is another pair.
		var next := _pair(blows[index + 1].strike) if index + 1 < blows.size() else Vector2i(-1, -1)
		if next.x != pair.x:
			if pair.y >= 2: _go_home(pair.y, true, strike)
			_go_home(pair.x, false, strike)
			engaged.erase(pair.x)
		elif next.y != pair.y and pair.y >= 2 and engaged.get(pair.x, -1) == pair.y:
			_go_home(pair.y, true, strike)
			engaged[pair.x] = -1
	if not await _moved(_moves.keys(), serial): return
	view._auto_fight_over()
	var rest := after.duplicate()
	_blows.clear()
	_after.clear()
	_dispatch_all(rest)
	_running = false
	if not queue.is_empty():
		# Events that arrived meanwhile without a strike of their own.
		var late := queue.duplicate()
		queue.clear()
		_dispatch_all(late)
	view._refresh()

func _dispatch_all(events: Array) -> void:
	for data: Dictionary in events: _dispatch(data)

## (attacker, opponent) of a blow: the attacking side's creature first.
func _pair(strike: Dictionary) -> Vector2i:
	if int(strike.from_owner) == int(strike.attacking): return Vector2i(int(strike.from), int(strike.to))
	return Vector2i(int(strike.to), int(strike.from))

func _range_of(strike: Dictionary, id: int) -> float:
	return float(strike.from_range) if int(strike.from) == id else float(strike.to_range)

func _has(id: int) -> bool:
	return view.models.has(id) and is_instance_valid(view.models[id])

func _position(id: int) -> Vector3:
	return view.models[id].position if _has(id) else Vector3.ZERO

## Second game: ranges and speeds follow the model's scale.
func _scale(id: int) -> float:
	if view.profile.id != "el2" or not _has(id): return 1.0
	return view.models[id].scale.x

## `distance` from `target` toward `from` (stay put when already closer).
func _contact(target: Vector3, from: Vector3, distance: float) -> Vector3:
	var offset := Vector3(from.x - target.x, 0, from.z - target.z)
	if offset.length() <= distance or offset.length() < 0.001: return from
	return target + offset.normalized() * distance

## The mean of where the attacker's lines to its blockers cross the centre
## line, stopped 0.75 short toward the attacker.
func _fight_point(attacker: int, defenders: Array) -> Vector3:
	var a := _position(attacker)
	var sum := 0.0
	for id: int in defenders:
		var b := _position(id)
		if absf(b.x - a.x) > 0.001: sum += a.z + (0.0 - a.x) * (b.z - a.z) / (b.x - a.x)
	var point := Vector3(0, 0, sum / maxf(defenders.size(), 1))
	var back := Vector3(a.x - point.x, 0, a.z - point.z)
	return point + back.normalized() * FIGHT_BACKOFF if back.length() > 0.001 else point

func _face(id: int, target: int) -> void:
	if not _has(id) or not _has(target): return
	var direction := _position(target) - _position(id)
	if Vector2(direction.x, direction.z).length() > 0.001: view.models[id].rotation.y = atan2(direction.x, direction.z)

## A figure's walk home after its exchange; it faces the enemy once there.
func _go_home(id: int, blocker: bool, strike: Dictionary) -> void:
	if not _has(id) or not view.homes.has(id) or not view.duel.creatures.has(id): return
	var c: Dictionary = view.duel.creatures[id]
	var wounds := int(_wounds.get(id, 0))
	var run := true
	if view.profile.id == "el1": run = wounds * 3 < int(c.get("toughness", 1))
	elif not blocker: run = wounds == 0
	_move(id, _home_path(id, int(c.owner)), run, _yaw_at(view.homes[id], int(c.owner)))

## Starts a move along `points` with the original clip and speed.
func _move(id: int, points: Array, run: bool, finish_yaw := NAN, delay := 0.0) -> void:
	if not _has(id) or points.is_empty(): return
	var model: ELModel = view.models[id]
	var fast := bool(view.settings.values.get("hide_motion", false))
	var clip := model.clip_for_code(RUN_CODE) if run or fast else ""
	if clip.is_empty(): clip = model.clip_for_code(WALK_CODE)
	if clip.is_empty() and (run or fast): clip = "crun" if model.has_clip("crun") else ""
	if clip.is_empty(): clip = "cwalk" if model.has_clip("cwalk") else ""
	var speed := FAST_SPEED
	if not fast:
		var recorded := float(model.timing.get(clip, {}).get("speed", 0.0)) if not clip.is_empty() else 0.0
		speed = 2.0 * (recorded if recorded > 0.0 else FALLBACK_SPEED) * _scale(id)
	var path: Array[Vector3] = []
	for point: Vector3 in points: path.append(Vector3(point.x, 0, point.z))
	# The original names the move Run only when the figure has a clip under
	# the run code; otherwise it walks (and loops walk.wav).
	var running := (run or fast) and not model.clip_for_code(RUN_CODE).is_empty()
	_moves[id] = {"points": path, "speed": speed, "finish": finish_yaw, "delay": delay, "clip": clip, "run": running}
	if delay <= 0.0: _set_off(id)

## The move's clip and its looping ground sound start together.
func _set_off(id: int) -> void:
	var move: Dictionary = _moves[id]
	var model: ELModel = view.models[id]
	if not str(move.clip).is_empty() and model.clip != move.clip: model.play(move.clip)
	view.battle_audio.glide(model, bool(move.run))

## Whether the figure is moving with this clip (its footfalls sound).
func stepping(id: int, clip: String) -> bool:
	return _moves.has(id) and float(_moves[id].delay) <= 0.0 and str(_moves[id].clip) == clip

func _process(delta: float) -> void:
	for id: int in _moves.keys():
		if not _has(id):
			_moves.erase(id)
			if view.models.has(id): view.battle_audio.stop_glide(view.models[id])
			continue
		var move: Dictionary = _moves[id]
		var model: ELModel = view.models[id]
		if float(move.delay) > 0.0:
			move.delay = float(move.delay) - delta
			if float(move.delay) > 0.0: continue
			_set_off(id)
		var step := float(move.speed) * delta
		while step > 0.0 and not move.points.is_empty():
			var goal: Vector3 = move.points[0]
			var flat := Vector3(goal.x - model.position.x, 0, goal.z - model.position.z)
			if flat.length() > 0.001: model.rotation.y = atan2(flat.x, flat.z)
			if flat.length() <= step:
				model.position = Vector3(goal.x, model.position.y, goal.z)
				step -= flat.length()
				move.points.pop_front()
			else:
				model.position += flat.normalized() * step
				step = 0.0
		model.position.y = view.arena.ground_height(model.position.x, model.position.z)
		if move.points.is_empty(): _arrive(id)

## A move's end: the final facing, then the figure's resting clip.
func _arrive(id: int) -> void:
	var move: Dictionary = _moves.get(id, {})
	_moves.erase(id)
	if view.models.has(id): view.battle_audio.stop_glide(view.models[id])
	if not _has(id): return
	var model: ELModel = view.models[id]
	if not move.is_empty() and not move.points.is_empty():
		var goal: Vector3 = move.points[-1]
		model.position = Vector3(goal.x, view.arena.ground_height(goal.x, goal.z), goal.z)
	if not move.is_empty() and not is_nan(float(move.finish)): model.rotation.y = float(move.finish)
	view._animation_done("", id)

func _moved(ids: Array, serial: int) -> bool:
	while serial == _serial and is_inside_tree() and ids.any(func(id: Variant) -> bool: return _moves.has(int(id))):
		await get_tree().process_frame
	return serial == _serial

func _wait(seconds: float, serial: int) -> bool:
	if seconds > 0.0 and is_inside_tree(): await get_tree().create_timer(seconds, false).timeout
	return serial == _serial
