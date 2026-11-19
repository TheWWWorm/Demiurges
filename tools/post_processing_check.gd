extends SceneTree
## Asset-free rendering check: bounded sharpening and gamma compositing after
## sharpening plus interface. No settings file or original art is accessed.
const Sharpen := preload("res://src/render/sharpen_layer.gd")
const Gamma := preload("res://src/render/gamma_layer.gd")
const SIZE := Vector2i(768, 320)
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sharpen := Sharpen.new()
	var gamma := Gamma.new()
	check(not sharpen.visible and not gamma.visible, "default post-processing skips both screen passes")
	sharpen.apply(2)
	gamma.apply(0.3)
	check(sharpen.visible and gamma.visible and gamma.layer > sharpen.layer, "requested sharpening runs below the final gamma pass")
	sharpen.apply(0)
	gamma.apply(0)
	check(not sharpen.visible and not gamma.visible, "turning the options off immediately removes both effects")
	check(is_equal_approx(Gamma.exponent(0.3), 1.0 / 1.75) and is_equal_approx(Gamma.exponent(-0.5), 1.0 / 0.875), "the original positive and negative gamma curves are preserved")
	sharpen.free()
	gamma.free()
	if "--render" in OS.get_cmdline_user_args(): await _render()
	print("POST PROCESSING: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _pattern() -> Image:
	var image := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	for y in SIZE.y:
		for x in SIZE.x:
			var colour: Color
			if x < 192:
				var value := 0.25 if x < 96 else 0.60
				colour = Color(value, value, value)
			elif x < 512:
				var value := 0.45 + 0.13 * sin((x - 192) * 0.15) + 0.08 * sin(y * 0.22)
				colour = Color(value * 0.9, value, value * 0.8)
			else:
				var value := 0.5 + 0.5 * sin(x * 0.18) * cos(y * 0.15)
				colour = Color(0.15 + 0.30 * value, 0.32 + 0.15 * value, 0.52 - 0.15 * value)
			image.set_pixel(x, y, colour)
	return image

func _capture() -> Image:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _range_error(source: Image, result: Image) -> float:
	var error := 0.0
	for y in range(60, SIZE.y - 8):
		for x in range(2, SIZE.x - 2):
			var centre := source.get_pixel(x, y)
			var low := Vector3(centre.r, centre.g, centre.b)
			var high := low
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var sample := source.get_pixelv(Vector2i(x, y) + offset)
				var value := Vector3(sample.r, sample.g, sample.b)
				low = low.min(value)
				high = high.max(value)
			var actual := result.get_pixel(x, y)
			for channel in 3:
				error = maxf(error, maxf(low[channel] - actual[channel], actual[channel] - high[channel]))
	return error

func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "post-processing pixels require a real windowed renderer")
		return
	root.size = SIZE
	root.content_scale_size = SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var backdrop := CanvasLayer.new()
	backdrop.layer = -20
	root.add_child(backdrop)
	var art := TextureRect.new()
	art.texture = ImageTexture.create_from_image(_pattern())
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.size = Vector2(SIZE)
	backdrop.add_child(art)
	var sharpen := Sharpen.new()
	root.add_child(sharpen)
	var interface := CanvasLayer.new()
	root.add_child(interface)
	var marker := ColorRect.new()
	marker.position = Vector2(690, 18)
	marker.size = Vector2(40, 20)
	marker.color = Color(0.70, 0.18, 0.10)
	interface.add_child(marker)
	var title := Label.new()
	title.position = Vector2(15, 13)
	title.text = "SYNTHETIC POST-PROCESSING / " + RenderingServer.get_current_rendering_method()
	title.add_theme_font_size_override("font_size", 16)
	interface.add_child(title)
	var gamma := Gamma.new()
	var base := await _capture()
	# Reconstruct the pre-update unclamped high-pass for a measured A/B.
	var legacy := Shader.new()
	legacy.code = Sharpen.SHADER.replace("clamp(result, low, high)", "clamp(result, 0.0, 1.0)")
	(sharpen.rect.material as ShaderMaterial).shader = legacy
	sharpen.apply(2)
	var old := await _capture()
	var corrected := Shader.new()
	corrected.code = Sharpen.SHADER
	(sharpen.rect.material as ShaderMaterial).shader = corrected
	sharpen.apply(2)
	var bounded := await _capture()
	var old_error := _range_error(base, old)
	var new_error := _range_error(base, bounded)
	check(old_error > 0.03 and new_error < 0.008, "sharpening no longer creates colours outside the local range (%.4f -> %.4f)" % [old_error, new_error])
	check(_distance(base.get_pixel(40, 160), bounded.get_pixel(40, 160)) < 0.008, "a flat painted region retains its original colour")
	var detail_change := 0.0
	for x in range(240, 480): detail_change += _distance(base.get_pixel(x, 160), bounded.get_pixel(x, 160))
	check(detail_change > 0.15, "bounded sharpening still increases contrast in soft texture detail (sum %.3f)" % detail_change)
	check(_distance(base.get_pixel(710, 28), bounded.get_pixel(710, 28)) < 0.008, "interface elements stay outside the sharpening pass")
	# Exercise the existing gamma layer after sharpening and ordinary UI.
	root.add_child(gamma)
	gamma.apply(0.3)
	var combined := await _capture()
	var exponent := Gamma.exponent(0.3)
	var worst := 0.0
	for at: Vector2i in [Vector2i(710, 28), Vector2i(300, 160), Vector2i(95, 160), Vector2i(600, 120)]:
		var input := bounded.get_pixelv(at)
		var expected := Color(pow(input.r, exponent), pow(input.g, exponent), pow(input.b, exponent))
		worst = maxf(worst, _distance(expected, combined.get_pixelv(at)))
	check(worst < 0.015, "gamma includes the sharpened scene and the finished interface (largest RGB error %.4f)" % worst)
	gamma.apply(0)
	sharpen.apply(0)
	var restored := await _capture()
	check(_distance(base.get_pixel(300, 160), restored.get_pixel(300, 160)) < 0.008, "disabling both effects restores the original image")
	var folder := "user://post_processing"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(folder)
	var names := ["source", "legacy_sharpen", "bounded_sharpen", "combined"]
	var captures := [base, old, bounded, combined]
	for i in names.size():
		var path := folder.path_join("post_%s_%s.png" % [RenderingServer.get_current_rendering_method(), names[i]])
		check(captures[i].save_png(path) == OK, "saved post-processing probe: " + path)
	gamma.free()
	interface.free()
	sharpen.free()
	backdrop.free()
