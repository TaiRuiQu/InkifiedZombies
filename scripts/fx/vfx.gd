class_name VFX
extends RefCounted

## Short-lived ink effects. Everything is pooled by lifetime rather than
## hand-managed; effects are cheap primitives.

const BRUSH_FONT: Font = preload("res://assets/fonts/MaShanZheng-Regular.ttf")
const UI_FONT: Font = preload("res://assets/fonts/NotoSansSC.ttf")


static func _bound_effect(parent: Node, effect: Node, group: String, capacity: int) -> void:
	var existing := parent.get_tree().get_nodes_in_group(group)
	while existing.size() >= capacity:
		var oldest: Node = existing.pop_front()
		oldest.remove_from_group(group)
		oldest.queue_free()
	effect.add_to_group(group)


static func burst(parent: Node3D, pos: Vector3, color: Color, amount: int = 18,
		speed: float = 5.0, size: float = 0.16, lifetime: float = 0.7,
		gravity: Vector3 = Vector3(0, -9, 0)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	if Browser.is_web():
		_bound_effect(parent, p, "web_bursts", 10)
	p.one_shot = true
	p.emitting = true
	p.amount = clampi(roundi(amount * 0.55), 1, 18) if Browser.is_web() else amount
	p.lifetime = lifetime
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = gravity
	p.scale_amount_min = size * 0.45
	p.scale_amount_max = size
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	p.mesh = quad
	var mat := Ink.unlit(color, false, true)
	mat.vertex_color_use_as_albedo = true
	p.material_override = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	parent.add_child(p)
	_free_after(p, lifetime + 0.35)


static func ring(parent: Node3D, pos: Vector3, radius: float, color: Color,
		duration: float = 0.4, start_alpha: float = 0.8) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	if Browser.is_web():
		_bound_effect(parent, mi, "web_rings", 18)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 6
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := Ink.unlit(Color(color.r, color.g, color.b, start_alpha), false, false)
	mi.material_override = mat
	mi.position = pos + Vector3(0, 0.07, 0)
	mi.scale = Vector3(0.15, 0.15, 0.15)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, maxf(radius * 0.35, 0.5), radius), duration * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_delay(duration * 0.15)
	tw.chain().tween_callback(mi.queue_free)


static func tracer(parent: Node3D, from: Vector3, to: Vector3, color: Color,
		width: float = 0.016, lifetime: float = 0.07) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	var mi := MeshInstance3D.new()
	if Browser.is_web():
		_bound_effect(parent, mi, "web_tracers", 48)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := Ink.unlit(Color(color.r, color.g, color.b, 0.75), false, false)
	mi.material_override = mat
	mi.position = (from + to) * 0.5
	mi.scale = Vector3(width, width, dist)
	parent.add_child(mi)
	if dist > 0.1:
		var up := Vector3.UP
		if absf((to - from).normalized().y) > 0.98:
			up = Vector3.RIGHT
		mi.look_at(parent.to_global(to), parent.global_basis * up)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tw.tween_callback(mi.queue_free)


static func beam(parent: Node3D, from: Vector3, to: Vector3, color: Color, width: float = 0.02) -> void:
	var points: Array[Vector3] = [from]
	var segments := 4
	for i in range(1, segments):
		var t := float(i) / float(segments)
		var base := from.lerp(to, t)
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.22
		points.append(base + jitter)
	points.append(to)
	for i in points.size() - 1:
		tracer(parent, points[i], points[i + 1], color, width, 0.12)
	burst(parent, to, color, 6, 2.2, 0.1, 0.35)


static func decal(parent: Node3D, pos: Vector3, normal: Vector3, size: float,
		color: Color, variant: int = 0) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var mi := MeshInstance3D.new()
	if Browser.is_web():
		_bound_effect(parent, mi, "web_decals", 64)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = Ink.unlit(color, false, false, false, ProcTex.splat(variant))
	var up := Vector3.UP
	if absf(normal.dot(Vector3.UP)) > 0.95:
		up = Vector3.FORWARD
	var x := up.cross(normal).normalized()
	var y := normal.cross(x).normalized()
	var basis := Basis(x, y, normal).rotated(normal, randf() * TAU)
	mi.transform = Transform3D(basis, pos + normal * 0.012)
	parent.add_child(mi)
	_free_after(mi, 10.0 if Browser.is_web() else 28.0)
	return mi


static func damage_number(parent: Node3D, pos: Vector3, amount: float,
		crit: bool = false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if not Settings.get_value("damage_numbers"):
		return
	var label := Label3D.new()
	if Browser.is_web():
		_bound_effect(parent, label, "web_damage_numbers", 24)
	label.text = str(int(round(amount)))
	label.font = BRUSH_FONT if crit else UI_FONT
	label.font_size = 86 if crit else 64
	label.pixel_size = 0.0085 if crit else 0.0075
	label.modulate = Color("ffd27a") if crit else Color("f1e7cf")
	label.outline_modulate = Ink.INK
	label.outline_size = 18
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.double_sided = true
	label.fixed_size = false
	label.position = pos + Vector3(randf_range(-0.25, 0.25), randf_range(-0.1, 0.3), randf_range(-0.25, 0.25))
	parent.add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position", label.position + Vector3(0, 0.9, 0), 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.3)
	tw.tween_property(label, "outline_modulate:a", 0.0, 0.45).set_delay(0.3)
	tw.chain().tween_callback(label.queue_free)


static func muzzle_flash(parent: Node3D, pos: Vector3, color: Color, scale_size: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mat := Ink.glow(Color(color.r, color.g, color.b, 0.8), true, true)
	var mi := Ink.add_quad(parent, Vector2(0.55, 0.55) * scale_size, mat, pos, Vector3(0, 0, randf_range(0, 360)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.7, 1.7, 1.7), 0.06)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.07)
	tw.chain().tween_callback(mi.queue_free)


static func explosion(parent: Node3D, pos: Vector3, radius: float, color: Color) -> void:
	burst(parent, pos, color, 34, 9.0, 0.28, 0.9)
	ring(parent, pos, radius, color, 0.55, 0.95)
	ring(parent, pos, radius * 0.6, Color("f0e5cb"), 0.35, 0.6)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mi.mesh = sphere
	var mat := Ink.unlit(Color(color.r, color.g, color.b, 0.5), true, false)
	mi.material_override = mat
	mi.position = pos + Vector3(0, 0.3, 0)
	mi.scale = Vector3.ONE * 0.3
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.8, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


static func spawn_portal(parent: Node3D, pos: Vector3) -> void:
	burst(parent, pos + Vector3(0, 0.2, 0), Color(0.12, 0.11, 0.1, 0.45), 20, 3.5, 0.22, 0.8, Vector3(0, -2, 0))
	ring(parent, pos, 1.5, Ink.CINNABAR_DARK, 0.7, 0.55)
	ring(parent, pos, 2.2, Color(0.1, 0.1, 0.1, 0.45), 0.9, 0.4)


static func skill_cast(parent: Node3D, id: String, pos: Vector3,
		direction: Vector3, radius: float = 6.0) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var effect := Node3D.new()
	effect.name = "SpellCast_" + id
	effect.position = pos
	parent.add_child(effect)
	effect.add_to_group("spell_effects")
	match id:
		"nova":
			# Transparent brush rings leave enemy silhouettes and warnings visible.
			_spell_sigil(effect, radius * 0.72, Ink.PLAYER_TRIMS[0], "墨", 0.9)
			ring(effect, Vector3.ZERO, radius, Ink.PLAYER_TRIMS[0], 0.65, 0.7)
			ring(effect, Vector3.UP * 0.15, radius * 0.85, Ink.INK, 0.48, 0.5)
			burst(effect, Vector3.UP * 0.45, Ink.INDIGO_LIGHT, 26, 5.0, 0.14, 0.7, Vector3(0, -1.0, 0))
			for i in 12:
				var angle := TAU * float(i) / 12.0
				var radial := Vector3(cos(angle), 0, sin(angle))
				tracer(effect, radial * radius * 0.25 + Vector3.UP * 0.12,
					radial * radius * 0.9 + Vector3.UP * 0.2, Ink.PLAYER_TRIMS[0], 0.035, 0.4)
		"dash":
			var forward := Vector3(direction.x, 0, direction.z).normalized()
			if forward.length_squared() < 0.1:
				forward = Vector3.FORWARD
			var side := forward.cross(Vector3.UP)
			for i in 6:
				var offset := side * (-0.65 if i % 2 == 0 else 0.65) + Vector3.UP * (0.25 + float(i / 2) * 0.4)
				tracer(effect, offset - forward * 0.35, offset + forward * (2.8 + i * 0.2), Ink.PLAYER_TRIMS[0], 0.025, 0.32)
			burst(effect, Vector3.UP * 0.4, Ink.PLAYER_TRIMS[0], 14, 2.2, 0.08, 0.45, Vector3(0, 0.5, 0))
			ring(effect, Vector3.ZERO, 1.1, Ink.INDIGO_LIGHT, 0.35, 0.5)
		"talisman":
			var origin := Vector3.UP * 1.3 + direction.normalized() * 0.8
			_spell_glyph(effect, "符", origin, Ink.GOLD, 0.38, true)
			burst(effect, origin, Ink.GOLD, 12, 1.8, 0.055, 0.4, Vector3(0, 0.8, 0))
	_free_after(effect, 1.4)


static func talisman_impact(parent: Node3D, pos: Vector3, radius: float) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var effect := Node3D.new()
	effect.name = "TalismanBloom"
	effect.position = pos
	parent.add_child(effect)
	effect.add_to_group("spell_effects")
	_spell_sigil(effect, radius * 0.6, Ink.GOLD, "火", 0.7)
	ring(effect, Vector3.ZERO, radius, Ink.GOLD, 0.5, 0.75)
	ring(effect, Vector3.UP * 0.2, radius * 0.72, Ink.CINNABAR_BRIGHT, 0.65, 0.65)
	burst(effect, Vector3.UP * 0.3, Ink.GOLD, 28, 6.0, 0.13, 0.75, Vector3(0, 2.0, 0))
	burst(effect, Vector3.UP * 0.2, Ink.CINNABAR_BRIGHT, 16, 4.0, 0.18, 0.65, Vector3(0, -2, 0))
	_spell_glyph(effect, "焚", Vector3.UP * 0.9, Ink.GOLD, 0.55, true)
	_free_after(effect, 1.2)


static func _spell_sigil(parent: Node3D, radius: float, color: Color,
		glyph: String, duration: float) -> void:
	var seal := Node3D.new()
	seal.position.y = 0.055
	parent.add_child(seal)
	var mat := Ink.unlit(Color(color.r, color.g, color.b, 0.5))
	for scale_factor in [1.0, 0.8]:
		var torus := TorusMesh.new()
		torus.inner_radius = radius * scale_factor - 0.025
		torus.outer_radius = radius * scale_factor
		torus.rings = 48
		torus.ring_segments = 4
		var circle := MeshInstance3D.new()
		circle.mesh = torus
		circle.material_override = mat
		circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seal.add_child(circle)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var point := Vector3(cos(angle), 0, sin(angle)) * radius * 0.9
		var stroke := Ink.add_box(seal, Vector3(0.04, 0.01, radius * 0.12), color,
			point, Vector3(0, -rad_to_deg(angle), 0), {"outline": 0})
		stroke.material_override = mat
		stroke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 4:
		var angle := TAU * float(i) / 4.0
		_spell_glyph(seal, glyph, Vector3(cos(angle), 0.02, sin(angle)) * radius * 0.55, color, duration, false)
	seal.scale = Vector3.ONE * 0.65
	var tw := seal.create_tween().set_parallel(true)
	tw.tween_property(seal, "scale", Vector3.ONE, duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(seal, "rotation:y", 0.22, duration)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration * 0.65).set_delay(duration * 0.35)
	tw.chain().tween_callback(seal.queue_free)


static func _spell_glyph(parent: Node3D, glyph: String, pos: Vector3,
		color: Color, duration: float, billboard: bool) -> void:
	var label := Label3D.new()
	label.text = glyph
	label.font = BRUSH_FONT
	label.font_size = 64
	label.pixel_size = 0.008
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	if not billboard:
		label.rotation.x = -PI * 0.5
	parent.add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 0.0, duration)
	tw.tween_callback(label.queue_free)


static func slash(parent: Node3D, pos: Vector3, dir: Vector3, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 0.5)
	mi.mesh = quad
	var mat := Ink.unlit(Color(color.r, color.g, color.b, 0.7), false, true)
	mat.albedo_texture = ProcTex.brush_stroke(128, 0)
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var yaw := atan2(-dir.x, -dir.z)
	mi.rotation_degrees = Vector3(0, rad_to_deg(yaw), randf_range(-14, 14))
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.6, 1.6, 1.6), 0.18)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.chain().tween_callback(mi.queue_free)


static func pickup_glow(parent: Node3D, pos: Vector3, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mat := Ink.glow(Color(color.r, color.g, color.b, 0.5), true, true)
	var mi := Ink.add_quad(parent, Vector2(1.2, 1.2), mat, pos, Vector3.ZERO)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(2.2, 2.2, 1), 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


static func _free_after(node: Node, seconds: float) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(seconds)
	# A decal may be evicted, or its whole scene freed, before this timer fires.
	# Capturing that Node in a lambda raises an engine error before the lambda's
	# is_instance_valid guard can run. Bind a WeakRef to a static callback instead.
	timer.timeout.connect(_release_if_alive.bind(weakref(node)))


static func _release_if_alive(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if is_instance_valid(node):
		node.queue_free()


static func hit_impact(parent: Node3D, position: Vector3, normal: Vector3,
		direction: Vector3, armored: bool, critical: bool) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var color := Ink.GOLD if armored else Ink.CINNABAR
	burst(parent, position - direction * 0.025, color, 7 if not critical else 12,
		4.2 if armored else 3.0, 0.045 if armored else 0.075, 0.28, Vector3(0, -11, 0))
	# Short, outward splinters distinguish armor sparks from the ink spray.
	if armored:
		for i in 3:
			var outward := (normal + Vector3(randf_range(-0.7, 0.7), randf_range(0.1, 0.8), randf_range(-0.7, 0.7))).normalized()
			tracer(parent, position, position + outward * randf_range(0.12, 0.3), Ink.GOLD, 0.009, 0.07)


static func eject_casing(parent: Node3D, position: Vector3, right: Vector3) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	if parent.get_tree().get_nodes_in_group("spent_casings").size() >= 24:
		return
	var casing := preload("res://scripts/fx/spent_casing.gd").new()
	casing.position = position
	casing.velocity = right * randf_range(1.2, 1.9) + Vector3.UP * randf_range(1.1, 1.7)
	parent.add_child(casing)
