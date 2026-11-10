extends Node

## Transport boundary. All gameplay packets are JSON dictionaries. Clients
## submit commands to the host; only the host can broadcast authoritative state.
signal message_received(sender: int, kind: String, data: Dictionary)
signal peer_joined(id: int)
signal peer_left(id: int)
signal connected
signal failed(reason: String)
signal disconnected(reason: String)
signal roster_changed

const MAX_PLAYERS := 4
const MAX_PACKET_BYTES := 262144
const CONNECT_TIMEOUT := 12.0
const DIRECT_PORT := 7777
const RELAY_PORT := 7778

var active := false
var connecting := false
var is_host := false
var local_id := 0
var host_id := 1
var peers: Dictionary = {}
var mode := "offline"
var address := ""
var room_code := ""
var player_name := "守墨人"

var _direct: ENetMultiplayerPeer
var _relay: WebSocketPeer
var _started_at := 0.0
var _hello_sent := false
var _relay_auth: Dictionary = {}
var _pending: Dictionary = {}
var _rates: Dictionary = {}
var _direct_events: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func host_direct(port: int = DIRECT_PORT, nickname: String = "守墨人") -> Error:
	leave()
	if port < 1 or port > 65535:
		return _reject("端口必须在 1–65535 之间。", ERR_INVALID_PARAMETER)
	player_name = _clean_name(nickname)
	_direct = ENetMultiplayerPeer.new()
	var result := _direct.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		return _reject("无法监听端口 %d，请检查端口占用或防火墙。" % port, result)
	mode = "direct"
	address = "0.0.0.0:%d" % port
	is_host = true
	local_id = 1
	active = true
	peers[1] = {"name": player_name, "ready": true}
	_connect_direct_signals()
	connected.emit()
	roster_changed.emit()
	return OK


func join_direct(host_address: String, port: int = DIRECT_PORT,
		nickname: String = "守墨人") -> Error:
	leave()
	var clean_address := host_address.strip_edges()
	if clean_address.is_empty() or port < 1 or port > 65535:
		return _reject("请输入有效的房主 IP 和端口。", ERR_INVALID_PARAMETER)
	player_name = _clean_name(nickname)
	_direct = ENetMultiplayerPeer.new()
	var result := _direct.create_client(clean_address, port)
	if result != OK:
		return _reject("无法连接房主：%s。" % error_string(result), result)
	mode = "direct"
	address = "%s:%d" % [clean_address, port]
	connecting = true
	_started_at = _now()
	_connect_direct_signals()
	return OK


func host_relay(server_address: String, room: String = "", password: String = "",
		nickname: String = "守墨人") -> Error:
	return _begin_relay(server_address, room, password, nickname, true)


func join_relay(server_address: String, room: String, password: String = "",
		nickname: String = "守墨人") -> Error:
	if room.strip_edges().is_empty():
		return _reject("请输入房间码。", ERR_INVALID_PARAMETER)
	return _begin_relay(server_address, room, password, nickname, false)


func _begin_relay(server_address: String, room: String, password: String,
		nickname: String, hosting: bool) -> Error:
	leave()
	var clean_address := server_address.strip_edges()
	if clean_address.is_empty():
		return _reject("请输入中转服务器 IP。", ERR_INVALID_PARAMETER)
	address = _relay_url(clean_address)
	room_code = room.strip_edges().to_upper()
	player_name = _clean_name(nickname)
	is_host = hosting
	mode = "relay"
	connecting = true
	_started_at = _now()
	_relay_auth = {"op": "create" if hosting else "join", "room": room_code,
		"password": password.left(128), "name": player_name}
	_relay = WebSocketPeer.new()
	_relay.inbound_buffer_size = MAX_PACKET_BYTES * 2
	_relay.outbound_buffer_size = MAX_PACKET_BYTES * 2
	var result := _relay.connect_to_url(address)
	if result != OK:
		return _reject("无法连接中转服务器：%s。" % error_string(result), result)
	return OK


func _process(_delta: float) -> void:
	if _direct:
		_poll_direct()
	if _relay:
		_poll_relay()
	if connecting and _now() - _started_at > CONNECT_TIMEOUT:
		_fail("连接超时，请检查 IP、端口、防火墙及服务器状态。")
	if is_host and _direct:
		for id in _pending.keys():
			if _now() - float(_pending[id]) > CONNECT_TIMEOUT:
				_direct.disconnect_peer(int(id))
				_pending.erase(id)


func _connect_direct_signals() -> void:
	_direct.peer_connected.connect(_on_direct_peer_connected)
	_direct.peer_disconnected.connect(_on_direct_peer_disconnected)


func _poll_direct() -> void:
	# ENet emits peer signals synchronously from poll(). Never close/free a
	# peer, notify application listeners, or disconnect peers inside that native
	# callback: doing so can invalidate ENet's current dispatch stack.
	var polled_peer := _direct
	polled_peer.poll()
	if _direct != polled_peer:
		return
	var pending_events := _direct_events.duplicate()
	_direct_events.clear()
	for event in pending_events:
		if event.has("joined"):
			_apply_direct_peer_connected(int(event.joined))
		else:
			_apply_direct_peer_disconnected(int(event.left))
		if _direct != polled_peer:
			return
	var status := _direct.get_connection_status()
	if not is_host:
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_fail("与房主的连接已断开。")
			return
		if status == MultiplayerPeer.CONNECTION_CONNECTED and not _hello_sent:
			local_id = _direct.get_unique_id()
			_hello_sent = true
			_direct_write({"op": "hello", "name": player_name}, 1)
	var budget := 160
	while _direct and _direct.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var sender := _direct.get_packet_peer()
		var packet := _direct.get_packet()
		if packet.size() > MAX_PACKET_BYTES or not _allow_rate(sender):
			continue
		var decoded: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if decoded is Dictionary:
			_handle_direct(sender, decoded)


func _on_direct_peer_connected(id: int) -> void:
	_direct_events.append({"joined": id})


func _on_direct_peer_disconnected(id: int) -> void:
	_direct_events.append({"left": id})


func _apply_direct_peer_connected(id: int) -> void:
	if not is_host:
		return
	if peers.size() + _pending.size() >= MAX_PLAYERS:
		_direct.disconnect_peer(id)
		return
	_pending[id] = _now()


func _apply_direct_peer_disconnected(id: int) -> void:
	_pending.erase(id)
	_rates.erase(id)
	if not is_host:
		if id == 1:
			_fail("房主已离开。")
		return
	if peers.erase(id):
		peer_left.emit(id)
		_broadcast_roster()


func _handle_direct(sender: int, envelope: Dictionary) -> void:
	if not envelope.get("op", null) is String:
		return
	if is_host:
		if envelope.op == "hello":
			if not _pending.has(sender) or peers.has(sender):
				return
			_pending.erase(sender)
			peers[sender] = {"name": _clean_name(_wire_text(envelope.get("name", null), "守墨人")), "ready": false}
			_direct_write({"op": "welcome", "peer_id": sender, "host_id": 1,
				"room": "", "peers": _roster_array()}, sender)
			peer_joined.emit(sender)
			_broadcast_roster()
			return
		if not peers.has(sender) or envelope.op != "packet":
			return
		var destination := _wire_id(envelope.get("to", 1))
		if destination != 0 and destination != 1:
			return
		_receive_payload(sender, envelope.get("data", {}))
	else:
		# The ENet server is the only trusted source of routed sender identities.
		if sender != 1:
			return
		if envelope.op == "welcome" and connecting:
			_accept_welcome(envelope)
		elif envelope.op == "packet" and active:
			_receive_payload(_wire_id(envelope.get("from", 1)), envelope.get("data", {}))


func _poll_relay() -> void:
	# Keep a strong local reference through the native poll, as with ENet.
	var polled_socket := _relay
	polled_socket.poll()
	if _relay != polled_socket:
		return
	var status := _relay.get_ready_state()
	if status == WebSocketPeer.STATE_CLOSED:
		_fail("中转连接已断开，请检查服务器和房间状态。")
		return
	if status != WebSocketPeer.STATE_OPEN:
		return
	if not _hello_sent:
		_hello_sent = true
		_relay.send_text(JSON.stringify(_relay_auth))
		_relay_auth.clear()
	var budget := 160
	while _relay and _relay.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var packet := _relay.get_packet()
		if packet.size() > MAX_PACKET_BYTES:
			continue
		var decoded: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not decoded is Dictionary:
			continue
		_handle_relay(decoded)


func _handle_relay(envelope: Dictionary) -> void:
	var op := _wire_text(envelope.get("op", null))
	match op:
		"welcome":
			if connecting:
				_accept_welcome(envelope)
		"peer_joined":
			if not active:
				return
			var id := _wire_id(envelope.get("peer_id", 0))
			if id <= 0 or id == local_id or peers.has(id):
				return
			peers[id] = {"name": _clean_name(String(envelope.get("name", "守墨人"))), "ready": false}
			peer_joined.emit(id)
			if is_host:
				_broadcast_roster()
			else:
				roster_changed.emit()
		"peer_left":
			var id := _wire_id(envelope.get("peer_id", 0))
			if peers.erase(id):
				peer_left.emit(id)
				if is_host:
					_broadcast_roster()
				else:
					roster_changed.emit()
		"packet":
			if active:
				_receive_payload(_wire_id(envelope.get("from", 0)), envelope.get("data", {}))
		"error":
			_fail(_friendly_error(String(envelope.get("code", "")), String(envelope.get("message", "连接失败。"))))
		"room_closed":
			_fail("房主已关闭房间。")


func _accept_welcome(envelope: Dictionary) -> void:
	var assigned := _wire_id(envelope.get("peer_id", 0))
	if assigned <= 0 or _wire_id(envelope.get("host_id", 1)) != 1:
		_fail("服务器返回了无效的会话信息。")
		return
	local_id = assigned
	is_host = local_id == 1
	room_code = String(envelope.get("room", room_code))
	_apply_roster(envelope.get("peers", []))
	if not peers.has(local_id):
		peers[local_id] = {"name": player_name, "ready": is_host}
	connecting = false
	active = true
	connected.emit()
	roster_changed.emit()


func send(kind: String, data: Dictionary, target: int = 0) -> Error:
	if not active:
		return ERR_UNCONFIGURED
	if kind.is_empty() or kind.length() > 64:
		return ERR_INVALID_PARAMETER
	if not is_host:
		target = 1
	elif target == local_id:
		return OK
	if target != 0 and not peers.has(target):
		return ERR_DOES_NOT_EXIST
	var payload := {"kind": kind, "data": data}
	var envelope := {"op": "packet", "to": target, "data": payload}
	if mode == "direct":
		if is_host:
			envelope["from"] = 1
		return _direct_write(envelope, target if is_host else 1)
	if _relay and _relay.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var wire := JSON.stringify(envelope)
		if wire.to_utf8_buffer().size() > MAX_PACKET_BYTES:
			return ERR_OUT_OF_MEMORY
		return _relay.send_text(wire)
	return ERR_CONNECTION_ERROR


func _direct_write(envelope: Dictionary, target: int) -> Error:
	if not _direct:
		return ERR_UNCONFIGURED
	var bytes := JSON.stringify(envelope).to_utf8_buffer()
	if bytes.size() > MAX_PACKET_BYTES:
		return ERR_OUT_OF_MEMORY
	_direct.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_direct.set_target_peer(target)
	return _direct.put_packet(bytes)


func _receive_payload(sender: int, raw_payload: Variant) -> void:
	if sender <= 0 or sender == local_id or not peers.has(sender) or not raw_payload is Dictionary:
		return
	var payload: Dictionary = raw_payload
	if not payload.get("kind", null) is String or not payload.get("data", null) is Dictionary:
		return
	var kind: String = payload.kind
	var data: Dictionary = payload.data
	if kind.is_empty() or kind.length() > 64:
		return
	if is_host and kind == "ready":
		peers[sender]["ready"] = bool(data.get("ready", false))
		_broadcast_roster()
	elif is_host and kind == "name":
		peers[sender]["name"] = _clean_name(_wire_text(data.get("name", null), "守墨人"))
		_broadcast_roster()
	elif kind == "_roster":
		if sender != 1 or is_host:
			return
		_apply_roster(data.get("peers", []))
		roster_changed.emit()
		return
	message_received.emit(sender, kind, data)


func set_ready(ready: bool) -> void:
	if not active or not peers.has(local_id):
		return
	if is_host:
		peers[local_id]["ready"] = ready
		_broadcast_roster()
	else:
		send("ready", {"ready": ready})


func set_player_name(nickname: String) -> void:
	player_name = _clean_name(nickname)
	if not active:
		return
	if is_host:
		peers[local_id]["name"] = player_name
		_broadcast_roster()
	else:
		send("name", {"name": player_name})


func announce_start(data: Dictionary = {}) -> void:
	if is_host and active:
		send("start", data)


func _broadcast_roster() -> void:
	if is_host and active:
		send("_roster", {"peers": _roster_array()})
	roster_changed.emit()


func _roster_array() -> Array:
	var result: Array = []
	for id in peers:
		result.append({"id": int(id), "name": String(peers[id].get("name", "守墨人")),
			"ready": bool(peers[id].get("ready", int(id) == 1))})
	return result


func _apply_roster(raw_roster: Variant) -> void:
	if not raw_roster is Array or raw_roster.size() > MAX_PLAYERS:
		return
	var updated: Dictionary = {}
	for raw_entry in raw_roster:
		if not raw_entry is Dictionary:
			continue
		var id := _wire_id(raw_entry.get("id", 0))
		if id <= 0:
			continue
		updated[id] = {"name": _clean_name(String(raw_entry.get("name", "守墨人"))),
			"ready": bool(raw_entry.get("ready", id == 1))}
	var previous := peers.keys()
	peers = updated
	if active:
		for id in previous:
			if int(id) != local_id and not peers.has(id):
				peer_left.emit(int(id))
		for id in peers:
			if int(id) != local_id and not previous.has(id):
				peer_joined.emit(int(id))


func leave() -> void:
	var old_peers := peers.keys()
	var old_id := local_id
	active = false
	connecting = false
	var old_direct := _direct
	_direct = null
	if old_direct:
		old_direct.close()
	var old_relay := _relay
	_relay = null
	if old_relay:
		old_relay.close(1000, "leaving")
	peers.clear()
	_pending.clear()
	_rates.clear()
	_direct_events.clear()
	_relay_auth.clear()
	_hello_sent = false
	is_host = false
	local_id = 0
	mode = "offline"
	address = ""
	room_code = ""
	for id in old_peers:
		if int(id) != old_id:
			peer_left.emit(int(id))
	if not old_peers.is_empty():
		roster_changed.emit()


func _reject(reason: String, error: Error) -> Error:
	_fail(reason)
	return error


func _fail(reason: String) -> void:
	var was_active := active
	leave()
	failed.emit(reason)
	if was_active:
		disconnected.emit(reason)


func _allow_rate(sender: int) -> bool:
	var now := _now()
	var entry: Dictionary = _rates.get(sender, {"time": now, "count": 0})
	if now - float(entry.time) >= 1.0:
		entry = {"time": now, "count": 0}
	entry.count = int(entry.count) + 1
	_rates[sender] = entry
	return int(entry.count) <= 180


func _clean_name(value: String) -> String:
	var cleaned := value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ").left(24)
	return cleaned if not cleaned.is_empty() else "守墨人"


func _wire_id(value: Variant) -> int:
	if (value is int or value is float) and is_finite(float(value)):
		if float(value) >= 0.0 and float(value) <= 2147483647.0:
			return int(value)
	return -1


func _wire_text(value: Variant, fallback: String = "") -> String:
	return value if value is String else fallback


func _relay_url(value: String) -> String:
	var result := value
	if not result.begins_with("ws://") and not result.begins_with("wss://"):
		result = "ws://" + result
	var scheme_end := result.find("://") + 3
	var path_start := result.find("/", scheme_end)
	var authority := result.substr(scheme_end) if path_start < 0 else result.substr(scheme_end, path_start - scheme_end)
	if not authority.contains(":"):
		result = result.substr(0, scheme_end) + authority + ":%d" % RELAY_PORT + ("" if path_start < 0 else result.substr(path_start))
	if path_start < 0 or result.ends_with("/"):
		result = result.trim_suffix("/") + "/ws"
	return result


func _friendly_error(code: String, fallback: String) -> String:
	return String({"room_exists": "房间码已被占用，请换一个或留空自动生成。",
		"room_not_found": "未找到房间，请核对房间码。", "wrong_password": "房间密码不正确。",
		"room_full": "房间已满，最多四名守墨人。", "host_left": "房主已离开。",
		"invalid_room": "房间码需为 4–16 位英文字母或数字。"}.get(code, fallback))


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
