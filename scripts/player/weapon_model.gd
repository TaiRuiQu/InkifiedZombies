class_name WeaponModel
extends Node3D

## Visual-only weapon assembly. Gameplay definitions remain in WeaponDB.
## Register a Callable(model) for a new visual without changing WeaponView.
const BUILTIN_BUILDERS := {
	"brush_pistol": "_build_pistol", "ink_shotgun": "_build_shotgun",
	"wolf_smg": "_build_smg", "cinnabar_rifle": "_build_rifle",
	"ink_launcher": "_build_launcher", "thunder_crossbow": "_build_crossbow",
}
static var custom_builders: Dictionary = {}
var muzzle: Node3D
var moving_parts: Array[Dictionary] = []
var shot_age := 10.0
var support_hand: Node3D
var support_origin := Vector3.ZERO

static func register_visual(id: String, builder: Callable) -> void:
	custom_builders[id] = builder

func build(id: String) -> void:
	if custom_builders.has(id):
		custom_builders[id].call(self)
	else:
		call(BUILTIN_BUILDERS.get(id, "_build_pistol"))
	WeaponDetails.build(self, id)

func _part(mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = Ink.view_material(color, opts)
	part.position = pos
	part.rotation_degrees = rot
	part.layers = 2
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part

func _mk_muzzle(pos: Vector3) -> void:
	muzzle = Node3D.new()
	muzzle.position = pos
	add_child(muzzle)

func register_moving(part: Node3D, motion: String, amount: Vector3) -> void:
	moving_parts.append({"part": part, "origin": part.position, "motion": motion, "amount": amount})

func animate(delta: float, reloading: bool, progress: float) -> void:
	shot_age += delta
	for item in moving_parts:
		var phase := 0.0
		if item.motion == "bolt":
			phase = maxf(0.0, 1.0 - shot_age * 9.0)
		elif item.motion == "magazine" and reloading:
			phase = sin(clampf((progress - 0.12) / 0.70, 0.0, 1.0) * PI)
		elif item.motion == "pump":
			phase = sin(clampf((shot_age - 0.10) / 0.32, 0.0, 1.0) * PI)
		item.part.position = item.origin + item.amount * phase
	if support_hand:
		var phase := sin(clampf(progress, 0.0, 1.0) * PI) if reloading else 0.0
		support_hand.position = support_origin + Vector3(-0.02, -0.17, 0.18) * phase
		support_hand.rotation.z = phase * -0.4

func _build_pistol() -> void:
	var ink := Color("1b1814")
	var dark := Color("0e0c0a")
	var wood := Color("3f2d1f")
	_part(Ink.box_mesh(Vector3(0.095, 0.21, 0.12)), wood, Vector3(0, -0.115, 0.03), Vector3(13, 0, 2))
	_part(Ink.box_mesh(Vector3(0.115, 0.1, 0.34)), ink, Vector3(0, -0.01, -0.08), Vector3.ZERO)
	var slide := _part(Ink.box_mesh(Vector3(0.1, 0.07, 0.36)), dark, Vector3(0, 0.055, -0.1), Vector3.ZERO)
	register_moving(slide, "bolt", Vector3(0, 0, 0.055))
	_part(Ink.box_mesh(Vector3(0.105, 0.015, 0.26)), Color("5c5545"), Vector3(0, 0.094, -0.1), Vector3.ZERO,
		{"outline": 0})
	_part(Ink.cylinder_mesh(0.032, 0.032, 0.3, 10), dark, Vector3(0, 0.02, -0.32), Vector3(90, 0, 0))
	_part(Ink.cylinder_mesh(0.0, 0.06, 0.17, 8), Ink.INK, Vector3(0, 0.02, -0.51), Vector3(-90, 0, 0))
	_part(Ink.cylinder_mesh(0.062, 0.062, 0.035, 8), Ink.CINNABAR, Vector3(0, 0.02, -0.43), Vector3(90, 0, 0),
		{"outline": 0.002})
	# Brush-tassel under the frame.
	_part(Ink.capsule_mesh(0.022, 0.19), Ink.CINNABAR_DARK, Vector3(-0.02, -0.14, -0.05), Vector3(0, 0, 18),
		{"outline": 0.002})
	_part(Ink.sphere_mesh(0.026), Ink.GOLD, Vector3(-0.02, -0.23, -0.05), Vector3.ZERO, {"outline": 0})
	# Paper talisman.
	_part(Ink.box_mesh(Vector3(0.075, 0.12, 0.012)), Ink.PAPER, Vector3(0.055, 0.045, -0.08), Vector3(0, 8, 4),
		{"outline": 0.002, "wobble": 0.002})
	_part(Ink.box_mesh(Vector3(0.03, 0.03, 0.008)), Ink.CINNABAR, Vector3(0.055, 0.03, -0.088), Vector3(0, 8, 4),
		{"outline": 0})
	_mk_muzzle(Vector3(0, 0.02, -0.56))


func _build_shotgun() -> void:
	var ink := Color("2a251e")
	var dark := Color("171410")
	var wood := Color("65492f")
	_part(Ink.box_mesh(Vector3(0.11, 0.16, 0.34)), wood, Vector3(0, -0.05, 0.24), Vector3(-6, 0, 0))
	_part(Ink.box_mesh(Vector3(0.17, 0.13, 0.38)), ink, Vector3(0, 0.005, 0.02), Vector3.ZERO)
	_part(Ink.box_mesh(Vector3(0.15, 0.08, 0.25)), dark, Vector3(0, -0.02, -0.29), Vector3.ZERO)
	for side in [-1, 1]:
		_part(Ink.cylinder_mesh(0.044, 0.044, 0.72, 10), dark,
			Vector3(0.048 * side, 0.055, -0.39), Vector3(90, 0, 0))
		_part(Ink.cylinder_mesh(0.05, 0.05, 0.055, 10), ink,
			Vector3(0.048 * side, 0.055, -0.72), Vector3(90, 0, 0), {"outline": 0.002})
	# Pump with carved grooves.
	var pump := _part(Ink.box_mesh(Vector3(0.18, 0.12, 0.24)), wood, Vector3(0, -0.025, -0.32), Vector3.ZERO,
		{"wash": 0.4})
	register_moving(pump, "pump", Vector3(0, 0, 0.12))
	for i in 3:
		var groove := _part(Ink.box_mesh(Vector3(0.185, 0.012, 0.02)), dark,
			Vector3(0, -0.025, -0.4 + i * 0.08), Vector3.ZERO, {"outline": 0})
		register_moving(groove, "pump", Vector3(0, 0, 0.12))
	_part(Ink.box_mesh(Vector3(0.08, 0.04, 0.035)), Ink.CINNABAR, Vector3(0, 0.125, -0.25), Vector3.ZERO,
		{"outline": 0.002})
	# Hanging paper charm.
	_part(Ink.box_mesh(Vector3(0.09, 0.2, 0.012)), Ink.PAPER, Vector3(-0.1, -0.1, 0.02), Vector3(0, 20, 8),
		{"outline": 0.002, "wobble": 0.003})
	_part(Ink.box_mesh(Vector3(0.04, 0.04, 0.008)), Ink.CINNABAR, Vector3(-0.1, -0.13, 0.01), Vector3(0, 20, 8),
		{"outline": 0})
	_mk_muzzle(Vector3(0, 0.055, -0.78))


func _build_smg() -> void:
	var ink := Color("27231d")
	var dark := Color("16130f")
	var wood := Color("4d3925")
	_part(Ink.box_mesh(Vector3(0.135, 0.18, 0.42)), ink, Vector3(0, 0, -0.02), Vector3.ZERO)
	_part(Ink.box_mesh(Vector3(0.1, 0.1, 0.22)), dark, Vector3(0, 0.055, -0.31), Vector3.ZERO)
	_part(Ink.cylinder_mesh(0.028, 0.028, 0.4, 8), dark, Vector3(0, 0.06, -0.55), Vector3(90, 0, 0))
	for i in 4:
		_part(Ink.box_mesh(Vector3(0.14, 0.014, 0.02)), Color("59503f"),
			Vector3(0, 0.095, -0.18 - i * 0.06), Vector3.ZERO, {"outline": 0})
	# Drum magazine.
	_part(Ink.cylinder_mesh(0.135, 0.135, 0.12, 14), dark, Vector3(0, -0.16, 0.0), Vector3(90, 0, 0),
		{"outline": 0.003})
	_part(Ink.cylinder_mesh(0.142, 0.142, 0.03, 14), Ink.GOLD, Vector3(0, -0.16, 0.0), Vector3(90, 0, 0),
		{"outline": 0})
	_part(Ink.box_mesh(Vector3(0.075, 0.12, 0.28)), wood, Vector3(0, -0.02, 0.31), Vector3(-4, 0, 0))
	# Bamboo foregrip.
	_part(Ink.cylinder_mesh(0.035, 0.045, 0.2, 8), Ink.JADE, Vector3(0, -0.12, -0.24), Vector3(-20, 0, 0),
		{"outline": 0.002})
	_part(Ink.box_mesh(Vector3(0.1, 0.1, 0.008)), Ink.PAPER, Vector3(0.055, -0.02, -0.02), Vector3(0, 12, 10),
		{"outline": 0.002})
	_part(Ink.box_mesh(Vector3(0.03, 0.03, 0.005)), Ink.CINNABAR, Vector3(0.055, -0.04, -0.025),
		Vector3(0, 12, 10), {"outline": 0})
	_mk_muzzle(Vector3(0, 0.06, -0.77))


func _build_rifle() -> void:
	var ink := Color("221e18")
	var dark := Color("12100c")
	var wood := Color("5c3f27")
	_part(Ink.box_mesh(Vector3(0.11, 0.17, 0.48)), wood, Vector3(0, -0.045, 0.3), Vector3(-5, 0, 0))
	_part(Ink.box_mesh(Vector3(0.13, 0.12, 0.52)), ink, Vector3(0, 0.01, 0.0), Vector3.ZERO)
	_part(Ink.cylinder_mesh(0.027, 0.027, 0.9, 10), dark, Vector3(0, 0.05, -0.63), Vector3(90, 0, 0))
	_part(Ink.box_mesh(Vector3(0.06, 0.06, 0.5)), dark, Vector3(0, 0.05, -0.55), Vector3.ZERO,
		{"outline": 0.002})
	# Open tube and collars: capped cylinders used to block the sight picture.
	scope_tube(0.055, 0.3, ink, Vector3(0, 0.135, -0.08))
	scope_tube(0.06, 0.035, dark, Vector3(0, 0.135, -0.23))
	var lens := _part(Ink.cylinder_mesh(0.045, 0.045, 0.002, 32), Ink.PAPER,
		Vector3(0, 0.135, -0.245), Vector3(90, 0, 0), {"outline": 0})
	lens.name = "ScopeGlass"
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.52, 0.85, 0.91, 0.08)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.no_depth_test = false
	lens.material_override = glass
	_part(Ink.box_mesh(Vector3(0.03, 0.05, 0.05)), ink, Vector3(0, 0.1, 0.02), Vector3.ZERO, {"outline": 0.002})
	# Bipod.
	for side in [-1, 1]:
		_part(Ink.cylinder_mesh(0.012, 0.012, 0.28, 6), dark,
			Vector3(0.05 * side, -0.03, -0.55), Vector3(0, 0, side * 18), {"outline": 0.0015})
	# Cinnabar binding.
	for i in 2:
		_part(Ink.cylinder_mesh(0.052, 0.052, 0.035, 10), Ink.CINNABAR,
			Vector3(0, 0.05, -0.3 - i * 0.25), Vector3(90, 0, 0), {"outline": 0.0015})
	_part(Ink.box_mesh(Vector3(0.1, 0.15, 0.012)), Ink.PAPER, Vector3(-0.075, -0.01, 0.15), Vector3(0, -25, 6),
		{"outline": 0.002})
	_mk_muzzle(Vector3(0, 0.05, -1.1))


func scope_tube(radius: float, length: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 32
	mesh.cap_top = false
	mesh.cap_bottom = false
	var tube := _part(mesh, color, pos, Vector3(90, 0, 0), {"outline": 0})
	tube.name = "ScopeTube"
	# Annular end faces give the open tube visible thickness around the glass.
	for side in [-1, 1]:
		var rim := TorusMesh.new()
		rim.inner_radius = radius * 0.82
		rim.outer_radius = radius
		rim.rings = 32
		rim.ring_segments = 6
		var lip := _part(rim, color, pos + Vector3(0, 0, side * length * 0.5), Vector3(90, 0, 0), {"outline": 0})
		lip.name = "ScopeRim"
	return tube


func _build_launcher() -> void:
	var ink := Color("2a251e")
	var dark := Color("15120e")
	var wood := Color("573d28")
	_part(Ink.box_mesh(Vector3(0.12, 0.16, 0.36)), wood, Vector3(0, -0.04, 0.26), Vector3(-6, 0, 0))
	_part(Ink.box_mesh(Vector3(0.15, 0.14, 0.36)), ink, Vector3(0, 0.01, 0.0), Vector3.ZERO)
	_part(Ink.cylinder_mesh(0.095, 0.095, 0.55, 14), dark, Vector3(0, 0.04, -0.33), Vector3(90, 0, 0))
	_part(Ink.cylinder_mesh(0.11, 0.11, 0.08, 14), ink, Vector3(0, 0.04, -0.59), Vector3(90, 0, 0),
		{"outline": 0.002})
	_part(Ink.cylinder_mesh(0.11, 0.11, 0.012, 14), Ink.CINNABAR, Vector3(0, 0.04, -0.635), Vector3(90, 0, 0),
		{"outline": 0})
	# Big drum.
	_part(Ink.cylinder_mesh(0.17, 0.17, 0.14, 16), dark, Vector3(0, -0.05, 0.02), Vector3(90, 0, 0),
		{"outline": 0.003})
	for i in 3:
		_part(Ink.cylinder_mesh(0.175, 0.175, 0.02, 16), Ink.GOLD,
			Vector3(0, -0.05, -0.02 + i * 0.045), Vector3(90, 0, 0), {"outline": 0})
	_part(Ink.box_mesh(Vector3(0.1, 0.2, 0.1)), wood, Vector3(0, -0.15, 0.1), Vector3(8, 0, 0))
	_part(Ink.box_mesh(Vector3(0.13, 0.015, 0.22)), Ink.CINNABAR, Vector3(0, 0.085, -0.22), Vector3.ZERO,
		{"outline": 0})
	_part(Ink.box_mesh(Vector3(0.1, 0.16, 0.012)), Ink.PAPER, Vector3(0.085, 0.02, 0.05), Vector3(0, 22, 5),
		{"outline": 0.002})
	_part(Ink.box_mesh(Vector3(0.04, 0.04, 0.008)), Ink.CINNABAR, Vector3(0.085, -0.02, 0.04),
		Vector3(0, 22, 5), {"outline": 0})
	_mk_muzzle(Vector3(0, 0.04, -0.66))


func _build_crossbow() -> void:
	var ink := Color("241f19")
	var dark := Color("14110d")
	var wood := Color("4d3726")
	_part(Ink.box_mesh(Vector3(0.08, 0.1, 0.62)), wood, Vector3(0, 0, -0.02), Vector3.ZERO)
	_part(Ink.box_mesh(Vector3(0.11, 0.07, 0.25)), ink, Vector3(0, 0.01, -0.32), Vector3.ZERO)
	for side in [-1, 1]:
		_part(Ink.box_mesh(Vector3(0.5, 0.035, 0.07)), ink,
			Vector3(0.24 * side, 0.06, 0.08), Vector3(0, side * -22, side * -6),
			{"outline": 0.0025})
		_part(Ink.box_mesh(Vector3(0.1, 0.05, 0.05)), Ink.CINNABAR,
			Vector3(0.46 * side, 0.06, 0.14), Vector3(0, side * -22, side * -6), {"outline": 0.002})
	# String.
	_part(Ink.box_mesh(Vector3(0.86, 0.012, 0.012)), Ink.PAPER_DARK, Vector3(0, 0.085, 0.26), Vector3.ZERO,
		{"outline": 0})
	# Loaded bolt.
	_part(Ink.cylinder_mesh(0.012, 0.012, 0.64, 6), dark, Vector3(0, 0.06, -0.3), Vector3(90, 0, 0),
		{"outline": 0.0015})
	_part(Ink.cylinder_mesh(0.0, 0.04, 0.14, 6), Color("8f8b7a"), Vector3(0, 0.06, -0.69), Vector3(-90, 0, 0),
		{"outline": 0.0015})
	_part(Ink.box_mesh(Vector3(0.12, 0.03, 0.1)), Ink.CINNABAR, Vector3(0, 0.1, -0.18), Vector3.ZERO,
		{"outline": 0.002})
	_part(Ink.box_mesh(Vector3(0.09, 0.12, 0.012)), Ink.PAPER, Vector3(-0.06, 0.0, 0.08), Vector3(0, -20, 5),
		{"outline": 0.002})
	_mk_muzzle(Vector3(0, 0.06, -0.82))
