# v0.2 工程结构与内容扩展

本文对应当前内测实现。目标是把流程、规则、内容数据、表现和网络边界分开，让新增内容有明确入口；现有 `Player` 和 `Coop` 仍包含较多协调逻辑，后续可继续拆分，不能把当前结构视作已经完成全部架构演进。

## 生命周期与职责

| 模块 | 职责 |
| --- | --- |
| `scripts/main.gd` | 构建场景、标题 / 设置 / 联机入口、开局、清波、升级、胜负、暂停与重开 |
| `core/game.gd`，Autoload `Game` | 会话选项、运行状态、战绩计数、版本化本地档案 |
| `core/settings.gd`，Autoload `Settings` | 偏好校验、显示 / 音量应用、输入映射与原子保存 |
| `core/sfx.gd`，Autoload `Sfx` | 程序化音效池；音效 `Ink` 与环境 `Ambient` 分总线 |
| `core/run_rules.gd` | 十波目标、三种难度、波次预算与生成节奏 |
| `core/upgrades.gd` | 升级卡池、前置与叠加限制、加权抽取 |
| `waves/wave_director.gd` | 消耗预算、从注册敌人池抽取、控制场上数量与清波判定 |
| `player/player.gd` | 移动、武器状态、命中与伤害、技能入口、升级应用、补给 |
| `combat/combat_query.gd` | 共用视线与范围伤害策略，实体世界阻挡伤害 |
| `combat/projectile.gd` | 友方 / 敌方弹丸的移动、碰撞与爆炸 |
| `enemies/enemy.gd` | 敌人碰撞、状态、攻击、生命与掉落 |
| `enemies/enemy_steering.gd` | 局部避障、群体分离查询节流、绕障方向记忆 |
| `enemies/enemy_visual.gd` | 六类模型、关节与表现；按关节 / 材质合并并缓存网格 |
| `player/weapon_view.gd` | 枪械切换、机瞄、摆动、后坐与装填表现 |
| `player/weapon_model.gd` / `weapon_details.gd` | 武器主体、机械细节、手部与可动部件 |
| `world/map_builder.gd` / `map_details.gd` | 数据选图、主体环境与碰撞；独立批处理装饰层 |
| `skills/` 与 `data/skills/` | 技能注册、资源参数和独立效果脚本 |
| `ui/` | 纸墨主题、HUD、菜单、升级、设置与房间界面 |
| `network/network_session.gd`，Autoload `NET` | 直连 / 中转、身份、房间成员、就绪、消息路由与连接错误 |
| `network/coop_session.gd`，Autoload `Coop` | 房主战斗判定、玩家代理、状态快照、升级同步与清波复活 |
| `network/remote_player.gd` | 队友外观、姓名 / 血量、插值与动作表现 |
| `dev/dev_scenarios.gd` | 自动截图与烟雾场景，避免挤在正常流程脚本中 |
| `server/` | 独立 Go WebSocket 中转；无需 Godot 和数据库 |
| `tools/build-client.ps1` | 资源导入、PCK 导出、Windows 引擎运行时与许可文件整理、试玩 ZIP 打包 |

单人流程为：标题 → 战斗 → 清波补给 → 升级 → 下一波。默认肃清第十波转为胜利，可续写无尽；死亡进入结算。设置覆盖在标题或暂停菜单上，关闭后回到来源菜单。地图与难度选项不随本局统计重置而清空。

## 注册时机

在构建地图、实例化玩家和启动 `WaveDirector` 之前注册新增内容。内置地图由 `MapDB` 初始化，内置枪械 / 敌人为默认字典，内置技能从 `data/skills/*.tres` 读取。注册接口接受资源，但**并非自动扫描任意目录**；新建 `.tres` 后仍要明确加载并注册。

资源 ID 应稳定、非空、在各客户端保持一致。注册同一 ID 会覆盖对应内容，适合显式调参；避免无意覆盖内置 ID。联机各端应使用相同版本的代码和内容，当前未提供资源下载或内容协商。

## 扩展地图

`MapDefinition` 是可保存为 `.tres` 的 Resource，包含 ID、显示名、描述、随机种子、出生点、碑 / 井 / 石柱位置、天空 / 光照 / 雾 / 地面色和夜景 / 竹林选项。

```gdscript
var definition: MapDefinition = load("res://data/maps/my_courtyard.tres")
MapDB.register_map(definition)

var arena := MapBuilder.new()
add_child(arena)
arena.configure(definition.id)
arena.build()
```

查询入口为 `MapDB.ids()` 和 `MapDB.get_map(id)`。`MapBuilder` 输出 `player_spawn` 与八个 `spawn_positions`，供玩家与波次导演使用。地标位置同时影响模型与主体碰撞；`MapDetails` 的瓦片、格栅、碎叶等小细节不额外增加碰撞体。

现有资源表达的是同类庭院的布局与环境变化。若新增洞穴、楼层或复杂通路，需要新增对应建图能力与导航方案；局部绕障不能代替任意复杂地图的完整寻路。标题地图列表从 `MapDB` 动态读取；在 UI 构建前注册，即可显示新地图选项。

## 扩展敌人

创建 `EnemyDefinition` 资源，设置生命、移速、攻击范围 / 冷却、碰撞尺寸、预算成本、最早波次、抽取权重、行为与外观 ID：

```gdscript
var definition: EnemyDefinition = load("res://data/enemies/my_enemy.tres")
assert(EnemyDB.register_definition(definition))
```

也可使用 `EnemyDB.register_type(id, values)` 注册字典。普通敌人必须具有正预算成本，主要物理 / 战斗参数必须为正数；`EnemyDB.unlocked_for_wave(wave)` 根据 `min_wave` 筛选，导演读取 `spawn_weight` 与 `cost`，不用为每种普通敌人增加抽取分支。

`visual_id` 可复用内置 `wraith`、`puppet`、`brute`、`mask`、`lantern`、`boss`。自定义外观可通过 `EnemyVisual.register_builder(id, callable)` 接入；构造回调接收视觉工厂、主色、强调色与发光色。静态细节按所属关节与材质合并，动画关节继续独立运动。

特殊 AI 使用 `behavior_script`：脚本继承 `RefCounted`，实现 `update(enemy, direction, distance, delta)`，可选实现 `perform_attack(enemy, attack_kind)`。自定义策略需负责相应移动 / 攻击逻辑，并沿用现有冷却、蓄力、死亡与遮挡约定。新 Boss 的波次安排仍需在导演中明确配置，注册 `is_boss` 不会自动替换现有墨将。

## 扩展枪械

`WeaponDefinition` 包含 `id`、`display_name`、`model_id`、可选 `view_scene` 与数值字典 `values`：

```gdscript
var definition: WeaponDefinition = load("res://data/weapons/my_weapon.tres")
assert(WeaponDB.register_definition(definition))
```

`WeaponDB.register_weapon(id, values)` 会继承初始手枪默认项并合并自定义字段。主要字段见 `weapon_db.gd`：伤害、RPM、自动开火、弹丸数、散布、机瞄散布、弹匣 / 备弹、装填、射程、穿透、后坐、衰减、声音与持枪位置。返回的数据副本可供本局计算使用，不应通过修改副本来改全局定义。

表现可以复用 `model_id`，或调用 `WeaponModel.register_visual(id, callable)` 注册接收 `model` 的构造回调。自定义 `view_scene` 根节点应为 `Node3D`，提供名为 `Muzzle` 的枪口节点；第一人称可见网格使用 Viewmodel 渲染层。可选实现 `notify_fire()` 等表现接口，避免在模型中写伤害逻辑。

注册武器不等于自动发放。通过 `player.unlock_weapon(id)` 授予，或往 `UpgradeDB.LIST` 加入带 `weapon` 前置标记与 `effects: {"weapon": id}` 的解锁卡。当前数字槽位为六个，额外持有武器仍需检查 Tab / 滚轮与 HUD 的实际使用体验。

## 扩展技能

每个技能由 `SkillDefinition .tres` 与效果脚本组成。资源包含 `id`、名称 / 图标、`input_action`、基础冷却、冷却修正字段、是否初始解锁与 `effect` Script。

```gdscript
var definition: SkillDefinition = load("res://data/skills/my_skill.tres")
assert(SkillDB.register(definition))
```

效果脚本示例：

```gdscript
extends RefCounted

static func cast(player: Node3D) -> void:
    CombatQuery.radial_damage(
        player, player.global_position + Vector3.UP,
        5.0, 30.0, 4.0
    )
```

`SkillDB.register` 校验非空 ID、正冷却、存在的输入动作和具有 `cast` 的效果脚本。`SkillDB.cast` 统一检查死亡、解锁与冷却。新增专用动作需加入 `project.godot` 的 InputMap，若允许玩家重绑，也要加入 `Settings.ACTIONS`；HUD 技能槽从注册表读取。

通过 `effects: {"unlock": id}` 升级卡解锁技能，或设置 `starts_unlocked`。新数值修正项须进入玩家的 `mods` 默认值 / 升级规则，不能只在资源里写一个未消费的字段。多人技能需验证本地反馈与房主判定，避免依赖房主电脑的本地输入来推导远端动作。

## 设置与持久化

读取使用 `Settings.get_value(key)`，修改使用 `set_value(key, value)`，订阅 `changed(key, value)`。显示与音频由服务直接应用；玩家、HUD 和 VFX 读取灵敏度、视野、晃动、闪烁、伤害数字等偏好。地图建立后调用 `Settings.apply_scene(root)`，将画质同步到场景灯光与环境。

按键使用物理键码或鼠标键，加载时先构造完整候选映射，再检查重复；冲突存档不会按部分错误映射启动。Alt / 系统键组合保留给操作系统。设置保存先写 `settings.cfg.tmp` 再覆盖正式文件，存档失败有可见反馈。战绩由 `Game` 独立管理，不和偏好设置混写。

## 多人数据边界

`NET` 对上层统一暴露房间与消息接口：`host_direct(port, name)`、`join_direct(address, port, name)`、`host_relay(address, room, password, name)`、`join_relay(...)`、`set_ready`、`send`、`leave`。创建成功 / 连接成功、失败、成员变化通过信号通知界面。房主 ID 固定为 1，最多四人。

`Coop` 由房主处理敌人、命中、生命、掉落、技能与升级；客户端提交动作请求，房主检查武器拥有情况、弹药、装填、射速、技能解锁 / 冷却等。移动采用客户端本地操作、定期姿态上报与房主位置范围 / 速度 / 视线校验，再以快照校正；没有完整回滚或命中延迟补偿。

当前快照间隔 0.1 秒，客户端姿态上报间隔 0.05 秒。数据为可靠 JSON 消息；`RemotePlayer`、敌人 / 弹丸 / 拾取物代理负责客户端表现。升级卡由房主抽取并逐人下发，只接受该玩家实际获选卡的 ID，全员提交后继续。

中转服务只维护房间、成员身份与路由。客人只能发给房主，房主可广播或定向发送；服务写入真实发送者身份，并限制房间容量和消息尺寸。中转不是独立游戏服务器，没有账号、匹配、战绩数据库或房主迁移。部署、协议与构建见 [server/README.md](../server/README.md)。

## 客户端交付

`tools/build-client.ps1` 根据 `export_presets.cfg` 的 `Windows Runtime Pack` 导出 PCK，并配套当前本机 Godot 4.7.2 Windows 引擎二进制、启动脚本与许可。输出 `dist/client-windows/` 和 `dist/InkTide-0.2.0-beta-Windows-x64.zip`。当前使用编辑器引擎二进制充当运行时，正常执行直接进入游戏；尚未采用正式 release export template，后续可替换以缩小包体。

只复制 EXE 不足以运行游戏，须同时携带同名 `InkTide.pck`。客户端包与 `dist/server/` 中转程序分别构建；中转的 Go 交叉构建不等于 Linux 游戏客户端交付。

## 验证入口与后续拆分

内容 / 物理回归、传输审计、Go 服务测试与人工试玩命令见 [PLAYTEST.md](PLAYTEST.md)。新增内容至少验证注册、创建、碰撞 / 枪口、动画、伤害与联机状态。不要用无界面结构测试替代渲染验收与真实跨网压力测试。

后续优先项是从 `Player` 进一步拆出伤害与枪械运行组件、把网络快照模式版本化、记录每局帧耗与网络量，并在新地图几何变复杂时引入合适的全局导航。扩展时沿现有边界推进，避免把新模型、UI 和规则重新塞回 `main.gd`。
