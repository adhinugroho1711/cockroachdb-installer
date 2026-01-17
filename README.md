# CockroachDB Installer & SOP

Automated installation and optimization scripts for **CockroachDB** on resource-constrained environments (2GB RAM) with support for production scale-up.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CockroachDB](https://img.shields.io/badge/CockroachDB-v23.1.11-blue)](https://www.cockroachlabs.com/)
[![Platform](https://img.shields.io/badge/Platform-Linux-green)](https://www.linux.org/)

---

## 🎯 Features

- **Auto-Detection**: Automatically detects OS (Ubuntu/Debian/RHEL/Rocky), Architecture (x86_64/ARM64), and RAM
- **Dynamic Memory Tuning**: Allocates 25% RAM for cache and 25% for SQL memory automatically
- **Multi-Distro Support**: Works on Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux
- **HAProxy Integration**: Replaces traditional PgBouncer/Patroni stack with native load balancing
- **Migration Tools**: Complete guide for migrating from PostgreSQL using MOLT
- **Failover Testing**: Built-in procedures to validate cluster resilience
- **Interactive Checklist**: Web-based progress tracker with auto-save (open `index.html`)

---

## 📦 What's Included

```text
cockroachdb-installer/
├── README.md                      # This file
├── RELEASE_NOTES.md               # Version history & changelog
├── index.html                     # Interactive checklist & detailed guide
├── scripts/
│   ├── setup_os.sh                # OS optimization for CockroachDB nodes
│   ├── setup_cockroach.sh         # CockroachDB installation & systemd
│   ├── setup_loadbalancer_os.sh   # OS optimization for HAProxy+PgBouncer server
│   ├── setup_haproxy.sh           # HAProxy load balancer (adaptive config)
│   └── setup_pgbouncer.sh         # PgBouncer for >1000 connections (adaptive)
```

---

## 🚀 Quick Start

### 1. Provision Infrastructure (Multipass Example)

```bash
# Load Balancer Node
multipass launch lts --name lb --cpus 1 --memory 1G --disk 10G

# CockroachDB Nodes
multipass launch lts --name n1 --cpus 1 --memory 2G --disk 10G
multipass launch lts --name n2 --cpus 1 --memory 2G --disk 10G
multipass launch lts --name n3 --cpus 1 --memory 2G --disk 10G
```

### 2. Clone Repository

```bash
git clone https://github.com/adhinugroho1711/cockroachdb-installer.git
cd cockroachdb-installer
```

### 3. Run OS Optimization (on each node)

```bash
multipass transfer scripts/setup_os.sh n1:/home/ubuntu/
multipass shell n1
bash setup_os.sh
```

### 4. Install CockroachDB (on each node)

```bash
bash setup_cockroach.sh
```

**Important:** Edit `/etc/systemd/system/cockroach.service` to update:

- `--join=<IP_NODE1>,<IP_NODE2>,<IP_NODE3>`
- `--advertise-addr=<THIS_NODE_IP>`

Then start:

```bash
sudo systemctl start cockroach
sudo systemctl enable cockroach
```

### 5. Initialize Cluster (run once)

```bash
cockroach init --insecure --host=<IP_NODE_1>
```

### 5a. Optimize Load Balancer Server (HAProxy+PgBouncer server)

**Run this on the dedicated load balancer server (NOT on CockroachDB nodes):**

```bash
bash scripts/setup_loadbalancer_os.sh
```

This optimizes kernel parameters specifically for HAProxy and PgBouncer workload (high connection count, low latency networking).

### 6. Setup Load Balancer

```bash
bash scripts/setup_haproxy.sh
```

### 6a. Setup PgBouncer (For Production with >1000 connections)

**Only if your application has >1000 concurrent connections:**

```bash
bash scripts/setup_pgbouncer.sh
```

Then update your application to connect to PgBouncer (port 6432) instead of HAProxy (port 26257).

### 7. Open Interactive Guide

Open `index.html` in your browser for detailed step-by-step checklist with progress tracking.

---

## 📊 Architecture Transition (PostgreSQL → CockroachDB)

| Component             | PostgreSQL Stack          | CockroachDB Stack                  |
|-----------------------|---------------------------|------------------------------------|
| **HA Manager**        | Patroni + ETCD            | Native Raft Consensus              |
| **Load Balancer**     | HAProxy / Keepalived      | HAProxy (same)                     |
| **Connection Pool**   | PgBouncer (required)      | Client-side (HikariCP/pg-pool)     |
| **Replication**       | Streaming Replication     | Multi-Raft Ranges                  |
| **Failover**          | Manual/Semi-Automatic     | Fully Automatic (~9s)              |

---

## 🔧 System Requirements

### Minimum (Testing/Lab)

- **Nodes:** 3
- **RAM:** 2GB per node
- **CPU:** 2 cores per node
- **Storage:** 10GB (any)

### Production Recommended

- **Nodes:** 3+ (odd number for quorum)
- **RAM:** 8-16GB per node
- **CPU:** 4-8 cores per node
- **Storage:** SSD/NVMe (write-heavy workload)

---

## 🔌 Connection Pooling Strategy

### ⚠️ For Production: High Connection Load (>1000 concurrent)

If your production application has **>1000 concurrent connections**, you **MUST use PgBouncer**:

**Why?** CockroachDB supports max **4 active connections per vCPU**:
```
Example: 3 nodes × 1 CPU = 3 vCPU
Max recommended: 3 × 4 = 12 active connections
Your production: >1000 connections ❌ PROBLEM!
```

**Solution Architecture:**
```
Application (1000+ conn) → PgBouncer (24 conn) → HAProxy → CockroachDB
                           └─ 40x reduction ─┘
```

### Setup PgBouncer (for >1000 connections)

```bash
bash scripts/setup_pgbouncer.sh
```

**Key Configuration:**
- **Pool Mode:** `transaction` (most efficient for CockroachDB)
- **Pool Size:** `4 × total vCPU` (e.g., 12 for 3 vCPU cluster)
- **Max Client Connections:** `5000` (adjust based on your load)
- **Port:** `6432` (PgBouncer default)

**Application Connection String:**
```
postgresql://user:password@pgbouncer-ip:6432/database
```

---

### For Development/Low Load (<100 connections)

CockroachDB uses a **thread-based connection model** (vs PostgreSQL's process-per-connection), making each connection 300x more lightweight (~30KB vs 9MB).

✅ **Use client-side pooling** (in your application)  
❌ **No PgBouncer needed** for low-traffic scenarios

**Example (Node.js):**
```javascript
const { Pool } = require('pg');
const pool = new Pool({
  host: 'haproxy-ip',
  port: 26257,
  max: 20,  // 4x CPU cores
  idleTimeoutMillis: 300000,  // 5 minutes
});
```

**Example (Java with HikariCP):**
```java
HikariConfig config = new HikariConfig();
config.setMaximumPoolSize(20);
config.setMinimumIdle(20);  // Same as max
config.setMaxLifetime(300000);  // 5 minutes
```

---

### Decision Matrix: When to Use PgBouncer?

| Scenario | Use PgBouncer? | Reason |
|----------|----------------|--------|
| **>1000 concurrent connections** | ✅ **YES (REQUIRED)** | Exceeds CockroachDB connection limits |
| **Serverless (Lambda/Cloud Functions)** | ✅ **YES** | Can't maintain persistent pools |
| **Legacy apps (can't modify code)** | ✅ **YES** | No control over connection logic |
| **Development/Testing** | ❌ NO | Client-side pooling sufficient |
| **<100 concurrent connections** | ❌ NO | Adds unnecessary complexity |



## 📚 Documentation

- **Interactive Guide:** Open `index.html` in browser for complete walkthrough with checklist
- **Release Notes:** See [RELEASE_NOTES.md](./RELEASE_NOTES.md) for version history

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📝 License

This project is licensed under the MIT License.

---

## 👤 Author

### Adhi Nugroho

- GitHub: [@adhinugroho1711](https://github.com/adhinugroho1711)

---

## 🙏 Acknowledgments

- CockroachDB team for excellent distributed database
- MOLT tool for seamless PostgreSQL migration
- Community for testing and feedback
