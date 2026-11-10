class_name SkillDB
extends RefCounted

static var _definitions: Dictionary = {}

static func _ensure_defaults() -> void:
	if not _definitions.is_empty():
		return
	for path in ["res://data/skills/dash.tres", "res://data/skills/nova.tres", "res://data/skills/talisman.tres"]:
		var definition: SkillDefinition = load(path)
		if definition != null:
			_definitions[definition.id] = definition

static func register(definition: SkillDefinition) -> bool:
	_ensure_defaults()
	if definition == null or definition.id.is_empty() or definition.cooldown <= 0.0:
		return false
	if definition.effect == null or not definition.effect.has_method("cast"):
		return false
	if not InputMap.has_action(definition.input_action):
		return false
	_definitions[definition.id] = definition
	return true

static func get_skill(id: String) -> SkillDefinition:
	_ensure_defaults()
	return _definitions.get(id)

static func ids() -> Array:
	_ensure_defaults()
	return _definitions.keys()

static func initial_unlocks() -> Dictionary:
	var result := {}
	for id in ids():
		result[id] = get_skill(id).starts_unlocked
	return result

static func cooldown_for(id: String, modifiers: Dictionary) -> float:
	var definition := get_skill(id)
	if definition == null:
		return 0.0
	return definition.cooldown * maxf(0.1, float(modifiers.get(definition.cooldown_modifier, 1.0)))

static func cast(id: String, player: Node3D) -> bool:
	var definition := get_skill(id)
	if definition == null or player.dead or not player.skills.get(id, false):
		return false
	if float(player.skill_cooldowns.get(id, 0.0)) > 0.0:
		return false
	player.skill_cooldowns[id] = cooldown_for(id, player.mods)
	if Coop.is_client():
		Coop.request_action("skill", {"id": id})
		if id == "dash":
			definition.effect.call("cast", player)
	else:
		definition.effect.call("cast", player)
	var direction: Vector3 = player.dash_dir if id == "dash" else -player.camera.global_transform.basis.z
	var radius := float(player.mods.get("nova_radius", 6.0))
	VFX.skill_cast(player.get_parent(), id, player.global_position, direction, radius)
	if NET.active and NET.is_host:
		NET.send("skill_fx", {"owner": int(player.get_meta("peer_id", NET.local_id)), "id": id,
			"position": Coop._pack(player.global_position), "direction": Coop._pack(direction), "radius": radius})
	player.stats_changed.emit()
	return true
