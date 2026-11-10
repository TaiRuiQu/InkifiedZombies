# v0.2 内测与验证说明

本版验证分为内容结构、战斗规则、完整流程、网络传输、多人实战、画面与人工试玩。**传输成功不等于整局合作体验通过；十波自动推进也不等于真实玩家难度已经平衡。**

## 当前已确认的范围

以下为 2026-11-10 本机验证范围。最终验收应保留相应命令、退出码、日志与画面，修改代码后重跑受影响项目。

| 项目 | 已验证内容 | 不能据此推导的结论 |
| --- | --- | --- |
| 地图 / 武器结构回归 | 两张地图、八个出生口、不同井位、装饰批次；六把武器创建、切枪、枪口、支撑手、开火与装填动画 | 所有视角都无遮挡、低配 FPS 达标 |
| 六类敌人模型审计 | 关节、有效网格、材质、合并网格缓存、注册与波次解锁 | 所有动画观感与碰撞都已人工验收 |
| 敌人战斗审计 | 实体墙阻挡近战 / 范围伤害、开放空间可命中、绕障选择切线、Boss 扇射覆盖左右 | 任意复杂地图不会卡路或穿模 |
| 房间 UI 集成 | 打开、创建直连、房主独自可开始、好友未就绪阻止开始、全员就绪、离开与关闭 | 公网 NAT / 防火墙环境已覆盖 |
| 真实 Godot 多进程传输 | 直连与中转均通过双进程及四进程并发测试；身份、双向 JSON、定向路由、就绪名单、正常退出 | 四人十波整局已稳定、弱网无延迟问题 |
| Go 中转服务 | 七项服务测试通过；密码 / 容量、名字、路由身份、越权拒绝、房主断开、握手 / 消息限制、健康检查 | 已完成真实公网压力、TLS 与 Linux 目标机运行验收 |
| Windows 运行时包 | 已从不含工程的临时工作目录无界面独立启动 `InkTide.exe`，PCK 资源载入无错误，正常退出 | 正式 release template 导出、全部目标机器与打包后图形性能均已验证 |
| 客户端完整流程 | `--beta-test` 零失败通过；实际击杀 122 个敌人，逐波确认场上清空，覆盖设置往返、暂停恢复、初始疾风步、十波 / 双 Boss、升级、胜利、无尽与死亡结算 | 自动化无敌 / 批量伤害可代表人工游玩平衡 |
| 多人实战流程 | 直连与真实 Go 中转均通过双 Godot 进程完整回归：远端战斗、防重复射击、血 / 倒地、清波复活、双人选卡、第二波、双方重开保持连接与失败结算；两端退出码均为 0 | 已覆盖四人真实公网长局、所有延迟 / 丢包与重连条件 |

单人完整流程日志为 `dev_shots/beta_test.log`，结果 `failures=0 kills=122`；多人实战完整结果位于 `dev_shots/coop-{direct,relay}-{host,client}.log`，四个进程均输出最终 PASS；另完成五轮真实房主断线回归，未出现原生崩溃。四人真实跨网长局、不同 NAT、丢包 / 高延迟、重连和目标硬件性能仍需独立试玩。Windows / Linux 中转二进制已经构建，Linux 文件的交叉构建成功不代替 Linux 实机运行。

## 快速回归命令

从工程根目录执行。以下 PowerShell 路径按本机示例，可改为实际 Godot 控制台程序位置：

```powershell
$godot = "G:\Godot\Godot_v4.7.2-stable_win64_console.exe"

# 注册新脚本类并检查整个工程导入
& $godot --headless --path . --editor --quit

# 两地图与全部六枪的结构、切换与动画
& $godot --headless --path . --script res://tests/model_content_smoke.gd

# 全部敌人外观 / 关节 / 缓存与数据注册
& $godot --headless --path . --script res://scripts/enemies/model_audit.gd

# 遮挡伤害、局部绕障和双向扇射
& $godot --headless --path . --script res://scripts/enemies/combat_audit.gd

# 完整单人流程回归
& $godot --headless --path . -- --beta-test
```

通过标准：进程正常结束、对应脚本输出 PASS / 零失败结果，且没有 `SCRIPT ERROR`、断言失败或超时。Godot 的单一进程退出码不能代替日志检查。带 Autoload 依赖的 UI 应通过工程导入或真实实例化检查；单独 `--check-only --script` 可能没有项目正常启动时的 Singleton 上下文。

`--beta-test` 会使用独立的 `user://test_settings.cfg`；测试模式不写入普通玩家战绩。不要把自动化测试的无敌、冻结或直接调用清波入口带入对玩家提供的启动命令。

### 现有烟雾场景

这些入口由 `scripts/dev/dev_scenarios.gd` 提供，适合定位故障：

```powershell
& $godot --headless --path . -- --smoke
& $godot --headless --path . -- --smokeidle
& $godot --headless --path . -- --smokeboss
& $godot --headless --path . -- --smoketest
```

| 参数 | 场景用途 |
| --- | --- |
| `--smoke` | 自动瞄准 / 射击和选择升级，观察波次与状态 |
| `--smokeidle` | 站桩承伤，检查敌人接近、攻击、玩家死亡 |
| `--smokeboss` | 第五波 Boss、半血阶段与狂暴 |
| `--smoketest` | 解锁武器 / 技能并应用多类升级，检查开火、近战、技能与效果 |

## 画面验收

截图需要正常渲染窗口，不能用无界面结构检查代替：

```powershell
& $godot --path . -- --gallery
& $godot --path . -- --autoshot
```

`tests/gallery.gd` 输出到 `dev_shots/`：`beta_title.png`、`settings_0..3.png`、`multiplayer_direct.png`、`multiplayer_relay.png`、`night_courtyard.png`、`weapon_*.png`、`victory.png`。旧的自动截图入口额外覆盖战斗、升级、Boss 与失败页。

人工逐张检查文字是否裁切、面板是否重叠、当前聚焦状态是否可见；逐把确认武器不遮住准星，机瞄 / 装填没有明显穿手。至少在 1280×720、1600×900、1920×1080、窗口与全屏、三档画质下查看。检查夜院的敌人轮廓、自爆蓄力与弹丸是否可辨，关闭晃动 / 闪烁 / 伤害数字后是否即时生效。

## 网络传输审计

传输测试会创建独立 `NetworkSession`，不运行完整战斗。先启动房主，再在其他终端启动客户端；连接等待上限为 15 秒。选择空闲测试端口，避免与正常房间冲突。

直连双进程，两个终端分别执行：

```powershell
# 终端 A：房主
& $godot --headless --path . --script res://scripts/network/transport_audit.gd -- --role=host --transport=direct --port=17779
```

```powershell
# 终端 B：客户端
& $godot --headless --path . --script res://scripts/network/transport_audit.gd -- --role=client --transport=direct --port=17779
```

四人测试给房主增加 `--clients=3`，并启动三个客户端实例；需等四人同时进入、就绪并完成定向 ACK，不能用三次先后进出代替四人并发：

```powershell
& $godot --headless --path . --script res://scripts/network/transport_audit.gd -- --role=host --transport=direct --port=17779 --clients=3
```

中转测试先运行服务器：

```powershell
.\dist\server\ink-tide-relay-windows-amd64.exe -addr 127.0.0.1:17778
```

然后另开房主与客户端终端：

```powershell
& $godot --headless --path . --script res://scripts/network/transport_audit.gd -- --role=host --transport=relay --port=17778 --room=AUDIT42 --clients=3
```

```powershell
# 运行三个客户端实例；双人测试时房主去掉 --clients=3 并只运行一个
& $godot --headless --path . --script res://scripts/network/transport_audit.gd -- --role=client --transport=relay --port=17778 --room=AUDIT42
```

审计脚本使用固定测试密码，不是公网服务的默认密码。预期各端出现 `[transport-audit] PASS`，四人房主输出 `concurrent players=4`。本轮日志位于 `dev_shots/network-four-direct-*` 与 `dev_shots/network-four-relay-*`。

## 多人真实场景回归

`tests/coop_integration.gd` 实例化真实主场景，使用两套独立 Godot 进程验证远端移动 / 换枪 / 射击、房主伤害与弹药判定、血同步、倒地、清波复活、逐人升级等待、第二波、重开与断线流程。测试失败时保留两端日志与当前波次 / 状态，不能只取其中一个 PASS 片段。

```powershell
# 终端 A
& $godot --headless --path . --script res://tests/coop_integration.gd -- --role=host --transport=direct --port=18777
```

```powershell
# 终端 B
& $godot --headless --path . --script res://tests/coop_integration.gd -- --role=client --transport=direct --port=18777
```

中转版先将服务监听在 `127.0.0.1:18778`，两端改用 `--transport=relay --port=18778 --room=COOPTEST`。应检查房主与客人均输出最终的 `PASS complete transport=...`。

## 中转服务测试与部署验收

```powershell
Push-Location server
 go test -count=1 -v ./...
 go vet ./...
 .\build.ps1
Pop-Location
```

源码要求 Go 1.24+，依赖锁定在 `server/go.mod` 与 `go.sum`。构建物为 `dist/server/ink-tide-relay-windows-amd64.exe` 和 `ink-tide-relay-linux-amd64`，附带使用说明、第三方声明与 `SHA256SUMS.txt`。完整部署见 [中转服务说明](../server/README.md)，客户端传输 API 见 [NETWORK_API.md](NETWORK_API.md)。

在实际部署目标上验收：启动服务、访问健康检查、从另一台电脑创建并加入房间、密码错误与房满提示、房主断线清房、服务重启后重新建房。直连验证 **UDP 7777** 可达；中转验证 **TCP 7778** 可达，不要混用协议。公网 WSS 还需验证真实证书与反向代理的 WebSocket 连接。

## Windows 客户端打包复核

```powershell
.\tools\build-client.ps1 -EnginePath "G:\Godot\Godot_v4.7.2-stable_win64.exe"
```

构建脚本要求相邻的 Godot `_console.exe`，用于资源导入、PCK 导出及退出码检查；输出 `dist/client-windows/` 和 `dist/InkTide-0.2.0-beta-Windows-x64.zip`。当前内测包配套编辑器引擎二进制作为运行时，不是正式 release template 的精简 EXE。

从工程目录之外启动客户端，确认资源来自随包 PCK；然后从完整解压的 ZIP 运行标题、开局、设置与联机入口。EXE 和 PCK 必须同目录，避免误用开发工程缓存掩盖漏包。每次最终代码变化后重新打包，重新检查资源加载与启动。Linux 中转程序与 Windows 游戏客户端是不同交付物，当前没有声称已经提供 Linux 游戏客户端。

## 人工试玩清单

每轮记录地图、难度、单人 / 多人数、连接方式、硬件与分辨率。建议先在「初入墨境」熟悉操作，再在标准难度连续完成多局。

| 阶段 | 需要确认 |
| --- | --- |
| 首次进入 | 看得懂目标与控制；E 可立即使用；不会因没有第二把武器而错过升级节奏 |
| 战斗 | 墨鬼 / 纸傀 / 墨甲 / 咒面 / 灯鬼轮廓可区分；攻击蓄力可辨；墙体有效遮挡；绕井与碑时敌人持续可达 |
| 资源 | 装填 / 切枪反馈明确；弹匣与备弹不负数；波间回血、补弹与技能重置符合难度；掉落可正常拾取 |
| 成长 | 三卡不重复；已拥有 / 已达上限卡正确过滤；新枪即时装备；弃牌回血有效 |
| 第 5 / 10 波 | 墨将出现、左右扇射、召唤与狂暴可观察；击败 Boss 后仍须清空其余敌人 |
| 结算 | 十波进入胜利；可续写第十一波；死亡不重复结算；返回标题与重开恢复控制 / 鼠标状态 |
| 设置 | 画面 / 声音 / 操作 / 舒适全部可调；静音有效；键位冲突拒绝；取消重绑有效；重启后偏好保留 |
| 多人房间 | 名单与昵称一致；未就绪阻止房主开始；房满、错误密码、超时、离开后重建有明确结果 |
| 多人对局 | 队友位置 / 持枪 / 血同步；攻击由房主判定；单人倒地不结束全队；清波复活；每人独立选卡并等待全员 |
| 多人退出 | 打开菜单时世界继续；客人退出不阻塞升级；房主退出明确断连，无自动房主迁移 |
| 长局 / 性能 | 连续多局与无尽模式的帧耗、节点 / 内存、敌群可达性、消息量与输入延迟无持续恶化 |

真实跨网至少覆盖两种不同网络、两人和四人、直连与中转、较高延迟 / 短暂断网。当前没有匹配服务、自动端口穿透、自动重连、服务器游戏托管、完善的反作弊或命中回滚；失败后按提示返回标题重新连接。

## 反馈格式

```text
版本 / 日期：
地图 / 难度 / 征途：
单人或人数 / 直连或中转：
系统 / CPU / GPU / 分辨率 / 画质：
触发前波次与武器 / 技能：
复现步骤：
预期结果：
实际结果：
是否每次复现 / 大约频率：
日志与画面文件名：
网络问题补充：房主或客人、局域网或跨网、估计延迟、两端现象。
```

避免在反馈中包含房间密码、私钥或不必要的个人信息。把可复现步骤与对应日志放在一起，优先处理崩溃、卡死、无法清波、输入丢失、联机状态分歧和存档损坏，再评估数值与美术细节。
