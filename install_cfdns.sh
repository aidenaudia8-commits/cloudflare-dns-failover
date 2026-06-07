#!/bin/bash

set -e

APP_DIR="/root/cloudflare"
APP_FILE="$APP_DIR/cfdns.py"
SERVICE_FILE="/etc/systemd/system/cfdns.service"
LOG_FILE="/var/log/cf_failover.log"

echo "======================================"
echo " Cloudflare DNS Failover 一键安装脚本"
echo "======================================"
echo

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行"
    exit 1
fi

read -p "请输入 Cloudflare API Token: " CF_TOKEN
read -p "请输入 Cloudflare Zone ID: " ZONE_ID
read -p "请输入 Cloudflare DNS Record ID: " RECORD_ID
read -p "请输入域名，例如 cdn.example.com: " DOMAIN
read -p "请输入主服务器 IP: " PRIMARY_IP
read -p "请输入备用服务器 IP: " BACKUP_IP
read -p "请输入检测端口，默认 80: " PORT
PORT=${PORT:-80}

read -p "请输入钉钉 Webhook，可留空: " DINGTALK_WEBHOOK

read -p "检测间隔秒数，默认 10: " CHECK_INTERVAL
CHECK_INTERVAL=${CHECK_INTERVAL:-10}

read -p "连续失败几次切换，默认 5: " FAIL_LIMIT
FAIL_LIMIT=${FAIL_LIMIT:-5}

read -p "连续恢复几次切回，默认 5: " OK_LIMIT
OK_LIMIT=${OK_LIMIT:-5}

echo
echo "[1/5] 安装依赖..."

apt update
apt install -y python3 python3-requests

echo
echo "[2/5] 创建目录..."

mkdir -p "$APP_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

echo
echo "[3/5] 写入 Python 脚本..."

cat > "$APP_FILE" <<EOF
#!/usr/bin/env python3

import socket
import time
import logging
import requests

from logging.handlers import TimedRotatingFileHandler

CF_TOKEN = "$CF_TOKEN"
ZONE_ID = "$ZONE_ID"
RECORD_ID = "$RECORD_ID"

DOMAIN = "$DOMAIN"

PRIMARY_IP = "$PRIMARY_IP"
BACKUP_IP = "$BACKUP_IP"

PORT = $PORT

DINGTALK_WEBHOOK = "$DINGTALK_WEBHOOK"

CHECK_INTERVAL = $CHECK_INTERVAL
CONNECT_TIMEOUT = 3

FAIL_LIMIT = $FAIL_LIMIT
OK_LIMIT = $OK_LIMIT

TTL = 1
PROXIED = True

API_BASE = f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/dns_records/{RECORD_ID}"

HEADERS = {
    "Authorization": f"Bearer {CF_TOKEN}",
    "Content-Type": "application/json",
}

LOG_FILE = "$LOG_FILE"

logger = logging.getLogger()
logger.setLevel(logging.INFO)

handler = TimedRotatingFileHandler(
    LOG_FILE,
    when="midnight",
    interval=1,
    backupCount=7,
    encoding="utf-8"
)

handler.suffix = "%Y-%m-%d"

formatter = logging.Formatter(
    "%(asctime)s [%(levelname)s] %(message)s"
)

handler.setFormatter(formatter)
logger.addHandler(handler)

def log(msg):
    print(msg, flush=True)
    logging.info(msg)

def ding_notify(title, text):

    if not DINGTALK_WEBHOOK:
        return

    payload = {
        "msgtype": "markdown",
        "markdown": {
            "title": title,
            "text": text
        }
    }

    try:
        r = requests.post(
            DINGTALK_WEBHOOK,
            json=payload,
            timeout=10
        )

        if r.status_code != 200:
            logging.error(f"钉钉通知失败: HTTP {r.status_code}")

    except Exception as e:
        logging.error(f"钉钉通知异常: {e}")

def port_ok(ip, port):

    try:
        with socket.create_connection(
            (ip, port),
            timeout=CONNECT_TIMEOUT
        ):
            return True

    except OSError:
        return False

def cf_request(method, url, **kwargs):

    max_retries = 3
    retry_delay = 3

    for attempt in range(1, max_retries + 1):

        try:
            r = requests.request(
                method,
                url,
                timeout=10,
                **kwargs
            )

            r.raise_for_status()

            data = r.json()

            if not data.get("success"):
                raise RuntimeError(data)

            return data

        except Exception as e:
            logging.error(
                f"Cloudflare API 请求失败 {attempt}/{max_retries}: {e}"
            )

            if attempt < max_retries:
                time.sleep(retry_delay)

    return None

def get_current_dns_ip():

    data = cf_request(
        "GET",
        API_BASE,
        headers=HEADERS
    )

    if not data:
        return None

    return data["result"]["content"]

def change_dns(ip):

    payload = {
        "type": "A",
        "name": DOMAIN,
        "content": ip,
        "ttl": TTL,
        "proxied": PROXIED,
    }

    data = cf_request(
        "PATCH",
        API_BASE,
        headers=HEADERS,
        json=payload
    )

    if data:
        log(f"[DNS] {DOMAIN} 已切换到 {ip}")
        return True

    ding_notify(
        "Cloudflare DNS 切换失败",
        f"### DNS 切换失败\\n\\n"
        f"- 域名：{DOMAIN}\\n"
        f"- 目标 IP：{ip}\\n"
        f"- 已重试：3 次"
    )

    return False

def main():

    current_dns_ip = get_current_dns_ip()

    if current_dns_ip is None:
        current_dns_ip = PRIMARY_IP
        log("[WARN] 无法读取当前 DNS，默认主服务器")

    log(f"[START] 当前 DNS -> {current_dns_ip}")

    ding_notify(
        "Cloudflare 监控启动",
        f"### Cloudflare 监控启动\\n\\n"
        f"- 域名：{DOMAIN}\\n"
        f"- 当前 DNS：{current_dns_ip}\\n"
        f"- 主服务器：{PRIMARY_IP}:{PORT}\\n"
        f"- 备用服务器：{BACKUP_IP}"
    )

    fail_count = 0
    ok_count = 0
    normal_log_count = 0

    while True:

        alive = port_ok(PRIMARY_IP, PORT)

        if current_dns_ip == PRIMARY_IP:

            if alive:
                fail_count = 0
                normal_log_count += 1

                if normal_log_count >= 60:
                    log(f"[OK] 主服务器正常 {PRIMARY_IP}:{PORT}")
                    normal_log_count = 0

            else:
                fail_count += 1
                log(f"[FAIL] 主服务器异常 {fail_count}/{FAIL_LIMIT}")

                if fail_count >= FAIL_LIMIT:

                    if change_dns(BACKUP_IP):

                        current_dns_ip = BACKUP_IP
                        fail_count = 0
                        ok_count = 0

                        ding_notify(
                            "已切换到备用服务器",
                            f"### 主服务器故障\\n\\n"
                            f"- 域名：{DOMAIN}\\n"
                            f"- 主服务器：{PRIMARY_IP}:{PORT}\\n"
                            f"- 已切换：{BACKUP_IP}\\n"
                            f"- 连续失败：{FAIL_LIMIT} 次"
                        )

        else:

            if alive:
                ok_count += 1
                log(f"[RECOVER] 主服务器恢复 {ok_count}/{OK_LIMIT}")

                if ok_count >= OK_LIMIT:

                    if change_dns(PRIMARY_IP):

                        current_dns_ip = PRIMARY_IP
                        ok_count = 0
                        fail_count = 0
                        normal_log_count = 0

                        ding_notify(
                            "已切回主服务器",
                            f"### 主服务器恢复\\n\\n"
                            f"- 域名：{DOMAIN}\\n"
                            f"- 当前 IP：{PRIMARY_IP}\\n"
                            f"- 连续成功：{OK_LIMIT} 次"
                        )

            else:
                ok_count = 0
                log("[WAIT] 主服务器仍未恢复")

        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()
EOF

chmod +x "$APP_FILE"

echo
echo "[4/5] 创建 systemd 服务..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Cloudflare DNS Failover
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3 $APP_FILE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo
echo "[5/5] 启动服务..."

systemctl daemon-reload
systemctl enable cfdns
systemctl restart cfdns

echo
echo "======================================"
echo "安装完成"
echo "======================================"
echo
echo "查看状态："
echo "systemctl status cfdns"
echo
echo "查看实时日志："
echo "journalctl -u cfdns -f"
echo
echo "查看文件日志："
echo "tail -f /var/log/cf_failover.log"
echo
