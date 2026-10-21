class_name ELLuaVM
extends RefCounted
## Bounded Lua 4 bytecode execution for original campaign and arena scripts.
## Adapted semantics from Lua 4.0 lvm.c; this is a new Godot implementation.
## No filesystem, shell, dynamic source execution, or implicit engine bindings.
class Table extends RefCounted:
	var values: Dictionary = {}
class Closure extends RefCounted:
	var prototype: Dictionary
	var captures: Array = []
	var label := ""
class Native extends RefCounted:
	var name := ""

var globals: Dictionary = {}
var bindings: Dictionary = {}
var natives: Dictionary = {}
var prototypes: Dictionary = {}
var error := ""
var instructions := 0
var instruction_limit := 500000
var rng_state := 212
var _depth := 0
var _tables: Array[Table] = []
var _context := ""

func _init() -> void:
	for name: String in ["type", "tonumber", "tostring", "getn", "next", "rawget", "rawset", "tinsert", "tremove", "getglobal", "setglobal", "call", "assert", "error",
		"abs", "floor", "ceil", "sqrt", "log", "log10", "exp", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "deg", "rad", "min", "max", "mod", "random", "randomseed", "format", "strlen", "strlower", "strupper", "strsub"]:
		var native := Native.new()
		native.name = name
		globals[name] = native
		natives[name] = native
	globals["PI"] = PI

func bind(name: String, function: Callable) -> void:
	var native := Native.new()
	native.name = name
	globals[name] = native
	natives[name] = native
	bindings[name] = function

func load_script(bytes: PackedByteArray, name: String) -> bool:
	var reader := ELLuaChunk.new()
	var prototype := reader.parse(bytes, name)
	if prototype.is_empty():
		error = name + ": " + reader.error
		return false
	_register_prototypes(prototype)
	var closure := Closure.new()
	closure.prototype = prototype
	closure.label = name
	_begin()
	_invoke(closure, [])
	return error.is_empty()

func invoke(name: String, arguments: Array = []) -> Array:
	_begin()
	if not globals.has(name):
		_fail("Missing script function: " + name)
		return []
	return _invoke(globals[name], arguments)

func has_function(name: String) -> bool:
	return globals.get(name) is Closure or globals.get(name) is Native

func table() -> Table:
	var result := Table.new()
	_tables.append(result)
	return result

func clear() -> void:
	# Break script-created table cycles explicitly; Godot uses reference counting.
	for value: Table in _tables: value.values.clear()
	_tables.clear()
	globals.clear()
	bindings.clear()
	natives.clear()
	prototypes.clear()

func _begin() -> void:
	error = ""
	instructions = 0
	_depth = 0
	_context = ""

func _register_prototypes(prototype: Dictionary) -> void:
	prototypes[prototype.id] = prototype
	for child: Dictionary in prototype.children: _register_prototypes(child)

func _invoke(function: Variant, arguments: Array) -> Array:
	if not error.is_empty(): return []
	_depth += 1
	var result: Array = []
	if _depth > 96:
		_fail("Script call depth exceeded.")
	elif function is Native:
		if bindings.has(function.name): result = bindings[function.name].call(arguments)
		else: result = _builtin(function.name, arguments)
	elif function is Closure:
		result = _execute(function, arguments)
	else:
		_fail("Attempt to call " + _type(function) + ".")
	_depth -= 1
	return result

func _execute(function: Closure, arguments: Array) -> Array:
	var p: Dictionary = function.prototype
	var stack: Array = arguments.slice(0, p.parameters)
	stack.resize(p.parameters)
	if p.vararg:
		var extra := table()
		for i in maxi(0, arguments.size() - int(p.parameters)): extra.values[float(i + 1)] = arguments[p.parameters + i]
		extra.values.n = float(maxi(0, arguments.size() - int(p.parameters)))
		stack.append(extra)
	var pc := 0
	while error.is_empty():
		instructions += 1
		_context = "%s @%d" % [function.label if not function.label.is_empty() else p.id, pc]
		if instructions > instruction_limit:
			_fail("Script instruction budget exceeded.")
			break
		if pc < 0 or pc >= p.code.size():
			_fail("Script program counter is outside the function.")
			break
		var word: int = p.code[pc]
		pc += 1
		var op := word & 63
		var u := word >> 6
		var a := word >> 15
		var b := (word >> 6) & 511
		var s := u - 33554431
		var size := stack.size()
		var needed := 0
		if op in [13, 23, 25, 26, 27, 28, 32, 33, 34, 35, 36, 37]: needed = 2
		if op in [14, 15, 16, 18, 19, 24, 30, 31, 38, 39, 40, 41, 46]: needed = 1
		if op in [44, 45, 47]: needed = 3
		if op in [5, 29]: needed = u
		if op == 20: needed = maxi(a, b)
		if op == 21: needed = b + 1
		if op == 22: needed = 2 * u + 1
		if op == 48: needed = b
		if size < needed or (op in [11, 15] and u >= size) or (op == 18 and u >= size - 1) or (op in [2, 3] and a >= size) or (op == 10 and u >= function.captures.size()) or (op == 1 and u > size) or (op == 4 and size + u > 4096):
			_fail("Invalid script stack access.")
			break
		match op:
			0: return []
			1: return stack.slice(u)
			2, 3:
				var values := _invoke(stack[a], stack.slice(a + 1))
				stack.resize(a)
				if op == 3:
					stack.append_array(values)
					return stack.slice(b)
				if b != 255: values.resize(b)
				stack.append_array(values)
			4: stack.resize(size + u)
			5: stack.resize(size - u)
			6: stack.append(float(s))
			7: stack.append(p.strings[u])
			8: stack.append(p.numbers[u])
			9: stack.append(-p.numbers[u])
			10: stack.append(function.captures[u])
			11: stack.append(stack[u])
			12: stack.append(globals.get(p.strings[u]))
			13:
				var key: Variant = stack.pop_back()
				stack[-1] = _table_get(stack[-1], key)
			14: stack[-1] = _table_get(stack[-1], p.strings[u])
			15: stack[-1] = _table_get(stack[-1], stack[u])
			16:
				var receiver: Variant = stack[-1]
				stack[-1] = _table_get(receiver, p.strings[u])
				stack.append(receiver)
			17: stack.append(table())
			18:
				var value: Variant = stack.pop_back()
				stack[u] = value
			19:
				var value: Variant = stack.pop_back()
				globals[p.strings[u]] = value
				if value is Closure and value.label.is_empty(): value.label = p.strings[u]
			20:
				if a < 3:
					_fail("Invalid table assignment.")
					break
				_table_set(stack[size - a], stack[size - a + 1], stack[-1])
				stack.resize(size - b)
			21:
				for i in b: _table_set(stack[size - b - 1], float(a * 64 + i + 1), stack[size - b + i])
				stack.resize(size - b)
			22:
				for i in range(u - 1, -1, -1): _table_set(stack[size - 2 * u - 1], stack[size - 2 * u + i * 2], stack[size - 2 * u + i * 2 + 1])
				stack.resize(size - 2 * u)
			23, 25, 26, 27, 28:
				var right := _number(stack.pop_back())
				var left := _number(stack[-1])
				match op:
					23: stack[-1] = left + right
					25: stack[-1] = left - right
					26: stack[-1] = left * right
					27: stack[-1] = left / right if right != 0 else NAN if left == 0 else signf(left) * INF
					28: stack[-1] = pow(left, right)
			24: stack[-1] = _number(stack[-1]) + s
			29:
				var joined := ""
				for i in range(size - u, size):
					if _type(stack[i]) not in ["string", "number"]: _fail("Invalid concatenation operand.")
					joined += _string(stack[i])
				stack.resize(size - u)
				stack.append(joined)
			30: stack[-1] = -_number(stack[-1])
			31: stack[-1] = 1.0 if stack[-1] == null else null
			32, 33, 34, 35, 36, 37:
				var right: Variant = stack.pop_back()
				var left: Variant = stack.pop_back()
				var jump := false
				match op:
					32: jump = not _equal(left, right)
					33: jump = _equal(left, right)
					34: jump = _less(left, right)
					35: jump = not _less(right, left)
					36: jump = _less(right, left)
					37: jump = not _less(left, right)
				if jump: pc += s
			38, 39:
				var truth: bool = stack.pop_back() != null
				if truth == (op == 38): pc += s
			40, 41:
				if (stack[-1] != null) == (op == 40): pc += s
				else: stack.pop_back()
			42: pc += s
			43:
				stack.append(null)
				pc += 1
			44, 45:
				var step := _number(stack[-1])
				var limit := _number(stack[-2])
				var index := _number(stack[-3]) + (step if op == 45 else 0.0)
				stack[-1] = step
				stack[-2] = limit
				stack[-3] = index
				var finished := index > limit if step > 0 else index < limit
				if finished:
					stack.resize(size - 3)
					if op == 44: pc += s
				elif op == 45: pc += s
			46, 47:
				var pair := _next(stack[-1] if op == 46 else stack[-3], null if op == 46 else stack[-2])
				if pair.is_empty():
					stack.resize(size - (1 if op == 46 else 3))
					if op == 46: pc += s
				elif op == 46: stack.append_array(pair)
				else:
					stack[-2] = pair[0]
					stack[-1] = pair[1]
					pc += s
			48:
				var closure := Closure.new()
				closure.prototype = p.children[a]
				closure.captures = stack.slice(size - b)
				stack.resize(size - b)
				stack.append(closure)
		if stack.size() > 4096:
			_fail("Script stack limit exceeded.")
			break
	return []

func _table_get(value: Variant, key: Variant) -> Variant:
	if value is Table: return value.values.get(_key(key))
	_fail("Attempt to index " + _type(value) + ".")
	return null

func _table_set(value: Variant, key: Variant, item: Variant) -> void:
	if not value is Table or key == null:
		_fail("Invalid table assignment.")
		return
	key = _key(key)
	if item == null: value.values.erase(key)
	else: value.values[key] = item

func _next(value: Variant, key: Variant) -> Array:
	if not value is Table:
		_fail("Expected a table.")
		return []
	var keys: Array = value.values.keys()
	var index := 0 if key == null else keys.find(_key(key)) + 1
	return [keys[index], value.values[keys[index]]] if index < keys.size() else []

static func _key(value: Variant) -> Variant:
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else value

static func _type(value: Variant) -> String:
	if value == null: return "nil"
	if value is Table: return "table"
	if value is Closure or value is Native: return "function"
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]: return "number"
	if typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]: return "string"
	return "userdata"

static func _equal(left: Variant, right: Variant) -> bool:
	if _type(left) != _type(right): return false
	if left is Table or left is Closure or left is Native: return is_same(left, right)
	return left == right

func _less(left: Variant, right: Variant) -> bool:
	if _type(left) == "number" and _type(right) == "number": return float(left) < float(right)
	if _type(left) == "string" and _type(right) == "string": return String(left) < String(right)
	_fail("Invalid comparison operands.")
	return false

func _number(value: Variant) -> float:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]: return float(value)
	if value is String and value.strip_edges().is_valid_float(): return value.to_float()
	_fail("Expected a number, received " + _type(value) + ".")
	return 0.0

static func _string(value: Variant) -> String:
	if value == null: return "nil"
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]: return str(int(value)) if is_finite(float(value)) and float(int(value)) == float(value) else str(value)
	return str(value)

## Lua's C-style format: each directive takes the next argument, unused
## arguments are ignored and %% is a literal percent sign.
func _format(pattern: String, values: Array) -> String:
	var out := ""
	var i := 0
	var next := 0
	while i < pattern.length():
		var c := pattern[i]
		if c != "%" or i + 1 >= pattern.length():
			out += c
			i += 1
			continue
		var j := i + 1
		while j < pattern.length() and "-+ #0123456789.".contains(pattern[j]): j += 1
		if j >= pattern.length():
			out += pattern.substr(i)
			break
		var kind := pattern[j]
		var flags := pattern.substr(i + 1, j - i - 1)
		i = j + 1
		if kind == "%":
			out += "%"
			continue
		var value: Variant = values[next] if next < values.size() else null
		next += 1
		match kind:
			"d", "i", "u", "c", "x", "X", "o":
				var n := int(_number(value))
				if kind == "c": out += char(n)
				else: out += ("%" + flags + ("d" if kind in ["i", "u"] else kind)) % n
			"f", "e", "E", "g", "G":
				var x := _number(value)
				if kind == "f": out += ("%" + flags + "f") % x
				else:
					var digits := int(flags.get_slice(".", 1)) if flags.contains(".") else 6
					out += String.num(x, maxi(digits, 0)) if kind in ["g", "G"] else String.num_scientific(x)
			"q": out += "\"" + _string(value).c_escape() + "\""
			_: out += ("%" + flags + "s") % _string(value)
	return out

func _builtin(name: String, args: Array) -> Array:
	var first: Variant = args[0] if not args.is_empty() else null
	match name:
		"type": return [_type(first)]
		"tostring": return [_string(first)]
		"tonumber":
			if _type(first) == "number": return [float(first)]
			return [first.to_float()] if first is String and first.strip_edges().is_valid_float() else [null]
		"getglobal": return [globals.get(_string(first))]
		"setglobal":
			if args.size() >= 2: globals[_string(first)] = args[1]
			return []
		"assert":
			if first == null: _fail(_string(args[1]) if args.size() > 1 else "Script assertion failed.")
			return [first]
		"error":
			_fail(_string(first))
			return []
		"getn": return [float(_length(first))]
		"next": return _next(first, args[1] if args.size() > 1 else null)
		"rawget": return [_table_get(first, args[1])] if args.size() >= 2 else []
		"rawset":
			if args.size() >= 3: _table_set(first, args[1], args[2])
			return [first]
		"tinsert":
			var count := _length(first)
			var position := int(_number(args[1])) if args.size() > 2 else count + 1
			if args.size() < 2 or position < 1 or position > count + 1:
				_fail("Invalid table insertion.")
				return []
			for i in range(count, position - 1, -1): _table_set(first, i + 1, _table_get(first, i))
			_table_set(first, position, args[-1])
			_table_set(first, "n", float(count + 1))
			return []
		"tremove":
			var count := _length(first)
			var position := int(_number(args[1])) if args.size() > 1 else count
			if position < 1 or position > count: return []
			var value: Variant = _table_get(first, position)
			for i in range(position, count): _table_set(first, i, _table_get(first, i + 1))
			_table_set(first, count, null)
			_table_set(first, "n", float(count - 1))
			return [value]
		"call":
			var values: Array = []
			if args.size() > 1:
				for i in _length(args[1]): values.append(_table_get(args[1], i + 1))
			return _invoke(first, values)
		"randomseed":
			rng_state = int(_number(first)) & 0xffffffff
			return []
		"random":
			rng_state = (rng_state * 1664525 + 1013904223) & 0xffffffff
			var value := rng_state / 4294967296.0
			if args.is_empty(): return [value]
			var low := int(_number(first)) if args.size() > 1 else 1
			var high := int(_number(args[1])) if args.size() > 1 else int(_number(first))
			if high < low:
				_fail("Empty random interval.")
				return []
			return [float(low + floori(value * (high - low + 1)))]
		"format": return [_format(_string(first), args.slice(1))]
		"strlen": return [float(_string(first).length())]
		"strlower": return [_string(first).to_lower()]
		"strupper": return [_string(first).to_upper()]
		"strsub":
			var text := _string(first)
			var start := int(_number(args[1])) if args.size() > 1 else 1
			var end := int(_number(args[2])) if args.size() > 2 else -1
			if start < 0: start += text.length() + 1
			if end < 0: end += text.length() + 1
			return [text.substr(maxi(start, 1) - 1, maxi(0, mini(end, text.length()) - maxi(start, 1) + 1))]
	var x := _number(first)
	match name:
		"abs": return [absf(x)]
		"floor": return [floorf(x)]
		"ceil": return [ceilf(x)]
		"sqrt": return [sqrt(x)]
		"log": return [log(x)]
		"log10": return [log(x) / log(10.0)]
		"exp": return [exp(x)]
		"sin": return [sin(deg_to_rad(x))]
		"cos": return [cos(deg_to_rad(x))]
		"tan": return [tan(deg_to_rad(x))]
		"asin": return [rad_to_deg(asin(x))]
		"acos": return [rad_to_deg(acos(x))]
		"atan": return [rad_to_deg(atan(x))]
		"atan2": return [rad_to_deg(atan2(x, _number(args[1])))] if args.size() > 1 else []
		"deg": return [rad_to_deg(x)]
		"rad": return [deg_to_rad(x)]
		"mod": return [fmod(x, _number(args[1]))] if args.size() > 1 else []
		"min", "max":
			for other: Variant in args.slice(1): x = minf(x, _number(other)) if name == "min" else maxf(x, _number(other))
			return [x]
	_fail("Unknown script binding: " + name)
	return []

func _length(value: Variant) -> int:
	if not value is Table:
		_fail("Expected a table.")
		return 0
	if value.values.has("n"): return int(_number(value.values.n))
	var highest := 0
	for key: Variant in value.values:
		if _type(key) == "number" and float(key) == floorf(float(key)): highest = maxi(highest, int(key))
	return highest

func _fail(message: String) -> void:
	if error.is_empty(): error = message + (" (" + _context + ")" if not _context.is_empty() else "")
