class_name WeaponDefinition
extends Resource

## A weapon resource inherits sensible pistol defaults. Values uses the same
## documented schema as WeaponDB; view_scene may contain authored meshes.
@export var id := ""
@export var display_name := ""
@export var model_id := "brush_pistol"
@export var view_scene: PackedScene
@export var values: Dictionary = {}

func to_dictionary() -> Dictionary:
	var result := values.duplicate(true)
	result["name"] = display_name
	result["model_id"] = model_id
	if view_scene != null:
		result["view_scene"] = view_scene
	return result
