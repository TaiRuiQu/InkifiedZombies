extends Node3D

## Ink Tide — game orchestration: title, run start, waves, upgrades, pause,
## death, and a development screenshot mode.

const MapBuilderScript: Script = preload("res://scripts/world/map_builder.gd")
const WaveDirectorScript: Script = preload("res://scripts/waves/wave_director.gd")
const PlayerScene: PackedScene = preload("res://scenes/player.tscn")
const POST_SHADER: Shader = preload("res://shaders/ink_post.gdshader")

var map: MapBuilder
var player: Player
var director: WaveDirector
var hud: HUD
var title: TitleScreen
var upgrades: UpgradeScreen
var pause: PauseMenu
var game_over: GameOverScreen

var settings_screen: SettingsScreen
var multiplayer_screen: MultiplayerScreen
var _settings_origin := "title"
var _dev: RefCounted

var _post_mat: ShaderMaterial
var _title_cam: Camera3D
var _title_t := 0.0
var _started := false
var _dying := false
var _clearing := false
var _autoshot := false
var _preview_requested := ""
var _preview_pending := false
var _quitting := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	Game.reset_run()
	Game.set_state(Game.State.TITLE)
	var args := OS.get_cmdline_user_args()
	_autoshot = args.has("--autoshot")
	if args.has("--autostart") or args.has("--smoke") or args.has("--smokeidle") or args.has("--smokeboss") or args.has("--smoketest"):
		Game.auto_start = true
	_build_world()
	_build_post()
	_build_ui()
	_build_title_camera()
	_connect()
	Coop.setup(self)
	Settings.apply_scene(self)
	_dev = load("res://scripts/dev/dev_scenarios.gd").new(self)
	if args.has("--verify-runtime"):
		title.open()
		_verify_runtime.call_deferred()
	elif args.has("--beta-test"):
		_dev = load("res://tests/beta_test.gd").new(self)
		_dev.run.call_deferred()
	elif args.has("--gallery"):
		_dev = load("res://tests/gallery.gd").new(self)
		_dev.run.call_deferred()
	elif args.has("--smokeboss"):
		_dev._run_smoke_boss.call_deferred()
	elif args.has("--smoketest"):
		_dev._run_smoke_test.call_deferred()
	elif args.has("--smokeidle"):
		_dev._run_smoke_idle.call_deferred()
	elif args.has("--smoke"):
		_dev._run_smoke.call_deferred()
	elif Game.auto_start:
		Game.auto_start = false
		start_run.call_deferred()
	elif _autoshot:
		title.open()
		_dev._run_autoshot.call_deferred()
	else:
		title.open()


func _build_world() -> void:
	map = MapBuilderScript.new()
	map.name = "Arena"
	map.configure(Game.selected_map)
	add_child(map)
	map.build()

	player = PlayerScene.instantiate()
	player.name = "Player"
	player.position = map.player_spawn
	add_child(player)
	player.set_controls(false)

	director = WaveDirectorScript.new()
	director.name = "WaveDirector"
	add_child(director)
	director.setup(player, map.spawn_positions)


func _build_post() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PaperGrade"
	layer.layer = 5
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = POST_SHADER
	rect.material = _post_mat
	layer.add_child(rect)


func _build_ui() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(player, director)
	hud.visible = false

	upgrades = UpgradeScreen.new()
	upgrades.name = "UpgradeScreen"
	add_child(upgrades)

	pause = PauseMenu.new()
	pause.name = "PauseMenu"
	add_child(pause)

	game_over = GameOverScreen.new()
	game_over.name = "GameOverScreen"
	add_child(game_over)

	settings_screen = SettingsScreen.new()
	add_child(settings_screen)
	multiplayer_screen = MultiplayerScreen.new()
	add_child(multiplayer_screen)

	title = TitleScreen.new()
	title.name = "TitleScreen"
	add_child(title)


func _build_title_camera() -> void:
	_title_cam = Camera3D.new()
	_title_cam.name = "TitleCamera"
	_title_cam.fov = 52.0
	_title_cam.near = 0.05
	_title_cam.far = 900.0
	_title_cam.position = Vector3(17.0, 6.4, 24.0)
	add_child(_title_cam)
	_title_cam.current = true
	_title_cam.look_at(Vector3(-1.0, 2.2, -4.0), Vector3.UP)


func _connect() -> void:
	title.start_requested.connect(func():
		NET.leave()
		start_run())
	title.quit_requested.connect(_quit_game)
	title.settings_requested.connect(func(): _open_settings("title"))
	title.multiplayer_requested.connect(_open_multiplayer)
	title.map_selected.connect(_on_preview_selected)
	multiplayer_screen.closed.connect(func():
		if Game.state == Game.State.TITLE:
			title.open())
	multiplayer_screen.start_requested.connect(start_coop_run)
	settings_screen.closed.connect(_close_settings)
	pause.settings_requested.connect(func(): _open_settings("pause"))
	game_over.continue_requested.connect(_continue_endless)
	director.wave_started.connect(_on_wave_started)
	director.wave_cleared.connect(_on_wave_cleared)
	director.boss_spawned.connect(_on_boss_spawned)
	director.boss_defeated.connect(_on_boss_defeated)
	player.died.connect(_on_player_died)
	upgrades.chosen.connect(_on_upgrade_chosen)
	upgrades.refresh_requested.connect(_on_upgrade_refresh)
	pause.resume_requested.connect(_resume)
	pause.restart_requested.connect(_restart_run)
	pause.title_requested.connect(_return_to_title)
	game_over.restart_requested.connect(_restart_run)
	game_over.title_requested.connect(_return_to_title)


func _process(delta: float) -> void:
	if _title_cam and _title_cam.current:
		_title_t += delta
		var sway := sin(_title_t * 0.12) * 1.2
		_title_cam.position = Vector3(17.0 + sway, 6.4 + sin(_title_t * 0.16) * 0.2, 24.0)
		_title_cam.look_at(Vector3(-1.0 + sin(_title_t * 0.09) * 1.5, 2.2, -4.0), Vector3.UP)
	if Game.state == Game.State.PLAYING or Game.state == Game.State.INTERMISSION:
		Game.run_time += delta


# --------------------------------------------------------------------------
# Run lifecycle
# --------------------------------------------------------------------------

func start_run() -> void:
	if _started:
		return
	_started = true
	if map.map_id != Game.selected_map:
		_replace_map(Game.selected_map)
	Game.reset_run()
	Game.set_state(Game.State.PLAYING)
	title.close()
	multiplayer_screen.close()
	_title_cam.current = false
	player.make_camera_current()
	player.set_controls(true)
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not NET.active or NET.is_host:
		director.start_wave(1)
	Coop.begin_run()
	Sfx.play("wave_start", -4.0)


func _on_wave_started(wave: int) -> void:
	Game.set_state(Game.State.PLAYING)
	var cn := UITheme.cn_num(wave)
	if wave % 5 == 0:
		hud.show_banner("第 %s 波" % cn, "墨将临阵 · 独守长夜", UITheme.CINNABAR, 2.8)
	elif wave == 1:
		hud.show_banner("第 一 波", "墨潮初起 · 左键挥墨", UITheme.CINNABAR, 3.0)
	else:
		var sub := "墨潮再至"
		match wave:
			2:
				sub = "纸傀现行 · 薄如纸，快如风"
			3:
				sub = "跃魇拔刀 · 留意落点，侧步避斩"
			4:
				sub = "咒面浮空 · 当心墨弹"
			6:
				sub = "旋刃与灯鬼 · 远离刀圈与引火"
			7:
				sub = "墨甲压境 · 重击难挡"
			9:
				sub = "墨潮渐急 · 稳住气息"
			12:
				sub = "长夜未尽 · 杀意更浓"
			15:
				sub = "墨海翻涌 · 已无退路"
		hud.show_banner("第 %s 波" % cn, sub, UITheme.PAPER_DARK, 2.5)


func _on_wave_cleared(wave: int) -> void:
	if _clearing or _dying:
		return
	_clearing = true
	Game.set_state(Game.State.INTERMISSION)
	player.set_controls(false)
	Game.record_wave_cleared(wave)
	player.resupply_between_waves()
	if NET.active and NET.is_host:
		Coop.resupply_team()
	if wave >= RunRules.TARGET_WAVES and not Game.endless:
		_clearing = false
		_show_victory()
		return
	hud.show_banner("波 次 肃 清", "第 %s 波 · 已回血、补弹与重置术法" % UITheme.cn_num(wave), UITheme.GOLD, 1.5)
	Sfx.play("wave_clear", -2.0)
	await get_tree().create_timer(1.5).timeout
	_clearing = false
	if _dying or not is_instance_valid(player):
		return
	var choices := UpgradeDB.roll(player, wave, 3)
	Game.set_state(Game.State.UPGRADE)
	player.set_controls(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	upgrades.open(wave, choices)
	if NET.active and NET.is_host:
		Coop.open_upgrades(wave)
	get_tree().paused = true


func _on_upgrade_refresh() -> void:
	if NET.active:
		Coop.refresh_upgrades()
		return
	var previous := upgrades._cards.map(func(card): return card.data)
	upgrades.apply_refresh(UpgradeDB.roll(player, Game.wave, 3, previous), upgrades.refreshes_left - 1)


func _on_upgrade_chosen(data: Dictionary) -> void:
	if NET.active:
		Coop.choose_upgrade(data)
		return
	player.apply_upgrade(data)
	upgrades.close()
	get_tree().paused = false
	Game.set_state(Game.State.PLAYING)
	player.set_controls(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.visible = true
	await get_tree().create_timer(0.9, false).timeout
	if _dying:
		return
	director.start_wave(Game.wave + 1)


func _on_boss_spawned(_boss: Enemy) -> void:
	hud.show_banner("墨 将", "第%s波 · 从墨海归来" % UITheme.cn_num(Game.wave), UITheme.CINNABAR, 2.6)


func _on_boss_defeated() -> void:
	hud.show_banner("墨将伏诛", "余烬之中，仍有敌影", UITheme.GOLD, 2.2)
	Sfx.play("wave_clear", -1.0, 0.72)


func _on_player_died(force: bool = false) -> void:
	if NET.active and not force:
		Coop.local_downed()
		return
	if _dying:
		return
	_dying = true
	Game.record_result(false)
	Game.set_state(Game.State.DEAD)
	director.stop()
	hud.show_banner("墨 尽", "长夜未央", UITheme.CINNABAR, 2.0)
	await get_tree().create_timer(1.9).timeout
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	game_over.open(Game.wave, Game.kills, int(Game.run_time), Game.best_wave)


# --------------------------------------------------------------------------
# Pause / menu handling
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if settings_screen.visible or multiplayer_screen.visible:
		return
	if event.is_action_pressed("pause"):
		if pause.visible:
			_resume()
			get_viewport().set_input_as_handled()
		elif Game.state == Game.State.PLAYING and not _dying:
			_open_pause()
			get_viewport().set_input_as_handled()


func _open_pause() -> void:
	if not NET.active:
		Game.set_state(Game.State.PAUSED)
	player.set_controls(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause.open()
	get_tree().paused = not NET.active


func _resume() -> void:
	if Coop.connection_lost:
		return
	pause.close()
	get_tree().paused = false
	Game.set_state(Game.State.PLAYING)
	player.set_controls(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restart_run() -> void:
	if NET.active and not NET.is_host:
		hud.show_banner("等待房主", "请由房主重新开始此局", UITheme.GOLD)
		return
	if NET.active:
		NET.send("restart", Coop.run_options())
	get_tree().paused = false
	Engine.time_scale = 1.0
	Game.auto_start = true
	Game.reset_run()
	Coop.clear_run()
	get_tree().reload_current_scene()


func _return_to_title() -> void:
	NET.leave()
	Coop.clear_run()
	get_tree().paused = false
	Engine.time_scale = 1.0
	Game.auto_start = false
	Game.reset_run()
	Game.set_state(Game.State.TITLE)
	get_tree().reload_current_scene()



func _open_settings(origin: String) -> void:
	_settings_origin = origin
	title.close()
	pause.close()
	settings_screen.open()


func _close_settings() -> void:
	if _settings_origin == "pause":
		pause.open()
	else:
		title.open()


func _open_multiplayer() -> void:
	title.close()
	multiplayer_screen.open()


func start_coop_run() -> void:
	if not NET.active or not NET.is_host:
		return
	NET.announce_start(Coop.run_options())
	start_run()


func _show_victory() -> void:
	Game.set_state(Game.State.VICTORY)
	Game.record_result(true)
	director.stop()
	player.set_controls(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	if NET.active and NET.is_host:
		NET.send("victory", {"wave": Game.wave, "kills": Game.kills, "seconds": int(Game.run_time)})
	game_over.open(Game.completed_waves, Game.kills, int(Game.run_time), Game.best_wave, true)
	get_tree().paused = true


func _continue_endless() -> void:
	if NET.active and not NET.is_host:
		return
	Game.endless = true
	game_over.close()
	if NET.active:
		NET.send("continue", {})
	get_tree().paused = false
	Game.set_state(Game.State.PLAYING)
	player.set_controls(not player.dead)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.visible = true
	director.start_wave(Game.wave + 1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(pause):
		if Game.state == Game.State.PLAYING and not pause.visible and not _dying:
			_open_pause()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()


func _exit_tree() -> void:
	if Coop.main == self:
		Coop.clear_run()
		Coop.main = null


func _on_preview_selected(map_id: String) -> void:
	if _started or not MapDB.ids().has(map_id):
		return
	_preview_requested = map_id
	if _preview_pending:
		return
	_preview_pending = true
	_refresh_map_preview.call_deferred()


func _refresh_map_preview() -> void:
	_preview_pending = false
	if _started or not is_inside_tree():
		return
	if is_instance_valid(map) and map.map_id == _preview_requested:
		return
	_replace_map(_preview_requested)
	_title_t = 0.0


func _replace_map(map_id: String) -> void:
	if is_instance_valid(map):
		map.free()
	map = MapBuilderScript.new()
	map.name = "Arena"
	map.configure(map_id)
	add_child(map)
	map.build()
	player.position = map.player_spawn
	director.setup(player, map.spawn_positions)
	Settings.apply_scene(map)


func _quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	Settings.save()
	NET.leave()
	Sfx.shutdown()
	await get_tree().create_timer(0.12, true).timeout
	get_tree().quit()


func _verify_runtime() -> void:
	for frame in 12:
		await get_tree().process_frame
	print("[runtime] title, map, settings, audio and content loaded")
	_quit_game()
