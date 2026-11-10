# 联机传输与远端表现 API

`NET`（`scripts/network/network_session.gd`）只负责会话、身份、名单和 JSON 传输。`Coop` 负责游戏权威模拟。房主 ID 恒为 `1`，房间最多四人。ENet 客户端 ID 是引擎分配的正整数；中转服务器分配小整数。业务代码应使用收到的 ID，不假设客户端为 `2`。

## 会话接口

```text
host_direct(port: int = 7777, nickname: String = "守墨人") -> Error
join_direct(address: String, port: int = 7777, nickname: String = "守墨人") -> Error
host_relay(address: String, room: String = "", password: String = "", nickname: String = "守墨人") -> Error
join_relay(address: String, room: String, password: String = "", nickname: String = "守墨人") -> Error
send(kind: String, data: Dictionary, target: int = 0) -> Error
set_ready(ready: bool)
set_player_name(nickname: String)
announce_start(data: Dictionary = {})
latency_ms(id: int) -> int
latency_text(id: int) -> String
connection_latency_text() -> String
leave()
```

四个连接方法返回 `Error`：`OK` 表示监听成功或已开始连接，异步握手结果以信号为准。`join_relay` 需要房间码；`host_relay` 留空房间码时由服务器生成。中转地址允许仅 IP、`IP:port` 或完整 `ws://IP:port/ws` / `wss://.../ws`，缺省端口为 `7778`。直连用 UDP `7777`；中转用 WebSocket TCP `7778`。使用公网时由部署者开放对应端口。

`active` 表示已完成握手；`connecting` 表示连接中。其他状态为 `is_host`、`local_id`、`host_id`、`mode`（`offline/direct/relay`）、`address`、`room_code`。`peers` 含本机，结构为 `{int_id: {"name": String, "ready": bool}}`。房主初始已准备，其他玩家初始未准备。昵称限制 24 字符。

## 信号与路由

```gdscript
NET.connected
NET.failed(reason: String)
NET.disconnected(reason: String)
NET.peer_joined(id: int)
NET.peer_left(id: int)
NET.roster_changed
NET.latency_updated
NET.message_received(sender: int, kind: String, data: Dictionary)
```

房主 `send(..., target=0)` 广播给所有远端；正整数 `target` 定向给一名队友。客户端所有发送均归到房主，不允许直接转发给其他客户端。发送不会回显给本机。业务层接收快照、开局、结算等指令时还应确认 `sender == NET.host_id`。

`ready` 和 `name` 由 NET 在房主端更新名单，随后广播内部 `_roster` 消息；业务层不应自行构造 `_roster`。`announce_start` 只广播 `start`，实际本机开局由控制器负责。

延迟使用应用层 `_ping` / `_pong` 测量真实往返时间，每秒一次，暂停选卡时仍工作；中转模式包含经中转到房主的完整往返。房主分别测量每位队友，HUD 显示最高队友延迟；客户端显示到房主的延迟。未测得或结果超过 5 秒时 `latency_ms` 返回 `-1`，界面显示「测量中…」。离开房间清空测量结果。

波末客户端发送 `upgrade_refresh`，房主验证该玩家仍在选卡并扣除独立的三次额度，再以 `upgrade_refreshed` 返回卡牌和剩余次数。所有法术施放由房主广播 `skill_fx`，火符命中广播 `spell_impact`；这些消息只创建表现，伤害仍由房主判定。

数据必须由 JSON 支持的字典、数组、字符串、数字、布尔或空值组成。`Vector3` 显式转为 `[x,y,z]`；不要直接发送节点、资源、`Vector2` 或 `Color`。较长生命周期的 64 位对象标识建议转字符串；当前 Node 实例 ID 在测试短局内保持在 JSON 双精度整数的精确范围内。

握手超时 12 秒、单包上限 256 KiB、直连每 peer 每秒最多 180 包。连接方身份由 ENet 的实际 packet peer 或中转服务器写入，不采信客户端声称的 `from`。连接层验证封包形状；具体 `move/fire/upgrade` 等字段、距离、冷却和所有权仍由权威游戏控制器验证。

## 中转服务器封包

首包：`{"op":"create"|"join","room":"CODE","password":"...","name":"..."}`。

服务器欢迎：`{"op":"welcome","peer_id":1,"host_id":1,"room":"CODE","peers":[{"id":1,"name":"..."}]}`。

发送：`{"op":"packet","to":0|peer_id,"data":{"kind":"...","data":{...}}}`。转发时服务器增加可信的 `from`；广播排除发送方，非房主只可发给 `1`。

事件包括 `peer_joined`、`peer_left`、`error` 和 `room_closed`。房主离开后房间关闭，无房主迁移。密码只交给服务端校验，不进入房间名单。

## 远端模型

```gdscript
var model = load("res://scripts/network/remote_player.gd").new()
model.setup(peer_id, nickname, team_index) # 先 setup 再加入场景
add_child(model)
model.update_snapshot({
    "position": [x,y,z], "yaw": yaw, "pitch": pitch,
    "health": hp, "max_health": max_hp, "dead": false,
    "weapon": "brush_pistol", "name": nickname,
})
model.play_shot()
```

模型含插值、行走、六种远端枪型、分色衣饰、名字与血、倒地姿势。它不参与物理和伤害；房主仍维护真正的 Player 权威角色。`update_snapshot` 也接受 `pos/p`、`hp/max_hp`、`current_weapon`、`firing/shot` 别名。

## 已执行验证

直连与中转均已使用**四个独立 Godot 进程**验证：四人同时完成握手、真实身份 ID、双向 JSON、定向回复、房主权威准备名单、正常离开。日志位于 `dev_shots/network-four-*.log`。中转使用项目随附 Windows 服务程序。此测试不等同于外网 NAT 或长时间四人整局压力测试。

双进程审计：先启动 host，再启动 client：

```powershell
Godot --headless --path . --script scripts/network/transport_audit.gd -- --role=host --transport=direct --port=17779
Godot --headless --path . --script scripts/network/transport_audit.gd -- --role=client --transport=direct --port=17779
```

四进程审计：host 增加 `--clients=3`，再启动三个 client。中转先启动 `dist/server/ink-tide-relay-windows-amd64.exe -addr 127.0.0.1:17778`，各 Godot 参数改为 `--transport=relay --port=17778 --room=AUDIT42`。审计使用固定测试密码，代码中已包含该测试配置。

给 host/client 都增加 `--disconnect` 可审计主动关闭房间的回调路径。ENet 的 peer 信号只记录事件，待原生 `poll()` 返回后处理关闭与业务通知；该路径已在五组独立双进程测试中连续通过，未出现回调内释放 ENet 的原生崩溃。
