extends SceneTree

## Run with Godot --headless --path . --script res://tests/audio_audit.gd.
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error("[audio] " + description)

func _run() -> void:
	await process_frame
	var sound = root.get_node("Sfx")
	var game = root.get_node("Game")
	_check(sound.has_sound("pistol") and sound.has_sound("nova"), "existing API events remain available")
	for id in ["pistol", "shotgun", "smg", "rifle", "launcher", "crossbow"]:
		_check(sound.sound_variants(id) == 3, "three weapon recordings: " + id)
		var prior: AudioStream = sound._variant(id)
		for iteration in 12:
			var chosen: AudioStream = sound._variant(id)
			_check(chosen != prior, "avoid immediate duplicate variant: " + id)
			prior = chosen
	for id in ["hit_flesh", "hit_armor", "headshot", "kill_confirm", "hurt_flesh", "hurt_shield", "heartbeat", "reload_eject", "reload_insert", "reload_bolt", "step_stone", "step_paper", "casing", "enemy_wraith", "enemy_brute"]:
		_check(sound.has_sound(id), "new feedback event exists: " + id)
	var score = sound.music
	_check(score != null and score.players.size() == 5, "five synchronized score layers")
	for stem in score.players:
		var stream: AudioStreamWAV = score.players[stem].stream
		_check(stream.stereo and stream.mix_rate == 22050, "stereo PCM score: " + stem)
		_check(absf(stream.get_length() - 48.0) < 0.002, "48-second music transport: " + stem)
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "seamless loop enabled: " + stem)
	var opening: Dictionary = score.arrangement(game.State.PLAYING, 1)
	var late: Dictionary = score.arrangement(game.State.PLAYING, 9)
	var boss: Dictionary = score.arrangement(game.State.PLAYING, 5)
	_check(float(late.drums) > float(opening.drums), "score gains rhythmic intensity with waves")
	_check(float(boss.boss) > -10.0, "boss has its own arrangement")
	_check(float(score.arrangement(game.State.TITLE, 0).menu) > -10.0, "menu has composed theme")
	sound.play("pistol", -9.0)
	_check(score._duck >= 4.0, "gun report ducks score")
	sound.play_at("enemy_wraith", Vector3(4, 1, -6), -8.0)
	await process_frame
	var world_voice: AudioStreamPlayer3D = sound._spatial_players[0]
	_check(world_voice.stream != null and world_voice.global_position == Vector3(4, 1, -6), "world audio plays at source position")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index("WorldSfx")) == "Ink", "world audio respects sound-effects volume")
	var limiter_found := false
	for index in AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master")):
		limiter_found = limiter_found or AudioServer.get_bus_effect(AudioServer.get_bus_index("Master"), index) is AudioEffectHardLimiter
	_check(limiter_found, "master peak protection exists")
	sound.set_music_volume(0.0)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music volume can mute independently")
	sound.set_music_volume(0.65)
	if failures.is_empty():
		print("[audio] PASS: 58 events / variants, spatial routing, synchronized 48s score, wave/boss arrangement, ducking, limiter and music volume")
	else:
		print("[audio] FAIL: ", failures)
	sound.shutdown()
	await create_timer(0.12).timeout
	quit(0 if failures.is_empty() else 1)
