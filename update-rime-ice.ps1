# Rime Ice 自动更新脚本 (PowerShell)
# 用法: 右键选择"使用 PowerShell 运行" 或在终端执行 .\update-rime-ice.ps1

$ErrorActionPreference = "Stop"

# 配置
$RimeDir = "$env:USERPROFILE\AppData\Roaming\Rime"
$BackupDir = "$RimeDir\backup"
$TempDir = "$RimeDir\rime-ice-new"
$RepoUrl = "https://github.com/iDvel/rime-ice.git"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Rime Ice 自动更新脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查当前版本
$currentVersion = "未知"
$schemaFile = "$RimeDir\rime_ice.schema.yaml"
if (Test-Path $schemaFile) {
    $content = Get-Content $schemaFile -Raw
    if ($content -match 'version:\s*"([^"]+)"') {
        $currentVersion = $matches[1]
    }
}
Write-Host "当前版本: $currentVersion" -ForegroundColor Yellow
Write-Host ""

# 步骤 1: 备份当前配置
Write-Host "[1/5] 正在备份当前配置..." -ForegroundColor Green
if (!(Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

# 备份自定义配置文件
$customFiles = @("*.custom.yaml", "custom_phrase.txt")
foreach ($pattern in $customFiles) {
    Get-ChildItem -Path $RimeDir -Filter $pattern -ErrorAction SilentlyContinue | 
        Copy-Item -Destination $BackupDir -Force
}

# 备份整个配置（以防万一）
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$fullBackupDir = "$BackupDir\full_$timestamp"
New-Item -ItemType Directory -Path $fullBackupDir -Force | Out-Null

$itemsToBackup = @("*.yaml", "*.txt", "lua", "cn_dicts", "en_dicts", "opencc")
foreach ($item in $itemsToBackup) {
    $source = Join-Path $RimeDir $item
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $fullBackupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "      备份完成: $fullBackupDir" -ForegroundColor Gray
Write-Host ""

# 步骤 2: 下载最新版本
Write-Host "[2/5] 正在下载最新版本..." -ForegroundColor Green

# 清理临时目录
if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force
}

# 检查是否有 git
$hasGit = $false
try {
    $gitVersion = git --version 2>$null
    if ($gitVersion) {
        $hasGit = $true
    }
} catch {}

if ($hasGit) {
    Write-Host "      使用 Git 克隆..." -ForegroundColor Gray
    git clone --depth 1 $RepoUrl $TempDir 2>&1 | Out-Null
} else {
    Write-Host "      未检测到 Git，使用下载方式..." -ForegroundColor Gray
    $zipUrl = "https://github.com/iDvel/rime-ice/archive/refs/heads/main.zip"
    $zipFile = "$RimeDir\rime-ice-temp.zip"
    
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
        Expand-Archive -Path $zipFile -DestinationPath $TempDir -Force
        Remove-Item $zipFile
        
        # 调整目录结构
        $extractedDir = Get-ChildItem -Path $TempDir -Directory | Select-Object -First 1
        if ($extractedDir) {
            Move-Item -Path "$($extractedDir.FullName)\*" -Destination $TempDir -Force
            Remove-Item $extractedDir.FullName
        }
    } catch {
        Write-Host "      下载失败，请检查网络连接" -ForegroundColor Red
        exit 1
    }
}

if (!(Test-Path $TempDir)) {
    Write-Host "      下载失败！" -ForegroundColor Red
    exit 1
}

# 检查新版本
$newVersion = "未知"
$newSchemaFile = "$TempDir\rime_ice.schema.yaml"
if (Test-Path $newSchemaFile) {
    $content = Get-Content $newSchemaFile -Raw
    if ($content -match 'version:\s*"([^"]+)"') {
        $newVersion = $matches[1]
    }
}

Write-Host "      最新版本: $newVersion" -ForegroundColor Gray
Write-Host ""

# 步骤 3: 更新文件
Write-Host "[3/5] 正在更新文件..." -ForegroundColor Green

# 复制主要文件
$filesToCopy = @(
    "*.yaml",
    "*.txt",
    "lua",
    "cn_dicts",
    "en_dicts",
    "opencc"
)

foreach ($pattern in $filesToCopy) {
    $source = Join-Path $TempDir $pattern
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $RimeDir -Recurse -Force
        Write-Host "      已更新: $pattern" -ForegroundColor Gray
    }
}

Write-Host ""

# 步骤 4: 恢复自定义配置
Write-Host "[4/5] 正在恢复自定义配置..." -ForegroundColor Green

# 从备份恢复 .custom.yaml 文件
Get-ChildItem -Path $BackupDir -Filter "*.custom.yaml" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $RimeDir -Force
    Write-Host "      已恢复: $($_.Name)" -ForegroundColor Gray
}

# 恢复 custom_phrase.txt
$customPhraseBackup = "$BackupDir\custom_phrase.txt"
if (Test-Path $customPhraseBackup) {
    Copy-Item -Path $customPhraseBackup -Destination $RimeDir -Force
    Write-Host "      已恢复: custom_phrase.txt" -ForegroundColor Gray
}

Write-Host ""

# 步骤 5: 清理
Write-Host "[5/5] 正在清理临时文件..." -ForegroundColor Green
if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force
}
Write-Host "      清理完成" -ForegroundColor Gray
Write-Host ""

# 完成
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  更新完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "版本: $currentVersion -> $newVersion" -ForegroundColor Yellow
Write-Host ""
Write-Host "请执行以下操作：" -ForegroundColor White
Write-Host "  1. 重新部署 Rime（任务栏图标右键 -> 重新部署）" -ForegroundColor White
Write-Host "  2. 测试输入法是否正常工作" -ForegroundColor White
Write-Host ""
Write-Host "备份位置: $fullBackupDir" -ForegroundColor Gray
Write-Host ""

# 提示重新部署
$deploy = Read-Host "是否立即重新部署 Rime? (y/n)"
if ($deploy -eq "y" -or $deploy -eq "Y") {
    Write-Host "正在重新部署..." -ForegroundColor Green
    # 尝试找到 Weasel 部署命令
    $weaselDeploy = "C:\Program Files\Rime\weasel-0.16.3\WeaselDeployer.exe"
    if (Test-Path $weaselDeploy) {
        & $weaselDeploy /deploy
    } else {
        Write-Host "请手动重新部署 Rime" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
