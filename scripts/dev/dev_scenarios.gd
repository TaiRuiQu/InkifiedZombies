extends RefCounted

var main: Node3D

func _init(owner_node: Node3D) -> void:
	main = owner_node


func _run_autoshot() -> void:
	await main.get_tree().create_timer(0.9).timeout
	await _capture("title")

	main.director.frozen = true
	main.start_run()
	await main.get_tree().create_timer(1.0).timeout

	var lineup := [
		["wraith", Vector3(-5.0, 0.05, 6.0)],
		["puppet", Vector3(-2.5, 0.05, 5.0)],
		["mask", Vector3(0.0, 0.05, 4.2)],
		["brute", Vector3(3.0, 0.05, 5.5)],
		["lantern", Vector3(5.5, 0.05, 6.0)],
	]
	for item in lineup:
		var e = main.director.debug_spawn(String(item[0]), item[1], String(item[0]) != "mask")
		e.frozen = true
		e.state = "chase"
		e.collision_layer = 4
		e.rotation.y = PI
	main.player.head.rotation.y = 0.0
	main.player.head.rotation.x = -0.03
	await main.get_tree().create_timer(0.9).timeout
	main.hud.clear_banner()
	await _capture("gameplay")

	main.player._fire_shot(main.player.get_weapon_data(), main.player.ammo[main.player.current_weapon])
	await main.get_tree().create_timer(0.06).timeout
	await _capture("combat")

	var choices := UpgradeDB.roll(main.player, 3, 3)
	main.hud.visible = false
	main.upgrades.open(3, choices)
	main.get_tree().paused = true
	await main.get_tree().create_timer(0.9).timeout
	await _capture("upgrade")
	main.get_tree().paused = false
	main.upgrades.close()
	main.hud.visible = true

	main.director.frozen = true
	var boss = main.director.debug_spawn("boss", Vector3(0, 0.05, 4.0))
	boss.frozen = true
	boss.state = "chase"
	boss.collision_layer = 4
	boss.rotation.y = PI
	Game.wave = 5
	main.director.boss = boss
	main.director.boss_spawned.emit(boss)
	main.hud.clear_banner()
	await main.get_tree().create_timer(0.8).timeout
	await _capture("boss")

	main.get_tree().paused = true
	main.game_over.open(7, 137, 402, 9)
	main.hud.visible = false
	main.player.view.visible = false
	await main.get_tree().create_timer(0.7).timeout
	await _capture("gameover")
	main.get_tree().quit()


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := "res://dev_shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var img := main.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, shot_name])
	print("[autoshot] ", shot_name)
	await main.get_tree().create_timer(0.05).timeout


func _run_smoke() -> void:
	await main.get_tree().create_timer(0.4).timeout
	main.start_run()
	await main.get_tree().create_timer(2.2).timeout
	var last_state := -1
	for i in 120:
		if main.player.dead:
			break
		if Game.state == Game.State.UPGRADE:
			if not main.upgrades._cards.is_empty():
				print("[smoke] choosing upgrade: ", main.upgrades._cards[0].data.get("name", "?"))
				main._on_upgrade_chosen(main.upgrades._cards[0].data)
				await main.get_tree().create_timer(1.8).timeout
			continue
		var target = _nearest_enemy()
		if target and is_instance_valid(target):
			main.player.head.look_at(target.aim_point(), Vector3.UP)
			main.player._fire_shot(main.player.get_weapon_data(), main.player.ammo[main.player.current_weapon])
		if i % 20 == 0:
			print("[smoke] t=%.1f state=%d wave=%d hp=%.1f shield=%.1f kills=%d alive=%d" % [
				i * 0.2, Game.state, Game.wave, main.player.health, main.player.shield,
				Game.kills, main.director.count_alive()
			])
		await main.get_tree().create_timer(0.2).timeout
	print("[smoke] FINAL state=%d wave=%d hp=%.1f kills=%d alive=%d dead=%s" % [
		Game.state, Game.wave, main.player.health, Game.kills, main.director.count_alive(), str(main.player.dead)
	])
	await main.get_tree().create_timer(0.3).timeout
	main.get_tree().quit()


func _nearest_enemy() -> Node:
	var best: Node = null
	var best_d := 9999.0
	for e in main.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.dead:
			continue
		var d: float = main.player.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _run_smoke_idle() -> void:
	await main.get_tree().create_timer(0.4).timeout
	main.start_run()
	await main.get_tree().create_timer(22.0).timeout
	print("[smokeidle] state=%d wave=%d hp=%.1f shield=%.1f kills=%d alive=%d dead=%s" % [
		Game.state, Game.wave, main.player.health, main.player.shield, Game.kills,
		main.director.count_alive(), str(main.player.dead)
	])
	await main.get_tree().create_timer(0.3).timeout
	main.get_tree().quit()


func _run_smoke_boss() -> void:
	await main.get_tree().create_timer(0.4).timeout
	main.start_run()
	await main.get_tree().create_timer(0.6).timeout
	main.director.stop()
	main.director.start_wave(5)
	await main.get_tree().create_timer(2.5).timeout
	var b = main.director.boss
	if is_instance_valid(b):
		b.take_damage(b.max_health * 0.54, Vector3.FORWARD, b.aim_point(), false, 0.0, 0.0)
		print("[smokeboss] boss hp %.0f/%.0f enraged=%s" % [b.health, b.max_health, str(b.enraged)])
	await main.get_tree().create_timer(18.0).timeout
	var boss_hp := -1.0
	if is_instance_valid(main.director.boss) and not main.director.boss.dead:
		boss_hp = main.director.boss.health
	print("[smokeboss] state=%d wave=%d hp=%.1f player_dead=%s boss_hp=%.0f alive=%d kills=%d" % [
		Game.state, Game.wave, main.player.health, str(main.player.dead), boss_hp,
		main.director.count_alive(), Game.kills
	])
	await main.get_tree().create_timer(0.3).timeout
	main.get_tree().quit()


func _run_smoke_test() -> void:
	await main.get_tree().create_timer(0.4).timeout
	main.start_run()
	await main.get_tree().create_timer(0.8).timeout
	for id in ["ink_shotgun", "wolf_smg", "cinnabar_rifle", "ink_launcher", "thunder_crossbow"]:
		main.player.unlock_weapon(id)
	var effects := [
		{"id": "t_dmg", "effects": {"damage_mult_add": 0.2, "fire_rate_mult_add": 0.1}},
		{"id": "t_hp", "effects": {"max_health_add": 40.0, "shield_add": 40.0}},
		{"id": "t_dash", "effects": {"unlock": "dash", "dash_cd_mult_add": -0.25, "dash_damage_add": 40.0}},
		{"id": "t_nova", "effects": {"unlock": "nova", "nova_radius_add": 1.5, "nova_damage_mult_add": 0.3}},
		{"id": "t_talisman", "effects": {"unlock": "talisman", "talisman_radius_add": 1.0, "talisman_damage_mult_add": 0.4}},
		{"id": "t_crit", "effects": {"crit_chance_add": 0.25, "crit_mult_add": 0.5}},
		{"id": "t_pierce", "effects": {"pierce_add": 2, "multishot_add": 1}},
		{"id": "t_chain", "effects": {"chain_add": 1, "explosive_add": 1}},
		{"id": "t_killnova", "effects": {"kill_nova_add": 1, "revive_add": 1, "lifesteal_add": 0.05}},
		{"id": "t_misc", "effects": {"heal_on_kill_add": 4.0, "slow_on_hit_add": 0.25, "thorns_add": 10.0, "ammo_regen_add": 2.0}},
	]
	for e in effects:
		main.player.apply_upgrade(e)
	main.player.health = main.player.max_health
	main.player.shield = main.player.max_shield
	var center: Vector3 = main.player.global_position
	for i in 8:
		var a := TAU * float(i) / 8.0
		var e = main.director.debug_spawn("wraith", center + Vector3(cos(a) * 4.5, 0.05, sin(a) * 4.5), i % 3 == 0)
		e.frozen = false
	await main.get_tree().create_timer(0.6).timeout
	main.player._start_dash()
	await main.get_tree().create_timer(0.3).timeout
	main.player._cast_nova()
	await main.get_tree().create_timer(0.35).timeout
	main.player._throw_talisman()
	await main.get_tree().create_timer(0.5).timeout
	main.player._melee_attack()
	await main.get_tree().create_timer(0.3).timeout
	var target = _nearest_enemy()
	if target:
		main.player.head.look_at(target.aim_point(), Vector3.UP)
	for i in main.player.owned_weapons.size():
		main.player.switch_to_index(i)
		await main.get_tree().create_timer(0.2).timeout
		if target and is_instance_valid(target):
			main.player.head.look_at(target.aim_point(), Vector3.UP)
		main.player._fire_shot(main.player.get_weapon_data(), main.player.ammo[main.player.current_weapon])
		await main.get_tree().create_timer(0.3).timeout
	await main.get_tree().create_timer(1.2).timeout
	print("[smoketest] hp=%.1f shield=%.1f maxhp=%.1f maxshield=%.1f skills=%s weapons=%d kills=%d alive=%d state=%d" % [
		main.player.health, main.player.shield, main.player.max_health, main.player.max_shield,
		str(main.player.skills), main.player.owned_weapons.size(), Game.kills,
		main.director.count_alive(), Game.state
	])
	await main.get_tree().create_timer(0.3).timeout
	main.get_tree().quit()
