class_name WeaponView
extends Node3D

## Procedurally modelled brush-weapons held in first person, with sway,
## bob, recoil, aim-down-sights and reload animation.

var weapon_id := ""
var data: Dictionary = {}
var muzzle: Node3D
var _flash: MeshInstance3D
var _flash_timer := 0.0
var model: Node3D

var base_pos := Vector3(0.27, -0.23, -0.5)
var base_rot := Vector3.ZERO
var aiming := false
var reloading := false
var reload_progress := 0.0
var reload_total := 1.0
var move_speed := 0.0
var grounded := true

var _time := 0.0
var _bob_phase := 0.0
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _kick := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var wall_proximity := 0.0
var _wall_blend := 0.0
var _equip_age := 1.0
var _melee_age := 1.0
var _hit_pause := 0.0
var _dash_pose := 0.0
var _dash_target := false


func _ready() -> void:
	scale = Vector3(0.85, 0.85, 0.85)


func set_weapon(id: String) -> void:
	weapon_id = id
	_equip_age = 0.0
	_melee_age = 1.0
	_hit_pause = 0.0
	data = WeaponDB.get_weapon(id)
	for c in get_children():
		c.visible = false
		c.queue_free()
	model = null
	muzzle = null
	_flash = null
	reloading = false
	reload_progress = 0.0
	base_pos = data.view_pos
	base_rot = Vector3.ZERO
	_sway = Vector2.ZERO
	_sway_target = Vector2.ZERO
	_kick = Vector3.ZERO
	_kick_rot = Vector3.ZERO
	position = base_pos
	rotation = base_rot
	var custom_scene: Variant = data.get("view_scene")
	if custom_scene is String and not String(custom_scene).is_empty():
		custom_scene = load(String(custom_scene))
	if custom_scene is PackedScene:
		model = custom_scene.instantiate() as Node3D
	if model == null:
		model = WeaponModel.new()
		add_child(model)
		(model as WeaponModel).build(String(data.get("model_id", id)))
	else:
		add_child(model)
	model.name = "WeaponModel"
	if model is WeaponModel:
		muzzle = (model as WeaponModel).muzzle
	else:
		muzzle = model.find_child("Muzzle", true, false) as Node3D
	_finish_muzzle()


func _finish_muzzle() -> void:
	if muzzle == null:
		muzzle = Node3D.new()
		muzzle.position = Vector3(0, 0.03, -0.6)
		add_child(muzzle)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	_flash = MeshInstance3D.new()
	_flash.mesh = quad
	_flash.material_override = Ink.glow(Color(1.0, 0.72, 0.35, 0.9), true, true)
	_flash.position = Vector3(0, 0, -0.03)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	muzzle.add_child(_flash)




# --------------------------------------------------------------------------
# Presentation
# --------------------------------------------------------------------------

func notify_look(relative: Vector2) -> void:
	_sway_target += Vector2(-relative.x, -relative.y) * 0.00028
	_sway_target = _sway_target.clamp(Vector2(-0.035, -0.03), Vector2(0.035, 0.03))


func notify_fire() -> void:
	if model is WeaponModel:
		(model as WeaponModel).shot_age = 0.0
	elif model and model.has_method("notify_fire"):
		model.call("notify_fire")
	var weight := 0.7 + float(data.get("recoil", 1.0)) * 0.3
	_kick.z += 0.075 * weight
	_kick_rot.x += 0.10 * weight
	_kick_rot.y += randf_range(-0.02, 0.02)
	_flash_timer = 0.055
	if _flash:
		_flash.visible = true
		_flash.rotation.z = randf() * TAU
		_flash.scale = Vector3.ONE * randf_range(0.85, 1.25)


func set_aiming(value: bool) -> void:
	aiming = value


func update_motion(delta: float, speed: float, is_grounded: bool) -> void:
	_hit_pause = maxf(_hit_pause - delta, 0.0)
	var action_delta := delta if _hit_pause <= 0.0 else 0.0
	_equip_age += delta
	_melee_age += delta
	_wall_blend = lerpf(_wall_blend, wall_proximity, 1.0 - exp(-delta * 14.0))
	_dash_pose = lerpf(_dash_pose, 1.0 if _dash_target else 0.0, 1.0 - exp(-delta * 18.0))
	if model and model.has_method("animate"):
		model.call("animate", action_delta, reloading, reload_progress)
	move_speed = speed
	grounded = is_grounded
	_time += delta
	var damp := 1.0 - exp(-delta * 11.0)
	_sway = _sway.lerp(_sway_target, damp)
	_sway_target = _sway_target.lerp(Vector2.ZERO, damp * 0.7)
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-action_delta * 13.0))
	_kick_rot = _kick_rot.lerp(Vector3.ZERO, 1.0 - exp(-action_delta * 11.0))

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			if _flash:
				_flash.visible = false

	if reloading:
		reload_progress = minf(reload_progress + delta / maxf(reload_total, 0.01), 1.0)

	var target := Vector3(data.get("view_aim", Vector3(0, -0.14, -0.42))) if aiming else Vector3(data.get("view_pos", Vector3(0.27, -0.23, -0.5)))
	base_pos = base_pos.lerp(target, 1.0 - exp(-delta * 13.0))
	var aim_factor := 1.0 if aiming else 0.0

	var bob_amp := (0.006 + minf(move_speed, 9.0) * 0.0011) * (0.25 if aiming else 1.0)
	if not grounded:
		bob_amp *= 0.4
	_bob_phase += delta * (5.0 + move_speed * 1.15)
	var bob := Vector3(cos(_bob_phase * 0.5) * bob_amp, absf(sin(_bob_phase)) * bob_amp * 0.9, 0.0)

	var reload_off := Vector3.ZERO
	var reload_rot := Vector3.ZERO
	if reloading:
		var p := sin(clampf(reload_progress, 0.0, 1.0) * PI)
		reload_off = Vector3(0.0, -0.16, 0.06) * p
		reload_rot = Vector3(-0.55, 0.2, -0.25) * p

	var sway_scale := 0.4 if aiming else 1.0
	var draw_phase := pow(1.0 - clampf(_equip_age / 0.28, 0.0, 1.0), 2.0)
	var melee_phase := sin(clampf(_melee_age / 0.44, 0.0, 1.0) * PI)
	var action_offset := Vector3(0.10, -0.32, 0.12) * draw_phase
	action_offset += Vector3(-0.28, -0.06, -0.22) * melee_phase
	action_offset += Vector3(0.03, -0.18, 0.16) * _dash_pose
	action_offset += Vector3(0.0, -0.08, 0.28) * _wall_blend
	var action_rotation := Vector3(-0.4, -0.12, -0.22) * draw_phase
	action_rotation += Vector3(-0.18, 0.7, -0.85) * melee_phase
	action_rotation += Vector3(-0.45, 0.0, 0.18) * _dash_pose
	action_rotation += Vector3(-0.6, 0.10, 0.12) * _wall_blend
	position = base_pos + bob + _kick + reload_off + action_offset + Vector3(_sway.x, _sway.y, 0.0) * sway_scale
	rotation = base_rot + action_rotation + Vector3(_kick_rot.x + reload_rot.x, _kick_rot.y + _sway.x * 1.5 + reload_rot.y, _kick_rot.z + reload_rot.z)


func start_reload(duration: float) -> void:
	reloading = true
	reload_total = maxf(duration, 0.01)
	reload_progress = 0.0


func finish_reload() -> void:
	reloading = false
	reload_progress = 0.0


func muzzle_world() -> Vector3:
	if muzzle:
		return muzzle.global_position
	return global_position + Vector3(0, 0, -0.6)


func notify_melee() -> void:
	_melee_age = 0.0


func notify_hurt(strength: float, side: float) -> void:
	_kick += Vector3(-side * 0.025, -0.025 - strength * 0.1, 0.045)
	_kick_rot += Vector3(-0.08, side * 0.04, side * 0.1)


func confirm_hit(killed: bool, critical: bool) -> void:
	_hit_pause = maxf(_hit_pause, 0.035 if killed else (0.025 if critical else 0.014))


func set_dashing(value: bool) -> void:
	_dash_target = value


func notify_land() -> void:
	_kick.y -= 0.045
	_kick_rot.x -= 0.055
