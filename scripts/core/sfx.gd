extends Node

signal cue_started(id: String, position: Vector3, kind: String, occluded: bool)

const ENEMY_CUE_CAPACITY := 10
const ENEMY_STEP_LIMIT := 6
const ENEMY_ROAR_LIMIT := 3
var _enemy_voices: Array[AudioStreamPlayer3D] = []
var _enemy_slots: Array[Dictionary] = []
var _enemy_recent: Dictionary = {}
var _occlusion_timer := 0.0

## Offline original recordings keep startup cheap. UI/local confirmation sounds
## use play(); world actors use the separate spatial pool through play_at().
const BUS_NAME := "Ink"
const GUNS := ["pistol", "shotgun", "smg", "rifle", "launcher", "crossbow"]
const IMPACTS := ["hit", "hit_flesh", "hit_armor", "headshot", "hurt", "hurt_flesh", "hurt_shield", "shield_break", "kill_confirm"]
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _spatial_players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next_spatial := 0
var _last_variant: Dictionary = {}
var _recent: Dictionary = {}
var _ambient: AudioStreamPlayer
var music: MusicDirector

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_bank()
	for index in (16 if Browser.is_web() else 32):
		var player := AudioStreamPlayer.new()
		player.name = "LocalVoice%d" % index
		player.bus = BUS_NAME
		player.max_polyphony = 1
		add_child(player)
		_players.append(player)
	for index in (12 if Browser.is_web() else 28):
		var player := AudioStreamPlayer3D.new()
		player.name = "WorldVoice%d" % index
		player.bus = "WorldSfx"
		player.max_polyphony = 1
		player.max_distance = 55.0
		player.unit_size = 6.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.attenuation_filter_cutoff_hz = 9000.0
		player.attenuation_filter_db = -12.0
		add_child(player)
		_spatial_players.append(player)
	for index in ENEMY_CUE_CAPACITY:
		var player := AudioStreamPlayer3D.new()
		player.name = "EnemyCue%d" % index
		player.bus = "EnemyCues"
		player.unit_size = 4.0
		player.max_distance = 28.0
		player.panning_strength = 1.25
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.attenuation_filter_cutoff_hz = 8500.0
		player.attenuation_filter_db = -16.0
		add_child(player)
		_enemy_voices.append(player)
		_enemy_slots.append({})
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "CourtyardWind"
	_ambient.bus = "Ambient"
	_ambient.volume_db = -13.0
	var wind: AudioStreamWAV = (load(AudioBank.MUSIC.ambience) as AudioStreamWAV).duplicate()
	wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind.loop_begin = 0
	wind.loop_end = int(round(wind.get_length() * wind.mix_rate))
	_ambient.stream = wind
	add_child(_ambient)
	_ambient.play()
	music = MusicDirector.new()
	music.name = "Score"
	add_child(music)
	Settings.apply_audio()

func _setup_buses() -> void:
	for bus: String in ["Ink", "Ambient", "Music", "WorldSfx", "EnemyCues", "EnemyMuffled"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "Ink" if bus == "WorldSfx" else "Master")
	AudioServer.set_bus_send(AudioServer.get_bus_index("EnemyCues"), "WorldSfx")
	AudioServer.set_bus_send(AudioServer.get_bus_index("EnemyMuffled"), "EnemyCues")
	# Web Sample playback does not apply bus AudioEffects. Occlusion already
	# applies a separate volume reduction; keep headroom without a live limiter.
	if Browser.is_web():
		return
	var muffled := AudioServer.get_bus_index("EnemyMuffled")
	if AudioServer.get_bus_effect_count(muffled) == 0:
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = 1700.0
		AudioServer.add_bus_effect(muffled, lowpass)
	var world := AudioServer.get_bus_index("WorldSfx")
	if AudioServer.get_bus_effect_count(world) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.52
		reverb.damping = 0.65
		reverb.wet = 0.075
		reverb.dry = 1.0
		AudioServer.add_bus_effect(world, reverb)
	# Leave headroom for a crowd and keep close impacts readable over the score.
	var master := AudioServer.get_bus_index("Master")
	var has_limiter := false
	for index in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, index) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.8
		limiter.pre_gain_db = -1.0
		limiter.release = 0.08
		AudioServer.add_bus_effect(master, limiter)

func _load_bank() -> void:
	for id: String in AudioBank.SOUNDS:
		var variants: Array[AudioStream] = []
		for path: String in AudioBank.SOUNDS[id]:
			var stream: AudioStream = load(path)
			if stream != null:
				variants.append(stream.duplicate())
		if not variants.is_empty():
			_streams[id] = variants

func has_sound(id: String) -> bool:
	return _streams.has(id)

func sound_variants(id: String) -> int:
	return (_streams.get(id, []) as Array).size()

func _variant(id: String) -> AudioStream:
	var variants: Array = _streams.get(id, [])
	if variants.is_empty():
		return null
	var previous := int(_last_variant.get(id, -1))
	var index := randi() % variants.size()
	if variants.size() > 1 and index == previous:
		index = (index + 1 + randi() % (variants.size() - 1)) % variants.size()
	_last_variant[id] = index
	return variants[index]

func _allow(id: String, spatial: bool) -> bool:
	# Shotgun pellets and a full horde must not stack dozens of identical impact
	# confirmations in the same mixer frame. Weapon reports are never throttled.
	if GUNS.has(id):
		return true
	var minimum_ms := 12 if not spatial else 24
	if id in ["kill", "kill_confirm", "spawn"]:
		minimum_ms = 40
	var key := id + ("_world" if spatial else "_local")
	var now := Time.get_ticks_msec()
	if now - int(_recent.get(key, -10000)) < minimum_ms:
		return false
	_recent[key] = now
	return true

func play(id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(id) or not _allow(id, false):
		return
	var player := _free_player()
	player.stream = _variant(id)
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch, 0.55, 1.85)
	player.play()
	if is_instance_valid(music):
		if GUNS.has(id):
			music.duck(4.0 if id == "smg" else 5.5, 0.065)
		elif IMPACTS.has(id):
			music.duck(2.5, 0.09)

func play_at(id: String, world_position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(id) or not _allow(id, true):
		return
	var player := _free_spatial_player()
	player.stream = _variant(id)
	player.global_position = world_position
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch, 0.55, 1.85)
	player.play()

func set_music_volume(value: float) -> void:
	var index := AudioServer.get_bus_index("Music")
	if index >= 0:
		var volume := clampf(value, 0.0, 1.0)
		AudioServer.set_bus_mute(index, volume <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))

func _free_player() -> AudioStreamPlayer:
	for offset in _players.size():
		var index := (_next + offset) % _players.size()
		if not _players[index].playing:
			_next = (index + 1) % _players.size()
			return _players[index]
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stop()
	return player

func _free_spatial_player() -> AudioStreamPlayer3D:
	for offset in _spatial_players.size():
		var index := (_next_spatial + offset) % _spatial_players.size()
		if not _spatial_players[index].playing:
			_next_spatial = (index + 1) % _spatial_players.size()
			return _spatial_players[index]
	var player := _spatial_players[_next_spatial]
	_next_spatial = (_next_spatial + 1) % _spatial_players.size()
	player.stop()
	return player

func shutdown() -> void:
	stop_enemy_cues()
	if is_instance_valid(music):
		music.shutdown()
	if is_instance_valid(_ambient):
		_ambient.stop()
		_ambient.stream = null
	for player: AudioStreamPlayer in _players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player: AudioStreamPlayer3D in _spatial_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_streams.clear()

func _exit_tree() -> void:
	shutdown()


func enemy_voice_count(kind: String = "") -> int:
	var count := 0
	for index in _enemy_voices.size():
		if _enemy_voices[index].playing and not _enemy_slots[index].is_empty():
			if kind.is_empty() or String(_enemy_slots[index].kind) == kind:
				count += 1
	return count


func stop_enemy_cues() -> void:
	for index in _enemy_voices.size():
		_enemy_voices[index].stop()
		_enemy_voices[index].stream = null
		_enemy_slots[index].clear()
	_enemy_recent.clear()


func _process(delta: float) -> void:
	if Game.state != Game.State.PLAYING or get_tree().paused:
		if enemy_voice_count() > 0:
			stop_enemy_cues()
		return
	_occlusion_timer -= delta
	var refresh := _occlusion_timer <= 0.0
	if refresh:
		_occlusion_timer = 0.18
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		stop_enemy_cues()
		return
	for index in _enemy_voices.size():
		var slot: Dictionary = _enemy_slots[index]
		var voice := _enemy_voices[index]
		if slot.is_empty():
			continue
		var source: Node3D = (slot.source as WeakRef).get_ref()
		if not voice.playing or not is_instance_valid(source) or not source.is_inside_tree() or source.get("dead") == true:
			voice.stop()
			voice.stream = null
			slot.clear()
			continue
		if bool(slot.follow):
			voice.global_position = source.global_position + Vector3(slot.offset)
		if camera.global_position.distance_to(voice.global_position) > voice.max_distance:
			voice.stop()
			slot.clear()
			continue
		if refresh and bool(slot.follow):
			_apply_enemy_occlusion(voice, slot, camera)


func play_enemy_cue(id: String, position: Vector3, options: Dictionary = {}) -> bool:
	if Game.state != Game.State.PLAYING or get_tree().paused or not has_sound(id):
		return false
	var source: Node3D = options.get("source") as Node3D
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(source) or not source.is_inside_tree() or source.get("dead") == true or camera == null:
		return false
	var distance := camera.global_position.distance_to(position)
	var maximum := clampf(float(options.get("max_distance", 28.0)), 8.0, 32.0)
	if distance > maximum:
		return false
	var kind := String(options.get("kind", "step"))
	var key := "%d/%s" % [source.get_instance_id(), kind]
	var now := Time.get_ticks_msec()
	var interval := 170 if kind == "step" else 1150
	if now - int(_enemy_recent.get(key, -10000)) < interval:
		return false
	# Reserve one voice for attacks. Crowd footsteps cannot evict weapon reports,
	# and ambient roars cannot drown out a close, telegraphed attack.
	var limit := ENEMY_STEP_LIMIT if kind == "step" else ENEMY_ROAR_LIMIT
	var matching := enemy_voice_count(kind)
	var candidate := -1
	if kind == "attack":
		for index in _enemy_voices.size():
			var active: Dictionary = _enemy_slots[index]
			if not active.is_empty() and String(active.kind) in ["roar", "attack"] and (active.source as WeakRef).get_ref() == source:
				candidate = index
				break
	if candidate < 0 and matching < limit:
		for index in _enemy_voices.size():
			if not _enemy_voices[index].playing:
				candidate = index
				break
	if candidate < 0:
		var farthest := distance + 2.0
		for index in _enemy_voices.size():
			var slot: Dictionary = _enemy_slots[index]
			if slot.is_empty():
				continue
			var replaceable := String(slot.kind) == kind or (kind == "attack" and String(slot.kind) != "attack")
			var other_distance := camera.global_position.distance_to(_enemy_voices[index].global_position)
			if replaceable and other_distance > farthest:
				farthest = other_distance
				candidate = index
	if candidate < 0:
		return false
	var voice := _enemy_voices[candidate]
	voice.stop()
	voice.stream = _variant(id)
	voice.max_distance = maximum
	voice.global_position = position
	voice.pitch_scale = clampf(float(options.get("pitch", 1.0)), 0.7, 1.3)
	var slot := {"kind": kind, "source": weakref(source), "follow": bool(options.get("follow", false)),
		"offset": options.get("offset", Vector3.ZERO), "volume_db": float(options.get("volume_db", -4.0)), "occluded": false}
	_enemy_slots[candidate] = slot
	_apply_enemy_occlusion(voice, slot, camera)
	voice.play()
	_enemy_recent[key] = now
	cue_started.emit(id, position, kind, bool(slot.occluded))
	if _enemy_recent.size() > 256:
		for old_key in _enemy_recent.keys():
			if now - int(_enemy_recent[old_key]) > 12000:
				_enemy_recent.erase(old_key)
	return true


func _apply_enemy_occlusion(voice: AudioStreamPlayer3D, slot: Dictionary, camera: Camera3D) -> void:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, voice.global_position, 1)
	var blocked := not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	slot.occluded = blocked
	voice.bus = "EnemyMuffled" if blocked else "EnemyCues"
	voice.volume_db = float(slot.volume_db) - (9.0 if blocked else 0.0)
