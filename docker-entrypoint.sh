#!/bin/bash
set -e

# ============================================================
# Docker Entrypoint for 3X-UI Panel with Proxy Chain
# ============================================================
# This script handles:
#   1. Directory creation and permissions
#   2. Fail2ban startup (if enabled)
#   3. Xray-core verification / fallback download
#   4. Proxy chain status reporting
#   5. Starting the application
# ============================================================

echo "========================================"
echo " 3X-UI Panel with Proxy Chain"
echo "========================================"

# ----------------------------------------------------------
# Ensure required directories exist
# ----------------------------------------------------------
mkdir -p "${XUI_DB_FOLDER:-/etc/x-ui}"
mkdir -p "${XUI_BIN_FOLDER:-/app/bin}"
mkdir -p "${XUI_LOG_FOLDER:-/var/log/x-ui}"
mkdir -p /root/cert

BIN_DIR="${XUI_BIN_FOLDER:-/app/bin}"

# ----------------------------------------------------------
# Start fail2ban if enabled
# ----------------------------------------------------------
if [ "${XUI_ENABLE_FAIL2BAN}" = "true" ]; then
    echo "[entrypoint] Starting fail2ban..."
    fail2ban-client -x start 2>/dev/null || echo "[entrypoint] WARNING: fail2ban failed to start"
fi

# ----------------------------------------------------------
# Verify Xray-core binary
# ----------------------------------------------------------
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  XRAY_BINARY="${BIN_DIR}/xray-linux-amd64" ;;
    aarch64) XRAY_BINARY="${BIN_DIR}/xray-linux-arm64" ;;
    armv7l)  XRAY_BINARY="${BIN_DIR}/xray-linux-arm32" ;;
    *)       XRAY_BINARY="${BIN_DIR}/xray-linux-amd64" ;;
esac

if [ -f "$XRAY_BINARY" ]; then
    XRAY_VER=$("$XRAY_BINARY" -version 2>/dev/null | head -1 || echo "unknown")
    echo "[entrypoint] Xray-core: ${XRAY_VER}"
else
    echo "[entrypoint] WARNING: Xray binary not found at ${XRAY_BINARY}"
    echo "[entrypoint]          Install it from the panel UI or download manually."

    # Attempt auto-download as fallback
    case "$ARCH" in
        x86_64)  XRAY_ARCH="64";        FNAME="amd64" ;;
        aarch64) XRAY_ARCH="arm64-v8a"; FNAME="arm64" ;;
        armv7l)  XRAY_ARCH="arm32-v7a"; FNAME="arm32" ;;
        *)       XRAY_ARCH="64";        FNAME="amd64" ;;
    esac

    echo "[entrypoint] Attempting auto-download of Xray-core..."
    XRAY_VERSION=$(wget -qO- "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
        | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null || echo "")

    if [ -n "$XRAY_VERSION" ]; then
        TMP_ZIP="/tmp/xray.zip"
        DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
        if wget -q -O "$TMP_ZIP" "$DOWNLOAD_URL" 2>/dev/null; then
            mkdir -p /tmp/xray-extract
            unzip -o "$TMP_ZIP" -d /tmp/xray-extract 2>/dev/null
            cp /tmp/xray-extract/xray "${BIN_DIR}/xray-linux-${FNAME}"
            chmod +x "${BIN_DIR}/xray-linux-${FNAME}"
            [ -f /tmp/xray-extract/geosite.dat ] && [ ! -f "${BIN_DIR}/geosite.dat" ] && cp /tmp/xray-extract/geosite.dat "${BIN_DIR}/"
            [ -f /tmp/xray-extract/geoip.dat ] && [ ! -f "${BIN_DIR}/geoip.dat" ] && cp /tmp/xray-extract/geoip.dat "${BIN_DIR}/"
            rm -rf /tmp/xray.zip /tmp/xray-extract
            echo "[entrypoint] Xray v${XRAY_VERSION} installed successfully."
        else
            echo "[entrypoint] WARNING: Auto-download failed. Install from panel UI."
        fi
    fi
fi

# ----------------------------------------------------------
# Display proxy chain status
# ----------------------------------------------------------
if [ "${PROXY_CHAIN_ENABLE}" = "true" ]; then
    echo "[entrypoint] Proxy chain: ENABLED"
    echo "[entrypoint]   Entry point: ${PROXY_CHAIN_ADDRESS:-not set}:${PROXY_CHAIN_PORT:-443}"
    echo "[entrypoint]   Configure via Settings > Proxy Chain Configuration"
fi

# ----------------------------------------------------------
# Display startup information
# ----------------------------------------------------------
echo "----------------------------------------"
echo " DB folder:  ${XUI_DB_FOLDER:-/etc/x-ui}"
echo " Bin folder: ${XUI_BIN_FOLDER:-/app/bin}"
echo " Log folder: ${XUI_LOG_FOLDER:-/var/log/x-ui}"
echo " Log level:  ${XUI_LOG_LEVEL:-info}"
echo " Timezone:   ${TZ:-UTC}"
echo " Fail2ban:   ${XUI_ENABLE_FAIL2BAN:-false}"
echo "----------------------------------------"
echo "[entrypoint] Starting 3X-UI Panel..."
echo ""

# ----------------------------------------------------------
# Execute the main command
# ----------------------------------------------------------
exec "$@"
