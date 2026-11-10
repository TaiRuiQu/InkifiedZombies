class_name EnemyVisual
extends RefCounted

## Presentation only. Enemy owns simulation, collision, damage and lifecycle.
## Register a builder to add a model without editing the combat controller.
static var _builders: Dictionary = {}
static var _merged_meshes: Dictionary = {}
var host: Node3D
var visual: Node3D
var parts: Array[MeshInstance3D] = []
var anim: Dictionary = {}
var aura: MeshInstance3D
var type_id := "wraith"
var data: Dictionary = {}
var boss := false
var elite := false
var radius := 0.42
var _time_offset := 0.0

static func register_builder(id: String, builder: Callable) -> void:
	_builders[id] = builder


func build(enemy: Node3D) -> void:
	host = enemy
	type_id = enemy.type_id
	data = enemy.data
	boss = enemy.boss
	elite = enemy.elite
	radius = enemy.radius
	# Eight shared material phases avoid creating a material for every spawn.
	_time_offset = float(posmod(hash(type_id), 8)) * 0.5
	visual = Node3D.new()
	visual.name = "Visual"
	host.add_child(visual)
	parts.clear()
	anim.clear()

	var ink: Color = data.color
	var accent: Color = data.accent
	var glow: Color = data.glow

	var visual_id: String = String(data.get("visual_id", type_id))
	if _builders.has(visual_id):
		(_builders[visual_id] as Callable).call(self, ink, accent, glow)
	else:
		match visual_id:
			"wraith": _build_wraith(ink, accent, glow)
			"puppet": _build_puppet(ink, accent, glow)
			"brute": _build_brute(ink, accent, glow)
			"mask": _build_mask(ink, accent, glow)
			"lantern": _build_lantern(ink, accent, glow)
			"boss": _build_boss(ink, accent, glow)
			"leaper": _build_duelist(ink, accent, glow, false)
			"reaver": _build_duelist(ink, accent, glow, true)
			_: _build_wraith(ink, accent, glow)
	_add_details(visual_id)
	_batch_parts()

	# Ground contact shadow.
	var shadow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 3.1, radius * 3.1)
	shadow.mesh = quad
	var smat := Ink.unlit(Color(0.04, 0.035, 0.03, 0.42), false, false, false, ProcTex.soft_circle(64))
	shadow.material_override = smat
	shadow.rotation_degrees.x = -90.0
	shadow.position.y = 0.03
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(shadow)

	if elite:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = radius * 1.1
		tm.outer_radius = radius * 1.35
		tm.rings = 20
		tm.ring_segments = 5
		ring.mesh = tm
		ring.material_override = Ink.unlit(Color(0.75, 0.2, 0.12, 0.55), true, false)
		ring.position.y = 0.06
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(ring)
		aura = ring

	if boss:
		var aura_ring := MeshInstance3D.new()
		var tm2 := TorusMesh.new()
		tm2.inner_radius = 1.5
		tm2.outer_radius = 2.1
		tm2.rings = 30
		tm2.ring_segments = 6
		aura_ring.mesh = tm2
		aura_ring.material_override = Ink.unlit(Color(0.55, 0.12, 0.08, 0.4), true, false)
		aura_ring.position.y = 0.08
		aura_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(aura_ring)
		aura = aura_ring


func _part(mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := Ink.part(visual, mesh, color, pos, rot, _enemy_opts(opts))
	parts.append(mi)
	return mi


func _pivot(pos: Vector3, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = "Joint%d" % anim.size()
	n.position = pos
	if parent == null:
		visual.add_child(n)
	else:
		parent.add_child(n)
	return n


func _enemy_opts(extra: Dictionary = {}) -> Dictionary:
	var opts := {
		"outline": 0.0085,
		"wobble": 0.009 if boss else 0.012,
		"time": _time_offset,
		"hatch": 0.6,
		"wash": 0.45,
		"rim": 0.18,
		"pool": 0.18,
	}
	for k in extra:
		opts[k] = extra[k]
	return opts


func _build_wraith(ink: Color, accent: Color, glow: Color) -> void:
	_part(Ink.capsule_mesh(0.28, 1.05), ink, Vector3(0, 1.1, 0))
	_part(Ink.cylinder_mesh(0.22, 0.5, 0.95, 10), ink.darkened(0.15), Vector3(0, 0.58, 0))
	for i in 4:
		var a := float(i) * 90.0 + 20.0
		_part(Ink.prism_mesh(Vector3(0.24, 0.65, 0.06)), ink.darkened(0.2),
			Vector3(cos(deg_to_rad(a)) * 0.36, 0.42, sin(deg_to_rad(a)) * 0.36),
			Vector3(6, a, 8), {"outline": 0.005})
	# A narrow funeral mask, cut cheek planes and exposed lower teeth.
	_face("wraith", Vector3(0, 1.84, -0.04), Vector3(0.26, 0.31, 0.24), accent, glow)
	# Chest paper seal.
	_part(Ink.box_mesh(Vector3(0.3, 0.5, 0.02)), accent, Vector3(0, 1.25, -0.3), Vector3(0, 0, 4),
		{"outline": 0.004, "wobble": 0.005})
	_part(Ink.box_mesh(Vector3(0.12, 0.12, 0.015)), Ink.CINNABAR, Vector3(0, 1.18, -0.315), Vector3.ZERO,
		{"outline": 0})
	# Long arms.
	for side in [-1, 1]:
		var sh := _pivot(Vector3(0.37 * side, 1.52, 0))
		var arm := _part(Ink.capsule_mesh(0.075, 1.15), ink, Vector3(0, -0.54, 0), Vector3.ZERO, {"outline": 0.006})
		arm.reparent(sh, false)
		_part(Ink.sphere_mesh(0.11), ink.darkened(0.1), Vector3(0, -1.1, 0), Vector3.ZERO, {"outline": 0.004}).reparent(sh, false)
		anim["arm_l" if side < 0 else "arm_r"] = sh
	# Thin legs.
	for side in [-1, 1]:
		var hip := _pivot(Vector3(0.14 * side, 0.55, 0))
		var leg := _part(Ink.cylinder_mesh(0.06, 0.08, 0.62), ink.darkened(0.25), Vector3(0, -0.31, 0), Vector3.ZERO, {"outline": 0.004})
		leg.reparent(hip, false)
		anim["leg_l" if side < 0 else "leg_r"] = hip


func _build_puppet(ink: Color, accent: Color, glow: Color) -> void:
	_part(Ink.box_mesh(Vector3(0.54, 0.88, 0.28)), ink, Vector3(0, 1.1, 0), Vector3(0, 0, 3),
		{"outline": 0.008, "wobble": 0.016, "hatch": 0.45})
	# Folded paper skull, hollow eyes, sharp central seam and painted smile.
	_face("puppet", Vector3(0.02, 1.79, 0), Vector3(0.24, 0.285, 0.17), Ink.PAPER, glow)
	_part(Ink.prism_mesh(Vector3(0.56, 0.3, 0.46)), accent, Vector3(0.02, 2.05, 0), Vector3(0, 0, 3),
		{"outline": 0.004, "wobble": 0.002})
	# Red seal and brush character.
	_part(Ink.box_mesh(Vector3(0.17, 0.17, 0.02)), Ink.CINNABAR, Vector3(0, 1.2, -0.155), Vector3(0, 0, 7),
		{"outline": 0.002})
	_part(Ink.box_mesh(Vector3(0.02, 0.42, 0.01)), Ink.INK, Vector3(-0.12, 1.1, -0.145), Vector3(0, 0, 14), {"outline": 0})
	_part(Ink.box_mesh(Vector3(0.24, 0.02, 0.01)), Ink.INK, Vector3(0.02, 1.06, -0.145), Vector3(0, 0, -6), {"outline": 0})
	# Limbs.
	for side in [-1, 1]:
		var sh := _pivot(Vector3(0.34 * side, 1.48, 0))
		var arm := _part(Ink.capsule_mesh(0.06, 0.86), ink, Vector3(0, -0.44, 0), Vector3(0, 0, side * 3), {"outline": 0.005})
		arm.reparent(sh, false)
		_part(Ink.box_mesh(Vector3(0.12, 0.2, 0.08)), accent, Vector3(0, -0.86, 0), Vector3.ZERO, {"outline": 0.003}).reparent(sh, false)
		anim["arm_l" if side < 0 else "arm_r"] = sh
	for side in [-1, 1]:
		var hip := _pivot(Vector3(0.14 * side, 0.66, 0))
		var leg := _part(Ink.capsule_mesh(0.06, 0.66), ink, Vector3(0, -0.33, 0), Vector3.ZERO, {"outline": 0.004})
		leg.reparent(hip, false)
		anim["leg_l" if side < 0 else "leg_r"] = hip
	# Hanging thread.
	_part(Ink.cylinder_mesh(0.008, 0.008, 1.5), Ink.CINNABAR, Vector3(0.02, 2.95, 0), Vector3(0, 0, 1), {"outline": 0})
	_part(Ink.box_mesh(Vector3(0.22, 0.28, 0.012)), accent, Vector3(0.02, 2.35, 0), Vector3(0, 0, 4),
		{"outline": 0.003, "wobble": 0.008})


func _build_brute(ink: Color, accent: Color, glow: Color) -> void:
	_part(Ink.capsule_mesh(0.62, 1.5), ink, Vector3(0, 1.55, 0))
	_part(Ink.cylinder_mesh(0.5, 0.76, 0.8, 10), ink.darkened(0.12), Vector3(0, 0.6, 0))
	_part(Ink.box_mesh(Vector3(1.35, 0.32, 0.7)), Ink.INK_SOFT, Vector3(0, 2.05, 0.02), Vector3(0, 0, 0),
		{"outline": 0.007})
	for side in [-1, 1]:
		_part(Ink.box_mesh(Vector3(0.55, 0.24, 0.62)), Color("5d584b"), Vector3(0.72 * side, 2.08, 0),
			Vector3(0, 0, side * -12), {"outline": 0.007, "wash": 0.5})
		_part(Ink.box_mesh(Vector3(0.4, 0.5, 0.08)), Color("6a6455"), Vector3(0.72 * side, 1.8, -0.3),
			Vector3(0, 0, side * -8), {"outline": 0.006})
	# Heavy oni jaw, raised brow ridge, recessed eyes and long outer fangs.
	_face("brute", Vector3(0, 2.60, -0.03), Vector3(0.39, 0.40, 0.30), Color("ba5540"), glow)
	for side in [-1, 1]:
		_part(Ink.cylinder_mesh(0.0, 0.13, 0.52, 6), Color("cdbf9f"), Vector3(0.2 * side, 2.95, -0.15),
			Vector3(0, 0, side * 22), {"outline": 0.003})
	# Arms and fists.
	for side in [-1, 1]:
		var sh := _pivot(Vector3(0.82 * side, 2.0, 0))
		var arm := _part(Ink.capsule_mesh(0.17, 1.15), ink, Vector3(0, -0.55, 0), Vector3(0, 0, side * 4), {"outline": 0.006})
		arm.reparent(sh, false)
		_part(Ink.sphere_mesh(0.3), ink.darkened(0.1), Vector3(0, -1.16, 0), Vector3(1, 0.9, 1),
			{"outline": 0.006}).reparent(sh, false)
		anim["arm_l" if side < 0 else "arm_r"] = sh
	# Legs.
	for side in [-1, 1]:
		var hip := _pivot(Vector3(0.28 * side, 0.65, 0))
		var leg := _part(Ink.capsule_mesh(0.16, 0.95), ink, Vector3(0, -0.48, 0), Vector3.ZERO, {"outline": 0.005})
		leg.reparent(hip, false)
		anim["leg_l" if side < 0 else "leg_r"] = hip
	# Chest seal plates.
	_part(Ink.box_mesh(Vector3(0.4, 0.55, 0.06)), Color("5b5547"), Vector3(0, 1.55, -0.55), Vector3(0, 0, 0),
		{"outline": 0.006, "wash": 0.5})
	_part(Ink.box_mesh(Vector3(0.18, 0.36, 0.02)), Ink.PAPER, Vector3(0, 1.5, -0.59), Vector3(0, 0, 5),
		{"outline": 0.003, "wobble": 0.006})
	_part(Ink.box_mesh(Vector3(0.1, 0.1, 0.015)), Ink.CINNABAR, Vector3(0, 1.44, -0.605), Vector3(0, 0, 5),
		{"outline": 0})
	# Club in the right hand.
	var club := _pivot(Vector3(0, -1.15, 0), anim["arm_r"] as Node3D)
	anim["club"] = club
	_part(Ink.cylinder_mesh(0.08, 0.1, 2.2), Color("3c2e21"), Vector3(0, -0.7, 0), Vector3(0, 0, 0),
		{"outline": 0.005}).reparent(club, false)
	_part(Ink.box_mesh(Vector3(0.55, 0.75, 0.55)), Color("4b4031"), Vector3(0, -1.85, 0), Vector3(8, 0, 6),
		{"outline": 0.007, "wobble": 0.003}).reparent(club, false)


func _build_mask(ink: Color, accent: Color, glow: Color) -> void:
	# Floating cloak.
	_part(Ink.cylinder_mesh(0.28, 0.62, 1.3, 12), Color("1b1814"), Vector3(0, 1.1, 0.1), Vector3(4, 0, 0),
		{"outline": 0.007, "wobble": 0.01})
	for i in 5:
		var a := float(i) * 72.0
		_part(Ink.prism_mesh(Vector3(0.28, 0.8, 0.05)), Color("211d18"),
			Vector3(cos(deg_to_rad(a)) * 0.34, 0.55, sin(deg_to_rad(a)) * 0.34 + 0.1),
			Vector3(4, a, 4), {"outline": 0.004})
	# Long Noh mask: pale cheeks, pinched nose, ink eye sockets and red lip.
	_face("mask", Vector3(0, 1.97, -0.03), Vector3(0.36, 0.46, 0.245), Ink.BONE, glow)
	# Crown horns.
	for side in [-1, 1]:
		_part(Ink.cylinder_mesh(0.0, 0.07, 0.62, 5), accent, Vector3(0.26 * side, 2.42, 0), Vector3(0, 0, side * 35),
			{"outline": 0.004})
	# Long arms and claws.
	for side in [-1, 1]:
		var sh := _pivot(Vector3(0.45 * side, 1.85, 0.05))
		var arm := _part(Ink.capsule_mesh(0.07, 1.35), ink, Vector3(0, -0.65, 0), Vector3(0, 0, side * 10), {"outline": 0.005})
		arm.reparent(sh, false)
		for k in 3:
			var claw := _part(Ink.cylinder_mesh(0.0, 0.035, 0.32, 4), accent,
				Vector3((k - 1) * 0.08, -1.36, 0.04), Vector3(18, 0, (k - 1) * 14), {"outline": 0.002})
			claw.reparent(sh, false)
		anim["arm_l" if side < 0 else "arm_r"] = sh
	# Cinnabar seals painted on the mask.
	_part(Ink.box_mesh(Vector3(0.06, 0.22, 0.02)), Ink.CINNABAR, Vector3(-0.27, 1.9, -0.34), Vector3(0, 0, 12), {"outline": 0})
	_part(Ink.box_mesh(Vector3(0.06, 0.22, 0.02)), Ink.CINNABAR, Vector3(0.27, 1.9, -0.34), Vector3(0, 0, -12), {"outline": 0})


func _build_lantern(ink: Color, accent: Color, glow: Color) -> void:
	# Paper lantern body.
	_part(Ink.cylinder_mesh(0.31, 0.31, 0.62, 12), ink, Vector3(0, 1.32, 0), Vector3.ZERO,
		{"outline": 0.007, "wobble": 0.008, "wash": 0.18, "rim": 0.4})
	for i in 3:
		_part(Ink.cylinder_mesh(0.335, 0.335, 0.04, 12), Color("2a241c"), Vector3(0, 1.06 + i * 0.26, 0),
			Vector3.ZERO, {"outline": 0.003})
	_part(Ink.cylinder_mesh(0.34, 0.24, 0.1, 12), Color("2a241c"), Vector3(0, 1.66, 0), Vector3.ZERO, {"outline": 0.004})
	_part(Ink.cylinder_mesh(0.22, 0.34, 0.1, 12), Color("2a241c"), Vector3(0, 0.98, 0), Vector3.ZERO, {"outline": 0.004})
	# The lantern carries a folded theatrical paper face, lit from within.
	_face("lantern", Vector3(0, 1.33, -0.19), Vector3(0.25, 0.28, 0.12), Color("eed39a"), glow, false)
	# Flame and glow.
	_ellipsoid(0.16, Ink.CINNABAR, Vector3(0, 1.32, 0), Vector3(1, 1.3, 1),
		{"outline": 0.003, "rim": 0.4})
	var fire := _add_glow_eye(Vector3(0, 1.32, -0.02), glow, 0.13)
	fire.scale = Vector3.ONE * 1.15
	# Wisps.
	for side in [-1, 1]:
		var sh := _pivot(Vector3(0.28 * side, 1.15, 0))
		_part(Ink.capsule_mesh(0.035, 0.7), Ink.INK, Vector3(0, -0.35, 0), Vector3(0, 0, side * 14),
			{"outline": 0.002, "wobble": 0.02}).reparent(sh, false)
		anim["arm_l" if side < 0 else "arm_r"] = sh
	for side in [-1, 1]:
		_part(Ink.capsule_mesh(0.025, 0.55), Ink.INK, Vector3(0.12 * side, 0.68, 0), Vector3(0, 0, side * 6),
			{"outline": 0.002, "wobble": 0.02})
	_part(Ink.cylinder_mesh(0.006, 0.006, 0.6), Ink.CINNABAR, Vector3(0, 1.95, 0), Vector3.ZERO, {"outline": 0})
	var light := OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 1.1
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.position = Vector3(0, 1.3, 0)
	visual.add_child(light)
	anim["light"] = light


func _build_boss(ink: Color, accent: Color, glow: Color) -> void:
	# Cape behind.
	var cape := _pivot(Vector3(0, 2.2, 0.55))
	for i in 3:
		var c := _part(Ink.box_mesh(Vector3(1.9 - i * 0.2, 2.4, 0.06)), Color("242b33"),
			Vector3(0, -1.2, 0.1 + i * 0.05), Vector3(2, 0, (i - 1) * 4),
			{"outline": 0.008, "wobble": 0.012})
		c.reparent(cape, false)
	anim["cape"] = cape
	# Legs.
	for side in [-1, 1]:
		var hip := _pivot(Vector3(0.35 * side, 1.1, 0))
		var leg := _part(Ink.capsule_mesh(0.22, 1.3), ink, Vector3(0, -0.65, 0), Vector3.ZERO, {"outline": 0.007})
		leg.reparent(hip, false)
		_part(Ink.box_mesh(Vector3(0.44, 0.25, 0.7)), Color("3b352b"), Vector3(0, -1.2, -0.12), Vector3.ZERO,
			{"outline": 0.006}).reparent(hip, false)
		anim["leg_l" if side < 0 else "leg_r"] = hip
	# Torso and armor.
	_part(Ink.capsule_mesh(0.85, 1.9), ink, Vector3(0, 2.45, 0))
	_part(Ink.cylinder_mesh(0.72, 1.1, 0.95, 12), ink.darkened(0.08), Vector3(0, 1.3, 0), Vector3.ZERO,
		{"outline": 0.008, "wobble": 0.01})
	for side in [-1, 1]:
		_part(Ink.box_mesh(Vector3(0.85, 0.32, 0.85)), Color("4b4539"), Vector3(0.86 * side, 3.05, 0),
			Vector3(0, 0, side * -16), {"outline": 0.008, "wash": 0.5})
		_part(Ink.box_mesh(Vector3(0.5, 0.7, 0.1)), Color("a93226"), Vector3(0.6 * side, 2.55, -0.7),
			Vector3(0, 0, side * 6), {"outline": 0.005})
		for k in 2:
			_part(Ink.cylinder_mesh(0.0, 0.09, 0.45, 5), accent,
				Vector3((0.72 + k * 0.24) * side, 3.35, 0), Vector3(0, 0, side * 20), {"outline": 0.004})
	# Chest seal.
	_part(Ink.box_mesh(Vector3(0.9, 1.15, 0.08)), Color("3e392e"), Vector3(0, 2.5, -0.75), Vector3.ZERO,
		{"outline": 0.008, "wash": 0.5})
	_part(Ink.box_mesh(Vector3(0.35, 0.7, 0.03)), Ink.PAPER, Vector3(0, 2.55, -0.81), Vector3(0, 0, 3),
		{"outline": 0.004, "wobble": 0.006})
	_part(Ink.box_mesh(Vector3(0.18, 0.18, 0.02)), Ink.CINNABAR, Vector3(0, 2.42, -0.83), Vector3(0, 0, 3),
		{"outline": 0})
	# A gilded menpo with a sculpted nose, cheek guards and a toothed jaw.
	_face("boss", Vector3(0, 3.56, -0.12), Vector3(0.51, 0.56, 0.38), Color("c2a16a"), glow)
	for side in [-1, 1]:
		_part(Ink.cylinder_mesh(0.0, 0.18, 1.15, 6), Color("c6b78f"),
			Vector3(0.32 * side, 4.05, -0.05), Vector3(0, 0, side * 34), {"outline": 0.004})
	# Arms.
	for side in [-1, 1]:
		var sh := _pivot(Vector3(1.05 * side, 3.0, 0))
		var arm := _part(Ink.capsule_mesh(0.24, 1.6), ink, Vector3(0, -0.78, 0), Vector3(0, 0, side * 3),
			{"outline": 0.007})
		arm.reparent(sh, false)
		_part(Ink.sphere_mesh(0.34), ink.darkened(0.1), Vector3(0, -1.58, 0), Vector3(1, 0.9, 1),
			{"outline": 0.006}).reparent(sh, false)
		anim["arm_l" if side < 0 else "arm_r"] = sh
	# Halberd held in the right hand.
	var hand := _pivot(Vector3(0, -1.55, 0), anim["arm_r"] as Node3D)
	anim["halberd"] = hand
	_part(Ink.cylinder_mesh(0.08, 0.1, 3.7), Color("3a2c20"), Vector3(0.5, 0.4, 0), Vector3(0, 0, -12),
		{"outline": 0.007}).reparent(hand, false)
	_part(Ink.box_mesh(Vector3(0.12, 0.9, 0.62)), Color("8d8a7c"), Vector3(0.9, 2.25, 0), Vector3(0, 0, 25),
		{"outline": 0.007, "wash": 0.25, "rim": 0.3}).reparent(hand, false)
	_part(Ink.box_mesh(Vector3(0.05, 0.55, 0.08)), Ink.CINNABAR, Vector3(0.92, 2.25, -0.28),
		Vector3(0, 0, 25), {"outline": 0}).reparent(hand, false)
	# Elaborate back-banner.
	_part(Ink.box_mesh(Vector3(1.2, 2.2, 0.04)), Color("6f1d16"), Vector3(0, 3.1, 0.75), Vector3(3, 0, 0),
		{"outline": 0.006, "wobble": 0.01}).reparent(visual, false)


func _build_duelist(ink: Color, accent: Color, glow: Color, twin: bool) -> void:
	var torso_y := 1.40 if twin else 1.25
	var shoulder_y := 1.84 if twin else 1.62
	var shoulder_x := 0.57 if twin else 0.37
	var waist := 0.78 if twin else 0.87
	_part(Ink.capsule_mesh(0.42 if twin else 0.27, 1.17 if twin else 0.88), ink, Vector3(0, torso_y, 0))
	_part(Ink.box_mesh(Vector3(0.85 if twin else 0.58, 0.24, 0.43)), accent.darkened(0.25), Vector3(0, waist, 0))
	_face("brute" if twin else "wraith", Vector3(0, 2.10 if twin else 1.93, -0.02),
		Vector3(0.31, 0.34, 0.24) if twin else Vector3(0.22, 0.30, 0.20),
		Color("b8955e") if twin else Color("e0d7c0"), glow)
	# Distinct crown: reaver wears a broad bronze visor, leaper two swept horns.
	for side in [-1, 1]:
		if twin:
			_part(Ink.prism_mesh(Vector3(0.27, 0.39, 0.44)), accent, Vector3(side*0.28, 2.27, -0.08), Vector3(0, 0, side*-22), {"outline": 0.003})
			_part(Ink.box_mesh(Vector3(0.49, 0.24, 0.58)), accent.darkened(0.25), Vector3(side*0.54, shoulder_y, 0), Vector3(0, 0, side*-10), {"outline": 0.004})
		else:
			_part(Ink.cylinder_mesh(0.0, 0.065, 0.42, 5), accent, Vector3(side*0.15, 2.17, 0.04), Vector3(-28, 0, side*22), {"outline": 0.002})
		var arm := _pivot(Vector3(side*shoulder_x, shoulder_y, 0))
		anim["arm_l" if side < 0 else "arm_r"] = arm
		_part(Ink.capsule_mesh(0.13 if twin else 0.085, 1.02 if twin else 0.96), ink,
			Vector3(0, -0.51 if twin else -0.48, 0), Vector3.ZERO, {"outline": 0.004}).reparent(arm, false)
		_part(Ink.box_mesh(Vector3(0.25 if twin else 0.17, 0.28, 0.20)), accent,
			Vector3(0, -0.75, -0.045), Vector3.ZERO, {"outline": 0.003}).reparent(arm, false)
		_part(Ink.sphere_mesh(0.14 if twin else 0.11, 8, 4), Ink.BONE,
			Vector3(0, -1.0 if twin else -0.94, 0), Vector3.ZERO, {"outline": 0.003}).reparent(arm, false)
		var hip := _pivot(Vector3(side*0.23 if twin else side*0.17, waist, 0))
		anim["leg_l" if side < 0 else "leg_r"] = hip
		_part(Ink.capsule_mesh(0.13 if twin else 0.09, 0.81 if twin else 0.91), ink.darkened(0.12),
			Vector3(0, -0.39 if twin else -0.43, 0), Vector3.ZERO, {"outline": 0.004}).reparent(hip, false)
		_part(Ink.box_mesh(Vector3(0.25 if twin else 0.18, 0.32, 0.12)), accent.darkened(0.15),
			Vector3(0, -0.49, -0.11), Vector3.ZERO, {"outline": 0.003}).reparent(hip, false)
		_part(Ink.box_mesh(Vector3(0.28 if twin else 0.2, 0.12, 0.39)), Ink.INK,
			Vector3(0, -0.78 if twin else -0.87, -0.06), Vector3.ZERO, {"outline": 0.003}).reparent(hip, false)
		if twin or side > 0:
			var sword := _pivot(Vector3(0, -1.0 if twin else -0.94, 0), arm)
			sword.rotation_degrees.x = 72.0
			anim["sword_l" if side < 0 else "sword_r"] = sword
			if not twin:
				anim["sword"] = sword
			_part(Ink.cylinder_mesh(0.035, 0.035, 0.31, 8), Ink.CINNABAR_DARK, Vector3(0, -0.06, 0), Vector3.ZERO, {"outline": 0.002}).reparent(sword, false)
			_part(Ink.box_mesh(Vector3(0.30, 0.045, 0.15)), Ink.GOLD, Vector3(0, -0.20, 0), Vector3.ZERO, {"outline": 0.002}).reparent(sword, false)
			var blade := _duelist_blade(twin)
			_part(blade, Ink.BONE.lightened(0.05), Vector3(0, -0.22, 0), Vector3.ZERO,
				{"outline": 0.002, "wobble": 0.0, "hatch": 0.1, "wash": 0.14}).reparent(sword, false)
			for wrap in 3:
				_part(Ink.box_mesh(Vector3(0.075, 0.018, 0.075)), Ink.GOLD, Vector3(0, -0.16 + wrap*0.065, 0), Vector3.ZERO, {"outline": 0}).reparent(sword, false)
	# Layered breast plates and tied waist ribbons remain separate from hit volumes.
	for row in 3:
		_part(Ink.box_mesh(Vector3(0.65 if twin else 0.41, 0.17, 0.07)), accent.darkened(0.18),
			Vector3(0, torso_y-0.2+row*0.2, -0.39 if twin else -0.25), Vector3.ZERO, {"outline": 0.003})
		for side in [-1, 1]:
			_part(Ink.sphere_mesh(0.02, 6, 3), Ink.GOLD,
				Vector3(side*(0.24 if twin else 0.15), torso_y-0.16+row*0.2, -0.435 if twin else -0.295), Vector3.ZERO, {"outline": 0})
	for side in [-1, 1]:
		_part(Ink.prism_mesh(Vector3(0.18, 0.65, 0.035)), Ink.CINNABAR_DARK,
			Vector3(side*0.28, waist-0.22, 0.22), Vector3(10, 0, side*18), {"outline": 0.003})
	_band(0.44 if twin else 0.30, 0.04, Vector3(0, waist+0.12, 0), Ink.GOLD)
	_glyph(Vector3(0, torso_y+0.2, -0.44 if twin else -0.3), 0.15, Ink.PAPER)


func _duelist_blade(twin: bool) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 1.15 if twin else 1.40
	var profile := [Vector2(-0.045, 0), Vector2(0.08, 0), Vector2(0.14 if twin else 0.09, -length*0.70),
		Vector2(0.29 if twin else 0.16, -length), Vector2(-0.055, -length*0.82)]
	for side in [-1.0, 1.0]:
		for index in range(1, profile.size()-1):
			var indices := [0, index, index+1] if side < 0 else [0, index+1, index]
			for vertex in indices:
				var point: Vector2 = profile[vertex]
				tool.add_vertex(Vector3(point.x, point.y, side*0.025))
	for index in profile.size():
		var next := (index+1)%profile.size()
		var a: Vector2 = profile[index]
		var b: Vector2 = profile[next]
		for point in [Vector3(a.x,a.y,-0.025),Vector3(b.x,b.y,-0.025),Vector3(a.x,a.y,0.025),Vector3(a.x,a.y,0.025),Vector3(b.x,b.y,-0.025),Vector3(b.x,b.y,0.025)]:
			tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()


func _face(style: String, center: Vector3, proportions: Vector3, color: Color, glow: Color,
		include_skull: bool = true) -> void:
	var head := _pivot(center)
	head.name = "SculptedHead"
	anim["head"] = head
	var face_geometry := EnemyFaceMesh.meshes(style)
	var colors := {"bone": color, "ridge": color.lightened(0.16), "sockets": Color("171413"),
		"lips": Ink.CINNABAR_DARK if style != "boss" else Color("702a20"), "teeth": Color("f0e7cc")}
	if include_skull:
		var skull_part := _part(EnemyFaceMesh.skull(), color.darkened(0.32), Vector3.ZERO, Vector3.ZERO,
			{"outline": 0.0025, "wobble": 0.0, "wash": 0.13, "hatch": 0.14, "grain": 0.1})
		skull_part.scale = proportions
		skull_part.reparent(head, false)
	for group in face_geometry:
		var surface := _part(face_geometry[group], colors[group], Vector3(0, 0, -proportions.z * 0.54), Vector3.ZERO,
			{"outline": 0.001 if group == "bone" else 0.0, "wobble": 0.0, "wash": 0.10,
			"hatch": 0.08, "grain": 0.08, "pool": 0.06, "rim": 0.09})
		surface.scale = proportions
		surface.reparent(head, false)
	for side in [-1, 1]:
		# Narrow luminous irises sit inside the eye cavities, not on the forehead.
		var eye := _part(Ink.sphere_mesh(1.0, 6, 3), glow, Vector3(side * proportions.x * 0.43,
			proportions.y * 0.235, -proportions.z * 1.72), Vector3.ZERO,
			{"outline": 0.0, "wobble": 0.0, "wash": 0.0, "hatch": 0.0, "grain": 0.0, "rim": 0.45})
		eye.scale = Vector3(proportions.x * 0.16, proportions.y * 0.065, proportions.z * 0.08)
		eye.reparent(head, false)


func _add_glow_eye(pos: Vector3, color: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(mi)
	return mi


func _ellipsoid(size: float, color: Color, pos: Vector3, stretch: Vector3,
		opts: Dictionary = {}) -> MeshInstance3D:
	var part := _part(Ink.sphere_mesh(size), color, pos, Vector3.ZERO, opts)
	part.scale = stretch
	return part


func _detail(mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		parent: Node3D = null) -> MeshInstance3D:
	var part := _part(mesh, color, pos, rot,
		{"outline": 0.002, "wobble": 0.002, "hatch": 0.4, "wash": 0.26})
	if parent:
		part.reparent(parent, false)
	return part


func _band(size: float, width: float, pos: Vector3, color: Color,
		parent: Node3D = null, rot: Vector3 = Vector3.ZERO) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = size - width
	torus.outer_radius = size
	torus.rings = 12
	torus.ring_segments = 4
	_detail(torus, color, pos, rot, parent)


func _glyph(pos: Vector3, size: float, color: Color = Ink.CINNABAR,
		parent: Node3D = null) -> void:
	# Deliberately irregular seal strokes, with an open centre and long tail.
	_detail(Ink.box_mesh(Vector3(size * 0.15, size, 0.008)), color, pos,
		Vector3(0, 0, -5), parent)
	_detail(Ink.box_mesh(Vector3(size * 0.85, size * 0.14, 0.008)), color,
		pos + Vector3(0, size * 0.22, -0.003), Vector3(0, 0, 7), parent)
	_detail(Ink.box_mesh(Vector3(size * 0.65, size * 0.13, 0.008)), color,
		pos + Vector3(0, -size * 0.12, -0.003), Vector3(0, 0, -8), parent)


func _joint_details(arm_length: float, leg_length: float, width: float,
		color: Color, finger_count: int = 3) -> void:
	for side in [-1, 1]:
		var arm := anim.get("arm_l" if side < 0 else "arm_r") as Node3D
		if arm:
			_band(width * 1.15, width * 0.25, Vector3(0, -arm_length * 0.45, 0), color, arm)
			for k in finger_count:
				_detail(Ink.cylinder_mesh(0.006, width * 0.2, width * 2.5, 5), color,
					Vector3((float(k) - float(finger_count - 1) * 0.5) * width * 0.6,
					-arm_length - width * 0.95, -width * 0.25),
					Vector3(-14, 0, (float(k) - 1.0) * 8.0), arm)
		var leg := anim.get("leg_l" if side < 0 else "leg_r") as Node3D
		if leg:
			_detail(Ink.box_mesh(Vector3(width * 2.0, width * 1.15, width * 3.8)), color,
				Vector3(0, -leg_length, -width * 0.7), Vector3.ZERO, leg)


func _add_details(id: String) -> void:
	match id:
		"wraith":
			# Frayed funeral collar and a bound, visibly broken face.
			_band(0.27, 0.07, Vector3(0, 1.58, 0), Ink.ASH_DARK)
			for side in [-1, 1]:
				_detail(Ink.prism_mesh(Vector3(0.2, 0.43, 0.09)), Ink.INDIGO,
					Vector3(side * 0.23, 1.43, -0.2), Vector3(0, 0, side * -18))
				_detail(Ink.box_mesh(Vector3(0.025, 0.17, 0.012)), Ink.CINNABAR_DARK,
					Vector3(side * 0.17, 1.72, -0.23), Vector3(0, 0, side * 14))
				for k in 3:
					_detail(Ink.box_mesh(Vector3(0.065, 0.012, 0.008)), Ink.BONE,
						Vector3(side * 0.26, 0.8 + k * 0.13, -0.28), Vector3(0, 0, side * 25))
			_band(0.32, 0.024, Vector3(0, 0.82, 0), Ink.OCHRE_DARK)
			_glyph(Vector3(0, 1.34, -0.318), 0.14)
			_joint_details(1.1, 0.57, 0.065, Ink.ASH)
		"puppet":
			# Accordion paper edges, joint pins, stitches and folded hands.
			for side in [-1, 1]:
				for k in 4:
					_detail(Ink.box_mesh(Vector3(0.045, 0.16, 0.29)), Ink.BONE,
						Vector3(side * 0.275, 0.8 + k * 0.2, 0), Vector3(0, 0, side * (12 if k % 2 == 0 else -12)))
				_detail(Ink.cylinder_mesh(0.045, 0.045, 0.025, 8), Ink.OCHRE,
					Vector3(side * 0.33, 1.49, -0.06), Vector3(90, 0, 0))
				_detail(Ink.box_mesh(Vector3(0.07, 0.018, 0.009)), Ink.CINNABAR,
					Vector3(side * 0.12, 1.74, -0.172), Vector3(0, 0, side * 27))
			for k in 4:
				_detail(Ink.box_mesh(Vector3(0.07, 0.014, 0.012)), Ink.INK,
					Vector3(0.17, 0.83 + k * 0.17, -0.148), Vector3(0, 0, 25))
			_detail(Ink.box_mesh(Vector3(0.57, 0.055, 0.3)), Ink.CINNABAR_DARK, Vector3(0, 0.73, 0))
			_glyph(Vector3(0.02, 2.35, -0.012), 0.14, Ink.PAPER)
			_joint_details(0.86, 0.63, 0.045, Ink.CINNABAR_DARK, 2)
		"brute":
			# Broad laminated iron plates, copper rivets and a reinforced kanabo.
			for row in 3:
				for col in 3:
					var p := Vector3((col - 1) * 0.25, 1.22 + row * 0.23, -0.59)
					_detail(Ink.box_mesh(Vector3(0.235, 0.19, 0.045)), Ink.ASH_DARK, p)
					_detail(Ink.sphere_mesh(0.025, 6, 3), Ink.OCHRE, p + Vector3(0, 0.05, -0.035))
			for side in [-1, 1]:
				var arm := anim["arm_l" if side < 0 else "arm_r"] as Node3D
				_detail(Ink.box_mesh(Vector3(0.35, 0.48, 0.16)), Ink.ASH_DARK,
					Vector3(0, -0.75, -0.15), Vector3.ZERO, arm)
				var leg := anim["leg_l" if side < 0 else "leg_r"] as Node3D
				_detail(Ink.box_mesh(Vector3(0.3, 0.4, 0.12)), Ink.OCHRE_DARK,
					Vector3(0, -0.48, -0.14), Vector3.ZERO, leg)
			var club := anim["club"] as Node3D
			for k in 3:
				_band(0.33, 0.045, Vector3(0, -1.57 - k * 0.24, 0), Ink.ASH, club)
				for side in [-1, 1]:
					_detail(Ink.cylinder_mesh(0, 0.07, 0.2, 5), Ink.OCHRE,
						Vector3(side * 0.34, -1.57 - k * 0.24, 0), Vector3(0, 0, side * -90), club)
			_joint_details(1.16, 0.9, 0.14, Ink.ASH_DARK)
		"mask":
			# Bone face with a pronounced nose, cracks and a floating ritual halo.
			_band(0.63, 0.018, Vector3(0, 2.03, 0.14), Ink.OCHRE, null, Vector3(90, 0, 0))
			for side in [-1, 1]:
				_detail(Ink.box_mesh(Vector3(0.12, 0.025, 0.02)), Ink.INK,
					Vector3(side * 0.16, 2.07, -0.37), Vector3(0, 0, side * -14))
				_detail(Ink.box_mesh(Vector3(0.012, 0.19, 0.008)), Ink.INK,
					Vector3(side * 0.19, 1.88, -0.35), Vector3(0, 0, side * 23))
			for k in 7:
				var angle := PI * float(k) / 6.0
				_detail(Ink.sphere_mesh(0.045, 6, 3), Ink.OCHRE_DARK,
					Vector3(cos(angle) * 0.36, 1.48 - sin(angle) * 0.14, -0.23))
			_glyph(Vector3(0, 2.2, -0.3), 0.11)
			var charms: Array[Node3D] = []
			for side in [-1, 1]:
				var charm := _pivot(Vector3(side * 0.44, 1.45, -0.1))
				_detail(Ink.box_mesh(Vector3(0.14, 0.55, 0.014)), Ink.PAPER,
					Vector3(0, -0.25, 0), Vector3(0, 0, side * 8), charm)
				_glyph(Vector3(0, -0.21, -0.012), 0.17, Ink.CINNABAR, charm)
				charms.append(charm)
			anim["charms"] = charms
		"lantern":
			# Bamboo ribs, scorched paper panels, a carrying loop and loose tassels.
			for k in 8:
				var angle := TAU * float(k) / 8.0
				_detail(Ink.box_mesh(Vector3(0.017, 0.58, 0.017)), Ink.OCHRE_DARK,
					Vector3(cos(angle) * 0.31, 1.32, sin(angle) * 0.31))
			_band(0.145, 0.018, Vector3(0, 1.82, 0), Ink.ASH_DARK, null, Vector3(90, 0, 0))
			for k in 5:
				_detail(Ink.prism_mesh(Vector3(0.09, 0.37, 0.025)), Ink.CINNABAR_DARK,
					Vector3((k - 2) * 0.045, 0.79, -0.05), Vector3(0, 0, (k - 2) * 11))
			_detail(Ink.box_mesh(Vector3(0.04, 0.18, 0.015)), Ink.INK,
				Vector3(-0.16, 1.15, -0.27), Vector3(0, 0, -25))
			_detail(Ink.box_mesh(Vector3(0.025, 0.13, 0.015)), Ink.INK,
				Vector3(0.2, 1.5, -0.245), Vector3(0, 0, 18))
			_detail(Ink.prism_mesh(Vector3(0.1, 0.25, 0.06)), Ink.CINNABAR,
				Vector3(0, 1.81, 0.03), Vector3(0, 0, 8))
			_glyph(Vector3(0, 1.17, -0.32), 0.1, Ink.CINNABAR)
		"boss":
			# Tiered lamellar harness, gilded crest, sash and a shaped halberd blade.
			for row in 4:
				for col in 4:
					var p := Vector3((col - 1.5) * 0.27, 1.92 + row * 0.25, -0.8)
					_detail(Ink.box_mesh(Vector3(0.25, 0.21, 0.045)), Ink.OCHRE_DARK, p)
					_detail(Ink.sphere_mesh(0.025, 6, 3), Ink.GOLD, p + Vector3(0, 0.06, -0.03))
			_band(0.51, 0.09, Vector3(0, 3.14, 0), Ink.OCHRE)
			_detail(Ink.prism_mesh(Vector3(0.45, 0.75, 0.13)), Ink.GOLD,
				Vector3(0, 4.07, 0), Vector3(0, 0, 0))
			_detail(Ink.box_mesh(Vector3(0.24, 1.6, 0.05)), Ink.CINNABAR_DARK,
				Vector3(0.42, 1.32, -0.72), Vector3(0, 0, -8))
			for side in [-1, 1]:
				var arm := anim["arm_l" if side < 0 else "arm_r"] as Node3D
				for row in 3:
					_detail(Ink.box_mesh(Vector3(0.48, 0.2, 0.13)), Ink.OCHRE_DARK,
						Vector3(0, -0.77 - row * 0.22, -0.22), Vector3.ZERO, arm)
				_detail(Ink.sphere_mesh(0.12, 8, 4), Ink.BONE,
					Vector3(side * 0.87, 3.16, -0.34))
			var halberd := anim["halberd"] as Node3D
			_detail(Ink.prism_mesh(Vector3(0.14, 1.18, 0.9)), Ink.ASH,
				Vector3(0.94, 2.36, 0), Vector3(0, 0, 25), halberd)
			for k in 6:
				_band(0.11, 0.02, Vector3(0.48 + k * 0.018, 0.1 + k * 0.08, 0),
					Ink.CINNABAR, halberd)
			_glyph(Vector3(0, 2.62, -0.84), 0.31)
			_joint_details(1.58, 1.2, 0.18, Ink.ASH_DARK)


func _batch_parts() -> void:
	# Merge rigid pieces by joint + material. Detail never adds one draw call
	# per rivet, stitch or finger, and generated meshes are reused across spawns.
	var groups: Dictionary = {}
	for part in parts:
		var key := "%d:%d" % [part.get_parent().get_instance_id(), part.material_override.get_instance_id()]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(part)
	var merged: Array[MeshInstance3D] = []
	var index := 0
	for key in groups:
		var group: Array = groups[key]
		if group.size() == 1:
			merged.append(group[0])
			index += 1
			continue
		var first := group[0] as MeshInstance3D
		var visual_id: String = String(data.get("visual_id", type_id))
		var cache_key := "%s:%s:%d" % [type_id, visual_id, index]
		var mesh: ArrayMesh
		if _merged_meshes.has(cache_key) and not _builders.has(visual_id):
			mesh = _merged_meshes[cache_key]
		else:
			var surface := SurfaceTool.new()
			for part: MeshInstance3D in group:
				surface.append_from(part.mesh, 0, part.transform)
			mesh = surface.commit()
			if not _builders.has(visual_id):
				_merged_meshes[cache_key] = mesh
		var combined := MeshInstance3D.new()
		combined.name = "PaintedDetail%d" % index
		combined.mesh = mesh
		combined.material_override = first.material_override
		first.get_parent().add_child(combined)
		for part: MeshInstance3D in group:
			part.get_parent().remove_child(part)
			part.free()
		merged.append(combined)
		index += 1
	parts = merged
