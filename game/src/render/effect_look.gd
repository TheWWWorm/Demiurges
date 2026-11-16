class_name ELEffectLook
extends RefCounted
## Remake additions to how effects look in the ordinary (not path-traced)
## picture, after Cursed Lands. Each is a preference of its own and none is
## in the original games. Bloom and soft particles are off by default; spell
## light is on, because without it a wall of fire lights nothing at all
## outside path tracing, and ELHardwareCheck turns it off again on a device
## that cannot afford the extras:
## - "bloom": glowing (additive) particles draw brighter than white and the
##   scene blooms what passes white, so fire, lightning and auras shine while
##   daylit scenery stays as it was. Path tracing always uses this bloom.
## - "soft_particles": particles fade out where they meet the ground, walls
##   and figures (ELParticleFile.set_soft).
## - "spell_light": in battles, glowing effects light the figures and
##   scenery near them (ELGlowLights). Path tracing traces that light itself.
##   The adventure map has none: its ground and scenery are drawn unlit.

## What each preference is called, for a message naming one.
const LABELS := {"bloom": "Bloom", "soft_particles": "Soft particles", "spell_light": "Spell light"}

## "Bloom and Spell light" for the preferences `keys`, in the page's order.
static func names(keys: PackedStringArray) -> String:
	var listed := PackedStringArray()
	for key: String in LABELS:
		if key in keys: listed.append(LABELS[key])
	if listed.size() < 2: return "".join(listed)
	return "%s and %s" % [", ".join(listed.slice(0, listed.size() - 1)), listed[listed.size() - 1]]

## Marks an environment whose scene is path traced (ELPathTracing).
const TRACED := &"traced_light"
## Glowing particles draw this much brighter while the scene blooms, which
## is also how far above the bloom's threshold they sit: raising this is the
## way to have more of a flame bloom without lowering the threshold onto the
## scenery (ELCombatEffects.ARENA_HDR_LIMIT holds the arenas' own fires a
## little lower, so a brazier does not outshine a spell).
const EFFECT_HDR := 1.6
## What blooms, how strongly, and how far it carries.
##
## The threshold is what keeps bloom off the scenery, and it has to stay
## above white: the snow of the second game's Blue arena is brighter than
## most flames, and a threshold of 0.4 turned 91,000 of its pixels flat
## white, hazing the whole field. Held at 1.25 that arena does not bloom at
## all, whatever the strength, because nothing in it passes the line. So
## bloom is made to carry by the strength here and by how brightly the
## effects themselves draw (EFFECT_HDR), never by dropping the threshold.
## A strength of 0.3 put a peak of one value in 255 on a hero's weapon,
## which could not be seen at all.
##
## The levels are the engine's blur sizes, and weight in the wider ones
## carries the glow further. They do nothing in the Compatibility renderer,
## which blurs its glow its own way; there the threshold and the strength
## are the whole of it.
const BLOOM_THRESHOLD := 1.25
const BLOOM_INTENSITY := 2.0
const BLOOM_LEVELS := [0.0, 0.6, 0.5, 0.35, 0.2, 0.1, 0.0]

static var bloom := false
static var spell_light := true

## Takes the three preferences from the settings' values.
static func use(values: Dictionary) -> void:
	bloom = bool(values.get("bloom", false))
	spell_light = bool(values.get("spell_light", false))
	ELParticleFile.set_soft(bool(values.get("soft_particles", false)))
	# Blended smoke, mist and water cast soft shadows with the shadows
	# preference (ELParticleFile.SHADOW_SHEETS).
	ELParticleFile.set_shadows(bool(values.get("shadows", false)))
	# A session that ends unexpectedly says what it was drawing with, so only
	# those are suspected of bringing it down (ELCrashReport.effects_fallback).
	var in_use := PackedStringArray()
	for key: String in LABELS:
		if bool(values.get(key, false)): in_use.append(key)
	ELCrashReport.effects_in_use(in_use)
	# Every scene adds colours as light, except in the Compatibility
	# renderer, where only a scene with an effect such as bloom does (sync
	# answers for the scene at hand).
	ELParticleFile.set_linear_blend(not encoded_sun_pass(null))

## Whether a scene with this environment blooms now.
static func blooms(environment: Environment) -> bool:
	return bloom or (environment != null and environment.has_meta(TRACED))

## Whether glowing effects light this environment's scene with lamps of
## their own (not while it is path traced).
static func lights(environment: Environment) -> bool:
	return spell_light and not (environment != null and environment.has_meta(TRACED))

## Switches a scene's bloom to the preference (always on while it is path
## traced) and the glowing particles' brightness with it. `effects` are the
## scene's combat effects, if it has any. Returns whether it blooms.
static func sync(environment: Environment, effects: ELCombatEffects = null) -> bool:
	var on := blooms(environment)
	if environment != null:
		environment.glow_enabled = on
		if on:
			environment.glow_hdr_threshold = BLOOM_THRESHOLD
			environment.glow_intensity = BLOOM_INTENSITY
			environment.glow_bloom = 0.0
			environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
			for level in BLOOM_LEVELS.size(): environment.set_glow_level(level, BLOOM_LEVELS[level])
	# Glowing sprites keep their authored strength where colours add as light.
	ELParticleFile.set_linear_blend(not encoded_sun_pass(environment))
	var level := EFFECT_HDR if on else 1.0
	if is_instance_valid(effects): effects.set_glow(level)
	else: ELCombatEffects.set_glow_level(level)
	ELAdventureEffects.set_glow_level(level)
	return on

## The Compatibility renderer adds a shadowed sun in a pass of its own,
## after the colour is display (sRGB) encoded, and draws what is unshaded
## (the glowing sprites) in display terms too. Bloom does not change either:
## measured against reference patches, that renderer hands light() the same
## colour and attenuation as Forward+ and encodes a lit surface the same way
## whether or not the scene glows, and only an unshaded one differs. Taking
## bloom for a linear pass left the arenas a third too bright wherever the
## sun was strong, since the shader then sent an uncompensated sun into a
## pass that still compensates. The `environment` is no longer read; it is
## kept so the callers need not know that.
static func encoded_sun_pass(_environment: Environment) -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"
