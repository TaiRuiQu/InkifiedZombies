class_name DamageIndicator
extends Control

## World-space incoming hits remain readable as the player turns. This is a
## positional warning, independent of camera shake or full-screen flashing.
const LIFETIME := 2.3
const MAX_DIRECTIONS := 4
const MERGE_DOT := 0.9063078 # 25 degrees.
var observer: Node3D
var view: Node3D
var entries: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func bind(origin_node: Node3D, view_node: Node3D) -> void:
	observer = origin_node
	view = view_node


func direction_for(source: Vector3) -> Vector2:
	if not is_instance_valid(observer) or not is_instance_valid(view):
		return Vector2.ZERO
	if not is_finite(source.x) or not is_finite(source.y) or not is_finite(source.z):
		return Vector2.ZERO
	var incoming := source - observer.global_position
	incoming.y = 0.0
	if incoming.length_squared() < 0.001:
		return Vector2.ZERO
	incoming = incoming.normalized()
	var forward := -view.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return Vector2.ZERO
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	return Vector2(incoming.dot(right), -incoming.dot(forward)).normalized()


func push_hit(amount: float, source: Vector3, shield_hit: bool) -> void:
	if amount <= 0.0:
		return
	var direction := direction_for(source)
	for entry in entries:
		var old_direction := direction_for(entry.source)
		var same_direction := direction == Vector2.ZERO and old_direction == Vector2.ZERO
		if direction != Vector2.ZERO and old_direction != Vector2.ZERO:
			same_direction = direction.dot(old_direction) >= MERGE_DOT
		if same_direction and bool(entry.shield) == shield_hit:
			entry.source = source
			entry.amount = minf(float(entry.amount) + amount, 999.0)
			entry.remaining = LIFETIME
			entry.age = 0.0
			queue_redraw()
			return
	entries.append({"source": source, "shield": shield_hit, "amount": amount,
		"remaining": LIFETIME, "age": 0.0})
	if entries.size() > MAX_DIRECTIONS:
		var oldest := 0
		for index in entries.size():
			if float(entries[index].age) > float(entries[oldest].age):
				oldest = index
		entries.remove_at(oldest)
	queue_redraw()


func tick(delta: float) -> void:
	for index in range(entries.size() - 1, -1, -1):
		entries[index].remaining = float(entries[index].remaining) - delta
		entries[index].age = float(entries[index].age) + delta
		if float(entries[index].remaining) <= 0.0:
			entries.remove_at(index)
	if not entries.is_empty():
		queue_redraw()
	elif delta > 0.0:
		queue_redraw()


func _process(delta: float) -> void:
	tick(delta)


func _draw() -> void:
	var center := size * 0.5
	var radius := clampf(minf(size.x, size.y) * 0.165, 110.0, 164.0)
	for entry in entries:
		var direction := direction_for(entry.source)
		var fade := clampf(float(entry.remaining) / 0.8, 0.0, 1.0)
		var ink := Color("8ec5e5") if bool(entry.shield) else Color("df5138")
		ink.a = fade * 0.96
		var width := 5.5 + minf(float(entry.amount) * 0.08, 4.5)
		if direction == Vector2.ZERO:
			for axis: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
				_draw_mark(center, axis, radius + 22.0, ink, width * 0.7, 0.1)
			var text := "护体受击" if bool(entry.shield) else "受到攻击"
			UITheme.centered_outlined(self, text, center.x, center.y + radius + 64.0,
				UITheme.BRUSH, 20, ink, 4, Color(UITheme.INK, fade))
			continue
		_draw_mark(center, direction, radius, ink, width, 0.24)
		var caption := _caption(direction)
		var text := "%s · 护体" % caption if bool(entry.shield) else caption
		var label_position := center + direction * (radius + 40.0)
		UITheme.centered_outlined(self, text, label_position.x, label_position.y + 7.0,
			UITheme.BRUSH, 21, ink, 4, Color(UITheme.INK, fade))


func _draw_mark(center: Vector2, direction: Vector2, radius: float, color: Color,
		width: float, half_angle: float) -> void:
	var angle := direction.angle()
	draw_arc(center, radius, angle - half_angle, angle + half_angle, 14,
		Color(UITheme.INK, color.a * 0.88), width + 4.0, true)
	draw_arc(center, radius, angle - half_angle, angle + half_angle, 14, color, width, true)
	var tangent := Vector2(-direction.y, direction.x)
	var tip := center + direction * (radius - 13.0)
	var base := center + direction * (radius - 1.0)
	var triangle := PackedVector2Array([tip, base + tangent * 8.0, base - tangent * 8.0])
	draw_colored_polygon(triangle, color)
	var border := triangle.duplicate()
	border.append(triangle[0])
	draw_polyline(border, Color(UITheme.INK, color.a), 1.3, true)


func _caption(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "右侧" if direction.x > 0.0 else "左侧"
	return "后方" if direction.y > 0.0 else "前方"
