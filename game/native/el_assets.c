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
 *       a 16- or 32-bit masked texture level as RGBA8, or empty when the
 *       header's size, masks or shifts are invalid or the level runs past
 *       the data;
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
 *       Godot axes), then each frame's bounds (low x, y, z, high x, y, z);
 *   metal_mask(pixels, parts, side) -> PackedByteArray
 *       where a figure's skin is painted as metal, one byte per texel, or
 *       empty when the inputs are invalid (src/render/metal_masks.gd
 *       describes the inputs and keeps the same classifier in GDScript);
 *   upscale(weights, pixels, width, height, threads) -> PackedByteArray
 *       an RGBA8 picture four times as wide and high, worked out by the
 *       Real-ESRGAN realesr-general-x4v3 network whose weights are given
 *       (native/models/), on up to `threads` threads; empty when the
 *       weights or the picture are invalid (src/content/icon_upscale.gd).
 */
#include <math.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <pthread.h>
#if defined(__linux__)
#include <sys/resource.h>
#endif
#endif

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

/* One channel as the GDScript reader rounds it (alpha without bits is opaque).
 * The mask, shift and bit count were checked by raw_format(). */
static int channel(int64_t px, int64_t mask, int64_t shift, int64_t bits, int alpha) {
	if (alpha && bits == 0) return 255;
	int64_t full = mask >> shift;
	if (!full) return 0;
	return (int)(0.5 + 255.0 * (double)((px & mask) >> shift) / (double)full);
}

#define DATA_OFFSET 76
/* Largest side and pixel count of a texture level. */
#define MAX_SIDE 16384
#define MAX_PIXELS (1 << 26)

static int dimensions_ok(int64_t w, int64_t h) {
	return w > 0 && h > 0 && w <= MAX_SIDE && h <= MAX_SIDE && w * h <= MAX_PIXELS;
}

/* Reads and checks a masked level's format, by the same rules as
 * ELTexture.raw_format: 16 or 32 bits a pixel; each channel's shift below
 * the pixel's width and its mask exactly `bits` ones from `shift` up (a
 * channel the format lacks has neither mask nor bits); the whole level
 * inside the data. Returns the bytes per pixel, or 0 when anything is off. */
static int64_t raw_format(const uint8_t *d, int64_t n, int64_t w, int64_t h, int64_t src, int64_t mask[4], int64_t shift[4], int64_t bits[4]) {
	if (!dimensions_ok(w, h) || n < DATA_OFFSET || src < DATA_OFFSET || src > n) return 0;
	int64_t depth = u32(d, n, 20);
	if (depth != 16 && depth != 32) return 0;
	for (int c = 0; c < 4; c++) { /* a, r, g, b */
		mask[c] = u32(d, n, 24 + c * 12);
		shift[c] = u32(d, n, 28 + c * 12);
		bits[c] = u32(d, n, 32 + c * 12);
		if (shift[c] >= depth || bits[c] > depth) return 0;
		if (mask[c] == 0) {
			if (bits[c] != 0) return 0;
		} else if (bits[c] == 0 || shift[c] + bits[c] > depth || mask[c] != ((((int64_t)1 << bits[c]) - 1) << shift[c])) {
			return 0;
		}
	}
	int64_t bpp = depth / 8;
	if (w * h * bpp > n - src) return 0;
	return bpp;
}

static void decode_raw(const uint8_t *d, int64_t n, int64_t w, int64_t h, int64_t src, Buffer *out) {
	int64_t mask[4], shift[4], bits[4];
	int64_t bpp = raw_format(d, n, w, h, src, mask, shift, bits);
	if (!bpp) return;
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
		for (int64_t i = 0; i < w * h; i++) pixels[i] = table[u16(d, n, src + i * 2)];
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

static void decode_pnt3(const uint8_t *d, int64_t n, int64_t size, int64_t w, int64_t h, Buffer *out) {
	if (!dimensions_ok(w, h) || size < 0 || n < DATA_OFFSET) return;
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

/* -------------------------------------------------------------- metal masks */

/* The same arithmetic, step by step and in the same precision, as
 * ELMetalMasks.classify_script: texel colours in single precision (Godot's
 * Color), everything else in double, stored back to single where GDScript
 * stores into a PackedFloat32Array, so both give the same bytes. */
#pragma STDC FP_CONTRACT OFF

#define METAL_CHROMA 13
#define METAL_LEVELS 5
#define METAL_BINS (METAL_CHROMA * METAL_CHROMA * METAL_LEVELS)
#define METAL_TAU 6.283185307179586

static double smooth(double from, double to, double s) {
	double t = (s - from) / (to - from);
	t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
	return t * t * (3.0 - 2.0 * t);
}

static double dmax(double a, double b) { return a > b ? a : b; }
static double dmin(double a, double b) { return a < b ? a : b; }

static int64_t wrapped(int64_t v, int64_t side) {
	int64_t m = v % side;
	return m < 0 ? m + side : m;
}

static int64_t clamp_bin(int64_t v, int64_t top) { return v < 0 ? 0 : (v > top ? top : v); }

/* How much a texel looks like skin: a faint warm tint (ELMetalMasks._skin_tone). */
static double skin_tone(double s, double h) {
	double away = fabs(h - 0.03);
	away = dmin(away, 1.0 - away);
	return smooth(0.08, 0.14, s) * (1.0 - smooth(0.05, 0.08, away));
}

static double painted_metal(double v, double s, double h, double tinted, double grey_below) {
	double grey = smooth(tinted, grey_below, s) * smooth(0.15, 0.35, v);
	double gold = smooth(0.45, 0.65, v) * (1.0 - smooth(0.02, 0.06, fabs(h - 0.12))) * smooth(0.25, 0.4, s);
	return dmax(grey, gold);
}

/* Marks the texels whose centres a UV triangle covers, and its centroid's. */
static void cover_triangle(uint8_t *cover, int64_t side, const float *uv, const int32_t *corner, uint8_t mark) {
	float fs = (float)side;
	float ax = uv[corner[0] * 2] * fs, ay = uv[corner[0] * 2 + 1] * fs;
	float bx = uv[corner[1] * 2] * fs, by = uv[corner[1] * 2 + 1] * fs;
	float cx = uv[corner[2] * 2] * fs, cy = uv[corner[2] * 2 + 1] * fs;
	double top = dmin(ay, dmin(by, cy)), bottom = dmax(ay, dmax(by, cy));
	double left = dmin(ax, dmin(bx, cx)), right = dmax(ax, dmax(bx, cx));
	if (bottom - top > (double)(side * 2) || right - left > (double)(side * 2)) return;
	float mx = (ax + bx + cx) / 3.0f, my = (ay + by + cy) / 3.0f;
	cover[wrapped((int64_t)floor(my), side) * side + wrapped((int64_t)floor(mx), side)] = mark;
	const double px[3] = { ax, bx, cx }, py[3] = { ay, by, cy };
	int64_t y0 = (int64_t)ceil(top - 0.5), y1 = (int64_t)floor(bottom - 0.5);
	for (int64_t y = y0; y <= y1; y++) {
		double row = (double)y + 0.5, low = INFINITY, high = -INFINITY;
		for (int e = 0; e < 3; e++) {
			int f = (e + 1) % 3;
			if ((py[e] <= row) != (py[f] <= row)) {
				double x = px[e] + (row - py[e]) * (px[f] - px[e]) / (py[f] - py[e]);
				low = dmin(low, x);
				high = dmax(high, x);
			}
		}
		if (low > high) continue;
		int64_t at = wrapped(y, side) * side;
		int64_t x1 = (int64_t)floor(high - 0.5);
		for (int64_t x = (int64_t)ceil(low - 0.5); x <= x1; x++) cover[at + wrapped(x, side)] = mark;
	}
}

/* Spreads a colour histogram to its neighbouring bins, normalised to sum 1. */
static void blur_bins(const float *hist, float *out) {
	double total = 0.0;
	for (int a = 0; a < METAL_CHROMA; a++)
		for (int b = 0; b < METAL_CHROMA; b++)
			for (int v = 0; v < METAL_LEVELS; v++) {
				double sum = 0.0;
				for (int da = -1; da <= 1; da++)
					for (int db = -1; db <= 1; db++)
						for (int dv = -1; dv <= 1; dv++) {
							int na = a + da, nb = b + db, nv = v + dv;
							if (na < 0 || nb < 0 || nv < 0 || na >= METAL_CHROMA || nb >= METAL_CHROMA || nv >= METAL_LEVELS) continue;
							double weight = (da != 0 ? 0.5 : 1.0) * (db != 0 ? 0.5 : 1.0) * (dv != 0 ? 0.5 : 1.0);
							sum += (double)hist[(na * METAL_CHROMA + nb) * METAL_LEVELS + nv] * weight;
						}
				out[(a * METAL_CHROMA + b) * METAL_LEVELS + v] = (float)sum;
				total += sum;
			}
	if (total > 0.0)
		for (int i = 0; i < METAL_BINS; i++) out[i] = (float)((double)out[i] / total);
}

/* The mean of each texel's square neighbourhood (`radius` texels out). */
static void box_mean(const float *values, float *rows, float *out, int64_t side, int64_t radius) {
	double span = (double)(radius * 2 + 1);
	for (int64_t y = 0; y < side; y++) {
		int64_t at = y * side;
		double sum = 0.0;
		for (int64_t d = -radius; d <= radius; d++) sum += values[at + clamp_bin(d, side - 1)];
		for (int64_t x = 0; x < side; x++) {
			rows[at + x] = (float)(sum / span);
			sum += (double)values[at + clamp_bin(x + radius + 1, side - 1)] - (double)values[at + clamp_bin(x - radius, side - 1)];
		}
	}
	for (int64_t x = 0; x < side; x++) {
		double sum = 0.0;
		for (int64_t d = -radius; d <= radius; d++) sum += rows[clamp_bin(d, side - 1) * side + x];
		for (int64_t y = 0; y < side; y++) {
			out[y * side + x] = (float)(sum / span);
			sum += (double)rows[clamp_bin(y + radius + 1, side - 1) * side + x] - (double)rows[clamp_bin(y - radius, side - 1) * side + x];
		}
	}
}

static int32_t s32_at(const uint8_t *d, int64_t at) {
	int32_t v;
	memcpy(&v, d + at, 4);
	return v;
}

/* `pixels`: side x side RGBA8. `parts`: per part an s32 mark (1 a figure
 * part, 2 a named metal one, 3 one metal all over), s32 UV count, s32 index
 * count, then the UVs (float u, v) and indices (s32). */
static void metal_mask(const uint8_t *pixels, int64_t pixels_n, const uint8_t *parts, int64_t parts_n, int64_t side, Buffer *out) {
	if (side <= 0 || side > 4096 || pixels_n != side * side * 4) return;
	int64_t count = side * side;
	uint8_t *cover = calloc((size_t)count, 1), *levels = malloc((size_t)count);
	float *painted = calloc((size_t)count, sizeof(float)), *greyer = calloc((size_t)count, sizeof(float));
	float *learnt = calloc((size_t)count, sizeof(float)), *rows = calloc((size_t)count, sizeof(float));
	float *around = calloc((size_t)count, sizeof(float)), *skin = calloc((size_t)count, sizeof(float));
	int32_t *bins = calloc((size_t)count, sizeof(int32_t));
	double seed_weight = 0.0, seed_warmth = 0.0;
	float seed_raw[METAL_BINS] = { 0 }, body_raw[METAL_BINS] = { 0 }, seed_hist[METAL_BINS], body_hist[METAL_BINS];
	if (!cover || !levels || !painted || !greyer || !learnt || !rows || !around || !skin || !bins) goto done;
	/* The figure's parts first, then its metal ones over them. */
	for (int pass = 0; pass < 2; pass++) {
		int64_t at = 0;
		while (at + 12 <= parts_n) {
			int32_t mark = s32_at(parts, at), uv_count = s32_at(parts, at + 4), index_count = s32_at(parts, at + 8);
			int64_t next = at + 12 + (int64_t)uv_count * 8 + (int64_t)index_count * 4;
			if (uv_count < 0 || index_count < 0 || next > parts_n) goto done;
			if ((pass == 0) == (mark == 1)) {
				float *uv = malloc((size_t)uv_count * 8 + 8);
				int32_t *indices = malloc((size_t)index_count * 4 + 4);
				if (!uv || !indices) {
					free(uv);
					free(indices);
					goto done;
				}
				memcpy(uv, parts + at + 12, (size_t)uv_count * 8);
				memcpy(indices, parts + at + 12 + (int64_t)uv_count * 8, (size_t)index_count * 4);
				for (int64_t t = 0; t + 2 < index_count; t += 3) {
					if (indices[t] < 0 || indices[t + 1] < 0 || indices[t + 2] < 0
							|| indices[t] >= uv_count || indices[t + 1] >= uv_count || indices[t + 2] >= uv_count) continue;
					cover_triangle(cover, side, uv, indices + t, (uint8_t)mark);
				}
				free(uv);
				free(indices);
			}
			at = next;
		}
	}
	for (int64_t i = 0; i < count; i++) {
		const uint8_t *p = pixels + i * 4;
		if (p[3] < 128) continue;
		float r = (float)(p[0] / 255.0), g = (float)(p[1] / 255.0), b = (float)(p[2] / 255.0);
		float low = r < g ? r : g, high = r > g ? r : g;
		low = low < b ? low : b;
		high = high > b ? high : b;
		float delta = high - low, hue = 0.0f;
		if (delta != 0.0f) {
			if (r == high) hue = (g - b) / delta;
			else if (g == high) hue = 2 + (b - r) / delta;
			else hue = 4 + (r - g) / delta;
			hue /= 6.0f;
			if (hue < 0.0f) hue += 1.0f;
		}
		float saturation = high != 0.0f ? delta / high : 0.0f, value = high;
		double metal = painted_metal(value, saturation, hue, 0.38, 0.18);
		painted[i] = (float)metal;
		greyer[i] = (float)painted_metal(value, saturation, hue, 0.32, 0.18);
		double tone = skin_tone(saturation, hue);
		skin[i] = (float)tone;
		double angle = (double)hue * METAL_TAU;
		int64_t a = clamp_bin((int64_t)(((double)saturation * cos(angle) + 1.0) * 0.5 * METAL_CHROMA), METAL_CHROMA - 1);
		int64_t c = clamp_bin((int64_t)(((double)saturation * sin(angle) + 1.0) * 0.5 * METAL_CHROMA), METAL_CHROMA - 1);
		int64_t v = clamp_bin((int64_t)((double)value * METAL_LEVELS), METAL_LEVELS - 1);
		int32_t bin = (int32_t)((a * METAL_CHROMA + c) * METAL_LEVELS + v);
		bins[i] = bin;
		if (cover[i] == 2) {
			seed_raw[bin] = (float)((double)seed_raw[bin] + metal);
			seed_weight += metal;
			seed_warmth += metal * tone;
		}
		else if (cover[i] == 1) body_raw[bin] = (float)((double)body_raw[bin] + metal);
	}
	blur_bins(seed_raw, seed_hist);
	blur_bins(body_raw, body_hist);
	double peak = 0.0;
	for (int i = 0; i < METAL_BINS; i++) peak = dmax(peak, seed_hist[i]);
	/* Skin-toned texels are learnt only beside warm-painted metal. */
	double skin_kept = 1.0 - smooth(0.1, 0.3, seed_warmth / dmax(seed_weight, 0.000001));
	if (peak > 0.0)
		for (int64_t i = 0; i < count; i++) {
			if (cover[i] == 0 || painted[i] <= 0.0f) continue;
			double in_seeds = seed_hist[bins[i]];
			double share = in_seeds / dmax(in_seeds + (double)body_hist[bins[i]], 0.000001);
			learnt[i] = (float)(smooth(0.1, 0.35, in_seeds / peak) * smooth(0.12, 0.3, share) * smooth(0.15, 0.45, greyer[i]) * (1.0 - (double)skin[i] * skin_kept));
		}
	/* A lone matching texel amid skin or cloth is paint, not a plate. */
	box_mean(learnt, rows, around, side, 2);
	for (int64_t i = 0; i < count; i++) {
		double named = cover[i] == 2 ? (double)painted[i] : (cover[i] == 3 ? 1.0 : 0.0);
		double value = dmax(named, (double)learnt[i] * smooth(0.1, 0.3, around[i]));
		levels[i] = (uint8_t)(int64_t)(value * 255.0 + 0.5);
	}
	put(out, levels, count);
done:
	free(cover);
	free(levels);
	free(painted);
	free(greyer);
	free(learnt);
	free(rows);
	free(around);
	free(skin);
	free(bins);
}

/* ---------------------------------------------------------- super resolution */

/* SRVGGNetCompact as Real-ESRGAN's realesr-general-x4v3 uses it: a 3x3
 * convolution from RGB to 64 features, 32 more 3x3 convolutions of 64
 * features, each followed by a per-channel PReLU, then a 3x3 convolution to
 * 48 channels that a pixel shuffle turns into a 4x picture, to which the
 * nearest-neighbour enlargement of the input is added.
 *
 * The weights blob: "ELSR", then u32 version, input channels, features,
 * body convolutions, last convolution's channels, scale and number type
 * (1: float16), then per convolution its weights (out, in, 3, 3), biases and
 * (all but the last) PReLU slopes. */
#pragma STDC FP_CONTRACT ON
/* The vector helpers below are always inlined: no vector crosses a call. */
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wpsabi"
#endif

#define SR_FEAT 64
#define SR_CONVS 34
#define SR_LAST 48
#define SR_SCALE 4
#define SR_FLOATS 1213296
/* The picture is first widened by this many repeated border pixels, so the
 * network's zero padding does not darken its edges. */
#define SR_PRE_PAD 8
/* Worked out in tiles of this many pixels, each read with this much more
 * picture around it (so tiles meet without seams). */
#define SR_TILE 192
#define SR_TILE_PAD 24
#define SR_WINDOW (SR_TILE + 2 * SR_TILE_PAD)
#define SR_MAX_THREADS 64
/* Largest picture side and pixel count (the result is 16 times as many). */
#define SR_MAX_SIDE 4096
#define SR_MAX_PIXELS (1 << 22)

typedef struct {
	/* Per convolution: weights as [ky * 3 + kx][in][out], biases, slopes. */
	float *w[SR_CONVS], *b[SR_CONVS], *s[SR_CONVS];
	float *storage;
} SrNet;

static float half_to_float(uint16_t h) {
	uint32_t sign = (uint32_t)(h & 0x8000) << 16, exp = (h >> 10) & 0x1f, man = h & 0x3ff, bits;
	if (exp == 0) {
		if (man == 0) bits = sign;
		else {
			/* Subnormal: normalise it. */
			int e = -1;
			do {
				e++;
				man <<= 1;
			} while (!(man & 0x400));
			bits = sign | ((uint32_t)(127 - 15 - e) << 23) | ((man & 0x3ff) << 13);
		}
	} else if (exp == 31) bits = sign | 0x7f800000 | (man << 13);
	else bits = sign | ((exp + 127 - 15) << 23) | (man << 13);
	float f;
	memcpy(&f, &bits, 4);
	return f;
}

static int sr_load(const uint8_t *d, int64_t n, SrNet *net) {
	memset(net, 0, sizeof(*net));
	if (n != 32 + (int64_t)SR_FLOATS * 2 || memcmp(d, "ELSR", 4) != 0) return 0;
	static const uint32_t header[7] = { 1, 3, SR_FEAT, SR_CONVS - 2, SR_LAST, SR_SCALE, 1 };
	for (int i = 0; i < 7; i++)
		if (u32(d, n, 4 + i * 4) != header[i]) return 0;
	net->storage = (float *)malloc((size_t)SR_FLOATS * sizeof(float));
	if (!net->storage) return 0;
	int64_t at = 32;
	float *put_at = net->storage;
	for (int layer = 0; layer < SR_CONVS; layer++) {
		int ci = layer == 0 ? 3 : SR_FEAT, co = layer == SR_CONVS - 1 ? SR_LAST : SR_FEAT;
		net->w[layer] = put_at;
		for (int o = 0; o < co; o++)
			for (int i = 0; i < ci; i++)
				for (int k = 0; k < 9; k++) {
					net->w[layer][(k * ci + i) * co + o] = half_to_float(u16(d, n, at));
					at += 2;
				}
		put_at += 9 * ci * co;
		net->b[layer] = put_at;
		for (int o = 0; o < co; o++, at += 2) net->b[layer][o] = half_to_float(u16(d, n, at));
		put_at += co;
		if (layer < SR_CONVS - 1) {
			net->s[layer] = put_at;
			for (int o = 0; o < co; o++, at += 2) net->s[layer][o] = half_to_float(u16(d, n, at));
			put_at += co;
		}
	}
	return at == n;
}

typedef float SrV8 __attribute__((vector_size(32)));

static inline __attribute__((always_inline)) SrV8 sr_ld(const float *p) {
	SrV8 v;
	memcpy(&v, p, sizeof(v));
	return v;
}

static inline __attribute__((always_inline)) void sr_st(float *p, SrV8 v) { memcpy(p, &v, sizeof(v)); }

static inline __attribute__((always_inline)) SrV8 sr_act(SrV8 a, const float *slope) {
	if (!slope) return a;
	SrV8 zero = { 0 };
	return __builtin_elementwise_max(a, zero) + sr_ld(slope) * __builtin_elementwise_min(a, zero);
}

/* One output row `y` of a 3x3 convolution. `in` has a border of zeros one
 * pixel wide: row stride (width + 2) * ci; `out` points at the row's first
 * pixel, `co` floats a pixel. Six pixels and 16 channels at a time. */
static inline __attribute__((always_inline)) void sr_conv_row_body(const float *in, int ci, float *out, int co, const float *w,
		const float *bias, const float *slope, int width, int y) {
	int64_t row = (int64_t)(width + 2) * ci;
	for (int c0 = 0; c0 < co; c0 += 16) {
		int x = 0;
		for (; x + 6 <= width; x += 6) {
			SrV8 lo[6], hi[6];
			for (int p = 0; p < 6; p++) {
				lo[p] = sr_ld(bias + c0);
				hi[p] = sr_ld(bias + c0 + 8);
			}
			for (int k = 0; k < 9; k++) {
				const float *ip = in + (y + k / 3) * row + (int64_t)(x + k % 3) * ci;
				const float *wp = w + (int64_t)k * ci * co + c0;
				for (int c = 0; c < ci; c++) {
					SrV8 w0 = sr_ld(wp + (int64_t)c * co), w1 = sr_ld(wp + (int64_t)c * co + 8);
					for (int p = 0; p < 6; p++) {
						float v = ip[p * ci + c];
						lo[p] += w0 * v;
						hi[p] += w1 * v;
					}
				}
			}
			float *op = out + (int64_t)x * co + c0;
			for (int p = 0; p < 6; p++) {
				sr_st(op + p * co, sr_act(lo[p], slope ? slope + c0 : NULL));
				sr_st(op + p * co + 8, sr_act(hi[p], slope ? slope + c0 + 8 : NULL));
			}
		}
		for (; x < width; x++) {
			SrV8 a0 = sr_ld(bias + c0), a1 = sr_ld(bias + c0 + 8);
			for (int k = 0; k < 9; k++) {
				const float *ip = in + (y + k / 3) * row + (int64_t)(x + k % 3) * ci;
				const float *wp = w + (int64_t)k * ci * co + c0;
				for (int c = 0; c < ci; c++) {
					a0 += sr_ld(wp + (int64_t)c * co) * ip[c];
					a1 += sr_ld(wp + (int64_t)c * co + 8) * ip[c];
				}
			}
			float *op = out + (int64_t)x * co + c0;
			sr_st(op, sr_act(a0, slope ? slope + c0 : NULL));
			sr_st(op + 8, sr_act(a1, slope ? slope + c0 + 8 : NULL));
		}
	}
}

static void sr_conv_row_plain(const float *in, int ci, float *out, int co, const float *w, const float *bias, const float *slope, int width, int y) {
	sr_conv_row_body(in, ci, out, co, w, bias, slope, width, y);
}

#if defined(__x86_64__) || defined(__i386__)
__attribute__((target("avx2,fma"))) static void sr_conv_row_avx2(const float *in, int ci, float *out, int co, const float *w,
		const float *bias, const float *slope, int width, int y) {
	sr_conv_row_body(in, ci, out, co, w, bias, slope, width, y);
}

/* Whether the processor and the system allow AVX2 and FMA. */
static int sr_has_avx2(void) {
	uint32_t a, b, c, d;
	__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(0), "c"(0));
	if (a < 7) return 0;
	__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1), "c"(0));
	int fma = (c >> 12) & 1, osxsave = (c >> 27) & 1, avx = (c >> 28) & 1;
	if (!fma || !osxsave || !avx) return 0;
	uint32_t lo, hi;
	__asm__ volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
	if ((lo & 6) != 6) return 0;
	__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(7), "c"(0));
	return (b >> 5) & 1;
}
#endif

typedef void (*SrConvRow)(const float *, int, float *, int, const float *, const float *, const float *, int, int);

typedef struct {
	const SrNet *net;
	SrConvRow conv_row;
	int width, height, threads, binary_alpha, has_alpha;
	/* The picture widened by SR_PRE_PAD on every side, RGB floats. */
	const float *padded;
	int padded_width, padded_height;
	const uint8_t *alpha;
	uint8_t *out;
	/* The tile in work: its window in the padded picture, its core. */
	int wx, wy, ww, wh, cx, cy, cw, ch;
	float *input, *a, *b, *last;
	atomic_int counters[2];
	atomic_int arrived, generation;
	/* Set once every helper thread has been started (or failed to). */
	atomic_int go;
	/* Threads that wait longer than a short spin sleep on these. */
#if defined(_WIN32)
	SRWLOCK lock;
	CONDITION_VARIABLE wake;
#else
	pthread_mutex_t lock;
	pthread_cond_t wake;
#endif
} SrJob;

/* Waits until `value` no longer holds `seen`: a short spin, then asleep
 * (a busy machine must not have waiting threads burn the time the late
 * ones need). */
static void sr_wait_change(SrJob *job, atomic_int *value, int seen) {
	for (int spins = 0; spins < 4000; spins++)
		if (atomic_load(value) != seen) return;
#if defined(_WIN32)
	AcquireSRWLockExclusive(&job->lock);
	while (atomic_load(value) == seen) SleepConditionVariableSRW(&job->wake, &job->lock, INFINITE, 0);
	ReleaseSRWLockExclusive(&job->lock);
#else
	pthread_mutex_lock(&job->lock);
	while (atomic_load(value) == seen) pthread_cond_wait(&job->wake, &job->lock);
	pthread_mutex_unlock(&job->lock);
#endif
}

/* Changes `value` and wakes the threads waiting for it. */
static void sr_signal(SrJob *job, atomic_int *value, int to) {
#if defined(_WIN32)
	AcquireSRWLockExclusive(&job->lock);
	atomic_store(value, to);
	ReleaseSRWLockExclusive(&job->lock);
	WakeAllConditionVariable(&job->wake);
#else
	pthread_mutex_lock(&job->lock);
	atomic_store(value, to);
	pthread_cond_broadcast(&job->wake);
	pthread_mutex_unlock(&job->lock);
#endif
}

/* Waits until every thread has reached it. The last to arrive clears the
 * row counter of the phase just finished. */
static void sr_barrier(SrJob *job, int phase) {
	int generation = atomic_load(&job->generation);
	if (atomic_fetch_add(&job->arrived, 1) == job->threads - 1) {
		atomic_store(&job->counters[phase & 1], 0);
		atomic_store(&job->arrived, 0);
		sr_signal(job, &job->generation, generation + 1);
		return;
	}
	sr_wait_change(job, &job->generation, generation);
}

/* Copies a tile's window of the padded picture into the first layer's input. */
static void sr_prepare_tile(SrJob *job) {
	int row = job->ww + 2;
	memset(job->input, 0, (size_t)(row * (job->wh + 2) * 3) * sizeof(float));
	for (int y = 0; y < job->wh; y++)
		memcpy(job->input + ((int64_t)(y + 1) * row + 1) * 3, job->padded + ((int64_t)(job->wy + y) * job->padded_width + job->wx) * 3,
			(size_t)job->ww * 3 * sizeof(float));
	/* The feature maps' zero borders. */
	memset(job->a, 0, (size_t)(row * (job->wh + 2) * SR_FEAT) * sizeof(float));
	memset(job->b, 0, (size_t)(row * (job->wh + 2) * SR_FEAT) * sizeof(float));
}

static float sr_cubic(float t) {
	/* Catmull-Rom. */
	t = fabsf(t);
	if (t < 1.0f) return 1.5f * t * t * t - 2.5f * t * t + 1.0f;
	if (t < 2.0f) return -0.5f * t * t * t + 2.5f * t * t - 4.0f * t + 2.0f;
	return 0.0f;
}

/* One output row of the alpha channel: bicubic, made sharp again for
 * pictures whose alpha is only on or off. */
static void sr_alpha_row(SrJob *job, int oy) {
	int w = job->width, h = job->height, ow = w * SR_SCALE;
	uint8_t *o = job->out + (int64_t)oy * ow * 4;
	if (!job->has_alpha) {
		for (int ox = 0; ox < ow; ox++) o[ox * 4 + 3] = 255;
		return;
	}
	float sy = (oy + 0.5f) / SR_SCALE - 0.5f;
	int y0 = (int)floorf(sy);
	float wy[4];
	for (int i = 0; i < 4; i++) wy[i] = sr_cubic(sy - (float)(y0 - 1 + i));
	for (int ox = 0; ox < ow; ox++) {
		float sx = (ox + 0.5f) / SR_SCALE - 0.5f;
		int x0 = (int)floorf(sx);
		float sum = 0.0f;
		for (int j = 0; j < 4; j++) {
			int yy = y0 - 1 + j;
			yy = yy < 0 ? 0 : (yy >= h ? h - 1 : yy);
			float line = 0.0f;
			for (int i = 0; i < 4; i++) {
				int xx = x0 - 1 + i;
				float weight = sr_cubic(sx - (float)xx);
				xx = xx < 0 ? 0 : (xx >= w ? w - 1 : xx);
				line += weight * (float)job->alpha[(int64_t)yy * w + xx];
			}
			sum += wy[j] * line;
		}
		if (job->binary_alpha) o[ox * 4 + 3] = sum >= 127.5f ? 255 : 0;
		else o[ox * 4 + 3] = (uint8_t)(sum <= 0.0f ? 0 : (sum >= 255.0f ? 255 : (int)(sum + 0.5f)));
	}
}

static void sr_worker(SrJob *job, int id) {
	sr_wait_change(job, &job->go, 0);
	const SrNet *net = job->net;
	int phase = 0;
	int core_w = job->width, core_h = job->height;
	for (int ty = 0; ty < core_h; ty += SR_TILE)
		for (int tx = 0; tx < core_w; tx += SR_TILE) {
			if (id == 0) {
				job->cx = SR_PRE_PAD + tx;
				job->cy = SR_PRE_PAD + ty;
				job->cw = core_w - tx < SR_TILE ? core_w - tx : SR_TILE;
				job->ch = core_h - ty < SR_TILE ? core_h - ty : SR_TILE;
				job->wx = job->cx - SR_TILE_PAD < 0 ? 0 : job->cx - SR_TILE_PAD;
				job->wy = job->cy - SR_TILE_PAD < 0 ? 0 : job->cy - SR_TILE_PAD;
				int right = job->cx + job->cw + SR_TILE_PAD, bottom = job->cy + job->ch + SR_TILE_PAD;
				if (right > job->padded_width) right = job->padded_width;
				if (bottom > job->padded_height) bottom = job->padded_height;
				job->ww = right - job->wx;
				job->wh = bottom - job->wy;
				sr_prepare_tile(job);
			}
			sr_barrier(job, phase++);
			int row = job->ww + 2;
			const float *in = job->input;
			for (int layer = 0; layer < SR_CONVS; layer++) {
				int ci = layer == 0 ? 3 : SR_FEAT, last = layer == SR_CONVS - 1;
				float *dst = last ? job->last : (layer & 1 ? job->b : job->a);
				for (int y; (y = atomic_fetch_add(&job->counters[phase & 1], 1)) < job->wh;) {
					float *o = last ? dst + (int64_t)y * job->ww * SR_LAST : dst + ((int64_t)(y + 1) * row + 1) * SR_FEAT;
					job->conv_row(in, ci, o, last ? SR_LAST : SR_FEAT, net->w[layer], net->b[layer], last ? NULL : net->s[layer], job->ww, y);
				}
				sr_barrier(job, phase++);
				in = dst;
			}
			/* Pixel shuffle, plus the input enlarged, into the tile's core. */
			for (int y; (y = atomic_fetch_add(&job->counters[phase & 1], 1)) < job->ch;) {
				int ly = job->cy - job->wy + y, py = job->cy + y;
				for (int x = 0; x < job->cw; x++) {
					int lx = job->cx - job->wx + x, px = job->cx + x;
					const float *f = job->last + ((int64_t)ly * job->ww + lx) * SR_LAST;
					const float *base = job->padded + ((int64_t)py * job->padded_width + px) * 3;
					for (int i = 0; i < SR_SCALE; i++) {
						uint8_t *o = job->out + (((int64_t)(py - SR_PRE_PAD) * SR_SCALE + i) * job->width * SR_SCALE + (int64_t)(px - SR_PRE_PAD) * SR_SCALE) * 4;
						for (int j = 0; j < SR_SCALE; j++)
							for (int c = 0; c < 3; c++) {
								float v = (f[c * 16 + i * 4 + j] + base[c]) * 255.0f;
								o[j * 4 + c] = (uint8_t)(v <= 0.0f ? 0 : (v >= 255.0f ? 255 : (int)(v + 0.5f)));
							}
					}
				}
			}
			sr_barrier(job, phase++);
		}
	for (int y; (y = atomic_fetch_add(&job->counters[phase & 1], 1)) < core_h * SR_SCALE;) sr_alpha_row(job, y);
	sr_barrier(job, phase++);
}

typedef struct {
	SrJob *job;
	int id;
} SrStart;

#if defined(_WIN32)
static DWORD WINAPI sr_thread(LPVOID arg) {
	SrStart *start = (SrStart *)arg;
	SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
	sr_worker(start->job, start->id);
	return 0;
}
#else
static void *sr_thread(void *arg) {
	SrStart *start = (SrStart *)arg;
#if defined(__linux__)
	/* Linux nice values are per thread: helpers yield to the game's own. */
	setpriority(PRIO_PROCESS, 0, 5);
#endif
	sr_worker(start->job, start->id);
	return NULL;
}
#endif

/* Gives fully transparent pixels the colour of their nearest visible
 * neighbours, so the network does not pull dark fringes into edges. */
static void sr_fill_hidden(float *rgb, const uint8_t *alpha, int w, int h) {
	int64_t count = (int64_t)w * h;
	uint8_t *known = (uint8_t *)malloc((size_t)count), *next = (uint8_t *)malloc((size_t)count);
	if (!known || !next) {
		free(known);
		free(next);
		return;
	}
	double sum[3] = { 0 };
	int64_t seen = 0;
	for (int64_t i = 0; i < count; i++) {
		known[i] = alpha[i] != 0;
		if (known[i]) {
			for (int c = 0; c < 3; c++) sum[c] += rgb[i * 3 + c];
			seen++;
		}
	}
	if (seen == 0 || seen == count) {
		free(known);
		free(next);
		return;
	}
	for (int pass = 0; pass < 24; pass++) {
		int changed = 0;
		memcpy(next, known, (size_t)count);
		for (int y = 0; y < h; y++)
			for (int x = 0; x < w; x++) {
				int64_t i = (int64_t)y * w + x;
				if (known[i]) continue;
				float acc[3] = { 0 };
				int n = 0;
				for (int dy = -1; dy <= 1; dy++)
					for (int dx = -1; dx <= 1; dx++) {
						int nx = x + dx, ny = y + dy;
						if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
						int64_t j = (int64_t)ny * w + nx;
						if (!known[j]) continue;
						for (int c = 0; c < 3; c++) acc[c] += rgb[j * 3 + c];
						n++;
					}
				if (n) {
					for (int c = 0; c < 3; c++) rgb[i * 3 + c] = acc[c] / (float)n;
					next[i] = 1;
					changed = 1;
				}
			}
		memcpy(known, next, (size_t)count);
		if (!changed) break;
	}
	for (int64_t i = 0; i < count; i++)
		if (!known[i])
			for (int c = 0; c < 3; c++) rgb[i * 3 + c] = (float)(sum[c] / (double)seen);
	free(known);
	free(next);
}

static void upscale(const uint8_t *weights, int64_t weights_n, const uint8_t *pixels, int64_t pixels_n, int64_t width, int64_t height,
		int64_t threads, Buffer *out) {
	if (width <= 0 || height <= 0 || width > SR_MAX_SIDE || height > SR_MAX_SIDE || width * height > SR_MAX_PIXELS || pixels_n != width * height * 4) return;
	SrNet net;
	if (!sr_load(weights, weights_n, &net)) {
		free(net.storage);
		return;
	}
	int w = (int)width, h = (int)height;
	int pw = w + 2 * SR_PRE_PAD, ph = h + 2 * SR_PRE_PAD;
	int64_t count = (int64_t)w * h;
	float *rgb = (float *)malloc((size_t)count * 3 * sizeof(float));
	float *padded = (float *)malloc((size_t)pw * ph * 3 * sizeof(float));
	uint8_t *alpha = (uint8_t *)malloc((size_t)count);
	size_t feature = (size_t)(SR_WINDOW + 2) * (SR_WINDOW + 2) * SR_FEAT;
	float *input = (float *)malloc((size_t)(SR_WINDOW + 2) * (SR_WINDOW + 2) * 3 * sizeof(float));
	float *a = (float *)malloc(feature * sizeof(float)), *b = (float *)malloc(feature * sizeof(float));
	float *last = (float *)malloc((size_t)SR_WINDOW * SR_WINDOW * SR_LAST * sizeof(float));
	uint8_t *result = (uint8_t *)malloc((size_t)count * SR_SCALE * SR_SCALE * 4);
	if (!rgb || !padded || !alpha || !input || !a || !b || !last || !result) {
		out->failed = 1;
		goto done;
	}
	int has_alpha = 0, binary = 1;
	for (int64_t i = 0; i < count; i++) {
		for (int c = 0; c < 3; c++) rgb[i * 3 + c] = pixels[i * 4 + c] / 255.0f;
		alpha[i] = pixels[i * 4 + 3];
		if (alpha[i] != 255) has_alpha = 1;
		if (alpha[i] != 0 && alpha[i] != 255) binary = 0;
	}
	if (has_alpha) sr_fill_hidden(rgb, alpha, w, h);
	for (int y = 0; y < ph; y++) {
		int sy = y - SR_PRE_PAD;
		sy = sy < 0 ? 0 : (sy >= h ? h - 1 : sy);
		for (int x = 0; x < pw; x++) {
			int sx = x - SR_PRE_PAD;
			sx = sx < 0 ? 0 : (sx >= w ? w - 1 : sx);
			memcpy(padded + ((int64_t)y * pw + x) * 3, rgb + ((int64_t)sy * w + sx) * 3, 3 * sizeof(float));
		}
	}
	SrJob job;
	memset(&job, 0, sizeof(job));
	job.net = &net;
	job.conv_row = sr_conv_row_plain;
#if defined(__x86_64__) || defined(__i386__)
	if (sr_has_avx2()) job.conv_row = sr_conv_row_avx2;
#endif
	job.width = w;
	job.height = h;
	job.threads = threads < 1 ? 1 : (threads > SR_MAX_THREADS ? SR_MAX_THREADS : (int)threads);
	job.has_alpha = has_alpha;
	job.binary_alpha = binary;
	job.padded = padded;
	job.padded_width = pw;
	job.padded_height = ph;
	job.alpha = alpha;
	job.out = result;
	job.input = input;
	job.a = a;
	job.b = b;
	job.last = last;
	atomic_init(&job.counters[0], 0);
	atomic_init(&job.counters[1], 0);
	atomic_init(&job.arrived, 0);
	atomic_init(&job.generation, 0);
	atomic_init(&job.go, 0);
#if defined(_WIN32)
	InitializeSRWLock(&job.lock);
	InitializeConditionVariable(&job.wake);
#else
	pthread_mutex_init(&job.lock, NULL);
	pthread_cond_init(&job.wake, NULL);
#endif
	SrStart starts[SR_MAX_THREADS];
#if defined(_WIN32)
	HANDLE handles[SR_MAX_THREADS];
#else
	pthread_t handles[SR_MAX_THREADS];
#endif
	int started = 1;
	for (int i = 1; i < job.threads; i++) {
		starts[i].job = &job;
		starts[i].id = i;
#if defined(_WIN32)
		handles[i] = CreateThread(NULL, 0, sr_thread, &starts[i], 0, NULL);
		if (!handles[i]) break;
#else
		if (pthread_create(&handles[i], NULL, sr_thread, &starts[i]) != 0) break;
#endif
		started++;
	}
	/* Threads that could not start leave the barrier to fewer. */
	job.threads = started;
	sr_signal(&job, &job.go, 1);
	sr_worker(&job, 0);
	for (int i = 1; i < started; i++) {
#if defined(_WIN32)
		WaitForSingleObject(handles[i], INFINITE);
		CloseHandle(handles[i]);
#else
		pthread_join(handles[i], NULL);
#endif
	}
#if !defined(_WIN32)
	pthread_mutex_destroy(&job.lock);
	pthread_cond_destroy(&job.wake);
#endif
	put(out, result, count * SR_SCALE * SR_SCALE * 4);
done:
	free(net.storage);
	free(rgb);
	free(padded);
	free(alpha);
	free(input);
	free(a);
	free(b);
	free(last);
	free(result);
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

enum { M_RAW, M_PNT3, M_FIGURE, M_UNPACK, M_MORPH, M_METAL, M_UPSCALE, M_COUNT };
#define B GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY
#define I GDEXTENSION_VARIANT_TYPE_INT
static const GDExtensionVariantType ARGS[M_COUNT][6] = {
	{ B, I, I, I }, { B, I, I, I }, { B }, { B }, { B, B, B, I, I, I }, { B, B, I }, { B, B, I, I, I },
};
static const int ARG_COUNT[M_COUNT] = { 4, 4, 1, 1, 6, 3, 5 };
static const char *NAMES[M_COUNT] = { "decode_raw", "decode_pnt3", "figure", "unpack_track", "morph", "metal_mask", "upscale" };
static const char *ARG_NAMES[M_COUNT][6] = {
	{ "data", "width", "height", "offset" }, { "data", "size", "width", "height" }, { "data" }, { "data" },
	{ "base", "indices", "data", "offset", "frames", "count" }, { "pixels", "parts", "side" },
	{ "weights", "pixels", "width", "height", "threads" },
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
	case M_METAL: {
		const uint8_t *d1 = bytes_of((const PackedBytes *)args[1], &n1);
		metal_mask(d0, n0, d1, n1, *(const int64_t *)args[2], &b);
		break;
	}
	case M_UPSCALE: {
		const uint8_t *d1 = bytes_of((const PackedBytes *)args[1], &n1);
		upscale(d0, n0, d1, n1, *(const int64_t *)args[2], *(const int64_t *)args[3], *(const int64_t *)args[4], &b);
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
