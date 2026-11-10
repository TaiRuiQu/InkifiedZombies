extends SceneTree

## Real-scene, headless UI/state audit. Uses the production button signals and
## input handlers; it never rewrites the run controller or normal player saves.
class ErrorCollector extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == 1:
			return
		_mutex.lock()
		errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		_mutex.unlock()

var _logger := ErrorCollector.new()
var _main: Node3D
var _failures: Array[String] = []
var _checks := 0
var _finished := false
var _original_settings: Dictionary = {}
var _original_bindings: Dictionary = {}
var _original_path := ""

func _initialize() -> void:
	OS.add_logger(_logger)
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	print("[interaction] %s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)

func _run() -> void:
	await process_frame
	var game = root.get_node("Game")
	var settings = root.get_node("Settings")
	game._test_profile = true
	game.auto_start = false
	game.selected_map = "courtyard"
	game.difficulty = "standard"
	game.endless = false
	_original_settings = settings.values.duplicate(true)
	_original_path = settings.save_path
	settings.save_path = "user://interaction_test_settings.cfg"
	for action: String in settings.ACTIONS:
		_original_bindings[action] = InputMap.action_get_events(action).duplicate(true)
	create_timer(35.0).timeout.connect(_watchdog)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	if _main.title == null:
		_check(false, "main scene UI constructed")
		await _finish()
		return
	_check(_main.title.visible and not _main.player.controls_enabled, "title owns input before run")
	for property: String in _main.title._selectors:
		var option: OptionButton = _main.title._selectors[property]
		option.show_popup()
		await process_frame
		var popup := option.get_popup()
		_check(popup.visible and option.has_meta("ink_dropdown"), "title %s opens styled popup" % property)
		_check(popup.get_theme_stylebox("panel") is StyleBoxTexture, "%s popup uses paper texture panel" % property)
		_check(popup.get_theme_color("font_color") == UITheme.INK, "%s popup uses ink text" % property)
		_check(popup.get_theme_icon("radio_checked").resource_path.ends_with("choice_seal.svg"), "%s popup uses cinnabar seal selection" % property)
		option._prepare_popup()
		_check(popup.is_item_checked(option.selected), "%s popup marks current selection" % property)
		popup.hide()
	var old_sun: Color = _main.map.get_node("Sun").light_color
	var old_fog := _fog_color(_main.map)
	var old_map_id: int = _main.map.get_instance_id()
	var map_option: OptionButton = _main.title._selectors.selected_map
	_choose(map_option, 1)
	await _settle_preview()
	_check(game.selected_map == "bamboo_night" and _main.map.map_id == "bamboo_night", "map selection replaces live title preview")
	_check(_main.map.get_instance_id() != old_map_id, "preview is a newly configured arena")
	_check(_main.map.get_node("Sun").light_color != old_sun and _fog_color(_main.map) != old_fog, "night preview changes real lighting and fog")
	_check(_main.title._preview_title.text == _main.map.definition.display_name, "preview caption follows selected map")
	_check(_main._title_cam.current and not _main.player.controls_enabled, "changing preview preserves title camera and controls")
	_choose(map_option, 0)
	_choose(map_option, 1)
	_choose(map_option, 0)
	await _settle_preview()
	_check(game.selected_map == "courtyard" and _main.map.map_id == "courtyard", "rapid changes resolve to the last selected map")
	_choose(map_option, 1)
	await _settle_preview()
	var chosen_arena_id: int = _main.map.get_instance_id()
	_main.title.settings_requested.emit()
	_check(_main.settings_screen.visible and not _main.title.visible, "title settings button opens settings")
	for control: Control in _main.settings_screen._controls.values():
		if control is OptionButton:
			control.show_popup()
			await process_frame
			_check(control.get_popup().get_theme_stylebox("panel") is StyleBoxTexture, "settings dropdown shares actual popup theme")
			control.get_popup().hide()
	_main.settings_screen._tabs.current_tab = 1
	var music_slider: HSlider = _main.settings_screen._controls.music_volume
	music_slider.value = 0.0
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music slider mutes music independently")
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Ink")), "muting music preserves gameplay effects")
	music_slider.value = 0.65
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music slider restores music immediately")
	_main.settings_screen._tabs.current_tab = 0
	var fov_slider: HSlider = _main.settings_screen._controls.fov
	fov_slider.value = 92.0
	_check(absf(float(settings.get_value("fov")) - 92.0) < 0.01, "FOV slider applies without closing settings")
	var quality: OptionButton = _main.settings_screen._controls.quality
	_choose(quality, 0)
	_check(not _main.map.get_node("Sun").shadow_enabled, "low quality option disables map shadows immediately")
	_choose(quality, 2)
	_check(_main.map.get_node("Sun").shadow_enabled, "high quality restores map shadows")
	_main.settings_screen._tabs.current_tab = 2
	var reload_button: Button = _main.settings_screen._binding_buttons.reload
	reload_button.pressed.emit()
	_check(_main.settings_screen._binding_action == "reload", "binding button enters key capture")
	var conflict: InputEvent = InputMap.action_get_events("move_forward")[0].duplicate()
	if conflict is InputEventKey:
		conflict.pressed = true
	elif conflict is InputEventMouseButton:
		conflict.pressed = true
	_main.settings_screen._input(conflict)
	_check(_main.settings_screen._binding_action == "reload", "conflicting binding stays in capture with a message")
	_main.settings_screen._input(_key(KEY_ESCAPE))
	_check(_main.settings_screen.visible and _main.settings_screen._binding_action.is_empty(), "ESC cancels binding without closing settings")
	var free_code := _unused_key()
	reload_button.pressed.emit()
	_main.settings_screen._input(_key(free_code))
	_check(_main.settings_screen._binding_action.is_empty(), "available key completes binding")
	_check((InputMap.action_get_events("reload")[0] as InputEventKey).physical_keycode == free_code, "new binding reaches gameplay InputMap")
	settings.save()
	settings.load_preferences()
	_check((InputMap.action_get_events("reload")[0] as InputEventKey).physical_keycode == free_code, "saved binding survives reload")
	_main.settings_screen._input(_key(KEY_ESCAPE))
	_check(_main.title.visible and not _main.settings_screen.visible, "ESC from settings restores title")
	_main.title.multiplayer_requested.emit()
	_check(_main.multiplayer_screen.visible and not _main.title.visible, "multiplayer button opens lobby")
	_main.multiplayer_screen._leave()
	_main.multiplayer_screen.close()
	_check(_main.title.visible and not root.get_node("NET").active, "leaving lobby restores single-player title state")
	_main.title.start_requested.emit()
	_check(_main._started and _main.player.controls_enabled and not _main.title.visible, "single-player start enables gameplay and hides title")
	_check(_main.map.get_instance_id() == chosen_arena_id and _main.map.map_id == "bamboo_night", "run uses exactly the map shown by the preview")
	_main.director.frozen = true
	_main._open_pause()
	_main.pause.settings_requested.emit()
	_check(paused and _main.settings_screen.visible and not _main.pause.visible, "pause settings keeps simulation stopped")
	_main.settings_screen._input(_key(KEY_ESCAPE))
	_check(paused and _main.pause.visible and not _main.player.controls_enabled, "closing pause settings does not resume combat")
	_main.pause.resume_requested.emit()
	_check(not paused and _main.player.controls_enabled, "resume button restores input and simulation")
	_main.director.stop()
	_main.player.health = _main.player.max_health * 0.3
	_main._on_wave_cleared(1)
	await _wait_for_upgrade()
	_check(game.state == game.State.UPGRADE and _main.upgrades.visible and paused, "clear wave enters real upgrade state")
	var before_skip: float = _main.player.health
	var max_health: float = _main.player.max_health
	_main.upgrades._skip.pressed.emit()
	_main.upgrades._skip.pressed.emit()
	await _wait_for_wave(2)
	_main.director.frozen = true
	_check(int(_main.player.upgrade_counts.get("skip_heal", 0)) == 1, "double click cannot apply skip twice")
	_check(absf(_main.player.health - minf(max_health, before_skip + max_health * 0.3)) < 0.01, "skip restores exactly thirty percent health")
	_check(not paused and not _main.upgrades.visible and game.wave == 2, "skip advances into next wave")
	_main.player.mods.revives = 0
	_main.player.invuln_time = 0.0
	_main.player.take_damage(_main.player.max_health * 100)
	await _wait_for_result()
	_check(_main.player.dead and game.state == game.State.DEAD and _main.game_over.visible, "lethal damage opens result screen")
	var old_scene := _main.get_instance_id()
	_main.game_over._restart_button.pressed.emit()
	_main = null
	await _wait_for_scene(old_scene)
	_main = current_scene
	await _wait_for_started()
	_check(_main._started and not _main.player.dead and game.wave == 1 and not paused, "result restart produces a fresh playable run")
	_main._return_to_title()
	_main = null
	await process_frame
	await process_frame
	_check(is_instance_valid(current_scene) and current_scene.title.visible, "return to title after restarted run")
	_check(_logger.errors.is_empty(), "all UI actions produced no engine/script errors")
	await _finish()

func _choose(option: OptionButton, index: int) -> void:
	# PopupMenu's production index_pressed handler updates OptionButton.selection and
	# emits item_selected; do not bypass it by calling controller private setters.
	option.show_popup()
	option.get_popup().index_pressed.emit(index)
	option.get_popup().hide()

func _settle_preview() -> void:
	await process_frame
	await process_frame

func _fog_color(arena: Node3D) -> Color:
	for child: Node in arena.get_children():
		if child is WorldEnvironment:
			return child.environment.fog_light_color
	return Color.TRANSPARENT

func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event

func _unused_key() -> int:
	var settings = root.get_node("Settings")
	for code in range(KEY_A, KEY_Z + 1):
		var available := true
		for action: String in settings.ACTIONS:
			for event: InputEvent in InputMap.action_get_events(action):
				if event is InputEventKey and (event.physical_keycode == code or event.keycode == code):
					available = false
		if available:
			return code
	return KEY_BRACKETLEFT

func _wait_for_upgrade() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(_main.upgrades) and _main.upgrades.visible:
			return
	_check(false, "upgrade screen opened before timeout")

func _wait_for_wave(target: int) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if root.get_node("Game").wave == target and not paused:
			return
	_check(false, "next wave started before timeout")

func _wait_for_result() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(_main.game_over) and _main.game_over.visible:
			return
	_check(false, "result screen opened before timeout")

func _wait_for_scene(old_id: int) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != old_id:
			return
	_check(false, "scene reload finished before timeout")

func _wait_for_started() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _main._started:
			return
	_check(false, "restarted run began before timeout")

func _watchdog() -> void:
	if _finished:
		return
	_failures.append("35-second watchdog expired")
	_finish.call_deferred()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	if is_instance_valid(current_scene):
		var scene := current_scene
		current_scene = null
		scene.free()
	_main = null
	root.get_node("NET").leave()
	var settings = root.get_node("Settings")
	settings._save_timer.stop()
	settings.values = _original_settings
	for action: String in _original_bindings:
		InputMap.action_erase_events(action)
		for event: InputEvent in _original_bindings[action]:
			InputMap.action_add_event(action, event)
	settings.save_path = _original_path
	settings.apply_all()
	root.get_node("Sfx").shutdown()
	await create_timer(0.15).timeout
	if not _logger.errors.is_empty():
		print("[interaction] ENGINE ERRORS: ", _logger.errors)
	print("[interaction] RESULT checks=%d errors=%d failures=%d" % [_checks, _logger.errors.size(), _failures.size()])
	OS.remove_logger(_logger)
	quit(0 if _logger.errors.is_empty() and _failures.is_empty() else 1)
