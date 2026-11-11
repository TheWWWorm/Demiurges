class_name ELLuaCompiler
extends RefCounted
## Lua 4.0 source compiler for custom maps, for platforms without the native
## Lua 4.0.1 compiler (native/el_lua.c; the web build): the map editor saves a
## map's scripts as plain Lua text (.scp), while the shipped maps carry
## compiled chunks. compile() returns the shape ELLuaChunk.parse returns
## (string, number and child-function tables and 32-bit instructions) and
## encode_chunk() writes it as a binary chunk, so ELLuaVM runs both the same
## way. Follows the Lua 4.0 language: `%name` upvalues, `and`/`or` at one
## priority, numeric and `for k, v in t` loops, no `local function`, no
## booleans. Text is read as UTF-8 when it is valid UTF-8, otherwise as the
## originals' Windows-1251.

const MAX_S := 33554431
const MULTI := 255
## Lua 4.0 flushes list items in groups of MAXSTACK / 4 = 62.
const LIST_FLUSH := 62
const KEYWORDS := ["and", "break", "do", "else", "elseif", "end", "for", "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "until", "while"]
## Binary operators: [left priority, right priority].
const PRIORITY := {"+": [5, 5], "-": [5, 5], "*": [6, 6], "/": [6, 6], "^": [9, 8], "..": [4, 3],
	"==": [2, 2], "~=": [2, 2], "<": [2, 2], "<=": [2, 2], ">": [2, 2], ">=": [2, 2], "and": [1, 1], "or": [1, 1]}
const UNARY_PRIORITY := 7
const ARITHMETIC := {"+": 23, "-": 25, "*": 26, "/": 27, "^": 28}
const COMPARE := {"~=": 32, "==": 33, "<": 34, "<=": 35, ">": 36, ">=": 37}
const INVERSE := {32: 33, 33: 32, 34: 37, 37: 34, 35: 36, 36: 35}
## Escape letters (a b f n r t v) and the control codes they stand for.
const ESCAPES := {97: 7, 98: 8, 102: 12, 110: 10, 114: 13, 116: 9, 118: 11}
const BLOCK_END := ["end", "else", "elseif", "until", "eof"]

## One function being generated.
class Func extends RefCounted:
	var parent: Func
	var id := ""
	var code := PackedInt64Array()
	var strings: Array[String] = []
	var string_index: Dictionary = {}
	var numbers := PackedFloat64Array()
	var number_index: Dictionary = {}
	var children: Array[Dictionary] = []
	## Active local names; a local's stack slot is its index here.
	var locals: Array[String] = []
	var upvalues: Array[String] = []
	var level := 0
	var top := 0
	var parameters := 0
	var vararg := 0
	## Enclosing loops: {level, breaks: [jump pcs]}.
	var loops: Array[Dictionary] = []

var error := ""
var _name := ""
var _tokens: Array = []
var _at := 0
var _fs: Func

## Compiles one script. Returns the main function's prototype, or {} with
## `error` set ("name:line: message").
func compile(bytes: PackedByteArray, name: String) -> Dictionary:
	error = ""
	_name = name
	_tokens = _lex(decode(bytes))
	_at = 0
	if not error.is_empty(): return {}
	var body := _block_body()
	if not error.is_empty(): return {}
	if _kind() != "eof": return _fail("'<eof>' expected near '%s'" % _text())
	var result := _function_prototype({"params": [], "vararg": false, "body": body}, name, null)
	result.erase("upvalues")
	_tokens = []
	return result if error.is_empty() else {}

## A compiled prototype as a little-endian Lua 4.0 binary chunk (4-byte
## sizes, 8-byte numbers), the layout ELLuaChunk reads. Strings are written in
## Windows-1251; a character it lacks becomes "?".
static func encode_chunk(prototype: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([27, 76, 117, 97, 64, 1, 4, 4, 4, 32, 6, 9, 8])
	var test := PackedByteArray()
	test.resize(8)
	test.encode_double(0, 314159265.358979)
	out.append_array(test)
	_encode_function(out, prototype)
	return out

static func _encode_function(out: PackedByteArray, f: Dictionary) -> void:
	_encode_string(out, str(f.get("source", "")))
	for value: int in [int(f.get("line", 0)), int(f.parameters)]: _encode_int(out, value)
	out.append(int(f.vararg))
	_encode_int(out, int(f.stack))
	_encode_int(out, 0)
	_encode_int(out, 0)
	_encode_int(out, f.strings.size())
	for text: String in f.strings: _encode_string(out, text)
	_encode_int(out, f.numbers.size())
	for number: float in f.numbers:
		var raw := PackedByteArray()
		raw.resize(8)
		raw.encode_double(0, number)
		out.append_array(raw)
	_encode_int(out, f.children.size())
	for child: Dictionary in f.children: _encode_function(out, child)
	_encode_int(out, f.code.size())
	for word: int in f.code: _encode_int(out, word)

static func _encode_int(out: PackedByteArray, value: int) -> void:
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_u32(0, value & 0xffffffff)
	out.append_array(raw)

static var _cp1251: Dictionary = {}

## Text as Windows-1251 bytes; a character it lacks becomes "?".
static func to_cp1251(text: String) -> PackedByteArray:
	if _cp1251.is_empty():
		for i in 128: _cp1251[ELText.CP1251[i].unicode_at(0)] = 128 + i
	var raw := PackedByteArray()
	raw.resize(text.length())
	for i in text.length():
		var c := text.unicode_at(i)
		raw[i] = c if c < 128 else int(_cp1251.get(c, 63))
	return raw

static func _encode_string(out: PackedByteArray, text: String) -> void:
	var raw := to_cp1251(text)
	raw.append(0)
	_encode_int(out, raw.size())
	out.append_array(raw)

## Script text: UTF-8 when the bytes are valid UTF-8 with non-ASCII letters,
## otherwise Windows-1251 like the originals.
static func decode(bytes: PackedByteArray) -> String:
	var ascii := true
	for value in bytes:
		if value >= 128:
			ascii = false
			break
	if ascii: return bytes.get_string_from_ascii()
	if valid_utf8(bytes): return bytes.get_string_from_utf8()
	var parts := PackedStringArray()
	parts.resize(bytes.size())
	for i in bytes.size():
		var value := bytes[i]
		parts[i] = String.chr(value) if value < 128 else ELText.CP1251[value - 128]
	return "".join(parts)

## Whether `bytes` are well-formed UTF-8 (checked without decoding, which
## would warn on every Windows-1251 letter).
static func valid_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	var size := bytes.size()
	while i < size:
		var lead := bytes[i]
		var extra := 0
		if lead < 0x80: extra = 0
		elif lead >= 0xc2 and lead <= 0xdf: extra = 1
		elif lead >= 0xe0 and lead <= 0xef: extra = 2
		elif lead >= 0xf0 and lead <= 0xf4: extra = 3
		else: return false
		if i + extra >= size and extra > 0: return false
		for k in range(1, extra + 1):
			if bytes[i + k] & 0xc0 != 0x80: return false
		i += extra + 1
	return true

# --- Lexer -------------------------------------------------------------------

func _lex(text: String) -> Array:
	var tokens: Array = []
	var i := 0
	var line := 1
	var size := text.length()
	if text.begins_with("#"):
		while i < size and text.unicode_at(i) != 10: i += 1
	while i < size:
		var c := text.unicode_at(i)
		if c == 10:
			line += 1
			i += 1
		elif c in [32, 9, 13, 11, 12]:
			i += 1
		elif c == 45 and i + 1 < size and text.unicode_at(i + 1) == 45:
			while i < size and text.unicode_at(i) != 10: i += 1
		elif _is_letter(c):
			var start := i
			while i < size and (_is_letter(text.unicode_at(i)) or _is_digit(text.unicode_at(i))): i += 1
			var word := text.substr(start, i - start)
			tokens.append([word if word in KEYWORDS else "name", word, line])
		elif _is_digit(c) or (c == 46 and i + 1 < size and _is_digit(text.unicode_at(i + 1))):
			var start := i
			while i < size and _is_digit(text.unicode_at(i)): i += 1
			if i < size and text.unicode_at(i) == 46 and not (i + 1 < size and text.unicode_at(i + 1) == 46):
				i += 1
				while i < size and _is_digit(text.unicode_at(i)): i += 1
			if i < size and text.unicode_at(i) in [101, 69]:
				i += 1
				if i < size and text.unicode_at(i) in [43, 45]: i += 1
				if i >= size or not _is_digit(text.unicode_at(i)):
					_fail_at(line, "malformed number")
					return []
				while i < size and _is_digit(text.unicode_at(i)): i += 1
			# As in Lua 4.0, a letter right after a number starts the next token ("1or").
			tokens.append(["number", text.substr(start, i - start).to_float(), line])
		elif c == 34 or c == 39:
			var quote := c
			var out := PackedStringArray()
			i += 1
			while true:
				if i >= size or text.unicode_at(i) == 10:
					_fail_at(line, "unfinished string")
					return []
				var d := text.unicode_at(i)
				if d == quote:
					i += 1
					break
				if d != 92:
					out.append(String.chr(d))
					i += 1
					continue
				i += 1
				if i >= size:
					_fail_at(line, "unfinished string")
					return []
				var e := text.unicode_at(i)
				if ESCAPES.has(e):
					out.append(String.chr(ESCAPES[e]))
					i += 1
				elif e == 10:
					out.append("\n")
					line += 1
					i += 1
				elif _is_digit(e):
					var number := 0
					var digits := 0
					while digits < 3 and i < size and _is_digit(text.unicode_at(i)):
						number = number * 10 + text.unicode_at(i) - 48
						i += 1
						digits += 1
					if number > 255:
						_fail_at(line, "escape sequence too large")
						return []
					out.append(String.chr(number) if number < 128 else ELText.CP1251[number - 128])
				else:
					out.append(String.chr(e))
					i += 1
			tokens.append(["string", "".join(out), line])
		elif c == 91 and i + 1 < size and text.unicode_at(i + 1) == 91:
			# Long string; nested [[ ]] pairs as in Lua 4.0; a first newline is skipped.
			var start_line := line
			i += 2
			if i < size and text.unicode_at(i) == 10:
				line += 1
				i += 1
			var start := i
			var depth := 1
			while depth > 0:
				if i >= size:
					_fail_at(start_line, "unfinished long string")
					return []
				var d := text.unicode_at(i)
				if d == 91 and i + 1 < size and text.unicode_at(i + 1) == 91:
					depth += 1
					i += 2
				elif d == 93 and i + 1 < size and text.unicode_at(i + 1) == 93:
					depth -= 1
					i += 2
				else:
					if d == 10: line += 1
					i += 1
			tokens.append(["string", text.substr(start, i - 2 - start), start_line])
		else:
			var two := text.substr(i, 2)
			if text.substr(i, 3) == "...":
				tokens.append(["...", "...", line])
				i += 3
			elif two in ["==", "~=", "<=", ">=", ".."]:
				tokens.append([two, two, line])
				i += 2
			elif "+-*/^<>=(){}[];:,.%".contains(String.chr(c)):
				tokens.append([String.chr(c), String.chr(c), line])
				i += 1
			else:
				_fail_at(line, "unexpected symbol '%s'" % String.chr(c))
				return []
	tokens.append(["eof", "<eof>", line])
	return tokens

static func _is_letter(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95

static func _is_digit(c: int) -> bool:
	return c >= 48 and c <= 57

# --- Parser (to a small syntax tree) -----------------------------------------

func _kind(offset := 0) -> String:
	return _tokens[mini(_at + offset, _tokens.size() - 1)][0]

func _text() -> String:
	return str(_tokens[mini(_at, _tokens.size() - 1)][1])

func _line() -> int:
	return _tokens[mini(_at, _tokens.size() - 1)][2]

func _next() -> Array:
	var token: Array = _tokens[mini(_at, _tokens.size() - 1)]
	if _at < _tokens.size() - 1: _at += 1
	return token

func _accept(kind: String) -> bool:
	if _kind() != kind: return false
	_next()
	return true

func _expect(kind: String, opening := "", line := 0) -> bool:
	if _accept(kind): return true
	if opening.is_empty() or line == _line(): _fail("'%s' expected near '%s'" % [kind, _text()])
	else: _fail("'%s' expected (to close '%s' at line %d) near '%s'" % [kind, opening, line, _text()])
	return false

func _name_token() -> String:
	if _kind() != "name":
		_fail("<name> expected near '%s'" % _text())
		return ""
	return str(_next()[1])

func _block_body() -> Array:
	var body: Array = []
	while error.is_empty() and not _kind() in BLOCK_END:
		if _kind() == "return" or _kind() == "break":
			body.append(_last_statement())
			_accept(";")
			if not _kind() in BLOCK_END: _fail("'end' expected near '%s'" % _text())
			break
		body.append(_statement())
		_accept(";")
	return body

func _last_statement() -> Dictionary:
	var line := _line()
	if _accept("break"): return {"s": "break", "line": line}
	_next()
	var values: Array = []
	if not _kind() in BLOCK_END and _kind() != ";": values = _expression_list()
	return {"s": "return", "values": values, "line": line}

func _statement() -> Dictionary:
	var line := _line()
	match _kind():
		"if":
			_next()
			var clauses: Array = []
			var condition := _expression()
			_expect("then")
			clauses.append([condition, _block_body()])
			var otherwise: Variant = null
			while _kind() == "elseif":
				_next()
				condition = _expression()
				_expect("then")
				clauses.append([condition, _block_body()])
			if _accept("else"): otherwise = _block_body()
			_expect("end", "if", line)
			return {"s": "if", "clauses": clauses, "else": otherwise, "line": line}
		"while":
			_next()
			var condition := _expression()
			_expect("do")
			var body := _block_body()
			_expect("end", "while", line)
			return {"s": "while", "condition": condition, "body": body, "line": line}
		"do":
			_next()
			var body := _block_body()
			_expect("end", "do", line)
			return {"s": "do", "body": body, "line": line}
		"repeat":
			_next()
			var body := _block_body()
			_expect("until", "repeat", line)
			return {"s": "repeat", "body": body, "condition": _expression(), "line": line}
		"for":
			_next()
			var first := _name_token()
			if _accept("="):
				var start := _expression()
				_expect(",")
				var limit := _expression()
				var step: Variant = _expression() if _accept(",") else null
				_expect("do")
				var body := _block_body()
				_expect("end", "for", line)
				return {"s": "fornum", "name": first, "start": start, "limit": limit, "step": step, "body": body, "line": line}
			if not _expect(","): return {}
			var second := _name_token()
			_expect("in")
			var source := _expression()
			_expect("do")
			var body := _block_body()
			_expect("end", "for", line)
			return {"s": "forin", "key": first, "value": second, "source": source, "body": body, "line": line}
		"function":
			_next()
			var path: Array[String] = [_name_token()]
			var method := false
			while _kind() == ".":
				_next()
				path.append(_name_token())
			if _accept(":"):
				path.append(_name_token())
				method = true
			var function := _function_body(method, line)
			return {"s": "function", "path": path, "function": function, "line": line}
		"local":
			_next()
			var names: Array[String] = [_name_token()]
			while _accept(","): names.append(_name_token())
			var values: Array = _expression_list() if _accept("=") else []
			return {"s": "local", "names": names, "values": values, "line": line}
	var target := _suffixed()
	if not error.is_empty(): return {}
	if _kind() in ["=", ","]:
		var targets: Array = [target]
		while _accept(","): targets.append(_suffixed())
		_expect("=")
		for item: Dictionary in targets:
			if not item.get("t") in ["name", "index"]:
				_fail("syntax error near '='")
				return {}
		return {"s": "assign", "targets": targets, "values": _expression_list(), "line": line}
	if not target.get("t") in ["call", "method"]:
		_fail("syntax error near '%s'" % _text())
		return {}
	return {"s": "call", "call": target, "line": line}

func _function_body(method: bool, line: int) -> Dictionary:
	var params: Array[String] = []
	if method: params.append("self")
	var vararg := false
	_expect("(")
	if _kind() != ")":
		while error.is_empty():
			if _accept("..."):
				vararg = true
				break
			params.append(_name_token())
			if not _accept(","): break
	_expect(")")
	var body := _block_body()
	_expect("end", "function", line)
	return {"t": "function", "params": params, "vararg": vararg, "body": body, "line": line}

func _expression_list() -> Array:
	var values: Array = [_expression()]
	while _accept(","): values.append(_expression())
	return values

func _expression(limit := 0) -> Dictionary:
	var left: Dictionary
	if _kind() == "not" or _kind() == "-":
		var operator := str(_next()[0])
		var operand := _expression(UNARY_PRIORITY)
		left = {"t": "not" if operator == "not" else "neg", "e": operand}
	else:
		left = _simple()
	while error.is_empty() and PRIORITY.has(_kind()) and PRIORITY[_kind()][0] > limit:
		var operator := str(_next()[0])
		var right := _expression(PRIORITY[operator][1])
		left = {"t": "bin", "op": operator, "l": left, "r": right}
	return left

func _simple() -> Dictionary:
	match _kind():
		"number": return {"t": "number", "v": float(_next()[1])}
		"string": return {"t": "string", "v": str(_next()[1])}
		"nil":
			_next()
			return {"t": "nil"}
		"{": return _table()
		"function":
			var line := _line()
			_next()
			return _function_body(false, line)
	return _suffixed()

func _suffixed() -> Dictionary:
	var value: Dictionary
	var line := _line()
	if _accept("%"):
		value = {"t": "upvalue", "name": _name_token()}
	elif _accept("("):
		value = _expression()
		_expect(")", "(", line)
		value = {"t": "paren", "e": value}
	elif _kind() == "name":
		value = {"t": "name", "name": _name_token()}
	else:
		_fail("unexpected symbol near '%s'" % _text())
		return {}
	while error.is_empty():
		match _kind():
			".":
				_next()
				value = {"t": "index", "object": value, "key": {"t": "string", "v": _name_token()}}
			"[":
				var open := _line()
				_next()
				var key := _expression()
				_expect("]", "[", open)
				value = {"t": "index", "object": value, "key": key}
			":":
				_next()
				var method := _name_token()
				value = {"t": "method", "object": value, "name": method, "args": _arguments()}
			"(", "string", "{":
				value = {"t": "call", "function": value, "args": _arguments()}
			_:
				return value
	return value

func _arguments() -> Array:
	match _kind():
		"string": return [{"t": "string", "v": str(_next()[1])}]
		"{": return [_table()]
		"(":
			var line := _line()
			_next()
			var values: Array = []
			if _kind() != ")": values = _expression_list()
			_expect(")", "(", line)
			return values
	_fail("function arguments expected near '%s'" % _text())
	return []

func _table() -> Dictionary:
	var line := _line()
	_expect("{")
	var items: Array = []
	while error.is_empty() and _kind() != "}":
		if _kind() == "[":
			var open := _line()
			_next()
			var key := _expression()
			_expect("]", "[", open)
			_expect("=")
			items.append({"key": key, "value": _expression()})
		elif _kind() == "name" and _kind(1) == "=":
			var key := {"t": "string", "v": _name_token()}
			_next()
			items.append({"key": key, "value": _expression()})
		else:
			items.append({"value": _expression()})
		if not _accept(",") and not _accept(";"): break
	_expect("}", "{", line)
	return {"t": "table", "items": items}

# --- Code generation ---------------------------------------------------------

func _function_prototype(node: Dictionary, id: String, parent: Func) -> Dictionary:
	var fs := Func.new()
	fs.parent = parent
	fs.id = id
	var saved := _fs
	_fs = fs
	for param: String in node.params: fs.locals.append(param)
	fs.parameters = node.params.size()
	if node.vararg:
		fs.vararg = 1
		fs.locals.append("arg")
	_grow(fs.locals.size())
	_block(node.body)
	_emit_u(1, fs.parameters + fs.vararg)
	_emit_u(0, 0)
	_fs = saved
	return {"id": id, "source": "@" + _name, "line": int(node.get("line", 0)), "parameters": fs.parameters, "vararg": fs.vararg,
		"stack": mini(maxi(fs.top, fs.parameters + fs.vararg), 250), "strings": fs.strings, "numbers": fs.numbers, "children": fs.children,
		"code": fs.code, "upvalues": fs.upvalues}

func _grow(count: int) -> void:
	_fs.level += count
	_fs.top = maxi(_fs.top, _fs.level)

func _here() -> int:
	return _fs.code.size()

func _emit_u(op: int, u: int) -> int:
	_fs.code.append(op | (u << 6))
	return _fs.code.size() - 1

func _emit_s(op: int, s: int) -> int:
	return _emit_u(op, s + MAX_S)

func _emit_ab(op: int, a: int, b: int) -> int:
	_fs.code.append(op | (b << 6) | (a << 15))
	return _fs.code.size() - 1

func _jump(op: int) -> int:
	return _emit_s(op, 0)

func _patch(jumps: Array, target: int) -> void:
	for pc: int in jumps:
		_fs.code[pc] = (_fs.code[pc] & 63) | ((target - (pc + 1) + MAX_S) << 6)

func _string_constant(text: String) -> int:
	if not _fs.string_index.has(text):
		_fs.string_index[text] = _fs.strings.size()
		_fs.strings.append(text)
	return _fs.string_index[text]

func _number_constant(value: float) -> int:
	if not _fs.number_index.has(value):
		_fs.number_index[value] = _fs.numbers.size()
		_fs.numbers.append(value)
	return _fs.number_index[value]

func _pop(count: int) -> void:
	if count <= 0: return
	_emit_u(5, count)
	_fs.level -= count

func _local_slot(name: String) -> int:
	return _fs.locals.rfind(name)

func _outer_local(name: String) -> bool:
	var outer := _fs.parent
	while outer != null:
		if outer.locals.has(name): return true
		outer = outer.parent
	return false

func _block(body: Array) -> void:
	var active := _fs.locals.size()
	for statement: Dictionary in body:
		if not error.is_empty(): return
		_statement_code(statement)
	var extra := _fs.locals.size() - active
	_pop(extra)
	_fs.locals.resize(active)

func _statement_code(node: Dictionary) -> void:
	if node.is_empty(): return
	match node.s:
		"local":
			_values(node.values, node.names.size())
			for name: String in node.names: _fs.locals.append(name)
		"assign": _assign(node)
		"call": _call(node.call, 0)
		"do": _block(node.body)
		"if":
			var exits: Array = []
			var clauses: Array = node.clauses
			for i in clauses.size():
				var falses := _condition(clauses[i][0], false)
				_block(clauses[i][1])
				if i < clauses.size() - 1 or node.else != null: exits.append(_jump(42))
				_patch(falses, _here())
			if node.else != null: _block(node.else)
			_patch(exits, _here())
		"while":
			var start := _here()
			var falses := _condition(node.condition, false)
			_fs.loops.append({"level": _fs.level, "breaks": []})
			_block(node.body)
			var back := _jump(42)
			_patch([back], start)
			_patch(falses, _here())
			_patch(_fs.loops.pop_back().breaks, _here())
		"repeat":
			var start := _here()
			_fs.loops.append({"level": _fs.level, "breaks": []})
			_block(node.body)
			_patch(_condition(node.condition, false), start)
			_patch(_fs.loops.pop_back().breaks, _here())
		"fornum":
			var level := _fs.level
			_fs.loops.append({"level": level, "breaks": []})
			_value(node.start)
			_value(node.limit)
			if node.step != null: _value(node.step)
			else:
				_emit_s(6, 1)
				_grow(1)
			var prepare := _jump(44)
			_fs.locals.append_array([node.name, "(limit)", "(step)"])
			var body := _here()
			_block(node.body)
			_patch([_jump(45)], body)
			_patch([prepare], _here())
			_fs.locals.resize(_fs.locals.size() - 3)
			_fs.level = level
			_patch(_fs.loops.pop_back().breaks, _here())
		"forin":
			var level := _fs.level
			_fs.loops.append({"level": level, "breaks": []})
			_value(node.source)
			var prepare := _jump(46)
			_grow(2)
			_fs.locals.append_array(["(table)", node.key, node.value])
			var body := _here()
			_block(node.body)
			_patch([_jump(47)], body)
			_patch([prepare], _here())
			_fs.locals.resize(_fs.locals.size() - 3)
			_fs.level = level
			_patch(_fs.loops.pop_back().breaks, _here())
		"function":
			var path: Array[String] = node.path
			if path.size() == 1:
				_closure(node.function)
				_store_name(path[0])
			else:
				_load_name(path[0])
				for i in range(1, path.size() - 1): _emit_u(14, _string_constant(path[i]))
				_emit_u(7, _string_constant(path[-1]))
				_grow(1)
				_closure(node.function)
				_emit_ab(20, 3, 3)
				_fs.level -= 3
		"return":
			var values: Array = node.values
			var base := _fs.level
			if values.size() == 1 and values[0].t in ["call", "method"]:
				_call_setup(values[0])
				_emit_ab(3, base, base)
				_fs.level = base
			else:
				_values(values, -1)
				_emit_u(1, base)
				_fs.level = base
		"break":
			if _fs.loops.is_empty():
				_fail_at(node.line, "no loop to break")
				return
			var loop: Dictionary = _fs.loops[-1]
			var extra: int = _fs.level - int(loop.level)
			if extra > 0: _emit_u(5, extra)
			loop.breaks.append(_jump(42))

func _assign(node: Dictionary) -> void:
	var targets: Array = node.targets
	var slots: Array[int] = []
	for target: Dictionary in targets:
		if target.t == "index":
			_value(target.object)
			_value(target.key)
			slots.append(_fs.level - 2)
		else:
			if target.t == "name" and _local_slot(target.name) < 0 and _outer_local(target.name):
				_fail_at(node.line, "cannot access a variable in outer scope: " + str(target.name))
				return
			slots.append(-1)
	_values(node.values, targets.size())
	var leftover := 0
	for i in range(targets.size() - 1, -1, -1):
		var target: Dictionary = targets[i]
		if target.t == "index":
			# Table and key right under the value are popped with it; pairs
			# further down stay until every value is stored.
			var a := _fs.level - slots[i]
			_emit_ab(20, a, 3 if a == 3 else 1)
			_fs.level -= 3 if a == 3 else 1
			if a != 3: leftover += 2
		else:
			_store_name(target.name)
	_pop(leftover)

func _store_name(name: String) -> void:
	var slot := _local_slot(name)
	if slot >= 0: _emit_u(18, slot)
	else: _emit_u(19, _string_constant(name))
	_fs.level -= 1

func _load_name(name: String) -> void:
	var slot := _local_slot(name)
	if slot >= 0: _emit_u(11, slot)
	else:
		if _outer_local(name): _fail("cannot access a variable in outer scope: " + name)
		_emit_u(12, _string_constant(name))
	_grow(1)

## Pushes `values` adjusted to `wanted` values (-1: all, open last call).
func _values(values: Array, wanted: int) -> void:
	if values.is_empty():
		if wanted > 0:
			_emit_u(4, wanted)
			_grow(wanted)
		return
	for i in values.size() - 1: _value(values[i])
	var last: Dictionary = values[-1]
	var before := values.size() - 1
	if last.t in ["call", "method"]:
		if wanted < 0:
			_call(last, MULTI)
			return
		var results := wanted - before
		_call(last, maxi(results, 0))
		if results < 0: _pop(-results)
		return
	_value(last)
	if wanted < 0: return
	var missing := wanted - values.size()
	if missing > 0:
		_emit_u(4, missing)
		_grow(missing)
	elif missing < 0: _pop(-missing)

## Pushes exactly one value.
func _value(node: Dictionary) -> void:
	if not error.is_empty() or node.is_empty(): return
	match node.t:
		"nil":
			_emit_u(4, 1)
			_grow(1)
		"number": _push_number(node.v)
		"string":
			_emit_u(7, _string_constant(node.v))
			_grow(1)
		"name": _load_name(node.name)
		"upvalue":
			var index := _fs.upvalues.find(node.name)
			if _fs.parent == null:
				_fail("cannot access upvalue in main: " + str(node.name))
				return
			if index < 0:
				index = _fs.upvalues.size()
				_fs.upvalues.append(node.name)
			_emit_u(10, index)
			_grow(1)
		"paren": _value(node.e)
		"index":
			_value(node.object)
			var key: Dictionary = node.key
			if key.t == "string": _emit_u(14, _string_constant(key.v))
			elif key.t == "name" and _local_slot(key.name) >= 0: _emit_u(15, _local_slot(key.name))
			else:
				_value(key)
				_emit_u(13, 0)
				_fs.level -= 1
		"call", "method": _call(node, 1)
		"function": _closure(node)
		"table": _table_code(node)
		"not":
			_value(node.e)
			_emit_u(31, 0)
		"neg":
			if node.e.t == "number": _push_number(-float(node.e.v))
			else:
				_value(node.e)
				_emit_u(30, 0)
		"bin":
			var operator: String = node.op
			if operator == "and" or operator == "or":
				_value(node.l)
				var skip := _jump(41 if operator == "and" else 40)
				_fs.level -= 1
				_value(node.r)
				_patch([skip], _here())
			elif COMPARE.has(operator):
				_value(node.l)
				_value(node.r)
				_emit_s(COMPARE[operator], 1)
				_fs.level -= 2
				_emit_u(43, 0)
				_emit_s(6, 1)
				_grow(1)
			else:
				_value(node.l)
				_value(node.r)
				if operator == "..": _emit_u(29, 2)
				else: _emit_u(ARITHMETIC[operator], 0)
				_fs.level -= 1

func _push_number(value: float) -> void:
	if value == floorf(value) and absf(value) <= MAX_S: _emit_s(6, int(value))
	elif value < 0: _emit_u(9, _number_constant(-value))
	else: _emit_u(8, _number_constant(value))
	_grow(1)

## Jumps taken when `node`'s truth equals `when`; falls through otherwise.
func _condition(node: Dictionary, when: bool) -> Array:
	if not error.is_empty() or node.is_empty(): return []
	match node.t:
		"paren": return _condition(node.e, when)
		"not": return _condition(node.e, not when)
		"nil": return [_jump(42)] if not when else []
		"number", "string", "function", "table":
			if node.t in ["number", "string"]: return [_jump(42)] if when else []
		"bin":
			var operator: String = node.op
			if COMPARE.has(operator):
				_value(node.l)
				_value(node.r)
				var op: int = COMPARE[operator]
				var jump := _jump(op if when else INVERSE[op])
				_fs.level -= 2
				return [jump]
			if operator == "and":
				if not when:
					var left := _condition(node.l, false)
					return left + _condition(node.r, false)
				var skip := _condition(node.l, false)
				var taken := _condition(node.r, true)
				_patch(skip, _here())
				return taken
			if operator == "or":
				if when:
					var left := _condition(node.l, true)
					return left + _condition(node.r, true)
				var skip := _condition(node.l, true)
				var taken := _condition(node.r, false)
				_patch(skip, _here())
				return taken
	_value(node)
	var jump := _jump(38 if when else 39)
	_fs.level -= 1
	return [jump]

## Pushes the function and its arguments (the last one open).
func _call_setup(node: Dictionary) -> int:
	var base := _fs.level
	if node.t == "method":
		_value(node.object)
		_emit_u(16, _string_constant(node.name))
		_grow(1)
	else:
		_value(node.function)
	_values(node.args, -1)
	return base

func _call(node: Dictionary, results: int) -> void:
	var base := _call_setup(node)
	_emit_ab(2, base, results)
	_fs.level = base + (0 if results == MULTI else results)
	_fs.top = maxi(_fs.top, _fs.level)

func _closure(node: Dictionary) -> void:
	var index := _fs.children.size()
	var child := _function_prototype(node, _fs.id + "/" + str(index), _fs)
	if not error.is_empty(): return
	_fs.children.append(child)
	var upvalues: Array = child.upvalues
	child.erase("upvalues")
	for name: String in upvalues:
		var slot := _local_slot(name)
		if slot >= 0: _emit_u(11, slot)
		else: _emit_u(12, _string_constant(name))
		_grow(1)
	_emit_ab(48, index, upvalues.size())
	_fs.level -= upvalues.size()
	_grow(1)

func _table_code(node: Dictionary) -> void:
	var items: Array = node.items
	_emit_u(17, items.size())
	_grow(1)
	var listed := 0
	var pending_list := 0
	var pending_pairs := 0
	var list_closed := false
	for item: Dictionary in items:
		if item.has("key"):
			if pending_list > 0:
				_set_list(listed, pending_list)
				pending_list = 0
				list_closed = true
			_value(item.key)
			_value(item.value)
			pending_pairs += 1
			if pending_pairs == LIST_FLUSH / 2:
				_set_map(pending_pairs)
				pending_pairs = 0
		else:
			if list_closed and listed % LIST_FLUSH != 0:
				_fail("table constructor mixes list and record items")
				return
			if pending_pairs > 0:
				_set_map(pending_pairs)
				pending_pairs = 0
			_value(item.value)
			listed += 1
			pending_list += 1
			if pending_list == LIST_FLUSH:
				_set_list(listed, pending_list)
				pending_list = 0
	if pending_list > 0: _set_list(listed, pending_list)
	if pending_pairs > 0: _set_map(pending_pairs)

func _set_list(listed: int, count: int) -> void:
	_emit_ab(21, (listed - count) / LIST_FLUSH, count)
	_fs.level -= count

func _set_map(pairs: int) -> void:
	_emit_u(22, pairs)
	_fs.level -= 2 * pairs

func _fail(message: String) -> Dictionary:
	_fail_at(_line() if not _tokens.is_empty() else 0, message)
	return {}

func _fail_at(line: int, message: String) -> void:
	if error.is_empty(): error = "%s:%d: %s" % [_name, line, message]
