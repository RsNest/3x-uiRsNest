# Docker Setup — 3X-UI with Proxy Chain

Complete Docker containerization for the modified 3X-UI panel with proxy chain functionality.

## Architecture Overview

```
Client → Russian Proxy (Nginx stream) → Polish Server (3X-UI + Xray) → Internet
         ────────────────────────────    ────────────────────────────
         Entry point for clients          This Docker container
         (address in client configs)      (exit point to internet)
```

## Quick Start

### 1. Build and Start

```bash
# Clone the repository
git clone <your-repo-url> 3x-ui
cd 3x-ui

# Build and start the container
docker-compose up -d

# Wait for initialization (~15 seconds on first run)
sleep 15

# Check if container is healthy
docker-compose ps
```

### 2. Access the Panel

Open your browser and navigate to:

```
http://YOUR_SERVER_IP:2053
```

**Default credentials:**
- Username: `admin`
- Password: `admin`

> **Important:** Change these immediately after first login via Settings > Security.

### 3. Configure Proxy Chain

1. Go to **Settings** → **Panel Settings** → **Proxy Chain Configuration**
2. Toggle **Enable Proxy Chain Mode** to ON
3. Fill in:
   - **Proxy Server Address**: Your Russian server IP or domain
   - **Proxy Server Port**: `443` (or whatever port Nginx listens on)
   - **Original Server Address**: This server's real IP (for your reference)
   - **Original Server Port**: `443`
4. Click **Save Configuration**
5. Verify the dashboard shows "Proxy Chain Mode: ENABLED"

### 4. Create an Inbound

1. Go to **Inbounds** → **Add Inbound**
2. Configure your preferred protocol (e.g., VLESS + Reality)
3. Add a client
4. Copy the subscription URL — the address inside the config will be the Russian proxy server

---

## Docker Commands Reference

### Lifecycle

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# Restart
docker-compose restart

# Rebuild after code changes
docker-compose up -d --build

# Force full rebuild (no cache)
docker-compose build --no-cache && docker-compose up -d
```

### Logs

```bash
# Follow all logs
docker-compose logs -f

# Last 100 lines
docker-compose logs --tail=100

# Xray logs (from inside container)
docker exec 3x-ui-proxy-chain cat /var/log/x-ui/access.log
```

### Shell Access

```bash
# Open shell in container
docker exec -it 3x-ui-proxy-chain bash

# Check xray binary
docker exec 3x-ui-proxy-chain /app/bin/xray-linux-amd64 -version

# Check panel settings
docker exec 3x-ui-proxy-chain /app/x-ui setting -show
```

### Backup and Restore

```bash
# Backup database
docker cp 3x-ui-proxy-chain:/etc/x-ui/x-ui.db ./backup/x-ui.db

# Restore database
docker cp ./backup/x-ui.db 3x-ui-proxy-chain:/etc/x-ui/x-ui.db
docker-compose restart
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `TZ` | `UTC` | Container timezone |
| `XUI_LOG_LEVEL` | `info` | Log level: debug, info, notice, warning, error |
| `XUI_DB_FOLDER` | `/etc/x-ui` | Database storage path |
| `XUI_BIN_FOLDER` | `/app/bin` | Xray binary + geo files path |
| `XUI_LOG_FOLDER` | `/var/log/x-ui` | Log files path |
| `XUI_DEBUG` | `false` | Enable debug mode |
| `PROXY_CHAIN_ENABLE` | `false` | Enable proxy chain (informational in entrypoint) |
| `PROXY_CHAIN_ADDRESS` | *(empty)* | Entry-point proxy address |
| `PROXY_CHAIN_PORT` | `443` | Entry-point proxy port |

Set these in `docker-compose.yml` under the `environment` section.

### Ports

| Port | Purpose |
|---|---|
| `2053` | Web panel (default) |
| `2096` | Subscription server (default) |
| `443` | Xray traffic (VLESS/Reality/TLS) |
| `80` | Xray traffic (HTTP) |

Add more port mappings in `docker-compose.yml` as needed for your inbounds.

### Volumes

| Volume | Container Path | Purpose |
|---|---|---|
| `xui-db` | `/etc/x-ui` | SQLite database (settings, inbounds, clients) |
| `xui-bin` | `/app/bin` | Xray binary, geoip.dat, geosite.dat |
| `xui-logs` | `/var/log/x-ui` | Application and access logs |
| `./cert` | `/root/cert` | SSL certificates (bind mount) |

### SSL Certificates

Place your SSL certificate files in the `./cert` directory:

```bash
mkdir -p cert
cp /path/to/fullchain.pem cert/
cp /path/to/privkey.pem cert/
```

Then configure the paths in the panel:
- Settings → Certificate: `/root/cert/fullchain.pem`
- Settings → Private Key: `/root/cert/privkey.pem`

---

## Proxy Chain Testing

### Verify Subscription Content

After enabling proxy chain mode and creating an inbound with a client:

```bash
# Get subscription URL from the panel (Inbounds → Client → Subscription)
# Then fetch it and decode:
curl -s "http://YOUR_SERVER:2096/sub/CLIENT_SUB_ID" | base64 -d
```

The decoded output should show:
- `address` = your Russian proxy server (not the Polish server)
- `port` = your Russian proxy port
- All other parameters (UUID, flow, security, SNI, etc.) = unchanged

### Test with JSON Subscription

```bash
curl -s "http://YOUR_SERVER:2096/json/CLIENT_SUB_ID" | python3 -m json.tool
```

Look for the `address` and `port` fields in the outbound settings.

### Verify Backward Compatibility

1. Disable proxy chain mode in Settings
2. Fetch the subscription again
3. Verify the address is now the original server address

---

## Nginx Configuration (Russian Server)

After the 3X-UI Docker container is running on the Polish server, configure Nginx on the Russian server:

```nginx
# /etc/nginx/nginx.conf (on Russian server)
stream {
    upstream polish_xray {
        server POLISH_SERVER_IP:443;
    }

    server {
        listen 443;
        listen [::]:443;
        proxy_pass polish_xray;
        proxy_protocol off;
        proxy_connect_timeout 10s;
        proxy_timeout 300s;
    }
}
```

Restart Nginx:
```bash
sudo nginx -t && sudo systemctl restart nginx
```

---

## Troubleshooting

### Container won't start

```bash
# Check logs for errors
docker-compose logs --tail=50

# Verify image built successfully
docker-compose build

# Check disk space
df -h
```

### Xray binary not found

The entrypoint script auto-downloads Xray on first run. If it fails:

```bash
# Install manually from the panel UI:
# Panel → Xray Settings → Install/Update Xray

# Or download manually:
docker exec -it 3x-ui-proxy-chain bash
cd /app/bin
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip Xray-linux-64.zip
mv xray xray-linux-amd64
chmod +x xray-linux-amd64
```

### Database permission errors

```bash
# Fix permissions
docker exec -it 3x-ui-proxy-chain chown -R xui:xui /etc/x-ui
docker-compose restart
```

### Port already in use

```bash
# Find what's using the port
sudo lsof -i :2053
sudo lsof -i :443

# Change ports in docker-compose.yml:
# ports:
#   - "8080:2053"   # Access panel on port 8080 instead
```

### Reset panel settings

```bash
docker exec -it 3x-ui-proxy-chain /app/x-ui setting -reset
docker-compose restart
```

### Reset admin credentials

```bash
docker exec -it 3x-ui-proxy-chain /app/x-ui setting -username admin -password admin
docker-compose restart
```

---

## Development

### Hot Reload (Development Mode)

For development, you can mount the source code and rebuild:

```bash
# Build and run with source mounted for quick iteration
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

### Running Tests

```bash
docker exec -it 3x-ui-proxy-chain /app/x-ui -v
```

---

## File Structure

```
3x-ui/
├── Dockerfile              # Multi-stage build definition
├── docker-compose.yml      # Service orchestration
├── docker-entrypoint.sh    # Container initialization script
├── .dockerignore           # Build context exclusions
├── DOCKER.md               # This file
├── cert/                   # SSL certificates (bind mount)
│   ├── fullchain.pem
│   └── privkey.pem
└── (source code...)
```
