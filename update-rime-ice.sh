#!/bin/bash
# ============================================================
# 一键更新雾凇拼音（rime-ice）
#   支持: macOS (Squirrel) / Linux (ibus / fcitx5) / Windows (Git Bash + Weasel)
# 用法:
#   chmod +x update-rime-ice.sh
#   ./update-rime-ice.sh              # 更新并自动重新部署
#   ./update-rime-ice.sh --no-deploy  # 只更新文件，不自动部署
#   ./update-rime-ice.sh --grammar    # 同时重新下载万象语法模型（约 400MB）
#   ./update-rime-ice.sh --keep-temp  # 保留临时克隆目录
# 说明:
#   会保留 *.custom.yaml、custom_phrase.txt、语法模型 *.gram、用户词库
# ============================================================

set -euo pipefail

# ---------- 参数 ----------
AUTO_DEPLOY=1
KEEP_TEMP=0
UPDATE_GRAMMAR=0
for arg in "$@"; do
    case "$arg" in
        --no-deploy)  AUTO_DEPLOY=0 ;;
        --keep-temp)  KEEP_TEMP=1 ;;
        --grammar)    UPDATE_GRAMMAR=1 ;;
        -h|--help)
            grep -E '^#\s' "$0" | sed 's/^#\s\?//'
            exit 0
            ;;
        *) echo "未知参数: $arg（可用 --no-deploy / --keep-temp / --grammar）"; exit 1 ;;
    esac
done

# ---------- 配置 ----------
RIME_DIR=""
BACKUP_DIR=""
REPO_URL="https://github.com/iDvel/rime-ice.git"
ZIP_URL="https://github.com/iDvel/rime-ice/archive/refs/heads/main.zip"
GRAMMAR_URL="https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram"
GRAMMAR_FILE=""

# ---------- 颜色 ----------
red()   { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow(){ echo -e "\033[33m$1\033[0m"; }
cyan()  { echo -e "\033[36m$1\033[0m"; }
gray()  { echo -e "\033[90m$1\033[0m"; }
step()  { echo ""; cyan "==> $1"; }
done_() { echo "    $1"; }

# ---------- 检测系统与路径 ----------
detect_os() {
    case "$(uname -s)" in
        Linux*)
            if [ -n "${XDG_CONFIG_HOME:-}" ] && [ -d "$XDG_CONFIG_HOME/ibus/rime" ]; then
                RIME_DIR="$XDG_CONFIG_HOME/ibus/rime"
            elif [ -d "$HOME/.config/ibus/rime" ]; then
                RIME_DIR="$HOME/.config/ibus/rime"
            elif [ -d "$HOME/.local/share/fcitx5/rime" ]; then
                RIME_DIR="$HOME/.local/share/fcitx5/rime"
            else
                RIME_DIR="$HOME/.config/ibus/rime"
            fi
            ;;
        Darwin*)
            RIME_DIR="$HOME/Library/Rime"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            RIME_DIR="$HOME/AppData/Roaming/Rime"
            ;;
        *)
            red "未知操作系统，请手动修改脚本中的 RIME_DIR"
            exit 1
            ;;
    esac
    GRAMMAR_FILE="$RIME_DIR/wanxiang-lts-zh-hans.gram"
    BACKUP_DIR="$RIME_DIR/backup"
}

# ---------- 读取版本（POSIX 兼容，macOS 也可用） ----------
get_version() {
    local f="$1"
    if [ -f "$f" ]; then
        sed -n 's/^[[:space:]]*version:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1
    fi
}

# ---------- 自动部署 ----------
deploy() {
    case "$(uname -s)" in
        Linux*)
            if command -v ibus-daemon >/dev/null 2>&1; then
                green "    已重启 IBus"
                ibus restart >/dev/null 2>&1 || true
            elif command -v fcitx5-remote >/dev/null 2>&1; then
                green "    已重启 Fcitx5"
                fcitx5-remote -r >/dev/null 2>&1 || true
            elif command -v fcitx >/dev/null 2>&1; then
                green "    已重启 Fcitx"
                fcitx -r >/dev/null 2>&1 || true
            else
                yellow "    未检测到 ibus/fcitx，请手动重新部署"
            fi
            ;;
        Darwin*)
            local squirrel=""
            if [ -x "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]; then
                squirrel="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
            elif [ -x "$HOME/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]; then
                squirrel="$HOME/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
            fi
            if [ -n "$squirrel" ]; then
                green "    已重新部署 Squirrel"
                "$squirrel" --deploy >/dev/null 2>&1 || true
            else
                yellow "    未找到 Squirrel，请手动重新部署（输入法菜单 -> 重新部署）"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            # Windows Git Bash：优先注册表，其次安装目录（命令替换加 || true，避免 set -e 误中断）
            local deployer=""
            deployer=$(reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\WeaselDeployer.exe" //ve 2>/dev/null | sed -n 's/.*REG_SZ[[:space:]]*//p' | head -1) || true
            if [ -z "$deployer" ] || [ ! -f "$deployer" ]; then
                deployer=$(ls -d /c/Program\ Files/Rime/weasel-*/WeaselDeployer.exe "/c/Program Files (x86)/Rime/weasel-"*/WeaselDeployer.exe 2>/dev/null | sort | tail -1) || true
            fi
            if [ -n "$deployer" ] && [ -f "$deployer" ]; then
                green "    已重新部署 Weasel"
                powershell.exe -NoProfile -Command "& '$deployer' /deploy" >/dev/null 2>&1 || true
            else
                yellow "    未找到 WeaselDeployer.exe，请手动重新部署（托盘图标右键 -> 重新部署）"
            fi
            ;;
    esac
}

# ---------- 主流程 ----------
detect_os

cyan "========================================"
cyan "  Rime Ice 自动更新脚本"
cyan "========================================"

if [ ! -d "$RIME_DIR" ]; then
    red "错误: 未找到 Rime 配置目录: $RIME_DIR"
    exit 1
fi
cd "$RIME_DIR"

current_version="$(get_version "$RIME_DIR/rime_ice.schema.yaml")"
[ -z "$current_version" ] && current_version="未知"
yellow "当前版本: $current_version"
echo ""

# 1. 备份
step "[1/5] 备份当前配置"
mkdir -p "$BACKUP_DIR"

timestamp="$(date +%Y%m%d_%H%M%S)"
full_backup_dir="$BACKUP_DIR/full_$timestamp"
mkdir -p "$full_backup_dir"
for item in *.yaml *.txt lua cn_dicts en_dicts opencc; do
    if [ -e "$item" ]; then
        cp -r "$item" "$full_backup_dir/" 2>/dev/null || true
    fi
done
done_ "完整备份: $full_backup_dir"

# 快照个人配置（更新后按这份清单恢复，不复活已删除的配置）
preserve_dir="$BACKUP_DIR/_preserve_$timestamp"
mkdir -p "$preserve_dir"
preserve_files=""
for pattern in "*.custom.yaml" "custom_phrase.txt"; do
    for f in $RIME_DIR/$pattern; do
        if [ -f "$f" ]; then
            cp "$f" "$preserve_dir/"
            preserve_files="$preserve_files $(basename "$f")"
            done_ "保留配置: $(basename "$f")"
        fi
    done
done
echo ""

# 2. 拉取
step "[2/5] 拉取上游最新 rime-ice"
TEMP_DIR="$RIME_DIR/rime-ice-new"
rm -rf "$TEMP_DIR"

if command -v git >/dev/null 2>&1; then
    gray "    使用 git 克隆（浅克隆）..."
    git clone --depth 1 "$REPO_URL" "$TEMP_DIR" 2>/dev/null || true
fi

if [ ! -d "$TEMP_DIR" ]; then
    gray "    未使用 git（或失败），改用 zip 下载..."
    zip_file="$RIME_DIR/rime-ice-temp.zip"
    if command -v curl >/dev/null 2>&1; then
        curl -L --retry 3 -o "$zip_file" "$ZIP_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$zip_file" "$ZIP_URL"
    else
        red "错误: 未找到 git / curl / wget"
        exit 1
    fi
    if [ ! -s "$zip_file" ]; then
        red "错误: 下载失败，请检查网络连接"
        rm -f "$zip_file"
        exit 1
    fi
    mkdir -p "$TEMP_DIR"
    unzip -q "$zip_file" -d "$TEMP_DIR"
    rm -f "$zip_file"
    extracted_dir="$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [ -n "$extracted_dir" ]; then
        mv "$extracted_dir"/* "$TEMP_DIR/" 2>/dev/null || true
        rmdir "$extracted_dir" 2>/dev/null || true
    fi
fi

if [ ! -d "$TEMP_DIR" ]; then
    red "错误: 下载失败！"
    exit 1
fi

new_version="$(get_version "$TEMP_DIR/rime_ice.schema.yaml")"
[ -z "$new_version" ] && new_version="未知"
yellow "最新版本: $new_version"
echo ""

# 3. 更新（跳过 .custom 个人文件，保留 .gram 模型）
step "[3/5] 更新方案与词库"
# 根目录下的 yaml / txt（注意：通配符必须在未加引号的位置展开）
for f in "$TEMP_DIR"/*.yaml; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in
        *.custom.yaml) continue ;;   # 个人配置由第 4 步恢复
        *) cp -f "$f" "$RIME_DIR/" ;;
    esac
done
for f in "$TEMP_DIR"/*.txt; do
    [ -f "$f" ] || continue
    cp -f "$f" "$RIME_DIR/"
done
# 子目录
for item in lua cn_dicts en_dicts opencc; do
    if [ -d "$TEMP_DIR/$item" ]; then
        cp -rf "$TEMP_DIR/$item" "$RIME_DIR/"
        done_ "已更新: $item"
    fi
done
echo ""

# 4. 恢复个人配置
step "[4/5] 恢复个人配置"
for name in $preserve_files; do
    if [ -f "$preserve_dir/$name" ]; then
        cp "$preserve_dir/$name" "$RIME_DIR/"
        done_ "已恢复: $name"
    fi
done
echo ""

# 5. 语法模型
if [ "$UPDATE_GRAMMAR" = "1" ]; then
    step "[5/6] 更新万象语法模型（约 400MB）"
    if command -v curl >/dev/null 2>&1; then
        curl -L --retry 3 -C - -o "$GRAMMAR_FILE" "$GRAMMAR_URL"
        if [ -s "$GRAMMAR_FILE" ]; then
            size_mb=$(du -m "$GRAMMAR_FILE" | cut -f1)
            done_ "语法模型已更新: ${size_mb}MB"
        else
            yellow "    警告: 语法模型下载失败"
        fi
    else
        yellow "    未找到 curl，跳过语法模型更新"
    fi
elif [ -f "$GRAMMAR_FILE" ]; then
    done_ "语法模型已保留: wanxiang-lts-zh-hans.gram"
else
    yellow "提示: 未检测到语法模型（如需安装请加 --grammar）"
fi
echo ""

# 6. 清理
step "[6/6] 清理"
if [ "$KEEP_TEMP" = "1" ]; then
    done_ "按 --keep-temp 保留临时目录: $TEMP_DIR"
else
    rm -rf "$TEMP_DIR"
    done_ "临时目录已清理"
fi
echo ""

# 7. 部署
if [ "$AUTO_DEPLOY" = "1" ]; then
    step "自动重新部署"
    deploy
else
    yellow "已按 --no-deploy 跳过自动部署，请手动重新部署"
fi
echo ""

# 8. 结果
cyan "========================================"
green "  更新完成！"
cyan "========================================"
yellow "版本: $current_version -> $new_version"
gray  "备份: $full_backup_dir"
echo ""
