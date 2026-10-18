#!/bin/bash
# =========================================
#  MY VPN AUTO-SCRIPT PROJECT (Clean & Safe)
# =========================================

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

# 2. เช็คเวอร์ชัน OS
source /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    echo -e "${RED}สคริปต์นี้รองรับเฉพาะ Ubuntu และ Debian เท่านั้น!${NC}"
    exit 1
fi

# 3. สร้างโฟลเดอร์เก็บข้อมูลและดึง IP
mkdir -p /etc/xray
MYIP=$(curl -sS ipv4.icanhazip.com)
CLIENT_NAME="Jannarong (Owner)"
EXP_DATE="Lifetime"
REPO="https://raw.githubusercontent.com/jannarong01/toeyvpn/main"

clear
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
echo -e "         ${CYAN}PRIVATE VPN SCRIPT${NC}"
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
echo -e " Client Name : ${GREEN}${CLIENT_NAME}${NC}"
echo -e " IP Address  : ${GREEN}${MYIP}${NC}"
echo -e " OS Version  : ${GREEN}${PRETTY_NAME}${NC}"
echo -e " Expired on  : ${GREEN}${EXP_DATE}${NC}"
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
sleep 2

# 4. อัปเดตแพ็กเกจพื้นฐานและติดตั้ง dos2unix ป้องกันไฟล์เสีย
echo -e "${CYAN}[INFO] กำลังอัปเดตแพ็กเกจพื้นฐาน...${NC}"
apt-get update -y
apt-get install -y wget curl jq zip unzip tar socat cron net-tools dos2unix python3

# 5. ตั้งค่า Domain (slhost.sh)
echo -e "${CYAN}[1/4] กำลังตั้งค่าโดเมน...${NC}"
wget -q -O /root/slhost.sh "${REPO}/ssh/slhost.sh"
dos2unix /root/slhost.sh
chmod +x /root/slhost.sh
./slhost.sh

# 6. ติดตั้ง SSH, Dropbear, Nginx และระบบ Menu (ssh-vpn.sh)
echo -e "${CYAN}[2/4] กำลังติดตั้งระบบ SSH และ Nginx...${NC}"
wget -q -O /root/ssh-vpn.sh "${REPO}/ssh/ssh-vpn.sh"
dos2unix /root/ssh-vpn.sh
chmod +x /root/ssh-vpn.sh
./ssh-vpn.sh

# 7. ติดตั้ง Xray Core และตั้งค่า Reverse Proxy (ins-xray.sh)
echo -e "${CYAN}[3/4] กำลังติดตั้งระบบ Xray Core...${NC}"
wget -q -O /root/ins-xray.sh "${REPO}/xray/ins-xray.sh"
dos2unix /root/ins-xray.sh
chmod +x /root/ins-xray.sh
./ins-xray.sh

# 8. ติดตั้งระบบ SSH WebSocket (edu.sh)
echo -e "${CYAN}[4/4] กำลังติดตั้งระบบ WebSocket...${NC}"
wget -q -O /root/edu.sh "${REPO}/websocket/edu.sh"
dos2unix /root/edu.sh
chmod +x /root/edu.sh
./edu.sh

# 9. บันทึก Log การติดตั้ง
cat <<EOF > /root/log-install.txt
=========================================
      รายละเอียดการติดตั้ง VPN Script
=========================================
- OpenSSH                 : 22
- Dropbear                : 109, 143
- Nginx Reverse Proxy     : 80
- SSH WebSocket           : 80 (Path: /)
- Vmess WS                : 80 (Path: /vmess)
- Vless WS                : 80 (Path: /vless)
=========================================
EOF

# ลบไฟล์ติดตั้งชั่วคราว
rm -f /root/slhost.sh /root/ssh-vpn.sh /root/ins-xray.sh /root/edu.sh

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  ติดตั้งเสร็จสมบูรณ์! พิมพ์คำสั่ง menu เพื่อใช้งาน  ${NC}"
echo -e "${GREEN}=========================================${NC}"