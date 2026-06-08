#!/bin/bash

set -e

GREEN='\033[01;32m'
BLUE='\033[01;34m'
YELLOW='\033[01;33m'
RESET='\033[00m'

# 脚本所在目录（兼容本地执行和在线下载执行）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 自动检测系统并配置换源（已换源则不重复操作）
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

# 读取文件批量安装（已安装的工具绝对不重复下载，失败自动跳过并报告）
install_required_packages() {
    local pkg_file="$SCRIPT_DIR/packages.txt"
    if [ ! -f "$pkg_file" ]; then
        echo -e "${YELLOW}[!] 未找到 packages.txt ，跳过批量安装${RESET}"
        return
    fi

    local failed_pkgs=()

    echo -e "${BLUE}[*] 开始从 packages.txt 读取并检查必备包...${RESET}"
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        # 忽略空行和注释
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue

        if ! command -v "$pkg" &> /dev/null; then
            echo -e "${BLUE}[*] 正在安装 $pkg...${RESET}"
            local install_ok=false
            if [ -f /etc/debian_version ]; then
                sudo apt install -y "$pkg" && install_ok=true
            elif [ -f /etc/redhat-release ]; then
                sudo yum install -y "$pkg" && install_ok=true
            fi

            if [ "$install_ok" = false ]; then
                echo -e "${YELLOW}[!] $pkg 安装失败，已跳过${RESET}"
                failed_pkgs+=("$pkg")
            fi
        else
            echo -e "${YELLOW}[!] $pkg 已存在，跳过安装${RESET}"
        fi
    done < "$pkg_file"

    # 报告安装失败列表
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

setup_git() {
    echo -e "${BLUE}[*] 配置 Git 核心信息...${RESET}"
    git config --global user.name "Jacob"
    git config --global user.email "jacob_ng@163.com"
    git config --global init.defaultBranch main
}

setup_bashrc_base() {
    if [ -f ~/.bashrc ]; then
        # 避免重复备份
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
        echo -e "${YELLOW}[!] 提示：$comment 已经配置过，跳过不再重复写入${RESET}"
    fi
}

show_menu() {
    clear
    echo -e "${YELLOW}=================================${RESET}"
    echo -e "${YELLOW}      Jacob 设备自动化部署脚本     ${RESET}"
    echo -e "${YELLOW}=================================${RESET}"

    setup_sources
    install_required_packages
    setup_git
    setup_bashrc_base

    echo -e "\n${BLUE}请选择需要启用的自定义功能 (y/n):${RESET}"

    read -p "1. 是否启用 [挂载NAS] 脚本? (y/n): " choice1
    if [[ "$choice1" =~ ^[Yy]$ ]]; then
        append_to_bashrc "挂载nas" "[ -x ~/scripts/check_nas.sh ] && ~/scripts/check_nas.sh -q"
    fi

    read -p "2. 是否启用 [同步hosts] 脚本? (y/n): " choice2
    if [[ "$choice2" =~ ^[Yy]$ ]]; then
        append_to_bashrc "同步hosts" "[ -x ~/scripts/sync_hosts.sh ] && ~/scripts/sync_hosts.sh -q"
    fi

    read -p "3. 是否启用 [监测可ssh设备] 脚本? (y/n): " choice3
    if [[ "$choice3" =~ ^[Yy]$ ]]; then
        append_to_bashrc "监测可ssh设备" "[ -x ~/scripts/lan_scan.sh ] && ~/scripts/lan_scan.sh"
    fi

    append_to_bashrc "显示系统信息" "command -v neofetch >/dev/null && neofetch"

    echo -e "\n${GREEN}=================================${RESET}"
    echo -e "${GREEN}  部署完成！请执行 'source ~/.bashrc' ${RESET}"
    echo -e "${GREEN}=================================${RESET}"
}

show_menu
