class_name CombatReadout
extends Control

## Confirmed combat events accumulate by short bursts (shotgun pellets share
## one readout). The text sits below the sight line, outside the hit marker.
var entries: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func push_feedback(amount: float, critical: bool, killed: bool, headshot: bool) -> void:
	if not entries.is_empty() and float(entries[0].since_hit) < 0.12:
		var entry := entries[0]
		entry.amount = float(entry.amount) + maxf(amount, 0.0)
		entry.critical = bool(entry.critical) or critical
		entry.killed = bool(entry.killed) or killed
		entry.headshot = bool(entry.headshot) or headshot
		entry.count = int(entry.count) + 1
		entry.remaining = 1.1 if bool(entry.killed) else 0.8
		entry.since_hit = 0.0
	else:
		entries.push_front({"amount": maxf(amount, 0.0), "critical": critical,
			"killed": killed, "headshot": headshot, "count": 1,
			"remaining": 1.1 if killed else 0.8, "since_hit": 0.0, "age": 0.0})
		if entries.size() > 3:
			entries.pop_back()
	queue_redraw()


func tick(delta: float) -> void:
	for index in range(entries.size() - 1, -1, -1):
		entries[index].remaining = float(entries[index].remaining) - delta
		entries[index].since_hit = float(entries[index].since_hit) + delta
		entries[index].age = float(entries[index].age) + delta
		if float(entries[index].remaining) <= 0.0:
			entries.remove_at(index)
	queue_redraw()


func _process(delta: float) -> void:
	tick(delta)


func _draw() -> void:
	var center := size * 0.5
	var numbers := bool(Settings.get_value("damage_numbers"))
	for index in entries.size():
		var entry := entries[index]
		var fade := clampf(float(entry.remaining) / 0.3, 0.0, 1.0)
		var strong := bool(entry.killed) or bool(entry.headshot) or bool(entry.critical)
		var ink := UITheme.PAPER_LIGHT
		var caption := "连中" if int(entry.count) > 1 else "命中"
		if bool(entry.critical):
			ink = Color("f4d681")
			caption = "会 心"
		if bool(entry.headshot):
			ink = Color("ffe4a1")
			caption = "破 面"
		if bool(entry.killed):
			ink = Color("ed6a4c")
			caption = "破面 · 斩杀" if bool(entry.headshot) else "斩 杀"
		if numbers:
			caption += "  %d" % roundi(float(entry.amount))
		ink.a = fade * (1.0 if index == 0 else 0.56)
		var font_size := 26 if strong and index == 0 else 19
		var pop := maxf(0.0, 1.0 - float(entry.since_hit) / 0.09) * 2.0
		var baseline := center.y + 76.0 + index * 29.0 - pop
		UITheme.centered_outlined(self, caption, center.x, baseline, UITheme.BRUSH,
			font_size, ink, 5, Color(UITheme.INK, ink.a))
		if bool(entry.killed) and index == 0:
			draw_line(Vector2(center.x - 46, baseline + 8), Vector2(center.x + 46, baseline + 8), ink, 1.6, true)
