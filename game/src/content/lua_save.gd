class_name ELLuaSave
extends RefCounted
## Saves script values as a graph, preserving aliases, cycles, closures and RNG.
## Function code comes from the mounted scripts, never from a saved game.
var error := ""
var _ids: Dictionary = {}
var _records: Array[Dictionary] = []
var _objects: Array = []

func encode(vm: ELLuaVM) -> Dictionary:
	error = ""
	_ids.clear()
	_records.clear()
	var values := {}
	# Sorted names keep object ids independent of global insertion order, so a
	# reloaded state encodes identically.
	var names: Array = vm.globals.keys()
	names.sort()
	for name: String in names: values[name] = _encode(vm.globals[name])
	return {"version": 1, "rng": vm.rng_state, "globals": values, "objects": _records.duplicate(true)} if error.is_empty() else {}

func _encode(value: Variant, depth := 0) -> Array:
	if depth > 128 or _records.size() > 100000:
		error = "Script state is too large."
		return []
	if value == null: return [0]
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		if not is_finite(float(value)):
			error = "Cannot save a non-finite script number."
			return []
		return [1, float(value)]
	if typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]: return [2, String(value)]
	if value is ELLuaVM.Native: return [3, value.name]
	if not (value is ELLuaVM.Table or value is ELLuaVM.Closure):
		error = "Unsupported script value in saved state."
		return []
	var key: int = value.get_instance_id()
	if _ids.has(key): return [4, _ids[key]]
	var id := _records.size()
	_ids[key] = id
	var record: Dictionary = {"kind": "table", "entries": []} if value is ELLuaVM.Table else {"kind": "closure", "prototype": value.prototype.id, "label": value.label, "captures": []}
	_records.append(record)
	if value is ELLuaVM.Table:
		for entry: Variant in value.values: record.entries.append([_encode(entry, depth + 1), _encode(value.values[entry], depth + 1)])
	else:
		for entry: Variant in value.captures: record.captures.append(_encode(entry, depth + 1))
	return [4, id]

func decode(vm: ELLuaVM, raw: Variant) -> bool:
	error = ""
	_objects.clear()
	if not raw is Dictionary or raw.get("version") != 1 or not raw.get("objects") is Array or not raw.get("globals") is Dictionary or not _integer(raw.get("rng"), 0, 0xffffffff):
		return _fail("Invalid saved script state.")
	if raw.objects.size() > 100000 or raw.globals.size() > 100000: return _fail("Saved script state exceeds limits.")
	for record: Variant in raw.objects:
		if not record is Dictionary: return _fail("Invalid script object record.")
		if record.get("kind") == "table" and record.get("entries") is Array:
			_objects.append(ELLuaVM.Table.new())
		elif record.get("kind") == "closure" and record.get("captures") is Array and record.get("prototype") is String and vm.prototypes.has(record.prototype) and record.get("label") is String:
			var closure := ELLuaVM.Closure.new()
			closure.prototype = vm.prototypes[record.prototype]
			closure.label = record.label
			_objects.append(closure)
		else: return _fail("Missing script function or invalid object record.")
	for i in _objects.size():
		var record: Dictionary = raw.objects[i]
		if _objects[i] is ELLuaVM.Table:
			if record.entries.size() > 100000: return _fail("Saved script table exceeds limits.")
			for pair: Variant in record.entries:
				if not pair is Array or pair.size() != 2: return _fail("Invalid script table entry.")
				var key: Variant = _decode(pair[0], vm)
				var value: Variant = _decode(pair[1], vm)
				if key == null: return _fail("A script table key cannot be nil.")
				if value != null: _objects[i].values[key] = value
		else:
			if record.captures.size() > 32: return _fail("Too many saved closure captures.")
			for capture: Variant in record.captures: _objects[i].captures.append(_decode(capture, vm))
	var values := {}
	for name: Variant in raw.globals:
		if not name is String: return _fail("Invalid global variable name.")
		values[name] = _decode(raw.globals[name], vm)
	if not error.is_empty(): return _fail(error)
	# Commit only after the entire graph validates.
	for value: ELLuaVM.Table in vm._tables: value.values.clear()
	vm._tables.clear()
	vm.globals = values
	vm.rng_state = int(raw.rng)
	for value: Variant in _objects:
		if value is ELLuaVM.Table: vm._tables.append(value)
	_objects.clear()
	return true

func _decode(raw: Variant, vm: ELLuaVM) -> Variant:
	if not raw is Array or raw.is_empty() or not _integer(raw[0], 0, 4):
		error = "Invalid encoded script value."
		return null
	if raw[0] == 0:
		if raw.size() != 1: error = "Invalid nil value."
		return null
	if raw.size() != 2:
		error = "Invalid encoded script value length."
		return null
	match int(raw[0]):
		1:
			if typeof(raw[1]) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw[1])): return float(raw[1])
		2:
			if raw[1] is String: return raw[1]
		3:
			if raw[1] is String and vm.natives.has(raw[1]): return vm.natives[raw[1]]
		4:
			if _integer(raw[1], 0, _objects.size() - 1): return _objects[int(raw[1])]
	error = "Invalid or unavailable script value reference."
	return null

static func _integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

func _fail(message: String) -> bool:
	error = message
	for value: Variant in _objects:
		if value is ELLuaVM.Table: value.values.clear()
		elif value is ELLuaVM.Closure: value.captures.clear()
	_objects.clear()
	return false
