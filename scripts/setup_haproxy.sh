#!/bin/bash

# SOP CockroachDB - HAProxy Setup Script
# Description: Load Balancer untuk mendistribusikan traffic SQL ke 3 node
# Pengganti konsep PgBouncer/Patroni dalam ekosistem CockroachDB

set -e

echo "Starting HAProxy Installation for CockroachDB..."

# 1. Install HAProxy
if command -v apt-get >/dev/null; then
    sudo apt-get update && sudo apt-get install -y haproxy
elif command -v yum >/dev/null; then
    sudo yum install -y haproxy
fi

# 2. Prompt for Node IPs
echo ""
echo "Please enter the IP addresses of your CockroachDB nodes:"
read -p "Node 1 IP: " NODE1_IP
read -p "Node 2 IP: " NODE2_IP
read -p "Node 3 IP: " NODE3_IP

echo "Configuring HAProxy with nodes: $NODE1_IP, $NODE2_IP, $NODE3_IP"
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
global
    maxconn 4096

defaults
    mode tcp
    timeout connect 10s
    timeout client 1m
    timeout server 1m

listen cockroachdb
    bind :26257
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check send-binary 50524f544f434f4c20434f4e4e4543542053514c0a
    tcp-check expect string SQL
    server node1 ${NODE1_IP}:26257 check
    server node2 ${NODE2_IP}:26257 check
    server node3 ${NODE3_IP}:26257 check

listen stats
    bind :8081
    mode http
    stats enable
    stats uri /
    stats refresh 5s
EOF

# 3. Restart HAProxy
sudo systemctl restart haproxy
sudo systemctl enable haproxy

echo "HAProxy Setup Complete."
echo "SQL traffic can now be directed to this server on port 26257."
echo "Monitoring HAProxy stats available at http://localhost:8081"
