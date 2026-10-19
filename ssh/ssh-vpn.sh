#!/bin/bash
# =================================================
#  SSH, DROPBEAR, BADVPN, MENU & SECURITY SUITE
# =================================================
export DEBIAN_FRONTEND=noninteractive

# 1. ลบ Apache2 และ UFW ป้องกันการแย่งพอร์ต 80
systemctl stop apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
apt-get purge -y ufw firewalld exim4 apache2 apache2-utils apache2-bin apache2-data >/dev/null 2>&1
apt-get autoremove -y >/dev/null 2>&1

# 2. ตั้งค่า Timezone เป็นเวลาไทย
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

# 3. ติดตั้งแพ็กเกจหลัก + Fail2Ban + Iptables-Persistent
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update -y
apt-get install -y nginx dropbear vnstat curl wget jq python3 net-tools openssl socat cron fail2ban iptables iptables-persistent psmisc

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

# 5. ตั้งค่า Iptables บล็อก BitTorrent / P2P (Anti-Torrent)
iptables -F FORWARD
for keyword in "get_peers" "announce_peer" "find_node" "BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "torrent" "announce" "info_hash"; do
    iptables -A FORWARD -m string --string "$keyword" --algo bm -j DROP
    iptables -A OUTPUT -m string --string "$keyword" --algo bm -j DROP
done
netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1

# 6. ติดตั้ง BadVPN UDPGW (พอร์ต 7100, 7200, 7300)
echo "กำลังติดตั้ง BadVPN UDPGW..."
wget -q -O /usr/local/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"

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

# 7. ตั้งค่า Dropbear ให้ทำงานที่พอร์ต 109 และ 143
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

# 8. สร้างสคริปต์ลบบัญชีหมดอายุอัตโนมัติ (xp)
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
            systemctl restart xray
            echo "Deleted Expired Xray Account: $x_user"
        fi
    done < /etc/xray/xray-exp.txt
fi
EOF
chmod +x /usr/bin/xp

# 9. สร้างสคริปต์เตะคนล็อกอินซ้อนเกินกำหนด (tendang / Auto-Kill Multi-Login)
mkdir -p /etc/xray
echo "2" > /etc/xray/limit-ssh

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

cat <<EOF > /etc/cron.d/vpn-cron
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
* * * * * root /usr/bin/tendang
EOF
systemctl restart cron

# 10. สร้างคำสั่งเช็กสถานะ 'running'
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

clear
echo -e "${YELLOW}=========================================${NC}"
echo -e "           ${CYAN}STATUS RUNNING SERVICE${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo -e " OpenSSH Service          : $(check_status ssh)"
echo -e " Dropbear Service         : $(check_status dropbear)"
echo -e " Nginx Proxy (80 / 443)   : $(check_status nginx)"
echo -e " Xray Core (Vmess/Vless)  : $(check_status xray)"
echo -e " SSH WebSocket (10015)    : $(check_status ws-epro)"
echo -e " BadVPN UDPGW (7300)      : $(check_status udpgw@7300)"
echo -e " Fail2Ban (Anti-Brute)    : $(check_status fail2ban)"
echo -e " Anti-Torrent Firewall    : ${TORRENT_STAT}"
echo -e " Cron (Auto-Kill / Exp)   : $(check_status cron)"
echo -e "${YELLOW}=========================================${NC}"
EOF
chmod +x /usr/bin/running

# 11. สร้างคำสั่งหน้าหลัก 'menu'
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
touch /etc/xray/xray-exp.txt

clear
echo -e "${YELLOW}☉———————————————————————————————————————☉${NC}"
echo -e "            ${CYAN}PRIVATE VPN MENU${NC}"
echo -e "${YELLOW}☉———————————————————————————————————————☉${NC}"
echo -e " IP Address  : ${GREEN}${MYIP}${NC}"
echo -e " Domain      : ${GREEN}${DOMAIN}${NC}"
echo -e " Multi-Login : ${GREEN}สูงสุด ${MAX_LOGIN} เครื่อง/บัญชี${NC}"
echo -e "${YELLOW}☉———————————————————————————————————————☉${NC}"
echo -e " [1]  สร้างบัญชี SSH / WebSocket"
echo -e " [2]  ดูรายชื่อบัญชี SSH ทั้งหมด (พร้อมวันหมดอายุ)"
echo -e " [3]  ลบบัญชี SSH / WebSocket"
echo -e " [4]  สร้างบัญชี Xray (Vmess & Vless)"
echo -e " [5]  ดูรายชื่อบัญชี Xray ทั้งหมด"
echo -e " [6]  ลบบัญชี Xray (Vmess & Vless)"
echo -e " [7]  เช็กผู้ใช้ออนไลน์ขณะนี้ (SSH / WS / Dropbear)"
echo -e " [8]  ตั้งค่าจำกัดจำนวนเครื่องล็อกอิน (Auto-Kill)"
echo -e " [9]  เปลี่ยนโดเมนและขอ SSL ใหม่ (Port 443)"
echo -e " [10] เช็กสถานะบริการและไฟร์วอลล์ (running)"
echo -e " [11] รีสตาร์ทบริการทั้งหมด"
echo -e " [12] ลบบัญชีที่หมดอายุทันที (เคลียร์ขยะ)"
echo -e " [0]  ออกจากเมนู"
echo -e "${YELLOW}☉———————————————————————————————————————☉${NC}"
read -rp "เลือกเมนู [0-12]: " opt

case $opt in
    1)
        read -rp "ชื่อผู้ใช้ (Username): " user
        if id "$user" &>/dev/null; then
            echo -e "${RED}ชื่อผู้ใช้นี้มีอยู่ในระบบแล้ว!${NC}"
            exit 1
        fi
        read -rp "รหัสผ่าน (Password): " pass
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        useradd -e $(date -d "$days days" +"%Y-%m-%d") -s /bin/false -M "$user"
        echo "$user:$pass" | chpasswd
        clear
        echo -e "${YELLOW}=== ข้อมูลบัญชี SSH & WebSocket ===${NC}"
        echo -e "Host/IP      : $DOMAIN ($MYIP)"
        echo -e "Username     : $user"
        echo -e "Password     : $pass"
        echo -e "OpenSSH      : 22"
        echo -e "Dropbear     : 109, 143"
        echo -e "WS Port      : 80"
        echo -e "WS SSL/TLS   : 443"
        echo -e "UDPGW Port   : 7100, 7200, 7300"
        echo -e "จำกัดล็อกอิน   : ไม่เกิน ${MAX_LOGIN} เครื่อง"
        echo -e "Payload      : GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
        echo -e "หมดอายุวันที่   : $(date -d "$days days" +"%Y-%m-%d")"
        echo -e "${YELLOW}=================================${NC}"
        ;;
    2)
        clear
        echo -e "${YELLOW}========= รายชื่อบัญชี SSH ทั้งหมด =========${NC}"
        printf "%-18s %-20s %s\n" "Username" "Expire Date" "Status"
        echo -e "---------------------------------------------------"
        for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
            exp=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
            passwd_stat=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
            if [[ "$passwd_stat" == "L" ]]; then
                stat="Locked"
            else
                stat="Active"
            fi
            printf "%-18s %-20s %s\n" "$user" "$exp" "$stat"
        done
        echo -e "${YELLOW}=========================================${NC}"
        ;;
    3)
        read -rp "พิมพ์ชื่อบัญชี SSH ที่ต้องการลบ: " delssh
        if id "$delssh" &>/dev/null; then
            killall -u "$delssh" 2>/dev/null
            userdel -f "$delssh" 2>/dev/null
            echo -e "${GREEN}ลบบัญชี SSH: ${delssh} เรียบร้อยแล้ว!${NC}"
        else
            echo -e "${RED}ไม่พบชื่อบัญชี ${delssh} ในระบบ!${NC}"
        fi
        ;;
    4)
        read -rp "ตั้งชื่อบัญชี Xray (ห้ามซ้ำ): " user
        if [[ -z "$user" ]]; then
            echo -e "${RED}ชื่อบัญชีห้ามเว้นว่าง!${NC}"
            exit 1
        fi
        EXISTS=$(jq -r '.inbounds[0].settings.clients[].email' /etc/xray/config.json | grep -w "$user")
        if [[ -n "$EXISTS" ]]; then
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
    5)
        clear
        echo -e "${YELLOW}========= รายชื่อบัญชี Xray ทั้งหมด =========${NC}"
        printf "%-15s %-15s %s\n" "Username" "Expire Date" "UUID"
        echo -e "---------------------------------------------------"
        if [ -s /etc/xray/xray-exp.txt ]; then
            while IFS=':' read -r u exp; do
                uuid=$(jq -r --arg usr "$u" '.inbounds[0].settings.clients[] | select(.email == $usr) | .id' /etc/xray/config.json)
                printf "%-15s %-15s %s\n" "$u" "$exp" "$uuid"
            done < /etc/xray/xray-exp.txt
        else
            echo "ยังไม่มีการสร้างบัญชี Xray ในระบบ"
        fi
        echo -e "${YELLOW}===========================================${NC}"
        ;;
    6)
        echo -e "${CYAN}รายชื่อบัญชี Xray ปัจจุบัน:${NC}"
        jq -r '.inbounds[0].settings.clients[] | "- \(.email) (UUID: \(.id))"' /etc/xray/config.json
        echo -e "${YELLOW}-------------------------------------------${NC}"
        read -rp "พิมพ์ชื่อบัญชีที่ต้องการลบ: " deluser
        if [[ "$deluser" == "default" ]]; then
            echo -e "${RED}ไม่สามารถลบบัญชีเริ่มต้น (default) ได้!${NC}"
            exit 1
        fi
        jq --arg u "$deluser" \
           '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
            (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
           /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
        sed -i "/^$deluser:/d" /etc/xray/xray-exp.txt
        systemctl restart xray
        echo -e "${GREEN}ลบบัญชี ${deluser} เรียบร้อยแล้ว!${NC}"
        ;;
    7)
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
        if [[ $has_online -eq 0 ]]; then
            echo "ไม่มีผู้ใช้ออนไลน์ผ่าน OpenSSH / SSH-WS ในขณะนี้"
        fi

        echo -e ""
        echo -e "${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ (Dropbear Port 109/143) ===${NC}"
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
        if [[ $has_db -eq 0 ]]; then
            echo "ไม่มีผู้ใช้ออนไลน์ผ่าน Dropbear ในขณะนี้"
        fi

        echo -e ""
        echo -e "${YELLOW}=== ประวัติการเตะล็อกอินซ้อน 10 รายการล่าสุด ===${NC}"
        tail -n 10 /var/log/autokill.log 2>/dev/null || echo "ยังไม่มีประวัติการทำผิดกฎ"
        echo -e "${YELLOW}===================================================${NC}"
        ;;
    8)
        read -rp "กำหนดจำนวนเครื่องสูงสุดต่อ 1 บัญชี (เช่น 2, ใส่ 0 เพื่อปิด): " max_num
        echo "$max_num" > /etc/xray/limit-ssh
        echo -e "${GREEN}บันทึกการจำกัดล็อกอินไว้ที่ ${max_num} เครื่อง เรียบร้อยแล้ว!${NC}"
        ;;
    9)
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
    10)
        running
        ;;
    11)
        systemctl restart ssh dropbear nginx xray ws-epro udpgw@7100 udpgw@7200 udpgw@7300 fail2ban cron
        echo -e "${GREEN}รีสตาร์ทบริการทั้งหมดเรียบร้อยแล้ว!${NC}"
        ;;
    12)
        echo -e "${CYAN}กำลังสแกนหาและลบบัญชีที่หมดอายุ...${NC}"
        /usr/bin/xp
        echo -e "${GREEN}เคลียร์บัญชีหมดอายุเสร็จสิ้น!${NC}"
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

echo "SSH, VPN, Menu & Security Suite Installed Successfully!"
