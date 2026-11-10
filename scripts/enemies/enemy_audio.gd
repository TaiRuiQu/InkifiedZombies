class_name EnemyAudio
extends Node

## Listener-local cues follow actual displacement, including network proxies.
## Playback is not replicated: each machine hears its own nearby threats once.
const PROFILES := {
	"wraith": {"stride": 0.90, "step_db": -5.0, "roar_db": -3.0, "roar_gap": 5.4, "floating": false},
	"puppet": {"stride": 0.95, "step_db": -7.0, "roar_db": -5.0, "roar_gap": 5.8, "floating": false},
	"brute": {"stride": 1.10, "step_db": -1.0, "roar_db": 0.0, "roar_gap": 5.1, "floating": false},
	"mask": {"stride": 1.45, "step_db": -9.0, "roar_db": -3.5, "roar_gap": 6.2, "floating": true},
	"lantern": {"stride": 1.65, "step_db": -7.5, "roar_db": -3.0, "roar_gap": 5.7, "floating": true},
	"boss": {"stride": 1.50, "step_db": 1.0, "roar_db": 1.0, "roar_gap": 6.0, "floating": false},
}

var enemy: Node3D
var profile: Dictionary = {}
var _previous_position := Vector3.ZERO
var _distance := 0.0
var _step_cooldown := 0.0
var _roar_timer := 0.0
var _voice_cooldown := 0.0
var _attack_cooldown := 0.0
var _spin_whoosh_timer := 0.0
var _old_state := "spawn"
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	enemy = get_parent() as Node3D
	_rng.seed = enemy.get_instance_id()
	var sound_type: String = enemy.type_id if PROFILES.has(enemy.type_id) else "wraith"
	profile = PROFILES[sound_type].duplicate(true)
	profile.merge(enemy.data.get("audio", {}), true)
	profile["step_id"] = String(profile.get("step_id", "enemy_step_" + sound_type))
	profile["roar_id"] = String(profile.get("roar_id", "enemy_" + sound_type))
	_previous_position = enemy.global_position
	_distance = _rng.randf_range(0.0, float(profile.stride) * 0.55)
	_roar_timer = _rng.randf_range(0.8, 2.8)
	_old_state = enemy.state

func get_profile() -> Dictionary:
	return profile.duplicate(true)

func _process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	var position := enemy.global_position
	var displacement := position - _previous_position
	_previous_position = position
	_step_cooldown = maxf(_step_cooldown - delta, 0.0)
	_voice_cooldown = maxf(_voice_cooldown - delta, 0.0)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_spin_whoosh_timer = maxf(_spin_whoosh_timer - delta, 0.0)
	if Game.state != Game.State.PLAYING or get_tree().paused or enemy.dead or enemy.state == "spawn":
		_distance = 0.0
		_old_state = enemy.state
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_squared_to(position) > 28.0 * 28.0:
		_distance = 0.0
		_old_state = enemy.state
		return
	if enemy.state != _old_state and enemy.state in ["windup", "fuse"]:
		request_roar(true)
	# Derive short action accents locally too: a network proxy never executes
	# perform_attack(), but its leap and blade swing still need audible motion.
	if enemy.state != _old_state:
		if enemy.state == "leap":
			Sfx.play_at("swipe", position + Vector3.UP, -5.0, 0.85)
		elif _old_state == "leap" and enemy.state == "recover":
			Sfx.play_at("slam", position, -3.0, 1.1)
	if enemy.state == "spin" and _spin_whoosh_timer <= 0.0:
		_spin_whoosh_timer = 0.45
		Sfx.play_at("swipe", position + Vector3.UP, -8.0, 0.8)
	_old_state = enemy.state
	_roar_timer -= delta
	if _roar_timer <= 0.0:
		var played := request_roar(false)
		_roar_timer = float(profile.roar_gap) * _rng.randf_range(0.85, 1.3) if played else _rng.randf_range(0.4, 1.2)
	# A snapshot correction / teleport must not sound like sprinting footsteps.
	var horizontal := Vector2(displacement.x, displacement.z).length()
	if horizontal > 2.8 or absf(displacement.y) > 0.55:
		_distance = 0.0
		return
	var grounded := bool(enemy.get_meta("audio_grounded", enemy.is_on_floor()))
	if enemy.state not in ["chase", "fuse"] or (not bool(profile.floating) and not grounded):
		_distance = 0.0
		return
	if horizontal < 0.0005:
		return
	_distance += horizontal
	if _distance >= float(profile.stride) and _step_cooldown <= 0.0:
		# Retain a partial stride; never emit a catch-up burst after a low FPS frame.
		_distance = fmod(_distance, float(profile.stride))
		_step_cooldown = 0.23 if not bool(profile.floating) else 0.40
		var offset := Vector3(0, 0.18, 0)
		if bool(profile.floating):
			offset.y = enemy.height * 0.5
		Sfx.play_enemy_cue(profile.step_id, position + offset, {"kind": "step", "source": enemy,
			"volume_db": float(profile.step_db), "pitch": _rng.randf_range(0.94, 1.06), "max_distance": 23.0})

func request_roar(attack: bool = false) -> bool:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree() or enemy.dead or enemy.state == "spawn":
		return false
	if (_attack_cooldown > 0.0 if attack else _voice_cooldown > 0.0):
		return false
	var mouth: Vector3 = enemy.global_position + Vector3.UP * enemy.height * 0.76
	var played := Sfx.play_enemy_cue(profile.roar_id, mouth, {"kind": "attack" if attack else "roar",
		"source": enemy, "follow": true, "offset": Vector3.UP * enemy.height * 0.76,
		"volume_db": float(profile.roar_db) + (1.5 if attack else 0.0),
		"pitch": _rng.randf_range(0.94, 1.05), "max_distance": 28.0})
	if played:
		if attack:
			_attack_cooldown = 1.15
		_voice_cooldown = 2.8
	return played
