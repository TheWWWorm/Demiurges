class_name ELContactShading
extends RefCounted
## Optional short-range ambient occlusion for the raster Forward+ picture.
## This adds a little shade where lit figures and scenery meet; it never
## substitutes for the sun's shadow or changes authored light colours.
## Unlit map materials do not receive it. Traced lighting already supplies
## occlusion, so its environment marker always takes priority.

const TRACED := &"traced_light"
const RADIUS := 0.55
const INTENSITY := 1.3
const POWER := 1.35
const DETAIL := 0.25

static var enabled := false

static func available() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus" and not OS.has_feature("mobile") and not OS.has_feature("web")

## Every caller supplies its own environment. No renderer-wide quality or
## lighting values are changed, and disabling the preference is immediate.
static func sync(environment: Environment) -> bool:
	if environment == null: return false
	var on := enabled and available() and not environment.has_meta(TRACED)
	environment.ssao_enabled = on
	if on:
		environment.ssao_radius = RADIUS
		environment.ssao_intensity = INTENSITY
		environment.ssao_power = POWER
		environment.ssao_detail = DETAIL
		environment.ssao_horizon = 0.06
		environment.ssao_sharpness = 0.9
		# Restrict the effect to ambient illumination. Direct sunlight and
		# spell lamps must retain their authored strength and colour.
		environment.ssao_light_affect = 0.0
		environment.ssao_ao_channel_affect = 0.0
	return on
