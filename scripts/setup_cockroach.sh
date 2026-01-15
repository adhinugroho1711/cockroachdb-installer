#!/bin/bash

# SOP CockroachDB - Installation & Startup Script (Auto-detect)
# Description: Instalasi CockroachDB dengan deteksi arsitektur dan optimasi memory otomatis

set -e

VERSION="v23.1.11"
INSTALL_DIR="/usr/local/bin"
DATA_DIR="/var/lib/cockroach"
LOG_DIR="/var/log/cockroach"

# 1. Detect Architecture
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64) ARCH="linux-amd64" ;;
    aarch64|arm64) ARCH="linux-arm64" ;;
    *) echo "Architecture $ARCH_RAW not supported"; exit 1 ;;
esac

# 2. Calculate Memory Limits (Default 25% Cache, 25% SQL)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
# Convert to MiB
TOTAL_MEM_MIB=$((TOTAL_MEM_KB / 1024))
CACHE_MIB=$((TOTAL_MEM_MIB * 25 / 100))
SQL_MEM_MIB=$((TOTAL_MEM_MIB * 25 / 100))

echo "Detected Arch: $ARCH"
echo "Detected RAM: ${TOTAL_MEM_MIB}MiB"
echo "Suggested Config: --cache=${CACHE_MIB}MiB --max-sql-memory=${SQL_MEM_MIB}MiB"

# 3. Download & Install Binary
echo "Downloading CockroachDB $VERSION for $ARCH..."
if ! curl -L "https://binaries.cockroachdb.com/cockroach-${VERSION}.${ARCH}.tgz" | tar -xz; then
    echo "ERROR: Failed to download or extract CockroachDB binary."
    exit 1
fi
sudo cp -i cockroach-${VERSION}.${ARCH}/cockroach ${INSTALL_DIR}/
rm -rf cockroach-${VERSION}.${ARCH}

# 4. Setup Directories
sudo mkdir -p ${DATA_DIR} ${LOG_DIR}
if id "cockroach" &>/dev/null; then
    sudo chown -R cockroach:cockroach ${DATA_DIR} ${LOG_DIR}
fi

# 5. Create Systemd Service
echo "Creating systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/cockroach.service
[Unit]
Description=CockroachDB (Auto-optimized)
After=network.target

[Service]
Type=notify
User=cockroach
ExecStart=${INSTALL_DIR}/cockroach start \
    --insecure \
    --store=${DATA_DIR} \
    --log-dir=${LOG_DIR} \
    --cache=${CACHE_MIB}MiB \
    --max-sql-memory=${SQL_MEM_MIB}MiB \
    --listen-addr=:26257 \
    --http-addr=:8080 \
    --join=localhost
Restart=always
RestartSec=10
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

echo "CockroachDB Installation & Optimization Complete."
echo "NOTE: Update --join and --advertise-addr in /etc/systemd/system/cockroach.service before starting."
