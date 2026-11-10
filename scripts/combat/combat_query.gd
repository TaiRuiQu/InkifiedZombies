class_name CombatQuery
extends RefCounted

const SHOT_MASK := 1 | 32

static func enemy_from_collider(collider: Object) -> Node3D:
	if not is_instance_valid(collider):
		return null
	if collider.has_method("get_enemy"):
		var enemy: Node3D = collider.get_enemy()
		return enemy if is_instance_valid(enemy) and not enemy.dead else null
	if collider is Node3D and collider.is_in_group("enemies") and not collider.dead:
		return collider
	return null

static func ray(world_node: Node3D, origin: Vector3, target: Vector3,
		excludes: Array[RID] = [], mask: int = SHOT_MASK) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, target, mask)
	query.exclude = excludes
	query.collide_with_areas = true
	query.hit_from_inside = true
	return world_node.get_world_3d().direct_space_state.intersect_ray(query)

## Shared collision policy: solid world geometry blocks radial damage.
static func has_line_of_sight(world_node: Node3D, origin: Vector3, target: Vector3) -> bool:
	if origin.distance_squared_to(target) < 0.01:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1)
	return world_node.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

static func radial_damage(player: Node3D, origin: Vector3, radius: float, damage: float,
		knockback: float = 4.0, slow: float = 0.0, ignore: Node = null) -> void:
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.dead or enemy == ignore:
			continue
		var target: Vector3 = enemy.aim_point()
		var distance: float = origin.distance_to(target)
		if distance > radius or not has_line_of_sight(player, origin, target):
			continue
		var direction := (target - origin).normalized()
		var killed: bool = enemy.take_damage(damage * (1.0 - 0.35 * distance / radius),
			direction, target, false, knockback, slow)
		if killed:
			player.credit_kill(target)
