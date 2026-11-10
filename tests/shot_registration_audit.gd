extends SceneTree

## Real Player shot code, rather than an isolated physics query. Runs above
## the courtyard so decorative map colliders cannot contaminate the fixtures.
var _main: Node3D
var _player: Node3D
var _world: Node3D
var _scene: PackedScene
var _checks := 0
var _failures: Array[String] = []
var _markers := 0
var _head_markers := 0
const TEST_ORIGIN := Vector3(0, 30, 0)

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, text: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(text)
		push_error("[shots] FAIL " + text)
	return condition

func _run() -> void:
	root.get_node("Game")._test_profile = true
	root.get_node("NET").leave()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_main.director.stop()
	_player = _main.player
	_player.set_controls(false)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.position = TEST_ORIGIN + Vector3(0, 0, -8)
	_player.camera.rotation = Vector3.ZERO
	_player.camera.position = Vector3.ZERO
	_player.view.position = WeaponDB.get_weapon("brush_pistol").view_pos
	_player.mods.crit_chance = 0.0
	_player.mods.damage_mult = 1.0
	_player.mods.pierce_add = 0
	_player.mods.multishot = 0
	_player.mods.pellets_add = 0
	_player.mods.explosive = 0
	_player.mods.chain = 0
	_player.hitmarker.connect(_on_hitmarker)
	_world = Node3D.new()
	_main.add_child(_world)
	_scene = load("res://scenes/enemy.tscn")
	var weapon := _weapon()
	for id in EnemyDB.ids():
		await _test_enemy(id, weapon)
	await _test_piercing(weapon)
	await _test_close_cover(weapon)
	await _test_seeded_pose()
	print("[shots] RESULT checks=%d failures=%d" % [_checks, _failures.size()])
	for sound in root.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
		sound.stream = null
	for sound in root.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
		sound.stream = null
	await create_timer(0.20).timeout
	quit(0 if _failures.is_empty() else 1)

func _test_enemy(id: String, weapon: Dictionary) -> void:
	var failures_before := _failures.size()
	var enemy := _enemy(id, TEST_ORIGIN)
	await create_timer(0.48).timeout
	await physics_frame
	await physics_frame
	var head: Node3D = enemy.anim.head
	var shape: ConvexPolygonShape3D = _head_area(enemy).get_child(0).shape
	var bounds := AABB(shape.points[0], Vector3.ZERO)
	for point in shape.points:
		bounds = bounds.expand(point)
	var offsets := [Vector3.ZERO, Vector3(bounds.size.x * 0.22, 0, 0),
		Vector3(-bounds.size.x * 0.22, 0, 0), Vector3(0, bounds.size.y * 0.22, 0),
		Vector3(0, -bounds.size.y * 0.22, 0)]
	for index in offsets.size():
		_reset_reaction(enemy)
		var target: Vector3 = head.to_global(offsets[index])
		var direction: Vector3 = (target - _player.camera.global_position).normalized()
		var before: float = enemy.health
		var marker_count := _markers
		var result: Dictionary = _player._trace_ray(_player.camera.global_position, direction, weapon)
		_check(result.hit_ids.size() == 1 and int(result.hit_ids[0]) == enemy.get_instance_id(), "%s face %d resolves one actual enemy" % [id, index])
		_check(is_equal_approx(before - enemy.health, float(weapon.damage) * float(weapon.head_mult)), "%s face %d applies head damage" % [id, index])
		_check(_markers == marker_count + 1, "%s face %d confirms hitmarker" % [id, index])
	# The actual trigger path must agree with a centred aim, during spawn too.
	_reset_reaction(enemy)
	_aim(head.global_position)
	var before: float = enemy.health
	var previous_markers := _markers
	var muzzle: Vector3 = _player.safe_muzzle_origin()
	_fire(_player, weapon, 2741)
	_check(enemy.health < before and (enemy.state == "spawn" or id == "boss"), id + " trigger damages visible entering enemy")
	_check(_markers == previous_markers + 1, id + " trigger confirms actual damage")
	_check(not _player._last_shot_traces.is_empty(), id + " trigger emits a physical tracer")
	if not _player._last_shot_traces.is_empty():
		var trace: Dictionary = _player._last_shot_traces[0]
		_check(_vector(trace.from).distance_to(muzzle) < 0.001, id + " tracer begins at the physical muzzle")
		var hit := CombatQuery.ray(_player, _vector(trace.from), _vector(trace.to) + (_vector(trace.to) - _vector(trace.from)).normalized() * 0.01, [_player.get_rid()])
		_check(not hit.is_empty() and CombatQuery.enemy_from_collider(hit.collider) == enemy, id + " tracer endpoint agrees with damage owner")
	# Torso targets and articulated arm tips must use the same Player path.
	for part in ["torso", "arm"]:
		_reset_reaction(enemy)
		var hitbox := _part_area(enemy, part)
		if hitbox == null and part == "torso":
			hitbox = _part_area(enemy, "cloak")
		if not _check(hitbox != null, id + " has tested " + part):
			continue
		var target: Vector3 = hitbox.global_position
		before = enemy.health
		var result: Dictionary = _player._trace_ray(_player.camera.global_position, (target - _player.camera.global_position).normalized(), weapon)
		_check(result.hit_ids.has(enemy.get_instance_id()) and enemy.health < before, id + " Player trace damages " + part)
	# Empty space just outside all painted body parts should never count as a hit.
	var empty := head.global_position + Vector3(enemy.radius * 4.5, 0, 0)
	before = enemy.health
	var result: Dictionary = _player._trace_ray(_player.camera.global_position, (empty - _player.camera.global_position).normalized(), weapon)
	_check(not result.hit_enemy and is_equal_approx(before, enemy.health), id + " outside silhouette misses")
	print("[shots] %s %s face offsets/body/arm/spawn/trigger/tracer/miss" % [id, "PASS" if _failures.size() == failures_before else "FAIL"])
	enemy.free()
	await physics_frame

func _test_piercing(weapon: Dictionary) -> void:
	var first := _enemy("wraith", TEST_ORIGIN)
	var second := _enemy("wraith", TEST_ORIGIN + Vector3(0, 0, 3))
	await create_timer(0.48).timeout
	await physics_frame
	await physics_frame
	var piercing := weapon.duplicate(true)
	piercing.pierce = 2
	piercing.range = 40.0
	var from := TEST_ORIGIN + Vector3(0, 1.17, -8)
	var a: float = first.health
	var b: float = second.health
	var result: Dictionary = _player._trace_ray(from, Vector3.BACK, piercing)
	_check(result.hit_ids.size() == 2, "piercing resolves exactly two unique enemies")
	_check(result.hit_ids == [first.get_instance_id(), second.get_instance_id()], "piercing preserves near-to-far ownership")
	_check(is_equal_approx(a - first.health, float(weapon.damage)), "piercing damages first enemy once")
	_check(is_equal_approx(b - second.health, float(weapon.damage)), "piercing damages second enemy once")
	_check((result.point as Vector3).distance_to(from + Vector3.BACK * 40.0) < 0.01, "remaining penetration extends tracer to full range")
	first.free()
	second.free()
	await physics_frame

func _test_close_cover(weapon: Dictionary) -> void:
	var enemy := _enemy("wraith", TEST_ORIGIN)
	await create_timer(0.48).timeout
	await physics_frame
	await physics_frame
	_aim(enemy.anim.head.global_position)
	var camera_position: Vector3 = _player.camera.global_position
	var desired: Vector3 = _player.view.muzzle_world()
	var plane_z := lerpf(camera_position.z, desired.z, 0.35)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0, camera_position.y, plane_z)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 7, 0.12)
	collider.shape = box
	wall.add_child(collider)
	_world.add_child(wall)
	await physics_frame
	await physics_frame
	var before: float = enemy.health
	var marker_count := _markers
	var safe: Vector3 = _player.safe_muzzle_origin()
	_check(safe.z < plane_z, "near cover retracts physical muzzle to player side")
	_fire(_player, weapon, 8123)
	_check(is_equal_approx(before, enemy.health) and marker_count == _markers, "close cover prevents damage and false hit confirmation")
	if _check(_player._last_shot_traces.size() == 1, "blocked trigger still emits one wall-bound tracer"):
		var trace: Dictionary = _player._last_shot_traces[0]
		_check(_vector(trace.from).distance_to(safe) < 0.001, "blocked tracer starts from retracted muzzle")
		_check(absf(_vector(trace.to).z - (plane_z - 0.06)) < 0.01, "blocked tracer ends at the same cover surface")
	wall.free()
	enemy.free()
	await physics_frame

func _test_seeded_pose() -> void:
	var other: Node3D = load("res://scenes/player.tscn").instantiate()
	_world.add_child(other)
	other.set_controls(false)
	other.set_process(false)
	other.set_physics_process(false)
	other.mods = _player.mods.duplicate(true)
	other.global_transform = _player.global_transform
	other.head.transform = _player.head.transform
	other.camera.transform = _player.camera.transform
	other.view.transform = _player.view.transform
	var enemies: Array[Node3D] = []
	for offset in [Vector3(0, 0, -0.5), Vector3(-0.65, 0, 0.1), Vector3(0.65, 0, 0.8)]:
		enemies.append(_enemy("brute", TEST_ORIGIN + offset))
	await create_timer(0.48).timeout
	await physics_frame
	await physics_frame
	var weapon := _weapon()
	weapon.pellets = 9
	weapon.tracer_count = 9
	weapon.spread = 4.0
	weapon.ads_spread = 4.0
	weapon.bloom = 0.0
	_aim(TEST_ORIGIN + Vector3(0, 1.65, 0))
	other.head.transform = _player.head.transform
	other.camera.transform = _player.camera.transform
	other.view.transform = _player.view.transform
	var initial: Array[float] = []
	for enemy in enemies:
		initial.append(enemy.health)
	_fire(_player, weapon, 555271, 4.0)
	var first_traces: Array = _player._last_shot_traces.duplicate(true)
	var first_damage: Array[float] = []
	for i in enemies.size():
		first_damage.append(initial[i] - enemies[i].health)
		initial[i] = enemies[i].health
	_fire(other, weapon, 555271, 4.0)
	_check(first_traces.size() == 9 and other._last_shot_traces.size() == 9, "seeded spread records every pellet")
	if first_traces.size() == other._last_shot_traces.size():
		for i in first_traces.size():
			_check(_vector(first_traces[i].from).distance_to(_vector(other._last_shot_traces[i].from)) < 0.001, "same pose reproduces muzzle %d" % i)
			_check(_vector(first_traces[i].to).distance_to(_vector(other._last_shot_traces[i].to)) < 0.001, "same seed reproduces impact point %d" % i)
	for i in enemies.size():
		_check(is_equal_approx(first_damage[i], initial[i] - enemies[i].health), "same pose/seed reproduces owner damage %d" % i)
		enemies[i].free()
	other.free()
	await physics_frame

func _enemy(id: String, where: Vector3) -> Node3D:
	var enemy: Node3D = _scene.instantiate()
	enemy.setup(id, 1, false)
	enemy.frozen = true
	enemy.position = where
	_world.add_child(enemy)
	enemy.max_health = 10000.0
	enemy.health = 10000.0
	return enemy

func _weapon() -> Dictionary:
	var result := WeaponDB.get_weapon("brush_pistol").duplicate(true)
	result.damage = 2.0
	result.spread = 0.0
	result.ads_spread = 0.0
	result.bloom = 0.0
	result.knockback = 0.0
	return result

func _fire(player: Node3D, weapon: Dictionary, shot_seed: int, spread: float = 0.0) -> void:
	player.reloading = false
	player.fire_timer = 0.0
	player.bloom = 0.0
	player.ammo[player.current_weapon].mag = 12
	var forward: Vector3 = -player.camera.global_basis.z
	player._fire_shot(weapon, player.ammo[player.current_weapon], {"shot_seed": shot_seed,
		"shot_spread": spread, "shot_forward": [forward.x, forward.y, forward.z]})

func _aim(target: Vector3) -> void:
	_player.head.look_at(target, Vector3.UP)

func _reset_reaction(enemy: Node3D) -> void:
	enemy._hit_react_timer = 0.0
	enemy.visual.rotation = Vector3.ZERO
	enemy.anim.head.rotation = Vector3.ZERO

func _part_area(enemy: Node3D, part: String) -> Area3D:
	for hitbox: Area3D in enemy.hitboxes:
		if hitbox.body_part == part:
			return hitbox
	return null

func _head_area(enemy: Node3D) -> Area3D:
	return _part_area(enemy, "head")

func _vector(array: Array) -> Vector3:
	return Vector3(float(array[0]), float(array[1]), float(array[2]))

func _on_hitmarker(_killed: bool, critical: bool) -> void:
	_markers += 1
	if critical:
		_head_markers += 1
