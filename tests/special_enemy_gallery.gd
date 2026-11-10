extends SceneTree

var main: Node3D
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func shot(label: String, delay: float = 0.08) -> void:
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dev_shots/special_%s.png" % label)
	print("[special-gallery] ", label)

func wait_state(enemy: Node3D, expected: String, maximum: float = 7.0, expected_kind: String = "") -> bool:
	var deadline := Time.get_ticks_msec() + int(maximum * 1000.0)
	while is_instance_valid(enemy) and (enemy.state != expected or (not expected_kind.is_empty() and enemy.attack_kind != expected_kind)) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not is_instance_valid(enemy) or enemy.state != expected or (not expected_kind.is_empty() and enemy.attack_kind != expected_kind):
		push_error("[special-gallery] missed state " + expected)
		return false
	return true

func _run() -> void:
	root.get_node("Game")._test_profile = true
	root.get_node("Settings").save_path = "user://special_gallery.cfg"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.start_run()
	main.director.stop()
	main.player.set_controls(false)
	main.player.set_physics_process(false)
	main.player.invuln_time = 999.0
	main.player.view.visible = false
	main.hud.visible = false
	camera = Camera3D.new()
	camera.fov = 52.0
	main.add_child(camera)
	camera.current = true
	for id in ["leaper", "reaver"]:
		main.player.position = Vector3(0, 0.05, 17)
		var distance := 8.0 if id == "leaper" else 3.1
		var enemy: Node3D = main.director.debug_spawn(id, Vector3(0, 0.05, 17 - distance))
		enemy.frozen = true
		enemy.rotation.y = PI
		await create_timer(0.5).timeout
		enemy.complete_spawn_visual()
		var head: Vector3 = enemy.anim.head.global_position
		camera.position = head + Vector3(1.4, 0.15, 2.8)
		camera.look_at(enemy.global_position + Vector3.UP * enemy.height * 0.55, Vector3.UP)
		await shot(id + "_model")
		camera.position = Vector3(7.5, 5.5, 22)
		camera.look_at(Vector3(0, 0.9, 17 - distance * 0.45), Vector3.UP)
		enemy.frozen = false
		if not await wait_state(enemy, "windup", 7.0, "leap_cut" if id == "leaper" else "spin_cut"):
			quit(1)
			return
		await shot(id + "_warning", 0.2)
		if not await wait_state(enemy, "leap" if id == "leaper" else "spin"):
			quit(1)
			return
		await shot(id + "_attack", 0.22 if id == "leaper" else 0.35)
		if not await wait_state(enemy, "recover"):
			quit(1)
			return
		await shot(id + "_recovery", 0.12)
		enemy.free()
	main._quit_game()
