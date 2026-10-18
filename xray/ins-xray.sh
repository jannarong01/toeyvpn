{
      "port": 10001,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid2}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess/"
        }
      }
    },
    {
      "port": 10002,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid4}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless/"
        }
      }
    },