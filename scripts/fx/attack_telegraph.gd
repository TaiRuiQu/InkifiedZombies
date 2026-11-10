class_name AttackTelegraph
extends Node3D

## Owned by the attacking enemy; no detached timers survive it.
var active := false
var mode := ""
var radius := 2.5
var progress := 0.0
var _outer: MeshInstance3D
var _inner: MeshInstance3D
var _arcs: Node3D

func _ready() -> void:
	name = "AttackWarning"
	_outer = _ring(0.94, 1.0, Ink.CINNABAR)
	_inner = _ring(0.97, 1.0, Ink.GOLD)
	_arcs = Node3D.new()
	add_child(_arcs)
	for side in [-1, 1]:
		var arc := MeshInstance3D.new()
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 18:
			var a := (float(i) / 18.0 * 1.15 + (PI if side < 0 else 0.0))
			var b := (float(i + 1) / 18.0 * 1.15 + (PI if side < 0 else 0.0))
			var points := [Vector3(cos(a)*0.80, 0, sin(a)*0.80), Vector3(cos(b), 0, sin(b)), Vector3(cos(a), 0, sin(a)), Vector3(cos(a)*0.80, 0, sin(a)*0.80), Vector3(cos(b)*0.80, 0, sin(b)*0.80), Vector3(cos(b), 0, sin(b))]
			for point: Vector3 in points:
				tool.add_vertex(point)
		arc.mesh = tool.commit()
		arc.material_override = Ink.unlit(Color(0.95, 0.73, 0.44, 0.6), true, false)
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arcs.add_child(arc)
	visible = false

func _ring(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 48
	mesh.ring_segments = 4
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = Ink.unlit(Color(color, 0.75), true, false)
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
	return item

func show_warning(kind: String, center: Vector3, warning_radius: float, phase: float, angle: float = 0.0) -> void:
	active = true
	mode = kind
	radius = warning_radius
	progress = clampf(phase, 0.0, 1.0)
	visible = true
	global_position = center + Vector3.UP * 0.16
	global_rotation = Vector3.ZERO
	_outer.scale = Vector3(radius, 0.07, radius)
	var fill_radius := maxf(0.1, radius * progress)
	_inner.scale = Vector3(fill_radius, 0.065, fill_radius)
	_arcs.visible = kind == "spin"
	_arcs.scale = Vector3(radius, 1, radius)
	_arcs.position.y = 0.8
	_arcs.rotation.y = angle

func clear() -> void:
	active = false
	visible = false
