extends SceneTree

## Regression coverage for wall-safe damage and the signed boss fan volley.
## --headless --path . --script scripts/enemies/combat_audit.gd

class Target extends Node3D:
	var dead := false
	var damage_received := 0.0
	func take_damage(amount: float, _source: Node, _force: float) -> void:
		damage_received += amount
	func add_trauma(_amount: float) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var target := Target.new()
	target.position = Vector3(0, 0, -2.0)
	target.add_to_group("player")
	world.add_child(target)
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy = scene.instantiate()
	enemy.setup("wraith", 1, false)
	enemy.frozen = true
	world.add_child(enemy)
	enemy.state = "chase"
	enemy.player = target
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0, 1.0, -1.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.3)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	assert(not enemy._has_line_of_sight(), "Wall must block line of sight.")
	enemy._melee_strike(2.6, 10.0)
	enemy._aoe_strike(3.4, 20.0)
	assert(is_zero_approx(target.damage_received), "Damage crossed a wall.")
	var steering := preload("res://scripts/enemies/enemy_steering.gd").new()
	steering.setup(2)
	var around: Vector3 = steering.direction(enemy, Vector3.FORWARD, 0.2)
	assert(absf(around.x) > 0.2, "Obstacle steering must choose a tangent.")
	wall.free()
	await physics_frame
	await physics_frame
	assert(enemy._has_line_of_sight(), "Open ground must allow damage.")
	enemy._melee_strike(2.6, 10.0)
	enemy._aoe_strike(3.4, 20.0)
	assert(target.damage_received > 10.0, "Open-ground strikes did not hit.")
	target.position.z = -12
	enemy._fire_projectile(1, -14.0)
	var first_velocity := _last_projectile_velocity(world)
	enemy._fire_projectile(1, 14.0)
	var second_velocity := _last_projectile_velocity(world)
	assert(first_velocity.x * second_velocity.x < 0.0, "Boss fan must shoot both sides.")
	world.free()
	print("[enemy-combat] PASS: wall blocks melee/AOE; open strikes hit; obstacles steer; signed volley fans both ways.")
	for audio: AudioStreamPlayer in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	await create_timer(0.1).timeout
	quit(0)


func _last_projectile_velocity(world: Node3D) -> Vector3:
	var result := Vector3.ZERO
	for child in world.get_children():
		if child.get_script() and child.get_script().resource_path == "res://scripts/combat/projectile.gd":
			result = child.velocity
	return result
