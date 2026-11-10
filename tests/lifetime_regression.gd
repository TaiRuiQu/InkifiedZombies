extends SceneTree

## Real timer/scene lifetime regression. Run headless with --script this file.
## Actual decals carry a 28-second lease, so this test deliberately waits for it.
class ErrorCollector extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		# Logger warning = 1. Errors and script/shader errors are failures.
		if error_type == 1:
			return
		_mutex.lock()
		errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		_mutex.unlock()

var _logger := ErrorCollector.new()
var _failures: Array[String] = []
var _references: Array[WeakRef] = []
var _main: Node3D
var _vfx: Script
var _finished := false
var _cycles := 0
var _fixture_start := 0
var _settings_path := ""

func _initialize() -> void:
	OS.add_logger(_logger)
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	print("[lifetime] %s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)

func _watchdog() -> void:
	if _finished:
		return
	_failures.append("45-second watchdog expired")
	_finish.call_deferred()

func _run() -> void:
	await process_frame
	_vfx = load("res://scripts/fx/vfx.gd")
	var game = root.get_node("Game")
	var settings = root.get_node("Settings")
	game._test_profile = true
	_settings_path = settings.save_path
	settings.save_path = "user://lifetime_test_settings.cfg"
	create_timer(45.0).timeout.connect(_watchdog)
	_fixture_start = Time.get_ticks_msec()
	var stage := Node3D.new()
	stage.name = "LifetimeFixture"
	root.add_child(stage)
	_references.append(weakref(stage))
	for index in 96:
		var node := Node3D.new()
		node.name = "EarlyExpiry%d" % index
		stage.add_child(node)
		_references.append(weakref(node))
		_vfx._free_after(node, 0.01 + float(index % 10) * 0.01)
		# Exercise both caller-evicted children and parent-owned early frees.
		if index % 2 == 0:
			node.free()
	for index in 24:
		var decal: Node3D = _vfx.decal(stage, Vector3(index * 0.02, 0, 0), Vector3.UP,
			0.15, Color(0.1, 0.08, 0.06, 0.7), index % 3)
		_references.append(weakref(decal))
		# A second short lease matches the wall-decal ring's early eviction case.
		_vfx._free_after(decal, 0.025 + float(index % 5) * 0.01)
		if index % 3 == 0:
			decal.free()
	stage.free()
	await create_timer(0.2).timeout
	_check(_all_released(), "96 leased nodes and 24 real decals released before expiry")
	_check(_logger.errors.is_empty(), "short expiry timers do not call freed captures")
	for iteration in 5:
		if iteration == 0:
			var scene: PackedScene = load("res://scenes/main.tscn")
			if scene == null:
				_check(false, "main scene can load")
				await _finish()
				return
			_main = scene.instantiate()
			root.add_child(_main)
			current_scene = _main
		else:
			_main = current_scene
		await process_frame
		_check(_main.title != null and _main.title.visible, "cycle %d starts on title" % (iteration + 1))
		if _main.title == null:
			await _finish()
			return
		_main._open_settings("title")
		_main.settings_screen.close()
		_main._open_multiplayer()
		_main.multiplayer_screen._leave()
		_main.multiplayer_screen.close()
		_main.start_run()
		_main.director.frozen = true
		_main._open_pause()
		_main._open_settings("pause")
		_main.settings_screen.close()
		_check(_main.pause.visible and paused, "cycle %d settings returns to pause" % (iteration + 1))
		var old_scene_id := _main.get_instance_id()
		_references.append(weakref(_main))
		_main._return_to_title()
		_main = null
		await _wait_for_scene(old_scene_id)
		_cycles += 1
		_check(_logger.errors.is_empty(), "cycle %d reload has no engine/script capture error" % (iteration + 1))
	if is_instance_valid(current_scene):
		var final_scene := current_scene
		current_scene = null
		final_scene.free()
	_main = null
	# Await the real VFX.decal default lease, not merely the added short leases.
	var wait_seconds := maxf(0.0, 28.3 - float(Time.get_ticks_msec() - _fixture_start) / 1000.0)
	if wait_seconds > 0.0:
		await create_timer(wait_seconds).timeout
	await process_frame
	_check(_all_released(), "all five old scenes and all early-freed nodes remain released")
	_check(_logger.errors.is_empty(), "all original 28-second decal timers fired without errors")
	await _finish()

func _wait_for_scene(old_id: int) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != old_id:
			await process_frame
			return
	_check(false, "scene reload completed before deadline")

func _all_released() -> bool:
	for reference: WeakRef in _references:
		if reference.get_ref() != null:
			return false
	return true

func _finish() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	var net = root.get_node("NET")
	net.leave()
	var settings = root.get_node("Settings")
	settings._save_timer.stop()
	settings.save_path = _settings_path
	var sound = root.get_node("Sfx")
	sound.shutdown()
	await create_timer(0.15).timeout
	if not _logger.errors.is_empty():
		print("[lifetime] ENGINE ERRORS: ", _logger.errors)
	print("[lifetime] RESULT cycles=%d freed_references=%d errors=%d failures=%d" % [_cycles, _references.size(), _logger.errors.size(), _failures.size()])
	OS.remove_logger(_logger)
	quit(0 if _logger.errors.is_empty() and _failures.is_empty() else 1)
