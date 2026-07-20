# Linux Deploy

Jacob 设备自动化部署脚本，支持键盘交互式菜单选择功能，从 Gitee 在线拉取一键部署。

## 快速启动

```bash
curl -fsSL "https://gitee.com/jacob_ng/linux-deploy/raw/main/install.sh" | bash
```

可选参数：

```bash
# 仅下载并更新脚本，不执行部署
curl -fsSL "https://gitee.com/jacob_ng/linux-deploy/raw/main/install.sh" | bash -s -- --scripts
```


## 交互式菜单

启动后进入键盘交互式菜单，所有选项默认全选：

```
=================================
      Jacob 设备自动化部署脚本
=================================
↑↓ 移动光标  |  空格 切换选中  |  Enter 确认部署  |  q 退出

>>> 【软件安装】
  [✓]   安装 nano
  [✓]   安装 fastfetch
  [✓]   安装 curl
  [✓]   安装 git
>>> 【脚本自启动】
  [✓]   登录时自动运行 fastfetch
  [✓]   登录时自动挂载 NAS
  [✓]   登录时自动同步 hosts
  [✓]   登录时自动扫描 SSH 设备
>>> 【快捷别名】
  [✓]   ll、la、l (ls 列表快捷别名)
  [✓]   lan (扫描局域网 SSH 设备)
  [✓]   pxon / pxoff / pxtest (代理开关)
```

操作方式：

| 按键        | 功能      |
| --------- | ------- |
| `↑` / `↓` | 移动光标    |
| `空格`      | 切换选中/取消 |
| `Enter`   | 确认并开始部署 |
| `q`       | 退出      |

> 软件安装列表从 `scripts/packages.txt` 动态读取，修改该文件即可增减菜单中的安装项。

## 部署输出示例

```
=================================
       Jacob 设备自动化部署脚本
=================================
[!] APT 源已经是阿里云，跳过换源
[*] 配置 Git 核心信息...

=================================
        开始执行部署...
=================================

[!] nano 已存在，跳过安装
[!] fastfetch 已存在，跳过安装
[!] git 已存在，跳过安装
[!] curl 已存在，跳过安装
[✓] 已添加: 登录显示系统信息
[✓] 已添加: 登录自动挂载 NAS
[✓] 已添加: 登录自动同步 hosts
[✓] 已添加: 登录自动扫描 SSH 设备
[✓] 已添加: ll、la、l 快捷别名
[✓] 已添加: lan 快捷别名
[✓] 已添加: 代理开关别名
[✓] 已更新 ~/.bashrc 的 linux-deploy 区块
[*] 正在配置 passwordless sudo（需输入一次密码）...
[✓] sudoers 免密配置完成

=================================
  部署完成！请执行 source ~/.bashrc
=================================
```

## sudoers 免密配置

部署时自动创建 `/etc/sudoers.d/linux_deploy`，对以下脚本免密：

```
jacob ALL=(ALL) NOPASSWD: /home/jacob/scripts/storage_scan.sh
jacob ALL=(ALL) NOPASSWD: /home/jacob/scripts/sync_hosts.sh
jacob ALL=(ALL) NOPASSWD: /home/jacob/scripts/lan_scan.sh
```

首次部署需输入一次 sudo 密码，之后所有脚本自动免密运行。语法自动校验，出错时自动回滚。

## \~/.bashrc 写入格式

所有自定义内容集中在 `# linux-deploy-start` / `# linux-deploy-end` 区块内，脚本可完整重写此区块：

```bash
# linux-deploy-start
# --- 脚本自启动 ---
command -v fastfetch >/dev/null && fastfetch
[ -x ~/scripts/storage_scan.sh ] && sudo ~/scripts/storage_scan.sh
[ -x ~/scripts/sync_hosts.sh ] && sudo -E ~/scripts/sync_hosts.sh --source=r2 -q
[ -x ~/scripts/lan_scan.sh ] && sudo ~/scripts/lan_scan.sh
# --- 快捷别名 ---
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias lan='sudo ~/scripts/lan_scan.sh'
# 代理
PROXY_NODE=http://tc:7890
alias pxon='export http_proxy="$PROXY_NODE"; export https_proxy="$PROXY_NODE"; echo "Proxy On: $PROXY_NODE"'
alias pxoff='unset http_proxy; unset https_proxy; echo "Proxy Off"'
alias pxtest='curl -I https://www.google.com'
# --- 环境变量 ---
# Cloudflare R2 配置
export R2_ACCESS_KEY_ID=YOUR_R2_ACCESS_KEY_ID
export R2_SECRET_ACCESS_KEY=YOUR_R2_SECRET_ACCESS_KEY
export R2_BUCKET_NAME=YOUR_R2_BUCKET_NAME
export R2_ENDPOINT_URL=YOUR_R2_ENDPOINT_URL
export R2_PUBLIC_URL=YOUR_R2_PUBLIC_URL
# linux-deploy-end
```

## 项目结构

```
linux-deploy/
├── install.sh              # 在线启动入口
├── scripts/
│   ├── linux-deploy.sh     # 主部署脚本（交互式菜单）
│   ├── storage_scan.sh     # 存储扫描与挂载脚本（自动提权）
│   ├── sync_hosts.sh       # Hosts 同步脚本（自动提权）
│   ├── lan_scan.sh         # 局域网 SSH 设备扫描
│   └── packages.txt        # 软件安装列表（动态读取）
├── .env                    # Gitee API Token（不上传仓库）
├── .gitignore
└── README.md
```

