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

    # 清理所有旧格式的自定义内容（包括各种历史版本）
    if [ -f ~/.bashrc ]; then
        # 删除旧的 neofetch 相关内容
        sed -i '/command -v neofetch/d' ~/.bashrc
        sed -i '/# 显示系统信息/d' ~/.bashrc
        sed -i '/# 登录显示系统信息/d' ~/.bashrc

        # 删除旧的单条注释+命令格式
        sed -i '/# 挂载nas/d' ~/.bashrc
        sed -i '/# 同步hosts/d' ~/.bashrc
        sed -i '/# 监测可ssh设备/d' ~/.bashrc
        sed -i '/# ll快捷命令/d' ~/.bashrc
        sed -i '/# lan快捷别名/d' ~/.bashrc
        sed -i '/# la快捷别名/d' ~/.bashrc
        sed -i '/# l快捷别名/d' ~/.bashrc
        sed -i '/# 登录自动挂载 NAS/d' ~/.bashrc
        sed -i '/# 登录自动同步 hosts/d' ~/.bashrc
        sed -i '/# 登录自动扫描 SSH 设备/d' ~/.bashrc
        sed -i '/# 自定义脚本/d' ~/.bashrc
        sed -i '/# linux-deploy 自定义脚本/d' ~/.bashrc

        # 删除旧命令行
        sed -i '/\[ -x ~\/scripts\/check_nas.sh \] && ~/d' ~/.bashrc
        sed -i '/\[ -x ~\/scripts\/sync_hosts.sh \] && ~/d' ~/.bashrc
        sed -i '/\[ -x ~\/scripts\/lan_scan.sh \] && ~/d' ~/.bashrc
        sed -i '/alias lan=.*/d' ~/.bashrc

        # 删除整个 linux-deploy 区块（如果有）
        if grep -q "# linux-deploy-start" ~/.bashrc 2>/dev/null; then
            sed -i '/# linux-deploy-start/,/# linux-deploy-end/d' ~/.bashrc
        fi
    fi
}

# 生成并写入 ~/.bashrc 的 linux-deploy 区块
write_linux_deploy_block() {
    local scripts_section=""
    local aliases_section=""

    # --- 脚本执行区 ---
    if [ "${CHECKED[$((PKG_COUNT + 0))]:-0}" = "1" ]; then
        scripts_section+="command -v fastfetch >/dev/null && fastfetch\n"
        echo -e "${GREEN}[✓] 已添加: 登录显示系统信息${RESET}"
    fi
    if [ "${CHECKED[$((PKG_COUNT + 1))]:-0}" = "1" ]; then
        scripts_section+="[ -x ~/scripts/check_nas.sh ] && sudo ~/scripts/check_nas.sh -q\n"
        echo -e "${GREEN}[✓] 已添加: 登录自动挂载 NAS${RESET}"
    fi
    if [ "${CHECKED[$((PKG_COUNT + 2))]:-0}" = "1" ]; then
        scripts_section+="[ -x ~/scripts/sync_hosts.sh ] && sudo ~/scripts/sync_hosts.sh -q\n"
        echo -e "${GREEN}[✓] 已添加: 登录自动同步 hosts${RESET}"
    fi
    if [ "${CHECKED[$((PKG_COUNT + 3))]:-0}" = "1" ]; then
        scripts_section+="[ -x ~/scripts/lan_scan.sh ] && sudo ~/scripts/lan_scan.sh\n"
        echo -e "${GREEN}[✓] 已添加: 登录自动扫描 SSH 设备${RESET}"
    fi

    # --- 快捷别名区 ---
    if [ "${CHECKED[$((PKG_COUNT + 4))]:-0}" = "1" ]; then
        aliases_section+="alias ll='ls -alF'\n"
        aliases_section+="alias la='ls -A'\n"
        aliases_section+="alias l='ls -CF'\n"
        echo -e "${GREEN}[✓] 已添加: ll、la、l 快捷别名${RESET}"
    fi
    if [ "${CHECKED[$((PKG_COUNT + 5))]:-0}" = "1" ]; then
        aliases_section+="alias lan='sudo ~/scripts/lan_scan.sh'\n"
        echo -e "${GREEN}[✓] 已添加: lan 快捷别名${RESET}"
    fi
    if [ "${CHECKED[$((PKG_COUNT + 6))]:-0}" = "1" ]; then
        aliases_section+="# 代理\nPROXY_NODE=http://tc:7890\n"
        aliases_section+="alias pxon='export http_proxy=\"\$PROXY_NODE\"; export https_proxy=\"\$PROXY_NODE\"; echo \"Proxy On: \$PROXY_NODE\"'\n"
        aliases_section+="alias pxoff='unset http_proxy; unset https_proxy; echo \"Proxy Off\"'\n"
        aliases_section+="alias pxtest='curl -I https://www.google.com'\n"
        echo -e "${GREEN}[✓] 已添加: 代理开关别名${RESET}"
    fi

    # 如果没有任何内容，不写入区块
    if [ -z "$scripts_section" ] && [ -z "$aliases_section" ]; then
        echo -e "${YELLOW}[!] 未选择任何快捷方式，跳过写入 ~/.bashrc${RESET}"
        return
    fi

    # 构建区块内容
    local block="\n# linux-deploy-start\n"

    if [ -n "$scripts_section" ]; then
        block+="# --- 脚本自启动 ---\n${scripts_section}"
    fi

    if [ -n "$aliases_section" ]; then
        block+="# --- 快捷别名 ---\n${aliases_section}"
    fi

    block+="# linux-deploy-end\n"

    # 写入 ~/.bashrc
    printf "%b" "$block" >> ~/.bashrc
    echo -e "${GREEN}[✓] 已更新 ~/.bashrc 的 linux-deploy 区块${RESET}"
}

# ==================== 交互式菜单 (支持方向键+空格) ====================

# 从 packages.txt 动态加载软件安装选项
load_package_options() {
    local pkg_file="$SCRIPT_DIR/packages.txt"
    local idx=0
    local pkg
    PKG_COUNT=0
    [ ! -f "$pkg_file" ] && return
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
        OPTIONS+=("$idx|1|安装 $pkg")
        CHECKED+=(1)
        idx=$((idx + 1))
    done < "$pkg_file"
    PKG_COUNT=$idx
}

# 固定选项（脚本自启动 + 快捷别名）
FIXED_OPTIONS=(
    "0|2|登录时自动运行 fastfetch"
    "1|2|登录时自动挂载 NAS"
    "2|2|登录时自动同步 hosts"
    "3|2|登录时自动扫描 SSH 设备"
    "4|3|ll、la、l (ls 列表快捷别名)"
    "5|3|lan (扫描局域网 SSH 设备)"
    "6|3|pxon / pxoff / pxtest (代理开关)"
)

# 选中状态数组
declare -a OPTIONS
declare -a CHECKED
declare -i CURSOR=0

# 加载动态选项（在父 shell 中执行，直接操作 OPTIONS/CHECKED 数组）
load_package_options

# 追加固定选项（索引偏移 PKG_COUNT）
for i in "${!FIXED_OPTIONS[@]}"; do
    opt="${FIXED_OPTIONS[$i]}"
    name="${opt#*|*|}"
    cat_id="${opt#*|}"
    cat_id="${cat_id%%|*}"
    OPTIONS+=("$((PKG_COUNT + i))|${cat_id}|${name}")
    CHECKED+=(1)
done

get_cat_name() {
    case "$1" in
        1) echo "【软件安装】" ;;
        2) echo "【脚本自启动】" ;;
        3) echo "【快捷别名】" ;;
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
    # CHECKED 已在定义时默认全选
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

# ==================== 配置 sudoers 免密 ====================

setup_sudoers() {
    local sudoers_file="/etc/sudoers.d/linux_deploy"

    if [ -f "$sudoers_file" ]; then
        echo -e "${YELLOW}[!] sudoers 免密已配置，跳过${RESET}"
        return
    fi

    echo -e "${BLUE}[*] 正在配置 passwordless sudo（需输入一次密码）...${RESET}"

    sudo tee "$sudoers_file" > /dev/null <<EOF
$USER ALL=(ALL) NOPASSWD: $HOME/scripts/check_nas.sh
$USER ALL=(ALL) NOPASSWD: $HOME/scripts/sync_hosts.sh
$USER ALL=(ALL) NOPASSWD: $HOME/scripts/lan_scan.sh
EOF

    sudo chmod 440 "$sudoers_file"

    # 验证语法
    if sudo visudo -c -f "$sudoers_file" 2>/dev/null; then
        echo -e "${GREEN}[✓] sudoers 免密配置完成${RESET}"
    else
        echo -e "${YELLOW}[!] sudoers 语法错误，已删除${RESET}"
        sudo rm -f "$sudoers_file"
    fi
}

# ==================== 执行部署 ====================

run_deploy() {
    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}        开始执行部署...           ${RESET}"
    echo -e "${GREEN}=================================${RESET}"
    echo

    # --- 软件安装 (从 packages.txt 动态读取) ---
    local pkg_file="$SCRIPT_DIR/packages.txt"
    if [ -f "$pkg_file" ]; then
        local idx=0 pkg
        while IFS= read -r pkg || [ -n "$pkg" ]; do
            [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
            if [ "${CHECKED[$idx]:-0}" = "1" ]; then
                install_pkg "$pkg" || true
            fi
            idx=$((idx + 1))
        done < "$pkg_file"
    fi

    # --- 写入 ~/.bashrc 区块 ---
    write_linux_deploy_block

    # --- 配置 sudoers 免密 ---
    setup_sudoers

    echo
    echo -e "${GREEN}=================================${RESET}"
    echo -e "${GREEN}  部署完成！请执行 source ~/.bashrc ${RESET}"
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
