#!/bin/bash
# ==============================================================================
#  MAIN INSTALLER (SETUP.SH) - PRIVATE VPN ALL-IN-ONE SUITE
#  Support: Ubuntu 20.04 / 22.04 / 24.04 LTS & Debian 10 / 11 / 12
# ==============================================================================
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 1. ตรวจสอบสิทธิ์ Root
if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}กรุณารันสคริปต์นี้ด้วยสิทธิ์ root เท่านั้น!${NC}"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
REPO_URL="https://raw.githubusercontent.com/jannarong01/toeyvpn/main"
MYIP=$(curl -sS ipv4.icanhazip.com)

clear
echo -e "${YELLOW}==========================================================${NC}"
echo -e "        ${CYAN}WELCOME TO PRIVATE VPN AUTO-INSTALLER${NC}"
echo -e "   ${GREEN}SSH/WS • XRAY • ZIVPN UDP • HYSTERIA 2 • WEB API${NC}"
echo -e "${YELLOW}==========================================================${NC}"
echo -e ""

# 2. รับค่าโดเมนสำหรับทำ SSL (Port 443 & Hysteria 2)
mkdir -p /etc/xray /etc/zivpn /etc/hysteria
read -rp "กรอกชื่อโดเมนของคุณ (หากไม่มี ให้กด Enter เพื่อใช้ IP ${MYIP}): " user_domain
if [[ -n "$user_domain" ]]; then
    DOMAIN="$user_domain"
else
    DOMAIN="$MYIP"
fi

echo "$DOMAIN" > /etc/xray/domain
echo "$DOMAIN" > /root/domain
echo -e "${GREEN}ตั้งค่า Host/Domain เป็น: ${DOMAIN}${NC}\n"
sleep 2

# 3. อัปเดตระบบพื้นฐาน และซิงค์เวลาป้องกันปัญหา Xray Time Out
echo -e "${CYAN}[1/5] กำลังเตรียมระบบพื้นฐานและซิงค์เวลามาตรฐาน (Asia/Bangkok)...${NC}"
apt-get update -y
apt-get install -y wget curl jq dos2unix openssl net-tools chrony socat cron rsyslog zip unzip
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
systemctl enable chrony >/dev/null 2>&1
systemctl restart chrony
chronyc makestep >/dev/null 2>&1

# 4. เปิดใช้งาน TCP BBR และปรับแต่ง Kernel ให้รองรับ High-Speed UDP
echo -e "${CYAN}[2/5] กำลังเปิดใช้งานระบบเร่งความเร็วเครือข่าย (TCP BBR & UDP Buffer)...${NC}"
grep -qxF 'net.core.default_qdisc=fq' /etc/sysctl.conf || echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
grep -qxF 'net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf || echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
grep -qxF 'net.core.rmem_max=16777216' /etc/sysctl.conf || echo 'net.core.rmem_max=16777216' >> /etc/sysctl.conf
grep -qxF 'net.core.wmem_max=16777216' /etc/sysctl.conf || echo 'net.core.wmem_max=16777216' >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

# 5. ติดตั้ง Xray Core & Nginx SSL (รันก่อนเพื่อสร้าง SSL Cert และตั้งค่า Nginx 80/443)
echo -e "${CYAN}[3/5] กำลังติดตั้ง Xray Core (Vmess/Vless) และตั้งค่า SSL...${NC}"
wget -q -O /root/ins-xray.sh "${REPO_URL}/xray/ins-xray.sh"
if [ -s /root/ins-xray.sh ]; then
    dos2unix /root/ins-xray.sh >/dev/null 2>&1
    chmod +x /root/ins-xray.sh
    ./ins-xray.sh
    rm -f /root/ins-xray.sh
else
    echo -e "${RED}ไม่พบไฟล์ xray/ins-xray.sh บน GitHub!${NC}"
fi

# 6. ติดตั้ง SSH, Dropbear, ZIVPN UDP, Hysteria 2, Web API (8081), Security & Menu
echo -e "${CYAN}[4/5] กำลังติดตั้ง SSH, ZIVPN, Hysteria 2, Web API (8081) และระบบความปลอดภัย...${NC}"
wget -q -O /root/ssh-vpn.sh "${REPO_URL}/ssh/ssh-vpn.sh"
if [ -s /root/ssh-vpn.sh ]; then
    dos2unix /root/ssh-vpn.sh >/dev/null 2>&1
    chmod +x /root/ssh-vpn.sh
    ./ssh-vpn.sh
    rm -f /root/ssh-vpn.sh
else
    echo -e "${RED}ไม่พบไฟล์ ssh/ssh-vpn.sh บน GitHub!${NC}"
fi

# 7. ติดตั้งระบบ SSH WebSocket (Port 10015 -> Nginx 80/443)
echo -e "${CYAN}[5/5] กำลังติดตั้งบริการ SSH WebSocket (ws-epro)...${NC}"
wget -q -O /root/insshws.sh "${REPO_URL}/websocket/insshws.sh"
if [ -s /root/insshws.sh ]; then
    dos2unix /root/insshws.sh >/dev/null 2>&1
    chmod +x /root/insshws.sh
    ./insshws.sh
    rm -f /root/insshws.sh
else
    # Fallback สร้าง Python WebSocket Proxy อัตโนมัติหากไม่มีไฟล์ในโฟลเดอร์ websocket
    cat << 'EOF' > /usr/local/bin/ws-epro
#!/usr/bin/env python3
import socket, threading, select, sys

LISTEN_PORT = 10015
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 22

def handle_client(client_sock):
    try:
        client_sock.recv(4096)
        client_sock.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_sock.connect((TARGET_HOST, TARGET_PORT))
        sockets = [client_sock, target_sock]
        while True:
            r, _, _ = select.select(sockets, [], [], 60)
            if not r:
                break
            for s in r:
                data = s.recv(8192)
                if not data:
                    return
                if s is client_sock:
                    target_sock.sendall(data)
                else:
                    client_sock.sendall(data)
    except Exception:
        pass
    finally:
        try: client_sock.close()
        except: pass
        try: target_sock.close()
        except: pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', LISTEN_PORT))
    server.listen(500)
    while True:
        client_sock, _ = server.accept()
        threading.Thread(target=handle_client, args=(client_sock,), daemon=True).start()

if __name__ == '__main__':
    main()
EOF
    chmod +x /usr/local/bin/ws-epro

    cat <<EOF > /etc/systemd/system/ws-epro.service
[Unit]
Description=SSH WebSocket Proxy Service (Port 10015)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-epro
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ws-epro >/dev/null 2>&1
    systemctl restart ws-epro
fi

# 8. รีสตาร์ทบริการทั้งหมดเพื่อให้ซิงค์ SSL และค่าคอนฟิกล่าสุด
systemctl restart rsyslog ssh dropbear nginx php*-fpm xray zivpn hysteria ws-epro udpgw@7100 udpgw@7200 udpgw@7300 fail2ban cron >/dev/null 2>&1

# ตั้งให้แสดงคำสั่งเมื่อเปิดเข้าหน้าต่าง Terminal
grep -qxF 'echo -e "พิมพ์คำสั่ง \033[0;32mmenu\033[0m เพื่อเข้าสู่หน้าจัดการระบบ VPN"' /root/.bashrc || \
echo 'echo -e "พิมพ์คำสั่ง \033[0;32mmenu\033[0m เพื่อเข้าสู่หน้าจัดการระบบ VPN"' >> /root/.bashrc

CUR_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php 2>/dev/null | cut -d'"' -f2 || echo "VNEXT_SSH_999")

clear
echo -e "${YELLOW}==========================================================${NC}"
echo -e "         ${GREEN}ติดตั้งระบบ PRIVATE VPN เสร็จสมบูรณ์ 100%!${NC}"
echo -e "${YELLOW}==========================================================${NC}"
echo -e " IP Address        : ${GREEN}${MYIP}${NC}"
echo -e " Domain            : ${GREEN}${DOMAIN}${NC}"
echo -e " OpenSSH / Dropbear: 22 / 109, 143"
echo -e " SSH WebSocket     : 80 (HTTP), 443 (SSL/TLS)"
echo -e " Xray Vmess/Vless  : 80 (HTTP), 443 (SSL/TLS)"
echo -e " ZIVPN UDP         : 5667, 6000-19999 (UDP)"
echo -e " Hysteria 2 QUIC   : 8443, 20000-50000 (UDP)"
echo -e " BadVPN UDPGW      : 7100, 7200, 7300"
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e " ${CYAN}[ข้อมูลสำหรับเชื่อมเว็บขาย VPN (toeyvpn.com)]${NC}"
echo -e " URL API           : ${GREEN}http://${MYIP}:8081/api_ssh.php${NC}"
echo -e " Secret Key        : ${GREEN}${CUR_KEY}${NC}"
echo -e "${YELLOW}==========================================================${NC}"
echo -e " พิมพ์คำสั่ง ${GREEN}menu${NC} เพื่อเข้าสู่หน้าจัดการระบบ หรือ ${GREEN}running${NC} เพื่อเช็กสถานะ"
echo -e "${YELLOW}==========================================================${NC}"
rm -f /root/setup.sh
