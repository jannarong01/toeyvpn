#!/bin/bash
# ==========================================
#  SSH & OVPN Installation Script (Cleaned)
# ==========================================

# Color
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'

# Getting IP
MYIP=$(wget -qO- ipinfo.io/ip);

# Link GitHub ของเรา (เปลี่ยนเป็น username ของคุณ)
GITHUB_REPO="raw.githubusercontent.com/jannarong01/toeyvpn/main"

export DEBIAN_FRONTEND=noninteractive
source /etc/os-release
ver=$VERSION_ID

# go to root
cd

# Edit file /etc/systemd/system/rc-local.service
cat > /etc/systemd/system/rc-local.service <<-END
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99
[Install]
WantedBy=multi-user.target
END

cat > /etc/rc.local <<-END
#!/bin/sh -e
# rc.local
exit 0
END

chmod +x /etc/rc.local
systemctl enable rc-local
systemctl start rc-local.service

# disable ipv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local

# Update & Remove unnecessary packages
apt update -y
apt upgrade -y
apt-get remove --purge ufw firewalld exim4 -y

# Install Requirements Tools
apt -y install wget curl net-tools ruby python3 make cmake coreutils rsyslog zip unzip nano sed gnupg bc apt-transport-https build-essential dirmngr libxml-parser-perl neofetch git lsof libsqlite3-dev zlib1g-dev gcc g++ libreadline-dev libssl-dev dos2unix

# set time GMT +7 (Thailand)
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

# set locale
sed -i 's/AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config

echo "clear" >> .profile
echo "neofetch" >> .profile

# install webserver (Nginx)
apt -y install nginx php php-fpm php-cli php-mysql
rm /etc/nginx/sites-enabled/default
rm /etc/nginx/sites-available/default
wget -q -O /etc/nginx/nginx.conf "https://${GITHUB_REPO}/ssh/nginx.conf"
wget -q -O /etc/nginx/conf.d/vps.conf "https://${GITHUB_REPO}/ssh/vps.conf"
sed -i 's/listen = \/var\/run\/php-fpm.sock/listen = 127.0.0.1:9000/g' /etc/php/fpm/pool.d/www.conf
useradd -m vps;
mkdir -p /home/vps/public_html
echo "<?php phpinfo() ?>" > /home/vps/public_html/info.php
chown -R www-data:www-data /home/vps/public_html
chmod -R g+rw /home/vps/public_html
cd /home/vps/public_html
wget -O /home/vps/public_html/index.html "https://${GITHUB_REPO}/ssh/index.html1"
/etc/init.d/nginx restart
cd

# install badvpn (พอร์ต 7100, 7200, 7300)
cd
wget -O /usr/bin/badvpn-udpgw "https://${GITHUB_REPO}/ssh/badvpn-udpgw64"
chmod +x /usr/bin/badvpn-udpgw
sed -i '$ i\screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 500' /etc/rc.local
sed -i '$ i\screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 500' /etc/rc.local
sed -i '$ i\screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 500' /etc/rc.local
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 500
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 500
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 500

# setting port ssh
sed -i 's/Port 22/Port 22/g' /etc/ssh/sshd_config
sed -i '/Port 22/a Port 2253' /etc/ssh/sshd_config
echo "Port 42" >> /etc/ssh/sshd_config
/etc/init.d/ssh restart

# install dropbear
apt -y install dropbear
sed -i 's/NO_START=1/NO_START=0/g' /etc/default/dropbear
sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=143/g' /etc/default/dropbear
sed -i 's/DROPBEAR_EXTRA_ARGS=/DROPBEAR_EXTRA_ARGS="-p 109 -p 1153"/g' /etc/default/dropbear
echo "/bin/false" >> /etc/shells
echo "/usr/sbin/nologin" >> /etc/shells
/etc/init.d/dropbear restart

# setting vnstat
apt -y install vnstat
/etc/init.d/vnstat restart
systemctl enable vnstat

# install fail2ban
apt -y install fail2ban
/etc/init.d/fail2ban restart

# banner /etc/issue.net
echo "Banner /etc/issue.net" >>/etc/ssh/sshd_config
sed -i 's@DROPBEAR_BANNER=""@DROPBEAR_BANNER="/etc/issue.net"@g' /etc/default/dropbear
wget -O /etc/issue.net "https://${GITHUB_REPO}/ssh/issue.net"

# blockir torrent
iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
iptables -A FORWARD -m string --string "announce_peer" --algo bm -j DROP
iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
iptables -A FORWARD -m string --algo bm --string "BitTorrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "BitTorrent protocol" -j DROP
iptables -A FORWARD -m string --algo bm --string "peer_id=" -j DROP
iptables -A FORWARD -m string --algo bm --string ".torrent" -j DROP
iptables-save > /etc/iptables.up.rules
iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload

# ตั้งค่า Cron Clean Log ทิ้งทุกเที่ยงคืน (ไม่รีบูตเครื่องมั่วซั่วแล้ว)
echo "0 0 * * * root clearlog" >> /etc/crontab
echo "0 1 * * * root delexp" >> /etc/crontab

# finishing
cd
chown -R www-data:www-data /home/vps/public_html
/etc/init.d/nginx restart
/etc/init.d/cron restart
/etc/init.d/ssh restart
/etc/init.d/dropbear restart
/etc/init.d/fail2ban restart
history -c
echo "unset HISTFILE" >> /etc/profile
rm -f /root/ssh-vpn.sh

clear
echo -e "${GREEN}SSH & VPN Service Installed Successfully!${NC}"