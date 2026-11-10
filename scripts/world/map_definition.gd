class_name MapDefinition
extends Resource

## Arena content independent of its builder. Coordinates use metres.
@export var id := "courtyard"
@export var display_name := "残照庭院"
@export_multiline var description := "残阳映墨，石庭守夜。视野开阔，适合初次入墨。"
@export var seed_value := 20261107
@export var player_spawn := Vector3(0, 0.1, 17)
@export var monument_position := Vector3(-6, 0, -8.5)
@export var well_position := Vector3(10.5, 0, 7.5)
@export var pillar_positions: Array[Vector3] = [Vector3(-16, 0, -3), Vector3(16, 0, 3), Vector3(-14, 0, -19), Vector3(14, 0, -19), Vector3(-17.5, 0, 16), Vector3(18.5, 0, 16)]
@export var sky_top := Color("4a5551")
@export var sky_horizon := Color("c9bfa9")
@export var sun_color := Color("cc4127")
@export var sun_energy := 0.72
@export var sun_light := Color("ffd2a1")
@export var ambient_color := Color("b8b0a0")
@export var ambient_energy := 0.18
@export var fog_color := Color("bdb5a3")
@export var fog_density := 0.0032
@export var ground_color := Color("5f5849")
@export var night := false
@export var extra_bamboo := false
