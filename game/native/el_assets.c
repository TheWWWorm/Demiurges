/*
 * Native decoders for the original games' assets (GDExtension, C).
 *
 * The same work as the GDScript readers in src/content/texture.gd and
 * src/render/figure.gd, compiled so that loading creatures, heroes and
 * battlefields takes a fraction of the time. Every function only reads its
 * arguments and returns new bytes, so worker threads may call them at once.
 * GDScript keeps its own readers and uses them wherever this library is
 * absent.
 *
 * Exposed as static methods of the class ELNativeAssets:
 *   decode_raw(data, width, height, offset) -> PackedByteArray
 *       a 16- or 32-bit masked texture level as RGBA8;
 *   decode_pnt3(data, size, width, height) -> PackedByteArray
 *       a run-length texture as RGBA8;
 *   figure(data) -> PackedByteArray
 *       a FIG mesh: u32 corner count, u32 index count, then the corners'
 *       positions, normals (float x, y, z each, in Godot axes), UVs
 *       (float u, v), source vertex indices (s32) and the triangle indices
 *       (s32); empty when the data is not a mesh;
 *   unpack_track(data) -> PackedByteArray
 *       a packed animation track in the plain layout, or empty;
 *   morph(base, indices, data, offset, frames, count) -> PackedByteArray
 *       every vertex-animation frame's corner positions (float x, y, z in
 *       Godot axes), then each frame's bounds (low x, y, z, high x, y, z).
 */
#include <math.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "include/gdextension_interface.h"

#if defined(_WIN32)
#define EL_EXPORT __declspec(dllexport)
#else
#define EL_EXPORT __attribute__((visibility("default")))
#endif

/* --------------------------------------------------------------- byte buffer */

typedef struct {
	uint8_t *data;
	int64_t size, capacity;
	int failed;
} Buffer;

static void put(Buffer *b, const void *bytes, int64_t n) {
	if (b->failed) return;
	if (b->size + n > b->capacity) {
		int64_t want = b->capacity ? b->capacity * 2 : 1024;
		while (want < b->size + n) want *= 2;
		uint8_t *grown = (uint8_t *)realloc(b->data, (size_t)want);
		if (!grown) {
			b->failed = 1;
			return;
		}
		b->data = grown;
		b->capacity = want;
	}
	memcpy(b->data + b->size, bytes, (size_t)n);
	b->size += n;
}

static void put_u32(Buffer *b, uint32_t v) { put(b, &v, 4); }
static void put_f32(Buffer *b, float v) { put(b, &v, 4); }

static uint32_t u32(const uint8_t *d, int64_t n, int64_t at) {
	if (at < 0 || at + 4 > n) return 0;
	uint32_t v;
	memcpy(&v, d + at, 4);
	return v;
}
static uint16_t u16(const uint8_t *d, int64_t n, int64_t at) {
	if (at < 0 || at + 2 > n) return 0;
	uint16_t v;
	memcpy(&v, d + at, 2);
	return v;
}
static int16_t s16(const uint8_t *d, int64_t n, int64_t at) { return (int16_t)u16(d, n, at); }
static float f32(const uint8_t *d, int64_t n, int64_t at) {
	if (at < 0 || at + 4 > n) return 0.0f;
	float v;
	memcpy(&v, d + at, 4);
	return v;
}

/* ------------------------------------------------------------------- textures */

/* One channel as the GDScript reader rounds it (alpha without bits is opaque). */
static int channel(int64_t px, int64_t mask, int64_t shift, int64_t bits, int alpha) {
	if (alpha && bits == 0) return 255;
	int64_t full = mask >> shift;
	if (!full) return 0;
	return (int)(0.5 + 255.0 * (double)((px & mask) >> shift) / (double)full);
}

static void decode_raw(const uint8_t *d, int64_t n, int64_t w, int64_t h, int64_t src, Buffer *out) {
	if (w <= 0 || h <= 0 || w * h > (1 << 26)) return;
	int64_t bpp = u32(d, n, 20) / 8;
	int64_t mask[4], shift[4], bits[4];
	for (int c = 0; c < 4; c++) { /* a, r, g, b */
		mask[c] = u32(d, n, 24 + c * 12);
		shift[c] = u32(d, n, 28 + c * 12);
		bits[c] = u32(d, n, 32 + c * 12);
	}
	uint32_t *pixels = (uint32_t *)calloc((size_t)(w * h), 4);
	if (!pixels) {
		out->failed = 1;
		return;
	}
	if (bpp == 2) {
		/* Every 16-bit value through a table. */
		uint32_t *table = (uint32_t *)malloc(65536 * 4);
		if (!table) {
			free(pixels);
			out->failed = 1;
			return;
		}
		for (int64_t px = 0; px < 65536; px++)
			table[px] = (uint32_t)channel(px, mask[1], shift[1], bits[1], 0) | ((uint32_t)channel(px, mask[2], shift[2], bits[2], 0) << 8)
				| ((uint32_t)channel(px, mask[3], shift[3], bits[3], 0) << 16) | ((uint32_t)channel(px, mask[0], shift[0], bits[0], 1) << 24);
		int64_t end = (n - src) / 2;
		if (end > w * h) end = w * h;
		for (int64_t i = 0; i < end; i++) pixels[i] = table[u16(d, n, src + i * 2)];
		free(table);
	} else {
		for (int64_t i = 0; i < w * h; i++) {
			int64_t px = u32(d, n, src);
			src += bpp;
			pixels[i] = (uint32_t)channel(px, mask[1], shift[1], bits[1], 0) | ((uint32_t)channel(px, mask[2], shift[2], bits[2], 0) << 8)
				| ((uint32_t)channel(px, mask[3], shift[3], bits[3], 0) << 16) | ((uint32_t)channel(px, mask[0], shift[0], bits[0], 1) << 24);
		}
	}
	put(out, pixels, w * h * 4);
	free(pixels);
}

#define DATA_OFFSET 76

static void decode_pnt3(const uint8_t *d, int64_t n, int64_t size, int64_t w, int64_t h, Buffer *out) {
	if (w <= 0 || h <= 0 || w * h > (1 << 26)) return;
	int64_t total = w * h * 4;
	uint8_t *o = (uint8_t *)calloc((size_t)total, 1);
	if (!o) {
		out->failed = 1;
		return;
	}
	int64_t dst = 0, src = DATA_OFFSET;
	int64_t end = DATA_OFFSET + size < n ? DATA_OFFSET + size : n;
	/* A dword with non-zero alpha is a BGRA pixel, otherwise a count of zero bytes. */
	while (src + 4 <= end && dst < total) {
		if (d[src + 3] != 0) {
			if (dst + 4 <= total) {
				o[dst] = d[src + 2];
				o[dst + 1] = d[src + 1];
				o[dst + 2] = d[src];
				o[dst + 3] = d[src + 3];
			}
			dst += 4;
		} else {
			uint32_t v = u32(d, n, src);
			dst += v != 0 ? v : 4;
		}
		src += 4;
	}
	put(out, o, total);
	free(o);
}

/* ---------------------------------------------------------------------- figures */

static void figure(const uint8_t *d, int64_t n, Buffer *out) {
	if (n < 80 || d[0] != 'F' || d[1] != 'I' || d[2] != 'G') return;
	int64_t variants = (int64_t)d[3] - 48;
	int64_t vb = u32(d, n, 4), nb = u32(d, n, 8), nt = u32(d, n, 12), ni = u32(d, n, 16), nc = u32(d, n, 20);
	int64_t vo = 40 + variants * 40;
	int64_t no = vo + vb * 12 * variants * 4;
	int64_t uo = no + nb * 16 * 4;
	int64_t io = uo + nt * 8;
	int64_t co = io + ni * 2;
	if (variants < 1 || variants > 8 || co + nc * 6 > n) return;
	int64_t tris = 0;
	for (int64_t i = 0; i + 2 < ni; i += 3) tris++;
	put_u32(out, (uint32_t)nc);
	put_u32(out, (uint32_t)(tris * 3));
	for (int64_t i = 0; i < nc; i++) {
		int64_t v = u16(d, n, co + i * 6);
		float p[3];
		for (int axis = 0; axis < 3; axis++) p[axis] = f32(d, n, vo + (((v >> 2) * 3 + axis) * variants * 4 + (v & 3)) * 4);
		put_f32(out, p[0]);
		put_f32(out, p[2]);
		put_f32(out, -p[1]);
	}
	for (int64_t i = 0; i < nc; i++) {
		int64_t m = u16(d, n, co + i * 6 + 2);
		int64_t at = no + ((m >> 2) * 16 + (m & 3)) * 4;
		float x = f32(d, n, at), y = f32(d, n, at + 16), z = f32(d, n, at + 32);
		/* Godot axes, then normalised as Vector3.normalized() does. */
		float g[3] = { x, z, -y };
		float lengthsq = g[0] * g[0] + g[1] * g[1] + g[2] * g[2];
		if (lengthsq == 0.0f) g[0] = g[1] = g[2] = 0.0f;
		else {
			float length = sqrtf(lengthsq);
			g[0] /= length;
			g[1] /= length;
			g[2] /= length;
		}
		put_f32(out, g[0]);
		put_f32(out, g[1]);
		put_f32(out, g[2]);
	}
	for (int64_t i = 0; i < nc; i++) {
		int64_t t = u16(d, n, co + i * 6 + 4);
		put_f32(out, f32(d, n, uo + t * 8));
		put_f32(out, f32(d, n, uo + t * 8 + 4));
	}
	for (int64_t i = 0; i < nc; i++) put_u32(out, u16(d, n, co + i * 6));
	for (int64_t i = 0; i + 2 < ni; i += 3) {
		put_u32(out, u16(d, n, io + i * 2));
		put_u32(out, u16(d, n, io + (i + 2) * 2));
		put_u32(out, u16(d, n, io + (i + 1) * 2));
	}
}

/* ----------------------------------------------------------------------- tracks */

/* The Steam release's packed tracks: 16-bit counts, thousandths in 16-bit
 * integers, key frames per vertex coordinate with straight lines between. */
static void unpack_track(const uint8_t *d, int64_t size, Buffer *out) {
	int64_t p = 0;
	if (p + 2 > size) goto bad;
	int64_t count = u16(d, size, p);
	p += 2;
	if (p + count * 16 > size) goto bad;
	put_u32(out, (uint32_t)count);
	put(out, d + p, count * 16);
	p += count * 16;
	if (p + 2 > size) goto bad;
	count = u16(d, size, p);
	p += 2;
	if (p + count * 6 > size) goto bad;
	put_u32(out, (uint32_t)count);
	for (int64_t i = 0; i < count * 3; i++) put_f32(out, (float)(s16(d, size, p + i * 2) / 1000.0));
	p += count * 6;
	if (p + 2 > size) goto bad;
	count = u16(d, size, p);
	p += 2;
	if (p + count * 12 > size) goto bad;
	put_u32(out, (uint32_t)count);
	put(out, d + p, count * 12);
	p += count * 12;
	if (p == size) {
		put_u32(out, 0);
		put_u32(out, 0);
		return;
	}
	if (p + 4 > size) goto bad;
	int64_t frames = u16(d, size, p), vertices = u16(d, size, p + 2);
	p += 4;
	put_u32(out, (uint32_t)frames);
	put_u32(out, (uint32_t)vertices);
	if (frames == 0 || vertices == 0) {
		if (p == size) return;
		goto bad;
	}
	{
		float *values = (float *)calloc((size_t)(frames * vertices * 3), sizeof(float));
		int64_t *keys = (int64_t *)malloc((size_t)frames * sizeof(int64_t));
		if (!values || !keys) {
			free(values);
			free(keys);
			goto bad;
		}
		int64_t mask_bytes = frames / 8 + 1;
		int ok = 1;
		for (int64_t vertex = 0; vertex < vertices && ok; vertex++) {
			if (p + 1 > size) { ok = 0; break; }
			uint8_t keyed = d[p];
			p += 1;
			if (keyed == 0) {
				if (p + frames * 6 > size) { ok = 0; break; }
				for (int64_t frame = 0; frame < frames; frame++)
					for (int axis = 0; axis < 3; axis++)
						values[(frame * vertices + vertex) * 3 + axis] = (float)(s16(d, size, p + (frame * 3 + axis) * 2) / 1000.0);
				p += frames * 6;
				continue;
			}
			for (int axis = 0; axis < 3; axis++) {
				if (p + mask_bytes + 2 > size) { ok = 0; break; }
				int64_t found = 0;
				for (int64_t frame = 0; frame < frames; frame++)
					if (d[p + frame / 8] & (1 << (frame % 8))) keys[found++] = frame;
				p += mask_bytes;
				count = u16(d, size, p);
				p += 2;
				if (count != found || count == 0 || p + count * 2 > size) { ok = 0; break; }
				int64_t key = 0;
				for (int64_t frame = 0; frame < frames; frame++) {
					while (key + 1 < count && keys[key + 1] <= frame) key++;
					double value = s16(d, size, p + key * 2) / 1000.0;
					if (frame > keys[key] && key + 1 < count) {
						double next = s16(d, size, p + (key + 1) * 2) / 1000.0;
						value += (next - value) * (double)(frame - keys[key]) / (double)(keys[key + 1] - keys[key]);
					}
					values[(frame * vertices + vertex) * 3 + axis] = (float)value;
				}
				p += count * 2;
			}
		}
		if (ok && p == size) put(out, values, frames * vertices * 3 * 4);
		else ok = 0;
		free(values);
		free(keys);
		if (ok) return;
	}
bad:
	out->size = 0;
	out->failed = 1;
}

/* ---------------------------------------------------------------- vertex frames */

static void morph(const uint8_t *base, int64_t base_n, const uint8_t *indices, int64_t index_n, const uint8_t *d, int64_t n,
		int64_t offset, int64_t frames, int64_t count, Buffer *out) {
	int64_t corners = base_n / 12;
	if (corners <= 0 || index_n / 4 < corners || frames <= 0 || count <= 0 || offset < 0 || offset + frames * count * 12 > n) return;
	float *bounds = (float *)malloc((size_t)(frames * 6) * sizeof(float));
	float *frame_out = (float *)malloc((size_t)(corners * 3 > 0 ? corners * 3 : 1) * sizeof(float));
	if (!bounds || !frame_out) {
		free(bounds);
		free(frame_out);
		out->failed = 1;
		return;
	}
	for (int64_t frame = 0; frame < frames; frame++) {
		float low[3] = { INFINITY, INFINITY, INFINITY }, high[3] = { -INFINITY, -INFINITY, -INFINITY };
		for (int64_t i = 0; i < corners; i++) {
			float v[3] = { f32(base, base_n, i * 12), f32(base, base_n, i * 12 + 4), f32(base, base_n, i * 12 + 8) };
			int64_t index = (int32_t)u32(indices, index_n, i * 4);
			if (index >= 0 && index < count) {
				int64_t q = offset + (frame * count + index) * 12;
				v[0] += f32(d, n, q);
				v[1] += f32(d, n, q + 8);
				v[2] += -f32(d, n, q + 4);
			}
			for (int a = 0; a < 3; a++) {
				frame_out[i * 3 + a] = v[a];
				if (v[a] < low[a]) low[a] = v[a];
				if (v[a] > high[a]) high[a] = v[a];
			}
		}
		put(out, frame_out, corners * 12);
		for (int a = 0; a < 3; a++) {
			bounds[frame * 6 + a] = low[a];
			bounds[frame * 6 + 3 + a] = high[a];
		}
	}
	put(out, bounds, frames * 24);
	free(bounds);
	free(frame_out);
}

/* ------------------------------------------------------------ Godot binding */

static GDExtensionInterfaceGetProcAddress get_proc;
static GDExtensionClassLibraryPtr library;

static GDExtensionInterfaceVariantGetType variant_get_type;
static GDExtensionInterfacePackedByteArrayOperatorIndex pba_index;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst pba_index_const;
static GDExtensionInterfaceStringNameNewWithLatin1Chars string_name_new;
static GDExtensionInterfaceStringNewWithLatin1Chars string_new;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionPtrConstructor pba_new;
static GDExtensionPtrDestructor pba_free, string_name_free, string_free;
static GDExtensionPtrBuiltInMethod pba_size, pba_resize;
static GDExtensionTypeFromVariantConstructorFunc int_from_variant, pba_from_variant;
static GDExtensionVariantFromTypeConstructorFunc variant_from_pba;

/* Opaque storage for builtin types (64-bit builds: PackedByteArray 16 bytes,
 * StringName and String 8). */
typedef struct { _Alignas(8) uint8_t data[16]; } PackedBytes;
typedef struct { _Alignas(8) uint8_t data[8]; } Name;
typedef struct { _Alignas(8) uint8_t data[8]; } Text;

static int64_t bytes_size(const PackedBytes *b) {
	int64_t n = 0;
	pba_size((GDExtensionTypePtr)b, NULL, &n, 0);
	return n;
}

static const uint8_t *bytes_of(const PackedBytes *b, int64_t *n) {
	*n = bytes_size(b);
	return *n > 0 ? pba_index_const((GDExtensionConstTypePtr)b, 0) : NULL;
}

/* Fills `result` (an uninitialised PackedByteArray) with the buffer. */
static void to_packed(Buffer *b, PackedBytes *result) {
	pba_new(result, NULL);
	if (b->failed || b->size <= 0) return;
	int64_t want = b->size, err = 0;
	const GDExtensionConstTypePtr args[1] = { &want };
	pba_resize(result, args, &err, 1);
	if (err == 0) memcpy(pba_index(result, 0), b->data, (size_t)b->size);
}

enum { M_RAW, M_PNT3, M_FIGURE, M_UNPACK, M_MORPH, M_COUNT };
#define B GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY
#define I GDEXTENSION_VARIANT_TYPE_INT
static const GDExtensionVariantType ARGS[M_COUNT][6] = {
	{ B, I, I, I }, { B, I, I, I }, { B }, { B }, { B, B, B, I, I, I },
};
static const int ARG_COUNT[M_COUNT] = { 4, 4, 1, 1, 6 };
static const char *NAMES[M_COUNT] = { "decode_raw", "decode_pnt3", "figure", "unpack_track", "morph" };
static const char *ARG_NAMES[M_COUNT][6] = {
	{ "data", "width", "height", "offset" }, { "data", "size", "width", "height" }, { "data" }, { "data" },
	{ "base", "indices", "data", "offset", "frames", "count" },
};

/* Runs method `m` on arguments already in their own types. */
static void run(int m, const void *const *args, PackedBytes *result) {
	Buffer b = { 0 };
	int64_t n0 = 0, n1 = 0, n2 = 0;
	const uint8_t *d0 = bytes_of((const PackedBytes *)args[0], &n0);
	switch (m) {
	case M_RAW:
		decode_raw(d0, n0, *(const int64_t *)args[1], *(const int64_t *)args[2], *(const int64_t *)args[3], &b);
		break;
	case M_PNT3:
		decode_pnt3(d0, n0, *(const int64_t *)args[1], *(const int64_t *)args[2], *(const int64_t *)args[3], &b);
		break;
	case M_FIGURE:
		figure(d0, n0, &b);
		break;
	case M_UNPACK:
		unpack_track(d0, n0, &b);
		break;
	case M_MORPH: {
		const uint8_t *d1 = bytes_of((const PackedBytes *)args[1], &n1);
		const uint8_t *d2 = bytes_of((const PackedBytes *)args[2], &n2);
		morph(d0, n0, d1, n1, d2, n2, *(const int64_t *)args[3], *(const int64_t *)args[4], *(const int64_t *)args[5], &b);
		break;
	}
	}
	to_packed(&b, result);
	free(b.data);
}

static void ptrcall(void *method, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	(void)instance;
	/* `ret` holds a constructed PackedByteArray: replace it. */
	pba_free(ret);
	run((int)(intptr_t)method, (const void *const *)args, (PackedBytes *)ret);
}

static void call(void *method, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt count, GDExtensionVariantPtr ret, GDExtensionCallError *error) {
	(void)instance;
	int m = (int)(intptr_t)method;
	error->error = GDEXTENSION_CALL_OK;
	if (count != ARG_COUNT[m]) {
		error->error = count < ARG_COUNT[m] ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		error->expected = ARG_COUNT[m];
		return;
	}
	PackedBytes packed[6];
	int64_t ints[6];
	const void *values[6];
	for (int i = 0; i < ARG_COUNT[m]; i++) {
		if (variant_get_type(args[i]) != ARGS[m][i]) {
			for (int j = 0; j < i; j++) if (ARGS[m][j] == B) pba_free(&packed[j]);
			error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
			error->argument = i;
			error->expected = ARGS[m][i];
			return;
		}
		if (ARGS[m][i] == B) {
			pba_from_variant(&packed[i], (GDExtensionVariantPtr)args[i]);
			values[i] = &packed[i];
		} else {
			int_from_variant(&ints[i], (GDExtensionVariantPtr)args[i]);
			values[i] = &ints[i];
		}
	}
	PackedBytes out;
	run(m, values, &out);
	variant_from_pba(ret, &out);
	pba_free(&out);
	for (int i = 0; i < ARG_COUNT[m]; i++) if (ARGS[m][i] == B) pba_free(&packed[i]);
}

static Name class_name, parent_name, empty_name;
static Text empty_text;

static GDExtensionPropertyInfo info(GDExtensionVariantType type, Name *name) {
	GDExtensionPropertyInfo p;
	p.type = type;
	p.name = name;
	p.class_name = &empty_name;
	p.hint = 0;
	p.hint_string = &empty_text;
	p.usage = 6; /* PROPERTY_USAGE_DEFAULT */
	return p;
}

static void add_method(int m) {
	Name method, names[6];
	string_name_new(&method, NAMES[m], 0);
	GDExtensionPropertyInfo args[6];
	GDExtensionClassMethodArgumentMetadata meta[6];
	for (int i = 0; i < ARG_COUNT[m]; i++) {
		string_name_new(&names[i], ARG_NAMES[m][i], 0);
		args[i] = info(ARGS[m][i], &names[i]);
		meta[i] = ARGS[m][i] == I ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	}
	GDExtensionPropertyInfo ret_info = info(B, &empty_name);
	GDExtensionClassMethodInfo mi;
	memset(&mi, 0, sizeof(mi));
	mi.name = &method;
	mi.method_userdata = (void *)(intptr_t)m;
	mi.call_func = call;
	mi.ptrcall_func = ptrcall;
	mi.method_flags = GDEXTENSION_METHOD_FLAG_STATIC;
	mi.has_return_value = 1;
	mi.return_value_info = &ret_info;
	mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	mi.argument_count = (uint32_t)ARG_COUNT[m];
	mi.arguments_info = args;
	mi.arguments_metadata = meta;
	register_method(library, &class_name, &mi);
	string_name_free(&method);
	for (int i = 0; i < ARG_COUNT[m]; i++) string_name_free(&names[i]);
}

static void free_instance(void *userdata, GDExtensionClassInstancePtr instance) {
	(void)userdata;
	(void)instance;
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	string_name_new(&class_name, "ELNativeAssets", 0);
	string_name_new(&parent_name, "Object", 0);
	string_name_new(&empty_name, "", 0);
	string_new(&empty_text, "");
	GDExtensionClassCreationInfo6 ci;
	memset(&ci, 0, sizeof(ci));
	ci.is_abstract = 1;
	ci.is_exposed = 1;
	ci.free_instance_func = free_instance;
	register_class(library, &class_name, &parent_name, &ci);
	for (int m = 0; m < M_COUNT; m++) add_method(m);
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	unregister_class(library, &class_name);
	string_name_free(&class_name);
	string_name_free(&parent_name);
	string_name_free(&empty_name);
	string_free(&empty_text);
}

#define LOAD(var, type, name) var = (type)get_proc(name); if (!var) return 0

EL_EXPORT GDExtensionBool el_assets_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	get_proc = p_get_proc_address;
	library = p_library;
	LOAD(variant_get_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
	LOAD(pba_index, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
	LOAD(pba_index_const, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
	LOAD(string_name_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
	LOAD(string_new, GDExtensionInterfaceStringNewWithLatin1Chars, "string_new_with_latin1_chars");
	LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
	LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
	LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
	GDExtensionInterfaceVariantGetPtrConstructor get_constructor;
	GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
	GDExtensionInterfaceVariantGetPtrBuiltinMethod get_method;
	GDExtensionInterfaceGetVariantToTypeConstructor get_to_type;
	GDExtensionInterfaceGetVariantFromTypeConstructor get_from_type;
	LOAD(get_constructor, GDExtensionInterfaceVariantGetPtrConstructor, "variant_get_ptr_constructor");
	LOAD(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
	LOAD(get_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");
	LOAD(get_to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
	LOAD(get_from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
	pba_new = get_constructor(B, 0);
	pba_free = get_destructor(B);
	string_name_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
	string_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
	Name size_name, resize_name;
	string_name_new(&size_name, "size", 0);
	string_name_new(&resize_name, "resize", 0);
	pba_size = get_method(B, &size_name, 3173160232);
	pba_resize = get_method(B, &resize_name, 848867239);
	string_name_free(&size_name);
	string_name_free(&resize_name);
	int_from_variant = get_to_type(I);
	pba_from_variant = get_to_type(B);
	variant_from_pba = get_from_type(B);
	if (!pba_new || !pba_free || !string_name_free || !string_free || !pba_size || !pba_resize
			|| !int_from_variant || !pba_from_variant || !variant_from_pba)
		return 0;
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = NULL;
	r_initialization->initialize = initialize;
	r_initialization->deinitialize = deinitialize;
	return 1;
}
