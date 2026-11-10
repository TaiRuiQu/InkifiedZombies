class_name HUD
extends CanvasLayer

## In-game heads-up display: brush bars, weapon readout, skill seals and
## wave/boss banners.

const EDGE_SHADER: Shader = preload("res://shaders/screen_edges.gdshader")

var player: Player
var director: WaveDirector

var _crosshair: HudWidgets.Crosshair
var _health: HudWidgets.HealthBar
var _ammo: HudWidgets.AmmoPanel
var _skills: Array[HudWidgets.SkillSlot] = []
var _wave: HudWidgets.WavePanel
var _boss: HudWidgets.BossBar
var _banner: HudWidgets.Banner
var _kills: Label
var _time: Label
var _weapon_hint: Label
var _objective: Label
var _team: Label
var _directions: DamageIndicator
var _combat: CombatReadout

var _edge_rect: ColorRect
var _edge_mat: ShaderMaterial
var _damage_flash := 0.0
var _low := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	_edge_rect = ColorRect.new()
	_edge_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_mat = ShaderMaterial.new()
	_edge_mat.shader = EDGE_SHADER
	_edge_rect.material = _edge_mat
	add_child(_edge_rect)

	_crosshair = HudWidgets.Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_crosshair)
	_directions = DamageIndicator.new()
	_directions.name = "IncomingDamageDirections"
	_directions.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_directions)
	_combat = CombatReadout.new()
	_combat.name = "ConfirmedCombatReadout"
	_combat.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_combat)

	_wave = HudWidgets.WavePanel.new()
	_wave.position = Vector2(44, 34)
	_wave.size = Vector2(290, 82)
	add_child(_wave)

	_health = HudWidgets.HealthBar.new()
	_health.position = Vector2(44, 764)
	_health.size = Vector2(338, 96)
	add_child(_health)

	_ammo = HudWidgets.AmmoPanel.new()
	_ammo.position = Vector2(1222, 764)
	_ammo.size = Vector2(334, 96)
	add_child(_ammo)

	for i in 3:
		var s := HudWidgets.SkillSlot.new()
		s.position = Vector2(686.0 + i * 80.0, 804.0)
		s.size = Vector2(64, 72)
		add_child(s)
		_skills.append(s)

	_boss = HudWidgets.BossBar.new()
	_boss.position = Vector2(490, 24)
	_boss.size = Vector2(620, 58)
	_boss.visible = false
	add_child(_boss)

	_banner = HudWidgets.Banner.new()
	_banner.position = Vector2(0, 124)
	_banner.size = Vector2(1600, 160)
	add_child(_banner)

	_kills = UITheme.brush("斩 0", 26, UITheme.PAPER)
	_kills.add_theme_constant_override("outline_size", 7)
	_kills.add_theme_color_override("font_outline_color", UITheme.INK)
	_kills.position = Vector2(1230, 40)
	_kills.size = Vector2(326, 32)
	_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_kills)

	_time = UITheme.body("00:00", 14, UITheme.PAPER_DARK)
	_time.add_theme_constant_override("outline_size", 5)
	_time.add_theme_color_override("font_outline_color", UITheme.INK)
	_time.position = Vector2(1230, 70)
	_time.size = Vector2(326, 24)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_time)

	_objective = UITheme.body("", 15, UITheme.PAPER)
	_objective.position = Vector2(46, 125)
	_objective.size = Vector2(440, 56)
	_objective.add_theme_constant_override("outline_size", 5)
	_objective.add_theme_color_override("font_outline_color", UITheme.INK)
	add_child(_objective)
	_team = UITheme.body("", 16, UITheme.PAPER)
	_team.position = Vector2(46, 208)
	_team.size = Vector2(440, 180)
	_team.add_theme_constant_override("outline_size", 5)
	_team.add_theme_color_override("font_outline_color", UITheme.INK)
	add_child(_team)

	_weapon_hint = UITheme.brush("V 近战 · R 装填 · 1-5 换枪", 16, UITheme.PAPER_DARK)
	_weapon_hint.add_theme_constant_override("outline_size", 5)
	_weapon_hint.add_theme_color_override("font_outline_color", UITheme.INK)
	_weapon_hint.position = Vector2(1190, 736)
	_weapon_hint.size = Vector2(366, 24)
	_weapon_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_weapon_hint)


func bind(p: Player, d: WaveDirector) -> void:
	player = p
	director = d
	player.damaged.connect(_on_damaged)
	player.hitmarker.connect(_on_hitmarker)
	player.stats_changed.connect(_refresh_immediate)
	player.damage_direction.connect(_on_damage_direction)
	player.combat_feedback.connect(_on_combat_feedback)
	_directions.bind(player, player.camera)
	_refresh_immediate()


func _on_damaged(amount: float) -> void:
	var add := clampf(amount / maxf(player.max_health, 1.0) * 0.9 + 0.12, 0.15, 0.8)
	_damage_flash = clampf(_damage_flash + add, 0.0, 1.0)


func _on_hitmarker(killed: bool, crit: bool) -> void:
	_crosshair.trigger_hit(killed, crit)


func _on_damage_direction(amount: float, source_position: Vector3, shield_hit: bool) -> void:
	_directions.push_hit(amount, source_position, shield_hit)


func _on_combat_feedback(amount: float, critical: bool, killed: bool, headshot: bool) -> void:
	_crosshair.trigger_hit(killed, critical, headshot)
	_combat.push_feedback(amount, critical, killed, headshot)


func _refresh_immediate() -> void:
	if not player:
		return
	_update_ammo()


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	_t += delta
	_damage_flash = move_toward(_damage_flash, 0.0, delta * 1.7)
	var ratio := player.health_ratio()
	_low = 0.0
	if ratio < 0.35 and not player.dead:
		_low = (0.35 - ratio) / 0.35 * (0.55 + 0.18 * sin(_t * 4.0))
	if player.dead:
		_low = 0.55
	var flashes := bool(Settings.get_value("damage_flash"))
	_edge_mat.set_shader_parameter("flash", _damage_flash if flashes else 0.0)
	_edge_mat.set_shader_parameter("low", _low if flashes else 0.0)

	_crosshair.spread = player.spread_degrees()
	_crosshair.enemy = player.aim_at_enemy
	_crosshair.aiming = player.aiming

	_health.set_values(player.health, player.max_health, player.shield, player.max_shield)
	_update_ammo()

	var slots := player.skill_slots()
	var order := ["nova", "dash", "talisman"]
	for i in order.size():
		_skills[i].set_values(slots[order[i]])

	if is_instance_valid(director):
		var rem := director.remaining() if director.wave_active else 0
		_wave.set_values(maxi(Game.wave, 1), rem, director.total_enemies())
		var br := director.boss_ratio()
		if br >= 0.0:
			_boss.visible = true
			_boss.set_values(br, Game.wave)
		else:
			_boss.visible = false
	else:
		_wave.set_values(maxi(Game.wave, 1), 0, 0)

	_kills.text = "斩 %d" % Game.kills
	var secs := int(Game.run_time)
	_time.text = "%02d:%02d" % [int(secs / 60), secs % 60]
	_objective.text = "%s · %s\n%s" % [MapDB.get_map(Game.selected_map).display_name,
		RunRules.difficulty(Game.difficulty).name, "无尽守夜 · 每五波迎战墨将" if Game.endless else "目标：肃清十波 · 第五 / 十波迎战墨将"]
	_weapon_hint.text = "%s 近战 · %s 装填 · 滚轮 / 1–6 换枪" % [Settings.binding_text("melee"), Settings.binding_text("reload")]
	_team.text = Coop.team_status() if NET.active else ""



func _update_ammo() -> void:
	if not is_instance_valid(player):
		return
	var w := player.get_weapon_data()
	_ammo.set_values(String(w.name), String(w.type), player.current_mag(), player.current_mag_cap(),
		player.current_reserve(), player.current_reserve_cap(), player.reloading,
		player.reload_ratio(), player.owned_weapons.duplicate(), player.current_weapon_index())


func show_banner(title: String, subtitle: String, color: Color = UITheme.CINNABAR, duration: float = 2.4) -> void:
	_banner.show_text(title, subtitle, color, duration)


func flash_damage(amount: float) -> void:
	_on_damaged(amount)


func clear_banner() -> void:
	_banner.active = false
	_banner.visible = false
