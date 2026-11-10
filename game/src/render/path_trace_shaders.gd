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
	uvec4 counts;           // diffuse lights, longest history, secondary lights
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
	bool include_secondary;
	vec3 secondary;
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

const ANY_HIT := SCENE + """
layout(location = 0) rayPayloadInEXT Payload payload;
hitAttributeEXT vec2 bary;
void main() {
	uint slot = instance_slot(uint(gl_InstanceCustomIndexEXT));
	Slot look = slots[slot];
	float alpha = surface_albedo(look, surface_uv(slot, uint(gl_PrimitiveID), bary), 0.0).a;
	if ((look.geometry.z & (SLOT_SOFT_EMITTER | SLOT_SOFT_CUTOUT)) == SLOT_SOFT_EMITTER) {
		// Accept the surface with its coverage probability. A rejected sample
		// continues on to the next surface instead of blocking the bounce.
		uint sample_id = hash(payload.alpha_seed ^ hash(uint(gl_InstanceID)) ^ hash(uint(gl_PrimitiveID)));
		if (float(sample_id >> 8) / 16777216.0 >= alpha * look.tint.a) ignoreIntersectionEXT;
	} else if ((look.geometry.z & SLOT_ALPHA) != 0u && alpha < look.tint.a) {
		ignoreIntersectionEXT;
	}
}
"""

const CLOSEST_HIT := SCENE + """
layout(location = 0) rayPayloadInEXT Payload payload;
hitAttributeEXT vec2 bary;

vec3 secondary_at(uint normal_index, vec3 local_point, bool normal_aware) {
	vec3 point = gl_ObjectToWorldEXT * vec4(local_point, 1.0);
	vec3 normal = vec3(0.0);
	if (normal_aware) {
		vec3 local_normal = uintBitsToFloat(uvec3(corner_normals[normal_index],
			corner_normals[normal_index + 1u], corner_normals[normal_index + 2u]));
		normal = normalize(transpose(mat3(gl_WorldToObjectEXT)) * local_normal);
	}
	vec3 result = vec3(0.0);
	for (uint i = 0u; i < frame.counts.z; i++) {
		uint at = 2u * (frame.counts.x + i);
		vec3 position = lights[at].xyz;
		vec4 colour = lights[at + 1u];
		if (normal_aware && distance(position, gl_ObjectToWorldEXT[3]) > colour.w + 10.0) continue;
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

void main() {
	uint index = uint(gl_InstanceCustomIndexEXT);
	uint slot = instance_slot(index);
	uint first = slots[slot].geometry.x + uint(gl_PrimitiveID) * 3u;
	vec3 a = corner(first), b = corner(first + 1u), c = corner(first + 2u);
	vec3 n = cross(mat3(gl_ObjectToWorldEXT) * (b - a), mat3(gl_ObjectToWorldEXT) * (c - a));
	n = length(n) > 0.0 ? normalize(n) : -gl_WorldRayDirectionEXT;
	payload.normal = dot(n, gl_WorldRayDirectionEXT) > 0.0 ? -n : n;
	payload.distance = gl_HitTEXT;
	payload.uv = surface_uv(slot, uint(gl_PrimitiveID), bary);
	payload.instance = index;
	payload.found = 1u;
	if (payload.include_secondary) {
		payload.secondary = vec3(0.0);
		uint flags = slots[slot].geometry.z;
		if ((flags & (SLOT_ARENA_FLOOR | SLOT_ARENA_SCENERY)) != 0u) {
			bool normal_aware = (flags & SLOT_ARENA_SCENERY) != 0u;
			uint normal_base = normal_aware ? corner_normals[slot] + uint(gl_PrimitiveID) * 9u : 0u;
			vec3 va = secondary_at(normal_base, a, normal_aware);
			vec3 vb = secondary_at(normal_base + 3u, b, normal_aware);
			vec3 vc = secondary_at(normal_base + 6u, c, normal_aware);
			payload.secondary = va * (1.0 - bary.x - bary.y) + vb * bary.x + vc * bary.y;
		}
	}
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


const int BOUNCES = 2;
const float SCENERY_HEADROOM = 1.1;
// The flat raster ambient becomes a sky: blue and bright overhead, dimmer
// at the horizon, almost nothing from below. The maps light sky and sun
// about equally, which flattens everything; daylight is mostly sun. So the
// sky keeps SKY_SHARE of the ambient, and the warm sun takes over the rest
// on open, level ground, which stays as bright as before. Shade, walls and
// anything under cover lose that share and turn cool, lit by what they face.
const vec3 SKY_TINT = vec3(0.58, 0.86, 1.80);
const vec3 SUN_TINT = vec3(1.30, 1.00, 0.60);
const float SKY_SHARE = 0.28;
const float ZENITH = 1.11, HORIZON = 0.55, GROUND = 0.08;
const vec3 LUMINANCE = vec3(0.2126, 0.7152, 0.0722);

vec3 sky(vec3 direction) {
	if (direction.y <= 0.0) return frame.ambient.rgb * GROUND * SKY_SHARE;
	float h = sqrt(direction.y);
	return frame.ambient.rgb * SKY_SHARE * mix(HORIZON, ZENITH, h) * mix(vec3(1.0), SKY_TINT / dot(SKY_TINT, LUMINANCE), h);
}

// Arena scenery caps its raster sun (painted light is already in its
// textures), which would flatten the sun's share again. The traced sun keeps
// its full cosine falloff and is scaled so open, level ground receives what
// the raster gave it there: the capped sun plus the ambient the sky gave up.
vec3 sunlight(float n_dot_l, bool scenery) {
	if (frame.sun_color.w < 0.5) return vec3(0.0);
	float level = max(frame.sun_direction.y, 0.35);
	float raw = max(dot(frame.sun_color.rgb, LUMINANCE) * level, 1e-4);
	float shown = dot(sun_term(level, scenery), LUMINANCE);
	float scale = (shown + (1.0 - SKY_SHARE) * dot(frame.ambient.rgb, LUMINANCE)) / raw;
	return frame.sun_color.rgb * max(n_dot_l, 0.0) * scale * SUN_TINT / dot(SUN_TINT, LUMINANCE);
}

bool occluded(vec3 origin, vec3 direction, float max_distance) {
	payload.found = 1u;
	traceRayEXT(scene, gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT, RAY_SOLID, 0, 0, 0, origin, 0.0, direction, max_distance, 0);
	return payload.found != 0u;
}

Payload closest(vec3 origin, vec3 direction, float max_distance, uint mask, uint alpha_seed, bool include_secondary, uint flags) {
	payload.alpha_seed = alpha_seed;
	payload.include_secondary = include_secondary;
	traceRayEXT(scene, flags, mask, 0, 0, 0, origin, 0.0, direction, max_distance, 0);
	return payload;
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
	// Only surfaces of the traced scene are relit; effects, the painted
	// backdrop and anything else keep their raster light.
	// Match the raster face selection when a hidden wall lies in front of it.
	Payload primary = closest(eye, view_direction, distance_to_eye * 1.03 + 0.1, RAY_SOLID, 0u, frame.counts.z > 0u, gl_RayFlagsCullBackFacingTrianglesEXT);
	if ((frame.info.w & 4u) != 0u) {
		imageStore(light_out, pixel, vec4(float(primary.found), primary.found != 0u ? primary.distance / max(distance_to_eye, 0.001) * 0.5 : 0.0, distance_to_eye / 50.0, 1.0));
		imageStore(guide_out, pixel, vec4(0.0, 0.0, 1.0, 1.0));
		imageStore(primary_out, pixel, vec4(0.0));
		return;
	}
	if (primary.found == 0u || abs(primary.distance - distance_to_eye) > 0.02 * distance_to_eye + 0.05) {
		imageStore(light_out, pixel, vec4(0.0));
		imageStore(guide_out, pixel, vec4(0.0));
		return;
	}
	Slot primary_look = slots[instance_slot(primary.instance)];
	// The raster material already shows its full authored texture colour.
	if ((primary_look.geometry.z & SLOT_FULLBRIGHT) != 0u) {
		imageStore(light_out, pixel, vec4(0.0));
		imageStore(guide_out, pixel, vec4(0.0));
		return;
	}
	bool scenery = (primary_look.geometry.z & SLOT_SCENERY) != 0u;
	bool ground = (primary_look.geometry.z & SLOT_GROUND) != 0u;
	imageStore(primary_out, pixel, vec4(surface_emission(primary_look, primary.uv, 0.0), ground ? 1.0 : 0.0));
	if (frame.counts.z > 0u) imageStore(secondary_out, pixel, vec4(primary.secondary, 0.0));
	if (dot(normal, view_direction) > 0.0) normal = -normal;
	uint state = hash(uint(pixel.x) * 1973u + uint(pixel.y) * 9277u + frame.info.x * 26699u);
	vec3 origin = world + normal * (0.02 + distance_to_eye * 0.001);

	// Sun: soft shadow through a cone of the sun's angular size.
	vec3 lighting = vec3(0.0);
	vec3 sun = frame.sun_direction.xyz;
	float n_dot_l = dot(normal, sun);
	if (n_dot_l > 0.0 && frame.sun_color.w > 0.5) {
		vec3 t, b;
		basis(sun, t, b);
		float r = sqrt(random(state)) * frame.sun_direction.w, phi = 6.2831853 * random(state);
		vec3 towards = normalize(sun + (t * cos(phi) + b * sin(phi)) * r);
		if (!occluded(origin, towards, 200.0)) lighting += sunlight(n_dot_l, scenery);
	}

	vec3 effects = effect_light(origin, normal, true, state);

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
			Payload bounce = closest(p, direction, 60.0, RAY_SOLID | RAY_SOFT_EMITTER, state, false, gl_RayFlagsNoneEXT);
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

const float KERNEL[3] = float[](3.0 / 8.0, 1.0 / 4.0, 1.0 / 16.0);

vec3 to_display(vec3 linear) {
	return mix(1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055, 12.92 * linear, lessThanEqual(linear, vec3(0.0031308)));
}

vec3 to_linear(vec3 display) {
	return mix(pow((display + 0.055) / 1.055, vec3(2.4)), display / 12.92, lessThanEqual(display, vec3(0.04045)));
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
		return;
	}
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
		c.rgb = (c.rgb - emission) * filtered / max(raster, vec3(0.02)) + emission;
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
