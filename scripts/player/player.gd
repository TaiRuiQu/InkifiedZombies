class_name Player
extends CharacterBody3D

signal died
signal damaged(amount: float)
signal hitmarker(killed: bool, crit: bool)
signal stats_changed
signal damage_direction(amount: float, source_position: Vector3, shield_hit: bool)
signal combat_feedback(amount: float, critical: bool, killed: bool, headshot: bool)

const WeaponViewScript: Script = preload("res://scripts/player/weapon_view.gd")
const ProjectileScript: Script = preload("res://scripts/combat/projectile.gd")

const WALK_SPEED := 5.7
const SPRINT_SPEED := 8.7
const CROUCH_SPEED := 3.1
const JUMP_VELOCITY := 8.5
const GRAVITY := 22.0
const MOUSE_SENS := 0.00215

var head: Node3D
var camera: Camera3D
var view: WeaponView

var mods: Dictionary = {}
var max_health := 100.0
var health := 100.0
var max_shield := 0.0
var shield := 0.0
var shield_regen_timer := 0.0

var owned_weapons: Array[String] = ["brush_pistol"]
var current_weapon := "brush_pistol"
var ammo: Dictionary = {}
var reloading := false
var reload_timer := 0.0
var reload_total := 1.0
var fire_timer := 0.0
var bloom := 0.0
var spread_now := 0.0

var aiming := false
var sprinting := false
var crouching := false
var dead := false
var controls_enabled := false
var input_cooldown := 0.0
var invuln_time := 0.0

var skills: Dictionary = {}
var skill_cooldowns: Dictionary = {}
var upgrade_counts: Dictionary = {}

var dash_time := 0.0
var dash_dir := Vector3.ZERO
var dash_cd: float:
	get: return float(skill_cooldowns.get("dash", 0.0))
	set(value): skill_cooldowns["dash"] = value
var nova_cd: float:
	get: return float(skill_cooldowns.get("nova", 0.0))
	set(value): skill_cooldowns["nova"] = value
var talisman_cd: float:
	get: return float(skill_cooldowns.get("talisman", 0.0))
	set(value): skill_cooldowns["talisman"] = value
var melee_cd := 0.0
var chain_cd := 0.0
var explosive_cd := 0.0

var recoil := Vector2.ZERO
var trauma := 0.0
var bob_phase := 0.0
var bob_amount := 0.0
var camera_roll := 0.0
var _recoil_seed := 0.0

var aim_at_enemy := false
var _was_on_floor := true
var _footstep_timer := 0.0
var _regen_accum := 0.0
var _kill_streak := 0
var _in_kill_nova := false
var _dash_damage_done := false
var _death_camera_tween: Tween
var wall_decals: Array[Node] = []
var damage_sequence := 0
var last_damage_amount := 0.0
var last_damage_position := Vector3.INF
var last_damage_shield := false
var _hurt_rotation := Vector3.ZERO
var _heartbeat_timer := 0.0
var _reload_stages := 0
var _shot_rng := RandomNumberGenerator.new()
var _shot_basis := Basis.IDENTITY
var _last_shot_traces: Array = []
var _pending_melee := -1.0
var _body_collision: CollisionShape3D
var _standing_clearance := CapsuleShape3D.new()
var _landing_offset := 0.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("coop_players")
	collision_layer = 2
	collision_mask = 5 | 64
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	_build_collision()
	_build_camera()
	_init_mods()
	skills = SkillDB.initial_unlocks()
	health = max_health
	_init_weapon("brush_pistol")
	view.set_weapon("brush_pistol")
	_apply_ammo_display()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_collision() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	_body_collision = col
	_standing_clearance.radius = 0.33
	_standing_clearance.height = 1.78
	col.position.y = 0.9
	add_child(col)


func _build_camera() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.63, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = float(Settings.get_value("fov"))
	camera.near = 0.025
	camera.far = 900.0
	head.add_child(camera)
	view = WeaponViewScript.new()
	view.name = "WeaponView"
	camera.add_child(view)


func _init_mods() -> void:
	mods = {
		"damage_mult": 1.0,
		"fire_rate_mult": 1.0,
		"reload_mult": 1.0,
		"spread_mult": 1.0,
		"mag_mult": 1.0,
		"reserve_mult": 1.0,
		"move_speed_mult": 1.0,
		"recoil_mult": 1.0,
		"crit_chance": 0.04,
		"crit_mult": 1.8,
		"pellets_add": 0,
		"pierce_add": 0,
		"multishot": 0,
		"lifesteal": 0.0,
		"heal_on_kill": 0.0,
		"slow_on_hit": 0.0,
		"explosive": 0,
		"chain": 0,
		"thorns": 0.0,
		"ammo_regen": 0.0,
		"melee_mult": 1.0,
		"melee_push": 4.0,
		"shield_break_blast": 0,
		"dash_cd_mult": 1.0,
		"dash_damage": 0.0,
		"nova_radius": 6.0,
		"nova_damage": 80.0,
		"talisman_radius": 4.5,
		"talisman_damage": 95.0,
		"kill_nova": 0,
		"revives": 0,
	}


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * float(Settings.get_value("mouse_sensitivity")) * (0.62 if aiming else 1.0)
		head.rotation.y -= event.relative.x * sens
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sens * (-1.0 if Settings.get_value("invert_y") else 1.0), -1.45, 1.45)
		view.notify_look(event.relative)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(1)


func set_controls(enabled: bool) -> void:
	controls_enabled = enabled
	if enabled:
		input_cooldown = 0.25
		fire_timer = maxf(fire_timer, 0.15)
	if not enabled:
		aiming = false
		sprinting = false
		view.set_aiming(false)


func make_camera_current() -> void:
	if camera:
		camera.current = true


# --------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if dead:
		_update_death_camera(delta)
		return
	if input_cooldown > 0.0:
		input_cooldown -= delta
	fire_timer -= delta
	melee_cd = maxf(melee_cd - delta, 0.0)
	for skill_id in skill_cooldowns:
		skill_cooldowns[skill_id] = maxf(float(skill_cooldowns[skill_id]) - delta, 0.0)
	chain_cd = maxf(chain_cd - delta, 0.0)
	explosive_cd = maxf(explosive_cd - delta, 0.0)
	invuln_time = maxf(invuln_time - delta, 0.0)
	shield_regen_timer = maxf(shield_regen_timer - delta, 0.0)
	bloom = move_toward(bloom, 0.0, delta * 6.0)
	_update_recoil(delta)
	_update_shield(delta)
	_update_ammo_regen(delta)
	_update_camera(delta)
	_update_aim_target()
	if _pending_melee >= 0.0:
		_pending_melee -= delta
		if _pending_melee < 0.0:
			_resolve_melee()
	if health_ratio() < 0.3 and Game.state == Game.State.PLAYING and is_local_actor():
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = lerpf(0.65, 1.2, health_ratio() / 0.3)
			Sfx.play("heartbeat", -12.0)

	if reloading:
		_update_reload_sounds()
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()

	if not controls_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_set_aiming(false)
		sprinting = false
		view.set_aiming(false)
		return
	if input_cooldown > 0.0:
		return

	# Aim-down-sights.
	var want_aim := Input.is_action_pressed("aim") and not sprinting and not reloading
	_set_aiming(want_aim)

	# Weapon selection.
	for i in range(owned_weapons.size()):
		if i < 6 and Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			switch_to_index(i)
	if Input.is_action_just_pressed("swap"):
		_cycle_weapon(1)

	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_just_pressed("melee"):
		_melee_attack()
	for skill_id in SkillDB.ids():
		var definition := SkillDB.get_skill(skill_id)
		if Input.is_action_just_pressed(definition.input_action):
			SkillDB.cast(skill_id, self)

	if not reloading:
		_try_fire()


func _physics_process(delta: float) -> void:
	if dash_time > 0.0:
		velocity = dash_dir * 25.0
		velocity.y = 0.0
		move_and_slide()
		dash_time -= delta
		if dash_time <= 0.0 and not _dash_damage_done:
			_dash_damage_done = true
			_finish_dash()
		return

	var input_vec := Vector2.ZERO
	if controls_enabled and not dead:
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, head.rotation.y) * Vector3(input_vec.x, 0.0, input_vec.y)
	var wish_len := wish.length()
	if wish_len > 1.0:
		wish = wish / wish_len
		wish_len = 1.0

	var wants_crouch := controls_enabled and Input.is_action_pressed("crouch") and not dead
	crouching = wants_crouch or (crouching and not _can_stand())
	var body_height := 1.22 if crouching else 1.8
	(_body_collision.shape as CapsuleShape3D).height = body_height
	_body_collision.position.y = body_height * 0.5
	aiming = aiming and not dead
	sprinting = controls_enabled and Input.is_action_pressed("sprint") and not aiming and not crouching and wish_len > 0.1 and not reloading

	var speed: float = WALK_SPEED * float(mods.move_speed_mult)
	if sprinting:
		speed = SPRINT_SPEED * float(mods.move_speed_mult)
	elif crouching:
		speed = CROUCH_SPEED * float(mods.move_speed_mult)
	elif aiming:
		speed *= 0.72

	var target_vel: Vector3 = wish * speed * wish_len
	var accel := 16.0 if is_on_floor() else 4.5
	if dead:
		target_vel = Vector3.ZERO
		accel = 8.0
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)

	if controls_enabled and not dead and is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			_footstep_timer = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -0.5

	_was_on_floor = is_on_floor()
	move_and_slide()
	if not _was_on_floor and is_on_floor():
		add_trauma(0.1)
		_landing_offset = -0.055
		view.notify_land()
		_play_personal_sound("land", -7.0, randf_range(0.94, 1.06))

	_update_footsteps(delta, wish_len, speed)
	_update_bob(delta, speed, wish_len)

	# Crouch head height.
	var target_head_y := 1.12 if crouching else 1.63
	head.position.y = lerpf(head.position.y, target_head_y, 1.0 - exp(-delta * 11.0))


func _update_footsteps(delta: float, wish_len: float, speed: float) -> void:
	if dead or not is_on_floor() or wish_len < 0.1 or speed < 0.2:
		_footstep_timer = 0.0
		return
	var interval := 0.48 if not sprinting else 0.34
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = interval
		_play_personal_sound("step_paper" if map_floor_is_paper() else "step_stone", -12.0, randf_range(0.95, 1.05))
		view.notify_look(Vector2(randf_range(-0.6, 0.6), 0.4))


func _update_bob(delta: float, speed: float, wish_len: float) -> void:
	if is_on_floor() and wish_len > 0.1:
		bob_phase += delta * (7.0 + speed * 0.7)
		bob_amount = lerpf(bob_amount, clampf(speed / SPRINT_SPEED, 0.0, 1.0) * 0.032, 1.0 - exp(-delta * 8.0))
	else:
		bob_amount = lerpf(bob_amount, 0.0, 1.0 - exp(-delta * 7.0))
	var target_roll := 0.0
	if controls_enabled:
		var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		target_roll = -input_vec.x * (0.012 if not aiming else 0.004)
	camera_roll = lerpf(camera_roll, target_roll, 1.0 - exp(-delta * 8.0))


func _update_camera(delta: float) -> void:
	var bob := Vector3(
		cos(bob_phase * 0.5) * bob_amount * 0.6,
		absf(sin(bob_phase)) * bob_amount,
		0.0
	)
	var motion := 1.0 if Settings.get_value("camera_shake") else 0.0
	bob.y += _landing_offset
	_landing_offset = lerpf(_landing_offset, 0.0, 1.0 - exp(-delta * 13.0))
	bob *= motion
	var shake := trauma * trauma * motion
	var shake_off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.018
	var shake_rot := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.02
	camera.position = bob + shake_off
	camera.rotation = Vector3(recoil.x + shake_rot.x, recoil.y + shake_rot.y, camera_roll * motion + shake_rot.z) + _hurt_rotation * motion
	_hurt_rotation = _hurt_rotation.lerp(Vector3.ZERO, 1.0 - exp(-delta * 12.0))
	trauma = maxf(trauma - delta * 1.9, 0.0)

	var base_fov := float(Settings.get_value("fov"))
	var fov_target := base_fov
	if aiming:
		fov_target = base_fov * 0.705
	elif sprinting:
		fov_target = base_fov + 4.0 * motion
	if dash_time > 0.0:
		fov_target = base_fov + 9.0 * motion
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-delta * 10.0))
	view.set_aiming(aiming)
	view.set_dashing(dash_time > 0.0)
	var proximity := CombatQuery.ray(self, camera.global_position, camera.global_position - camera.global_transform.basis.z * 1.25, [get_rid()], 1)
	view.wall_proximity = 0.0 if proximity.is_empty() else clampf(1.0 - camera.global_position.distance_to(proximity.position) / 1.25, 0.0, 1.0)
	view.update_motion(delta, Vector2(velocity.x, velocity.z).length(), is_on_floor())


func _update_aim_target() -> void:
	var origin := camera.global_position
	var hit := CombatQuery.ray(self, origin, origin - camera.global_transform.basis.z * 90.0, [get_rid()])
	aim_at_enemy = not hit.is_empty() and CombatQuery.enemy_from_collider(hit.collider) != null


func _update_recoil(delta: float) -> void:
	recoil = recoil.lerp(Vector2.ZERO, 1.0 - exp(-delta * 8.5))


func _update_shield(delta: float) -> void:
	if shield_regen_timer > 0.0:
		return
	if shield < max_shield:
		shield = minf(max_shield, shield + delta * 7.0)


func _update_ammo_regen(delta: float) -> void:
	var regen: float = mods.ammo_regen
	if regen <= 0.0:
		return
	_regen_accum += regen * delta
	if _regen_accum >= 1.0:
		var whole := int(_regen_accum)
		_regen_accum -= float(whole)
		var st: Dictionary = ammo[current_weapon]
		st["reserve"] = mini(int(st.reserve) + whole, _reserve_cap(WeaponDB.get_weapon(current_weapon)))


func _set_aiming(value: bool) -> void:
	if aiming == value:
		return
	aiming = value
	view.set_aiming(value)


# --------------------------------------------------------------------------
# Weapons
# --------------------------------------------------------------------------

func _init_weapon(id: String) -> void:
	var w := WeaponDB.get_weapon(id)
	var cap := _mag_cap(w)
	var reserve := _reserve_cap(w)
	ammo[id] = {"mag": cap, "reserve": reserve}
	if not owned_weapons.has(id):
		owned_weapons.append(id)


func _mag_cap(w: Dictionary) -> int:
	return maxi(1, int(round(float(w.mag) * float(mods.mag_mult))))


func _reserve_cap(w: Dictionary) -> int:
	return maxi(1, int(round(float(w.reserve) * float(mods.reserve_mult))))


func _apply_ammo_display() -> void:
	stats_changed.emit()


func get_weapon_data() -> Dictionary:
	return WeaponDB.get_weapon(current_weapon)


func current_mag() -> int:
	return int(ammo.get(current_weapon, {"mag": 0}).mag)


func current_reserve() -> int:
	return int(ammo.get(current_weapon, {"reserve": 0}).reserve)


func current_mag_cap() -> int:
	return _mag_cap(get_weapon_data())


func current_reserve_cap() -> int:
	return _reserve_cap(get_weapon_data())


func current_weapon_index() -> int:
	return owned_weapons.find(current_weapon)


func switch_to_index(index: int) -> void:
	if dead or index < 0 or index >= owned_weapons.size():
		return
	var id := owned_weapons[index]
	if id == current_weapon:
		return
	current_weapon = id
	if Coop.is_client():
		Coop.request_action("equip", {"weapon": id})
	reloading = false
	view.finish_reload()
	view.set_weapon(id)
	fire_timer = maxf(fire_timer, 0.28)
	bloom = 0.0
	Sfx.play("equip", -5.0, randf_range(0.95, 1.1))
	stats_changed.emit()


func _cycle_weapon(dir: int) -> void:
	if owned_weapons.size() <= 1:
		return
	var idx := owned_weapons.find(current_weapon)
	idx = (idx + dir + owned_weapons.size()) % owned_weapons.size()
	switch_to_index(idx)


func start_reload() -> void:
	if Coop.is_client():
		Coop.request_action("reload")
	if reloading or dead:
		return
	var w := get_weapon_data()
	var st: Dictionary = ammo[current_weapon]
	if int(st.mag) >= current_mag_cap() or int(st.reserve) <= 0:
		return
	reloading = true
	reload_total = maxf(float(w.reload) / maxf(float(mods.reload_mult), 0.2), 0.15)
	reload_timer = reload_total
	view.start_reload(reload_total)
	_reload_stages = 0
	_play_personal_sound("reload_eject", -5.0)
	stats_changed.emit()


func _finish_reload() -> void:
	reloading = false
	var st: Dictionary = ammo[current_weapon]
	var cap := current_mag_cap()
	var need := cap - int(st.mag)
	var take := mini(need, int(st.reserve))
	st.mag = int(st.mag) + take
	if current_weapon != WeaponDB.STARTING_WEAPON:
		st.reserve = int(st.reserve) - take
	view.finish_reload()
	_play_personal_sound("reload_end", -6.0)
	stats_changed.emit()


func _try_fire() -> void:
	if reloading or fire_timer > 0.0 or dash_time > 0.0:
		return
	var w := get_weapon_data()
	var auto: bool = w.auto
	var wants := Input.is_action_pressed("fire") if auto else Input.is_action_just_pressed("fire")
	if not wants:
		return
	var st: Dictionary = ammo[current_weapon]
	if int(st.mag) <= 0:
		if Input.is_action_just_pressed("fire"):
			Sfx.play("empty", -4.0)
		start_reload()
		return
	_fire_shot(w, st)


func _fire_shot(w: Dictionary, st: Dictionary, context: Dictionary = {}) -> void:
	if dead or reloading or int(st.mag) <= 0:
		return
	var shot_seed := int(context.get("shot_seed", randi()))
	_shot_rng.seed = shot_seed
	var forward := -camera.global_transform.basis.z
	if context.has("shot_forward"):
		var requested := Coop._unpack(context.shot_forward)
		if requested.length_squared() > 0.5:
			forward = requested.normalized()
	_shot_basis = Basis.looking_at(forward, Vector3.UP)
	var spread := _current_spread(w)
	if context.has("shot_spread"):
		var minimum := float(w.ads_spread if aiming else w.spread) * float(mods.spread_mult) * (0.82 if crouching else 1.0)
		spread = clampf(float(context.shot_spread), minimum, minf(15.0, spread + 0.75))
	Game.shots_fired += 1
	if Coop.is_client():
		Coop.request_action("fire", {"weapon": current_weapon, "shot_seed": shot_seed,
			"shot_spread": spread, "shot_forward": [forward.x, forward.y, forward.z]})
	st.mag = maxi(int(st.mag) - 1, 0)
	fire_timer = 60.0 / maxf(float(w.rpm) * float(mods.fire_rate_mult), 10.0)
	_last_shot_traces.clear()
	var pellets := int(w.pellets) + int(mods.pellets_add) + int(mods.multishot)
	if bool(w.get("projectile", false)):
		if not Coop.is_client():
			_spawn_grenade(w, spread)
	else:
		var camera_origin := camera.global_position
		var muzzle_origin := safe_muzzle_origin()
		for i in pellets:
			var direction := _spread_direction(spread)
			var aim_end := camera_origin + direction * float(w.range)
			var aim_hit := CombatQuery.ray(self, camera_origin, aim_end, [get_rid()])
			if not aim_hit.is_empty():
				aim_end = aim_hit.position
			var physical_direction := (aim_end - muzzle_origin).normalized()
			var result := _trace_ray(muzzle_origin, physical_direction, w)
			if i < maxi(int(w.tracer_count), 1):
				VFX.tracer(get_parent(), muzzle_origin, result.point, w.tracer, 0.018, 0.065)
				_last_shot_traces.append({"from": [muzzle_origin.x, muzzle_origin.y, muzzle_origin.z],
					"to": [result.point.x, result.point.y, result.point.z]})
		if mods.chain > 0 and chain_cd <= 0.0 and not Coop.is_client():
			chain_cd = maxf(0.9 - float(mods.chain) * 0.15, 0.35)
			var chain_target := _nearest_enemy(camera_origin, 12.0)
			if chain_target and CombatQuery.has_line_of_sight(self, camera_origin, chain_target.aim_point()):
				_chain_lightning(chain_target.aim_point(), 0)

	bloom = minf(bloom + float(w.bloom), 10.0)
	var recoil_kick := float(w.recoil) * 0.022 * float(mods.recoil_mult) * (0.7 if aiming else 1.0)
	recoil.x += recoil_kick
	recoil.y += randf_range(-0.25, 0.25) * recoil_kick
	add_trauma(float(w.trauma) * 1.4)
	view.notify_fire()
	VFX.muzzle_flash(get_parent(), safe_muzzle_origin(), Color("ffd18f"), 0.7 if aiming else 1.0)
	_play_personal_sound(String(w.sound), -2.5, randf_range(0.97, 1.03))
	if current_weapon not in ["ink_launcher", "thunder_crossbow"]:
		VFX.eject_casing(get_parent(), camera.global_position + camera.global_transform.basis.x * 0.22 - camera.global_transform.basis.y * 0.18, camera.global_transform.basis.x)
	Coop.shot_fired(self, w)
	if int(st.mag) <= 0 and int(st.reserve) > 0:
		start_reload()
	stats_changed.emit()


func safe_muzzle_origin() -> Vector3:
	var origin := camera.global_position
	var desired := view.muzzle_world()
	var obstruction := CombatQuery.ray(self, origin, desired, [get_rid()])
	if obstruction.is_empty():
		return desired
	var normal: Vector3 = obstruction.normal
	if normal.length_squared() < 0.01:
		return origin
	return obstruction.position + normal * 0.025


func _current_spread(w: Dictionary) -> float:
	var base := float(w.ads_spread) if aiming else float(w.spread)
	var spread := base * float(mods.spread_mult) + bloom
	if sprinting:
		spread += 2.8
	if crouching:
		spread *= 0.82
	if not bool(get_meta("network_grounded", is_on_floor())):
		spread *= 1.35
	return clampf(spread, 0.0, 15.0)


func _spread_direction(spread_deg: float) -> Vector3:
	var rad := deg_to_rad(maxf(spread_deg, 0.01))
	var a := _shot_rng.randf() * TAU
	var r := sqrt(_shot_rng.randf()) * tan(rad)
	var local := Vector3(cos(a) * r, sin(a) * r, -1.0)
	return (_shot_basis * local).normalized()


func _trace_ray(origin: Vector3, direction: Vector3, w: Dictionary) -> Dictionary:
	var excludes: Array[RID] = [get_rid()]
	var pierce_left := int(w.pierce) + int(mods.pierce_add)
	var ray_end := origin + direction * float(w.range)
	var end_point := ray_end
	var hit_enemy := false
	var hit_ids: Array[int] = []
	for step in range(16):
		var hit := CombatQuery.ray(self, origin, ray_end, excludes)
		if hit.is_empty():
			end_point = ray_end
			break
		end_point = hit.position
		var enemy := CombatQuery.enemy_from_collider(hit.collider)
		if enemy != null:
			hit_enemy = true
			hit_ids.append(enemy.get_instance_id())
			var part := String(hit.collider.get("body_part")) if hit.collider.has_method("get_enemy") else ""
			_damage_enemy(enemy, w, direction, hit.position, part, hit.normal)
			for rid: RID in enemy.damage_rids():
				if not excludes.has(rid):
					excludes.append(rid)
			pierce_left -= 1
			if pierce_left < 0:
				break
		else:
			_wall_impact(hit.position, hit.normal)
			break
	return {"point": end_point, "hit_enemy": hit_enemy, "hit_ids": hit_ids, "from": origin}


func _damage_enemy(enemy: Node, w: Dictionary, dir: Vector3, hit_pos: Vector3, hit_part: String = "", normal: Vector3 = Vector3.UP) -> void:
	if Coop.is_client():
		# Visual prediction is immediate; hit/kill feedback waits for authority.
		VFX.hit_impact(get_parent(), hit_pos, normal, dir, false, false)
		return
	var dist := camera.global_position.distance_to(hit_pos)
	var falloff_range: Vector2 = w.falloff
	var falloff := 1.0
	if dist > falloff_range.x:
		var t := clampf((dist - falloff_range.x) / maxf(falloff_range.y - falloff_range.x, 0.01), 0.0, 1.0)
		falloff = lerpf(1.0, float(w.falloff_min), t)
	var base := float(w.damage) * float(mods.damage_mult) * falloff
	var is_crit := randf() < float(mods.crit_chance)
	var head: bool = hit_part == "head" if not hit_part.is_empty() else enemy.is_headshot(hit_pos)
	var mult := 1.0
	if head:
		mult *= float(w.head_mult)
	if is_crit:
		mult *= float(mods.crit_mult)
	var final := base * mult
	var previous_health: float = enemy.health
	var killed: bool = enemy.take_damage(final, dir, hit_pos, is_crit or head, float(w.knockback), float(mods.slow_on_hit))
	var applied: float = maxf(previous_health - enemy.health, 0.0)
	if applied <= 0.0:
		return
	VFX.hit_impact(get_parent(), hit_pos, normal, dir, enemy.behavior in ["brute", "boss"], is_crit or head)
	confirm_combat(applied, is_crit or head, killed, head)
	Coop.confirm_hit(self, applied, is_crit or head, killed, head, hit_pos, dir)
	if mods.lifesteal > 0.0:
		heal(final * float(mods.lifesteal))
	if killed:
		credit_kill(hit_pos)
	# Explosive rounds (rate-limited so shotguns don't erase the arena).
	if int(mods.explosive) > 0 and explosive_cd <= 0.0:
		explosive_cd = 0.22
		_small_explosion(hit_pos, 2.2, final * 0.32, enemy)
	# Chain lightning is handled per trigger, not per pellet.


func _wall_impact(pos: Vector3, normal: Vector3) -> void:
	if normal.length_squared() < 0.01:
		normal = camera.global_transform.basis.z
	VFX.burst(get_parent(), pos, Color(0.1, 0.09, 0.08, 0.45), 5, 2.6, 0.06, 0.3, Vector3(0, -10, 0))
	if randf() < 0.6:
		var d := VFX.decal(get_parent(), pos, normal, randf_range(0.24, 0.5), Color(0.055, 0.05, 0.045, 0.55), randi() % 3)
		if d:
			wall_decals.append(d)
			while wall_decals.size() > 45:
				var old = wall_decals.pop_front()
				if is_instance_valid(old):
					old.queue_free()


func _spawn_grenade(w: Dictionary, spread: float) -> void:
	var proj = ProjectileScript.new()
	var dmg := float(w.damage) * float(mods.damage_mult)
	var ex := float(w.explode_damage) * float(mods.damage_mult)
	proj.setup({
		"source": self, "friendly": true, "damage": dmg, "speed": 34.0, "gravity": 9.5,
		"lifetime": 5.0, "color": Color("1b1712"), "radius": 0.17,
		"explode_radius": float(w.explode_radius), "explode_damage": ex,
	})
	get_parent().add_child(proj)
	proj.global_position = safe_muzzle_origin()
	proj.launch(_spread_direction(spread))


func _nearest_enemy(from: Vector3, max_dist: float) -> Node:
	var best: Node = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.dead:
			continue
		var d: float = from.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


# --------------------------------------------------------------------------
# Skills / melee
# --------------------------------------------------------------------------

func _melee_attack() -> void:
	if melee_cd > 0.0 or dead:
		return
	melee_cd = 0.62
	view.notify_melee()
	_play_personal_sound("swipe", -5.0)
	if Coop.is_client():
		Coop.request_action("melee")
		return
	_pending_melee = 0.1


func _resolve_melee() -> void:
	if dead:
		return
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var hit := CombatQuery.ray(self, origin, origin + direction * 2.9, [get_rid()])
	var enemy := CombatQuery.enemy_from_collider(hit.get("collider"))
	var did_hit := enemy != null
	if did_hit:
		var damage := 34.0 * float(mods.melee_mult)
		var killed: bool = enemy.take_damage(damage, direction, hit.position, false, 8.0 + float(mods.melee_push), 0.3)
		if killed:
			credit_kill(hit.position)
		confirm_combat(damage, false, killed, false)
		Coop.confirm_hit(self, damage, false, killed, false, hit.position, direction)
		_play_personal_sound("melee_hit", -2.0)
		add_trauma(0.12)
		VFX.hit_impact(get_parent(), hit.position, hit.normal, direction, false, false)
	VFX.slash(get_parent(), origin + direction * 1.4, direction, Ink.CINNABAR if did_hit else Ink.PAPER)


func _start_dash() -> void:
	SkillDB.cast("dash", self)


func _finish_dash() -> void:
	if float(mods.dash_damage) > 0.0:
		var dmg := float(mods.dash_damage) * float(mods.damage_mult)
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or e.dead:
				continue
			if global_position.distance_to(e.global_position) <= 3.2 and CombatQuery.has_line_of_sight(self, global_position + Vector3.UP, e.aim_point()):
				var dir: Vector3 = (e.global_position - global_position).normalized()
				var killed: bool = e.take_damage(dmg, dir, e.global_position + Vector3(0, 1, 0), false, 9.0, 0.45)
				if killed:
					credit_kill(e.global_position)
		VFX.ring(get_parent(), global_position, 3.2, Ink.CINNABAR, 0.4, 0.8)
		Sfx.play("slam", -3.0, 1.2)


func _cast_nova() -> void:
	SkillDB.cast("nova", self)


func _throw_talisman() -> void:
	SkillDB.cast("talisman", self)


func _chain_lightning(first_pos: Vector3, depth: int, visited: Array = []) -> void:
	if depth >= 3:
		return
	var candidates: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.dead:
			continue
		if not visited.has(e) and e.global_position.distance_to(first_pos) <= 8.0 and CombatQuery.has_line_of_sight(self, first_pos, e.aim_point()):
			candidates.append(e)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a.global_position.distance_to(first_pos) < b.global_position.distance_to(first_pos))
	var target = candidates[0]
	visited.append(target)
	var target_pos: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	VFX.beam(get_parent(), first_pos, target_pos, Color("cfd9ff"), 0.026)
	var dmg := 34.0 * float(mods.damage_mult) * (1.0 - depth * 0.2)
	var dir: Vector3 = (target_pos - first_pos).normalized()
	var killed: bool = target.take_damage(dmg, dir, target_pos, false, 2.0, 0.15)
	if killed:
		credit_kill(target_pos)
	Sfx.play("zap", -8.0, randf_range(0.9, 1.2))
	if depth < 2:
		_chain_lightning(target_pos, depth + 1, visited)


func _small_explosion(pos: Vector3, radius: float, dmg: float, ignore: Node = null) -> void:
	VFX.explosion(get_parent(), pos, radius, Ink.CINNABAR)
	Sfx.play("explosion", -8.0, 1.25)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.dead or e == ignore:
			continue
		var d: float = pos.distance_to(e.global_position)
		if d <= radius and CombatQuery.has_line_of_sight(self, pos + Vector3.UP * 0.1, e.aim_point()):
			var dir: Vector3 = (e.global_position - pos).normalized()
			var killed: bool = e.take_damage(dmg * (1.0 - 0.4 * d / radius), dir, e.global_position + Vector3(0, 1, 0), false, 4.0, 0.0)
			if killed:
				credit_kill(e.global_position)


func _shield_blast() -> void:
	var radius := 4.8
	var dmg := 40.0 * float(mods.damage_mult)
	VFX.ring(get_parent(), global_position, radius, Ink.INDIGO_LIGHT, 0.55, 0.9)
	VFX.burst(get_parent(), global_position + Vector3(0, 0.8, 0), Color("8fa6b8"), 24, 6.0, 0.14, 0.6, Vector3(0, -6, 0))
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.dead:
			continue
		if global_position.distance_to(e.global_position) <= radius and CombatQuery.has_line_of_sight(self, global_position + Vector3.UP, e.aim_point()):
			var dir: Vector3 = (e.global_position - global_position).normalized()
			var killed: bool = e.take_damage(dmg, dir, e.global_position + Vector3(0, 1, 0), false, 8.0, 0.2)
			if killed:
				credit_kill(e.global_position)
	Sfx.play("shield_break", 0.0)


# --------------------------------------------------------------------------
# Damage / progression
# --------------------------------------------------------------------------

func take_damage(amount: float, source: Node3D = null, knockback: float = 0.0, source_position: Vector3 = Vector3.INF) -> void:
	if Coop.is_client() or dead or invuln_time > 0.0 or amount <= 0.0:
		return
	amount = maxf(amount, 0.0) * float(RunRules.difficulty(Game.difficulty).incoming_damage)
	var remaining := amount
	var previous_shield := shield
	Game.damage_taken += minf(health + shield, amount)
	invuln_time = 0.28
	shield_regen_timer = 3.2
	if shield > 0.0:
		var absorbed := minf(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
		if shield <= 0.01 and int(mods.shield_break_blast) > 0:
			_shield_blast()
	if remaining > 0.0:
		health = maxf(health - remaining, 0.0)
	if source_position == Vector3.INF and is_instance_valid(source):
		source_position = source.global_position
	damage_sequence += 1
	last_damage_amount = amount
	last_damage_position = source_position
	last_damage_shield = previous_shield > 0.0 and remaining <= 0.0
	apply_damage_feedback(amount, source_position, last_damage_shield)
	if previous_shield > 0.0 and shield <= 0.0 and int(mods.shield_break_blast) == 0:
		_play_personal_sound("shield_break", -1.0)
	if is_instance_valid(source):
		var away := global_position - source.global_position
		away.y = 0.0
		if away.length() > 0.01 and knockback > 0.0:
			velocity += away.normalized() * knockback * 0.35
		if float(mods.thorns) > 0.0 and source.has_method("take_damage"):
			var killed: bool = source.take_damage(float(mods.thorns), away.normalized(), source.global_position + Vector3(0, 1, 0), false, 0.0, 0.0)
			if killed:
				credit_kill(source.global_position)
	if health <= 0.0:
		_on_death()


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = minf(max_health, health + amount)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func collect(kind: String, amount: float) -> void:
	if dead:
		return
	if kind == "health":
		heal(amount)
	elif kind == "ammo":
		var ratio := amount if amount <= 1.0 else 0.3
		for id in owned_weapons:
			var w := WeaponDB.get_weapon(id)
			var st: Dictionary = ammo[id]
			st.reserve = mini(int(st.reserve) + int(round(_reserve_cap(w) * ratio)), _reserve_cap(w))
	stats_changed.emit()


func credit_kill(pos: Vector3) -> void:
	if Coop.is_client():
		return
	_kill_streak += 1
	Game.kills += 1
	if float(mods.heal_on_kill) > 0.0:
		heal(float(mods.heal_on_kill))
	if int(mods.kill_nova) > 0 and _kill_streak % 10 == 0 and not _in_kill_nova:
		_in_kill_nova = true
		var radius := 5.5
		var dmg := 65.0 * float(mods.damage_mult)
		VFX.ring(get_parent(), global_position, radius, Ink.CINNABAR, 0.55, 0.9)
		VFX.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Ink.CINNABAR, 26, 7.0, 0.2, 0.6, Vector3(0, -4, 0))
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or e.dead:
				continue
			if global_position.distance_to(e.global_position) <= radius and CombatQuery.has_line_of_sight(self, global_position + Vector3.UP, e.aim_point()):
				var dir: Vector3 = (e.global_position - global_position).normalized()
				var killed: bool = e.take_damage(dmg, dir, e.global_position + Vector3(0, 1, 0), false, 9.0, 0.0)
				if killed:
					Game.kills += 1
		Sfx.play("nova", -2.0, 1.2)
		_in_kill_nova = false
	stats_changed.emit()


func _on_death() -> void:
	if dead:
		return
	if int(mods.revives) > 0:
		mods.revives = int(mods.revives) - 1
		health = maxf(max_health * 0.5, 1.0)
		invuln_time = 2.0
		view.visible = true
		VFX.explosion(get_parent(), global_position + Vector3(0, 0.8, 0), 6.0, Ink.CINNABAR)
		VFX.ring(get_parent(), global_position, 8.0, Ink.CINNABAR, 0.8, 0.9)
		add_trauma(0.6)
		Sfx.play("revive", 2.0)
		return
	dead = true
	health = 0.0
	controls_enabled = false
	aiming = false
	sprinting = false
	view.set_aiming(false)
	view.finish_reload()
	view.visible = false
	reloading = false
	velocity = Vector3.ZERO
	Sfx.play("player_death", 1.0)
	add_trauma(0.8)
	_death_camera_tween = create_tween()
	_death_camera_tween.set_parallel(true)
	_death_camera_tween.tween_property(head, "position:y", 0.35, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_death_camera_tween.tween_property(camera, "rotation:z", 1.25, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	died.emit()


func _update_death_camera(delta: float) -> void:
	# Keep the post/hud values ticking while dead.
	shield_regen_timer = maxf(shield_regen_timer - delta, 0.0)
	trauma = maxf(trauma - delta * 1.9, 0.0)


# --------------------------------------------------------------------------
# Upgrades
# --------------------------------------------------------------------------

func apply_upgrade(upgrade: Dictionary) -> void:
	var uid := String(upgrade.id)
	upgrade_counts[uid] = int(upgrade_counts.get(uid, 0)) + 1
	var effects: Dictionary = upgrade.get("effects", {})
	for key in effects.keys():
		var value = effects[key]
		match String(key):
			"weapon":
				unlock_weapon(String(value))
			"unlock":
				var skill := String(value)
				if skills.has(skill):
					skills[skill] = true
				stats_changed.emit()
			"heal_flat":
				heal(float(value))
			"heal_percent":
				heal(max_health * float(value))
			"max_health_add":
				max_health += float(value)
				health += float(value)
			"shield_add":
				max_shield += float(value)
				shield += float(value)
			"revive_add":
				mods.revives = int(mods.revives) + int(value)
			"dash_cd_mult_add":
				mods.dash_cd_mult = maxf(0.3, float(mods.dash_cd_mult) + float(value))
			"dash_damage_add":
				mods.dash_damage = float(mods.dash_damage) + float(value)
			"nova_radius_add":
				mods.nova_radius = float(mods.nova_radius) + float(value)
			"nova_damage_mult_add":
				mods.nova_damage = float(mods.nova_damage) * (1.0 + float(value))
			"talisman_radius_add":
				mods.talisman_radius = float(mods.talisman_radius) + float(value)
			"talisman_damage_mult_add":
				mods.talisman_damage = float(mods.talisman_damage) * (1.0 + float(value))
			"thorns_add":
				mods.thorns = float(mods.thorns) + float(value)
			"melee_push_add":
				mods.melee_push = float(mods.melee_push) + float(value)
			"kill_nova_add":
				mods.kill_nova = int(value)
			"explosive_add":
				mods.explosive = int(value)
			"shield_break_blast_add":
				mods.shield_break_blast = int(value)
			"pellets_add", "pierce_add", "multishot_add", "chain_add":
				var base_key := String(key).trim_suffix("_add")
				mods[base_key] = int(mods.get(base_key, 0)) + int(value)
			_:
				var k := String(key)
				if k.ends_with("_add") and mods.has(k.trim_suffix("_add")):
					var base_key := k.trim_suffix("_add")
					mods[base_key] = float(mods[base_key]) + float(value)
				elif mods.has(k):
					mods[k] = float(mods[k]) + float(value)
	mods.crit_chance = clampf(float(mods.crit_chance), 0.0, 0.95)
	mods.spread_mult = maxf(float(mods.spread_mult), 0.15)
	mods.damage_mult = maxf(float(mods.damage_mult), 0.1)
	mods.fire_rate_mult = maxf(float(mods.fire_rate_mult), 0.2)
	mods.reload_mult = maxf(float(mods.reload_mult), 0.2)
	health = clampf(health, 0.0, max_health)
	shield = clampf(shield, 0.0, max_shield)
	stats_changed.emit()


func unlock_weapon(id: String) -> void:
	if not WeaponDB.has_weapon(id) or owned_weapons.has(id):
		return
	_init_weapon(id)
	switch_to_index(owned_weapons.find(id))
	stats_changed.emit()


func get_shield_max() -> float:
	return max_shield


# --------------------------------------------------------------------------
# HUD data
# --------------------------------------------------------------------------

func skill_slots() -> Dictionary:
	var slots := {}
	for id in SkillDB.ids():
		var definition := SkillDB.get_skill(id)
		slots[id] = {"unlocked": bool(skills.get(id, false)),
			"cd": float(skill_cooldowns.get(id, 0.0)),
			"max_cd": SkillDB.cooldown_for(id, mods), "icon": definition.icon,
			"key": Settings.binding_text(definition.input_action), "name": definition.display_name}
	return slots


func resupply_between_waves() -> void:
	var rules := RunRules.difficulty(Game.difficulty)
	heal(max_health * float(rules.recovery))
	collect("ammo", float(rules.reserve_refill))
	reloading = false
	view.finish_reload()
	for id in owned_weapons:
		ammo[id].mag = _mag_cap(WeaponDB.get_weapon(id))
	for skill_id in skill_cooldowns:
		skill_cooldowns[skill_id] = 0.0
	stats_changed.emit()


func reload_ratio() -> float:
	if not reloading:
		return 1.0
	return clampf(1.0 - reload_timer / maxf(reload_total, 0.01), 0.0, 1.0)


func spread_degrees() -> float:
	return _current_spread(get_weapon_data())


func health_ratio() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


func is_dashing() -> bool:
	return dash_time > 0.0


func interact_hint() -> String:
	return ""


func is_local_actor() -> bool:
	return not NET.active or int(get_meta("peer_id", NET.local_id)) == NET.local_id


func _play_personal_sound(id: String, volume: float = -4.0, pitch: float = 1.0) -> void:
	if is_local_actor():
		Sfx.play(id, volume, pitch)
	else:
		Sfx.play_at(id, global_position + Vector3.UP, volume - 3.0, pitch)


func _update_reload_sounds() -> void:
	var progress := 1.0 - reload_timer / maxf(reload_total, 0.01)
	if progress > 0.48 and _reload_stages & 1 == 0:
		_reload_stages |= 1
		_play_personal_sound("reload_insert", -4.5)
	if progress > 0.83 and _reload_stages & 2 == 0:
		_reload_stages |= 2
		_play_personal_sound("reload_bolt", -5.0)


func apply_damage_feedback(amount: float, source_position: Vector3, shield_hit: bool) -> void:
	damaged.emit(amount)
	damage_direction.emit(amount, source_position, shield_hit)
	var side := 0.0
	if source_position != Vector3.INF:
		var local := head.global_transform.basis.inverse() * (source_position - global_position)
		side = clampf(local.x / maxf(local.length(), 0.01), -1.0, 1.0)
	var strength := clampf(amount / maxf(max_health, 1.0), 0.02, 0.5)
	_hurt_rotation += Vector3(-0.025 - strength * 0.07, -side * 0.025, side * 0.045)
	add_trauma(0.26 + strength * 0.65)
	view.notify_hurt(strength, side)
	_play_personal_sound("hurt_shield" if shield_hit else "hurt_flesh", -2.0, randf_range(0.96, 1.04))


func confirm_combat(amount: float, critical: bool, killed: bool, headshot: bool) -> void:
	if not is_local_actor():
		return
	hitmarker.emit(killed, critical)
	combat_feedback.emit(amount, critical, killed, headshot)
	view.confirm_hit(killed, critical)
	if killed:
		Sfx.play("kill_confirm", -2.0)
	elif headshot:
		Sfx.play("headshot", -4.0)


func map_floor_is_paper() -> bool:
	var floor_hit := CombatQuery.ray(self, global_position + Vector3.UP * 0.2, global_position - Vector3.UP * 0.45, [get_rid()], 1)
	return not floor_hit.is_empty() and floor_hit.collider.get_meta("footstep_surface", "stone") == "paper"


func _can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _standing_clearance
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 0.91)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
