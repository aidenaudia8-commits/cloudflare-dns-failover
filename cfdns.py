#!/usr/bin/env python3

import socket
import time
import logging
import requests

from logging.handlers import TimedRotatingFileHandler

# ==========================================
# Cloudflare 配置
# ==========================================

CF_TOKEN = "cfut_xxx"
ZONE_ID = "xxx"
RECORD_ID = "xxx"

DOMAIN = "demo.com"

PRIMARY_IP = "1.1.1.1"
BACKUP_IP = "2.2.2.2"

PORT = 80

# =========================
# 钉钉通知
# =========================

DINGTALK_WEBHOOK = "https://oapi.dingtalk.com/robot/send?access_token=xxx"

# ==========================================
# 检测参数
# ==========================================

CHECK_INTERVAL = 10
CONNECT_TIMEOUT = 3

FAIL_LIMIT = 5
OK_LIMIT = 5

TTL = 1
PROXIED = True

# ==========================================
# Cloudflare API
# ==========================================

API_BASE = f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/dns_records/{RECORD_ID}"

HEADERS = {
    "Authorization": f"Bearer {CF_TOKEN}",
    "Content-Type": "application/json",
}

# ==========================================
# 日志配置
# 每天生成一个日志
# 保留 7 天
# 第 8 天自动删除
# ==========================================

LOG_FILE = "/var/log/cf_failover.log"

logger = logging.getLogger()
logger.setLevel(logging.INFO)

handler = TimedRotatingFileHandler(
    LOG_FILE,
    when="midnight",      # 每天 0 点切割
    interval=1,
    backupCount=7,        # 保留 7 天
    encoding="utf-8"
)

handler.suffix = "%Y-%m-%d"

formatter = logging.Formatter(
    "%(asctime)s [%(levelname)s] %(message)s"
)

handler.setFormatter(formatter)
logger.addHandler(handler)

# ==========================================
# 日志函数
# ==========================================

def log(msg):
    print(msg)
    logging.info(msg)

# ==========================================
# 钉钉通知
# ==========================================

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

# ==========================================
# TCP 检测
# ==========================================

def port_ok(ip, port):

    try:

        with socket.create_connection(
            (ip, port),
            timeout=CONNECT_TIMEOUT
        ):

            return True

    except OSError:

        return False

# ==========================================
# Cloudflare API 重试
# ==========================================

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
                f"Cloudflare API 请求失败 "
                f"{attempt}/{max_retries}: {e}"
            )

            if attempt < max_retries:
                time.sleep(retry_delay)

    return None

# ==========================================
# 获取当前 DNS IP
# ==========================================

def get_current_dns_ip():

    data = cf_request(
        "GET",
        API_BASE,
        headers=HEADERS
    )

    if not data:
        return None

    return data["result"]["content"]

# ==========================================
# 修改 DNS
# ==========================================

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
        f"### DNS 切换失败\n\n"
        f"- 域名：{DOMAIN}\n"
        f"- 目标 IP：{ip}\n"
        f"- 已重试：3 次"
    )

    return False

# ==========================================
# 主逻辑
# ==========================================

def main():

    current_dns_ip = get_current_dns_ip()

    if current_dns_ip is None:

        current_dns_ip = PRIMARY_IP

        log("[WARN] 无法读取当前 DNS，默认主服务器")

    log(f"[START] 当前 DNS -> {current_dns_ip}")

    ding_notify(
        "Cloudflare 监控启动",
        f"### Cloudflare 监控启动\n\n"
        f"- 域名：{DOMAIN}\n"
        f"- 当前 DNS：{current_dns_ip}\n"
        f"- 主服务器：{PRIMARY_IP}:{PORT}\n"
        f"- 备用服务器：{BACKUP_IP}"
    )

    fail_count = 0
    ok_count = 0

    # 控制正常日志频率
    normal_log_count = 0

    while True:

        alive = port_ok(PRIMARY_IP, PORT)

        # ==========================================
        # 当前是主服务器
        # ==========================================

        if current_dns_ip == PRIMARY_IP:

            if alive:

                fail_count = 0

                normal_log_count += 1

                # 每 60 次记录一次正常日志
                # 10 秒检测一次 = 10 分钟记录一次
                if normal_log_count >= 60:

                    log(f"[OK] 主服务器正常 {PRIMARY_IP}:{PORT}")

                    normal_log_count = 0

            else:

                fail_count += 1

                log(
                    f"[FAIL] 主服务器异常 "
                    f"{fail_count}/{FAIL_LIMIT}"
                )

                if fail_count >= FAIL_LIMIT:

                    if change_dns(BACKUP_IP):

                        current_dns_ip = BACKUP_IP

                        fail_count = 0
                        ok_count = 0

                        ding_notify(
                            "已切换到备用服务器",
                            f"### 主服务器故障\n\n"
                            f"- 域名：{DOMAIN}\n"
                            f"- 主服务器：{PRIMARY_IP}:{PORT}\n"
                            f"- 已切换：{BACKUP_IP}\n"
                            f"- 连续失败：{FAIL_LIMIT} 次"
                        )

        # ==========================================
        # 当前是备用服务器
        # ==========================================

        else:

            if alive:

                ok_count += 1

                log(
                    f"[RECOVER] 主服务器恢复 "
                    f"{ok_count}/{OK_LIMIT}"
                )

                if ok_count >= OK_LIMIT:

                    if change_dns(PRIMARY_IP):

                        current_dns_ip = PRIMARY_IP

                        ok_count = 0
                        fail_count = 0
                        normal_log_count = 0

                        ding_notify(
                            "已切回主服务器",
                            f"### 主服务器恢复\n\n"
                            f"- 域名：{DOMAIN}\n"
                            f"- 当前 IP：{PRIMARY_IP}\n"
                            f"- 连续成功：{OK_LIMIT} 次"
                        )

            else:

                ok_count = 0

                log("[WAIT] 主服务器仍未恢复")

        time.sleep(CHECK_INTERVAL)

# ==========================================
# 启动
# ==========================================

if __name__ == "__main__":
    main()
