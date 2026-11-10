extends RefCounted

static func cast(player: Node3D) -> void:
	var radius: float = player.mods.nova_radius
	var damage: float = player.mods.nova_damage * player.mods.damage_mult
	VFX.explosion(player.get_parent(), player.global_position + Vector3(0, 0.4, 0), radius, Ink.INK)
	VFX.ring(player.get_parent(), player.global_position, radius * 1.25, Ink.CINNABAR, 0.6, 0.9)
	player.add_trauma(0.45)
	Sfx.play("nova", 1.0)
	CombatQuery.radial_damage(player, player.global_position + Vector3(0, 1.0, 0), radius, damage, 12.0, 0.35)
