#!/bin/bash

# SOP CockroachDB - HAProxy Setup Script (Adaptive Configuration)
# Description: Load Balancer untuk mendistribusikan traffic SQL ke CockroachDB nodes

set -e

echo "Starting HAProxy Installation for CockroachDB..."

# 1. Detect server specifications
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
# Display memory in GB with 1 decimal place precision
TOTAL_MEM_GB_DISPLAY=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MEM_MB/1024}")
TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))
CPU_CORES=$(nproc)

echo "Detected Server Specs:"
echo "  - RAM: ${TOTAL_MEM_GB_DISPLAY}GB (${TOTAL_MEM_MB}MB)"
echo "  - CPU Cores: ${CPU_CORES}"
echo ""

# 2. Calculate adaptive HAProxy settings
# maxconn formula: min(RAM_MB / 2, 50000) 
# Each connection uses ~2KB RAM in HAProxy
if [ "$TOTAL_MEM_MB" -lt 2048 ]; then
    # <2GB RAM
    MAXCONN=1024
    TIMEOUT_CLIENT="30s"
    TIMEOUT_SERVER="30s"
elif [ "$TOTAL_MEM_MB" -lt 4096 ]; then
    # 2-4GB RAM
    MAXCONN=4096
    TIMEOUT_CLIENT="1m"
    TIMEOUT_SERVER="1m"
elif [ "$TOTAL_MEM_MB" -lt 8192 ]; then
    # 4-8GB RAM
    MAXCONN=10000
    TIMEOUT_CLIENT="2m"
    TIMEOUT_SERVER="2m"
else
    # >8GB RAM
    MAXCONN=$((TOTAL_MEM_MB / 2))
    # Cap at reasonable limit
    if [ "$MAXCONN" -gt 50000 ]; then
        MAXCONN=50000
    fi
    TIMEOUT_CLIENT="5m"
    TIMEOUT_SERVER="5m"
fi

echo "Calculated HAProxy Configuration:"
echo "  - Max Connections: $MAXCONN"
echo "  - Client Timeout: $TIMEOUT_CLIENT"
echo "  - Server Timeout: $TIMEOUT_SERVER"
echo ""

# 3. Install HAProxy
if command -v apt-get >/dev/null; then
    sudo apt-get update && sudo apt-get install -y haproxy
elif command -v yum >/dev/null; then
    sudo yum install -y haproxy
fi

# 4. Interactive: Get CockroachDB node IPs
echo ""
echo "CockroachDB Cluster Configuration:"
echo "You can enter IPs separated by comma or one by one"
echo ""

read -p "Enter all node IPs (comma-separated) OR press Enter to input one by one: " NODES_INPUT

if [ -n "$NODES_INPUT" ]; then
    # Parse comma-separated input
    IFS=',' read -ra NODE_IPS <<< "$NODES_INPUT"
    # Trim whitespace
    for i in "${!NODE_IPS[@]}"; do
        NODE_IPS[$i]=$(echo "${NODE_IPS[$i]}" | xargs)
    done
else
    # Input one by one
    read -p "Node 1 IP: " NODE1_IP
    read -p "Node 2 IP: " NODE2_IP
    read -p "Node 3 IP (press Enter if only 2 nodes): " NODE3_IP
    
    NODE_IPS=("$NODE1_IP" "$NODE2_IP")
    if [ -n "$NODE3_IP" ]; then
        NODE_IPS+=("$NODE3_IP")
    fi
fi

# 5. Optional: Stats authentication
read -p "Enable HAProxy stats authentication? (y/N): " ENABLE_AUTH
if [[ "$ENABLE_AUTH" =~ ^[Yy]$ ]]; then
    read -p "Stats username [admin]: " STATS_USER
    STATS_USER=${STATS_USER:-admin}
    read -sp "Stats password: " STATS_PASS
    echo ""
    STATS_AUTH="stats auth ${STATS_USER}:${STATS_PASS}"
else
    STATS_AUTH=""
fi

# 6. Generate HAProxy config
echo ""
echo "Generating HAProxy configuration..."

cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
# HAProxy Configuration for CockroachDB
# Auto-generated for ${TOTAL_MEM_GB_DISPLAY}GB RAM, ${CPU_CORES} CPU cores
# Generated: $(date)

global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Adaptive max connections ($MAXCONN for ${TOTAL_MEM_GB_DISPLAY}GB RAM)
    maxconn $MAXCONN
    
    # Performance tuning
    tune.bufsize 32768
    tune.maxrewrite 1024
    nbthread $CPU_CORES

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 10s
    timeout client  $TIMEOUT_CLIENT
    timeout server  $TIMEOUT_SERVER
    timeout check   5s

# CockroachDB SQL Backend
listen cockroachdb
    bind *:26257
    mode tcp
    balance roundrobin
    option tcp-check
    
    # CockroachDB health check (PostgreSQL wire protocol handshake)
    tcp-check send-binary 50524f544f434f4c20434f4e4e4543542053514c0a
    tcp-check expect string SQL
    
    # Backend servers
EOF

# Add each node to config
NODE_COUNT=1
for NODE_IP in "${NODE_IPS[@]}"; do
    echo "    server node${NODE_COUNT} ${NODE_IP}:26257 check inter 5s fall 3 rise 2" | sudo tee -a /etc/haproxy/haproxy.cfg
    ((NODE_COUNT++))
done

# Add stats interface
cat <<EOF | sudo tee -a /etc/haproxy/haproxy.cfg

# HAProxy Statistics Dashboard
listen stats
    bind *:8081
    mode http
    stats enable
    stats uri /
    stats refresh 10s
    stats show-node
    stats show-legends
    $STATS_AUTH
EOF

# 7. Verify configuration
echo ""
echo "Verifying HAProxy configuration..."
if sudo haproxy -c -f /etc/haproxy/haproxy.cfg; then
    echo "✅ Configuration valid"
else
    echo "❌ Configuration has errors!"
    exit 1
fi

# 8. Restart HAProxy
sudo systemctl restart haproxy
sudo systemctl enable haproxy

# 9. Show status
echo ""
echo "=========================================="
echo "  ✅ HAProxy Setup Complete!"
echo "=========================================="
echo ""
echo "Configuration Summary:"
echo "  - Backend Nodes: ${#NODE_IPS[@]}"
for i in "${!NODE_IPS[@]}"; do
    echo "    Node $((i+1)): ${NODE_IPS[$i]}:26257"
done
echo "  - Max Connections: $MAXCONN"
echo "  - Load Balancing: Round Robin (CockroachDB recommended)"
echo ""
echo "Access Points:"
echo "  - SQL Traffic: <this-server-ip>:26257"
echo "  - Stats Dashboard: http://<this-server-ip>:8081"
echo ""
echo "Test Connection:"
echo "  cockroach sql --insecure --host=<this-server-ip> --port=26257"
echo ""
echo "Monitor HAProxy:"
echo "  sudo systemctl status haproxy"
echo "  sudo tail -f /var/log/haproxy.log"
echo ""
