extends SceneTree

## New tactics must be dodgeable and authoritative. Tests drive real Enemy
## physics from chase through warning, attack and recovery without calling
## perform_attack or manually inflicting the expected target damage.
const ORIGIN := Vector3(0, 30, 0)
var _main: Node3D
var _world: Node3D
var _scene: PackedScene
var _database: Script
var _checks := 0
var _failures: Array[String] = []

class Target extends CharacterBody3D:
	var dead := false
	var damage_received := 0.0
	var health := 100.0
	var max_health := 100.0
	var hits: Array[Dictionary] = []
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 1
		var collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.34
		capsule.height = 1.8
		collider.shape = capsule
		collider.position.y = 0.9
		add_child(collider)
	func take_damage(amount: float, source: Node = null, _knockback: float = 0.0) -> void:
		damage_received += amount
		hits.append({"amount": amount, "source": source, "time": Time.get_ticks_msec() * 0.001})
	func add_trauma(_amount: float) -> void:
		pass
	func collect(_kind: String, _amount: float) -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[special] FAIL " + description)
	return condition

func _run() -> void:
	root.get_node("Game")._test_profile = true
	root.get_node("NET").leave()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_main.director.stop()
	_main.title.close()
	_main.player.set_controls(false)
	_main.player.set_process(false)
	_main.player.set_physics_process(false)
	_main.player.remove_from_group("player")
	_main.player.remove_from_group("coop_players")
	_main.player.position = ORIGIN + Vector3(0, 0, -45)
	_world = Node3D.new()
	_main.add_child(_world)
	_box(Vector3(100, 0.5, 100), ORIGIN - Vector3.UP * 0.25)
	_scene = load("res://scenes/enemy.tscn")
	_database = load("res://scripts/enemies/enemy_db.gd")
	if not _check(_database.ids().has("leaper") and _database.ids().has("reaver"), "special archetypes are registered"):
		_finish()
		return
	_check(not _database.unlocked_for_wave(2).has("leaper") and _database.unlocked_for_wave(3).has("leaper"), "leaper unlocks on wave three")
	_check(not _database.unlocked_for_wave(5).has("reaver") and _database.unlocked_for_wave(6).has("reaver"), "reaver unlocks on wave six")
	await physics_frame
	await physics_frame
	await _test_rigs_and_near_fallback()
	await _test_leap_dodge()
	await _test_leap_hit_and_wall()
	await _test_spin_multiple_targets()
	await _test_target_lost()
	await _test_interruptible_warnings()
	await _test_dead_and_proxy()
	_finish()

func _test_rigs_and_near_fallback() -> void:
	for id in ["leaper", "reaver"]:
		var target := _target(ORIGIN + Vector3(0, 0, -1.5))
		var enemy := _enemy(id)
		if _check(await _until(func(): return enemy.state == "windup", 2.0), id + " close target starts a readable attack"):
			_check(String(enemy.attack_kind) == id + "_melee", id + " uses close-range fallback instead of a special lunge")
		_check(enemy.anim.has("head") and enemy.anim.has("arm_l") and enemy.anim.has("arm_r"), id + " has head and articulated weapon arms")
		var weapon_found := false
		for key in enemy.anim:
			weapon_found = weapon_found or String(key) in ["blade", "blades", "sword", "sword_l", "sword_r", "weapon", "dual_blades"]
		_check(weapon_found, id + " exposes a distinct blade rig")
		var arm_count := 0
		for area in enemy.hitboxes:
			if area.body_part == "arm":
				arm_count += 1
		_check(arm_count >= 2 and enemy.damage_rids().size() > 5, id + " visible arms belong to damage silhouette")
		_check(await _until(func(): return target.hits.size() > 0, 2.0), id + " close fallback lands during actual state flow")
		enemy.free()
		target.free()
		await physics_frame
	print("[special] distinct rigs / hitboxes / close fallbacks checked")

func _test_leap_dodge() -> void:
	var target := _target(ORIGIN + Vector3(0, 0, -7))
	var enemy := _enemy("leaper")
	if not _check(await _until(func(): return enemy.state == "windup" and enemy.attack_kind == "leap_cut", 3.0), "leaper begins leap warning from chase"):
		enemy.free()
		target.free()
		return
	var strategy = enemy._custom_behavior
	var locked: Vector3 = strategy.landing
	_check(locked.distance_to(target.global_position) < 0.8, "leap warning locks the original target location")
	_check(is_instance_valid(strategy.telegraph) and strategy.telegraph.active, "leap displays an active landing warning")
	target.position += Vector3.RIGHT * 5.0
	var highest := enemy.global_position.y
	var airborne := false
	var landed := false
	var deadline := Time.get_ticks_msec() + 3500
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		highest = maxf(highest, enemy.global_position.y)
		airborne = airborne or enemy.state == "leap"
		if airborne and enemy.state == "recover":
			landed = true
			break
	_check(airborne and highest > ORIGIN.y + 0.8, "leap performs actual airborne movement")
	_check(landed and Vector2(enemy.global_position.x - locked.x, enemy.global_position.z - locked.z).length() < 0.65, "leap lands at announced position instead of tracking a dodging player")
	_check(target.hits.is_empty(), "moving out of the warning avoids the landing strike")
	_check(strategy.special_cd > 1.0, "leap consumes its special cooldown")
	var hit_count := target.hits.size()
	await create_timer(0.35).timeout
	_check(enemy.state == "recover" and target.hits.size() == hit_count, "landing recovery cannot repeat the attack")
	await _until(func(): return enemy.state == "chase", 1.0)
	await create_timer(0.3).timeout
	_check(not (enemy.state == "windup" and enemy.attack_kind == "leap_cut"), "leap cannot immediately repeat through recovery")
	enemy.free()
	target.free()
	await physics_frame
	print("[special] locked landing / dodge / airborne / recovery / cooldown checked")

func _test_leap_hit_and_wall() -> void:
	var target := _target(ORIGIN + Vector3(0, 0, -6))
	var enemy := _enemy("leaper")
	_check(await _until(func(): return enemy.state == "leap", 3.0), "undodged target reaches live leap")
	_check(target.hits.is_empty(), "leap windup does not apply landing damage early")
	_check(await _until(func(): return enemy.state == "recover", 2.0), "undodged leap reaches recovery")
	_check(target.hits.size() == 1 and target.damage_received > 0.0, "undodged landing applies exactly one impact")
	await create_timer(0.4).timeout
	_check(target.hits.size() == 1, "landing impact is not repeated during recovery")
	enemy.free()
	target.free()
	await physics_frame
	target = _target(ORIGIN + Vector3(0, 0, -7))
	enemy = _enemy("leaper")
	if _check(await _until(func(): return enemy.state == "windup" and enemy.attack_kind == "leap_cut", 3.0), "wall fixture obtains locked leap warning"):
		var wall := _box(Vector3(7, 7, 0.4), ORIGIN + Vector3(0, 3.5, -3.5))
		await physics_frame
		await physics_frame
		await _until(func(): return enemy.state == "recover", 3.0)
		_check(target.hits.is_empty(), "solid wall prevents landing damage to covered target")
		_check(enemy.global_position.z > ORIGIN.z - 3.8, "jump attack does not teleport through a tall wall")
		wall.free()
	enemy.free()
	target.free()
	await physics_frame
	print("[special] single impact / solid cover checked")

func _test_spin_multiple_targets() -> void:
	var target := _target(ORIGIN + Vector3(0, 0, -4.6))
	var enemy := _enemy("reaver")
	if not _check(await _until(func(): return enemy.state == "windup" and enemy.attack_kind == "spin_cut", 3.0), "reaver begins visible spin warning"):
		enemy.free()
		target.free()
		return
	var strategy = enemy._custom_behavior
	_check(is_instance_valid(strategy.telegraph) and strategy.telegraph.active, "spin radius is previewed before attack")
	var attack_center: Vector3 = enemy.global_position
	target.hits.clear()
	target.damage_received = 0.0
	target.position = attack_center + Vector3(-1.6, 0, -0.5)
	var second := _target(attack_center + Vector3(1.6, 0, -0.5))
	var covered := _target(attack_center + Vector3(0, 0, 2.4))
	var wall := _box(Vector3(3.4, 5, 0.20), attack_center + Vector3(0, 2.5, 1.3))
	await physics_frame
	await physics_frame
	_check(target.hits.is_empty() and second.hits.is_empty(), "spin windup does not inflict early damage")
	_check(await _until(func(): return enemy.state == "spin", 2.0), "warning flows into live spin")
	var spin_start: Vector3 = enemy.global_position
	enemy.take_damage(1.0, Vector3.ZERO, enemy.aim_point())
	await create_timer(0.18).timeout
	var slow_velocity := Vector2(enemy.velocity.x, enemy.velocity.z).length()
	_check(slow_velocity < float(enemy.speed) * 0.4 * 0.95, "impact slowdown also reduces spin translation")
	_check(await _until(func(): return enemy.state == "recover", 3.0), "spin exits into recovery")
	_check(enemy.global_position.distance_to(spin_start) < float(enemy.speed) * 1.7, "spin advances at controlled speed")
	_check(target.hits.size() >= 2 and second.hits.size() >= 2, "spin damages multiple co-op targets independently")
	for victim in [target, second]:
		for i in range(1, victim.hits.size()):
			_check(float(victim.hits[i].time) - float(victim.hits[i - 1].time) >= 0.40, "spin per-target contact cooldown prevents frame-rate damage")
	_check(covered.hits.is_empty(), "wall blocks a spin victim within its radius")
	var count := target.hits.size() + second.hits.size()
	await create_timer(0.35).timeout
	_check(enemy.state == "recover" and target.hits.size() + second.hits.size() == count, "spin recovery cannot continue ticking damage")
	_check(strategy.special_cd > 0.0, "spin special has a post-attack cooldown")
	wall.free()
	enemy.free()
	target.free()
	second.free()
	covered.free()
	await physics_frame
	print("[special] spin warning / multiple targets / cooldown / cover / slowdown checked")

func _test_target_lost() -> void:
	for id in ["leaper", "reaver"]:
		var target := _target(ORIGIN + Vector3(0, 0, -6))
		var enemy := _enemy(id)
		var active_state := "leap" if id == "leaper" else "spin"
		if _check(await _until(func(): return enemy.state == active_state, 8.0), id + " target-loss fixture reaches live attack"):
			target.dead = true
			_check(await _until(func(): return enemy.state == "recover", 2.5), id + " completes and recovers after its chosen target dies")
			_check(enemy.global_position.y < ORIGIN.y + 0.2, id + " cannot remain suspended after target loss")
		enemy.free()
		target.free()
		await physics_frame
	print("[special] target loss during active attacks checked")


func _test_interruptible_warnings() -> void:
	for id in ["leaper", "reaver"]:
		var target := _target(ORIGIN + Vector3(0, 0, -6))
		var enemy := _enemy(id)
		if _check(await _until(func(): return enemy.state == "windup" and enemy.attack_kind in ["leap_cut", "spin_cut"], 8.0), id + " interruption fixture reaches special warning"):
			target.hits.clear()
			enemy.take_damage(1.0, Vector3.ZERO, enemy.aim_point(), true)
			_check(enemy.state == "recover", id + " critical hit interrupts a special warning")
			await create_timer(0.40).timeout
			_check(target.hits.is_empty() and enemy.state == "recover", id + " cancelled warning never resolves hidden damage")
			_check(enemy._custom_behavior.special_cd > 0.0, id + " interrupted warning still consumes its special cooldown")
		enemy.free()
		target.free()
		await physics_frame
	print("[special] critical warning interruption / cancelled damage checked")


func _test_dead_and_proxy() -> void:
	for id in ["leaper", "reaver"]:
		var target := _target(ORIGIN + Vector3(0, 0, -6))
		var enemy := _enemy(id)
		var active_state := "leap" if id == "leaper" else "spin"
		if not _check(await _until(func(): return enemy.state == "windup" and enemy.attack_kind in ["leap_cut", "spin_cut"], 8.0), id + " death fixture reaches windup"):
			enemy.free()
			target.free()
			continue
		var snapshot: Dictionary = enemy.get_behavior_snapshot()
		var snapshot_state: String = enemy.state
		var kind: String = enemy.attack_kind
		var warning_timer: float = enemy.state_timer
		target.hits.clear()
		target.damage_received = 0.0
		enemy.take_damage(enemy.max_health * 2.0, Vector3.ZERO, enemy.aim_point())
		await create_timer(1.0).timeout
		_check(target.hits.is_empty(), id + " death cancels pending special damage")
		# A late-arriving proxy receives a snapshot and draws its warning while its
		# simulation remains frozen; no custom attack may run on the client.
		var proxy := _enemy(id)
		proxy.frozen = true
		proxy.set_meta("network_proxy", true)
		proxy.state = snapshot_state
		proxy.attack_kind = kind
		proxy.state_timer = warning_timer
		proxy.apply_behavior_snapshot(snapshot)
		await process_frame
		await process_frame
		_check(is_instance_valid(proxy._custom_behavior.telegraph) and proxy._custom_behavior.telegraph.active, id + " proxy snapshot restores attack telegraph")
		var before := target.hits.size()
		await create_timer(1.2).timeout
		_check(target.hits.size() == before, id + " frozen proxy is presentation-only")
		proxy.free()
		target.free()
		await physics_frame
	print("[special] death cancellation / snapshot telegraphs / proxy authority checked")

func _enemy(id: String) -> Node3D:
	var enemy: Node3D = _scene.instantiate()
	enemy.setup(id, 6, false)
	enemy.position = ORIGIN + Vector3.UP * 0.03
	_world.add_child(enemy)
	enemy.state = "chase"
	enemy.complete_spawn_visual()
	enemy.max_health = 10000.0
	enemy.health = 10000.0
	return enemy

func _target(position: Vector3) -> Target:
	var target := Target.new()
	target.position = position
	_world.add_child(target)
	target.add_to_group("player")
	target.add_to_group("coop_players")
	return target

func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = position
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	_world.add_child(body)
	return body

func _until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await physics_frame
	return condition.call()

func _finish() -> void:
	if is_instance_valid(_world):
		_world.free()
	root.get_node("Sfx").shutdown()
	await create_timer(0.20).timeout
	print("[special] RESULT checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
