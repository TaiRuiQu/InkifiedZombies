# Ink Tide relay / 墨潮公网中转

`dist/server/` 包含可直接运行的 Windows x64 与 Linux x64 中转程序。服务器只转发消息，**不需要 Godot、不需要数据库**，游戏逻辑由房主客户端运行。一个房间最多 4 人，房主离开时房间关闭。

## 直接运行

Windows PowerShell，在二进制所在目录运行：

```powershell
.\ink-tide-relay-windows-amd64.exe -addr :7778
```

Linux x64：

```sh
chmod +x ink-tide-relay-linux-amd64
./ink-tide-relay-linux-amd64 -addr :7778
```

随后在游戏「多人同守 → 公网中转」填写服务器公网 IP，或完整地址 `ws://服务器IP:7778/ws`。房主创建房间后，把服务器地址、六位房间码和可选密码告知同伴；同伴选加入。房主仍需点击开始，服务器不自动开始对局。

仅本机联调可用 `ws://127.0.0.1:7778/ws`。`127.0.0.1` 代表玩家自己的电脑；跨电脑时填写中转机器的局域网 IP 或公网 IP。

- 监听地址默认 `:7778`，接受所有网卡连接。
- 云服务器安全组与系统防火墙需要允许 **TCP 7778 入站**。中转玩家通常无需端口映射。
- 如果在家用网络自建公网中转，需要路由器把 TCP 7778 映射到运行中转的电脑；没有公网 IPv4 的网络可部署到云服务器。
- 直连模式使用游戏房主的 **UDP 7777**，与本中转的 TCP 7778 是不同端口。
- `http://服务器IP:7778/healthz` 返回服务状态与房间数；不会公开房间码、密码或玩家名。
- 使用 Ctrl+C / SIGTERM 关闭服务器，客户端收到 `room_closed`。

Windows 管理员可按实际需要添加规则：

```powershell
New-NetFirewallRule -DisplayName "Ink Tide relay" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 7778
```

Ubuntu 使用 UFW 时：

```sh
sudo ufw allow 7778/tcp
```

## 启动参数

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `-addr` | `:7778` | HTTP / WebSocket 监听地址 |
| `-max-rooms` | `256` | 同时存在的房间上限 |
| `-max-connections` | `1024` | 包括握手中的连接总上限 |
| `-tls-cert` | 空 | 可选 PEM 证书 |
| `-tls-key` | 空 | 可选 PEM 私钥，需与证书一起提供 |

有可信域名证书时可直接提供 TLS 证书：

```sh
./ink-tide-relay-linux-amd64 -addr :7778 -tls-cert fullchain.pem -tls-key privkey.pem
```

游戏填写 `wss://relay.example.com:7778/ws`。也可在 Caddy / Nginx 后方运行 `-addr 127.0.0.1:7778`，反向代理 WebSocket 路径 `/ws`，域名对外使用 `wss://relay.example.com/ws`。公网长期部署建议使用 WSS，使房间密码和战斗流量经过 TLS 加密。

systemd 最简示例（先把二进制放入 `/opt/ink-tide/`）：

```ini
[Unit]
Description=Ink Tide relay
After=network-online.target

[Service]
ExecStart=/opt/ink-tide/ink-tide-relay-linux-amd64 -addr :7778
Restart=on-failure
RestartSec=3
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
```

## 协议 v1

所有帧使用 UTF-8 JSON。连接 `/ws` 后 **10 秒内**发送首帧。

创建房间（`room` 为空时自动生成六位无歧义大写房间码；也允许 4–16 位英文字母/数字自定义房间码）：

```json
{"op":"create","room":"","name":"守夜人","password":"可选密码"}
```

加入：

```json
{"op":"join","room":"ABC234","name":"同行者","password":"可选密码"}
```

成功后首个服务消息总是 `welcome`：

```json
{"op":"welcome","peer_id":2,"host_id":1,"room":"ABC234","peers":[{"id":1,"name":"守夜人"},{"id":2,"name":"同行者"}]}
```

房主固定 `peer_id=1`；房客从 2 递增，离开后不会在同一房间复用旧 ID。服务将玩家名字截断到 24 个 Unicode 字符，过滤控制字符。房间密码仅保留 SHA-256 摘要，不在回包或日志中输出。

| 方向 | 帧 | 行为 |
| --- | --- | --- |
| 客户端 → 服务 | `{"op":"packet","to":1,"data":{"kind":"input","data":{}}}` | 向房主提交输入；`data` 保持原 JSON |
| 房主 → 服务 | `{"op":"packet","to":0,"data":{"kind":"snapshot","data":{}}}` | 向本房所有其他玩家广播；不回送发送者 |
| 房主 → 服务 | `{"op":"packet","to":2,"data":{}}` | 定向发给指定房客 |
| 服务 → 客户端 | `{"op":"packet","from":1,"data":{}}` | `from` 总由服务根据连接写入，忽略客户端伪造字段 |
| 服务 → 客户端 | `{"op":"peer_joined","peer_id":3,"name":"墨客"}` | 有玩家进入 |
| 服务 → 客户端 | `{"op":"peer_left","peer_id":3}` | 有房客离开 |
| 服务 → 客户端 | `{"op":"room_closed","reason":"host_left"}` | 房主离开；随后关闭 WebSocket |
| 客户端 → 服务 | `{"op":"ping"}` | 应用心跳；服务回复 `{"op":"pong"}` |

**房客只允许 `to:1`**；只有房主可以广播权威状态。服务器不执行游戏逻辑，也不接受客户端指定的发送者身份。不同房间永不互相转发。

失败消息为 `{"op":"error","code":"room_full","message":"..."}`。握手失败随后断开；对局期间无效目标或越权消息被拒绝，连接仍保留。错误码包括 `handshake_required`、`bad_json`、`text_required`、`invalid_room`、`password_too_long`、`room_exists`、`room_not_found`、`wrong_password`、`room_full`、`server_full`、`server_closing`、`unknown_op`、`invalid_data`、`invalid_target`、`host_only`、`peer_not_found`、`room_closed`。

限制：每帧最大 256 KiB；每连接最多缓存 128 个待发消息；服务每 15 秒发送 WebSocket Ping，45 秒无数据/Pong断开；写超时 5 秒。无在线玩家的房间不保留，服务器重启后所有房间消失。此服务不提供匹配、账号、存档、房主迁移或游戏反作弊。

## 从源码构建与测试

需要 Go 1.24+。依赖版本锁定在 `go.mod` / `go.sum`，仅使用 Gorilla WebSocket 与 Go 标准库。

```powershell
# 在 server 目录
 go test -count=1 -v ./...
 .\build.ps1
```

或手动交叉构建：

```sh
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ../dist/server/ink-tide-relay-windows-amd64.exe .
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ../dist/server/ink-tide-relay-linux-amd64 .
```

测试覆盖：带密码创建/加入、Unicode名字、四人容量与重连、新peer ID、身份防伪、房主广播/客人输入、客人越权拒绝、无效目标、房主断线清房、房间上限、超大帧断开、握手超时、健康检查。

官方参考：Go 的 `net/http` / `httptest`、Gorilla WebSocket 的 `doc.go` 并发与控制帧说明。第三方许可见 `THIRD_PARTY_LICENSES.md`。
