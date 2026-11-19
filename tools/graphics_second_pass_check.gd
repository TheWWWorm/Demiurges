extends SceneTree
## Asset-free check for blood-stain rotation and its seeded particle stream.
## Run from the repository root with Demiurges' Godot 4.7 runtime:
##   godot --headless --path game --script ../tools/graphics_second_pass_check.gd
## It does not load source-game art or edit persistent player preferences.

var checks := 0
var failures: Array[String] = []

func check(ok: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + description)
	if not ok: failures.append(description)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_blood_stream()
	print("SECOND PASS PRESENTATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _blood_stream() -> void:
	# Reference captured from the delivered V1 implementation with the same
	# seed and two bursts. V2's extra random draw for yaw changed this state.
	var blood := ELCombatBlood.new()
	root.add_child(blood)
	blood.set_process(false)
	blood.rng.seed = 1729
	var shader := Shader.new()
	shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(1.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	blood._drop_node = blood._layer(QuadMesh.new(), material, ELCombatBlood.DROP_LIMIT)
	blood._print_node = blood._layer(PlaneMesh.new(), material, ELCombatBlood.PRINT_LIMIT)
	blood.burst(Vector3(2, 3, -4))
	blood.burst(Vector3(-2, 1, 6), "Plant")
	check(blood.rng.state == 1845242196327316311, "print rotation preserves the original seeded random sequence across later bursts")
	check((blood.drops[45].v as Vector3).distance_to(Vector3(0.17628, -0.310854, 0)) < 0.000002 and blood.prints[16].cell == Vector2i(1, 2), "later blood trajectories and atlas choices match the pre-rotation reference")
	check(not is_equal_approx(blood.prints[0].yaw, blood.prints[-1].yaw), "ground stains still receive varied orientations")
	blood.free()
