extends SceneTree

## Developer-only structural check: all enemy rigs, merged mesh reuse, hit-flash
## surfaces and content registration. Run with --headless --script <this file>.
const VisualFactory: Script = preload("res://scripts/enemies/enemy_visual.gd")
const Database: Script = preload("res://scripts/enemies/enemy_db.gd")

class ModelHost extends Node3D:
	var type_id := "wraith"
	var data: Dictionary = {}
	var boss := false
	var elite := false
	var radius := 0.42


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var total := 0
	for id in Database.ids():
		var first_mesh: Mesh
		for copy_index in 2:
			var host := ModelHost.new()
			host.type_id = id
			host.data = Database.get_type(id)
			host.boss = bool(host.data.get("is_boss", false))
			host.radius = float(host.data.radius)
			root.add_child(host)
			var model: RefCounted = VisualFactory.new()
			model.build(host)
			assert(not model.parts.is_empty(), "Missing model: " + id)
			assert(model.anim.has("arm_l") and model.anim.has("arm_r"), "Missing rig: " + id)
			for part: MeshInstance3D in model.parts:
				assert(part.mesh.get_surface_count() > 0, "Empty mesh in " + id)
				assert(part.material_override is ShaderMaterial, "Missing ink shader in " + id)
			if copy_index == 0:
				first_mesh = model.parts[0].mesh
			else:
				assert(first_mesh == model.parts[0].mesh, "Mesh cache missed: " + id)
			if copy_index == 0:
				print("[enemy-models] %s: %d rendered parts, %d animated joints" % [id, model.parts.size(), model.anim.size()])
			total += model.parts.size()
			host.free()
	var registration: Dictionary = Database.get_type("wraith")
	registration["min_wave"] = 3
	assert(Database.register_type("audit_enemy", registration))
	assert(not Database.unlocked_for_wave(2).has("audit_enemy"))
	assert(Database.unlocked_for_wave(3).has("audit_enemy"))
	Database.TYPES.erase("audit_enemy")
	print("[enemy-models] PASS: all 6 rigs, meshes, material batches, cache and registration (%d parts total)." % total)
	for audio: AudioStreamPlayer in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	await create_timer(0.1).timeout
	quit(0)
