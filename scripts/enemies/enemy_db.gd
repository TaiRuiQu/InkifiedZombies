class_name EnemyDB
extends RefCounted

## Enemy archetypes. HP is the wave-1 baseline and is scaled by the director.

static var TYPES := {
	"wraith": {
		"min_wave": 1, "spawn_weight": 5.0,
		"name": "墨鬼", "hp": 62.0, "speed": 2.55, "damage": 9.0,
		"range": 1.9, "attack_cd": 1.25, "radius": 0.42, "height": 1.95,
		"cost": 2.0, "behavior": "chaser", "color": Color("1c1915"),
		"accent": Color("d8cfb9"), "glow": Color("b33428"), "score": 10,
		"desc": "最常见的墨中残念。成群结队，不知痛楚。",
	},
	"puppet": {
		"min_wave": 2, "spawn_weight": 4.2,
		"name": "纸傀", "hp": 34.0, "speed": 4.15, "damage": 6.0,
		"range": 1.75, "attack_cd": 0.8, "radius": 0.36, "height": 1.75,
		"cost": 1.35, "behavior": "chaser", "color": Color("d9d0bb"),
		"accent": Color("a93226"), "glow": Color("a93226"), "score": 8,
		"desc": "被符咒驱使的纸人。薄，但快得不像纸。",
	},
	"brute": {
		"min_wave": 7, "spawn_weight": 1.1,
		"name": "墨甲", "hp": 330.0, "speed": 1.5, "damage": 24.0,
		"range": 2.8, "attack_cd": 1.9, "radius": 0.78, "height": 2.75,
		"cost": 7.0, "behavior": "brute", "color": Color("23201a"),
		"accent": Color("8f2f24"), "glow": Color("e0a54c"), "score": 40,
		"desc": "披着碎甲的墨块。慢，但一击能打碎骨头。",
	},
	"mask": {
		"min_wave": 4, "spawn_weight": 2.2,
		"name": "咒面", "hp": 78.0, "speed": 2.05, "damage": 12.0,
		"range": 13.0, "attack_cd": 2.5, "radius": 0.48, "height": 2.0,
		"cost": 4.2, "behavior": "ranged", "color": Color("cfc5ad"),
		"accent": Color("8f2f24"), "glow": Color("c23a2c"), "score": 24,
		"desc": "悬在半空的怨面。会吐出墨弹，也会退。",
	},
	"lantern": {
		"min_wave": 6, "spawn_weight": 1.5,
		"name": "灯鬼", "hp": 44.0, "speed": 3.5, "damage": 40.0,
		"range": 2.5, "attack_cd": 2.0, "radius": 0.38, "height": 1.55,
		"cost": 3.0, "behavior": "exploder", "color": Color("e2c68b"),
		"accent": Color("a93226"), "glow": Color("ff9a45"), "score": 18,
		"desc": "提着自己脑袋的灯。靠近时，会亮得刺眼。",
	},
	"leaper": {
		"min_wave": 3, "spawn_weight": 1.6,
		"name": "跃魇", "hp": 110.0, "speed": 2.9, "damage": 17.0,
		"range": 2.4, "attack_cd": 1.65, "radius": 0.40, "height": 2.15,
		"cost": 5.2, "behavior": "duelist", "visual_id": "leaper",
		"behavior_script": preload("res://scripts/enemies/behaviors/leaper.gd"),
		"color": Color("242637"), "accent": Color("9b302e"), "glow": Color("df8757"), "score": 35,
		"audio": {"stride": 0.95, "step_id": "enemy_step_puppet", "roar_id": "enemy_puppet", "step_db": -4.0, "roar_db": -3.0, "roar_gap": 5.8, "floating": false},
		"desc": "长刀跃魇。锁定落点后跳砍，离开朱砂圈再反击。",
	},
	"reaver": {
		"min_wave": 6, "spawn_weight": 1.0,
		"name": "旋刃", "hp": 190.0, "speed": 2.3, "damage": 12.0,
		"range": 2.5, "attack_cd": 1.8, "radius": 0.52, "height": 2.40,
		"cost": 6.8, "behavior": "duelist", "visual_id": "reaver",
		"behavior_script": preload("res://scripts/enemies/behaviors/reaver.gd"),
		"color": Color("243c38"), "accent": Color("b58b58"), "glow": Color("e7b963"), "score": 45,
		"audio": {"stride": 1.15, "step_id": "enemy_step_brute", "roar_id": "enemy_brute", "step_db": -2.0, "roar_db": 0.0, "roar_gap": 5.8, "floating": false},
		"desc": "双刀旋刃。蓄势后旋风斩，拉开距离，等收刀硬直。",
	},
	"boss": {
		"min_wave": 5, "is_boss": true, "spawn_weight": 0.0,
		"name": "墨将", "hp": 1500.0, "speed": 1.65, "damage": 30.0,
		"range": 3.6, "attack_cd": 1.7, "radius": 1.15, "height": 3.9,
		"cost": 0.0, "behavior": "boss", "color": Color("191713"),
		"accent": Color("b08a52"), "glow": Color("d0402c"), "score": 300,
		"desc": "从墨海深处走出的将军。每五波，来收一次账。",
	},
}


static func get_type(id: String) -> Dictionary:
	return (TYPES.get(id, TYPES["wraith"]) as Dictionary).duplicate(true)


static func unlocked_for_wave(wave: int) -> Array:
	var out: Array = []
	for id in TYPES:
		var entry: Dictionary = TYPES[id]
		if not bool(entry.get("is_boss", false)) and wave >= int(entry.get("min_wave", 1)):
			out.append(id)
	return out


static func register_type(id: String, values: Dictionary) -> bool:
	if id.strip_edges().is_empty():
		push_error("EnemyDB: an enemy needs a stable, nonempty id.")
		return false
	var entry: Dictionary = TYPES["wraith"].duplicate(true)
	entry.merge(values, true)
	for field in ["hp", "speed", "range", "attack_cd", "radius", "height"]:
		if not (entry[field] is float or entry[field] is int) or not is_finite(float(entry[field])) or float(entry[field]) <= 0.0:
			push_error("EnemyDB: %s.%s must be a positive number." % [id, field])
			return false
	if not bool(entry.get("is_boss", false)) and float(entry.cost) <= 0.0:
		push_error("EnemyDB: non-boss spawn cost must be positive: " + id)
		return false
	entry["visual_id"] = String(entry.get("visual_id", id))
	TYPES[id] = entry
	return true


static func register_definition(definition: Resource) -> bool:
	if not definition or not definition.has_method("to_dictionary"):
		push_error("EnemyDB: expected an EnemyDefinition resource.")
		return false
	return register_type(String(definition.get("id")), definition.to_dictionary())


static func ids() -> Array:
	return TYPES.keys()
