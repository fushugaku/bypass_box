#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

echo ""
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}       Router Proxy Setup (Minimal)${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""

# VLESS Configuration
VLESS_ADDRESS=""
VLESS_PORT=""
VLESS_UUID=""
VLESS_PATH=""

# URL decode function
urldecode() {
    local data="${1//+/ }"
    printf '%b' "${data//%/\\x}"
}

# Parse VLESS URL
parse_vless_url() {
    local url="$1"
    url="${url#vless://}"
    url="${url%%#*}"

    local base="${url%%\?*}"
    local query="${url#*\?}"
    [[ "$query" == "$base" ]] && query=""

    VLESS_UUID="${base%%@*}"
    local addr_port="${base#*@}"
    VLESS_ADDRESS="${addr_port%%:*}"
    VLESS_PORT="${addr_port##*:}"

    VLESS_PATH=""
    if [[ -n "$query" ]]; then
        local path_param=$(echo "$query" | tr '&' '\n' | grep '^path=' | cut -d'=' -f2)
        [[ -n "$path_param" ]] && VLESS_PATH=$(urldecode "$path_param")
    fi

    [[ -n "$VLESS_UUID" && -n "$VLESS_ADDRESS" && -n "$VLESS_PORT" ]]
}

configure_vless() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Try to load from config.env if it exists
    if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
        log "Loading configuration from config.env..."
        source "${SCRIPT_DIR}/config.env"
    fi

    # Check if all values are already set
    if [[ -n "$VLESS_ADDRESS" && -n "$VLESS_PORT" && -n "$VLESS_UUID" && -n "$VLESS_PATH" ]]; then
        info "Found existing configuration:"
        echo "  Address: $VLESS_ADDRESS"
        echo "  Port:    $VLESS_PORT"
        echo "  UUID:    ${VLESS_UUID:0:8}..."
        echo "  Path:    $VLESS_PATH"
        echo ""
        read -p "Use this configuration? [Y/n]: " use_existing
        if [[ "${use_existing,,}" != "n" ]]; then
            return 0
        fi
        VLESS_ADDRESS="" && VLESS_PORT="" && VLESS_UUID="" && VLESS_PATH=""
    fi

    info "Paste VLESS URL or enter details manually."
    echo ""

    read -p "VLESS URL (or Enter for manual): " vless_url

    if [[ -n "$vless_url" ]]; then
        if parse_vless_url "$vless_url"; then
            log "Parsed VLESS URL successfully"
            [[ -z "$VLESS_PATH" ]] && read -p "WebSocket path: " VLESS_PATH
            [[ "${VLESS_PATH:0:1}" != "/" ]] && VLESS_PATH="/${VLESS_PATH}"
        else
            warn "Failed to parse URL, using manual input."
            VLESS_ADDRESS="" && VLESS_PORT="" && VLESS_UUID="" && VLESS_PATH=""
        fi
    fi

    # Manual input for missing values
    while [[ -z "$VLESS_ADDRESS" ]]; do
        read -p "VLESS Server Address: " VLESS_ADDRESS
    done

    while [[ -z "$VLESS_PORT" || ! "$VLESS_PORT" =~ ^[0-9]+$ ]]; do
        read -p "VLESS Server Port [443]: " VLESS_PORT
        VLESS_PORT="${VLESS_PORT:-443}"
    done

    while [[ -z "$VLESS_UUID" ]]; do
        read -p "VLESS UUID: " VLESS_UUID
    done

    while [[ -z "$VLESS_PATH" ]]; do
        read -p "VLESS WebSocket Path: " VLESS_PATH
        [[ "${VLESS_PATH:0:1}" != "/" ]] && VLESS_PATH="/${VLESS_PATH}"
    done

    echo ""
    log "Configuration: $VLESS_ADDRESS:$VLESS_PORT"

    read -p "Save to config.env? [y/N]: " save_config
    if [[ "${save_config,,}" == "y" ]]; then
        cat > "${SCRIPT_DIR}/config.env" << EOF
VLESS_ADDRESS="$VLESS_ADDRESS"
VLESS_PORT=$VLESS_PORT
VLESS_UUID="$VLESS_UUID"
VLESS_PATH="$VLESS_PATH"
EOF
        log "Saved to config.env"
    fi
}

# Configure VLESS
configure_vless

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64) XRAY_ARCH="64"; BYEDPI_ARCH="x86_64" ;;
    aarch64|arm64) XRAY_ARCH="arm64-v8a"; BYEDPI_ARCH="aarch64" ;;
    armv7l) XRAY_ARCH="arm32-v7a"; BYEDPI_ARCH="armv7" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Create directories
mkdir -p /opt/proxy/{xray,byedpi}
cd /opt/proxy

# Install xray-core
echo "Installing xray-core..."
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d'"' -f4)
curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
unzip -o xray.zip -d xray/
chmod +x xray/xray
rm xray.zip

# Install ByeDPI
echo "Installing ByeDPI..."
cd /opt/proxy/byedpi
git clone --depth 1 https://github.com/hufrea/byedpi.git src 2>/dev/null || (cd src && git pull)
cd src
make clean 2>/dev/null || true
make
cp ciadpi /opt/proxy/byedpi/
cd /opt/proxy

# Create xray config
log "Creating xray configuration..."
cat > /opt/proxy/xray/config.json << XRAY_CONFIG
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "port": 1081,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"],
        "routeOnly": false
      }
    }
  ],
  "outbounds": [
    {
      "tag": "vless-out",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${VLESS_ADDRESS}",
            "port": ${VLESS_PORT},
            "users": [
              {
                "id": "${VLESS_UUID}",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${VLESS_ADDRESS}",
          "fingerprint": "chrome"
        },
        "wsSettings": {
          "path": "${VLESS_PATH}"
        }
      }
    },
    {
      "tag": "byedpi-out",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 1080
          }
        ]
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "domain": [
          "domain:youtube.com",
          "domain:youtu.be",
          "domain:ytimg.com",
          "domain:yt3.ggpht.com",
          "domain:googlevideo.com",
          "domain:youtube-nocookie.com",
          "domain:yt.be"
        ],
        "outboundTag": "byedpi-out"
      },
      {
        "type": "field",
        "domain": [
          "domain:ru",
          "domain:xn--p1ai"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": [
          "geosite:ru"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "vless-out"
      }
    ]
  }
}
XRAY_CONFIG

# Create systemd services
echo "Creating systemd services..."

cat > /etc/systemd/system/byedpi.service << 'EOF'
[Unit]
Description=ByeDPI - DPI bypass proxy
After=network.target

[Service]
Type=simple
ExecStart=/opt/proxy/byedpi/ciadpi -i 127.0.0.1 -p 1080 --tlsrec 2+s
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/xray-router.service << 'EOF'
[Unit]
Description=Xray Routing Proxy
After=network.target byedpi.service
Wants=byedpi.service

[Service]
Type=simple
ExecStart=/opt/proxy/xray/xray run -config /opt/proxy/xray/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable byedpi xray-router
systemctl restart byedpi
sleep 2
systemctl restart xray-router

echo ""
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}       Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo "  SOCKS5 Proxy: 0.0.0.0:1081 (no auth)"
echo ""
echo "  Routing:"
echo "    YouTube     → ByeDPI (DPI bypass)"
echo "    .ru/.рф     → Direct"
echo "    Other       → VLESS (${VLESS_ADDRESS})"
echo ""
echo "  Commands:"
echo "    Status:  systemctl status byedpi xray-router"
echo "    Logs:    journalctl -u xray-router -f"
echo ""
