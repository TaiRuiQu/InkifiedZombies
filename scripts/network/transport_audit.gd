extends SceneTree

## Launch in TWO Godot processes: --script scripts/network/transport_audit.gd
## -- --role=host|client --transport=direct|relay --port=17777 --room=AUDIT42
var _session: Node
var _host := false
var _transport := "direct"
var _port := 17777
var _room := "AUDIT42"
var _server := "127.0.0.1"
var _ack := false
var _done := false
var _expected_clients := 1
var _hello_players: Dictionary = {}
var _done_players: Dictionary = {}
var _acks_sent := false
var _disconnect_test := false
var _ever_connected := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_host = arg.trim_prefix("--role=") == "host"
		elif arg.begins_with("--transport="):
			_transport = arg.trim_prefix("--transport=")
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--room="):
			_room = arg.trim_prefix("--room=")
		elif arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--clients="):
			_expected_clients = clampi(int(arg.trim_prefix("--clients=")), 1, 3)
		elif arg == "--disconnect":
			_disconnect_test = true
	_session = load("res://scripts/network/network_session.gd").new()
	root.add_child(_session)
	_session.connected.connect(_connected)
	_session.failed.connect(_connection_failed)
	_session.message_received.connect(_message)
	_session.roster_changed.connect(_roster_changed)
	if _transport == "relay":
		if _host:
			_session.host_relay("%s:%d" % [_server, _port], _room, "audit-password", "审计房主")
		else:
			_session.join_relay("%s:%d" % [_server, _port], _room, "audit-password", "审计队友")
	elif _host:
		_session.host_direct(_port, "审计房主")
	else:
		_session.join_direct(_server, _port, "审计队友")
	await create_timer(15.0).timeout
	if not _done:
		_fail("Timed out waiting for another process.")


func _connected() -> void:
	_ever_connected = true
	print("[transport-audit] %s %s connected id=%d" % [_transport, "host" if _host else "client", _session.local_id])
	if not _host:
		if _disconnect_test:
			_session.send("audit_disconnect", {})
			return
		_session.set_ready(true)
		_session.send("audit_hello", {"value": 42, "vector": [1.0, 2.0, 3.0]})


func _message(sender: int, kind: String, data: Dictionary) -> void:
	if _host and _disconnect_test and kind == "audit_disconnect":
		_session.leave()
		_finish()
		return
	if _host and kind == "audit_hello":
		if int(data.get("value", 0)) != 42 or sender == 1:
			_fail("Invalid client payload/sender.")
			return
		_hello_players[sender] = true
		_try_host_ack()
	elif not _host and kind == "audit_ack":
		if sender != 1 or int(data.get("value", 0)) != 84 or int(data.get("echo_sender", 0)) != _session.local_id:
			_fail("Invalid host response/recipient.")
			return
		_ack = true
		_try_client_done()
	elif _host and kind == "audit_done":
		if not bool(_session.peers[sender].get("ready", false)):
			_fail("Ready roster was not authoritative.")
			return
		_done_players[sender] = true
		if _done_players.size() == _expected_clients:
			_finish()


func _roster_changed() -> void:
	_try_client_done()
	_try_host_ack()


func _try_host_ack() -> void:
	if not _host or _acks_sent or _hello_players.size() != _expected_clients:
		return
	if _session.peers.size() != _expected_clients + 1:
		return
	for id in _hello_players:
		if not bool(_session.peers[id].get("ready", false)):
			return
	_acks_sent = true
	print("[transport-audit] concurrent players=%d" % _session.peers.size())
	for id in _hello_players:
		_session.send("audit_ack", {"value": 84, "echo_sender": int(id)}, int(id))


func _try_client_done() -> void:
	if _host or _done or not _ack or not _session.active:
		return
	if not _session.peers.has(_session.local_id):
		return
	if bool(_session.peers[_session.local_id].get("ready", false)):
		_session.send("audit_done", {"ready": true})
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var description := "host closure handled without poll reentrancy" if _disconnect_test else "authenticated IDs, bidirectional JSON, target routing and host-ready roster"
	print("[transport-audit] PASS %s %s: %s." % [_transport, "host" if _host else "client", description])
	await create_timer(0.5).timeout
	_session.leave()
	for audio: AudioStreamPlayer in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	await create_timer(0.1).timeout
	quit(0)


func _connection_failed(reason: String) -> void:
	if _disconnect_test and not _host and _ever_connected:
		_finish()
	else:
		_fail(reason)


func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	printerr("[transport-audit] FAIL ", reason)
	if _session:
		_session.leave()
	quit(1)
