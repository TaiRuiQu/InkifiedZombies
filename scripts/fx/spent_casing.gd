extends MeshInstance3D

## Small, bounded ballistic accents. No bodies are added to the physics world.
var velocity := Vector3.ZERO
var age := 0.0
var bounces := 0

func _ready() -> void:
	add_to_group("spent_casings")
	mesh = Ink.cylinder_mesh(0.012, 0.012, 0.052, 8)
	material_override = Ink.surface(Ink.GOLD, {"outline": 0.0, "wash": 0.15, "hatch": 0.0})
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _physics_process(delta: float) -> void:
	age += delta
	if age > 1.8:
		queue_free()
		return
	if bounces >= 2:
		if age > 1.2:
			scale = Vector3.ONE * maxf(0.01, (1.8 - age) / 0.6)
		return
	velocity.y -= 11.0 * delta
	var next := global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = next
		rotation += Vector3(10.0, 7.0, 4.0) * delta
	else:
		global_position = hit.position + hit.normal * 0.015
		velocity = velocity.bounce(hit.normal) * 0.28
		bounces += 1
		if bounces == 1:
			Sfx.play_at("casing", global_position, -19.0, randf_range(0.94, 1.08))
