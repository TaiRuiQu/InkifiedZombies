class_name WaveDirector
extends Node3D

signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal boss_spawned(enemy: Enemy)
signal boss_defeated
signal remaining_changed(remaining: int)

const EnemyScene: PackedScene = preload("res://scenes/enemy.tscn")

var player: Node3D
var spawn_points: Array[Vector3] = []

var current_wave := 0
var wave_active := false
var frozen := false
var boss: Enemy

var _queue: Array[String] = []
var _total := 0
var _spawned := 0
var _spawn_timer := 1.0
var _alive_cap := 12
var _boss_wave := false
var _last_reported := -1
var _boss_reported := false
var _rng := RandomNumberGenerator.new()
var _plan: Dictionary = {}
var _pressure_timer := 0.0


func setup(p_player: Node3D, p_spawn_points: Array[Vector3]) -> void:
	player = p_player
	spawn_points = p_spawn_points
	_rng.randomize()


func start_wave(wave: int) -> void:
	current_wave = wave
	Game.wave = wave
	Game.record_wave_reached(wave)
	wave_active = true
	frozen = false
	boss = null
	_boss_reported = false
	_queue.clear()
	_spawned = 0
	_last_reported = -1
	_plan = RunRules.wave_plan(wave, Game.difficulty)
	_boss_wave = bool(_plan.boss)
	_alive_cap = int(_plan.alive_cap)
	_spawn_timer = float(_plan.opening_delay)
	_pressure_timer = 0.0

	var available := EnemyDB.unlocked_for_wave(wave)
	if _boss_wave:
		_spawn_boss()
	_build_queue(available, float(_plan.budget))
	_total = _queue.size() + (1 if _boss_wave else 0)
	wave_started.emit(wave)
	remaining_changed.emit(remaining())
	Sfx.play("wave_start", -3.0)


func _build_queue(available: Array, budget: float) -> void:
	var guard := 0
	while budget > 0.2 and guard < 200:
		guard += 1
		var pick := _pick_type(available)
		var cost := float(EnemyDB.get_type(pick).cost)
		if cost <= 0.0:
			break
		if cost > budget:
			# Try the cheapest available type before giving up.
			var cheapest := _cheapest(available)
			if cheapest.is_empty():
				break
			pick = cheapest
			cost = float(EnemyDB.get_type(pick).cost)
			if cost > budget:
				break
		_queue.append(pick)
		budget -= cost


func _cheapest(available: Array) -> String:
	var best := ""
	var best_cost := 999.0
	for id in available:
		var c := float(EnemyDB.get_type(id).cost)
		if c < best_cost:
			best_cost = c
			best = id
	return best


func _pick_type(available: Array) -> String:
	var total := 0.0
	for id in available:
		total += float(EnemyDB.get_type(id).get("spawn_weight", 1.0))
	var r := _rng.randf() * maxf(total, 0.001)
	for id in available:
		r -= float(EnemyDB.get_type(id).get("spawn_weight", 1.0))
		if r <= 0.0:
			return id
	return available[0]


func _spawn_boss() -> void:
	if boss and is_instance_valid(boss):
		return
	var e: Enemy = EnemyScene.instantiate()
	e.setup("boss", current_wave, false)
	_scale_enemy(e)
	var pos := _far_spawn_point()
	e.position = pos
	_set_entry_route(e, pos)
	add_child(e)
	boss = e
	boss.died.connect(_on_boss_died)
	boss_spawned.emit(boss)
	Sfx.play("boss_spawn", 1.0)


func _on_boss_died(_e: Enemy) -> void:
	if _boss_reported:
		return
	_boss_reported = true
	boss_defeated.emit()


func _physics_process(delta: float) -> void:
	if Coop.is_client():
		return
	if not wave_active or frozen:
		return
	if not is_instance_valid(player):
		return
	if player.get("dead") == true and (not NET.active or not Coop._has_living_actor()):
		return

	var alive := count_alive()
	if alive < _alive_cap and not _queue.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = float(_plan.get("spawn_interval", 0.8)) * _rng.randf_range(0.8, 1.15)
			_spawn_next()
			alive = count_alive()

	var rem := _queue.size() + alive
	if rem != _last_reported:
		_last_reported = rem
		remaining_changed.emit(rem)

	if _queue.is_empty() and alive <= 0:
		_complete_wave()


func _spawn_next() -> void:
	if _queue.is_empty():
		return
	var id: String = _queue.pop_front()
	var e: Enemy = EnemyScene.instantiate()
	var elite := current_wave >= 7 and _rng.randf() < clampf(float(current_wave - 6) * 0.035, 0.0, 0.22)
	e.setup(id, current_wave, elite)
	_scale_enemy(e)
	var pos := _spawn_point_away_from_player()
	e.position = pos
	_set_entry_route(e, pos)
	add_child(e)
	_spawned += 1


func _spawn_point_away_from_player() -> Vector3:
	if spawn_points.is_empty():
		var angle := TAU * float(_rng.randi_range(0, MapBuilder.GATE_COUNT - 1)) / MapBuilder.GATE_COUNT
		return Vector3(cos(angle), 0, sin(angle)) * MapBuilder.SPAWN_RADIUS + Vector3.UP * 0.05
	var best := spawn_points[_rng.randi() % spawn_points.size()]
	var best_d := -1.0
	for i in 6:
		var p: Vector3 = spawn_points[_rng.randi() % spawn_points.size()]
		var d := 999.0
		if is_instance_valid(player):
			d = p.distance_to(player.global_position)
		if d > best_d:
			best_d = d
			best = p
		if d > 14.0:
			break
	return best + Vector3(_rng.randf_range(-1.1, 1.1), 0.05, _rng.randf_range(-1.1, 1.1))


func _far_spawn_point() -> Vector3:
	var best := Vector3(0, 0.05, -MapBuilder.SPAWN_RADIUS)
	var best_d := -1.0
	for p in spawn_points:
		var d := 999.0
		if is_instance_valid(player):
			d = p.distance_to(player.global_position)
		if d > best_d:
			best_d = d
			best = p
	return best


func _set_entry_route(enemy: Enemy, pos: Vector3) -> void:
	if Vector2(pos.x, pos.z).length() <= MapBuilder.ARENA_RADIUS:
		return
	var step := TAU / MapBuilder.GATE_COUNT
	var angle := roundf(atan2(pos.z, pos.x) / step) * step
	enemy.entry_target = Vector3(cos(angle), 0, sin(angle)) * (MapBuilder.GATE_RADIUS - 2.5)


func _scale_enemy(enemy: Enemy) -> void:
	enemy.max_health *= float(RunRules.difficulty(Game.difficulty).enemy_health)
	if NET.active:
		enemy.max_health *= 1.0 + maxf(float(NET.peers.size() - 1), 0.0) * 0.55
	enemy.health = enemy.max_health


func _complete_wave() -> void:
	if not wave_active:
		return
	wave_active = false
	remaining_changed.emit(0)
	wave_cleared.emit(current_wave)


func count_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.get("dead") != true:
			n += 1
	return n


func remaining() -> int:
	if Coop.is_client():
		return int(get_meta("network_remaining", 0))
	return _queue.size() + count_alive()


func total_enemies() -> int:
	if Coop.is_client():
		return int(get_meta("network_total", 0))
	return _total


func boss_ratio() -> float:
	if boss and is_instance_valid(boss) and not boss.dead:
		return boss.health_ratio()
	return -1.0


func stop() -> void:
	wave_active = false
	_queue.clear()


func debug_spawn(id: String, pos: Vector3, elite: bool = false) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.setup(id, maxi(current_wave, 1), elite)
	e.position = pos
	add_child(e)
	return e
