/*
 * Local Discord IPC for the game's Discord activity (GDExtension, C).
 *
 * Opens the Discord desktop client's local pipe (Windows) or socket (Linux,
 * macOS) and moves raw bytes; the framing and the activity itself are done
 * in GDScript (src/content/discord_presence.gd). Nothing here blocks: reads
 * return what has arrived, writes what fits. No network access.
 *
 * Exposed as static methods of the class ELDiscordIpc:
 *   open(path: String) -> int        a handle, or -1
 *   close(handle: int) -> int        0
 *   is_open(handle: int) -> int      1 while the connection lasts
 *   read(handle: int) -> PackedByteArray
 *                                    the bytes waiting (may be empty); the
 *                                    handle closes when the other end does
 *   write(handle: int, data: PackedByteArray) -> int
 *                                    bytes written, 0 when it would block,
 *                                    -1 when the connection is gone
 * Handles are used from the main thread only.
 */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "include/gdextension_interface.h"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define EL_EXPORT __declspec(dllexport)
#else
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#define EL_EXPORT __attribute__((visibility("default")))
#endif

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

#define SLOTS 4
#define CHUNK 65536

#if defined(_WIN32)
typedef HANDLE Conn;
#define NO_CONN INVALID_HANDLE_VALUE
#else
typedef int Conn;
#define NO_CONN (-1)
#endif

static Conn conns[SLOTS] = { NO_CONN, NO_CONN, NO_CONN, NO_CONN };

static void conn_close(Conn *c) {
	if (*c == NO_CONN) return;
#if defined(_WIN32)
	CloseHandle(*c);
#else
	close(*c);
#endif
	*c = NO_CONN;
}

static Conn *conn_of(int64_t handle) {
	if (handle < 0 || handle >= SLOTS || conns[handle] == NO_CONN) return NULL;
	return &conns[handle];
}

static int64_t native_open(const char *path) {
	int slot = -1;
	for (int i = 0; i < SLOTS; i++) {
		if (conns[i] == NO_CONN) {
			slot = i;
			break;
		}
	}
	if (slot < 0 || !path || !path[0]) return -1;
#if defined(_WIN32)
	HANDLE h = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
	if (h == INVALID_HANDLE_VALUE) return -1;
	/* Non-blocking, so a stalled client never stalls a game frame. */
	DWORD mode = PIPE_READMODE_BYTE | PIPE_NOWAIT;
	if (!SetNamedPipeHandleState(h, &mode, NULL, NULL)) {
		CloseHandle(h);
		return -1;
	}
	conns[slot] = h;
#else
	struct sockaddr_un address;
	size_t length = strlen(path);
	if (length >= sizeof(address.sun_path)) return -1;
	memset(&address, 0, sizeof(address));
	address.sun_family = AF_UNIX;
	memcpy(address.sun_path, path, length + 1);
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) return -1;
	fcntl(fd, F_SETFD, FD_CLOEXEC);
	if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
		close(fd);
		return -1;
	}
	int flags = fcntl(fd, F_GETFL, 0);
	if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
		close(fd);
		return -1;
	}
#if defined(SO_NOSIGPIPE)
	int one = 1;
	setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
	conns[slot] = fd;
#endif
	return slot;
}

/* Fills `buffer` with up to CHUNK waiting bytes; returns the count. */
static int64_t native_read(int64_t handle, uint8_t *buffer) {
	Conn *c = conn_of(handle);
	if (!c) return 0;
#if defined(_WIN32)
	DWORD available = 0, count = 0;
	if (!PeekNamedPipe(*c, NULL, 0, NULL, &available, NULL)) {
		conn_close(c);
		return 0;
	}
	if (available == 0) return 0;
	if (!ReadFile(*c, buffer, available > CHUNK ? CHUNK : available, &count, NULL)) {
		if (GetLastError() != ERROR_NO_DATA) conn_close(c);
		return 0;
	}
	return count;
#else
	ssize_t count = recv(*c, buffer, CHUNK, 0);
	if (count <= 0) {
		if (count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) conn_close(c);
		return 0;
	}
	return count;
#endif
}

static int64_t native_write(int64_t handle, const uint8_t *data, int64_t size) {
	Conn *c = conn_of(handle);
	if (!c || size > CHUNK) return -1;
	if (size <= 0) return 0;
#if defined(_WIN32)
	DWORD count = 0;
	if (!WriteFile(*c, data, (DWORD)size, &count, NULL)) {
		if (GetLastError() == ERROR_NO_DATA) return 0;
		conn_close(c);
		return -1;
	}
	return count;
#else
	ssize_t count = send(*c, data, (size_t)size, MSG_NOSIGNAL);
	if (count < 0) {
		if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return 0;
		conn_close(c);
		return -1;
	}
	return count;
#endif
}

/* ------------------------------------------------------------ Godot binding */

typedef struct { _Alignas(8) uint8_t data[16]; } PackedBytes;
typedef struct { _Alignas(8) uint8_t data[8]; } Name;
typedef struct { _Alignas(8) uint8_t data[8]; } Text;

static GDExtensionInterfaceGetProcAddress get_proc;
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceVariantGetType variant_get_type;
static GDExtensionInterfacePackedByteArrayOperatorIndex pba_index;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst pba_index_const;
static GDExtensionInterfaceStringNameNewWithLatin1Chars string_name_new;
static GDExtensionInterfaceStringNewWithLatin1Chars string_new;
static GDExtensionInterfaceStringToUtf8Chars string_to_utf8;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionPtrConstructor pba_new;
static GDExtensionPtrDestructor pba_free, string_name_free, string_free;
static GDExtensionPtrBuiltInMethod pba_size, pba_resize;
static GDExtensionTypeFromVariantConstructorFunc int_from_variant, pba_from_variant, string_from_variant;
static GDExtensionVariantFromTypeConstructorFunc variant_from_int, variant_from_pba;

static int64_t bytes_size(const PackedBytes *p) {
	int64_t n = 0;
	pba_size((GDExtensionTypePtr)p, NULL, &n, 0);
	return n;
}

/* Copies a Godot String path into a NUL-terminated UTF-8 buffer. */
static void path_of(GDExtensionConstStringPtr text, char *out, int64_t room) {
	int64_t n = string_to_utf8(text, NULL, 0);
	if (n <= 0 || n >= room) {
		out[0] = 0;
		return;
	}
	string_to_utf8(text, out, n);
	out[n] = 0;
}

/* Builds `result` (an uninitialised PackedByteArray) from the waiting bytes. */
static void read_into(int64_t handle, PackedBytes *result) {
	pba_new(result, NULL);
	uint8_t *buffer = (uint8_t *)malloc(CHUNK);
	if (!buffer) return;
	int64_t count = native_read(handle, buffer);
	if (count > 0) {
		const GDExtensionConstTypePtr args[1] = { &count };
		int64_t err = 0;
		pba_resize(result, args, &err, 1);
		uint8_t *to = err == 0 ? pba_index(result, 0) : NULL;
		if (to) memcpy(to, buffer, (size_t)count);
	}
	free(buffer);
}

static int64_t write_from(int64_t handle, const PackedBytes *data) {
	int64_t n = bytes_size(data);
	if (n <= 0) return conn_of(handle) ? 0 : -1;
	return native_write(handle, pba_index_const((GDExtensionConstTypePtr)data, 0), n);
}

enum { M_OPEN, M_CLOSE, M_IS_OPEN, M_READ, M_WRITE, M_COUNT };

static const GDExtensionVariantType ARGS[M_COUNT][2] = {
	{ GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_NIL },
	{ GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL },
	{ GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL },
	{ GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_NIL },
	{ GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY },
};
static const int ARG_COUNT[M_COUNT] = { 1, 1, 1, 1, 2 };

static int64_t run_int(int m, const void *a0, const void *a1) {
	char path[1024];
	switch (m) {
	case M_OPEN:
		path_of((GDExtensionConstStringPtr)a0, path, sizeof(path));
		return native_open(path);
	case M_CLOSE: {
		Conn *c = conn_of(*(const int64_t *)a0);
		if (c) conn_close(c);
		return 0;
	}
	case M_IS_OPEN:
		return conn_of(*(const int64_t *)a0) ? 1 : 0;
	case M_WRITE:
		return write_from(*(const int64_t *)a0, (const PackedBytes *)a1);
	}
	return -1;
}

static void ptrcall(void *method, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	(void)instance;
	int m = (int)(intptr_t)method;
	if (m == M_READ) {
		/* `ret` holds a constructed PackedByteArray: replace it. */
		pba_free(ret);
		read_into(*(const int64_t *)args[0], (PackedBytes *)ret);
		return;
	}
	*(int64_t *)ret = run_int(m, args[0], ARG_COUNT[m] > 1 ? args[1] : NULL);
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
	for (int i = 0; i < ARG_COUNT[m]; i++) {
		if (variant_get_type(args[i]) != ARGS[m][i]) {
			error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
			error->argument = i;
			error->expected = ARGS[m][i];
			return;
		}
	}
	int64_t handle = 0;
	if (m == M_OPEN) {
		Text path;
		string_from_variant(&path, (GDExtensionVariantPtr)args[0]);
		int64_t result = run_int(m, &path, NULL);
		string_free(&path);
		variant_from_int(ret, &result);
		return;
	}
	int_from_variant(&handle, (GDExtensionVariantPtr)args[0]);
	if (m == M_READ) {
		PackedBytes out;
		read_into(handle, &out);
		variant_from_pba(ret, &out);
		pba_free(&out);
		return;
	}
	int64_t result;
	if (m == M_WRITE) {
		PackedBytes data;
		pba_from_variant(&data, (GDExtensionVariantPtr)args[1]);
		result = write_from(handle, &data);
		pba_free(&data);
	} else {
		result = run_int(m, &handle, NULL);
	}
	variant_from_int(ret, &result);
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

static GDExtensionClassMethodArgumentMetadata meta_of(GDExtensionVariantType type) {
	return type == GDEXTENSION_VARIANT_TYPE_INT ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
}

static void add_method(int m, const char *name, const char *arg0, const char *arg1, GDExtensionVariantType ret) {
	Name method, a0, a1;
	string_name_new(&method, name, 0);
	string_name_new(&a0, arg0, 0);
	string_name_new(&a1, arg1 ? arg1 : "", 0);
	GDExtensionPropertyInfo args[2] = { info(ARGS[m][0], &a0), info(ARGS[m][1], &a1) };
	GDExtensionClassMethodArgumentMetadata meta[2] = { meta_of(ARGS[m][0]), meta_of(ARGS[m][1]) };
	GDExtensionPropertyInfo ret_info = info(ret, &empty_name);
	GDExtensionClassMethodInfo mi;
	memset(&mi, 0, sizeof(mi));
	mi.name = &method;
	mi.method_userdata = (void *)(intptr_t)m;
	mi.call_func = call;
	mi.ptrcall_func = ptrcall;
	mi.method_flags = GDEXTENSION_METHOD_FLAG_STATIC;
	mi.has_return_value = 1;
	mi.return_value_info = &ret_info;
	mi.return_value_metadata = meta_of(ret);
	mi.argument_count = (uint32_t)ARG_COUNT[m];
	mi.arguments_info = args;
	mi.arguments_metadata = meta;
	register_method(library, &class_name, &mi);
	string_name_free(&method);
	string_name_free(&a0);
	string_name_free(&a1);
}

static void free_instance(void *userdata, GDExtensionClassInstancePtr instance) {
	(void)userdata;
	(void)instance;
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	string_name_new(&class_name, "ELDiscordIpc", 0);
	string_name_new(&parent_name, "Object", 0);
	string_name_new(&empty_name, "", 0);
	string_new(&empty_text, "");
	GDExtensionClassCreationInfo6 ci;
	memset(&ci, 0, sizeof(ci));
	ci.is_abstract = 1;
	ci.is_exposed = 1;
	ci.free_instance_func = free_instance;
	register_class(library, &class_name, &parent_name, &ci);
	add_method(M_OPEN, "open", "path", NULL, GDEXTENSION_VARIANT_TYPE_INT);
	add_method(M_CLOSE, "close", "handle", NULL, GDEXTENSION_VARIANT_TYPE_INT);
	add_method(M_IS_OPEN, "is_open", "handle", NULL, GDEXTENSION_VARIANT_TYPE_INT);
	add_method(M_READ, "read", "handle", NULL, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	add_method(M_WRITE, "write", "handle", "data", GDEXTENSION_VARIANT_TYPE_INT);
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	for (int i = 0; i < SLOTS; i++) conn_close(&conns[i]);
	unregister_class(library, &class_name);
	string_name_free(&class_name);
	string_name_free(&parent_name);
	string_name_free(&empty_name);
	string_free(&empty_text);
}

#define LOAD(var, type, name) var = (type)get_proc(name); if (!var) return 0

EL_EXPORT GDExtensionBool el_discord_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	get_proc = p_get_proc_address;
	library = p_library;
	LOAD(variant_get_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
	LOAD(pba_index, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
	LOAD(pba_index_const, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
	LOAD(string_name_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
	LOAD(string_new, GDExtensionInterfaceStringNewWithLatin1Chars, "string_new_with_latin1_chars");
	LOAD(string_to_utf8, GDExtensionInterfaceStringToUtf8Chars, "string_to_utf8_chars");
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
	pba_new = get_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
	pba_free = get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	string_name_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
	string_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
	Name size_name, resize_name;
	string_name_new(&size_name, "size", 0);
	string_name_new(&resize_name, "resize", 0);
	pba_size = get_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &size_name, 3173160232);
	pba_resize = get_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &resize_name, 848867239);
	string_name_free(&size_name);
	string_name_free(&resize_name);
	int_from_variant = get_to_type(GDEXTENSION_VARIANT_TYPE_INT);
	pba_from_variant = get_to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	string_from_variant = get_to_type(GDEXTENSION_VARIANT_TYPE_STRING);
	variant_from_int = get_from_type(GDEXTENSION_VARIANT_TYPE_INT);
	variant_from_pba = get_from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!pba_new || !pba_free || !string_name_free || !string_free || !pba_size || !pba_resize
			|| !int_from_variant || !pba_from_variant || !string_from_variant || !variant_from_int || !variant_from_pba)
		return 0;
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = NULL;
	r_initialization->initialize = initialize;
	r_initialization->deinitialize = deinitialize;
	return 1;
}
