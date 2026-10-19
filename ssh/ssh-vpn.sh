#!/bin/bash
# ==========================================================================
#  SSH, DROPBEAR, BADVPN, ZIVPN UDP, WEB API (8081), SECURITY & MAINTENANCE
# ==========================================================================
export DEBIAN_FRONTEND=noninteractive

# 1. ลบ Apache2 และ UFW ป้องกันการแย่งพอร์ต 80
systemctl stop apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
apt-get purge -y ufw firewalld exim4 apache2 apache2-utils apache2-bin apache2-data >/dev/null 2>&1
apt-get autoremove -y >/dev/null 2>&1

# 2. ตั้งค่า Timezone เป็นเวลาไทย
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

# 3. ติดตั้งแพ็กเกจหลัก + PHP-FPM + Fail2Ban + Iptables-Persistent
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update -y
apt-get install -y nginx dropbear vnstat curl wget jq python3 net-tools openssl socat cron fail2ban iptables iptables-persistent psmisc dos2unix php-fpm php-cli php-curl

# 4. ตั้งค่าระบบป้องกันการสุ่มรหัสผ่าน (Fail2Ban)
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[dropbear]
enabled = true
port = 109,143
logpath = /var/log/auth.log
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

# 5. ตั้งค่า Iptables บล็อก BitTorrent / P2P
for keyword in "get_peers" "announce_peer" "find_node" "BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "torrent" "announce" "info_hash"; do
    iptables -C FORWARD -m string --string "$keyword" --algo bm -j DROP 2>/dev/null || iptables -A FORWARD -m string --string "$keyword" --algo bm -j DROP
    iptables -C OUTPUT -m string --string "$keyword" --algo bm -j DROP 2>/dev/null || iptables -A OUTPUT -m string --string "$keyword" --algo bm -j DROP
done

# 6. ติดตั้งระบบ Web API (Port 8081) เชื่อมต่อทั้ง SSH และ ZIVPN UDP อัตโนมัติ
mkdir -p /etc/zivpn /home/vps/public_html /root/vnext_api
touch /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt

cat << 'EOF' > /usr/bin/api-vpn
#!/bin/bash
ACTION=$1
USER=$2
PASS=$3
EXP=$4

mkdir -p /etc/zivpn
touch /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt

if [[ "$ACTION" == "add" ]]; then
    /usr/sbin/useradd -e "$EXP" -s /bin/false -M "$USER" 2>/dev/null
    echo "$USER:$PASS" | /usr/sbin/chpasswd 2>/dev/null

    if [[ -n "$PASS" && -f /etc/zivpn/config.json ]]; then
        jq --arg p "$PASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
        sed -i "/^${PASS}:/d" /etc/zivpn/zivpn-exp.txt
        echo "${PASS}:${EXP}" >> /etc/zivpn/zivpn-exp.txt
        sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
        echo "${USER}:${PASS}" >> /etc/zivpn/zivpn-users.txt
        systemctl restart zivpn >/dev/null 2>&1
    fi

elif [[ "$ACTION" == "renew" ]]; then
    /usr/bin/chage -E "$EXP" "$USER" 2>/dev/null

    ZPASS=$(grep "^${USER}:" /etc/zivpn/zivpn-users.txt | cut -d: -f2 | tail -n 1)
    [[ -z "$ZPASS" && -n "$PASS" ]] && ZPASS="$PASS"
    if [[ -n "$ZPASS" && -f /etc/zivpn/zivpn-exp.txt ]]; then
        sed -i "/^${ZPASS}:/d" /etc/zivpn/zivpn-exp.txt
        echo "${ZPASS}:${EXP}" >> /etc/zivpn/zivpn-exp.txt
        if [ -f /etc/zivpn/config.json ]; then
            jq --arg p "$ZPASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
            systemctl restart zivpn >/dev/null 2>&1
        fi
    fi

elif [[ "$ACTION" == "delete" ]]; then
    /usr/bin/killall -u "$USER" 2>/dev/null
    /usr/sbin/userdel -f "$USER" 2>/dev/null

    ZPASS=$(grep "^${USER}:" /etc/zivpn/zivpn-users.txt | cut -d: -f2 | tail -n 1)
    sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
    if [[ -n "$ZPASS" && -f /etc/zivpn/config.json ]]; then
        if ! grep -q ":${ZPASS}$" /etc/zivpn/zivpn-users.txt; then
            jq --arg p "$ZPASS" '.auth.config -= [$p]' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
            sed -i "/^${ZPASS}:/d" /etc/zivpn/zivpn-exp.txt
            systemctl restart zivpn >/dev/null 2>&1
        fi
    fi
fi
EOF
chmod +x /usr/bin/api-vpn

cat <<EOF > /etc/sudoers.d/vpn-api
www-data ALL=(ALL) NOPASSWD: /usr/bin/api-vpn, /usr/sbin/useradd, /usr/sbin/chpasswd, /usr/bin/chage, /usr/sbin/userdel, /usr/bin/killall, /bin/systemctl, /usr/bin/jq, /bin/sed
EOF
chmod 440 /etc/sudoers.d/vpn-api

if [ -s /home/vps/public_html/api_ssh.php ]; then
    SAVED_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php | cut -d'"' -f2)
fi
SAVED_KEY=${SAVED_KEY:-VNEXT_SSH_999}

cat <<EOF > /home/vps/public_html/api_ssh.php
<?php
header('Content-Type: application/json');
\$secret_key = "${SAVED_KEY}"; // กุญแจลับ รหัสผ่านคุยกันระหว่างเว็บ

if (!isset(\$_POST['key']) || \$_POST['key'] !== \$secret_key) {
    die(json_encode(['success' => false, 'msg' => 'Invalid Key']));
}

\$action = \$_POST['action'] ?? '';
\$user = preg_replace('/[^a-zA-Z0-9_]/', '', \$_POST['user'] ?? '');
\$pass = preg_replace('/[^a-zA-Z0-9_@#]/', '', \$_POST['pass'] ?? '');
\$days = intval(\$_POST['days'] ?? 0);

if (empty(\$user)) {
    die(json_encode(['success' => false, 'msg' => 'User empty']));
}

if (\$action === 'add') {
    \$exp = date('Y-m-d', strtotime("+\$days days"));
    exec("sudo /usr/bin/api-vpn add '\$user' '\$pass' '\$exp' 2>&1", \$out, \$ret);
    echo json_encode(['success' => true, 'exp' => \$exp]);
} elseif (\$action === 'renew') {
    \$exp = date('Y-m-d', strtotime("+\$days days"));
    exec("sudo /usr/bin/api-vpn renew '\$user' '\$pass' '\$exp' 2>&1", \$out, \$ret);
    echo json_encode(['success' => true, 'exp' => \$exp]);
} elseif (\$action === 'delete') {
    exec("sudo /usr/bin/api-vpn delete '\$user' '' '' 2>&1", \$out, \$ret);
    echo json_encode(['success' => true]);
} else {
    echo json_encode(['success' => false, 'msg' => 'Unknown action']);
}
?>
EOF

cp /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php
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

iptables -C INPUT -p tcp --dport 8081 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 8081 -j ACCEPT

# 7. ติดตั้ง ZIVPN UDP Tunnel (พอร์ต 5667 และ 6000-19999)
if [ ! -s /usr/local/bin/zivpn-udp ]; then
    echo "กำลังติดตั้ง ZIVPN UDP Server..."
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        wget -q -O /usr/local/bin/zivpn-udp "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
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

NET_IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -C PREROUTING -i "$NET_IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5667 -j ACCEPT
iptables -C INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 6000:19999 -j ACCEPT
netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1

systemctl daemon-reload
systemctl enable zivpn >/dev/null 2>&1
systemctl restart zivpn
systemctl restart nginx

# 8. ติดตั้ง BadVPN UDPGW (พอร์ต 7100, 7200, 7300)
if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    echo "กำลังติดตั้ง BadVPN UDPGW..."
    wget -q -O /usr/local/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
fi

if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    wget -q -O /usr/local/bin/badvpn-udpgw "https://github.com/ambrop72/badvpn/raw/master/badvpn-udpgw64"
fi

if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    apt-get install -y cmake build-essential git libnspr4-dev libnss3-dev pkg-config
    git clone https://github.com/ambrop72/badvpn.git /tmp/badvpn
    mkdir -p /tmp/badvpn/build
    cd /tmp/badvpn/build || exit
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
    make install
    cd /root || exit
    rm -rf /tmp/badvpn
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

systemctl daemon-reload
for port in 7100 7200 7300; do
    systemctl enable udpgw@${port} >/dev/null 2>&1
    systemctl restart udpgw@${port}
done

# 9. ตั้งค่า Dropbear ให้ทำงานที่พอร์ต 109 และ 143
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

grep -qxF '/bin/false' /etc/shells || echo "/bin/false" >> /etc/shells
grep -qxF '/usr/sbin/nologin' /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

cat <<EOF > /etc/issue.net
<p style="text-align:center"><b>=== PRIVATE VPN SERVER (NO TORRENT) ===</b></p>
EOF

systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear

# 10. สร้างสคริปต์ลบบัญชีหมดอายุอัตโนมัติ (xp)
cat << 'EOF' > /usr/bin/xp
#!/bin/bash
export LC_ALL=en_US.UTF-8
today=$(date +%Y-%m-%d)
today_sec=$(date -d "$today" +%s)

for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    exp_date=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
    if [[ "$exp_date" != "never" && -n "$exp_date" ]]; then
        exp_sec=$(date -d "$exp_date" +%s)
        if [[ $today_sec -ge $exp_sec ]]; then
            killall -u "$user" 2>/dev/null
            userdel -f "$user"
            sed -i "/^$user:/d" /etc/zivpn/zivpn-users.txt 2>/dev/null
            echo "Deleted Expired SSH Account: $user"
        fi
    fi
done

if [ -f /etc/xray/xray-exp.txt ]; then
    while IFS=':' read -r x_user x_exp; do
        exp_sec=$(date -d "$x_exp" +%s)
        if [[ $today_sec -ge $exp_sec ]]; then
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
        exp_sec=$(date -d "$z_exp" +%s)
        if [[ $today_sec -ge $exp_sec ]]; then
            jq --arg p "$z_pass" '.auth.config -= [$p]' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
            sed -i "/^$z_pass:/d" /etc/zivpn/zivpn-exp.txt
            sed -i "/:$z_pass$/d" /etc/zivpn/zivpn-users.txt 2>/dev/null
            systemctl restart zivpn
            echo "Deleted Expired ZIVPN Password: $z_pass"
        fi
    done < /etc/zivpn/zivpn-exp.txt
fi
EOF
chmod +x /usr/bin/xp

# 11. สร้างสคริปต์เตะคนล็อกอินซ้อนเกินกำหนด (tendang) และสคริปต์ล้างขยะ (clear-log)
mkdir -p /etc/xray
[ ! -f /etc/xray/limit-ssh ] && echo "2" > /etc/xray/limit-ssh
[ ! -f /etc/xray/autoreboot-status ] && echo "เปิดใช้งาน (ทุกวัน เวลา 03:00 น.)" > /etc/xray/autoreboot-status

cat << 'EOF' > /usr/bin/tendang
#!/bin/bash
MAX=$(cat /etc/xray/limit-ssh 2>/dev/null || echo 2)
if [[ "$MAX" -le 0 ]]; then
    exit 0
fi

for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    pids=$(pgrep -u "$user" sshd)
    if [[ -n "$pids" ]]; then
        count=$(echo "$pids" | wc -l)
    else
        count=0
    fi

    if [[ $count -gt $MAX ]]; then
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

# 12. สร้างคำสั่งเช็กสถานะ 'running'
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
if [[ $TorrentRules -gt 0 ]]; then
    TORRENT_STAT="${GREEN}[ACTIVE]${NC}"
else
    TORRENT_STAT="${RED}[INACTIVE]${NC}"
fi

if netstat -tunlp | grep -q ":8081 "; then
    API_STAT="${GREEN}[ON]${NC}"
else
    API_STAT="${RED}[OFF]${NC}"
fi

REBOOT_STAT=$(cat /etc/xray/autoreboot-status 2>/dev/null || echo "เปิดใช้งาน (03:00 น.)")

clear
echo -e "${YELLOW}=========================================${NC}"
echo -e "           ${CYAN}STATUS RUNNING SERVICE${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo -e " OpenSSH Service          : $(check_status ssh)"
echo -e " Dropbear Service         : $(check_status dropbear)"
echo -e " Nginx Proxy (80 / 443)   : $(check_status nginx)"
echo -e " Web API Panel (8081)     : ${API_STAT}"
echo -e " Xray Core (Vmess/Vless)  : $(check_status xray)"
echo -e " ZIVPN UDP (5667/6000+)   : $(check_status zivpn)"
echo -e " SSH WebSocket (10015)    : $(check_status ws-epro)"
echo -e " BadVPN UDPGW (7300)      : $(check_status udpgw@7300)"
echo -e " Fail2Ban (Anti-Brute)    : $(check_status fail2ban)"
echo -e " Anti-Torrent Firewall    : ${TORRENT_STAT}"
echo -e " Cron (Auto-Kill / Exp)   : $(check_status cron)"
echo -e " Auto-Reboot Schedule     : ${GREEN}${REBOOT_STAT}${NC}"
echo -e "${YELLOW}=========================================${NC}"
EOF
chmod +x /usr/bin/running

# 13. สร้างคำสั่งหน้าหลัก 'menu'
cat << 'EOF' > /usr/bin/menu
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

MYIP=$(curl -sS ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "$MYIP")
MAX_LOGIN=$(cat /etc/xray/limit-ssh 2>/dev/null || echo "2")
REBOOT_STAT=$(cat /etc/xray/autoreboot-status 2>/dev/null || echo "เปิดใช้งาน (ทุกวัน เวลา 03:00 น.)")
RAM_USAGE=$(free -m | awk 'NR==2{printf "%s/%s MB (%.1f%%)", $3,$2,$3*100/$2 }')
mkdir -p /etc/xray /etc/zivpn
touch /etc/xray/xray-exp.txt /etc/xray/xray-lock.txt /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt

clear
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
echo -e "               ${CYAN}PRIVATE VPN MENU${NC}"
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
echo -e " IP Address  : ${GREEN}${MYIP}${NC}"
echo -e " Domain      : ${GREEN}${DOMAIN}${NC}"
echo -e " RAM Usage   : ${GREEN}${RAM_USAGE}${NC}"
echo -e " Multi-Login : ${GREEN}สูงสุด ${MAX_LOGIN} เครื่อง/บัญชี${NC}"
echo -e " Auto-Reboot : ${GREEN}${REBOOT_STAT}${NC}"
echo -e "${YELLOW}☉——————————— [ จัดการบัญชี SSH / WS ] ———————————☉${NC}"
echo -e " [1]  สร้างบัญชี SSH / WebSocket (+ZIVPN UDP)"
echo -e " [2]  ต่ออายุบัญชี SSH (Renew)"
echo -e " [3]  ระงับ / ปลดล็อกบัญชี SSH (Lock/Unlock)"
echo -e " [4]  ลบบัญชี SSH / WebSocket"
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
echo -e "${YELLOW}☉——————————— [ ระบบความปลอดภัยและบำรุงรักษา ] —————☉${NC}"
echo -e " [15] เช็กผู้ใช้ออนไลน์ (SSH / Dropbear / Xray)"
echo -e " [16] ตั้งค่าจำกัดจำนวนเครื่องล็อกอิน (Auto-Kill)"
echo -e " [17] เปลี่ยนโดเมนและขอ SSL ใหม่ (Port 443)"
echo -e " [18] เช็กสถานะบริการและไฟร์วอลล์ (running)"
echo -e " [19] รีสตาร์ทบริการทั้งหมด"
echo -e " [20] ลบบัญชีที่หมดอายุทันที (เคลียร์ขยะบัญชี)"
echo -e " [21] ล้างไฟล์ขยะ Log และเคลียร์ RAM ทันที"
echo -e " [22] ตั้งเวลา Auto-Reboot เซิร์ฟเวอร์อัตโนมัติ"
echo -e " [23] อัปเดตสคริปต์และเมนูเวอร์ชันล่าสุดจาก GitHub"
echo -e " [24] ดูข้อมูลเชื่อมต่อ API สำหรับเว็บขาย VPN (Port 8081)"
echo -e " [0]  ออกจากเมนู"
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
read -rp "เลือกเมนู [0-24]: " opt

case $opt in
    1)
        read -rp "ชื่อผู้ใช้ (Username): " user
        if id "$user" &>/dev/null; then
            echo -e "${RED}ชื่อผู้ใช้นี้มีอยู่ในระบบแล้ว!${NC}"
            exit 1
        fi
        read -rp "รหัสผ่าน (Password): " pass
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")
        /usr/bin/api-vpn add "$user" "$pass" "$exp"
        clear
        echo -e "${YELLOW}=== ข้อมูลบัญชี SSH, WebSocket & ZIVPN UDP ===${NC}"
        echo -e "Host/IP      : $DOMAIN ($MYIP)"
        echo -e "Username     : $user"
        echo -e "Password     : $pass (ใช้เป็น UDP Password ใน ZIVPN ได้ทันที)"
        echo -e "OpenSSH      : 22"
        echo -e "Dropbear     : 109, 143"
        echo -e "WS Port      : 80"
        echo -e "WS SSL/TLS   : 443"
        echo -e "ZIVPN UDP    : 5667, 6000-19999"
        echo -e "UDPGW Port   : 7100, 7200, 7300"
        echo -e "จำกัดล็อกอิน   : ไม่เกิน ${MAX_LOGIN} เครื่อง"
        echo -e "Payload      : GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
        echo -e "หมดอายุวันที่   : ${exp}"
        echo -e "${YELLOW}============================================${NC}"
        ;;
    2)
        read -rp "พิมพ์ชื่อบัญชี SSH ที่ต้องการต่ออายุ: " user
        if ! id "$user" &>/dev/null; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        exp_old=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
        today_sec=$(date +%s)
        exp_sec=$(date -d "$exp_old" +%s 2>/dev/null || echo "$today_sec")
        if [[ $exp_sec -lt $today_sec ]]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$exp_old" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        /usr/bin/api-vpn renew "$user" "" "$new_exp"
        echo -e "${GREEN}ต่ออายุบัญชี ${user} (รวมถึงรหัส ZIVPN UDP) สำเร็จ! วันหมดอายุใหม่คือ: ${new_exp}${NC}"
        ;;
    3)
        echo -e " [1] ระงับบัญชีชั่วคราว (Lock)"
        echo -e " [2] ปลดล็อกบัญชี (Unlock)"
        read -rp "เลือกทำรายการ [1-2]: " lopt
        read -rp "พิมพ์ชื่อบัญชี SSH: " user
        if ! id "$user" &>/dev/null; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        if [[ "$lopt" == "1" ]]; then
            passwd -l "$user" >/dev/null 2>&1
            killall -u "$user" 2>/dev/null
            echo -e "${YELLOW}ระงับการใช้งานและตัดการเชื่อมต่อบัญชี ${user} เรียบร้อยแล้ว!${NC}"
        elif [[ "$lopt" == "2" ]]; then
            passwd -u "$user" >/dev/null 2>&1
            echo -e "${GREEN}ปลดล็อกบัญชี ${user} ให้กลับมาใช้งานได้ตามปกติแล้ว!${NC}"
        fi
        ;;
    4)
        read -rp "พิมพ์ชื่อบัญชี SSH ที่ต้องการลบ: " delssh
        if id "$delssh" &>/dev/null; then
            /usr/bin/api-vpn delete "$delssh" "" ""
            echo -e "${GREEN}ลบบัญชี SSH และรหัส ZIVPN ของ ${delssh} เรียบร้อยแล้ว!${NC}"
        else
            echo -e "${RED}ไม่พบชื่อบัญชี ${delssh} ในระบบ!${NC}"
        fi
        ;;
    5)
        clear
        echo -e "${YELLOW}========= รายชื่อบัญชี SSH ทั้งหมด =========${NC}"
        printf "%-18s %-20s %s\n" "Username" "Expire Date" "Status"
        echo -e "---------------------------------------------------"
        for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
            exp=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
            passwd_stat=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
            if [[ "$passwd_stat" == "L" ]]; then
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
        if [[ -z "$user" ]]; then
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
        echo -e "${CYAN}[ลิงก์ Vmess SSL/TLS (Port 443)]${NC}"
        echo -e "vmess://${VMESS_TLS}\n"
        echo -e "${CYAN}[ลิงก์ Vmess HTTP (Port 80)]${NC}"
        echo -e "vmess://${VMESS_NTLS}\n"
        echo -e "${CYAN}[ลิงก์ Vless SSL/TLS (Port 443)]${NC}"
        echo -e "${VLESS_TLS}\n"
        echo -e "${CYAN}[ลิงก์ Vless HTTP (Port 80)]${NC}"
        echo -e "${VLESS_NTLS}\n"
        echo -e "${YELLOW}===========================================${NC}"
        ;;
    7)
        read -rp "พิมพ์ชื่อบัญชี Xray ที่ต้องการต่ออายุ: " user
        old_exp=$(grep "^${user}:" /etc/xray/xray-exp.txt | cut -d: -f2)
        if [[ -z "$old_exp" ]]; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null || echo "$today_sec")
        if [[ $exp_sec -lt $today_sec ]]; then
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
        if [[ "$xlopt" == "1" ]]; then
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
        elif [[ "$xlopt" == "2" ]]; then
            uuid=$(grep "^${user}:" /etc/xray/xray-lock.txt | cut -d: -f2)
            if [[ -z "$uuid" ]]; then
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
        if [[ "$deluser" == "default" ]]; then
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
        if [[ -n "$showuser" ]]; then
            UUID=$(jq -r --arg usr "$showuser" '.inbounds[0].settings.clients[] | select(.email == $usr) | .id' /etc/xray/config.json)
            if [[ -z "$UUID" ]]; then
                UUID=$(grep "^${showuser}:" /etc/xray/xray-lock.txt | cut -d: -f2)
            fi
            if [[ -n "$UUID" ]]; then
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
        if [[ -z "$zpass" ]]; then
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
        if [[ -z "$old_exp" ]]; then
            echo -e "${RED}ไม่พบรหัสผ่าน ${zpass} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null || echo "$today_sec")
        if [[ $exp_sec -lt $today_sec ]]; then
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
                [[ -z "$owner" ]] && owner="-"
                printf "%-20s %-18s %-15s %b\n" "$zp" "$owner" "$zexp" "${GREEN}Active${NC}"
            done < /etc/zivpn/zivpn-exp.txt
        else
            echo "ยังไม่มีการสร้างรหัสผ่าน ZIVPN ในระบบ"
        fi
        echo -e "${YELLOW}============================================================${NC}"
        ;;
    15)
        clear
        echo -e "${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ (OpenSSH & SSH-WS) ===${NC}"
        printf "%-18s %-15s %s\n" "Username" "จำนวนที่เชื่อมต่อ" "PID"
        echo -e "---------------------------------------------------"
        has_online=0
        for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
            pids=$(pgrep -u "$user" sshd 2>/dev/null | tr '\n' ' ')
            if [[ -z "$pids" ]]; then
                pids=$(ps -ef | grep -E "sshd: ${user}" | grep -v grep | awk '{print $2}' | tr '\n' ' ')
            fi
            if [[ -n "$pids" ]]; then
                count=$(echo "$pids" | wc -w)
                printf "%-18s %-15s %s\n" "$user" "${count} เครื่อง" "$pids"
                has_online=1
            fi
        done
        [[ $has_online -eq 0 ]] && echo "ไม่มีผู้ใช้ออนไลน์ผ่าน OpenSSH / SSH-WS ในขณะนี้"

        echo -e "\n${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ (Dropbear Port 109/143) ===${NC}"
        db_pids=$(ps aux | grep -i dropbear | awk '{print $2}')
        has_db=0
        for pid in $db_pids; do
            db_log=$(grep -i "dropbear\[$pid\]" /var/log/auth.log 2>/dev/null | grep -i "Password auth succeeded" | tail -n 1)
            if [[ -n "$db_log" ]]; then
                db_user=$(echo "$db_log" | awk '{print $10}' | tr -d "'")
                printf "%-18s %-15s %s\n" "$db_user" "1 เครื่อง" "$pid"
                has_db=1
            fi
        done
        [[ $has_db -eq 0 ]] && echo "ไม่มีผู้ใช้ออนไลน์ผ่าน Dropbear ในขณะนี้"

        echo -e "\n${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ล่าสุด (Xray Vmess/Vless) ===${NC}"
        if [ -s /var/log/xray/access.log ]; then
            xray_active=$(tail -n 300 /var/log/xray/access.log | grep "email:" | awk -F"email: " '{print $2}' | sort -u)
            if [[ -n "$xray_active" ]]; then
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
        tail -n 10 /var/log/autokill.log 2>/dev/null || echo "ยังไม่มีประวัติการทำผิดกฎ"
        echo -e "${YELLOW}===================================================${NC}"
        ;;
    16)
        read -rp "กำหนดจำนวนเครื่องสูงสุดต่อ 1 บัญชี (เช่น 2, ใส่ 0 เพื่อปิด): " max_num
        echo "$max_num" > /etc/xray/limit-ssh
        echo -e "${GREEN}บันทึกการจำกัดล็อกอินไว้ที่ ${max_num} เครื่อง เรียบร้อยแล้ว!${NC}"
        ;;
    17)
        read -rp "กรอกโดเมนใหม่ของคุณ (ชี้ IP มายังเซิร์ฟเวอร์นี้แล้ว): " newdom
        if [[ -z "$newdom" ]]; then
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
        systemctl restart xray
        echo -e "${GREEN}อัปเดตโดเมนและติดตั้ง SSL พอร์ต 443 เรียบร้อยแล้ว!${NC}"
        ;;
    18)
        running
        ;;
    19)
        systemctl restart ssh dropbear nginx php*-fpm xray zivpn ws-epro udpgw@7100 udpgw@7200 udpgw@7300 fail2ban cron
        echo -e "${GREEN}รีสตาร์ทบริการทั้งหมดเรียบร้อยแล้ว!${NC}"
        ;;
    20)
        echo -e "${CYAN}กำลังสแกนหาและลบบัญชีที่หมดอายุ...${NC}"
        /usr/bin/xp
        echo -e "${GREEN}เคลียร์บัญชีหมดอายุเสร็จสิ้น!${NC}"
        ;;
    21)
        echo -e "${CYAN}กำลังล้างไฟล์ Log และเคลียร์ RAM Cache...${NC}"
        BEFORE_RAM=$(free -m | awk 'NR==2{print $3}')
        /usr/bin/clear-log
        AFTER_RAM=$(free -m | awk 'NR==2{print $3}')
        echo -e "${GREEN}ล้างไฟล์ขยะและเคลียร์ RAM สำเร็จ! (RAM ที่ใช้งานลดลงจาก ${BEFORE_RAM} MB เหลือ ${AFTER_RAM} MB)${NC}"
        ;;
    22)
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
    23)
        echo -e "${CYAN}กำลังดึงไฟล์อัปเดตล่าสุดจาก GitHub (jannarong01/toeyvpn)...${NC}"
        wget -q -O /root/update-vpn.sh "https://raw.githubusercontent.com/jannarong01/toeyvpn/main/ssh/ssh-vpn.sh"
        if [ -s /root/update-vpn.sh ]; then
            sed -i 's/\r$//' /root/update-vpn.sh
            chmod +x /root/update-vpn.sh
            /root/update-vpn.sh
            rm -f /root/update-vpn.sh
            echo -e "${GREEN}อัปเดตสคริปต์และเมนูเป็นเวอร์ชันล่าสุดเรียบร้อยแล้ว!${NC}"
        else
            rm -f /root/update-vpn.sh
            echo -e "${RED}ไม่สามารถดาวน์โหลดไฟล์จาก GitHub ได้ กรุณาตรวจสอบลิงก์หรือการเชื่อมต่ออินเทอร์เน็ต${NC}"
        fi
        ;;
    24)
        CUR_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php | cut -d'"' -f2)
        clear
        echo -e "${YELLOW}====== ข้อมูลสำหรับตั้งค่าในหน้าเว็บ Admin (toeyvpn.com) ======${NC}"
        echo -e "URL API        : ${GREEN}http://${MYIP}:8081/api_ssh.php${NC}"
        echo -e "Secret Key     : ${GREEN}${CUR_KEY}${NC}"
        echo -e "Path ไฟล์ระบบ   : /home/vps/public_html/api_ssh.php"
        echo -e "การทำงานอัตโนมัติ : สร้าง/ต่ออายุ/ลบ ทั้ง SSH และ ZIVPN UDP พร้อมกัน"
        echo -e "${YELLOW}===========================================================${NC}"
        read -rp "ต้องการเปลี่ยนรหัส Secret Key ใหม่หรือไม่? (พิมพ์รหัสใหม่ หรือกด Enter เพื่อใช้ค่าเดิม): " new_key
        if [[ -n "$new_key" ]]; then
            sed -i "s/\$secret_key = \".*\";/\$secret_key = \"${new_key}\";/g" /home/vps/public_html/api_ssh.php
            cp /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php
            echo -e "${GREEN}เปลี่ยน Secret Key เป็น ${new_key} เรียบร้อยแล้ว!${NC}"
        fi
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RED}เลือกเมนูไม่ถูกต้อง${NC}"
        ;;
esac
EOF
chmod +x /usr/bin/menu

echo "SSH, VPN, ZIVPN UDP, Web API (8081), Security & Maintenance Suite Installed Successfully!"
