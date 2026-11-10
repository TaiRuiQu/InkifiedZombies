extends SceneTree

## Real scene + two independent Godot processes. Usage:
## Godot --headless --path . --script res://tests/coop_integration.gd -- --role=host --transport=direct --port=18777
## Godot --headless --path . --script res://tests/coop_integration.gd -- --role=client --transport=direct --port=18777
## For relay use --transport=relay --port=18778 --room=COOPTEST with relay listening there.
var _game: Node
var _net: Node
var _coop: Node
var _main: Node3D
var _role := "host"
var _transport := "direct"
var _port := 18777
var _room := "COOPTEST"
var _inbox: Dictionary = {}
var _failed := false
var _remote_id := 0
var _confirmed_hits := 0
var _incoming_directions: Array[Vector3] = []
var _enemy_steps_heard := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): _role = arg.trim_prefix("--role=")
		elif arg.begins_with("--transport="): _transport = arg.trim_prefix("--transport=")
		elif arg.begins_with("--port="): _port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--room="): _room = arg.trim_prefix("--room=")
	_run.call_deferred()

func _run() -> void:
	_game = root.get_node("Game")
	_net = root.get_node("NET")
	_coop = root.get_node("Coop")
	var watchdog := create_timer(35.0)
	watchdog.timeout.connect(func(): _fail("whole-test timeout"))
	_game.auto_start = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_net.message_received.connect(_receive)
	await create_timer(0.5).timeout
	var result: Error
	if _role == "host":
		result = _net.host_direct(_port, "审计房主") if _transport == "direct" else _net.host_relay("ws://127.0.0.1:%d/ws" % _port, _room, "beta", "审计房主")
	else:
		result = _net.join_direct("127.0.0.1", _port, "审计队友") if _transport == "direct" else _net.join_relay("ws://127.0.0.1:%d/ws" % _port, _room, "beta", "审计队友")
	if result != OK:
		_fail("transport start failed: %s" % error_string(result))
		return
	print("[coop:%s] connecting transport=%s port=%d" % [_role, _transport, _port])
	if not await _until(func(): return _net.active and _net.peers.size() == 2, "two authenticated peers"):
		return
	var ping_peer: int = _net.peers.keys().filter(func(id): return int(id) != _net.local_id)[0]
	if not await _until(func(): return _net.latency_ms(ping_peer) >= 0, "real round-trip latency measurement"):
		return
	if not _check(_net.connection_latency_text().contains("ms"), "connection latency has milliseconds"):
		return
	print("[coop:%s] PASS measured RTT %s" % [_role, _net.latency_text(ping_peer)])
	if _role == "host":
		await _host()
	else:
		await _client()

func _host() -> void:
	for id in _net.peers:
		if int(id) != _net.local_id:
			_remote_id = int(id)
	if not await _until(func(): return bool(_net.peers.get(_remote_id, {}).get("ready", false)), "client ready"):
		return
	_main.start_coop_run()
	_main.director.stop()
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	if not await _until(func(): return _coop.running and _coop.actors.size() == 2, "host actors"):
		return
	var actor: Node3D = _coop.actors[_remote_id]
	actor.invuln_time = 30.0
	_main.player.invuln_time = 30.0
	actor.unlock_weapon("wolf_smg")
	var enemy = _main.director.debug_spawn("wraith", Vector3(0.5, 0.05, 10.0))
	enemy.frozen = true
	enemy.state = "chase"
	enemy.collision_layer = 4
	enemy.max_health = 500.0
	enemy.health = 500.0
	_net.send("coop_audit", {"phase": "combat", "enemy_id": enemy.get_instance_id()})
	if not await _until(func(): return _inbox.has("combat_sent"), "client move and fire"):
		return
	if not await _until(func(): return enemy.health < 500.0, "authoritative shot damaged enemy"):
		return
	if not _check(actor.current_weapon == "wolf_smg", "remote weapon switch"):
		return
	if not _check(int(actor.ammo["wolf_smg"].mag) == 34, "one network fire consumed one authoritative round"):
		return
	if not _check(absf(actor.global_position.x - 0.5) < 1.0, "remote movement reached authority"):
		return
	print("[coop:host] PASS combat hp=%.1f remote_ammo=%d remote_x=%.2f" % [enemy.health, actor.ammo["wolf_smg"].mag, actor.global_position.x])
	# A transport can spread packets across frames. Check the host rate guard
	# deterministically within one authority frame after proving real network fire.
	actor.fire_timer = 0.0
	var before_burst := int(actor.ammo["wolf_smg"].mag)
	var burst := {"weapon": "wolf_smg", "yaw": actor.head.rotation.y, "pitch": actor.head.rotation.x}
	for i in 3:
		_coop._on_message(_remote_id, "fire", burst)
	if not _check(int(actor.ammo["wolf_smg"].mag) == before_burst - 1, "authority rejected same-frame duplicate fire"):
		return
	enemy.frozen = false
	_net.send("coop_audit", {"phase": "enemy_motion"})
	if not await _until(func(): return _inbox.has("enemy_steps_seen"), "client hears snapshot-driven enemy footsteps"):
		return
	enemy.frozen = true
	print("[coop:host] PASS client snapshot-driven enemy location audio")
	var leaper: Node3D = _main.director.debug_spawn("leaper", Vector3(5.0, 0.05, 10.0))
	var reaver: Node3D = _main.director.debug_spawn("reaver", Vector3(-1.0, 0.05, 13.7))
	_net.send("coop_audit", {"phase": "special_attacks", "leaper": leaper.get_instance_id(), "reaver": reaver.get_instance_id()})
	if not await _until(func(): return _inbox.has("special_attacks_seen"), "client receives both special attack states and locked target"):
		return
	leaper.queue_free()
	reaver.queue_free()
	print("[coop:host] PASS special attack snapshot presentation")
	actor.skills.talisman = true
	_main.player.skills.nova = true
	load("res://scripts/skills/skill_db.gd").cast("nova", _main.player)
	_net.send("coop_audit", {"phase": "spell_test"})
	if not await _until(func(): return _inbox.has("spells_seen"), "host cast and remote talisman impact effects"):
		return
	if not _check(float(actor.skill_cooldowns.talisman) > 0.0, "remote spell cast consumed authoritative cooldown"):
		return
	print("[coop:host] PASS host spell broadcast and client fire talisman")
	actor.invuln_time = 0.0
	actor.take_damage(17.0, null, 0.0, actor.global_position + Vector3(8, 0, -5))
	actor.invuln_time = 30.0
	_net.send("coop_audit", {"phase": "health", "health": actor.health})
	if not await _until(func(): return _inbox.has("health_seen"), "remote health reconciliation"):
		return
	actor.mods.revives = 0
	actor._on_death()
	_net.send("coop_audit", {"phase": "downed"})
	if not await _until(func(): return _inbox.has("downed_seen"), "remote downed reconciliation"):
		return
	if not _check(not _main._dying, "one downed teammate must not end the run"):
		return
	enemy.queue_free()
	_main.director.stop()
	_main._on_wave_cleared(1)
	if not await _until(func(): return _game.state == _game.State.UPGRADE and not _main.upgrades._cards.is_empty(), "host upgrade screen"):
		return
	if not await _until(func(): return _inbox.has("upgrade_seen"), "client upgrade screen"):
		return
	if not _check(not actor.dead and actor.health > 0.0, "team revived after clearing wave"):
		return
	for attempt in 3:
		_main.upgrades._on_refresh()
		if not _check(_main.upgrades.refreshes_left == 2 - attempt and int(_coop._refreshes[_net.local_id]) == 2 - attempt, "host refresh is authoritative"):
			return
	if not await _until(func(): return _inbox.has("refresh_seen"), "client completed three refreshes"):
		return
	if not _check(int(_coop._refreshes[_remote_id]) == 0, "remote refresh budget independent of host"):
		return
	var remote_choices: Array = _coop._choices[_remote_id].duplicate(true)
	_coop._accept_refresh(_remote_id)
	if not _check(_coop._choices[_remote_id] == remote_choices and int(_coop._refreshes[_remote_id]) == 0, "authority rejects fourth remote refresh"):
		return
	_main._on_upgrade_chosen(_main.upgrades._cards[0].data)
	if not _check(_coop._waiting.has(_remote_id), "host waits for teammate choice"):
		return
	_net.send("coop_audit", {"phase": "choose_upgrade"})
	if not await _until(func(): return _game.wave == 2 and _game.state == _game.State.PLAYING and not paused, "both choices advanced wave two"):
		return
	if not _check(not actor.upgrade_counts.is_empty(), "remote upgrade applied by authority"):
		return
	_main.director.stop()
	_net.send("coop_audit", {"phase": "wave_two"})
	if not await _until(func(): return _inbox.has("wave_two_seen"), "client next wave and revive"):
		return
	print("[coop:host] PASS upgrade wait, teammate revival and wave two")
	var old_scene_id := _main.get_instance_id()
	_net.send("coop_audit", {"phase": "restart_incoming"})
	_main._restart_run()
	if not await _until(func(): return is_instance_valid(current_scene) and current_scene.get_instance_id() != old_scene_id and current_scene._started and _coop.running, "host scene restart"):
		return
	_main = current_scene
	_main.director.stop()
	for player in _coop.actors.values():
		player.invuln_time = 30.0
	if not await _until(func(): return _inbox.has("restart_seen"), "client scene restart"):
		return
	print("[coop:host] PASS both scenes reloaded while transport survived")
	_net.send("defeat", {"wave": _game.wave, "kills": _game.kills, "seconds": int(_game.run_time)})
	_main._on_player_died(true)
	if not await _until(func(): return _main.game_over.visible and _inbox.has("defeat_seen"), "both defeat screens"):
		return
	_net.send("coop_audit", {"phase": "done"})
	await create_timer(0.3).timeout
	print("[coop:host] PASS complete transport=%s" % _transport)
	_net.leave()
	root.get_node("Sfx").shutdown()
	await create_timer(0.15).timeout
	quit(0)

func _client() -> void:
	_main.player.combat_feedback.connect(_on_confirmed_hit)
	_main.player.damage_direction.connect(_on_incoming_direction)
	root.get_node("Sfx").cue_started.connect(_on_enemy_cue)
	_net.set_ready(true)
	if not await _until(func(): return _coop.running and _main._started and _coop._last_sequence > 0, "client auto-start and snapshot"):
		return
	if not await _until(func(): return _inbox.has("combat") and _main.player.owned_weapons.has("wolf_smg") and _main.player.current_weapon == "wolf_smg" and not _coop.enemy_proxies.is_empty(), "enemy and weapon snapshots"):
		return
	var enemy_id := int(_inbox.combat.enemy_id)
	if not await _until(func(): return _coop.enemy_proxies.has(enemy_id), "chosen enemy proxy"):
		return
	if not _check(_main.player.view.weapon_id == "wolf_smg", "authoritative weapon snapshot rebuilt the local view"):
		return
	_main.player.global_position.x = 0.5
	await create_timer(0.3).timeout
	var enemy: Node3D = _coop.enemy_proxies[enemy_id]
	_main.player.head.look_at(enemy.aim_point(), Vector3.UP)
	_main.player.reloading = false
	_main.player.fire_timer = 0.0
	_main.player._fire_shot(_main.player.get_weapon_data(), _main.player.ammo["wolf_smg"])
	_net.send("coop_audit", {"phase": "combat_sent"})
	if not await _until(func(): return _inbox.has("enemy_motion") and _enemy_steps_heard > 0, "moving enemy spatial sound on client"):
		return
	_net.send("coop_audit", {"phase": "enemy_steps_seen"})
	print("[coop:client] PASS enemy location audio from remote motion")
	if not await _until(func(): return _inbox.has("special_attacks"), "host special attack fixture"):
		return
	var observed := {"leap": false, "spin": false}
	if not await _until(func():
		var message: Dictionary = _inbox.special_attacks
		var leaper = _coop.enemy_proxies.get(int(message.leaper))
		var reaver = _coop.enemy_proxies.get(int(message.reaver))
		if is_instance_valid(leaper) and leaper.state == "leap":
			var custom: Dictionary = leaper.get_behavior_snapshot()
			observed.leap = custom.get("landing", []).size() == 3 and leaper.frozen
		if is_instance_valid(reaver) and reaver.state == "spin":
			observed.spin = not reaver.get_behavior_snapshot().is_empty() and reaver.frozen
		return observed.leap and observed.spin,
		"both special proxy attacks animate with behavior data"):
		return
	_net.send("coop_audit", {"phase": "special_attacks_seen"})
	print("[coop:client] PASS leap target and whirlwind state arrive from authority")
	if not await _until(func(): return _inbox.has("spell_test") and _inbox.has("host_spell") and _main.player.skills.talisman, "host spell effect and talisman unlock"):
		return
	_main.player.head.look_at(_main.player.position + Vector3(0, 0, -4), Vector3.UP)
	load("res://scripts/skills/skill_db.gd").cast("talisman", _main.player)
	if not await _until(func(): return _inbox.has("spell_bloom"), "authoritative talisman impact effect"):
		return
	_net.send("coop_audit", {"phase": "spells_seen"})
	print("[coop:client] PASS host cast and fire impact visual effects")
	if not await _until(func(): return _inbox.has("health"), "host damage signal"):
		return
	if not await _until(func(): return absf(_main.player.health - float(_inbox.health.health)) < 0.1, "health snapshot"):
		return
	if not await _until(func(): return _confirmed_hits > 0 and not _incoming_directions.is_empty(), "confirmed hit and directional damage events"):
		return
	if not _check(_incoming_directions[0].x > _main.player.global_position.x, "client damage direction matches authority world source"):
		return
	print("[coop:client] PASS authoritative hit confirmation and directional hurt")
	_net.send("coop_audit", {"phase": "health_seen"})
	if not await _until(func(): return _inbox.has("downed") and _main.player.dead, "downed snapshot"):
		return
	_net.send("coop_audit", {"phase": "downed_seen"})
	if not await _until(func(): return _game.state == _game.State.UPGRADE and not _main.upgrades._cards.is_empty(), "client upgrade open"):
		return
	_net.send("coop_audit", {"phase": "upgrade_seen"})
	for attempt in 3:
		_main.upgrades._on_refresh()
		if not await _until(func(): return not _main.upgrades._refresh_pending, "client refresh response while paused"):
			return
		if not _check(_main.upgrades.refreshes_left == 2 - attempt and _main.upgrades._cards.size() == 3, "client receives authoritative refresh cards and charges"):
			return
	_net.send("coop_audit", {"phase": "refresh_seen"})
	if not await _until(func(): return _inbox.has("choose_upgrade"), "host own choice completed"):
		return
	_main._on_upgrade_chosen(_main.upgrades._cards[0].data)
	if not await _until(func(): return _inbox.has("wave_two") and _game.wave == 2 and _game.state == _game.State.PLAYING and not _main.player.dead and not paused, "client wave two and revival"):
		return
	var old_scene_id := _main.get_instance_id()
	_net.send("coop_audit", {"phase": "wave_two_seen"})
	if not await _until(func(): return _inbox.has("restart_incoming"), "host restart command"):
		return
	if not await _until(func(): return is_instance_valid(current_scene) and current_scene.get_instance_id() != old_scene_id and current_scene._started and _coop.running, "client scene restart"):
		return
	_main = current_scene
	if not await _until(func(): return _coop._last_sequence > 0, "restarted scene snapshots"):
		return
	_net.send("coop_audit", {"phase": "restart_seen"})
	if not await _until(func(): return _game.state == _game.State.DEAD and _main.game_over.visible, "client defeat screen"):
		return
	_net.send("coop_audit", {"phase": "defeat_seen"})
	if not await _until(func(): return _inbox.has("done"), "host completed audit"):
		return
	print("[coop:client] PASS complete transport=%s" % _transport)
	_net.leave()
	root.get_node("Sfx").shutdown()
	await create_timer(0.15).timeout
	quit(0)

func _receive(_sender: int, kind: String, data: Dictionary) -> void:
	if kind == "skill_fx" and int(data.get("owner", 0)) == 1 and data.get("id", "") == "nova":
		_inbox["host_spell"] = data
		_check(not get_nodes_in_group("spell_effects").is_empty(), "host nova creates client-side visual")
	elif kind == "spell_impact":
		_inbox["spell_bloom"] = data
		_check(not get_nodes_in_group("spell_effects").is_empty(), "authoritative impact creates client-side visual")
	if kind == "coop_audit":
		_inbox[String(data.get("phase", ""))] = data
		print("[coop:%s] phase=%s wave=%d state=%d paused=%s" % [_role, data.get("phase", ""), _game.wave, _game.state, str(paused)])

func _until(condition: Callable, label: String, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call():
		if _failed:
			return false
		if Time.get_ticks_msec() > deadline:
			_fail("timed out: " + label)
			return false
		await process_frame
	return true

func _check(condition: bool, label: String) -> bool:
	if not condition:
		_fail(label)
	return condition

func _fail(reason: String) -> void:
	if _failed:
		return
	_failed = true
	print("[coop:%s] context wave=%d state=%d paused=%s inbox=%s" % [_role, _game.wave, _game.state, str(paused), str(_inbox.keys())])
	if is_instance_valid(_main):
		print("[coop:%s] player dead=%s health=%.1f upgrade_open=%s" % [_role, str(_main.player.dead), _main.player.health, str(_main.upgrades.visible)])
	push_error("[coop:%s] FAIL %s" % [_role, reason])
	_net.leave()
	quit(1)


func _on_confirmed_hit(_amount: float, _critical: bool, _killed: bool, _headshot: bool) -> void:
	_confirmed_hits += 1


func _on_incoming_direction(_amount: float, source_position: Vector3, _shield: bool) -> void:
	_incoming_directions.append(source_position)


func _on_enemy_cue(id: String, _position: Vector3, kind: String, _occluded: bool) -> void:
	if kind == "step" and id == "enemy_step_wraith":
		_enemy_steps_heard += 1
