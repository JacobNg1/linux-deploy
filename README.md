# Linux Deploy

Jacob 设备自动化部署脚本，支持交互式菜单选择功能。

## 快速启动

```bash
export GITEE_API_TOKEN="aee0c6d82280dd56de52b4eab884cdfd"
export GITEE_BRANCH="dev"
export R2_SCRIPT_URL="https://pub-b4b7de76533e439c9056fa7c1ce37150.r2.dev/b64json.py"

curl -s $R2_SCRIPT_URL | python3 - "$GITEE_API_TOKEN" "${GITEE_BRANCH:-main}" \
  > /tmp/linux-deploy-install.sh && bash /tmp/linux-deploy-install.sh
```

## 环境变量说明

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `GITEE_API_TOKEN` | 是 | - | Gitee API Token，用于访问私有仓库 |
| `GITEE_BRANCH` | 否 | `main` | 指定拉取的分支 |
| `R2_SCRIPT_URL` | 是 | - | R2 上托管的 base64 解码脚本地址 |

## 功能菜单

启动后进入交互式菜单，支持方向键 + 空格选择：

- **软件安装**：nano、fastfetch、curl、git
- **快捷方式**：登录时自动运行 fastfetch、挂载 NAS、同步 hosts、扫描 SSH 设备
- **其他配置**：批量安装 packages.txt 中的软件

操作方式：
- `↑` / `↓`：移动光标
- `空格`：切换选中/取消
- `Enter`：确认部署
- `q`：退出

## 项目结构

```
linux-deploy/
├── install.sh              # 在线启动入口
├── scripts/
│   ├── linux-deploy.sh     # 主部署脚本（交互式菜单）
│   ├── check_nas.sh        # NAS 挂载脚本（自动提权）
│   ├── sync_hosts.sh       # Hosts 同步脚本（自动提权）
│   └── packages.txt        # 批量安装包列表
└── README.md
```

## 自动提权说明

`check_nas.sh` 和 `sync_hosts.sh` 已内置自动提权逻辑：
- 检测到非 root 用户时，自动通过 `sudo` 重新执行自身
- 无需手动输入 `sudo`，但首次运行可能需要输入密码
- 建议配置 sudo 免密以完全自动化
