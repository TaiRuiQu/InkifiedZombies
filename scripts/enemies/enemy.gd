class_name Enemy
extends CharacterBody3D

signal died(enemy)

const ProjectileScript: Script = preload("res://scripts/combat/projectile.gd")
const PickupScript: Script = preload("res://scripts/world/pickup.gd")
const SteeringScript: Script = preload("res://scripts/enemies/enemy_steering.gd")

var type_id := "wraith"
var data: Dictionary = {}
var wave_level := 1
var elite := false
var boss := false

var max_health := 60.0
var health := 60.0
var speed := 2.5
var damage := 9.0
var attack_range := 2.0
var attack_cd := 1.2
var radius := 0.42
var height := 1.9
var behavior := "chaser"

var player: Node3D
var dead := false
var frozen := false
var state := "spawn"
var state_timer := 0.0
var windup_total := 0.4
var attack_kind := "melee"
var cooldown := 0.0
var stagger_timer := 0.0
var slow_timer := 0.0
var slow_factor := 0.0
var impact_slow_timer := 0.0
var impact_slow_factor := 0.0
var impulse := Vector3.ZERO
var flash := 0.0
var walk_phase := 0.0
var time_alive := 0.0
var enraged := false
var volley_timer := 5.0
var _hit_decal_budget := 0.0
var _rng := RandomNumberGenerator.new()
var _time_offset := 0.0
var _base_visual_scale := Vector3.ONE
var _spawn_tween: Tween
var _steering: RefCounted = SteeringScript.new()
var _custom_behavior: RefCounted
var _target_timer := 0.0
var entry_target := Vector3.INF
var _hit_react_timer := 0.0
var _hit_react_duration := 0.20
var _hit_react_direction := Vector3.ZERO
var _hit_react_strength := 0.0

var visual: Node3D
var parts: Array[MeshInstance3D] = []
var anim: Dictionary = {}
var aura: MeshInstance3D
var hitboxes: Array[Area3D] = []
var audio: EnemyAudio


func setup(id: String, wave: int, elite_flag: bool = false) -> void:
	type_id = id
	data = EnemyDB.get_type(id)
	wave_level = maxi(wave, 1)
	elite = elite_flag
	boss = bool(data.get("is_boss", id == "boss"))
	behavior = data.get("behavior", "chaser")
	radius = float(data.radius)
	height = float(data.height)
	var hp_scale := 1.0 + float(wave_level - 1) * 0.205 + pow(float(wave_level), 1.35) * 0.024
	var dmg_scale := 1.0 + float(wave_level - 1) * 0.085
	if boss:
		var boss_step := maxf(float(wave_level) / 5.0 - 1.0, 0.0)
		max_health = float(data.hp) * (1.0 + boss_step * 0.62)
	else:
		max_health = float(data.hp) * hp_scale
	if elite:
		max_health *= 1.85
	health = max_health
	var speed_scale := 1.0 + minf(float(wave_level) * 0.006, 0.16)
	speed = float(data.speed) * speed_scale * RunRules.ENEMY_SPEED_MULTIPLIER
	damage = float(data.damage) * dmg_scale * (1.28 if elite else 1.0)
	attack_range = float(data.range)
	attack_cd = float(data.attack_cd)
	var strategy: Script = data.get("behavior_script") as Script
	if strategy:
		_custom_behavior = strategy.new()


func _ready() -> void:
	_rng.seed = randi()
	_time_offset = randf() * 9.0
	_steering.setup(get_instance_id())
	player = get_tree().get_first_node_in_group("player")
	collision_layer = 0 if state == "spawn" else 4
	collision_mask = 7
	floor_snap_length = 0.35
	up_direction = Vector3.UP
	add_to_group("enemies")
	if not boss:
		state_timer = 0.5
	_build_collision()
	_build_visual()
	_build_damage_hitboxes()
	visual.scale = Vector3.ONE * 0.01
	var target_scale := Vector3.ONE * (1.12 if elite else 1.0)
	_base_visual_scale = target_scale
	_spawn_tween = create_tween()
	_spawn_tween.tween_property(visual, "scale", target_scale, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	VFX.spawn_portal(get_parent(), global_position)
	var snd := "boss_spawn" if boss else "spawn"
	_play_world_sound(snd, global_position + Vector3.UP, -2.0)
	audio = EnemyAudio.new()
	audio.name = "PositionalCues"
	add_child(audio)
	if boss:
		state = "chase"
		collision_layer = 4
		volley_timer = 5.0


func complete_spawn_visual() -> void:
	# Network proxies may first appear after the authority's birth animation.
	# Finish both painted model and attached damage shapes in the same frame.
	if is_instance_valid(_spawn_tween) and _spawn_tween.is_running():
		_spawn_tween.kill()
	if is_instance_valid(visual):
		visual.scale = _base_visual_scale


func _build_collision() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = minf(radius, height * 0.48)
	shape.height = maxf(height, shape.radius * 2.0 + 0.02)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = shape.height * 0.5
	add_child(col)


# Damage collision follows visible body parts. The narrow movement capsule is
# deliberately independent so arms / masks do not snag on map obstacles.
func _build_damage_hitboxes() -> void:
	var head := anim.get("head") as Node3D
	if head:
		var points := PackedVector3Array()
		for child in head.get_children():
			if not child is MeshInstance3D:
				continue
			for surface in child.mesh.get_surface_count():
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					points.append(child.transform * vertex)
		if points.size() >= 4:
			var face_shape := ConvexPolygonShape3D.new()
			face_shape.points = points
			_add_damage_shape(head, "head", face_shape, Vector3.ZERO)
	var visual_id := String(data.get("visual_id", type_id))
	match visual_id:
		"wraith":
			_add_damage_capsule(visual, "torso", 0.29, 1.08, Vector3(0, 1.1, 0))
			_add_damage_cone(visual, "robe", 0.22, 0.50, 0.95, Vector3(0, 0.58, 0))
			_limb_hitboxes(0.095, 1.18, -0.54, 0.08, 0.64, -0.31)
		"puppet":
			_add_damage_box(visual, "torso", Vector3(0.55, 0.89, 0.29), Vector3(0, 1.1, 0), Vector3(0, 0, 3))
			_add_damage_box(visual, "head", Vector3(0.56, 0.25, 0.44), Vector3(0.02, 2.04, 0), Vector3(0, 0, 3))
			_limb_hitboxes(0.08, 1.04, -0.47, 0.08, 0.72, -0.34)
		"brute":
			_add_damage_capsule(visual, "torso", 0.64, 1.55, Vector3(0, 1.55, 0))
			_add_damage_cone(visual, "waist", 0.50, 0.76, 0.80, Vector3(0, 0.60, 0))
			_add_damage_box(visual, "shoulders", Vector3(1.80, 0.34, 0.70), Vector3(0, 2.07, 0))
			_limb_hitboxes(0.23, 1.40, -0.63, 0.18, 1.03, -0.49)
		"mask":
			_add_damage_cone(visual, "cloak", 0.28, 0.62, 1.30, Vector3(0, 1.10, 0.10))
			_limb_hitboxes(0.085, 1.55, -0.73, 0.0, 0.0, 0.0)
		"lantern":
			var drum := CylinderShape3D.new()
			drum.radius = 0.34
			drum.height = 0.77
			_add_damage_shape(visual, "torso", drum, Vector3(0, 1.32, 0))
			_limb_hitboxes(0.05, 0.73, -0.36, 0.0, 0.0, 0.0)
		"leaper":
			_add_damage_capsule(visual, "torso", 0.28, 0.90, Vector3(0, 1.25, 0))
			_add_damage_box(visual, "waist", Vector3(0.62, 0.36, 0.40), Vector3(0, 0.87, 0))
			_limb_hitboxes(0.095, 0.98, -0.48, 0.10, 0.92, -0.43)
		"reaver":
			_add_damage_capsule(visual, "torso", 0.44, 1.20, Vector3(0, 1.40, 0))
			_add_damage_box(visual, "shoulders", Vector3(1.30, 0.30, 0.60), Vector3(0, 1.84, 0))
			_limb_hitboxes(0.15, 1.05, -0.51, 0.14, 0.82, -0.39)
		"boss":
			_add_damage_capsule(visual, "torso", 0.86, 1.91, Vector3(0, 2.45, 0))
			_add_damage_cone(visual, "waist", 0.72, 1.10, 0.95, Vector3(0, 1.30, 0))
			for side in [-1, 1]:
				_add_damage_box(visual, "shoulder", Vector3(0.85, 0.34, 0.85), Vector3(0.86 * side, 3.05, 0), Vector3(0, 0, side * -16))
			_limb_hitboxes(0.29, 1.87, -0.87, 0.24, 1.43, -0.68)
		_:
			_add_damage_capsule(visual, "torso", radius, height, Vector3(0, height * 0.5, 0))


func _add_damage_shape(parent: Node3D, part_name: String, shape: Shape3D,
		center: Vector3, angles: Vector3 = Vector3.ZERO) -> void:
	var hitbox := EnemyHitbox.new()
	hitbox.setup(self, part_name, shape)
	hitbox.position = center
	hitbox.rotation_degrees = angles
	parent.add_child(hitbox)
	hitboxes.append(hitbox)


func _add_damage_box(parent: Node3D, part_name: String, size: Vector3,
		center: Vector3, angles: Vector3 = Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_add_damage_shape(parent, part_name, shape, center, angles)


func _add_damage_capsule(parent: Node3D, part_name: String, width: float,
		length: float, center: Vector3) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = width
	shape.height = maxf(length, width * 2.0)
	_add_damage_shape(parent, part_name, shape, center)


func _add_damage_cone(parent: Node3D, part_name: String, top: float, bottom: float,
		length: float, center: Vector3) -> void:
	var points := PackedVector3Array()
	for i in 12:
		var angle := TAU * float(i) / 12.0
		points.append(Vector3(cos(angle) * top, length * 0.5, sin(angle) * top))
		points.append(Vector3(cos(angle) * bottom, -length * 0.5, sin(angle) * bottom))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	_add_damage_shape(parent, part_name, shape, center)


func _limb_hitboxes(arm_width: float, arm_length: float, arm_y: float,
		leg_width: float, leg_length: float, leg_y: float) -> void:
	var visual_id := String(data.get("visual_id", type_id))
	var tilt: float = {"puppet": 3.0, "brute": 4.0, "mask": 10.0, "lantern": 14.0, "boss": 3.0}.get(visual_id, 0.0)
	var feet: Dictionary = {"wraith": Vector3(0.065, 0.57, 0.065), "puppet": Vector3(0.045, 0.63, 0.045),
		"brute": Vector3(0.14, 0.90, 0.14), "leaper": Vector3(0.10, 0.87, 0.10), "reaver": Vector3(0.14, 0.78, 0.14), "boss": Vector3(0.22, 1.20, 0.18)}
	for side in ["l", "r"]:
		var arm := anim.get("arm_" + side) as Node3D
		if arm:
			_add_damage_capsule(arm, "arm", arm_width, arm_length, Vector3(0, arm_y, 0))
			hitboxes.back().rotation_degrees.z = tilt * (-1.0 if side == "l" else 1.0)
			if visual_id in ["brute", "boss"]:
				var fist := SphereShape3D.new()
				fist.radius = 0.31 if visual_id == "brute" else 0.35
				_add_damage_shape(arm, "hand", fist, Vector3(0, -1.16 if visual_id == "brute" else -1.58, 0))
		var leg := anim.get("leg_" + side) as Node3D
		if leg and leg_width > 0.0:
			_add_damage_capsule(leg, "leg", leg_width, leg_length, Vector3(0, leg_y, 0))
			if feet.has(visual_id):
				var foot: Vector3 = feet[visual_id]
				_add_damage_box(leg, "foot", Vector3(foot.x * 2.0, foot.x * 1.15, foot.z * 3.8),
					Vector3(0, -foot.y, -foot.z * 0.7))


func damage_rids() -> Array[RID]:
	var result: Array[RID] = [get_rid()]
	for hitbox in hitboxes:
		if is_instance_valid(hitbox):
			result.append(hitbox.get_rid())
	return result


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if frozen:
		return
	if flash > 0.0:
		flash = maxf(flash - delta * 5.5, 0.0)
		_apply_flash()
	if cooldown > 0.0:
		cooldown -= delta
	impact_slow_timer = maxf(impact_slow_timer - delta, 0.0)
	if impact_slow_timer <= 0.0:
		impact_slow_factor = 0.0
	if _hit_decal_budget > 0.0:
		_hit_decal_budget -= delta
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 0.0
	if stagger_timer > 0.0:
		stagger_timer -= delta
	if impulse.length() > 0.02:
		impulse = impulse.move_toward(Vector3.ZERO, delta * 18.0)
	else:
		impulse = Vector3.ZERO
	time_alive += delta

	if dead:
		return
	if state == "spawn":
		state_timer -= delta
		if state_timer <= 0.0:
			state = "chase"
			collision_layer = 4
		_apply_gravity(delta)
		move_and_slide()
		return
	if entry_target != Vector3.INF:
		var approach := entry_target - global_position
		approach.y = 0.0
		if approach.length() > 0.8:
			_move(approach.normalized(), speed, delta)
			return
		entry_target = Vector3.INF

	_target_timer -= delta
	if _target_timer <= 0.0 or not _player_valid():
		_target_timer = 0.35
		_choose_target()
	# Committed attacks finish even if their locked target dies or disconnects.
	if _custom_behavior and _custom_behavior.has_method("physics_update"):
		if _custom_behavior.physics_update(self, delta):
			return
	var has_target: bool = is_instance_valid(player) and player.get("dead") != true
	if not has_target and state not in ["windup", "recover", "fuse"]:
		_apply_gravity(delta)
		move_and_slide()
		return

	if stagger_timer > 0.0 and state == "chase":
		_decelerate(delta)
		return
	var to_player := player.global_position - global_position if has_target else _flat_forward()
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.001 else Vector3.FORWARD
	_face(dir, delta)

	match state:
		"windup":
			state_timer -= delta
			_decelerate(delta)
			if state_timer <= 0.0:
				_perform_attack()
				if state == "windup":
					state = "recover"
					state_timer = 0.42 if not boss else 0.55
		"recover":
			state_timer -= delta
			_decelerate(delta)
			if state_timer <= 0.0:
				state = "chase"
		"fuse":
			state_timer -= delta
			_move(dir, speed * 0.65, delta)
			if state_timer <= 0.0:
				_explode()
		"chase":
			_chase(dir, dist, delta)

	if boss and not dead:
		volley_timer -= delta
		if volley_timer <= 0.0 and state == "chase":
			volley_timer = 6.0
			_begin_windup("boss_volley", 0.85)
		if not enraged and health < max_health * 0.5:
			_enrage()


func _chase(dir: Vector3, dist: float, delta: float) -> void:
	if _custom_behavior and _custom_behavior.has_method("update"):
		_custom_behavior.update(self, dir, dist, delta)
		return
	if boss:
		if dist <= attack_range and cooldown <= 0.0:
			_begin_windup("boss_slam", 0.95)
			cooldown = attack_cd
		else:
			_move(dir, speed, delta)
		return

	match behavior:
		"chaser":
			if dist <= attack_range and cooldown <= 0.0:
				_begin_windup("melee", 0.38)
				cooldown = attack_cd
			else:
				_move(dir, speed, delta)
		"brute":
			if dist <= attack_range and cooldown <= 0.0:
				_begin_windup("brute_slam", 0.72)
				cooldown = attack_cd
			else:
				_move(dir, speed, delta)
		"ranged":
			var move_dir := Vector3.ZERO
			if dist < 7.5:
				move_dir = -dir + _strafe_dir() * 0.6
			elif dist > 14.0:
				move_dir = dir + _strafe_dir() * 0.3
			else:
				move_dir = _strafe_dir()
			_move(move_dir.normalized(), speed * 0.7, delta)
			_face(dir, delta * 3.0)
			if dist <= 18.0 and cooldown <= 0.0 and _has_line_of_sight():
				_begin_windup("ranged", 0.55)
				cooldown = attack_cd
		"exploder":
			if dist <= 2.5 and _has_line_of_sight():
				state = "fuse"
				state_timer = 0.66
				VFX.ring(get_parent(), global_position, 4.2, Ink.CINNABAR, 0.66, 0.65)
				cooldown = 999.0
				_play_world_sound("lantern_fuse", global_position + Vector3.UP, 0.0)
				_stop_moving(delta)
			else:
				_move(dir, speed, delta)
		_:
			_move(dir, speed, delta)


func _begin_windup(kind: String, duration: float) -> void:
	state = "windup"
	attack_kind = kind
	state_timer = duration
	windup_total = duration
	velocity.x = 0.0
	velocity.z = 0.0
	if kind in ["brute_slam", "boss_slam"]:
		var rad := 3.9 if kind == "brute_slam" else 5.1
		VFX.ring(get_parent(), global_position, rad, Color(0.65, 0.15, 0.1, 0.5), duration, 0.5)
	# PositionalCues observes this state transition on hosts and network proxies.
	# Its attack growl replaces the former non-positional windup / boss roar.



func _perform_attack() -> void:
	if _custom_behavior and _custom_behavior.has_method("perform_attack"):
		_custom_behavior.perform_attack(self, attack_kind)
		return
	match attack_kind:
		"melee":
			_melee_strike(2.6, damage)
		"brute_slam":
			_aoe_strike(3.4, damage * 1.1)
			VFX.ring(get_parent(), global_position, 3.4, Ink.CINNABAR, 0.5, 0.9)
			VFX.burst(get_parent(), global_position + Vector3(0, 0.15, 0), Color(0.15, 0.13, 0.1, 0.5), 24, 6.0, 0.26, 0.7)
			Sfx.play("slam", -1.0)
		"ranged":
			_fire_projectile(1, 0.0)
		"boss_slam":
			_aoe_strike(4.6, damage * 1.25)
			VFX.ring(get_parent(), global_position, 4.6, Ink.CINNABAR, 0.65, 0.95)
			VFX.burst(get_parent(), global_position, Color(0.12, 0.1, 0.08, 0.55), 40, 8.0, 0.3, 0.9)
			Sfx.play("slam", 1.0, 0.8)
		"boss_volley":
			for i in 5:
				_fire_projectile(1, (float(i) - 2.0) * 7.0)
		"explode":
			_explode()
	# brief lunge forward for melee
	if attack_kind in ["melee", "brute_slam"]:
		impulse += _flat_to_player() * (3.0 if attack_kind == "melee" else 2.0)


func _melee_strike(reach: float, amount: float) -> void:
	if not _player_valid():
		return
	var to_player := _flat_to_player()
	var dist := global_position.distance_to(player.global_position)
	if dist <= reach + 0.6 and to_player.dot(_flat_forward()) > -0.1 and _has_line_of_sight():
		player.take_damage(amount, self, 4.0)
		VFX.slash(get_parent(), player.global_position + Vector3(0, 1.1, 0) - to_player * 0.8, to_player, Ink.CINNABAR)
		_play_world_sound("enemy_hit", player.global_position + Vector3.UP, -2.0)
	else:
		Sfx.play("swipe", -8.0)


func _aoe_strike(rad: float, amount: float) -> void:
	for target in _damage_targets():
		var d := global_position.distance_to(target.global_position)
		if d <= rad + 0.5 and _has_line_of_sight_to(target):
			var falloff := 1.0 - clampf(d / (rad + 0.5), 0.0, 1.0) * 0.35
			target.take_damage(amount * falloff, self, 7.5)
			target.add_trauma(0.35)


func _fire_projectile(count: int, spread_deg: float) -> void:
	if not _player_valid() or not _has_line_of_sight():
		return
	var origin := global_position + Vector3(0, height * 0.62, 0)
	var target := player.global_position + Vector3(0, 1.1, 0)
	for i in count:
		var dir := (target - origin).normalized()
		if not is_zero_approx(spread_deg) or count > 1:
			var angle := deg_to_rad(spread_deg) + deg_to_rad(float(i) * 4.0)
			dir = dir.rotated(Vector3.UP, angle)
		var proj = ProjectileScript.new()
		proj.setup({
			"friendly": false, "damage": damage * 0.72, "speed": 15.5,
			"gravity": 1.2, "lifetime": 4.5, "color": data.glow,
			"radius": 0.16, "explode_radius": 1.2, "explode_damage": 4.0,
			"source": self,
		})
		get_parent().add_child(proj)
		proj.global_position = origin + Vector3(0, 0, 0)
		proj.launch(dir)
		VFX.burst(get_parent(), origin, data.glow, 5, 2.0, 0.08, 0.3, Vector3.ZERO)


func _explode() -> void:
	if dead:
		return
	var rad := 3.8
	VFX.explosion(get_parent(), global_position + Vector3(0, 0.5, 0), rad, Color("9e3526"))
	Sfx.play("explosion", 1.0)
	for target in _damage_targets():
		if global_position.distance_to(target.global_position) <= rad + 0.4 and _has_line_of_sight_to(target):
			target.take_damage(damage * 1.5, self, 10.0)
			target.add_trauma(0.4)
	_die(true)


func _enrage() -> void:
	enraged = true
	speed *= 1.32
	cooldown = 0.5
	VFX.explosion(get_parent(), global_position, 3.0, Ink.CINNABAR)
	VFX.ring(get_parent(), global_position, 6.0, Ink.CINNABAR, 0.8, 0.9)
	if is_instance_valid(audio):
		audio.request_roar(true)
	# Summon a handful of paper puppets.
	for i in 4:
		var e = preload("res://scenes/enemy.tscn").instantiate()
		e.setup("puppet", wave_level, false)
		var ang := TAU * float(i) / 4.0
		var spawn := Vector3(cos(ang), 0, sin(ang)) * MapBuilder.SPAWN_RADIUS + Vector3.UP * 0.1
		e.position = get_parent().to_local(spawn)
		e.entry_target = Vector3(cos(ang), 0, sin(ang)) * (MapBuilder.GATE_RADIUS - 2.5)
		get_parent().add_child(e)


# --------------------------------------------------------------------------
# Movement helpers
# --------------------------------------------------------------------------

func _move(dir: Vector3, spd: float, delta: float) -> void:
	dir = _steering.direction(self, dir, delta)
	var spd_mult := 1.0 - maxf(slow_factor, impact_slow_factor)
	var target := dir * spd * maxf(spd_mult, 0.25) + impulse
	var accel := 18.0 if behavior != "brute" else 10.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	_apply_gravity(delta)
	move_and_slide()
	if dir.length() > 0.01:
		_face(dir, delta)


func _decelerate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, impulse.x, 22.0 * delta)
	velocity.z = move_toward(velocity.z, impulse.z, 22.0 * delta)
	_apply_gravity(delta)
	move_and_slide()


func _stop_moving(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 22.0 * delta)
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if behavior in ["ranged"]:
		velocity.y = 0.0
		return
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = -0.6


func _separation() -> Vector3:
	var push := Vector3.ZERO
	var nodes := get_tree().get_nodes_in_group("enemies")
	for other in nodes:
		if other == self or not is_instance_valid(other):
			continue
		if other is Enemy and other.dead:
			continue
		var off: Vector3 = global_position - other.global_position
		off.y = 0.0
		var d := off.length()
		var other_radius := 0.4
		if other is Enemy:
			other_radius = other.radius
		var min_dist := radius + other_radius + 0.3
		if d < min_dist and d > 0.001:
			push += off / d * (1.0 - d / min_dist)
	return push


func _strafe_dir() -> Vector3:
	var side := sin(time_alive * 1.7 + _time_offset) > 0.0
	var forward := _flat_to_player()
	return Vector3(-forward.z, 0, forward.x) * (1.0 if side else -1.0)


func _face(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 7.0, 1.0))


func _flat_forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0, -cos(rotation.y))


func _flat_to_player() -> Vector3:
	if not _player_valid():
		return Vector3.FORWARD
	var v := player.global_position - global_position
	v.y = 0.0
	return v.normalized() if v.length() > 0.001 else Vector3.FORWARD


func _player_valid() -> bool:
	return is_instance_valid(player) and player.get("dead") != true


func _choose_target() -> void:
	var candidates := get_tree().get_nodes_in_group("coop_players")
	if candidates.is_empty():
		candidates = get_tree().get_nodes_in_group("player")
	var nearest: Node3D
	var best := INF
	for candidate in candidates:
		if not is_instance_valid(candidate) or candidate.get("dead") == true or not candidate is Node3D:
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < best:
			best = distance
			nearest = candidate
	player = nearest


func _has_line_of_sight() -> bool:
	if not _player_valid():
		return false
	return _has_line_of_sight_to(player)


func _has_line_of_sight_to(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, height * 0.72, 0)
	var to := target.global_position + Vector3(0, 1.1, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func _damage_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	var candidates := get_tree().get_nodes_in_group("coop_players")
	if candidates.is_empty() and _player_valid():
		candidates.append(player)
	for candidate in candidates:
		if is_instance_valid(candidate) and candidate is Node3D and candidate.get("dead") != true:
			targets.append(candidate)
	return targets


func apply_slow(factor: float, duration: float) -> void:
	slow_factor = maxf(slow_factor, factor)
	slow_timer = maxf(slow_timer, duration)


# --------------------------------------------------------------------------
# Damage / death
# --------------------------------------------------------------------------

func take_damage(amount: float, dir: Vector3 = Vector3.ZERO, hit_pos: Vector3 = Vector3.INF,
		crit: bool = false, knockback: float = 0.0, slow: float = 0.0) -> bool:
	var network := get_node_or_null("/root/NET")
	if network and network.active and not network.is_host:
		return false
	if dead:
		return false
	var actual := maxf(amount, 0.0)
	if actual <= 0.0:
		return false
	health -= actual
	if _custom_behavior and _custom_behavior.has_method("on_damaged"):
		_custom_behavior.on_damaged(self, actual, crit)
	impact_slow_timer = RunRules.IMPACT_SLOW_DURATION
	impact_slow_factor = 0.08 if boss else (0.12 if behavior == "brute" else 0.25)
	notify_hit_reaction(dir, actual, crit)
	flash = 1.0
	_apply_flash()
	if slow > 0.0:
		apply_slow(slow, 2.0)
	if knockback > 0.0 and dir.length() > 0.01:
		var resist := 0.15 if (boss or behavior == "brute") else 1.0
		impulse += dir.normalized() * knockback * resist
	var vfx_pos := hit_pos
	if vfx_pos == Vector3.INF:
		vfx_pos = global_position + Vector3(0, height * 0.62, 0)
	VFX.damage_number(get_parent(), vfx_pos, actual, crit)
	if _hit_decal_budget <= 0.0:
		VFX.burst(get_parent(), vfx_pos, _ink_color(), 7, 3.8, 0.09, 0.45, Vector3(0, -14, 0))
		_hit_decal_budget = 0.07
	_play_world_sound("hit_armor" if behavior in ["boss", "brute"] else "hit_flesh", vfx_pos, -1.0, randf_range(0.94, 1.06))
	if crit:
		_play_world_sound("headshot", vfx_pos, -2.0, 1.0)
	if (actual > max_health * 0.14 or crit) and behavior not in ["boss", "brute"]:
		stagger_timer = maxf(stagger_timer, 0.15 if crit else 0.10)
	if health <= 0.0:
		_die(false)
		return true
	return false


func _play_world_sound(id: String, at: Vector3, volume: float = 0.0, pitch: float = 1.0) -> void:
	# Dynamic call keeps custom audio services compatible with the enemy module.
	if Sfx.has_method("play_at"):
		Sfx.call("play_at", id, at, volume, pitch)
	else:
		Sfx.play(id, volume, pitch)


func notify_hit_reaction(direction: Vector3, amount: float, critical: bool = false) -> void:
	var resistance := 0.22 if boss else (0.42 if behavior == "brute" else 1.0)
	_hit_react_direction = global_basis.inverse() * direction.normalized() if direction.length() > 0.01 else Vector3.BACK
	_hit_react_strength = clampf(amount / maxf(max_health, 1.0) * 3.5 + 0.30, 0.35, 1.0) * resistance
	_hit_react_duration = 0.24 if critical else 0.18
	_hit_react_timer = _hit_react_duration


func _apply_flash() -> void:
	for p in parts:
		if is_instance_valid(p):
			p.set_instance_shader_parameter("hit_flash", flash)


func _ink_color() -> Color:
	if type_id == "puppet":
		return Color("ddd4be")
	if type_id == "mask":
		return Color("bfb49c")
	return Color("16130f")


func _die(exploded: bool) -> void:
	if dead:
		return
	dead = true
	if _custom_behavior and _custom_behavior.has_method("cleanup"):
		_custom_behavior.cleanup(self)
	state = "dead"
	collision_layer = 0
	collision_mask = 0
	for hitbox in hitboxes:
		if is_instance_valid(hitbox):
			hitbox.set_deferred("collision_layer", 0)
	velocity = Vector3.ZERO
	VFX.burst(get_parent(), global_position + Vector3(0, height * 0.45, 0), _ink_color(),
		28 if not boss else 70, 6.5, 0.24 if not boss else 0.4, 0.9)
	VFX.decal(get_parent(), global_position + Vector3(0, 0.02, 0), Vector3.UP,
		randf_range(1.1, 2.2) * (2.0 if boss else 1.0), Color(0.06, 0.055, 0.05, 0.55), randi() % 3)
	_play_world_sound("kill", global_position + Vector3.UP, -1.0, randf_range(0.92, 1.06))
	if boss:
		VFX.explosion(get_parent(), global_position + Vector3(0, 1.5, 0), 7.0, Ink.CINNABAR)
		VFX.ring(get_parent(), global_position, 9.0, Ink.CINNABAR, 1.0, 0.9)
		Sfx.play("boss_death", 2.0)
		Engine.time_scale = 0.42
		var timer := get_tree().create_timer(0.75, true, false, true)
		timer.timeout.connect(func(): Engine.time_scale = 1.0)
	_drop_loot(exploded)
	died.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "rotation_degrees:z", 75.0 if randf() > 0.5 else -75.0, 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "position:y", position.y + 0.1, 0.55)
	tw.tween_interval(0.55 if not boss else 1.4)
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tw.tween_callback(queue_free)


func _drop_loot(exploded: bool) -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	var amount_h := 3 if boss else 1
	var amount_a := 2 if boss else 1
	if boss:
		for i in amount_h:
			PickupScript.spawn(parent, global_position + Vector3(randf_range(-2, 2), 0.2, randf_range(-2, 2)), "health")
		for i in amount_a:
			PickupScript.spawn(parent, global_position + Vector3(randf_range(-2, 2), 0.2, randf_range(-2, 2)), "ammo")
		return
	if exploded:
		if randf() < 0.6:
			PickupScript.spawn(parent, global_position + Vector3(0, 0.2, 0), "ammo")
		return
	var r := randf()
	if r < 0.16:
		PickupScript.spawn(parent, global_position + Vector3(0, 0.2, 0), "health")
	elif r < 0.44:
		PickupScript.spawn(parent, global_position + Vector3(0, 0.2, 0), "ammo")


func is_headshot(pos: Vector3) -> bool:
	# Legacy callers can still ask by position; hitscan uses the exact part id.
	for hitbox in hitboxes:
		if is_instance_valid(hitbox) and hitbox.body_part == "head":
			var point: Vector3 = hitbox.to_local(pos)
			var collider: CollisionShape3D = hitbox.get_child(0)
			if collider.shape is ConvexPolygonShape3D:
				var bounds := AABB()
				var points: PackedVector3Array = collider.shape.points
				if not points.is_empty():
					bounds = AABB(points[0], Vector3.ZERO)
					for vertex in points:
						bounds = bounds.expand(vertex)
					return bounds.grow(0.03).has_point(point)
	return false


func aim_point() -> Vector3:
	return global_position + Vector3(0, height * 0.62, 0)


func health_ratio() -> float:
	return clampf(health / max_health, 0.0, 1.0)


# --------------------------------------------------------------------------
# Visual construction
# --------------------------------------------------------------------------

func _build_visual() -> void:
	var factory := preload("res://scripts/enemies/enemy_visual.gd").new()
	factory.build(self)
	visual = factory.visual
	parts = factory.parts
	anim = factory.anim
	aura = factory.aura


# --------------------------------------------------------------------------
# Animation
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if dead or not is_instance_valid(visual):
		return
	var move_amt := clampf(Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.1), 0.0, 1.0)
	# Rebuild the visual pose from its base every frame; recoil never accumulates.
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	var head_joint := anim.get("head") as Node3D
	if head_joint:
		head_joint.rotation = Vector3.ZERO
	walk_phase += delta * (2.2 + move_amt * 5.6) * (1.4 if boss else 1.0)
	var swing := sin(walk_phase) * (0.42 if not boss else 0.3) * move_amt
	var arm_l := anim.get("arm_l") as Node3D
	var arm_r := anim.get("arm_r") as Node3D
	var leg_l := anim.get("leg_l") as Node3D
	var leg_r := anim.get("leg_r") as Node3D
	if leg_l:
		leg_l.rotation.x = swing
	if leg_r:
		leg_r.rotation.x = -swing
	if arm_l:
		arm_l.rotation = Vector3(-swing * 0.8, 0, 0)
	if arm_r:
		arm_r.rotation = Vector3(swing * 0.8, 0, 0)

	# Attack animation overrides the walk swing.
	if state == "windup":
		var p := 1.0 - clampf(state_timer / maxf(windup_total, 0.01), 0.0, 1.0)
		if arm_r:
			arm_r.rotation.x = lerpf(0.1, -2.15, ease(p, 0.35))
		if arm_l:
			arm_l.rotation.x = lerpf(0.0, -1.1, ease(p, 0.5))
		if boss and anim.has("cape"):
			(anim["cape"] as Node3D).rotation.x = -p * 0.25
	elif state == "recover":
		var p := 1.0 - clampf(state_timer / 0.42, 0.0, 1.0)
		if arm_r:
			arm_r.rotation.x = lerpf(0.55, 0.0, p)
		if arm_l:
			arm_l.rotation.x = lerpf(-0.4, 0.0, p)
	elif state == "fuse":
		if visual:
			visual.scale = _base_visual_scale * (1.0 + sin(time_alive * 34.0) * 0.06)
	else:
		if visual:
			var hover := 0.0
			if behavior == "ranged" or type_id == "lantern":
				hover = 0.22 + sin(time_alive * 2.1 + _time_offset) * 0.14
			var bob := absf(sin(walk_phase * 2.0)) * 0.025 * move_amt
			visual.position.y = hover + bob
		if boss and visual:
			visual.position.y = absf(sin(walk_phase * 2.0)) * 0.04 * move_amt
	if boss and aura:
		aura.rotation.y += delta * 0.6
		aura.scale = Vector3.ONE * (1.0 + sin(time_alive * 1.6) * 0.05)
	if type_id == "lantern" and anim.has("light"):
		var l := anim["light"] as OmniLight3D
		if l:
			var pulse := 1.0 + sin(time_alive * 3.2 + _time_offset) * 0.25
			if state == "fuse":
				pulse = 1.4 + sin(time_alive * 24.0) * 0.7
			l.light_energy = 1.1 * pulse
	if anim.has("charms"):
		var charms: Array = anim["charms"]
		for i in charms.size():
			var charm := charms[i] as Node3D
			charm.rotation.z = sin(time_alive * 2.3 + float(i) * PI) * 0.14
			charm.rotation.x = sin(time_alive * 1.7 + float(i)) * 0.1

	_hit_react_timer = maxf(_hit_react_timer - delta, 0.0)
	if _hit_react_timer > 0.0:
		var reaction := sin(_hit_react_timer / _hit_react_duration * PI * 0.5) * _hit_react_strength
		var kick := Vector3(_hit_react_direction.x, 0, _hit_react_direction.z)
		visual.position += kick * reaction * 0.09
		visual.rotation = Vector3(kick.z * 0.14, 0, -kick.x * 0.19) * reaction
		if head_joint:
			head_joint.rotation = Vector3(kick.z * -0.22, kick.x * 0.12, kick.x * 0.16) * reaction

	if _custom_behavior and _custom_behavior.has_method("visual_update"):
		_custom_behavior.visual_update(self, delta)


func get_behavior_snapshot() -> Dictionary:
	if _custom_behavior and _custom_behavior.has_method("get_network_state"):
		return _custom_behavior.get_network_state(self)
	return {}


func apply_behavior_snapshot(data: Dictionary) -> void:
	if _custom_behavior and _custom_behavior.has_method("apply_network_state"):
		_custom_behavior.apply_network_state(self, data)
