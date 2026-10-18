#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p /etc/xray
MYIP=$(curl -sS ipv4.icanhazip.com)

echo -e "${YELLOW}-----------------------------------------${NC}"
echo -e "  ตั้งค่าโดเมนสำหรับเซิร์ฟเวอร์ (กด Enter เพื่อใช้ IP แทนได้)"
echo -e "${YELLOW}-----------------------------------------${NC}"
read -rp "กรุณากรอกโดเมนของคุณ (เช่น vpn.example.com): " USER_DOMAIN

if [[ -z "$USER_DOMAIN" ]]; then
    DOMAIN="$MYIP"
    echo -e "${GREEN}ไม่ได้ระบุโดเมน ระบบจะใช้ IP: ${DOMAIN} แทน${NC}"
else
    DOMAIN="$USER_DOMAIN"
    echo -e "${GREEN}บันทึกโดเมน: ${DOMAIN} เรียบร้อยแล้ว${NC}"
fi

echo "$DOMAIN" > /etc/xray/domain
echo "$DOMAIN" > /root/domain
sleep 1