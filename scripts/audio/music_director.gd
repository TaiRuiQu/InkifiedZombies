class_name MusicDirector
extends Node

## All stems share the same 48-second/80 BPM transport. Arrangement changes
## crossfade, preserving the score through pauses, menus and scene reloads.
const STEMS := ["menu", "melody", "strings", "drums", "boss"]
var players: Dictionary = {}
var current_cue := "menu"
var _duck := 0.0
var _duck_hold := 0.0
var _levels: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for stem: String in STEMS:
		var player := AudioStreamPlayer.new()
		player.name = "Music_" + stem
		player.bus = "Music"
		player.volume_db = -70.0
		var stream: AudioStreamWAV = (load(AudioBank.MUSIC[stem]) as AudioStreamWAV).duplicate()
		if stream == null:
			push_error("Missing score stem: " + stem)
			continue
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		player.stream = stream
		add_child(player)
		players[stem] = player
		_levels[stem] = -70.0
	# Queued in the same audio frame; stems retain phase even while inaudible.
	for player: AudioStreamPlayer in players.values():
		player.play()

func duck(amount_db: float = 5.0, hold_seconds: float = 0.1) -> void:
	_duck = maxf(_duck, clampf(amount_db, 0.0, 10.0))
	_duck_hold = maxf(_duck_hold, hold_seconds)

func _process(delta: float) -> void:
	_duck_hold = maxf(_duck_hold - delta, 0.0)
	if _duck_hold <= 0.0:
		_duck = move_toward(_duck, 0.0, delta * 14.0)
	var targets := arrangement(Game.state, Game.wave)
	for stem: String in players:
		var rate := 1.7 if Game.state == Game.State.DEAD else 1.0
		_levels[stem] = lerpf(float(_levels[stem]), float(targets.get(stem, -70.0)), 1.0 - exp(-delta * rate))
		(players[stem] as AudioStreamPlayer).volume_db = float(_levels[stem]) - _duck

func arrangement(state: int, wave: int) -> Dictionary:
	var levels := {"menu": -70.0, "melody": -70.0, "strings": -70.0, "drums": -70.0, "boss": -70.0}
	var intensity := clampf(float(wave - 1) / 9.0, 0.0, 1.0)
	match state:
		Game.State.TITLE:
			current_cue = "menu"
			levels.menu = -5.0
		Game.State.PLAYING, Game.State.INTERMISSION:
			var boss_fight := wave > 0 and wave % 5 == 0
			current_cue = "boss" if boss_fight else "combat"
			levels.melody = -10.0 if boss_fight else -7.5
			levels.strings = -9.0
			levels.drums = lerpf(-14.0, -7.0, intensity)
			if boss_fight:
				levels.boss = -6.5
		Game.State.UPGRADE, Game.State.PAUSED:
			current_cue = "reflection"
			levels.menu = -13.0
			levels.strings = -17.0
		Game.State.VICTORY:
			current_cue = "dawn"
			levels.menu = -5.0
			levels.melody = -17.0
		Game.State.DEAD:
			current_cue = "silence"
			levels.strings = -22.0
	return levels

func shutdown() -> void:
	for player: AudioStreamPlayer in players.values():
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	players.clear()

func _exit_tree() -> void:
	shutdown()
