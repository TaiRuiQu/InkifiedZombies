extends SceneTree

var main: Node3D
var player: Node3D
var enemy: Node3D

func _initialize() -> void:
	_run.call_deferred()

func shot(label: String, seconds: float = 0.08) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dev_shots/action_%s.png" % label)
	print("[action-gallery] ", label)

func _run() -> void:
	root.get_node("Game")._test_profile = true
	root.get_node("Settings").save_path = "user://action_gallery.cfg"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.start_run()
	main.director.stop()
	player = main.player
	player.set_controls(false)
	player.invuln_time = 999.0
	await create_timer(0.4).timeout
	enemy = main.director.debug_spawn("wraith", Vector3(0, 0, 11.0))
	enemy.frozen = true
	enemy.state = "chase"
	enemy.rotation.y = PI
	enemy.max_health = 500.0
	enemy.health = 500.0
	await create_timer(0.5).timeout
	enemy.complete_spawn_visual()
	player.head.look_at(enemy.anim.head.global_position, Vector3.UP)
	main.hud.clear_banner()
	await shot("idle", 0.3)
	player._fire_shot(player.get_weapon_data(), player.ammo[player.current_weapon])
	await shot("fire_reaction", 0.025)
	await shot("fire_recover", 0.11)
	await create_timer(0.25).timeout
	player.ammo[player.current_weapon].mag = 3
	player.start_reload()
	await shot("reload_eject", player.reload_total * 0.2)
	await shot("reload_insert", player.reload_total * 0.35)
	await shot("reload_close", player.reload_total * 0.30)
	await create_timer(0.3).timeout
	player.invuln_time = 0.0
	player.take_damage(18.0, null, 0.0, player.global_position + Vector3(7, 0, -3))
	await shot("hurt_right", 0.045)
	await create_timer(0.4).timeout
	player._start_dash()
	await shot("dash", 0.045)
	await create_timer(0.35).timeout
	player.position = enemy.position + Vector3(0, 0, 2.0)
	player.head.look_at(enemy.aim_point(), Vector3.UP)
	player._melee_attack()
	await shot("melee_windup", 0.05)
	await shot("melee_contact", 0.08)
	await create_timer(0.5).timeout
	player.unlock_weapon("ink_shotgun")
	await shot("equip", 0.1)
	await shot("shotgun_idle", 0.35)
	main._quit_game()
