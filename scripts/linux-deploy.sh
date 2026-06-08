#!/bin/bash

set -e

GREEN='\033[01;32m'
BLUE='\033[01;34m'
YELLOW='\033[01;33m'
CYAN='\033[01;36m'
RESET='\033[00m'

# 脚本所在目录（兼容本地执行和在线下载执行）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==================== 基础功能 ====================

setup_sources() {
    if [ -f /etc/debian_version ]; then
        if ! grep -q "mirrors.aliyun.com" /etc/apt/sources.list 2>/dev/null; then
            echo -e "${BLUE}[*] 检测到 Debian 系统，正在备份并切换为阿里云镜像源...${RESET}"
            sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%Y%m%d)
            sudo sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
            sudo sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
            sudo apt update -y
        else
            echo -e "${YELLOW}[!] APT 源已经是阿里云，跳过换源${RESET}"
        fi
    elif [ -f /etc/redhat-release ]; then
        if ! grep -q "mirrors.aliyun.com" /etc/yum.repos.d/*.repo 2>/dev/null; then
            echo -e "${BLUE}[*] 检测到 RedHat 系列系统，正在配置阿里云 YUM 源...${RESET}"
            sudo mkdir -p /etc/yum.repos.d/bak
            sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null || true
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo || \
            curl -o /etc/yum.repos.d/Rocky-Base.repo https://mirrors.aliyun.com/repo/rocky-8.repo
            sudo yum makecache
        else
            echo -e "${YELLOW}[!] YUM 源已经是阿里云，跳过换源${RESET}"
        fi
    fi
}

install_pkg() {
    local pkg="$1"
    if command -v "$pkg" &> /dev/null; then
        echo -e "${YELLOW}[!] $pkg 已存在，跳过安装${RESET}"
        return 0
    fi
    echo -e "${BLUE}[*] 正在安装 $pkg...${RESET}"
    if [ -f /etc/debian_version ]; then
        sudo apt install -y "$pkg" && return 0
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y "$pkg" && return 0
    fi
    return 1
}

setup_git() {
    echo -e "${BLUE}[*] 配置 Git 核心信息...${RESET}"
    git config --global user.name "Jacob"
    git config --global user.email "jacob_ng@163.com"
    git config --global init.defaultBranch main
}

setup_bashrc_base() {
    if [ -f ~/.bashrc ]; then
        [ ! -f ~/.bashrc.bak_origin ] && cp ~/.bashrc ~/.bashrc.bak_origin
        sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/' ~/.bashrc
    fi
}

# 统一写入 ~/.bashrc 的自定义脚本区块
append_custom_to_bashrc() {
    local tag="$1"
    local cmd="$2"
    local marker="# $tag"

    if [ -f ~/.bashrc ] && grep -Fxq "$cmd" ~/.bashrc 2>/dev/null; then
        echo -e "${YELLOW}[!] $tag 已经配置过，跳过${RESET}"
        return
    fi

    # 确保区块头存在
    if ! grep -Fxq "# 自定义脚本" ~/.bashrc 2>/dev/null; then
        echo -e "\n# 自定义脚本" >> ~/.bashrc
    fi

    echo "$marker" >> ~/.bashrc
    echo "$cmd" >> ~/.bashrc
    echo -e "${GREEN}[✓] 已成功添加: $tag${RESET}"
}

# ==================== 交互式菜单 (支持方向键+空格) ====================

# 选项定义: 索引|类别|名称
# 类别: 1=软件安装, 2=快捷方式
OPTIONS=(
    "0|1|安装 nano"
    "1|1|安装 fastfetch"
    "2|1|安装 curl"
    "3|1|安装 git"
    "4|2|登录时自动运行 fastfetch"
    "5|2|登录时自动挂载 NAS"
    "6|2|登录时自动同步 hosts"
    "7|2|登录时自动扫描 SSH 设备"
    "8|2|启用 ll 快捷命令"
    "9|2|添加 lan 快捷别名"
)

# 选中状态数组
declare -a CHECKED
declare -i CURSOR=0

get_cat_name() {
    case "$1" in
        1) echo "【软件安装】" ;;
        2) echo "【快捷方式 / 自启动】" ;;
    esac
}

# 读取单个按键 (支持方向键)
read_key() {
    local key key2 key3
    IFS= read -rs -n1 key

    # 方向键 ESC 序列
    if [[ "$key" == $'\x1b' ]]; then
        if IFS= read -rs -t 0.05 -n1 key2; then
            if [[ "$key2" == "[" ]]; then
                if IFS= read -rs -t 0.05 -n1 key3; then
                    case "$key3" in
                        A) echo "UP" ;;
                        B) echo "DOWN" ;;
                        *) echo "UNKNOWN" ;;
                    esac
                    return
                fi
            fi
        fi
        echo "ESC"
        return
    fi

    if [[ "$key" == " " ]]; then
        echo "SPACE"
        return
    fi

    if [[ "$key" == $'\n' ]] || [[ "$key" == $'\r' ]] || [[ "$key" == "" ]]; then
        echo "ENTER"
        return
    fi

    if [[ "$key" == "q" ]] || [[ "$key" == "Q" ]]; then
        echo "QUIT"
        return
    fi

    echo "UNKNOWN"
}

render_menu() {
    tput cup 0 0

    echo -e "${YELLOW}=================================${RESET}"
    echo -e "${YELLOW}      Jacob 设备自动化部署脚本     ${RESET}"
    echo -e "${YELLOW}=================================${RESET}"
    echo -e "${BLUE}↑↓ 移动光标  |  空格 切换选中  |  Enter 确认部署  |  q 退出${RESET}"
    echo

    local last_cat=""
    for i in "${!OPTIONS[@]}"; do
        local opt="${OPTIONS[$i]}"
        local cat_id="${opt#*|}"
        cat_id="${cat_id%%|*}"
        local name="${opt#*|*|}"

        if [ "$cat_id" != "$last_cat" ]; then
            echo -e "${CYAN}>>> $(get_cat_name "$cat_id")${RESET}"
            last_cat="$cat_id"
        fi

        local marker="[ ]"
        [ "${CHECKED[$i]:-0}" = "1" ] && marker="[${GREEN}✓${RESET}]"

        if [ "$i" -eq "$CURSOR" ]; then
            echo -e "  ${marker}${YELLOW} > $name${RESET}"
        else
            echo -e "  ${marker}   $name${RESET}"
        fi
    done

    echo
    echo -e "${BLUE}---------------------------------${RESET}"
}

show_interactive_menu() {
    for i in "${!OPTIONS[@]}"; do CHECKED[$i]=0; done
    CURSOR=0

    tput smcup
    tput civis

    clear
    render_menu

    while true; do
        local key
        key=$(read_key)

        case "$key" in
            "UP")
                if [ "$CURSOR" -gt 0 ]; then
                    CURSOR=$((CURSOR - 1))
                    render_menu
                fi
                ;;
            "DOWN")
                if [ "$CURSOR" -lt $((${#OPTIONS[@]} - 1)) ]; then
                    CURSOR=$((CURSOR + 1))
                    render_menu
                fi
                ;;
            "SPACE")
                if [ "${CHECKED[$CURSOR]:-0}" = "1" ]; then
                    CHECKED[$CURSOR]=0
                else
                    CHECKED[$CURSOR]=1
                fi
                render_menu
                ;;
            "ENTER")
                break
                ;;
            "QUIT")
                tput rmcup
                tput cnorm
                echo -e "${YELLOW}[!] 已取消部署${RESET}"
                exit 0
                ;;
            "UNKNOWN")
                ;;
        esac
    done

    tput rmcup
    tput cnorm
}

# ==================== 执行部署 ====================

run_deploy() {
    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}        开始执行部署...           ${RESET}"
    echo -e "${GREEN}=================================${RESET}"
    echo

    # --- 软件安装 ---
    [ "${CHECKED[0]:-0}" = "1" ] && install_pkg nano
    [ "${CHECKED[1]:-0}" = "1" ] && install_pkg fastfetch
    [ "${CHECKED[2]:-0}" = "1" ] && install_pkg curl
    [ "${CHECKED[3]:-0}" = "1" ] && install_pkg git

    # --- 快捷方式 ---
    [ "${CHECKED[4]:-0}" = "1" ] && append_custom_to_bashrc "显示系统信息" \
        "command -v fastfetch >/dev/null && fastfetch || command -v neofetch >/dev/null && neofetch"
    [ "${CHECKED[5]:-0}" = "1" ] && append_custom_to_bashrc "挂载nas" \
        "[ -x ~/scripts/check_nas.sh ] && sudo ~/scripts/check_nas.sh -q"
    [ "${CHECKED[6]:-0}" = "1" ] && append_custom_to_bashrc "同步hosts" \
        "[ -x ~/scripts/sync_hosts.sh ] && sudo ~/scripts/sync_hosts.sh -q"
    [ "${CHECKED[7]:-0}" = "1" ] && append_custom_to_bashrc "监测可ssh设备" \
        "[ -x ~/scripts/lan_scan.sh ] && ~/scripts/lan_scan.sh"
    [ "${CHECKED[8]:-0}" = "1" ] && append_custom_to_bashrc "ll快捷命令" \
        "alias ll='ls -l'"
    [ "${CHECKED[9]:-0}" = "1" ] && append_custom_to_bashrc "lan快捷别名" \
        "alias lan='~/scripts/lan_scan.sh'"

    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}  部署完成！请执行 'source ~/.bashrc' ${RESET}"
    echo -e "${GREEN}=================================${RESET}"
}

# ==================== 入口 ====================

show_menu() {
    clear
    echo -e "${YELLOW}=================================${RESET}"
    echo -e "${YELLOW}      Jacob 设备自动化部署脚本     ${RESET}"
    echo -e "${YELLOW}=================================${RESET}"

    setup_sources
    setup_git
    setup_bashrc_base

    show_interactive_menu
    run_deploy
}

show_menu
