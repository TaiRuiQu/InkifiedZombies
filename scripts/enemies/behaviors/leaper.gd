extends RefCounted

const WINDUP := 0.75
const FLIGHT_TIME := 0.72
const RADIUS := 2.5
var landing := Vector3.ZERO
var launch := Vector3.ZERO
var flight_elapsed := 0.0
var flight_total := FLIGHT_TIME
var special_cd := 1.0
var telegraph: Node3D
var _landed := false
var _cancelled := false

func update(enemy, direction: Vector3, distance: float, delta: float) -> void:
	if enemy.cooldown > 0.0:
		enemy._move(direction, enemy.speed, delta)
		return
	if distance < 2.6:
		enemy._begin_windup("leaper_melee", 0.42)
		enemy.cooldown = enemy.attack_cd
	elif distance <= 10.5 and special_cd <= 0.0 and enemy.is_on_floor() and enemy._has_line_of_sight():
		landing = enemy.player.global_position
		landing.y = enemy.global_position.y
		launch = enemy.global_position
		_landed = false
		_cancelled = false
		enemy._begin_windup("leap_cut", WINDUP)
		enemy.cooldown = 4.8
		special_cd = 4.8
	else:
		enemy._move(direction, enemy.speed, delta)

func physics_update(enemy, delta: float) -> bool:
	special_cd = maxf(special_cd - delta, 0.0)
	if enemy.state != "leap":
		return false
	flight_elapsed += delta
	enemy.state_timer = maxf(flight_total - flight_elapsed, 0.0)
	# Committed jump: horizontal momentum does not retarget the player midair.
	enemy.velocity.y -= 22.0 * delta
	enemy.move_and_slide()
	if enemy.is_on_wall():
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
	if (enemy.is_on_floor() and flight_elapsed > 0.15) or flight_elapsed > flight_total + 0.60:
		if not _landed:
			_landed = true
			_strike_landing(enemy)
		enemy.state = "recover"
		enemy.state_timer = 0.70
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
	return true

func perform_attack(enemy, kind: String) -> void:
	if kind == "leaper_melee":
		enemy._melee_strike(2.35, enemy.damage * 0.75)
		return
	if kind != "leap_cut":
		return
	launch = enemy.global_position
	flight_elapsed = 0.0
	flight_total = FLIGHT_TIME
	_landed = false
	enemy.state = "leap"
	enemy.state_timer = flight_total
	var horizontal := landing - launch
	horizontal.y = 0.0
	enemy.velocity = horizontal / flight_total
	enemy.velocity.y = 22.0 * flight_total * 0.5
	enemy.floor_snap_length = 0.0
	enemy._play_world_sound("swipe", enemy.global_position + Vector3.UP, -2.0, 0.85)

func _strike_landing(enemy) -> void:
	enemy.floor_snap_length = 0.35
	for target in enemy._damage_targets():
		var offset: Vector3 = target.global_position - enemy.global_position
		if Vector2(offset.x, offset.z).length() <= RADIUS and absf(offset.y) < 2.2 and enemy._has_line_of_sight_to(target):
			target.take_damage(enemy.damage * 1.35, enemy, 6.0)
	enemy._play_world_sound("slam", enemy.global_position, -1.0, 1.12)
	var effects: Script = load("res://scripts/fx/vfx.gd")
	effects.call("ring", enemy.get_parent(), enemy.global_position, RADIUS, Ink.CINNABAR, 0.35, 0.7)
	effects.call("burst", enemy.get_parent(), enemy.global_position + Vector3.UP * 0.1, Ink.INK, 14, 4.2, 0.16, 0.5)

func on_damaged(enemy, amount: float, critical: bool) -> void:
	if enemy.state == "windup" and enemy.attack_kind == "leap_cut" and (critical or amount >= enemy.max_health * 0.14):
		enemy.state = "recover"
		enemy.state_timer = 0.55
		_cancelled = true

func visual_update(enemy, _delta: float) -> void:
	_ensure_telegraph(enemy)
	if enemy.state == "windup" and enemy.attack_kind == "leap_cut":
		var phase: float = 1.0 - enemy.state_timer / WINDUP
		telegraph.show_warning("leap", landing, RADIUS, phase)
		enemy.visual.position.y -= 0.19 * phase
		(enemy.anim.arm_r as Node3D).rotation.x = -2.45
		(enemy.anim.arm_l as Node3D).rotation.x = -1.0
		(enemy.anim.leg_l as Node3D).rotation.x = -0.5 * phase
		(enemy.anim.leg_r as Node3D).rotation.x = 0.4 * phase
	elif enemy.state == "leap":
		telegraph.show_warning("leap", landing, RADIUS, 1.0)
		var phase: float = clampf(1.0 - enemy.state_timer / flight_total, 0.0, 1.0)
		(enemy.anim.arm_r as Node3D).rotation.x = lerpf(-2.5, 0.6, phase * phase)
		(enemy.anim.arm_l as Node3D).rotation.x = -1.25
		(enemy.anim.leg_l as Node3D).rotation.x = -0.85
		(enemy.anim.leg_r as Node3D).rotation.x = 0.65
	elif enemy.state == "recover" and enemy.attack_kind == "leap_cut":
		telegraph.clear()
		enemy.visual.position.y -= 0.12 * clampf(enemy.state_timer / 0.7, 0.0, 1.0)
	else:
		telegraph.clear()

func _ensure_telegraph(enemy) -> void:
	if not is_instance_valid(telegraph):
		telegraph = load("res://scripts/fx/attack_telegraph.gd").new()
		enemy.add_child(telegraph)

func get_network_state(_enemy) -> Dictionary:
	return {"landing": [landing.x, landing.y, landing.z], "launch": [launch.x, launch.y, launch.z],
		"flight_elapsed": flight_elapsed, "flight_total": flight_total, "special_cd": special_cd}

func apply_network_state(_enemy, data: Dictionary) -> void:
	var point: Array = data.get("landing", [0, 0, 0])
	if point.size() == 3:
		landing = Vector3(float(point[0]), float(point[1]), float(point[2]))
	var origin: Array = data.get("launch", [0, 0, 0])
	if origin.size() == 3:
		launch = Vector3(float(origin[0]), float(origin[1]), float(origin[2]))
	flight_elapsed = float(data.get("flight_elapsed", 0.0))
	flight_total = maxf(0.1, float(data.get("flight_total", FLIGHT_TIME)))
	special_cd = float(data.get("special_cd", 0.0))


func cleanup(_enemy) -> void:
	if is_instance_valid(telegraph):
		telegraph.clear()
