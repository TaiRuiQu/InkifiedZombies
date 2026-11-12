extends Node

## Browser lifecycle, the small same-page shell bridge and the Paper account
## state. No account secrets cross this boundary: the shell hands over a display
## name and a short-lived room ticket, never the session cookie.
signal interrupted
signal account_changed
signal ticket_received(result: Dictionary)

const NATIVE_ACCOUNT := {"state": "native", "signed_in": false, "name": "", "user_id": ""}

var account: Dictionary = NATIVE_ACCOUNT.duplicate()

var _window: JavaScriptObject
var _callback: JavaScriptObject
var _ticket_callback: JavaScriptObject
var _ticket_pending := false
var _metrics_timer := 0.0
var _diagnostics := false


func is_web() -> bool:
	return OS.has_feature("web")


func is_compatibility() -> bool:
	return is_web() or RenderingServer.get_current_rendering_method() == "gl_compatibility"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not is_web():
		set_process(false)
		return
	# Browsers cannot use the desktop's installed-font fallback for punctuation.
	var brush_font: Font = UITheme.BRUSH
	var fallback_fonts: Array[Font] = [UITheme.BODY]
	brush_font.set_fallbacks(fallback_fonts)
	_window = JavaScriptBridge.get_interface("window")
	_callback = JavaScriptBridge.create_callback(_on_shell_event)
	if _window.InkTideShell:
		_window.InkTideShell.attach(_callback)
		_read_account()
	_diagnostics = OS.get_cmdline_user_args().has("--web-diagnostics")


func _on_shell_event(arguments: Array) -> void:
	if arguments.is_empty():
		return
	match String(arguments[0]):
		"hidden", "pointerlost":
			interrupted.emit()
		"account":
			_read_account()


## Hosting or joining a room needs a Paper account only where Paper serves the
## game. Desktop builds keep their own direct and relay networking.
func account_required() -> bool:
	return is_web()


func account_signed_in() -> bool:
	return bool(account.get("signed_in", false))


func account_name() -> String:
	return String(account.get("name", ""))


func account_ready() -> bool:
	return String(account.get("state", "")) in ["signed-in", "guest"]


func _read_account() -> void:
	if not is_web() or _window == null or not _window.InkTideShell:
		return
	var parsed: Variant = JSON.parse_string(String(_window.InkTideShell.getAccount()))
	if not parsed is Dictionary:
		return
	var updated := {
		"state": String(parsed.get("state", "guest")),
		"signed_in": bool(parsed.get("signedIn", false)),
		"name": String(parsed.get("name", "")),
		"user_id": String(parsed.get("id", "")),
	}
	if updated == account:
		return
	account = updated
	account_changed.emit()


func refresh_account() -> void:
	if is_web() and _window != null and _window.InkTideShell:
		_window.InkTideShell.refreshAccount()
		_read_account()


func open_login() -> void:
	if is_web() and _window != null and _window.InkTideShell:
		_window.InkTideShell.openLogin()


## Asks the shell for a room ticket. Its answer arrives on ticket_received so
## the caller never blocks the main loop while the request travels to Center.
func request_ticket() -> bool:
	if not is_web() or _window == null or not _window.InkTideShell:
		return false
	if _ticket_pending:
		return false
	_ticket_pending = true
	_ticket_callback = JavaScriptBridge.create_callback(_on_ticket_result)
	_window.InkTideShell.requestTicket(_ticket_callback)
	return true


func _on_ticket_result(arguments: Array) -> void:
	_ticket_pending = false
	var parsed: Variant = null
	if not arguments.is_empty():
		parsed = JSON.parse_string(String(arguments[0]))
	var result: Dictionary = parsed if parsed is Dictionary else {"ok": false, "error": "bridge"}
	_read_account()
	ticket_received.emit(result)


func default_relay_url() -> String:
	if is_web() and _window:
		var scheme := "wss://" if String(_window.location.protocol) == "https:" else "ws://"
		return scheme + String(_window.location.host) + "/games/ink-tide/ws"
	return "127.0.0.1"


func requires_secure_relay() -> bool:
	return is_web() and _window != null and String(_window.location.protocol) == "https:"


func return_to_paper() -> void:
	if is_web() and _window:
		_window.location.assign("/")


func _process(delta: float) -> void:
	if not _diagnostics or _window == null or not _window.InkTideShell:
		return
	_metrics_timer += delta
	if _metrics_timer < 1.0:
		return
	_metrics_timer = 0.0
	_window.InkTideShell.record(JSON.stringify({
		"fps": Engine.get_frames_per_second(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"state": Game.state, "wave": Game.wave,
		"network": NET.mode, "host": NET.is_host, "peers": NET.peers.size(),
		"account": String(account.get("state", "")),
		"enemies": get_tree().get_nodes_in_group("enemies").size(),
		"render_scale": get_viewport().scaling_3d_scale,
	}))
