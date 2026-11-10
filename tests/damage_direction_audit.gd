extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	print("[damage-directions] %s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures += 1


func _run() -> void:
	var observer := Node3D.new()
	root.add_child(observer)
	var camera := Camera3D.new()
	observer.add_child(camera)
	var indicator: Control = load("res://scripts/ui/damage_indicator.gd").new()
	root.add_child(indicator)
	indicator.bind(observer, camera)
	_check(indicator.direction_for(Vector3(0, 0, -10)).is_equal_approx(Vector2.UP), "front source points up")
	_check(indicator.direction_for(Vector3(10, 0, 0)).is_equal_approx(Vector2.RIGHT), "right source points right")
	_check(indicator.direction_for(Vector3(0, 0, 10)).is_equal_approx(Vector2.DOWN), "rear source points down")
	_check(indicator.direction_for(Vector3(-10, 0, 0)).is_equal_approx(Vector2.LEFT), "left source points left")
	camera.rotation.y = PI * 0.5
	_check(indicator.direction_for(Vector3(0, 0, -10)).is_equal_approx(Vector2.RIGHT), "turning left moves old front source to right")
	camera.rotation = Vector3(0.7, 0, 0.1)
	_check(indicator.direction_for(Vector3(0, 0, -10)).is_equal_approx(Vector2.UP), "camera pitch and roll do not rotate azimuth")
	camera.rotation = Vector3.ZERO
	_check(indicator.direction_for(Vector3.INF) == Vector2.ZERO, "unknown source is omnidirectional")
	indicator.push_hit(10.0, Vector3(0, 0, -10), false)
	indicator.push_hit(5.0, Vector3(1, 0, -10), false)
	_check(indicator.entries.size() == 1 and float(indicator.entries[0].amount) == 15.0, "same direction merges its damage")
	indicator.push_hit(7.0, Vector3(0, 0, -10), true)
	_check(indicator.entries.size() == 2, "shield and blood warnings stay distinguishable")
	indicator.push_hit(8.0, Vector3(10, 0, 0), false)
	indicator.push_hit(8.0, Vector3(0, 0, 10), false)
	indicator.tick(0.1)
	indicator.push_hit(8.0, Vector3(-10, 0, 0), false)
	_check(indicator.entries.size() == 4, "at most four incoming directions are retained")
	indicator.tick(2.4)
	_check(indicator.entries.is_empty(), "direction warnings expire")
	indicator.push_hit(9.0, Vector3.INF, false)
	_check(indicator.entries.size() == 1 and indicator.direction_for(indicator.entries[0].source) == Vector2.ZERO, "unknown source remains a distinct warning")
	var readout: Control = load("res://scripts/ui/combat_readout.gd").new()
	root.add_child(readout)
	readout.push_feedback(10.0, false, false, false)
	readout.push_feedback(20.0, true, true, true)
	_check(readout.entries.size() == 1 and float(readout.entries[0].amount) == 30.0, "one burst aggregates pellets")
	_check(readout.entries[0].headshot and readout.entries[0].killed, "burst preserves headshot and kill confirmation")
	readout.tick(1.2)
	_check(readout.entries.is_empty(), "combat confirmation expires")
	var player: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(player)
	var director: Node3D = load("res://scripts/waves/wave_director.gd").new()
	root.add_child(director)
	var hud: CanvasLayer = load("res://scripts/ui/hud.gd").new()
	root.add_child(hud)
	hud.bind(player, director)
	var settings: Node = root.get_node("Settings")
	var previous_shake: Variant = settings.values.camera_shake
	var previous_flash: Variant = settings.values.damage_flash
	settings.values.camera_shake = false
	settings.values.damage_flash = false
	player.damage_direction.emit(17.0, Vector3(10, 0, 0), true)
	player.combat_feedback.emit(68.0, true, true, true)
	_check(hud._directions.entries.size() == 1, "HUD receives direction with shake and flash disabled")
	_check(hud._combat.entries.size() == 1 and hud._crosshair.hit_headshot and hud._crosshair.hit_kill, "HUD receives confirmed headshot kill")
	settings.values.camera_shake = previous_shake
	settings.values.damage_flash = previous_flash
	hud.queue_free()
	director.queue_free()
	player.queue_free()
	readout.queue_free()
	indicator.queue_free()
	observer.queue_free()
	await process_frame
	print("[damage-directions] RESULT failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)
