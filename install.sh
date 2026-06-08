#!/bin/bash

# ============================================
# Jacob Linux 一键在线部署脚本
# 用法: curl -fsSL https://gitee.com/<你的用户名>/linux-deploy/raw/main/install.sh | bash
# ============================================

clear
echo -e "${GREEN}"
echo "       ██╗  █████╗  ██████╗  ██████╗ ██████╗ "
echo "       ██║ ██╔══██╗██╔════╝ ██╔═══██╗██╔══██╗"
echo "       ██║ ███████║██║      ██║   ██║██████╔╝"
echo "  ██   ██║ ██╔══██║██║      ██║   ██║██╔══██╗"
echo "  ╚█████╔╝ ██║  ██║╚██████╗ ╚██████╔╝██████╔╝"
echo "   ╚════╝  ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═════╝ "
echo -e "${YELLOW}  =================== SYSTEM DEPLOY ===================${RESET}"
echo


set -e

GREEN='\033[01;32m'
BLUE='\033[01;34m'
YELLOW='\033[01;33m'
RESET='\033[00m'

# Gitee 仓库配置（用户需要修改这里）
REPO_URL="https://gitee.com/jacob_ng/linux-deploy"
RAW_URL="https://gitee.com/jacob_ng/linux-deploy/raw/main"

# 本地部署目录
DEPLOY_DIR="$HOME/linux-deploy"
SCRIPTS_DIR="$HOME/scripts"

echo -e "${BLUE}[*] Jacob Linux 一键在线部署脚本${RESET}"
echo -e "${BLUE}[*] 仓库地址: $REPO_URL${RESET}"
echo

# 检查依赖
check_dependency() {
    local cmd="$1"
    local pkg="${2:-$1}"
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}[!] 未检测到 $cmd，尝试安装...${RESET}"
        if [ -f /etc/debian_version ]; then
            sudo apt update -y && sudo apt install -y "$pkg"
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y "$pkg"
        else
            echo -e "${YELLOW}[!] 无法自动安装 $pkg，请手动安装后重试${RESET}"
            exit 1
        fi
    fi
}

check_dependency curl curl
check_dependency git git

# 创建目录
mkdir -p "$DEPLOY_DIR"
mkdir -p "$SCRIPTS_DIR"

# 下载文件函数
download_file() {
    local remote_path="$1"
    local local_path="$2"
    local filename=$(basename "$local_path")

    echo -e "${BLUE}[*] 正在下载 $filename ...${RESET}"
    if curl -fsSL -o "$local_path" "$RAW_URL/$remote_path"; then
        echo -e "${GREEN}[✓] $filename 下载成功${RESET}"
        chmod +x "$local_path"
    else
        echo -e "${YELLOW}[!] $filename 下载失败${RESET}"
        return 1
    fi
}

# 下载主脚本（新路径：scripts/linux-deploy.sh）
download_file "scripts/linux-deploy.sh" "$DEPLOY_DIR/linux-deploy.sh"

# 下载子脚本（新路径：scripts/ 目录下）
download_file "scripts/check_nas.sh" "$SCRIPTS_DIR/check_nas.sh"
download_file "scripts/sync_hosts.sh" "$SCRIPTS_DIR/sync_hosts.sh"

# 下载 packages.txt（新路径：scripts/packages.txt）
if curl -fsSL -o "$DEPLOY_DIR/packages.txt" "$RAW_URL/scripts/packages.txt" 2>/dev/null; then
    echo -e "${GREEN}[✓] packages.txt 下载成功${RESET}"
else
    echo -e "${YELLOW}[!] 未找到 packages.txt，跳过${RESET}"
fi

# 执行主部署脚本
echo
echo -e "${BLUE}[*] 开始执行部署...${RESET}"
cd "$DEPLOY_DIR"
bash "$DEPLOY_DIR/linux-deploy.sh"

echo
echo -e "${GREEN}=================================${RESET}"
echo -e "${GREEN}  在线部署完成！${RESET}"
echo -e "${GREEN}=================================${RESET}"
