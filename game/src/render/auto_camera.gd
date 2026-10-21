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
## them turned half round. Hero, victory and multi-target tracks play
## at their authored world positions (the battlefield uses the original slots);
## creature and fight tracks are relative and follow the figure they frame.

const RATE := 30.0
const MAGIC := 0x1567fbca
## The authored default view's field of view and the remake's own view (degrees,
## vertical); other track angles keep their ratio of tangents to these. The
## second game's cameras take the authored angle as the horizontal one of a
## 4:3 screen (the map camera does natively; the original's standing battle
## view fits it), which is 34.5 degrees vertically.
const TRACK_FOV := 0.785398
const VIEW_FOV := 38.0
const SECOND_VIEW_FOV := 34.5
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
## Creature kinds already summoned under the camera this battle.
var seen: Dictionary = {}

## This edition's view angle (vertical degrees).
var view_angle := VIEW_FOV

func _init(source: ELProfile = null, seed := 0) -> void:
	profile = source
	rng.seed = seed
	if source != null: odds = read_odds(source.file("CombatCamera.ini"))
	if source != null and source.id == "el2": view_angle = SECOND_VIEW_FOV

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

static func view_fov(track_fov: float, angle := VIEW_FOV) -> float:
	return rad_to_deg(2.0 * atan(tan(track_fov * 0.5) * tan(deg_to_rad(angle) * 0.5) / tan(TRACK_FOV * 0.5)))

## The player's standing battle view as an orbit: the authored Default1 in
## both games (the second game's original frames its forest arena that way).
func standing_view() -> Dictionary:
	return default_view()

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
	var fov := view_fov(lerpf(shot.fovs[i], shot.fovs[j], f), view_angle)
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
## caster's figure position; targets: [{at: Vector3, side: int, slot: int,
## hero: bool}] of the figures it affects (the summoned creature for a summon;
## `slot` is a creature's home slot). `local` is the player's own side: the
## first game shows summoning only for that side.
##
## Both games choose alike: the first spell of a kind shows the caster and
## its target, the second only the target, later ones roll PlayHero/PlayMonster. The overview OwnerMonstersAll_<view> plays
## instead of the close-ups when the PlayFullScene roll succeeds (summons from
## the third on; enchantments from the second; sorcery once two enchantment
## shots have played: the original tests the enchantment counter there), when
## neither close-up was chosen, when the targets stand on both sides (both
## heroes, or creatures of both sides), or when a creature target stands in
## home slots 4-5. Several targets: _3 when one stands in slots 2-3 or 6+,
## else _2. A summoned creature in slots 4-5 gets no close-up; from the third
## summon, neither does a kind already summoned this battle while a caster
## shot or overview plays.
##
## `timing` is the caster's animation table: the caster shot and the overview
## are stretched over its casting gesture (summon and enchantment: the summon
## clip's length; sorcery: the instant clip's release frame).
##
## Sorcery that passes its effect's length (`length` seconds, plus `extra`)
## shows no caster shot and holds the target shot length + extra + 1 s;
## `forced` (Comet's lethal hit on a hero) always shows the target shot.
func cast(kind: String, caster: int, hero: Vector3, targets: Array, local: bool, dynamics: int, timing := {}, length := -1.0, extra := 0.0, forced := false) -> bool:
	if not counts.has(kind) or (kind == "summon" and not local): return false
	if not _roll(dynamics): return false
	var n: int = counts[kind]
	counts[kind] = n + 1
	var owner := caster if local else 1 - caster
	var flags := _target_flags(caster, targets)
	var gesture := cast_seconds(timing, kind)
	var list: Array[Dictionary] = []
	if kind == "summon":
		var variant := (n & 1) + 1
		var overview := n >= 2 and _roll(_odd(kind, "playfullscene"))
		if overview:
			list.append(placed("OwnerMonstersAll_1.cmf", Vector3.ZERO, owner, false, gesture))
		elif n == 0 or (n >= 2 and _roll(_odd(kind, "playhero"))):
			list.append(placed("SummonOwnerCaster%d_1.cmf" % variant, hero, caster, false, gesture))
		var new_kind := false
		for target: Dictionary in targets:
			var key := String(target.get("card", ""))
			if not seen.has(key):
				new_kind = true
				seen[key] = true
		# From the third summon a creature kind already seen this battle gets
		# no close-up while the caster shot or overview plays; the overview
		# then runs on by itself.
		if n >= 2 and not new_kind and not list.is_empty():
			return _queue(list, not overview)
		var stretch := _odd(kind, "monstertracktime")
		if targets.is_empty() or flags.slots & 4: pass
		elif flags.slots & 0x100:
			var pick := 3 if rng.randi() % 3 == 0 else variant
			list.append(placed("SummonOwnerMonster%d_1.cmf" % pick, targets[0].at, caster, true, stretch))
		else:
			list.append(placed(("SummonOwnerMonster%d_3.cmf" if flags.slots & 2 else "SummonOwnerMonster%d_2.cmf") % variant, _middle(targets), caster, false, stretch))
		return _queue(list)
	var hero_shot := n == 0 or (n >= 2 and _roll(_odd(kind, "playhero")))
	if kind == "sorcery" and length > 0.0: hero_shot = false
	var monster_shot := n < 2 or (kind == "sorcery" and forced) or _roll(_odd(kind, "playmonster"))
	if flags.sides & 0xe == 0:
		hero_shot = hero_shot or monster_shot
		monster_shot = false
	var gate: int = counts.enchantment
	var overview := gate > 1 and _roll(_odd(kind, "playfullscene"))
	if (not hero_shot and not monster_shot) or flags.sides & 0x30 or flags.slots & 4: overview = true
	if overview:
		return _queue([placed("OwnerMonstersAll_1.cmf", Vector3.ZERO, owner, false, gesture)], false)
	var variant := ((n + 1) & 1) + 1
	var stretch := _odd(kind, "monstertracktime") if kind == "enchantment" else (length + extra + 1.0 if length > 0.0 else -1.0)
	if hero_shot:
		var caster_shot := placed(("InstantOwner%d_1.cmf" if kind == "sorcery" else "EnchantmentOwnerCaster%d_1.cmf") % variant, hero, caster, false, gesture)
		# The spell's single target, when the caster's shot happens to show it.
		if not caster_shot.is_empty() and targets.size() == 1: caster_shot["with"] = [targets[0].at]
		list.append(caster_shot)
	# The target shot faces the targets' side: sorcery tracks look at enemy
	# creatures and turn round for the caster's own, enchantment tracks look
	# at the caster's own and turn round for enemies.
	var enemy: bool = int(flags.sides) & 0xa != 0
	var facing: int = (caster if enemy else 1 - caster) if kind == "sorcery" else (1 - caster if enemy else caster)
	if monster_shot and flags.slots & 0x100:
		list.append(placed(("InstantEnemyMonsters%d_1.cmf" if kind == "sorcery" else "EnchantmentOwnerMonster%d_1.cmf") % variant, targets[0].at, facing, true, stretch))
	elif monster_shot:
		var name := ("InstantEnemyMonsters%d_%d.cmf" if kind == "sorcery" else "SummonOwnerMonster%d_%d.cmf") % [variant, 3 if flags.slots & 2 else 2]
		list.append(placed(name, _middle(targets), facing, false, stretch))
	return _queue(list)

## Seconds of the caster's gesture that the caster shot and overview last
## (-1: the track's own length): for summons and enchantments the frame count
## of the summon clip (else the instant, else the attack clip); for sorcery the
## release frame of the instant clip (else the attack clip).
static func cast_seconds(timing: Dictionary, kind: String) -> float:
	var order := ["usummon", "uinstant", "uattack"] if kind != "sorcery" else ["uinstant", "uattack"]
	for clip: String in order:
		if timing.has(clip):
			var frames := int(timing[clip].get("frames" if kind != "sorcery" else "mark", 0))
			return frames / 30.0 if frames > 0 else -1.0
	return -1.0

## The original's target flags. sides: 1 own hero, 2 other hero, 4 own creature, 8 other
## creature, 0x10 both heroes, 0x20 creatures of both sides. slots (creatures
## only): 1 home slots 0-1, 2 slots 2-3 or 6+, 4 slots 4-5; 0x100 exactly one
## target of any kind.
static func _target_flags(caster: int, targets: Array) -> Dictionary:
	var sides := 0
	var slots := 0
	for target: Dictionary in targets:
		var own := int(target.get("side", caster)) == caster
		if target.get("hero", false):
			sides |= 1 if own else 2
			continue
		sides |= 4 if own else 8
		var slot := int(target.get("slot", 0))
		slots |= 1 if slot < 2 else (2 if slot < 4 or slot > 5 else 4)
	if sides & 3 == 3: sides |= 0x10
	if sides & 0xc == 0xc: sides |= 0x20
	if targets.size() == 1: slots |= 0x100
	return {"sides": sides, "slots": slots}

static func _middle(targets: Array) -> Vector3:
	var middle := Vector3.ZERO
	for target: Dictionary in targets: middle += target.at
	return middle / targets.size()

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

## The winner's camera; it keeps its last frame until the battle closes or the
## player moves the view.
func victory(winner: int, hero: Vector3) -> bool:
	var shot := placed("WINCameraOwner.cmf", hero, winner)
	if shot.is_empty(): return false
	shot.hold = true
	return _queue([shot], false)
