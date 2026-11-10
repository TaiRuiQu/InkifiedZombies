extends SceneTree

## Real Enemy physics in an unobstructed raised arena. Each archetype pursues
## the same distant player; speed comparisons use travelled world distance.
const ORIGIN := Vector3(0, 30, 0)
const DT := 1.0 / 60.0
var _main: Node3D
var _world: Node3D
var _player: Node3D
var _checks := 0
var _failures: Array[String] = []
var _impact_ratios: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[pacing] FAIL " + description)

func _run() -> void:
	root.get_node("Game")._test_profile = true
	root.get_node("NET").leave()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_main.director.stop()
	_main.title.close()
	_player = _main.player
	_player.set_controls(false)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.position = ORIGIN + Vector3(0, 0, -55)
	_world = Node3D.new()
	_main.add_child(_world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.position = ORIGIN - Vector3.UP * 0.25
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(150, 0.5, 150)
	collider.shape = box
	floor.add_child(collider)
	_world.add_child(floor)
	await physics_frame
	await physics_frame
	for id in EnemyDB.ids():
		await _test_archetype(id)
	_check(float(_impact_ratios.brute) > float(_impact_ratios.wraith) + 0.07, "heavy armor resists impact slowdown more than ordinary enemy")
	_check(float(_impact_ratios.boss) > float(_impact_ratios.brute) + 0.015, "boss has stronger impact resistance than heavy armor")
	await _test_refresh_and_upgrade()
	_world.free()
	root.get_node("Sfx").shutdown()
	await create_timer(0.20).timeout
	print("[pacing] RESULT checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_archetype(id: String) -> void:
	var enemy := _enemy(id)
	var data := EnemyDB.get_type(id)
	var previous_speed := float(data.speed) * (1.0 + minf(4.0 * 0.006, 0.16))
	var faster_speed: float = enemy.speed
	_check(absf(faster_speed / previous_speed - 1.18) < 0.001, id + " setup preserves wave scaling and applies 18% increase")
	enemy.speed = previous_speed
	_reset(enemy)
	await _advance(enemy, 24)
	var old_distance: float = await _advance(enemy, 36)
	enemy.speed = faster_speed
	_reset(enemy)
	await _advance(enemy, 24)
	var new_distance: float = await _advance(enemy, 36)
	_check(new_distance > old_distance * 1.12 and new_distance < old_distance * 1.24, id + " actual pursuit covers more ground")
	var steady_speed := _horizontal_speed(enemy)
	var before: float = enemy.health
	enemy.take_damage(1.0, Vector3.ZERO, enemy.aim_point(), false, 0.0, 0.0)
	_check(enemy.health < before and enemy.impact_slow_timer > 0.20, id + " valid hit starts short movement impairment")
	await _advance(enemy, 10)
	var impacted_speed := _horizontal_speed(enemy)
	var ratio := impacted_speed / maxf(steady_speed, 0.01)
	_impact_ratios[id] = ratio
	_check(enemy.stagger_timer <= 0.0 and enemy.impact_slow_timer > 0.05, id + " slowdown remains after ordinary stagger window")
	_check(ratio < 0.97 and ratio > 0.60, id + " hit reduces actual horizontal velocity")
	await _advance(enemy, 20)
	_check(enemy.impact_slow_timer <= 0.0 and _horizontal_speed(enemy) > steady_speed * 0.96, id + " brief hit slowdown expires and pursuit recovers")
	print("[pacing] %s distance %.3f -> %.3f; hit ratio %.3f" % [id, old_distance, new_distance, ratio])
	enemy.free()
	await physics_frame

func _test_refresh_and_upgrade() -> void:
	var enemy := _enemy("wraith")
	_reset(enemy)
	await _advance(enemy, 30)
	var steady_speed := _horizontal_speed(enemy)
	enemy.take_damage(1.0, Vector3.ZERO, enemy.aim_point())
	await _advance(enemy, 11)
	var first_ratio := _horizontal_speed(enemy) / steady_speed
	enemy.take_damage(1.0, Vector3.ZERO, enemy.aim_point())
	await _advance(enemy, 11)
	_check(enemy.impact_slow_timer > 0.05, "second hit refreshes slowdown past first hit expiry")
	_check(absf(_horizontal_speed(enemy) / steady_speed - first_ratio) < 0.025, "successive hits refresh rather than stack stronger slow")
	await _advance(enemy, 23)
	_check(_horizontal_speed(enemy) > steady_speed * 0.97 and enemy.impact_slow_factor == 0.0, "successive impacts leave no permanent slow")
	# The actual on-hit slow argument uses the same route as the cold-ink upgrade.
	enemy.take_damage(1.0, Vector3.ZERO, enemy.aim_point(), false, 0.0, 0.40)
	await _advance(enemy, 12)
	var cold_ratio := _horizontal_speed(enemy) / steady_speed
	_check(cold_ratio > 0.55 and cold_ratio < 0.66, "cold ink wins over transient impact instead of multiplying both")
	await _advance(enemy, 18)
	_check(enemy.impact_slow_timer <= 0.0 and enemy.slow_timer > 1.0, "cold ink duration survives short impact expiry")
	_check(absf(_horizontal_speed(enemy) / steady_speed - cold_ratio) < 0.025, "movement stays slowed after transient effect ends")
	await _advance(enemy, 96)
	_check(enemy.slow_timer <= 0.0 and _horizontal_speed(enemy) > steady_speed * 0.95, "cold ink eventually expires and restores movement")
	var before: float = enemy.health
	enemy.take_damage(0.0, Vector3.ZERO, enemy.aim_point())
	enemy.take_damage(-20.0, Vector3.ZERO, enemy.aim_point())
	_check(is_equal_approx(enemy.health, before) and enemy.impact_slow_timer == 0.0, "zero and negative damage do not impair movement")
	# Explicit critical stagger ends first; the impact tail must still be present.
	enemy.take_damage(1.0, Vector3.ZERO, enemy.aim_point(), true, 0.0, 0.0)
	await _advance(enemy, 12)
	_check(enemy.stagger_timer <= 0.0 and enemy.impact_slow_timer > 0.05 and _horizontal_speed(enemy) < steady_speed * 0.9, "movement remains impaired after critical stagger finishes")
	await _advance(enemy, 24)
	# Airborne vertical velocity is gravity-driven, independent of hit slowdown.
	enemy.position.y += 3.0
	enemy.velocity = Vector3(0, 5, -enemy.speed)
	enemy.move_and_slide()
	enemy.take_damage(1.0, Vector3.ZERO, enemy.aim_point())
	var vertical_before: float = enemy.velocity.y
	await _advance(enemy, 1)
	_check(absf(enemy.velocity.y - (vertical_before - 22.0 * DT)) < 0.03, "impact movement factor does not scale vertical gravity velocity")
	enemy.free()
	await physics_frame
	print("[pacing] refresh / armor / cold-ink precedence / nonpositive damage / gravity checked")

func _enemy(id: String) -> Node3D:
	var enemy: Node3D = load("res://scenes/enemy.tscn").instantiate()
	enemy.setup(id, 4, false)
	enemy.position = ORIGIN + Vector3.UP * 0.03
	_world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.audio.set_process(false)
	enemy.complete_spawn_visual()
	enemy.state = "chase"
	enemy.player = _player
	enemy.max_health = 100000.0
	enemy.health = 100000.0
	enemy.volley_timer = 999.0
	return enemy

func _reset(enemy: Node3D) -> void:
	enemy.position = ORIGIN + Vector3.UP * 0.03
	enemy.velocity = Vector3.ZERO
	enemy.impulse = Vector3.ZERO
	enemy.slow_factor = 0.0
	enemy.slow_timer = 0.0
	enemy.impact_slow_timer = 0.0
	enemy.impact_slow_factor = 0.0
	enemy.stagger_timer = 0.0
	enemy.time_alive = 0.0
	enemy.volley_timer = 999.0
	enemy.state = "chase"

func _advance(enemy: Node3D, frames: int) -> float:
	var distance := 0.0
	for frame in frames:
		await physics_frame
		var previous: Vector3 = enemy.global_position
		enemy._physics_process(DT)
		var offset: Vector3 = enemy.global_position - previous
		distance += Vector2(offset.x, offset.z).length()
	return distance

func _horizontal_speed(enemy: Node3D) -> float:
	return Vector2(enemy.velocity.x, enemy.velocity.z).length()
