#!/bin/bash

# 处理参数：检查是否有 -q
QUIET=false
if [[ "$1" == "-q" ]]; then
    QUIET=true
fi

MOUNT_POINTS=("/mnt/data1" "/mnt/data2")

# 自动提权：如果当前不是 root，用 sudo 重新执行本脚本
if [ "$EUID" -ne 0 ]; then
    if [ "$QUIET" = true ]; then
        exec sudo "$0" -q
    else
        exec sudo "$0"
    fi
fi

for MP in "${MOUNT_POINTS[@]}"
do
    if mountpoint -q "$MP"; then
        # 只有在非静默模式下才打印已挂载警告
        if [ "$QUIET" = false ]; then
            echo -e "\e[33m[警告] $MP 已经挂载，无需重复操作。\e[0m"
        fi
    else
        [ "$QUIET" = false ] && echo "[信息] $MP 未挂载，正在尝试挂载..."

        mount "$MP" 2>/dev/null

        if mountpoint -q "$MP"; then
            echo -e "\e[32m[成功] $MP 挂载成功。\e[0m"
        else
            # 无论是否静默模式，失败都要报错
            echo -e "\e[31m[错误] $MP 挂载失败，请检查网络或 NAS 状态。\e[0m"
        fi
    fi
done
