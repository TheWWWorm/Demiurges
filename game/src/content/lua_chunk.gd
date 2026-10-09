class_name ELLuaChunk
extends RefCounted
## Lua 4.0 binary chunks, as shipped in Etherlords II's scripts archive.
## Layout reference: Lua 4.0 lundump.c; see THIRD_PARTY_NOTICES.md.
var error := ""
var bytes := PackedByteArray()
var offset := 0
var size_width := 4
var instruction_width := 4
var number_width := 8
var functions := 0

func parse(data: PackedByteArray, name := "chunk") -> Dictionary:
	error = ""
	bytes = data
	offset = 0
	functions = 0
	if bytes.size() < 21 or bytes.size() > 16777216: return _fail("Invalid script size.")
	if _take(6) != PackedByteArray([27, 76, 117, 97, 64, 1]): return _fail("Expected little-endian Lua 4.0 bytecode.")
	var int_width := _uint(1)
	size_width = _uint(1)
	instruction_width = _uint(1)
	var bits := _uint(1)
	var op_bits := _uint(1)
	var b_bits := _uint(1)
	number_width = _uint(1)
	if int_width != 4 or size_width not in [4, 8] or instruction_width not in [4, 8] or number_width not in [4, 8] or bits != 32 or op_bits != 6 or b_bits != 9:
		return _fail("Unsupported Lua bytecode layout.")
	if absi(int(_number()) - 314159265) > 16: return _fail("Unsupported Lua number format.")
	var result := _function(name, 0)
	if offset != bytes.size() and error.is_empty(): _fail("Trailing bytes in script.")
	bytes = PackedByteArray()
	return result if error.is_empty() else {}

func _function(name: String, depth: int) -> Dictionary:
	functions += 1
	if depth > 64 or functions > 16384: return _fail("Script nesting limit exceeded.")
	var source := _string()
	var line := _uint()
	var parameters := _uint()
	var vararg := _uint(1)
	var stack := _uint()
	if parameters > 250 or stack > 250 or stack < parameters or vararg > 1: return _fail("Invalid function header.")
	for i in _count():
		_string()
		_uint()
		_uint()
	for i in _count(): _uint()
	var strings: Array[String] = []
	for i in _count(): strings.append(_string())
	var numbers := PackedFloat64Array()
	for i in _count(): numbers.append(_number())
	var children: Array[Dictionary] = []
	for i in _count():
		children.append(_function(name + "/" + str(i), depth + 1))
		if not error.is_empty(): return {}
	var code := PackedInt64Array()
	for i in _count():
		var word := _uint(instruction_width)
		if word < 0 or word > 0xffffffff or (word & 63) > 48: return _fail("Invalid Lua instruction.")
		code.append(word)
	if code.is_empty() or code[-1] != 0: return _fail("Missing script terminator.")
	for pc in code.size():
		var word := code[pc]
		var op := word & 63
		var u := word >> 6
		if op in [7, 12, 14, 16, 19] and u >= strings.size(): return _fail("Invalid string constant.")
		if op in [8, 9] and u >= numbers.size(): return _fail("Invalid number constant.")
		if op == 48 and (word >> 15) >= children.size(): return _fail("Invalid child function.")
		if (op >= 32 and op <= 42) or (op >= 44 and op <= 47):
			var jump := pc + 1 + u - 33554431
			if jump < 0 or jump >= code.size(): return _fail("Invalid script jump.")
	return {"id": name, "source": source, "line": line, "parameters": parameters, "vararg": vararg, "stack": stack,
		"strings": strings, "numbers": numbers, "children": children, "code": code}

func _count() -> int:
	var result := _uint()
	if result > 1048576 or result < 0:
		_fail("Invalid script array length.")
		return 0
	return result if error.is_empty() else 0

func _string() -> String:
	var length := _uint(size_width)
	if length == 0: return ""
	if length < 1 or length > 1048576 or length > bytes.size() - offset:
		_fail("Invalid script string length.")
		return ""
	var raw := _take(length)
	if raw[-1] != 0:
		_fail("Unterminated script string.")
		return ""
	var result := ""
	for i in length - 1:
		var value := raw[i]
		result += String.chr(value) if value < 128 else ELText.CP1251[value - 128]
	return result

func _number() -> float:
	var raw := _take(number_width)
	if raw.size() != number_width: return 0.0
	return raw.decode_double(0) if number_width == 8 else raw.decode_float(0)

func _uint(width := 4) -> int:
	var raw := _take(width)
	if raw.size() != width: return 0
	if width == 1: return raw[0]
	return raw.decode_u64(0) if width == 8 else raw.decode_u32(0)

func _take(length: int) -> PackedByteArray:
	if length < 0 or length > bytes.size() - offset:
		_fail("Truncated script.")
		return PackedByteArray()
	var result := bytes.slice(offset, offset + length)
	offset += length
	return result

func _fail(message: String) -> Dictionary:
	if error.is_empty(): error = message
	return {}
