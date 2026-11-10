class_name EnemyFaceMesh
extends RefCounted

## Hand-built planes, rather than a smooth sphere with painted cubes. All six
## masks share a low-poly facial topology, with distinct jaws and expressions.
## The normalised face looks down -Z. Scale it to the character's proportions.
static var _cache: Dictionary = {}

static func meshes(style: String) -> Dictionary:
	if _cache.has(style):
		return _cache[style]
	var builders := {}
	for group in ["bone", "ridge", "sockets", "lips", "teeth"]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		builders[group] = tool
	var wide := 1.08 if style in ["brute", "boss"] else (0.90 if style == "mask" else 1.0)
	var jaw := 0.84 if style in ["brute", "boss"] else (0.56 if style == "wraith" else 0.69)
	var top := Vector3(0, 1.04, -0.55)
	var brow := Vector3(0, 0.53, -0.91)
	var bridge := Vector3(0, 0.17, -1.04)
	var nose := Vector3(0, -0.13, -1.46 if style != "puppet" else -1.14)
	var upper_lip := Vector3(0, -0.41, -1.05)
	var chin := Vector3(0, -1.0, -0.65)
	for side in [-1.0, 1.0]:
		var temple := Vector3(side * wide * 0.91, 0.63, -0.34)
		var brow_outer := Vector3(side * wide * 0.78, 0.49, -0.93)
		var brow_inner := Vector3(side * 0.15, 0.35, -1.04)
		var temple_lower := Vector3(side * wide, -0.03, -0.33)
		var cheek := Vector3(side * wide * 0.72, -0.16, -1.02)
		var nose_side := Vector3(side * 0.23, -0.20, -0.98)
		var mouth_corner := Vector3(side * 0.47, -0.48, -0.94)
		var jaw_corner := Vector3(side * jaw, -0.70, -0.60)
		var lower_lip := Vector3(side * 0.21, -0.64, -0.97)
		_triangle(builders.bone, top, temple, brow_outer)
		_triangle(builders.bone, top, brow_outer, brow)
		_triangle(builders.ridge, brow, brow_outer, brow_inner)
		_triangle(builders.bone, brow, brow_inner, bridge)
		_triangle(builders.ridge, bridge, brow_inner, nose)
		_triangle(builders.bone, temple, temple_lower, brow_outer)
		_triangle(builders.bone, temple_lower, cheek, brow_outer)
		_triangle(builders.ridge, cheek, nose_side, brow_inner)
		_triangle(builders.bone, brow_inner, nose_side, nose)
		_triangle(builders.ridge, nose, nose_side, upper_lip)
		_triangle(builders.bone, nose_side, cheek, mouth_corner)
		_triangle(builders.bone, nose_side, mouth_corner, upper_lip)
		_triangle(builders.bone, temple_lower, jaw_corner, cheek)
		_triangle(builders.ridge, cheek, jaw_corner, mouth_corner)
		_triangle(builders.bone, mouth_corner, jaw_corner, lower_lip)
		_triangle(builders.bone, jaw_corner, chin, lower_lip)
		# Thick, angular eye cavities remain legible at gameplay distance.
		var expression := -0.06 if style in ["brute", "boss"] else 0.04
		_polygon(builders.sockets, [Vector3(side * 0.17, 0.32, -1.07),
			Vector3(side * 0.74, 0.39 + expression, -1.02),
			Vector3(side * 0.69, 0.13 + expression, -1.11),
			Vector3(side * 0.28, 0.08, -1.17)])
		# The folded lip and nose underside create actual depth and nostrils.
		_triangle(builders.sockets, nose + Vector3(0, -0.04, 0.02),
			nose_side + Vector3(0, -0.03, -0.06), upper_lip + Vector3(side * 0.07, 0.05, -0.04))
		_triangle(builders.bone, lower_lip, chin, Vector3(0, -0.66, -0.98))
	var mouth_y := -0.49
	var mouth_h := 0.24 if style in ["brute", "boss", "wraith"] else 0.11
	_polygon(builders.sockets, [Vector3(-0.47, mouth_y, -0.99), Vector3(0, -0.39, -1.08),
		Vector3(0.47, mouth_y, -0.99), Vector3(0.35, mouth_y - mouth_h, -1.02),
		Vector3(-0.35, mouth_y - mouth_h, -1.02)])
	_polygon(builders.lips, [Vector3(-0.49, mouth_y, -1.005), Vector3(0, -0.365, -1.095),
		Vector3(0.49, mouth_y, -1.005), Vector3(0, -0.425, -1.115)])
	if style in ["wraith", "brute", "boss"]:
		for i in 6:
			var x := (float(i) - 2.5) * 0.115
			var fang := 0.30 if style in ["brute", "boss"] and i in [0, 5] else 0.12
			_polygon(builders.teeth, [Vector3(x - 0.045, -0.45, -1.11),
				Vector3(x + 0.045, -0.45, -1.11), Vector3(x + 0.025, -0.45 - fang, -1.13),
				Vector3(x - 0.035, -0.45 - fang, -1.13)])
	else:
		# A central fold on paper / lantern masks, rather than human dentures.
		_triangle(builders.ridge, Vector3(0, 0.95, -0.60), Vector3(-0.07, 0.53, -0.93),
			Vector3(0.06, 0.53, -0.93))
	var result := {}
	for group in builders:
		if group == "teeth" and style not in ["wraith", "brute", "boss"]:
			continue
		var tool: SurfaceTool = builders[group]
		tool.generate_normals()
		var mesh := tool.commit()
		if mesh != null:
			result[group] = mesh
	_cache[style] = result
	return result

static func skull() -> ArrayMesh:
	if _cache.has("skull"):
		return _cache.skull
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := [Vector3(0.45, -0.92, 0.55), Vector3(0.88, -0.45, 0.91),
		Vector3(1.0, 0.25, 1.0), Vector3(0.78, 0.83, 0.85), Vector3(0.32, 1.03, 0.40)]
	for row in rows.size() - 1:
		for i in 10:
			var a := TAU * float(i) / 10.0
			var b := TAU * float(i + 1) / 10.0
			var lower: Vector3 = rows[row]
			var upper: Vector3 = rows[row + 1]
			var p0 := Vector3(cos(a) * lower.x, lower.y, sin(a) * lower.z)
			var p1 := Vector3(cos(b) * lower.x, lower.y, sin(b) * lower.z)
			var p2 := Vector3(cos(b) * upper.x, upper.y, sin(b) * upper.z)
			var p3 := Vector3(cos(a) * upper.x, upper.y, sin(a) * upper.z)
			_skull_triangle(tool, p0, p1, p2)
			_skull_triangle(tool, p0, p2, p3)
	for i in 10:
		var a := TAU * float(i) / 10.0
		var b := TAU * float(i + 1) / 10.0
		var upper: Vector3 = rows.back()
		var lower: Vector3 = rows.front()
		tool.add_vertex(Vector3(0, 1.10, 0))
		tool.add_vertex(Vector3(cos(a) * upper.x, upper.y, sin(a) * upper.z))
		tool.add_vertex(Vector3(cos(b) * upper.x, upper.y, sin(b) * upper.z))
		tool.add_vertex(Vector3(0, -0.98, 0))
		tool.add_vertex(Vector3(cos(b) * lower.x, lower.y, sin(b) * lower.z))
		tool.add_vertex(Vector3(cos(a) * lower.x, lower.y, sin(a) * lower.z))
	tool.generate_normals()
	var mesh := tool.commit()
	_cache.skull = mesh
	return mesh

static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Front masks require clockwise winding when viewed from -Z.
	var normal := (b - a).cross(c - a)
	if normal.z < 0.0:
		var swap := b
		b = c
		c = swap
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)

static func _polygon(tool: SurfaceTool, points: Array) -> void:
	for i in range(1, points.size() - 1):
		_triangle(tool, points[0], points[i], points[i + 1])


static func _skull_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var center := (a + b + c) / 3.0
	var normal := (b - a).cross(c - a)
	if normal.dot(Vector3(center.x, 0, center.z)) > 0.0:
		var swap := b
		b = c
		c = swap
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
