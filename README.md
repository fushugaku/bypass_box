# Router Proxy Setup

A smart proxy router for Linux that intelligently routes network traffic through different proxy mechanisms based on destination domains. Designed for environments with network restrictions, particularly to bypass Deep Packet Inspection (DPI).

## Features

- **Intelligent Domain-Based Routing**: Routes traffic through different proxies based on destination
- **DPI Bypass**: Uses ByeDPI for YouTube traffic to circumvent Deep Packet Inspection
- **VLESS Tunnel**: Encrypted tunneling for general traffic via WebSocket + TLS
- **Direct Access**: Russian domains (.ru, .su, .рф) bypass all proxies
- **Auto-Recovery**: Systemd services with automatic restart on failure
- **Cross-Architecture**: Supports x86_64, aarch64, and armv7l

## Routing Rules

| Destination | Proxy Method | Description |
|-------------|--------------|-------------|
| YouTube domains | ByeDPI | DPI bypass via TLS record fragmentation |
| Russian domains (.ru, .su, .рф) | Direct | No proxy, direct connection |
| All other traffic | VLESS | Encrypted tunnel via WebSocket |

## Requirements

- Linux with systemd
- Root access
- One of the following package managers: apt-get, pacman, dnf, or apk
- Internet connection for downloading dependencies

### Dependencies (auto-installed)

- curl
- unzip
- git
- build-essential (or equivalent)

## Installation

### Prerequisites

You need a VLESS server to use this proxy. You'll need the following information from your VLESS provider:

- Server address (e.g., `your-server.example.com`)
- Port (usually `443`)
- UUID (e.g., `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- WebSocket path (e.g., `/ws` or `/your-path`)

### Option 1: Interactive Setup (Recommended)

The setup script will prompt you for your VLESS configuration:

```bash
sudo ./setup-proxy.sh
```

**Easiest method**: Just paste your VLESS URL when prompted:

```
vless://ee998ef8-fb98-4756-8281-43f92099f1e2@server.example.com:443?path=%2Fws&security=tls&...#MyVPN
```

The script will automatically extract:
- Server address
- Port
- UUID
- WebSocket path

Alternatively, press Enter to input each field manually.

### Option 2: Configuration File

Create a configuration file before running the setup:

```bash
# Copy the template
cp config.env.example config.env

# Edit with your VLESS credentials
nano config.env
```

Then run the setup:

```bash
sudo ./setup-proxy.sh
```

### Alternative (Minimal Install)

```bash
sudo ./install.sh
```

### What the Setup Does

1. Prompts for VLESS configuration (or reads from `config.env`)
2. Detects your system architecture
3. Installs required dependencies
4. Downloads and installs Xray-core
5. Builds and installs ByeDPI from source
6. Disables IPv6 (required for ByeDPI)
7. Configures firewall rules
8. Creates and starts systemd services
9. Verifies the installation

## Configuration

### Proxy Endpoints

After installation, two proxy endpoints are available:

#### SOCKS5 Proxy (for browsers and general apps)

```
Host: 0.0.0.0 (accessible from network)
Port: 1081
Authentication: None
UDP: Enabled
```

#### HTTP Proxy (for CLI tools like Claude Code)

```
Host: 0.0.0.0 (accessible from network)
Port: 1082
Authentication: None
```

### Configure Applications

**Browsers and general applications** - use SOCKS5:

```
Proxy Type: SOCKS5
Host: <router-ip>
Port: 1081
```

**Claude Code and CLI tools** - use HTTP proxy:

```bash
# Add to ~/.zshrc or ~/.bashrc
export HTTPS_PROXY=http://<router-ip>:1082
export HTTP_PROXY=http://<router-ip>:1082
```

For example, with router at 192.168.1.23:

```bash
export HTTPS_PROXY=http://192.168.1.23:1082
export HTTP_PROXY=http://192.168.1.23:1082
```

### Xray Configuration

The main configuration file is located at:

```
/opt/proxy/xray/xray-config.json
```

Key settings:
- **Inbound**: SOCKS5 on port 1081 with domain sniffing
- **Outbound**: VLESS, ByeDPI (SOCKS), and Direct
- **DNS**: Google (8.8.8.8) and Cloudflare (1.1.1.1), IPv4 only

### Modifying Routing Rules

Edit the `routing.rules` section in `xray-config.json`:

```json
{
  "type": "field",
  "domain": ["your-domain.com"],
  "outboundTag": "direct"
}
```

Available outbound tags:
- `vless-out` - Route through VLESS tunnel
- `byedpi` - Route through ByeDPI (DPI bypass)
- `direct` - Direct connection (no proxy)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Client Applications                     │
│              (Browser, Apps with SOCKS5)                │
└────────────────────────┬────────────────────────────────┘
                         │ SOCKS5 :1081
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Xray-core Routing Engine                    │
│  • Domain Sniffing (HTTP/TLS)                           │
│  • Rule-based Routing                                    │
│  • IPv4-only DNS Resolution                             │
└──────┬─────────────────┬─────────────────┬──────────────┘
       │                 │                 │
       │ YouTube         │ .ru/.su/.рф     │ Other
       ▼                 ▼                 ▼
┌────────────┐    ┌────────────┐    ┌────────────────┐
│  ByeDPI    │    │   Direct   │    │ VLESS Tunnel   │
│  :1080     │    │ Connection │    │ (WebSocket+TLS)│
└─────┬──────┘    └─────┬──────┘    └───────┬────────┘
      │                 │                   │
      └────────────────┴───────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │    Internet      │
              └──────────────────┘
```

## Services

Two systemd services are created:

### ByeDPI Service

```bash
# Check status
sudo systemctl status byedpi

# Restart
sudo systemctl restart byedpi

# View logs
sudo journalctl -u byedpi -f
```

### Xray Router Service

```bash
# Check status
sudo systemctl status xray-router

# Restart
sudo systemctl restart xray-router

# View logs
sudo journalctl -u xray-router -f
```

**Note**: xray-router depends on byedpi. Restarting byedpi will also restart xray-router.

## File Structure

### Repository Files

```
router-proxy-setup/
├── README.md             # This documentation
├── setup-proxy.sh        # Main setup script (interactive)
├── install.sh            # Minimal setup script
├── config.env.example    # Configuration template
├── config.env            # Your VLESS config (git-ignored)
├── byedpi.service        # Systemd service template
└── .gitignore            # Excludes sensitive files
```

### Installed Files

```
/opt/proxy/
├── xray/
│   ├── xray              # Xray binary
│   └── config.json       # Xray configuration
└── byedpi/
    └── ciadpi            # ByeDPI binary
```

## Troubleshooting

### Check Service Status

```bash
sudo systemctl status byedpi xray-router
```

### View Logs

```bash
# ByeDPI logs
sudo journalctl -u byedpi -n 50

# Xray logs
sudo journalctl -u xray-router -n 50
```

### Test Routing

**SOCKS5 proxy (port 1081):**

```bash
# Test YouTube (should use ByeDPI)
curl -x socks5h://127.0.0.1:1081 https://www.youtube.com -I

# Test Russian domain (should be direct)
curl -x socks5h://127.0.0.1:1081 https://ya.ru -I

# Test other domain (should use VLESS)
curl -x socks5h://127.0.0.1:1081 https://www.google.com -I
```

**HTTP proxy (port 1082):**

```bash
# Test HTTP proxy
curl -x http://127.0.0.1:1082 https://www.google.com -I

# Test from another machine (e.g., Mac using router at 192.168.1.23)
curl -x http://192.168.1.23:1082 https://api.anthropic.com -I
```

### Common Issues

**Services fail to start:**
- Ensure IPv6 is disabled: `cat /proc/sys/net/ipv6/conf/all/disable_ipv6` (should be 1)
- Check if ports 1080 and 1081 are available: `ss -tlnp | grep -E '1080|1081'`

**YouTube not working:**
- Verify ByeDPI is running: `systemctl status byedpi`
- Check ByeDPI logs for errors

**General connectivity issues:**
- Verify VLESS server is accessible
- Check firewall rules: `sudo firewall-cmd --list-ports` or `sudo ufw status`

### Restart All Services

```bash
sudo systemctl restart byedpi xray-router
```

## Security Considerations

- The SOCKS5 proxy has no authentication and is accessible from the network
- IPv6 is disabled system-wide
- **VLESS credentials**: Stored in `config.env` (excluded from git via `.gitignore`)
- Never commit `config.env` or `xray-config.json` to version control
- Consider restricting proxy access via firewall rules in production

### Restrict Proxy Access

```bash
# Allow only local network (example)
sudo firewall-cmd --remove-port=1081/tcp --permanent
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port protocol="tcp" port="1081" accept' --permanent
sudo firewall-cmd --reload
```

## Remote Deployment

To deploy to a remote Linux server (e.g., 192.168.1.23):

### 1. Copy files to the server

```bash
# From your local machine
scp -r /path/to/router-proxy-setup user@192.168.1.23:~/
```

### 2. SSH into the server and run setup

```bash
ssh user@192.168.1.23
cd ~/router-proxy-setup
sudo ./setup-proxy.sh
```

### 3. Configure your Mac to use the proxy

Add to `~/.zshrc`:

```bash
# For Claude Code and other CLI tools (HTTP proxy)
export HTTPS_PROXY=http://192.168.1.23:1082
export HTTP_PROXY=http://192.168.1.23:1082

# Optional: bypass proxy for local addresses
export NO_PROXY=localhost,127.0.0.1,.local
```

Then reload:

```bash
source ~/.zshrc
```

### 4. Verify connection

```bash
# Test that Claude Code can reach Anthropic API through the proxy
curl -x http://192.168.1.23:1082 https://api.anthropic.com -I
```

## Uninstallation

```bash
# Stop and disable services
sudo systemctl stop xray-router byedpi
sudo systemctl disable xray-router byedpi

# Remove service files
sudo rm /etc/systemd/system/xray-router.service
sudo rm /etc/systemd/system/byedpi.service
sudo systemctl daemon-reload

# Remove binaries and config
sudo rm -rf /opt/proxy

# Re-enable IPv6 (optional)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0
```

## License

This project uses the following open-source components:
- [Xray-core](https://github.com/XTLS/Xray-core) - MPL-2.0 License
- [ByeDPI (ciadpi)](https://github.com/hufrea/byedpi) - MIT License
