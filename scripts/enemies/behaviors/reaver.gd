extends RefCounted

const WINDUP := 0.9
const SPIN_TIME := 1.7
const RADIUS := 2.9
const HIT_INTERVAL := 0.45
var special_cd := 1.8
var spin_phase := 0.0
var telegraph: Node3D
var _target_last_hit: Dictionary = {}
var _elapsed := 0.0

func update(enemy, direction: Vector3, distance: float, delta: float) -> void:
	if enemy.cooldown <= 0.0 and distance <= 5.2 and special_cd <= 0.0 and enemy._has_line_of_sight():
		enemy._begin_windup("spin_cut", WINDUP)
		enemy.cooldown = 5.7
		special_cd = 5.7
	elif enemy.cooldown <= 0.0 and distance <= 2.5:
		enemy._begin_windup("reaver_melee", 0.48)
		enemy.cooldown = enemy.attack_cd
	else:
		enemy._move(direction, enemy.speed, delta)

func physics_update(enemy, delta: float) -> bool:
	special_cd = maxf(special_cd - delta, 0.0)
	if enemy.state != "spin":
		return false
	_elapsed += delta
	enemy.state_timer -= delta
	spin_phase = fposmod(spin_phase + delta * TAU * 2.3, TAU)
	if enemy.state_timer <= 0.0:
		enemy.state = "recover"
		enemy.state_timer = 0.8
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
		return true
	var direction := Vector3.ZERO
	if enemy._player_valid():
		direction = enemy._flat_to_player()
	enemy._move(direction, enemy.speed * 0.40, delta)
	for target in enemy._damage_targets():
		var offset: Vector3 = target.global_position - enemy.global_position
		if Vector2(offset.x, offset.z).length() > RADIUS or absf(offset.y) > 2.2:
			continue
		var identity: int = target.get_instance_id()
		if _elapsed - float(_target_last_hit.get(identity, -100.0)) < HIT_INTERVAL:
			continue
		if not enemy._has_line_of_sight_to(target):
			continue
		_target_last_hit[identity] = _elapsed
		target.take_damage(enemy.damage, enemy, 3.0)
	return true

func perform_attack(enemy, kind: String) -> void:
	if kind == "reaver_melee":
		enemy._melee_strike(2.45, enemy.damage)
		return
	if kind != "spin_cut":
		return
	enemy.state = "spin"
	enemy.state_timer = SPIN_TIME
	spin_phase = 0.0
	_elapsed = 0.0
	_target_last_hit.clear()
	enemy._play_world_sound("swipe", enemy.global_position + Vector3.UP, -2.0, 0.72)

func on_damaged(enemy, amount: float, critical: bool) -> void:
	if enemy.state == "windup" and enemy.attack_kind == "spin_cut" and (critical or amount >= enemy.max_health * 0.14):
		enemy.state = "recover"
		enemy.state_timer = 0.55

func visual_update(enemy, delta: float) -> void:
	_ensure_telegraph(enemy)
	var left: Node3D = enemy.anim.arm_l
	var right: Node3D = enemy.anim.arm_r
	left.rotation.y = 0.0
	left.rotation.z = 0.0
	right.rotation.y = 0.0
	right.rotation.z = 0.0
	var sword_l: Node3D = enemy.anim.sword_l
	var sword_r: Node3D = enemy.anim.sword_r
	sword_l.rotation.x = deg_to_rad(72.0)
	sword_r.rotation.x = deg_to_rad(72.0)
	if enemy.state == "windup" and enemy.attack_kind == "spin_cut":
		var progress: float = 1.0 - enemy.state_timer / WINDUP
		telegraph.show_warning("spin_warning", enemy.global_position, RADIUS, progress)
		sword_l.rotation.x = deg_to_rad(72.0) * (1.0-progress)
		sword_r.rotation.x = deg_to_rad(72.0) * (1.0-progress)
		left.rotation = Vector3(-0.8, 0.0, -0.9 * progress)
		right.rotation = Vector3(-0.8, 0.0, 0.9 * progress)
		enemy.visual.rotation.y = -progress * 0.75
	elif enemy.state == "spin":
		# The host sends phase; proxies advance it locally between snapshots.
		if enemy.frozen:
			spin_phase = fposmod(spin_phase + delta * TAU * 2.3, TAU)
		enemy.visual.rotation.y = spin_phase
		sword_l.rotation.x = 0.0
		sword_r.rotation.x = 0.0
		left.rotation = Vector3(0.0, 0.0, -PI * 0.48)
		right.rotation = Vector3(0.0, 0.0, PI * 0.48)
		telegraph.show_warning("spin", enemy.global_position, RADIUS, 1.0, spin_phase)
	elif enemy.state == "recover" and enemy.attack_kind == "spin_cut":
		telegraph.clear()
		left.rotation.x = 0.4
		right.rotation.x = 0.4
		enemy.visual.position.y -= 0.10 * clampf(enemy.state_timer / 0.8, 0.0, 1.0)
	else:
		telegraph.clear()

func _ensure_telegraph(enemy) -> void:
	if not is_instance_valid(telegraph):
		telegraph = load("res://scripts/fx/attack_telegraph.gd").new()
		enemy.add_child(telegraph)

func get_network_state(_enemy) -> Dictionary:
	return {"special_cd": special_cd, "spin_phase": spin_phase}

func apply_network_state(_enemy, data: Dictionary) -> void:
	special_cd = float(data.get("special_cd", 0.0))
	spin_phase = fposmod(float(data.get("spin_phase", 0.0)), TAU)


func cleanup(_enemy) -> void:
	if is_instance_valid(telegraph):
		telegraph.clear()
