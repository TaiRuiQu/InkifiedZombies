extends SceneTree

var main: Node3D
var _game: Node
var _settings: Node
var _sfx: Node

func _initialize() -> void:
	_run.call_deferred()

func shot(label: String, delay: float = 0.35) -> void:
	await create_timer(delay, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dev_shots/polish_%s.png" % label)
	print("[polish-gallery] ", label)

func _run() -> void:
	_game = root.get_node("Game")
	_settings = root.get_node("Settings")
	_sfx = root.get_node("Sfx")
	_game._test_profile = true
	_settings.save_path = "user://polish_test_settings.cfg"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await shot("title_day", 0.7)
	var map_option: OptionButton = main.title._selectors.selected_map
	map_option.select(1)
	map_option.item_selected.emit(1)
	await shot("title_night", 0.6)
	var mode_option: OptionButton = main.title._selectors.endless
	mode_option.show_popup()
	await shot("dropdown", 0.25)
	mode_option.get_popup().hide()
	main._open_settings("title")
	main.settings_screen._tabs.current_tab = 1
	await shot("sound_settings")
	main.settings_screen.close()
	main.start_run()
	main.director.stop()
	main.player.set_controls(false)
	main.player.head.rotation = Vector3.ZERO
	main.player.set_process(false)
	main.player.set_physics_process(false)
	main.player.health = 63.0
	main.player.damage_direction.emit(22.0, main.player.global_position + Vector3(8, 0, -5), false)
	main.player.damage_direction.emit(9.0, main.player.global_position + Vector3(-8, 0, 0), true)
	main.player.combat_feedback.emit(128.0, true, true, true)
	await shot("combat_feedback", 0.12)
	main.hud.visible = false
	main.player.view.visible = false
	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.03
	main.add_child(camera)
	camera.current = true
	for id in EnemyDB.ids():
		var enemy: Node3D = load("res://scenes/enemy.tscn").instantiate()
		enemy.setup(String(id), 1, false)
		enemy.position = Vector3(0, 0, 9.0)
		enemy.frozen = true
		main.add_child(enemy)
		await create_timer(0.5).timeout
		var target: Vector3 = enemy.anim.head.global_position
		camera.position = target + Vector3(0.1, 0.07, -1.8 if id != "boss" else -2.8)
		camera.look_at(target + Vector3(0, -0.025, 0), Vector3.UP)
		await shot("face_%s" % id, 0.1)
		camera.position = target + Vector3(1.25, 0.12, -2.0 if id != "boss" else -3.2)
		camera.look_at(target, Vector3.UP)
		await shot("face_%s_angle" % id, 0.1)
		enemy.free()
	_sfx.shutdown()
	await create_timer(0.15).timeout
	quit()
