class_name ELPathTraceShaders
extends RefCounted
## GLSL sources of the experimental path-traced battle lighting
## (ELPathTracing). They are compiled when the effect starts, so they need no
## import step and use the running device's ray-query support.

## The frame block, shared by the ray and filter programs.
const FRAME := """
#version 460
// A storage buffer rather than a uniform block: Godot 4.7 declares ray-stage
// descriptors with the wrong stage mask, which uniform blocks do not survive.
layout(set = 0, binding = 0, std430) readonly buffer Frame {
	mat4 inv_projection;    // device clip (y down, reversed 0..1 depth) to view
	mat4 camera;            // view to world
	mat4 previous_view_projection;
	vec4 camera_position;
	vec4 previous_camera_position;
	vec4 sun_direction;     // towards the sun; w = tan of the sun's angular radius
	vec4 sun_color;         // linear colour times energy; w = 1 while the sun shines
	vec4 ambient;           // linear ambient; w = scenery light limit
	uvec4 info;             // frame, width, height, flags
	uvec4 counts;           // diffuse lights, longest history, secondary lights, diffuse rays
	vec4 tuning;            // x = sky strength (1 the default; settings "sky_light")
} frame;

// Raster-equivalent sun term: Lambert without the 1/pi Godot removes from
// directional energy, with scenery capped at the light limit.
vec3 sun_term(float n_dot_l, bool scenery) {
	if (frame.sun_color.w < 0.5) return vec3(0.0);
	vec3 sun = frame.sun_color.rgb * max(n_dot_l, 0.0);
	if (scenery) sun = min(sun, max(vec3(frame.ambient.w) - frame.ambient.rgb, vec3(0.0)));
	return sun;
}
"""

## The traced scene snapshot, read by every ray stage.
const SCENE := FRAME + """
#extension GL_EXT_ray_tracing : require
layout(set = 0, binding = 1) uniform accelerationStructureEXT scene;
layout(set = 0, binding = 2, std430) readonly buffer Corners { float corners[]; };
layout(set = 0, binding = 3, std430) readonly buffer CornerUVs { vec2 corner_uvs[]; };
struct Slot {
	uvec4 geometry;   // first corner, albedo layer, flags, emission layer
	vec4 tint;        // linear RGB, alpha cutoff or soft emitter opacity
	vec4 emission;    // linear RGB, energy
	vec4 uv;          // UV scale XY and offset ZW
};
layout(set = 0, binding = 4, std430) readonly buffer Slots { Slot slots[]; };
layout(set = 0, binding = 5) uniform sampler2DArray albedo;
// Diffuse lights: place and soft radius, linear RGB and reach. Secondary
// lights follow them: place, display RGB and reach.
layout(set = 0, binding = 6, std430) readonly buffer Lights { vec4 lights[]; };
layout(set = 0, binding = 7, std430) readonly buffer CornerNormals { uint corner_normals[]; };

const uint SLOT_ALPHA = 1u;
const uint SLOT_SCENERY = 2u;
const uint SLOT_GROUND = 4u;
const uint SLOT_EMISSION = 8u;
const uint SLOT_EMISSION_MULTIPLY = 16u;
const uint SLOT_CLAMP_UV = 32u;
const uint SLOT_FULLBRIGHT = 64u;
const uint SLOT_SOFT_EMITTER = 128u;
const uint SLOT_SOFT_CUTOUT = 256u;
const uint SLOT_ARENA_FLOOR = 512u;
const uint SLOT_ARENA_SCENERY = 1024u;
const uint SLOT_UNLIT_SHADOWED = 8192u;
const uint SLOT_METAL = 16384u;
const uint SLOT_THIN = 32768u;
const uint RAY_SOLID = 1u;
const uint RAY_SOFT_EMITTER = 2u;
const uint NO_TEXTURE = 0xffffffffu;

struct Payload {
	vec3 normal;     // world space, facing the ray's origin
	float distance;
	vec2 uv;
	uint instance;
	uint found;
	uint alpha_seed;
	float opacity_sample;
	bool shadow_ray;
	bool include_secondary;
	vec3 secondary;
	vec2 bary;       // the hit stage's report, resolved by resolve_hit
	uint primitive;
	uint instance_id;
	mat4x3 to_world;
};

uint hash(uint x) {
	x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
	return x;
}

uint instance_slot(uint index) { return index & 0xffffu; }
float instance_tint(uint index) { return float(index >> 16u) / 255.0; }

vec3 corner(uint index) {
	return vec3(corners[index * 3u], corners[index * 3u + 1u], corners[index * 3u + 2u]);
}

vec2 surface_uv(uint slot, uint primitive, vec2 bary) {
	uint first = slots[slot].geometry.x + primitive * 3u;
	vec2 uv = corner_uvs[first] * (1.0 - bary.x - bary.y) + corner_uvs[first + 1u] * bary.x + corner_uvs[first + 2u] * bary.y;
	return uv * slots[slot].uv.xy + slots[slot].uv.zw;
}

vec4 sample_layer(uint layer, vec2 uv, float lod, uint flags) {
	if ((flags & SLOT_CLAMP_UV) != 0u) {
		vec2 edge = 0.5 / vec2(textureSize(albedo, int(lod)).xy);
		uv = clamp(uv, edge, 1.0 - edge);
	}
	return textureLod(albedo, vec3(uv, float(layer)), lod);
}

vec4 surface_albedo(Slot look, vec2 uv, float lod) {
	return look.geometry.y == NO_TEXTURE ? vec4(1.0) : sample_layer(look.geometry.y, uv, lod, look.geometry.z);
}

vec3 surface_emission(Slot look, vec2 uv, float lod) {
	if ((look.geometry.z & SLOT_EMISSION) == 0u) return vec3(0.0);
	vec3 tex = look.geometry.w == NO_TEXTURE ? vec3(0.0) : sample_layer(look.geometry.w, uv, lod, look.geometry.z).rgb;
	vec3 radiance = (look.geometry.z & SLOT_EMISSION_MULTIPLY) != 0u ? look.emission.rgb * tex : look.emission.rgb + tex;
	return radiance * look.emission.w;
}
"""

## The hit stage only reports which triangle was hit and where. Godot's ray
## pipeline leaves the scene's buffers reading as zeros there, so the ray
## generation stage resolves the surface (resolve_hit).
const CLOSEST_HIT := SCENE + """
layout(location = 0) rayPayloadInEXT Payload payload;
hitAttributeEXT vec2 bary;

void main() {
	payload.distance = gl_HitTEXT;
	payload.instance = uint(gl_InstanceCustomIndexEXT);
	payload.found = 1u;
	payload.bary = bary;
	payload.primitive = uint(gl_PrimitiveID);
	payload.instance_id = uint(gl_InstanceID);
	payload.to_world = gl_ObjectToWorldEXT;
}
"""

const MISS := SCENE + """
layout(location = 0) rayPayloadInEXT Payload payload;
void main() {
	payload.found = 0u;
}
"""

## Expands a slot's indexed vertices (and once, its UVs) into the
## unindexed triangle corners that the acceleration structures read.
const EXPAND := """
#version 450
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) readonly buffer Source { float source[]; };
layout(set = 0, binding = 1, std430) readonly buffer Indices { uint indices[]; };
layout(set = 0, binding = 2, std430) writeonly buffer Corners { float corners[]; };
layout(set = 0, binding = 3, std430) readonly buffer SourceUVs { vec2 source_uvs[]; };
layout(set = 0, binding = 4, std430) writeonly buffer CornerUVs { vec2 corner_uvs[]; };
layout(push_constant, std430) uniform Push {
	uint first_vertex;
	uint first_index;
	uint first_corner;
	uint count;     // corners; bit 31 also expands the UVs
} push;

void main() {
	uint k = gl_GlobalInvocationID.x;
	uint count = push.count & 0x7fffffffu;
	if (k >= count) return;
	uint v = push.first_vertex + indices[push.first_index + k];
	uint o = push.first_corner + k;
	corners[o * 3u] = source[v * 3u];
	corners[o * 3u + 1u] = source[v * 3u + 1u];
	corners[o * 3u + 2u] = source[v * 3u + 2u];
	if ((push.count & 0x80000000u) != 0u) corner_uvs[o] = source_uvs[v];
}
"""

## Per pixel: matches the raster surface to the traced scene, then traces a
## soft sun shadow and a diffuse path of up to BOUNCES hits (each lit by the
## sun and the effects; a ray that escapes sees the sky), and accumulates the
## result over frames.
const RAYGEN := SCENE + """
layout(location = 0) rayPayloadEXT Payload payload;
layout(set = 1, binding = 0) uniform sampler2D depth_buffer;
layout(set = 1, binding = 1) uniform sampler2D normal_roughness;
layout(set = 1, binding = 2, rgba16f) uniform readonly image2D previous_light;
layout(set = 1, binding = 3, rgba16f) uniform readonly image2D previous_guide;
layout(set = 1, binding = 4, rgba16f) uniform writeonly image2D light_out;   // rgb lighting, a history length
layout(set = 1, binding = 5, rgba16f) uniform writeonly image2D guide_out;   // world normal, signed distance (0 = not traced)
layout(set = 1, binding = 6, rgba16f) uniform writeonly image2D primary_out; // raster emission, ground flag
layout(set = 1, binding = 7, rgba16f) uniform writeonly image2D secondary_out;


// Diffuse rays per pixel path (settings "light_bounces", 1 to 4).
#define BOUNCES int(frame.counts.w)
const float SCENERY_HEADROOM = 1.1;
// The flat raster ambient becomes a sky: blue overhead and brightest low
// around the horizon, as hazy daylight is, so upright figures and walls
// facing away from the sun still see plenty of it; almost nothing from below. The maps light sky and sun
// about equally, which flattens everything; daylight is mostly sun. So the
// sky keeps SKY_SHARE of the ambient, and the sun takes over the rest on
// open, level ground, which stays as bright and keeps the colour the map gave
// it. Shade, walls and anything under cover lose that share and turn cool,
// lit by what they face. A clear sky still lights open shade at a fifth or so
// of full sun; a smaller share left figures with their backs to the sun
// nearly black.
const vec3 SKY_TINT = vec3(0.58, 0.86, 1.80);
// Scaled by the player's sky strength: less sky, deeper and cooler shade.
#define SKY_SHARE (0.28 * frame.tuning.x)
const float ZENITH = 1.0, HORIZON = 1.4, GROUND = 0.08;
const vec3 LUMINANCE = vec3(0.2126, 0.7152, 0.0722);

vec3 sky(vec3 direction) {
	if (direction.y <= 0.0) return frame.ambient.rgb * GROUND * SKY_SHARE;
	float h = sqrt(direction.y);
	return frame.ambient.rgb * SKY_SHARE * mix(HORIZON, ZENITH, h) * mix(vec3(1.0), SKY_TINT / dot(SKY_TINT, LUMINANCE), h);
}

// What the sky gives open, level ground: sky() over the cosine-weighted
// hemisphere (with h = sqrt(cos), E[h] = 4/5 and E[h^2] = 2/3).
vec3 sky_on_level() {
	vec3 tint = SKY_TINT / dot(SKY_TINT, LUMINANCE) - 1.0;
	vec3 mean = HORIZON + 0.8 * ((ZENITH - HORIZON) + HORIZON * tint) + (2.0 / 3.0) * (ZENITH - HORIZON) * tint;
	return frame.ambient.rgb * SKY_SHARE * mean;
}

// Arena scenery caps its raster sun (painted light is already in its
// textures), which would flatten the sun's share again. The traced sun keeps
// its full cosine falloff and is scaled so open, level ground receives what
// the raster gave it there: the capped sun plus the ambient the sky gave up.
// Its colour is what that ground needs besides the blue sky to come out in
// the raster's light colour: so the sun still reads warm against the cool
// shade, but the ground keeps the colour the map lights it with. A fixed
// warm tint on the sun (neutral map light on the ice and snow fields too)
// turned snow and ice cream-coloured.
vec3 sunlight(float n_dot_l, bool scenery) {
	if (frame.sun_color.w < 0.5) return vec3(0.0);
	float level = max(frame.sun_direction.y, 0.35);
	vec3 shown = sun_term(level, scenery);
	float bright = dot(shown, LUMINANCE) + (1.0 - SKY_SHARE) * dot(frame.ambient.rgb, LUMINANCE);
	vec3 colour = max(shown + frame.ambient.rgb - sky_on_level(), vec3(0.0));
	colour = dot(colour, LUMINANCE) > 1e-4 ? colour / dot(colour, LUMINANCE) : frame.sun_color.rgb / max(dot(frame.sun_color.rgb, LUMINANCE), 1e-4);
	return colour * bright * max(n_dot_l, 0.0) / level;
}

// The arena's vertex light at one corner of a hit triangle, from the
// secondary lights.
vec3 secondary_at(mat4x3 to_world, mat3 normal_matrix, uint normal_index, vec3 local_point, bool normal_aware) {
	vec3 point = to_world * vec4(local_point, 1.0);
	vec3 normal = vec3(0.0);
	if (normal_aware) {
		vec3 local_normal = uintBitsToFloat(uvec3(corner_normals[normal_index],
			corner_normals[normal_index + 1u], corner_normals[normal_index + 2u]));
		normal = normalize(normal_matrix * local_normal);
	}
	vec3 result = vec3(0.0);
	for (uint i = 0u; i < frame.counts.z; i++) {
		uint at = 2u * (frame.counts.x + i);
		vec3 position = lights[at].xyz;
		vec4 colour = lights[at + 1u];
		if (normal_aware && distance(position, to_world[3]) > colour.w + 10.0) continue;
		vec3 offset = position - point;
		float distance_squared = dot(offset, offset);
		float weight = max(1.0 - distance_squared / (colour.w * colour.w), 0.0);
		if (normal_aware) {
			weight *= distance_squared > 0.0 ? max(dot(normal, offset) * inversesqrt(distance_squared), 0.0) : 0.0;
		}
		result = max(result, colour.rgb * weight);
	}
	// The original packs this color per vertex before interpolating it.
	return roundEven(result * 255.0) / 255.0;
}

// Completes a hit from the hit stage's report: its texture coordinates, a
// soft emitter's opacity sample and, unless only coverage matters, the normal
// facing the ray and the arena's vertex light.
void resolve_hit(inout Payload hit, vec3 direction) {
	uint slot = instance_slot(hit.instance);
	uint flags = slots[slot].geometry.z;
	if (!hit.shadow_ray || (flags & SLOT_ALPHA) != 0u)
		hit.uv = surface_uv(slot, hit.primitive, hit.bary);
	if ((flags & (SLOT_SOFT_EMITTER | SLOT_SOFT_CUTOUT)) == SLOT_SOFT_EMITTER) {
		uint sample_id = hash(hit.alpha_seed ^ hash(hit.instance_id) ^ hash(hit.primitive));
		hit.opacity_sample = float(sample_id >> 8) / 16777216.0;
	}
	if (hit.shadow_ray) return;
	uint first = slots[slot].geometry.x + hit.primitive * 3u;
	vec3 a = corner(first), b = corner(first + 1u), c = corner(first + 2u);
	mat3 linear = mat3(hit.to_world);
	vec3 n = cross(linear * (b - a), linear * (c - a));
	n = length(n) > 0.0 ? normalize(n) : -direction;
	hit.normal = dot(n, direction) > 0.0 ? -n : n;
	if (hit.include_secondary) {
		hit.secondary = vec3(0.0);
		if ((flags & (SLOT_ARENA_FLOOR | SLOT_ARENA_SCENERY)) != 0u) {
			bool normal_aware = (flags & SLOT_ARENA_SCENERY) != 0u;
			mat3 normal_matrix = transpose(inverse(linear));
			uint normal_base = normal_aware ? corner_normals[slot] + hit.primitive * 9u : 0u;
			vec3 va = secondary_at(hit.to_world, normal_matrix, normal_base, a, normal_aware);
			vec3 vb = secondary_at(hit.to_world, normal_matrix, normal_base + 3u, b, normal_aware);
			vec3 vc = secondary_at(hit.to_world, normal_matrix, normal_base + 6u, c, normal_aware);
			hit.secondary = va * (1.0 - hit.bary.x - hit.bary.y) + vb * hit.bary.x + vc * hit.bary.y;
		}
	}
}

Payload closest(vec3 origin, vec3 direction, float max_distance, uint mask, uint alpha_seed, bool include_secondary, uint flags, bool shadow_ray) {
	payload.alpha_seed = alpha_seed;
	payload.include_secondary = include_secondary;
	payload.shadow_ray = shadow_ray;
	// Test coverage in raygen. On Vulkan, the any-hit path can accept whole
	// cutout triangles, leaving foliage cards and transparent parts in shadows.
	// Advance past each rejected hit to find the next surface on this ray.
	float start = 0.0;
	for (int i = 0; i < 32 && start < max_distance; i++) {
		traceRayEXT(scene, flags, mask, 0, 0, 0, origin, start, direction, max_distance, 0);
		if (payload.found == 0u) return payload;
		resolve_hit(payload, direction);
		Slot look = slots[instance_slot(payload.instance)];
		if ((look.geometry.z & SLOT_ALPHA) == 0u) return payload;
		float alpha = surface_albedo(look, payload.uv, 0.0).a;
		bool soft = (look.geometry.z & (SLOT_SOFT_EMITTER | SLOT_SOFT_CUTOUT)) == SLOT_SOFT_EMITTER;
		if (soft ? payload.opacity_sample < alpha * look.tint.a : alpha >= look.tint.a) return payload;
		start = payload.distance + 0.0001;
	}
	payload.found = 0u;
	return payload;
}

bool occluded(vec3 origin, vec3 direction, float max_distance) {
	return closest(origin, direction, max_distance, RAY_SOLID, 0u, false, gl_RayFlagsNoneEXT, true).found != 0u;
}

// How much of the sun reaches a point along `direction`. Feather and hair
// cards (SLOT_THIN) let light through by their coverage at a coarse mip, not
// by the cut at single texels: overlapping feather cards cast that cut on each
// other as fine, binary specks that changed with every frame of a wing's
// motion. Anything else blocks the sun outright, as `occluded` does.
const float CARD_SHADOW_LOD = 3.0;
// The share of the sun a thin card passes to its far side.
const float THIN_TRANSMISSION = 0.5;
float sun_transmission(vec3 origin, vec3 direction, float max_distance) {
	float light = 1.0;
	float start = 0.0;
	for (int i = 0; i < 32 && start < max_distance; i++) {
		payload.alpha_seed = 0u;
		payload.include_secondary = false;
		payload.shadow_ray = true;
		traceRayEXT(scene, gl_RayFlagsNoneEXT, RAY_SOLID, 0, 0, 0, origin, start, direction, max_distance, 0);
		if (payload.found == 0u) return light;
		resolve_hit(payload, direction);
		Slot look = slots[instance_slot(payload.instance)];
		uint flags = look.geometry.z;
		if ((flags & SLOT_ALPHA) == 0u) return 0.0;
		bool soft = (flags & (SLOT_SOFT_EMITTER | SLOT_SOFT_CUTOUT)) == SLOT_SOFT_EMITTER;
		if (soft || (flags & SLOT_THIN) == 0u) {
			float alpha = surface_albedo(look, payload.uv, 0.0).a;
			if (soft ? payload.opacity_sample < alpha * look.tint.a : alpha >= look.tint.a) return 0.0;
		} else {
			float coverage = surface_albedo(look, payload.uv, CARD_SHADOW_LOD).a;
			light *= 1.0 - smoothstep(look.tint.a - 0.25, look.tint.a + 0.25, coverage);
			if (light < 0.02) return 0.0;
		}
		start = payload.distance + 0.0001;
	}
	return light;
}

float random(inout uint state) {
	state = hash(state);
	return float(state >> 8) / 16777216.0;
}

void basis(vec3 n, out vec3 t, out vec3 b) {
	float s = n.z >= 0.0 ? 1.0 : -1.0;
	float a = -1.0 / (s + n.z);
	float c = n.x * n.y * a;
	t = vec3(1.0 + s * n.x * n.x * a, s * c, -s * n.x);
	b = vec3(c, s + n.y * n.y * a, -n.y);
}

// Point-light falloff as Godot's: a smooth window to the reach, over distance.
float light_falloff(float d, float reach, float radius) {
	float x = d / reach;
	x *= x;
	x = clamp(1.0 - x * x, 0.0, 1.0);
	return x * x / max(d, radius);
}

// Light from the effects (fire, glows, spell lights) at a point: one light
// chosen in proportion to what it would give here, then a ray towards a
// random point of it (when shadowed), weighted back to the whole sum.
vec3 effect_light(vec3 p, vec3 n, bool shadowed, inout uint state) {
	uint count = frame.counts.x;
	if (count == 0u) return vec3(0.0);
	float total = 0.0, chosen_weight = 0.0;
	uint chosen = 0u;
	for (uint i = 0u; i < count; i++) {
		vec4 place = lights[i * 2u], colour = lights[i * 2u + 1u];
		vec3 to = place.xyz - p;
		float d = length(to);
		float facing = dot(n, to) / max(d, 1e-4);
		float w = dot(colour.rgb, vec3(0.3, 0.6, 0.1)) * light_falloff(d, colour.w, place.w) * max(facing + place.w / max(d, place.w), 0.0);
		if (w <= 0.0) continue;
		total += w;
		if (random(state) * total < w) { chosen = i; chosen_weight = w; }
	}
	if (total <= 0.0) return vec3(0.0);
	vec4 place = lights[chosen * 2u], colour = lights[chosen * 2u + 1u];
	vec3 jitter = vec3(random(state), random(state), random(state)) * 2.0 - 1.0;
	vec3 target = place.xyz + jitter * place.w * 0.7;
	vec3 to = target - p;
	float d = length(to);
	vec3 direction = to / max(d, 1e-4);
	float n_dot_l = dot(n, direction);
	if (n_dot_l <= 0.0) return vec3(0.0);
	if (shadowed && occluded(p, direction, max(d - place.w, 0.01))) return vec3(0.0);
	return colour.rgb * light_falloff(d, colour.w, place.w) * n_dot_l * total / chosen_weight;
}

// Unlit map scenery keeps its authored colour in the sun. Where the traced
// sun is blocked, it darkens by as much as the sky alone lights level ground
// compared with sun and sky, so a plant's shadow also falls on the plant.
float unlit_shadow(vec3 point, float lift, inout uint state) {
	if (frame.sun_color.w < 0.5) return 1.0;
	vec3 sun = frame.sun_direction.xyz;
	vec3 t, b;
	basis(sun, t, b);
	float r = sqrt(random(state)) * frame.sun_direction.w, phi = 6.2831853 * random(state);
	vec3 towards = normalize(sun + (t * cos(phi) + b * sin(phi)) * r);
	if (!occluded(point + towards * lift, towards, 200.0)) return 1.0;
	float shade = dot(frame.ambient.rgb, LUMINANCE) * SKY_SHARE;
	float open = dot(sunlight(max(sun.y, 0.0), false), LUMINANCE) + shade;
	return clamp(shade / max(open, 1e-4), 0.0, 1.0);
}

// Metal (ELFigure.metal_material): how metallic its grey and gold texels
// are, its GGX width (roughness 0.4, squared twice) and the metallic share
// the raster already darkened its diffuse colour by (ELFigure.METAL_METALLIC).
const float METALNESS = 0.85;
const float METAL_A2 = 0.0256;
const float RASTER_METALLIC = 0.6;

// Where a texel is painted as metal: low saturation at a mid to high value,
// or a bright gold (as ELFigure._painted_metal judges it).
float metal_mask(vec3 c) {
	float high = max(c.r, max(c.g, c.b));
	float low = min(c.r, min(c.g, c.b));
	float saturation = high <= 0.0 ? 0.0 : (high - low) / high;
	float grey = smoothstep(0.38, 0.18, saturation) * smoothstep(0.15, 0.35, high);
	float hue = 0.0;
	if (high > low) {
		float d = high - low;
		if (high == c.r) hue = mod((c.g - c.b) / d, 6.0);
		else if (high == c.g) hue = (c.b - c.r) / d + 2.0;
		else hue = (c.r - c.g) / d + 4.0;
		hue /= 6.0;
	}
	float gold = smoothstep(0.45, 0.65, high) * (1.0 - smoothstep(0.02, 0.06, abs(hue - 0.12))) * smoothstep(0.25, 0.4, saturation);
	return max(grey, gold);
}

// How metallic a metal surface's texel is: its mask (ELMetalMasks,
// in the emission layer's place), else judged from its colour.
float metal_texels(Slot look, vec2 uv) {
	if ((look.geometry.z & SLOT_EMISSION) == 0u && look.geometry.w != NO_TEXTURE)
		return sample_layer(look.geometry.w, uv, 0.0, look.geometry.z).r;
	return metal_mask(surface_albedo(look, uv, 0.0).rgb);
}

float ggx_d(float n_dot_h, float a2) {
	float d = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	return a2 / (3.14159265 * d * d);
}

float smith_g1(float n_dot_x, float a2) {
	return 2.0 * n_dot_x / (n_dot_x + sqrt(a2 + (1.0 - a2) * n_dot_x * n_dot_x));
}

// A GGX microfacet normal around n.
vec3 ggx_half(vec3 n, float a2, inout uint state) {
	float u = random(state), phi = 6.2831853 * random(state);
	float cos_t = sqrt((1.0 - u) / (1.0 + (a2 - 1.0) * u));
	float sin_t = sqrt(max(0.0, 1.0 - cos_t * cos_t));
	vec3 t, b;
	basis(n, t, b);
	return normalize(t * sin_t * cos(phi) + b * sin_t * sin(phi) + n * cos_t);
}

// Metal's glossy light: the sun's highlight and one reflection of the sky or
// the scene, each hit lit by the sun. The composite multiplies by the raster
// colour, which stands in for metal's albedo-tinted reflectance.
vec3 metal_shine(vec3 origin, vec3 normal, vec3 geometric_normal, vec3 view_direction, bool sun_visible, inout uint state) {
	vec3 v = -view_direction;
	float n_dot_v = max(dot(normal, v), 1e-3);
	vec3 sun = frame.sun_direction.xyz;
	vec3 shine = vec3(0.0);
	float n_dot_l = dot(normal, sun);
	if (sun_visible && n_dot_l > 0.0) {
		vec3 h = normalize(sun + v);
		shine += sunlight(1.0, false) * ggx_d(max(dot(normal, h), 0.0), METAL_A2) * smith_g1(n_dot_v, METAL_A2) * smith_g1(n_dot_l, METAL_A2) / (4.0 * n_dot_v);
	}
	vec3 h = ggx_half(normal, METAL_A2, state);
	vec3 r = reflect(view_direction, h);
	float n_dot_r = dot(normal, r);
	if (n_dot_r <= 0.0 || dot(geometric_normal, r) <= 0.0) return shine;
	float weight = min(smith_g1(n_dot_v, METAL_A2) * smith_g1(n_dot_r, METAL_A2) * max(dot(v, h), 1e-3) / (n_dot_v * max(dot(normal, h), 1e-3)), 2.0);
	Payload seen = closest(origin, r, 60.0, RAY_SOLID | RAY_SOFT_EMITTER, state, false, gl_RayFlagsNoneEXT, false);
	if (seen.found == 0u) return shine + sky(r) * weight;
	Slot look = slots[instance_slot(seen.instance)];
	vec3 colour = look.tint.rgb * surface_albedo(look, seen.uv, 2.0).rgb * instance_tint(seen.instance);
	if ((look.geometry.z & SLOT_FULLBRIGHT) != 0u) return shine + colour * weight;
	vec3 seen_normal = dot(seen.normal, r) > 0.0 ? -seen.normal : seen.normal;
	vec3 p = origin + r * seen.distance + seen_normal * 0.03;
	vec3 incoming = frame.ambient.rgb * SKY_SHARE * 0.6;
	float seen_n_dot_l = dot(seen_normal, sun);
	if (seen_n_dot_l > 0.0 && frame.sun_color.w > 0.5 && !occluded(p, sun, 200.0))
		incoming += sunlight(seen_n_dot_l, (look.geometry.z & SLOT_SCENERY) != 0u);
	return shine + (colour * incoming + surface_emission(look, seen.uv, 2.0)) * weight;
}

vec3 decode_normal(vec4 encoded) {
	return normalize(encoded.xyz * 2.0 - 1.0);
}

void main() {
	ivec2 pixel = ivec2(gl_LaunchIDEXT.xy);
	ivec2 size = ivec2(frame.info.yz);
	vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
	float depth = texelFetch(depth_buffer, pixel, 0).r;
	if (depth <= 0.0) {
		imageStore(light_out, pixel, vec4(0.0));
		imageStore(guide_out, pixel, vec4(0.0));
		return;
	}
	vec4 view = frame.inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (frame.camera * vec4(view.xyz, 1.0)).xyz;
	vec3 normal = normalize(mat3(frame.camera) * decode_normal(texelFetch(normal_roughness, pixel, 0)));
	vec3 eye = frame.camera_position.xyz;
	float distance_to_eye = length(world - eye);
	vec3 view_direction = (world - eye) / max(distance_to_eye, 1e-4);
	// Rasterization already resolved texture coverage and chose the visible
	// surface. Look up its material at that depth so a cutout in front of it
	// cannot leave an unlit silhouette around the model.
	// Feather and hair cards overlap closer than that depth tolerance: the
	// first card in it may be cut away right here (the raster saw through
	// it), so its normal and texture would light this pixel. Pass such cuts.
	float tolerance = max(0.005, 0.0008 * distance_to_eye);
	float window = max(distance_to_eye - tolerance, 0.0);
	Payload first;
	first.found = 0u;
	for (int i = 0; i < 8; i++) {
		payload.shadow_ray = false;
		payload.include_secondary = frame.counts.z > 0u;
		traceRayEXT(scene, gl_RayFlagsCullBackFacingTrianglesEXT, RAY_SOLID, 0, 0, 0,
			eye, window, view_direction, distance_to_eye + tolerance, 0);
		if (payload.found == 0u) {
			// All cut away at this texel's detail: the raster's filtered
			// coverage kept it, so the first card stands.
			payload = first;
			break;
		}
		resolve_hit(payload, view_direction);
		if (first.found == 0u) first = payload;
		Slot seen = slots[instance_slot(payload.instance)];
		if ((seen.geometry.z & (SLOT_ALPHA | SLOT_SOFT_EMITTER)) != SLOT_ALPHA || surface_albedo(seen, payload.uv, 0.0).a >= seen.tint.a) break;
		window = payload.distance + 0.0001;
		if (i == 7) payload = first;
	}
	Payload primary = payload;
	if ((frame.info.w & 4u) != 0u) {
		imageStore(light_out, pixel, vec4(float(primary.found), primary.found != 0u ? primary.distance / max(distance_to_eye, 0.001) * 0.5 : 0.0, distance_to_eye / 50.0, 1.0));
		imageStore(guide_out, pixel, vec4(0.0, 0.0, 1.0, 1.0));
		imageStore(primary_out, pixel, vec4(0.0));
		return;
	}
	if (primary.found == 0u) {
		imageStore(light_out, pixel, vec4(0.0));
		imageStore(guide_out, pixel, vec4(0.0));
		return;
	}
	Slot primary_look = slots[instance_slot(primary.instance)];
	// The raster material already shows its full authored texture colour.
	// Unlit map scenery only takes the traced sun's shadow on top of it.
	bool unlit = (primary_look.geometry.z & SLOT_FULLBRIGHT) != 0u;
	if (unlit && (primary_look.geometry.z & SLOT_UNLIT_SHADOWED) == 0u) {
		imageStore(light_out, pixel, vec4(0.0));
		imageStore(guide_out, pixel, vec4(0.0));
		return;
	}
	bool scenery = (primary_look.geometry.z & SLOT_SCENERY) != 0u;
	bool ground = (primary_look.geometry.z & SLOT_GROUND) != 0u || unlit;
	imageStore(primary_out, pixel, vec4(unlit ? vec3(0.0) : surface_emission(primary_look, primary.uv, 0.0), ground ? 1.0 : 0.0));
	if (frame.counts.z > 0u) imageStore(secondary_out, pixel, vec4(primary.secondary, 0.0));
	// A smoothed vertex normal can face away from the camera near a low-poly
	// silhouette while still pointing out of its triangle. Flipping it there
	// sends lighting rays into the model and draws a black rim.
	vec3 geometric_normal = primary.normal;
	if (dot(normal, geometric_normal) < 0.0) normal = -normal;
	uint state = hash(uint(pixel.x) * 1973u + uint(pixel.y) * 9277u + frame.info.x * 26699u);
	vec3 origin = eye + view_direction * primary.distance + geometric_normal * (0.02 + distance_to_eye * 0.001);

	vec3 lighting = vec3(0.0);
	vec3 effects = vec3(0.0);
	if (unlit) {
		lighting = vec3(unlit_shadow(eye + view_direction * primary.distance, 0.02 + distance_to_eye * 0.001, state));
	} else {
		// Sun: soft shadow through a cone of the sun's angular size.
		vec3 sun = frame.sun_direction.xyz;
		float n_dot_l = dot(normal, sun);
		bool sun_visible = false;
		// A feather or hair card lit from behind passes part of the sun through
		// (seen from there, its side away from the sun). Lit only from the
		// front, a flapping wing's cards turned from full sun to deep shade
		// each time they swung past edge-on to the sun.
		vec3 sun_origin = origin;
		float sun_share = 1.0;
		if (n_dot_l < 0.0 && (primary_look.geometry.z & SLOT_THIN) != 0u) {
			n_dot_l = -n_dot_l;
			sun_origin = origin - geometric_normal * 2.0 * (0.02 + distance_to_eye * 0.001);
			sun_share = THIN_TRANSMISSION;
		}
		if (n_dot_l > 0.0 && frame.sun_color.w > 0.5) {
			vec3 t, b;
			basis(sun, t, b);
			float r = sqrt(random(state)) * frame.sun_direction.w, phi = 6.2831853 * random(state);
			vec3 towards = normalize(sun + (t * cos(phi) + b * sin(phi)) * r);
			float sun_seen = sun_transmission(sun_origin, towards, 200.0) * sun_share;
			sun_visible = sun_seen > 0.5;
			lighting += sunlight(n_dot_l, scenery) * sun_seen;
		}

		effects = effect_light(origin, normal, true, state);

		// A cosine-weighted diffuse path. Each hit passes on its albedo's colour
		// and adds the sun and effect light reaching it; an escaping ray sees the
		// sky. Past the last hit, a share of the sky stands in for the rest.
		{
			vec3 throughput = vec3(1.0);
			vec3 p = origin, n = normal;
			for (int i = 0; i < BOUNCES; i++) {
				vec3 t, b;
				basis(n, t, b);
				float r = sqrt(random(state)), phi = 6.2831853 * random(state);
				vec3 direction = normalize(t * r * cos(phi) + b * r * sin(phi) + n * sqrt(max(0.0, 1.0 - r * r)));
				Payload bounce = closest(p, direction, 60.0, RAY_SOLID | RAY_SOFT_EMITTER, state, false, gl_RayFlagsNoneEXT, false);
				if (bounce.found == 0u) {
					lighting += throughput * sky(direction);
					break;
				}
				Slot hit_look = slots[instance_slot(bounce.instance)];
				vec3 reflected_colour = hit_look.tint.rgb * surface_albedo(hit_look, bounce.uv, 2.0).rgb * instance_tint(bounce.instance);
				if ((hit_look.geometry.z & SLOT_FULLBRIGHT) != 0u) {
					effects += throughput * reflected_colour;
					break;
				}
				effects += throughput * surface_emission(hit_look, bounce.uv, 2.0);
				throughput *= reflected_colour;
				bool hit_scenery = (hit_look.geometry.z & SLOT_SCENERY) != 0u;
				vec3 hit_normal = dot(bounce.normal, direction) > 0.0 ? -bounce.normal : bounce.normal;
				p = p + direction * bounce.distance + hit_normal * 0.03;
				n = hit_normal;
				vec3 incoming = vec3(0.0);
				float hit_n_dot_l = dot(n, sun);
				if (hit_n_dot_l > 0.0 && frame.sun_color.w > 0.5 && !occluded(p, sun, 200.0))
					incoming += sunlight(hit_n_dot_l, hit_scenery);
				incoming += effect_light(p, n, false, state);
				if (i == BOUNCES - 1) incoming += frame.ambient.rgb * SKY_SHARE * 0.6;
				lighting += throughput * incoming;
			}
		}
		if ((primary_look.geometry.z & SLOT_METAL) != 0u) {
			float raster_mask = metal_texels(primary_look, primary.uv);
			float metal = raster_mask * METALNESS;
			if (metal > 0.0) {
				vec3 shine = metal_shine(origin, normal, geometric_normal, view_direction, sun_visible, state);
				// The raster drew this texel's diffuse partly metallic, so darker:
				// undo that before the composite multiplies by its colour.
				lighting = mix(lighting, shine, metal) / max(1.0 - RASTER_METALLIC * raster_mask, 0.25);
			}
		}
	}
	// Painted arena scenery already carries its daylight: sun and sky may
	// pass the raster's limit only a little, or sunlit slopes wash out.
	// Effect light comes on top, uncapped.
	if (scenery) {
		float peak = max(max(lighting.r, lighting.g), lighting.b);
		lighting *= min(1.0, SCENERY_HEADROOM * frame.ambient.w / max(peak, 1e-4));
	}
	lighting += effects;

	// Temporal accumulation, reprojected through the previous camera and
	// rejected where the surface there differs (moved, uncovered).
	vec4 clip = frame.previous_view_projection * vec4(world, 1.0);
	float history = 0.0;
	vec3 previous = vec3(0.0);
	if (clip.w > 0.0 && (frame.info.w & 1u) == 0u) {
		vec2 at = (clip.xy / clip.w * 0.5 + 0.5) * vec2(size) - 0.5;
		ivec2 base = ivec2(floor(at));
		vec2 f = at - vec2(base);
		float expected = length(world - frame.previous_camera_position.xyz);
		float total = 0.0;
		vec4 sum = vec4(0.0);
		for (int i = 0; i < 4; i++) {
			ivec2 q = base + ivec2(i & 1, i >> 1);
			if (q.x < 0 || q.y < 0 || q.x >= size.x || q.y >= size.y) continue;
			vec4 guide = imageLoad(previous_guide, q);
			if (guide.w == 0.0 || (guide.w < 0.0) != scenery) continue;
			if (abs(abs(guide.w) - expected) > 0.03 * expected + 0.05 || dot(guide.xyz, normal) < 0.85) continue;
			float w = ((i & 1) == 1 ? f.x : 1.0 - f.x) * ((i >> 1) == 1 ? f.y : 1.0 - f.y);
			sum += imageLoad(previous_light, q) * w;
			total += w;
		}
		if (total > 0.05) {
			sum /= total;
			previous = sum.rgb;
			history = sum.a;
		}
	}
	history = min(history + 1.0, float(frame.counts.y));
	vec3 result = mix(previous, lighting, 1.0 / history);
	imageStore(light_out, pixel, vec4(result, history));
	imageStore(guide_out, pixel, vec4(normal, scenery ? -distance_to_eye : distance_to_eye));
}
"""

## Edge-aware a-trous smoothing of the lighting; the last pass relights the
## raster colour: reflected colour * traced / raster lighting, plus emission.
const FILTER := FRAME + """
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 1, binding = 0, rgba16f) uniform readonly image2D source;
layout(set = 1, binding = 1, rgba16f) uniform readonly image2D guide;
layout(set = 1, binding = 2, rgba16f) uniform writeonly image2D target;
layout(set = 1, binding = 3, rgba16f) uniform image2D color;
layout(set = 1, binding = 4, rgba16f) uniform readonly image2D primary_surface;
layout(set = 1, binding = 5, rgba16f) uniform readonly image2D secondary_light;
layout(push_constant, std430) uniform Push {
	int step;
	int last;
	int pad0;
	int pad1;
} push;

#ifdef RAY_RECONSTRUCTION
// Compiled only for DLSS Ray Reconstruction (ELPathTracing adds the define):
// one composing pass of the unsmoothed light, which also writes the guides.
// The composed colour is diffuse albedo times light plus emission, so the
// raster colour before relighting is the albedo guide. All traced light is
// treated as diffuse: no specular albedo and no specular hit distance.
layout(set = 1, binding = 6, rgba16f) uniform writeonly image2D rr_diffuse_albedo;
layout(set = 1, binding = 7, rgba16f) uniform writeonly image2D rr_specular_albedo;
layout(set = 1, binding = 8, rgba16f) uniform writeonly image2D rr_normal_roughness;
layout(set = 1, binding = 9, r16f) uniform writeonly image2D rr_hit_distance;
layout(set = 1, binding = 10) uniform sampler2D rr_depth;
layout(set = 1, binding = 11) uniform sampler2D rr_raster_normal;

// `normal` is the traced world normal, or zero to use the raster's.
void store_guides(ivec2 pixel, vec3 albedo, vec3 normal) {
	float roughness = 1.0;
	if (texelFetch(rr_depth, pixel, 0).r <= 0.0) {
		// The sky is drawn after this pass.
		albedo = vec3(1.0);
		normal = vec3(0.0);
	} else {
		vec4 raster = texelFetch(rr_raster_normal, pixel, 0);
		roughness = clamp(min(raster.a, 1.0 - raster.a) * (255.0 / 127.0), 0.0, 1.0);
		if (dot(normal, normal) == 0.0) normal = normalize(mat3(frame.camera) * normalize(raster.xyz * 2.0 - 1.0));
	}
	imageStore(rr_diffuse_albedo, pixel, vec4(clamp(albedo, vec3(0.0), vec3(1.0)), 1.0));
	imageStore(rr_specular_albedo, pixel, vec4(0.0));
	imageStore(rr_normal_roughness, pixel, vec4(normal, roughness));
	imageStore(rr_hit_distance, pixel, vec4(0.0));
}
#endif

const float KERNEL[3] = float[](3.0 / 8.0, 1.0 / 4.0, 1.0 / 16.0);

vec3 to_display(vec3 linear) {
	return mix(1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055, 12.92 * linear, lessThanEqual(linear, vec3(0.0031308)));
}

vec3 to_linear(vec3 display) {
	return mix(pow((display + 0.055) / 1.055, vec3(2.4)), display / 12.92, lessThanEqual(display, vec3(0.04045)));
}

// Traced light against the raster's, through a tone curve as eyes or a
// camera take daylight: shade (a ratio below 1) is lifted and full daylight
// and anything brighter, such as spell light, pass unchanged. The curve meets
// the identity smoothly at 1, so nothing ends brighter than in the sun.
// It eases off with a weaker sky, so a player asking for deep shade gets it.
#define SHADE_LIFT (1.5 * min(frame.tuning.x, 1.0))
vec3 exposed(vec3 ratio) {
	float q = dot(ratio, vec3(0.2126, 0.7152, 0.0722));
	if (q <= 0.0 || q >= 1.0) return ratio;
	return ratio * (1.0 + SHADE_LIFT * (1.0 - q) * (1.0 - q));
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(frame.info.yz);
	if (pixel.x >= size.x || pixel.y >= size.y) return;
	vec4 g = imageLoad(guide, pixel);
	vec4 center = imageLoad(source, pixel);
	if (g.w == 0.0) {
		if (push.last == 0) imageStore(target, pixel, center);
		else if ((frame.info.w & 2u) != 0u) imageStore(color, pixel, vec4(0.02, 0.02, 0.03, 1.0));  // untraced
#ifdef RAY_RECONSTRUCTION
		// Untraced (unlit scenery): its raster colour is all albedo.
		else store_guides(pixel, imageLoad(color, pixel).rgb, vec3(0.0));
#endif
		return;
	}
#ifdef RAY_RECONSTRUCTION
	// The reconstruction removes the noise: the light stays as traced.
	vec3 filtered = center.rgb;
#else
	float d = abs(g.w);
	float luminance = dot(center.rgb, vec3(0.299, 0.587, 0.114));
	float sigma = 0.3 * (luminance + 0.05) * mix(4.0, 1.0, clamp(center.a / 16.0, 0.0, 1.0));
	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			ivec2 q = pixel + ivec2(x, y) * push.step;
			if (q.x < 0 || q.y < 0 || q.x >= size.x || q.y >= size.y) continue;
			vec4 gq = imageLoad(guide, q);
			if (gq.w == 0.0) continue;
			vec3 s = imageLoad(source, q).rgb;
			float w = KERNEL[abs(x)] * KERNEL[abs(y)];
			w *= pow(max(dot(gq.xyz, g.xyz), 0.0), 32.0);
			w *= exp(-abs(abs(gq.w) - d) / (0.01 * d * float(push.step) + 0.02));
			w *= exp(-abs(dot(s, vec3(0.299, 0.587, 0.114)) - luminance) / sigma);
			sum += s * w;
			total += w;
		}
	}
	vec3 filtered = total > 0.0 ? sum / total : center.rgb;
#endif
	if (push.last == 0) {
		imageStore(target, pixel, vec4(filtered, center.a));
		return;
	}
	bool scenery = g.w < 0.0;
	vec4 c = imageLoad(color, pixel);
	if ((frame.info.w & 2u) != 0u) c.rgb = filtered * 0.5;  // lighting view
	else {
		vec4 surface = imageLoad(primary_surface, pixel);
		// The adventure ground already draws at full texture colour when the
		// raster shadow map is off. Keep its water, fog and detail in that colour.
		vec3 raster = surface.a > 0.5 ? vec3(1.0) : frame.ambient.rgb + sun_term(dot(g.xyz, frame.sun_direction.xyz), scenery);
		vec3 emission = min(surface.rgb, c.rgb);
#ifdef RAY_RECONSTRUCTION
		store_guides(pixel, c.rgb - emission, g.xyz);
#endif
		c.rgb = (c.rgb - emission) * exposed(filtered / max(raster, vec3(0.02))) + emission;
		if (frame.counts.z > 0u && (frame.info.w & 4u) == 0u) {
			vec3 secondary = imageLoad(secondary_light, pixel).rgb;
			if (any(greaterThan(secondary, vec3(0.0)))) {
				// Native D3D adds the encoded vertex color after texturing.
				vec3 base = clamp(c.rgb, 0.0, 1.0);
				c.rgb += to_linear(min(to_display(base) + secondary, vec3(1.0))) - base;
			}
		}
	}
	imageStore(color, pixel, c);
}
"""
