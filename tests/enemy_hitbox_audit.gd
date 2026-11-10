extends SceneTree

## Every visible head / body / limb is damageable, independent of movement
## capsules. Run in the project so autoloads and collision masks are real.
var _world: Node3D
var _scene: PackedScene
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, text: String) -> void:
	assert(condition, text)
	_checks += 1

func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_scene = load("res://scenes/enemy.tscn")
	for id in EnemyDB.ids():
		for material_group in EnemyFaceMesh.meshes(id):
			var mesh: ArrayMesh = EnemyFaceMesh.meshes(id)[material_group]
			var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			var average := Vector3.ZERO
			for normal in normals:
				average += normal
			_check(average.z < 0.0, id + " face normals must look forward (-Z)")
		var enemy: Node3D = _scene.instantiate()
		enemy.setup(id, 1, false)
		enemy.frozen = true
		_world.add_child(enemy)
		# Born enemies may visibly be shot before their entrance animation ends.
		var initial: float = enemy.health
		enemy.take_damage(1.0, Vector3.BACK, enemy.aim_point())
		_check(enemy.health < initial, id + " spawn should accept damage")
		await create_timer(0.50).timeout
		await physics_frame
		await physics_frame
		var head: Node3D = enemy.anim.head
		var target := head.global_position
		var result := _ray(target + Vector3(0, 0, -7.0), target + Vector3(0, 0, 1.0))
		_check(not result.is_empty(), id + " sculpted head must be hittable")
		_check(result.collider is EnemyHitbox and result.collider.get_enemy() == enemy, id + " head resolves its owner")
		_check(result.collider.body_part == "head" and result.collider.is_headshot(result.position), id + " explicit headshot part")
		_check(enemy.is_headshot(result.position), id + " legacy positional headshot agrees")
		var chest_hit := false
		var limb_hits := 0
		for hitbox: Area3D in enemy.hitboxes:
			var body_position := hitbox.global_position
			if hitbox.body_part in ["torso", "cloak"]:
				result = _ray(body_position + Vector3(0, 0, -7), body_position)
				chest_hit = not result.is_empty() and result.collider.get_enemy() == enemy
			elif hitbox.body_part in ["arm", "leg"]:
				result = _ray(body_position + Vector3(0, 0, -7), body_position)
				if not result.is_empty() and result.collider.get_enemy() == enemy:
					limb_hits += 1
		_check(chest_hit, id + " chest must be hittable")
		_check(limb_hits >= 2, id + " articulated arms must be hittable")
		var miss := target + Vector3(enemy.radius * 4.5, 0, 0)
		_check(_ray(miss + Vector3(0, 0, -7), miss).is_empty(), id + " empty silhouette must miss")
		# Solid cover still wins over damage areas, regardless of face detail.
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		wall.position = Vector3(0, 2.5, -2.0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(5, 7, 0.25)
		shape.shape = box
		wall.add_child(shape)
		_world.add_child(wall)
		await physics_frame
		await physics_frame
		result = _ray(target + Vector3(0, 0, -7), target)
		_check(not result.is_empty() and result.collider == wall, id + " cover blocks headshots")
		wall.free()
		var follower: Node3D = _scene.instantiate()
		follower.setup(id, 1, false)
		follower.frozen = true
		follower.position.z = 3.0
		_world.add_child(follower)
		await create_timer(0.50).timeout
		await physics_frame
		await physics_frame
		var exclusions: Array[RID] = enemy.damage_rids()
		_check(exclusions.size() == enemy.hitboxes.size() + 1, id + " excludes every body part once")
		result = _ray(target + Vector3(0, 0, -7), target + Vector3(0, 0, 5), exclusions)
		_check(not result.is_empty() and result.collider.get_enemy() == follower, id + " piercing skips the entire first enemy")
		follower.free()
		# Clear collision on death, including an enemy killed during spawn.
		enemy.take_damage(enemy.max_health * 3, Vector3.BACK, target)
		await physics_frame
		await physics_frame
		for hitbox: Area3D in enemy.hitboxes:
			_check(hitbox.collision_layer == 0, id + " dead damage area disabled")
		print("[hitbox] %s PASS head/body/limbs/spawn/cover/penetration/death; areas=%d" % [id, enemy.hitboxes.size()])
		enemy.free()
	_world.free()
	print("[hitbox] PASS all registered enemies, %d checks" % _checks)
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	for player in root.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
		player.stream = null
	await create_timer(0.2).timeout
	quit(0)

func _ray(origin: Vector3, target: Vector3, excludes: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, target, 33)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = excludes
	return _world.get_world_3d().direct_space_state.intersect_ray(query)
