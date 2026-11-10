class_name RemotePlayer
extends Node3D

## Interpolated presentation for a remote teammate. Damage and collision remain
## on the host's authoritative Player instance; this node only draws snapshots.
var peer_id := 0
var player_name := "守墨人"
var dead := false
var health := 100.0
var max_health := 100.0
var current_weapon := "brush_pistol"
var _target_position := Vector3.ZERO
var _target_yaw := 0.0
var _pitch := 0.0
var _has_snapshot := false
var _phase := 0.0
var _shot_timer := 0.0
var _body: Node3D
var _head: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _gun: Node3D
var _flash: MeshInstance3D
var _label: Label3D
var _team_color: Color = Ink.PLAYER_TRIMS[0]


func setup(id: int, nickname: String, team_index: int = 0) -> void:
	peer_id = id
	player_name = nickname.left(24)
	_team_color = Ink.PLAYER_TRIMS[posmod(team_index, 4)]
	if _label:
		_refresh_label()


func _ready() -> void:
	name = "Teammate%d" % peer_id
	_build_model()
	_refresh_label()
	if not _has_snapshot:
		_target_position = global_position
		_target_yaw = rotation.y


func update_snapshot(data: Dictionary) -> void:
	var raw_position: Variant = data.get("position", data.get("pos", data.get("p", null)))
	if raw_position is Vector3:
		_target_position = raw_position
	elif raw_position is Array and raw_position.size() >= 3:
		_target_position = Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2]))
	_target_yaw = float(data.get("yaw", _target_yaw))
	_pitch = clampf(float(data.get("pitch", _pitch)), -1.4, 1.4)
	health = float(data.get("health", data.get("hp", health)))
	max_health = maxf(1.0, float(data.get("max_health", data.get("max_hp", max_health))))
	dead = bool(data.get("dead", health <= 0.0))
	player_name = String(data.get("name", player_name)).left(24)
	var weapon := String(data.get("weapon", data.get("current_weapon", current_weapon)))
	if weapon != current_weapon:
		current_weapon = weapon
		if _gun:
			_build_weapon()
	if bool(data.get("firing", data.get("shot", false))):
		play_shot()
	if not _has_snapshot or global_position.distance_squared_to(_target_position) > 100.0:
		if is_inside_tree():
			global_position = _target_position
		else:
			position = _target_position
		rotation.y = _target_yaw
	_has_snapshot = true
	_refresh_label()


func play_shot() -> void:
	_shot_timer = 0.09


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func _process(delta: float) -> void:
	if not _body:
		return
	var previous := global_position
	if _has_snapshot:
		global_position = global_position.lerp(_target_position, 1.0 - exp(-delta * 15.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-delta * 18.0))
	var speed := minf((global_position - previous).length() / maxf(delta, 0.001), 8.0)
	_phase += delta * (2.0 + speed * 1.8)
	var stride := sin(_phase) * minf(speed * 0.08, 0.55)
	_left_leg.rotation.x = stride
	_right_leg.rotation.x = -stride
	_left_arm.rotation.x = -0.9 + _pitch * 0.55 - stride * 0.12
	_right_arm.rotation.x = -1.15 + _pitch * 0.8
	_head.rotation.x = _pitch * 0.5
	_body.position.y = absf(sin(_phase * 2.0)) * minf(speed * 0.004, 0.03)
	_body.rotation.z = lerp_angle(_body.rotation.z, PI * 0.45 if dead else 0.0, minf(delta * 5.0, 1.0))
	_body.position.y -= 0.75 if dead else 0.0
	_shot_timer = maxf(_shot_timer - delta, 0.0)
	if _flash:
		_flash.visible = _shot_timer > 0.0 and not dead


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return Ink.part(parent, mesh, color, pos, rot,
		{"outline": 0.004, "wash": 0.3, "wobble": 0.002, "hatch": 0.45})


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = pos
	parent.add_child(joint)
	return joint


func _build_model() -> void:
	_body = _joint(self, Vector3.ZERO)
	_part(_body, Ink.capsule_mesh(0.23, 0.68), Ink.PLAYER_COAT, Vector3(0, 1.06, 0))
	_part(_body, Ink.cylinder_mesh(0.2, 0.34, 0.6, 10), Ink.INK_SOFT, Vector3(0, 0.64, 0))
	_part(_body, Ink.box_mesh(Vector3(0.5, 0.1, 0.34)), _team_color, Vector3(0, 0.88, 0))
	for side in [-1, 1]:
		_part(_body, Ink.box_mesh(Vector3(0.12, 0.65, 0.03)), _team_color,
			Vector3(side * 0.15, 1.12, -0.19), Vector3(0, 0, side * -8))
	_part(_body, Ink.box_mesh(Vector3(0.12, 0.2, 0.035)), Ink.PAPER, Vector3(0, 1.12, -0.24))
	_part(_body, Ink.box_mesh(Vector3(0.07, 0.06, 0.012)), Ink.CINNABAR, Vector3(0, 1.1, -0.265))
	_head = _joint(_body, Vector3(0, 1.54, 0))
	_part(_head, Ink.sphere_mesh(0.2), Ink.PAPER_DARK, Vector3.ZERO)
	_part(_head, Ink.box_mesh(Vector3(0.3, 0.12, 0.06)), Ink.INDIGO, Vector3(0, -0.06, -0.16))
	for side in [-1, 1]:
		_part(_head, Ink.box_mesh(Vector3(0.065, 0.016, 0.018)), Ink.INK,
			Vector3(side * 0.08, 0.04, -0.183), Vector3(0, 0, side * -4))
	_part(_head, Ink.cylinder_mesh(0.025, 0.42, 0.18, 14), Ink.OCHRE_DARK, Vector3(0, 0.19, 0.015))
	_part(_head, Ink.cylinder_mesh(0.03, 0.43, 0.025, 14), Ink.OCHRE, Vector3(0, 0.105, 0.015))
	for side in [-1, 1]:
		var arm := _joint(_body, Vector3(side * 0.32, 1.32, 0))
		_part(arm, Ink.capsule_mesh(0.095, 0.53), Ink.PLAYER_COAT, Vector3(0, -0.24, 0))
		_part(arm, Ink.cylinder_mesh(0.105, 0.09, 0.08, 8), _team_color, Vector3(0, -0.38, 0))
		_part(arm, Ink.sphere_mesh(0.075), Ink.PAPER_DARK, Vector3(0, -0.5, 0))
		var leg := _joint(_body, Vector3(side * 0.14, 0.55, 0))
		_part(leg, Ink.capsule_mesh(0.085, 0.5), Ink.INK_SOFT, Vector3(0, -0.23, 0))
		_part(leg, Ink.box_mesh(Vector3(0.18, 0.12, 0.3)), Ink.ASH_DARK, Vector3(0, -0.48, -0.06))
		_part(leg, Ink.box_mesh(Vector3(0.18, 0.17, 0.07)), _team_color, Vector3(0, -0.3, -0.075))
		if side < 0:
			_left_arm = arm
			_left_leg = leg
		else:
			_right_arm = arm
			_right_leg = leg
	_gun = _joint(_right_arm, Vector3(0, -0.48, -0.08))
	_gun.rotation.x = PI * 0.5
	_build_weapon()
	_label = Label3D.new()
	_label.font = preload("res://assets/fonts/NotoSansSC.ttf")
	_label.font_size = 25
	_label.outline_size = 8
	_label.pixel_size = 0.004
	_label.modulate = Ink.PAPER
	_label.outline_modulate = Ink.INK
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.02
	_label.no_depth_test = false
	add_child(_label)


func _build_weapon() -> void:
	for child in _gun.get_children():
		child.free()
	var length := 0.5
	var radius := 0.035
	match current_weapon:
		"ink_shotgun": length = 0.8
		"wolf_smg": length = 0.6
		"cinnabar_rifle": length = 1.05
		"ink_launcher":
			length = 0.7
			radius = 0.115
		"thunder_crossbow": length = 0.7
	_part(_gun, Ink.box_mesh(Vector3(0.12, 0.12, 0.3)), Ink.INK_SOFT, Vector3(0, 0, -0.1))
	_part(_gun, Ink.cylinder_mesh(radius, radius, length, 10), Ink.ASH_DARK,
		Vector3(0, 0.03, -length * 0.5), Vector3(90, 0, 0))
	_part(_gun, Ink.cylinder_mesh(radius * 1.18, radius * 1.18, 0.035, 10), Ink.CINNABAR,
		Vector3(0, 0.03, -length + 0.07), Vector3(90, 0, 0))
	_part(_gun, Ink.box_mesh(Vector3(0.08, 0.15, 0.09)), Ink.OCHRE_DARK, Vector3(0, -0.1, -0.02))
	if current_weapon == "ink_shotgun":
		_part(_gun, Ink.cylinder_mesh(radius, radius, length, 10), Ink.ASH_DARK,
			Vector3(0.08, 0.03, -length * 0.5), Vector3(90, 0, 0))
	elif current_weapon == "thunder_crossbow":
		for side in [-1, 1]:
			_part(_gun, Ink.box_mesh(Vector3(0.36, 0.035, 0.05)), Ink.OCHRE,
				Vector3(side * 0.2, 0.02, -0.47), Vector3(0, side * -18, 0))
	elif current_weapon == "wolf_smg":
		_part(_gun, Ink.box_mesh(Vector3(0.08, 0.23, 0.12)), Ink.INK, Vector3(0, -0.17, -0.19))
	elif current_weapon == "cinnabar_rifle":
		_part(_gun, Ink.cylinder_mesh(0.04, 0.04, 0.24, 8), Ink.INK,
			Vector3(0, 0.15, -0.22), Vector3(90, 0, 0))
	_flash = MeshInstance3D.new()
	_flash.mesh = Ink.sphere_mesh(0.1, 8, 4)
	_flash.material_override = Ink.glow(Ink.CINNABAR_BRIGHT, true, false)
	_flash.position = Vector3(0, 0.03, -length - 0.035)
	_flash.visible = false
	_gun.add_child(_flash)


func _refresh_label() -> void:
	if _label:
		_label.text = "%s\n%s" % [player_name, "倒地 · 等待波末归队" if dead else "血 %d" % int(ceil(health))]
