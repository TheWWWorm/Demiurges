extends SceneTree
## First-game map picking check: for each visible figure and building on the
## first mission, samples its drawn body on screen and reports the share of
## points that pick it (hover and click use the same pick). Points around a
## figure but off its drawn box need not pick it (the margin ring is shown).

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
	var args := OS.get_cmdline_user_args()
	var margin := 0.25
	var failures := 0
	for zoom_at: float in [map.zoom, map.zoom_limits.y]:
		for turn: float in [0.0, 1.2]:
			var inside := Vector2i.ZERO
			var near := Vector2i.ZERO
			for id: int in map.state.objects:
				var item: Dictionary = map.state.objects[id]
				if not item.alive or not item.visible or not item.get("placed", true): continue
				var kind := str(item.get("type", ""))
				var group := str(item.get("group", ""))
				if not (kind in ["hero", "monster"] or group in ELAdventureView.FIRST_SITE_GROUPS or ELMapPickups.is_pickup(item) or ELFirstScenario.is_castle(item)): continue
				var box := map.world.object_bounds(id)
				if not box.has_volume(): continue
				map.target = map.world.to_global(box.get_center() * Vector3(1, 0, 1))
				map.zoom = zoom_at
				map.yaw = ELAdventureView.FIRST_YAW + turn
				map._update_camera()
				var rect := _screen_rect(map, box)
				if rect.size.x < 2: continue
				var got := Vector2i.ZERO
				var ring := Vector2i.ZERO
				var miss := []
				for gy in 9:
					for gx in 9:
						var f := Vector2((gx + 0.5) / 9.0, (gy + 0.5) / 9.0) * (1.0 + 2.0 * margin) - Vector2(margin, margin)
						var at := rect.position + rect.size * f
						var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(map.camera.project_ray_origin(at), map.camera.project_ray_normal(at))
						if hit == null: continue
						var chosen := map._object_at(Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL, at)
						var picked := chosen == id
						var body := f.x >= 0.0 and f.x <= 1.0 and f.y >= 0.0 and f.y <= 1.0
						# A figure's body is where the ray meets its drawn box: with
						# a turned view the corners of the box's screen rectangle
						# show the ground around it, which picks the ground.
						if body and kind in ["hero", "monster"] and box.intersects_ray(map.world.to_local(map.camera.project_ray_origin(at)), map.world.global_basis.inverse() * map.camera.project_ray_normal(at)) == null: continue
						if body:
							got.y += 1
							if picked: got.x += 1
							else: miss.append("%d,%d:%s" % [gx, gy, str(map.state.object(chosen).get("name", chosen)).left(8)])
						else:
							ring.y += 1
							if picked: ring.x += 1
				inside += got
				# Figures take a click over nearly all their drawn body, also
				# when it stands in front of a building (a hero by its castle).
				if kind in ["hero", "monster"] and got.x < int(got.y * 0.85):
					failures += 1
					print("FAIL: %s %s picked on %d/%d of its body (yaw+%.1f)" % [kind, item.get("name", id), got.x, got.y, turn])
				near += ring
				if "--verbose" in args: print("%-8s %-22s %4.0fx%-4.0f body %2d/%2d ring %2d/%2d miss %s" % [kind if kind in ["hero", "monster"] else group.left(8), str(item.get("name", id)).left(22), rect.size.x, rect.size.y, got.x, got.y, ring.x, ring.y, " ".join(miss)])
			print("zoom %.0f yaw+%.1f: body %d/%d (%.0f%%), margin ring %d/%d (%.0f%%)" % [zoom_at, turn, inside.x, inside.y, 100.0 * inside.x / maxi(inside.y, 1), near.x, near.y, 100.0 * near.x / maxi(near.y, 1)])
	print("PASS: figure bodies pick" if failures == 0 else "FAILURES: %d" % failures)
	view.queue_free()
	quit(1 if failures > 0 else 0)
