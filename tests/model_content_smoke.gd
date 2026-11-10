extends SceneTree

## Content regression: both selectable arenas and every first-person assembly.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arena_positions: Array[Vector3] = []
	for id: String in MapDB.ids():
		var arena := MapBuilder.new()
		root.add_child(arena)
		arena.configure(id)
		arena.build()
		assert(arena.spawn_positions.size() == 8, "Each arena requires eight clear spawn lanes")
		assert(arena.get_node_or_null("ArchitecturalDetails") != null, "Arena detail pass missing")
		arena_positions.append(arena.definition.well_position)
		print("[content] arena=%s nodes=%d detail_batches=%d" % [id, arena.get_child_count(), arena.get_node("ArchitecturalDetails").get_child_count()])
		arena.queue_free()
		await process_frame
	assert(arena_positions.size() >= 2 and arena_positions[0] != arena_positions[1], "Arena layouts must differ")
	for id: String in WeaponDB.all_ids():
		var model := WeaponModel.new()
		root.add_child(model)
		model.build(id)
		assert(model.muzzle != null, "Weapon has no muzzle: " + id)
		assert(model.support_hand != null, "Weapon has no support hand: " + id)
		assert(model.get_child_count() >= 32, "Weapon assembly lacks its detail pass: " + id)
		model.shot_age = 0.0
		model.animate(0.04, true, 0.5)
		for item: Dictionary in model.moving_parts:
			assert(item.part.position.is_finite(), "Invalid weapon animation")
		print("[content] weapon=%s parts=%d moving=%d" % [id, model.get_child_count(), model.moving_parts.size()])
		model.queue_free()
		await process_frame
	var view := WeaponView.new()
	root.add_child(view)
	for id: String in WeaponDB.all_ids():
		view.set_weapon(id)
		view.start_reload(1.0)
		view.notify_fire()
		view.update_motion(0.1, 5.0, true)
		assert(view.muzzle != null and view.muzzle_world().is_finite(), "View assembly failed: " + id)
		view.finish_reload()
		await process_frame
	view.queue_free()
	await process_frame
	print("[content] PASS: all arenas and all weapons built, switched and animated")
	quit()
