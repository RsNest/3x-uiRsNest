# ============================================================
# Multi-stage Dockerfile for 3X-UI Panel with Proxy Chain
# ============================================================

# ----------------------------------------------------------
# Stage 1: Build the Go binary
# ----------------------------------------------------------
FROM golang:1.25.7-alpine AS builder

# Install build dependencies required by CGO (sqlite3) and git
RUN apk add --no-cache git build-base

WORKDIR /src

# Cache Go module downloads
COPY go.mod go.sum ./
RUN go mod download

# Copy the entire source tree
COPY . .

# Build the application
# CGO_ENABLED=1 is required for mattn/go-sqlite3
# -s -w strips debug info to reduce binary size
RUN CGO_ENABLED=1 GOOS=linux go build \
    -a -installsuffix cgo \
    -ldflags="-s -w" \
    -o /src/x-ui \
    main.go

# ----------------------------------------------------------
# Stage 2: Download Xray-core and geo files
# ----------------------------------------------------------
FROM alpine:3.21 AS xray-downloader

RUN apk add --no-cache curl unzip

ARG TARGETARCH=amd64

WORKDIR /xray

# Download Xray-core binary
RUN set -ex; \
    case "${TARGETARCH}" in \
        amd64)  XRAY_ARCH="64";           FNAME="amd64" ;; \
        arm64)  XRAY_ARCH="arm64-v8a";    FNAME="arm64" ;; \
        arm)    XRAY_ARCH="arm32-v7a";    FNAME="arm32" ;; \
        386)    XRAY_ARCH="32";            FNAME="i386"  ;; \
        *)      XRAY_ARCH="64";           FNAME="amd64" ;; \
    esac; \
    XRAY_VERSION=$(curl -sf "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
        | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/'); \
    echo "Downloading Xray v${XRAY_VERSION} for ${FNAME}..."; \
    curl -sfLRO "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"; \
    unzip "Xray-linux-${XRAY_ARCH}.zip"; \
    rm -f "Xray-linux-${XRAY_ARCH}.zip"; \
    mv xray "xray-linux-${FNAME}"; \
    chmod +x "xray-linux-${FNAME}"

# Download geo files
RUN curl -sfLRO "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" && \
    curl -sfLRO "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" && \
    curl -sfLRo geoip_IR.dat "https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat" && \
    curl -sfLRo geosite_IR.dat "https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat" && \
    curl -sfLRo geoip_RU.dat "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat" && \
    curl -sfLRo geosite_RU.dat "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat"

# ----------------------------------------------------------
# Stage 3: Minimal runtime image
# ----------------------------------------------------------
FROM alpine:3.21

LABEL maintainer="3x-ui-proxy-chain"
LABEL description="3X-UI Panel with Proxy Chain support"

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    wget \
    unzip \
    bash \
    fail2ban

# Create directories that the application expects
RUN mkdir -p /app/bin \
             /etc/x-ui \
             /var/log/x-ui \
             /root/cert

WORKDIR /app

# Copy the compiled binary from the builder stage
# (web assets, HTML templates, and translations are embedded in the binary)
COPY --from=builder /src/x-ui /app/x-ui

# Copy Xray binary and geo files from the downloader stage
COPY --from=xray-downloader /xray/ /app/bin/

# Make binaries executable
RUN chmod +x /app/x-ui

# Copy the entrypoint script and fix Windows line endings (CRLF → LF)
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN sed -i 's/\r$//' /app/docker-entrypoint.sh && \
    chmod +x /app/docker-entrypoint.sh

# Environment variables with sensible defaults
# These can be overridden in docker-compose.yml or docker run
ENV TZ=UTC \
    XUI_LOG_LEVEL=info \
    XUI_DB_FOLDER=/etc/x-ui \
    XUI_BIN_FOLDER=/app/bin \
    XUI_LOG_FOLDER=/var/log/x-ui \
    XUI_ENABLE_FAIL2BAN=false

# Expose ports:
#   2053  - Web panel (default)
#   2096  - Subscription server (default)
#   443   - Xray traffic (common)
#   80    - Xray traffic (alternative)
EXPOSE 2053 2096 443 80

# Volumes for persistent data
VOLUME ["/etc/x-ui", "/app/bin", "/var/log/x-ui", "/root/cert"]

# Health check: verify the panel is responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:2053/ || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["/app/x-ui"]
