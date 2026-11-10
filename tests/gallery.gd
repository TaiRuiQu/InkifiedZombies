extends RefCounted

var main: Node3D

func _init(owner_node: Node3D) -> void:
	main = owner_node

func shot(name: String) -> void:
	await main.get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("res://dev_shots/%s.png" % name)
	print("[gallery] ", name)

func run() -> void:
	main.title.open()
	await shot("beta_title")
	main._open_settings("title")
	for i in main.settings_screen._tabs.get_tab_count():
		main.settings_screen._tabs.current_tab = i
		await shot("settings_%d" % i)
	main.settings_screen.close()
	main._open_multiplayer()
	await shot("multiplayer_direct")
	main.multiplayer_screen._tabs.current_tab = 1
	await shot("multiplayer_relay")
	main.multiplayer_screen.close()
	Game.selected_map = "bamboo_night"
	main.start_run()
	main.director.frozen = true
	main.hud.clear_banner()
	await shot("night_courtyard")
	for id in WeaponDB.all_ids():
		main.player.unlock_weapon(id)
		main.player.switch_to_index(main.player.owned_weapons.find(id))
		await shot("weapon_%s" % id)
	main.director.stop()
	Game.completed_waves = 10
	Game.wave = 10
	main._show_victory()
	await shot("victory")
	main.get_tree().quit()
