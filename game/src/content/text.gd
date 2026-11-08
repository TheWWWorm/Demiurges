class_name ELText
extends RefCounted
const CP1251 := "ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—�™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕїАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя"
static func ansi(bytes: PackedByteArray) -> String:
	var out := ""
	for value in bytes:
		if value == 0:
			continue
		out += String.chr(value) if value < 128 else CP1251[value - 128]
	return out
## The Russian Etherlords II sold on Steam (version 1.03) stores its text
## table scrambled: each byte is XORed with ROW[i % 11] ^ COLUMN[i % 256].
const SCRAMBLE_ROW := "e93b9a3fda8a2f7021899c"
const SCRAMBLE_COLUMN := "00b9afdc0c21ab4c08a9570cb4a1d31c30b95f1cbc411bacb8c9072ca441039c60398f9cec210b8c6829b74c14a1b3dc1039bf5c1c817b2c9889e72c0481635cc0396fdccca16b4cc829178c7421939cf0391f9c7c41db2c78c9c7ac6441c31c20b94f1caca1cb0c28a9774cd42173dcd0b97f5cdc013bac5809a7acc401235c80b92fdc8c212b4c88a9d70c34a1531cb0b9df1c3c419bac38c9872c2441839ce0390f9c6c218b8ce829374c94a133dc90393f5c9c81fb2c1889672c8481e35c4039efdc4ca1eb4c4829978cf421139c70399f9cfc415b2cf8c947ace441431ca0b9cf1c2ca14b0ca8a9f74c5421f3dc50b9ff5c5c01bbacd80927ac4401a35c"

## The text table as stored, unscrambled when it is the Steam Russian layout.
static func unscramble(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() < 2 or (bytes[0] == 255 and bytes[1] == 254) or bytes[0] == 35: return bytes
	var row := SCRAMBLE_ROW.hex_decode()
	var column := SCRAMBLE_COLUMN.hex_decode()
	if bytes[0] ^ row[0] ^ column[0] != 255 or bytes[1] ^ row[1] ^ column[1] != 254: return bytes
	var out := bytes.duplicate()
	for i in out.size():
		out[i] ^= row[i % 11] ^ column[i % 256]
	return out

static func parse(bytes: PackedByteArray) -> Dictionary:
	bytes = unscramble(bytes)
	var text := _utf16(bytes) if bytes.size() > 1 and bytes[0] == 255 and bytes[1] == 254 else ansi(bytes)
	var result := {}
	var key := ""
	for line in text.replace("\r", "").split("\n"):
		if line.begins_with("#"):
			key = line.substr(1).strip_edges()
			result[key] = ""
		elif not key.is_empty():
			result[key] += ("\n" if not result[key].is_empty() else "") + line
	return result

## UTF-16 text; a NUL (one repacked Russian table has some inside an entry)
## would otherwise end the whole decoded string.
static func _utf16(bytes: PackedByteArray) -> String:
	var units := PackedByteArray()
	var skipping := false
	for i in range(0, bytes.size() - 1, 2):
		var unit := bytes[i] | (bytes[i + 1] << 8)
		# As in the original's string reading, a NUL ends the line's text.
		if unit == 0: skipping = true
		elif unit == 13 or unit == 10: skipping = false
		if skipping: continue
		units.append(bytes[i])
		units.append(bytes[i + 1])
	return units.get_string_from_utf16()
