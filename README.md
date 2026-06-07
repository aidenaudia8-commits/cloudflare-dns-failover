# Cloudflare DNS Failover

A lightweight Cloudflare DNS automatic failover and failback tool written in Python.

一个基于 Python 开发的 Cloudflare DNS 主备自动切换工具。

当主服务器故障时，自动切换 DNS 到备用服务器；主服务器恢复后自动切回。

---

## Features | 功能特点

* Automatic DNS failover（自动故障切换）
* Automatic DNS failback（自动恢复回切）
* Cloudflare API integration（Cloudflare API 集成）
* DingTalk notifications（钉钉通知）
* Systemd service support（Systemd 服务支持）
* Daily log rotation（日志自动轮转）
* Automatic API retry（API 自动重试）
* Low resource consumption（超低资源占用）

---

## Architecture | 工作流程

```text
Primary Server
      │
      ▼
 TCP Health Check
      │
      ▼
Fail Count >= FAIL_LIMIT
      │
      ▼
Cloudflare DNS → Backup Server
      │
      ▼
Keep Monitoring
      │
      ▼
Success Count >= OK_LIMIT
      │
      ▼
Cloudflare DNS → Primary Server
```

主服务器正常时持续进行 TCP 端口检测。

当连续检测失败达到设定次数后，自动将 Cloudflare DNS 记录切换至备用服务器。

主服务器恢复后，自动切换回主服务器。

---

## Requirements | 环境要求

* Debian 10+
* Debian 11+
* Debian 12+
* Ubuntu 20.04+
* Ubuntu 22.04+
* Python 3.8+

---

## Installation | 安装方法

### One-click Installation | 一键安装

```bash
wget https://raw.githubusercontent.com/aidenaudia8-commits/cloudflare-dns-failover/main/install.sh

chmod +x install.sh

./install.sh
```

按照提示填写：

* Cloudflare API Token
* Zone ID
* DNS Record ID
* 域名
* 主服务器 IP
* 备用服务器 IP

即可完成安装。

---

## Configuration | 配置说明

```python
PRIMARY_IP = "1.1.1.1"
BACKUP_IP = "2.2.2.2"

PORT = 80

CHECK_INTERVAL = 10

FAIL_LIMIT = 5

OK_LIMIT = 5
```

### CHECK_INTERVAL

检测间隔（秒）

Health check interval in seconds.

### FAIL_LIMIT

连续失败次数达到后切换备用服务器。

Switch to backup server after consecutive failures.

### OK_LIMIT

连续成功次数达到后切回主服务器。

Switch back to primary server after consecutive successful checks.

---

## Service Management | 服务管理

查看状态：

```bash
systemctl status cfdns
```

重启服务：

```bash
systemctl restart cfdns
```

停止服务：

```bash
systemctl stop cfdns
```

查看实时日志：

```bash
journalctl -u cfdns -f
```

---

## Log File | 日志文件

默认日志位置：

```text
/var/log/cf_failover.log
```

日志特性：

* 每天自动切割
* 保留最近 7 天
* 自动删除历史日志

---

## License | 开源协议

MIT License
