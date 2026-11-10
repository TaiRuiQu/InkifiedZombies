extends SceneTree

## Actual input, physics, damage and weapon presentation on a real Player.
## Uses an isolated raised floor and low ceiling instead of mocking movement.
var _main: Node3D
var _player: Node3D
var _world: Node3D
var _vfx: Script
var _checks := 0
var _failures: Array[String] = []
var _damage_events: Array[Dictionary] = []
const ORIGIN := Vector3(0, 30, 0)

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, text: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(text)
		push_error("[actions] FAIL " + text)

func _run() -> void:
	root.get_node("Game")._test_profile = true
	root.get_node("NET").leave()
	root.get_node("Settings").save_path = "user://test_settings.cfg"
	root.get_node("Settings").set_value("camera_shake", true)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_main.director.stop()
	_main.title.close()
	_world = Node3D.new()
	_main.add_child(_world)
	_box(Vector3(16, 0.5, 16), ORIGIN - Vector3.UP * 0.25)
	_vfx = load("res://scripts/fx/vfx.gd")
	_player = _main.player
	_player.position = ORIGIN + Vector3.UP * 0.1
	_player.head.rotation = Vector3.ZERO
	_player.set_controls(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.damage_direction.connect(_on_damage_direction)
	await create_timer(0.3).timeout
	await _test_crouch()
	await _test_jump_land()
	_player.set_controls(false)
	await _test_weapon_actions()
	await _test_melee()
	await _test_damage_feedback()
	await _test_reload()
	await _test_casings()
	print("[actions] RESULT checks=%d failures=%d" % [_checks, _failures.size()])
	Input.action_release("crouch")
	Input.action_release("jump")
	root.get_node("Settings").set_value("camera_shake", true)
	root.get_node("Settings").set_value("damage_flash", true)
	for sound in root.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
		sound.stream = null
	for sound in root.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
		sound.stream = null
	await create_timer(0.2).timeout
	quit(0 if _failures.is_empty() else 1)

func _test_crouch() -> void:
	_check(_player.is_on_floor(), "fixture player rests on physical floor")
	var standing_eye: float = _player.camera.global_position.y
	Input.action_press("crouch")
	await create_timer(0.3).timeout
	_check(_player.crouching and (_player._body_collision.shape as CapsuleShape3D).height < 1.3, "crouch input reduces real collision height")
	_check(standing_eye - _player.camera.global_position.y > 0.42, "crouch lowers actual viewpoint")
	var ceiling := _box(Vector3(3, 0.20, 3), ORIGIN + Vector3.UP * 1.55)
	await physics_frame
	await physics_frame
	_check(not _player._can_stand(), "low ceiling rejects standing clearance")
	Input.action_release("crouch")
	await create_timer(0.2).timeout
	_check(_player.crouching and (_player._body_collision.shape as CapsuleShape3D).height < 1.3, "releasing crouch under cover cannot clip into ceiling")
	ceiling.free()
	await create_timer(0.3).timeout
	_check(not _player.crouching and (_player._body_collision.shape as CapsuleShape3D).height > 1.7, "removing ceiling restores standing collision")
	_check(absf(_player.camera.global_position.y - standing_eye) < 0.06, "standing restores eye height")
	print("[actions] crouch / clearance / viewpoint checked")

func _test_jump_land() -> void:
	var initial_y: float = _player.global_position.y
	var peak := initial_y
	var airborne := false
	var landed := false
	var landing_impulse := false
	Input.action_press("jump")
	for index in 90:
		await physics_frame
		if index == 2:
			Input.action_release("jump")
		peak = maxf(peak, _player.global_position.y)
		if not _player.is_on_floor():
			airborne = true
		elif airborne:
			landed = true
			landing_impulse = _player._landing_offset < -0.02 or _player.view._kick.y < -0.015
			break
	_check(airborne and peak > initial_y + 0.5, "jump input produces actual upward travel")
	_check(landed and absf(_player.global_position.y - initial_y) < 0.06, "jump lands back on the same floor")
	_check(landing_impulse, "actual landing triggers camera / gun compression")
	await create_timer(0.8).timeout
	_check(absf(_player.camera.position.y) < 0.015 and absf(_player._landing_offset) < 0.002, "landing camera settles without persistent offset")
	print("[actions] jump / landing / settling checked")

func _test_weapon_actions() -> void:
	var amplitudes := {}
	for id in WeaponDB.all_ids():
		_player.unlock_weapon(id)
		_player.switch_to_index(_player.owned_weapons.find(id))
		await create_timer(0.35).timeout
		_player.reloading = false
		_player.recoil = Vector2.ZERO
		_player.camera.rotation = Vector3.ZERO
		_player.trauma = 0.0
		_player.ammo[id].mag = maxi(2, _player.current_mag_cap())
		var weapon := WeaponDB.get_weapon(id)
		_player._fire_shot(weapon, _player.ammo[id], {"shot_seed": 511, "shot_spread": 0.0})
		amplitudes[id] = _player.recoil.x
		_check(_player.recoil.x > 0.0, id + " shot kicks camera upward")
		await process_frame
		await process_frame
		_check(_player.camera.rotation.x > 0.0, id + " actual camera follows upward recoil")
		_check(_player.view.position.z > float(weapon.view_pos.z), id + " weapon physically recoils toward player")
	_check(float(amplitudes.ink_shotgun) > float(amplitudes.wolf_smg) * 2.0, "heavy shotgun recoil differs from SMG")
	_check(float(amplitudes.cinnabar_rifle) > float(amplitudes.brush_pistol) * 1.5, "rifle recoil differs from sidearm")
	_player.switch_to_index(_player.owned_weapons.find("brush_pistol"))
	await process_frame
	await process_frame
	_check(_player.view.position.y < float(_player.get_weapon_data().view_pos.y) - 0.12, "equipping visibly raises gun from below")
	await create_timer(0.4).timeout
	_check(absf(_player.view.position.y - float(_player.get_weapon_data().view_pos.y)) < 0.025, "equip animation completes at usable rest pose")
	# A close obstacle should visibly lower the weapon, then release it again.
	var obstacle := _box(Vector3(3, 4, 0.18), _player.camera.global_position + Vector3.FORWARD * 0.55)
	await create_timer(0.2).timeout
	_check(_player.view.wall_proximity > 0.4 and _player.view.position.z > float(_player.get_weapon_data().view_pos.z) + 0.07, "close wall retracts visible gun")
	obstacle.free()
	await create_timer(0.5).timeout
	_check(_player.view.wall_proximity < 0.05 and _player.view.rotation.length() < 0.03, "clearing wall restores gun pose without accumulating tilt")
	# Local confirmation briefly holds the gun; the simulation clock stays live.
	var engine_scale := Engine.time_scale
	_player.view.notify_fire()
	_player.confirm_combat(10.0, true, false, true)
	var shot_age: float = _player.view.model.shot_age
	_player.view.update_motion(0.005, 0.0, true)
	_check(is_equal_approx(_player.view.model.shot_age, shot_age), "confirmed impact briefly holds only gun animation")
	_check(is_equal_approx(Engine.time_scale, engine_scale), "impact never freezes global simulation")
	await create_timer(0.7).timeout
	_check(_player.view.rotation.length() < 0.03, "impact pose returns to rest")
	print("[actions] six weapon recoils / equip / cover / local impact checked")

func _test_melee() -> void:
	var enemy: Node3D = load("res://scenes/enemy.tscn").instantiate()
	enemy.setup("wraith", 1, false)
	enemy.frozen = true
	enemy.position = _player.global_position + Vector3.FORWARD * 1.7
	_world.add_child(enemy)
	enemy.complete_spawn_visual()
	enemy.max_health = 1000.0
	enemy.health = 1000.0
	await physics_frame
	await physics_frame
	_player.head.look_at(enemy.aim_point(), Vector3.UP)
	_player.melee_cd = 0.0
	var initial: float = enemy.health
	_player._melee_attack()
	_check(is_equal_approx(enemy.health, initial), "melee windup does not damage instantly")
	await create_timer(0.045).timeout
	_check(is_equal_approx(enemy.health, initial), "melee windup remains readable before contact")
	await create_timer(0.095).timeout
	_check(enemy.health < initial and enemy.health >= initial - 35.0, "melee contact applies a single delayed strike")
	_check(absf(_player.view.rotation.z) > 0.25, "melee contact occurs during visible gun sweep")
	await create_timer(0.55).timeout
	_check(_player.view.rotation.length() < 0.03, "melee sweep returns to rest")
	enemy.free()
	_player.head.rotation = Vector3.ZERO
	print("[actions] timed melee checked")

func _test_damage_feedback() -> void:
	var settings := root.get_node("Settings")
	settings.set_value("camera_shake", false)
	settings.set_value("damage_flash", false)
	_player.recoil = Vector2.ZERO
	_player.camera.rotation = Vector3.ZERO
	_player.invuln_time = 0.0
	_player.max_shield = 30.0
	_player.shield = 30.0
	_player.health = _player.max_health
	var initial_health: float = _player.health
	var source := _player.global_position + Vector3.RIGHT * 3
	_player.take_damage(12.0, null, 0.0, source)
	_check(_player.health == initial_health and _player.shield < 20.0, "shield absorbs real incoming damage")
	_check(not _damage_events.is_empty() and bool(_damage_events.back().shield), "shield hit emits the shield-colored direction event")
	_check(_main.hud._directions.direction_for(source).dot(Vector2.RIGHT) > 0.95, "right-side impact points to attacker")
	await process_frame
	await process_frame
	_check(_player.camera.rotation.length() < 0.001, "camera shake preference suppresses hurt rotation")
	_check(not _main.hud._directions.entries.is_empty(), "direction HUD remains active with shake and flash disabled")
	_player.invuln_time = 0.0
	_player.shield = 0.0
	var other_side := _player.global_position + Vector3.LEFT * 3
	_player.take_damage(8.0, null, 0.0, other_side)
	_check(_player.health < initial_health and not bool(_damage_events.back().shield), "flesh hit emits distinct direction event")
	_check(_main.hud._directions.entries.size() >= 2, "opposite attackers retain separate directional warnings")
	_player.head.rotation.y = PI * 0.5
	_check(absf(_main.hud._directions.direction_for(source).y) > 0.95, "warning tracks world attacker as player turns")
	_player.head.rotation = Vector3.ZERO
	await create_timer(0.7).timeout
	_check(_player.view.rotation.length() < 0.03, "hurt gun pose settles without drift")
	settings.set_value("camera_shake", true)
	settings.set_value("damage_flash", true)
	print("[actions] shield / flesh / direction / comfort checked")

func _test_reload() -> void:
	_player.switch_to_index(_player.owned_weapons.find("wolf_smg"))
	_player.reloading = false
	_player.ammo.wolf_smg.mag = 8
	_player.ammo.wolf_smg.reserve = 100
	_player.start_reload()
	_check(_player.reloading and int(_player.ammo.wolf_smg.mag) == 8, "reload begins without granting ammunition early")
	await create_timer(_player.reload_total * 0.60).timeout
	_check(_player._reload_stages & 1 != 0 and _player._reload_stages & 2 == 0, "reload reaches insertion before bolt action")
	await create_timer(_player.reload_total * 0.30).timeout
	_check(_player._reload_stages & 2 != 0 and _player.reloading, "reload reaches bolt action before completing")
	await create_timer(_player.reload_total * 0.25).timeout
	_check(not _player.reloading and int(_player.ammo.wolf_smg.mag) == 35 and int(_player.ammo.wolf_smg.reserve) == 73, "completed reload transfers exact reserve rounds")
	_player.switch_to_index(_player.owned_weapons.find("brush_pistol"))
	_player.reloading = false
	_player.ammo.brush_pistol.mag = 0
	_player.ammo.brush_pistol.reserve = 2
	_player.start_reload()
	await create_timer(_player.reload_total + 0.08).timeout
	_check(int(_player.ammo.brush_pistol.mag) == 2 and int(_player.ammo.brush_pistol.reserve) == 2, "sidearm reload preserves emergency reserve")
	print("[actions] reload timing / ammunition checked")

func _test_casings() -> void:
	for casing in get_nodes_in_group("spent_casings"):
		casing.queue_free()
	await process_frame
	var sfx := root.get_node("Sfx")
	var previous_tinkle := int(sfx._recent.get("casing_world", -1))
	for index in 40:
		_vfx.call("eject_casing", _world, ORIGIN + Vector3(0, 1.1, 0), Vector3.RIGHT)
	_check(get_nodes_in_group("spent_casings").size() == 24, "rapid fire casing population remains bounded at 24")
	await create_timer(0.9).timeout
	var bounced := false
	for casing in get_nodes_in_group("spent_casings"):
		bounced = bounced or casing.bounces > 0
	_check(bounced, "ejected casings physically bounce off the floor")
	_check(int(sfx._recent.get("casing_world", -1)) > previous_tinkle, "casing impact reaches spatial tinkle playback")
	await create_timer(1.1).timeout
	_check(get_nodes_in_group("spent_casings").is_empty(), "casing lifetime cleans up all spent objects")
	print("[actions] casing budget / bounce / sound / cleanup checked")

func _box(size: Vector3, where: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = where
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	_world.add_child(body)
	return body

func _on_damage_direction(amount: float, where: Vector3, shield: bool) -> void:
	_damage_events.append({"amount": amount, "source": where, "shield": shield})
