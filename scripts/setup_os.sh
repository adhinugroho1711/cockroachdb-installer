#!/bin/bash

# SOP CockroachDB - OS Optimization Script (Auto-detect)
# Description: Optimasi kernel, network, dan limits dengan deteksi OS dan Arsitektur

set -e

echo "Starting OS Optimization..."

# 1. Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

ARCH=$(uname -m)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))

echo "Detected OS: $OS (${VERSION_ID:-unknown})"
echo "Detected Arch: $ARCH"
echo "Detected Total RAM: $TOTAL_MEM_MB MB"

# 2. Update & Install Dependencies based on OS
case "$OS" in
    ubuntu|debian)
        sudo apt-get update
        # Don't install ntp - use systemd-timesyncd (default on modern Ubuntu)
        sudo apt-get install -y curl software-properties-common
        ;;
    centos|rhel|rocky|almalinux)
        sudo yum update -y
        sudo yum install -y chrony curl bind-utils
        ;;
    *)
        echo "OS $OS not explicitly supported, but will try to continue..."
        ;;
esac

# 3. Timezone & Time Sync
echo "Configuring timezone and time synchronization..."
# Auto-detect current timezone or allow user to set it
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
echo "Current timezone: $CURRENT_TZ"
read -p "Change timezone? (leave blank to keep current, or enter timezone like 'Asia/Jakarta'): " NEW_TZ
if [ -n "$NEW_TZ" ]; then
    sudo timedatectl set-timezone "$NEW_TZ" && echo "Timezone set to: $NEW_TZ"
else
    echo "Keeping current timezone: $CURRENT_TZ"
fi

# Enable time sync (systemd-timesyncd for Ubuntu/Debian, chronyd for RHEL-based)
if systemctl list-unit-files | grep -q systemd-timesyncd; then
    sudo systemctl enable systemd-timesyncd || true
    sudo systemctl start systemd-timesyncd || true
    echo "Using systemd-timesyncd for time synchronization"
elif systemctl list-unit-files | grep -q chronyd; then
    sudo systemctl enable chronyd || true
    sudo systemctl start chronyd || true
    echo "Using chronyd for time synchronization"
else
    echo "Warning: No time sync daemon found. Consider installing chrony."
fi

# 4. Create Database User
if ! id "cockroach" &>/dev/null; then
    sudo useradd -m -s /bin/bash cockroach || sudo adduser --disabled-password --gecos "" cockroach
fi

# 5. File Descriptors & Limits
echo "Configuring file limits..."
cat <<EOF | sudo tee /etc/security/limits.d/cockroach.conf
cockroach soft nofile 100000
cockroach hard nofile 100000
EOF

# 6. Kernel Tuning (sysctl) - Adaptive based on RAM
echo "Tuning kernel parameters (adaptive to ${TOTAL_MEM_MB}MB RAM)..."

# Calculate adaptive values based on RAM
if [ "$TOTAL_MEM_MB" -lt 4096 ]; then
    # Low RAM servers (<4GB)
    SOMAXCONN=1024
    MAX_SYN_BACKLOG=1024
    FILE_MAX=500000
    echo "Using LOW RAM profile"
elif [ "$TOTAL_MEM_MB" -lt 16384 ]; then
    # Medium RAM servers (4-16GB)
    SOMAXCONN=4096
    MAX_SYN_BACKLOG=4096
    FILE_MAX=1000000
    echo "Using MEDIUM RAM profile"
else
    # High RAM servers (>16GB)
    SOMAXCONN=8192
    MAX_SYN_BACKLOG=8192
    FILE_MAX=2000000
    echo "Using HIGH RAM profile"
fi

sudo mkdir -p /etc/sysctl.d
cat <<EOF | sudo tee /etc/sysctl.d/99-cockroach.conf
# Memory Tuning
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.overcommit_memory = 0

# File System (adaptive: $FILE_MAX)
fs.file-max = $FILE_MAX

# Network Tuning (adaptive: somaxconn=$SOMAXCONN)
net.core.somaxconn = $SOMAXCONN
net.ipv4.tcp_max_syn_backlog = $MAX_SYN_BACKLOG
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.tcp_fin_timeout = 30
EOF

sudo sysctl -p /etc/sysctl.d/99-cockroach.conf

# 7. Configure Transparent Huge Pages (THP) - CockroachDB Recommendation
echo "Configuring Transparent Huge Pages (THP)..."
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    # Set THP to 'madvise' mode (recommended by CockroachDB)
    echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
    echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/defrag
    echo "THP set to 'madvise' mode"
    
    # Make it persistent across reboots
    sudo mkdir -p /etc/systemd/system/cockroach.service.d
    cat <<THPEOF | sudo tee /etc/rc.local
#!/bin/bash
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo madvise > /sys/kernel/mm/transparent_hugepage/defrag
exit 0
THPEOF
    sudo chmod +x /etc/rc.local
else
    echo "THP not available on this kernel, skipping..."
fi

# 8. Disable Swap (Recommended for CockroachDB latency)
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab || true

# 8. Firewall Configuration (UFW or Firewalld)
if command -v ufw >/dev/null; then
    sudo ufw allow 26257/tcp comment 'CockroachDB SQL'
    sudo ufw allow 8080/tcp comment 'CockroachDB Web UI'
    sudo ufw allow 22/tcp comment 'SSH'
    sudo ufw --force enable
elif command -v firewall-cmd >/dev/null; then
    sudo firewall-cmd --permanent --add-port=26257/tcp
    sudo firewall-cmd --permanent --add-port=8080/tcp
    sudo firewall-cmd --permanent --add-port=22/tcp
    sudo firewall-cmd --reload
fi

echo "OS Optimization Complete for $OS on $ARCH."
