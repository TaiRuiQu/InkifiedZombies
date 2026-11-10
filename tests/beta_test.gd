extends RefCounted

var main: Node3D
var failures: Array[String] = []

func _init(owner_node: Node3D) -> void:
	main = owner_node

func check(condition: bool, description: String) -> void:
	print("[beta] %s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		failures.append(description)

func run() -> void:
	await main.get_tree().process_frame
	Game._test_profile = true
	Settings.set_value("fov", 500.0)
	check(float(Settings.get_value("fov")) == 105.0, "FOV rejects out of range values")
	Settings.set_value("fov", 78.0)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	check(not Settings.rebind("reload", event).is_empty(), "conflicting binding rejected")
	event.physical_keycode = KEY_T
	check(Settings.rebind("reload", event).is_empty(), "free binding accepted")
	Settings.save()
	Settings.values.fov = 99.0
	Settings.load_preferences()
	check(float(Settings.get_value("fov")) == 78.0 and Settings.binding_text("reload") == "T", "settings and keybinding round trip")
	event.physical_keycode = KEY_R
	Settings.rebind("reload", event)
	Settings.save()
	main._open_settings("title")
	check(main.settings_screen.visible and not main.title.visible, "title settings open")
	main.settings_screen.close()
	check(main.title.visible, "title restored after settings")
	Game.difficulty = "standard"
	Game.endless = false
	main.start_run()
	check(main.player.skills.dash and not main.player.skills.nova, "initial dodge unlocked")
	main._open_pause()
	main._open_settings("pause")
	main.settings_screen.close()
	check(main.pause.visible and main.get_tree().paused, "closing settings preserves pause")
	main._resume()
	check(not main.get_tree().paused and main.player.controls_enabled, "pause resumes controls")
	main.player.invuln_time = 999.0
	var st: Dictionary = main.player.ammo.brush_pistol
	st.mag = 0
	st.reserve = 1
	main.player.start_reload()
	main.player._finish_reload()
	check(int(st.mag) == 1 and int(st.reserve) == 1, "sidearm remains available with finite magazine")
	main.player.resupply_between_waves()
	for wave in range(1, RunRules.TARGET_WAVES + 1):
		if main.director.current_wave != wave:
			main.director.start_wave(wave)
		main.director.frozen = true
		while not main.director._queue.is_empty():
			main.director._spawn_next()
		var enemies: Array = main.get_tree().get_nodes_in_group("enemies")
		var boss_found := false
		for enemy in enemies:
			if enemy.dead:
				continue
			enemy.frozen = true
			enemy.state = "chase"
			enemy.collision_layer = 4
			boss_found = boss_found or enemy.boss
			if enemy.take_damage(enemy.max_health * 2, Vector3.FORWARD, enemy.aim_point()):
				main.player.credit_kill(enemy.global_position)
		if wave % 5 == 0:
			check(boss_found, "boss spawned on wave %d" % wave)
		check(main.director.count_alive() == 0, "all wave %d enemies defeated" % wave)
		Engine.time_scale = 1.0
		main.director.frozen = false
		main.director._physics_process(0.016)
		if wave == RunRules.TARGET_WAVES:
			break
		var deadline := Time.get_ticks_msec() + 6000
		while Game.state != Game.State.UPGRADE and Time.get_ticks_msec() < deadline:
			await main.get_tree().process_frame
		check(Game.state == Game.State.UPGRADE, "wave %d reaches upgrade" % wave)
		if Game.state != Game.State.UPGRADE:
			main.get_tree().quit(1)
			return
		var choices: Array = main.upgrades._cards.map(func(card): return card.data)
		check(choices.size() == 3, "three upgrade choices")
		var ids := {}
		for choice in choices:
			ids[choice.id] = true
		check(ids.size() == choices.size(), "unique upgrade choices")
		main._on_upgrade_chosen(choices[0])
		await main.get_tree().create_timer(1.05).timeout
	check(Game.state == Game.State.VICTORY and main.game_over.visible, "ten wave victory screen")
	check(Game.completed_waves == 10, "completed wave record")
	main._continue_endless()
	check(Game.endless and Game.wave == 11 and not main.get_tree().paused, "continue into endless wave eleven")
	main.director.stop()
	main.player.invuln_time = 0.0
	main.player.mods.revives = 0
	main.player.take_damage(99999.0)
	await main.get_tree().create_timer(2.1).timeout
	check(main.game_over.visible and Game.state == Game.State.DEAD, "lethal damage reaches result screen")
	print("[beta] RESULT failures=%d kills=%d" % [failures.size(), Game.kills])
	Sfx.shutdown()
	await main.get_tree().create_timer(0.15).timeout
	main.get_tree().quit(0 if failures.is_empty() else 1)
