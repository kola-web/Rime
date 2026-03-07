# Rime Ice 自动更新脚本

本目录包含用于自动更新 [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) 的脚本。

## 文件说明

| 文件 | 用途 | 适用平台 |
|------|------|----------|
| `update-rime-ice.ps1` | PowerShell 脚本 | Windows |
| `update-rime-ice.sh` | Bash 脚本 | Linux / macOS |

## 功能特性

两个脚本都会自动执行以下步骤：

1. **备份当前配置** - 保存到 `backup/full_时间戳/` 目录
2. **下载最新版本** - 从 GitHub 克隆 rime-ice 最新代码
3. **更新文件** - 更新所有 yaml、txt、lua、词库等文件
4. **恢复自定义配置** - 保留你的 `.custom.yaml` 和 `custom_phrase.txt`
5. **清理临时文件** - 删除下载的临时文件
6. **提示重新部署** - 询问是否立即重新部署 Rime

## Windows 使用方法

### 方式一：右键运行（推荐）
1. 打开文件资源管理器，进入 Rime 配置目录
2. 右键点击 `update-rime-ice.ps1`
3. 选择 **"使用 PowerShell 运行"**

### 方式二：终端执行
```powershell
cd $env:USERPROFILE\AppData\Roaming\Rime
.\update-rime-ice.ps1
```

> **注意**：如果执行策略限制，可能需要先运行 `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

## Linux 使用方法

```bash
cd ~/.config/ibus/rime
chmod +x update-rime-ice.sh
./update-rime-ice.sh
```

> **Fcitx5 用户**：配置目录可能是 `~/.local/share/fcitx5/rime`

## macOS 使用方法

```bash
cd ~/Library/Rime
chmod +x update-rime-ice.sh
./update-rime-ice.sh
```

## 更新后操作

脚本运行完成后，需要**重新部署 Rime** 才能使更新生效：

| 平台 | 操作方式 |
|------|----------|
| Windows (小狼毫) | 任务栏 Rime 图标右键 → **重新部署** |
| Linux (IBus) | 点击输入法菜单中的 **重新部署** |
| Linux (Fcitx5) | 执行 `fcitx5 -r` 或重启 Fcitx5 |
| macOS (鼠须管) | 在 Squirrel 菜单中选择 **重新部署** |

## 备份说明

每次更新前，脚本会自动备份：

- **自定义配置文件**：`backup/*.custom.yaml`, `backup/custom_phrase.txt`
- **完整配置备份**：`backup/full_YYYYMMDD_HHMMSS/`（包含所有文件）

如需恢复旧版本，可从备份目录复制文件回来。

## 自定义配置

脚本会自动保留以下个人配置：

- `*.custom.yaml` - 你的个性化配置文件
- `custom_phrase.txt` - 自定义短语

这些文件不会被更新覆盖。

## 网络问题

如果下载失败，脚本会提示错误。你可以：

1. 检查网络连接
2. 使用代理（设置 `HTTP_PROXY` 和 `HTTPS_PROXY` 环境变量）
3. 手动下载并解压到临时目录

## 故障排除

### Windows 执行策略错误
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Linux/macOS 权限错误
```bash
chmod +x update-rime-ice.sh
```

### Git 未安装
脚本会自动检测 Git 是否安装：
- 如果已安装 Git：使用 `git clone` 下载（更快，增量更新）
- 如果未安装 Git：使用 `curl`/`wget` 下载 zip 包

## 相关链接

- [雾凇拼音 GitHub](https://github.com/iDvel/rime-ice)
- [雾凇拼音 文档](https://dvel.me/posts/make-rime-en-better/)
- [Rime 官方文档](https://rime.im/docs/)

---

*脚本版本：2024.03*
