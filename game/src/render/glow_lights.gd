class_name ELGlowLights
extends Node3D
## Light from glowing effects in the ordinary picture (the "spell_light"
## preference, a remake addition after Cursed Lands' spell lighting): the
## brightest glowing patches of the particle systems and effect models now
## showing each get a pooled lamp, so a fireball, an aura or a wall of fire
## lights the figures and scenery near it. The effects' own authored point
## lights are untouched. One spell lamp may cast a shadow. Path tracing traces the same
## glow itself, so these stay dark while it runs.

## Most lamps lit at once (the Compatibility renderer lights a surface with
## at most eight lamps, authored ones included).
const LIMIT := 6
## Patches this close together share one lamp: a dense effect is one source
## of light, not a floodlight of six.
const MERGE := 2.5
## The most energy a lamp gives, and how fast it gets there with the summed
## colour of its patches (energy = limit * (1 - exp(-colour * rise))): a faint
## aura gives a little light, a fireball most of the limit, and no effect
## bleaches the ground however dense it is.
const ENERGY_LIMIT := 0.9
## A passing spell (and a hero's cast) may give more: held to the standing
## fires' limit, a bolt or a cast hardly showed on the ground beside it.
const SPELL_ENERGY_LIMIT := 1.5
## A spell's own lamp goes further still. At SPELL_ENERGY_LIMIT it matched a
## glowing weapon's: two staffs beside the cast filled its shadow in, and the
## figures threw none from it.
const CAST_ENERGY_LIMIT := 7.0
const ENERGY_RISE := 0.2
## A lamp's reach: this, plus three times the patch's own extent. Two units
## are a metre, so a fire lights the ground a few metres around it.
const REACH := 8.0
## A spell's own lamp reaches further: at REACH a lightning bolt lit the
## creature it struck and hardly the hero beside it.
const SPELL_REACH := 14.0
## The brightest lamp casts a shadow, so a figure standing in front of a wall
## of fire throws one. The rest do not: a dozen shadow maps a frame would
## cost more than the picture gains, and the light of a dense effect comes
## from every side of it anyway. Measured on a 3090 Ti at 720p, through a
## fire wave in a dark arena, the one shadow costs about 0.05 ms a frame in
## Forward+; a device that cannot afford that has no spell light at all, as
## ELHardwareCheck turns the preference off below its full budget.
const SHADOW_LAMPS := 1
## A figure's own glowing particles (a Kinet hero's blade, which glows the
## whole battle) light only this share of what a spell would, and never cast
## a shadow. At full strength and casting, the lamp stood inside the figure:
## it threw the wings' shadow across the hero's own body and the ground,
## jumping as the clip changed, and it lifted the snow of the Kinet arenas
## past the bloom threshold, so the hero stood in a white haze.
## Held to a quarter at half the reach, a Chaot hero's glowing axe lit
## nothing round it, and the hero stood black in a dark arena with a bright
## blue blade: the weapon's own light (kind 1) gives WEAPON_SHARE at
## WEAPON_REACH, still without a shadow, and the spread glow keeps the rest.
const ATTACHED_SHARE := 0.25
const ATTACHED_REACH := 0.5
const WEAPON_SHARE := 1.0
const WEAPON_REACH := 1.0
## The highlight a weapon's lamp leaves on metal, and the energy it may reach
## (a spell's limit: at the standing fires' it still hardly showed on plate).
const WEAPON_SPECULAR := 0.5

## The share and reach factor of a figure's light of `kind` (1 its weapon,
## 2 the glow spread over it).
static func figure_share(kind: int) -> float:
	return WEAPON_SHARE if kind == 1 else (AURA_SHARE if kind == 2 else ATTACHED_SHARE)

static func figure_reach(kind: int) -> float:
	return WEAPON_REACH if kind == 1 else ATTACHED_REACH
## The glow spread over a figure (the sparkles on a Kinet hero's wings): a
## soft light that keeps the wings lit from within, as the old lamp at the
## chest did, without its shadows or its hopping.
const AURA_SHARE := 0.35

## Whether a lamp may cast one. The Compatibility renderer draws the glowing
## sprites beside a shadowing omni light as opaque white squares, and a
## shadow costs twelve times there what it does in Forward+, so its lamps
## light without casting. Spell light itself works in both.
static func shadows_available() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"
## Lamps fall off gently (Godot's inverse-distance power), so the ground a
## low effect touches does not burn out.
const FALLOFF := 0.35
## Sudden changes are spread over about this long (seconds): the glowing
## patches of a particle system regroup from frame to frame.
const SMOOTHING := 0.08
## A figure's lamp fades this slowly (seconds) when its glow is gone, and
## keeps its place among the LIMIT meanwhile: a Kinet hero's wing sparkles
## leave a gap of a few frames each time the idle clip starts over, and the
## lamp went out and came back with it.
const FIGURE_FADE := 0.5

## A continuing spell keeps its shadow unless another lamp is substantially
## brighter, and only after holding it SHADOW_HOLD seconds. Small particle
## flickers must not trade the shadow every frame: at a quarter brighter
## and no hold, a battle's shadow hopped from lamp to lamp a few dozen
## times, each time swinging every figure's shadow round at once.
const SHADOW_SWITCH_RATIO := 1.6
const SHADOW_HOLD := 0.75
## A shadow handed on fades out over this long (seconds) and the next fades
## in, rather than the figures' shadows snapping to a new direction.
const SHADOW_FADE := 0.2
## Spell lamps hang at least this high over `floor_height` (two units are a
## metre). A spell's glowing patches sit at a figure's waist or lower, often
## inside it: a lamp there, below the top of the figure beside it, threw that
## figure's shadow out to the end of its reach, across half the ring. Just
## over a figure's head, a figure beside the spell throws a shadow about as
## long as it is tall. Hung higher (6), the shadow fell under the figure and
## hid from the overhead camera.
const SPELL_LAMP_HEIGHT := 4.5
## A spell lamp eases to where its glow now stands over this long (seconds):
## its patches regroup as the sparks come and go, and the lamp followed them
## up to a metre in one frame, dragging the shadow with it.
const SPELL_SETTLING := 0.3

## The ground the spell lamps hang over (the battle arena's, set by
## ELCombatEffects); NAN leaves them where their glow is.
var floor_height := NAN
var _pool: Array[OmniLight3D] = []
var _shadow_lamp: OmniLight3D
## The lamp that should cast next, while _shadow_lamp's shadow fades out.
var _shadow_next: OmniLight3D
var _shadow_held := 0.0

## Shows `sources` ([[world centre, extent, summed linear colour, steady,
## attached], ...], as the effects' glow_sources give them), merged into
## lamps, brightest first up to LIMIT. A spell comes before the arena's own
## standing fires and the figures' own glow: their light is painted into the
## scenery already, or stands there all battle, while a spell's is the light
## the picture is missing, and they would otherwise take the whole budget in
## an arena ringed with braziers.
func show_sources(sources: Array, delta: float) -> void:
	sources = merged(sources)
	# Spells first, then figures, then standing fires. Keep a fading figure
	# through short gaps only when that does not displace an incoming spell.
	sources.sort_custom(func(a: Array, b: Array) -> bool:
		var a_rank := _rank(a)
		var b_rank := _rank(b)
		if a_rank != b_rank: return a_rank < b_rank
		return a[2].length_squared() > b[2].length_squared())
	var held := 0
	for lamp: OmniLight3D in _pool:
		if lamp.visible and lamp.get_meta(&"figure", false): held += 1
	var figures := 0
	var spells := 0
	for source: Array in sources:
		if _attached(source): figures += 1
		elif not _steady(source): spells += 1
	var reserved := mini(maxi(0, held - figures), maxi(0, LIMIT - spells - figures))
	if sources.size() > LIMIT - reserved: sources.resize(LIMIT - reserved)
	var blend := 1.0 - exp(-delta / SMOOTHING) if delta > 0.0 else 1.0
	var slow := 1.0 - exp(-delta / FIGURE_FADE) if delta > 0.0 else 1.0
	var settle := 1.0 - exp(-delta / SPELL_SETTLING) if delta > 0.0 else 1.0
	var free: Array[OmniLight3D] = _pool.duplicate()
	# Match every continuing source before recycling a slot. Otherwise a new,
	# bright spell could steal the lamp still needed by another nearby source.
	var matches: Array[OmniLight3D] = []
	for source: Array in sources:
		var nearest: OmniLight3D = null
		var distance := 4.0
		for candidate: OmniLight3D in free:
			if not candidate.visible or int(candidate.get_meta(&"source_rank", -1)) != _rank(source): continue
			var gap := candidate.global_position.distance_squared_to(_hung(source))
			if gap <= distance:
				nearest = candidate
				distance = gap
		matches.append(nearest)
		if nearest != null: free.erase(nearest)
	var shadow_candidates: Array[OmniLight3D] = []
	for index in sources.size():
		var source: Array = sources[index]
		var attached := _attached(source)
		var colour: Vector3 = source[2]
		var peak := maxf(colour.x, maxf(colour.y, colour.z))
		var centre := _hung(source)
		var spell := not _steady(source)
		var lamp: OmniLight3D = matches[index]
		var fresh := lamp == null
		if fresh:
			for candidate: OmniLight3D in free:
				if not candidate.visible:
					lamp = candidate
					break
			if lamp == null and _pool.size() < LIMIT:
				lamp = OmniLight3D.new()
				lamp.shadow_enabled = false
				lamp.light_specular = 0.0
				lamp.omni_attenuation = FALLOFF
				lamp.visible = false
				add_child(lamp)
				_pool.append(lamp)
			if lamp == null:
				# All slots exist: recycle an unmatched fading lamp, keeping a
				# figure's steady aura in preference to a departed spell or fire.
				for candidate: OmniLight3D in free:
					if lamp == null or _retire_before(candidate, lamp): lamp = candidate
			free.erase(lamp)
		var tint := colour / peak
		var wanted := Color(tint.x, tint.y, tint.z).linear_to_srgb()
		var weapon := attached and int(source[4]) == 1
		var energy := energy_limit(source) * (1.0 - exp(-peak * ENERGY_RISE))
		var reach := (REACH if _steady(source) else SPELL_REACH) + clampf(float(source[1]), 0.1, 3.0) * 3.0
		if attached:
			energy *= figure_share(int(source[4]))
			reach *= figure_reach(int(source[4]))
		# A weapon's light glints on the armour beside it. Armour is painted
		# as metal, which takes little diffuse light: lit without a highlight,
		# a Chaot warrior in plate stayed black beside her glowing mace.
		lamp.light_specular = WEAPON_SPECULAR if weapon else 0.0
		lamp.set_meta(&"figure", attached)
		lamp.set_meta(&"source_rank", _rank(source))
		if fresh:
			# A recycled lamp belongs to a new source. Do not drag its old
			# colour/position or shadow across the intervening ground.
			if lamp == _shadow_lamp or lamp == _shadow_next:
				lamp.shadow_enabled = false
				if lamp == _shadow_lamp: _shadow_lamp = null
				if lamp == _shadow_next: _shadow_next = null
			lamp.global_position = centre
			lamp.light_color = wanted
			lamp.light_energy = energy * blend
			lamp.omni_range = reach
			lamp.visible = true
		else:
			lamp.global_position = lamp.global_position.lerp(centre, settle if spell else blend)
			lamp.light_color = lamp.light_color.lerp(wanted, blend)
			lamp.light_energy = lerpf(lamp.light_energy, energy, blend)
			lamp.omni_range = lerpf(lamp.omni_range, reach, blend)
		if spell: shadow_candidates.append(lamp)
	for lamp: OmniLight3D in free:
		if not lamp.visible: continue
		var figure: bool = lamp.get_meta(&"figure", false)
		lamp.light_energy = lerpf(lamp.light_energy, 0.0, slow if figure else blend)
		if lamp.light_energy < 0.01:
			lamp.visible = false
			lamp.set_meta(&"figure", false)
	_sync_shadows(shadow_candidates, delta)

## The most a source's lamp gives: a spell CAST_ENERGY_LIMIT, a glowing
## weapon SPELL_ENERGY_LIMIT, anything else standing ENERGY_LIMIT.
static func energy_limit(source: Array) -> float:
	if not _steady(source): return CAST_ENERGY_LIMIT
	return SPELL_ENERGY_LIMIT if _attached(source) and int(source[4]) == 1 else ENERGY_LIMIT


## Where a source's lamp hangs: a spell's no lower than SPELL_LAMP_HEIGHT.
func _hung(source: Array) -> Vector3:
	var centre: Vector3 = source[0]
	if not _steady(source) and not is_nan(floor_height): centre.y = maxf(centre.y, floor_height + SPELL_LAMP_HEIGHT)
	return centre

static func _retire_before(a: OmniLight3D, b: OmniLight3D) -> bool:
	var a_figure: bool = a.get_meta(&"figure", false)
	var b_figure: bool = b.get_meta(&"figure", false)
	if a_figure != b_figure: return not a_figure
	return a.light_energy < b.light_energy

## One lamp casts (SHADOW_LAMPS). A delta of 0 hands the shadow on at once.
func _sync_shadows(candidates: Array[OmniLight3D], delta := 0.0) -> void:
	var best: OmniLight3D = null
	if shadows_available() and SHADOW_LAMPS > 0:
		for lamp: OmniLight3D in candidates:
			if best == null or lamp.light_energy > best.light_energy: best = lamp
		var holding := _shadow_lamp if _shadow_next == null else _shadow_next
		if best != null and holding != null and candidates.has(holding):
			var settled := delta <= 0.0 or _shadow_held >= SHADOW_HOLD
			if not settled or best.light_energy <= holding.light_energy * SHADOW_SWITCH_RATIO: best = holding
	_shadow_held += delta
	if best != (_shadow_lamp if _shadow_next == null else _shadow_next): _shadow_held = 0.0
	var step := 1.0 if delta <= 0.0 else delta / SHADOW_FADE
	if best != _shadow_lamp and _shadow_lamp != null and _shadow_lamp.visible and _shadow_lamp.shadow_enabled:
		# Fade the current shadow out first; the next one waits.
		_shadow_next = best
		_shadow_lamp.shadow_opacity = maxf(_shadow_lamp.shadow_opacity - step, 0.0)
		if _shadow_lamp.shadow_opacity <= 0.0:
			_shadow_lamp.shadow_enabled = false
			_shadow_lamp = best
			_shadow_next = null
			if best != null:
				best.shadow_opacity = 0.0 if delta > 0.0 else 1.0
				best.shadow_enabled = true
	else:
		if best != _shadow_lamp and best != null:
			best.shadow_opacity = 0.0 if delta > 0.0 else 1.0
		_shadow_lamp = best
		_shadow_next = null
		if best != null:
			best.shadow_enabled = true
			best.shadow_opacity = minf(best.shadow_opacity + step, 1.0)
	for lamp: OmniLight3D in _pool:
		if lamp != _shadow_lamp and lamp.shadow_enabled: lamp.shadow_enabled = false

static func _rank(source: Array) -> int:
	if _attached(source): return 1
	return 2 if source.size() > 3 and source[3] else 0

static func _steady(source: Array) -> bool:
	return (source.size() > 3 and source[3]) or _attached(source)

static func _attached(source: Array) -> bool:
	return source.size() > 4 and int(source[4]) > 0

## Sources within MERGE of a brighter one joined to it (colours summed, the
## centre weighted by brightness, the wider extent kept), brightest first.
## A transient spell never merges into a standing fire: they have different
## priorities and shadow policies even when their patches overlap.
## A source may carry further entries (such as whether it is one of the
## arena's own standing lights); the joined source keeps the brightest one's.
## `spell_merge` is the distance a spell's own patches join at (path tracing
## keeps a wall of fire as many lights along its length, so a figure beside it
## stands in front of one and throws its shadow).
static func merged(sources: Array, spell_merge := MERGE) -> Array:
	var ordered := sources.duplicate()
	ordered.sort_custom(func(a: Array, b: Array) -> bool: return a[2].length_squared() > b[2].length_squared())
	var result := []
	var weights := PackedFloat32Array()
	for source: Array in ordered:
		var colour: Vector3 = source[2]
		var weight := colour.x + colour.y + colour.z
		if weight <= 0.0 or maxf(colour.x, maxf(colour.y, colour.z)) <= 0.001: continue
		var joined := false
		var reach := MERGE if _steady(source) else spell_merge
		for i in result.size():
			var lamp: Array = result[i]
			if lamp[0].distance_squared_to(source[0]) > reach * reach: continue
			# A figure's lights stand where they are (its weapon, its wings).
			if _attached(lamp) or _attached(source) or _steady(lamp) != _steady(source): continue
			lamp[0] = (lamp[0] * weights[i] + source[0] * weight) / (weights[i] + weight)
			lamp[1] = maxf(lamp[1], source[1])
			lamp[2] += colour
			weights[i] += weight
			joined = true
			break
		if not joined:
			var lamp := [source[0], source[1], colour]
			lamp.append_array(source.slice(3))
			result.append(lamp)
			weights.append(weight)
	result.sort_custom(func(a: Array, b: Array) -> bool: return a[2].length_squared() > b[2].length_squared())
	return result

## Lamps lit now, for checks.
func lit() -> int:
	var count := 0
	for lamp: OmniLight3D in _pool:
		if lamp.visible: count += 1
	return count
