class_name UpgradeCard
extends Control

signal chosen(card: UpgradeCard, data: Dictionary)

var data: Dictionary = {}
var index := 0
var hovered := false
var hover_t := 0.0
var _seed := 0
var _locked := false
var _selected := false


func _ready() -> void:
	custom_minimum_size = Vector2(360, 480)
	size = Vector2(360, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	focus_entered.connect(_on_focus_enter)
	focus_exited.connect(_on_focus_exit)
	set_process(true)


func set_data(d: Dictionary, i: int) -> void:
	data = d
	index = i
	_seed = hash(String(d.get("id", ""))) + i * 37
	queue_redraw()


func _on_enter() -> void:
	if _locked:
		return
	hovered = true
	Sfx.play("hover", -14.0)


func _on_exit() -> void:
	hovered = false


func _process(delta: float) -> void:
	var target := 1.0 if not _locked and (hovered or has_focus()) else 0.0
	var old := hover_t
	hover_t = move_toward(hover_t, target, delta * 7.0)
	if old != hover_t:
		queue_redraw()


func _on_focus_enter() -> void:
	if not _locked and not hovered:
		Sfx.play("hover", -14.0)
	queue_redraw()


func _on_focus_exit() -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _locked:
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		activate()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		activate()
		accept_event()


func activate() -> void:
	if not _locked and is_visible_in_tree():
		chosen.emit(self, data)


func lock(selected: bool = false) -> void:
	_locked = true
	_selected = selected
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if has_focus():
		release_focus()
	hovered = false
	queue_redraw()


func _draw() -> void:
	if data.is_empty():
		return
	var rarity := int(data.get("rarity", 0))
	var rarity_color := UpgradeDB.rarity_color(rarity)
	var lift := hover_t * 3.0
	var rect := Rect2(0, -lift, size.x, size.y)
	# Ink shadow.
	UITheme.rough_rect(self, Rect2(5, 5 - lift, size.x, size.y), Color(0.03, 0.025, 0.02, 0.4),
		Color(0.0, 0.0, 0.0, 0.0), 0.0, _seed + 3, 2.4)
	# Paper card.
	var paper := UITheme.PAPER.lerp(UITheme.PAPER_LIGHT, hover_t * 0.6)
	var border := UITheme.INK if hover_t < 0.4 else rarity_color.darkened(0.1)
	UITheme.rough_rect(self, rect.grow(-1.0), paper, border, 2.4 + hover_t * 1.2, _seed, 2.2)
	# Rarity band and inner border.
	UITheme.rough_rect(self, Rect2(14, 12, size.x - 28, 9), rarity_color,
		Color(0, 0, 0, 0), 0.0, _seed + 8, 1.2)
	UITheme.rough_rect(self, Rect2(14, 30, size.x - 28, size.y - 50), Color(0, 0, 0, 0),
		Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, 0.18), 1.0, _seed + 9, 1.8)
	# Tag and rarity labels.
	draw_string(UITheme.BODY, Vector2(26, 58), String(data.get("tag", "")), HORIZONTAL_ALIGNMENT_LEFT,
		-1, 13, UITheme.MUTED)
	draw_string(UITheme.BODY, Vector2(0, 58), UpgradeDB.rarity_name(rarity),
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - 26.0, 13, rarity_color)
	# Seal.
	var center := Vector2(size.x * 0.5, 120 - lift)
	var glyph := String(data.get("icon", "?"))
	UITheme.seal(self, center, 40.0 + hover_t * 2.0, rarity_color, glyph, UITheme.PAPER, 50)
	# Name.
	UITheme.centered(self, String(data.get("name", "")), size.x * 0.5, 202 - lift,
		UITheme.BRUSH, 38, UITheme.INK)
	UITheme.rough_line(self, Vector2(32, 218 - lift), Vector2(size.x - 32, 218 - lift),
		Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, 0.35), 1.5, _seed + 4)
	# Description: first paragraph is flavour, later ones are effects.
	var desc := String(data.get("desc", ""))
	var paragraphs := desc.split("\n")
	var y := 246.0 - lift
	var first := true
	for paragraph in paragraphs:
		if paragraph.strip_edges() == "":
			continue
		var lines := UITheme.wrap_text(paragraph, 17.5)
		for line in lines:
			var col := UITheme.MUTED if first else UITheme.INK_SOFT
			draw_string(UITheme.BODY, Vector2(30, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
			y += 24.0
		first = false
		y += 4.0
	# Key hint.
	var hint_rect := Rect2(size.x * 0.5 - 46, size.y - 48 - lift, 92, 30)
	UITheme.rough_rect(self, hint_rect, Color(UITheme.PAPER_DARK.r, UITheme.PAPER_DARK.g, UITheme.PAPER_DARK.b, 0.8),
		UITheme.INK, 1.2, _seed + 5, 1.2)
	var hint_text := "Enter 择之" if has_focus() and not _locked else "「%d」" % (index + 1)
	UITheme.centered(self, hint_text, hint_rect.get_center().x, hint_rect.position.y + 21,
		UITheme.BODY, 14, UITheme.CINNABAR_DARK if has_focus() else UITheme.INK_SOFT)
	# Hover wash.
	if hover_t > 0.01:
		draw_rect(rect.grow(-6.0), Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.045 * hover_t))
		draw_circle(Vector2(size.x - 30, 20), 3.0, Color(rarity_color.r, rarity_color.g, rarity_color.b, hover_t))

	if has_focus() and not _locked:
		UITheme.rough_rect(self, rect.grow(-7.0), Color(0, 0, 0, 0), UITheme.CINNABAR,
			1.4, _seed + 71, 0.8)
	if _selected:
		UITheme.seal(self, Vector2(size.x - 45.0, size.y - 51.0), 23.0,
			UITheme.CINNABAR, "定", UITheme.PAPER_LIGHT, 28)
