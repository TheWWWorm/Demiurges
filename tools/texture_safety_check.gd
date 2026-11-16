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

## A masked texture as the games store one: `depth` bits a pixel, channels
## a, r, g, b as [mask, shift, bits], then `payload` bytes of pixels.
static func _masked(w: int, h: int, depth: int, channels: Array, payload: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(ELTexture.DATA_OFFSET + payload)
	for i in payload: data[ELTexture.DATA_OFFSET + i] = (i * 37 + 11) & 0xff
	data.encode_u32(0, ELTexture.MAGIC)
	data.encode_u32(4, w)
	data.encode_u32(8, h)
	data.encode_u32(12, 1)
	data.encode_u32(16, 0x5650)
	data.encode_u32(20, depth)
	for c in 4:
		for k in 3: data.encode_u32(24 + c * 12 + k * 4, int(channels[c][k]))
	return data

## Decodes with the compiled reader where there is one, then with the
## GDScript one: [native image, GDScript image].
static func _both(data: PackedByteArray) -> Array:
	var had := ELTexture.native
	var compiled: Image = ELTexture.decode(data) if had else null
	ELTexture.native = false
	var script := ELTexture.decode(data)
	ELTexture.native = had
	return [compiled, script]

## Damaged texture headers are refused by both readers (the compiled one
## used a header's shift directly, and a shift of 64 is undefined in C);
## sound ones decode alike in both.
func _damaged_headers() -> void:
	var c565 := [[0, 0, 0], [0xf800, 11, 5], [0x7e0, 5, 6], [0x1f, 0, 5]]
	var c4444 := [[0xf000, 12, 4], [0xf00, 8, 4], [0xf0, 4, 4], [0xf, 0, 4]]
	var c8888 := [[0xff000000, 24, 8], [0xff0000, 16, 8], [0xff00, 8, 8], [0xff, 0, 8]]
	var native := ELTexture.native
	for sound: Array in [["565", _masked(16, 8, 16, c565, 256)], ["4444", _masked(16, 8, 16, c4444, 256)], ["8888", _masked(16, 8, 32, c8888, 512)]]:
		var images := _both(sound[1])
		check(images[1] != null and images[1].get_size() == Vector2i(16, 8), "a sound %s texture decodes" % sound[0])
		if native: check(images[0] != null and images[1] != null and images[0].get_data() == images[1].get_data(), "the compiled and GDScript readers agree on a %s texture" % sound[0])
	var shifted := c565.duplicate(true)
	shifted[1] = [0xf800, 64, 5]
	var wide_bits := c565.duplicate(true)
	wide_bits[2] = [0x7e0, 5, 40]
	var stray := c565.duplicate(true)
	stray[3] = [0x1f, 3, 5]
	var outside := c565.duplicate(true)
	outside[1] = [0x1f800, 11, 6]
	var ghost := c565.duplicate(true)
	ghost[0] = [0, 0, 3]
	var damaged := {
		"a channel shifted by 64": _masked(16, 8, 16, shifted, 256),
		"a channel shifted past a 16-bit pixel": _masked(16, 8, 16, [[0, 0, 0], [0xf800, 16, 5], [0x7e0, 5, 6], [0x1f, 0, 5]], 256),
		"a channel of 40 bits": _masked(16, 8, 16, wide_bits, 256),
		"a mask that does not match its shift": _masked(16, 8, 16, stray, 256),
		"a mask wider than the pixel": _masked(16, 8, 16, outside, 256),
		"bits without a mask": _masked(16, 8, 16, ghost, 256),
		"24 bits a pixel": _masked(16, 8, 24, c565, 384),
		"no bits a pixel": _masked(16, 8, 0, c565, 256),
		"no width": _masked(0, 8, 16, c565, 256),
		"a width of 2^31": _masked(0x80000000, 8, 16, c565, 256),
		"a huge size": _masked(65536, 65536, 16, c565, 256),
		"pixels short of the size": _masked(16, 8, 16, c565, 255),
		"8888 pixels short of the size": _masked(16, 8, 32, c8888, 300)}
	var dxt := _masked(16, 16, 0, c565, 64)
	dxt.encode_u32(16, 0x31545844)   # "DXT1", whose 16×16 level needs 128 bytes
	damaged["a DXT1 level short of its size"] = dxt
	var odd := _masked(6, 6, 0, c565, 64)
	odd.encode_u32(16, 0x31545844)
	damaged["a DXT1 level of part blocks"] = odd
	for what: String in damaged:
		var images := _both(damaged[what])
		check(images[0] == null and images[1] == null, "a texture with %s is refused by both readers" % what)
	# Arena cutouts' later levels go through the same reader.
	var cutout := _masked(8, 8, 16, [[0x8000, 15, 1], [0x7c00, 10, 5], [0x3e0, 5, 5], [0x1f, 0, 5]], 8 * 8 * 2 + 4 * 4 * 2 + 2 * 2 * 2 + 2)
	cutout.encode_u32(12, 4)
	cutout.encode_u32(16, 0x5551)
	cutout.encode_u32(20, 16)
	var base := ELTexture.decode(cutout)
	check(base != null and ELTexture.authored_mask_mipmaps(cutout, base) != null, "a sound cutout's levels decode")
	if base != null:
		cutout.encode_u32(28, 64)
		check(ELTexture.authored_mask_mipmaps(cutout, base) == null, "a cutout with a damaged header gives no levels")

## The compiled and GDScript readers give the same bytes for every masked
## and run-length texture of a few of the game's folders.
func _readers_agree(data: ELProfile) -> void:
	if not ELTexture.native: return
	var archive: ELArchive = data.archives.get("textures")
	if archive == null: return
	var compared := 0
	var differ := 0
	for name: String in archive.entries:
		if name.get_extension() != "mmp" or not (name.begins_with("heroes/") or name.begins_with("effects/") or name.begins_with("interface/")): continue
		var bytes := archive.read(name)
		if bytes.size() < 20 or bytes.slice(16, 19) == "DXT".to_ascii_buffer(): continue
		var images := _both(bytes)
		compared += 1
		if (images[0] == null) != (images[1] == null) or (images[0] != null and images[0].get_data() != images[1].get_data()): differ += 1
	check(compared > 100 and differ == 0, "the compiled and GDScript readers agree on %d of the game's textures (%d differ)" % [compared, differ])

func _run() -> void:
	_damaged_headers()
	var data := _profile("el2")
	if data == null:
		print("SKIP: the second game is not imported here; its textures are not read")
		print("TEXTURE SAFETY: %d failure(s)" % failures.size())
		quit(0 if failures.is_empty() else 1)
		return
	_readers_agree(data)

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
