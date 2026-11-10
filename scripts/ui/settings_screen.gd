class_name SettingsScreen
extends CanvasLayer

## A persistent, keyboard-accessible settings overlay shared by title and pause.
## Changes apply immediately, including while the game tree is paused.
signal closed

var _root: Control
var _tabs: TabContainer
var _status: Label
var _back: Button
var _controls: Dictionary = {}
var _binding_buttons: Dictionary = {}
var _binding_action := ""
var _refreshing := false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	Settings.bindings_changed.connect(_refresh_bindings)
	Settings.save_failed.connect(_on_save_failed)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = create_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.025, 0.022, 0.018, 0.86)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.065
	panel.anchor_bottom = 0.935
	panel.add_theme_stylebox_override("panel", _style(UITheme.PAPER, UITheme.INK, 2))
	_root.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := UITheme.brush("调 墨", 48)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var subtitle := UITheme.body("偏好随行 · 设置自动保存", 16, UITheme.MUTED)
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(subtitle)
	var line := HSeparator.new()
	column.add_child(line)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_override("font", UITheme.BODY)
	column.add_child(_tabs)
	_build_display(_tab("画 面"))
	_build_audio(_tab("声 音"))
	_build_controls(_tab("操 作"))
	_build_accessibility(_tab("舒 适"))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	column.add_child(footer)
	_status = UITheme.body("调整即时生效 · ESC 返回 · Tab 切换焦点", 14, UITheme.MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(200, 50)
	footer.add_child(_status)
	var defaults := Button.new()
	defaults.text = "恢复默认"
	defaults.custom_minimum_size = Vector2(144, 48)
	defaults.pressed.connect(_reset_defaults)
	footer.add_child(defaults)
	_back = Button.new()
	_back.text = "保 存 并 返 回"
	_back.custom_minimum_size = Vector2(196, 48)
	_back.pressed.connect(close)
	footer.add_child(_back)


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	return column


func _build_display(column: VBoxContainer) -> void:
	_note(column, "清晰的墨线，适合你的视野。画质与帧率可随时调整。")
	_option(column, "显示模式", "window_mode", ["窗口", "无边框全屏", "独占全屏"], [0, 1, 2])
	_option(column, "窗口分辨率", "resolution", ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"], [0, 1, 2, 3])
	_note(column, "全屏使用显示器原生分辨率。窗口尺寸会适配屏幕可用空间。", 13)
	_option(column, "画质", "quality", ["流畅 · 75% 渲染 / 无阴影", "标准 · 100% 渲染 / 2× MSAA", "精细 · 100% 渲染 / 4× MSAA"], [0, 1, 2])
	_option(column, "帧率上限", "fps_limit", ["60 FPS", "90 FPS", "120 FPS", "144 FPS", "165 FPS", "240 FPS", "不限"], [60, 90, 120, 144, 165, 240, 0])
	_check(column, "垂直同步", "vsync")
	_slider(column, "视野范围", "fov", 65, 105, 1, "°")
	_note(column, "较大的视野可看见更多敌人；机瞄会按比例收窄视野。", 13)


func _build_audio(column: VBoxContainer) -> void:
	_note(column, "枪声、敌袭与环境，各有分寸。音量为零时完全静音。")
	_slider(column, "主音量", "master_volume", 0, 1, 0.01, "%")
	_slider(column, "音效音量", "sfx_volume", 0, 1, 0.01, "%")
	_slider(column, "环境音量", "ambient_volume", 0, 1, 0.01, "%")
	_slider(column, "背景音乐", "music_volume", 0, 1, 0.01, "%")
	var preview := Button.new()
	preview.text = "试听 · 挥墨"
	preview.custom_minimum_size = Vector2(240, 46)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preview.pressed.connect(_preview_sound)
	column.add_child(preview)


func _build_controls(column: VBoxContainer) -> void:
	_slider(column, "鼠标灵敏度", "mouse_sensitivity", 0.15, 3.0, 0.05, "×")
	_check(column, "反转鼠标纵轴", "invert_y")
	_note(column, "点击操作按键后，按下新按键或鼠标键。ESC 取消；重复按键会提示冲突。", 14)
	_note(column, "ESC 固定为暂停 / 返回；滚轮固定为切换武器。数字键在升级时选择卡片。", 13)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(grid)
	for action: String in Settings.ACTIONS:
		var label := UITheme.body(String(Settings.ACTIONS[action]), 16)
		label.custom_minimum_size = Vector2(140, 40)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(label)
		var button := Button.new()
		button.text = Settings.binding_text(action)
		button.custom_minimum_size = Vector2(220, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_begin_binding.bind(action))
		grid.add_child(button)
		_binding_buttons[action] = button


func _build_accessibility(column: VBoxContainer) -> void:
	_note(column, "把注意力留给战斗。减少镜头运动与闪烁，让长夜更舒适。")
	_check(column, "镜头晃动与行走起伏", "camera_shake")
	_check(column, "受击边缘闪烁", "damage_flash")
	_check(column, "浮动伤害数字", "damage_numbers")
	_slider(column, "准星大小", "crosshair_scale", 0.6, 1.8, 0.05, "×")
	_note(column, "关闭镜头晃动会保留瞄准与武器反馈，便于判断弹着点。", 13)


func _row(column: VBoxContainer, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.custom_minimum_size.y = 46
	column.add_child(row)
	var text := UITheme.body(label, 17)
	text.custom_minimum_size.x = 200
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	return row


func _option(column: VBoxContainer, label: String, key: String, options: Array, values: Array) -> void:
	var row := _row(column, label)
	var button := InkOptionButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 44
	for i: int in options.size():
		button.add_item(String(options[i]), i)
	button.set_meta("setting_values", values)
	button.item_selected.connect(_on_option_selected.bind(key))
	row.add_child(button)
	_controls[key] = button


func _slider(column: VBoxContainer, label: String, key: String, minimum: float, maximum: float, step_size: float, suffix: String) -> void:
	var row := _row(column, label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 180
	row.add_child(slider)
	var number := UITheme.body("", 17, UITheme.CINNABAR)
	number.custom_minimum_size.x = 90
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(number)
	slider.set_meta("value_label", number)
	slider.set_meta("suffix", suffix)
	slider.value_changed.connect(_on_slider_changed.bind(key))
	_controls[key] = slider


func _check(column: VBoxContainer, label: String, key: String) -> void:
	var check := CheckButton.new()
	check.text = label
	check.custom_minimum_size.y = 44
	check.toggled.connect(_on_check_toggled.bind(key))
	column.add_child(check)
	_controls[key] = check


func _on_save_failed(_error: Error) -> void:
	_status.text = "设置保存失败，请检查存档目录权限。"


func _preview_sound() -> void:
	Sfx.play("pistol", -8.0)


func _on_option_selected(index: int, key: String) -> void:
	var button: OptionButton = _controls.get(key)
	if _refreshing or button == null:
		return
	var values: Array = button.get_meta("setting_values", [])
	if index >= 0 and index < values.size():
		Settings.set_value(key, values[index])


func _on_slider_changed(value: float, key: String) -> void:
	var slider: HSlider = _controls.get(key)
	if slider == null:
		return
	var label: Label = slider.get_meta("value_label")
	_update_number(label, value, String(slider.get_meta("suffix")))
	if not _refreshing:
		Settings.set_value(key, value)


func _on_check_toggled(pressed: bool, key: String) -> void:
	if not _refreshing:
		Settings.set_value(key, pressed)


func _note(column: VBoxContainer, text: String, font_size: int = 15) -> void:
	var label := UITheme.body(text, font_size, UITheme.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(label)


func _update_number(label: Label, value: float, suffix: String) -> void:
	if suffix == "%":
		label.text = "%d %%" % roundi(value * 100.0)
	elif suffix == "°":
		label.text = "%d°" % roundi(value)
	else:
		label.text = "%.2f ×" % value


func _refresh() -> void:
	_refreshing = true
	for key: String in _controls:
		var control: Control = _controls[key]
		var value: Variant = Settings.get_value(key)
		if control is OptionButton:
			var options: Array = control.get_meta("setting_values")
			control.select(maxi(options.find(value), 0))
		elif control is HSlider:
			var number: float = float(value) if value is int or value is float else control.value
			control.value = number
			_update_number(control.get_meta("value_label"), number, String(control.get_meta("suffix")))
		elif control is CheckButton:
			control.button_pressed = bool(value)
	_refresh_bindings()
	_refreshing = false


func _refresh_bindings() -> void:
	for action: String in _binding_buttons:
		var button: Button = _binding_buttons[action]
		button.text = Settings.binding_text(action)


func _begin_binding(action: String) -> void:
	_refresh_bindings()
	_binding_action = action
	var button: Button = _binding_buttons[action]
	button.text = "等待按键…"
	_status.text = "正在修改「%s」· 按 ESC 取消" % Settings.ACTIONS[action]


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Leave OS shortcuts (Alt+Tab, Alt+F4, the Windows key) to the host.
	# In particular they must not accidentally become a plain Tab / F4 binding.
	if event is InputEventKey and (event.alt_pressed or event.meta_pressed):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _binding_action != "":
			_binding_action = ""
			_refresh_bindings()
			_status.text = "已取消按键修改。"
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if _binding_action == "":
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		var error: String = Settings.rebind(_binding_action, event)
		if error == "":
			_status.text = "「%s」已设为 %s" % [Settings.ACTIONS[_binding_action], Settings.binding_text(_binding_action)]
			_binding_action = ""
			_refresh_bindings()
		else:
			_status.text = error + " · ESC 取消"
		get_viewport().set_input_as_handled()


func _reset_defaults() -> void:
	_binding_action = ""
	Settings.reset_defaults()
	_refresh()
	_status.text = "已恢复默认设置与按键。"


func open() -> void:
	_binding_action = ""
	_refresh()
	_status.text = "调整即时生效 · ESC 返回 · Tab 切换焦点"
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UITheme.focus_later(_back)


func close() -> void:
	if not visible:
		return
	_binding_action = ""
	Settings.save()
	visible = false
	closed.emit()


static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = UITheme.BODY
	theme.default_font_size = 16
	for type: String in ["Button", "OptionButton", "CheckButton", "Label", "TabContainer", "TabBar", "PopupMenu", "LineEdit"]:
		theme.set_color("font_color", type, UITheme.INK)
		theme.set_color("font_hover_color", type, UITheme.CINNABAR)
		theme.set_color("font_pressed_color", type, UITheme.CINNABAR_DARK)
		theme.set_color("font_focus_color", type, UITheme.CINNABAR)
	for type: String in ["TabContainer", "TabBar"]:
		theme.set_color("font_selected_color", type, UITheme.INK)
		theme.set_color("font_unselected_color", type, UITheme.INK_SOFT)
		theme.set_color("font_hovered_color", type, UITheme.CINNABAR)
	for type: String in ["Button", "OptionButton", "LineEdit"]:
		theme.set_stylebox("normal", type, _style(UITheme.PAPER_LIGHT, UITheme.PAPER_DARK, 1))
		theme.set_stylebox("hover", type, _style(UITheme.PAPER_LIGHT, UITheme.CINNABAR, 2))
		theme.set_stylebox("pressed", type, _style(UITheme.PAPER_DARK, UITheme.CINNABAR_DARK, 2))
		theme.set_stylebox("focus", type, _style(Color(0, 0, 0, 0), UITheme.CINNABAR, 2))
		theme.set_stylebox("disabled", type, _style(UITheme.PAPER_DARK, UITheme.MUTED, 1))
		theme.set_color("font_disabled_color", type, UITheme.MUTED)
	theme.set_stylebox("panel", "TabContainer", _style(UITheme.PAPER_LIGHT, UITheme.PAPER_DARK, 1))
	theme.set_stylebox("tab_selected", "TabContainer", _style(UITheme.PAPER_LIGHT, UITheme.CINNABAR, 1))
	theme.set_stylebox("tab_unselected", "TabContainer", _style(UITheme.PAPER_DARK, UITheme.PAPER_DARK, 1))
	theme.set_stylebox("panel", "PopupMenu", _style(UITheme.PAPER_LIGHT, UITheme.INK, 1))
	theme.set_stylebox("hover", "PopupMenu", _style(UITheme.PAPER_DARK, UITheme.CINNABAR, 1))
	theme.set_color("caret_color", "LineEdit", UITheme.CINNABAR)
	theme.set_color("font_placeholder_color", "LineEdit", UITheme.MUTED)
	theme.set_color("selection_color", "LineEdit", Color(UITheme.CINNABAR, 0.25))
	theme.set_icon("clear", "LineEdit", load("res://assets/ui/clear_field.svg"))
	# Sliders, toggles and scrollbars share the ink/vermillion language instead
	# of leaving default grey tracks and bright desktop toggle sprites behind.
	var track := _style(UITheme.PAPER_DARK, UITheme.MUTED, 1)
	track.set_content_margin_all(3)
	theme.set_stylebox("slider", "HSlider", track)
	var filled := _style(Color(UITheme.CINNABAR, 0.78), UITheme.CINNABAR_DARK, 1)
	filled.set_content_margin_all(3)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_icon("grabber", "HSlider", load("res://assets/ui/slider_seal.svg"))
	theme.set_icon("grabber_highlight", "HSlider", load("res://assets/ui/slider_seal.svg"))
	theme.set_icon("grabber_disabled", "HSlider", load("res://assets/ui/choice_empty.svg"))
	for control_type: String in ["VScrollBar", "HScrollBar"]:
		var groove := _style(Color(UITheme.INK, 0.10), Color(UITheme.MUTED, 0.28), 1)
		groove.set_content_margin_all(5)
		var thumb := _style(Color(UITheme.CINNABAR_DARK, 0.65), UITheme.CINNABAR_DARK, 1)
		thumb.set_content_margin_all(5)
		theme.set_stylebox("scroll", control_type, groove)
		theme.set_stylebox("grabber", control_type, thumb)
		theme.set_stylebox("grabber_highlight", control_type, thumb)
		theme.set_stylebox("grabber_pressed", control_type, thumb)
	for icon: String in ["checked", "checked_disabled"]:
		theme.set_icon(icon, "CheckButton", load("res://assets/ui/toggle_on.svg"))
	for icon: String in ["unchecked", "unchecked_disabled"]:
		theme.set_icon(icon, "CheckButton", load("res://assets/ui/toggle_off.svg"))
	theme.set_stylebox("normal", "CheckButton", _style(Color(UITheme.PAPER_LIGHT, 0.45), UITheme.PAPER_DARK, 1))
	theme.set_stylebox("hover", "CheckButton", _style(UITheme.PAPER_LIGHT, UITheme.CINNABAR, 1))
	theme.set_stylebox("focus", "CheckButton", _style(Color(0, 0, 0, 0), UITheme.CINNABAR, 2))
	theme.set_stylebox("panel", "TooltipPanel", _style(UITheme.PAPER_LIGHT, UITheme.INK, 1))
	theme.set_color("font_color", "TooltipLabel", UITheme.INK)
	return theme


static func _style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_content_margin_all(12)
	box.set_corner_radius_all(2)
	return box
