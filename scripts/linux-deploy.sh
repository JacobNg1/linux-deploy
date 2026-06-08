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
        sed -i "s/#alias ll='ls -l'/alias ll='ls -l'/" ~/.bashrc
        sed -i "s/#alias la='ls -A'/alias la='ls -A'/" ~/.bashrc
        sed -i "s/#alias l='ls -CF'/alias l='ls -CF'/" ~/.bashrc
    fi
}

append_to_bashrc() {
    local comment="$1"
    local cmd="$2"
    if [ -f ~/.bashrc ] && ! grep -f <(echo "$cmd") ~/.bashrc >/dev/null 2>&1; then
        echo -e "\n# $comment\n$cmd" >> ~/.bashrc
        echo -e "${GREEN}[✓] 已成功添加: $comment${RESET}"
    else
        echo -e "${YELLOW}[!] $comment 已经配置过，跳过${RESET}"
    fi
}

# ==================== 交互式菜单 (支持方向键+空格) ====================

# 选项定义: 索引|类别|名称|执行函数
# 类别: 1=软件安装, 2=快捷方式, 3=其他
OPTIONS=(
    "1|1|安装 nano"
    "2|1|安装 fastfetch"
    "3|1|安装 curl"
    "4|1|安装 git"
    "5|2|登录时自动运行 fastfetch"
    "6|2|登录时自动挂载 NAS"
    "7|2|登录时自动同步 hosts"
    "8|2|登录时自动扫描 SSH 设备"
    "9|3|批量安装 packages.txt"
)

# 选中状态数组
declare -a CHECKED
declare -i CURSOR=0

get_option_name() {
    echo "${OPTIONS[$1]#*|*|}"
}

get_option_cat() {
    echo "${OPTIONS[$1]#*|}"
    echo "${OPTIONS[$1]%%|*}"
}

get_cat_name() {
    case "$1" in
        1) echo "【软件安装】" ;;
        2) echo "【快捷方式 / 自启动】" ;;
        3) echo "【其他配置】" ;;
    esac
}

# 读取单个按键 (支持方向键)
read_key() {
    IFS= read -rs -n1 key
    if [[ "$key" == $'\x1b' ]]; then
        IFS= read -rs -n1 key2
        if [[ "$key2" == "[" ]]; then
            IFS= read -rs -n1 key3
            case "$key3" in
                A) echo "UP" ;;
                B) echo "DOWN" ;;
                *) echo "UNKNOWN" ;;
            esac
        else
            echo "ESC"
        fi
    elif [[ "$key" == " " ]]; then
        echo "SPACE"
    elif [[ "$key" == $'\n' ]] || [[ "$key" == $'\r' ]]; then
        echo "ENTER"
    elif [[ "$key" == "q" ]] || [[ "$key" == "Q" ]]; then
        echo "QUIT"
    else
        echo "$key"
    fi
}

render_menu() {
    # 移动光标到顶部（不需要 clear，避免闪烁）
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
    # 初始化
    for i in "${!OPTIONS[@]}"; do CHECKED[$i]=0; done
    CURSOR=0

    # 保存屏幕并隐藏光标
    tput smcup
    tput civis

    # 首次渲染
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
        esac
    done

    # 恢复屏幕并显示光标
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
    [ "${CHECKED[4]:-0}" = "1" ] && append_to_bashrc "登录显示系统信息" \
        "command -v fastfetch >/dev/null && fastfetch || command -v neofetch >/dev/null && neofetch"
    [ "${CHECKED[5]:-0}" = "1" ] && append_to_bashrc "登录自动挂载 NAS" \
        "[ -x ~/scripts/check_nas.sh ] && ~/scripts/check_nas.sh -q"
    [ "${CHECKED[6]:-0}" = "1" ] && append_to_bashrc "登录自动同步 hosts" \
        "[ -x ~/scripts/sync_hosts.sh ] && ~/scripts/sync_hosts.sh -q"
    [ "${CHECKED[7]:-0}" = "1" ] && append_to_bashrc "登录自动扫描 SSH 设备" \
        "[ -x ~/scripts/lan_scan.sh ] && ~/scripts/lan_scan.sh"

    # --- 其他 ---
    [ "${CHECKED[8]:-0}" = "1" ] && install_required_packages

    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}  部署完成！请执行 'source ~/.bashrc' ${RESET}"
    echo -e "${GREEN}=================================${RESET}"
}

# 读取文件批量安装（packages.txt）
install_required_packages() {
    local pkg_file="$SCRIPT_DIR/packages.txt"
    if [ ! -f "$pkg_file" ]; then
        echo -e "${YELLOW}[!] 未找到 packages.txt ，跳过批量安装${RESET}"
        return
    fi

    local failed_pkgs=()

    echo -e "${BLUE}[*] 开始从 packages.txt 读取并检查必备包...${RESET}"
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
        if ! install_pkg "$pkg"; then
            failed_pkgs+=("$pkg")
        fi
    done < "$pkg_file"

    if [ ${#failed_pkgs[@]} -gt 0 ]; then
        echo
        echo -e "${YELLOW}=================================${RESET}"
        echo -e "${YELLOW}  以下软件包安装失败，请手动处理:${RESET}"
        for fp in "${failed_pkgs[@]}"; do
            echo -e "${YELLOW}    - $fp${RESET}"
        done
        echo -e "${YELLOW}=================================${RESET}"
    fi
}

# ==================== 入口 ====================

show_menu() {
    clear
    echo -e "${YELLOW}=================================${RESET}"
    echo -e "${YELLOW}      Jacob 设备自动化部署脚本     ${RESET}"
    echo -e "${YELLOW}=================================${RESET}"

    # 基础环境（自动执行，不询问）
    setup_sources
    setup_git
    setup_bashrc_base

    # 交互式菜单
    show_interactive_menu

    # 执行部署
    run_deploy
}

show_menu
