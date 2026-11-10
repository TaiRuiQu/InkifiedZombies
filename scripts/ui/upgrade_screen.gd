class_name UpgradeScreen
extends CanvasLayer

signal chosen(upgrade: Dictionary)

var _root: Control
var _dim: ColorRect
var _wave_label: Label
var _title: Label
var _sub: Label
var _cards: Array[UpgradeCard] = []
var _skip: InkButton
var _hint: Label
var _choosing := false
var _wave := 1
var _choice_timer: Timer
var _panel_tween: Tween
var _pending_choice: Dictionary = {}


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	_choice_timer = Timer.new()
	_choice_timer.one_shot = true
	_choice_timer.wait_time = 0.55
	_choice_timer.timeout.connect(_complete_choice)
	add_child(_choice_timer)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.035, 0.03, 0.024, 0.77)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	var wash := InkBackdrop.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wash)

	_wave_label = UITheme.body("第 一 波 · 肃清", 16, UITheme.PAPER_DARK)
	_wave_label.add_theme_constant_override("outline_size", 5)
	_wave_label.add_theme_color_override("font_outline_color", UITheme.INK)
	_wave_label.position = Vector2(0, 64)
	_wave_label.size = Vector2(1600, 24)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_wave_label)

	_title = UITheme.brush("择 一 而 进", 66, UITheme.PAPER)
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_outline_color", UITheme.INK)
	_title.position = Vector2(0, 88)
	_title.size = Vector2(1600, 86)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_title)

	_sub = UITheme.body("余下之路，由此笔定。", 16, UITheme.PAPER_DARK)
	_sub.add_theme_constant_override("outline_size", 5)
	_sub.add_theme_color_override("font_outline_color", UITheme.INK)
	_sub.position = Vector2(0, 172)
	_sub.size = Vector2(1600, 24)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_sub)

	_skip = InkButton.new()
	_skip.text = "弃 · 回气三成"
	_skip.position = Vector2(675, 760)
	_skip.size = Vector2(250, 48)
	_skip.custom_minimum_size = Vector2(250, 48)
	_skip.pressed.connect(_on_skip)
	_root.add_child(_skip)
	_hint = UITheme.body("按下 1 / 2 / 3 择之", 14, UITheme.PAPER_DARK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.add_theme_color_override("font_outline_color", UITheme.INK)
	_hint.position = Vector2(0, 820)
	_hint.size = Vector2(1600, 22)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)


func open(wave: int, choices: Array) -> void:
	_cancel_pending_choice()
	_wave = wave
	_choosing = false
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_wave_label.text = "第 %s 波 · 肃清" % UITheme.cn_num(wave)
	_title.text = "择 一 而 进"
	_sub.text = "余下之路，由此笔定。"
	_hint.text = "1 / 2 / 3 快选 · Tab / 方向键移笔 · Enter 择之"
	_skip.enabled = true
	_skip.modulate.a = 1.0

	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()

	for i in choices.size():
		var card := UpgradeCard.new()
		card.position = Vector2(220.0 + i * 400.0, 250.0)
		card.size = Vector2(360, 480)
		card.set_data(choices[i], i)
		card.chosen.connect(_on_card_chosen)
		card.pivot_offset = Vector2(180, 240)
		_root.add_child(card)
		_cards.append(card)
		card.modulate.a = 0.0
		card.position.y += 24.0
		var tw := card.create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.3).set_delay(0.06 * i)
		tw.tween_property(card, "position:y", 250.0, 0.38).set_delay(0.06 * i)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_wire_card_focus()
	_root.modulate.a = 0.0
	_panel_tween = _root.create_tween()
	_panel_tween.tween_property(_root, "modulate:a", 1.0, 0.22)
	_focus_initial.call_deferred()


func close() -> void:
	_cancel_pending_choice()
	visible = false
	_choosing = false
	for card in _cards:
		if is_instance_valid(card):
			card.lock()


func _on_card_chosen(card: UpgradeCard, data: Dictionary) -> void:
	if _choosing or not visible:
		return
	_choose(data, card)


func _on_skip() -> void:
	if _choosing or not visible:
		return
	var data := {
		"id": "skip_heal", "name": "静心", "icon": "息", "rarity": 0, "tag": "护体",
		"desc": "退一步，也是一种笔法。\n立即回复 30% 气血。",
		"effects": {"heal_percent": 0.3}, "max_stack": 99,
	}
	_choose(data, null)


func _choose(data: Dictionary, card: UpgradeCard) -> void:
	_choosing = true
	_pending_choice = data.duplicate(true)
	_title.text = "此 笔 已 定" if card != null else "静 心 回 气"
	_sub.text = String(data.get("name", "静心"))
	_hint.text = "凝墨成形，稍候再进。"
	Sfx.play("upgrade", -1.0)
	_skip.enabled = false
	for c in _cards:
		if is_instance_valid(c):
			c.lock(c == card)
	if card and is_instance_valid(card):
		var tw := card.create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "scale", Vector2(1.04, 1.04), 0.2)
		tw.tween_property(card, "modulate:a", 1.0, 0.2)
		for other in _cards:
			if other != card and is_instance_valid(other):
				other.create_tween().tween_property(other, "modulate:a", 0.15, 0.2)
	if is_instance_valid(_panel_tween):
		_panel_tween.kill()
	_panel_tween = _root.create_tween()
	_panel_tween.tween_property(_root, "modulate:a", 0.0, 0.35).set_delay(0.22)
	_choice_timer.start()


func _cancel_pending_choice() -> void:
	if is_instance_valid(_choice_timer):
		_choice_timer.stop()
	if is_instance_valid(_panel_tween):
		_panel_tween.kill()
	_pending_choice.clear()


func _complete_choice() -> void:
	if not visible or not _choosing or _pending_choice.is_empty():
		return
	var selected := _pending_choice.duplicate(true)
	_pending_choice.clear()
	visible = false
	_choosing = false
	chosen.emit(selected)


func _wire_card_focus() -> void:
	if _cards.is_empty():
		return
	for index in _cards.size():
		var card := _cards[index]
		var previous: Control = _cards[index - 1] if index > 0 else _skip
		var next: Control = _cards[index + 1] if index + 1 < _cards.size() else _skip
		card.focus_previous = card.get_path_to(previous)
		card.focus_next = card.get_path_to(next)
		card.focus_neighbor_left = card.get_path_to(previous)
		card.focus_neighbor_right = card.get_path_to(next)
		card.focus_neighbor_bottom = card.get_path_to(_skip)
	_skip.focus_previous = _skip.get_path_to(_cards.back())
	_skip.focus_next = _skip.get_path_to(_cards.front())
	_skip.focus_neighbor_top = _skip.get_path_to(_cards.front())


func _focus_initial() -> void:
	if not visible or _choosing or not is_inside_tree():
		return
	if not _cards.is_empty() and is_instance_valid(_cards[0]):
		UITheme.focus_later(_cards[0])
	else:
		UITheme.focus_later(_skip)


func _input(event: InputEvent) -> void:
	if not visible or _choosing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		if event.keycode >= KEY_1 and event.keycode <= KEY_3:
			idx = int(event.keycode - KEY_1)
		if idx >= 0 and idx < _cards.size():
			_on_card_chosen(_cards[idx], _cards[idx].data)
			get_viewport().set_input_as_handled()


class InkBackdrop extends Control:
	func _draw() -> void:
		var cx := size.x * 0.5
		UITheme.rough_rect(self, Rect2(cx - 470, 42, 940, 168),
			Color(0.06, 0.052, 0.042, 0.35), Color(0.7, 0.65, 0.55, 0.12), 1.5, 5551, 3.0)
		UITheme.rough_line(self, Vector2(cx - 410, 200), Vector2(cx + 410, 200),
			Color(0.72, 0.64, 0.5, 0.18), 2.0, 12)
		for i in 8:
			var x := cx - 430 + i * 122
			draw_circle(Vector2(x, 96.0 + sin(i * 1.7) * 36.0), 1.4,
				Color(0.85, 0.8, 0.68, 0.12))
