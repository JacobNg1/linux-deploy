#!/usr/bin/env bash

set -o pipefail

readonly RESET='\033[0m'
readonly BOLD='\033[1m'
readonly BLUE='\033[38;5;33m'
readonly CYAN='\033[38;5;45m'
readonly GREEN='\033[38;5;40m'
readonly YELLOW='\033[38;5;214m'
readonly RED='\033[38;5;196m'

quiet=false
list_only=false

info() { printf '%b\n' "${BLUE}[信息]${RESET} $*"; }
success() { printf '%b\n' "${GREEN}[成功]${RESET} $*"; }
error() { printf '%b\n' "${RED}${BOLD}[错误]${RESET} $*" >&2; }

usage() {
    printf '%s\n' \
        '用法: storage_scan.sh [选项]' \
        '' \
        '选项:' \
        '  -q, --quiet  静默挂载，不显示设备列表' \
        '  -l, --list   仅显示存储设备与挂载信息，不执行挂载' \
        '  -h, --help   显示帮助'
}

for arg in "$@"; do
    case "$arg" in
        -q|--quiet) quiet=true ;;
        -l|--list) list_only=true ;;
        -h|--help) usage; exit 0 ;;
        *) error "未知参数：$arg"; usage >&2; exit 2 ;;
    esac
done

require_commands() {
    local command
    for command in lsblk findmnt mount; do
        command -v "$command" >/dev/null || {
            error "缺少命令：$command"
            exit 127
        }
    done
}

show_local_storage() {
    printf '%b\n' "${CYAN}${BOLD}================ 本地块设备及挂载信息 ================${RESET}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
    printf '%b\n' "${CYAN}======================================================${RESET}"
}

show_remote_mounts() {
    local remote_types="nfs,nfs4,cifs,smb3,sshfs,fuse.sshfs,9p,ceph,glusterfs,afs,davfs,ftpfs"

    printf '%b\n' "${YELLOW}${BOLD}================ 远程文件系统挂载信息 ================${RESET}"
    if ! findmnt -t "$remote_types" -o TARGET,SOURCE,FSTYPE,OPTIONS; then
        printf '%b\n' "${YELLOW}（未发现已挂载的远程文件系统）${RESET}"
    fi
    printf '%b\n' "${YELLOW}======================================================${RESET}"
}

show_storage() {
    show_local_storage
    show_remote_mounts
}

require_commands

if [ "$list_only" = true ]; then
    show_storage
    exit 0
fi

# mount -a 仅处理 /etc/fstab 中配置的挂载项，不会自动挂载任意块设备。
if [ "$EUID" -ne 0 ]; then
    command -v sudo >/dev/null || { error "需要 sudo 执行挂载"; exit 127; }
    exec sudo -- "$0" "$@"
fi

if [ "$quiet" = false ]; then
    info "正在挂载 /etc/fstab 中尚未挂载的设备..."
fi

if ! mount -a; then
    error "存在挂载失败项，请检查 /etc/fstab、网络或设备状态。"
    exit 1
fi

if [ "$quiet" = false ]; then
    success "已处理 /etc/fstab 中的挂载项。"
    show_storage
fi
