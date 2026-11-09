class_name ELRemakeTranslation
extends Translation
## The remake's Russian texts as a Godot translation: every label, button,
## tooltip and window title of the remake's own screens is looked up here
## while the locale is "ru" (see ELRemakeText.use). Texts of the original
## games are already in their own language and pass through unchanged.

func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var text := String(src_message)
	var shown := ELRemakeText.russian(text)
	return StringName(shown) if shown != text else &""
