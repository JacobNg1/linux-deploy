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
        local distro_name="Debian"
        if [ -f /etc/os-release ]; then
            local name=$(grep "^NAME=" /etc/os-release | sed 's/NAME="\(.*\)"/\1/')
            if [[ "$name" == *Ubuntu* ]]; then
                distro_name="Ubuntu"
            fi
        fi

        local sources_files=()
        [ -f /etc/apt/sources.list ] && sources_files+=("/etc/apt/sources.list")
        for f in /etc/apt/sources.list.d/*.list; do
            [ -f "$f" ] && sources_files+=("$f")
        done

        if [ ${#sources_files[@]} -eq 0 ]; then
            echo -e "${YELLOW}[!] 未找到 APT 源配置文件，跳过换源${RESET}"
            return
        fi

        local need_update=0

        if [ "$distro_name" = "Ubuntu" ]; then
            if ! grep -q "universe" /etc/apt/sources.list 2>/dev/null; then
                echo -e "${BLUE}[*] 为 ${distro_name} 启用 universe/multiverse 仓库...${RESET}"
                [ ! -f /etc/apt/sources.list.bak ] && sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
                sudo sed -i '/^deb/s/ main$/ main universe multiverse/' /etc/apt/sources.list
                need_update=1
            fi
        fi

        if ! grep -q "mirrors.aliyun.com" /etc/apt/sources.list 2>/dev/null; then
            need_update=1
            echo -e "${BLUE}[*] 检测到 ${distro_name} 系统，正在备份并切换为阿里云镜像源...${RESET}"
            [ ! -f /etc/apt/sources.list.bak ] && sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
            if [ "$distro_name" = "Ubuntu" ]; then
                sudo sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list
                sudo sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list
            else
                sudo sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
                sudo sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
            fi
        elif ! grep -q "mirrors.aliyun.com" "${sources_files[@]}" 2>/dev/null; then
            need_update=1
            echo -e "${BLUE}[*] 检测到 ${distro_name} 系统，部分源非阿里云，正在切换...${RESET}"
            for f in "${sources_files[@]}"; do
                [ ! -f "${f}.bak" ] && sudo cp "$f" "${f}.bak"
                if [ "$distro_name" = "Ubuntu" ]; then
                    sudo sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' "$f"
                    sudo sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' "$f"
                else
                    sudo sed -i 's/deb.debian.org/mirrors.aliyun.com/g' "$f"
                    sudo sed -i 's/security.debian.org/mirrors.aliyun.com/g' "$f"
                fi
            done
        else
            echo -e "${YELLOW}[!] APT 源已经是阿里云，跳过换源${RESET}"
        fi

        if [ "$need_update" -eq 1 ]; then
            sudo apt update -y
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
    local input="$1"
    local pkg="${input%%:*}"
    local cmd="${input#*:}"
    [ "$cmd" = "$input" ] && cmd="$pkg"
    
    if command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}[!] $pkg 已存在，跳过安装${RESET}"
        return 0
    fi
    echo -e "${BLUE}[*] 正在安装 $pkg...${RESET}"
    if [ -f /etc/debian_version ]; then
        if sudo apt install -y "$pkg"; then
            return 0
        else
            if [ "$pkg" = "awscli" ]; then
                echo -e "${YELLOW}[!] apt 安装 awscli 失败，尝试使用系统 python3-pip 安装...${RESET}"
                if sudo apt install -y python3-pip && sudo python3 -m pip install awscli; then
                    return 0
                fi
                echo -e "${YELLOW}[!] pip 安装 awscli 失败，已跳过${RESET}"
            fi
            echo -e "${YELLOW}[!] 安装 $pkg 失败，已跳过${RESET}"
            return 1
        fi
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y "$pkg" && return 0
    fi
    echo -e "${YELLOW}[!] 安装 $pkg 失败，已跳过${RESET}"
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

setup_bashrc_clean_scripts() {
    if [ -f ~/.bashrc ]; then
        sed -i '/command -v neofetch/d' ~/.bashrc
        sed -i '/# 显示系统信息/d' ~/.bashrc
        sed -i '/# 登录显示系统信息/d' ~/.bashrc

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

        sed -i '/\[ -x ~\/scripts\/check_nas.sh \] && ~/d' ~/.bashrc
        sed -i '/\[ -x ~\/scripts\/storage_scan.sh \] && ~/d' ~/.bashrc
        sed -i '/\[ -x ~\/scripts\/sync_hosts.sh \] && ~/d' ~/.bashrc
        sed -i '/\[ -x ~\/scripts\/lan_scan.sh \] && ~/d' ~/.bashrc
        sed -i '/alias lan=.*/d' ~/.bashrc

        if grep -q "# linux-deploy-start" ~/.bashrc 2>/dev/null; then
            sed -i '/# linux-deploy-start/,/# linux-deploy-end/d' ~/.bashrc
        fi
    fi
}

setup_bashrc_clean_r2() {
    if [ -f ~/.bashrc ]; then
        sed -i '/# Cloudflare R2 配置/d' ~/.bashrc
        sed -i '/# 如需修改，请编辑 ~\/.bashrc/d' ~/.bashrc
        sed -i '/^export R2_ACCESS_KEY_ID=/d' ~/.bashrc
        sed -i '/^export R2_SECRET_ACCESS_KEY=/d' ~/.bashrc
        sed -i '/^export R2_BUCKET_NAME=/d' ~/.bashrc
        sed -i '/^export R2_ENDPOINT_URL=/d' ~/.bashrc
        sed -i '/^export R2_PUBLIC_URL=/d' ~/.bashrc
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
        scripts_section+="[ -x ~/scripts/storage_scan.sh ] && sudo ~/scripts/storage_scan.sh\n"
        echo -e "${GREEN}[✓] 已添加: 登录自动挂载 NAS${RESET}"
    fi
    if [ "${CHECKED[$((PKG_COUNT + 2))]:-0}" = "1" ]; then
        scripts_section+="[ -x ~/scripts/sync_hosts.sh ] && sudo -E ~/scripts/sync_hosts.sh --source=r2 -q\n"
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
    if [ -z "$scripts_section" ] && [ -z "$aliases_section" ] && [ -z "$R2_CONFIG_SECTION" ]; then
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

    if [ -n "$R2_CONFIG_SECTION" ]; then
        block+="# --- 环境变量 ---\n${R2_CONFIG_SECTION}"
    fi

    block+="# linux-deploy-end\n"

    # 写入 ~/.bashrc
    printf "%b" "$block" >> ~/.bashrc
    echo -e "${GREEN}[✓] 已更新 ~/.bashrc 的 linux-deploy 区块${RESET}"
}

# 配置 Cloudflare R2（可选）- 收集配置，返回配置字符串
# 配置结果存储在全局变量 R2_CONFIG_SECTION 中
R2_CONFIG_SECTION=""

get_existing_r2_value() {
    local key="$1"
    if [ -f ~/.bashrc ]; then
        grep "^export $key=" ~/.bashrc | head -n 1 | sed "s/^export $key=//"
    fi
}

configure_r2() {
    echo
    echo -e "${BLUE}[*] 配置 Cloudflare R2（可选）${RESET}"
    echo -e "${BLUE}    用于从 R2 下载 hosts 等文件${RESET}"

    local default_id="$EXISTING_R2_ID"
    local default_secret="$EXISTING_R2_SECRET"
    local default_bucket="$EXISTING_R2_BUCKET"
    local default_endpoint="$EXISTING_R2_ENDPOINT"
    local default_public="$EXISTING_R2_PUBLIC"

    if [ "$KEEP_OLD_CONFIG" -eq 1 ] && [ -n "$default_id" ]; then
        echo -e "${GREEN}[*] 检测到已有 R2 配置，将使用现有值${RESET}"
    fi

    read -p "是否现在配置 R2? (y/n，默认 n): " configure_now
    if [[ "$configure_now" =~ ^[Yy]$ ]]; then
        read -p "R2_ACCESS_KEY_ID [$default_id]: " r2_access_key_id
        read -p "R2_SECRET_ACCESS_KEY [$default_secret]: " r2_secret_access_key
        read -p "R2_BUCKET_NAME [$default_bucket]: " r2_bucket_name
        read -p "R2_ENDPOINT_URL [$default_endpoint]: " r2_endpoint_url
        read -p "R2_PUBLIC_URL [$default_public]: " r2_public_url

        r2_access_key_id="${r2_access_key_id:-$default_id}"
        r2_secret_access_key="${r2_secret_access_key:-$default_secret}"
        r2_bucket_name="${r2_bucket_name:-$default_bucket}"
        r2_endpoint_url="${r2_endpoint_url:-$default_endpoint}"
        r2_public_url="${r2_public_url:-$default_public}"
    else
        if [ "$KEEP_OLD_CONFIG" -eq 1 ] && [ -n "$default_id" ]; then
            echo -e "${GREEN}[*] 使用已有的 R2 配置${RESET}"
            r2_access_key_id="$default_id"
            r2_secret_access_key="$default_secret"
            r2_bucket_name="$default_bucket"
            r2_endpoint_url="$default_endpoint"
            r2_public_url="$default_public"
        else
            echo -e "${YELLOW}[!] 已跳过，将在 ~/.bashrc 中写入占位符，日后可手动修改${RESET}"
            r2_access_key_id="YOUR_R2_ACCESS_KEY_ID"
            r2_secret_access_key="YOUR_R2_SECRET_ACCESS_KEY"
            r2_bucket_name="YOUR_R2_BUCKET_NAME"
            r2_endpoint_url="YOUR_R2_ENDPOINT_URL"
            r2_public_url="YOUR_R2_PUBLIC_URL"
        fi
    fi

    R2_CONFIG_SECTION="# Cloudflare R2 配置\n"
    R2_CONFIG_SECTION+="export R2_ACCESS_KEY_ID=$r2_access_key_id\n"
    R2_CONFIG_SECTION+="export R2_SECRET_ACCESS_KEY=$r2_secret_access_key\n"
    R2_CONFIG_SECTION+="export R2_BUCKET_NAME=$r2_bucket_name\n"
    R2_CONFIG_SECTION+="export R2_ENDPOINT_URL=$r2_endpoint_url\n"
    R2_CONFIG_SECTION+="export R2_PUBLIC_URL=$r2_public_url\n"

    echo -e "${GREEN}[✓] R2 配置已准备${RESET}"
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

# 固定选项（脚本自启动 + 快捷别名 + 环境配置）
FIXED_OPTIONS=(
    "0|2|登录时自动运行 fastfetch"
    "1|2|登录时自动挂载 NAS"
    "2|2|登录时自动同步 hosts"
    "3|2|登录时自动扫描 SSH 设备"
    "4|3|ll、la、l (ls 列表快捷别名)"
    "5|3|lan (扫描局域网 SSH 设备)"
    "6|3|pxon / pxoff / pxtest (代理开关)"
    "7|4|配置 R2"
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
        4) echo "【环境配置】" ;;
    esac
}

# 读取单个按键 (支持方向键)
read_key() {
    local key key2 key3

    # 检查 stdin 是否可读
    if ! IFS= read -rs -n1 -t 30 key; then
        # read 失败（EOF 或超时），返回空值让调用方处理
        echo ""
        return
    fi

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

# 检测是否为交互式终端
is_interactive_terminal() {
    # 检查 stdin 是否连接到终端
    [ -t 0 ] && [ -t 1 ] && return 0
    return 1
}

# 简单菜单（非交互式终端备选方案）
show_simple_menu() {
    echo
    echo -e "${CYAN}>>> 请选择要部署的选项（输入序号，多个用空格分隔，直接回车全选）:${RESET}"
    echo

    local last_cat=""
    for i in "${!OPTIONS[@]}"; do
        local opt="${OPTIONS[$i]}"
        local cat_id="${opt#*|}"
        cat_id="${cat_id%%|*}"
        local name="${opt#*|*|}"

        if [ "$cat_id" != "$last_cat" ]; then
            echo -e "${CYAN}$(get_cat_name "$cat_id")${RESET}"
            last_cat="$cat_id"
        fi

        echo -e "  ${YELLOW}$((i+1))${RESET}. $name"
    done

    echo
    echo -e "${BLUE}输入选项 (例如: 1 3 5 或直接回车全选，输入 0 或 q 退出):${RESET}"
    read -r selection

    # 用户输入 0 或 q 退出
    if [[ "$selection" == "0" ]] || [[ "$selection" =~ ^[qQ]$ ]]; then
        echo -e "${YELLOW}[!] 已取消部署${RESET}"
        exit 0
    fi

    # 直接回车 = 全选（保持默认）
    if [ -z "$selection" ]; then
        echo -e "${GREEN}[✓] 已选择全部选项${RESET}"
        return
    fi

    # 先取消所有选择
    for i in "${!CHECKED[@]}"; do
        CHECKED[$i]=0
    done

    # 根据用户输入设置选择
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#OPTIONS[@]}" ]; then
            CHECKED[$((num-1))]=1
        fi
    done

    # 显示用户选择的内容
    echo
    echo -e "${GREEN}[✓] 已选择:${RESET}"
    for i in "${!OPTIONS[@]}"; do
        if [ "${CHECKED[$i]:-0}" = "1" ]; then
            local opt="${OPTIONS[$i]}"
            local name="${opt#*|*|}"
            echo -e "    - $name"
        fi
    done
    echo
}

show_interactive_menu() {
    # 检测终端环境
    if ! is_interactive_terminal; then
        echo -e "${YELLOW}[!] 检测到非交互式终端，使用简单菜单模式${RESET}"
        show_simple_menu
        return
    fi

    # 检测 tput 是否可用
    if ! command -v tput &>/dev/null; then
        echo -e "${YELLOW}[!] tput 不可用，使用简单菜单模式${RESET}"
        show_simple_menu
        return
    fi

    # CHECKED 已在定义时默认全选
    CURSOR=0

    # 尝试进入备用屏幕，如果失败则使用简单菜单
    if ! tput smcup 2>/dev/null; then
        echo -e "${YELLOW}[!] 终端不支持备用屏幕，使用简单菜单模式${RESET}"
        show_simple_menu
        return
    fi

    tput civis 2>/dev/null || true

    clear
    render_menu

    while true; do
        local key
        key=$(read_key)

        # 如果 read_key 返回空值（可能是 stdin 问题），切换到简单模式
        if [ -z "$key" ]; then
            tput rmcup 2>/dev/null || true
            tput cnorm 2>/dev/null || true
            echo -e "${YELLOW}[!] 按键读取失败，切换到简单菜单模式${RESET}"
            show_simple_menu
            return
        fi

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
                tput rmcup 2>/dev/null || true
                tput cnorm 2>/dev/null || true
                echo -e "${YELLOW}[!] 已取消部署${RESET}"
                exit 0
                ;;
            "UNKNOWN")
                ;;
        esac
    done

    tput rmcup 2>/dev/null || true
    tput cnorm 2>/dev/null || true
}

# ==================== 配置 sudoers 免密 ====================

setup_sudoers() {
    local sudoers_file="/etc/sudoers.d/linux_deploy"
    local need_update=0

    # 检查主 sudoers 文件中是否有旧配置，需要清理
    if sudo grep -q "sync_hosts.sh\|storage_scan.sh\|lan_scan.sh" /etc/sudoers 2>/dev/null; then
        echo -e "${BLUE}[*] 检测到 /etc/sudoers 中存在旧配置，正在清理...${RESET}"
        local tmp_file=$(mktemp)
        sudo grep -v "sync_hosts.sh\|storage_scan.sh\|lan_scan.sh" /etc/sudoers > "$tmp_file"
        if sudo visudo -c -f "$tmp_file" 2>/dev/null; then
            sudo cp "$tmp_file" /etc/sudoers
            sudo chmod 440 /etc/sudoers
            echo -e "${GREEN}[✓] 已清理 /etc/sudoers 中的旧配置${RESET}"
        else
            echo -e "${YELLOW}[!] 清理旧配置失败，请手动编辑 /etc/sudoers${RESET}"
        fi
        rm -f "$tmp_file"
        need_update=1
    fi

    # 检查是否需要更新（文件不存在、缺少脚本路径或 SETENV 未正确配置）
    if [ -f "$sudoers_file" ]; then
        if ! sudo grep -q "$HOME/scripts/storage_scan.sh" "$sudoers_file" 2>/dev/null || \
           ! sudo grep -q "$HOME/scripts/lan_scan.sh" "$sudoers_file" 2>/dev/null || \
           ! sudo grep -q "SETENV:.*sync_hosts.sh" "$sudoers_file" 2>/dev/null; then
            echo -e "${YELLOW}[!] sudoers 配置需要更新${RESET}"
            need_update=1
        else
            echo -e "${YELLOW}[!] sudoers 免密已配置，跳过${RESET}"
            return
        fi
    else
        need_update=1
    fi

    if [ "$need_update" = "1" ]; then
        echo -e "${BLUE}[*] 正在配置 passwordless sudo（需输入一次密码）...${RESET}"

        sudo tee "$sudoers_file" > /dev/null <<EOF
$USER ALL=(ALL) NOPASSWD: $HOME/scripts/storage_scan.sh
$USER ALL=(ALL) NOPASSWD: SETENV: $HOME/scripts/sync_hosts.sh
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
    fi
}

# ==================== 执行部署 ====================

run_deploy() {
    echo
    # --- 清除旧配置警告 ---
    echo -e "${YELLOW}=================================${RESET}"
    echo -e "${YELLOW}  [!] 警告: 即将清除 ~/.bashrc 中的旧配置${RESET}"
    echo -e "${YELLOW}      包括 linux-deploy 区块和独立 R2 配置${RESET}"
    echo -e "${YELLOW}=================================${RESET}"
    echo -e "${YELLOW}  请选择处理方式：${RESET}"
    echo -e "${YELLOW}    1) 保留旧配置（保留 R2 export 配置）${RESET}"
    echo -e "${YELLOW}    2) 全部清除（清除所有旧配置）${RESET}"
    echo -e "${YELLOW}    3) 取消（终止执行）${RESET}"
    echo -e "${YELLOW}=================================${RESET}"
    read -p "请输入选择 [1/2/3]，默认 1: " clear_option
    KEEP_OLD_CONFIG=0
    EXISTING_R2_ID=""
    EXISTING_R2_SECRET=""
    EXISTING_R2_BUCKET=""
    EXISTING_R2_ENDPOINT=""
    EXISTING_R2_PUBLIC=""

    if [[ "$clear_option" == "1" || -z "$clear_option" ]]; then
        EXISTING_R2_ID=$(get_existing_r2_value "R2_ACCESS_KEY_ID")
        EXISTING_R2_SECRET=$(get_existing_r2_value "R2_SECRET_ACCESS_KEY")
        EXISTING_R2_BUCKET=$(get_existing_r2_value "R2_BUCKET_NAME")
        EXISTING_R2_ENDPOINT=$(get_existing_r2_value "R2_ENDPOINT_URL")
        EXISTING_R2_PUBLIC=$(get_existing_r2_value "R2_PUBLIC_URL")
    fi

    case "$clear_option" in
        1|"")
            echo -e "${GREEN}[*] 选择保留旧配置，仅清除 linux-deploy 区块${RESET}"
            KEEP_OLD_CONFIG=1
            setup_bashrc_base
            setup_bashrc_clean_scripts
            ;;
        2)
            echo -e "${GREEN}[*] 选择全部清除，将清除所有旧配置${RESET}"
            setup_bashrc_base
            setup_bashrc_clean_scripts
            setup_bashrc_clean_r2
            ;;
        3)
            echo -e "${YELLOW}[!] 已取消部署${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}[!] 无效选择，默认执行保留旧配置${RESET}"
            KEEP_OLD_CONFIG=1
            EXISTING_R2_ID=$(get_existing_r2_value "R2_ACCESS_KEY_ID")
            EXISTING_R2_SECRET=$(get_existing_r2_value "R2_SECRET_ACCESS_KEY")
            EXISTING_R2_BUCKET=$(get_existing_r2_value "R2_BUCKET_NAME")
            EXISTING_R2_ENDPOINT=$(get_existing_r2_value "R2_ENDPOINT_URL")
            EXISTING_R2_PUBLIC=$(get_existing_r2_value "R2_PUBLIC_URL")
            setup_bashrc_base
            setup_bashrc_clean_scripts
            ;;
    esac
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

    # --- 配置 R2 环境变量（先收集配置） ---
    if [ "${CHECKED[$((PKG_COUNT + 7))]:-0}" = "1" ]; then
        configure_r2
    fi

    # --- 写入 ~/.bashrc 区块（包含 R2 配置） ---
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

    show_interactive_menu
    run_deploy
}

show_menu
