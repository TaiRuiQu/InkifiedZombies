class_name EnemySteering
extends RefCounted

## Lightweight local steering for the open courtyard. Obstacle direction is
## remembered between frames; crowd queries are staggered instead of N² / tick.
var _probe_timer := 0.0
var _crowd_timer := 0.0
var _wall_memory := 0.0
var _side := 1.0
var _normal := Vector3.ZERO
var _crowd := Vector3.ZERO


func setup(seed_value: int) -> void:
	_probe_timer = float(posmod(seed_value, 13)) * 0.013
	_crowd_timer = float(posmod(seed_value, 11)) * 0.011
	_side = 1.0 if seed_value % 2 == 0 else -1.0


func direction(enemy: CharacterBody3D, desired: Vector3, delta: float) -> Vector3:
	_probe_timer -= delta
	_crowd_timer -= delta
	_wall_memory = maxf(_wall_memory - delta, 0.0)
	if _crowd_timer <= 0.0:
		_crowd_timer = 0.14
		_crowd = enemy._separation()
	var result := desired + _crowd * 0.85
	if result.length_squared() < 0.001:
		return Vector3.ZERO
	result = result.normalized()
	if _probe_timer <= 0.0:
		_probe_timer = 0.14
		var origin := enemy.global_position + Vector3.UP * 0.65
		var space := enemy.get_world_3d().direct_space_state
		var look_ahead: float = maxf(1.55, float(enemy.radius) * 2.8)
		var hit := _probe(space, origin, result, look_ahead)
		if not hit.is_empty():
			_normal = hit.normal
			_normal.y = 0.0
			_normal = _normal.normalized()
			if _wall_memory <= 0.0:
				var tangent := _normal.cross(Vector3.UP)
				var left := _clearance(space, origin, tangent, look_ahead)
				var right := _clearance(space, origin, -tangent, look_ahead)
				_side = 1.0 if left + tangent.dot(desired) * 0.7 > right - tangent.dot(desired) * 0.7 else -1.0
			_wall_memory = 0.8
	if _wall_memory > 0.0 and _normal.length_squared() > 0.1:
		var tangent := _normal.cross(Vector3.UP) * _side
		result = (tangent * 1.15 + _normal * 0.28 + desired * 0.22 + _crowd * 0.55).normalized()
	return result


func _probe(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3,
		distance: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, 1)
	return space.intersect_ray(query)


func _clearance(space: PhysicsDirectSpaceState3D, origin: Vector3,
		direction: Vector3, distance: float) -> float:
	var hit := _probe(space, origin, direction, distance)
	if hit.is_empty():
		return distance
	return origin.distance_to(hit.position)
