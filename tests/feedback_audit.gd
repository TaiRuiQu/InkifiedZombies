extends SceneTree

var main: Node3D
var player: Node3D
var skill_db: Script
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("[feedback] FAIL " + label)

func _run() -> void:
	root.get_node("Game")._test_profile = true
	root.get_node("Settings").save_path = "user://feedback_audit.cfg"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.start_run()
	main.director.stop()
	main.hud.clear_banner()
	player = main.player
	skill_db = load("res://scripts/skills/skill_db.gd")
	player.invuln_time = 999.0
	await create_timer(0.2).timeout
	await _crates()
	await _entries()
	_slopes()
	main._replace_map("bamboo_night")
	await create_timer(0.2).timeout
	await _entries()
	main._replace_map("courtyard")
	await create_timer(0.2).timeout
	await _refresh()
	await _scope()
	await _spells()
	print("[feedback] RESULT checks=%d failures=%d" % [checks, failures])
	root.get_node("Sfx").shutdown()
	await create_timer(0.15).timeout
	quit(0 if failures == 0 else 1)

func _crates() -> void:
	for group in main.map.get_children():
		if not String(group.name).begins_with("Crates"):
			continue
		for crate in group.get_children():
			if not crate is StaticBody3D:
				continue
			var collider: CollisionShape3D = crate.get_child(0)
			var size: Vector3 = collider.shape.size
			var center: Vector3 = collider.position
			# Approach from whichever side of the cluster is open.
			var side := 1.0 if center.z > 0.5 else -1.0
			var approach := Vector3(0, 0, side)
			player.position = group.to_global(center * Vector3(1, 0, 1) + approach * (size.z * 0.5 + 1.0)) + Vector3.UP * 0.05
			player.velocity = Vector3.ZERO
			player.head.rotation = Vector3(0, group.rotation.y + (PI if side < 0 else 0.0), 0)
			player.set_controls(true)
			await create_timer(0.2).timeout
			var direction: Vector3 = group.basis * -approach
			player.velocity = direction * float(player.get_script().WALK_SPEED)
			Input.action_press("move_forward")
			Input.action_press("jump")
			var reached := false
			for frame in 55:
				await physics_frame
				if frame == 2:
					Input.action_release("jump")
				var local: Vector3 = group.to_local(player.global_position)
				if absf(local.z - center.z) < 0.2 and local.y > size.y:
					reached = true
					break
			Input.action_release("move_forward")
			Input.action_release("jump")
			player.velocity.x = 0.0
			player.velocity.z = 0.0
			await create_timer(0.55).timeout
			check(reached and player.is_on_floor() and absf(player.position.y - size.y) < 0.08,
				"jump and stand on %s/%s (feet=%.2f top=%.2f)" % [group.name, crate.name, player.position.y, size.y])
	player.set_controls(false)
	player.position = main.map.player_spawn
	player.velocity = Vector3.ZERO
	print("[feedback] actual crate jumps checked")

func _entries() -> void:
	var enemies: Array[Node3D] = []
	var entered: Array[bool] = []
	var ids := EnemyDB.TYPES.keys()
	for i in main.map.spawn_positions.size():
		var pos: Vector3 = main.map.spawn_positions[i]
		check(Vector2(pos.x, pos.z).length() > MapBuilder.ARENA_RADIUS + 4.0, "spawn %d outside arena" % i)
		var enemy: Node3D = main.director.debug_spawn(ids[i % ids.size()], pos)
		main.director._set_entry_route(enemy, pos)
		enemy.speed = 14.0
		enemies.append(enemy)
		entered.append(false)
	for frame in 240:
		await physics_frame
		for i in enemies.size():
			var enemy := enemies[i]
			# Ranged enemies may strafe back out after completing their entry.
			entered[i] = entered[i] or (enemy.entry_target == Vector3.INF and Vector2(enemy.position.x, enemy.position.z).length() < MapBuilder.GATE_RADIUS)
	for i in enemies.size():
		var enemy := enemies[i]
		check(entered[i],
			"enemy %d enters without getting stuck at boundary (position=%s)" % [i, enemy.position])
		enemy.queue_free()
	await physics_frame
	# A player still cannot leave through the same entrance.
	player.position = Vector3(MapBuilder.ARENA_RADIUS - 1.5, 0.05, 0)
	player.velocity = Vector3.RIGHT * 10.0
	player.move_and_collide(Vector3.RIGHT * 4.0)
	check(player.position.x < MapBuilder.ARENA_RADIUS, "gate boundary still contains players")
	player.position = main.map.player_spawn
	player.velocity = Vector3.ZERO
	print("[feedback] outside spawns and eight physical entrances checked")

func _slopes() -> void:
	var count := 0
	for hill in main.map.get_children():
		if not String(hill.name).begins_with("GreenSlope_"):
			continue
		count += 1
		var from: Vector3 = hill.position + Vector3.UP * 100.0
		var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * 150.0, 1)
		var hit: Dictionary = main.map.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.position.y > 1.0, "green slope %d has solid visible surface" % count)
	check(count == 9, "all nine green slopes tested")
	var ridge := main.map.get_node_or_null("GreenRidgeTerrain") as MeshInstance3D
	check(ridge != null and ridge.mesh.get_faces().size() > 1000, "near green ridge has actual terrain geometry")
	var ridge_query := PhysicsRayQueryParameters3D.create(Vector3(98, 60, 0), Vector3(98, -10, 0), 1)
	var ridge_hit: Dictionary = main.map.get_world_3d().direct_space_state.intersect_ray(ridge_query)
	check(not ridge_hit.is_empty() and ridge_hit.position.y > 5.0, "green terrain surface has solid collision")

func _refresh() -> void:
	var game := root.get_node("Game")
	game.wave = 3
	game.set_state(game.State.UPGRADE)
	paused = true
	main.upgrades.open(3, UpgradeDB.roll(player, 3))
	var starting_health: float = player.health
	for attempt in 3:
		var previous: Array = main.upgrades._cards.map(func(card): return card.data.id)
		main.upgrades._on_refresh()
		check(main.upgrades.refreshes_left == 2 - attempt, "refresh spends one charge while paused")
		check(main.upgrades._cards.size() == 3, "refresh returns three cards")
		for card in main.upgrades._cards:
			check(not previous.has(card.data.id), "refresh prefers a different set")
		await process_frame
	var final_cards: Array = main.upgrades._cards.map(func(card): return card.data.id)
	main.upgrades._on_refresh()
	check(final_cards == main.upgrades._cards.map(func(card): return card.data.id), "fourth refresh is rejected")
	check(player.health == starting_health and player.upgrade_counts.is_empty(), "refresh never applies a card or heal")
	main.upgrades.open(4, UpgradeDB.roll(player, 4))
	check(main.upgrades.refreshes_left == 3 and main.upgrades._refresh.enabled, "next wave resets three charges")
	main.upgrades._on_skip()
	main.upgrades._on_refresh()
	check(main.upgrades.refreshes_left == 3, "refresh rejected during card confirmation")
	main.upgrades.close()
	paused = false
	game.set_state(game.State.PLAYING)
	await process_frame
	print("[feedback] refresh budget, paused input and choice locking checked")

func _scope() -> void:
	player.unlock_weapon("cinnabar_rifle")
	player.switch_to_index(player.owned_weapons.find("cinnabar_rifle"))
	await process_frame
	var model: Node3D = player.view.model
	var tube_count := 0
	for part in model.get_children():
		if String(part.name).begins_with("ScopeTube"):
			tube_count += 1
			check(not part.mesh.cap_top and not part.mesh.cap_bottom, "scope tube/collar is open")
	check(tube_count == 4, "scope and both detail collars audited")
	var lens: MeshInstance3D = model.get_node("ScopeGlass")
	check(lens.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and lens.material_override.albedo_color.a < 0.1,
		"scope lens transmits the world")
	# Ray through the geometric sight axis must hit no opaque viewmodel faces.
	var ray_from := Vector3(0, 0.135, 0.2)
	var ray_to := Vector3(0, 0.135, -1.2)
	var intersections := 0
	for part in model.get_children():
		if not part is MeshInstance3D or part == lens:
			continue
		var faces: PackedVector3Array = part.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(ray_from, ray_to, part.transform * faces[i], part.transform * faces[i + 1], part.transform * faces[i + 2]) != null:
				intersections += 1
	check(intersections == 0, "opaque geometry never blocks scope sight axis")

func _spells() -> void:
	player.position = main.map.player_spawn
	for id in skill_db.ids():
		player.skills[id] = true
		player.skill_cooldowns[id] = 0.0
		check(skill_db.cast(id, player), "skill casts: " + id)
		check(not skill_db.cast(id, player), "skill cooldown still enforced: " + id)
	check(get_nodes_in_group("spell_effects").size() == 3, "three distinct cast effects")
	for projectile in get_nodes_in_group("projectiles"):
		if projectile.spell_id == "talisman":
			check(projectile._trail.amount == 32, "fire talisman has its own flame trail")
			projectile._explode(player.position + Vector3(0, 0.1, -4))
	await create_timer(1.8).timeout
	check(get_nodes_in_group("spell_effects").is_empty(), "all spell effects release after their lifetime")
