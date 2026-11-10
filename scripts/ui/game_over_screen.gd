class_name GameOverScreen
extends CanvasLayer

signal restart_requested
signal title_requested
signal continue_requested

var _root: Control
var _wave: Label
var _kills: Label
var _time: Label
var _best: Label
var _heading: Label
var _subtitle: Label
var _continue: InkButton
var _detail: Label
var _restart_button: InkButton
var _wave_caption: Label
var _footer: Label
var _art: DeathArt
var _back_button: InkButton
var _panel_tween: Tween
var _action_pending := false


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.022, 0.019, 0.015, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var art := DeathArt.new()
	_art = art
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(art)

	var title := UITheme.brush("墨 尽", 150, UITheme.PAPER)
	_heading = title
	title.add_theme_constant_override("outline_size", 20)
	title.add_theme_color_override("font_outline_color", UITheme.INK)
	title.position = Vector2(0, 120)
	title.size = Vector2(1600, 170)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)

	var sub := UITheme.body("灯灭，墨干，长夜未央。", 17, UITheme.PAPER_DARK)
	_subtitle = sub
	sub.position = Vector2(0, 300)
	sub.size = Vector2(1600, 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(sub)

	_wave = _stat("止步于", 360)
	_kills = _stat("斩", 560)
	_time = _stat("存活", 760)
	_best = UITheme.body("最深 · 第 一 波", 14, UITheme.MUTED)
	_best.position = Vector2(0, 506)
	_best.size = Vector2(1600, 24)
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_best)

	_continue = InkButton.new()
	_continue.text = "续 写 · 无 尽 守 夜"
	_continue.position = Vector2(600, 548)
	_continue.size = Vector2(400, 56)
	_continue.custom_minimum_size = Vector2(400, 56)
	_continue.accent = UITheme.GOLD
	_continue.pressed.connect(_request_continue)
	_root.add_child(_continue)
	_continue.visible = false
	_detail = UITheme.body("", 14, UITheme.PAPER_DARK)
	_detail.position = Vector2(340, 740)
	_detail.size = Vector2(920, 28)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_detail)

	var restart := InkButton.new()
	_restart_button = restart
	restart.text = "再 入 墨 境"
	restart.position = Vector2(600, 620)
	restart.size = Vector2(400, 62)
	restart.custom_minimum_size = Vector2(400, 62)
	restart.pressed.connect(_request_restart)
	_root.add_child(restart)

	var back := InkButton.new()
	_back_button = back
	back.text = "归 隐"
	back.position = Vector2(690, 692)
	back.size = Vector2(220, 50)
	back.custom_minimum_size = Vector2(220, 50)
	back.accent = UITheme.INK_SOFT
	back.pressed.connect(_request_title)
	_root.add_child(back)

	var hint := UITheme.body("此局已尽，墨迹长存。", 13, UITheme.MUTED)
	_footer = hint
	hint.position = Vector2(0, 780)
	hint.size = Vector2(1600, 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(hint)
	_root.modulate.a = 0.0


func _stat(caption: String, x: float) -> Label:
	var label := UITheme.brush("0", 52, UITheme.PAPER)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", UITheme.INK)
	label.position = Vector2(x, 370)
	label.size = Vector2(200, 70)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(label)
	var cap := UITheme.body(caption, 13, UITheme.PAPER_DARK)
	if caption == "止步于":
		_wave_caption = cap
	cap.position = Vector2(x, 440)
	cap.size = Vector2(200, 22)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(cap)
	return label


func open(wave_reached: int, kills: int, seconds: int, best: int, victory: bool = false) -> void:
	visible = true
	_action_pending = false
	_back_button.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_art.victory = victory
	_art.queue_redraw()
	_wave_caption.text = "肃清" if victory else "止步于"
	_footer.text = "天色已明，笔锋未尽。" if victory else "此局已尽，墨迹长存。"
	_heading.text = "破 晓" if victory else "墨 尽"
	_heading.add_theme_color_override("font_color", UITheme.GOLD if victory else UITheme.PAPER)
	_subtitle.text = "十波墨劫已平，长夜终有尽时。" if victory else "灯灭，墨干，长夜未央。"
	_restart_button.enabled = not NET.active or NET.is_host
	_continue.visible = victory
	_continue.enabled = not NET.active or NET.is_host
	_restart_button.text = "等待房主重开" if NET.active and not NET.is_host else "再 入 墨 境"
	_continue.text = "等 待 房 主 续 写" if NET.active and not NET.is_host else "续 写 · 无 尽 守 夜"
	if NET.active and not NET.is_host:
		_footer.text = "下一程由房主决定；你也可归隐离开房间。"
	_detail.text = "%s · %s · 肃清 %d 波 · 承伤 %d" % [MapDB.get_map(Game.selected_map).display_name, RunRules.difficulty(Game.difficulty).name, Game.completed_waves, Game.damage_taken]
	_wave.text = "第 %s 波" % UITheme.cn_num(wave_reached)
	_kills.text = "%d" % kills
	_time.text = "%02d:%02d" % [int(seconds / 60), seconds % 60]
	_best.text = "最深 · 第 %s 波" % UITheme.cn_num(best)
	_root.modulate.a = 0.0
	if is_instance_valid(_panel_tween):
		_panel_tween.kill()
	_panel_tween = _root.create_tween()
	_panel_tween.tween_property(_root, "modulate:a", 1.0, 0.55)
	_focus_default.call_deferred()


func close() -> void:
	visible = false
	if is_instance_valid(_panel_tween):
		_panel_tween.kill()


func _focus_default() -> void:
	if not visible or not is_inside_tree() or _action_pending:
		return
	if _continue.visible and _continue.enabled:
		UITheme.focus_later(_continue)
	elif _restart_button.enabled:
		UITheme.focus_later(_restart_button)
	else:
		UITheme.focus_later(_back_button)


func _begin_action() -> void:
	_action_pending = true
	_continue.enabled = false
	_restart_button.enabled = false
	_back_button.enabled = false


func _request_continue() -> void:
	if visible and not _action_pending and _continue.visible and _continue.enabled:
		_begin_action()
		continue_requested.emit()


func _request_restart() -> void:
	if visible and not _action_pending and _restart_button.enabled:
		_begin_action()
		restart_requested.emit()


func _request_title() -> void:
	if visible and not _action_pending and _back_button.enabled:
		_begin_action()
		title_requested.emit()


class DeathArt extends Control:
	var victory := false
	func _draw() -> void:
		# An enormous torn ink stain behind everything.
		var rng := RandomNumberGenerator.new()
		rng.seed = 8012
		var center := Vector2(800, 380)
		for i in 12:
			var off := Vector2(rng.randf_range(-240, 240), rng.randf_range(-160, 160))
			draw_circle(center + off, rng.randf_range(100, 280), Color(0.02, 0.018, 0.015, rng.randf_range(0.04, 0.12)))
		# Cinnabar seal sun, dimmed.
		draw_circle(Vector2(800, 380), 230.0, Color(0.52, 0.13, 0.1, 0.07))
		draw_arc(Vector2(800, 380), 231.0, 0, TAU, 80, Color(0.52, 0.13, 0.1, 0.14), 3.0, true)
		# Horizontal dry-brush tear.
		for i in 8:
			var y := 540.0 + i * 4.0
			UITheme.rough_line(self, Vector2(420, y), Vector2(1180, y),
				Color(0.7, 0.65, 0.55, 0.04), 6.0, 50 + i)
		# Small seal marks.
		draw_circle(Vector2(1260, 250), 26.0, Color(0.55, 0.16, 0.12, 0.65))
		UITheme.centered(self, "晓" if victory else "殁", 1260, 259, UITheme.BRUSH, 24, UITheme.PAPER)
