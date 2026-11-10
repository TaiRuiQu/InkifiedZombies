param(
    [string]$EnginePath = 'G:\Godot\Godot_v4.7.2-stable_win64.exe',
    [switch]$SkipImport,
    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engineFullPath = [IO.Path]::GetFullPath($EnginePath)
if ($engineFullPath.EndsWith('_console.exe', [StringComparison]::OrdinalIgnoreCase)) {
    $engineFullPath = $engineFullPath.Substring(0, $engineFullPath.Length - '_console.exe'.Length) + '.exe'
}
if (-not (Test-Path -LiteralPath $engineFullPath -PathType Leaf)) {
    throw "Godot engine was not found: $engineFullPath"
}
$engineCliPath = Join-Path ([IO.Path]::GetDirectoryName($engineFullPath)) ([IO.Path]::GetFileNameWithoutExtension($engineFullPath) + '_console.exe')
if (-not (Test-Path -LiteralPath $engineCliPath -PathType Leaf)) {
    throw 'Use the Godot Windows distribution with its matching _console.exe wrapper for build output and exit codes.'
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot'))) {
    throw "project.godot was not found in the expected workspace."
}
$clientDirectory = Join-Path $projectRoot 'dist\client-windows'
$packPath = Join-Path $clientDirectory 'InkTide.pck'
$runtimePath = Join-Path $clientDirectory 'InkTide.exe'
$versionMatch = [regex]::Match([IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot')), '(?m)^config/version="([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)"\s*$')
if (-not $versionMatch.Success) { throw 'project.godot must define a valid application version.' }
$releaseVersion = $versionMatch.Groups[1].Value
$archivePath = Join-Path $projectRoot "dist\InkTide-$releaseVersion-Windows-x64.zip"
New-Item -ItemType Directory -Path $clientDirectory -Force | Out-Null

if (-not $SkipImport) {
    & $engineCliPath --headless --path $projectRoot --editor --import --quit
    if ($LASTEXITCODE -ne 0) { throw "Godot project import failed ($LASTEXITCODE)." }
}
& $engineCliPath --headless --path $projectRoot --export-pack 'Windows Runtime Pack' $packPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packPath)) {
    throw "Godot PCK export failed ($LASTEXITCODE)."
}
Copy-Item -LiteralPath $engineFullPath -Destination $runtimePath -Force

$launcher = @'
@echo off
cd /d "%~dp0"
start "Ink Tide" "%~dp0InkTide.exe" --main-pack "%~dp0InkTide.pck"
'@
[IO.File]::WriteAllText((Join-Path $clientDirectory 'Start-InkTide.cmd'), $launcher, [Text.Encoding]::ASCII)
$readme = @'
墨潮 · Ink Tide __VERSION__ / Windows x64

解压整个文件夹，双击 InkTide.exe 或 Start-InkTide.cmd 即可进入游戏，无需安装 Godot。
InkTide.exe 与 InkTide.pck 必须放在同一文件夹。请勿只复制 exe。
系统需要兼容 Vulkan 的显卡/驱动；如遇图形启动问题，请更新驱动。

联机：标题页进入「同守 · 联机」，支持至多四人。
直连默认 UDP 7777；中转默认 TCP 7778。中转服务程序另附在 server 包内。

本包随附 Godot 4.7.2 编辑器构建作为引擎运行时和独立游戏 PCK，
并非使用正式 Windows export template 生成的精简发布二进制。
正常双击启动为游戏，不进入编辑器；体积会大于使用 release template 的版本。
没有房主迁移。公网连通性取决于防火墙、端口开放和服务器部署。

字体与引擎许可见 THIRD_PARTY_NOTICES.md / FONT_LICENSE.txt / ENGINE_LICENSES.txt。
测试快捷键与开发源码不属于本客户端发行说明。
'@
[IO.File]::WriteAllText((Join-Path $clientDirectory 'README-先读我.txt'), $readme.Replace('__VERSION__', $releaseVersion), [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $clientDirectory -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\OFL.txt') -Destination (Join-Path $clientDirectory 'FONT_LICENSE.txt') -Force

# The engine exposes its own exact license and bundled third-party licenses.
# Read them from the same local binary rather than substituting a versioned web copy.
$licenseScript = Join-Path ([IO.Path]::GetTempPath()) ('ink-tide-license-' + [guid]::NewGuid().ToString('N') + '.gd')
$licenseText = @'
extends SceneTree
func _initialize() -> void:
    var destination := OS.get_cmdline_user_args()[0]
    var output := FileAccess.open(destination, FileAccess.WRITE)
    output.store_string(Engine.get_license_text() + "\n\nBundled engine dependency licenses\n")
    var licenses := Engine.get_license_info()
    for key in licenses:
        output.store_string("\n===== " + String(key) + " =====\n" + String(licenses[key]) + "\n")
    output.store_string("\nBundled engine dependency copyright notices\n")
    output.store_string(JSON.stringify(Engine.get_copyright_info(), "  ") + "\n")
    output.close()
    quit(0)
'@
try {
    [IO.File]::WriteAllText($licenseScript, $licenseText, [Text.UTF8Encoding]::new($false))
    & $engineCliPath --headless --path ([IO.Path]::GetTempPath()) --script $licenseScript -- (Join-Path $clientDirectory 'ENGINE_LICENSES.txt')
    if ($LASTEXITCODE -ne 0) { throw "Engine license extraction failed ($LASTEXITCODE)." }
} finally {
    Remove-Item -LiteralPath $licenseScript -ErrorAction SilentlyContinue
}

# Launch the distributable from outside the project so missing packed files
# cannot be silently found in the developer checkout.
$verificationDirectory = Join-Path $projectRoot 'dev_shots'
New-Item -ItemType Directory -Path $verificationDirectory -Force | Out-Null
$verificationLog = Join-Path $verificationDirectory 'client-runtime-build-check.log'
$runtimeCheck = Start-Process -FilePath $runtimePath -ArgumentList @('--headless', '--log-file', ('"' + $verificationLog + '"'), '--', '--verify-runtime') -WorkingDirectory ([IO.Path]::GetTempPath()) -WindowStyle Hidden -PassThru -Wait
if ($runtimeCheck.ExitCode -ne 0) {
    throw "Packaged client exited with $($runtimeCheck.ExitCode). See $verificationLog"
}
if (Test-Path -LiteralPath $verificationLog) {
    $verificationText = [IO.File]::ReadAllText($verificationLog)
    if ($verificationText -match '(?m)^(SCRIPT ERROR|ERROR:)' -or $verificationText -notmatch '\[runtime\] title, map, settings, audio and content loaded') {
        throw "Packaged client reported a resource/script error. See $verificationLog"
    }
}
$manifest = [ordered]@{
    name = 'Ink Tide'
    version = $releaseVersion
    platform = 'Windows-x64'
    packaging = 'Godot-4.7.2-editor-binary-as-runtime-with-standalone-PCK'
    built_utc = [DateTime]::UtcNow.ToString('o')
    executable_sha256 = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash
    pack_sha256 = (Get-FileHash -LiteralPath $packPath -Algorithm SHA256).Hash
    headless_startup_exit_code = $runtimeCheck.ExitCode
}
[IO.File]::WriteAllText((Join-Path $clientDirectory 'BUILD-MANIFEST.json'), ($manifest | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

if (-not $NoZip) {
    Compress-Archive -LiteralPath $clientDirectory -DestinationPath $archivePath -CompressionLevel Optimal -Force
    Write-Host "Client archive: $archivePath"
}
Write-Host "Client runtime: $runtimePath"
Write-Host "Client data:    $packPath"
