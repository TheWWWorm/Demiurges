class_name ELGlowLights
extends Node3D
## Light from glowing effects in the ordinary picture (the "spell_light"
## preference, a remake addition after Cursed Lands' spell lighting): the
## brightest glowing patches of the particle systems and effect models now
## showing each get a pooled lamp, so a fireball, an aura or a wall of fire
## lights the figures and scenery near it. The effects' own authored point
## lights are untouched. No lamp casts shadows. Path tracing traces the same
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
const ENERGY_RISE := 0.2
## A lamp's reach: this, plus three times the patch's own extent. Two units
## are a metre, so a fire lights the ground a few metres around it.
const REACH := 8.0
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
const ATTACHED_SHARE := 0.25
const ATTACHED_REACH := 0.5
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

var _pool: Array[OmniLight3D] = []

## Shows `sources` ([[world centre, extent, summed linear colour, steady,
## attached], ...], as the effects' glow_sources give them), merged into
## lamps, brightest first up to LIMIT. A spell comes before the arena's own
## standing fires and the figures' own glow: their light is painted into the
## scenery already, or stands there all battle, while a spell's is the light
## the picture is missing, and they would otherwise take the whole budget in
## an arena ringed with braziers.
func show_sources(sources: Array, delta: float) -> void:
	sources = merged(sources)
	# Spells first, then the figures' own glow (light the scenery does not
	# have painted in), then the arena's standing fires.
	sources.sort_custom(func(a: Array, b: Array) -> bool:
		var a_rank := _rank(a)
		var b_rank := _rank(b)
		if a_rank != b_rank: return a_rank < b_rank
		return a[2].length_squared() > b[2].length_squared())
	# Places kept for figure lamps whose glow is gone for the moment.
	var held := 0
	for lamp: OmniLight3D in _pool:
		if lamp.visible and lamp.get_meta(&"figure", false): held += 1
	var incoming := sources.filter(func(source: Array) -> bool: return _attached(source)).size()
	var room := LIMIT - maxi(0, held - incoming)
	if sources.size() > room: sources.resize(maxi(room, 0))
	var blend := 1.0 - exp(-delta / SMOOTHING) if delta > 0.0 else 1.0
	var slow := 1.0 - exp(-delta / FIGURE_FADE) if delta > 0.0 else 1.0
	var free: Array[OmniLight3D] = _pool.duplicate()
	var shadows_left := SHADOW_LAMPS if shadows_available() else 0
	for source: Array in sources:
		var attached := _attached(source)
		var colour: Vector3 = source[2]
		var peak := maxf(colour.x, maxf(colour.y, colour.z))
		if peak <= 0.001: continue
		var centre: Vector3 = source[0]
		# A lamp already near this patch carries on, so light does not hop
		# between lamps as patches regroup.
		var lamp: OmniLight3D = null
		for candidate: OmniLight3D in free:
			if candidate.visible and (lamp == null or candidate.global_position.distance_squared_to(centre) < lamp.global_position.distance_squared_to(centre)):
				lamp = candidate
		if lamp != null and lamp.global_position.distance_squared_to(centre) > 4.0: lamp = null
		var fresh := lamp == null
		if fresh:
			for candidate: OmniLight3D in free:
				if not candidate.visible:
					lamp = candidate
					break
		if lamp == null:
			lamp = OmniLight3D.new()
			lamp.shadow_enabled = false
			lamp.light_specular = 0.0
			lamp.omni_attenuation = FALLOFF
			lamp.visible = false
			add_child(lamp)
			_pool.append(lamp)
		else:
			free.erase(lamp)
		# Only a spell's lamp casts: the arena's flickering fires traded the
		# one shadow between them frame by frame, so it jumped about the room.
		var wants_shadow := shadows_left > 0 and not _steady(source)
		if wants_shadow: shadows_left -= 1
		if lamp.shadow_enabled != wants_shadow: lamp.shadow_enabled = wants_shadow
		var tint := colour / peak
		var wanted := Color(tint.x, tint.y, tint.z).linear_to_srgb()
		var energy := ENERGY_LIMIT * (1.0 - exp(-peak * ENERGY_RISE))
		var reach := REACH + clampf(float(source[1]), 0.1, 3.0) * 3.0
		if attached:
			energy *= AURA_SHARE if int(source[4]) == 2 else ATTACHED_SHARE
			reach *= ATTACHED_REACH
		lamp.set_meta(&"figure", attached)
		if fresh:
			lamp.global_position = centre
			lamp.light_color = wanted
			lamp.light_energy = energy * blend
			lamp.omni_range = reach
			lamp.visible = true
		else:
			lamp.global_position = lamp.global_position.lerp(centre, blend)
			lamp.light_color = lamp.light_color.lerp(wanted, blend)
			lamp.light_energy = lerpf(lamp.light_energy, energy, blend)
			lamp.omni_range = lerpf(lamp.omni_range, reach, blend)
	# Lamps whose patch is gone fade out, and give up their place at once if
	# the lamps now lit would otherwise pass LIMIT: the Compatibility renderer
	# lights a surface with only so many, and a lamp on its way out is the
	# one to drop.
	var fading: Array[OmniLight3D] = []
	for lamp: OmniLight3D in free:
		if not lamp.visible: continue
		lamp.shadow_enabled = false
		var figure: bool = lamp.get_meta(&"figure", false)
		lamp.light_energy = lerpf(lamp.light_energy, 0.0, slow if figure else blend)
		if lamp.light_energy < 0.01:
			lamp.visible = false
			lamp.set_meta(&"figure", false)
		else: fading.append(lamp)
	var over := lit() - LIMIT
	if over > 0:
		# Figure lamps are the last to give up their place.
		fading.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
			var a_figure: bool = a.get_meta(&"figure", false)
			var b_figure: bool = b.get_meta(&"figure", false)
			if a_figure != b_figure: return b_figure
			return a.light_energy < b.light_energy)
		for i in mini(over, fading.size()):
			fading[i].light_energy = 0.0
			fading[i].visible = false
			fading[i].set_meta(&"figure", false)

static func _rank(source: Array) -> int:
	if _attached(source): return 1
	return 2 if source.size() > 3 and source[3] else 0

static func _steady(source: Array) -> bool:
	return (source.size() > 3 and source[3]) or _attached(source)

static func _attached(source: Array) -> bool:
	return source.size() > 4 and int(source[4]) > 0

## Sources within MERGE of a brighter one joined to it (colours summed, the
## centre weighted by brightness, the wider extent kept), brightest first.
## A source may carry further entries (such as whether it is one of the
## arena's own standing lights); the joined source keeps the brightest one's.
static func merged(sources: Array) -> Array:
	var ordered := sources.duplicate()
	ordered.sort_custom(func(a: Array, b: Array) -> bool: return a[2].length_squared() > b[2].length_squared())
	var result := []
	var weights := PackedFloat32Array()
	for source: Array in ordered:
		var colour: Vector3 = source[2]
		var weight := colour.x + colour.y + colour.z
		if weight <= 0.0: continue
		var joined := false
		for i in result.size():
			var lamp: Array = result[i]
			if lamp[0].distance_squared_to(source[0]) > MERGE * MERGE: continue
			# A figure's lights stand where they are (its weapon, its wings).
			if _attached(lamp) or _attached(source): continue
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
