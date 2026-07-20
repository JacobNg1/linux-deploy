#!/usr/bin/env bash

set -o pipefail

quiet=false
list_only=false

usage() {
    printf '%s\n' \
        '用法: check_nas.sh [选项]' \
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
        *) echo "错误：未知参数 $arg" >&2; usage >&2; exit 2 ;;
    esac
done

show_local_storage() {
    echo "================ 本地块设备及挂载信息 ================"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
    echo "======================================================"
}

show_remote_mounts() {
    local remote_types="nfs,nfs4,cifs,smb3,sshfs,fuse.sshfs,9p,ceph,glusterfs,afs,davfs,ftpfs"

    echo "================ 远程文件系统挂载信息 ================"
    if ! findmnt -t "$remote_types" -o TARGET,SOURCE,FSTYPE,OPTIONS; then
        echo "（未发现已挂载的远程文件系统）"
    fi
    echo "======================================================"
}

show_storage() {
    show_local_storage
    show_remote_mounts
}

if [ "$list_only" = true ]; then
    show_storage
    exit 0
fi

# mount -a 仅处理 /etc/fstab 中配置的挂载项，不会自动挂载任意块设备。
if [ "$EUID" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

if [ "$quiet" = false ]; then
    echo "[信息] 正在挂载 /etc/fstab 中尚未挂载的设备..."
fi

if ! mount -a; then
    echo "[错误] 存在挂载失败项，请检查 /etc/fstab、网络或设备状态。" >&2
    exit 1
fi

if [ "$quiet" = false ]; then
    echo "[成功] 已处理 /etc/fstab 中的挂载项。"
    show_storage
fi
