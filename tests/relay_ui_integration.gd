extends SceneTree

## Run with the standalone relay bound to 127.0.0.1:18778.
## Exercises actual lobby controls and their pressed-signal handlers headlessly.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var network: Node = root.get_node("NET")
	var screen: CanvasLayer = load("res://scripts/ui/multiplayer_screen.gd").new()
	root.add_child(screen)
	screen.open()
	screen._tabs.current_tab = 1
	screen._relay.text = "127.0.0.1"
	if not _check(screen._relay_address() == "127.0.0.1", "UI accepts bare IP"):
		return
	if not _check(network._relay_url("127.0.0.1") == "ws://127.0.0.1:7778/ws", "transport adds default relay port and path"):
		return
	screen._relay.text = "127.0.0.1:18778"
	screen._nickname.text = "裸IP界面审计"
	screen._room.text = ""
	screen._password.text = "ui-beta"
	if not _check(screen._relay_address() == "127.0.0.1:18778", "UI accepts bare IP with custom port"):
		return
	# The real Create Relay button invokes the same handler as a mouse click.
	screen._connect_buttons[2].pressed.emit()
	var deadline := Time.get_ticks_msec() + 10000
	while not network.active:
		if Time.get_ticks_msec() > deadline:
			_check(false, "UI connection timed out: " + screen._status.text)
			return
		await process_frame
	if not _check(network.is_host and network.local_id == 1, "created authenticated host through lobby"):
		return
	if not _check(screen._room.text == network.room_code and screen._room.text.length() == 6, "generated room code appears in UI"):
		return
	if not _check(screen._session.text.contains("ws://127.0.0.1:18778/ws"), "resolved address appears in UI"):
		return
	print("[relay-ui] PASS bare IP, default port, custom port, real create button, generated room and host identity")
	screen._disconnect.pressed.emit()
	if not _check(not network.active and screen._relay.editable, "Leave button restored editable lobby"):
		return
	screen.queue_free()
	await process_frame
	quit(0)

func _check(condition: bool, label: String) -> bool:
	if not condition:
		push_error("[relay-ui] FAIL " + label)
		root.get_node("NET").leave()
		quit(1)
	return condition
