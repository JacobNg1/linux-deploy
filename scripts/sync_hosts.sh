#!/bin/bash

# 参数默认值
USE_R2=0
QUIET=0

# 路径变量
SRC="/mnt/nas/OneDrive-Sync/PC/host/main/hosts"

# 解析参数
for arg in "$@"; do
    case "$arg" in
        --source=r2) USE_R2=1 ;;
        --source=*) SRC="${arg#*=}" ;;
        -q|--quiet) QUIET=1 ;;
    esac
done
DEST="/etc/hosts"
TMP="/tmp/hosts_clean"
HOSTNAME=$(hostname)

# 自动提权：如果当前不是 root，用 sudo -E 重新执行本脚本，保留 R2 等环境变量
if [ "$EUID" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

# R2 模式：从环境变量读取配置并下载 hosts
if [ "$USE_R2" -eq 1 ]; then
    SRC="/tmp/hosts_r2"
    R2_FILE_PATH="hosts/main/hosts"

    # 优先使用公开 URL（如果配置了）
    if [ -n "$R2_PUBLIC_URL" ] && [[ "$R2_PUBLIC_URL" != YOUR_* ]]; then
        if ! curl -fsSL -o "$SRC" "${R2_PUBLIC_URL}/${R2_FILE_PATH}"; then
            [ "$QUIET" -ne 1 ] && echo "错误: 从 R2 公开 URL 下载 hosts 失败" >&2
            exit 1
        fi
    # 否则使用 AWS CLI + API 凭证
    elif [ -n "$R2_ACCESS_KEY_ID" ] && [ -n "$R2_SECRET_ACCESS_KEY" ] && [ -n "$R2_BUCKET_NAME" ] && [ -n "$R2_ENDPOINT_URL" ]; then
        if ! command -v aws &>/dev/null; then
            [ "$QUIET" -ne 1 ] && echo "错误: 未安装 aws CLI，请先安装: sudo apt install awscli" >&2
            exit 1
        fi
        if ! AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
             AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
             aws --endpoint-url="$R2_ENDPOINT_URL" s3 cp "s3://${R2_BUCKET_NAME}/${R2_FILE_PATH}" "$SRC" --quiet 2>/dev/null; then
            [ "$QUIET" -ne 1 ] && echo "错误: 从 R2 API 下载 hosts 失败" >&2
            exit 1
        fi
    else
        [ "$QUIET" -ne 1 ] && echo "错误: 未配置 R2 凭证，请配置 ~/.bashrc 中的 R2 环境变量" >&2
        exit 1
    fi
fi

# 1. 前置检查
[ ! -f "$SRC" ]  && { [ "$QUIET" -ne 1 ] && echo "跳过: 源文件不存在"; exit 0; }
[ ! -s "$SRC" ]  && echo "错误: 源文件为空" && exit 1

# 2. 生成临时文件 (处理换行符)
sed 's/\r//g' "$SRC" > "$TMP"

# 3. 在末尾追加适配代码 (不删除原有内容)
echo -e "\n# 适配 Linux 机器" >> "$TMP"
echo -e "127.0.1.1\t$HOSTNAME" >> "$TMP"

# 4. MD5 校验
if [ "$(md5sum < "$TMP")" == "$(md5sum < "$DEST")" ]; then
    [ "$QUIET" -ne 1 ] && echo "Hosts 已是最新"
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
