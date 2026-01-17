#!/bin/bash

# SOP CockroachDB - PgBouncer Setup for High Connection Load
# Description: Setup PgBouncer for production environments with >1000 concurrent connections

set -e

echo "Starting PgBouncer Installation for CockroachDB..."

# 1. Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

# 2. Detect Server Specifications
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
# Display memory in GB with 1 decimal place precision
TOTAL_MEM_GB_DISPLAY=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MEM_MB/1024}")
TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))

echo "Detected Server Specs:"
echo "  - RAM: ${TOTAL_MEM_GB_DISPLAY}GB (${TOTAL_MEM_MB}MB)"
echo ""

# 3. Install PgBouncer
echo "Installing PgBouncer..."
case "$OS" in
    ubuntu|debian)
        sudo apt-get update
        sudo apt-get install -y pgbouncer
        ;;
    centos|rhel|rocky|almalinux)
        sudo yum install -y pgbouncer
        ;;
    *)
        echo "ERROR: OS $OS not supported for automatic PgBouncer installation"
        exit 1
        ;;
esac

# 4. Calculate adaptive limits based on RAM
# PgBouncer uses ~5KB per client connection + ~20KB per server connection
# Safe formula: (RAM_MB - 512) / 0.005 KB per connection

if [ "$TOTAL_MEM_MB" -lt 1024 ]; then
    # <1GB RAM - not recommended for PgBouncer
    RECOMMENDED_MAX_CLIENT=500
    echo "⚠️  WARNING: ${TOTAL_MEM_GB_DISPLAY}GB RAM is low for PgBouncer"
elif [ "$TOTAL_MEM_MB" -lt 2048 ]; then
    # 1-2GB RAM
    RECOMMENDED_MAX_CLIENT=2000
elif [ "$TOTAL_MEM_MB" -lt 4096 ]; then
    # 2-4GB RAM
    RECOMMENDED_MAX_CLIENT=5000
elif [ "$TOTAL_MEM_MB" -lt 8192 ]; then
    # 4-8GB RAM
    RECOMMENDED_MAX_CLIENT=10000
else
    # >8GB RAM
    RECOMMENDED_MAX_CLIENT=20000
fi

echo "Recommended max client connections for ${TOTAL_MEM_GB_DISPLAY}GB RAM: $RECOMMENDED_MAX_CLIENT"
echo ""

# 5. Interactive Configuration
echo "=============================================="
echo "  PGBOUNCER CONFIGURATION"
echo "=============================================="
echo ""

# Get HAProxy IP (or first CockroachDB node IP)
read -p "Enter HAProxy IP (or CockroachDB node IP) [localhost]: " CRDB_HOST
CRDB_HOST=${CRDB_HOST:-localhost}

read -p "Enter CockroachDB port [26257]: " CRDB_PORT
CRDB_PORT=${CRDB_PORT:-26257}

read -p "Enter database name [defaultdb]: " DATABASE
DATABASE=${DATABASE:-defaultdb}

read -p "Enter database user [root]: " DB_USER
DB_USER=${DB_USER:-root}

read -p "Enter database password (press Enter if using --insecure mode): " DB_PASSWORD

# Calculate pool size based on CockroachDB cluster
read -p "Total vCPU in CockroachDB cluster (e.g., 3 nodes × 2 CPU = 6): " TOTAL_VCPU
TOTAL_VCPU=${TOTAL_VCPU:-6}

# Recommended: 4 connections per vCPU
DEFAULT_POOL_SIZE=$((TOTAL_VCPU * 4))

read -p "PgBouncer pool size per database [${DEFAULT_POOL_SIZE}]: " POOL_SIZE
POOL_SIZE=${POOL_SIZE:-$DEFAULT_POOL_SIZE}

read -p "Maximum client connections [${RECOMMENDED_MAX_CLIENT}]: " MAX_CLIENT_CONN
MAX_CLIENT_CONN=${MAX_CLIENT_CONN:-$RECOMMENDED_MAX_CLIENT}

echo ""
echo "Configuration Summary:"
echo "  - CockroachDB Host: ${CRDB_HOST}:${CRDB_PORT}"
echo "  - Database: ${DATABASE}"
echo "  - User: ${DB_USER}"
echo "  - Pool Size: ${POOL_SIZE} connections to CockroachDB"
echo "  - Max Clients: ${MAX_CLIENT_CONN} concurrent client connections"
echo ""

# 4. Backup existing config
if [ -f /etc/pgbouncer/pgbouncer.ini ]; then
    sudo cp /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini.bak.$(date +%s)
    echo "Backed up existing config"
fi

# 5. Create PgBouncer configuration
echo "Creating PgBouncer configuration..."
cat <<EOF | sudo tee /etc/pgbouncer/pgbouncer.ini
[databases]
${DATABASE} = host=${CRDB_HOST} port=${CRDB_PORT} dbname=${DATABASE}

[pgbouncer]
# Connection settings
listen_addr = *
listen_port = 6432

# Authentication
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Connection pooling
pool_mode = transaction
max_client_conn = ${MAX_CLIENT_CONN}
default_pool_size = ${POOL_SIZE}
reserve_pool_size = $((POOL_SIZE / 2))
reserve_pool_timeout = 5

# Connection limits per user
max_db_connections = ${POOL_SIZE}
max_user_connections = ${MAX_CLIENT_CONN}

# Timeouts (in seconds)
server_idle_timeout = 600
server_lifetime = 1800
server_connect_timeout = 15
query_timeout = 0
query_wait_timeout = 120

# Logging
admin_users = ${DB_USER}
stats_users = ${DB_USER}
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1

# Performance
server_reset_query = DISCARD ALL
server_check_delay = 30
server_check_query = SELECT 1

# Compatibility for CockroachDB
ignore_startup_parameters = extra_float_digits,options

# TLS/SSL (if using secure mode)
# server_tls_sslmode = require
# server_tls_ca_file = /var/lib/cockroach/certs/ca.crt
EOF

# 6. Create userlist.txt (authentication file)
echo "Creating user authentication file..."
if [ -z "$DB_PASSWORD" ]; then
    # For --insecure mode, use empty password
    echo "\"${DB_USER}\" \"\"" | sudo tee /etc/pgbouncer/userlist.txt
else
    # For secure mode, hash the password (MD5)
    # Format: "username" "md5<md5(password + username)>"
    PASSWORD_HASH=$(echo -n "${DB_PASSWORD}${DB_USER}" | md5sum | awk '{print $1}')
    echo "\"${DB_USER}\" \"md5${PASSWORD_HASH}\"" | sudo tee /etc/pgbouncer/userlist.txt
fi

sudo chmod 640 /etc/pgbouncer/userlist.txt
sudo chown postgres:postgres /etc/pgbouncer/userlist.txt 2>/dev/null || true

# 7. Create systemd service (if not exists)
if [ ! -f /etc/systemd/system/pgbouncer.service ]; then
    echo "Creating systemd service..."
    cat <<EOF | sudo tee /etc/systemd/system/pgbouncer.service
[Unit]
Description=PgBouncer Connection Pooler for CockroachDB
After=network.target

[Service]
Type=forking
User=postgres
ExecStart=/usr/bin/pgbouncer -d /etc/pgbouncer/pgbouncer.ini
ExecReload=/bin/kill -HUP \$MAINPID
KillSignal=SIGINT
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
fi

# 8. Skip explicit test as many pgbouncer versions don't support -t
echo "PgBouncer configuration generated at /etc/pgbouncer/pgbouncer.ini"
echo "✅ Setup steps completed"

echo ""
echo "=============================================="
echo "  ✅ PgBouncer Installation Complete!"
echo "=============================================="
echo ""
echo "Next Steps:"
echo "1. Start PgBouncer:"
echo "   sudo systemctl start pgbouncer"
echo "   sudo systemctl enable pgbouncer"
echo ""
echo "2. Verify PgBouncer is running:"
echo "   sudo systemctl status pgbouncer"
echo "   netstat -tlnp | grep 6432"
echo ""
echo "3. Test connection through PgBouncer:"
echo "   psql -h localhost -p 6432 -U ${DB_USER} -d ${DATABASE}"
echo ""
echo "4. Monitor PgBouncer stats (connect to pgbouncer database):"
echo "   psql -h localhost -p 6432 -U ${DB_USER} -d pgbouncer"
echo "   pgbouncer=# SHOW POOLS;"
echo "   pgbouncer=# SHOW STATS;"
echo ""
echo "5. Update your application connection string:"
echo "   Host: <pgbouncer-ip>"
echo "   Port: 6432"
echo "   Database: ${DATABASE}"
echo ""
echo "Configuration files:"
echo "  - Main config: /etc/pgbouncer/pgbouncer.ini"
echo "  - User auth: /etc/pgbouncer/userlist.txt"
echo ""
echo "⚠️  IMPORTANT for Production:"
echo "  - Pool ratio: ${MAX_CLIENT_CONN} clients → ${POOL_SIZE} CockroachDB connections"
echo "  - This is a $(( MAX_CLIENT_CONN / POOL_SIZE ))x reduction in database connections"
echo "  - Monitor 'SHOW POOLS' to ensure pools aren't saturated"
echo ""
