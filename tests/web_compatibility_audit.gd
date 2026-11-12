extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("[web-compatibility] FAIL " + label)

func count_type(node: Node, kind: String) -> int:
	var total := 1 if node.is_class(kind) else 0
	for child in node.get_children():
		total += count_type(child, kind)
	return total

func _run() -> void:
	root.get_node("Game")._test_profile = true
	var network := root.get_node("NET")
	check(network._relay_url("127.0.0.1") == "ws://127.0.0.1:7778/ws", "bare native address preserves relay port")
	check(network._relay_url("wss://paperagent.work/games/ink-tide/ws") == "wss://paperagent.work/games/ink-tide/ws", "WSS path does not gain port 7778")
	check(network._relay_url("ws://localhost:40000/games/ink-tide/ws") == "ws://localhost:40000/games/ink-tide/ws", "development URL stays intact")
	check(network._relay_url("wss://relay.example/") == "wss://relay.example/ws", "explicit secure endpoint uses default TLS port")
	var browser := root.get_node("Browser")
	check(not browser.account_required(), "native builds keep direct and relay play without a Paper account")
	check(not browser.account_signed_in(), "native builds report no signed-in Paper account")
	check(not browser.request_ticket(), "native builds never ask the shell for a room ticket")
	check(network._friendly_error("login_required", "") != "login_required", "relay account errors get a friendly message")
	root.get_node("Settings")._apply_quality()
	check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "Compatibility disables unsupported screen-space AA")
	var holder := Node3D.new()
	root.add_child(holder)
	var first: Node3D = load("res://scenes/enemy.tscn").instantiate()
	var second: Node3D = load("res://scenes/enemy.tscn").instantiate()
	first.setup("wraith", 1, false)
	second.setup("wraith", 1, false)
	holder.add_child(first)
	holder.add_child(second)
	first.frozen = true
	second.frozen = true
	check(not first._flash_materials.is_empty(), "Compatibility uses per-actor flash materials")
	first.flash = 0.8
	first._apply_flash()
	for material in first._flash_materials:
		check(is_equal_approx(float(material.get_shader_parameter("hit_flash")), 0.8), "hit actor flashes")
	for material in second._flash_materials:
		var other_flash: Variant = material.get_shader_parameter("hit_flash")
		check(other_flash == null or is_zero_approx(float(other_flash)), "other actor does not flash")
	for id: String in MapDB.ids():
		var map: Node3D = load("res://scripts/world/map_builder.gd").new()
		holder.add_child(map)
		map.configure(id)
		map.build()
		var collisions := count_type(map, "CollisionShape3D")
		var meshes := count_type(map, "MeshInstance3D")
		map._batch_static_geometry()
		check(count_type(map, "CollisionShape3D") == collisions, "batching preserves map collision")
		check(count_type(map, "MeshInstance3D") < meshes, "batching reduces independent meshes")
		check(is_instance_valid(map._dome), "sky remains independently movable")
		print("[web-compatibility] map=%s meshes=%d -> %d collisions=%d" % [id, meshes, count_type(map, "MeshInstance3D"), collisions])
		map.queue_free()
		await process_frame
	holder.queue_free()
	root.get_node("Sfx").shutdown()
	await create_timer(1.5).timeout
	print("[web-compatibility] RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
