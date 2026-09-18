# encoding: utf-8
<#
.SYNOPSIS
    一键更新雾凇拼音（rime-ice）—— Windows / 小狼毫 Weasel

.DESCRIPTION
    自动完成：备份 -> 拉取上游最新 rime-ice -> 覆盖方案与词库 -> 恢复个人配置 -> 自动重新部署。
    会保留：*.custom.yaml、custom_phrase.txt、语法模型（*.gram）、用户词库（*.userdb）、同步数据（sync/）。
    若输入法正在运行，个别被进程占用的文件（如 lua/lunar.db）会自动跳过并提示，不影响整体更新。

.PARAMETER SkipDeploy
    更新完成后不自动重新部署（默认自动部署）。

.PARAMETER KeepTemp
    保留临时克隆目录 rime-ice-new，便于检查（默认更新后删除）。

.PARAMETER UpdateGrammar
    重新下载万象语法模型 wanxiang-lts-zh-hans.gram（约 400MB，覆盖旧文件；跳过则保留现有模型）。

.EXAMPLE
    .\update-rime-ice.ps1
    .\update-rime-ice.ps1 -SkipDeploy -KeepTemp
    .\update-rime-ice.ps1 -UpdateGrammar
#>
[CmdletBinding()]
param(
    [switch]$SkipDeploy,
    [switch]$KeepTemp,
    [switch]$UpdateGrammar
)

$ErrorActionPreference = "Stop"

# ---------- 路径与资源 ----------
$RimeDir = "$env:APPDATA\Rime"
if (-not (Test-Path $RimeDir)) {
    $RimeDir = "$env:USERPROFILE\AppData\Roaming\Rime"
}
$BackupDir    = Join-Path $RimeDir "backup"
$TempDir      = Join-Path $RimeDir "rime-ice-new"
$RepoUrl      = "https://github.com/iDvel/rime-ice.git"
$ZipUrl       = "https://github.com/iDvel/rime-ice/archive/refs/heads/main.zip"
$GrammarUrl   = "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram"
$GrammarFile  = Join-Path $RimeDir "wanxiang-lts-zh-hans.gram"

# 需要保留的个人配置文件（相对 Rime 根目录，更新前快照、更新后原样恢复）
$PreservePatterns = @("*.custom.yaml", "custom_phrase.txt")

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Done {
    param([string]$Text)
    Write-Host "    $Text" -ForegroundColor Green
}

function Get-RimeVersion {
    param([string]$SchemaPath)
    if (-not (Test-Path $SchemaPath)) { return "未知" }
    $content = Get-Content $SchemaPath -Raw -Encoding UTF8
    if ($content -match 'version:\s*"([^"]+)"') { return $matches[1] }
    return "未知"
}

function Find-WeaselDeployer {
    $appPath = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\WeaselDeployer.exe" -ErrorAction SilentlyContinue
    if ($appPath -and (Test-Path $appPath.'(default)')) {
        return $appPath.'(default)'
    }
    $candidates = @(Get-ChildItem "C:\Program Files\Rime\weasel-*\WeaselDeployer.exe" -ErrorAction SilentlyContinue)
    if ($candidates.Count -gt 0) {
        return ($candidates | Sort-Object Name -Descending | Select-Object -First 1).FullName
    }
    return $null
}

# 容错复制目录：逐个文件复制，被占用的文件跳过并提示，不中断整体更新
# 返回跳过的文件数
function Copy-DirectoryTolerant {
    param([string]$Source, [string]$DestRoot, [string]$ItemName)
    $copied = 0
    $skipped = 0
    $files = @(Get-ChildItem -Path $Source -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Source.Length + 1)
        $dest = Join-Path (Join-Path $DestRoot $ItemName) $rel
        try {
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -Path $f.FullName -Destination $dest -Force -ErrorAction Stop
            $copied++
        } catch {
            Write-Host "    跳过（被占用）: $ItemName\$rel" -ForegroundColor Yellow
            $skipped++
        }
    }
    Write-Done "已更新: $ItemName ($copied 个文件)"
    return $skipped
}

# ---------- 主体 ----------
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Rime Ice 自动更新脚本 (Windows)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path $RimeDir)) {
    Write-Host "错误: 未找到 Rime 配置目录: $RimeDir" -ForegroundColor Red
    exit 1
}
Set-Location $RimeDir

# 1. 版本
$currentVersion = Get-RimeVersion (Join-Path $RimeDir "rime_ice.schema.yaml")
Write-Host ""
Write-Host "当前版本: $currentVersion" -ForegroundColor Yellow

# 2. 备份
Write-Step "[1/5] 备份当前配置"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$fullBackupDir = Join-Path $BackupDir "full_$timestamp"
New-Item -ItemType Directory -Path $fullBackupDir -Force | Out-Null

# 2a. 完整备份方案与词库
$backupItems = @("*.yaml", "*.txt", "lua", "cn_dicts", "en_dicts", "opencc")
foreach ($item in $backupItems) {
    $src = Join-Path $RimeDir $item
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $fullBackupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Done "完整备份: $fullBackupDir"

# 2b. 快照个人配置文件（更新后按这份清单恢复，避免"复活"已删除的配置）
$preserveSnapshotDir = Join-Path $BackupDir "_preserve_$timestamp"
New-Item -ItemType Directory -Path $preserveSnapshotDir -Force | Out-Null
$preserveFiles = @()
foreach ($pattern in $PreservePatterns) {
    Get-ChildItem -Path $RimeDir -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $preserveSnapshotDir -Force
        $preserveFiles += $_.Name
        Write-Done "保留配置: $($_.Name)"
    }
}
Write-Host ""

# 3. 拉取最新版本
Write-Step "[2/5] 拉取上游最新 rime-ice"
if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force
}

$downloadOk = $false
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    Write-Host "    使用 git 克隆（浅克隆，失败自动重试一次）..." -ForegroundColor Gray
    # PS 5.1 / pwsh 下 EAP=Stop 会把原生命令的 stderr 当作终止错误，这里临时切到 Continue
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git clone --depth 1 $RepoUrl $TempDir 2>$null
    if (-not (Test-Path $TempDir)) {
        git clone --depth 1 $RepoUrl $TempDir 2>$null
    }
    $ErrorActionPreference = $oldEap
    if (Test-Path $TempDir) { $downloadOk = $true }
}
if (-not $downloadOk) {
    Write-Host "    未使用 git（或失败），改用 zip 下载..." -ForegroundColor Gray
    $zipFile = Join-Path $RimeDir "rime-ice-temp.zip"
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    curl.exe -sSL --retry 3 -o $zipFile $ZipUrl
    $ErrorActionPreference = $oldEap
    if ($LASTEXITCODE -ne 0) {
        Write-Host "错误: 下载失败，请检查网络连接" -ForegroundColor Red
        exit 1
    }
    Expand-Archive -Path $zipFile -DestinationPath $TempDir -Force
    Remove-Item $zipFile -Force
    # 去掉多出来的一层目录（main 分支解压后为 rime-ice-main/）
    $nested = Get-ChildItem -Path $TempDir -Directory | Select-Object -First 1
    if ($nested -and $nested.Name -like "rime-ice-*") {
        Get-ChildItem -Path $nested.FullName | Move-Item -Destination $TempDir -Force
        Remove-Item -Path $nested.FullName -Recurse -Force
    }
    $downloadOk = Test-Path $TempDir
}
if (-not $downloadOk) {
    Write-Host "错误: 下载失败！" -ForegroundColor Red
    exit 1
}

$newVersion = Get-RimeVersion (Join-Path $TempDir "rime_ice.schema.yaml")
Write-Host "最新版本: $newVersion" -ForegroundColor Yellow
Write-Host ""

# 4. 覆盖方案文件（不碰 *.custom.yaml、custom_phrase.txt 等个人配置）
Write-Step "[3/5] 更新方案与词库"
$copyItems = @("*.yaml", "*.txt")
foreach ($item in $copyItems) {
    $files = Get-ChildItem -Path $TempDir -Filter $item -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notlike "*.custom.yaml" -and $_.Name -notlike "*.custom.txt" -and $_.Name -ne "custom_phrase.txt" }
    foreach ($f in $files) {
        Copy-Item -Path $f.FullName -Destination $RimeDir -Force
    }
    Write-Done "已更新: $item ($($files.Count) 个文件)"
}

$totalSkipped = 0
foreach ($item in @("lua", "cn_dicts", "en_dicts", "opencc")) {
    $src = Join-Path $TempDir $item
    if (-not (Test-Path $src)) { continue }
    $totalSkipped += Copy-DirectoryTolerant -Source $src -DestRoot $RimeDir -ItemName $item
}
if ($totalSkipped -gt 0) {
    Write-Host "    共 $totalSkipped 个文件被占用跳过（输入法运行中属正常，多为 lunar.db）。" -ForegroundColor Yellow
    Write-Host "    如在意版本同步，可退出小狼毫后重新运行本脚本一次。" -ForegroundColor Yellow
}
Write-Host ""

# 5. 恢复个人配置
Write-Step "[4/5] 恢复个人配置"
foreach ($name in $preserveFiles) {
    $src = Join-Path $preserveSnapshotDir $name
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $RimeDir -Force
        Write-Done "已恢复: $name"
    }
}
Write-Host ""

# 6. 语法模型（默认保留；-UpdateGrammar 时重新下载）
if ($UpdateGrammar) {
    Write-Step "[可选] 更新万象语法模型（约 400MB）"
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    curl.exe -sSL --retry 3 -C - -o $GrammarFile $GrammarUrl
    $ErrorActionPreference = $oldEap
    if ($LASTEXITCODE -eq 0 -and (Test-Path $GrammarFile)) {
        $sizeMb = [math]::Round((Get-Item $GrammarFile).Length / 1MB, 1)
        Write-Done "语法模型已更新: $sizeMb MB"
    } else {
        Write-Host "警告: 语法模型下载失败，保留原文件" -ForegroundColor Yellow
    }
} elseif (Test-Path $GrammarFile) {
    Write-Done "语法模型已保留: wanxiang-lts-zh-hans.gram"
} else {
    Write-Host "提示: 未检测到语法模型（如需安装请加 -UpdateGrammar）" -ForegroundColor Yellow
}
Write-Host ""

# 7. 清理临时目录
Write-Step "[5/5] 清理"
if ($KeepTemp) {
    Write-Done "按 -KeepTemp 保留临时目录: $TempDir"
} else {
    if (Test-Path $TempDir) { Remove-Item -Path $TempDir -Recurse -Force }
    Write-Done "临时目录已清理"
}
Write-Host ""

# 8. 自动重新部署
$deployDone = $false
if (-not $SkipDeploy) {
    Write-Step "重新部署小狼毫"
    $deployer = Find-WeaselDeployer
    if ($deployer) {
        Write-Host "    使用部署器: $deployer" -ForegroundColor Gray
        & $deployer /deploy
        $deployDone = $true
        Write-Done "部署完成"
    } else {
        Write-Host "警告: 未找到 WeaselDeployer.exe，请手动重新部署（托盘图标右键 -> 重新部署）" -ForegroundColor Yellow
    }
} else {
    Write-Host "已按 -SkipDeploy 跳过自动部署，请手动重新部署" -ForegroundColor Yellow
}
Write-Host ""

# 9. 结果
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  更新完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "版本: $currentVersion -> $newVersion" -ForegroundColor Yellow
Write-Host "备份: $fullBackupDir" -ForegroundColor Gray
if ($totalSkipped -gt 0) {
    Write-Host "提示: 本次有 $totalSkipped 个被占用文件未更新，下次退出输入法后运行即可补全" -ForegroundColor Yellow
}
if (-not $deployDone -and -not $SkipDeploy) {
    Write-Host "提示: 请手动重新部署后生效" -ForegroundColor Yellow
}

if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and $Host.Name -eq "ConsoleHost") {
    Write-Host ""
    Read-Host "按回车键退出"
}
