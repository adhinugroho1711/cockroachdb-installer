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

# 7. Create Systemd Service
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

# 8. Verify service file
if [ -f /etc/systemd/system/cockroach.service ]; then
    echo "✅ Systemd service created successfully"
else
    echo "❌ ERROR: Failed to create systemd service file"
    exit 1
fi

echo ""
echo "=============================================="
echo "CockroachDB Installation Complete!"
echo "=============================================="
echo ""
echo "Next Steps:"
echo "1. Edit /etc/systemd/system/cockroach.service"
echo "   - Update --join=<IP_NODE1>,<IP_NODE2>,<IP_NODE3>"
echo "   - Add --advertise-addr=<THIS_NODE_IP>"
echo ""
echo "2. Start the service:"
echo "   sudo systemctl enable --now cockroach"
echo ""
echo "3. Verify it's running:"
echo "   ps aux | grep cockroach | grep -v grep"
echo ""

