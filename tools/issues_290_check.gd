extends SceneTree
## First-game map picking near creatures: a mouse pointer on the ground next
## to a creature (its guarded cells) picks that ground cell, not the creature,
## unless the creature's drawn body is under the pointer; a pointer on the
## creature's own cell or its body picks it. A tap keeps the wider reach.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + message)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _screen_rect(map: ELAdventureView, box: AABB) -> Rect2:
	var rect := Rect2()
	var first := true
	for i in 8:
		var corner := map.world.to_global(box.get_endpoint(i))
		if map.camera.is_position_behind(corner): continue
		var p := map.camera.unproject_position(corner)
		rect = Rect2(p, Vector2.ZERO) if first else rect.expand(p)
		first = false
	return rect

## Screen position of a ground point (map cells).
func _screen_of(map: ELAdventureView, cell_point: Vector2) -> Vector2:
	var cell := ELAdventureTerrain.CELL
	var ground := map.state.map.surface_height(cell_point)
	return map.camera.unproject_position(map.world.to_global(Vector3(cell_point.x * cell, ground, -cell_point.y * cell)))

func _run() -> void:
	root.size = Vector2i(1280, 960)
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	var campaign := ELCampaign.new()
	campaign.load_campaign(view.profiles.el1, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	view.settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(view.settings).persist = false
	await view._begin_campaign("el1", row, 1)
	var map: ELAdventureView = view.campaign_view
	await frames(10)
	if map.tutorial_panel != null and map.tutorial_panel.visible: map.tutorial_panel.close()
	ELFog.reveal_for_console(map.state, map.state.current_player, true)
	await frames(3)
	var occupied := {}
	for id: int in map.state.objects:
		var item: Dictionary = map.state.objects[id]
		if not item.alive or not item.visible or not item.get("placed", true): continue
		var size: Vector2i = map.director.grid.footprints.get(id, {}).get("size", Vector2i.ONE)
		for dy in size.y:
			for dx in size.x: occupied[Vector2i(int(item.x) + dx, int(item.y) + dy)] = id
	var monsters := 0
	for turn: float in [0.0, 1.2, 3.1]:
		var mouse := Vector2i.ZERO
		var tap := Vector2i.ZERO
		for id: int in map.state.objects:
			var item: Dictionary = map.state.objects[id]
			if item.get("type") != "monster" or not item.alive or not item.visible or not item.get("placed", true): continue
			var box := map.world.object_bounds(id)
			if not box.has_volume(): continue
			monsters += 1
			map.target = map.world.to_global(box.get_center() * Vector3(1, 0, 1))
			map.yaw = ELAdventureView.FIRST_YAW + turn
			map._update_camera()
			var body := _screen_rect(map, box)
			var name := str(item.get("name", id))
			# On the creature: its own cell and the middle of its drawn body.
			var own := _screen_of(map, Vector2(float(item.x) + 0.5, float(item.y) + 0.5))
			var hit: Variant = map._ground_hit(own)
			check(hit != null and map._object_at(Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL, own) == id, "%s: its own cell picks it (yaw+%.1f)" % [name, turn])
			var middle := body.get_center()
			hit = map._ground_hit(middle)
			check(hit != null and map._object_at(Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL, middle) == id, "%s: its drawn body picks it (yaw+%.1f)" % [name, turn])
			# Next to the creature: points in the eight neighbouring cells,
			# off its drawn body, pick the ground (or whatever stands there).
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var cell := Vector2i(int(item.x) + dx, int(item.y) + dy)
					if (dx == 0 and dy == 0) or occupied.has(cell): continue
					for sy in 3:
						for sx in 3:
							var at := _screen_of(map, Vector2(cell) + Vector2(0.2 + 0.3 * sx, 0.2 + 0.3 * sy))
							if body.grow(8.0).has_point(at): continue
							hit = map._ground_hit(at)
							if hit == null: continue
							var point := Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL
							if Vector2i(floori(point.x), floori(point.y)) != cell: continue
							mouse.y += 1
							tap.y += 1
							if map._object_at(point, at) == id:
								mouse.x += 1
								check(false, "%s: ground at %s next to it picks it (yaw+%.1f)" % [name, point, turn])
							if map._object_at(point, at, true) == id: tap.x += 1
		print("yaw+%.1f: ground next to creatures picked by mouse %d/%d, by tap %d/%d" % [turn, mouse.x, mouse.y, tap.x, tap.y])
		if turn == 0.0: check(tap.x > 0, "a tap keeps some reach around a creature")
	check(monsters > 0, "the mission has creatures to test")
	print("PASS: ground next to creatures picks the ground" if failures == 0 else "FAILURES: %d" % failures)
	view.queue_free()
	quit(1 if failures > 0 else 0)
