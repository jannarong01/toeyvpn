#!/bin/bash
# =========================================
#  MY VPN AUTO-SCRIPT PROJECT (Clean & Safe)
# =========================================

# สีสำหรับตกแต่งข้อความ
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. เช็คสิทธิ์ Root
if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}กรุณารันสคริปต์นี้ด้วยสิทธิ์ root (พิมพ์ sudo su ก่อนรัน)${NC}"
    exit 1
fi

# 2. เช็คเวอร์ชัน OS (เปิดให้รองรับ Ubuntu 20.04, 22.04 และ Debian 10, 11)
source /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    echo -e "${RED}สคริปต์นี้รองรับเฉพาะ Ubuntu และ Debian เท่านั้น!${NC}"
    exit 1
fi

# 3. ดึง IP ปัจจุบันของ VPS
MYIP=$(curl -sS ipv4.icanhazip.com)
CLIENT_NAME="Jannarong (Owner)"
EXP_DATE="Lifetime"

# แสดงหน้าต่างต้อนรับสไตล์เดียวกับตัวอย่าง
clear
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
echo -e "         ${CYAN}PRIVATE VPN SCRIPT${NC}"
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
echo -e " Client Name : ${GREEN}${CLIENT_NAME}${NC}"
echo -e " IP Address  : ${GREEN}${MYIP}${NC}"
echo -e " OS Version  : ${GREEN}${PRETTY_NAME}${NC}"
echo -e " Expired on  : ${GREEN}${EXP_DATE}${NC}"
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
sleep 3

# 4. เตรียมระบบพื้นฐานและปิด IPv6 (เพื่อให้ VPN เสถียร)
echo -e "${CYAN}[INFO] กำลังอัปเดตแพ็กเกจพื้นฐาน...${NC}"
apt-get update -y
apt-get install -y wget curl jq zip unzip tar socat cron net-tools

# ลำดับต่อไป: เรียกไฟล์ติดตั้งโมดูลต่างๆ จาก GitHub ของเรา

wget -q https://raw.githubusercontent.com/jannarong01/toeyvpn/main/ssh/ssh-vpn.sh && chmod +x ssh-vpn.sh && ./ssh-vpn.sh
wget -q https://raw.githubusercontent.com/jannarong01/toeyvpn/main/xray/ins-xray.sh && chmod +x ins-xray.sh && ./ins-xray.sh
wget -q https://raw.githubusercontent.com/jannarong01/toeyvpn/main/websocket/edu.sh && chmod +x edu.sh && ./edu.sh
