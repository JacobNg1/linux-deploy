#!/bin/bash

set -e

# ============================================
# Jacob Linux 一键在线部署脚本
# 用法:
#   1. 先设置环境变量:
#      export GITEE_API_TOKEN=你的token
#      export GITEE_BRANCH=main        # 可选，默认 main
#
#   2. 然后执行:
#      curl -H "Authorization: token $GITEE_API_TOKEN" -fsSL \
#        "https://gitee.com/api/v5/repos/jacob_ng/linux-deploy/contents/install.sh?ref=${GITEE_BRANCH:-main}" \
#        | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content']).decode('utf-8'))" \
#        > /tmp/linux-deploy-install.sh && bash /tmp/linux-deploy-install.sh
#
#   注意: 必须使用 "先下载到文件再执行" 的方式，
#         直接 "| bash" 会导致 read 无法获取键盘输入
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
GITEE_BRANCH="${GITEE_BRANCH:-main}"

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

# 检查 GITEE_API_TOKEN 是否设置
if [ -z "$GITEE_API_TOKEN" ]; then
    echo -e "${YELLOW}[!] 错误: 未设置 GITEE_API_TOKEN 环境变量${RESET}"
    echo -e "${BLUE}[*] 请先执行以下命令设置 Token，然后再运行本脚本:${RESET}"
    echo -e "${BLUE}    export GITEE_API_TOKEN=aee0c6d82280dd56de52b4eab884cdfd${RESET}"
    exit 1
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
check_dependency python3 python3

# 创建目录
mkdir -p "$DEPLOY_DIR"
mkdir -p "$SCRIPTS_DIR"

# 使用 Gitee API 下载文件函数
download_from_gitee_api() {
    local file_path="$1"
    local local_path="$2"
    local filename=$(basename "$local_path")

    local api_url="https://gitee.com/api/v5/repos/$GITEE_OWNER/$GITEE_REPO/contents/$file_path?ref=$GITEE_BRANCH"

    echo -e "${BLUE}[*] 正在下载 $filename ...${RESET}"
    echo -e "${BLUE}    URL: $api_url${RESET}"

    # 使用 API + Token 获取文件内容（base64 编码）
    local response
    response=$(curl -sSL -H "Authorization: token $GITEE_API_TOKEN" "$api_url" 2>&1)
    local curl_exit_code=$?

    if [ $curl_exit_code -ne 0 ]; then
        echo -e "${YELLOW}[!] curl 请求失败 (exit code: $curl_exit_code)${RESET}"
        echo -e "${YELLOW}    响应: $response${RESET}"
        return 1
    fi

    if [ -z "$response" ]; then
        echo -e "${YELLOW}[!] $filename 下载失败: 空响应${RESET}"
        return 1
    fi

    if echo "$response" | grep -q '"message"'; then
        echo -e "${YELLOW}[!] $filename 下载失败 (API 错误)${RESET}"
        echo -e "${YELLOW}    响应: $response${RESET}"
        return 1
    fi

    # 解析 JSON 并解码 base64
    echo "$response" | python3 -c "
import sys, json, base64
try:
    data = json.load(sys.stdin)
    content = base64.b64decode(data['content']).decode('utf-8')
    print(content, end='')
except Exception as e:
    sys.stderr.write(f'Error: {e}\n')
    sys.exit(1)
" > "$local_path"

    if [ $? -eq 0 ] && [ -s "$local_path" ]; then
        echo -e "${GREEN}[✓] $filename 下载成功${RESET}"
        chmod +x "$local_path"
    else
        echo -e "${YELLOW}[!] $filename 解码失败${RESET}"
        rm -f "$local_path"
        return 1
    fi
}

# 下载主脚本
download_from_gitee_api "scripts/linux-deploy.sh" "$DEPLOY_DIR/linux-deploy.sh"

# 下载子脚本
download_from_gitee_api "scripts/check_nas.sh" "$SCRIPTS_DIR/check_nas.sh"
download_from_gitee_api "scripts/sync_hosts.sh" "$SCRIPTS_DIR/sync_hosts.sh"
download_from_gitee_api "scripts/lan_scan.sh" "$SCRIPTS_DIR/lan_scan.sh"

# 执行主部署脚本
echo
echo -e "${BLUE}[*] 开始执行部署...${RESET}"
cd "$DEPLOY_DIR"
bash "$DEPLOY_DIR/linux-deploy.sh"

echo
echo -e "${GREEN}=================================${RESET}"
echo -e "${GREEN}  在线部署完成！${RESET}"
echo -e "${GREEN}=================================${RESET}"
