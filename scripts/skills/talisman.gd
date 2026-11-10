extends RefCounted

const Projectile := preload("res://scripts/combat/projectile.gd")

static func cast(player: Node3D) -> void:
	var projectile := Projectile.new()
	projectile.setup({"source": player, "friendly": true, "damage": 20.0, "speed": 19.0, "gravity": 5.5,
		"lifetime": 5.0, "color": Ink.GOLD, "radius": 0.14, "spell": "talisman",
		"explode_radius": float(player.mods.talisman_radius),
		"explode_damage": float(player.mods.talisman_damage) * float(player.mods.damage_mult)})
	player.get_parent().add_child(projectile)
	projectile.global_position = player.camera.global_position
	projectile.launch(-player.camera.global_transform.basis.z + Vector3(0, 0.08, 0))
	player.view.notify_fire()
	Sfx.play("talisman", -2.0)
