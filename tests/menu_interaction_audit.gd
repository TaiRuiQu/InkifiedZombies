extends SceneTree

var _failures := 0
var _choice_count := 0
var _last_choice := ""
var _action_count := 0
var _start_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	print("[menus] %s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures += 1


func _chosen(data: Dictionary) -> void:
	_choice_count += 1
	_last_choice = String(data.get("id", ""))


func _action() -> void:
	_action_count += 1


func _start() -> void:
	_start_count += 1


func _run() -> void:
	var net: Node = root.get_node("NET")
	var coop: Node = root.get_node("Coop")
	net.leave()
	var choices: Array = []
	var database: Script = load("res://scripts/core/upgrades.gd")
	for index in 3:
		choices.append(database.LIST[index])
	var upgrades: CanvasLayer = load("res://scripts/ui/upgrade_screen.gd").new()
	root.add_child(upgrades)
	upgrades.chosen.connect(_chosen)
	upgrades.open(2, choices)
	await process_frame
	_check(upgrades._cards[0].has_focus(), "upgrade begins on first card")
	_check(upgrades._cards[0].focus_mode == Control.FOCUS_ALL, "cards accept keyboard focus")
	_check(upgrades._cards[0].find_next_valid_focus() == upgrades._cards[1], "Tab moves from first to second card")
	_check(upgrades._cards[2].find_next_valid_focus() == upgrades._skip, "Tab reaches healing skip action")
	upgrades._cards[1].grab_focus()
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.pressed = true
	paused = true
	upgrades._cards[1]._gui_input(accept)
	upgrades._cards[1].activate()
	_check(upgrades._choosing and upgrades._cards[1]._selected, "Enter locks and stamps the chosen card")
	_check(not upgrades._skip.enabled and upgrades._cards[0].focus_mode == Control.FOCUS_NONE, "choice locks all alternative actions")
	await create_timer(0.65).timeout
	paused = false
	_check(_choice_count == 1 and _last_choice == String(choices[1].id), "keyboard choice emits once while tree is paused")
	upgrades.open(3, choices)
	upgrades._cards[0].activate()
	upgrades.close()
	await create_timer(0.65).timeout
	_check(_choice_count == 1, "closing the menu cancels pending delayed choice")
	upgrades.open(3, choices)
	upgrades._cards[2].activate()
	upgrades.open(4, choices)
	await create_timer(0.65).timeout
	_check(_choice_count == 1 and upgrades.visible, "reopening cancels stale animation and result")
	upgrades._on_skip()
	await create_timer(0.65).timeout
	_check(_choice_count == 2 and _last_choice == "skip_heal", "healing skip completes exactly once")
	upgrades.queue_free()
	await process_frame
	var pause_menu: CanvasLayer = load("res://scripts/ui/pause_menu.gd").new()
	root.add_child(pause_menu)
	pause_menu.restart_requested.connect(_action)
	coop.connection_lost = true
	pause_menu.open()
	await process_frame
	_check(not pause_menu._resume_button.enabled and not pause_menu._restart_button.enabled, "disconnected pause disables resume and restart")
	_check(pause_menu._back_button.has_focus(), "disconnected pause defaults to return action")
	coop.connection_lost = false
	net.active = true
	net.is_host = false
	pause_menu.open()
	pause_menu._request_restart()
	_check(_action_count == 0 and pause_menu._restart_button.text.contains("房主"), "guest pause explains and blocks host-only restart")
	pause_menu.close()
	net.leave()
	var result: CanvasLayer = load("res://scripts/ui/game_over_screen.gd").new()
	root.add_child(result)
	result.restart_requested.connect(_action)
	result.continue_requested.connect(_action)
	result.open(3, 12, 100, 5)
	await process_frame
	_check(result._restart_button.has_focus(), "defeat defaults to restart")
	result._request_restart()
	result._request_restart()
	_check(_action_count == 1, "result action cannot submit twice")
	result.close()
	result.open(10, 122, 600, 10, true)
	await process_frame
	_check(result._continue.has_focus() and result._wave_caption.text == "肃清", "victory defaults to continuing with correct labels")
	result.close()
	net.active = true
	net.is_host = false
	result.open(10, 122, 600, 10, true)
	await process_frame
	result._request_continue()
	result._request_restart()
	_check(_action_count == 1 and result._back_button.has_focus(), "guest result defaults to return and blocks host actions")
	_check(result._footer.text.contains("房主"), "guest result explicitly explains host control")
	result.close()
	net.leave()
	var lobby: CanvasLayer = load("res://scripts/ui/multiplayer_screen.gd").new()
	root.add_child(lobby)
	lobby.start_requested.connect(_start)
	lobby.open()
	await process_frame
	_check(lobby._nickname.has_focus(), "new lobby focuses name instead of accidentally starting")
	lobby._ip.text = "http://invalid"
	lobby._join_direct()
	_check(not net.active and lobby._status.text.contains("未能完成"), "invalid direct address shows inline error")
	lobby._tabs.current_tab = 1
	lobby._relay.text = "127.0.0.1"
	lobby._room.text = "??"
	lobby._join_relay()
	_check(not net.connecting and lobby._status.text.contains("房间码"), "invalid room is rejected before connection")
	lobby._room.text = "abcd42"
	_check(lobby._validated_room(false) == "ABCD42", "room code is normalized")
	_check(net.host_direct(21777, "菜单审计") == OK, "direct room can be created")
	lobby._refresh()
	_check(lobby.can_start() and not lobby._copy_button.disabled, "host room enables invitation and start")
	net.peers[2] = {"name": "好友", "ready": false}
	lobby._refresh()
	_check(lobby._start_button.disabled and lobby._start_button.text.replace(" ", "").contains("等待"), "unready friend blocks start with explicit status")
	net.peers[2].ready = true
	lobby._refresh()
	_check(not lobby._start_button.disabled, "all ready enables start")
	lobby._request_start()
	lobby._request_start()
	_check(_start_count == 1, "lobby start submits once")
	_check(not lobby.invitation_text().contains("密码"), "invitation never includes secret password")
	lobby._leave()
	_check(not net.active and lobby._nickname.editable and lobby._disconnect.disabled, "leave restores editable lobby")
	lobby.close()
	var singleton_settings: Node = root.get_node("Settings")
	singleton_settings.bindings_changed.emit()
	lobby.queue_free()
	pause_menu.queue_free()
	result.queue_free()
	await process_frame
	print("[menus] RESULT failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)
