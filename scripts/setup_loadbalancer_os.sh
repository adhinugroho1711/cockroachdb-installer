#!/bin/bash

# SOP CockroachDB - HAProxy & PgBouncer Server Optimization
# Description: OS-level optimization for dedicated load balancer/connection pooler server
# Run this BEFORE installing HAProxy or PgBouncer

set -e

echo "=========================================="
echo "  HAProxy + PgBouncer Server Optimizer"
echo "=========================================="
echo ""

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
TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))

echo "Detected OS: $OS (${VERSION_ID:-unknown})"
echo "Detected Architecture: $ARCH"
echo "Detected Total RAM: ${TOTAL_MEM_GB}GB (${TOTAL_MEM_MB}MB)"
echo ""

# 2. Update system
echo "Updating package manager..."
case "$OS" in
    ubuntu|debian)
        sudo apt-get update -qq
        sudo apt-get install -y curl sysstat net-tools
        ;;
    centos|rhel|rocky|almalinux)
        sudo yum update -y -q
        sudo yum install -y curl sysstat net-tools
        ;;
esac

# 3. Timezone Configuration (Interactive)
echo "Configuring timezone..."
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
echo "Current timezone: $CURRENT_TZ"
read -p "Change timezone? (leave blank to keep current, or enter timezone like 'Asia/Jakarta'): " NEW_TZ
if [ -n "$NEW_TZ" ]; then
    sudo timedatectl set-timezone "$NEW_TZ" && echo "Timezone set to: $NEW_TZ"
else
    echo "Keeping current timezone: $CURRENT_TZ"
fi

# 4. Enable time sync
if systemctl list-unit-files | grep -q systemd-timesyncd; then
    sudo systemctl enable systemd-timesyncd || true
    sudo systemctl start systemd-timesyncd || true
elif systemctl list-unit-files | grep -q chronyd; then
    sudo systemctl enable chronyd || true
    sudo systemctl start chronyd || true
fi

# 5. Adaptive Kernel Parameters for Load Balancer/Proxy Server
echo ""
echo "Optimizing kernel parameters for HAProxy/PgBouncer workload..."

# Calculate adaptive values based on RAM
if [ "$TOTAL_MEM_MB" -lt 2048 ]; then
    # Very small server (<2GB) - minimal config
    SOMAXCONN=1024
    MAX_SYN_BACKLOG=2048
    FILE_MAX=100000
    RMEM_MAX=2097152      # 2MB
    WMEM_MAX=2097152      # 2MB
    TCP_MEM_LOW=131072
    TCP_MEM_PRESSURE=262144
    TCP_MEM_HIGH=524288
    PROFILE="MINIMAL"
elif [ "$TOTAL_MEM_MB" -lt 8192 ]; then
    # Small-Medium server (2-8GB) - standard config
    SOMAXCONN=4096
    MAX_SYN_BACKLOG=8192
    FILE_MAX=200000
    RMEM_MAX=8388608      # 8MB
    WMEM_MAX=8388608      # 8MB
    TCP_MEM_LOW=262144
    TCP_MEM_PRESSURE=524288
    TCP_MEM_HIGH=1048576
    PROFILE="STANDARD"
elif [ "$TOTAL_MEM_MB" -lt 16384 ]; then
    # Medium server (8-16GB) - optimized for HAProxy
    SOMAXCONN=8192
    MAX_SYN_BACKLOG=16384
    FILE_MAX=500000
    RMEM_MAX=16777216     # 16MB
    WMEM_MAX=16777216     # 16MB
    TCP_MEM_LOW=524288
    TCP_MEM_PRESSURE=1048576
    TCP_MEM_HIGH=2097152
    PROFILE="OPTIMIZED"
else
    # Large server (>16GB) - high performance
    SOMAXCONN=16384
    MAX_SYN_BACKLOG=32768
    FILE_MAX=1000000
    RMEM_MAX=33554432     # 32MB
    WMEM_MAX=33554432     # 32MB
    TCP_MEM_LOW=1048576
    TCP_MEM_PRESSURE=2097152
    TCP_MEM_HIGH=4194304
    PROFILE="HIGH_PERFORMANCE"
fi

echo "Using profile: $PROFILE for ${TOTAL_MEM_GB}GB RAM"
echo "  - somaxconn: $SOMAXCONN"
echo "  - max_syn_backlog: $MAX_SYN_BACKLOG"
echo "  - file-max: $FILE_MAX"

sudo mkdir -p /etc/sysctl.d
cat <<EOF | sudo tee /etc/sysctl.d/99-haproxy-pgbouncer.conf
# HAProxy + PgBouncer Optimizations (Auto-generated for ${TOTAL_MEM_GB}GB RAM)
# Profile: $PROFILE

# Network Connection Queue (adaptive: $SOMAXCONN)
net.core.somaxconn = $SOMAXCONN
net.ipv4.tcp_max_syn_backlog = $MAX_SYN_BACKLOG

# File Descriptors (adaptive: $FILE_MAX)
fs.file-max = $FILE_MAX

# TCP Buffer Sizes (adaptive based on RAM)
# Format: min default max (in bytes)
net.ipv4.tcp_rmem = 4096 87380 $RMEM_MAX
net.ipv4.tcp_wmem = 4096 65536 $WMEM_MAX
net.core.rmem_max = $RMEM_MAX
net.core.wmem_max = $WMEM_MAX

# TCP Memory Pages (adaptive)
net.ipv4.tcp_mem = $TCP_MEM_LOW $TCP_MEM_PRESSURE $TCP_MEM_HIGH

# TCP Performance Tuning for Proxy
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_slow_start_after_idle = 0

# Connection Tracking (for high concurrent connections)
net.netfilter.nf_conntrack_max = $((SOMAXCONN * 4))
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15

# Memory Management (less aggressive swap for proxy workload)
vm.swappiness = 1
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Disable IPv6 if not used (optional, comment out if using IPv6)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1
EOF

sudo sysctl -p /etc/sysctl.d/99-haproxy-pgbouncer.conf

# 6. File Descriptor Limits for HAProxy/PgBouncer users
echo ""
echo "Configuring file descriptor limits..."

# For HAProxy user
if id "haproxy" &>/dev/null 2>&1; then
    cat <<EOF | sudo tee /etc/security/limits.d/haproxy.conf
haproxy soft nofile $FILE_MAX
haproxy hard nofile $FILE_MAX
EOF
fi

# For PgBouncer user (postgres)
if id "postgres" &>/dev/null 2>&1; then
    cat <<EOF | sudo tee /etc/security/limits.d/pgbouncer.conf
postgres soft nofile $FILE_MAX
postgres hard nofile $FILE_MAX
EOF
fi

# Generic limit for root (for testing)
cat <<EOF | sudo tee -a /etc/security/limits.d/haproxy-pgbouncer.conf
root soft nofile $FILE_MAX
root hard nofile $FILE_MAX
* soft nofile $((FILE_MAX / 2))
* hard nofile $((FILE_MAX / 2))
EOF

# 7. Disable Swap (for consistent latency)
echo ""
echo "Disabling swap for consistent latency..."
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab || true

# 8. Transparent Huge Pages (madvise mode)
echo ""
echo "Configuring Transparent Huge Pages..."
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
    echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/defrag
    
    # Persist across reboots
    cat <<EOF | sudo tee /etc/rc.local
#!/bin/bash
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo madvise > /sys/kernel/mm/transparent_hugepage/defrag
exit 0
EOF
    sudo chmod +x /etc/rc.local
fi

# 9. Firewall Configuration
echo ""
echo "Configuring firewall..."
if command -v ufw >/dev/null; then
    sudo ufw allow 26257/tcp comment 'HAProxy - CockroachDB SQL'
    sudo ufw allow 6432/tcp comment 'PgBouncer'
    sudo ufw allow 8081/tcp comment 'HAProxy Stats'
    sudo ufw allow 22/tcp comment 'SSH'
    sudo ufw --force enable
elif command -v firewall-cmd >/dev/null; then
    sudo firewall-cmd --permanent --add-port=26257/tcp
    sudo firewall-cmd --permanent --add-port=6432/tcp
    sudo firewall-cmd --permanent --add-port=8081/tcp
    sudo firewall-cmd --permanent --add-port=22/tcp
    sudo firewall-cmd --reload
fi

# 10. Verify kernel module for connection tracking
echo ""
echo "Loading connection tracking module..."
sudo modprobe nf_conntrack || true
echo "nf_conntrack" | sudo tee -a /etc/modules

echo ""
echo "=========================================="
echo "  ✅ Optimization Complete!"
echo "=========================================="
echo ""
echo "Server Profile: $PROFILE"
echo "  RAM: ${TOTAL_MEM_GB}GB"
echo "  Max Connections: $SOMAXCONN"
echo "  File Descriptors: $FILE_MAX"
echo "  TCP Buffer (max): ${RMEM_MAX} bytes"
echo ""
echo "Next Steps:"
echo "1. Install HAProxy:"
echo "   bash scripts/setup_haproxy.sh"
echo ""
echo "2. Install PgBouncer (if needed for >1000 connections):"
echo "   bash scripts/setup_pgbouncer.sh"
echo ""
echo "⚠️  Recommended Reboot:"
echo "   Some kernel parameters will be fully active after reboot"
echo "   sudo reboot"
echo ""
