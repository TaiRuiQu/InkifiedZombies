class_name EnemyDefinition
extends Resource

## A designer-editable enemy archetype. Save as .tres, then register it with
## EnemyDB.register_definition(). Custom AI is a RefCounted script exposing
## update(enemy, direction, distance, delta), plus optional physics_update(),
## perform_attack(), visual_update(), damage/cleanup and JSON snapshot hooks.
@export var id: StringName = &"new_enemy"
@export var display_name := "新敌人"
@export_multiline var description := ""
@export_range(1, 100000) var max_health := 62.0
@export_range(0.1, 20.0) var move_speed := 2.55
@export_range(0.0, 1000.0) var damage := 9.0
@export_range(0.1, 30.0) var attack_range := 1.9
@export_range(0.1, 20.0) var attack_cooldown := 1.25
@export_range(0.1, 5.0) var radius := 0.42
@export_range(0.2, 10.0) var height := 1.95
@export_range(0.1, 100.0) var spawn_cost := 2.0
@export_range(1, 100) var min_wave := 1
@export_range(0.01, 20.0) var spawn_weight := 1.0
@export var is_boss := false
@export_enum("chaser", "brute", "ranged", "exploder", "boss", "duelist") var behavior := "chaser"
@export var behavior_script: Script
@export var visual_id: StringName = &"wraith"
@export var color := Color("1c1915")
@export var accent := Color("d8cfb9")
@export var glow := Color("b33428")
@export var score := 10
@export var audio: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"name": display_name, "desc": description, "hp": max_health,
		"speed": move_speed, "damage": damage, "range": attack_range,
		"attack_cd": attack_cooldown, "radius": radius, "height": height,
		"cost": spawn_cost, "min_wave": min_wave, "spawn_weight": spawn_weight,
		"is_boss": is_boss, "behavior": behavior, "behavior_script": behavior_script,
		"visual_id": String(visual_id), "color": color, "accent": accent,
		"glow": glow, "score": score, "audio": audio.duplicate(true),
	}
