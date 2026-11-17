extends SceneTree
## Path-traced flicker of thin blades: the Autochess sideline hero Gamma-200F
## "Tricker" (Etherlords II model he103) has four flat metal blades for wings
## (r_wing2..5) whose vertex normals lie almost in their plane. The tracer
## once reversed such a normal whenever it pointed a hair away from the face
## the ray hit, so with each small turn of the idling wings a blade went from
## sunlit to black and back from one frame to the next (owner report,
## attachments/wings-pt.png).
##
##   godot --path game --rendering-method forward_plus --rendering-driver vulkan \
##       --resolution 1600x900 --script ../tools/path_tracing_wings_check.gd
##
## The hero idles beside the board under the match's own camera. For FRAMES
## frames with tracing off and then on, every frame, the blades' pixels (their
## current triangles projected, two pixels in from their outline) are measured:
## the share of them near black and their mean brightness. Traced, the blades
## may be darker or lighter than the raster, but from one frame to the next
## they may change only about as much as the wings move: the mean change of
## the near-black share and its largest single change are held to limits.
## Prints one PTWINGS line per frame for plotting.
##
## Needs a GPU with hardware ray tracing (else skipped) and the second game's
## files (user://profiles.json).

const HERO := "Gamma-200F \"Tricker\""
const WINGS := ["r_wing2", "r_wing3", "r_wing4", "r_wing5"]
const FRAMES := 90
## A pixel at most this bright (linear luminance of the shown colour) counts
## as near black.
const BLACK := 0.04
## Limits on the traced blades' frame-to-frame change of their near-black
## share: on average and at worst (the reversed normals gave 0.22 and 0.59;
## the raster changes by 0.004 and 0.02).
const MEAN_CHANGE := 0.03
const WORST_CHANGE := 0.12

var failures: Array[String] = []
var model: ELModel

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ELPathTracing.available():
		print("SKIP: no ray-tracing device")
		_finish()
		return
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var profile := ELProfile.new()
	if paths is not Dictionary or not paths.has("el2") or not profile.mount("el2", str(paths.el2)):
		print("SKIP: no second-game files")
		_finish()
		return
	var tracer := ELPathTracing.new()
	root.add_child(tracer)
	var screen := ELAutochessScreen.new()
	root.add_child(screen)
	screen.path_tracing = tracer
	screen.build(profile, ELSettings.new().values)
	var game := ELAutochessMatch.new()
	game.auto_save = false
	game.begin(profile, 777, HERO, [], ["Wom"])
	game.paused = true
	screen.show_match(game, 0, null)
	for i in 30: await process_frame
	model = screen.board.heroes.get(0, {}).get("model")
	check(is_instance_valid(model) and WINGS.all(func(name: String) -> bool: return model.parts.has(name)), "the sideline hero is %s with its four blades" % HERO)
	if not is_instance_valid(model):
		_finish()
		return
	var changes := {}
	for mode in ["raster", "traced"]:
		tracer.set_enabled(mode == "traced")
		for i in (90 if mode == "traced" else 10): await process_frame
		if mode == "traced": check(tracer.enabled and tracer._committed, "tracing runs")
		var dark: Array[float] = []
		var pixels := 0
		for f in FRAMES:
			await RenderingServer.frame_post_draw
			var stats := _measure(root.get_texture().get_image())
			dark.append(stats.dark)
			pixels = maxi(pixels, stats.count)
			print("PTWINGS %s %d dark %.4f mean %.4f pixels %d" % [mode, f, stats.dark, stats.mean, stats.count])
		var steps: Array[float] = []
		for i in dark.size() - 1: steps.append(absf(dark[i + 1] - dark[i]))
		var mean := 0.0
		for step in steps: mean += step
		mean /= maxf(1.0, steps.size())
		changes[mode] = [mean, steps.max()]
		check(pixels > 200, "%s: the blades cover %d pixels" % [mode, pixels])
	var traced: Array = changes.traced
	check(traced[0] <= MEAN_CHANGE and traced[1] <= WORST_CHANGE, "traced blades do not flicker: their near-black share changes by %.3f a frame on average, %.3f at most (raster %.3f, %.3f)" % [traced[0], traced[1], changes.raster[0], changes.raster[1]])
	_finish()

func _finish() -> void:
	print("PATH TRACING WINGS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## The blades' interior pixels in this frame: the share near black and their
## mean brightness.
func _measure(img: Image) -> Dictionary:
	var size := img.get_size()
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	var camera := root.get_camera_3d()
	var lo := Vector2(size)
	var hi := Vector2.ZERO
	for name: String in WINGS:
		var node: MeshInstance3D = model.parts[name]
		if node.mesh == null or not node.is_visible_in_tree(): continue
		var arrays := node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var points := PackedVector2Array()
		for v in vertices: points.append(camera.unproject_position(node.global_transform * v))
		var count := index.size() if not index.is_empty() else vertices.size()
		for t in range(0, count, 3):
			var a := points[index[t] if not index.is_empty() else t]
			var b := points[index[t + 1] if not index.is_empty() else t + 1]
			var c := points[index[t + 2] if not index.is_empty() else t + 2]
			_fill(mask, a, b, c)
			lo = lo.min(a.min(b).min(c))
			hi = hi.max(a.max(b).max(c))
	var total := 0
	var dark := 0
	var sum := 0.0
	var x0 := clampi(int(lo.x), 2, size.x - 3)
	var x1 := clampi(int(hi.x), 2, size.x - 3)
	var y0 := clampi(int(lo.y), 2, size.y - 3)
	var y1 := clampi(int(hi.y), 2, size.y - 3)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if mask.get_pixel(x, y).r < 0.5 or mask.get_pixel(x - 2, y).r < 0.5 or mask.get_pixel(x + 2, y).r < 0.5 or mask.get_pixel(x, y - 2).r < 0.5 or mask.get_pixel(x, y + 2).r < 0.5: continue
			var colour := img.get_pixel(x, y)
			var light := 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
			total += 1
			sum += light
			if light < BLACK: dark += 1
	return {"dark": float(dark) / maxf(1.0, total), "mean": sum / maxf(1.0, total), "count": total}

static func _fill(mask: Image, a: Vector2, b: Vector2, c: Vector2) -> void:
	var area := (b - a).cross(c - a)
	if absf(area) < 0.5: return
	var lo := a.min(b).min(c).floor().max(Vector2.ZERO)
	var hi := a.max(b).max(c).ceil().min(Vector2(mask.get_width() - 1, mask.get_height() - 1))
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			if (b - a).cross(p - a) / area >= 0.0 and (c - b).cross(p - b) / area >= 0.0 and (a - c).cross(p - c) / area >= 0.0:
				mask.set_pixel(x, y, Color.WHITE)
