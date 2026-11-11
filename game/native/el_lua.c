/*
 * Lua 4.0 compiler for custom maps' scripts (GDExtension, C).
 *
 * The Etherlords II map editor saves a map's scripts as Lua 4.0 source text;
 * the shipped maps carry compiled chunks. This library builds the unmodified
 * Lua 4.0.1 core (lua40/, see lua40/COPYRIGHT) and returns the same binary
 * chunk luac 4.0 writes, which ELLuaChunk reads like the shipped ones.
 * The chunk writer below follows luac's dump.c (Lua 4.0.1, same copyright).
 * Nothing is executed: the source is only parsed.
 *
 * Exposed as a static method of the class ELNativeLua:
 *   compile(source, name) -> PackedByteArray
 *       the binary chunk (starting with ESC "Lua"), or, when the source does
 *       not compile, the parser's error message as text.
 */
#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "include/gdextension_interface.h"

#include "lua40/lapi.c"
#include "lua40/lcode.c"
#include "lua40/ldebug.c"
#include "lua40/ldo.c"
#include "lua40/lfunc.c"
#include "lua40/lgc.c"
#include "lua40/llex.c"
/* The sources are built as one unit: llex.c's private macros end here. */
#undef next
#undef save
#undef save_and_next
#undef checkbuffer
#undef EXTRABUFF
#undef MAXSRC
#include "lua40/lmem.c"
#include "lua40/lobject.c"
#include "lua40/lparser.c"
#include "lua40/lstate.c"
#include "lua40/lstring.c"
#include "lua40/ltable.c"
#include "lua40/ltm.c"
#include "lua40/lundump.c"
/* ldo.c and lvm.c each define it. */
#undef EXTRA_STACK
#include "lua40/lvm.c"
#include "lua40/lzio.c"

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
	if (b->failed || n <= 0) return;
	if (b->size + n > b->capacity) {
		int64_t want = b->capacity ? b->capacity * 2 : 4096;
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

/* ------------------------------------------------------------ chunk writer */

static void dump_int(Buffer *b, int x) { put(b, &x, sizeof(x)); }
static void dump_size(Buffer *b, size_t x) { put(b, &x, sizeof(x)); }
static void dump_byte(Buffer *b, int x) { uint8_t v = (uint8_t)x; put(b, &v, 1); }

static void dump_string(Buffer *b, const TString *s) {
	if (s == NULL) {
		dump_size(b, 0);
		return;
	}
	size_t size = s->len + 1; /* the trailing zero is included */
	dump_size(b, size);
	put(b, s->str, (int64_t)size);
}

static void dump_function(Buffer *b, const Proto *f, int depth) {
	if (depth > 200) {
		b->failed = 1;
		return;
	}
	dump_string(b, f->source);
	dump_int(b, f->lineDefined);
	dump_int(b, f->numparams);
	dump_byte(b, f->is_vararg);
	dump_int(b, f->maxstacksize);
	dump_int(b, f->nlocvars);
	for (int i = 0; i < f->nlocvars; i++) {
		dump_string(b, f->locvars[i].varname);
		dump_int(b, f->locvars[i].startpc);
		dump_int(b, f->locvars[i].endpc);
	}
	dump_int(b, f->nlineinfo);
	put(b, f->lineinfo, (int64_t)sizeof(*f->lineinfo) * f->nlineinfo);
	dump_int(b, f->nkstr);
	for (int i = 0; i < f->nkstr; i++) dump_string(b, f->kstr[i]);
	dump_int(b, f->nknum);
	put(b, f->knum, (int64_t)sizeof(*f->knum) * f->nknum);
	dump_int(b, f->nkproto);
	for (int i = 0; i < f->nkproto; i++) dump_function(b, f->kproto[i], depth + 1);
	dump_int(b, f->ncode);
	put(b, f->code, (int64_t)sizeof(*f->code) * f->ncode);
}

static void dump_header(Buffer *b) {
	dump_byte(b, ID_CHUNK);
	put(b, SIGNATURE, 3);
	dump_byte(b, VERSION);
	dump_byte(b, luaU_endianess());
	dump_byte(b, sizeof(int));
	dump_byte(b, sizeof(size_t));
	dump_byte(b, sizeof(Instruction));
	dump_byte(b, SIZE_INSTRUCTION);
	dump_byte(b, SIZE_OP);
	dump_byte(b, SIZE_B);
	dump_byte(b, sizeof(Number));
	Number test = TEST_NUMBER;
	put(b, &test, sizeof(test));
}

/* ---------------------------------------------------------------- compiling */

/* The parser's message, kept by the state's _ERRORMESSAGE handler. */
static _Thread_local char message_text[512];

static int keep_message(lua_State *L) {
	const char *s = lua_tostring(L, 1);
	if (s) {
		strncpy(message_text, s, sizeof(message_text) - 1);
		message_text[sizeof(message_text) - 1] = 0;
	}
	return 0;
}

typedef struct {
	ZIO *z;
	Buffer *out;
} Job;

static void parse_and_dump(lua_State *L, void *ud) {
	Job *job = (Job *)ud;
	Proto *f = luaY_parser(L, job->z);
	dump_header(job->out);
	dump_function(job->out, f, 0);
}

static void compile(const char *source, int64_t size, const char *name, int64_t name_size, Buffer *out) {
	char chunk_name[256];
	int64_t length = name_size < (int64_t)sizeof(chunk_name) - 2 ? name_size : (int64_t)sizeof(chunk_name) - 2;
	chunk_name[0] = '@';
	if (length > 0) memcpy(chunk_name + 1, name, (size_t)length);
	chunk_name[length + 1] = 0;
	message_text[0] = 0;
	if (size < 0 || size > 16 * 1024 * 1024) {
		const char *text = "script too large";
		put(out, text, (int64_t)strlen(text));
		return;
	}
	lua_State *L = lua_open(0);
	if (L == NULL) {
		out->failed = 1;
		return;
	}
	lua_register(L, LUA_ERRORMESSAGE, keep_message);
	ZIO z;
	zmopen(&z, source ? source : "", (size_t)size, chunk_name);
	Job job = { &z, out };
	int status = luaD_runprotected(L, parse_and_dump, &job);
	lua_close(L);
	if (status != 0 || out->failed) {
		out->size = 0;
		out->failed = 0;
		const char *text = message_text[0] ? message_text : "script does not compile";
		put(out, text, (int64_t)strlen(text));
	}
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

enum { M_COMPILE, M_COUNT };
#define B GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY
#define I GDEXTENSION_VARIANT_TYPE_INT
static const GDExtensionVariantType ARGS[M_COUNT][6] = { { B, B } };
static const int ARG_COUNT[M_COUNT] = { 2 };
static const char *NAMES[M_COUNT] = { "compile" };
static const char *ARG_NAMES[M_COUNT][6] = { { "source", "name" } };

/* Runs method `m` on arguments already in their own types. */
static void run(int m, const void *const *args, PackedBytes *result) {
	(void)m;
	Buffer b = { 0 };
	int64_t n0 = 0, n1 = 0;
	const uint8_t *d0 = bytes_of((const PackedBytes *)args[0], &n0);
	const uint8_t *d1 = bytes_of((const PackedBytes *)args[1], &n1);
	compile((const char *)d0, n0, (const char *)d1, n1, &b);
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
	string_name_new(&class_name, "ELNativeLua", 0);
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

EL_EXPORT GDExtensionBool el_lua_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
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
