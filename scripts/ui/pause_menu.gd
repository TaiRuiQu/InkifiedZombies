class_name PauseMenu
extends CanvasLayer

signal resume_requested
signal restart_requested
signal title_requested
signal settings_requested

var _root: Control
var _resume_button: InkButton
var _restart_button: InkButton
var _subtitle: Label
var _hint: Label
var _back_button: InkButton
var _panel_tween: Tween


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.025, 0.022, 0.018, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var art := PauseArt.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(art)

	var title := UITheme.brush("止", 108, UITheme.INK)
	title.position = Vector2(0, 292)
	title.size = Vector2(1600, 130)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)
	var sub := UITheme.body("长 夜 暂 歇", 15, UITheme.MUTED)
	_subtitle = sub
	sub.position = Vector2(0, 412)
	sub.size = Vector2(1600, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(sub)

	var resume := InkButton.new()
	resume.text = "继 续"
	resume.position = Vector2(650, 468)
	resume.size = Vector2(300, 56)
	resume.custom_minimum_size = Vector2(300, 56)
	resume.pressed.connect(_request_resume)
	_root.add_child(resume)
	_resume_button = resume

	var settings := InkButton.new()
	settings.text = "调 墨 · 设 置"
	settings.position = Vector2(650, 534)
	settings.size = Vector2(300, 50)
	settings.custom_minimum_size = Vector2(300, 50)
	settings.accent = UITheme.INDIGO
	settings.pressed.connect(_request_settings)
	_root.add_child(settings)

	var restart := InkButton.new()
	_restart_button = restart
	restart.text = "重 开 此 局"
	restart.position = Vector2(650, 596)
	restart.size = Vector2(300, 56)
	restart.custom_minimum_size = Vector2(300, 56)
	restart.accent = UITheme.INDIGO
	restart.pressed.connect(_request_restart)
	_root.add_child(restart)

	var back := InkButton.new()
	_back_button = back
	back.text = "归 返"
	back.position = Vector2(650, 662)
	back.size = Vector2(300, 56)
	back.custom_minimum_size = Vector2(300, 56)
	back.accent = UITheme.INK_SOFT
	back.pressed.connect(_request_title)
	_root.add_child(back)

	var hint := UITheme.body("ESC 继续 · 墨未干，路未尽", 13, UITheme.MUTED)
	_hint = hint
	hint.position = Vector2(0, 746)
	hint.size = Vector2(1600, 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(hint)
	_root.modulate.a = 0.0


func open() -> void:
	visible = true
	var disconnected := Coop.connection_lost
	_resume_button.enabled = not disconnected
	_restart_button.enabled = not disconnected and (not NET.active or NET.is_host)
	_restart_button.text = "等待房主重开" if NET.active and not NET.is_host else "重 开 此 局"
	_resume_button.text = "墨 路 已 断" if disconnected else "继 续"
	_subtitle.text = "墨路已断 · 请归返重新连接" if disconnected else ("同守仍在继续 · 此菜单仅锁定你的操作" if NET.active else "长 夜 暂 歇")
	_hint.text = "归返标题可重新连接好友。" if disconnected else "ESC 继续 · 墨未干，路未尽"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.modulate.a = 0.0
	if is_instance_valid(_panel_tween):
		_panel_tween.kill()
	_panel_tween = _root.create_tween()
	_panel_tween.tween_property(_root, "modulate:a", 1.0, 0.18)
	_focus_default.call_deferred()


func close() -> void:
	visible = false
	if is_instance_valid(_panel_tween):
		_panel_tween.kill()


func _focus_default() -> void:
	if not visible or not is_inside_tree():
		return
	if _resume_button.enabled:
		UITheme.focus_later(_resume_button)
	else:
		UITheme.focus_later(_back_button)


func _request_resume() -> void:
	if visible and _resume_button.enabled:
		resume_requested.emit()


func _request_settings() -> void:
	if visible:
		settings_requested.emit()


func _request_restart() -> void:
	if visible and _restart_button.enabled:
		restart_requested.emit()


func _request_title() -> void:
	if visible:
		title_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		_request_resume()
		get_viewport().set_input_as_handled()


class PauseArt extends Control:
	func _draw() -> void:
		var panel := Rect2(480, 210, 640, 590)
		UITheme.rough_rect(self, Rect2(panel.position + Vector2(8, 10), panel.size),
			Color(0.02, 0.018, 0.015, 0.5), Color(0, 0, 0, 0), 0.0, 91, 4.0)
		UITheme.rough_rect(self, panel, Color(0.925, 0.89, 0.80, 0.96), UITheme.INK, 2.4, 92, 2.2)
		draw_line(Vector2(510, 360), Vector2(1090, 360), Color(0.12, 0.1, 0.08, 0.22), 1.5)
		# Large ink sun wash behind the title.
		draw_circle(Vector2(800, 352), 120.0, Color(0.56, 0.16, 0.12, 0.08))
		# Corner seals.
		draw_circle(Vector2(1062, 250), 22.0, Color(0.66, 0.19, 0.14, 0.85))
		UITheme.centered(self, "夜", 1062, 258, UITheme.BRUSH, 22, UITheme.PAPER)
		UITheme.rough_line(self, Vector2(536, 730), Vector2(1064, 730), Color(0.1, 0.09, 0.08, 0.3), 1.5, 7)
