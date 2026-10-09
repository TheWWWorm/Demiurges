class_name ELAutoCamera
extends RefCounted
## The battle's automatic camera (Options: automatic camera, camera dynamics,
## numbers in close-ups).
##
## Each edition's camera.res holds authored camera tracks (*.cmf): 30 keys a
## second of camera position, rotation and field of view. A battle event picks
## its tracks with the odds in the installation's CombatCamera.ini; "camera
## dynamics" is the percentage of events that cut to a close-up at all. After
## the close-ups a short return track brings back the player's own view.
##
## The tracks are authored for the side standing at +X and the other side sees
## them turned half round. The remake spaces its battlefield differently, so
## every track is anchored on the figure it frames (a hero, a creature or the
## middle of a fight) instead of being played at its authored world position.

const RATE := 30.0
const MAGIC := 0x1567fbca
## The authored default view's field of view and the remake's own view (degrees,
## vertical); other track angles keep their ratio of tangents to these.
const TRACK_FOV := 0.785398
const VIEW_FOV := 38.0
## Shipped CombatCamera.ini values, used when the installation lacks the file.
const DEFAULT_ODDS := {
	"summon": {"camerasideselect": 50.0, "playfullscene": 5.0, "playhero": 80.0, "monstertracktime": 4.0},
	"sorcery": {"camerasideselect": 50.0, "playhero": 80.0, "playmonster": 90.0, "playfullscene": 5.0},
	"enchantment": {"camerasideselect": 50.0, "playhero": 70.0, "playmonster": 60.0, "playfullscene": 10.0, "monstertracktime": 4.0},
	"combat": {"camerasideselect": 50.0, "playtrack": 90.0}}

var profile: ELProfile
var rng := RandomNumberGenerator.new()
var odds: Dictionary = DEFAULT_ODDS.duplicate(true)
## Queued shots; the first one plays. Each: {name, keys, duration, focus, orbit, hold}.
var shots: Array[Dictionary] = []
var clock := 0.0
## Spells of each kind cast so far in this battle: the first two always follow
## a fixed pattern before the odds apply.
var counts := {"summon": 0, "sorcery": 0, "enchantment": 0}
var _tracks: Dictionary = {}

func _init(source: ELProfile = null, seed := 0) -> void:
	profile = source
	rng.seed = seed
	if source != null: odds = read_odds(source.file("CombatCamera.ini"))

func active() -> bool:
	return not shots.is_empty()

## True while an authored close-up (not the return to the player's view) plays.
func close_up() -> bool:
	return not shots.is_empty() and not bool(shots[0].orbit)

func stop() -> void:
	shots.clear()
	clock = 0.0

## CombatCamera.ini: [Summon]/[Sorcery]/[Enchantment]/[Combat] with
## `Key = value` lines; `//` starts a comment.
static func read_odds(path: String) -> Dictionary:
	var result: Dictionary = DEFAULT_ODDS.duplicate(true)
	if path.is_empty() or not FileAccess.file_exists(path): return result
	var section := ""
	for raw: String in ELText.ansi(FileAccess.get_file_as_bytes(path)).split("\n"):
		var line := raw.get_slice("//", 0).strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges().to_lower()
		elif "=" in line and result.has(section):
			var value := line.get_slice("=", 1).strip_edges()
			if value.is_valid_float(): result[section][line.get_slice("=", 0).strip_edges().to_lower()] = value.to_float()
	return result

## One track in the remake's axes: {target: Vector3, positions, rotations, fovs};
## empty when the entry is missing or malformed.
static func parse(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 64 or bytes.decode_u32(0) != MAGIC: return {}
	var count := bytes.decode_u32(4)
	if count < 1 or 32 + count * 32 > bytes.size(): return {}
	var positions := PackedVector3Array()
	var rotations: Array[Quaternion] = []
	var fovs := PackedFloat32Array()
	for i in count:
		var at := 32 + i * 32
		positions.append(ELFigure.vector(Vector3(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8))))
		# Stored as the inverse rotation; the camera looks along its local -Z with +Y up.
		var turn := Basis(Quaternion(bytes.decode_float(at + 12), bytes.decode_float(at + 16), bytes.decode_float(at + 20), -bytes.decode_float(at + 24)).normalized())
		rotations.append(Basis(ELFigure.vector(turn.x), ELFigure.vector(turn.y), ELFigure.vector(turn.z)).get_rotation_quaternion())
		fovs.append(bytes.decode_float(at + 28))
	var target := ELFigure.vector(Vector3(bytes.decode_float(8), bytes.decode_float(12), bytes.decode_float(16)))
	return {"target": target, "positions": positions, "rotations": rotations, "fovs": fovs}

func track(name: String) -> Dictionary:
	if not _tracks.has(name):
		_tracks[name] = parse(profile.read("camera", name)) if profile != null else {}
	return _tracks[name]

## A track's keys turned for `side` and moved onto `anchor`. Absolute tracks are
## anchored by their authored look-at point on the ground; relative ones by
## their origin (the original adds the framed figure's position to them).
func placed(name: String, anchor: Vector3, side: int, relative := false, duration := -1.0) -> Dictionary:
	var source := track(name)
	if source.is_empty(): return {}
	var turn := Basis(Vector3.UP, PI) if side == 0 else Basis.IDENTITY
	var origin: Vector3 = Vector3.ZERO if relative else Vector3(source.target.x, 0, source.target.z)
	var shift := anchor - turn * origin
	var positions := PackedVector3Array()
	var rotations: Array[Quaternion] = []
	for i in source.positions.size():
		positions.append(turn * source.positions[i] + shift)
		rotations.append(Quaternion(turn) * source.rotations[i])
	var natural: float = source.positions.size() / RATE
	return {"name": name, "positions": positions, "rotations": rotations, "fovs": source.fovs,
		"duration": duration if duration > 0.0 else natural, "focus": turn * source.target + shift, "orbit": false, "hold": false}

static func view_fov(track_fov: float) -> float:
	return rad_to_deg(2.0 * atan(tan(track_fov * 0.5) * tan(deg_to_rad(VIEW_FOV) * 0.5) / tan(TRACK_FOV * 0.5)))

## Advances the playing shot. Returns {position, rotation, fov, focus} for a
## close-up, {orbit: true, fov} while returning to the player's view, and {}
## once the automatic camera has finished.
func step(delta: float) -> Dictionary:
	while not shots.is_empty():
		var shot: Dictionary = shots[0]
		if clock < float(shot.duration) or bool(shot.hold): break
		clock -= float(shot.duration)
		shots.pop_front()
	if shots.is_empty():
		clock = 0.0
		return {}
	var shot: Dictionary = shots[0]
	var count: int = shot.fovs.size()
	var at := clampf(clock / maxf(float(shot.duration), 0.001), 0.0, 1.0) * float(maxi(count - 1, 0))
	var i := mini(int(at), count - 1)
	var j := mini(i + 1, count - 1)
	var f := at - i
	clock += delta
	var fov := view_fov(lerpf(shot.fovs[i], shot.fovs[j], f))
	if bool(shot.orbit): return {"orbit": true, "fov": fov}
	return {"position": shot.positions[i].lerp(shot.positions[j], f), "rotation": shot.rotations[i].slerp(shot.rotations[j], f), "fov": fov, "focus": shot.focus}

func _roll(percent: float) -> bool:
	return rng.randi_range(1, 100) <= int(percent)

func _odd(kind: String, key: String) -> float:
	return float(odds.get(kind, {}).get(key, DEFAULT_ODDS[kind].get(key, 0.0)))

func _queue(list: Array[Dictionary], back := true) -> bool:
	var playable: Array[Dictionary] = []
	for shot in list:
		if not shot.is_empty(): playable.append(shot)
	if playable.is_empty(): return false
	if back:
		var home := track("ReturnOwner_1.cmf")
		if not home.is_empty():
			playable.append({"name": "ReturnOwner_1.cmf", "fovs": home.fovs, "duration": home.fovs.size() / RATE, "orbit": true, "hold": false})
	# A new event replaces whatever was still playing.
	shots = playable
	clock = 0.0
	return true

## A hero's spell. kind: "summon", "sorcery" or "enchantment"; hero: the
## caster's figure position; targets: [{at: Vector3, side: int}] of the
## creatures it affects (the summoned creature for a summon). `local` is the
## player's own side: the first game shows summoning only for that side.
func cast(kind: String, caster: int, hero: Vector3, targets: Array, local: bool, dynamics: int) -> bool:
	if not counts.has(kind) or (kind == "summon" and not local): return false
	if not _roll(dynamics): return false
	var n: int = counts[kind]
	counts[kind] = n + 1
	var list: Array[Dictionary] = []
	if kind == "summon":
		var variant := (n & 1) + 1
		if n >= 2 and _roll(_odd(kind, "playfullscene")): return false
		if n == 0 or (n >= 2 and _roll(_odd(kind, "playhero"))):
			list.append(placed("SummonOwnerCaster%d_1.cmf" % variant, hero, caster))
		if targets.size() == 1:
			var pick := 3 if rng.randi() % 3 == 0 else variant
			list.append(placed("SummonOwnerMonster%d_1.cmf" % pick, targets[0].at, caster, true, _odd(kind, "monstertracktime")))
		return _queue(list)
	var hero_shot := n == 0 or (n >= 2 and _roll(_odd(kind, "playhero")))
	var monster_shot := n < 2 or _roll(_odd(kind, "playmonster"))
	if targets.is_empty():
		hero_shot = hero_shot or monster_shot
		monster_shot = false
	if (not hero_shot and not monster_shot) or (targets.size() > 1 and _roll(_odd(kind, "playfullscene"))): return false
	var variant := ((n + 1) & 1) + 1
	var stretch := _odd(kind, "monstertracktime") if kind == "enchantment" else -1.0
	if hero_shot:
		list.append(placed(("InstantOwner%d_1.cmf" if kind == "sorcery" else "EnchantmentOwnerCaster%d_1.cmf") % variant, hero, caster))
	if monster_shot and targets.size() == 1:
		if kind == "sorcery": list.append(placed("InstantEnemyMonsters%d_1.cmf" % variant, targets[0].at, caster, true))
		else: list.append(placed("EnchantmentOwnerMonster%d_1.cmf" % variant, targets[0].at, int(targets[0].side), true, stretch))
	elif monster_shot:
		var middle := Vector3.ZERO
		for target: Dictionary in targets: middle += target.at
		list.append(placed(("InstantEnemyMonsters%d_2.cmf" if kind == "sorcery" else "SummonOwnerMonster%d_2.cmf") % variant, middle / targets.size(), caster, false, stretch))
	return _queue(list)

## The first blow of a fight: a close-up beside the middle of the fighting
## creatures, from the attacking side; "Left"/"Right" by where the fight is.
func combat(attacker: int, middle: Vector3, dynamics: int) -> bool:
	if not _roll(dynamics) or not _roll(_odd("combat", "playtrack")): return false
	var lateral := middle.z if attacker == 1 else -middle.z
	var right := lateral >= 2.0 or (lateral > -2.0 and rng.randi() % 2 == 0)
	return _queue([placed("AttackCombat%sMonsters%d_1.cmf" % ["Right" if right else "Left", rng.randi_range(1, 2)], middle, attacker, true)])

## The winner's camera; it keeps its last frame until the battle closes or the
## player moves the view.
func victory(winner: int, hero: Vector3) -> bool:
	var shot := placed("WINCameraOwner.cmf", hero, winner)
	if shot.is_empty(): return false
	shot.hold = true
	return _queue([shot], false)
