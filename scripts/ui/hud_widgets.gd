class_name HudWidgets
extends RefCounted

## Small hand-drawn HUD controls. Kept together so the ink language is
## consistent across the crosshair, bars and seals.


class Crosshair extends Control:
	var spread := 1.0
	var aiming := false
	var enemy := false
	var hit_timer := 0.0
	var hit_kill := false
	var hit_crit := false
	var hit_headshot := false
	const HIT_DURATION := 0.36

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		set_process(true)

	func trigger_hit(killed: bool, crit: bool, headshot: bool = false) -> void:
		var same_burst := hit_timer > HIT_DURATION - 0.10
		hit_kill = killed or (hit_kill and same_burst)
		hit_crit = crit or (hit_crit and same_burst)
		hit_headshot = headshot or (hit_headshot and same_burst)
		hit_timer = HIT_DURATION
		queue_redraw()

	func _process(delta: float) -> void:
		if hit_timer > 0.0:
			hit_timer = maxf(hit_timer - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var col := UITheme.CINNABAR_BRIGHT if enemy else UITheme.PAPER
		var gap := clampf(5.0 + spread * 5.0, 4.0, 38.0) * float(Settings.get_value("crosshair_scale"))
		var line_len := 7.0
		if aiming:
			gap = 3.0
			line_len = 3.0
		var dirs := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
		for d in dirs:
			var a: Vector2 = c + d * gap
			var b: Vector2 = c + d * (gap + line_len)
			draw_line(a, b, Color(0.06, 0.055, 0.05, 0.85), 3.4, true)
			draw_line(a, b, col, 1.5, true)
		draw_circle(c, 2.2, Color(0.06, 0.055, 0.05, 0.9))
		draw_circle(c, 1.0, col)
		if hit_timer > 0.0:
			var alpha := clampf(hit_timer / 0.16, 0.0, 1.0)
			var pop := clampf((hit_timer - 0.23) / 0.13, 0.0, 1.0)
			var mc := Color("ffe4a1") if hit_headshot or hit_crit else (Color("ee6344") if hit_kill else UITheme.PAPER_LIGHT)
			var col_hit := Color(mc, alpha)
			var r0 := 8.0 + pop * 3.0
			var r1 := (24.0 if hit_kill or hit_headshot else 20.0) + pop * 8.0
			var width := 3.2 if hit_kill or hit_headshot else 2.2
			for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var dd := d.normalized()
				draw_line(c + dd * r0, c + dd * r1, Color(UITheme.INK, alpha), width + 3.0, true)
				draw_line(c + dd * r0, c + dd * r1, col_hit, width, true)
				if hit_kill:
					var tangent := Vector2(-dd.y, dd.x)
					draw_line(c + dd * r1 - tangent * 3.5, c + dd * r1 + tangent * 3.5,
						Color(Color("ee6344"), alpha), 2.0, true)



class HealthBar extends Control:
	var health := 100.0
	var max_health := 100.0
	var shield := 0.0
	var max_shield := 0.0
	var display_health := 100.0
	var _pulse := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func set_values(h: float, mh: float, s: float, ms: float) -> void:
		health = h
		max_health = maxf(mh, 1.0)
		shield = s
		max_shield = ms
		if display_health < health:
			display_health = health
		queue_redraw()

	func _process(delta: float) -> void:
		display_health = move_toward(display_health, health, delta * maxf(max_health * 0.9, 20.0))
		_pulse += delta
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(0, 0, size.x, size.y)
		UITheme.rough_rect(self, rect, Color(0.92, 0.89, 0.81, 0.93), UITheme.INK, 2.2, 4411, 2.0)
		draw_string(UITheme.BRUSH, Vector2(14, 28), "气血", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, UITheme.INK)
		draw_string(UITheme.BODY, Vector2(0, 25), "%d / %d" % [ceili(maxf(health, 0.0)), int(max_health)],
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14.0, 15, UITheme.INK_SOFT)
		var bar := Rect2(14, 36, size.x - 28, 17)
		draw_rect(bar, Color(0.07, 0.065, 0.06, 0.92))
		var ratio := clampf(health / max_health, 0.0, 1.0)
		var ghost_ratio := clampf(display_health / max_health, 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ghost_ratio, bar.size.y)), UITheme.CINNABAR_DARK)
		var fill := UITheme.CINNABAR
		if ratio < 0.3:
			var p := 0.5 + 0.5 * sin(_pulse * 5.0)
			fill = UITheme.CINNABAR.lerp(UITheme.CINNABAR_BRIGHT, p * 0.7)
		var fw := bar.size.x * ratio
		var pts := PackedVector2Array([
			bar.position,
			bar.position + Vector2(fw, 0),
			bar.position + Vector2(fw + 2.0, bar.size.y * 0.45),
			bar.position + Vector2(fw - 1.0, bar.size.y),
			bar.position + Vector2(0, bar.size.y),
		])
		if fw > 0.5:
			draw_colored_polygon(pts, fill)
			draw_line(bar.position + Vector2(0, 2), bar.position + Vector2(fw, 2),
				Color(1.0, 0.86, 0.7, 0.25), 1.2)
		for i in range(1, int(max_health / 25.0) + 1):
			var x := bar.position.x + bar.size.x * (i * 25.0 / max_health)
			draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.1, 0.09, 0.08, 0.35), 1.0)
		draw_rect(bar, UITheme.INK, false, 1.4)
		# Shield.
		draw_string(UITheme.BODY, Vector2(14, size.y - 8), "护体", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.INK_SOFT)
		var sbar := Rect2(52, size.y - 17, size.x - 68, 8)
		draw_rect(sbar, Color(0.08, 0.08, 0.08, 0.7))
		if max_shield > 0.0:
			var sr := clampf(shield / max_shield, 0.0, 1.0)
			draw_rect(Rect2(sbar.position, Vector2(sbar.size.x * sr, sbar.size.y)), UITheme.INDIGO)
			draw_line(sbar.position + Vector2(0, 1), sbar.position + Vector2(sbar.size.x * sr, 1),
				Color(0.75, 0.84, 0.9, 0.4), 1.0)
			draw_string(UITheme.BODY, Vector2(0, size.y - 7), "%d" % ceili(shield),
				HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14.0, 11, UITheme.INDIGO)
		else:
			draw_string(UITheme.BODY, Vector2(0, size.y - 7), "—", HORIZONTAL_ALIGNMENT_RIGHT,
				size.x - 14.0, 11, UITheme.MUTED)
		draw_rect(sbar, UITheme.INK, false, 1.0)


class AmmoPanel extends Control:
	var weapon_name := "墨毫"
	var weapon_type := "手枪"
	var mag := 12
	var mag_cap := 12
	var reserve := 120
	var reserve_cap := 120
	var reloading := false
	var reload_ratio := 0.0
	var slots: Array = []
	var current_index := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func set_values(name_: String, type_: String, m: int, mc: int, r: int, rc: int,
			rl: bool, rr: float, slot_list: Array, idx: int) -> void:
		weapon_name = name_
		weapon_type = type_
		mag = m
		mag_cap = mc
		reserve = r
		reserve_cap = rc
		reloading = rl
		reload_ratio = rr
		slots = slot_list
		current_index = idx
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(0, 0, size.x, size.y)
		UITheme.rough_rect(self, rect, Color(0.92, 0.89, 0.81, 0.94), UITheme.INK, 2.2, 7731, 2.0)
		draw_string(UITheme.BRUSH, Vector2(14, 32), weapon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UITheme.INK)
		draw_string(UITheme.BODY, Vector2(0, 48), weapon_type, HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - 18.0, 11, UITheme.MUTED)
		# Weapon slot tabs.
		var count: int = slots.size()
		for i in count:
			var x := size.x - 18.0 - (count - i) * 20.0
			var tab := Rect2(x, 11.0, 16.0, 17.0)
			var is_current := i == current_index
			UITheme.rough_rect(self, tab, UITheme.CINNABAR if is_current else Color(0.92, 0.89, 0.81, 0.0),
				UITheme.INK, 1.2, 100 + i, 0.8)
			draw_string(UITheme.BODY, Vector2(tab.position.x, tab.position.y + 12), str(i + 1),
				HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 10,
				UITheme.PAPER if is_current else UITheme.INK)
		# Big magazine count.
		var low_ammo := mag <= maxi(1, int(mag_cap * 0.25))
		var mag_col := UITheme.CINNABAR if low_ammo else UITheme.INK
		draw_string(UITheme.BRUSH, Vector2(14, 86), str(mag), HORIZONTAL_ALIGNMENT_LEFT, -1, 42, mag_col)
		var mag_w := UITheme.BRUSH.get_string_size(str(mag), HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
		var sidearm := not slots.is_empty() and current_index >= 0 and current_index < slots.size() and String(slots[current_index]) == "brush_pistol"
		var reserve_text := "/ ∞" if sidearm else "/ %d" % reserve
		draw_string(UITheme.BODY, Vector2(14 + mag_w + 10, 80), reserve_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UITheme.INK_SOFT)
		if reloading:
			var rr := clampf(reload_ratio, 0.0, 1.0)
			var rb := Rect2(14, size.y - 9, size.x - 112, 6)
			draw_rect(rb, Color(0.1, 0.09, 0.08, 0.35))
			draw_rect(Rect2(rb.position, Vector2(rb.size.x * rr, rb.size.y)), UITheme.CINNABAR)
			draw_string(UITheme.BODY, Vector2(0, size.y - 12), "装填 %d%%" % roundi(rr * 100.0), HORIZONTAL_ALIGNMENT_RIGHT,
				size.x - 14.0, 14, UITheme.CINNABAR_DARK)
		elif mag <= 0:
			var caption := "%s 装填" % Settings.binding_text("reload") if reserve > 0 or sidearm else "备弹耗尽 · 切换武器"
			draw_string(UITheme.BODY, Vector2(0, size.y - 12), caption, HORIZONTAL_ALIGNMENT_RIGHT,
				size.x - 14.0, 14, UITheme.CINNABAR_DARK)


class SkillSlot extends Control:
	var icon := "爆"
	var key_label := "Q"
	var skill_name := "墨爆"
	var unlocked := false
	var cd := 0.0
	var max_cd := 8.0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func set_values(data: Dictionary) -> void:
		icon = String(data.get("icon", "?"))
		key_label = String(data.get("key", "Q"))
		skill_name = String(data.get("name", ""))
		unlocked = bool(data.get("unlocked", false))
		cd = float(data.get("cd", 0.0))
		max_cd = float(data.get("max_cd", 1.0))
		tooltip_text = "%s · %s%s" % [skill_name, key_label, " · 升级解锁" if not unlocked else ""]
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 29.0)
		var r := 25.0
		var fill := Color(0.92, 0.89, 0.81, 0.94) if unlocked else Color(0.18, 0.17, 0.15, 0.82)
		draw_circle(c + Vector2(2, 3), r + 1.0, Color(0.04, 0.035, 0.03, 0.25))
		draw_circle(c, r, fill)
		draw_arc(c, r, 0, TAU, 40, UITheme.INK, 2.2, true)
		draw_arc(c, r - 2.5, 0, TAU, 40, Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, 0.25), 1.0, true)
		var glyph_col := UITheme.INK if unlocked else UITheme.MUTED
		var sz := UITheme.BRUSH.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 27)
		draw_string(UITheme.BRUSH, c - Vector2(sz.x * 0.5, -10.0), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, glyph_col)
		# Key tab.
		var short_key := key_label.replace("鼠标左键", "M1").replace("鼠标右键", "M2").replace("鼠标中键", "M3").replace("鼠标侧键 1", "M4").replace("鼠标侧键 2", "M5")
		var tab_width := clampf(UITheme.BODY.get_string_size(short_key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8.0, 18.0, 56.0)
		var tab := Rect2(c.x - r + 1.0, c.y - r + 1.0, tab_width, 17.0)
		draw_rect(tab, UITheme.CINNABAR if unlocked else UITheme.INK_SOFT)
		draw_string(UITheme.BODY, Vector2(tab.position.x, tab.position.y + 12.0), short_key,
			HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 11, UITheme.PAPER)
		# Cooldown wedge.
		if unlocked and cd > 0.01:
			var ratio := clampf(cd / maxf(max_cd, 0.01), 0.0, 1.0)
			var pts := PackedVector2Array([c])
			var steps := 28
			for i in range(steps + 1):
				var a := -PI * 0.5 + TAU * ratio * float(i) / float(steps)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, Color(0.07, 0.06, 0.05, 0.68))
			UITheme.centered(self, "%.0f" % ceili(cd), c.x, c.y + 5.0, UITheme.BODY, 14, UITheme.PAPER)
		# Label.
		var name_col := UITheme.PAPER if unlocked else UITheme.MUTED
		UITheme.centered_outlined(self, skill_name if unlocked else "升级解锁", c.x, size.y - 4.0,
			UITheme.BODY, 11, name_col, 3, UITheme.INK)
		if unlocked and cd <= 0.01:
			draw_circle(c + Vector2(r - 5, -r + 5), 2.5, UITheme.CINNABAR_BRIGHT)


class BossBar extends Control:
	var boss_name := "墨将"
	var ratio := 1.0
	var wave := 5

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func set_values(r: float, w: int) -> void:
		ratio = clampf(r, 0.0, 1.0)
		wave = w
		queue_redraw()

	func _draw() -> void:
		var c := size.x * 0.5
		UITheme.centered_outlined(self, "墨 将 · 第 %s 波" % UITheme.cn_num(wave), c, 24,
			UITheme.BRUSH, 24, UITheme.PAPER, 8, UITheme.INK)
		var bar := Rect2(60, 33, size.x - 120, 13)
		draw_rect(bar.grow(3.0), Color(0.05, 0.045, 0.04, 0.45))
		draw_rect(bar, Color(0.1, 0.085, 0.075, 0.9))
		var fill := bar.size.x * ratio
		var col := UITheme.CINNABAR.lerp(UITheme.CINNABAR_BRIGHT, 0.35)
		draw_rect(Rect2(bar.position, Vector2(fill, bar.size.y)), col)
		draw_line(bar.position + Vector2(0, 2), bar.position + Vector2(fill, 2),
			Color(1.0, 0.82, 0.64, 0.28), 1.0)
		for i in range(1, 4):
			var x := bar.position.x + bar.size.x * i / 4.0
			draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.05, 0.045, 0.04, 0.5), 1.0)
		draw_rect(bar, UITheme.INK, false, 1.4)
		draw_circle(Vector2(36, 40), 14.0, UITheme.CINNABAR_DARK)
		draw_arc(Vector2(36, 40), 14.0, 0, TAU, 24, UITheme.INK, 1.6, true)
		UITheme.centered(self, "将", 36, 46, UITheme.BRUSH, 18, UITheme.PAPER)


class WavePanel extends Control:
	var wave := 1
	var remaining := 0
	var total := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func set_values(w: int, rem: int, tot: int) -> void:
		wave = w
		remaining = rem
		total = tot
		queue_redraw()

	func _draw() -> void:
		draw_line(Vector2(2, 4), Vector2(2, 42), UITheme.CINNABAR, 4.0, true)
		var title := "第 %s 波" % UITheme.cn_num(wave)
		draw_string_outline(UITheme.BRUSH, Vector2(14, 40), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, UITheme.INK)
		draw_string(UITheme.BRUSH, Vector2(14, 40), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UITheme.PAPER)
		var sub := "余 敌 %d" % remaining if remaining > 0 else "肃 清"
		draw_string_outline(UITheme.BODY, Vector2(16, 64), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, UITheme.INK)
		draw_string(UITheme.BODY, Vector2(16, 64), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.PAPER_DARK)
		draw_circle(Vector2(236, 26), 16.0, UITheme.CINNABAR_DARK)
		draw_arc(Vector2(236, 26), 16.0, 0, TAU, 24, UITheme.INK, 1.4, true)
		UITheme.centered(self, "潮", 236, 33, UITheme.BRUSH, 18, UITheme.PAPER)


class Banner extends Control:
	var title := ""
	var subtitle := ""
	var accent := UITheme.CINNABAR
	var t := 0.0
	var duration := 2.4
	var active := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func show_text(text_title: String, text_sub: String, color: Color = UITheme.CINNABAR, dur: float = 2.4) -> void:
		title = text_title
		subtitle = text_sub
		accent = color
		t = 0.0
		duration = dur
		active = true
		visible = true
		queue_redraw()

	func _process(delta: float) -> void:
		if not active:
			return
		t += delta
		if t > duration + 0.6:
			active = false
			visible = false
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var fade_in := clampf(t / 0.25, 0.0, 1.0)
		var fade_out := clampf((duration + 0.6 - t) / 0.6, 0.0, 1.0)
		var a := minf(fade_in, fade_out)
		var rise := (1.0 - fade_in) * 14.0 - (1.0 - fade_out) * 8.0
		var cx := size.x * 0.5
		var cy := 34.0 + rise
		# Ink wash band.
		var band := Rect2(cx - 300, cy - 30, 600, 88)
		UITheme.rough_rect(self, band, Color(0.06, 0.055, 0.05, 0.23 * a), Color(accent.r, accent.g, accent.b, 0.0), 0.0, 9182, 2.0)
		UITheme.centered_outlined(self, title, cx, cy + 34.0, UITheme.BRUSH, 56,
			Color(UITheme.PAPER.r, UITheme.PAPER.g, UITheme.PAPER.b, a), 14,
			Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, a))
		if subtitle != "":
			UITheme.centered_outlined(self, subtitle, cx, cy + 66.0, UITheme.BODY, 17,
				Color(UITheme.PAPER_DARK.r, UITheme.PAPER_DARK.g, UITheme.PAPER_DARK.b, a), 6,
				Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, a))
		draw_line(Vector2(cx - 140, cy + 46), Vector2(cx + 140, cy + 46),
			Color(accent.r, accent.g, accent.b, a * 0.85), 3.0, true)
		draw_circle(Vector2(cx - 150, cy + 46), 3.0, Color(accent.r, accent.g, accent.b, a))
		draw_circle(Vector2(cx + 150, cy + 46), 3.0, Color(accent.r, accent.g, accent.b, a))
