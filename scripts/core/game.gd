extends Node

## Session state and versioned local profile. Settings have a separate lifetime.
signal state_changed(new_state)
signal best_updated(wave)

enum State { TITLE, PLAYING, INTERMISSION, UPGRADE, DEAD, PAUSED, VICTORY }
const SAVE_PATH := "user://ink_tide.cfg"
const SAVE_VERSION := 2

var state: State = State.TITLE
var selected_map := "courtyard"
var difficulty := "standard"
var endless := false
var auto_start := false
var wave := 0
var completed_waves := 0
var kills := 0
var run_time := 0.0
var damage_taken := 0.0
var shots_fired := 0
var best_wave := 0
var best_completed := 0
var total_runs := 0
var victories := 0
var history: Array = []
var _run_id := ""
var _recorded := false
var _win_recorded := false
var _test_profile := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--smoke") or arg.begins_with("--role=") or arg in ["--autoshot", "--beta-test", "--gallery"]:
			_test_profile = true
	load_progress()

func reset_run() -> void:
	wave = 0
	completed_waves = 0
	kills = 0
	run_time = 0.0
	damage_taken = 0.0
	shots_fired = 0
	_run_id = "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	_recorded = false
	_win_recorded = false

func set_state(new_state: State) -> void:
	if state != new_state:
		state = new_state
		state_changed.emit(new_state)

func record_wave_reached(value: int) -> void:
	wave = maxi(wave, value)
	if wave > best_wave:
		best_wave = wave
		best_updated.emit(best_wave)
		save_progress()

func record_wave_cleared(value: int) -> void:
	completed_waves = maxi(completed_waves, value)
	best_completed = maxi(best_completed, completed_waves)
	save_progress()

func record_result(won: bool) -> void:
	if not _recorded:
		total_runs += 1
		_recorded = true
	if won and not _win_recorded:
		victories += 1
		_win_recorded = true
	var result := {"id": _run_id, "map": selected_map, "difficulty": difficulty,
		"endless": endless, "won": won or _win_recorded, "wave": wave,
		"cleared": completed_waves, "kills": kills, "seconds": int(run_time),
		"date": Time.get_datetime_string_from_system(), "damage_taken": int(damage_taken)}
	for i in range(history.size() - 1, -1, -1):
		if history[i] is Dictionary and history[i].get("id", "") == _run_id:
			history.remove_at(i)
	history.push_front(result)
	while history.size() > 10:
		history.pop_back()
	save_progress()

func save_progress() -> void:
	if _test_profile:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "version", SAVE_VERSION)
	cfg.set_value("progress", "best_wave", best_wave)
	cfg.set_value("progress", "best_completed", best_completed)
	cfg.set_value("progress", "total_runs", total_runs)
	cfg.set_value("progress", "victories", victories)
	cfg.set_value("progress", "history", history)
	var temporary := SAVE_PATH + ".tmp"
	if cfg.save(temporary) == OK:
		var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(SAVE_PATH))
		if err != OK:
			push_warning("无法保存本地战绩：%s" % error_string(err))

func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_wave = maxi(0, int(cfg.get_value("progress", "best_wave", 0)))
	best_completed = maxi(0, int(cfg.get_value("progress", "best_completed", 0)))
	total_runs = maxi(0, int(cfg.get_value("progress", "total_runs", 0)))
	victories = maxi(0, int(cfg.get_value("progress", "victories", 0)))
	var saved_history = cfg.get_value("progress", "history", [])
	if saved_history is Array:
		for entry in saved_history:
			if entry is Dictionary and entry.has("wave") and history.size() < 10:
				history.append(entry)
