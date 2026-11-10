extends SceneTree

## Spatial warnings are exercised through real Enemy nodes and their attached
## audio component. A captured playback signal observes the admitted cues.
var _main: Node3D
var _world: Node3D
var _player: Node3D
var _sfx: Node
var _game: Node
var _events: Array[Dictionary] = []
var _checks := 0
var _failures: Array[String] = []
const ORIGIN := Vector3(0, 30, 0)

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, text: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(text)
		push_error("[enemy-audio] FAIL " + text)
	return condition

func _run() -> void:
	_sfx = root.get_node("Sfx")
	_game = root.get_node("Game")
	_game._test_profile = true
	root.get_node("NET").leave()
	if not _check(_sfx.has_signal("cue_started") and _sfx.has_method("play_enemy_cue"), "spatial warning service is available"):
		quit(1)
		return
	_sfx.connect("cue_started", _on_cue)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_main.director.stop()
	_main.title.close()
	_player = _main.player
	_player.set_controls(false)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.position = ORIGIN
	_player.camera.current = true
	_player.head.rotation = Vector3.ZERO
	_world = Node3D.new()
	_main.add_child(_world)
	_box(Vector3(200, 0.5, 200), ORIGIN - Vector3.UP * 0.25)
	_game.set_state(_game.State.PLAYING)
	await physics_frame
	await physics_frame
	await _test_stationary_and_cadence()
	await _test_six_profiles()
	await _test_state_gates()
	await _test_spatial_position_and_cover()
	await _test_same_source_attack()
	await _test_crowd_and_channel_isolation()
	_world.free()
	_sfx.shutdown()
	await create_timer(0.20).timeout
	print("[enemy-audio] RESULT checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_stationary_and_cadence() -> void:
	var enemy := _enemy("wraith", ORIGIN + Vector3(0, 0, -5))
	var component := _component(enemy)
	if not _check(component != null, "real Enemy owns an audio component"):
		enemy.free()
		return
	_events.clear()
	for index in 20:
		_tick(component, 0.05)
		await create_timer(0.05).timeout
	_check(_count("step") == 0, "stationary enemy does not fabricate footsteps")
	await _stop_voices()
	_events.clear()
	await _move(enemy, component, 1.8, 2.0)
	var slow_count := _count("step")
	_check(slow_count >= 2, "actual slow displacement produces distance-based steps")
	enemy.free()
	await _stop_voices()
	enemy = _enemy("wraith", ORIGIN + Vector3(0, 0, -5))
	component = _component(enemy)
	_events.clear()
	await _move(enemy, component, 4.8, 2.0)
	var fast_count := _count("step")
	_check(fast_count > slow_count, "faster enemy covers more strides in the same time")
	_events.clear()
	enemy.global_position += Vector3.RIGHT * 15.0
	_tick(component, 0.05)
	_check(_count("step") <= 1, "snapshot teleport cannot burst a backlog of footsteps")
	enemy.free()
	await _stop_voices()
	print("[enemy-audio] cadence checked slow=%d fast=%d" % [slow_count, fast_count])

func _test_six_profiles() -> void:
	for id in EnemyDB.ids():
		var enemy := _enemy(id, ORIGIN + Vector3(0, 0, -5))
		var component := _component(enemy)
		var profile: Dictionary = component.get_profile()
		var expected_roar: String = profile.roar_id
		var expected_step: String = profile.step_id
		_check(not expected_roar.is_empty() and not expected_step.is_empty() and _sfx.has_sound(expected_roar) and _sfx.has_sound(expected_step), id + " has playable configured movement and cry assets")
		if id in ["wraith", "puppet", "brute", "mask", "lantern", "boss"]:
			_check(expected_roar == "enemy_" + id and expected_step == "enemy_step_" + id, id + " retains its distinct original audio family")
		_events.clear()
		_request_roar(component)
		_check(_has_event(expected_roar, "roar"), id + " selects its configured positional cry")
		await _stop_voices()
		_events.clear()
		await _move(enemy, component, 2.5, 1.2)
		_check(_has_event(expected_step, "step"), id + " selects its configured movement sound")
		enemy.free()
		await _stop_voices()
	print("[enemy-audio] %d enemy profiles checked" % EnemyDB.ids().size())

func _test_state_gates() -> void:
	for gate in ["dead", "spawn", "title", "paused", "distant"]:
		var enemy := _enemy("puppet", ORIGIN + Vector3(0, 0, -5))
		var component := _component(enemy)
		match gate:
			"dead": enemy.dead = true
			"spawn": enemy.state = "spawn"
			"title": _game.set_state(_game.State.TITLE)
			"paused":
				_game.set_state(_game.State.PAUSED)
				paused = true
			"distant": enemy.position = ORIGIN + Vector3(0, 0, -100)
		_events.clear()
		enemy.position += Vector3.RIGHT * 1.5
		_tick(component, 1.0)
		_request_roar(component)
		_check(_events.is_empty(), gate + " suppresses enemy warning emission")
		paused = false
		_game.set_state(_game.State.PLAYING)
		enemy.free()
		await _stop_voices()
	# A frozen network proxy still carries real snapshot displacement.
	var proxy := _enemy("puppet", ORIGIN + Vector3(0, 0, -5))
	proxy.set_meta("network_proxy", true)
	proxy.frozen = true
	_events.clear()
	await _move(proxy, _component(proxy), 3.5, 1.2)
	_check(_count("step") > 0, "frozen remote proxy movement still supplies positional steps")
	proxy.free()
	await _stop_voices()
	print("[enemy-audio] game-state / distance / proxy gates checked")

func _test_spatial_position_and_cover() -> void:
	var enemy := _enemy("brute", ORIGIN + Vector3(4, 0, 2))
	var position := enemy.global_position + Vector3.UP * 1.3
	_events.clear()
	var accepted: bool = _sfx.play_enemy_cue("enemy_brute", position, {"kind": "roar", "source": enemy, "follow": true, "offset": Vector3.UP * 1.3})
	_check(accepted and _has_event("enemy_brute", "roar"), "near enemy behind the camera remains audible")
	if not _events.is_empty():
		_check((_events.back().position as Vector3).distance_to(position) < 0.01, "right/rear cue preserves actual world position")
	var clear_voice := _voice_at(position)
	var clear_db: float = clear_voice.volume_db if clear_voice != null else -100.0
	_check(clear_voice != null, "accepted cue uses a real spatial voice")
	if clear_voice != null:
		enemy.position += Vector3.RIGHT
		await process_frame
		await process_frame
		_check(clear_voice.global_position.x > position.x + 0.8, "voice follows living source instead of remaining at old cue position")
	enemy.free()
	await _stop_voices()
	enemy = _enemy("brute", ORIGIN + Vector3(4, 0, 2))
	var wall := _box(Vector3(0.35, 5, 6), ORIGIN + Vector3(2, 1.6, 1))
	await physics_frame
	await physics_frame
	_events.clear()
	accepted = _sfx.play_enemy_cue("enemy_brute", position, {"kind": "roar", "source": enemy, "follow": true, "offset": Vector3.UP * 1.3})
	_check(accepted and not _events.is_empty() and bool(_events.back().occluded), "wall attenuates rather than erases nearby threat cue")
	var covered_voice := _voice_at(position)
	if covered_voice != null and clear_voice != null:
		_check(covered_voice.volume_db < clear_db - 3.0, "occluded cue has lower gain than open cue")
		_check(covered_voice.bus == "EnemyMuffled", "covered voice reaches the dedicated muffled bus")
	var muffled := AudioServer.get_bus_index("EnemyMuffled")
	var lowpass: AudioEffect = AudioServer.get_bus_effect(muffled, 0) if muffled >= 0 and AudioServer.get_bus_effect_count(muffled) > 0 else null
	_check(lowpass is AudioEffectLowPassFilter and lowpass.cutoff_hz < 2000.0, "occlusion low-pass retains a muffled location cue")
	wall.free()
	enemy.free()
	await _stop_voices()
	var left_enemy := _enemy("mask", ORIGIN + Vector3(-4, 0, -3))
	position = left_enemy.global_position + Vector3.UP * 1.3
	_events.clear()
	_check(_sfx.play_enemy_cue("enemy_mask", position, {"kind": "roar", "source": left_enemy}), "left enemy cry is admitted")
	_check(not _events.is_empty() and (_events.back().position as Vector3).x < _player.global_position.x, "left cue remains on correct side of listener")
	_check(_sfx.enemy_voice_count() > 0, "live threat voice is playing before pause")
	_game.set_state(_game.State.PAUSED)
	paused = true
	await process_frame
	await process_frame
	_check(_sfx.enemy_voice_count() == 0, "pausing silences ongoing threat voices")
	paused = false
	_game.set_state(_game.State.PLAYING)
	left_enemy.free()
	await _stop_voices()
	print("[enemy-audio] spatial position / behind-camera / source-follow / wall checked")

func _test_same_source_attack() -> void:
	var enemy := _enemy("wraith", ORIGIN + Vector3(0, 0, -5))
	var component := _component(enemy)
	_events.clear()
	_check(bool(component.request_roar(false)), "same-source ambient cry begins normally")
	_check(_sfx.enemy_voice_count("roar") == 1, "ambient cue occupies one threat channel")
	_check(bool(component.request_roar(true)), "immediate attack overrides same-source ambient cooldown")
	_check(_sfx.enemy_voice_count("roar") == 0 and _sfx.enemy_voice_count("attack") == 1 and _sfx.enemy_voice_count() == 1, "attack replaces ambient source instead of doubling its voice")
	_check(not bool(component.request_roar(true)), "immediate repeated attack cannot spam its priority channel")
	await create_timer(1.25).timeout
	_tick(component, 1.25)
	_check(bool(component.request_roar(true)), "attack cue becomes available after its own cooldown")
	_check(_sfx.enemy_voice_count() == 1, "subsequent attack remains a single voice")
	enemy.free()
	await _stop_voices()
	print("[enemy-audio] same-source ambient-to-attack priority / replacement / cooldown checked")


func _test_crowd_and_channel_isolation() -> void:
	var crowd: Array[Node3D] = []
	for index in 30:
		crowd.append(_enemy("wraith", ORIGIN + Vector3((index % 6) * 0.3, 0, -4 - (index / 6) * 0.15)))
	await _stop_voices()
	_sfx.play("pistol", -3.0)
	var guns: Array[Dictionary] = []
	for voice: AudioStreamPlayer in _sfx._players:
		if voice.playing:
			guns.append({"voice": voice, "stream": voice.stream})
	_check(not guns.is_empty(), "local gunshot starts before cue flood")
	_events.clear()
	var accepted_steps := 0
	for enemy in crowd:
		if _sfx.play_enemy_cue("enemy_step_wraith", enemy.global_position + Vector3.UP * 0.2, {"kind": "step", "source": enemy}):
			accepted_steps += 1
	_check(accepted_steps > 0 and _sfx.enemy_voice_count("step") <= 6, "crowd admission caps simultaneous footsteps")
	var accepted_roars := 0
	for index in range(6, 15):
		var source: Node3D = crowd[index]
		if _sfx.play_enemy_cue("enemy_wraith", source.global_position + Vector3.UP * 1.3, {"kind": "roar", "source": source}):
			accepted_roars += 1
	_check(accepted_roars > 0 and _sfx.enemy_voice_count("roar") <= 3, "crowd admission caps simultaneous ambient cries")
	var attacking: Node3D = crowd[20]
	_check(_sfx.play_enemy_cue("enemy_wraith", attacking.global_position + Vector3.UP * 1.3, {"kind": "attack", "source": attacking}), "crowded steps and roars preserve an attack warning slot")
	_check(_sfx.enemy_voice_count() <= 10 and _sfx.enemy_voice_count("attack") > 0, "full threat mixer remains bounded while attack is audible")
	var preserved := true
	for record in guns:
		preserved = preserved and record.voice.playing and record.voice.stream == record.stream
	_check(preserved, "enemy cue crowd never steals the active gun channel")
	for enemy in crowd:
		enemy.free()
	await process_frame
	await process_frame
	_check(_sfx.enemy_voice_count() == 0, "freed crowd sources release all weak-follow voices")
	await _stop_voices()
	print("[enemy-audio] crowd admission / gun-channel isolation checked admitted=%d" % accepted_steps)

func _enemy(id: String, position: Vector3) -> Node3D:
	var enemy: Node3D = load("res://scenes/enemy.tscn").instantiate()
	enemy.setup(id, 1, false)
	enemy.frozen = true
	enemy.position = position
	_world.add_child(enemy)
	enemy.state = "chase"
	enemy.set_meta("audio_grounded", true)
	enemy.complete_spawn_visual()
	var component := _component(enemy)
	if component != null:
		component.set_process(false)
	return enemy

func _component(enemy: Node3D) -> Node:
	for node in enemy.get_children():
		if node.get_script() != null and node.get_script().resource_path == "res://scripts/enemies/enemy_audio.gd":
			return node
	return null

func _tick(component: Node, delta: float) -> void:
	if component == null:
		return
	if component.has_method("tick"):
		component.call("tick", delta)
	else:
		component.call("_process", delta)

func _request_roar(component: Node) -> void:
	if component == null:
		return
	if component.has_method("request_roar"):
		component.call("request_roar")
	else:
		_tick(component, 30.0)

func _move(enemy: Node3D, component: Node, speed: float, duration: float) -> void:
	for index in int(round(duration / 0.05)):
		enemy.global_position += Vector3.RIGHT * speed * 0.05
		_tick(component, 0.05)
		await create_timer(0.05).timeout

func _stop_voices() -> void:
	if _sfx.has_method("stop_enemy_cues"):
		_sfx.call("stop_enemy_cues")
	else:
		for voice in _sfx.find_children("*", "AudioStreamPlayer3D", true, false):
			voice.stop()
	await process_frame
	await process_frame

func _voice_at(position: Vector3) -> AudioStreamPlayer3D:
	for voice: AudioStreamPlayer3D in _sfx.find_children("*", "AudioStreamPlayer3D", true, false):
		if voice.playing and voice.global_position.distance_to(position) < 0.08:
			return voice
	return null

func _count(kind: String) -> int:
	var count := 0
	for event in _events:
		if event.kind == kind:
			count += 1
	return count

func _has_event(id: String, kind: String) -> bool:
	for event in _events:
		if event.id == id and event.kind == kind:
			return true
	return false

func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = position
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	_world.add_child(body)
	return body

func _on_cue(id: String, position: Vector3, kind: String, occluded: bool) -> void:
	_events.append({"id": id, "position": position, "kind": kind, "occluded": occluded})
