# 自动检查与版本构建

GitHub Actions 使用 `.github/godot-version` 指定的 Godot 稳定版本，并校验官方发布的 SHA-512 清单。Git 仓库保存源码与游戏素材；`.godot/`、`dev_shots/`、`.ci/` 和 `dist/` 不提交。

## 日常检查

推送分支、创建或更新 Pull Request 会执行 **CI**：

- Godot 资源导入、音频、交互、命中箱、射击、玩家动作、敌人节奏与特殊招式、生命周期及十波流程回归。
- Compatibility 材质隔离、静态合批保留碰撞、WebSocket 地址规则回归。
- Windows / Linux 原生中转服务测试与 `go vet`；Linux 额外运行 Go race detector。
- 构建工具的校验、归档与版本保护测试。

失败时可从运行页面的 `godot-test-logs-*` 附件下载日志。除了进程退出码，检查脚本还会查找 Godot 的引擎和脚本错误。

## 发布版本

1. 更新 `project.godot` 的 `config/version`，例如 `0.2.3`，并提交代码。
2. 推送对应的 `v` 标签：

   ```sh
   git tag v0.2.3
   git push origin main
   git push origin v0.2.3
   ```

3. **Build release** 先执行检查，再在 Windows / Linux 运行器分别构建客户端与中转服务，并在 Linux 上导出单线程 Web 客户端。
4. 五个安装包和 SHA-256 清单全部完成后，自动创建 GitHub Release 并上传。带预发布后缀的版本标为 Pre-release。

也可以在 GitHub 页面发布一个指向已有版本标签的 Release，同样会启动构建。标签和工程版本不匹配时构建会拒绝继续，避免把旧代码标成新版本。相同标签的重跑会替换同名附件。

自动生成的附件为：

- `InkTide-<版本>-Windows-x64.zip`
- `InkTide-<版本>-Linux-x64.tar.gz`
- `InkTide-Relay-<版本>-Windows-x64.zip`
- `InkTide-Relay-<版本>-Linux-x64.tar.gz`
- `InkTide-<版本>-Web.zip`
- 每个包的 `.sha256.txt` 和汇总 `SHA256SUMS.txt`

客户端使用官方 release export template，附带 PCK、许可和构建清单；原生客户端会从工程目录之外启动自己的成品进行检查。Web 包校验导出完整性和 WASM 文件头，实际浏览器操作另行验证。中转程序也会在对应系统启动并通过 `/healthz` 检查。CI 不需要额外提供个人访问令牌，上传 Release 只使用当前运行的 `GITHUB_TOKEN`。

## 手动试构建

在 Actions → **Build release** → **Run workflow** 中：

- `tag` 留空：构建当前分支版本，将五个包保存为 Actions Artifacts，不创建 Release。
- 填入已存在的版本标签：构建并发布该标签版本。

从命令行试构建当前 `main`：

```sh
gh workflow run release.yml --ref main
```

本地可运行与 CI 相同的脚本。安装器与打包脚本只依赖 Python 标准库；音频素材已经烘焙，不要求构建环境安装 NumPy / SciPy。

```powershell
python tools/ci/install_godot.py --version 4.7.2 --destination .ci/godot --templates
python tools/ci/build_client.py --godot .ci/godot/godot.exe --platform windows --version 0.2.3 --output dist/release
python tools/ci/build_relay.py --platform windows --version 0.2.3 --output dist/release
python tools/ci/install_godot.py --version 4.7.2 --destination .ci/godot --web-templates
python tools/ci/build_web.py --godot .ci/godot/godot.exe --output dist/release/web --paper-root G:/paper-agent
```

Linux 将引擎路径改为 `.ci/godot/godot`、平台改为 `linux`。中转构建另需 Go；版本要求见 `server/go.mod`。

云端无界面检查不代替目标显卡性能、音频设备听感或真实公网多人长局测试。
