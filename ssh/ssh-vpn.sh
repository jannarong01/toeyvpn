#!/bin/bash
# =========================================
#  XRAY CORE & NGINX SSL (PORT 80 / 443)
# =========================================
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

MYIP=$(curl -sS ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "$MYIP")

# 1. ติดตั้งแพ็กเกจที่จำเป็นและ Xray Core
apt-get update -y
apt-get install -y socat openssl cron jq curl
echo -e "${CYAN}กำลังดาวน์โหลดและติดตั้ง Xray Core...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# สร้างโฟลเดอร์และไฟล์ Log พร้อมให้สิทธิ์ 777 ป้องกัน Permission Denied
mkdir -p /etc/xray
mkdir -p /var/log/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chmod -R 777 /var/log/xray

# 2. ระบบขอใบรับรอง SSL (Let's Encrypt หรือ Self-Signed Fallback)
systemctl stop nginx >/dev/null 2>&1

if [[ "$DOMAIN" != "$MYIP" ]]; then
    echo -e "${CYAN}กำลังขอใบรับรอง SSL (Let's Encrypt) สำหรับโดเมน ${DOMAIN}...${NC}"
    curl https://get.acme.sh | sh -s email=admin@${DOMAIN}
    /root/.acme.sh/acme.sh --upgrade --auto-upgrade
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    /root/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone -k ec-256 --force
    /root/.acme.sh/acme.sh --installcert -d "${DOMAIN}" \
        --fullchainpath /etc/xray/xray.crt \
        --keypath /etc/xray/xray.key --ecc
fi

if [[ ! -s /etc/xray/xray.crt || ! -s /etc/xray/xray.key ]]; then
    echo -e "${YELLOW}สร้างใบรับรอง SSL จำลอง (Self-Signed) สำหรับพอร์ต 443...${NC}"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/xray/xray.key \
        -out /etc/xray/xray.crt \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=PrivateVPN/CN=${DOMAIN}" >/dev/null 2>&1
fi

chmod 644 /etc/xray/xray.crt /etc/xray/xray.key

# 3. สร้างไฟล์ตั้งค่า /etc/xray/config.json
UUID=$(cat /proc/sys/kernel/random/uuid)

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
            "alterId": 0,
            "email": "default"
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
            "id": "${UUID}",
            "email": "default"
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

# 4. บันทึกข้อมูลบัญชีเริ่มต้น
cat <<EOF > /etc/xray/client-info.txt
=========================================
         ข้อมูลบัญชีเริ่มต้น Xray Core
=========================================
Host / Domain : ${DOMAIN}
Port HTTP     : 80
Port SSL/TLS  : 443
UUID          : ${UUID}
Network       : WebSocket (ws)
Path Vmess    : /vmess
Path Vless    : /vless
=========================================
EOF

# 5. ตั้งค่า Nginx Reverse Proxy ให้รับทั้งพอร์ต 80 และ 443
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/conf.d/*.conf

cat << 'EOF' > /etc/nginx/conf.d/vpn.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name _;

    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

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

# 6. บังคับให้ Xray Service อ่านไฟล์จาก /etc/xray/config.json โดยตรง (ปลดข้อจำกัดสิทธิ์)
rm -rf /etc/systemd/system/xray.service.d
cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1
systemctl restart xray
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx
echo -e "${GREEN}Xray & Nginx SSL (Port 80/443) Installed Successfully!${NC}"
