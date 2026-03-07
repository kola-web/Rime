#!/bin/bash
# Rime Ice 自动更新脚本 (Bash)
# 用法: chmod +x update-rime-ice.sh && ./update-rime-ice.sh

set -e

# 配置
RIME_DIR=""
BACKUP_DIR=""
TEMP_DIR=""
REPO_URL="https://github.com/iDvel/rime-ice.git"

# 检测操作系统并设置路径
detect_os() {
    case "$(uname -s)" in
        Linux*)
            if [ -n "$XDG_CONFIG_HOME" ]; then
                RIME_DIR="$XDG_CONFIG_HOME/ibus/rime"
            else
                RIME_DIR="$HOME/.config/ibus/rime"
            fi
            # 也检查 fcitx5
            if [ ! -d "$RIME_DIR" ] && [ -d "$HOME/.local/share/fcitx5/rime" ]; then
                RIME_DIR="$HOME/.local/share/fcitx5/rime"
            fi
            ;;
        Darwin*)
            # macOS
            RIME_DIR="$HOME/Library/Rime"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            # Windows (Git Bash, MSYS2, etc.)
            RIME_DIR="$HOME/AppData/Roaming/Rime"
            ;;
        *)
            echo "未知操作系统，请手动指定 RIME_DIR"
            exit 1
            ;;
    esac
    
    BACKUP_DIR="$RIME_DIR/backup"
    TEMP_DIR="$RIME_DIR/rime-ice-new"
}

# 颜色输出
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
cyan() { echo -e "\033[36m$1\033[0m"; }
gray() { echo -e "\033[90m$1\033[0m"; }

# 主函数
main() {
    detect_os
    
    # 检查 Rime 目录
    if [ ! -d "$RIME_DIR" ]; then
        red "错误: 未找到 Rime 配置目录: $RIME_DIR"
        exit 1
    fi
    
    cd "$RIME_DIR"
    
    cyan "========================================"
    cyan "  Rime Ice 自动更新脚本"
    cyan "========================================"
    echo ""
    
    # 检查当前版本
    current_version="未知"
    schema_file="$RIME_DIR/rime_ice.schema.yaml"
    if [ -f "$schema_file" ]; then
        current_version=$(grep -oP 'version:\s*"\K[^"]+' "$schema_file" 2>/dev/null || echo "未知")
    fi
    yellow "当前版本: $current_version"
    echo ""
    
    # 步骤 1: 备份
    green "[1/5] 正在备份当前配置..."
    mkdir -p "$BACKUP_DIR"
    
    # 备份自定义配置文件
    for file in *.custom.yaml custom_phrase.txt; do
        if [ -f "$file" ]; then
            cp "$file" "$BACKUP_DIR/" 2>/dev/null || true
        fi
    done
    
    # 完整备份
    timestamp=$(date +"%Y%m%d_%H%M%S")
    full_backup_dir="$BACKUP_DIR/full_$timestamp"
    mkdir -p "$full_backup_dir"
    
    for item in *.yaml *.txt lua cn_dicts en_dicts opencc; do
        if [ -e "$item" ]; then
            cp -r "$item" "$full_backup_dir/" 2>/dev/null || true
        fi
    done
    
    gray "      备份完成: $full_backup_dir"
    echo ""
    
    # 步骤 2: 下载
    green "[2/5] 正在下载最新版本..."
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"
    
    # 检查是否有 git
    if command -v git &> /dev/null; then
        gray "      使用 Git 克隆..."
        git clone --depth 1 "$REPO_URL" "$TEMP_DIR" 2>&1 | grep -v "^remote:" || true
    else
        gray "      未检测到 Git，使用下载方式..."
        zip_url="https://github.com/iDvel/rime-ice/archive/refs/heads/main.zip"
        zip_file="$RIME_DIR/rime-ice-temp.zip"
        
        if command -v curl &> /dev/null; then
            curl -L -o "$zip_file" "$zip_url" 2>/dev/null
        elif command -v wget &> /dev/null; then
            wget -O "$zip_file" "$zip_url" 2>/dev/null
        else
            red "错误: 未找到 curl 或 wget"
            exit 1
        fi
        
        unzip -q "$zip_file" -d "$TEMP_DIR"
        rm "$zip_file"
        
        # 调整目录结构
        extracted_dir=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
        if [ -n "$extracted_dir" ]; then
            mv "$extracted_dir"/* "$TEMP_DIR/"
            rmdir "$extracted_dir" 2>/dev/null || true
        fi
    fi
    
    if [ ! -d "$TEMP_DIR" ]; then
        red "错误: 下载失败！"
        exit 1
    fi
    
    # 检查新版本
    new_version="未知"
    new_schema_file="$TEMP_DIR/rime_ice.schema.yaml"
    if [ -f "$new_schema_file" ]; then
        new_version=$(grep -oP 'version:\s*"\K[^"]+' "$new_schema_file" 2>/dev/null || echo "未知")
    fi
    
    gray "      最新版本: $new_version"
    echo ""
    
    # 步骤 3: 更新
    green "[3/5] 正在更新文件..."
    
    for pattern in *.yaml *.txt lua cn_dicts en_dicts opencc; do
        source="$TEMP_DIR/$pattern"
        if [ -e "$source" ]; then
            cp -r "$source" "$RIME_DIR/" 2>/dev/null || true
            gray "      已更新: $pattern"
        fi
    done
    
    echo ""
    
    # 步骤 4: 恢复自定义配置
    green "[4/5] 正在恢复自定义配置..."
    
    for file in "$BACKUP_DIR"/*.custom.yaml; do
        if [ -f "$file" ]; then
            cp "$file" "$RIME_DIR/"
            gray "      已恢复: $(basename "$file")"
        fi
    done
    
    if [ -f "$BACKUP_DIR/custom_phrase.txt" ]; then
        cp "$BACKUP_DIR/custom_phrase.txt" "$RIME_DIR/"
        gray "      已恢复: custom_phrase.txt"
    fi
    
    echo ""
    
    # 步骤 5: 清理
    green "[5/5] 正在清理临时文件..."
    rm -rf "$TEMP_DIR"
    gray "      清理完成"
    echo ""
    
    # 完成
    cyan "========================================"
    green "  更新完成！"
    cyan "========================================"
    echo ""
    yellow "版本: $current_version -> $new_version"
    echo ""
    echo "请执行以下操作："
    echo "  1. 重新部署 Rime"
    echo "     - Linux: 点击输入法菜单中的重新部署"
    echo "     - macOS: 在 Squirrel 菜单中选择重新部署"
    echo "     - Windows: 任务栏图标右键 -> 重新部署"
    echo "  2. 测试输入法是否正常工作"
    echo ""
    gray "备份位置: $full_backup_dir"
    echo ""
    
    # 尝试自动重新部署（Linux/macOS）
    if [ "$(uname -s)" = "Linux" ]; then
        if command -v ibus-daemon &> /dev/null; then
            read -p "是否立即重新部署 Rime? (y/n) " deploy
            if [ "$deploy" = "y" ] || [ "$deploy" = "Y" ]; then
                ibus restart 2>/dev/null || true
                green "已重启 IBus"
            fi
        elif command -v fcitx5 &> /dev/null; then
            read -p "是否立即重新部署 Rime? (y/n) " deploy
            if [ "$deploy" = "y" ] || [ "$deploy" = "Y" ]; then
                fcitx5 -r 2>/dev/null || true
                green "已重启 Fcitx5"
            fi
        fi
    elif [ "$(uname -s)" = "Darwin" ]; then
        read -p "是否立即重新部署 Rime? (y/n) " deploy
        if [ "$deploy" = "y" ] || [ "$deploy" = "Y" ]; then
            if [ -f "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]; then
                "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --deploy 2>/dev/null || true
                green "已重新部署 Squirrel"
            fi
        fi
    fi
    
    echo ""
    read -n 1 -s -r -p "按任意键退出..."
    echo ""
}

# 运行主函数
main "$@"
