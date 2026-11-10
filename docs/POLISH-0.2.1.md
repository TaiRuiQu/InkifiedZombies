# v0.2.1 打磨与验收记录

本轮针对试玩反馈修复界面、命中判定和生命周期问题，并补充更清晰的低多边形面部、打击反馈、受击方向与原创配乐。以下记录区分实际验证范围和仍需真实试玩的部分。

## 下拉弹窗与地图预览

原下拉按钮只设置了关闭状态的样式；`OptionButton` 内部的 `PopupMenu` 是独立窗口，仍使用默认灰色菜单。新增 `InkOptionButton`，将纸纹面板、墨字、悬停笔触和朱砂选中图标直接应用于弹窗，同时保留键盘导航。标题和设置统一使用该控件。

标题选择地图后，预览会重建对应的真实场景，更新井、碑、石柱等布局以及日月灯光、雾色、标题与说明。快速连续选择只采用最终请求；开局沿用已经展示的地图。

## Lambda 与场景生命周期

原 `VFX._free_after()` 的定时器闭包捕获了待回收的 Node。墙面墨迹被提前逐出或整个场景先释放时，Godot 在进入闭包前就会报告 `Lambda capture ... was freed`，闭包内部的有效性检查来不及执行。

回收改为静态命名回调，并绑定 `WeakRef`；到期时取出仍存活的对象再回收。快速菜单切换还暴露了延迟 `grab_focus` 在控件离树后执行的问题，现统一通过安全的弱引用焦点回调，检查控件、场景树和可见性。UI 的延迟操作不再依赖捕获控件的匿名闭包。

## 可见模型与命中判定

原先用于移动的胶囊同时承担伤害检测；部分可见头部高于胶囊，肩臂也超出胶囊范围，导致准星落在模型上却没有伤害。现在移动胶囊继续负责角色移动，独立 `EnemyHitbox` 区域负责头、躯干和活动肢体的伤害检测，并随模型关节运动。

射线查询统一包含世界遮挡和受击区域，解析区域所属敌人及命中部位。子弹命中一个敌人后排除其全部受击区域，避免穿透在同一敌人上重复扣血。出现动画期间的模型也能受击；死亡后关闭受击区域。

射击先取得相机瞄准点，再从经过遮挡修正的枪口进行实际射线检测；曳光使用这条路径的真实起点与终点。枪口被薄墙遮挡时会停止在墙面，镜头看得见目标不代表枪管能够穿过掩体。霰弹与连续射击保留武器散布，准星不是自动命中保证。

## 面部与战斗表现

六类敌人的头部加入手工分面的面部拓扑，用实际几何塑造眉骨、眼眶、鼻梁、颧骨、嘴唇、下颌和牙齿，不同类型调整脸宽、下颌、眼形和表情。保留 low-poly 风格，并控制面部描边，减少细节被粗线遮住的情况。

射击强化枪械后坐、机械动作、枪口与抛壳反馈；命中反馈区分普通命中、会心、爆头和斩杀，短时间的多弹丸命中合并显示。敌人增加受击反应。受击 HUD 保存攻击来源的世界坐标，按当前视角计算前后左右方向，支持多个来源并区分生命与护盾；关闭镜头晃动、闪烁时仍保留方向信息。联机的伤害确认、斩杀和受击来源由房主结果传给对应玩家。

## 音效与音乐

音频改为离线生成的原创 PCM 资产：120 个文件、58 个兼容事件，包含六枪各三个变体、肉体与护甲命中、爆头与击杀、生命与护盾受击、装填三阶段、石地与纸面脚步、弹壳、敌人空间声和重制技能音效。没有使用下载的采样、真人语音或第三方歌曲。

配乐为 80 BPM、16 小节的 48 秒原创乐段，五条音乐 stem 共用时间轴，另有独立环境声。菜单使用疏朗拨弦与和声；战斗随波次提高鼓层，Boss 加入弦乐动机、战鼓和金属敲击。状态改变通过交叉淡化编曲，暂停和场景重载不重启曲子。音乐总线独立调节，枪声暂时压低音乐，主总线限制叠加峰值。

生成与波形审计：`tools/generate_audio.py`；十秒混音试听：`assets/audio/previews/battle_mix.wav`。音频说明见 [assets/audio/README.md](../assets/audio/README.md)。

## 已完成的同版验证

| 项目 | 结果与范围 |
| --- | --- |
| 下拉控件 | `ui_polish_audit.gd` 零失败，检查真实弹窗主题、选中状态和地图选择信号 |
| 敌人受击区域 | `enemy_hitbox_audit.gd` 144 项通过，覆盖六类敌人的头 / 身体 / 肢体、出现、墙体遮挡、穿透与死亡 |
| 实际开火 | `shot_registration_audit.gd` 182 项、零失败；覆盖面部不同瞄点、身体与手臂、出现阶段、扳机路径、曳光与实际弹着点及未命中 |
| 受击方向 | `damage_direction_audit.gd` 17 项、零失败；包括转身后的方向、来源合并、到期、护盾与生命、关闭晃动 / 闪烁后的 HUD |
| 界面操作 | `interaction_audit.gd` 55 项、零引擎错误；包括地图真实灯光 / 雾色预览、快速选择、重绑定 / ESC / 保存、音乐独立静音、FOV 与画质即时应用、暂停返回、弃牌防双击、死亡重开 |
| 生命周期 | `lifetime_regression.gd` 实际等待原始 28 秒墨迹定时器；96 个短租期节点、24 个真实墨迹及五个旧场景共 126 个弱引用全部释放，五轮主场景快切 / 重载，零引擎错误 |
| 音频 | Python 检查 120 个 PCM 文件无削波或静音文件；六条 48 秒立体声循环首尾样本差为 0；Godot 音频审计通过变体、空间路由、编曲、压低音乐、峰值保护和独立音量 |
| 菜单完整操作 | `menu_interaction_audit.gd` 29 项通过，覆盖菜单选择、键盘操作、升级和联机就绪 / 开始 / 离开等生产交互 |
| 玩家动作与反馈 | `player_action_audit.gd` 61 项通过，覆盖真实蹲伏净空、起跳 / 落地、六枪后坐、近战延迟、护盾 / 生命受击、视角跟踪、舒适设置、装填三阶段与弹药、24 枚弹壳弹跳和清理 |
| 十波完整流程 | 同版 `--beta-test` 零失败，逐波确认场上清空，覆盖两次 Boss、升级、通关、继续无尽第 11 波及死亡结算；本次随机波次共击杀 126 个敌人，总量不作为固定通过条件 |
| 直连与中转合作战斗 | 同版直连和真实 Go 中转均以两个 Godot 进程通过开局、战斗、升级、复活、重开和结算，并验证远端 `combat_confirm` 与 `damage_direction` 来源世界坐标 |
| 最终客户端包 | v0.2.1 最终 ZIP 为 111,192,385 字节；从无工程的 TEMP 目录分别运行正常渲染和无界面成品，两次验证退出码均为 0，日志无 ERROR / WARNING |

同版直连、Go 中转、玩家动作、菜单操作和十波流程均已完成上述回归。此前直连 / 中转四人同时传输的验证记录继续保留；四人真实公网长局仍属于后续试玩范围。

关键日志位于 `dev_shots/`：`enemy-hitbox-audit.log`、`shot-registration-audit.log`、`damage_direction_audit.log`、`interaction-audit.log`、`lifetime-regression.log`、`audio-audit.log`、`menu_interaction_audit.log`、`player-action-audit.log`、`beta-polish.log`、`coop-{direct,relay}-{host,client}.log`、`client-0.2.1-rendered.log`、`client-runtime-build-check.log`。生命周期和界面审计通过 Godot `Logger` 捕获实际引擎错误；进程退出码之外还检查错误记录。

## 复现与交付

```powershell
$godot = "G:\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --editor --quit
& $godot --headless --path . --script res://tests/enemy_hitbox_audit.gd
& $godot --headless --path . --script res://tests/shot_registration_audit.gd
& $godot --headless --path . --script res://tests/damage_direction_audit.gd
& $godot --headless --path . --script res://tests/interaction_audit.gd
& $godot --headless --path . --script res://tests/lifetime_regression.gd
& $godot --headless --path . --script res://tests/audio_audit.gd
& $godot --headless --path . --script res://tests/menu_interaction_audit.gd
& $godot --headless --path . --script res://tests/player_action_audit.gd
& $godot --headless --path . -- --beta-test
python tools/generate_audio.py --audit-only
```

`lifetime_regression.gd` 约需 29 秒，等待真实定时器而非提前结束测试。场景审计使用独立测试设置文件，关闭正常战绩写入。正常渲染画面的检查使用 `tests/polish_gallery.gd`，不能以无界面检查代替画面验收。

Windows x64 客户端打包路径为 `dist/InkTide-0.2.1-beta-Windows-x64.zip`；完整解压后运行 `InkTide.exe`，无需安装 Godot。当前仍采用随附引擎运行时与 PCK 的方案，未改为精简 release template。中转服务继续使用 v0.2 二进制与部署方式，位于 `dist/server/`，默认 TCP 7778，详见 [部署说明](../server/README.md)。

本轮本机回归不能替代真实公网高延迟 / 丢包、四人长期实战、所有 NAT 条件、Linux 服务器实机及目标低配硬件性能验收。当前仍无房主迁移或自动重连，人工平衡和视听体验需继续结合试玩调整。
