#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# 1. ลบ Apache2 และ UFW ป้องกันการแย่งพอร์ต 80
systemctl stop apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
apt-get purge -y ufw firewalld exim4 apache2 apache2-utils apache2-bin apache2-data >/dev/null 2>&1
apt-get autoremove -y >/dev/null 2>&1

# 2. ตั้งค่า Timezone เป็นเวลาไทย
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

# 3. ติดตั้งแพ็กเกจหลักและเครื่องมือสร้าง BadVPN
apt-get update -y
apt-get install -y nginx dropbear vnstat curl jq python3 cmake build-essential git

# 4. คอมไพล์และติดตั้ง BadVPN UDPGW (พอร์ต 7100, 7200, 7300)
git clone https://github.com/ambrop72/badvpn.git /tmp/badvpn
mkdir -p /tmp/badvpn/build
cd /tmp/badvpn/build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make install
cd /root
rm -rf /tmp/badvpn

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
    systemctl enable udpgw@${port}
    systemctl restart udpgw@${port}
done

# 5. ตั้งค่า Dropbear ให้ทำงานที่พอร์ต 109 และ 143
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
<p style="text-align:center"><b>=== PRIVATE VPN SERVER ===</b></p>
EOF

systemctl enable dropbear
systemctl restart dropbear

# 6. สร้างคำสั่งเช็กสถานะ 'running'
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

clear
echo -e "${YELLOW}=========================================${NC}"
echo -e "           ${CYAN}STATUS RUNNING SERVICE${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo -e " OpenSSH Service        : $(check_status ssh)"
echo -e " Dropbear Service       : $(check_status dropbear)"
echo -e " Nginx Reverse Proxy    : $(check_status nginx)"
echo -e " Xray Core (Vmess/Vless): $(check_status xray)"
echo -e " SSH WebSocket (10015)  : $(check_status ws-epro)"
echo -e " BadVPN UDPGW (7300)    : $(check_status udpgw@7300)"
echo -e " Vnstat Service         : $(check_status vnstat)"
echo -e "${YELLOW}=========================================${NC}"
EOF
chmod +x /usr/bin/running

# 7. สร้างคำสั่งหน้าหลัก 'menu'
cat << 'EOF' > /usr/bin/menu
#!/bin/bash
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

MYIP=$(curl -sS ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "$MYIP")

clear
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
echo -e "         ${CYAN}PRIVATE VPN MENU${NC}"
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
echo -e " IP Address : ${GREEN}${MYIP}${NC}"
echo -e " Domain     : ${GREEN}${DOMAIN}${NC}"
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
echo -e " [1] สร้างบัญชี SSH / WebSocket"
echo -e " [2] ดูรายละเอียด Xray (Vmess / Vless)"
echo -e " [3] เช็กสถานะบริการทั้งหมด (running)"
echo -e " [4] รีสตาร์ทบริการทั้งหมด"
echo -e " [0] ออกจากเมนู"
echo -e "${YELLOW}☉———————————————————————————————☉${NC}"
read -rp "เลือกเมนู [0-4]: " opt

case $opt in
    1)
        read -rp "ชื่อผู้ใช้ (Username): " user
        read -rp "รหัสผ่าน (Password): " pass
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        useradd -e $(date -d "$days days" +"%Y-%m-%d") -s /bin/false -M "$user"
        echo "$user:$pass" | chpasswd
        clear
        echo -e "=== ข้อมูลบัญชี SSH & WebSocket ==="
        echo -e "Host/IP      : $DOMAIN ($MYIP)"
        echo -e "Username     : $user"
        echo -e "Password     : $pass"
        echo -e "OpenSSH      : 22"
        echo -e "Dropbear     : 109, 143"
        echo -e "WS Port      : 80"
        echo -e "UDPGW Port   : 7100, 7200, 7300"
        echo -e "Payload      : GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
        echo -e "หมดอายุวันที่   : $(date -d "$days days" +"%Y-%m-%d")"
        ;;
    2)
        clear
        cat /etc/xray/client-info.txt 2>/dev/null || echo "ยังไม่มีข้อมูล Xray"
        ;;
    3)
        running
        ;;
    4)
        systemctl restart ssh dropbear nginx xray ws-epro udpgw@7100 udpgw@7200 udpgw@7300
        echo -e "${GREEN}รีสตาร์ทบริการทั้งหมดเรียบร้อยแล้ว!${NC}"
        ;;
    0)
        exit 0
        ;;
    *)
        echo "เลือกเมนูไม่ถูกต้อง"
        ;;
esac
EOF
chmod +x /usr/bin/menu

echo "SSH, VPN & UDPGW Service Installed Successfully!"
