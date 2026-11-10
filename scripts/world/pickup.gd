class_name Pickup
extends Node3D

## Floating ink droplet (health) or rolled paper scroll (ammo).

var kind := "health"
var amount := 18.0
var life := 26.0
var player: Node3D
var base_y := 0.0
var _t := 0.0
var _mesh_root: Node3D
var _blink := 0.0


static func spawn(parent: Node3D, pos: Vector3, pickup_kind: String, pickup_amount: float = 0.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := Pickup.new()
	p.kind = pickup_kind
	p.amount = pickup_amount if pickup_amount > 0.0 else (18.0 if pickup_kind == "health" else 0.32)
	parent.add_child(p)
	p.global_position = pos + Vector3(0, 0.35, 0)
	p.base_y = p.global_position.y


func _ready() -> void:
	add_to_group("pickups")
	player = get_tree().get_first_node_in_group("player")
	_build()


func _build() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	if kind == "health":
		var color := Color("7c1f18")
		Ink.add_sphere(_mesh_root, 0.14, color, Vector3(0, 0.1, 0), Vector3(1.0, 1.35, 1.0),
			Vector3.ZERO, {"outline": 0.0035, "wobble": 0.004, "wash": 0.2, "rim": 0.35})
		Ink.add_cylinder(_mesh_root, 0.0, 0.1, 0.2, color, Vector3(0, 0.30, 0), Vector3.ZERO,
			{"outline": 0.0025, "wobble": 0.003})
		Ink.add_box(_mesh_root, Vector3(0.16, 0.2, 0.02), Ink.PAPER, Vector3(0, 0.06, 0.13),
			Vector3(0, 0, 6), {"outline": 0.002, "wobble": 0.004})
		Ink.add_box(_mesh_root, Vector3(0.06, 0.06, 0.015), Ink.CINNABAR, Vector3(0, 0.04, 0.145),
			Vector3(0, 0, 6), {"outline": 0})
		# Lacquer medicine flask: gilt neck, stopper, shoulder seams and tied seal.
		Ink.add_cylinder(_mesh_root, 0.055, 0.09, 0.055, Ink.GOLD, Vector3(0, 0.26, 0), Vector3.ZERO, {"outline": 0.0015})
		Ink.add_cylinder(_mesh_root, 0.056, 0.056, 0.045, Ink.INK, Vector3(0, 0.30, 0))
		for side in [-1, 1]:
			Ink.add_cylinder(_mesh_root, 0.012, 0.012, 0.17, Ink.GOLD, Vector3(side * 0.13, 0.10, 0), Vector3(0, 0, side * 12), {"outline": 0})
		Ink.add_box(_mesh_root, Vector3(0.10, 0.012, 0.023), Ink.CINNABAR_DARK, Vector3(0, -0.03, 0.14))
		_glow(Color("c23b2a"))
	else:
		var paper := Color("ded4bc")
		Ink.add_cylinder(_mesh_root, 0.1, 0.1, 0.34, paper, Vector3(0, 0.15, 0), Vector3(0, 0, 90),
			{"outline": 0.003, "wobble": 0.004, "wash": 0.25})
		Ink.add_cylinder(_mesh_root, 0.105, 0.105, 0.05, Ink.CINNABAR_DARK, Vector3(0.07, 0.15, 0),
			Vector3(0, 0, 90), {"outline": 0.002})
		Ink.add_cylinder(_mesh_root, 0.105, 0.105, 0.05, Ink.CINNABAR_DARK, Vector3(-0.07, 0.15, 0),
			Vector3(0, 0, 90), {"outline": 0.002})
		Ink.add_box(_mesh_root, Vector3(0.18, 0.02, 0.34), paper, Vector3(0, 0.33, 0), Vector3(0, 20, 0),
			{"outline": 0.002, "wobble": 0.004})
		# Scroll end caps, central spindle and hand-written ink lines.
		for side in [-1, 1]:
			Ink.add_cylinder(_mesh_root, 0.115, 0.115, 0.025, Ink.GOLD, Vector3(side * 0.18, 0.15, 0), Vector3(0, 0, 90))
			Ink.add_cylinder(_mesh_root, 0.04, 0.04, 0.07, Ink.INK, Vector3(side * 0.215, 0.15, 0), Vector3(0, 0, 90))
		for i in 4:
			Ink.add_box(_mesh_root, Vector3(0.12, 0.006, 0.009), Ink.INK, Vector3(0, 0.345, -0.10 + i * 0.06), Vector3(0, 20, 0), {"outline": 0})
		_glow(Color("c9a44f"))


func _glow(color: Color) -> void:
	var mat := Ink.glow(Color(color.r, color.g, color.b, 0.35), true, true)
	var q := Ink.add_quad(self, Vector2(1.4, 1.4), mat, Vector3(0, 0.25, 0), Vector3.ZERO)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.3
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = Ink.unlit(Color(color.r, color.g, color.b, 0.5), true, false)
	ring.position.y = 0.02
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _process(delta: float) -> void:
	_t += delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	position.y = base_y + sin(_t * 2.2) * 0.09
	_mesh_root.rotation.y += delta * 1.6
	if life < 5.0:
		_blink += delta
		visible = fmod(_blink, 0.4) < 0.25
	if Coop.is_client():
		return
	for candidate in get_tree().get_nodes_in_group("coop_players"):
		if not is_instance_valid(candidate) or candidate.dead:
			continue
		if candidate.global_position.distance_to(global_position) >= 1.75:
			continue
		if kind == "health" and candidate.health >= candidate.max_health:
			continue
		if not CombatQuery.has_line_of_sight(self, global_position + Vector3.UP * 0.3, candidate.global_position + Vector3.UP):
			continue
		candidate.collect(kind, amount)
		VFX.pickup_glow(get_parent(), global_position, Ink.CINNABAR if kind == "health" else Ink.GOLD)
		Sfx.play("pickup", -3.0, randf_range(0.95, 1.15))
		queue_free()
		return
