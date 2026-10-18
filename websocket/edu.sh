#!/bin/bash
apt-get install -y python3

wget -q -O /usr/local/bin/ws-nontls https://${GITHUB_REPO}/websocket.py
chmod +x /usr/local/bin/ws-nontls
sed -i 's/print .*/pass/g' /usr/local/bin/ws-nontls 2>/dev/null

cat > /etc/systemd/system/ws-epro.service << END
[Unit]
Description=SSH WebSocket Proxy (Port 80 & 443 Multiplexer)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-nontls 10015
Restart=on-failure

[Install]
WantedBy=multi-user.target
END

systemctl daemon-reload
systemctl enable ws-epro
systemctl restart ws-epro