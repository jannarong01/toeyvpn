#!/bin/bash
# ==============================================================================
#  ALL-IN-ONE VPN SUITE: SSH/WS, UDP CUSTOM, BADVPN, ZIVPN, HYSTERIA 2, WEB PANEL
#  Support: Ubuntu 20.04 / 22.04 / 24.04 LTS & Debian 10 / 11 / 12
# ==============================================================================
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 0. รอให้ระบบอัปเดตอัตโนมัติหลังเปิดเครื่องใหม่ (apt/dpkg lock) ทำงานเสร็จก่อนเริ่มติดตั้ง
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ ระบบกำลังอัปเดตแพ็กเกจพื้นหลังของ VPS... กรุณารอสักครู่ (รอปลดล็อก dpkg)"
    sleep 3
done
dpkg --configure -a >/dev/null 2>&1

# 1. ลบ Apache2 และ UFW ป้องกันการแย่งพอร์ต 80
systemctl stop apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
apt-get purge -y ufw firewalld exim4 apache2 apache2-utils apache2-bin apache2-data >/dev/null 2>&1
apt-get autoremove -y >/dev/null 2>&1

# 2. ตั้งค่า Timezone เป็นเวลาไทย และเปิด IPv4 Forwarding
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
if ! grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -p >/dev/null 2>&1

# 3. ติดตั้งแพ็กเกจหลัก + PHP-FPM + Fail2Ban + Iptables-Persistent + Zip/Unzip + Rsyslog
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update -y
apt-get install -y nginx dropbear vnstat curl wget jq python3 net-tools openssl socat cron fail2ban iptables iptables-persistent psmisc dos2unix php-fpm php-cli php-curl zip unzip rsyslog tar util-linux

# ติดตั้ง Speedtest by Ookla (Official CLI)
if [ ! -s /usr/local/bin/speedtest ]; then
    echo "กำลังติดตั้ง Speedtest by Ookla..."
    ARCH=$(uname -m)
    S_ARCH="x86_64"
    if [ "$ARCH" = "aarch64" ]; then S_ARCH="aarch64"; fi
    if [ "$ARCH" = "arm64" ]; then S_ARCH="aarch64"; fi
    wget -q -O /tmp/speedtest.tgz "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${S_ARCH}.tgz"
    tar -xzf /tmp/speedtest.tgz -C /usr/local/bin speedtest 2>/dev/null
    chmod +x /usr/local/bin/speedtest
    rm -f /tmp/speedtest.tgz
fi

# เปิดใช้งาน rsyslog และเตรียมไฟล์ Log สำหรับ Ubuntu 24.04 และ Debian 12
touch /var/log/auth.log /var/log/syslog
systemctl enable rsyslog >/dev/null 2>&1
systemctl restart rsyslog

# ปลดล็อก OpenSSH 9.2+ บน Debian 12 / Ubuntu 24.04 ให้รองรับแอปมือถือ (ssh-rsa & PasswordAuth)
mkdir -p /etc/ssh/sshd_config.d
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
cat <<EOF > /etc/ssh/sshd_config.d/99-vpn-compat.conf
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAcceptedKeyTypes +ssh-rsa,ssh-dss
HostKeyAlgorithms +ssh-rsa,ssh-dss
KexAlgorithms +diffie-hellman-group1-sha1,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1
EOF
systemctl restart ssh

# ลบหน้าเริ่มต้นของ Nginx (แก้ปัญหา HTTP 200 OK Welcome to nginx บน Debian 12)
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

# 4. ตั้งค่าระบบป้องกันการสุ่มรหัสผ่าน (Fail2Ban)
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log
backend = auto

[dropbear]
enabled = true
port = 109,143
logpath = /var/log/auth.log
backend = auto
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

# 5. ตั้งค่า Iptables บล็อก BitTorrent / P2P
for keyword in "get_peers" "announce_peer" "find_node" "BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "torrent" "announce" "info_hash"; do
    if ! iptables -C FORWARD -m string --string "$keyword" --algo bm -j DROP 2>/dev/null; then
        iptables -A FORWARD -m string --string "$keyword" --algo bm -j DROP
    fi
    if ! iptables -C OUTPUT -m string --string "$keyword" --algo bm -j DROP 2>/dev/null; then
        iptables -A OUTPUT -m string --string "$keyword" --algo bm -j DROP
    fi
done

# 6. เตรียมโฟลเดอร์หลัก, ถามชื่อโดเมน (เฉพาะเครื่องใหม่) และสร้าง SSL เบื้องต้น
mkdir -p /etc/xray /etc/zivpn /etc/hysteria /home/vps/public_html /root/vnext_api /root/udp
touch /etc/xray/xray-exp.txt /etc/xray/xray-lock.txt /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt /etc/hysteria/hys-users.txt

MYIP=$(curl -sS ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)

# ถ้ายังไม่มีไฟล์โดเมน (ติดตั้งเครื่องใหม่ครั้งแรก) ให้ถามโดเมนก่อน
if [ -z "$DOMAIN" ]; then
    clear
    echo "======================================================"
    echo "   🌐 ตั้งค่าโดเมนสำหรับเซิร์ฟเวอร์ VPN เครื่องใหม่"
    echo "======================================================"
    read -rp "กรุณากรอกชื่อโดเมนของคุณ (หรือกด Enter เพื่อใช้ IP): " INPUT_DOMAIN
    if [ -n "$INPUT_DOMAIN" ]; then
        DOMAIN="$INPUT_DOMAIN"
    else
        DOMAIN="$MYIP"
    fi
    echo "$DOMAIN" > /etc/xray/domain
    echo "$DOMAIN" > /root/domain
fi

if [ ! -s /etc/xray/xray.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/xray/xray.key \
        -out /etc/xray/xray.crt \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=PrivateVPN/CN=${DOMAIN}" >/dev/null 2>&1
    chmod 644 /etc/xray/xray.crt /etc/xray/xray.key
fi

# 7. ติดตั้ง Hysteria 2 (UDP Port 8443 และ Port Hopping 20000-50000)
if [ ! -s /usr/local/bin/hysteria ]; then
    echo "กำลังติดตั้ง Hysteria 2 Server..."
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        wget -q -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64"
    else
        wget -q -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-arm64"
    fi
    chmod +x /usr/local/bin/hysteria
fi

cat << 'EOF' > /usr/bin/hys-auth
#!/bin/bash
ADDR="$1"
AUTH="$2"
TX="$3"

MATCH_USER=$(awk -F: -v p="$AUTH" '$2 == p {print $1; exit}' /etc/hysteria/hys-users.txt)

if [ -z "$MATCH_USER" ]; then
    case "$AUTH" in
        *:*)
            u="${AUTH%%:*}"
            p="${AUTH#*:}"
            MATCH_USER=$(awk -F: -v usr="$u" -v pas="$p" '$1 == usr && $2 == pas {print $1; exit}' /etc/hysteria/hys-users.txt)
            ;;
    esac
fi

if [ -n "$MATCH_USER" ]; then
    echo "$MATCH_USER"
    exit 0
else
    exit 1
fi
EOF
chmod +x /usr/bin/hys-auth

cat << 'EOF' > /usr/bin/rebuild-hysteria
#!/bin/bash
mkdir -p /etc/hysteria
touch /etc/hysteria/hys-users.txt

cat <<YAML > /etc/hysteria/config.yaml
listen: :8443

tls:
  cert: /etc/xray/xray.crt
  key: /etc/xray/xray.key

auth:
  type: command
  command: /usr/bin/hys-auth

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
YAML

systemctl restart hysteria >/dev/null 2>&1
EOF
chmod +x /usr/bin/rebuild-hysteria

cat <<EOF > /etc/systemd/system/hysteria.service
[Unit]
Description=Hysteria 2 Server Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

/usr/bin/rebuild-hysteria
systemctl daemon-reload
systemctl enable hysteria >/dev/null 2>&1
systemctl restart hysteria

# 8. ติดตั้ง ZIVPN UDP Tunnel (พอร์ต 5667 และ 6000-19999)
if [ ! -s /usr/local/bin/zivpn-udp ]; then
    echo "กำลังติดตั้ง ZIVPN UDP Server..."
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        wget -q -O /usr/local/bin/zivpn-udp "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
    else
        wget -q -O /usr/local/bin/zivpn-udp "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64"
    fi
    chmod +x /usr/local/bin/zivpn-udp
fi

if [ ! -s /etc/zivpn/zivpn.crt ]; then
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=ZIVPN/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1

if [ ! -s /etc/zivpn/config.json ]; then
cat <<EOF > /etc/zivpn/config.json
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": [
      "zivpn-default"
    ]
  }
}
EOF
fi

cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Tunnel Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn-udp server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn >/dev/null 2>&1
systemctl restart zivpn

# 9. ติดตั้ง UDP Custom (พอร์ตภายใน 7200)
echo "กำลังติดตั้ง UDP Custom..."
mkdir -p /root/udp
UDP_SIZE=$(stat -c%s "/usr/local/bin/udp-custom" 2>/dev/null)
[ -z "$UDP_SIZE" ] && UDP_SIZE=0
if [ "$UDP_SIZE" -lt 1000000 ]; then
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        URLS=(
            "https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-amd64"
            "https://github.com/rudi9999/Herramientas/raw/main/UDP/udp-custom-linux-amd64"
            "https://raw.githubusercontent.com/zahidbd2/udp-custom/main/bin/udp-custom-linux-amd64"
        )
    else
        URLS=(
            "https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-arm"
            "https://github.com/rudi9999/Herramientas/raw/main/UDP/udp-custom-linux-arm"
        )
    fi
    for url in "${URLS[@]}"; do
        wget -q --no-check-certificate -O /usr/local/bin/udp-custom "$url"
        NEW_SIZE=$(stat -c%s "/usr/local/bin/udp-custom" 2>/dev/null)
        [ -z "$NEW_SIZE" ] && NEW_SIZE=0
        if [ "$NEW_SIZE" -gt 1000000 ]; then
            break
        fi
    done
fi
chmod +x /usr/local/bin/udp-custom
cp -f /usr/local/bin/udp-custom /root/udp/udp-custom
chmod +x /root/udp/udp-custom

cat <<EOF > /root/udp/config.json
{
  "listen": ":7200",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF
chmod 644 /root/udp/config.json

cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP Custom VPN Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/udp
ExecStart=/usr/local/bin/udp-custom server
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udp-custom >/dev/null 2>&1
systemctl restart udp-custom

# 10. ตั้งค่า Iptables Port Forwarding แยกช่วงพอร์ตชัดเจน (ZIVPN + Hysteria 2 + UDP Custom)
NET_IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -F PREROUTING

iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 5667 -j ACCEPT
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 8443 -j ACCEPT
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :8443
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 1:65535 -j DNAT --to-destination :7200

if ! iptables -t nat -C POSTROUTING -o "$NET_IFACE" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -o "$NET_IFACE" -j MASQUERADE
fi

for uport in 7200 5667 8443; do
    if ! iptables -C INPUT -p udp --dport "$uport" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport "$uport" -j ACCEPT
    fi
done

# 11. ติดตั้งระบบ Web API & Web Dashboard (Port 8081)
cat << 'EOF' > /usr/bin/api-vpn
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exec 200>/var/lock/api-vpn.lock
if ! flock -w 10 200; then
    rm -f /var/lock/api-vpn.lock 2>/dev/null
    exec 200>/var/lock/api-vpn.lock
    flock -n 200
fi

ACTION=$1
USER=$2
PASS=$3
EXP=$4

mkdir -p /etc/zivpn /etc/hysteria
touch /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt /etc/hysteria/hys-users.txt

if ! pgrep -x "useradd" >/dev/null && ! pgrep -x "usermod" >/dev/null && ! pgrep -x "chpasswd" >/dev/null; then
    rm -f /etc/passwd.lock /etc/shadow.lock /etc/group.lock /etc/gshadow.lock /etc/.pwd.lock 2>/dev/null
fi

if ! echo "$EXP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    EXP=$(date -d "+1 days" +"%Y-%m-%d")
fi

if [ "$ACTION" = "add" ]; then
    for i in 1 2 3; do
        if ! id "$USER" >/dev/null 2>&1; then
            if ! pgrep -x "useradd" >/dev/null; then
                rm -f /etc/passwd.lock /etc/shadow.lock /etc/group.lock /etc/gshadow.lock /etc/.pwd.lock 2>/dev/null
            fi
            /usr/sbin/useradd -e "$EXP" -s /bin/false -M "$USER" 2>/dev/null || \
            /usr/sbin/useradd -e "$EXP" -s /bin/false -M -N "$USER" 2>/dev/null
            sleep 0.3
        else
            break
        fi
    done

    if ! id "$USER" >/dev/null 2>&1; then
        flock -u 200
        exit 1
    fi

    echo "$USER:$PASS" | /usr/sbin/chpasswd 2>/dev/null
    /usr/bin/chage -E "$EXP" "$USER" 2>/dev/null
    /usr/sbin/usermod -e "$EXP" "$USER" 2>/dev/null

    if [ -n "$PASS" ] && [ -f /etc/zivpn/config.json ]; then
        jq --arg p "$PASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > "/tmp/zivpn_tmp_$$.json"
        if [ -s "/tmp/zivpn_tmp_$$.json" ]; then
            mv "/tmp/zivpn_tmp_$$.json" /etc/zivpn/config.json
        else
            rm -f "/tmp/zivpn_tmp_$$.json"
        fi
        sed -i "/^${PASS}:/d" /etc/zivpn/zivpn-exp.txt
        echo "${PASS}:${EXP}" >> /etc/zivpn/zivpn-exp.txt
        sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
        echo "${USER}:${PASS}" >> /etc/zivpn/zivpn-users.txt
        (systemctl restart zivpn >/dev/null 2>&1) 200>&- &
    fi

    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        sed -i "/^${USER}:/d" /etc/hysteria/hys-users.txt
        echo "${USER}:${PASS}:${EXP}" >> /etc/hysteria/hys-users.txt
        (/usr/bin/rebuild-hysteria >/dev/null 2>&1) 200>&- &
    fi

elif [ "$ACTION" = "renew" ]; then
    ZPASS=$(grep "^${USER}:" /etc/zivpn/zivpn-users.txt | cut -d: -f2 | tail -n 1)
    HPASS=$(grep "^${USER}:" /etc/hysteria/hys-users.txt | cut -d: -f2 | tail -n 1)
    [ -z "$ZPASS" ] && [ -n "$PASS" ] && ZPASS="$PASS"
    [ -z "$ZPASS" ] && [ -n "$HPASS" ] && ZPASS="$HPASS"
    [ -z "$HPASS" ] && [ -n "$ZPASS" ] && HPASS="$ZPASS"

    if ! id "$USER" >/dev/null 2>&1; then
        for i in 1 2 3; do
            if ! id "$USER" >/dev/null 2>&1; then
                /usr/sbin/useradd -e "$EXP" -s /bin/false -M "$USER" 2>/dev/null || \
                /usr/sbin/useradd -e "$EXP" -s /bin/false -M -N "$USER" 2>/dev/null
                sleep 0.3
            else
                break
            fi
        done
        if [ -n "$ZPASS" ]; then
            echo "$USER:$ZPASS" | /usr/sbin/chpasswd 2>/dev/null
        fi
    elif [ -n "$PASS" ]; then
        echo "$USER:$PASS" | /usr/sbin/chpasswd 2>/dev/null
    fi

    if ! id "$USER" >/dev/null 2>&1; then
        flock -u 200
        exit 1
    fi

    /usr/bin/chage -E "$EXP" "$USER" 2>/dev/null
    /usr/sbin/usermod -e "$EXP" "$USER" 2>/dev/null

    if [ -n "$ZPASS" ]; then
        sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
        echo "${USER}:${ZPASS}" >> /etc/zivpn/zivpn-users.txt
        sed -i "/^${ZPASS}:/d" /etc/zivpn/zivpn-exp.txt
        echo "${ZPASS}:${EXP}" >> /etc/zivpn/zivpn-exp.txt
        if [ -f /etc/zivpn/config.json ]; then
            jq --arg p "$ZPASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > "/tmp/zivpn_tmp_$$.json"
            if [ -s "/tmp/zivpn_tmp_$$.json" ]; then
                mv "/tmp/zivpn_tmp_$$.json" /etc/zivpn/config.json
            else
                rm -f "/tmp/zivpn_tmp_$$.json"
            fi
            (systemctl restart zivpn >/dev/null 2>&1) 200>&- &
        fi
    fi

    if [ -n "$HPASS" ]; then
        sed -i "/^${USER}:/d" /etc/hysteria/hys-users.txt
        echo "${USER}:${HPASS}:${EXP}" >> /etc/hysteria/hys-users.txt
        (/usr/bin/rebuild-hysteria >/dev/null 2>&1) 200>&- &
    fi

elif [ "$ACTION" = "delete" ]; then
    /usr/bin/killall -u "$USER" 2>/dev/null
    /usr/sbin/userdel -f "$USER" 2>/dev/null
    /usr/sbin/groupdel "$USER" 2>/dev/null

    ZPASS=$(grep "^${USER}:" /etc/zivpn/zivpn-users.txt | cut -d: -f2 | tail -n 1)
    sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
    if [ -n "$ZPASS" ] && [ -f /etc/zivpn/config.json ]; then
        if ! grep -q ":${ZPASS}$" /etc/zivpn/zivpn-users.txt; then
            jq --arg p "$ZPASS" '.auth.config -= [$p]' /etc/zivpn/config.json > "/tmp/zivpn_tmp_$$.json"
            if [ -s "/tmp/zivpn_tmp_$$.json" ]; then
                mv "/tmp/zivpn_tmp_$$.json" /etc/zivpn/config.json
            else
                rm -f "/tmp/zivpn_tmp_$$.json"
            fi
            sed -i "/^${ZPASS}:/d" /etc/zivpn/zivpn-exp.txt
            (systemctl restart zivpn >/dev/null 2>&1) 200>&- &
        fi
    fi

    if grep -q "^${USER}:" /etc/hysteria/hys-users.txt; then
        sed -i "/^${USER}:/d" /etc/hysteria/hys-users.txt
        (/usr/bin/rebuild-hysteria >/dev/null 2>&1) 200>&- &
    fi
fi

flock -u 200
exit 0
EOF
chmod +x /usr/bin/api-vpn

# Backend หน้า Web Dashboard (/usr/bin/panel-cmd)
cat << 'EOF' > /usr/bin/panel-cmd
#!/bin/bash
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ACTION="$1"

MYIP=$(curl -sS --max-time 2 ipv4.icanhazip.com 2>/dev/null)
if [ -z "$MYIP" ]; then
    MYIP=$(hostname -I | awk '{print $1}')
fi
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)
if [ -z "$DOMAIN" ]; then
    DOMAIN="$MYIP"
fi

case "$ACTION" in
    stats)
        RAM_USED=$(free -m | awk 'NR==2{print $3}')
        RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
        CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | tr -d ' ')
        UPTIME_STR=$(uptime -p | sed 's/up //')

        SSH_ON=0
        for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
            c=$(pgrep -u "$u" sshd 2>/dev/null | wc -l)
            SSH_ON=$((SSH_ON + c))
        done

        Services=("ssh" "dropbear" "nginx" "xray" "udp-custom" "udpgw@7300" "zivpn" "hysteria" "ws-epro" "fail2ban")
        SVC_JSON="{"
        first=1
        for s in "${Services[@]}"; do
            if systemctl is-active --quiet "$s"; then
                st="ON"
            else
                st="OFF"
            fi
            [ $first -eq 0 ] && SVC_JSON="${SVC_JSON},"
            SVC_JSON="${SVC_JSON}\"${s}\":\"${st}\""
            first=0
        done
        SVC_JSON="${SVC_JSON}}"

        jq -n \
            --arg ip "$MYIP" \
            --arg dom "$DOMAIN" \
            --arg ram_u "$RAM_USED" \
            --arg ram_t "$RAM_TOTAL" \
            --arg cpu "$CPU_LOAD" \
            --arg up "$UPTIME_STR" \
            --arg ssh_on "$SSH_ON" \
            --argjson svc "$SVC_JSON" \
            '{ip:$ip, domain:$dom, ram_used:$ram_u, ram_total:$ram_t, cpu:$cpu, uptime:$up, ssh_online:$ssh_on, services:$svc}'
        ;;

    list_ssh)
        echo "["
        first=1
        USERS_LIST=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | tac)
        for u in $USERS_LIST; do
            exp_raw=$(chage -l "$u" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
            if [ "$exp_raw" = "never" ] || [ -z "$exp_raw" ]; then
                exp="Never"
            else
                exp=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null)
                [ -z "$exp" ] && exp="$exp_raw"
            fi
            pstat=$(passwd -S "$u" 2>/dev/null | awk '{print $2}')
            if [ "$pstat" = "L" ]; then
                stat="Locked"
            else
                stat="Active"
            fi
            on_cnt=$(pgrep -u "$u" sshd 2>/dev/null | wc -l)
            pass=$(grep "^${u}:" /etc/zivpn/zivpn-users.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
            [ -z "$pass" ] && pass="-"

            [ $first -eq 0 ] && echo ","
            jq -n --arg u "$u" --arg p "$pass" --arg e "$exp" --arg s "$stat" --arg o "$on_cnt" \
                '{user:$u, pass:$p, exp:$e, status:$s, online:$o}'
            first=0
        done
        echo "]"
        ;;

    list_xray)
        echo "["
        first=1
        if [ -s /etc/xray/xray-exp.txt ]; then
            while IFS=':' read -r u exp; do
                [ -z "$u" ] && continue
                if grep -q "^${u}:" /etc/xray/xray-lock.txt 2>/dev/null; then
                    uuid=$(grep "^${u}:" /etc/xray/xray-lock.txt | cut -d: -f2)
                    stat="Locked"
                else
                    uuid=$(jq -r --arg usr "$u" '.inbounds[0].settings.clients[] | select(.email == $usr) | .id' /etc/xray/config.json 2>/dev/null)
                    stat="Active"
                fi
                [ -z "$uuid" ] && continue

                v_tls_json=$(printf '{"v":"2","ps":"%s-TLS","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","path":"/vmess","type":"none","host":"%s","tls":"tls"}' "$u" "$DOMAIN" "$uuid" "$DOMAIN" | base64 -w 0)
                v_ntls_json=$(printf '{"v":"2","ps":"%s-HTTP","add":"%s","port":"80","id":"%s","aid":"0","net":"ws","path":"/vmess","type":"none","host":"%s","tls":"none"}' "$u" "$DOMAIN" "$uuid" "$DOMAIN" | base64 -w 0)
                vmess_tls="vmess://${v_tls_json}"
                vmess_ntls="vmess://${v_ntls_json}"
                vless_tls="vless://${uuid}@${DOMAIN}:443?path=%2Fvless&security=tls&encryption=none&type=ws&host=${DOMAIN}&sni=${DOMAIN}#${u}-TLS"
                vless_ntls="vless://${uuid}@${DOMAIN}:80?path=%2Fvless&security=none&encryption=none&type=ws&host=${DOMAIN}#${u}-HTTP"

                [ $first -eq 0 ] && echo ","
                jq -n --arg u "$u" --arg e "$exp" --arg s "$stat" --arg id "$uuid" \
                      --arg vmt "$vmess_tls" --arg vmn "$vmess_ntls" --arg vlt "$vless_tls" --arg vln "$vless_ntls" \
                      '{user:$u, exp:$e, status:$s, uuid:$id, vmess_tls:$vmt, vmess_http:$vmn, vless_tls:$vlt, vless_http:$vln}'
                first=0
            done < /etc/xray/xray-exp.txt
        fi
        echo "]"
        ;;

    add_ssh)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        PASS=$(echo "$3" | tr -cd 'a-zA-Z0-9_@#.-')
        DAYS=$(echo "$4" | tr -cd '0-9')
        if [ -z "$USER" ]; then echo '{"success":false,"msg":"กรุณากรอกชื่อผู้ใช้"}'; exit 0; fi
        if [ -z "$PASS" ]; then echo '{"success":false,"msg":"กรุณากรอกรหัสผ่าน"}'; exit 0; fi
        if [ -z "$DAYS" ]; then DAYS=30; fi
        if id "$USER" >/dev/null 2>&1; then
            echo '{"success":false,"msg":"มีชื่อผู้ใช้นี้ในระบบแล้ว"}'
            exit 0
        fi
        EXP=$(date -d "$DAYS days" +"%Y-%m-%d")
        /usr/bin/api-vpn add "$USER" "$PASS" "$EXP" >/dev/null 2>&1
        if id "$USER" >/dev/null 2>&1; then
            echo "{\"success\":true,\"msg\":\"สร้างบัญชี $USER สำเร็จ (หมดอายุ $EXP)\",\"user\":\"$USER\",\"pass\":\"$PASS\",\"exp\":\"$EXP\"}"
        else
            echo "{\"success\":false,\"msg\":\"สร้างบัญชี $USER ไม่สำเร็จ! กรุณาลองใหม่อีกครั้ง\"}"
        fi
        ;;

    renew_ssh)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        DAYS=$(echo "$3" | tr -cd '0-9')
        if [ -z "$USER" ]; then echo '{"success":false,"msg":"ไม่พบชื่อผู้ใช้"}'; exit 0; fi
        if [ -z "$DAYS" ]; then DAYS=30; fi
        exp_old=$(chage -l "$USER" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        today_sec=$(date +%s)
        exp_sec=$(date -d "$exp_old" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$exp_old" +%Y-%m-%d 2>/dev/null)
            [ -z "$base_date" ] && base_date=$(date +%Y-%m-%d)
        fi
        NEW_EXP=$(date -d "$base_date + $DAYS days" +%Y-%m-%d)
        /usr/bin/api-vpn renew "$USER" "" "$NEW_EXP" >/dev/null 2>&1
        echo "{\"success\":true,\"msg\":\"ต่ออายุ $USER สำเร็จ (หมดอายุ $NEW_EXP)\"}"
        ;;

    set_pass)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        PASS=$(echo "$3" | tr -cd 'a-zA-Z0-9_@#.-')
        if [ -z "$USER" ]; then echo '{"success":false,"msg":"ไม่พบชื่อผู้ใช้"}'; exit 0; fi
        if [ -z "$PASS" ]; then echo '{"success":false,"msg":"กรุณากรอกรหัสผ่าน"}'; exit 0; fi
        exp_raw=$(chage -l "$USER" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        EXP=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null)
        [ -z "$EXP" ] && EXP=$(date -d "30 days" +%Y-%m-%d)
        /usr/bin/api-vpn add "$USER" "$PASS" "$EXP" >/dev/null 2>&1
        echo "{\"success\":true,\"msg\":\"บันทึกรหัสผ่านของ $USER เรียบร้อยแล้ว\"}"
        ;;

    del_ssh)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        /usr/bin/api-vpn delete "$USER" "" "" >/dev/null 2>&1
        echo "{\"success\":true,\"msg\":\"ลบบัญชี $USER เรียบร้อยแล้ว\"}"
        ;;

    toggle_ssh)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        pstat=$(passwd -S "$USER" 2>/dev/null | awk '{print $2}')
        if [ "$pstat" = "L" ]; then
            passwd -u "$USER" >/dev/null 2>&1
            echo "{\"success\":true,\"msg\":\"ปลดล็อกบัญชี $USER แล้ว\"}"
        else
            passwd -l "$USER" >/dev/null 2>&1
            killall -u "$USER" >/dev/null 2>&1
            echo "{\"success\":true,\"msg\":\"ระงับบัญชี $USER ชั่วคราวแล้ว\"}"
        fi
        ;;

    add_xray)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        DAYS=$(echo "$3" | tr -cd '0-9')
        if [ -z "$USER" ]; then echo '{"success":false,"msg":"กรุณากรอกชื่อบัญชี"}'; exit 0; fi
        if [ -z "$DAYS" ]; then DAYS=30; fi
        if grep -q "^${USER}:" /etc/xray/xray-exp.txt 2>/dev/null; then
            echo '{"success":false,"msg":"มีชื่อบัญชี Xray นี้แล้ว"}'
            exit 0
        fi
        EXP=$(date -d "$DAYS days" +"%Y-%m-%d")
        UUID=$(cat /proc/sys/kernel/random/uuid)
        (
            flock -x 200
            jq --arg u "$USER" --arg id "$UUID" \
               '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}] |
                .inbounds[1].settings.clients += [{"id": $id, "email": $u}]' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            echo "$USER:$EXP" >> /etc/xray/xray-exp.txt
        ) 200>/var/lock/vpn-panel.lock
        (sleep 1 && systemctl restart xray) >/dev/null 2>&1 &
        echo "{\"success\":true,\"msg\":\"สร้างบัญชี Xray $USER สำเร็จ\"}"
        ;;

    renew_xray)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        DAYS=$(echo "$3" | tr -cd '0-9')
        [ -z "$DAYS" ] && DAYS=30
        old_exp=$(grep "^${USER}:" /etc/xray/xray-exp.txt | cut -d: -f2)
        if [ -z "$old_exp" ]; then echo '{"success":false,"msg":"ไม่พบชื่อบัญชี"}'; exit 0; fi
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$old_exp" +%Y-%m-%d 2>/dev/null)
            [ -z "$base_date" ] && base_date=$(date +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $DAYS days" +%Y-%m-%d)
        (
            flock -x 200
            sed -i "s/^${USER}:${old_exp}/${USER}:${new_exp}/g" /etc/xray/xray-exp.txt
        ) 200>/var/lock/vpn-panel.lock
        echo "{\"success\":true,\"msg\":\"ต่ออายุ Xray $USER ถึง $new_exp สำเร็จ\"}"
        ;;

    del_xray)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        (
            flock -x 200
            jq --arg u "$USER" \
               '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
                (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            sed -i "/^${USER}:/d" /etc/xray/xray-exp.txt
            sed -i "/^${USER}:/d" /etc/xray/xray-lock.txt 2>/dev/null
        ) 200>/var/lock/vpn-panel.lock
        (sleep 1 && systemctl restart xray) >/dev/null 2>&1 &
        echo "{\"success\":true,\"msg\":\"ลบบัญชี Xray $USER เรียบร้อยแล้ว\"}"
        ;;

    restart_all)
        (sleep 1 && systemctl restart rsyslog ssh dropbear xray zivpn hysteria udp-custom ws-epro udpgw@7100 udpgw@7300 fail2ban cron nginx) >/dev/null 2>&1 &
        echo '{"success":true,"msg":"กำลังรีสตาร์ทบริการทั้งหมด (รอประมาณ 3 วินาที)"}'
        ;;

    clear_ram)
        /usr/bin/clear-log >/dev/null 2>&1
        echo '{"success":true,"msg":"ล้างไฟล์ขยะ Log และเคลียร์ RAM Cache เรียบร้อยแล้ว"}'
        ;;

    run_speedtest)
        if pgrep -f "/usr/local/bin/speedtest" >/dev/null 2>&1; then
            echo '{"success":false,"msg":"กำลังทดสอบความเร็วอยู่ กรุณารอสักครู่..."}'
            exit 0
        fi
        echo "⏳ กำลังเชื่อมต่อเซิร์ฟเวอร์ Ookla Speedtest... กรุณารอ 15-25 วินาที" > /tmp/speedtest_panel.log
        (
            if [ ! -s /usr/local/bin/speedtest ]; then
                ARCH=$(uname -m)
                S_ARCH="x86_64"
                [ "$ARCH" = "aarch64" ] && S_ARCH="aarch64"
                [ "$ARCH" = "arm64" ] && S_ARCH="aarch64"
                wget -q -O /tmp/speedtest.tgz "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${S_ARCH}.tgz"
                tar -xzf /tmp/speedtest.tgz -C /usr/local/bin speedtest 2>/dev/null
                chmod +x /usr/local/bin/speedtest
                rm -f /tmp/speedtest.tgz
            fi
            /usr/local/bin/speedtest --accept-license --accept-gdpr > /tmp/speedtest_panel.log 2>&1
        ) >/dev/null 2>&1 &
        echo '{"success":true,"msg":"เริ่มการทดสอบความเร็วแล้ว"}'
        ;;

    get_speedtest)
        if pgrep -f "/usr/local/bin/speedtest" >/dev/null 2>&1; then
            RUNNING=true
        else
            RUNNING=false
        fi
        CONTENT=$(cat /tmp/speedtest_panel.log 2>/dev/null)
        [ -z "$CONTENT" ] && CONTENT="กดปุ่ม 'เริ่มวัดความเร็ว' ด้านบนเพื่อทดสอบความเร็วอินเทอร์เน็ตของ VPS"
        jq -n --argjson r "$RUNNING" --arg c "$CONTENT" '{running:$r, output:$c}'
        ;;
esac
EOF
chmod +x /usr/bin/panel-cmd

cat <<EOF > /etc/sudoers.d/vpn-api
www-data ALL=(ALL) NOPASSWD: /usr/bin/api-vpn, /usr/bin/panel-cmd, /usr/bin/rebuild-hysteria, /usr/sbin/useradd, /usr/sbin/usermod, /usr/sbin/groupdel, /usr/sbin/chpasswd, /usr/bin/chage, /usr/sbin/userdel, /usr/bin/killall, /bin/systemctl, /usr/bin/jq, /bin/sed
EOF
chmod 440 /etc/sudoers.d/vpn-api

if [ -s /home/vps/public_html/api_ssh.php ]; then
    SAVED_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php | cut -d'"' -f2)
fi
[ -z "$SAVED_KEY" ] && SAVED_KEY="VNEXT_SSH_999"

cat <<EOF > /home/vps/public_html/api_ssh.php
<?php
header('Content-Type: application/json');
\$secret_key = "${SAVED_KEY}";

\$req_key = \$_POST['key'] ?? '';
if (\$req_key !== \$secret_key) {
    die(json_encode(['success' => false, 'msg' => 'Invalid Key']));
}

\$action = \$_POST['action'] ?? '';
\$user = preg_replace('/[^a-zA-Z0-9_]/', '', \$_POST['user'] ?? '');
\$pass = preg_replace('/[^a-zA-Z0-9_@#]/', '', \$_POST['pass'] ?? '');
\$days = intval(\$_POST['days'] ?? 0);

if (empty(\$user)) {
    die(json_encode(['success' => false, 'msg' => 'User empty']));
}

if (\$days < 1) {
    \$days = 1;
}

if (\$action === 'add') {
    \$exp = date('Y-m-d', strtotime("+\$days days"));
    exec("sudo /usr/bin/api-vpn add '\$user' '\$pass' '\$exp' 2>&1", \$out, \$ret);
    exec("id -u '\$user' 2>/dev/null", \$id_out, \$id_ret);
    if (\$id_ret === 0) {
        echo json_encode(['success' => true, 'exp' => \$exp]);
    } else {
        echo json_encode(['success' => false, 'msg' => 'Create user failed']);
    }
} elseif (\$action === 'renew') {
    \$exp = date('Y-m-d', strtotime("+\$days days"));
    exec("sudo /usr/bin/api-vpn renew '\$user' '\$pass' '\$exp' 2>&1", \$out, \$ret);
    exec("id -u '\$user' 2>/dev/null", \$id_out, \$id_ret);
    if (\$id_ret === 0) {
        echo json_encode(['success' => true, 'exp' => \$exp]);
    } else {
        echo json_encode(['success' => false, 'msg' => 'Renew user failed']);
    }
} elseif (\$action === 'delete') {
    exec("sudo /usr/bin/api-vpn delete '\$user' '' '' 2>&1", \$out, \$ret);
    echo json_encode(['success' => true]);
} else {
    echo json_encode(['success' => false, 'msg' => 'Unknown action']);
}
?>
EOF

cp -f /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php

# สร้างหน้า Web Dashboard (Modern Glassmorphism UI + ระบบจำสิทธิ์ Cookie HMAC ป้องกันเด้งหลุด)
cat << 'EOF' > /home/vps/public_html/index.php
<?php
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Pragma: no-cache");

$sess_dir = "/tmp/vpn_panel_sessions";
if (!is_dir($sess_dir)) {
    @mkdir($sess_dir, 0777, true);
}
@chmod($sess_dir, 0777);
session_save_path($sess_dir);
session_name("TOEYVPN_NODE_SESS");
session_start();

$admin_pass = "VNEXT_SSH_999";
if (file_exists(__DIR__ . '/api_ssh.php')) {
    $api_content = file_get_contents(__DIR__ . '/api_ssh.php');
    if (preg_match('/\$secret_key\s*=\s*"([^"]+)"/', $api_content, $m)) {
        $admin_pass = $m[1];
    }
}

$auth_token = hash_hmac('sha256', $admin_pass, 'toeyvpn_node_auth_v1');

if (isset($_COOKIE['toeyvpn_node_token']) && $_COOKIE['toeyvpn_node_token'] === $auth_token) {
    $_SESSION['vpn_admin_logged'] = true;
}

if (isset($_GET['logout'])) {
    $_SESSION = [];
    session_destroy();
    setcookie('toeyvpn_node_token', '', time() - 3600, '/');
    header("Location: index.php?t=" . time());
    exit;
}

$login_error = "";
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login_pass'])) {
    if (trim($_POST['login_pass']) === $admin_pass) {
        $_SESSION['vpn_admin_logged'] = true;
        setcookie('toeyvpn_node_token', $auth_token, time() + (86400 * 30), '/', '', false, true);
        session_write_close();
        header("Location: index.php?t=" . time());
        exit;
    } else {
        $login_error = "รหัสผ่านไม่ถูกต้อง! (ใช้รหัสเดียวกับ Secret Key ในเมนู 28)";
    }
}

if (isset($_GET['ajax']) && !empty($_SESSION['vpn_admin_logged'])) {
    header('Content-Type: application/json; charset=utf-8');
    $act = $_GET['ajax'];

    if ($act === 'stats') {
        echo shell_exec("sudo /usr/bin/panel-cmd stats");
    } elseif ($act === 'list_ssh') {
        echo shell_exec("sudo /usr/bin/panel-cmd list_ssh");
    } elseif ($act === 'list_xray') {
        echo shell_exec("sudo /usr/bin/panel-cmd list_xray");
    } elseif ($act === 'add_ssh') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $p = escapeshellarg($_POST['pass'] ?? '');
        $d = escapeshellarg($_POST['days'] ?? '30');
        echo shell_exec("sudo /usr/bin/panel-cmd add_ssh $u $p $d");
    } elseif ($act === 'renew_ssh') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $d = escapeshellarg($_POST['days'] ?? '30');
        echo shell_exec("sudo /usr/bin/panel-cmd renew_ssh $u $d");
    } elseif ($act === 'set_pass') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $p = escapeshellarg($_POST['pass'] ?? '');
        echo shell_exec("sudo /usr/bin/panel-cmd set_pass $u $p");
    } elseif ($act === 'del_ssh') {
        $u = escapeshellarg($_POST['user'] ?? '');
        echo shell_exec("sudo /usr/bin/panel-cmd del_ssh $u");
    } elseif ($act === 'toggle_ssh') {
        $u = escapeshellarg($_POST['user'] ?? '');
        echo shell_exec("sudo /usr/bin/panel-cmd toggle_ssh $u");
    } elseif ($act === 'add_xray') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $d = escapeshellarg($_POST['days'] ?? '30');
        echo shell_exec("sudo /usr/bin/panel-cmd add_xray $u $d");
    } elseif ($act === 'renew_xray') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $d = escapeshellarg($_POST['days'] ?? '30');
        echo shell_exec("sudo /usr/bin/panel-cmd renew_xray $u $d");
    } elseif ($act === 'del_xray') {
        $u = escapeshellarg($_POST['user'] ?? '');
        echo shell_exec("sudo /usr/bin/panel-cmd del_xray $u");
    } elseif ($act === 'restart_all') {
        echo shell_exec("sudo /usr/bin/panel-cmd restart_all");
    } elseif ($act === 'clear_ram') {
        echo shell_exec("sudo /usr/bin/panel-cmd clear_ram");
    } elseif ($act === 'run_speedtest') {
        echo shell_exec("sudo /usr/bin/panel-cmd run_speedtest");
    } elseif ($act === 'get_speedtest') {
        echo shell_exec("sudo /usr/bin/panel-cmd get_speedtest");
    }
    exit;
}
?>
<!DOCTYPE html>
<html lang="th" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>TOEYVPN • Node Management Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;600;700;800&family=Prompt:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/remixicon@4.2.0/fonts/remixicon.css" rel="stylesheet">
    <style>
        * { font-family: 'Prompt', 'Plus Jakarta Sans', sans-serif; }
        body {
            background-color: #060913;
            background-image: 
                radial-gradient(at 0% 0%, rgba(6, 182, 212, 0.14) 0px, transparent 50%),
                radial-gradient(at 100% 0%, rgba(99, 102, 241, 0.12) 0px, transparent 50%),
                radial-gradient(at 50% 100%, rgba(16, 185, 129, 0.08) 0px, transparent 50%);
            background-attachment: fixed;
            color: #f1f5f9;
        }
        .glass-card {
            background: rgba(15, 23, 42, 0.72);
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border: 1px solid rgba(255, 255, 255, 0.08);
            box-shadow: 0 10px 30px -10px rgba(0, 0, 0, 0.5);
        }
        .glow-dot-on { box-shadow: 0 0 10px #10b981, 0 0 20px #10b981; }
        .glow-dot-off { box-shadow: 0 0 10px #ef4444; }
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-track { background: #0f172a; }
        ::-webkit-scrollbar-thumb { background: #334155; border-radius: 3px; }
    </style>
</head>
<body class="min-h-screen pb-12 selection:bg-cyan-500 selection:text-slate-950">

<?php if (empty($_SESSION['vpn_admin_logged'])): ?>
    <div class="flex items-center justify-center min-h-screen px-4">
        <div class="glass-card p-8 rounded-3xl w-full max-w-md relative overflow-hidden">
            <div class="absolute -top-20 -right-20 w-40 h-40 bg-cyan-500/20 rounded-full blur-3xl pointer-events-none"></div>
            <div class="flex flex-col items-center text-center mb-7">
                <div class="w-16 h-16 rounded-2xl bg-gradient-to-br from-cyan-400 to-blue-600 flex items-center justify-center shadow-lg shadow-cyan-500/25 mb-4">
                    <i class="ri-shield-keyhole-fill text-3xl text-slate-950"></i>
                </div>
                <h1 class="text-2xl font-bold bg-gradient-to-r from-white via-cyan-200 to-cyan-400 bg-clip-text text-transparent">
                    TOEYVPN NODE PANEL
                </h1>
                <p class="text-slate-400 text-xs mt-1">ระบบจัดการเซิร์ฟเวอร์ VPN ครบวงจร (Port 8081)</p>
            </div>

            <?php if ($login_error): ?>
                <div class="bg-red-500/15 border border-red-500/40 text-red-300 text-xs p-3.5 rounded-xl mb-5 flex items-center gap-2.5">
                    <i class="ri-error-warning-fill text-lg text-red-400"></i>
                    <span><?= htmlspecialchars($login_error) ?></span>
                </div>
            <?php endif; ?>

            <form method="POST" class="space-y-4">
                <div>
                    <label class="block text-xs font-medium text-slate-300 mb-2 ml-1">รหัสผ่านผู้ดูแลระบบ (Secret Key)</label>
                    <div class="relative">
                        <i class="ri-key-2-line absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 text-lg"></i>
                        <input type="password" name="login_pass" required placeholder="กรอก Secret Key ของโหนดนี้..."
                               class="w-full pl-11 pr-4 py-3.5 rounded-xl bg-slate-950/80 border border-slate-700/80 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-cyan-400 focus:ring-1 focus:ring-cyan-400 transition">
                    </div>
                </div>
                <button type="submit" class="w-full bg-gradient-to-r from-cyan-400 to-blue-500 hover:from-cyan-300 hover:to-blue-400 text-slate-950 font-bold py-3.5 rounded-xl shadow-lg shadow-cyan-500/20 transition flex items-center justify-center gap-2 text-sm">
                    <i class="ri-login-circle-line text-lg"></i> เข้าสู่ระบบจัดการ
                </button>
            </form>
        </div>
    </div>

<?php else: ?>
    <header class="sticky top-0 z-30 glass-card border-b border-white/10 px-4 py-3">
        <div class="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-3 min-w-0">
                <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-cyan-400 to-blue-600 flex items-center justify-center shadow-md shadow-cyan-500/20 shrink-0">
                    <i class="ri-server-fill text-xl text-slate-950"></i>
                </div>
                <div class="min-w-0">
                    <div class="flex items-center gap-2">
                        <span class="font-bold text-base tracking-wide text-white">TOEYVPN</span>
                        <span class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-cyan-500/20 text-cyan-300 border border-cyan-500/30">NODE</span>
                    </div>
                    <div class="flex items-center gap-1.5 text-xs text-slate-400 truncate">
                        <span class="w-2 h-2 rounded-full bg-emerald-400 glow-dot-on shrink-0"></span>
                        <span id="nav-domain" class="truncate">กำลังโหลดข้อมูล...</span>
                    </div>
                </div>
            </div>

            <div class="flex items-center gap-1.5 sm:gap-2 ml-auto">
                <button onclick="clearRam()" class="flex items-center gap-1.5 text-xs font-medium bg-amber-500/15 hover:bg-amber-500/25 text-amber-300 border border-amber-500/30 px-3 py-2 rounded-xl transition">
                    <i class="ri-brush-3-line text-sm"></i>
                    <span class="hidden sm:inline">เคลียร์ RAM</span>
                </button>
                <button onclick="restartAll()" class="flex items-center gap-1.5 text-xs font-medium bg-indigo-500/15 hover:bg-indigo-500/25 text-indigo-300 border border-indigo-500/30 px-3 py-2 rounded-xl transition">
                    <i class="ri-restart-line text-sm"></i>
                    <span class="hidden sm:inline">รีสตาร์ทบริการ</span>
                </button>
                <a href="?logout=1" class="flex items-center gap-1 text-xs font-medium bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 border border-rose-500/30 px-3 py-2 rounded-xl transition" title="ออกจากระบบ">
                    <i class="ri-logout-box-r-line text-sm"></i>
                </a>
            </div>
        </div>
    </header>

    <main class="max-w-7xl mx-auto px-4 pt-5 space-y-5">
        <div id="toast" class="hidden fixed bottom-5 right-5 left-5 sm:left-auto glass-card border-emerald-500/50 bg-slate-900/95 text-white px-4 py-3.5 rounded-2xl shadow-2xl z-50 flex items-center gap-3 text-xs sm:text-sm font-medium transition-all">
            <i class="ri-checkbox-circle-fill text-xl text-emerald-400 shrink-0"></i>
            <span id="toast-msg">สำเร็จ</span>
        </div>

        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
            <div class="glass-card p-4 rounded-2xl relative overflow-hidden">
                <div class="flex items-start justify-between gap-2">
                    <span class="text-[11px] font-medium text-slate-400">Host / Domain</span>
                    <div class="w-8 h-8 rounded-lg bg-cyan-500/15 border border-cyan-500/25 flex items-center justify-center text-cyan-400 shrink-0">
                        <i class="ri-global-line text-base"></i>
                    </div>
                </div>
                <div id="stat-domain" class="text-sm sm:text-base font-bold text-white mt-1.5 truncate" title="">-</div>
                <div id="stat-ip" class="text-[11px] text-cyan-400 font-mono truncate mt-0.5">IP: -</div>
                <div id="stat-up" class="text-[10px] text-slate-400 truncate mt-1"><i class="ri-time-line"></i> -</div>
            </div>

            <div class="glass-card p-4 rounded-2xl relative overflow-hidden">
                <div class="flex items-start justify-between gap-2">
                    <span class="text-[11px] font-medium text-slate-400">RAM Usage</span>
                    <div class="w-8 h-8 rounded-lg bg-blue-500/15 border border-blue-500/25 flex items-center justify-center text-blue-400 shrink-0">
                        <i class="ri-ram-2-line text-base"></i>
                    </div>
                </div>
                <div id="stat-ram" class="text-sm sm:text-base font-bold text-white mt-1.5">- MB</div>
                <div id="stat-ram-pct" class="text-[11px] text-blue-400 mt-0.5">ใช้งานไป 0%</div>
                <div class="w-full bg-slate-800 h-1.5 rounded-full mt-2 overflow-hidden">
                    <div id="stat-ram-bar" class="bg-gradient-to-r from-cyan-400 to-blue-500 h-full transition-all duration-500" style="width: 0%"></div>
                </div>
            </div>

            <div class="glass-card p-4 rounded-2xl relative overflow-hidden">
                <div class="flex items-start justify-between gap-2">
                    <span class="text-[11px] font-medium text-slate-400">CPU Load</span>
                    <div class="w-8 h-8 rounded-lg bg-amber-500/15 border border-amber-500/25 flex items-center justify-center text-amber-400 shrink-0">
                        <i class="ri-cpu-line text-base"></i>
                    </div>
                </div>
                <div id="stat-cpu" class="text-lg sm:text-xl font-bold text-amber-400 mt-1">0.00</div>
                <div class="text-[11px] text-slate-400 mt-1">Debian / Ubuntu VPS</div>
            </div>

            <div class="glass-card p-4 rounded-2xl relative overflow-hidden">
                <div class="flex items-start justify-between gap-2">
                    <span class="text-[11px] font-medium text-slate-400">กำลังออนไลน์</span>
                    <div class="w-8 h-8 rounded-lg bg-emerald-500/15 border border-emerald-500/25 flex items-center justify-center text-emerald-400 shrink-0">
                        <i class="ri-user-voice-line text-base"></i>
                    </div>
                </div>
                <div id="stat-online" class="text-lg sm:text-xl font-bold text-emerald-400 mt-1">0 เครื่อง</div>
                <div class="text-[11px] text-slate-400 mt-1">SSH / WS / UDP Custom</div>
            </div>
        </div>

        <div class="glass-card p-4 sm:p-5 rounded-2xl">
            <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2">
                    <i class="ri-pulse-line text-cyan-400 text-lg"></i>
                    <h2 class="text-xs sm:text-sm font-semibold text-slate-200">สถานะการทำงานของโปรโตคอล (Services Status)</h2>
                </div>
                <span class="text-[11px] text-slate-400">อัปเดตเรียลไทม์</span>
            </div>
            <div id="svc-grid" class="grid grid-cols-2 sm:grid-cols-5 gap-2 text-xs"></div>
        </div>

        <div class="glass-card p-1.5 rounded-2xl grid grid-cols-3 gap-1.5">
            <button onclick="switchTab('ssh')" id="tab-btn-ssh" class="flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-semibold text-xs sm:text-sm bg-gradient-to-r from-cyan-400 to-blue-500 text-slate-950 shadow-md transition">
                <i class="ri-shield-user-line text-base"></i>
                <span class="truncate">All-in-One</span>
            </button>
            <button onclick="switchTab('xray')" id="tab-btn-xray" class="flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-medium text-xs sm:text-sm text-slate-300 hover:bg-slate-800/60 transition">
                <i class="ri-radar-line text-base"></i>
                <span class="truncate">Xray Core</span>
            </button>
            <button onclick="switchTab('speed')" id="tab-btn-speed" class="flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-medium text-xs sm:text-sm text-slate-300 hover:bg-slate-800/60 transition">
                <i class="ri-speed-up-line text-base"></i>
                <span class="truncate">Speedtest</span>
            </button>
        </div>

        <div id="tab-ssh" class="space-y-5">
            <div class="glass-card p-5 rounded-2xl">
                <div class="flex items-center gap-2 mb-4">
                    <div class="w-7 h-7 rounded-lg bg-emerald-500/20 text-emerald-400 flex items-center justify-center">
                        <i class="ri-user-add-line"></i>
                    </div>
                    <div>
                        <h3 class="text-sm font-bold text-white">สร้างบัญชี All-in-One ใหม่</h3>
                        <p class="text-[11px] text-slate-400">ใช้ได้พร้อมกันทั้ง SSH-WS, UDP Custom (1-65535), ZIVPN และ Hysteria 2</p>
                    </div>
                </div>
                <form onsubmit="addSshUser(event)" class="grid grid-cols-1 sm:grid-cols-4 gap-3">
                    <div class="relative">
                        <i class="ri-user-3-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="text" id="ssh-user" required placeholder="ชื่อผู้ใช้ (Username)" class="w-full pl-10 pr-3 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                    </div>
                    <div class="relative flex">
                        <i class="ri-lock-password-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="text" id="ssh-pass" required placeholder="รหัสผ่าน (Password)" class="w-full pl-10 pr-9 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                        <button type="button" onclick="randPass()" title="สุ่มรหัสผ่าน" class="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-cyan-400">
                            <i class="ri-dice-line text-lg"></i>
                        </button>
                    </div>
                    <div class="relative">
                        <i class="ri-calendar-check-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="number" id="ssh-days" value="30" required placeholder="จำนวนวัน (เช่น 30)" class="w-full pl-10 pr-3 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                    </div>
                    <button type="submit" class="bg-gradient-to-r from-emerald-400 to-teal-500 hover:from-emerald-300 hover:to-teal-400 text-slate-950 font-bold py-2.5 px-4 rounded-xl text-xs sm:text-sm shadow-lg shadow-emerald-500/15 transition flex items-center justify-center gap-1.5">
                        <i class="ri-add-circle-fill text-base"></i> สร้างบัญชีทันที
                    </button>
                </form>
            </div>

            <div class="glass-card rounded-2xl overflow-hidden">
                <div class="p-4 border-b border-white/10 flex justify-between items-center">
                    <div class="flex items-center gap-2">
                        <i class="ri-group-line text-cyan-400"></i>
                        <h3 class="font-bold text-xs sm:text-sm text-white">รายชื่อบัญชี All-in-One ทั้งหมด</h3>
                        <span id="ssh-count" class="text-[11px] bg-slate-800 text-cyan-300 px-2 py-0.5 rounded-full">0</span>
                    </div>
                    <button onclick="loadSshUsers()" class="text-xs text-cyan-400 hover:text-cyan-300 flex items-center gap-1">
                        <i class="ri-refresh-line"></i> รีเฟรช
                    </button>
                </div>
                <div class="overflow-x-auto">
                    <table class="w-full text-left text-xs sm:text-sm">
                        <thead class="bg-slate-950/60 text-slate-400 text-[11px] uppercase">
                            <tr>
                                <th class="py-3 px-4">บัญชีผู้ใช้</th>
                                <th class="py-3 px-4">รหัสผ่าน (แตะเพื่อแก้)</th>
                                <th class="py-3 px-4">หมดอายุ</th>
                                <th class="py-3 px-4">ออนไลน์</th>
                                <th class="py-3 px-4">สถานะ</th>
                                <th class="py-3 px-4 text-right">จัดการ / คัดลอก</th>
                            </tr>
                        </thead>
                        <tbody id="ssh-tbody" class="divide-y divide-white/5"></tbody>
                    </table>
                </div>
            </div>
        </div>

        <div id="tab-xray" class="hidden space-y-5">
            <div class="glass-card p-5 rounded-2xl">
                <div class="flex items-center gap-2 mb-4">
                    <div class="w-7 h-7 rounded-lg bg-cyan-500/20 text-cyan-400 flex items-center justify-center">
                        <i class="ri-radar-fill"></i>
                    </div>
                    <div>
                        <h3 class="text-sm font-bold text-white">สร้างบัญชี Xray Core (Vmess & Vless)</h3>
                        <p class="text-[11px] text-slate-400">รองรับทั้งพอร์ต 443 (SSL/TLS) และพอร์ต 80 (HTTP WebSocket)</p>
                    </div>
                </div>
                <form onsubmit="addXrayUser(event)" class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div class="relative">
                        <i class="ri-user-star-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="text" id="xray-user" required placeholder="ชื่อบัญชี Xray (ห้ามซ้ำ)" class="w-full pl-10 pr-3 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                    </div>
                    <div class="relative">
                        <i class="ri-calendar-check-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="number" id="xray-days" value="30" required placeholder="จำนวนวัน (เช่น 30)" class="w-full pl-10 pr-3 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                    </div>
                    <button type="submit" class="bg-gradient-to-r from-cyan-400 to-blue-500 hover:from-cyan-300 hover:to-blue-400 text-slate-950 font-bold py-2.5 px-4 rounded-xl text-xs sm:text-sm shadow-lg shadow-cyan-500/15 transition flex items-center justify-center gap-1.5">
                        <i class="ri-add-circle-fill text-base"></i> สร้างบัญชี Xray
                    </button>
                </form>
            </div>

            <div class="glass-card rounded-2xl overflow-hidden">
                <div class="p-4 border-b border-white/10 flex justify-between items-center">
                    <div class="flex items-center gap-2">
                        <i class="ri-links-line text-cyan-400"></i>
                        <h3 class="font-bold text-xs sm:text-sm text-white">รายชื่อบัญชี Xray ทั้งหมด</h3>
                    </div>
                    <button onclick="loadXrayUsers()" class="text-xs text-cyan-400 hover:text-cyan-300 flex items-center gap-1">
                        <i class="ri-refresh-line"></i> รีเฟรช
                    </button>
                </div>
                <div class="overflow-x-auto">
                    <table class="w-full text-left text-xs sm:text-sm">
                        <thead class="bg-slate-950/60 text-slate-400 text-[11px] uppercase">
                            <tr>
                                <th class="py-3 px-4">ชื่อบัญชี</th>
                                <th class="py-3 px-4">วันหมดอายุ</th>
                                <th class="py-3 px-4">คัดลอกลิงก์ด่วน</th>
                                <th class="py-3 px-4 text-right">จัดการ</th>
                            </tr>
                        </thead>
                        <tbody id="xray-tbody" class="divide-y divide-white/5"></tbody>
                    </table>
                </div>
            </div>
        </div>

        <div id="tab-speed" class="hidden space-y-4">
            <div class="glass-card p-5 rounded-2xl">
                <div class="flex flex-wrap justify-between items-center gap-3 mb-4">
                    <div class="flex items-center gap-2.5">
                        <div class="w-9 h-9 rounded-xl bg-cyan-500/15 text-cyan-400 flex items-center justify-center">
                            <i class="ri-speed-up-fill text-xl"></i>
                        </div>
                        <div>
                            <h3 class="text-sm font-bold text-white">Speedtest by Ookla (Official CLI)</h3>
                            <p class="text-[11px] text-slate-400">วัดความเร็ว Download / Upload / Ping จากสายสัญญาณ VPS โดยตรง</p>
                        </div>
                    </div>
                    <button onclick="startSpeedtest()" id="btn-speedtest" class="bg-gradient-to-r from-cyan-400 to-blue-500 hover:from-cyan-300 hover:to-blue-400 text-slate-950 font-bold px-4 py-2.5 rounded-xl text-xs sm:text-sm shadow-lg shadow-cyan-500/15 transition flex items-center gap-1.5">
                        <i class="ri-play-circle-fill text-base"></i> เริ่มวัดความเร็ว
                    </button>
                </div>
                <pre id="speedtest-box" class="bg-slate-950/90 border border-slate-800 p-4 rounded-xl text-xs text-emerald-400 font-mono overflow-x-auto leading-relaxed min-h-[180px]">กดปุ่ม "เริ่มวัดความเร็ว" เพื่อเริ่มทดสอบ...</pre>
            </div>
        </div>
    </main>

    <div id="info-modal" class="hidden fixed inset-0 z-50 bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
        <div class="glass-card border border-white/15 rounded-3xl max-w-lg w-full p-5 space-y-4 shadow-2xl">
            <div class="flex items-center justify-between border-b border-white/10 pb-3">
                <div class="flex items-center gap-2">
                    <i class="ri-file-list-3-fill text-cyan-400 text-lg"></i>
                    <h3 id="modal-title" class="font-bold text-sm text-white">ข้อมูลบัญชีพร้อมใช้งาน</h3>
                </div>
                <button onclick="closeModal()" class="text-slate-400 hover:text-white"><i class="ri-close-line text-xl"></i></button>
            </div>
            <textarea id="modal-text" readonly rows="11" class="w-full bg-slate-950/90 border border-slate-800 rounded-xl p-3.5 text-xs text-cyan-200 font-mono focus:outline-none"></textarea>
            <div class="flex gap-2">
                <button onclick="copyModalText()" class="flex-1 bg-gradient-to-r from-cyan-400 to-blue-500 text-slate-950 font-bold py-2.5 rounded-xl text-xs sm:text-sm flex items-center justify-center gap-1.5">
                    <i class="ri-file-copy-2-line"></i> คัดลอกข้อมูลทั้งหมด
                </button>
                <button onclick="closeModal()" class="px-4 py-2.5 rounded-xl bg-slate-800 text-slate-300 text-xs sm:text-sm">ปิด</button>
            </div>
        </div>
    </div>

    <script>
        let currentDomain = location.hostname;
        let currentIp = location.hostname;

        function showToast(msg) {
            const t = document.getElementById('toast');
            document.getElementById('toast-msg').textContent = msg;
            t.classList.remove('hidden');
            setTimeout(() => t.classList.add('hidden'), 3200);
        }

        function randPass() {
            const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
            let out = '';
            for (let i = 0; i < 6; i++) out += chars.charAt(Math.floor(Math.random() * chars.length));
            document.getElementById('ssh-pass').value = out;
        }

        function switchTab(tab) {
            ['ssh', 'xray', 'speed'].forEach(t => {
                document.getElementById('tab-' + t).classList.add('hidden');
                document.getElementById('tab-btn-' + t).className = 'flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-medium text-xs sm:text-sm text-slate-300 hover:bg-slate-800/60 transition';
            });
            document.getElementById('tab-' + tab).classList.remove('hidden');
            document.getElementById('tab-btn-' + tab).className = 'flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-semibold text-xs sm:text-sm bg-gradient-to-r from-cyan-400 to-blue-500 text-slate-950 shadow-md transition';
            if (tab === 'xray') loadXrayUsers();
            if (tab === 'speed') pollSpeedtest();
        }

        async function loadStats() {
            try {
                const res = await fetch('?ajax=stats');
                const d = await res.json();
                currentDomain = d.domain;
                currentIp = d.ip;

                document.getElementById('nav-domain').textContent = `${d.domain} (${d.ip})`;
                document.getElementById('stat-domain').textContent = d.domain;
                document.getElementById('stat-domain').title = d.domain;
                document.getElementById('stat-ip').textContent = `IP: ${d.ip}`;
                document.getElementById('stat-up').innerHTML = `<i class="ri-time-line"></i> ${d.uptime}`;

                const pct = Math.round((d.ram_used / d.ram_total) * 100);
                document.getElementById('stat-ram').textContent = `${d.ram_used} / ${d.ram_total} MB`;
                document.getElementById('stat-ram-pct').textContent = `ใช้งานไป ${pct}%`;
                document.getElementById('stat-ram-bar').style.width = pct + '%';
                document.getElementById('stat-cpu').textContent = d.cpu;
                document.getElementById('stat-online').textContent = d.ssh_online + ' เครื่อง';

                const labels = {
                    'ssh': 'OpenSSH (22)',
                    'dropbear': 'Dropbear (109/143)',
                    'nginx': 'Nginx (80/443)',
                    'xray': 'Xray Core',
                    'udp-custom': 'UDP Custom (7200)',
                    'udpgw@7300': 'BadVPN (7300)',
                    'zivpn': 'ZIVPN (5667)',
                    'hysteria': 'Hysteria 2 (8443)',
                    'ws-epro': 'SSH-WS (10015)',
                    'fail2ban': 'Fail2Ban'
                };
                let html = '';
                for (const [k, v] of Object.entries(d.services)) {
                    const isOn = v === 'ON';
                    const lbl = labels[k] ?? k;
                    html += `
                        <div class="bg-slate-950/70 border border-white/5 px-3 py-2.5 rounded-xl flex items-center justify-between gap-2">
                            <span class="text-slate-300 truncate text-[11px] sm:text-xs">${lbl}</span>
                            <span class="flex items-center gap-1.5 text-[10px] font-bold px-2 py-0.5 rounded-full ${isOn ? 'bg-emerald-500/15 text-emerald-400' : 'bg-rose-500/15 text-rose-400'}">
                                <span class="w-1.5 h-1.5 rounded-full ${isOn ? 'bg-emerald-400 glow-dot-on' : 'bg-rose-400 glow-dot-off'}"></span>
                                ${v}
                            </span>
                        </div>`;
                }
                document.getElementById('svc-grid').innerHTML = html;
            } catch (e) {}
        }

        function showSshModal(user, pass, exp) {
            const hysHop = `hysteria2://${encodeURIComponent(pass)}@${currentDomain}:20000/?insecure=1&sni=${currentDomain}&mport=20000-50000#${user}-Hys2`;
            const text = `=== ข้อมูลบัญชี VPN All-in-One ===
Host / Domain : ${currentDomain}
IP Address    : ${currentIp}
Username      : ${user}
Password      : ${pass}
หมดอายุวันที่    : ${exp}
---------------------------------
• SSH / WS Port : 22, 80, 443
• Dropbear Port : 109, 143
• UDP Custom    : 1-5999, 50001-65535
• BadVPN UDPGW  : 7300
• ZIVPN UDP     : 5667, 6000-19999 (รหัส: ${pass})
• Hysteria 2    : 8443, 20000-50000
---------------------------------
[Payload SSH-WS มาตรฐาน]
GET /ssh-ws HTTP/1.1[crlf]Host: ${currentDomain}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]

[ลิงก์ Hysteria 2 Port Hopping]
${hysHop}`;
            document.getElementById('modal-title').textContent = `ข้อมูลบัญชี: ${user}`;
            document.getElementById('modal-text').value = text;
            document.getElementById('info-modal').classList.remove('hidden');
        }

        function closeModal() {
            document.getElementById('info-modal').classList.add('hidden');
        }

        function copyModalText() {
            const el = document.getElementById('modal-text');
            navigator.clipboard.writeText(el.value);
            showToast('คัดลอกข้อมูลบัญชีเรียบร้อยแล้ว!');
        }

        async function loadSshUsers() {
            const res = await fetch('?ajax=list_ssh');
            const list = await res.json();
            document.getElementById('ssh-count').textContent = list.length;
            const tbody = document.getElementById('ssh-tbody');
            if (!list.length) {
                tbody.innerHTML = '<tr><td colspan="6" class="text-center py-8 text-slate-400">ยังไม่มีบัญชีในระบบ กดสร้างบัญชีด้านบนได้เลย</td></tr>';
                return;
            }
            tbody.innerHTML = list.map(u => `
                <tr class="hover:bg-white/[0.02] transition">
                    <td class="py-3 px-4 font-semibold text-white">${u.user}</td>
                    <td class="py-3 px-4">
                        <button onclick="setPass('${u.user}','${u.pass}')" class="text-cyan-300 hover:text-white font-mono underline decoration-dotted underline-offset-4 flex items-center gap-1" title="กดเพื่อตั้ง/บันทึกรหัสผ่าน">
                            <span>${u.pass}</span>
                            <i class="ri-edit-2-line text-xs text-slate-400"></i>
                        </button>
                    </td>
                    <td class="py-3 px-4 text-slate-300 whitespace-nowrap">${u.exp}</td>
                    <td class="py-3 px-4 whitespace-nowrap">
                        <span class="px-2.5 py-0.5 rounded-full text-[11px] ${u.online > 0 ? 'bg-emerald-500/20 text-emerald-300 font-bold border border-emerald-500/30' : 'bg-slate-800 text-slate-400'}">
                            ${u.online} เครื่อง
                        </span>
                    </td>
                    <td class="py-3 px-4">
                        <span class="px-2 py-0.5 rounded-md text-[11px] ${u.status === 'Active' ? 'bg-emerald-500/15 text-emerald-400' : 'bg-rose-500/15 text-rose-400'}">
                            ${u.status}
                        </span>
                    </td>
                    <td class="py-3 px-4 text-right whitespace-nowrap space-x-1">
                        <button onclick="showSshModal('${u.user}','${u.pass}','${u.exp}')" class="bg-cyan-500/15 hover:bg-cyan-500/25 text-cyan-300 border border-cyan-500/30 px-2.5 py-1 rounded-lg text-xs" title="ดูข้อมูล/คัดลอก">
                            <i class="ri-file-copy-2-line"></i> ข้อมูล
                        </button>
                        <button onclick="renewSsh('${u.user}')" class="bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-300 border border-emerald-500/30 px-2 py-1 rounded-lg text-xs" title="ต่ออายุ">
                            <i class="ri-calendar-todo-line"></i> ต่ออายุ
                        </button>
                        <button onclick="toggleSsh('${u.user}')" class="bg-amber-500/15 hover:bg-amber-500/25 text-amber-300 border border-amber-500/30 px-2 py-1 rounded-lg text-xs">
                            ${u.status === 'Active' ? '<i class="ri-lock-line"></i>' : '<i class="ri-lock-unlock-line"></i>'}
                        </button>
                        <button onclick="delSsh('${u.user}')" class="bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 border border-rose-500/30 px-2 py-1 rounded-lg text-xs" title="ลบ">
                            <i class="ri-delete-bin-line"></i>
                        </button>
                    </td>
                </tr>
            `).join('');
        }

        async function addSshUser(e) {
            e.preventDefault();
            const fd = new FormData();
            fd.append('user', document.getElementById('ssh-user').value);
            fd.append('pass', document.getElementById('ssh-pass').value);
            fd.append('days', document.getElementById('ssh-days').value);
            const res = await fetch('?ajax=add_ssh', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            if (r.success) {
                document.getElementById('ssh-user').value = '';
                document.getElementById('ssh-pass').value = '';
                loadSshUsers();
                showSshModal(r.user, r.pass, r.exp);
            }
        }

        async function setPass(user, oldPass) {
            const def = oldPass === '-' ? '' : oldPass;
            const pass = prompt(`กำหนดหรือบันทึกรหัสผ่านสำหรับบัญชี "${user}"\n(ซิงค์เข้า SSH, UDP Custom, ZIVPN และ Hysteria 2 ทันที):`, def);
            if (!pass) return;
            const fd = new FormData();
            fd.append('user', user);
            fd.append('pass', pass);
            const res = await fetch('?ajax=set_pass', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadSshUsers();
        }

        async function renewSsh(user) {
            const days = prompt(`ต้องการต่ออายุบัญชี "${user}" เพิ่มกี่วัน?`, '30');
            if (!days) return;
            const fd = new FormData();
            fd.append('user', user);
            fd.append('days', days);
            const res = await fetch('?ajax=renew_ssh', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadSshUsers();
        }

        async function delSsh(user) {
            if (!confirm(`ยืนยันการลบบัญชี "${user}" ออกจากทุกโปรโตคอล?`)) return;
            const fd = new FormData();
            fd.append('user', user);
            const res = await fetch('?ajax=del_ssh', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadSshUsers();
        }

        async function toggleSsh(user) {
            const fd = new FormData();
            fd.append('user', user);
            const res = await fetch('?ajax=toggle_ssh', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadSshUsers();
        }

        async function loadXrayUsers() {
            const res = await fetch('?ajax=list_xray');
            const list = await res.json();
            const tbody = document.getElementById('xray-tbody');
            if (!list.length) {
                tbody.innerHTML = '<tr><td colspan="4" class="text-center py-8 text-slate-400">ยังไม่มีบัญชี Xray ในระบบ</td></tr>';
                return;
            }
            tbody.innerHTML = list.map(u => `
                <tr class="hover:bg-white/[0.02] transition">
                    <td class="py-3 px-4 font-semibold text-white">
                        <div>${u.user}</div>
                        <div class="text-[10px] text-slate-500 font-mono truncate max-w-[140px]">${u.uuid}</div>
                    </td>
                    <td class="py-3 px-4 text-slate-300 whitespace-nowrap">${u.exp}</td>
                    <td class="py-3 px-4 whitespace-nowrap space-x-1">
                        <button onclick="copyLink('${u.vmess_tls}', 'Vmess TLS (443)')" class="text-xs bg-cyan-500/15 hover:bg-cyan-500/25 text-cyan-300 border border-cyan-500/30 px-2.5 py-1 rounded-lg">Vmess TLS</button>
                        <button onclick="copyLink('${u.vmess_http}', 'Vmess HTTP (80)')" class="text-xs bg-indigo-500/15 hover:bg-indigo-500/25 text-indigo-300 border border-indigo-500/30 px-2.5 py-1 rounded-lg">Vmess 80</button>
                        <button onclick="copyLink('${u.vless_tls}', 'Vless TLS (443)')" class="text-xs bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-300 border border-emerald-500/30 px-2.5 py-1 rounded-lg">Vless TLS</button>
                    </td>
                    <td class="py-3 px-4 text-right whitespace-nowrap space-x-1">
                        <button onclick="renewXray('${u.user}')" class="bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-300 border border-emerald-500/30 px-2 py-1 rounded-lg text-xs">
                            <i class="ri-calendar-todo-line"></i> ต่ออายุ
                        </button>
                        <button onclick="delXray('${u.user}')" class="bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 border border-rose-500/30 px-2 py-1 rounded-lg text-xs">
                            <i class="ri-delete-bin-line"></i>
                        </button>
                    </td>
                </tr>
            `).join('');
        }

        async function addXrayUser(e) {
            e.preventDefault();
            const fd = new FormData();
            fd.append('user', document.getElementById('xray-user').value);
            fd.append('days', document.getElementById('xray-days').value);
            const res = await fetch('?ajax=add_xray', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            if (r.success) {
                document.getElementById('xray-user').value = '';
                loadXrayUsers();
            }
        }

        async function renewXray(user) {
            const days = prompt(`ต้องการต่ออายุบัญชี Xray "${user}" เพิ่มกี่วัน?`, '30');
            if (!days) return;
            const fd = new FormData();
            fd.append('user', user);
            fd.append('days', days);
            const res = await fetch('?ajax=renew_xray', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadXrayUsers();
        }

        async function delXray(user) {
            if (!confirm(`ยืนยันการลบบัญชี Xray "${user}" ?`)) return;
            const fd = new FormData();
            fd.append('user', user);
            const res = await fetch('?ajax=del_xray', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadXrayUsers();
        }

        function copyLink(text, label) {
            navigator.clipboard.writeText(text);
            showToast('คัดลอกลิงก์ ' + label + ' แล้ว!');
        }

        async function clearRam() {
            const res = await fetch('?ajax=clear_ram');
            const r = await res.json();
            showToast(r.msg);
            loadStats();
        }

        async function restartAll() {
            if (!confirm('ต้องการรีสตาร์ทบริการทั้งหมดใช่หรือไม่?')) return;
            const res = await fetch('?ajax=restart_all');
            const r = await res.json();
            showToast(r.msg);
            setTimeout(loadStats, 3500);
        }

        let speedTimer = null;
        async function startSpeedtest() {
            const res = await fetch('?ajax=run_speedtest');
            const r = await res.json();
            showToast(r.msg);
            pollSpeedtest();
        }

        async function pollSpeedtest() {
            const res = await fetch('?ajax=get_speedtest');
            const r = await res.json();
            document.getElementById('speedtest-box').textContent = r.output;
            const btn = document.getElementById('btn-speedtest');
            if (r.running) {
                btn.innerHTML = '<i class="ri-loader-4-line animate-spin text-base"></i> กำลังวัดความเร็ว...';
                btn.disabled = true;
                clearTimeout(speedTimer);
                speedTimer = setTimeout(pollSpeedtest, 2000);
            } else {
                btn.innerHTML = '<i class="ri-play-circle-fill text-base"></i> เริ่มวัดความเร็ว';
                btn.disabled = false;
            }
        }

        loadStats();
        loadSshUsers();
        setInterval(loadStats, 10000);
    </script>
<?php endif; ?>
</body>
</html>
EOF

chown -R www-data:www-data /home/vps/public_html
chmod -R 755 /home/vps/public_html

systemctl enable php*-fpm >/dev/null 2>&1
systemctl restart php*-fpm
PHP_SOCK=$(find /run/php/ -name "php*-fpm.sock" | head -n 1)

cat <<EOF > /etc/nginx/conf.d/api.conf
server {
    listen 8081;
    listen [::]:8081;
    server_name _;
    root /home/vps/public_html;
    index index.php index.html;

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }
}
EOF

if ! iptables -C INPUT -p tcp --dport 8081 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport 8081 -j ACCEPT
fi
netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1
systemctl restart nginx

# 11.5 ติดตั้ง Xray Core, ออกใบรับรอง SSL (Let's Encrypt) และตั้งค่า Nginx (Port 80/443)
if [ ! -f /usr/local/bin/xray ]; then
    echo "กำลังติดตั้ง Xray Core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
fi

# สร้าง config.json ของ Xray เฉพาะกรณีติดตั้งใหม่ (ไม่ทับบัญชีลูกค้าเดิมตอนกดเมนู 27)
if [ ! -s /etc/xray/config.json ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    cat <<JSON > /etc/xray/config.json
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
JSON
fi

mkdir -p /var/log/xray
chown -R nobody:nogroup /var/log/xray 2>/dev/null

cat << 'SVC' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SVC

# ขอใบรับรอง SSL ของจริง (Let's Encrypt) เฉพาะตอนติดตั้งใหม่ที่ยังไม่ได้ขอ acme.sh
if [[ ! "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ ! -d "/root/.acme.sh/${DOMAIN}_ecc" ]; then
    echo "กำลังออกใบรับรอง SSL สำหรับโดเมน ${DOMAIN}..."
    systemctl stop nginx >/dev/null 2>&1
    curl https://get.acme.sh | sh -s email=admin@${DOMAIN} >/dev/null 2>&1
    /root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    /root/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone -k ec-256 --force
    /root/.acme.sh/acme.sh --installcert -d "${DOMAIN}" \
        --fullchainpath /etc/xray/xray.crt \
        --keypath /etc/xray/xray.key --ecc
    chmod 644 /etc/xray/xray.crt /etc/xray/xray.key
    /usr/bin/rebuild-hysteria
fi

# สร้างไฟล์คอนฟิก Nginx พอร์ต 80 และ 443 (/vmess, /vless, และ /ssh-ws)
cat <<NGX > /etc/nginx/conf.d/xray.conf
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2 reuseport;
    listen [::]:443 http2 reuseport;
    server_name ${DOMAIN} _;

    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location = /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location = /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10015;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGX

for xport in 80 443; do
    if ! iptables -C INPUT -p tcp --dport "$xport" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport "$xport" -j ACCEPT
    fi
done
netfilter-persistent save >/dev/null 2>&1
systemctl daemon-reload
systemctl enable xray nginx >/dev/null 2>&1
mkdir -p /usr/local/etc/xray
rm -f /usr/local/etc/xray/config.json
ln -s /etc/xray/config.json /usr/local/etc/xray/config.json
systemctl restart xray nginx

# 12. ติดตั้ง BadVPN UDPGW (พอร์ต 7100 และ 7300)
if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    echo "กำลังติดตั้ง BadVPN UDPGW..."
    wget -q -O /usr/local/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
fi
if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    wget -q -O /usr/local/bin/badvpn-udpgw "https://github.com/ambrop72/badvpn/raw/master/badvpn-udpgw64"
fi
chmod +x /usr/local/bin/badvpn-udpgw

cat <<EOF > /etc/systemd/system/udpgw@.service
[Unit]
Description=BadVPN UDPGW Service on Port %i
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:%i --max-clients 1000 --max-connections-for-client 100
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl stop udpgw@7200 >/dev/null 2>&1
systemctl disable udpgw@7200 >/dev/null 2>&1
systemctl daemon-reload
for port in 7100 7300; do
    systemctl enable udpgw@${port} >/dev/null 2>&1
    systemctl restart udpgw@${port}
done

# 13. ตั้งค่า Dropbear (พอร์ต 109 และ 143) และ SSH WebSocket (ws-epro พอร์ต 10015)
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

if ! grep -qxF '/bin/false' /etc/shells; then echo "/bin/false" >> /etc/shells; fi
if ! grep -qxF '/usr/sbin/nologin' /etc/shells; then echo "/usr/sbin/nologin" >> /etc/shells; fi

cat <<EOF > /etc/issue.net
<p style="text-align:center"><b>=== PRIVATE VPN SERVER (NO TORRENT) ===</b></p>
EOF

systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear

cat << 'EOF' > /usr/local/bin/ws-epro
#!/usr/bin/env python3
import socket, threading, select

LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 10015
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 22

def handle_client(client_sock):
    target_sock = None
    try:
        client_sock.settimeout(10)
        data = client_sock.recv(4096)
        if not data:
            return
        client_sock.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        client_sock.settimeout(None)

        target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_sock.connect((TARGET_HOST, TARGET_PORT))

        sockets = [client_sock, target_sock]
        while True:
            r, _, _ = select.select(sockets, [], [], 120)
            if not r:
                break
            for s in r:
                buf = s.recv(16384)
                if not buf:
                    return
                if s is client_sock:
                    target_sock.sendall(buf)
                else:
                    client_sock.sendall(buf)
    except Exception:
        pass
    finally:
        try: client_sock.close()
        except: pass
        try:
            if target_sock: target_sock.close()
        except: pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(1024)
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
RestartSec=2
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ws-epro >/dev/null 2>&1
systemctl restart ws-epro

# 14. สร้างสคริปต์ลบบัญชีหมดอายุอัตโนมัติ (xp)
cat << 'EOF' > /usr/bin/xp
#!/bin/bash
export LC_ALL=en_US.UTF-8
today=$(date +%Y-%m-%d)
today_sec=$(date -d "$today" +%s)

for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    exp_date=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
    if [ "$exp_date" != "never" ] && [ -n "$exp_date" ]; then
        exp_sec=$(date -d "$exp_date" +%s)
        if [ $today_sec -ge $exp_sec ]; then
            killall -u "$user" 2>/dev/null
            userdel -f "$user"
            sed -i "/^$user:/d" /etc/zivpn/zivpn-users.txt 2>/dev/null
            echo "Deleted Expired SSH Account: $user"
        fi
    fi
done

if [ -f /etc/xray/xray-exp.txt ]; then
    while IFS=':' read -r x_user x_exp; do
        [ -z "$x_user" ] && continue
        exp_sec=$(date -d "$x_exp" +%s)
        if [ $today_sec -ge $exp_sec ]; then
            jq --arg u "$x_user" \
               '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
                (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            sed -i "/^$x_user:/d" /etc/xray/xray-exp.txt
            sed -i "/^$x_user:/d" /etc/xray/xray-lock.txt 2>/dev/null
            systemctl restart xray
            echo "Deleted Expired Xray Account: $x_user"
        fi
    done < /etc/xray/xray-exp.txt
fi

if [ -f /etc/zivpn/zivpn-exp.txt ]; then
    while IFS=':' read -r z_pass z_exp; do
        [ -z "$z_pass" ] && continue
        exp_sec=$(date -d "$z_exp" +%s)
        if [ $today_sec -ge $exp_sec ]; then
            jq --arg p "$z_pass" '.auth.config -= [$p]' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
            sed -i "/^$z_pass:/d" /etc/zivpn/zivpn-exp.txt
            sed -i "/:$z_pass$/d" /etc/zivpn/zivpn-users.txt 2>/dev/null
            systemctl restart zivpn
            echo "Deleted Expired ZIVPN Password: $z_pass"
        fi
    done < /etc/zivpn/zivpn-exp.txt
fi

if [ -f /etc/hysteria/hys-users.txt ]; then
    hys_changed=0
    while IFS=':' read -r h_user h_pass h_exp; do
        if [ -n "$h_exp" ]; then
            exp_sec=$(date -d "$h_exp" +%s 2>/dev/null)
            [ -z "$exp_sec" ] && exp_sec=9999999999
            if [ $today_sec -ge $exp_sec ]; then
                sed -i "/^$h_user:/d" /etc/hysteria/hys-users.txt
                echo "Deleted Expired Hysteria2 Account: $h_user"
                hys_changed=1
            fi
        fi
    done < /etc/hysteria/hys-users.txt
    [ $hys_changed -eq 1 ] && /usr/bin/rebuild-hysteria
fi
EOF
chmod +x /usr/bin/xp

# 15. สร้างสคริปต์เตะคนล็อกอินซ้อน (tendang), ล้างขยะ (clear-log), สำรองข้อมูล (backup-vpn / restore-vpn)
[ ! -f /etc/xray/limit-ssh ] && echo "2" > /etc/xray/limit-ssh
[ ! -f /etc/xray/autoreboot-status ] && echo "เปิดใช้งาน (ทุกวัน เวลา 03:00 น.)" > /etc/xray/autoreboot-status

cat << 'EOF' > /usr/bin/tendang
#!/bin/bash
MAX=$(cat /etc/xray/limit-ssh 2>/dev/null)
[ -z "$MAX" ] && MAX=2
if [ "$MAX" -le 0 ]; then
    exit 0
fi

for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    pids=$(pgrep -u "$user" sshd)
    if [ -n "$pids" ]; then
        count=$(echo "$pids" | wc -l)
    else
        count=0
    fi

    if [ $count -gt $MAX ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Kick Multi-Login User: $user ($count/$MAX sessions)" >> /var/log/autokill.log
        kill -9 $pids 2>/dev/null
    fi
done
EOF
chmod +x /usr/bin/tendang

cat << 'EOF' > /usr/bin/clear-log
#!/bin/bash
for logfile in /var/log/xray/access.log /var/log/xray/error.log /var/log/nginx/access.log /var/log/nginx/error.log /var/log/syslog /var/log/btmp /var/log/messages /var/log/debug; do
    if [ -f "$logfile" ]; then
        cat /dev/null > "$logfile"
    fi
done
journalctl --vacuum-size=50M >/dev/null 2>&1
sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
EOF
chmod +x /usr/bin/clear-log

cat << 'EOF' > /usr/bin/backup-vpn
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

MYIP=$(curl -sS ipv4.icanhazip.com)
DATE=$(date +%Y-%m-%d_%H-%M)
RAND_KEY=$(openssl rand -hex 4)
BACKUP_DIR="/tmp/vpn_backup_data"
ZIP_NAME="vpn-backup-${DATE}-${RAND_KEY}.zip"

rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/xray" "$BACKUP_DIR/zivpn" "$BACKUP_DIR/hysteria" "$BACKUP_DIR/api"

> "$BACKUP_DIR/ssh-users.txt"
for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    hash=$(grep "^${user}:" /etc/shadow | cut -d: -f2)
    exp_raw=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
    if [ "$exp_raw" = "never" ] || [ -z "$exp_raw" ]; then
        exp_ymd="never"
    else
        exp_ymd=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null)
        [ -z "$exp_ymd" ] && exp_ymd="never"
    fi
    echo "${user}|${hash}|${exp_ymd}" >> "$BACKUP_DIR/ssh-users.txt"
done

cp -f /etc/xray/config.json "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/xray-exp.txt "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/xray-lock.txt "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/limit-ssh "$BACKUP_DIR/xray/" 2>/dev/null

cp -f /etc/zivpn/config.json "$BACKUP_DIR/zivpn/" 2>/dev/null
cp -f /etc/zivpn/zivpn-exp.txt "$BACKUP_DIR/zivpn/" 2>/dev/null
cp -f /etc/zivpn/zivpn-users.txt "$BACKUP_DIR/zivpn/" 2>/dev/null

cp -f /etc/hysteria/hys-users.txt "$BACKUP_DIR/hysteria/" 2>/dev/null
cp -f /home/vps/public_html/api_ssh.php "$BACKUP_DIR/api/" 2>/dev/null

cd "$BACKUP_DIR" || exit
zip -r -q "/root/${ZIP_NAME}" ./*
cd /root || exit
rm -rf "$BACKUP_DIR"

mkdir -p /home/vps/public_html
rm -f /home/vps/public_html/vpn-backup-*.zip
cp "/root/${ZIP_NAME}" "/home/vps/public_html/${ZIP_NAME}"
chown www-data:www-data "/home/vps/public_html/${ZIP_NAME}"
chmod 644 "/home/vps/public_html/${ZIP_NAME}"

TELE_STAT="ไม่ได้ตั้งค่า"
if [ -f /etc/xray/tele-bot.conf ]; then
    source /etc/xray/tele-bot.conf
    if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        curl -s -F chat_id="$CHAT_ID" \
             -F document=@"/root/${ZIP_NAME}" \
             -F caption="📦 Backup ข้อมูล VPN เซิร์ฟเวอร์: ${MYIP} (${DATE})" \
             "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" >/dev/null 2>&1
        TELE_STAT="${GREEN}ส่งเข้า Telegram เรียบร้อยแล้ว${NC}"
    fi
fi

if [ "$1" != "silent" ]; then
    clear
    echo -e "${YELLOW}================= สำรองข้อมูลสำเร็จ (BACKUP) =================${NC}"
    echo -e "ไฟล์สำรองในเครื่อง : ${GREEN}/root/${ZIP_NAME}${NC}"
    echo -e "ลิงก์สำหรับดึงย้ายเครื่อง : ${CYAN}http://${MYIP}:8081/${ZIP_NAME}${NC}"
    echo -e "สถานะ Telegram : ${TELE_STAT}"
    echo -e "${YELLOW}------------------------------------------------------------${NC}"
    echo -e "วิธีใช้งาน: นำลิงก์ด้านบนไปวางในเมนู [30] ของเซิร์ฟเวอร์เครื่องใหม่ได้เลย"
    echo -e "${YELLOW}============================================================${NC}"
fi
EOF
chmod +x /usr/bin/backup-vpn

cat << 'EOF' > /usr/bin/restore-vpn
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${YELLOW}============= กู้คืนข้อมูลบัญชีทั้งหมด (RESTORE) =============${NC}"
echo -e "สามารถใส่ได้ทั้ง ลิงก์ตรง (http://...:8081/vpn-backup-xxx.zip)"
echo -e "หรือ พาธไฟล์ในเครื่อง (เช่น /root/vpn-backup-xxx.zip)"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
read -rp "กรอกลิงก์ หรือ พาธไฟล์ Backup (.zip): " src_input

if [ -z "$src_input" ]; then
    echo -e "${RED}ยกเลิกการทำรายการ${NC}"
    exit 1
fi

RESTORE_ZIP="/tmp/restore_target.zip"
RESTORE_DIR="/tmp/vpn_restore_data"
rm -rf "$RESTORE_ZIP" "$RESTORE_DIR"

case "$src_input" in
    http*)
        echo -e "${CYAN}กำลังดาวน์โหลดไฟล์สำรองข้อมูล...${NC}"
        wget -q -O "$RESTORE_ZIP" "$src_input"
        ;;
    *)
        if [ -f "$src_input" ]; then
            cp "$src_input" "$RESTORE_ZIP"
        fi
        ;;
esac

if [ ! -s "$RESTORE_ZIP" ]; then
    echo -e "${RED}ไม่พบไฟล์สำรองข้อมูล หรือดาวน์โหลดไม่สำเร็จ!${NC}"
    exit 1
fi

mkdir -p "$RESTORE_DIR"
unzip -q "$RESTORE_ZIP" -d "$RESTORE_DIR"

if [ -f "$RESTORE_DIR/ssh-users.txt" ]; then
    while IFS='|' read -r u hash exp; do
        if [ -n "$u" ] && [ -n "$hash" ]; then
            if ! id "$u" >/dev/null 2>&1; then
                useradd -s /bin/false -M "$u" 2>/dev/null
            fi
            usermod -p "$hash" "$u" 2>/dev/null
            if [ "$exp" != "never" ] && [ -n "$exp" ]; then
                chage -E "$exp" "$u" 2>/dev/null
            fi
        fi
    done < "$RESTORE_DIR/ssh-users.txt"
fi

mkdir -p /etc/xray
[ -f "$RESTORE_DIR/xray/config.json" ] && cp -f "$RESTORE_DIR/xray/config.json" /etc/xray/config.json
[ -f "$RESTORE_DIR/xray/xray-exp.txt" ] && cp -f "$RESTORE_DIR/xray/xray-exp.txt" /etc/xray/xray-exp.txt
[ -f "$RESTORE_DIR/xray/xray-lock.txt" ] && cp -f "$RESTORE_DIR/xray/xray-lock.txt" /etc/xray/xray-lock.txt
[ -f "$RESTORE_DIR/xray/limit-ssh" ] && cp -f "$RESTORE_DIR/xray/limit-ssh" /etc/xray/limit-ssh

mkdir -p /etc/zivpn
[ -f "$RESTORE_DIR/zivpn/config.json" ] && cp -f "$RESTORE_DIR/zivpn/config.json" /etc/zivpn/config.json
[ -f "$RESTORE_DIR/zivpn/zivpn-exp.txt" ] && cp -f "$RESTORE_DIR/zivpn/zivpn-exp.txt" /etc/zivpn/zivpn-exp.txt
[ -f "$RESTORE_DIR/zivpn/zivpn-users.txt" ] && cp -f "$RESTORE_DIR/zivpn/zivpn-users.txt" /etc/zivpn/zivpn-users.txt

mkdir -p /etc/hysteria
if [ -f "$RESTORE_DIR/hysteria/hys-users.txt" ]; then
    cp -f "$RESTORE_DIR/hysteria/hys-users.txt" /etc/hysteria/hys-users.txt
    /usr/bin/rebuild-hysteria
fi

if [ -f "$RESTORE_DIR/api/api_ssh.php" ]; then
    mkdir -p /home/vps/public_html /root/vnext_api
    cp -f "$RESTORE_DIR/api/api_ssh.php" /home/vps/public_html/api_ssh.php
    cp -f "$RESTORE_DIR/api/api_ssh.php" /root/vnext_api/api_ssh.php
    chown -R www-data:www-data /home/vps/public_html
    chmod -R 755 /home/vps/public_html
fi

rm -rf "$RESTORE_ZIP" "$RESTORE_DIR"
systemctl restart ssh dropbear xray zivpn hysteria udp-custom nginx >/dev/null 2>&1

echo -e "${GREEN}กู้คืนข้อมูลบัญชีทั้งหมด (SSH, UDP Custom, Xray, ZIVPN, Hysteria 2 และ API) เรียบร้อยแล้ว!${NC}"
EOF
chmod +x /usr/bin/restore-vpn

if [ ! -f /etc/cron.d/vpn-cron ]; then
cat <<EOF > /etc/cron.d/vpn-cron
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
* * * * * root /usr/bin/tendang
0 */6 * * * root /usr/bin/clear-log
0 3 * * * root /sbin/reboot
EOF
fi
systemctl restart cron

# 16. สร้างคำสั่งเช็กสถานะ 'running'
cat << 'EOF' > /usr/bin/running
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

check_status() {
    if systemctl is-active --quiet "$1"; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

TorrentRules=$(iptables -L OUTPUT -n | grep -c "BitTorrent")
if [ "$TorrentRules" -gt 0 ]; then
    TORRENT_STAT="${GREEN}[ACTIVE]${NC}"
else
    TORRENT_STAT="${RED}[INACTIVE]${NC}"
fi

if netstat -tunlp | grep -q ":8081 "; then
    API_STAT="${GREEN}[ON]${NC}"
else
    API_STAT="${RED}[OFF]${NC}"
fi

REBOOT_STAT=$(cat /etc/xray/autoreboot-status 2>/dev/null)
[ -z "$REBOOT_STAT" ] && REBOOT_STAT="เปิดใช้งาน (03:00 น.)"

clear
echo -e "${YELLOW}=========================================${NC}"
echo -e "           ${CYAN}STATUS RUNNING SERVICE${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo -e " OpenSSH Service          : $(check_status ssh)"
echo -e " Dropbear Service         : $(check_status dropbear)"
echo -e " Nginx Proxy (80 / 443)   : $(check_status nginx)"
echo -e " Web Panel & API (8081)   : ${API_STAT}"
echo -e " Xray Core (Vmess/Vless)  : $(check_status xray)"
echo -e " UDP Custom (Port 7200)   : $(check_status udp-custom)"
echo -e " BadVPN UDPGW (Port 7300) : $(check_status udpgw@7300)"
echo -e " ZIVPN UDP (5667/6000+)   : $(check_status zivpn)"
echo -e " Hysteria 2 (8443/20000+) : $(check_status hysteria)"
echo -e " SSH WebSocket (10015)    : $(check_status ws-epro)"
echo -e " Fail2Ban (Anti-Brute)    : $(check_status fail2ban)"
echo -e " Anti-Torrent Firewall    : ${TORRENT_STAT}"
echo -e " Cron (Auto-Kill / Exp)   : $(check_status cron)"
echo -e " Auto-Reboot Schedule     : ${GREEN}${REBOOT_STAT}${NC}"
echo -e "${YELLOW}=========================================${NC}"
EOF
chmod +x /usr/bin/running

# 17. สร้างคำสั่งหน้าหลัก 'menu'
cat << 'EOF' > /usr/bin/menu
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

MYIP=$(curl -sS ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)
[ -z "$DOMAIN" ] && DOMAIN="$MYIP"
MAX_LOGIN=$(cat /etc/xray/limit-ssh 2>/dev/null)
[ -z "$MAX_LOGIN" ] && MAX_LOGIN="2"
REBOOT_STAT=$(cat /etc/xray/autoreboot-status 2>/dev/null)
[ -z "$REBOOT_STAT" ] && REBOOT_STAT="เปิดใช้งาน (ทุกวัน เวลา 03:00 น.)"
RAM_USAGE=$(free -m | awk 'NR==2{printf "%s/%s MB (%.1f%%)", $3,$2,$3*100/$2 }')
mkdir -p /etc/xray /etc/zivpn /etc/hysteria
touch /etc/xray/xray-exp.txt /etc/xray/xray-lock.txt /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt /etc/hysteria/hys-users.txt

clear
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
echo -e "               ${CYAN}PRIVATE VPN MENU${NC}"
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
echo -e " IP Address  : ${GREEN}${MYIP}${NC}"
echo -e " Domain      : ${GREEN}${DOMAIN}${NC}"
echo -e " Web Panel   : ${CYAN}http://${DOMAIN}:8081${NC}"
echo -e " RAM Usage   : ${GREEN}${RAM_USAGE}${NC}"
echo -e " Multi-Login : ${GREEN}สูงสุด ${MAX_LOGIN} เครื่อง/บัญชี${NC}"
echo -e " Auto-Reboot : ${GREEN}${REBOOT_STAT}${NC}"
echo -e "${YELLOW}☉—————— [ จัดการบัญชี SSH / ZIVPN / HYS2 ] ——————☉${NC}"
echo -e " [1]  สร้างบัญชี All-in-One (SSH + UDP Custom + ZIVPN + Hys2)"
echo -e " [2]  ต่ออายุบัญชี All-in-One (Renew)"
echo -e " [3]  ระงับ / ปลดล็อกบัญชี SSH (Lock/Unlock)"
echo -e " [4]  ลบบัญชี All-in-One (Delete)"
echo -e " [5]  ดูรายชื่อบัญชี SSH ทั้งหมด"
echo -e "${YELLOW}☉——————————— [ จัดการบัญชี XRAY CORE ] ——————————☉${NC}"
echo -e " [6]  สร้างบัญชี Xray (Vmess & Vless)"
echo -e " [7]  ต่ออายุบัญชี Xray (Renew)"
echo -e " [8]  ระงับ / ปลดล็อกบัญชี Xray (Lock/Unlock)"
echo -e " [9]  ลบบัญชี Xray (Vmess & Vless)"
echo -e " [10] ดูรายชื่อบัญชี Xray และขอดูลิงก์ย้อนหลัง"
echo -e "${YELLOW}☉——————————— [ จัดการบัญชี ZIVPN UDP ] ——————————☉${NC}"
echo -e " [11] สร้างรหัสผ่าน ZIVPN UDP แยกเฉพาะ"
echo -e " [12] ต่ออายุรหัสผ่าน ZIVPN UDP (Renew)"
echo -e " [13] ลบรหัสผ่าน ZIVPN UDP (Delete)"
echo -e " [14] ดูรหัสผ่าน ZIVPN UDP ทั้งหมด"
echo -e "${YELLOW}☉——————————— [ จัดการบัญชี HYSTERIA 2 ] —————————☉${NC}"
echo -e " [15] สร้างบัญชี Hysteria 2 แยกเฉพาะ"
echo -e " [16] ต่ออายุบัญชี Hysteria 2 (Renew)"
echo -e " [17] ลบบัญชี Hysteria 2 (Delete)"
echo -e " [18] ดูรายชื่อบัญชี Hysteria 2 และขอดูลิงก์เชื่อมต่อ"
echo -e "${YELLOW}☉—————— [ ความปลอดภัย / บำรุงรักษา / สำรองข้อมูล ] —————☉${NC}"
echo -e " [19] เช็กผู้ใช้ออนไลน์ (SSH / Dropbear / Xray)"
echo -e " [20] ตั้งค่าจำกัดจำนวนเครื่องล็อกอิน (Auto-Kill)"
echo -e " [21] เปลี่ยนโดเมนและขอ SSL ใหม่ (Port 443)"
echo -e " [22] เช็กสถานะบริการและไฟร์วอลล์ (running)"
echo -e " [23] รีสตาร์ทบริการทั้งหมด"
echo -e " [24] ลบบัญชีที่หมดอายุทันที (เคลียร์ขยะบัญชี)"
echo -e " [25] ล้างไฟล์ขยะ Log และเคลียร์ RAM ทันที"
echo -e " [26] ตั้งเวลา Auto-Reboot เซิร์ฟเวอร์อัตโนมัติ"
echo -e " [27] อัปเดตสคริปต์และเมนูเวอร์ชันล่าสุดจาก GitHub"
echo -e " [28] ดูข้อมูลเชื่อมต่อ Web Panel & API (Port 8081)"
echo -e " [29] สำรองข้อมูลบัญชีทั้งหมด (Backup & Telegram Bot)"
echo -e " [30] กู้คืนข้อมูลบัญชีทั้งหมด (Restore ย้ายเซิร์ฟเวอร์)"
echo -e " [31] ทดสอบความเร็วอินเทอร์เน็ตเซิร์ฟเวอร์ (Speedtest by Ookla)"
echo -e " [0]  ออกจากเมนู"
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
read -rp "เลือกเมนู [0-31]: " opt

case $opt in
    1)
        read -rp "ชื่อผู้ใช้ (Username): " user
        if id "$user" >/dev/null 2>&1; then
            echo -e "${RED}ชื่อผู้ใช้นี้มีอยู่ในระบบแล้ว!${NC}"
            exit 1
        fi
        read -rp "รหัสผ่าน (Password): " pass
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")
        /usr/bin/api-vpn add "$user" "$pass" "$exp"
        if ! id "$user" >/dev/null 2>&1; then
            echo -e "${RED}สร้างบัญชีไม่สำเร็จ! ระบบติดล็อก กรุณาลองใหม่อีกครั้ง${NC}"
            exit 1
        fi
        pass_enc=$(echo -n "$pass" | jq -sRr @uri)
        HYS_LINK="hysteria2://${pass_enc}@${DOMAIN}:8443/?insecure=1&sni=${DOMAIN}#${user}-Hysteria2"
        HYS_HOP="hysteria2://${pass_enc}@${DOMAIN}:20000/?insecure=1&sni=${DOMAIN}&mport=20000-50000#${user}-Hys2-Hopping"
        clear
        echo -e "${YELLOW}=== ข้อมูลบัญชี SSH, UDP Custom, ZIVPN & Hysteria 2 ===${NC}"
        echo -e "Host/IP      : $DOMAIN ($MYIP)"
        echo -e "Username     : $user"
        echo -e "Password     : $pass"
        echo -e "OpenSSH      : 22 | Dropbear : 109, 143"
        echo -e "WS Port      : 80 | WS TLS   : 443"
        echo -e "UDP Custom   : 1-5999, 50001-65535 (พอร์ตภายใน 7200)"
        echo -e "BadVPN UDPGW : 7100, 7300"
        echo -e "ZIVPN UDP    : 5667, 6000-19999 (ใช้รหัส $pass)"
        echo -e "Hysteria 2   : 8443, 20000-50000 (ใช้รหัส $pass)"
        echo -e "Payload WS   : GET /ssh-ws HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
        echo -e "หมดอายุวันที่   : ${exp}"
        echo -e "${YELLOW}----------------------------------------------------${NC}"
        echo -e "${CYAN}[ลิงก์เชื่อมต่อ Hysteria 2 แบบ Port Hopping (20000-50000)]${NC}"
        echo -e "${HYS_HOP}"
        echo -e "${YELLOW}====================================================${NC}"
        ;;
    2)
        read -rp "พิมพ์ชื่อบัญชีที่ต้องการต่ออายุ: " user
        if ! id "$user" >/dev/null 2>&1; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        exp_old=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
        today_sec=$(date +%s)
        exp_sec=$(date -d "$exp_old" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$exp_old" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        /usr/bin/api-vpn renew "$user" "" "$new_exp"
        echo -e "${GREEN}ต่ออายุบัญชี ${user} (SSH + UDP Custom + ZIVPN + Hysteria 2) สำเร็จ! หมดอายุ: ${new_exp}${NC}"
        ;;
    3)
        echo -e " [1] ระงับบัญชีชั่วคราว (Lock)"
        echo -e " [2] ปลดล็อกบัญชี (Unlock)"
        read -rp "เลือกทำรายการ [1-2]: " lopt
        read -rp "พิมพ์ชื่อบัญชี SSH: " user
        if ! id "$user" >/dev/null 2>&1; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        if [ "$lopt" = "1" ]; then
            passwd -l "$user" >/dev/null 2>&1
            killall -u "$user" 2>/dev/null
            echo -e "${YELLOW}ระงับการใช้งานและตัดการเชื่อมต่อบัญชี ${user} เรียบร้อยแล้ว!${NC}"
        elif [ "$lopt" = "2" ]; then
            passwd -u "$user" >/dev/null 2>&1
            echo -e "${GREEN}ปลดล็อกบัญชี ${user} ให้กลับมาใช้งานได้ตามปกติแล้ว!${NC}"
        fi
        ;;
    4)
        read -rp "พิมพ์ชื่อบัญชีที่ต้องการลบ: " delssh
        if id "$delssh" >/dev/null 2>&1; then
            /usr/bin/api-vpn delete "$delssh" "" ""
            echo -e "${GREEN}ลบบัญชี ${delssh} ออกจากทั้ง SSH, UDP Custom, ZIVPN และ Hysteria 2 เรียบร้อยแล้ว!${NC}"
        else
            echo -e "${RED}ไม่พบชื่อบัญชี ${delssh} ในระบบ!${NC}"
        fi
        ;;
    5)
        clear
        echo -e "${YELLOW}========= รายชื่อบัญชี SSH ทั้งหมด =========${NC}"
        printf "%-18s %-20s %s\n" "Username" "Expire Date" "Status"
        echo -e "---------------------------------------------------"
        for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | tac); do
            exp=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
            passwd_stat=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
            if [ "$passwd_stat" = "L" ]; then
                stat="${RED}Locked${NC}"
            else
                stat="${GREEN}Active${NC}"
            fi
            printf "%-18s %-20s %b\n" "$user" "$exp" "$stat"
        done
        echo -e "${YELLOW}=========================================${NC}"
        ;;
    6)
        read -rp "ตั้งชื่อบัญชี Xray (ห้ามซ้ำ): " user
        if [ -z "$user" ]; then
            echo -e "${RED}ชื่อบัญชีห้ามเว้นว่าง!${NC}"
            exit 1
        fi
        if grep -q "^${user}:" /etc/xray/xray-exp.txt; then
            echo -e "${RED}มีชื่อบัญชีนี้อยู่ในระบบแล้ว!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")
        UUID=$(cat /proc/sys/kernel/random/uuid)

        jq --arg u "$user" --arg id "$UUID" \
           '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}] |
            .inbounds[1].settings.clients += [{"id": $id, "email": $u}]' \
           /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
        echo "$user:$exp" >> /etc/xray/xray-exp.txt
        systemctl restart xray

        VMESS_TLS=$(cat <<JSON | base64 -w 0
{"v":"2","ps":"${user}-TLS","add":"${DOMAIN}","port":"443","id":"${UUID}","aid":"0","net":"ws","path":"/vmess","type":"none","host":"${DOMAIN}","tls":"tls"}
JSON
)
        VMESS_NTLS=$(cat <<JSON | base64 -w 0
{"v":"2","ps":"${user}-HTTP","add":"${DOMAIN}","port":"80","id":"${UUID}","aid":"0","net":"ws","path":"/vmess","type":"none","host":"${DOMAIN}","tls":"none"}
JSON
)
        VLESS_TLS="vless://${UUID}@${DOMAIN}:443?path=%2Fvless&security=tls&encryption=none&type=ws&host=${DOMAIN}&sni=${DOMAIN}#${user}-TLS"
        VLESS_NTLS="vless://${UUID}@${DOMAIN}:80?path=%2Fvless&security=none&encryption=none&type=ws&host=${DOMAIN}#${user}-HTTP"

        clear
        echo -e "${YELLOW}====== ข้อมูลบัญชี Xray (Vmess / Vless) ======${NC}"
        echo -e "ชื่อบัญชี        : ${GREEN}${user}${NC}"
        echo -e "Host / Domain : ${GREEN}${DOMAIN}${NC}"
        echo -e "Port TLS/HTTP : 443 / 80"
        echo -e "UUID          : ${GREEN}${UUID}${NC}"
        echo -e "หมดอายุวันที่     : ${GREEN}${exp} (${days} วัน)${NC}"
        echo -e "${YELLOW}-------------------------------------------${NC}"
        echo -e "${CYAN}[ลิงก์ Vmess SSL/TLS (Port 443)]${NC}\nvmess://${VMESS_TLS}\n"
        echo -e "${CYAN}[ลิงก์ Vmess HTTP (Port 80)]${NC}\nvmess://${VMESS_NTLS}\n"
        echo -e "${CYAN}[ลิงก์ Vless SSL/TLS (Port 443)]${NC}\n${VLESS_TLS}\n"
        echo -e "${CYAN}[ลิงก์ Vless HTTP (Port 80)]${NC}\n${VLESS_NTLS}\n"
        echo -e "${YELLOW}===========================================${NC}"
        ;;
    7)
        read -rp "พิมพ์ชื่อบัญชี Xray ที่ต้องการต่ออายุ: " user
        old_exp=$(grep "^${user}:" /etc/xray/xray-exp.txt | cut -d: -f2)
        if [ -z "$old_exp" ]; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$old_exp" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        sed -i "s/^${user}:${old_exp}/${user}:${new_exp}/g" /etc/xray/xray-exp.txt
        echo -e "${GREEN}ต่ออายุบัญชี Xray: ${user} สำเร็จ! วันหมดอายุใหม่คือ: ${new_exp}${NC}"
        ;;
    8)
        echo -e " [1] ระงับบัญชี Xray ชั่วคราว (Lock)"
        echo -e " [2] ปลดล็อกบัญชี Xray (Unlock)"
        read -rp "เลือกทำรายการ [1-2]: " xlopt
        read -rp "พิมพ์ชื่อบัญชี Xray: " user
        if ! grep -q "^${user}:" /etc/xray/xray-exp.txt; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        if [ "$xlopt" = "1" ]; then
            if grep -q "^${user}:" /etc/xray/xray-lock.txt; then
                echo -e "${YELLOW}บัญชีนี้ถูกระงับอยู่แล้ว!${NC}"
                exit 1
            fi
            uuid=$(jq -r --arg u "$user" '.inbounds[0].settings.clients[] | select(.email == $u) | .id' /etc/xray/config.json)
            echo "${user}:${uuid}" >> /etc/xray/xray-lock.txt
            jq --arg u "$user" \
               '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
                (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            systemctl restart xray
            echo -e "${YELLOW}ระงับการใช้งานบัญชี Xray: ${user} ชั่วคราวเรียบร้อยแล้ว!${NC}"
        elif [ "$xlopt" = "2" ]; then
            uuid=$(grep "^${user}:" /etc/xray/xray-lock.txt | cut -d: -f2)
            if [ -z "$uuid" ]; then
                echo -e "${RED}บัญชีนี้ไม่ได้อยู่ในสถานะถูกระงับ!${NC}"
                exit 1
            fi
            jq --arg u "$user" --arg id "$uuid" \
               '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}] |
                .inbounds[1].settings.clients += [{"id": $id, "email": $u}]' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            sed -i "/^${user}:/d" /etc/xray/xray-lock.txt
            systemctl restart xray
            echo -e "${GREEN}ปลดล็อกบัญชี Xray: ${user} (UUID เดิม) เรียบร้อยแล้ว!${NC}"
        fi
        ;;
    9)
        read -rp "พิมพ์ชื่อบัญชี Xray ที่ต้องการลบถาวร: " deluser
        if [ "$deluser" = "default" ]; then
            echo -e "${RED}ไม่สามารถลบบัญชีเริ่มต้น (default) ได้!${NC}"
            exit 1
        fi
        jq --arg u "$deluser" \
           '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
            (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
           /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
        sed -i "/^$deluser:/d" /etc/xray/xray-exp.txt
        sed -i "/^$deluser:/d" /etc/xray/xray-lock.txt
        systemctl restart xray
        echo -e "${GREEN}ลบบัญชี ${deluser} ถาวรเรียบร้อยแล้ว!${NC}"
        ;;
    10)
        clear
        echo -e "${YELLOW}================= รายชื่อบัญชี Xray ทั้งหมด =================${NC}"
        printf "%-15s %-15s %-12s %s\n" "Username" "Expire Date" "Status" "UUID"
        echo -e "------------------------------------------------------------"
        if [ -s /etc/xray/xray-exp.txt ]; then
            while IFS=':' read -r u exp; do
                if grep -q "^${u}:" /etc/xray/xray-lock.txt; then
                    uuid=$(grep "^${u}:" /etc/xray/xray-lock.txt | cut -d: -f2)
                    stat="${RED}Locked${NC}"
                else
                    uuid=$(jq -r --arg usr "$u" '.inbounds[0].settings.clients[] | select(.email == $usr) | .id' /etc/xray/config.json)
                    stat="${GREEN}Active${NC}"
                fi
                printf "%-15s %-15s %-21b %s\n" "$u" "$exp" "$stat" "$uuid"
            done < /etc/xray/xray-exp.txt
        else
            echo "ยังไม่มีการสร้างบัญชี Xray ในระบบ"
        fi
        echo -e "${YELLOW}============================================================${NC}"
        read -rp "ต้องการดูลิงก์เชื่อมต่อของบัญชีใดไหมครับ? (พิมพ์ชื่อบัญชี หรือกด Enter เพื่อข้าม): " showuser
        if [ -n "$showuser" ]; then
            UUID=$(jq -r --arg usr "$showuser" '.inbounds[0].settings.clients[] | select(.email == $usr) | .id' /etc/xray/config.json)
            if [ -z "$UUID" ]; then
                UUID=$(grep "^${showuser}:" /etc/xray/xray-lock.txt | cut -d: -f2)
            fi
            if [ -n "$UUID" ]; then
                VMESS_TLS=$(cat <<JSON | base64 -w 0
{"v":"2","ps":"${showuser}-TLS","add":"${DOMAIN}","port":"443","id":"${UUID}","aid":"0","net":"ws","path":"/vmess","type":"none","host":"${DOMAIN}","tls":"tls"}
JSON
)
                VMESS_NTLS=$(cat <<JSON | base64 -w 0
{"v":"2","ps":"${showuser}-HTTP","add":"${DOMAIN}","port":"80","id":"${UUID}","aid":"0","net":"ws","path":"/vmess","type":"none","host":"${DOMAIN}","tls":"none"}
JSON
)
                VLESS_TLS="vless://${UUID}@${DOMAIN}:443?path=%2Fvless&security=tls&encryption=none&type=ws&host=${DOMAIN}&sni=${DOMAIN}#${showuser}-TLS"
                VLESS_NTLS="vless://${UUID}@${DOMAIN}:80?path=%2Fvless&security=none&encryption=none&type=ws&host=${DOMAIN}#${showuser}-HTTP"
                echo -e "\n${CYAN}[ลิงก์ Vmess SSL/TLS (443)]${NC}\nvmess://${VMESS_TLS}\n"
                echo -e "${CYAN}[ลิงก์ Vmess HTTP (80)]${NC}\nvmess://${VMESS_NTLS}\n"
                echo -e "${CYAN}[ลิงก์ Vless SSL/TLS (443)]${NC}\n${VLESS_TLS}\n"
                echo -e "${CYAN}[ลิงก์ Vless HTTP (80)]${NC}\n${VLESS_NTLS}\n"
            else
                echo -e "${RED}ไม่พบบัญชี ${showuser}${NC}"
            fi
        fi
        ;;
    11)
        read -rp "กำหนดรหัสผ่าน (udp password) [กด Enter เพื่อสุ่มอัตโนมัติ 8 หลัก]: " zpass
        if [ -z "$zpass" ]; then
            zpass=$(openssl rand -hex 4)
        fi
        if grep -q "^${zpass}:" /etc/zivpn/zivpn-exp.txt; then
            echo -e "${RED}รหัสผ่านนี้มีอยู่ในระบบแล้ว!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")

        jq --arg p "$zpass" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
        echo "${zpass}:${exp}" >> /etc/zivpn/zivpn-exp.txt
        systemctl restart zivpn

        clear
        echo -e "${YELLOW}====== ข้อมูลการเชื่อมต่อ ZIVPN (UDP Tunnel) ======${NC}"
        echo -e "Receive window : ${GREEN}3 (หรือค่าเริ่มต้น)${NC}"
        echo -e "udp server     : ${GREEN}${DOMAIN}${NC} (หรือ ${MYIP})"
        echo -e "udp password   : ${GREEN}${zpass}${NC}"
        echo -e "Port Range     : 5667, 6000-19999 (UDP)"
        echo -e "หมดอายุวันที่     : ${GREEN}${exp} (${days} วัน)${NC}"
        echo -e "${YELLOW}=================================================${NC}"
        ;;
    12)
        read -rp "พิมพ์รหัสผ่าน ZIVPN (udp password) ที่ต้องการต่ออายุ: " zpass
        old_exp=$(grep "^${zpass}:" /etc/zivpn/zivpn-exp.txt | cut -d: -f2)
        if [ -z "$old_exp" ]; then
            echo -e "${RED}ไม่พบรหัสผ่าน ${zpass} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$old_exp" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        sed -i "s/^${zpass}:${old_exp}/${zpass}:${new_exp}/g" /etc/zivpn/zivpn-exp.txt
        echo -e "${GREEN}ต่ออายุรหัสผ่าน ZIVPN: ${zpass} สำเร็จ! วันหมดอายุใหม่คือ: ${new_exp}${NC}"
        ;;
    13)
        read -rp "พิมพ์รหัสผ่าน ZIVPN (udp password) ที่ต้องการลบ: " delpass
        if grep -q "^${delpass}:" /etc/zivpn/zivpn-exp.txt; then
            jq --arg p "$delpass" '.auth.config -= [$p]' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
            sed -i "/^${delpass}:/d" /etc/zivpn/zivpn-exp.txt
            sed -i "/:${delpass}$/d" /etc/zivpn/zivpn-users.txt 2>/dev/null
            systemctl restart zivpn
            echo -e "${GREEN}ลบรหัสผ่าน ZIVPN: ${delpass} เรียบร้อยแล้ว!${NC}"
        else
            echo -e "${RED}ไม่พบรหัสผ่าน ${delpass} ในระบบ!${NC}"
        fi
        ;;
    14)
        clear
        echo -e "${YELLOW}========= รายชื่อรหัสผ่าน ZIVPN UDP ทั้งหมด =========${NC}"
        echo -e "UDP Server : ${GREEN}${DOMAIN}${NC} (${MYIP})"
        echo -e "------------------------------------------------------------"
        printf "%-20s %-18s %-15s %s\n" "UDP Password" "Owner (SSH User)" "Expire Date" "Status"
        echo -e "------------------------------------------------------------"
        if [ -s /etc/zivpn/zivpn-exp.txt ]; then
            while IFS=':' read -r zp zexp; do
                owner=$(grep ":${zp}$" /etc/zivpn/zivpn-users.txt 2>/dev/null | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
                [ -z "$owner" ] && owner="-"
                printf "%-20s %-18s %-15s %b\n" "$zp" "$owner" "$zexp" "${GREEN}Active${NC}"
            done < /etc/zivpn/zivpn-exp.txt
        else
            echo "ยังไม่มีการสร้างรหัสผ่าน ZIVPN ในระบบ"
        fi
        echo -e "${YELLOW}============================================================${NC}"
        ;;
    15)
        read -rp "ตั้งชื่อผู้ใช้สำหรับบันทึกในระบบ (Username): " huser
        if grep -q "^${huser}:" /etc/hysteria/hys-users.txt; then
            echo -e "${RED}มีชื่อผู้ใช้นี้ในระบบ Hysteria 2 แล้ว!${NC}"
            exit 1
        fi
        read -rp "ตั้งรหัสผ่าน (Password) [กด Enter เพื่อสุ่ม 8 หลัก]: " hpass
        [ -z "$hpass" ] && hpass=$(openssl rand -hex 4)
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")

        echo "${huser}:${hpass}:${exp}" >> /etc/hysteria/hys-users.txt
        /usr/bin/rebuild-hysteria

        pass_enc=$(echo -n "$hpass" | jq -sRr @uri)
        HYS_LINK="hysteria2://${pass_enc}@${DOMAIN}:8443/?insecure=1&sni=${DOMAIN}#${huser}-Hysteria2"
        HYS_HOP="hysteria2://${pass_enc}@${DOMAIN}:20000/?insecure=1&sni=${DOMAIN}&mport=20000-50000#${huser}-Hys2-Hopping"
        clear
        echo -e "${YELLOW}====== ข้อมูลการเชื่อมต่อ Hysteria 2 (UDP QUIC) ======${NC}"
        echo -e "Host / Domain  : ${GREEN}${DOMAIN}${NC} (${MYIP})"
        echo -e "ชื่อกำกับบัญชี      : ${GREEN}${huser}${NC}"
        echo -e "Password       : ${GREEN}${hpass}${NC}"
        echo -e "Main UDP Port  : 20000 (หรือ 8443)"
        echo -e "Port Hopping   : 20000-50000 (UDP)"
        echo -e "หมดอายุวันที่     : ${GREEN}${exp} (${days} วัน)${NC}"
        echo -e "${YELLOW}----------------------------------------------------${NC}"
        echo -e "${CYAN}[ลิงก์ Hysteria 2 แบบ Port Hopping (20000-50000)]${NC}"
        echo -e "${HYS_HOP}\n"
        echo -e "${CYAN}[ลิงก์ Hysteria 2 แบบพอร์ตเดียว (Port 8443)]${NC}"
        echo -e "${HYS_LINK}"
        echo -e "${YELLOW}====================================================${NC}"
        ;;
    16)
        read -rp "พิมพ์ชื่อบัญชี Hysteria 2 ที่ต้องการต่ออายุ: " huser
        line=$(grep "^${huser}:" /etc/hysteria/hys-users.txt)
        if [ -z "$line" ]; then
            echo -e "${RED}ไม่พบบัญชี ${huser} ในระบบ Hysteria 2!${NC}"
            exit 1
        fi
        hpass=$(echo "$line" | cut -d: -f2)
        old_exp=$(echo "$line" | cut -d: -f3)
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$old_exp" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        sed -i "/^${huser}:/d" /etc/hysteria/hys-users.txt
        echo "${huser}:${hpass}:${new_exp}" >> /etc/hysteria/hys-users.txt
        /usr/bin/rebuild-hysteria
        echo -e "${GREEN}ต่ออายุบัญชี Hysteria 2: ${huser} สำเร็จ! วันหมดอายุใหม่คือ: ${new_exp}${NC}"
        ;;
    17)
        read -rp "พิมพ์ชื่อบัญชี Hysteria 2 ที่ต้องการลบ: " delhys
        if grep -q "^${delhys}:" /etc/hysteria/hys-users.txt; then
            sed -i "/^${delhys}:/d" /etc/hysteria/hys-users.txt
            /usr/bin/rebuild-hysteria
            echo -e "${GREEN}ลบบัญชี Hysteria 2: ${delhys} เรียบร้อยแล้ว!${NC}"
        else
            echo -e "${RED}ไม่พบบัญชี ${delhys} ในระบบ!${NC}"
        fi
        ;;
    18)
        clear
        echo -e "${YELLOW}========= รายชื่อบัญชี Hysteria 2 ทั้งหมด =========${NC}"
        printf "%-18s %-18s %-15s %s\n" "Username" "Password" "Expire Date" "Status"
        echo -e "------------------------------------------------------------"
        if [ -s /etc/hysteria/hys-users.txt ]; then
            while IFS=':' read -r hu hp hexp; do
                printf "%-18s %-18s %-15s %b\n" "$hu" "$hp" "$hexp" "${GREEN}Active${NC}"
            done < /etc/hysteria/hys-users.txt
        else
            echo "ยังไม่มีการสร้างบัญชี Hysteria 2 ในระบบ"
        fi
        echo -e "${YELLOW}============================================================${NC}"
        read -rp "ต้องการดูลิงก์เชื่อมต่อของบัญชีใดไหมครับ? (พิมพ์ชื่อผู้ใช้ หรือกด Enter เพื่อข้าม): " showhys
        if [ -n "$showhys" ]; then
            hline=$(grep "^${showhys}:" /etc/hysteria/hys-users.txt)
            if [ -n "$hline" ]; then
                hp=$(echo "$hline" | cut -d: -f2)
                hp_enc=$(echo -n "$hp" | jq -sRr @uri)
                echo -e "\n${CYAN}[ลิงก์ Hysteria 2 แบบ Port Hopping (20000-50000)]${NC}"
                echo -e "hysteria2://${hp_enc}@${DOMAIN}:20000/?insecure=1&sni=${DOMAIN}&mport=20000-50000#${showhys}-Hys2-Hopping\n"
                echo -e "${CYAN}[ลิงก์ Hysteria 2 แบบพอร์ตเดียว (Port 8443)]${NC}"
                echo -e "hysteria2://${hp_enc}@${DOMAIN}:8443/?insecure=1&sni=${DOMAIN}#${showhys}-Hysteria2\n"
            else
                echo -e "${RED}ไม่พบบัญชี ${showhys}${NC}"
            fi
        fi
        ;;
    19)
        clear
        echo -e "${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ (OpenSSH / SSH-WS / UDP Custom) ===${NC}"
        printf "%-18s %-15s %s\n" "Username" "จำนวนที่เชื่อมต่อ" "PID"
        echo -e "---------------------------------------------------"
        has_online=0
        for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
            pids=$(pgrep -u "$user" sshd 2>/dev/null | tr '\n' ' ')
            if [ -z "$pids" ]; then
                pids=$(ps -ef | grep -E "sshd: ${user}" | grep -v grep | awk '{print $2}' | tr '\n' ' ')
            fi
            if [ -n "$pids" ]; then
                count=$(echo "$pids" | wc -w)
                printf "%-18s %-15s %s\n" "$user" "${count} เครื่อง" "$pids"
                has_online=1
            fi
        done
        [ $has_online -eq 0 ] && echo "ไม่มีผู้ใช้ออนไลน์ผ่าน OpenSSH / SSH-WS / UDP Custom ในขณะนี้"

        echo -e "\n${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ (Dropbear Port 109/143) ===${NC}"
        db_pids=$(ps aux | grep -i dropbear | awk '{print $2}')
        has_db=0
        for pid in $db_pids; do
            db_log=$(grep -i "dropbear\[$pid\]" /var/log/auth.log 2>/dev/null | grep -i "Password auth succeeded" | tail -n 1)
            if [ -n "$db_log" ]; then
                db_user=$(echo "$db_log" | awk '{print $10}' | tr -d "'")
                printf "%-18s %-15s %s\n" "$db_user" "1 เครื่อง" "$pid"
                has_db=1
            fi
        done
        [ $has_db -eq 0 ] && echo "ไม่มีผู้ใช้ออนไลน์ผ่าน Dropbear ในขณะนี้"

        echo -e "\n${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ล่าสุด (Xray Vmess/Vless) ===${NC}"
        if [ -s /var/log/xray/access.log ]; then
            xray_active=$(tail -n 300 /var/log/xray/access.log | grep "email:" | awk -F"email: " '{print $2}' | sort -u)
            if [ -n "$xray_active" ]; then
                for xusr in $xray_active; do
                    last_time=$(tail -n 300 /var/log/xray/access.log | grep "email: $xusr" | tail -n 1 | awk '{print $1, $2}')
                    echo -e "- บัญชี: ${GREEN}${xusr}${NC} (ใช้งานล่าสุด: ${last_time})"
                done
            else
                echo "ไม่มีความเคลื่อนไหวของบัญชี Xray ในช่วงเวลานี้"
            fi
        else
            echo "ยังไม่มีข้อมูลการเชื่อมต่อ Xray"
        fi

        echo -e "\n${YELLOW}=== ประวัติการเตะล็อกอินซ้อน 10 รายการล่าสุด ===${NC}"
        if [ -s /var/log/autokill.log ]; then
            tail -n 10 /var/log/autokill.log
        else
            echo "ยังไม่มีประวัติการทำผิดกฎ"
        fi
        echo -e "${YELLOW}===================================================${NC}"
        ;;
    20)
        read -rp "กำหนดจำนวนเครื่องสูงสุดต่อ 1 บัญชี (เช่น 1 หรือ 2, ใส่ 0 เพื่อปิด): " max_num
        echo "$max_num" > /etc/xray/limit-ssh
        echo -e "${GREEN}บันทึกการจำกัดล็อกอินไว้ที่ ${max_num} เครื่อง เรียบร้อยแล้ว!${NC}"
        ;;
    21)
        read -rp "กรอกโดเมนใหม่ของคุณ (ชี้ IP มายังเซิร์ฟเวอร์นี้แล้ว): " newdom
        if [ -z "$newdom" ]; then
            echo -e "${RED}ยกเลิกการทำรายการ${NC}"
            exit 1
        fi
        echo "$newdom" > /etc/xray/domain
        echo "$newdom" > /root/domain
        systemctl stop nginx
        curl https://get.acme.sh | sh -s email=admin@${newdom}
        /root/.acme.sh/acme.sh --issue -d "${newdom}" --standalone -k ec-256 --force
        /root/.acme.sh/acme.sh --installcert -d "${newdom}" \
            --fullchainpath /etc/xray/xray.crt \
            --keypath /etc/xray/xray.key --ecc
        systemctl start nginx
        systemctl restart xray hysteria
        echo -e "${GREEN}อัปเดตโดเมนและติดตั้ง SSL สำหรับ Xray และ Hysteria 2 เรียบร้อยแล้ว!${NC}"
        ;;
    22)
        running
        ;;
    23)
        systemctl restart rsyslog ssh dropbear nginx php*-fpm xray zivpn hysteria udp-custom ws-epro udpgw@7100 udpgw@7300 fail2ban cron
        echo -e "${GREEN}รีสตาร์ทบริการทั้งหมดเรียบร้อยแล้ว!${NC}"
        ;;
    24)
        echo -e "${CYAN}กำลังสแกนหาและลบบัญชีที่หมดอายุ...${NC}"
        /usr/bin/xp
        echo -e "${GREEN}เคลียร์บัญชีหมดอายุเสร็จสิ้น!${NC}"
        ;;
    25)
        echo -e "${CYAN}กำลังล้างไฟล์ Log และเคลียร์ RAM Cache...${NC}"
        BEFORE_RAM=$(free -m | awk 'NR==2{print $3}')
        /usr/bin/clear-log
        AFTER_RAM=$(free -m | awk 'NR==2{print $3}')
        echo -e "${GREEN}ล้างไฟล์ขยะและเคลียร์ RAM สำเร็จ! (RAM ที่ใช้งานลดลงจาก ${BEFORE_RAM} MB เหลือ ${AFTER_RAM} MB)${NC}"
        ;;
    26)
        echo -e "${YELLOW}=== ตั้งเวลา Auto-Reboot เซิร์ฟเวอร์อัตโนมัติ ===${NC}"
        echo -e " [1] รีบูตทุกวัน เวลา 03:00 น. (แนะนำ)"
        echo -e " [2] รีบูตทุกวัน เวลา 05:00 น."
        echo -e " [3] รีบูตทุกๆ 12 ชั่วโมง (00:00 น. และ 12:00 น.)"
        echo -e " [4] ปิดระบบ Auto-Reboot"
        read -rp "เลือกตั้งเวลา [1-4]: " rb_opt
        sed -i '/\/sbin\/reboot/d' /etc/cron.d/vpn-cron
        case $rb_opt in
            1)
                echo "0 3 * * * root /sbin/reboot" >> /etc/cron.d/vpn-cron
                echo "เปิดใช้งาน (ทุกวัน เวลา 03:00 น.)" > /etc/xray/autoreboot-status
                echo -e "${GREEN}ตั้งค่า Auto-Reboot ทุกวัน เวลา 03:00 น. เรียบร้อยแล้ว!${NC}"
                ;;
            2)
                echo "0 5 * * * root /sbin/reboot" >> /etc/cron.d/vpn-cron
                echo "เปิดใช้งาน (ทุกวัน เวลา 05:00 น.)" > /etc/xray/autoreboot-status
                echo -e "${GREEN}ตั้งค่า Auto-Reboot ทุกวัน เวลา 05:00 น. เรียบร้อยแล้ว!${NC}"
                ;;
            3)
                echo "0 */12 * * * root /sbin/reboot" >> /etc/cron.d/vpn-cron
                echo "เปิดใช้งาน (ทุกๆ 12 ชั่วโมง)" > /etc/xray/autoreboot-status
                echo -e "${GREEN}ตั้งค่า Auto-Reboot ทุกๆ 12 ชั่วโมง เรียบร้อยแล้ว!${NC}"
                ;;
            4)
                echo "ปิดใช้งาน (OFF)" > /etc/xray/autoreboot-status
                echo -e "${YELLOW}ปิดระบบ Auto-Reboot เรียบร้อยแล้ว!${NC}"
                ;;
            *)
                echo -e "${RED}ตัวเลือกไม่ถูกต้อง${NC}"
                ;;
        esac
        systemctl restart cron
        ;;
    27)
        echo -e "${CYAN}กำลังดึงไฟล์อัปเดตล่าสุดจาก GitHub (jannarong01/toeyvpn)...${NC}"
        rm -f /root/update-vpn.sh
        wget -4 -q --no-check-certificate -O /root/update-vpn.sh "https://raw.githubusercontent.com/jannarong01/toeyvpn/main/ssh/ssh-vpn.sh?v=$(date +%s)"
        if [ ! -s /root/update-vpn.sh ]; then
            curl -4 -fsSL "https://raw.githubusercontent.com/jannarong01/toeyvpn/main/ssh/ssh-vpn.sh?v=$(date +%s)" -o /root/update-vpn.sh 2>/dev/null
        fi
        if [ -s /root/update-vpn.sh ]; then
            sed -i 's/\r$//' /root/update-vpn.sh
            chmod +x /root/update-vpn.sh
            /root/update-vpn.sh
            rm -f /root/update-vpn.sh
            echo -e "${GREEN}อัปเดตสคริปต์และเมนูเป็นเวอร์ชันล่าสุดเรียบร้อยแล้ว!${NC}"
            exit 0
        else
            rm -f /root/update-vpn.sh
            echo -e "${RED}ไม่สามารถดาวน์โหลดไฟล์จาก GitHub ได้ กรุณาตรวจสอบลิงก์หรือการเชื่อมต่ออินเทอร์เน็ต${NC}"
            exit 1
        fi
        ;;
    28)
        CUR_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php | cut -d'"' -f2)
        clear
        echo -e "${YELLOW}====== ข้อมูล Web Panel & API (Port 8081) ======${NC}"
        echo -e "เข้าหน้าเว็บจัดการ : ${CYAN}http://${DOMAIN}:8081/${NC}"
        echo -e "URL API เว็บขาย  : ${GREEN}http://${MYIP}:8081/api_ssh.php${NC}"
        echo -e "รหัสผ่าน / Key   : ${GREEN}${CUR_KEY}${NC}"
        echo -e "Path ไฟล์ระบบ   : /home/vps/public_html/"
        echo -e "${YELLOW}=================================================${NC}"
        read -rp "ต้องการเปลี่ยนรหัส Secret Key / รหัสแอดมินใหม่หรือไม่? (พิมพ์รหัสใหม่ หรือกด Enter เพื่อข้าม): " new_key
        if [ -n "$new_key" ]; then
            sed -i "s/\$secret_key = \".*\";/\$secret_key = \"${new_key}\";/g" /home/vps/public_html/api_ssh.php
            cp -f /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php
            echo -e "${GREEN}เปลี่ยนรหัสผ่าน Web Panel และ Secret Key เป็น ${new_key} เรียบร้อยแล้ว!${NC}"
        fi
        ;;
    29)
        clear
        echo -e "${YELLOW}====== ระบบสำรองข้อมูล (Backup & Telegram Bot) ======${NC}"
        echo -e " [1] สำรองข้อมูลทันที (สร้างไฟล์ .zip และลิงก์ย้ายเครื่อง)"
        echo -e " [2] ตั้งค่า Telegram Bot (ส่งไฟล์ Backup เข้าแชทอัตโนมัติทุกเที่ยงคืน)"
        read -rp "เลือกทำรายการ [1-2]: " b_opt
        if [ "$b_opt" = "1" ]; then
            /usr/bin/backup-vpn
        elif [ "$b_opt" = "2" ]; then
            read -rp "กรอก Telegram Bot Token: " t_token
            read -rp "กรอก Telegram Chat ID: " t_chat
            cat <<CONF > /etc/xray/tele-bot.conf
BOT_TOKEN="${t_token}"
CHAT_ID="${t_chat}"
CONF
            sed -i '/\/usr\/bin\/backup-vpn/d' /etc/cron.d/vpn-cron
            echo "5 0 * * * root /usr/bin/backup-vpn silent" >> /etc/cron.d/vpn-cron
            systemctl restart cron
            echo -e "${GREEN}บันทึกการตั้งค่า Telegram Bot และเปิดใช้งาน Auto-Backup ทุกวันเวลา 00:05 น. เรียบร้อยแล้ว!${NC}"
            /usr/bin/backup-vpn
        fi
        ;;
    30)
        /usr/bin/restore-vpn
        ;;
    31)
        clear
        echo -e "${YELLOW}====== ทดสอบความเร็วอินเทอร์เน็ตเซิร์ฟเวอร์ (Speedtest by Ookla) ======${NC}"
        if [ ! -s /usr/local/bin/speedtest ]; then
            echo -e "${CYAN}กำลังติดตั้ง Speedtest CLI...${NC}"
            ARCH=$(uname -m)
            S_ARCH="x86_64"
            if [ "$ARCH" = "aarch64" ]; then S_ARCH="aarch64"; fi
            if [ "$ARCH" = "arm64" ]; then S_ARCH="aarch64"; fi
            wget -q -O /tmp/speedtest.tgz "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${S_ARCH}.tgz"
            tar -xzf /tmp/speedtest.tgz -C /usr/local/bin speedtest 2>/dev/null
            chmod +x /usr/local/bin/speedtest
            rm -f /tmp/speedtest.tgz
        fi
        /usr/local/bin/speedtest --accept-license --accept-gdpr
        echo -e "${YELLOW}=================================================================${NC}"
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RED}เลือกเมนูไม่ถูกต้อง${NC}"
        ;;
esac
EOF
# --- (โค้ดส่วนอื่นๆ ด้านบนตามปกติ) ---

# เพิ่มโค้ดส่วนนี้ก่อนบรรทัดสุดท้ายสุด
# ------------------------------------------------------------------------------
#  FIX: ตั้งค่า Iptables NAT และเปิดพอร์ต UDP Custom อัตโนมัติหลังติดตั้งเสร็จ
# ------------------------------------------------------------------------------
NET_IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

iptables -t nat -F PREROUTING
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 5667 -j ACCEPT
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 8443 -j ACCEPT
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :8443
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 1:5999 -j DNAT --to-destination :7200
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 50001:65535 -j DNAT --to-destination :7200

if ! iptables -C INPUT -p udp --dport 7200 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p udp --dport 7200 -j ACCEPT
fi

netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1
systemctl restart udp-custom

# บรรทัดสุดท้ายเดิมที่มีอยู่แล้ว
Chmod +x /usr/bin/menu

echo "✅ All-in-One VPN Suite + Modern Web Dashboard (Port 8081) Installed Successfully!"
