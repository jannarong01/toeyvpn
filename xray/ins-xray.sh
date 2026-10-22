#!/bin/bash
# ==============================================================================
#  XRAY CORE & NGINX REVERSE PROXY INSTALLER (VMESS / VLESS / SSH-WS)
# ==============================================================================
export DEBIAN_FRONTEND=noninteractive

MYIP=$(curl -sS ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "$MYIP")

apt-get update -y
apt-get install -y curl wget jq socat openssl nginx xz-utils

# 1. ติดตั้ง Xray Core
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

mkdir -p /etc/xray /var/log/xray
touch /etc/xray/xray-exp.txt /etc/xray/xray-lock.txt /var/log/xray/access.log /var/log/xray/error.log
chmod -R 777 /var/log/xray

# 2. ขอใบรับรอง SSL (Let's Encrypt) หรือสร้าง Self-Signed กรณีใช้ IP
systemctl stop nginx >/dev/null 2>&1
if [[ "$DOMAIN" != "$MYIP" ]]; then
    curl https://get.acme.sh | sh -s email=admin@${DOMAIN}
    /root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    /root/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone -k ec-256 --force
    /root/.acme.sh/acme.sh --installcert -d "${DOMAIN}" \
        --fullchainpath /etc/xray/xray.crt \
        --keypath /etc/xray/xray.key --ecc
fi

if [[ ! -s /etc/xray/xray.crt || ! -s /etc/xray/xray.key ]]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/xray/xray.key \
        -out /etc/xray/xray.crt \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=PrivateVPN/CN=${DOMAIN}" >/dev/null 2>&1
fi
chmod 644 /etc/xray/xray.crt /etc/xray/xray.key

# 3. สร้างไฟล์ตั้งค่า Xray (/etc/xray/config.json)
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
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 4. ตั้งค่า Nginx สำหรับพอร์ต 80 และ 443 (ลบหน้า Default ออกป้องกัน 200 OK)
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
rm -f /etc/nginx/conf.d/default.conf

cat << 'EOF' > /etc/nginx/conf.d/xray.conf
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
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
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

systemctl daemon-reload
systemctl enable xray nginx >/dev/null 2>&1
systemctl restart xray nginx
