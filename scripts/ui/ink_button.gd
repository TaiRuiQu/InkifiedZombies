class_name InkButton
extends Control

signal pressed

var text := "按钮"
var accent := UITheme.CINNABAR
var enabled := true:
	set(value):
		enabled = value
		if is_node_ready():
			_update_enabled()

var _hover := 0.0
var _press := 0.0
var _seed := 0
var _hover_tween: Tween
var _press_tween: Tween
var _activation_cooldown := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_seed = hash(text)
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(230, 58)
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	focus_entered.connect(_on_enter)
	focus_exited.connect(_on_exit)
	_update_enabled()


func _update_enabled() -> void:
	focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	if not enabled:
		if is_instance_valid(_hover_tween):
			_hover_tween.kill()
		if is_instance_valid(_press_tween):
			_press_tween.kill()
		if has_focus():
			release_focus()
		_hover = 0.0
		_press = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_activation_cooldown = maxf(_activation_cooldown - delta, 0.0)


func _on_enter() -> void:
	if not enabled:
		return
	if _hover < 0.1:
		Sfx.play("hover", -15.0)
	_animate_hover(1.0)


func _on_exit() -> void:
	_animate_hover(1.0 if has_focus() and enabled else 0.0)


func _animate_hover(target: float) -> void:
	if is_instance_valid(_hover_tween):
		_hover_tween.kill()
	if not is_inside_tree():
		return
	_hover_tween = create_tween()
	_hover_tween.tween_method(_set_hover, _hover, target, 0.16)


func _set_hover(value: float) -> void:
	_hover = value
	queue_redraw()


func _set_press(value: float) -> void:
	_press = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			_activate()
			accept_event()


func _activate() -> void:
	if not enabled or _activation_cooldown > 0.0 or not is_visible_in_tree():
		return
	_activation_cooldown = 0.14
	_press = 1.0
	queue_redraw()
	Sfx.play("click", -5.0)
	if is_instance_valid(_press_tween):
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_method(_set_press, 1.0, 0.0, 0.2)
	# Build feedback first: an action may synchronously remove this scene.
	pressed.emit()


func _draw() -> void:
	var rect := Rect2(0, 0, size.x, size.y)
	var fill := UITheme.PAPER.lerp(UITheme.PAPER_LIGHT, _hover * 0.8) if enabled else UITheme.PAPER_DARK
	if _press > 0.5:
		fill = fill.darkened(0.06)
	var border := UITheme.INK
	if _hover > 0.4:
		border = UITheme.CINNABAR
	UITheme.rough_rect(self, rect.grow(-2.0), fill, border, 2.4, _seed, 2.2)
	# Accent brush slash on the left.
	draw_line(Vector2(18, 16), Vector2(13, size.y - 16), accent, 4.0, true)
	draw_line(Vector2(21, 18), Vector2(18, size.y - 18), Color(accent.r, accent.g, accent.b, 0.35), 2.0, true)
	# Text.
	var fs := 28
	var sz := UITheme.BRUSH.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2(size.x * 0.5 - sz.x * 0.5, size.y * 0.5 + fs * 0.34)
	draw_string(UITheme.BRUSH, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UITheme.INK if enabled else UITheme.MUTED)
	# Small seal dot.
	draw_circle(Vector2(size.x - 22, 20), 3.5, accent if enabled else UITheme.MUTED)
	if _hover > 0.01:
		var alpha := _hover * 0.12
		draw_rect(rect.grow(-5.0), Color(UITheme.CINNABAR.r, UITheme.CINNABAR.g, UITheme.CINNABAR.b, alpha))
	if has_focus():
		draw_rect(rect.grow(-7.0), Color(UITheme.CINNABAR, 0.7), false, 1.5)
