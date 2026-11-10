class_name SkillDefinition
extends Resource

## .tres data plus an effect script implementing static cast(player).
@export var id := ""
@export var display_name := ""
@export var icon := ""
@export var input_action := ""
@export var cooldown := 8.0
@export var cooldown_modifier := ""
@export var starts_unlocked := false
@export var effect: Script
