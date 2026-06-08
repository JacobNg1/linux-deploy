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

# ==================== 菜单交互 ====================

# 状态数组：索引 -> 选中状态(1/0)
declare -a CHECKED

print_category() {
    echo -e "\n${CYAN}>>> $1${RESET}"
}

print_option() {
    local idx="$1"
    local name="$2"
    local mark="${CHECKED[$idx]:-0}"
    if [ "$mark" = "1" ]; then
        echo -e "  [${GREEN}✓${RESET}] $idx. $name"
    else
        echo -e "  [ ] $idx. $name"
    fi
}

toggle_option() {
    local idx="$1"
    if [ "${CHECKED[$idx]:-0}" = "1" ]; then
        CHECKED[$idx]=0
    else
        CHECKED[$idx]=1
    fi
}

# ==================== 主菜单 ====================

show_menu() {
    clear
    echo -e "${YELLOW}=================================${RESET}"
    echo -e "${YELLOW}      Jacob 设备自动化部署脚本     ${RESET}"
    echo -e "${YELLOW}=================================${RESET}"

    # 基础环境（自动执行，不询问）
    setup_sources
    setup_git
    setup_bashrc_base

    # 初始化所有选项为未选中
    for i in {1..9}; do CHECKED[$i]=0; done

    while true; do
        clear
        echo -e "${YELLOW}=================================${RESET}"
        echo -e "${YELLOW}      Jacob 设备自动化部署脚本     ${RESET}"
        echo -e "${YELLOW}=================================${RESET}"
        echo -e "${BLUE}请输入编号切换选项，输入 0 开始部署:${RESET}\n"

        print_category "【软件安装】"
        print_option 1 "安装 nano"
        print_option 2 "安装 fastfetch (neofetch替代品)"
        print_option 3 "安装 curl"
        print_option 4 "安装 git"

        print_category "【快捷方式 / 自启动】"
        print_option 5 "登录时自动运行 fastfetch"
        print_option 6 "登录时自动挂载 NAS"
        print_option 7 "登录时自动同步 hosts"
        print_option 8 "登录时自动扫描 SSH 设备"

        print_category "【其他配置】"
        print_option 9 "批量安装 packages.txt 中的软件"

        echo
        echo -e "${BLUE}---------------------------------${RESET}"
        echo -e "${BLUE}提示: 输入数字切换选中，输入 0 确认部署${RESET}"
        read -p "> " choice

        case "$choice" in
            1|2|3|4|5|6|7|8|9)
                toggle_option "$choice"
                ;;
            0)
                break
                ;;
            *)
                echo -e "${YELLOW}[!] 无效输入${RESET}"
                sleep 0.5
                ;;
        esac
    done

    # ==================== 执行部署 ====================
    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}        开始执行部署...           ${RESET}"
    echo -e "${GREEN}=================================${RESET}"
    echo

    # --- 软件安装 ---
    if [ "${CHECKED[1]}" = "1" ]; then install_pkg nano; fi
    if [ "${CHECKED[2]}" = "1" ]; then install_pkg fastfetch; fi
    if [ "${CHECKED[3]}" = "1" ]; then install_pkg curl; fi
    if [ "${CHECKED[4]}" = "1" ]; then install_pkg git; fi

    # --- 快捷方式 ---
    if [ "${CHECKED[5]}" = "1" ]; then
        append_to_bashrc "登录显示系统信息" "command -v fastfetch >/dev/null && fastfetch || command -v neofetch >/dev/null && neofetch"
    fi
    if [ "${CHECKED[6]}" = "1" ]; then
        append_to_bashrc "登录自动挂载 NAS" "[ -x ~/scripts/check_nas.sh ] && ~/scripts/check_nas.sh -q"
    fi
    if [ "${CHECKED[7]}" = "1" ]; then
        append_to_bashrc "登录自动同步 hosts" "[ -x ~/scripts/sync_hosts.sh ] && ~/scripts/sync_hosts.sh -q"
    fi
    if [ "${CHECKED[8]}" = "1" ]; then
        append_to_bashrc "登录自动扫描 SSH 设备" "[ -x ~/scripts/lan_scan.sh ] && ~/scripts/lan_scan.sh"
    fi

    # --- 其他 ---
    if [ "${CHECKED[9]}" = "1" ]; then
        install_required_packages
    fi

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

show_menu
