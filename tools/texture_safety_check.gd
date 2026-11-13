extends SceneTree
## Headless check that reading a texture never changes it.
##
## An ImageTexture hands out the very image it was made from, so a reader
## that decompresses, converts, resizes or clears the mipmaps of what
## get_image() returns corrupts the texture that everything else draws with.
## That is what made the particle sheets lose their transparency and draw as
## white squares, and it stayed hidden until a preference that was off by
## default (spell light) started reading those sheets every frame.
##
## Every reader of a shared texture is run here over the game's own sheets,
## and the texture is compared with itself afterwards (size, format and
## pixels). ELTexture.readable and uncompressed are checked to copy only
## when something has to change, so this costs no memory where it need not.
##
##   godot --headless --path game --script ../tools/texture_safety_check.gd
##
## Needs the second game's files (the profile this computer has imported).

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

## Size, format and pixels, as a texture's image stands now.
func _state(texture: Texture2D) -> Array:
	var image := texture.get_image()
	if image == null: return []
	var pixels := image.get_data()
	return [image.get_size(), image.get_format(), pixels.size(), pixels.slice(0, mini(pixels.size(), 4096)), pixels.slice(maxi(pixels.size() - 4096, 0))]

func _profile(edition: String) -> ELProfile:
	var folder := ""
	if FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get(edition, ""))
	var data := ELProfile.new()
	return data if not folder.is_empty() and data.mount(edition, folder) else null

func _run() -> void:
	var data := _profile("el2")
	if data == null:
		print("texture safety check: the second game is not imported here; nothing to read")
		quit(0)
		return

	# The sheets the effects read every frame while spell light or path
	# tracing is on, an arena's detail grain, and a figure's skin.
	var sheets := {
		"Effects/MagmaGlow": Vector2i(4, 4),
		"Effects/Fire": Vector2i(4, 4),
		"Effects/Smoke": Vector2i(4, 4)}
	var read := 0
	for name: String in sheets:
		var texture := data.texture(name)
		if texture == null: continue
		read += 1
		var before := _state(texture)
		var tints := ELCombatEffects._atlas_cell_tints(texture, sheets[name])
		check(_state(texture) == before, "%s is unchanged after its cell colours are worked out" % name.get_file())
		check(tints.size() == sheets[name].x * sheets[name].y, "%s gives a colour per cell" % name.get_file())
		ELCombatEffects._texture_glow(texture)
		check(_state(texture) == before, "%s is unchanged after its average colour is read" % name.get_file())
		ELCombatEffects._flame_colour(texture)
		check(_state(texture) == before, "%s is unchanged after it is judged for flame" % name.get_file())
		ELColorless.grey_image(texture.get_image())
		check(_state(texture) == before, "%s is unchanged after a grey copy is made" % name.get_file())
		var image := texture.get_image()
		check(ELTexture.readable(image) == image or image.get_format() != Image.FORMAT_RGBA8 or image.is_compressed(), "%s is shared, not copied, when it needs no change" % name.get_file())
		check(ELTexture.uncompressed(image) == image or image.is_compressed(), "%s is shared by a reader that only wants its pixels" % name.get_file())
		check(_state(texture) == before, "%s is unchanged after both" % name.get_file())
	check(read > 0, "the effect sheets were found and read")

	# An arena's detail grain: its average was taken from the sheet itself,
	# which left the sheet one pixel wide.
	var arena_texture := data.texture("CombatScenes/" + String(data.table("CombatSceneDB").get("Green.001", {}).get("DetailTextureName", "")))
	if arena_texture != null:
		var before := _state(arena_texture)
		var average: Image = arena_texture.get_image().duplicate()
		average.clear_mipmaps()
		average.resize(1, 1, Image.INTERPOLATE_LANCZOS)
		check(_state(arena_texture) == before and before[0] != Vector2i.ONE, "an arena's detail sheet keeps its size after its average is taken")

	# The helper itself.
	var plain := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	check(ELTexture.readable(plain) == plain, "a reader is handed the image itself when it is already as wanted")
	check(ELTexture.uncompressed(plain) == plain, "and by the one that takes any format")
	var other := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	var converted := ELTexture.readable(other)
	check(converted != other and converted.get_format() == Image.FORMAT_RGBA8 and other.get_format() == Image.FORMAT_RGB8, "an image that must change is copied, and the original left alone")
	check(ELTexture.readable(null) == null and ELTexture.uncompressed(null) == null, "no image is no trouble")

	print("TEXTURE SAFETY: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
