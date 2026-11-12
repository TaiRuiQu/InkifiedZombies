# 墨潮 Web 导出与 Paper Agent 接入记录

检查日期：2026-11-11。游戏版本：0.2.3；本机引擎：`4.7.2.stable.official.ed1daf0bf`。

## 2026-11-11 第二批：Paper 账号联机与自包含运行

Paper 页面现在区分两种体验，且不引入任何运行时外部依赖：

- **未登录玩家**：游戏入口、引擎与资源全部来自 Center 同源的 `dist/web/`（单目录、文件名带内容指纹），不请求外部 CDN、外站 WASM 或字体。标题、设置、单人试玩、结算与刷新恢复照常可用，联机按钮会提示先登录。
- **已登录玩家**：`bootstrap.js` 读取同源 `/api/auth/session`，玩家点击创建/加入房间时才 `POST /api/ink-tide/ticket` 取票；GDScript 通过 `Browser.request_ticket()` 异步取得票据，`NET.host_relay/join_relay` 把票据放进握手首帧。
- **中转校验**：relay 用 `INK_TIDE_TICKET_SECRET`（与 Center 相同的 64 位十六进制）验证 HMAC、版本与过期时间（300 秒），票据昵称覆盖客户端自报昵称。浏览器连接带 `Origin`，Paper 部署以 `-require-login=browser` 强制校验；桌面原生客户端不带 `Origin`，保留原有中转玩法。`-require-login=all` 可对全部客户端强制。
- **未配置密钥时**：`/api/ink-tide/ticket` 返回 `ink_tide_auth_unavailable`，界面提示「联机登录校验尚未配置」，单人试玩不受影响。

新增或修改的文件：`web/bootstrap.js`（账号/票据桥）、`scripts/core/browser_platform.gd`（账号状态与票据信号）、`scripts/network/network_session.gd`（票据转发与错误文案）、`scripts/ui/multiplayer_screen.gd`（登录状态行、创建/加入前取票）、`scripts/ui/title_screen.gd`（标题提示）、`server/ticket.go`、`server/relay.go`、`server/main.go` 与对应 Go 测试。Paper 侧新增 `packages/center/server/game-ticket.ts`、`POST /api/ink-tide/ticket`、`deploy/paper-ink-tide-relay.service` 的环境文件与 `-require-login` 参数。

验证方式：Go 单元测试覆盖票据签名/过期/篡改、浏览器强制登录、桌面保留中转与 `all` 严格模式；Center 集成测试覆盖未登录 401、票据字段与签名、退出登录后不可再签；Godot 的 `web_compatibility_audit` 断言原生构建不请求票据。生产部署与验收记录见本文件末尾的部署小节。

### 生产部署记录（2026-11-11）

生产服务器 `43.133.63.169` 原先运行 `cnb-20261111T020538Z-a1bf825b6e78` 版本，且没有墨潮路由与中转进程。本次按 CNB 相同的目录与 PM2 语义手工发布，第二轮改为单目录指纹资源：

| 项目 | 值 |
| --- | --- |
| 当前版本目录 | `/opt/paper-agent/releases/manual-20261111T043324Z-043324/repo`（`current` 已指向） |
| 上一版本（回滚） | `/opt/paper-agent/releases/manual-20261111T042453Z-042453/repo` |
| 更早的 CNB 版本 | `/opt/paper-agent/releases/cnb-20261111T020538Z-a1bf825b6e78-YUmDs7/repo`（内容未被改动） |
| 游戏构建指纹 | `eb179c957a5f`，文件如 `app.eb179c957a5f.wasm`、`shell.eb179c957a5f.css`；`dist/web/` 内不再有 `builds/` 或 `active.json` |
| 中转程序 | `/opt/ink-tide-relay/0.2.3/ink-tide-relay-linux-amd64`，`current` 指向该目录 |
| 中转配置 | `/etc/paper-ink-tide-relay/relay.env`（600，仅 `INK_TIDE_TICKET_SECRET`），unit 已 `enable` 并带 `-require-login=browser` |
| Center 配置 | `/var/lib/paper-agent/env/center.env` 追加同一个 `INK_TIDE_TICKET_SECRET` |
| Caddy | `/root/.hydro/Caddyfile` 的 `(paper_ai_routes)` 片段新增 `@ink_tide_relay`，两个域名共用；改前备份 `Caddyfile.before-ink-tide-<时间>`，`caddy validate` 后热加载 |

资源与缓存：`index.html` 返回 `max-age=0, must-revalidate`；带指纹的 JS/CSS/PNG 与 `.wasm`/`.pck` 均为 `immutable`。Cloudflare 默认只缓存常见扩展名，因此引擎大文件的稳定 URL 用 308 指向同内容的 `.js` 别名（`app.<指纹>.wasm` → `app.<指纹>.wasm.js`，仍以 `application/wasm` 返回）。实测 `https://paperagent.work/games/ink-tide/app.eb179c957a5f.wasm.js` 与 `...pck.js` 第二次请求为 `cf-cache-status: HIT`，`.js`/`.css` 同样命中；重定向本身带 immutable，浏览器会缓存，不再重复请求。

验收结果：`/games/ink-tide/health` 返回 `ready=true` 与构建指纹；入口 200 且不缓存 HTML；WASM 308 → 别名 200 `application/wasm`；`build.json` 与缺失资源 404；匿名 `POST /api/ink-tide/ticket` 返回 401 `login_required`；经 Caddy 的 `/games/ink-tide/ws` 升级返回 101，原始 WebSocket 握手在带 `Origin` 且无票据时收到 `login_required`，带 Center 格式票据时进入房间且昵称取自票据（伪造昵称被忽略）。无头 Chrome 以未登录身份从公网进入游戏，`InkTideShell.getAccount()` 为 `guest`，点击后引擎进入 `ready`，控制台无错误，标题页截图确认「同守需先登录 Paper 账号」提示。`paperagent.work` 回源需要 Cloudflare 客户端证书，本机通过公网域名验证；源站另经 Host 头验证。

回滚（不急停中转）：

```sh
previous=/opt/paper-agent/releases/manual-20261111T042453Z-042453/repo
pm2 delete paper-v2-center paper-v2-chat paper-v2-ocr paper-v2-diff paper-v2-workbench
PAPER_RELEASE_ROOT="$previous" pm2 start /usr/local/lib/paper-cnb/pm2.config.cjs
ln -sfn "$previous" /opt/paper-agent/.current-tmp && mv -Tf /opt/paper-agent/.current-tmp /opt/paper-agent/current
node /usr/local/lib/paper-cnb/health.mjs && pm2 save
```

后续 CNB 发布若要保留墨潮，必须配置 `INK_TIDE_WEB_URL` 与 `INK_TIDE_WEB_SHA256`，否则发行包不含游戏静态文件，项目卡片会回到「即将开放」。运行时不从外部下载：游戏页面只引用同源目录下带内容指纹的 HTML、JS、WASM、PCK 与音频 worklet。

### 已实现的接入

- 新增 `Web Release` 单线程预设、自定义点击加载页面和 `tools/ci/build_web.py`。已安装官方 SHA-512 校验的 4.7.2 Web 模板，导出真实 WASM/PCK，并导入 `G:/paper-agent/packages/ink-tide/dist/web/`。
- 修复 Compatibility 的实例变量耗尽。静态世界采用普通 uniform；每个敌人在合批后创建自己的材质副本，同一敌人内部复用，受击不会串色。Forward+ 保留原有实例变量方式。
- Web 默认 60 FPS、80% 3D 渲染、无 FXAA/阴影/glow；高档使用 100%、2× MSAA 和有限阴影。加载页将画布限制为 1600×900、DPR 不高于 1，页面以 16:9 自适应显示。
- Web 重复静态部件按空间区域和网格/材质做 MultiMesh。残照庭院独立网格从 1179 降到 512，青岚夜院从 1667 降到 575；碰撞均保持 88 个。CPU 粒子减少，并对短期特效、墨迹和伤害数字设并发上限。
- 保留关键空间敌声，减少本地/世界音效声道；Web 不创建不受 Sample 播放支持的 AudioEffects，采用音量余量与现有遮挡衰减。回归发现同一敌人连续攻击声可能重叠，现改为复用它自己的攻击声道。
- 浏览器隐藏 ENet，默认使用当前页面同源 WS/WSS；显式 WSS 地址不再被错误追加 `:7778`。已添加指针锁丢失/后台暂停桥接、返回 Paper 操作和可选性能诊断。
- Paper 增加 `@paper/ink-tide` 路由包与 Center 项目卡片，复用 Center 端口，独立设置游戏 CSP。游戏放在单个 `dist/web/` 目录，文件名带内容指纹，入口 HTML 每次校验，指纹资源长期 immutable；大文件的稳定 URL 用 308 指向 `.js` 别名以命中 Cloudflare 默认缓存；缺失资源返回 404。
- 新增校验后原子导入脚本，CNB 可用固定 URL+SHA-256 将 Web ZIP 纳入原发行包。游戏 Release 工作流新增 Web 附件，Paper 提供单独 relay systemd 服务文件。

重新构建与导入：

```powershell
python tools/ci/build_web.py --godot G:/Godot/Godot_v4.7.2-stable_win64_console.exe --paper-root G:/paper-agent
```

Paper 的本机启动、生产附件配置、Caddy 与 relay 操作详见 `G:/paper-agent/packages/ink-tide/README.md`。本地地址为 `http://localhost:40000/games/ink-tide/`，需要 Center API 与 Vite 正常运行；多人另需 `127.0.0.1:7778` 的 relay。

### 已完成的验证范围

原生 Compatibility 的材质/网络 URL/静态合批回归有 56 项检查；Paper 已完成构建、类型检查、资源 HTTP/CSP/MIME/缓存/404 逻辑测试、Center 测试和归档安全测试。实际 Chrome WebGL 页面已从 Paper 路径加载并进入第一波、显示暂停菜单，浏览器控制台无错误。两份完整 Godot Web 客户端已通过同源 WebSocket 创建/加入房间、准备、开始战斗，两端诊断均记录到 relay、两名玩家、第一波及同步敌人，未出现控制台错误。

最终验证还包括：全部 Godot CI 检查与十波流程通过；原生双进程中转合作通过；Go relay 测试通过；Paper 共 149 项测试通过，另有导入/部署检查；浏览器设置刷新保留、第二张地图、指针解锁和恢复捕获正常。Caddy 标准配置及 EdgeOne 共享路由已解析，并在本地 Caddy 下验证游戏健康检查、WASM MIME/缓存与同源 WebSocket。EdgeOne 生产 TLS 所需的 Cloudflare CA 文件只存在于部署主机，本机未验证该证书配置。

上述浏览器验证为本机短时检查；同机并行运行浏览器和多套测试的帧率不能作为最低配置保证。尚未声称完成核显、移动触控、四人真实公网长局、20 分钟内存趋势或生产服务器上线验收。文件改动与 Web ZIP 当前留在本地，未推送或部署到线上。

## 首次评估（修改前）

### 1. 建议路线

保留 Godot 工程，以 Compatibility / WebGL 2 导出 WebAssembly，作为 Paper Agent 的独立游戏页面，入口建议为 `/games/ink-tide/`。Center 项目卡片打开游戏页面，点击后才下载引擎与资源。第一阶段做桌面浏览器单人版，第二阶段接现有 WebSocket 中转；账号云存档可以后续接入。

初版使用单线程、不启用 PWA。这样无需为了 SharedArrayBuffer 给主站增加 COOP/COEP。若后续测量表明需要线程，再增加独立的线程构建和部署策略。线程不会自动把 GDScript 游戏逻辑并行化。

当前最先要解决的是 shader 实例变量耗尽，其次才是导出配置、场景绘制成本和产品接入。单纯新增 Web 导出预设无法完成适配。

## 2. 已验证的阻塞与资源规模

### Compatibility 实际启动

原工程通过命令行覆盖为 `gl_compatibility`，进入标题，执行已有 `--verify-runtime`。机器使用 NVIDIA GeForce RTX 5060 Ti，日志显示 OpenGL 3.3 Compatibility。进程退出码为 0，但日志存在错误，不能视为通过：

- 916 条 shader 实例变量分配不足错误。
- 914 条分配失败后的重复实例记录错误。
- 1 条 screen-space AA 不支持警告，来源于现有 FXAA 设置。

错误发生在标题阶段，不需要等到敌人或大量战斗特效出现。原始日志在本地忽略目录 `.ci/web-audit/compatibility.log`。

`shaders/ink_surface.gdshader` 声明了 `instance uniform float hit_flash`；`Ink.surface()` 又把该 shader 用于大量静态建筑、植被和其他物体。它们即使从不闪白，也会占用实例变量空间。Godot 4.7 的 Compatibility 支持实例变量，但缓冲区受硬件限制，不能把此问题描述成“完全不支持 instance uniform”。

在单独诊断进程内，将该声明替换为普通 `uniform`，不修改磁盘 shader。再次加载标题后，上述两类错误消失，FXAA 警告仍在；标题渲染截图也已查看。证据为 `.ci/web-audit/compatibility-probe.log` 和 `.ci/web-audit/compatibility-probe.png`。这只验证了错误来源，未验证敌人受击闪白与完整对局。

建议正式修复：静态世界材质不声明实例变量；Web 敌人使用普通 `hit_flash` uniform，并在每个敌人内部缓存其专属材质副本，再更新这些材质。不能直接更新 `Ink` 全局共享材质，否则一个敌人受击会让其他物体一起闪白。仅给敌人保留 instance uniform 仍需核算每个敌人几十个网格带来的分配量；不应把增大缓冲区作为浏览器通用修复。

### 结构统计

统计使用本机 headless 实例构建场景，结果为对象数量，不是可见 draw call，也不是 Web 性能测试：

| 场景 | 独立 MeshInstance3D | 其中带 next_pass | MultiMesh 批次 | MultiMesh 内实例 | 灯光 | 碰撞形状 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 残照庭院 | 1179 | 844 | 58 | 2739 | 7 | 88 |
| 青岚夜院 | 1667 | 1044 | 61 | 2781 | 7 | 88 |

普通敌人单体有 20–37 个独立网格，墨将有 45 个；第一人称武器有 67–78 个独立网格。大量网格使用第二次描边绘制。实际绘制次数还取决于可见性、材质 surface、灯光与阴影等，应由运行时测量。

`map_details.gd` 已对部分装饰做 MultiMesh 合批，`Ink` 已缓存网格和材质，应在这些基础上扩展。敌人避让查询也已按约 0.14 秒错峰；当前同时存活上限是 20。初期应优先优化渲染、材质与特效，不必先重写 AI 或削减敌人数。

资源源文件：两份字体共约 22.54 MiB，146 个 WAV 共约 32.55 MiB。音频已有导入压缩配置；源文件大小不能当作最终 PCK 大小或传输大小。结构诊断完整日志在 `.ci/web-audit/structure.log`；该临时夹具退出时存在 ObjectDB 泄漏警告，未将其作为产品回归测试通过记录。

### 导出工具链现状

`export_presets.cfg` 只有 Windows Runtime Pack、Windows Release、Linux Release。本机 4.7.2 模板目录仅有 Windows debug/release 模板，没有 Web 模板。现有 `tools/ci/install_godot.py`、`build_client.py` 和发布工作流只处理原生客户端，需要单独扩展 Web 构建。

## 3. Web 导出配置

使用与工程相同的 Godot 4.7.2 Web release 模板，避免编辑器和模板版本不一致。新增预设建议：

| 配置 | 初版建议 |
| --- | --- |
| 名称 / 平台 | `Web Release` / `Web` |
| 输出 | `dist/web/index.html` |
| `variant/thread_support` | `false` |
| `variant/extensions_support` | `false`，当前没有 GDExtension |
| `progressive_web_app/enabled` | `false` |
| `html/custom_html_shell` | 自定义加载页，显示进度、失败原因、点击开始和返回 Paper |
| 资源过滤 | 继承原生排除项，同时排除本地诊断和其他构建产物 |

显式增加 `renderer/rendering_method.web="gl_compatibility"` 便于审阅，尽管 Godot 本身已有该平台默认值。桌面 Forward+ 可以保留。

画质要由 `Settings` 增加 Web 分支控制；仅写 `project.godot` 平台覆盖不够，`Settings.apply_all()` 会在启动时再次设置 MSAA、FXAA、缩放比例和帧率。

在预设和模板准备好后，执行：

```powershell
& 'G:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'G:\InkifiedZombies' --editor --import --quit
& 'G:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'G:\InkifiedZombies' --export-release 'Web Release' 'G:\InkifiedZombies\dist\web\index.html'
```

以上为实施后的命令，当前缺少预设与模板，尚不能直接成功执行。发布时保留所有生成文件及它们的对应名称，包括 HTML、JS、WASM、PCK 与音频相关脚本；不要导出后随意改名。必须通过 HTTP/HTTPS 提供页面，不能双击 HTML 运行。

## 4. 浏览器性能适配顺序

| 优先级 | 位置 | 建议 |
| --- | --- | --- |
| P0 | `ink_surface.gdshader`、`core/ink.gd`、`enemy_visual.gd`、`enemy.gd::_apply_flash` | 处理实例变量容量，验证受击反馈互不串色 |
| P0 | `core/settings.gd::_apply_quality` | Web 禁用 FXAA，默认 60 FPS；采用单独的 Web 画质配置 |
| P0 | `core/settings.gd::_apply_display`、`ui/settings_screen.gd` | 浏览器不调用窗口移动、独占全屏等桌面设置；改为渲染比例、画质与用户点击全屏 |
| P1 | `world/map_builder.gd`、`world/map_details.gd` | 合并相同材质的静态部件；重复植被按区域做 MultiMesh；远景关闭小物体描边 |
| P1 | `player/weapon_model.gd`、`weapon_details.gd` | 同一运动部件内合并静态细节，保留机匣、弹匣等需要独立动画的结构 |
| P1 | `shaders/ink_surface.gdshader`、`ink_wall.gdshader`、`ink_sky_dome.gdshader` | 增加轻量 shader，减少多层实时噪声；优先烘焙静态天空与纸纹 |
| P1 | `main.gd::_build_post`、`ink_post.gdshader` | 给全屏纸纹后处理增加独立开关或轻量版本；保留重要受击反馈 |
| P1 | `fx/vfx.gd`、`combat/projectile.gd` | 为粒子、墨迹和伤害数字设并发上限，复用对象；墨迹目前可存活 28 秒 |
| P2 | 字体、音频、`core/proc_tex.gd` | 字体裁剪；对确有必要的过程纹理做离线生成；实测压缩与预热效果 |

`VFX` 当前是创建节点后按生命周期回收，并非复用对象池。CPU 粒子不能在 Web 上简单改成 GPU 粒子就算优化完成，应优先控制粒子数量和同时存在的效果数。

建议初始配置为：3D 渲染比例 0.75、MSAA 关闭、FXAA 关闭、glow 关闭、阴影关闭或小范围 1024、减少环境粒子。中档可试 0.85–1.0、2× MSAA 和有限阴影。以上是起始参数，需测量后定版。

另需限制画布物理像素尺寸或 DPR。仅设置 0.75 倍 3D 分辨率不能约束全屏 Canvas 后处理成本；在 DPR=2 的高分屏上像素量可能增加到四倍。建议先以 1280×720 或 1600×900 的渲染预算验证，页面仍按容器尺寸显示，检查 UI 的实际可读性。

需要动态降档时，用稳定窗口采样帧耗时并设置升降档滞回，先调整分辨率和视觉效果。不要让网络各端因本地帧率不同而改变敌人数量、碰撞、伤害判定或物理步长。

## 5. 音频、输入与生命周期

- `Sfx` 已预载音效并使用 32 个本地声道、28 个空间声道和 10 个敌人提示声道；Web 应按实测减少并发，优先保留枪声、受击和敌人攻击提示。
- 默认 Web Sample 音频不支持 AudioEffects。当前低通、混响和硬限幅不能假定在浏览器中等效；可为 Sample 模式做静态音量余量、遮挡音量衰减或预处理音色。若必须保留完整混音效果，再对关键声道试 Stream，并测延迟与卡顿。
- 加载完成后展示“点击进入墨境”；音频恢复、全屏与鼠标捕获应由真实用户操作触发。网络回包和异步加载完成后的 `MOUSE_MODE_CAPTURED` 不能假定成功，应显示点击继续入口。
- `main.gd` 已处理应用失焦暂停，但还需要验证浏览器 Pointer Lock 丢失和页面隐藏。Esc 被浏览器用于释放指针时，游戏应进入可恢复状态；单人暂停，联机不要暂停整个队伍。
- 联机暂停菜单仍可让模拟继续，但浏览器标签页进入后台可能停止处理，浏览器房主会成为风险点。前台页面上的提示无法消除此限制；长局可先建议原生客户端当房主，后续再评估权威服务器。
- Web 的退出按钮应返回 Paper 页面，或退出引擎后显示返回入口。需要释放场景、声音和联机连接；不能只把 iframe/CSS 隐藏。
- 现有 `user://` 设置与战绩需要验证 IndexedDB 持久化、刷新恢复和存储不可用提示。两个 Paper 域名的浏览器存档相互独立；跨域名同步需要账号服务支持。
- 首版定位桌面键鼠。当前移动、瞄准和技能依赖键鼠，支持手机浏览器还需另做触控输入和界面适配。

## 6. Paper Agent 的具体接入点

已检查 `G:/paper-agent/AGENTS.md`、Center 项目列表、Vite 代理、Caddy 与 CNB 打包脚本。

| 文件 / 目录 | 所需改动 |
| --- | --- |
| `packages/center/server/app.ts` | `projects()` 添加 `ink-tide` 项目及 URL 映射，分类可为“游戏” |
| `packages/center/src/main.tsx` | 现有卡片已用新标签页打开 URL，可复用；需要新图标时补充图标映射 |
| `packages/ink-tide/`（建议新增） | 保存可追踪的加载页、同步脚本与游戏构建清单；二进制由构建阶段写入发行目录 |
| `packages/center/vite.config.ts` | 增加 `/games/ink-tide` 的本地静态服务代理；联机时增加相应 WS 代理 |
| `deploy/Caddyfile`、`deploy/Caddyfile.edgeone` | 增加独立静态路由和中转路由，使其不落入 Center SPA 兜底 |
| `deploy/cnb/build-release.sh` | 打包前拉取/复制固定版本 Web 构建；目前 `packages` 会被包含，目录内的 `artifacts` 会被排除 |
| `deploy/cnb/release.sh` 等实际发布入口 | 同步游戏静态目录；联机阶段管理 relay 生命周期、健康检查与回滚 |

建议保留游戏和 Paper 两个仓库：游戏 CI 输出固定版本 Web 附件，Paper 构建按版本与 SHA-256 获取，并记录来源提交。禁止把日常可变的 `latest` 直接作为可重现部署输入。游戏静态文件可由 Caddy 直接服务；单人阶段无需另加 Node 后端或数据库。

当前 Center 设置了 `Cache-Control: no-store`、严格 CSP 和 `X-Frame-Options: DENY`。直接将 Godot 默认 HTML 塞入 Center 现有静态处理链会遇到内联启动脚本与 WASM 策略问题。建议游戏子路径单独服务，配置该路径所需的 CSP；将启动逻辑外置或使用 hash/nonce，并按实际产物处理 `wasm-unsafe-eval`、音频脚本与 worker 策略，不放宽整个站点的 CSP。

下面是放入同一站点块的路由示意，路径和磁盘目录需按实际发布布局替换；尚未部署或通过本机 Caddy 校验：

```caddyfile
redir /games/ink-tide /games/ink-tide/ 308

@ink_relay path /games/ink-tide/ws
handle @ink_relay {
    rewrite * /ws
    reverse_proxy 127.0.0.1:7778
}

handle_path /games/ink-tide/* {
    root * /srv/paper-agent/games/ink-tide
    file_server
}
```

静态资源缺失应返回 404，不能兜底返回 Center HTML。验收 `.wasm` 的 `Content-Type: application/wasm`、PCK 的二进制响应以及压缩编码。现有 Caddy 有 zstd/gzip；需要在真实 CDN 路径核对压缩和缓存。

缓存建议使用“稳定入口 + 带版本/提交号目录”：入口 HTML 重新验证；版本目录中的二进制可长期 immutable 缓存。HTML、JS、PCK、WASM 必须同版本发布，并以原子切换支持回滚。先关闭 PWA，避免旧 service worker 造成混合版本或影响主站路径。

新增项目卡片只是入口，不等于访问控制。若后续要求登录后才能玩，需要实际保护游戏页/资源或房间 API；登录信息、服务密钥不能打进 PCK。初期本地游玩无需 OAuth 或 credits 接入。

## 7. 联机复用现有中转

`network_session.gd` 已把 ENet 与 `WebSocketPeer` 分开，Go relay 只转发协议数据，可沿用。Web 版隐藏并禁止 ENet 直连入口，默认中转地址由当前页面 host 推导：

```text
wss://当前页面域名/games/ink-tide/ws
```

本地 HTTP 开发使用同源 `ws://`。正式 HTTPS 页面不能继续默认连接 `ws://127.0.0.1:7778/ws`；该地址还会指向每个玩家自己的电脑。

relay 默认采用 Gorilla 同 host 的 Origin 校验。同域路径转发时保留公开 Host；不要随意改成上游内部 host。两个 Paper 域名分别使用各自同源 WSS 地址时，可以连接同一中转进程。如果改成独立 relay 域名，需显式支持两个前端 Origin，再验证原生客户端兼容性。

现有同步是房主每 0.1 秒广播快照、房客每 0.05 秒发输入，先沿用并统计每秒字节数、包大小、JSON 编解码耗时和队列积压；不要未经测量就提高频率。Web 版房主后台挂起、四人战斗和桌面/Web 混合组队是必要的验收项。

## 8. 分阶段交付与验收

1. **Compatibility 适配**：解决实例变量与 FXAA，增加 Web 画质/显示分支。两张地图、六把武器、八类敌人都要检查；敌人闪白互不影响，命中与预警正常。
2. **单人 Web 构建**：安装模板、新增 Web 预设与加载页，真实浏览器运行。验证开始、暂停、Esc、恢复捕获、设置保存、结算和刷新重开。
3. **Paper 入口与静态部署**：本地和两个生产域名路径一致，游戏资源按需下载；检查 MIME、缓存、CSP、404、CDN 压缩与回滚。
4. **性能优化**：同机同场景比较修改前后。至少覆盖两张地图、20 敌人、墨将、连续自动武器射击与技能爆发；分别记录冷启动和暖缓存。
5. **Web 中转联机**：同域 WSS、2–4 人和原生/Web 混合客户端；验证浏览器房主切后台、断线及返回标题行为。

建议先以桌面 720p 60 FPS 为优化目标，并提供低档 30 FPS 的可用体验；这些是验收目标，当前没有达标结论。记录浏览器/版本、GPU、DPR、分辨率、平均与 P95/P99 帧耗时、最长停顿、主线程任务、真实 draw call、引擎对象/内存和 10–20 分钟趋势。独显上流畅不能代替核显测试。

首次加载要拆分记录传输、WASM 编译、PCK 读取、场景构建和首帧 shader 编译。源码统计、headless 退出码与原生 Compatibility 成功都不能代替真实 WebGL 2 浏览器验收。

## 9. 官方资料

核对版本为 Godot 4.7。参考：

```text
https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html
https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformweb.html
https://docs.godotengine.org/en/4.7/tutorials/platform/web/customizing_html5_shell.html
https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html
https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html
https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html
https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/drivers/gles3/storage/material_storage.cpp
https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html
https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html
https://caddyserver.com/docs/caddyfile/directives/file_server
https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src
```
