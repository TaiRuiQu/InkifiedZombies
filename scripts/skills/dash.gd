extends RefCounted

static func cast(player: Node3D) -> void:
	var input_vec: Vector2 = player.get_meta("remote_input", Input.get_vector("move_left", "move_right", "move_forward", "move_back"))
	var direction: Vector3 = Basis(Vector3.UP, player.head.rotation.y) * Vector3(input_vec.x, 0, input_vec.y)
	if direction.length() < 0.1:
		direction = -player.camera.global_transform.basis.z
	direction.y = 0.0
	player.dash_dir = direction.normalized()
	player.dash_time = 0.16
	player._dash_damage_done = false
	player.invuln_time = maxf(player.invuln_time, 0.3)
	player.add_trauma(0.16)
	Sfx.play("dash", -2.0)
