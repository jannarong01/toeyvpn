#!/bin/bash
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

DOMAIN=$(cat /etc/xray/domain 2>/dev/null || curl -sS ipv4.icanhazip.com)

# 1. ติดตั้ง Xray Core จาก Official
echo -e "${CYAN}กำลังดาวน์โหลดและติดตั้ง Xray Core...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 2. สุ่มค่า UUID สำหรับใช้งานเริ่มต้น
UUID=$(cat /proc/sys/kernel/random/uuid)
mkdir -p /etc/xray

# 3. สร้างไฟล์ตั้งค่า /etc/xray/config.json (ครอบด้วย EOF ป้องกัน Error)
cat <<EOF > /etc/xray/config.json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# 4. บันทึกข้อมูล Client ไว้ดูผ่านคำสั่ง menu
cat <<EOF > /etc/xray/client-info.txt
=========================================
         ข้อมูลบัญชีเริ่มต้น Xray Core
=========================================
Host / Domain : ${DOMAIN}
Port          : 80
UUID          : ${UUID}
Network       : WebSocket (ws)
Path Vmess    : /vmess
Path Vless    : /vless
=========================================
EOF

# 5. ตั้งค่า Nginx Reverse Proxy ให้แชร์พอร์ต 80 ร่วมกัน
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/conf.d/*.conf

cat << 'EOF' > /etc/nginx/conf.d/vpn.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # ส่งต่อ Path /vmess ไปยัง Xray พอร์ต 10001
    location /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # ส่งต่อ Path /vless ไปยัง Xray พอร์ต 10002
    location /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # ส่งต่อ Path อื่นๆ ทั้งหมดไปยัง SSH WebSocket พอร์ต 10015
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10015;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

systemctl enable xray
systemctl restart xray
systemctl enable nginx
systemctl restart nginx
echo -e "${GREEN}Xray & Nginx Reverse Proxy Installed Successfully!${NC}"