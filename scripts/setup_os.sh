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
        sudo apt-get install -y ntp curl software-properties-common
        ;;
    centos|rhel|rocky|almalinux)
        sudo yum update -y
        sudo yum install -y ntp curl bind-utils
        ;;
    *)
        echo "OS $OS not explicitly supported, but will try to continue..."
        ;;
esac

# 3. Timezone & NTP
sudo timedatectl set-timezone Asia/Jakarta
if command -v systemctl >/dev/null; then
    sudo systemctl enable ntp || sudo systemctl enable chronyd || true
    sudo systemctl start ntp || sudo systemctl start chronyd || true
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

# 6. Kernel Tuning (sysctl)
# Adjust dynamic limits if needed, but standard CockroachDB values are generally robust
echo "Tuning kernel parameters..."
sudo mkdir -p /etc/sysctl.d
cat <<EOF | sudo tee /etc/sysctl.d/99-cockroach.conf
# Memory Tuning
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.overcommit_memory = 0

# File System
fs.file-max = 1000000

# Network Tuning
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.tcp_fin_timeout = 30
EOF

sudo sysctl -p /etc/sysctl.d/99-cockroach.conf

# 7. Disable Swap (Recommended for CockroachDB latency)
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
