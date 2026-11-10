extends SceneTree

var main: Node3D
var player: Node3D

func _initialize() -> void:
	_run.call_deferred()

func shot(label: String, delay: float = 0.12) -> void:
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dev_shots/feedback_%s.png" % label)
	print("[feedback-gallery] " + label)

func _run() -> void:
	root.get_node("Game")._test_profile = true
	root.get_node("Settings").save_path = "user://feedback_gallery.cfg"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.start_run()
	main.director.stop()
	main.hud.clear_banner()
	player = main.player
	player.set_controls(false)
	player.set_physics_process(false)
	player.invuln_time = 999.0
	player.position = Vector3(0, 0.05, 17)
	var enemy: Node3D = main.director.debug_spawn("puppet", Vector3(0, 0.05, 7))
	enemy.frozen = true
	enemy.state = "chase"
	enemy.complete_spawn_visual()
	player.unlock_weapon("cinnabar_rifle")
	player.switch_to_index(player.owned_weapons.find("cinnabar_rifle"))
	await create_timer(0.8).timeout
	player.head.look_at(enemy.aim_point(), Vector3.UP)
	player.set_controls(true)
	Input.action_press("aim")
	await shot("scope", 0.8)
	Input.action_release("aim")
	player.set_controls(false)
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.current = true
	camera.position = Vector3(9, 7, 20)
	camera.look_at(Vector3(0, 0, 12), Vector3.UP)
	player.view.visible = false
	var vfx: Script = load("res://scripts/fx/vfx.gd")
	vfx.skill_cast(main, "nova", Vector3(0, 0.05, 13), Vector3.FORWARD, 6.0)
	await shot("nova", 0.2)
	await create_timer(1.3).timeout
	vfx.skill_cast(main, "dash", Vector3(0, 0.05, 13), Vector3.FORWARD, 6.0)
	await shot("dash", 0.08)
	await create_timer(1.3).timeout
	vfx.talisman_impact(main, Vector3(0, 0.05, 13), 4.0)
	await shot("fire", 0.2)
	await create_timer(1.3).timeout
	var remote_script: Script = load("res://scripts/network/remote_player.gd")
	var teammate: Node3D = remote_script.new()
	teammate.setup(2, "队友 · 冷色系", 0)
	teammate.position = Vector3(2.0, 0, 12)
	main.add_child(teammate)
	for i in 3:
		var foe: Node3D = main.director.debug_spawn(["wraith", "puppet", "reaver"][i], Vector3(-4 + i * 2.0, 0.05, 12))
		foe.frozen = true
		foe.state = "chase"
		foe.complete_spawn_visual()
	camera.position = Vector3(1, 2.6, 19)
	camera.look_at(Vector3(-1, 1.2, 12), Vector3.UP)
	await shot("palette", 0.3)
	main.upgrades.open(3, load("res://scripts/core/upgrades.gd").roll(player, 3))
	main.upgrades._on_refresh()
	await shot("upgrades", 0.5)
	main.upgrades.close()
	main._quit_game()
