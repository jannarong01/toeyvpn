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
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
REPO_URL="https://raw.githubusercontent.com/jannarong01/toeyvpn/main"
MYIP=$(curl -sS ipv4.icanhazip.com)

clear
echo -e "${YELLOW}==========================================================${NC}"
echo -e "        ${CYAN}WELCOME TO PRIVATE VPN AUTO-INSTALLER${NC}"
echo -e "  ${GREEN}SSH/WS • UDP CUSTOM • XRAY • ZIVPN • HYSTERIA 2 • API${NC}"
echo -e "${YELLOW}==========================================================${NC}"
echo -e ""

# 2. รับค่าโดเมนสำหรับทำ SSL (Port 443 & Hysteria 2)
mkdir -p /etc/xray /etc/zivpn /etc/hysteria /root/udp
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

# 3. รอปลดล็อก apt/dpkg และอัปเดตระบบพื้นฐาน + ซิงค์เวลามาตรฐาน (Asia/Bangkok)
echo -e "${CYAN}[1/4] กำลังเตรียมระบบพื้นฐานและซิงค์เวลามาตรฐาน (Asia/Bangkok)...${NC}"
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ ระบบกำลังอัปเดตแพ็กเกจพื้นหลังของ VPS... กรุณารอสักครู่"
    sleep 3
done
dpkg --configure -a >/dev/null 2>&1

apt-get update -y
apt-get install -y wget curl jq dos2unix openssl net-tools chrony socat cron rsyslog zip unzip psmisc
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
systemctl enable chrony >/dev/null 2>&1
systemctl restart chrony
chronyc makestep >/dev/null 2>&1

# 4. เปิดใช้งาน TCP BBR, IPv4 Forwarding และปรับแต่ง Kernel ให้รองรับ High-Speed UDP
echo -e "${CYAN}[2/4] กำลังเปิดใช้งานระบบเร่งความเร็วเครือข่าย (TCP BBR & UDP Buffer)...${NC}"
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
grep -qxF 'net.core.default_qdisc=fq' /etc/sysctl.conf || echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
grep -qxF 'net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf || echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
grep -qxF 'net.core.rmem_max=16777216' /etc/sysctl.conf || echo 'net.core.rmem_max=16777216' >> /etc/sysctl.conf
grep -qxF 'net.core.wmem_max=16777216' /etc/sysctl.conf || echo 'net.core.wmem_max=16777216' >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

# 5. ติดตั้ง Xray Core & Nginx SSL (รันก่อนเพื่อสร้าง SSL Cert และตั้งค่า Nginx 80/443)
echo -e "${CYAN}[3/4] กำลังติดตั้ง Xray Core (Vmess/Vless) และตั้งค่า SSL...${NC}"
wget -4 -q --no-check-certificate -O /root/ins-xray.sh "${REPO_URL}/xray/ins-xray.sh?v=$(date +%s)"
if [ -s /root/ins-xray.sh ]; then
    sed -i 's/\r$//' /root/ins-xray.sh
    dos2unix /root/ins-xray.sh >/dev/null 2>&1
    chmod +x /root/ins-xray.sh
    /root/ins-xray.sh
    rm -f /root/ins-xray.sh
else
    echo -e "${RED}ไม่พบไฟล์ xray/ins-xray.sh บน GitHub!${NC}"
fi

# 6. ติดตั้ง SSH, WS, UDP Custom (7200), BadVPN (7300), ZIVPN, Hysteria 2, Web API (8081) & Menu
echo -e "${CYAN}[4/4] กำลังติดตั้ง SSH, UDP Custom, ZIVPN, Hysteria 2, Web API (8081) และเมนูจัดการ...${NC}"
wget -4 -q --no-check-certificate -O /root/ssh-vpn.sh "${REPO_URL}/ssh/ssh-vpn.sh?v=$(date +%s)"
if [ -s /root/ssh-vpn.sh ]; then
    sed -i 's/\r$//' /root/ssh-vpn.sh
    dos2unix /root/ssh-vpn.sh >/dev/null 2>&1
    chmod +x /root/ssh-vpn.sh
    /root/ssh-vpn.sh
    rm -f /root/ssh-vpn.sh
else
    echo -e "${RED}ไม่พบไฟล์ ssh/ssh-vpn.sh บน GitHub!${NC}"
fi

# 7. รีสตาร์ทบริการทั้งหมดเพื่อให้ซิงค์ SSL และค่าคอนฟิกล่าสุด
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
chmod +x /usr/bin/menu /usr/bin/running 2>/dev/null
systemctl daemon-reload
systemctl restart rsyslog ssh dropbear nginx php*-fpm xray zivpn hysteria udp-custom ws-epro udpgw@7100 udpgw@7300 fail2ban cron >/dev/null 2>&1

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
echo -e " UDP Custom        : 1-65535 (Internal Port 7200)"
echo -e " BadVPN UDPGW      : 7100, 7300"
echo -e " Xray Vmess/Vless  : 80 (HTTP), 443 (SSL/TLS)"
echo -e " ZIVPN UDP         : 5667, 6000-19999 (UDP)"
echo -e " Hysteria 2 QUIC   : 8443, 20000-50000 (UDP)"
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e " ${CYAN}[ข้อมูลสำหรับเชื่อมเว็บขาย VPN (toeyvpn.com)]${NC}"
echo -e " URL API           : ${GREEN}http://${MYIP}:8081/api_ssh.php${NC}"
echo -e " Secret Key        : ${GREEN}${CUR_KEY}${NC}"
echo -e "${YELLOW}==========================================================${NC}"
echo -e " พิมพ์คำสั่ง ${GREEN}menu${NC} เพื่อเข้าสู่หน้าจัดการระบบ หรือ ${GREEN}running${NC} เพื่อเช็กสถานะ"
echo -e "${YELLOW}==========================================================${NC}"
rm -f /root/setup.sh