#!/bin/bash

set -e

# ============================================
# Jacob Linux 一键在线部署脚本
# 用法:
#   curl -fsSL "https://gitee.com/jacob_ng/linux-deploy/raw/main/install.sh" | bash
#   curl -fsSL "https://gitee.com/jacob_ng/linux-deploy/raw/dev/install.sh" | bash -s dev
#   curl -fsSL "https://gitee.com/jacob_ng/linux-deploy/raw/main/install.sh" | bash -s -- --scripts
#
#   分支优先级: 命令行参数 > 环境变量 GITEE_BRANCH > 默认 main
# ============================================

GREEN='\033[01;32m'
BLUE='\033[01;34m'
YELLOW='\033[01;33m'
RESET='\033[00m'

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

# Gitee 仓库配置
GITEE_OWNER="jacob_ng"
GITEE_REPO="linux-deploy"
GITHUB_OWNER="JacobNg1"

# 解析参数：位置参数为分支名，--scripts 仅更新脚本
SCRIPTS_ONLY=0
GITEE_BRANCH="${GITEE_BRANCH:-main}"
for arg in "$@"; do
    case "$arg" in
        --scripts)
            SCRIPTS_ONLY=1
            ;;
        --help|-h)
            echo "用法: bash install.sh [分支名] [--scripts]"
            echo "  --scripts  仅下载并更新脚本，不执行部署"
            exit 0
            ;;
        --*)
            echo -e "${YELLOW}[!] 未知参数: $arg${RESET}"
            exit 1
            ;;
        *)
            GITEE_BRANCH="$arg"
            ;;
    esac
done

DEPLOY_SHELL="$(ps -p "$PPID" -o comm= 2>/dev/null | tr -d ' ')"
DEPLOY_SHELL="${DEPLOY_SHELL#-}"
case "$DEPLOY_SHELL" in
    bash|zsh) export DEPLOY_SHELL ;;
    *) unset DEPLOY_SHELL ;;
esac

# 本地部署目录
DEPLOY_DIR="$HOME/linux-deploy"
SCRIPTS_DIR="$HOME/scripts"

# 检测是否在 ~ 目录下执行
if [ "$PWD" != "$HOME" ]; then
    echo -e "${YELLOW}[!] 警告: 当前目录是 $PWD，建议在家目录 (~) 下执行此脚本。${RESET}"
    read -p "是否仍要继续? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}[*] 已取消执行。请执行: cd ~ 后重新运行脚本。${RESET}"
        exit 0
    fi
    echo -e "${YELLOW}[!] 用户确认不在 ~ 目录下继续执行。${RESET}"
    echo
fi


echo -e "${BLUE}[*] Jacob Linux 一键在线部署脚本${RESET}"
echo -e "${BLUE}[*] 仓库: $GITEE_OWNER/$GITEE_REPO${RESET}"
echo -e "${BLUE}[*] 分支: $GITEE_BRANCH${RESET}"
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

# 创建目录
mkdir -p "$DEPLOY_DIR"
mkdir -p "$SCRIPTS_DIR"

# 使用 raw URL 直接下载文件（无需 Token）
download_file() {
    local file_path="$1"
    local local_path="$2"
    local filename=$(basename "$local_path")

    local gitee_url="https://gitee.com/$GITEE_OWNER/$GITEE_REPO/raw/$GITEE_BRANCH/$file_path"
    local gitee_archive_url="https://gitee.com/$GITEE_OWNER/$GITEE_REPO/repository/archive/$GITEE_BRANCH.tar.gz"
    local github_url="https://raw.githubusercontent.com/$GITHUB_OWNER/$GITEE_REPO/$GITEE_BRANCH/$file_path"

    echo -e "${BLUE}[*] 正在下载 $filename ...${RESET}"

    if curl -fsSL "$gitee_url" -o "$local_path"; then
        echo -e "${GREEN}[✓] $filename 下载成功${RESET}"
        chmod +x "$local_path"
    elif curl -fsSL "$gitee_archive_url" |
         tar -xOzf - --wildcards "*/$file_path" > "$local_path"; then
        echo -e "${YELLOW}[!] Gitee Raw 下载失败，已自动切换 Gitee 压缩包${RESET}"
        echo -e "${GREEN}[✓] $filename 下载成功${RESET}"
        chmod +x "$local_path"
    elif curl -fsSL "$github_url" -o "$local_path"; then
        echo -e "${YELLOW}[!] Gitee 下载失败，已自动切换 GitHub 镜像${RESET}"
        echo -e "${GREEN}[✓] $filename 下载成功${RESET}"
        chmod +x "$local_path"
    else
        echo -e "${YELLOW}[!] $filename 从 Gitee 和 GitHub 下载均失败${RESET}"
        rm -f "$local_path"
        return 1
    fi
}

# 下载主脚本
download_file "scripts/linux-deploy.sh" "$DEPLOY_DIR/linux-deploy.sh"

# 下载 packages.txt（软件列表）
download_file "scripts/packages.txt" "$DEPLOY_DIR/packages.txt" || true

# 下载子脚本
download_file "scripts/storage_scan.sh" "$SCRIPTS_DIR/storage_scan.sh"
download_file "scripts/sync_hosts.sh" "$SCRIPTS_DIR/sync_hosts.sh"
download_file "scripts/lan_scan.sh" "$SCRIPTS_DIR/lan_scan.sh"

if [ "$SCRIPTS_ONLY" -eq 1 ]; then
    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}  脚本更新完成，未执行部署。${RESET}"
    echo -e "${GREEN}=================================${RESET}"
    exit 0
fi

# 执行主部署脚本
echo
echo -e "${BLUE}[*] 开始执行部署...${RESET}"
cd "$DEPLOY_DIR"

# 检查是否为交互式终端
if [ -t 0 ]; then
    # 正常交互式执行
    bash "$DEPLOY_DIR/linux-deploy.sh"
else
    # stdin 被重定向（如管道），需要重新连接到终端
    echo -e "${YELLOW}[!] 检测到非交互式输入，尝试连接终端...${RESET}"
    if [ -e /dev/tty ]; then
        bash "$DEPLOY_DIR/linux-deploy.sh" < /dev/tty
    else
        echo -e "${YELLOW}[!] 无法连接终端，使用非交互模式${RESET}"
        bash "$DEPLOY_DIR/linux-deploy.sh"
    fi
fi

echo
echo -e "${GREEN}=================================${RESET}"
echo -e "${GREEN}  在线部署完成！${RESET}"
echo -e "${GREEN}=================================${RESET}"
