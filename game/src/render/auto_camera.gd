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
## them turned half round. Hero, victory, tremor and multi-target tracks play
## at their authored world positions (the battlefield uses the original slots);
## creature and fight tracks are relative and follow the figure they frame.

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

## A track's keys turned for `side`. Relative tracks are moved onto `anchor`
## (the original adds the framed figure's position to them); absolute ones
## keep their authored place and `anchor` only names what they frame.
func placed(name: String, anchor: Vector3, side: int, relative := false, duration := -1.0) -> Dictionary:
	var source := track(name)
	if source.is_empty(): return {}
	var turn := Basis(Vector3.UP, PI) if side == 0 else Basis.IDENTITY
	var shift := anchor if relative else Vector3.ZERO
	var positions := PackedVector3Array()
	var rotations: Array[Quaternion] = []
	for i in source.positions.size():
		positions.append(turn * source.positions[i] + shift)
		rotations.append(Quaternion(turn) * source.rotations[i])
	var natural: float = source.positions.size() / RATE
	return {"name": name, "positions": positions, "rotations": rotations, "fovs": source.fovs,
		"duration": duration if duration > 0.0 else natural, "focus": turn * source.target + shift, "anchor": anchor, "orbit": false, "hold": false}

## The original's standing battle view (Default<n>.cmf, n = AutoCameraView + 1,
## shipped 0; ReturnOwner_<n> ends on it) seen from the player's side at -X,
## as an orbit about the point it looks at on the ground.
func default_view(index := 0) -> Dictionary:
	var source := track("Default%d.cmf" % (index + 1))
	if source.is_empty(): return {}
	var turn := Basis(Vector3.UP, PI)
	var position: Vector3 = turn * source.positions[0]
	var forward: Vector3 = turn * (Basis(source.rotations[0]) * Vector3.FORWARD)
	if forward.y > -0.01: return {}
	var target := position + forward * (-position.y / forward.y)
	var offset := position - target
	return {"target": target, "yaw": atan2(offset.x, offset.z), "pitch": asin(offset.y / offset.length()), "distance": offset.length()}

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
	return {"position": shot.positions[i].lerp(shot.positions[j], f), "rotation": shot.rotations[i].slerp(shot.rotations[j], f), "fov": fov, "focus": shot.focus, "anchor": shot.get("anchor", shot.focus), "with": shot.get("with", [])}

## Where `point` appears (pixels) for a camera at `position` turned by
## `rotation` with a vertical field of view `fov` (degrees) on `screen`.
static func project(position: Vector3, rotation: Quaternion, fov: float, screen: Vector2, point: Vector3) -> Vector2:
	var local := Basis(rotation).inverse() * (point - position)
	var depth := maxf(-local.z, 0.001)
	var half := tan(deg_to_rad(fov) * 0.5) * depth
	return Vector2((local.x / (half * screen.x / screen.y) + 1.0) * 0.5 * screen.x, (1.0 - local.y / half) * 0.5 * screen.y)

## The remake's battle screen has interface pieces over its edges, which the
## authored tracks did not allow for. A close-up keeps its angle and motion but
## slides sideways or up/down just enough that the framed `point` stays inside
## `safe` (pixels on `screen`); the camera is unchanged when it already is.
## `limit` (pixels) caps the slide; 0 leaves it uncapped.
static func keep_in(position: Vector3, rotation: Quaternion, fov: float, screen: Vector2, safe: Rect2, point: Vector3, limit := 0.0) -> Vector3:
	if screen.x <= 0.0 or screen.y <= 0.0 or not safe.has_area(): return position
	var basis := Basis(rotation)
	var local := basis.inverse() * (point - position)
	var depth := -local.z
	if depth <= 0.01: return position
	var at := project(position, rotation, fov, screen, point)
	var wanted := Vector2(clampf(at.x, safe.position.x, safe.end.x), clampf(at.y, safe.position.y, safe.end.y))
	if wanted.is_equal_approx(at): return position
	if limit > 0.0: wanted = at + (wanted - at).limit_length(limit)
	var half := tan(deg_to_rad(fov) * 0.5) * depth
	var per_pixel := Vector2(2.0 * half * screen.x / screen.y / screen.x, 2.0 * half / screen.y)
	# Moving the camera right moves the point left on screen; up moves it down.
	return position + basis.x * (at.x - wanted.x) * per_pixel.x + basis.y * (wanted.y - at.y) * per_pixel.y

## A close-up's camera position kept clear of the interface: points in `with`
## that the shot already shows (on screen but under the frame) are eased out
## from under it by at most a tenth of the screen, then the framed `point`
## always ends inside `safe`.
static func clear_of_frame(position: Vector3, rotation: Quaternion, fov: float, screen: Vector2, safe: Rect2, point: Vector3, with: Array = []) -> Vector3:
	var visible := Rect2(Vector2.ZERO, screen)
	for other: Vector3 in with:
		if (Basis(rotation).inverse() * (other - position)).z >= -0.01: continue
		if visible.has_point(project(position, rotation, fov, screen, other)):
			position = keep_in(position, rotation, fov, screen, safe, other, screen.y * 0.1)
	return keep_in(position, rotation, fov, screen, safe, point)

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
		var caster_shot := placed(("InstantOwner%d_1.cmf" if kind == "sorcery" else "EnchantmentOwnerCaster%d_1.cmf") % variant, hero, caster)
		# The spell's single target, when the caster's shot happens to show it.
		if not caster_shot.is_empty() and targets.size() == 1: caster_shot["with"] = [targets[0].at]
		list.append(caster_shot)
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

## The own-attack declaration shot (EL1 event 3, EL2
## ). The track follows the committed attackers' home
## slots (flags from EL1 / EL2): all on even slots
## AttackOwnLeft, all on odd slots -> AttackOwnRight; otherwise _3 when one
## stands in slots 4-5, _2 when one stands in slots 2-3 or 6-9, else _1.
## Monsters1/2 is a roll against the combat side-select odds.
func attack_own(side: int, middle: Vector3, dynamics: int, slots: Array[int] = []) -> bool:
	if profile == null or profile.id not in ["el1", "el2"] or not _roll(dynamics): return false
	var flags := 0
	for slot: int in slots:
		if slot < 2: flags |= 1
		elif slot < 4 or slot > 5: flags |= 2
		else: flags |= 4
		flags |= 0x10 if slot % 2 == 0 else 0x20
	var name := "AttackOwnMonsters%d_1.cmf"
	if flags & 0x30 == 0x10: name = "AttackOwnLeftMonsters%d_1.cmf"
	elif flags & 0x30 == 0x20: name = "AttackOwnRightMonsters%d_1.cmf"
	elif flags & 4: name = "AttackOwnMonsters%d_3.cmf"
	elif flags & 2: name = "AttackOwnMonsters%d_2.cmf"
	var variant := 2 if _roll(100.0 - _odd("combat", "camerasideselect")) else 1
	return _queue([placed(name % variant, middle, side, true)])

## The original camera archive contains a dedicated, short Tremor1.CMF
## track (16 keys at 30 fps). Anchor its authored motion on the arena
## centre instead of substituting the ordinary hero/monster sorcery shots.
## The edition-specific cast dispatcher controls when this track is selected.
func tremor(side: int, dynamics: int) -> bool:
	if not _roll(dynamics): return false
	return _queue([placed("Tremor1.cmf", Vector3.ZERO, side)])

## The winner's camera; it keeps its last frame until the battle closes or the
## player moves the view.
func victory(winner: int, hero: Vector3) -> bool:
	var shot := placed("WINCameraOwner.cmf", hero, winner)
	if shot.is_empty(): return false
	shot.hold = true
	return _queue([shot], false)
