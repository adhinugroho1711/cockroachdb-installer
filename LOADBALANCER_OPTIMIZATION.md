# HAProxy + PgBouncer Server Optimization Summary

## 🎯 Purpose
This document explains the adaptive optimizations for the dedicated HAProxy and PgBouncer server.

## 📊 Adaptive Parameters

### 1. Kernel Parameters (`setup_loadbalancer_os.sh`)

All values are calculated based on **actual server RAM**, not hardcoded:

| RAM Size | Profile | somaxconn | file-max | TCP Buffer (max) |
|----------|---------|-----------|----------|------------------|
| <2GB | MINIMAL | 1,024 | 100,000 | 2 MB |
| 2-8GB | STANDARD | 4,096 | 200,000 | 8 MB |
| 8-16GB | OPTIMIZED | 8,192 | 500,000 | 16 MB |
| >16GB | HIGH_PERFORMANCE | 16,384 | 1,000,000 | 32 MB |

**Key Optimizations:**
- ✅ Connection queue (`somaxconn`, `tcp_max_syn_backlog`)
- ✅ File descriptors (`file-max`)
- ✅ TCP buffer sizes (`tcp_rmem`, `tcp_wmem`)
- ✅ TCP memory pages (`tcp_mem`)
- ✅ Connection tracking (`nf_conntrack_max`)
- ✅ Minimize swap (`vm.swappiness = 1`)
- ✅ Transparent Huge Pages (`madvise` mode)

### 2. HAProxy Configuration (`setup_haproxy.sh`)

**Adaptive Settings:**

```bash
# maxconn calculation
if RAM < 2GB:
    maxconn = 1,024
elif RAM < 4GB:
    maxconn = 4,096
elif RAM < 8GB:
    maxconn = 10,000
else:
    maxconn = RAM_MB / 2  (capped at 50,000)

# nbthread = CPU cores (utilize all available cores)
```

**Features:**
- ✅ Flexible node count (2+ nodes)
- ✅ Comma-separated IP input or one-by-one
- ✅ Optional stats authentication
- ✅ Least-connection load balancing (better than round-robin for CockroachDB)
- ✅ Adaptive timeouts based on RAM
- ✅ Multi-threaded (uses all CPU cores)

### 3. PgBouncer Configuration (`setup_pgbouncer.sh`)

**Adaptive Settings:**

```bash
# max_client_conn calculation based on RAM
if RAM < 1GB:
    max_client = 500
elif RAM < 2GB:
    max_client = 2,000
elif RAM < 4GB:
    max_client = 5,000
elif RAM < 8GB:
    max_client = 10,000
else:
    max_client = 20,000

# Pool size = CockroachDB vCPU × 4 (user-provided)
```

**Features:**
- ✅ RAM-based client limit recommendations
- ✅ Auto-calculate pool size from cluster vCPU
- ✅ Transaction pooling mode (optimal for CockroachDB)
- ✅ MD5 password hashing support
- ✅ Support for --insecure mode

## 🔧 Setup Order

```bash
# On HAProxy+PgBouncer Server:

# 1. OS optimization (MUST run first)
bash scripts/setup_loadbalancer_os.sh

# 2. Install HAProxy
bash scripts/setup_haproxy.sh
# → Will detect: 4GB RAM, 2 CPU
# → Apply: maxconn=4096, nbthread=2

# 3. Install PgBouncer (if >1000 connections)
bash scripts/setup_pgbouncer.sh
# → Will detect: 4GB RAM
# → Recommend: max_client_conn=5000
```

## 📈 Resource Calculations

### Memory Usage Estimates

**HAProxy:**
- Base process: ~50 MB
- Per connection: ~2 KB
- Example (4GB server, 4096 maxconn):
  - Memory: 50 MB + (4096 × 2 KB) = ~58 MB

**PgBouncer:**
- Base process: ~20 MB
- Per client connection: ~5 KB
- Per server connection: ~20 KB
- Example (5000 clients, 24 server pool):
  - Memory: 20 MB + (5000 × 5 KB) + (24 × 20 KB) = ~45 MB

**Total for Co-located Setup (4GB server):**
- HAProxy: ~58 MB
- PgBouncer: ~45 MB
- OS + overhead: ~500 MB
- **Total: ~600 MB** (leaves 3.4GB free)

### CPU Usage

**Idle/Low Load:**
- HAProxy: 2-5% CPU
- PgBouncer: 1-3% CPU

**High Load (1000+ active connections):**
- HAProxy: 10-20% CPU (distributed across all threads)
- PgBouncer: 5-10% CPU

## 🎯 Optimization Benefits

### Before Optimization (Hardcoded)
```
❌ maxconn = 4096 (same for all servers)
❌ timeout = 1m (same for all workloads)
❌ No CPU threading
❌ Default kernel limits
❌ Swap enabled
```

### After Optimization (Adaptive)
```
✅ maxconn = calculated per RAM (1K - 50K)
✅ timeout = adaptive (30s - 5m)
✅ Multi-threaded (uses all CPU cores)
✅ Tuned kernel for high-concurrency networking
✅ Swap disabled for consistent latency
✅ THP enabled in madvise mode
✅ Connection tracking optimized
```

## 🔒 Security Enhancements

**Firewall (automatic):**
```
Port 26257 - HAProxy SQL
Port 6432  - PgBouncer
Port 8081  - HAProxy Stats
Port 22    - SSH
```

**Optional HAProxy Stats Auth:**
- Username/password protection for `/stats`
- Disabled by default (can enable during setup)

## 📊 Monitoring

**HAProxy Stats Dashboard:**
```
http://<server-ip>:8081
```

**PgBouncer Stats:**
```bash
psql -h localhost -p 6432 -U root -d pgbouncer
pgbouncer=# SHOW POOLS;
pgbouncer=# SHOW STATS;
pgbouncer=# SHOW SERVERS;
```

**Kernel Stats:**
```bash
# Connection tracking
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max

# File descriptors
cat /proc/sys/fs/file-nr

# Network buffers
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem
```

## 🚨 Troubleshooting

**If connection refused:**
```bash
# Check HAProxy
sudo systemctl status haproxy
sudo tail -f /var/log/haproxy.log

# Check PgBouncer
sudo systemctl status pgbouncer
sudo journalctl -u pgbouncer -f
```

**If high latency:**
```bash
# Check connection pool saturation
psql -h localhost -p 6432 -U root -d pgbouncer
SHOW POOLS;  # Look for cl_waiting > 0

# Check HAProxy backend health
curl http://localhost:8081  # Check server status
```

**If running out of file descriptors:**
```bash
# Check current limits
ulimit -n

# Check kernel limit
cat /proc/sys/fs/file-max

# Should be set by setup_loadbalancer_os.sh
# Re-run if needed
```

## 📚 Reference

**Kernel Tuning Guide:**
- https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt

**HAProxy Best Practices:**
- https://www.haproxy.com/documentation/

**PgBouncer Configuration:**
- https://www.pgbouncer.org/config.html

**CockroachDB Connection Pooling:**
- https://www.cockroachlabs.com/docs/stable/connection-pooling
