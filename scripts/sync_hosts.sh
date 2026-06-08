#!/bin/bash

# 路径变量
SRC="/mnt/nas/OneDrive-Sync/PC/host/main/hosts"
DEST="/etc/hosts"
TMP="/tmp/hosts_clean"
HOSTNAME=$(hostname)

# 自动提权：如果当前不是 root，用 sudo 重新执行本脚本
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# 1. 前置检查
[ ! -f "$SRC" ]  && { [[ "$1" != "-q" ]] && echo "跳过: 源文件不存在"; exit 0; }
[ ! -s "$SRC" ]  && echo "错误: 源文件为空" && exit 1

# 2. 生成临时文件 (处理换行符)
sed 's/\r//g' "$SRC" > "$TMP"

# 3. 在末尾追加适配代码 (不删除原有内容)
echo -e "\n# 适配 Linux 机器" >> "$TMP"
echo -e "127.0.1.1\t$HOSTNAME" >> "$TMP"

# 4. MD5 校验
if [ "$(md5sum < "$TMP")" == "$(md5sum < "$DEST")" ]; then
    [[ "$1" != "-q" ]] && echo "Hosts 已是最新"
    rm "$TMP" && exit 0
fi

# 5. 备份与同步
[ ! -f "$DEST.bak" ] && cp "$DEST" "$DEST.bak"

if cp "$TMP" "$DEST" && chmod 644 "$DEST"; then
    resolvectl flush-caches 2>/dev/null || true
    echo "Hosts 同步成功 ($(date))"
else
    echo -e "\e[31m同步失败: 写入错误\e[0m"
    exit 1
fi

rm "$TMP"
