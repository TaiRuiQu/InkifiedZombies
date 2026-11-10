class_name EnemyHitbox
extends Area3D

## Movement collision stays on Enemy. These shapes follow the painted model
## and its articulated limbs, so the damage silhouette matches what is visible.
const DAMAGE_LAYER := 32
var enemy: Node3D
var body_part := "body"

func setup(owner_enemy: Node3D, part_name: String, shape: Shape3D) -> void:
	enemy = owner_enemy
	body_part = part_name
	name = "Hitbox_%s" % part_name
	collision_layer = DAMAGE_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = false
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)

func get_enemy() -> Node3D:
	return enemy if is_instance_valid(enemy) else null

func take_damage(amount: float, direction: Vector3 = Vector3.ZERO, hit_position: Vector3 = Vector3.INF,
		critical: bool = false, knockback: float = 0.0, slow: float = 0.0) -> bool:
	if not is_instance_valid(enemy):
		return false
	return enemy.take_damage(amount, direction, hit_position, critical, knockback, slow)

func is_headshot(_position: Vector3) -> bool:
	return body_part == "head"

func aim_point() -> Vector3:
	return global_position
