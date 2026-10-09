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
static func parse(bytes: PackedByteArray) -> Dictionary:
	var text := bytes.get_string_from_utf16() if bytes.size() > 1 and bytes[0] == 255 and bytes[1] == 254 else ansi(bytes)
	var result := {}
	var key := ""
	for line in text.replace("\r", "").split("\n"):
		if line.begins_with("#"):
			key = line.substr(1).strip_edges()
			result[key] = ""
		elif not key.is_empty():
			result[key] += ("\n" if not result[key].is_empty() else "") + line
	return result
