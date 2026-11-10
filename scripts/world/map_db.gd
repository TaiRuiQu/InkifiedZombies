class_name MapDB
extends RefCounted

## Add a MapDefinition via register_map; the builder and UI need no branches.
static var _maps: Dictionary = {}

static func _ensure_defaults() -> void:
	if not _maps.is_empty():
		return
	var courtyard := MapDefinition.new()
	_maps[courtyard.id] = courtyard
	var night := MapDefinition.new()
	night.id = "bamboo_night"
	night.display_name = "青岚夜院"
	night.description = "月下竹影，冷雾缠身。石碑与古井移位，沿双环路线周旋。"
	night.seed_value = 20261110
	night.monument_position = Vector3(8.5, 0, -8.0)
	night.well_position = Vector3(-10.0, 0, 7.0)
	night.pillar_positions = [Vector3(-15, 0, -12), Vector3(15, 0, 12), Vector3(-12, 0, -19), Vector3(13, 0, -18), Vector3(-17, 0, 14), Vector3(18, 0, -1)]
	night.sky_top = Color("172c39")
	night.sky_horizon = Color("819e9f")
	night.sun_color = Color("d2e0d4")
	night.sun_energy = 0.48
	night.sun_light = Color("a4c5dc")
	night.ambient_color = Color("a3bdc9")
	night.ambient_energy = 0.30
	night.fog_color = Color("77999b")
	night.fog_density = 0.0050
	night.ground_color = Color("4b5957")
	night.night = true
	night.extra_bamboo = true
	_maps[night.id] = night

static func register_map(definition: MapDefinition) -> void:
	_ensure_defaults()
	assert(not definition.id.is_empty(), "A map definition requires an id")
	_maps[definition.id] = definition

static func ids() -> Array:
	_ensure_defaults()
	return _maps.keys()

static func get_map(id: String) -> MapDefinition:
	_ensure_defaults()
	return _maps.get(id, _maps["courtyard"])
