extends Node3D

## Shared ink projectile for player grenades and enemy spit.

var friendly := true
var damage := 20.0
var speed := 22.0
var gravity := 0.0
var lifetime := 4.0
var color := Color("1c1915")
var radius := 0.14
var explode_radius := 0.0
var explode_damage := 0.0
var source: Node = null
var velocity := Vector3.ZERO
var dead := false
var _trail: CPUParticles3D
var _spin := 0.0


func setup(opts: Dictionary) -> void:
	friendly = bool(opts.get("friendly", true))
	damage = float(opts.get("damage", 20.0))
	speed = float(opts.get("speed", 22.0))
	gravity = float(opts.get("gravity", 0.0))
	lifetime = float(opts.get("lifetime", 4.0))
	color = opts.get("color", Color("1c1915"))
	radius = float(opts.get("radius", 0.14))
	explode_radius = float(opts.get("explode_radius", 0.0))
	explode_damage = float(opts.get("explode_damage", 0.0))
	source = opts.get("source", null)


func _ready() -> void:
	add_to_group("projectiles")
	_build_mesh()
	_build_trail()


func _build_mesh() -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sphere)
	if friendly:
		# A bound ink charge with a paper ignition seal and bronze collar.
		Ink.add_cylinder(self, radius * 0.8, radius * 0.8, radius * 0.3, Ink.GOLD,
			Vector3(0, radius * 0.55, 0), Vector3.ZERO, {"outline": 0.002})
		Ink.add_box(self, Vector3(radius * 0.8, radius * 1.8, 0.015), Ink.PAPER,
			Vector3(0, radius * 0.25, radius), Vector3(0, 0, 10), {"outline": 0.0015})
		Ink.add_box(self, Vector3(radius * 0.35, radius * 0.65, 0.018), Ink.CINNABAR,
			Vector3(0, radius * 0.3, radius + 0.01), Vector3(0, 0, 10), {"outline": 0})
	else:
		for side in [-1, 1]:
			Ink.add_cylinder(self, 0.0, radius * 0.35, radius * 2.5, Ink.INK,
				Vector3(side * radius * 0.7, 0, 0), Vector3(35, 0, side * 35), {"outline": 0.002})
	var glow := Ink.add_quad(self, Vector2(radius * 6.0, radius * 6.0),
		Ink.glow(Color(color.r, color.g, color.b, 0.38), true, true), Vector3.ZERO, Vector3.ZERO)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_trail() -> void:
	_trail = CPUParticles3D.new()
	_trail.amount = 18
	_trail.lifetime = 0.38
	_trail.local_coords = false
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_trail.emission_sphere_radius = radius
	_trail.direction = Vector3.UP
	_trail.spread = 180.0
	_trail.initial_velocity_min = 0.05
	_trail.initial_velocity_max = 0.5
	_trail.gravity = Vector3.ZERO
	_trail.scale_amount_min = radius * 0.5
	_trail.scale_amount_max = radius * 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_trail.mesh = quad
	var mat := Ink.unlit(color, false, true)
	mat.vertex_color_use_as_albedo = true
	_trail.material_override = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.75))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	_trail.color_ramp = ramp
	add_child(_trail)
	_trail.emitting = true


func launch(direction: Vector3) -> void:
	velocity = direction.normalized() * speed
	if velocity.length() > 0.01:
		_spin = randf() * TAU


func _physics_process(delta: float) -> void:
	if dead:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_impact(global_position, Vector3.UP, null)
		return
	velocity.y -= gravity * delta
	var prev := global_position
	var next := prev + velocity * delta
	var mask := CombatQuery.SHOT_MASK if friendly else 3
	var query := PhysicsRayQueryParameters3D.create(prev, next, mask)
	query.collide_with_areas = true
	query.hit_from_inside = true
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		global_position = next
		_spin += delta * 12.0
		rotation = Vector3(_spin, _spin * 0.7, 0)
	else:
		global_position = hit.position
		_impact(hit.position, hit.normal, hit.collider)


func _impact(pos: Vector3, normal: Vector3, collider: Object) -> void:
	if dead:
		return
	dead = true
	if explode_radius > 0.01:
		_explode(pos + normal * 0.025)
	else:
		var enemy := CombatQuery.enemy_from_collider(collider)
		if friendly and enemy != null:
			var killed: bool = enemy.take_damage(damage, velocity.normalized(), pos, false, 3.0, 0.0)
			var owner_player: Node = source if is_instance_valid(source) and source.is_in_group("player") else get_tree().get_first_node_in_group("player")
			if is_instance_valid(owner_player):
				if killed:
					owner_player.credit_kill(pos)
				owner_player.confirm_combat(damage, false, killed, false)
				Coop.confirm_hit(owner_player, damage, false, killed, false, pos, velocity.normalized())
		elif not friendly and is_instance_valid(collider) and collider.is_in_group("player"):
			var attacker: Node3D = source if is_instance_valid(source) else null
			collider.take_damage(damage, attacker, 3.0, pos - velocity.normalized() * 2.0)
		VFX.burst(get_parent(), pos, color, 12, 3.5, 0.1, 0.4)
		if normal.length() > 0.1:
			VFX.decal(get_parent(), pos, normal, randf_range(0.25, 0.55), Color(0.05, 0.045, 0.04, 0.5), randi() % 3)
		Sfx.play("impact", -6.0)
	queue_free()


func _explode(pos: Vector3) -> void:
	VFX.explosion(get_parent(), pos, explode_radius, color)
	Sfx.play("explosion", 0.0, randf_range(0.9, 1.1))
	if friendly:
		var player: Node = source if is_instance_valid(source) and source.is_in_group("player") else get_tree().get_first_node_in_group("player")
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or e.dead:
				continue
			var d: float = e.global_position.distance_to(pos)
			if d <= explode_radius and CombatQuery.has_line_of_sight(self, pos + Vector3.UP * 0.1, e.aim_point()):
				var f := 1.0 - 0.55 * clampf(d / explode_radius, 0.0, 1.0)
				var dir: Vector3 = (e.global_position - pos).normalized()
				var dealt := explode_damage * f
				var killed: bool = e.take_damage(dealt, dir, e.aim_point(), false, 5.0, 0.0)
				if player:
					if killed:
						player.credit_kill(e.global_position)
					player.confirm_combat(dealt, false, killed, false)
					Coop.confirm_hit(player, dealt, false, killed, false, e.aim_point(), dir)
		if player and is_instance_valid(player):
			var pd: float = player.global_position.distance_to(pos)
			player.add_trauma(clampf(1.0 - pd / (explode_radius * 2.5), 0.0, 1.0) * 0.35)
	else:
		for player in get_tree().get_nodes_in_group("coop_players"):
			if is_instance_valid(player) and not player.dead:
				var d: float = player.global_position.distance_to(pos)
				if d <= explode_radius and CombatQuery.has_line_of_sight(self, pos + Vector3.UP * 0.1, player.global_position + Vector3.UP):
					player.take_damage(explode_damage, source if is_instance_valid(source) else null, 4.0, pos)
					player.add_trauma(0.3)
	queue_free()
