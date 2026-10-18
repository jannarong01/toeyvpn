#!/bin/bash
# =========================================
#  SSH, DROPBEAR, NGINX & BADVPN INSTALLER
# =========================================
export DEBIAN_FRONTEND=noninteractive

# 1. ลบ Apache2 และ UFW ป้องกันการแย่งพอร์ต 80
systemctl stop apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
apt-get purge -y ufw firewalld exim4 apache2 apache2-utils apache2-bin apache2-data >/dev/null 2>&1
apt-get autoremove -y >/dev/null 2>&1

# 2. ตั้งค่า Timezone เป็นเวลาไทย
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

# 3. ติดตั้งแพ็กเกจหลัก
apt-get update -y
apt-get install -y nginx dropbear vnstat curl wget jq python3 net-tools

# 4. ติดตั้ง BadVPN UDPGW (พอร์ต 7100, 7200, 7300)
echo "กำลังติดตั้ง BadVPN UDPGW..."
wget -q -O /usr/local/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"

# หากลิงก์แรกโหลดไม่ผ่านหรือไฟล์มีขนาด 0 byte ให้ลองลิงก์สำรอง
if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    wget -q -O /usr/local/bin/badvpn-udpgw "https://github.com/ambrop72/badvpn/raw/master/badvpn-udpgw64"
fi

# หากยังโหลดไฟล์ Binary ไม่ได้อีก ให้ทำการ Compile เองพร้อมไลบรารีที่จำเป็นครบชุด
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

# สร้าง Systemd Service สำหรับรัน UDPGW หลายพอร์ต
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

# 5. ตั้งค่า Dropbear ให้ทำงานที่พอร์ต 109 และ 143
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

# เพิ่ม Shell ที่อนุญาตสำหรับบัญชี VPN (ไม่ให้เข้าหน้า Terminal ได้)
grep -qxF '/bin/false' /etc/shells || echo "/bin/false" >> /etc/shells
grep -qxF '/usr/sbin/nologin' /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

# สร้าง Banner ต้อนรับเวลาเชื่อมต่อ SSH
cat <<EOF > /etc/issue.net
<p style="text-align:center"><b>=== PRIVATE VPN SERVER ===</b></p>
EOF

systemctl enable dropbear >/dev/null 2>&1
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
RED='\033[0;31m'
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
        echo -e "UDPGW Port   : 7100, 7200, 7300"
        echo -e "Payload      : GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
        echo -e "หมดอายุวันที่   : $(date -d "$days days" +"%Y-%m-%d")"
        echo -e "${YELLOW}=================================${NC}"
        ;;
    2)
        clear
        cat /etc/xray/client-info.txt 2>/dev/null || echo "ยังไม่มีข้อมูล Xray"
        ;;
    3)
        running
        ;;
    4)
        systemctl restart ssh dropbear nginx xray ws-epro udpgw@7100 udpgw@7200 udpgw@7300 vnstat
        echo -e "${GREEN}รีสตาร์ทบริการทั้งหมดเรียบร้อยแล้ว!${NC}"
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

echo "SSH, VPN & UDPGW Service Installed Successfully!"
