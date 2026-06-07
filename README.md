# Cloudflare DNS Failover

一个基于 Python 的 Cloudflare DNS 主备自动切换工具。

当主服务器故障时，自动将 Cloudflare DNS 记录切换至备用服务器；主服务器恢复后自动切回。

适用于：

* 网站高可用
* API 服务
* 视频站回源
* CDN 回源
* 海外 VPS 主备容灾
* Cloudflare DNS 自动故障转移

---

## 功能特点

✅ TCP 端口健康检测

✅ 主服务器故障自动切换

✅ 主服务器恢复自动切回

✅ Cloudflare API 自动更新 DNS

✅ 钉钉机器人通知

✅ Systemd 服务支持

✅ 开机自启

✅ 自动日志轮转

✅ API 自动重试

✅ 超低资源占用

---

## 工作流程

```text
主服务器正常
        │
        ▼
持续监控 TCP 端口
        │
        ▼
连续失败 N 次
        │
        ▼
Cloudflare DNS → 备用服务器
        │
        ▼
持续检测主服务器
        │
        ▼
连续成功 N 次
        │
        ▼
Cloudflare DNS → 主服务器
```

---

## 环境要求

* Debian 10+
* Ubuntu 20.04+
* Python 3.8+

---

## 安装

### 一键安装

```bash
bash install.sh
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

## 手动安装

安装依赖：

```bash
apt update
apt install python3 python3-requests -y
```

运行：

```bash
python3 cfdns.py
```

---

## 配置说明

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

默认：

```python
10
```

### FAIL_LIMIT

连续失败次数达到后切换

默认：

```python
5
```

### OK_LIMIT

连续恢复次数达到后切回

默认：

```python
5
```

---

## Cloudflare API 权限

推荐创建最小权限 Token：

### Permissions

```text
Zone
 └ DNS
    └ Edit
```

### Zone Resources

```text
Include
Specific Zone
```

---

## Systemd 管理

查看状态：

```bash
systemctl status cfdns
```

启动：

```bash
systemctl start cfdns
```

停止：

```bash
systemctl stop cfdns
```

重启：

```bash
systemctl restart cfdns
```

查看日志：

```bash
journalctl -u cfdns -f
```

---

## 日志

默认位置：

```text
/var/log/cf_failover.log
```

自动轮转：

* 每天生成一个日志文件
* 保留 7 天
* 自动删除旧日志

---

## 钉钉通知

支持：

* 服务启动
* 主服务器故障
* DNS 切换成功
* DNS 切换失败
* 主服务器恢复

配置：

```python
DINGTALK_WEBHOOK = "https://oapi.dingtalk.com/robot/send?access_token=xxxx"
```

---

## 免责声明

本项目按“现状”提供，不保证适用于所有生产环境。

使用前请自行测试。

作者不对因使用本项目导致的业务中断、数据丢失或经济损失承担责任。

---

## License

MIT License
