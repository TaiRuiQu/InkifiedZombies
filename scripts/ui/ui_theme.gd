class_name UITheme
extends RefCounted

## Shared ink-paper UI language: fonts, palette and rough brush shapes.

const BRUSH: Font = preload("res://assets/fonts/MaShanZheng-Regular.ttf")
const BODY: Font = preload("res://assets/fonts/NotoSansSC.ttf")

const PAPER := Color("e9e1cb")
const PAPER_LIGHT := Color("f1ead8")
const PAPER_DARK := Color("d4c7ac")
const INK := Color("15130f")
const INK_SOFT := Color("2b261f")
const CINNABAR := Color("a93226")
const CINNABAR_BRIGHT := Color("c94b35")
const CINNABAR_DARK := Color("6f1d16")
const GOLD := Color("c9a44f")
const INDIGO := Color("3c5366")
const MUTED := Color("7c7466")
const BONE := Color("ddd4be")

static var _dropdown_theme: Theme


## Queue focus without retaining a Control from a screen that may be closed or
## replaced before the next idle frame. Script-owned callback holds a WeakRef.
static func focus_later(control: Control) -> void:
	if is_instance_valid(control):
		_focus_if_alive.call_deferred(weakref(control))


static func _focus_if_alive(candidate: WeakRef) -> void:
	var target: Object = candidate.get_ref()
	if not is_instance_valid(target) or not target is Control:
		return
	if not target.is_inside_tree() or not target.is_visible_in_tree() or target.focus_mode == Control.FOCUS_NONE:
		return
	var ancestor: Node = target.get_parent()
	while is_instance_valid(ancestor):
		if ancestor is CanvasLayer and not ancestor.visible:
			return
		ancestor = ancestor.get_parent()
	target.grab_focus()


## This theme is applied directly to PopupMenu as well as its OptionButton.
## The popup uses its own Window theme rather than inheriting Control styling.
static func dropdown_theme() -> Theme:
	if _dropdown_theme != null:
		return _dropdown_theme
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = 18
	for control_type: String in ["OptionButton", "PopupMenu"]:
		result.set_font("font", control_type, BODY)
		result.set_font_size("font_size", control_type, 18)
		result.set_color("font_color", control_type, INK)
		result.set_color("font_hover_color", control_type, CINNABAR_DARK)
		result.set_color("font_focus_color", control_type, CINNABAR)
		result.set_color("font_pressed_color", control_type, CINNABAR)
		result.set_color("font_disabled_color", control_type, MUTED)
	var panel := StyleBoxTexture.new()
	panel.texture = load("res://assets/ui/popup_paper.svg")
	panel.set_texture_margin_all(12)
	panel.set_content_margin_all(12)
	result.set_stylebox("panel", "PopupMenu", panel)
	var hover := StyleBoxTexture.new()
	hover.texture = load("res://assets/ui/popup_hover.svg")
	hover.set_texture_margin_all(12)
	hover.set_content_margin_all(9)
	result.set_stylebox("hover", "PopupMenu", hover)
	result.set_constant("v_separation", "PopupMenu", 18)
	result.set_constant("h_separation", "PopupMenu", 12)
	result.set_constant("item_start_padding", "PopupMenu", 7)
	result.set_constant("item_end_padding", "PopupMenu", 12)
	result.set_constant("indent", "PopupMenu", 0)
	var checked: Texture2D = load("res://assets/ui/choice_seal.svg")
	var unchecked: Texture2D = load("res://assets/ui/choice_empty.svg")
	for icon: String in ["checked", "radio_checked", "checked_disabled", "radio_checked_disabled"]:
		result.set_icon(icon, "PopupMenu", checked)
	for icon: String in ["unchecked", "radio_unchecked", "unchecked_disabled", "radio_unchecked_disabled"]:
		result.set_icon(icon, "PopupMenu", unchecked)
	result.set_icon("arrow", "OptionButton", load("res://assets/ui/choice_arrow.svg"))
	result.set_constant("arrow_margin", "OptionButton", 12)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = PAPER_DARK if state == "pressed" else PAPER_LIGHT
		box.border_color = CINNABAR if state in ["hover", "focus"] else PAPER_DARK
		box.set_border_width_all(2 if state in ["hover", "focus"] else 1)
		box.set_content_margin_all(12)
		box.content_margin_right = 42
		if state == "focus":
			box.bg_color.a = 0.0
		result.set_stylebox(state, "OptionButton", box)
	_dropdown_theme = result
	return result


static func brush(text: String, size: int, color: Color = INK, outline: int = 0,
		outline_color: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", BRUSH)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func body(text: String, size: int, color: Color = INK, outline: int = 0,
		outline_color: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", BODY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rough_rect(ci: CanvasItem, rect: Rect2, fill: Color, border: Color,
		border_width: float = 2.0, seed: int = 0, jitter: float = 1.7) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + int(rect.size.x) * 17 + int(rect.size.y) * 31 + int(rect.position.x) * 7
	var pts := PackedVector2Array()
	var steps := 7
	# Top.
	for i in steps + 1:
		var t := float(i) / float(steps)
		pts.append(Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y + rng.randf_range(-jitter, jitter)))
	# Right.
	for i in steps + 1:
		var t := float(i) / float(steps)
		pts.append(Vector2(rect.end.x + rng.randf_range(-jitter, jitter), lerpf(rect.position.y, rect.end.y, t)))
	# Bottom.
	for i in steps + 1:
		var t := float(i) / float(steps)
		pts.append(Vector2(lerpf(rect.end.x, rect.position.x, t), rect.end.y + rng.randf_range(-jitter, jitter)))
	# Left.
	for i in steps + 1:
		var t := float(i) / float(steps)
		pts.append(Vector2(rect.position.x + rng.randf_range(-jitter, jitter), lerpf(rect.end.y, rect.position.y, t)))
	if fill.a > 0.001:
		ci.draw_rect(rect, fill)
	if border_width > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, border, border_width, true)
		# A second, offset pen stroke for the hand-inked edge.
		ci.draw_polyline(closed, Color(border.r, border.g, border.b, 0.25), border_width * 0.45, true)
	# Sparse paper speckles.
	for i in 7:
		var px := rng.randf_range(rect.position.x + 4.0, rect.end.x - 4.0)
		var py := rng.randf_range(rect.position.y + 4.0, rect.end.y - 4.0)
		ci.draw_circle(Vector2(px, py), rng.randf_range(0.5, 1.5), Color(INK.r, INK.g, INK.b, rng.randf_range(0.04, 0.12)))


static func rough_line(ci: CanvasItem, from: Vector2, to: Vector2, color: Color,
		width: float = 2.0, seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dir := (to - from)
	var normal := Vector2(-dir.y, dir.x).normalized()
	var pts := PackedVector2Array()
	var steps := 8
	for i in steps + 1:
		var t := float(i) / float(steps)
		pts.append(from.lerp(to, t) + normal * rng.randf_range(-1.6, 1.6))
	ci.draw_polyline(pts, color, width, true)


static func seal(ci: CanvasItem, center: Vector2, radius: float, fill: Color,
		glyph: String, glyph_color: Color, font_size: int) -> void:
	ci.draw_circle(center, radius + 2.0, Color(INK.r, INK.g, INK.b, 0.25))
	ci.draw_circle(center, radius, fill)
	ci.draw_arc(center, radius, 0, TAU, 40, INK, 2.4, true)
	var sz := BRUSH.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	ci.draw_string(BRUSH, center - Vector2(sz.x * 0.5, -font_size * 0.34), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glyph_color)


static func centered(ci: CanvasItem, text: String, center_x: float, y: float,
		font: Font, size: int, color: Color) -> void:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	ci.draw_string(font, Vector2(center_x - sz.x * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func centered_outlined(ci: CanvasItem, text: String, center_x: float, y: float,
		font: Font, size: int, color: Color, outline_size: int, outline_color: Color) -> void:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := Vector2(center_x - sz.x * 0.5, y)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, outline_color)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func cn_num(n: int) -> String:
	var digits := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if n <= 0:
		return "零"
	if n < 10:
		return digits[n]
	if n == 10:
		return "十"
	if n < 20:
		return "十" + digits[n % 10]
	if n < 100:
		var tens: String = digits[int(n / 10)]
		var ones: String = "" if n % 10 == 0 else digits[n % 10]
		return tens + "十" + ones
	return str(n)


static func wrap_text(text: String, max_units: float = 17.0) -> Array[String]:
	var lines: Array[String] = []
	for paragraph in text.split("\n"):
		var current := ""
		var count := 0.0
		for i in paragraph.length():
			var ch := paragraph.substr(i, 1)
			var w := 0.52 if ch.unicode_at(0) < 128 else 1.0
			if count + w > max_units and current != "":
				lines.append(current)
				current = ""
				count = 0.0
			current += ch
			count += w
		if current != "":
			lines.append(current)
	return lines
