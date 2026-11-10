class_name MapDetails
extends Node3D

## Static decorative meshes are batched by geometry/material. The pass never
## adds collision: small trim cannot snag a player or block a spawn lane.
var _batches: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _roof: ArrayMesh
const STONE := Color("79786a")
const STONE_DARK := Color("414943")
const WOOD := Color("514234")
const BRASS := Color("a38a57")
const MOSS := Color("475c49")

func build(arena: MapBuilder, definition: MapDefinition) -> void:
	_rng.seed = definition.seed_value + 77
	_roof = _roof_mesh()
	for gate in arena.get_children():
		if String(gate.name).begins_with("Gate_"):
			_gate(gate.transform)
	_wall_footings(arena)
	_processional_path()
	_well(definition.well_position)
	_monument(definition.monument_position)
	for p in definition.pillar_positions:
		_pillar(p)
	_props()
	_banners()
	_torii()
	_nature()
	if definition.night:
		_night_garden()
	_flush()

func _add(mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale_v := Vector3.ONE, parent := Transform3D.IDENTITY) -> void:
	var key := "%s|%s" % [mesh.get_instance_id(), color.to_html()]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "color": color, "transforms": []}
	var basis := Basis.from_euler(rot * (PI / 180.0)).scaled(scale_v)
	_batches[key].transforms.append(parent * Transform3D(basis, pos))

func _box(size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO, parent := Transform3D.IDENTITY) -> void:
	_add(Ink.box_mesh(size), color, pos, rot, Vector3.ONE, parent)

func _cyl(radius: float, height: float, color: Color, pos: Vector3, rot := Vector3.ZERO, parent := Transform3D.IDENTITY) -> void:
	_add(Ink.cylinder_mesh(radius, radius, height, 10), color, pos, rot, Vector3.ONE, parent)

func _flush() -> void:
	for item: Dictionary in _batches.values():
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = item.mesh
		mesh.instance_count = item.transforms.size()
		for i in mesh.instance_count:
			mesh.set_instance_transform(i, item.transforms[i])
		var batch := MultiMeshInstance3D.new()
		batch.name = "DetailBatch_%d" % get_child_count()
		batch.multimesh = mesh
		batch.material_override = Ink.surface(item.color, {"outline": 0, "wobble": 0, "wash": 0.20, "hatch": 0.15, "rim": 0.06})
		batch.visibility_range_end = 85.0
		batch.visibility_range_end_margin = 8.0
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
	_batches.clear()

func _gate(t: Transform3D) -> void:
	# Curved, overhanging roof silhouette with paired barrel-tile slopes.
	_add(_roof, STONE_DARK, Vector3(0, 3.93, 0), Vector3.ZERO, Vector3.ONE, t)
	for i in 25:
		var z := -2.98 + i * 0.249
		for side in [-1, 1]:
			_cyl(0.043, 1.35, STONE, Vector3(side * 0.56, 4.25, z), Vector3(0, 0, side * 64), t)
			_cyl(0.060, 0.065, STONE_DARK, Vector3(side * 1.23, 4.10, z), Vector3(0, 0, 90), t)
		# Ridge caps accent the summit without a solid flat slab.
		_cyl(0.074, 0.20, STONE_DARK, Vector3(0, 4.53, z), Vector3(90, 0, 0), t)
	for z in [-2.35, 2.35]:
		_box(Vector3(0.42, 0.18, 0.42), STONE, Vector3(0, 0.20, z), Vector3.ZERO, t)
		_box(Vector3(0.40, 0.12, 0.40), BRASS.darkened(0.3), Vector3(0, 3.30, z), Vector3.ZERO, t)
		for y in [0.42, 0.63]:
			_box(Vector3(0.33, 0.08, 0.33), Ink.INK_SOFT, Vector3(0, y, z), Vector3.ZERO, t)
		for k in 3:
			_box(Vector3(0.14 + k * 0.15, 0.12, 0.30 + k * 0.12), WOOD, Vector3(0, 3.57 + k * 0.12, z), Vector3.ZERO, t)
		for side in [-1, 1]:
			_box(Vector3(0.035, 1.65, 0.055), Color("887052"), Vector3(side * 0.17, 1.9, z - 0.07), Vector3(0, 0, 2), t)
			_cyl(0.037, 0.025, BRASS, Vector3(side * 0.17, 2.90, z), Vector3(0, 0, 90), t)
	# Eave corner tips, braces and a tension rope.
	for side in [-1, 1]:
		_box(Vector3(0.30, 0.13, 0.74), STONE_DARK, Vector3(0, 4.56, side * 3.12), Vector3(side * 15, 0, 0), t)
		_box(Vector3(0.15, 0.90, 0.15), WOOD, Vector3(0, 3.1, side * 2.05), Vector3(side * 42, 0, 0), t)
		for k in 3:
			_box(Vector3(0.035, 0.23, 0.10), Ink.PAPER, Vector3(-0.17, 2.95 - k * 0.19, side * (0.72 + k * 0.15)), Vector3(k * 8, 0, 0), t)
	_cyl(0.025, 4.3, BRASS.darkened(0.4), Vector3(-0.16, 3.0, 0), Vector3(90, 0, 0), t)

func _roof_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [Vector2(-1.28, 0.16), Vector2(-1.0, 0.03), Vector2(-0.72, 0.13), Vector2(0, 0.60), Vector2(0.72, 0.13), Vector2(1.0, 0.03), Vector2(1.28, 0.16)]
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		var p0 := Vector3(a.x, a.y, -3.12)
		var p1 := Vector3(b.x, b.y, -3.12)
		var p2 := Vector3(b.x, b.y, 3.12)
		var p3 := Vector3(a.x, a.y, 3.12)
		for v in [p0, p2, p1, p0, p3, p2]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _wall_footings(arena: MapBuilder) -> void:
	for i in 32:
		var a := TAU * float(i) / 32.0
		if arena._near_gate(a, 6.2):
			continue
		var p := Vector3(cos(a), 0, sin(a)) * 27.3
		var t := Transform3D(Basis(Vector3.UP, -a), p)
		_box(Vector3(0.55, 0.22, 5.45), STONE_DARK, Vector3(0, 0.11, 0), Vector3.ZERO, t)
		_box(Vector3(0.14, 0.09, 5.30), STONE, Vector3(-0.30, 0.32, 0), Vector3.ZERO, t)
		for k in 6:
			_box(Vector3(0.06, 0.065, 0.73), MOSS, Vector3(-0.28, 0.06, -2.3 + k * 0.88), Vector3(0, k * 9, 0), t)
		for k in 3:
			_box(Vector3(0.018, 0.40, 0.035), STONE_DARK, Vector3(-0.34, 0.60, -1.5 + k * 1.5), Vector3(8, 0, 0), t)

func _processional_path() -> void:
	# Raised edges are a few centimetres tall and remain visual only.
	for side in [-1, 1]:
		for i in 25:
			_box(Vector3(0.12, 0.06, 0.58), STONE, Vector3(side * 2.2, 0.035, 1.3 + i * 0.82), Vector3(0, side * 2, 0))
	for i in 32:
		var a := float(i) * TAU / 32.0
		var p := Vector3(cos(a) * 6.3, 0.025, sin(a) * 6.3)
		_box(Vector3(0.65, 0.035, 0.06), BRASS.darkened(0.3), p, Vector3(0, -rad_to_deg(a), 0))
	# Gaps and chipped edges in the central invocation seal.
	for i in 8:
		var a := TAU * float(i) / 8.0
		var t := Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 7.2, 0.024, sin(a) * 7.2))
		_box(Vector3(0.85, 0.02, 0.04), Ink.CINNABAR_DARK, Vector3.ZERO, Vector3.ZERO, t)
		_box(Vector3(0.04, 0.02, 0.55), Ink.CINNABAR_DARK, Vector3(0.2, 0, 0), Vector3.ZERO, t)
	for i in 75:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(19.0, 26.0)
		_box(Vector3(0.15, 0.025, 0.30), STONE, Vector3(cos(a) * r, 0.022, sin(a) * r), Vector3(0, _rng.randf() * 360, 0))

func _well(p: Vector3) -> void:
	for i in 16:
		var a := TAU * float(i) / 16.0
		_box(Vector3(0.36, 0.065, 0.24), STONE, p + Vector3(cos(a) * 1.19, 0.86, sin(a) * 1.19), Vector3(0, -rad_to_deg(a), 0))
	for side in [-1, 1]:
		_box(Vector3(0.29, 0.09, 0.29), BRASS.darkened(0.3), p + Vector3(side * 1.15, 1.90, 0))
		_box(Vector3(0.13, 0.65, 0.13), WOOD, p + Vector3(side * 0.90, 1.96, 0), Vector3(0, 0, side * -42))
	for i in 8:
		_cyl(0.042, 2.0, STONE_DARK, p + Vector3(-1.14 + i * 0.325, 2.53, 0), Vector3(74, 0, 0))
	_cyl(0.10, 2.65, WOOD, p + Vector3(0, 1.95, 0), Vector3(0, 0, 90))
	_cyl(0.024, 0.47, BRASS.darkened(0.2), p + Vector3(1.40, 1.75, 0), Vector3(0, 0, -15))
	_cyl(0.025, 0.35, WOOD, p + Vector3(1.42, 1.51, 0.13), Vector3(90, 0, 0))
	for i in 6:
		_cyl(0.13, 0.035, Color("9b8c67"), p + Vector3(-0.14 + i * 0.043, 1.95, 0), Vector3(0, 0, 90))

func _monument(p: Vector3) -> void:
	# Stone plinth inscriptions and metal ferrule etching.
	for side in [-1, 1]:
		_box(Vector3(1.65, 0.12, 0.24), STONE_DARK, p + Vector3(0, 0.08, side * 1.32))
		for i in 5:
			_box(Vector3(0.09, 0.03, 0.24), BRASS.darkened(0.25), p + Vector3(-0.52 + i * 0.25, 0.16, side * 1.30))
	for i in 9:
		var a := TAU * float(i) / 9.0
		_box(Vector3(0.035, 0.37, 0.035), BRASS, p + Vector3(0.41 + cos(a) * 0.42, 2.20, sin(a) * 0.42), Vector3(0, 0, -6))

func _pillar(p: Vector3) -> void:
	for side in [-1, 1]:
		_box(Vector3(0.06, 0.31, 0.85), STONE_DARK, p + Vector3(side * 0.47, 0.82, 0))
	for i in 5:
		_box(Vector3(0.19, 0.025, 0.02), Ink.INK_SOFT, p + Vector3(-0.08 + (i % 2) * 0.07, 1.4 + i * 0.1, 0.44))
	for i in 3:
		var a := _rng.randf() * TAU
		_add(Ink.prism_mesh(Vector3(0.24, 0.18, 0.31)), STONE, p + Vector3(cos(a), 0.10, sin(a)), Vector3(0, rad_to_deg(a), 0))

func _props() -> void:
	# Lantern lattice and reliefs; barrel staves and lids; broken wheel spokes.
	var lanterns := [Vector3(-12.5, 0, 10.5), Vector3(12.5, 0, 10.5), Vector3(-12.5, 0, -10.5), Vector3(12.5, 0, -10.5), Vector3(0, 0, 23.5)]
	for p: Vector3 in lanterns:
		for side in [-1, 1]:
			for i in 3:
				_box(Vector3(0.56, 0.025, 0.025), STONE_DARK, p + Vector3(0, 1.55 + i * 0.21, side * 0.285))
				_box(Vector3(0.025, 0.56, 0.025), STONE_DARK, p + Vector3(-0.21 + i * 0.21, 1.78, side * 0.285))
			_box(Vector3(0.10, 0.22, 0.02), BRASS, p + Vector3(0, 0.85, side * 0.22))
	for p: Vector3 in [Vector3(17, 0, 14), Vector3(-16, 0, -15)]:
		for i in 3:
			var c := p + Vector3(i * 0.85 - 0.8, 0, 0)
			for j in 9:
				var a := TAU * float(j) / 9.0
				_box(Vector3(0.014, 0.85, 0.025), WOOD.darkened(0.3), c + Vector3(cos(a) * 0.36, 0.56, sin(a) * 0.36), Vector3(0, -rad_to_deg(a), 0))
			_cyl(0.034, 0.025, BRASS, c + Vector3(0.10, 1.12, 0.04))
	for i in 10:
		var a := TAU * float(i) / 10.0
		var t := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(35), deg_to_rad(78))), Vector3(-14.5, 0.85, -9))
		_box(Vector3(0.055, 0.08, 1.28), WOOD, Vector3.ZERO, Vector3(0, rad_to_deg(a), 0), t)

func _banners() -> void:
	for p: Vector3 in [Vector3(-14.5, 0, -24.8), Vector3(14.5, 0, -24.8)]:
		for k in 8:
			_box(Vector3(0.08, 0.38, 0.035), Ink.CINNABAR_DARK, p + Vector3(0.2 + k * 0.26, 1.58 + (k % 3) * 0.06, 0.06), Vector3(0, 0, -3))
		for k in 4:
			_box(Vector3(0.14, 0.10, 0.12), BRASS, p + Vector3(0.35 + k * 0.52, 5.82, 0.06))

func _torii() -> void:
	var p := Vector3(0, 0, -34.5)
	for side in [-1, 1]:
		_box(Vector3(0.80, 0.18, 0.82), BRASS.darkened(0.35), p + Vector3(side * 4.1, 4.70, 0))
		_box(Vector3(0.80, 0.28, 0.95), STONE_DARK, p + Vector3(side * 5.20, 6.42, 0), Vector3(0, 0, side * 12))
		_box(Vector3(0.20, 1.0, 0.20), WOOD, p + Vector3(side * 3.70, 5.28, 0), Vector3(0, 0, side * 35))
	for i in 22:
		_box(Vector3(0.10, 0.06, 0.88), STONE, p + Vector3(-5.0 + i * 0.46, 6.51, 0))

func _nature() -> void:
	# Clumps of fine needles and leaf litter are batched, never individual nodes.
	for i in 200:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(20.0, 26.6)
		var p := Vector3(cos(a) * r, 0.020, sin(a) * r)
		_add(Ink.prism_mesh(Vector3(0.08, 0.025, 0.26)), MOSS.lerp(Color("9b8051"), float(i % 4) / 4.0), p, Vector3(0, _rng.randf() * 360, 0))
	for p: Vector3 in [Vector3(-18.5, 0, -3), Vector3(18, 0, -10.5), Vector3(-19, 0, 14.5)]:
		for k in 10:
			var a := TAU * float(k) / 10.0
			_box(Vector3(0.025, 1.6, 0.025), WOOD.lightened(0.10), p + Vector3(cos(a) * 0.40, 1.15, sin(a) * 0.40), Vector3(0, 0, k % 3 - 1))

func _night_garden() -> void:
	# A procession of low stone prayer markers changes visual routes while
	# keeping the central arena, gate lanes and all spawn points unobstructed.
	for side in [-1, 1]:
		for i in 7:
			var p := Vector3(side * (12.0 + sin(i * 0.55) * 3.5), 0, -12 + i * 3.4)
			_box(Vector3(0.45, 0.55, 0.25), STONE, p + Vector3(0, 0.275, 0), Vector3(0, side * 22, 0))
			_box(Vector3(0.24, 0.025, 0.30), BRASS, p + Vector3(0, 0.57, 0))
			_box(Vector3(0.018, 0.20, 0.02), Ink.CINNABAR, p + Vector3(0, 0.29, 0.15))
