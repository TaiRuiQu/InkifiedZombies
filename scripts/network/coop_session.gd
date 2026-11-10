extends Node

## Host-authoritative cooperative simulation. NET owns transports and rooms;
## this adapter owns combat actors and snapshots, independent of menu widgets.
const SNAPSHOT_INTERVAL := 0.1
const INPUT_INTERVAL := 0.05
var main: Node3D
var running := false
var connection_lost := false
var actors: Dictionary = {}
var remote_models: Dictionary = {}
var enemy_proxies: Dictionary = {}
var projectile_proxies: Dictionary = {}
var pickup_proxies: Dictionary = {}
var _waiting: Dictionary = {}
var _choices: Dictionary = {}
var _movement_times: Dictionary = {}
var _snapshot_timer := 0.0
var _input_timer := 0.0
var _sequence := 0
var _last_sequence := -1
var _ending := false
var _team_lines := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	NET.message_received.connect(_on_message)
	NET.peer_left.connect(_on_peer_left)
	NET.peer_joined.connect(_on_peer_joined)
	NET.disconnected.connect(_on_disconnected)

func setup(owner_node: Node3D) -> void:
	clear_run()
	main = owner_node

func clear_run() -> void:
	running = false
	connection_lost = false
	actors.clear()
	remote_models.clear()
	enemy_proxies.clear()
	projectile_proxies.clear()
	pickup_proxies.clear()
	_waiting.clear()
	_choices.clear()
	_movement_times.clear()
	_last_sequence = -1
	_ending = false
	_team_lines = ""

func is_client() -> bool:
	return NET.active and not NET.is_host and running

func run_options() -> Dictionary:
	return {"map": Game.selected_map, "difficulty": Game.difficulty, "endless": Game.endless}

func begin_run() -> void:
	if not NET.active:
		return
	running = true
	_ending = false
	main.player.set_meta("peer_id", NET.local_id)
	if NET.is_host:
		actors[NET.local_id] = main.player
		for id in NET.peers:
			if int(id) != NET.local_id:
				_add_actor(int(id))
	else:
		main.director.stop()
	_snapshot_timer = 0.0
	_input_timer = 0.0

func _add_actor(id: int) -> void:
	if actors.has(id) or not is_instance_valid(main):
		return
	var actor: Node3D = load("res://scenes/player.tscn").instantiate()
	actor.name = "CoopPlayer_%d" % id
	actor.position = main.map.player_spawn + Vector3(float(actors.size()) * 1.4, 0, 0)
	actor.set_meta("peer_id", id)
	var previous_mouse_mode := Input.mouse_mode
	main.add_child(actor)
	Input.mouse_mode = previous_mouse_mode
	actor.set_controls(false)
	actor.set_physics_process(false)
	actor.view.visible = false
	actor.camera.current = false
	actor.invuln_time = 3.0
	actor.max_health *= 1.0
	actors[id] = actor
	var model: Node3D = load("res://scripts/network/remote_player.gd").new()
	model.setup(id, String(NET.peers.get(id, {}).get("name", "守墨人")), id % 4)
	main.add_child(model)
	remote_models[id] = model

func _process(delta: float) -> void:
	if not running or not NET.active or not is_instance_valid(main) or not main.is_inside_tree():
		return
	if NET.is_host:
		for id in actors:
			var actor = actors[id]
			if int(id) != NET.local_id and is_instance_valid(actor) and actor.is_inside_tree():
				if actor.dash_time > 0.0 and not get_tree().paused:
					actor.dash_time = maxf(actor.dash_time - delta, 0.0)
					if actor.dash_time == 0.0:
						actor._finish_dash()
				_update_remote_model(int(id), _actor_snapshot(int(id), actor))
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = SNAPSHOT_INTERVAL
			_send_snapshot()
		if not _ending and Game.state == Game.State.PLAYING and not _has_living_actor():
			_ending = true
			NET.send("defeat", {"wave": Game.wave, "kills": Game.kills, "seconds": int(Game.run_time)})
			main._on_player_died(true)
	else:
		_input_timer -= delta
		if _input_timer <= 0.0 and not main.player.dead:
			_input_timer = INPUT_INTERVAL
			NET.send("move", _local_pose())
	if main.player.dead and not _ending:
		_spectate()

func _local_pose() -> Dictionary:
	return {"position": _pack(main.player.global_position), "yaw": main.player.head.rotation.y,
		"pitch": main.player.head.rotation.x, "weapon": main.player.current_weapon, "aim": main.player.aiming,
		"move_input": [Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")],
		"grounded": main.player.is_on_floor(), "crouching": main.player.crouching, "sprinting": main.player.sprinting}

func _actor_snapshot(id: int, actor: Node3D) -> Dictionary:
	return {"id": id, "name": String(NET.peers.get(id, {}).get("name", "守墨人")),
		"position": _pack(actor.global_position), "yaw": actor.head.rotation.y, "pitch": actor.head.rotation.x,
		"health": actor.health, "max_health": actor.max_health, "shield": actor.shield, "max_shield": actor.max_shield,
		"dead": actor.dead, "weapon": actor.current_weapon, "ammo": actor.ammo,
		"owned_weapons": actor.owned_weapons, "skills": actor.skills, "cooldowns": actor.skill_cooldowns,
		"damage_event": {"sequence": actor.damage_sequence, "amount": actor.last_damage_amount,
			"source": _pack(actor.last_damage_position) if actor.last_damage_position != Vector3.INF else [],
			"shield": actor.last_damage_shield},
		"mods": actor.mods, "upgrade_counts": actor.upgrade_counts, "reloading": actor.reloading, "reload_timer": actor.reload_timer, "reload_total": actor.reload_total}

func _send_snapshot() -> void:
	_sequence += 1
	var players: Array = []
	for id in actors:
		if is_instance_valid(actors[id]) and actors[id].is_inside_tree():
			players.append(_actor_snapshot(int(id), actors[id]))
	var enemies: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		enemies.append({"id": enemy.get_instance_id(), "type": enemy.type_id, "elite": enemy.elite,
			"position": _pack(enemy.global_position), "yaw": enemy.rotation.y, "health": enemy.health,
			"max_health": enemy.max_health, "state": enemy.state, "timer": enemy.state_timer,
			"attack_kind": enemy.attack_kind, "behavior": enemy.get_behavior_snapshot(),
			"windup": enemy.windup_total, "velocity": _pack(enemy.velocity), "enraged": enemy.enraged, "age": enemy.time_alive, "phase": enemy._time_offset, "grounded": enemy.is_on_floor()})
	var projectiles: Array = []
	for projectile in get_tree().get_nodes_in_group("projectiles"):
		if not projectile.dead:
			projectiles.append({"id": projectile.get_instance_id(), "position": _pack(projectile.global_position),
				"friendly": projectile.friendly, "radius": projectile.radius,
				"color": [projectile.color.r, projectile.color.g, projectile.color.b]})
	var pickups: Array = []
	for pickup in get_tree().get_nodes_in_group("pickups"):
		pickups.append({"id": pickup.get_instance_id(), "position": _pack(pickup.global_position),
			"kind": pickup.kind, "amount": pickup.amount})
	NET.send("snapshot", {"seq": _sequence, "wave": Game.wave, "kills": Game.kills,
		"seconds": Game.run_time, "remaining": main.director.remaining(), "total": main.director.total_enemies(),
		"players": players, "enemies": enemies, "projectiles": projectiles, "pickups": pickups})
	_build_team_status(players)

func _on_message(sender: int, kind: String, data: Dictionary) -> void:
	if not is_instance_valid(main) or not main.is_inside_tree():
		return
	if NET.is_host:
		if not running or not actors.has(sender):
			return
		var actor = actors[sender]
		if not is_instance_valid(actor) or not actor.is_inside_tree():
			return
		for string_field in ["weapon", "id"]:
			if data.has(string_field) and not data[string_field] is String:
				return
		for number_field in ["yaw", "pitch", "shot_seed", "shot_spread"]:
			if data.has(number_field) and (not (data[number_field] is int or data[number_field] is float) or not is_finite(float(data[number_field]))):
				return
		match kind:
			"move": _accept_pose(sender, actor, data)
			"fire":
				if actor.dead or get_tree().paused:
					return
				_accept_pose(sender, actor, data)
				if data.has("shot_forward"):
					var forward := _unpack(data.shot_forward)
					if forward.length_squared() < 0.5 or forward.normalized().dot(-actor.head.global_transform.basis.z) < 0.95:
						return
				var weapon := String(data.get("weapon", ""))
				if actor.current_weapon != weapon:
					return
				if not actor.reloading and actor.fire_timer <= 0.02 and actor.current_mag() > 0:
					actor._fire_shot(actor.get_weapon_data(), actor.ammo[actor.current_weapon], data)
			"equip":
				var weapon := String(data.get("weapon", ""))
				if not actor.dead and actor.owned_weapons.has(weapon):
					actor.switch_to_index(actor.owned_weapons.find(weapon))
			"reload":
				if not actor.dead and not get_tree().paused:
					actor.start_reload()
			"skill":
				if not actor.dead and not get_tree().paused:
					_accept_look(actor, data)
					_accept_move_input(actor, data)
					var id := String(data.get("id", ""))
					if SkillDB.cast(id, actor):
						NET.send("skill_fx", {"owner": sender, "id": id, "position": _pack(actor.global_position)})
			"melee":
				if not actor.dead and not get_tree().paused:
					actor._melee_attack()
			"upgrade": _accept_upgrade(sender, String(data.get("id", "")))
		return
	if sender != NET.host_id:
		return
	match kind:
		"start":
			_apply_options(data)
			if not main._started:
				main.start_run()
		"restart":
			_apply_options(data)
			Game.auto_start = true
			get_tree().paused = false
			Engine.time_scale = 1.0
			clear_run()
			get_tree().reload_current_scene()
		"snapshot":
			if running:
				_apply_snapshot(data)
		"shot": _remote_shot(data)
		"combat_confirmed":
			main.player.confirm_combat(float(data.get("amount", 0)), bool(data.get("critical", false)), bool(data.get("killed", false)), bool(data.get("headshot", false)))
		"skill_fx":
			if int(data.get("owner", 0)) != NET.local_id:
				VFX.ring(main, _unpack(data.get("position", [])), 3.5, Ink.INDIGO_LIGHT, 0.4)
		"upgrade_open": _open_client_upgrades(int(data.get("wave", 1)), data.get("choices", []))
		"next_wave":
			_waiting.clear()
			main.upgrades.close()
			get_tree().paused = false
			if main.player.dead:
				_revive(main.player)
			main.player.resupply_between_waves()
			Game.set_state(Game.State.PLAYING)
			main.player.set_controls(true)
			main.hud.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			var next_wave := int(data.get("wave", Game.wave + 1))
			Game.wave = next_wave
			main._on_wave_started(next_wave)
		"victory":
			Game.completed_waves = int(data.get("wave", 10))
			Game.wave = Game.completed_waves
			main._show_victory()
		"defeat":
			_ending = true
			main._on_player_died(true)
		"continue":
			Game.endless = true
			main.game_over.close()
			get_tree().paused = false
			Game.set_state(Game.State.PLAYING)
			main.player.set_controls(not main.player.dead)
			main.hud.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _accept_pose(id: int, actor: Node3D, data: Dictionary) -> void:
	if actor.dead or get_tree().paused:
		return
	var position := _unpack(data.get("position", []))
	var now := Time.get_ticks_msec() * 0.001
	var elapsed := clampf(now - float(_movement_times.get(id, now - 0.1)), 0.01, 0.25)
	_movement_times[id] = now
	if position.length() < 32.0 and position.y > -1.0 and position.y < 7.0:
		if actor.global_position.distance_to(position) < 35.0 * elapsed + 0.7:
			if CombatQuery.has_line_of_sight(actor, actor.global_position + Vector3.UP, position + Vector3.UP):
				actor.global_position = position
	_accept_look(actor, data)
	_accept_move_input(actor, data)

func _accept_move_input(actor: Node3D, data: Dictionary) -> void:
	var raw: Variant = data.get("move_input", [0.0, -1.0])
	if raw is Array and raw.size() == 2 and (raw[0] is int or raw[0] is float) and (raw[1] is int or raw[1] is float):
		var direction := Vector2(float(raw[0]), float(raw[1]))
		if is_finite(direction.x) and is_finite(direction.y):
			actor.set_meta("remote_input", direction.limit_length(1.0))

func _accept_look(actor: Node3D, data: Dictionary) -> void:
	var yaw := float(data.get("yaw", 0.0))
	var pitch := float(data.get("pitch", 0.0))
	if is_finite(yaw) and is_finite(pitch):
		actor.head.rotation = Vector3(clampf(pitch, -1.45, 1.45), wrapf(yaw, -PI, PI), 0)
	actor.aiming = bool(data.get("aim", false))
	actor.crouching = bool(data.get("crouching", false))
	actor.sprinting = bool(data.get("sprinting", false))
	actor.set_meta("network_grounded", bool(data.get("grounded", actor.global_position.y < 0.3)))

func _apply_snapshot(data: Dictionary) -> void:
	var sequence := int(data.get("seq", -1))
	if sequence <= _last_sequence:
		return
	_last_sequence = sequence
	Game.wave = int(data.get("wave", 1))
	Game.kills = int(data.get("kills", 0))
	Game.run_time = float(data.get("seconds", 0.0))
	main.director.set_meta("network_remaining", int(data.get("remaining", 0)))
	main.director.set_meta("network_total", int(data.get("total", 0)))
	main.director.wave_active = true
	var players: Array = data.get("players", [])
	for state in players:
		var id := int(state.get("id", 0))
		if id == NET.local_id:
			_reconcile_local(state)
		else:
			_update_remote_model(id, state)
	_build_team_status(players)
	var seen := {}
	for state in data.get("enemies", []):
		var id := int(state.get("id", 0))
		seen[id] = true
		var enemy = enemy_proxies.get(id)
		if not is_instance_valid(enemy):
			enemy = load("res://scenes/enemy.tscn").instantiate()
			enemy.setup(String(state.get("type", "wraith")), Game.wave, bool(state.get("elite", false)))
			enemy.frozen = true
			enemy.position = _unpack(state.get("position", []))
			main.add_child(enemy)
			enemy.set_meta("network_proxy", true)
			enemy.collision_layer = 4
			enemy_proxies[id] = enemy
			enemy.health = float(state.health)
			enemy._time_offset = float(state.get("phase", 0.0))
			if String(state.state) != "spawn":
				enemy.complete_spawn_visual()
		if float(state.health) < enemy.health:
			var amount: float = enemy.health - float(state.health)
			VFX.damage_number(main, enemy.aim_point(), amount)
			enemy.notify_hit_reaction((enemy.global_position - main.player.global_position).normalized(), amount)
			enemy.flash = 1.0
			enemy._apply_flash()
		else:
			enemy.flash = maxf(enemy.flash - 0.4, 0.0)
			enemy._apply_flash()
		enemy.global_position = enemy.global_position.lerp(_unpack(state.position), 0.85)
		enemy.rotation.y = float(state.yaw)
		enemy.health = float(state.health)
		enemy.max_health = float(state.max_health)
		enemy.state = String(state.state)
		enemy.attack_kind = String(state.get("attack_kind", "melee"))
		enemy.state_timer = float(state.timer)
		enemy.windup_total = float(state.windup)
		enemy.velocity = _unpack(state.velocity)
		enemy.enraged = bool(state.enraged)
		enemy.time_alive = float(state.get("age", enemy.time_alive))
		enemy._time_offset = float(state.get("phase", enemy._time_offset))
		enemy.set_meta("audio_grounded", bool(state.get("grounded", false)))
		enemy.apply_behavior_snapshot(state.get("behavior", {}))
		if enemy.boss:
			main.director.boss = enemy
	_remove_missing(enemy_proxies, seen, true)
	_sync_projectiles(data.get("projectiles", []))
	_sync_pickups(data.get("pickups", []))

func _reconcile_local(state: Dictionary) -> void:
	var player = main.player
	var old_health: float = player.health
	player.max_health = float(state.max_health)
	player.max_shield = float(state.max_shield)
	player.health = float(state.health)
	player.shield = float(state.shield)
	player.mods = state.mods.duplicate(true)
	player.skills = state.skills.duplicate(true)
	player.skill_cooldowns = state.cooldowns.duplicate(true)
	var owned: Array[String] = []
	for id in state.owned_weapons:
		owned.append(String(id))
	player.owned_weapons = owned
	player.ammo = state.ammo.duplicate(true)
	player.upgrade_counts = state.get("upgrade_counts", {}).duplicate(true)
	var weapon := String(state.weapon)
	if player.current_weapon != weapon and owned.has(weapon):
		player.switch_to_index(owned.find(weapon))
	if bool(state.reloading) and not player.reloading:
		player.view.start_reload(float(state.reload_total))
	elif not bool(state.reloading) and player.reloading:
		player.view.finish_reload()
	player.reloading = bool(state.reloading)
	player.reload_timer = float(state.reload_timer)
	player.reload_total = float(state.reload_total)
	var authority_position := _unpack(state.position)
	if player.global_position.distance_to(authority_position) > 2.5:
		player.global_position = authority_position
	var damage_event: Dictionary = state.get("damage_event", {})
	var damage_id := int(damage_event.get("sequence", 0))
	if damage_id > player.damage_sequence:
		player.damage_sequence = damage_id
		var source_array: Array = damage_event.get("source", [])
		player.apply_damage_feedback(float(damage_event.get("amount", 0.0)), _unpack(source_array) if source_array.size() == 3 else Vector3.INF, bool(damage_event.get("shield", false)))
	if bool(state.dead) and not player.dead:
		player.mods.revives = 0
		player._on_death()
	elif not bool(state.dead) and player.dead:
		_revive(player)

func _sync_projectiles(states: Array) -> void:
	var seen := {}
	for state in states:
		var id := int(state.id)
		seen[id] = true
		var projectile = projectile_proxies.get(id)
		if not is_instance_valid(projectile):
			projectile = load("res://scripts/combat/projectile.gd").new()
			var c: Array = state.color
			projectile.setup({"friendly": bool(state.friendly), "radius": float(state.radius),
				"color": Color(float(c[0]), float(c[1]), float(c[2]))})
			main.add_child(projectile)
			projectile.set_physics_process(false)
			projectile_proxies[id] = projectile
		projectile.global_position = _unpack(state.position)
	_remove_missing(projectile_proxies, seen)

func _sync_pickups(states: Array) -> void:
	var seen := {}
	for state in states:
		var id := int(state.id)
		seen[id] = true
		var pickup = pickup_proxies.get(id)
		if not is_instance_valid(pickup):
			pickup = load("res://scripts/world/pickup.gd").new()
			pickup.kind = String(state.kind)
			pickup.amount = float(state.amount)
			main.add_child(pickup)
			pickup.set_process(false)
			pickup_proxies[id] = pickup
		pickup.global_position = _unpack(state.position)
		pickup.rotation.y += 0.15
	_remove_missing(pickup_proxies, seen)

func _remove_missing(proxies: Dictionary, seen: Dictionary, death_effect: bool = false) -> void:
	for id in proxies.keys():
		if seen.has(id):
			continue
		var node = proxies[id]
		if is_instance_valid(node):
			if death_effect:
				VFX.burst(main, node.global_position + Vector3.UP, Ink.INK, 14, 4.0, 0.16, 0.5)
			node.queue_free()
		proxies.erase(id)

func _update_remote_model(id: int, state: Dictionary) -> void:
	var model = remote_models.get(id)
	if not is_instance_valid(model):
		model = load("res://scripts/network/remote_player.gd").new()
		model.setup(id, String(state.get("name", "守墨人")), remote_models.size())
		main.add_child(model)
		remote_models[id] = model
	model.update_snapshot(state)

func request_action(kind: String, data: Dictionary = {}) -> void:
	if is_client():
		var payload := _local_pose()
		payload.merge(data, true)
		NET.send(kind, payload)

func shot_fired(actor: Node3D, weapon: Dictionary) -> void:
	if not NET.active or not NET.is_host:
		return
	var actor_id := int(actor.get_meta("peer_id", 1))
	if remote_models.has(actor_id) and is_instance_valid(remote_models[actor_id]):
		remote_models[actor_id].play_shot()
	NET.send("shot", {"owner": int(actor.get_meta("peer_id", 1)), "weapon": actor.current_weapon,
		"position": _pack(actor.camera.global_position), "direction": _pack(-actor.camera.global_transform.basis.z),
		"projectile": bool(weapon.get("projectile", false)), "traces": actor._last_shot_traces})

func _remote_shot(data: Dictionary) -> void:
	if int(data.get("owner", 0)) == NET.local_id:
		return
	var shooter_id := int(data.get("owner", 0))
	if remote_models.has(shooter_id) and is_instance_valid(remote_models[shooter_id]):
		remote_models[shooter_id].play_shot()
	var origin := _unpack(data.get("position", []))
	var direction := _unpack(data.get("direction", [])).normalized()
	var weapon := WeaponDB.get_weapon(String(data.get("weapon", "brush_pistol")))
	var traces: Array = data.get("traces", [])
	for trace in traces:
		VFX.tracer(main, _unpack(trace.get("from", [])), _unpack(trace.get("to", [])), weapon.tracer, 0.018, 0.065)
	VFX.muzzle_flash(main, origin + direction * 0.8, Ink.GOLD, 0.6)
	Sfx.play_at(String(weapon.sound), origin, -5.0)

func confirm_hit(actor: Node3D, amount: float, critical: bool, killed: bool, headshot: bool,
		position: Vector3, direction: Vector3) -> void:
	if not NET.active or not NET.is_host:
		return
	var actor_id := int(actor.get_meta("peer_id", NET.local_id))
	if actor_id == NET.local_id:
		return
	NET.send("combat_confirmed", {"amount": amount, "critical": critical, "killed": killed,
		"headshot": headshot, "position": _pack(position), "direction": _pack(direction)}, actor_id)

func resupply_team() -> void:
	for id in actors:
		if int(id) == NET.local_id:
			continue
		if actors[id].dead:
			_revive(actors[id])
		actors[id].resupply_between_waves()
	if main.player.dead:
		_revive(main.player)

func open_upgrades(wave: int) -> void:
	_waiting.clear()
	_choices.clear()
	for id in actors:
		_waiting[id] = true
		if int(id) == NET.local_id:
			_choices[id] = main.upgrades._cards.map(func(card): return card.data)
		else:
			_choices[id] = UpgradeDB.roll(actors[id], wave, 3)
			NET.send("upgrade_open", {"wave": wave, "choices": _choices[id]}, int(id))

func _open_client_upgrades(wave: int, choices: Array) -> void:
	# Card data is supplied by the host, so unlocks and random rolls agree.
	Game.set_state(Game.State.UPGRADE)
	main.upgrades.open(wave, choices)
	main.player.set_controls(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.hud.visible = false
	get_tree().paused = true

func choose_upgrade(data: Dictionary) -> void:
	main.upgrades.close()
	if NET.is_host:
		_accept_upgrade(NET.local_id, String(data.get("id", "")))
	else:
		NET.send("upgrade", {"id": String(data.get("id", ""))})
	main.hud.visible = true
	main.hud.show_banner("凝 墨", "等待同伴完成修习", UITheme.GOLD, 60.0)

func _accept_upgrade(id: int, upgrade_id: String) -> void:
	if not _waiting.has(id) or not actors.has(id):
		return
	var selected: Dictionary = {}
	for choice in _choices.get(id, []):
		if String(choice.get("id", "")) == upgrade_id:
			selected = choice
	if upgrade_id == "skip_heal":
		selected = {"id": "skip_heal", "effects": {"heal_percent": 0.3}}
	if selected.is_empty():
		return
	actors[id].apply_upgrade(selected)
	_waiting.erase(id)
	if _waiting.is_empty():
		_next_wave()

func _next_wave() -> void:
	get_tree().paused = false
	main.upgrades.close()
	Game.set_state(Game.State.PLAYING)
	main.player.set_controls(true)
	main.hud.visible = true
	main.hud.clear_banner()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	NET.send("next_wave", {"wave": Game.wave + 1})
	main.director.start_wave(Game.wave + 1)

func local_downed() -> void:
	main.hud.show_banner("暂 歇", "队友肃清本波后，你将重新归来", UITheme.INDIGO, 60.0)

func _revive(actor: Node3D) -> void:
	if actor._death_camera_tween and actor._death_camera_tween.is_running():
		actor._death_camera_tween.kill()
	actor.dead = false
	actor.health = actor.max_health * 0.7
	actor.velocity = Vector3.ZERO
	actor.position = main.map.player_spawn
	actor.head.position = Vector3(0, 1.63, 0)
	actor.camera.position = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO
	actor.invuln_time = 3.0
	actor.view.visible = actor == main.player

func _has_living_actor() -> bool:
	for actor in actors.values():
		if is_instance_valid(actor) and not actor.dead:
			return true
	return false

func _spectate() -> void:
	for model in remote_models.values():
		if is_instance_valid(model) and model.visible and not model.dead:
			main.player.camera.global_position = model.global_position + Vector3(0, 3.2, 5.2)
			main.player.camera.look_at(model.global_position + Vector3.UP, Vector3.UP)
			return

func _build_team_status(players: Array) -> void:
	var lines: Array[String] = ["同 守 · %d / 4" % players.size()]
	for player in players:
		lines.append("%s%s · %s" % ["你 · " if int(player.id) == NET.local_id else "", String(player.name),
			"暂歇" if bool(player.dead) else "%d / %d" % [int(player.health), int(player.max_health)]])
	_team_lines = "\n".join(lines)

func team_status() -> String:
	return _team_lines

func _on_peer_joined(id: int) -> void:
	if running and NET.is_host:
		_add_actor(id)
		NET.send("start", run_options(), id)
		if Game.state == Game.State.UPGRADE:
			_waiting[id] = true
			_choices[id] = UpgradeDB.roll(actors[id], Game.wave, 3)
			NET.send("upgrade_open", {"wave": Game.wave, "choices": _choices[id]}, id)
		elif Game.state == Game.State.VICTORY:
			NET.send("victory", {"wave": Game.wave, "kills": Game.kills}, id)
		elif Game.state == Game.State.DEAD:
			NET.send("defeat", {"wave": Game.wave, "kills": Game.kills}, id)

func _on_peer_left(id: int) -> void:
	if actors.has(id):
		if is_instance_valid(actors[id]) and actors[id] != main.player:
			actors[id].queue_free()
		actors.erase(id)
	if remote_models.has(id):
		if is_instance_valid(remote_models[id]):
			remote_models[id].queue_free()
		remote_models.erase(id)
	_waiting.erase(id)
	if running and NET.is_host and Game.state == Game.State.UPGRADE and _waiting.is_empty():
		_next_wave()

func _on_disconnected(reason: String) -> void:
	if running and is_instance_valid(main):
		running = false
		connection_lost = true
		get_tree().paused = true
		main.player.set_controls(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		main.pause.open()
		main.hud.show_banner("墨 路 已 断", reason + " · 归返后重新连接", UITheme.CINNABAR, 60.0)

func _apply_options(data: Dictionary) -> void:
	var map_id := String(data.get("map", "courtyard"))
	Game.selected_map = map_id if MapDB.ids().has(map_id) else "courtyard"
	var difficulty_id := String(data.get("difficulty", "standard"))
	Game.difficulty = difficulty_id if RunRules.DIFFICULTIES.has(difficulty_id) else "standard"
	Game.endless = bool(data.get("endless", false))

func _pack(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]

func _unpack(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3.ZERO
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)):
			return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
