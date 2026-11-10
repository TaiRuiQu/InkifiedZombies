extends Node

## User preferences and input bindings. Gameplay reads this service; menu controls
## never reach into player internals. All settings survive a scene reload.
signal changed(key: String, value: Variant)
signal bindings_changed
signal save_failed(error: Error)

var save_path := "user://settings.cfg"
const DEFAULTS := {
	"master_volume": 0.8, "sfx_volume": 0.8, "ambient_volume": 0.65, "music_volume": 0.65,
	"mouse_sensitivity": 1.0, "invert_y": false, "fov": 78.0,
	"window_mode": 0, "resolution": 1, "vsync": true, "fps_limit": 120,
	"quality": 1, "camera_shake": true, "damage_flash": true,
	"damage_numbers": true, "crosshair_scale": 1.0,
}
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const ACTIONS := {
	"move_forward": "向前", "move_back": "后退", "move_left": "左移", "move_right": "右移",
	"jump": "跳跃", "sprint": "冲刺", "crouch": "蹲伏", "fire": "射击", "aim": "机瞄",
	"reload": "装填", "melee": "近战", "skill": "墨爆", "dash": "疾风步", "grenade": "火符",
	"swap": "切换武器", "weapon_1": "武器 1", "weapon_2": "武器 2", "weapon_3": "武器 3",
	"weapon_4": "武器 4", "weapon_5": "武器 5", "weapon_6": "武器 6",
}
const LIMITS := {
	"master_volume": Vector2(0, 1), "sfx_volume": Vector2(0, 1), "ambient_volume": Vector2(0, 1), "music_volume": Vector2(0, 1),
	"mouse_sensitivity": Vector2(0.15, 3.0), "fov": Vector2(65, 105),
	"window_mode": Vector2(0, 2), "resolution": Vector2(0, 3), "quality": Vector2(0, 2),
	"crosshair_scale": Vector2(0.6, 1.8),
}

var values: Dictionary = DEFAULTS.duplicate(true)
var _default_bindings: Dictionary = {}
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--smoke") or argument.begins_with("--role=") or argument in ["--beta-test", "--autoshot", "--gallery"]:
			save_path = "user://test_settings.cfg"
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.35
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	for action: String in ACTIONS:
		_default_bindings[action] = InputMap.action_get_events(action).duplicate()
	load_preferences()
	apply_all()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Unknown preference: " + key)
		return
	var checked: Variant = _validated(key, value)
	if values[key] == checked:
		return
	values[key] = checked
	_apply(key)
	changed.emit(key, checked)
	_save_timer.start()


func _validated(key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	if typeof(value) != typeof(fallback) and not (value is float or value is int):
		return fallback
	if fallback is bool:
		return bool(value)
	if key == "fps_limit":
		return int(value) if int(value) in [0, 60, 90, 120, 144, 165, 240] else 120
	if LIMITS.has(key):
		var bounds: Vector2 = LIMITS[key]
		var number: float = float(value)
		if not is_finite(number):
			return fallback
		number = clampf(number, bounds.x, bounds.y)
		return int(number) if fallback is int else number
	return value


func apply_all() -> void:
	apply_audio()
	_apply_display()
	_apply_quality()
	Engine.max_fps = int(values.fps_limit)


func _apply(key: String) -> void:
	if key.ends_with("_volume"):
		apply_audio()
	elif key in ["window_mode", "resolution", "vsync"]:
		_apply_display()
	elif key == "fps_limit":
		Engine.max_fps = int(values.fps_limit)
	elif key == "quality":
		_apply_quality()
		if is_instance_valid(get_tree().current_scene):
			apply_scene(get_tree().current_scene)


func apply_audio() -> void:
	for bus: String in ["Ink", "Ambient", "Music"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "Master")
	_set_bus("Master", float(values.master_volume))
	_set_bus("Ink", float(values.sfx_volume))
	_set_bus("Ambient", float(values.ambient_volume))
	_set_bus("Music", float(values.music_volume))


func _set_bus(bus: String, volume: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = int(values.window_mode)
	if mode == 0:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		var screen: int = DisplayServer.window_get_current_screen()
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
		var target: Vector2i = RESOLUTIONS[int(values.resolution)]
		target = Vector2i(mini(target.x, usable.size.x), mini(target.y, usable.size.y))
		DisplayServer.window_set_size(target)
		DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)
	elif mode == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values.vsync) else DisplayServer.VSYNC_DISABLED)


func _apply_quality() -> void:
	var viewport: Viewport = get_viewport()
	var quality: int = int(values.quality)
	viewport.scaling_3d_scale = [0.75, 1.0, 1.0][quality]
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.positional_shadow_atlas_size = [1024, 2048, 4096][quality]


func apply_scene(node: Node) -> void:
	if node is Light3D:
		if not node.has_meta("settings_default_shadow"):
			node.set_meta("settings_default_shadow", node.shadow_enabled)
		node.shadow_enabled = bool(node.get_meta("settings_default_shadow")) and int(values.quality) > 0
	if node is WorldEnvironment and node.environment:
		node.environment.glow_enabled = int(values.quality) > 0
	for child: Node in node.get_children():
		apply_scene(child)


func binding_text(action: String) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		return "未绑定"
	var event: InputEvent = events[0]
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "鼠标左键"
			MOUSE_BUTTON_RIGHT: return "鼠标右键"
			MOUSE_BUTTON_MIDDLE: return "鼠标中键"
			MOUSE_BUTTON_XBUTTON1: return "鼠标侧键 1"
			MOUSE_BUTTON_XBUTTON2: return "鼠标侧键 2"
	return event.as_text()


## Returns a localized validation error, or an empty string on success.
func rebind(action: String, event: InputEvent) -> String:
	if not ACTIONS.has(action):
		return "未知操作"
	var normalized: InputEvent
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code in [KEY_ESCAPE, KEY_ALT, KEY_META, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12]:
			return "ESC、Alt 与功能键为系统保留键"
		if event.alt_pressed or event.meta_pressed or (event.ctrl_pressed and code != KEY_CTRL) or (event.shift_pressed and code != KEY_SHIFT):
			return "请使用单个按键，不支持组合键"
		var key := InputEventKey.new()
		key.physical_keycode = code
		normalized = key
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return "滚轮用于切换武器，请使用其他按键"
		var mouse := InputEventMouseButton.new()
		mouse.button_index = event.button_index
		normalized = mouse
	else:
		return "请按键盘按键或鼠标按键"
	for other: String in ACTIONS:
		if other == action:
			continue
		for bound: InputEvent in InputMap.action_get_events(other):
			if _same_binding(normalized, bound):
				return "已用于「%s」，请先更换该操作的按键" % ACTIONS[other]
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, normalized)
	bindings_changed.emit()
	_save_timer.start()
	return ""


func _same_binding(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ac: int = a.physical_keycode if a.physical_keycode != 0 else a.keycode
		var bc: int = b.physical_keycode if b.physical_keycode != 0 else b.keycode
		return ac == bc
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false


func reset_defaults() -> void:
	values = DEFAULTS.duplicate(true)
	for action: String in _default_bindings:
		InputMap.action_erase_events(action)
		for event: InputEvent in _default_bindings[action]:
			InputMap.action_add_event(action, event)
	apply_all()
	if is_instance_valid(get_tree().current_scene):
		apply_scene(get_tree().current_scene)
	for key: String in values:
		changed.emit(key, values[key])
	bindings_changed.emit()
	save()


func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in values:
		cfg.set_value("settings", key, values[key])
	for action: String in ACTIONS:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.is_empty():
			continue
		var event: InputEvent = events[0]
		if event is InputEventKey:
			cfg.set_value("bindings", action, {"key": event.physical_keycode if event.physical_keycode != 0 else event.keycode})
		elif event is InputEventMouseButton:
			cfg.set_value("bindings", action, {"mouse": event.button_index})
	# Write beside the destination, then rename over it. An interrupted write
	# leaves the previous valid preference file available for the next launch.
	var temporary_path: String = save_path + ".tmp"
	var error: Error = cfg.save(temporary_path)
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(save_path))
	if error != OK:
		push_warning("Could not save preferences: " + error_string(error))
		save_failed.emit(error)


func load_preferences() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	for key: String in DEFAULTS:
		values[key] = _validated(key, cfg.get_value("settings", key, DEFAULTS[key]))
	# Validate the complete candidate map before changing InputMap. A damaged
	# record must never silently leave two gameplay actions on the same key.
	var candidates: Dictionary = {}
	for action: String in ACTIONS:
		var defaults: Array = _default_bindings.get(action, [])
		if not defaults.is_empty():
			candidates[action] = defaults[0]
		var record: Variant = cfg.get_value("bindings", action, {})
		if not record is Dictionary:
			continue
		if record.has("key") and int(record.key) > 0 and not int(record.key) in [KEY_ESCAPE, KEY_ALT, KEY_META] and not (int(record.key) >= KEY_F1 and int(record.key) <= KEY_F12):
			var key := InputEventKey.new()
			key.physical_keycode = int(record.key)
			candidates[action] = key
		elif record.has("mouse") and int(record.mouse) in [1, 2, 3, 8, 9]:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(record.mouse)
			candidates[action] = mouse
	var seen: Array[InputEvent] = []
	for action: String in candidates:
		var event: InputEvent = candidates[action]
		for prior: InputEvent in seen:
			if _same_binding(event, prior):
				push_warning("Conflicting saved bindings; using default controls.")
				return
		seen.append(event)
	for action: String in candidates:
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, candidates[action])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
