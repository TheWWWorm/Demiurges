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

var _pool: Array[OmniLight3D] = []

## Shows `sources` ([[world centre, extent, summed linear colour, steady],
## ...], as the effects' glow_sources give them), merged into lamps,
## brightest first up to LIMIT. A spell comes before the arena's own standing
## fires: their light is painted into the scenery already, while a spell's is
## the light the picture is missing, and they would otherwise take the whole
## budget in an arena ringed with braziers.
func show_sources(sources: Array, delta: float) -> void:
	sources = merged(sources)
	sources.sort_custom(func(a: Array, b: Array) -> bool:
		var a_steady: bool = a.size() > 3 and a[3]
		var b_steady: bool = b.size() > 3 and b[3]
		if a_steady != b_steady: return b_steady
		return a[2].length_squared() > b[2].length_squared())
	if sources.size() > LIMIT: sources.resize(LIMIT)
	var blend := 1.0 - exp(-delta / SMOOTHING) if delta > 0.0 else 1.0
	var free: Array[OmniLight3D] = _pool.duplicate()
	var result_index := -1
	for source: Array in sources:
		result_index += 1
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
		var wants_shadow := result_index < SHADOW_LAMPS and shadows_available()
		if lamp.shadow_enabled != wants_shadow: lamp.shadow_enabled = wants_shadow
		var tint := colour / peak
		var wanted := Color(tint.x, tint.y, tint.z).linear_to_srgb()
		var energy := ENERGY_LIMIT * (1.0 - exp(-peak * ENERGY_RISE))
		var reach := REACH + clampf(float(source[1]), 0.1, 3.0) * 3.0
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
		lamp.light_energy = lerpf(lamp.light_energy, 0.0, blend)
		if lamp.light_energy < 0.01: lamp.visible = false
		else: fading.append(lamp)
	var over := lit() - LIMIT
	if over > 0:
		fading.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool: return a.light_energy < b.light_energy)
		for i in mini(over, fading.size()):
			fading[i].light_energy = 0.0
			fading[i].visible = false

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
