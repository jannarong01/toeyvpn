#!/bin/bash
# ==========================================
#  Setup Domain & Email for VPN Script
# ==========================================

red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
NC='\e[0m'

MYIP=$(wget -qO- icanhazip.com);
apt install jq curl -y

# ล้างค่าโดเมนเก่าทิ้งทั้งหมดเพื่อป้องกันความผิดพลาด
rm -f /root/domain
rm -f /etc/v2ray/domain
rm -f /etc/xray/domain
rm -rf /etc/xray/domain
rm -rf /root/nsdomain
rm -rf /var/lib/crot/ipvps.conf
mkdir -p /usr/bin/xray
mkdir -p /usr/bin/v2ray
mkdir -p /etc/xray
mkdir -p /etc/v2ray

clear
echo -e "$yellow==================================================$NC"
echo -e "$green         CONFIGURATION DOMAIN & SSL EMAIL         $NC"
echo -e "$yellow==================================================$NC"
echo ""

# 1. รับค่าโดเมนจากผู้ใช้งาน
read -p " กรุณากรอก Domain ของคุณ (เช่น vpn.yourdomain.com): " host

if [ -z "$host" ]; then
    echo -e "$red[ERROR] โดเมนห้ามเว้นว่าง! กรุณารันสคริปต์ใหม่อีกครั้ง $NC"
    exit 1
fi

# 2. รับค่าอีเมลจากผู้ใช้งาน (สำหรับใช้ขอใบรับรอง SSL / Let's Encrypt)
read -p " กรุณากรอกอีเมลของคุณ (เช่น yourname@gmail.com): " email

if [ -z "$email" ]; then
    email="admin@$host"
    echo -e "$yellow[INFO] ไม่ได้กรอกอีเมล ระบบจะใช้อีเมลสำรอง: $email $NC"
fi

# บันทึกโดเมนและอีเมลลงในระบบ
echo "$host" > /root/domain
echo "$host" > /etc/xray/domain
echo "IP=$host" > /var/lib/crot/ipvps.conf
echo "$email" > /etc/xray/email

echo ""
echo -e "$green==================================================$NC"
echo -e "$green[✓] บันทึกโดเมนสำเร็จ : $host $NC"
echo -e "$green[✓] บันทึกอีเมลสำเร็จ : $email $NC"
echo -e "$green==================================================$NC"
cd