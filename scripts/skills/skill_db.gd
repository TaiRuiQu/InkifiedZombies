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
			VFX.ring(player.get_parent(), player.global_position, 3.5, Ink.INDIGO_LIGHT, 0.4)
	else:
		definition.effect.call("cast", player)
	player.stats_changed.emit()
	return true
