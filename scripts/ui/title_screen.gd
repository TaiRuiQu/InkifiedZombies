class_name TitleScreen
extends CanvasLayer

signal start_requested
signal quit_requested
signal settings_requested
signal multiplayer_requested
signal map_selected(id: String)

var _root: Control
var _best: Label
var _start: InkButton
var _quit: InkButton
var _hint: Label
var _selectors: Dictionary = {}
var _preview_title: Label
var _preview_description: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var art := TitleArt.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(art)
	var title1 := UITheme.brush("墨", 140, UITheme.INK)
	title1.position = Vector2(96, 34)
	title1.size = Vector2(250, 170)
	_root.add_child(title1)
	var title2 := UITheme.brush("潮", 140, UITheme.INK)
	title2.position = Vector2(128, 162)
	title2.size = Vector2(250, 170)
	_root.add_child(title2)
	var en := UITheme.body("I N K   T I D E", 15, UITheme.MUTED)
	en.position = Vector2(104, 350)
	_root.add_child(en)
	var tagline := UITheme.brush("以墨为刃，独守长夜。", 25, UITheme.INK_SOFT)
	tagline.position = Vector2(102, 385)
	_root.add_child(tagline)
	var sep := ColorRect.new()
	sep.color = Color(0.1, 0.09, 0.08, 0.35)
	sep.position = Vector2(104, 434)
	sep.size = Vector2(492, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(sep)
	var map_names: Array = []
	for map_id in MapDB.ids():
		map_names.append(MapDB.get_map(map_id).display_name)
	_selection("墨 境", "selected_map", map_names, MapDB.ids(), 456)
	_selection("难 度", "difficulty", ["初入墨境 · 从容", "守夜人 · 标准", "墨潮试炼 · 艰险"], ["story", "standard", "ordeal"], 510)
	_selection("征 途", "endless", ["十波试炼 · 双将镇关", "无尽守夜 · 挑战纪录"], [false, true], 564)
	_hint = UITheme.body("", 13, UITheme.INK_SOFT)
	_hint.position = Vector2(104, 628)
	_hint.size = Vector2(500, 52)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_hint)
	_best = UITheme.body("尚无墨迹。", 14, UITheme.MUTED)
	_best.position = Vector2(104, 689)
	_best.size = Vector2(490, 24)
	_root.add_child(_best)
	_start = InkButton.new()
	_start.text = "独 守 · 单 人"
	_start.position = Vector2(104, 730)
	_start.size = Vector2(238, 54)
	_start.custom_minimum_size = Vector2(238, 54)
	_start.accent = UITheme.CINNABAR
	_start.pressed.connect(_request_start)
	_root.add_child(_start)
	var coop := InkButton.new()
	coop.text = "同 守 · 多 人"
	coop.position = Vector2(358, 730)
	coop.size = Vector2(238, 54)
	coop.custom_minimum_size = Vector2(238, 54)
	coop.accent = UITheme.INDIGO
	coop.pressed.connect(_request_multiplayer)
	_root.add_child(coop)
	var settings := InkButton.new()
	settings.text = "调 墨 · 设 置"
	settings.position = Vector2(104, 800)
	settings.size = Vector2(238, 44)
	settings.custom_minimum_size = Vector2(238, 44)
	settings.accent = UITheme.INDIGO
	settings.pressed.connect(_request_settings)
	_root.add_child(settings)
	_quit = InkButton.new()
	_quit.text = "归 隐"
	_quit.position = Vector2(358, 800)
	_quit.size = Vector2(238, 44)
	_quit.custom_minimum_size = Vector2(238, 44)
	_quit.accent = UITheme.INK_SOFT
	_quit.pressed.connect(_request_quit)
	_root.add_child(_quit)
	var foot := UITheme.body("空格 / Enter 独守 · 同守支持好友直连与中转", 12, UITheme.MUTED)
	foot.position = Vector2(104, 861)
	_root.add_child(foot)
	var side := UITheme.brush("十 波 墨 劫", 26, UITheme.PAPER)
	side.add_theme_constant_override("outline_size", 8)
	side.add_theme_color_override("font_outline_color", UITheme.INK)
	side.position = Vector2(1320, 770)
	side.size = Vector2(240, 40)
	side.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(side)
	var preview := PreviewCaption.new()
	preview.position = Vector2(912, 620)
	preview.size = Vector2(644, 142)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(preview)
	_preview_title = UITheme.brush("", 34, UITheme.PAPER_LIGHT, 7, UITheme.INK)
	_preview_title.position = Vector2(26, 16)
	_preview_title.size = Vector2(590, 48)
	preview.add_child(_preview_title)
	_preview_description = UITheme.body("", 16, UITheme.PAPER_LIGHT)
	_preview_description.position = Vector2(28, 76)
	_preview_description.size = Vector2(578, 52)
	_preview_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_description.add_theme_color_override("font_outline_color", UITheme.INK)
	_preview_description.add_theme_constant_override("outline_size", 3)
	preview.add_child(_preview_description)
	var version := String(ProjectSettings.get_setting("application/config/version", "0.2.3"))
	var ver := UITheme.body("墨潮 v%s 内测 · 十波双 Boss · 好友同守" % version, 12, UITheme.PAPER_DARK)
	ver.add_theme_constant_override("outline_size", 5)
	ver.add_theme_color_override("font_outline_color", UITheme.INK)
	ver.position = Vector2(1040, 846)
	ver.size = Vector2(520, 24)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(ver)
	_root.modulate.a = 0.0


func _selection(label: String, property: String, labels: Array, values: Array, y: float) -> void:
	var caption := UITheme.brush(label, 23, UITheme.CINNABAR)
	caption.position = Vector2(104, y + 7)
	caption.size = Vector2(90, 36)
	_root.add_child(caption)
	var option := InkOptionButton.new()
	option.position = Vector2(210, y)
	option.size = Vector2(386, 46)
	option.add_theme_font_override("font", UITheme.BODY)
	option.add_theme_font_size_override("font_size", 16)
	option.add_theme_color_override("font_color", UITheme.INK)
	option.add_theme_color_override("font_hover_color", UITheme.CINNABAR)
	option.add_theme_color_override("font_pressed_color", UITheme.CINNABAR_DARK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = UITheme.PAPER_LIGHT if state != "pressed" else UITheme.PAPER_DARK
		box.border_color = UITheme.CINNABAR if state in ["hover", "focus"] else UITheme.PAPER_DARK
		box.set_border_width_all(1)
		box.set_content_margin_all(10)
		option.add_theme_stylebox_override(state, box)
	for i: int in labels.size():
		option.add_item(String(labels[i]), i)
	option.set_meta("setting_values", values)
	option.item_selected.connect(_on_selection_changed.bind(property))
	_root.add_child(option)
	_selectors[property] = option


func _on_selection_changed(index: int, property: String) -> void:
	var selector: OptionButton = _selectors.get(property)
	if selector == null:
		return
	var values: Array = selector.get_meta("setting_values", [])
	if index < 0 or index >= values.size():
		return
	Game.set(property, values[index])
	if property == "selected_map":
		_refresh_preview_caption()
		map_selected.emit(String(values[index]))


func _request_start() -> void:
	start_requested.emit()


func _request_multiplayer() -> void:
	multiplayer_requested.emit()


func _request_settings() -> void:
	settings_requested.emit()


func _request_quit() -> void:
	quit_requested.emit()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	UITheme.focus_later(_start)
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.45)


func close() -> void:
	visible = false


func refresh() -> void:
	for property: String in _selectors:
		var selector: OptionButton = _selectors[property]
		var values: Array = selector.get_meta("setting_values")
		selector.select(maxi(values.find(Game.get(property)), 0))
	_refresh_preview_caption()
	_hint.text = "WASD 移动 · %s 射击 · %s 疾风步 · ESC 暂停\n每波择一升级 · 第五 / 十波迎战墨将" % [Settings.binding_text("fire"), Settings.binding_text("dash")]
	if Game.best_wave > 0:
		_best.text = "最深 · 第 %s 波" % UITheme.cn_num(Game.best_wave)
	else:
		_best.text = "尚无墨迹。"


func _refresh_preview_caption() -> void:
	if _preview_title == null:
		return
	var definition := MapDB.get_map(Game.selected_map)
	_preview_title.text = definition.display_name
	_preview_description.text = definition.description


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			start_requested.emit()
			get_viewport().set_input_as_handled()


class TitleArt extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.022, 0.018, 0.16))
		# Rising seal sun behind the title.
		draw_circle(Vector2(420, 300), 132.0, Color(0.66, 0.2, 0.14, 0.13))
		draw_arc(Vector2(420, 300), 132.0, 0, TAU, 64, Color(0.5, 0.14, 0.1, 0.18), 8.0, true)
		# Pale ink wash circle.
		draw_circle(Vector2(260, 300), 230.0, Color(0.06, 0.055, 0.05, 0.035))
		# Paper scroll panel.
		UITheme.rough_rect(self, Rect2(-36, -36, 720, 972),
			Color(0.925, 0.89, 0.80, 0.955), UITheme.INK, 2.0, 7741, 2.5)
		# Vertical ink edge.
		UITheme.rough_line(self, Vector2(682, -20), Vector2(682, 920),
			Color(0.08, 0.07, 0.06, 0.55), 2.0, 31)
		UITheme.rough_line(self, Vector2(690, 40), Vector2(690, 800),
			Color(0.08, 0.07, 0.06, 0.16), 6.0, 32)
		# Dry brush strokes.
		var rng := RandomNumberGenerator.new()
		rng.seed = 4412
		for i in 14:
			var y := rng.randf_range(860, 900)
			var x := rng.randf_range(70, 630)
			var w := rng.randf_range(30, 160)
			draw_line(Vector2(x, y), Vector2(x + w, y + rng.randf_range(-3, 3)),
				Color(0.12, 0.11, 0.1, rng.randf_range(0.04, 0.12)), rng.randf_range(1.0, 3.0), true)
		# Small seals.
		draw_circle(Vector2(560, 120), 36.0, Color(0.66, 0.19, 0.14, 0.9))
		draw_arc(Vector2(560, 120), 36.0, 0, TAU, 36, UITheme.INK, 2.0, true)
		UITheme.centered(self, "墨", 560, 132, UITheme.BRUSH, 38, UITheme.PAPER)
		draw_circle(Vector2(556, 300), 16.0, Color(0.66, 0.19, 0.14, 0.8))
		UITheme.centered(self, "潮", 556, 307, UITheme.BRUSH, 18, UITheme.PAPER)
		# Vertical cinnabar line beside the title.
		UITheme.rough_line(self, Vector2(86, 74), Vector2(86, 380), Color(0.66, 0.19, 0.14, 0.55), 3.0, 8)
		# Ink speckles near the bottom.
		for i in 20:
			var px := rng.randf_range(90, 650)
			var py := rng.randf_range(450, 880)
			draw_circle(Vector2(px, py), rng.randf_range(0.5, 1.8),
				Color(0.1, 0.09, 0.08, rng.randf_range(0.03, 0.1)))


class PreviewCaption extends Control:
	func _draw() -> void:
		UITheme.rough_rect(self, Rect2(Vector2.ZERO, size), Color(0.035, 0.032, 0.028, 0.68),
			Color(0.81, 0.74, 0.60, 0.58), 1.2, 9611, 1.3)
		UITheme.rough_line(self, Vector2(13, 20), Vector2(13, size.y - 20), UITheme.CINNABAR, 3.0, 9621)
