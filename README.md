# ssh-hardening-kit

用于服务器 SSH 改端口、fail2ban 和 UFW 基础防护的一组 Bash 脚本，适合上传到 GitHub 后在新服务器上重复使用。

默认目标系统是 Ubuntu/Debian；`fail2ban` 安装脚本也尽量兼容 `dnf`/`yum` 系统。所有会改系统配置的脚本都需要 `root` 权限。

在 AlmaLinux/Rocky Linux/CentOS/RHEL 这类系统上，如果默认仓库没有 `fail2ban`，脚本会自动安装 `epel-release` 后重试。

## 一行命令

预检：

```bash
curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh | bash -s -- preflight
```

修改 SSH 端口为默认 `55889`，保留 root 密码登录：

```bash
curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh | sudo bash -s -- sshd
```

添加默认 SSH 公钥到 `root`：

```bash
curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh | sudo bash -s -- add-key
```

安装并配置 fail2ban：

```bash
curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh | sudo bash -s -- fail2ban
```

配置 UFW：

```bash
curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh | sudo bash -s -- ufw
```

关闭 22 端口：

```bash
curl -Ls https://raw.githubusercontent.com/fengyunzaidushi/ssh-hardening-kit/main/install.sh | sudo env CLOSE_PORT_22=yes bash -s -- ufw
```

## 执行顺序

先预检：

```bash
sudo bash scripts/00-preflight.sh
```

修改 SSH 端口，默认保留 root 密码登录：

```bash
sudo bash scripts/10-harden-sshd.sh
```

添加默认 SSH 公钥到 `root`：

```bash
sudo bash scripts/05-add-ssh-key.sh
```

然后不要关闭当前 SSH 窗口，新开一个终端测试新端口：

```bash
ssh -p 55889 root@YOUR_SERVER_IP
```

确认新端口可以登录后，再安装并配置 fail2ban：

```bash
sudo bash scripts/20-install-fail2ban.sh
```

最后配置 UFW 防火墙。固定办公 IP/VPN IP 推荐这样写：

```bash
sudo ALLOWED_SSH_CIDRS="203.0.113.10/32" bash scripts/30-configure-ufw.sh
```

如果你还没有固定 IP，至少先开放新 SSH 端口：

```bash
sudo bash scripts/30-configure-ufw.sh
```

确认新端口、防火墙、安全组都正常后，再关闭 22 端口：

```bash
sudo CLOSE_PORT_22=yes bash scripts/30-configure-ufw.sh
```

## 重要变量

`scripts/10-harden-sshd.sh`

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `NEW_SSH_PORT` | `55889` | 新 SSH 端口 |
| `SSH_ALLOW_USERS` | `root` | 写入 `AllowUsers`，例如 `"root"` 或 `"root deploy"` |
| `DISABLE_PASSWORD` | `no` | 是否禁用密码登录；默认不禁用 |
| `PERMIT_ROOT_LOGIN` | `yes` | 是否允许 root 登录；默认允许 root 密码/密钥登录 |
| `MAX_AUTH_TRIES` | `3` | 单连接最大认证尝试次数 |
| `ALLOW_NO_KEY` | `no` | 仅当 `DISABLE_PASSWORD=yes` 时生效；没检测到 authorized_keys 是否仍继续 |

`scripts/05-add-ssh-key.sh`

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SSH_KEY_USER` | `root` | 要添加公钥的用户 |
| `SSH_PUBLIC_KEY` | `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH535gEQjjfN8kGVCo4743cvNL5nih2gX+JgWts9Dqeo fengx@fxy-win11` | 要添加的 ed25519 公钥 |

`scripts/20-install-fail2ban.sh`

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SSH_PORT` | `55889` | fail2ban 保护的 SSH 端口 |
| `FAIL2BAN_MAXRETRY` | `5` | 失败次数阈值 |
| `FAIL2BAN_FINDTIME` | `10m` | 统计窗口 |
| `FAIL2BAN_BANTIME` | `1d` | 封禁时间 |
| `FAIL2BAN_IGNORE_IPS` | 空 | 永不封禁的 IP/CIDR，空格分隔 |

`scripts/30-configure-ufw.sh`

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SSH_PORT` | `55889` | 允许访问的 SSH 端口 |
| `ALLOWED_SSH_CIDRS` | 空 | 限制 SSH 来源，支持空格或逗号分隔 |
| `ALLOW_HTTP` | `yes` | 是否允许 80/tcp |
| `ALLOW_HTTPS` | `yes` | 是否允许 443/tcp |
| `CLOSE_PORT_22` | `no` | 是否删除常见 22/tcp allow 规则并 deny 22/tcp |

## 回滚 SSH 配置

SSH 加固脚本会把备份放在：

```text
/root/ssh-hardening-backups/
```

回滚最近一次 SSH 备份：

```bash
sudo bash scripts/90-rollback-sshd.sh
```

指定备份目录回滚：

```bash
sudo BACKUP_DIR=/root/ssh-hardening-backups/20260619-120000-sshd bash scripts/90-rollback-sshd.sh
```

## 注意事项

- 先确认云厂商安全组也放行了 `NEW_SSH_PORT`。
- 默认允许 `root` 继续使用密码登录，只修改 SSH 端口及基础连接参数，并重启 SSH 监听服务让端口立即生效。
- 如果系统启用了 `ssh.socket`/`sshd.socket`，脚本会停用它们，避免 systemd socket 继续固定监听 22。
- 所有脚本都有默认值，不需要 `.env.example`；需要覆盖时直接在命令前加环境变量。
- 如果你以后设置 `DISABLE_PASSWORD=yes`，脚本会先检查 `/root/.ssh/authorized_keys` 是否存在且非空。
- UFW 和 Docker 同机使用时，Docker 端口暴露可能绕过 UFW，需要另做 Docker 网络规则。
