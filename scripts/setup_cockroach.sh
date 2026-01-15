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
echo ""

# 3. Interactive Cluster Configuration
echo "=============================================="
echo "  CLUSTER CONFIGURATION"
echo "=============================================="
echo "Masukkan IP untuk konfigurasi cluster."
echo "Tekan ENTER untuk skip (bisa diubah nanti di systemd service file)."
echo ""

# Get this node's IP (auto-detect primary interface)
DEFAULT_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$DEFAULT_IP" ]; then
    DEFAULT_IP="localhost"
fi

read -p "IP Node ini (advertise-addr) [${DEFAULT_IP}]: " ADVERTISE_ADDR
ADVERTISE_ADDR=${ADVERTISE_ADDR:-$DEFAULT_IP}

read -p "IP semua nodes (join), pisahkan dengan koma [${ADVERTISE_ADDR}]: " JOIN_ADDRS
JOIN_ADDRS=${JOIN_ADDRS:-$ADVERTISE_ADDR}

echo ""
echo "Config Summary:"
echo "  - Advertise Address: ${ADVERTISE_ADDR}"
echo "  - Join Addresses: ${JOIN_ADDRS}"
echo ""

# 3. Download & Install Binary
echo "Downloading CockroachDB $VERSION for $ARCH..."
if ! curl -L "https://binaries.cockroachdb.com/cockroach-${VERSION}.${ARCH}.tgz" | tar -xz; then
    echo "ERROR: Failed to download or extract CockroachDB binary."
    exit 1
fi
sudo cp -i cockroach-${VERSION}.${ARCH}/cockroach ${INSTALL_DIR}/
rm -rf cockroach-${VERSION}.${ARCH}

# 4. Create cockroach user if not exists
if ! id "cockroach" &>/dev/null; then
    echo "Creating user 'cockroach'..."
    sudo useradd -m -s /bin/bash cockroach || sudo adduser --disabled-password --gecos "" cockroach
fi

# 5. Setup Directories
echo "Setting up directories..."
sudo mkdir -p ${DATA_DIR} ${LOG_DIR}
sudo chown -R cockroach:cockroach ${DATA_DIR} ${LOG_DIR}

# 6. Verify installation
echo "Verifying installation..."
if [ ! -f ${INSTALL_DIR}/cockroach ]; then
    echo "ERROR: CockroachDB binary not found at ${INSTALL_DIR}/cockroach"
    exit 1
fi
echo "Binary installed successfully: $(${INSTALL_DIR}/cockroach version | grep 'Build Tag')"

# 8. Create Systemd Service
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
    --advertise-addr=${ADVERTISE_ADDR} \
    --join=${JOIN_ADDRS}
Restart=always
RestartSec=10
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

# 9. Verify service file
if [ -f /etc/systemd/system/cockroach.service ]; then
    echo "✅ Systemd service created successfully"
else
    echo "❌ ERROR: Failed to create systemd service file"
    exit 1
fi

echo ""
echo "=============================================="
echo "  ✅ CockroachDB Installation Complete!"
echo "=============================================="
echo ""
echo "Configured Settings:"
echo "  - Advertise Address: ${ADVERTISE_ADDR}"
echo "  - Join Addresses: ${JOIN_ADDRS}"
echo "  - Cache: ${CACHE_MIB}MiB"
echo "  - SQL Memory: ${SQL_MEM_MIB}MiB"
echo ""
echo "Next Steps:"
echo "1. Start the service:"
echo "   sudo systemctl enable --now cockroach"
echo ""
echo "2. Verify it's running:"
echo "   ps aux | grep cockroach | grep -v grep"
echo ""
echo "3. (Optional) Edit config if IPs change:"
echo "   sudo nano /etc/systemd/system/cockroach.service"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl restart cockroach"
echo ""
