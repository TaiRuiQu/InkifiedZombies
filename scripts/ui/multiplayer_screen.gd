class_name MultiplayerScreen
extends CanvasLayer

## A lobby shared by direct ENet and hosted relay transports. The network
## service owns connectivity; the main scene owns starting the actual run.
signal start_requested
signal closed

var _root: Control
var _tabs: TabContainer
var _nickname: LineEdit
var _ip: LineEdit
var _port: SpinBox
var _relay: LineEdit
var _room: LineEdit
var _password: LineEdit
var _status: Label
var _session: Label
var _members: VBoxContainer
var _ready_button: Button
var _start_button: Button
var _disconnect: Button
var _copy_button: Button
var _back: Button
var _connect_buttons: Array[Button] = []
var _busy := false
var _last_roster := ""
var _launch_requested := false


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	NET.connected.connect(_on_connected)
	NET.failed.connect(_on_failed)
	NET.roster_changed.connect(_refresh)
	NET.latency_updated.connect(_refresh)
	NET.peer_joined.connect(_on_peer_changed)
	NET.peer_left.connect(_on_peer_changed)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = SettingsScreen.create_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.022, 0.018, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.085
	panel.anchor_right = 0.915
	panel.anchor_top = 0.055
	panel.anchor_bottom = 0.945
	panel.add_theme_stylebox_override("panel", SettingsScreen._style(UITheme.PAPER, UITheme.INK, 2))
	_root.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 25)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := UITheme.brush("同 守 · 好 友 联 机", 42)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var caption := UITheme.body("至多四人 · 同赴墨境，共守长夜", 15, UITheme.MUTED)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(caption)
	var profile := HBoxContainer.new()
	profile.add_theme_constant_override("separation", 16)
	layout.add_child(profile)
	profile.add_child(UITheme.body("你的名字", 16))
	_nickname = _edit("守墨人", "好友看见的昵称", 24)
	_nickname.custom_minimum_size = Vector2(250, 42)
	profile.add_child(_nickname)
	var run_note := UITheme.body("开局采用房主在标题选定的墨境、难度与征途", 13, UITheme.MUTED)
	run_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	run_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile.add_child(run_note)
	# Keep the main area scrollable at small window sizes without losing actions.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	scroll.add_child(body)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(650, 420)
	body.add_child(_tabs)
	_build_direct(_tab("直 连"))
	_build_relay(_tab("中 转"))
	var lobby := VBoxContainer.new()
	lobby.custom_minimum_size.x = 360
	lobby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby.size_flags_stretch_ratio = 0.65
	lobby.add_theme_constant_override("separation", 12)
	body.add_child(lobby)
	lobby.add_child(UITheme.brush("守 夜 人", 29, UITheme.INDIGO))
	_session = UITheme.body("尚未加入房间", 14, UITheme.MUTED)
	_session.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_session.custom_minimum_size.y = 50
	lobby.add_child(_session)
	var roster_panel := PanelContainer.new()
	roster_panel.add_theme_stylebox_override("panel", SettingsScreen._style(UITheme.PAPER_LIGHT, UITheme.PAPER_DARK, 1))
	roster_panel.custom_minimum_size.y = 176
	lobby.add_child(roster_panel)
	_members = VBoxContainer.new()
	_members.add_theme_constant_override("separation", 10)
	roster_panel.add_child(_members)
	_copy_button = _button("复制联机信息", _copy_invite)
	lobby.add_child(_copy_button)
	_ready_button = _button("准 备 就 绪", _toggle_ready)
	lobby.add_child(_ready_button)
	_start_button = _button("开 始 同 守", _request_start)
	lobby.add_child(_start_button)
	_note(lobby, "房主可独自试开；有好友加入后，需所有好友就绪再出发。", 13)
	_status = UITheme.body("选择直连或中转，创建房间或加入好友。", 15, UITheme.INDIGO)
	_status.custom_minimum_size.y = 52
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	layout.add_child(footer)
	var hint := UITheme.body("ESC 返回标题 · 连接只在离开房间时断开", 13, UITheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)
	_disconnect = _button("离 开 房 间", _leave)
	_disconnect.custom_minimum_size.x = 190
	footer.add_child(_disconnect)
	_back = _button("返 回 标 题", close)
	_back.custom_minimum_size.x = 190
	footer.add_child(_back)
	_refresh()


func _tab(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	_tabs.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	return column


func _build_direct(column: VBoxContainer) -> void:
	_note(column, "局域网好友可直接加入。房主创建后，把本机 IP 与端口发给好友。")
	_ip = _edit("127.0.0.1", "房主的 IP 或主机名", 253)
	_field(column, "房主地址", _ip)
	_port = SpinBox.new()
	_port.min_value = 1
	_port.max_value = 65535
	_port.step = 1
	_port.value = 7777
	_port.allow_greater = false
	_port.allow_lesser = false
	_port.add_theme_icon_override("updown", load("res://assets/ui/port_stepper.svg"))
	_port.tooltip_text = "直连使用 UDP；房主与好友必须使用相同端口。"
	_port.custom_minimum_size.y = 44
	_port.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field(column, "UDP 端口", _port)
	_note(column, "房主创建时无需填写地址。跨网络直连需要路由器转发 UDP 端口，也可使用中转。", 13)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var host := _button("创 建 直 连", _host_direct)
	var join := _button("加 入 直 连", _join_direct)
	row.add_child(host)
	row.add_child(join)
	_connect_buttons.append(host)
	_connect_buttons.append(join)
	_ip.text_submitted.connect(_submit_direct)


func _build_relay(column: VBoxContainer) -> void:
	_note(column, "通过好友或自建的中转服务相聚，无需房主开放本地端口。")
	_relay = _edit("127.0.0.1", "服务器 IP，例如 203.0.113.10；也支持 ws:// 地址", 512)
	_field(column, "中转地址", _relay)
	_room = _edit("", "创建可留空；自定义码 4–16 位", 16)
	_field(column, "房间码", _room)
	_password = _edit("", "可选 · 只与好友分享", 64)
	_password.secret = true
	_field(column, "房间密码", _password)
	_note(column, "中转服务需先运行。分享中转地址与房间码；密码不会复制到邀请信息或保存。", 13)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var host := _button("创 建 中 转", _host_relay)
	var join := _button("加 入 中 转", _join_relay)
	row.add_child(host)
	row.add_child(join)
	_connect_buttons.append(host)
	_connect_buttons.append(join)
	_room.text_submitted.connect(_submit_relay)


func _field(column: VBoxContainer, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name_label := UITheme.body(label, 16)
	name_label.custom_minimum_size.x = 100
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	column.add_child(row)


func _edit(text: String, placeholder: String, maximum: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.max_length = maximum
	edit.custom_minimum_size.y = 44
	edit.clear_button_enabled = true
	return edit


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_button_activated.bind(callback))
	button.mouse_entered.connect(_button_hovered)
	button.focus_entered.connect(_button_hovered)
	return button


func _button_activated(callback: Callable) -> void:
	if not visible:
		return
	Sfx.play("click", -8.0)
	if callback.is_valid():
		callback.call()


func _button_hovered() -> void:
	if visible:
		Sfx.play("hover", -17.0)


func _on_peer_changed(_id: int) -> void:
	_refresh()


func _submit_direct(_text: String) -> void:
	_join_direct()


func _submit_relay(_text: String) -> void:
	_join_relay()


func _note(column: VBoxContainer, text: String, font_size: int = 14) -> void:
	var label := UITheme.body(text, font_size, UITheme.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(label)


func _player_name() -> String:
	var result: String = _nickname.text.strip_edges()
	return result if not result.is_empty() else "守墨人"


func _can_connect() -> bool:
	if not visible or NET.active or NET.connecting or _busy:
		return false
	return true


func _begin_connection(message: String) -> void:
	_busy = true
	_set_status(message)
	_refresh()


func _host_direct() -> void:
	if not _can_connect():
		return
	_port.apply()
	_begin_connection("正在创建直连房间…")
	NET.host_direct(int(_port.value), _player_name())


func _join_direct() -> void:
	if not _can_connect():
		return
	var address: String = _ip.text.strip_edges()
	if address.is_empty() or address.contains("/") or address.contains(" "):
		_set_status("请填写房主 IP 或主机名，不需要 http:// 前缀。", true)
		_ip.grab_focus()
		return
	_port.apply()
	_begin_connection("正在连接 %s:%d…" % [address, int(_port.value)])
	NET.join_direct(address, int(_port.value), _player_name())


func _relay_address() -> String:
	var address: String = _relay.text.strip_edges()
	if address.is_empty() or address.contains(" ") or address.contains("\n"):
		_set_status("请输入服务器 IP 或有效的中转地址。", true)
		_relay.grab_focus()
		return ""
	if address.contains("://") and not (address.begins_with("ws://") or address.begins_with("wss://")):
		_set_status("支持服务器 IP、ws:// 或 wss:// 地址。", true)
		return ""
	return address


func _host_relay() -> void:
	if not _can_connect():
		return
	var address: String = _relay_address()
	if address.is_empty():
		return
	var room := _validated_room(true)
	if room == "!invalid":
		return
	_begin_connection("正在连接中转服务并创建房间…")
	NET.host_relay(address, room, _password.text, _player_name())


func _join_relay() -> void:
	if not _can_connect():
		return
	var address: String = _relay_address()
	if address.is_empty():
		return
	var room := _validated_room(false)
	if room == "!invalid":
		return
	_begin_connection("正在加入中转房间 %s…" % room)
	NET.join_relay(address, room, _password.text, _player_name())


func _validated_room(allow_empty: bool) -> String:
	var room := _room.text.strip_edges().to_upper()
	if room.is_empty() and allow_empty:
		return ""
	if room.length() < 4 or room.length() > 16:
		_set_status("房间码应为 4–16 位英文字母或数字；请核对好友的房间码。", true)
		_room.grab_focus()
		return "!invalid"
	for index in room.length():
		var code := room.unicode_at(index)
		if not (code >= 48 and code <= 57 or code >= 65 and code <= 90):
			_set_status("房间码仅接受英文字母与数字。", true)
			_room.grab_focus()
			return "!invalid"
	_room.text = room
	return room


func _on_connected() -> void:
	_busy = false
	for index in _tabs.get_tab_count():
		_tabs.set_tab_disabled(index, false)
	_tabs.current_tab = 1 if NET.mode == "relay" else 0
	if NET.mode == "relay":
		_room.text = NET.room_code
	_set_status("房间已建立，等待好友加入。" if NET.is_host else "已加入房间。准备就绪后，等待房主开始。")
	_refresh()
	_focus_connected.call_deferred()


func _on_failed(reason: String) -> void:
	_busy = false
	_set_status(reason, true)
	_refresh()


func _set_status(text: String, error: bool = false) -> void:
	_status.text = ("未能完成 · " + text) if error else text
	_status.add_theme_color_override("font_color", UITheme.CINNABAR if error else UITheme.INDIGO)


func _refresh() -> void:
	if _disconnect == null:
		return
	var connected: bool = NET.active
	var locked: bool = connected or NET.connecting or _busy
	for button: Button in _connect_buttons:
		button.disabled = locked
	for edit: LineEdit in [_nickname, _ip, _relay, _room, _password]:
		edit.editable = not locked
	_port.editable = not locked
	_disconnect.disabled = not locked
	_disconnect.text = "取 消 连 接" if locked and not connected else "离 开 房 间"
	for index in _tabs.get_tab_count():
		_tabs.set_tab_disabled(index, locked and index != _tabs.current_tab)
	_copy_button.disabled = not connected
	_ready_button.disabled = not connected or NET.is_host
	_ready_button.visible = not connected or not NET.is_host
	_start_button.visible = connected and NET.is_host
	_start_button.disabled = _launch_requested or not can_start()
	_start_button.text = "正 在 入 墨…" if _launch_requested else ("开 始 同 守" if can_start() else "等 待 好 友 就 绪")
	if connected:
		var mine: Dictionary = NET.peers.get(NET.local_id, {})
		_ready_button.text = "取 消 就 绪" if bool(mine.get("ready", false)) else "准 备 就 绪"
		if NET.mode == "relay":
			_session.text = "中转 · 房间 %s\n%s" % [NET.room_code, NET.address]
		else:
			_session.text = "直连 · %s\n%d 位守夜人" % [NET.address, NET.peers.size()]
		_session.text += " · " + NET.connection_latency_text()
	else:
		_session.text = "正在连接…" if locked else "尚未加入房间"
	var roster_signature: String = JSON.stringify(NET.peers) + str(NET.local_id)
	for id in NET.peers:
		roster_signature += "|%d:%d" % [int(id), NET.latency_ms(int(id))]
	if roster_signature == _last_roster:
		return
	_last_roster = roster_signature
	for child: Node in _members.get_children():
		child.queue_free()
	if NET.peers.is_empty():
		_members.add_child(UITheme.body("墨未起，静候同伴。", 15, UITheme.MUTED))
		return
	var ids: Array = NET.peers.keys()
	ids.sort()
	for peer_id: Variant in ids:
		var peer: Dictionary = NET.peers[peer_id]
		var row := HBoxContainer.new()
		var suffix: String = " · 房主" if int(peer_id) == NET.host_id else ""
		if int(peer_id) == NET.local_id:
			suffix += " · 你"
		elif NET.is_host or int(peer_id) == NET.host_id:
			suffix += " · " + NET.latency_text(int(peer_id))
		var name_label := UITheme.body(String(peer.get("name", "守墨人")) + suffix, 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_label)
		var ready: bool = bool(peer.get("ready", false))
		row.add_child(UITheme.body("已就绪" if ready else "准备中", 13, UITheme.INDIGO if ready else UITheme.MUTED))
		_members.add_child(row)


func can_start() -> bool:
	if not NET.active or not NET.is_host:
		return false
	for peer_id: Variant in NET.peers:
		if int(peer_id) == NET.local_id:
			continue
		var peer: Dictionary = NET.peers[peer_id]
		if not bool(peer.get("ready", false)):
			return false
	return true


func _toggle_ready() -> void:
	if not NET.active or NET.is_host:
		return
	var mine: Dictionary = NET.peers.get(NET.local_id, {})
	var ready := not bool(mine.get("ready", false))
	NET.set_ready(ready)
	_set_status("已就绪，等待房主开始；可再次点击取消。" if ready else "已取消就绪，可继续整理准备。")
	_refresh()


func _request_start() -> void:
	if _launch_requested:
		return
	if visible and can_start():
		_launch_requested = true
		_refresh()
		start_requested.emit()
	else:
		_set_status("请等待所有好友准备就绪。", true)


func invitation_text() -> String:
	if not NET.active:
		return ""
	var invite: String
	if NET.mode == "relay":
		invite = "墨潮 · 好友同守\n中转：%s\n房间码：%s" % [NET.address, NET.room_code]
	else:
		var addresses: Array[String] = []
		for address: String in IP.get_local_addresses():
			if address.contains(".") and not address.begins_with("127.") and not address.begins_with("169.254."):
				addresses.append(address)
		var host: String = " / ".join(addresses) if NET.is_host else _ip.text.strip_edges()
		if host.is_empty():
			host = "127.0.0.1（仅本机测试）"
		invite = "墨潮 · 好友同守\n直连地址：%s\nUDP 端口：%d" % [host, int(_port.value)]
	return invite


func _copy_invite() -> void:
	var invite := invitation_text()
	if invite.is_empty():
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(invite)
	_set_status("已复制联机信息。房间密码请单独告诉好友。" if NET.mode == "relay" else "已复制本机候选 IP 与端口；请使用与好友网络相通的地址。")


func _leave() -> void:
	NET.leave()
	_busy = false
	_launch_requested = false
	_last_roster = ""
	_set_status("已离开房间，可以重新创建或加入。")
	_refresh()


func open() -> void:
	visible = true
	_launch_requested = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NET.active:
		_nickname.text = NET.player_name
		if NET.mode == "relay":
			_tabs.current_tab = 1
			_relay.text = NET.address
			_room.text = NET.room_code
		else:
			_tabs.current_tab = 0
			var separator: int = NET.address.rfind(":")
			if separator > 0:
				_port.value = int(NET.address.substr(separator + 1))
				if not NET.is_host:
					_ip.text = NET.address.substr(0, separator)
	_refresh()
	_focus_initial.call_deferred()


func _focus_initial() -> void:
	if not visible or not is_inside_tree():
		return
	if NET.active:
		_focus_connected()
	elif not NET.connecting and not _busy:
		UITheme.focus_later(_nickname)
	else:
		UITheme.focus_later(_disconnect)


func _focus_connected() -> void:
	if not visible or not is_inside_tree() or not NET.active:
		return
	if NET.is_host:
		if can_start():
			UITheme.focus_later(_start_button)
		else:
			UITheme.focus_later(_copy_button)
	else:
		UITheme.focus_later(_ready_button)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event.alt_pressed or event.meta_pressed):
		return
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
