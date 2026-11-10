class_name WeaponDB
extends RefCounted

## Weapon definitions. Ranges are metres, spreads are degrees, rpm is
## rounds per minute. All numbers are tuned for 100 HP enemies at wave 1.

static var WEAPONS := {
	"brush_pistol": {
		"name": "墨毫", "type": "手枪", "icon": "毫",
		"desc": "以笔为枪。可靠、精准，墨尽之前永不疲倦。",
		"damage": 27.0, "rpm": 300.0, "auto": false, "pellets": 1,
		"spread": 0.62, "ads_spread": 0.16, "bloom": 0.30,
		"mag": 12, "reserve": 132, "reload": 1.10, "range": 90.0,
		"pierce": 0, "knockback": 3.0, "recoil": 0.65, "trauma": 0.055,
		"head_mult": 2.0, "falloff": Vector2(32.0, 70.0), "falloff_min": 0.7,
		"sound": "pistol", "tracer": Color("f6ebd1"), "tracer_count": 1,
		"view_pos": Vector3(0.30, -0.28, -0.60),
		"view_aim": Vector3(0.0, -0.15, -0.50),
	},
	"ink_shotgun": {
		"name": "泼墨铳", "type": "霰弹枪", "icon": "泼",
		"desc": "把一整砚墨泼出去。近距离无人能挡。",
		"damage": 11.0, "rpm": 78.0, "auto": false, "pellets": 9,
		"spread": 5.6, "ads_spread": 3.4, "bloom": 1.3,
		"mag": 6, "reserve": 60, "reload": 1.85, "range": 45.0,
		"pierce": 0, "knockback": 6.5, "recoil": 2.1, "trauma": 0.16,
		"head_mult": 1.6, "falloff": Vector2(8.0, 28.0), "falloff_min": 0.45,
		"sound": "shotgun", "tracer": Color("f6ebd1"), "tracer_count": 3,
		"view_pos": Vector3(0.32, -0.30, -0.62),
		"view_aim": Vector3(0.0, -0.17, -0.50),
	},
	"wolf_smg": {
		"name": "狼毫", "type": "冲锋枪", "icon": "狼",
		"desc": "笔锋如狼群扑食。以数量换精准。",
		"damage": 13.0, "rpm": 760.0, "auto": true, "pellets": 1,
		"spread": 1.9, "ads_spread": 0.95, "bloom": 0.16,
		"mag": 35, "reserve": 280, "reload": 1.5, "range": 70.0,
		"pierce": 0, "knockback": 1.8, "recoil": 0.42, "trauma": 0.035,
		"head_mult": 1.7, "falloff": Vector2(20.0, 55.0), "falloff_min": 0.6,
		"sound": "smg", "tracer": Color("f6ebd1"), "tracer_count": 1,
		"view_pos": Vector3(0.31, -0.29, -0.60),
		"view_aim": Vector3(0.0, -0.16, -0.50),
	},
	"cinnabar_rifle": {
		"name": "朱砂", "type": "步枪", "icon": "砂",
		"desc": "一笔朱砂，贯骨透纸。弹匣小，但每一发都算数。",
		"damage": 68.0, "rpm": 92.0, "auto": false, "pellets": 1,
		"spread": 0.32, "ads_spread": 0.06, "bloom": 0.5,
		"mag": 8, "reserve": 80, "reload": 1.65, "range": 120.0,
		"pierce": 2, "knockback": 5.0, "recoil": 1.5, "trauma": 0.12,
		"head_mult": 2.4, "falloff": Vector2(55.0, 110.0), "falloff_min": 0.8,
		"sound": "rifle", "tracer": Color("ffd9ad"), "tracer_count": 1,
		"view_pos": Vector3(0.33, -0.30, -0.66),
		"view_aim": Vector3(0.0, -0.16, -0.54),
	},
	"ink_launcher": {
		"name": "泼墨炮", "type": "榴弹", "icon": "炮",
		"desc": "把一池浓墨砸在地上。范围极大，近身慎用。",
		"damage": 30.0, "rpm": 52.0, "auto": false, "pellets": 1,
		"spread": 0.8, "ads_spread": 0.4, "bloom": 0.8,
		"mag": 4, "reserve": 24, "reload": 2.2, "range": 80.0,
		"pierce": 0, "knockback": 4.0, "recoil": 2.2, "trauma": 0.2,
		"head_mult": 1.2, "falloff": Vector2(100.0, 120.0), "falloff_min": 1.0,
		"sound": "launcher", "tracer": Color("f6ebd1"), "tracer_count": 0,
		"projectile": true, "explode_radius": 4.6, "explode_damage": 92.0,
		"view_pos": Vector3(0.32, -0.30, -0.60),
		"view_aim": Vector3(0.0, -0.17, -0.50),
	},
	"thunder_crossbow": {
		"name": "雷纹弩", "type": "弩", "icon": "雷",
		"desc": "弩矢绘着雷纹，能穿透一整列墨鬼。",
		"damage": 95.0, "rpm": 48.0, "auto": false, "pellets": 1,
		"spread": 0.22, "ads_spread": 0.05, "bloom": 0.4,
		"mag": 1, "reserve": 40, "reload": 1.05, "range": 130.0,
		"pierce": 4, "knockback": 6.0, "recoil": 1.3, "trauma": 0.10,
		"head_mult": 2.2, "falloff": Vector2(80.0, 130.0), "falloff_min": 0.9,
		"sound": "crossbow", "tracer": Color("d7e6ff"), "tracer_count": 1,
		"view_pos": Vector3(0.31, -0.28, -0.62),
		"view_aim": Vector3(0.0, -0.16, -0.52),
	},
}

const STARTING_WEAPON := "brush_pistol"
const ORDER := ["brush_pistol", "ink_shotgun", "wolf_smg", "cinnabar_rifle", "ink_launcher", "thunder_crossbow"]


static func get_weapon(id: String) -> Dictionary:
	return (WEAPONS.get(id, WEAPONS[STARTING_WEAPON]) as Dictionary).duplicate(true)


static func all_ids() -> Array:
	return WEAPONS.keys()


static func has_weapon(id: String) -> bool:
	return WEAPONS.has(id)


static func register_weapon(id: String, values: Dictionary) -> bool:
	if id.strip_edges().is_empty():
		return false
	var entry: Dictionary = WEAPONS[STARTING_WEAPON].duplicate(true)
	entry.merge(values, true)
	for field in ["damage", "rpm", "pellets", "mag", "reserve", "reload", "range"]:
		if not (entry[field] is float or entry[field] is int) or not is_finite(float(entry[field])) or float(entry[field]) <= 0.0:
			return false
	entry["model_id"] = String(values.get("model_id", "brush_pistol"))
	WEAPONS[id] = entry
	return true


static func register_definition(definition: WeaponDefinition) -> bool:
	return definition != null and register_weapon(definition.id, definition.to_dictionary())
