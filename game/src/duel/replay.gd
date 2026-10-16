class_name ELDuelReplay
extends RefCounted
## Second-game combat replay (.rpl): an uncompressed little-endian record of a
## duel's setup, its battle seed and the command list, as written by the
## original's replay recorder. Format versions 4-7 are accepted; strings are a
## 32-bit length followed by the bytes, four-character codes are 32-bit values.
## Each command may carry a note: a text key ("#d" prefix = hand slot d to
## preselect) plus a list of integer triples.

const COMMANDS := ["next_phase", "cast", "artifact", "hero_ability", "ability", "attack", "block", "retreat",
	"test", "start_game", "surrender", "cheat_cast", "cheat_cast_effects", "cheat_add_spell", "cheat_health",
	"cheat_mana", "cheat_channels", "cheat_win", "cheat_disenchant"]
## Counts above this are treated as corrupt (the original throws at 0x100).
const LIMIT := 0x100

var version := 0
var name := ""
## Names recorded by version 6+ (two hero names, then two templates).
var labels: Array[String] = []
var local_side := 0
var rounds := 1
var arena := ""
## Setup words of the original record, kept for reference.
var setup_words: Array[int] = []
## Per side: template, name, colour (0 Red, 1 Green, 2 Blue, 3 Black, 4 White),
## field_1c, level, specialization, artifacts, skills {code: rank}, portrait,
## deck (codes) and bag ([code, count]).
var heroes: Array[Dictionary] = []
var seed_value := 0
## {kind, side, values..., effects, note: {text, triples} or null}
var commands: Array[Dictionary] = []
var error := ""

var _bytes := PackedByteArray()
var _at := 0
## Byte spans [start, end) of the recorded name and of each command's note
## block, so an edited copy keeps every other byte as recorded.
var _name_span := Vector2i.ZERO
var _note_spans: Array[Vector2i] = []

static func fourcc(value: int) -> String:
	var b := PackedByteArray([value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff])
	return b.get_string_from_ascii()

func decode(bytes: PackedByteArray) -> bool:
	_bytes = bytes
	_at = 0
	error = ""
	heroes.clear()
	commands.clear()
	labels.clear()
	setup_words.clear()
	if bytes.size() < 2: return _fail("Replay is too short.")
	var major := _u8()
	version = _u8()
	if major != 0 or version < 4 or version > 7: return _fail("Unsupported replay version.")
	_note_spans.clear()
	_name_span.x = _at
	name = _string()
	_name_span.y = _at
	if version >= 6:
		for i in 4: labels.append(_string())
	setup_words.append(_i32())
	setup_words.append(_i32())
	arena = _string()
	rounds = 1
	local_side = _i32()
	setup_words.append(_i32())
	for side in 2:
		var hero := {"template": _string()}
		hero.name = _string()
		hero.colour = _i32()
		hero.field_1c = _i32()
		hero.level = _i32()
		hero.specialization = fourcc(_i32())
		var artifacts: Array = []
		var count := _count()
		for i in count:
			if version <= 6: artifacts.append(_string())
			else: artifacts.append(_i32())
		hero.artifacts = artifacts
		var skills := {}
		count = _count()
		for i in count:
			var code := _i32()
			var rank := _i32()
			# A rank r is stored as r+1 inserts; −1 is an empty skill slot.
			if rank >= 0 and code != 0: skills[fourcc(code)] = rank
		hero.skills = skills
		hero.portrait = _i32()
		count = _count()
		var deck: Array[String] = []
		for i in count: deck.append(fourcc(_i32()))
		hero.deck = deck
		var bag: Array = []
		if version >= 5:
			count = _count()
			for i in count:
				var code := fourcc(_i32())
				bag.append([code, _i32()])
		hero.bag = bag
		heroes.append(hero)
		if not error.is_empty(): return false
	seed_value = _i32()
	var total := _i32()
	for i in total:
		var command := _command()
		if command.is_empty(): return false
		commands.append(command)
	if not error.is_empty(): return false
	if _at != _bytes.size(): return _fail("Trailing replay data.")
	return true

func _command() -> Dictionary:
	var kind := _i32()
	if kind < 0 or kind >= COMMANDS.size():
		_fail("Unknown replay command.")
		return {}
	var c := {"kind": COMMANDS[kind]}
	match kind:
		# NextPhase, Test, StartGame and Surrender carry only the side.
		0, 8, 9, 10: c.side = _i32()
		# Cheats: add spell (side, code), set health/ether/channels (side,
		# value); win (side); disenchant (entity).
		13, 14, 15, 16:
			c.side = _i32()
			c.value = _i32()
		17: c.side = _i32()
		18:
			# No side is recorded; -1 plays it as the computer's.
			c.side = -1
			c.target = _i32()
		1, 2, 3, 11, 12:
			c.side = _i32()
			c.id = _i32()
			c.targets = _ints()
		4:
			c.side = _i32()
			c.id = _i32()
			c.ability = _i32()
			c.targets = _ints()
		5, 7:
			c.side = _i32()
			c.id = _i32()
		6:
			c.side = _i32()
			c.id = _i32()
			c.target = _i32()
		_:
			_fail("Unsupported replay command: " + COMMANDS[kind])
			return {}
	var effects: Array = []
	var count := _count()
	for i in count:
		if _i32() != 0:
			_fail("Unknown replay effect record.")
			return {}
		effects.append([_i32(), _i32(), _i32()])
	c.effects = effects
	var note_start := _at
	var notes := _i8()
	c.note = null
	if notes >= 0:
		var note := {"text": _string(), "triples": []}
		for i in notes: note.triples.append([_i32(), _i32(), _i32()])
		c.note = note
	if not error.is_empty(): return {}
	_note_spans.append(Vector2i(note_start, _at))
	return c

## The recorded bytes with a new name and each command's current note
## (null for none): what the original writes when it saves a loaded replay
## again. Empty when the replay was not decoded.
func encode(new_name: String) -> PackedByteArray:
	if _bytes.is_empty() or _note_spans.size() != commands.size(): return PackedByteArray()
	var out := PackedByteArray()
	out.append_array(_bytes.slice(0, _name_span.x))
	out.append_array(_string_bytes(new_name))
	var at := _name_span.y
	for index in commands.size():
		var span := _note_spans[index]
		out.append_array(_bytes.slice(at, span.x))
		var note: Variant = commands[index].note
		if note == null:
			out.append(0xff)
		else:
			var triples: Array = note.get("triples", [])
			out.append(triples.size())
			out.append_array(_string_bytes(str(note.get("text", ""))))
			for triple: Array in triples:
				for value: Variant in triple:
					var word := PackedByteArray()
					word.resize(4)
					word.encode_s32(0, int(value))
					out.append_array(word)
		at = span.y
	out.append_array(_bytes.slice(at))
	return out

static func _string_bytes(text: String) -> PackedByteArray:
	var body := cp1251(text)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_s32(0, body.size())
	out.append_array(body)
	return out

## Windows-1251, the original's text code page (Cyrillic letters; other
## characters outside ASCII become "?").
static func cp1251(text: String) -> PackedByteArray:
	var out := PackedByteArray()
	for index in text.length():
		var code := text.unicode_at(index)
		if code < 0x80: out.append(code)
		elif code >= 0x410 and code <= 0x44f: out.append(code - 0x410 + 0xc0)
		elif code == 0x401: out.append(0xa8)
		elif code == 0x451: out.append(0xb8)
		else: out.append(0x3f)
	return out

static func from_cp1251(bytes: PackedByteArray) -> String:
	var text := ""
	for value in bytes:
		# As before: the text ends at a NUL byte.
		if value == 0: break
		if value < 0x80: text += char(value)
		elif value >= 0xc0: text += char(value - 0xc0 + 0x410)
		elif value == 0xa8: text += char(0x401)
		elif value == 0xb8: text += char(0x451)
		else: text += "?"
	return text

func _ints() -> Array[int]:
	var result: Array[int] = []
	var count := _count()
	for i in count: result.append(_i32())
	return result

func _count() -> int:
	var value := _i32()
	if value < 0 or value >= LIMIT:
		_fail("Replay count out of range.")
		return 0
	return value

func _u8() -> int:
	if _at + 1 > _bytes.size(): return _short()
	_at += 1
	return _bytes[_at - 1]

func _i8() -> int:
	var value := _u8()
	return value - 256 if value >= 128 else value

func _i32() -> int:
	if _at + 4 > _bytes.size(): return _short()
	var value := _bytes.decode_s32(_at)
	_at += 4
	return value

func _string() -> String:
	var length := _i32()
	if length < 0 or _at + length > _bytes.size():
		_short()
		return ""
	var text := from_cp1251(_bytes.slice(_at, _at + length))
	_at += length
	return text

func _short() -> int:
	if error.is_empty(): error = "Replay ends early."
	_at = _bytes.size()
	return 0

func _fail(message: String) -> bool:
	if error.is_empty(): error = message
	return false
