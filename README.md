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

## 🌐 Multi-Site Quick Start (2+3 Architecture)

For **2-site disaster recovery** with automatic failover, follow these steps:

### Infrastructure Overview

```
Site A (Primary):  2 CockroachDB nodes + 1 Load Balancer
Site B (DR):       3 CockroachDB nodes (2 full + 1 witness) + 1 Load Balancer
Total:             7 servers
```

---

### Step 1: Provision Infrastructure

#### **Site A (Primary)**
```bash
# CockroachDB Nodes (Full)
multipass launch lts --name n1 --cpus 2 --memory 4G --disk 20G
multipass launch lts --name n2 --cpus 2 --memory 4G --disk 20G

# Load Balancer
multipass launch lts --name lb-a --cpus 1 --memory 1G --disk 10G
```

#### **Site B (DR)**
```bash
# CockroachDB Nodes (Full)
multipass launch lts --name n3 --cpus 2 --memory 4G --disk 20G
multipass launch lts --name n4 --cpus 2 --memory 4G --disk 20G

# Witness Node (Lightweight - voting only)
multipass launch lts --name n5 --cpus 1 --memory 1G --disk 10G

# Load Balancer
multipass launch lts --name lb-b --cpus 1 --memory 1G --disk 10G
```

---

### Step 2: Clone Repository (Both Sites)

```bash
git clone https://github.com/adhinugroho1711/cockroachdb-installer.git
cd cockroachdb-installer
```

---

### Step 3: Install CockroachDB

#### **Site A: Node 1 & Node 2**
```bash
# On each node (n1, n2)
bash scripts/setup_os.sh
bash scripts/setup_cockroach.sh
```

**Edit `/etc/systemd/system/cockroach.service`:**
```bash
# Node 1
--join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP>,<NODE5_IP>
--advertise-addr=<NODE1_IP>
--locality=site=a,rack=1

# Node 2
--join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP>,<NODE5_IP>
--advertise-addr=<NODE2_IP>
--locality=site=a,rack=2
```

#### **Site B: Node 3, 4, 5**
```bash
# On each node (n3, n4, n5)
bash scripts/setup_os.sh
bash scripts/setup_cockroach.sh
```

**Edit `/etc/systemd/system/cockroach.service`:**
```bash
# Node 3 (Full)
--join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP>,<NODE5_IP>
--advertise-addr=<NODE3_IP>
--locality=site=b,rack=1

# Node 4 (Full)
--join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP>,<NODE5_IP>
--advertise-addr=<NODE4_IP>
--locality=site=b,rack=2

# Node 5 (Witness)
--join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP>,<NODE5_IP>
--advertise-addr=<NODE5_IP>
--locality=site=b,rack=3
```

---

### Step 4: Start Cluster (All Nodes)

```bash
# On all nodes (n1, n2, n3, n4, n5)
sudo systemctl start cockroach
sudo systemctl enable cockroach
```

**Initialize cluster (run once from any node):**
```bash
cockroach init --certs-dir=/var/lib/cockroach/certs --host=<NODE1_IP>
```

---

### Step 5: Configure Replication Preferences

```sql
-- Connect to any node
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE1_IP>

-- Set replication preferences
ALTER DATABASE defaultdb CONFIGURE ZONE USING 
  num_replicas = 3,
  constraints = '{"+site=a": 2, "+site=b": 1}',
  lease_preferences = '[[+site=a]]';
```

**Explanation:**
- 2 replicas in Site A (low latency writes)
- 1 replica in Site B (disaster recovery)
- Node 5 (witness) only votes, doesn't store data

---

### Step 6: Setup Load Balancers

#### **Site A: LB-A (Primary)**
```bash
# On lb-a
bash scripts/setup_loadbalancer_os.sh
bash scripts/setup_haproxy.sh
```

**HAProxy Backend (prioritize local nodes):**
- Primary: Node 1, Node 2
- Backup: Node 3, Node 4

#### **Site B: LB-B (Standby)**
```bash
# On lb-b
bash scripts/setup_loadbalancer_os.sh
bash scripts/setup_haproxy.sh
```

**HAProxy Backend (prioritize local nodes):**
- Primary: Node 3, Node 4, Node 5
- Backup: Node 1, Node 2

---

### Step 7: Application Connection

**Primary (Normal Operation):**
```
postgresql://user:pass@lb-a:26257/defaultdb
```

**Failover (Site A Down):**
```
postgresql://user:pass@lb-b:26257/defaultdb
```

**Best Practice - Multi-Host Connection:**
```
postgresql://user:pass@lb-a:26257,lb-b:26257/defaultdb?target_session_attrs=read-write
```

---

### Step 8: Test Failover

```bash
# Stop Site A nodes
sudo systemctl stop cockroach  # On Node 1
sudo systemctl stop cockroach  # On Node 2

# Verify cluster still online (3/5 quorum from Site B)
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP> -e "SELECT 1;"

# Expected: Success! Automatic failover in ~5-10 seconds
```

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


## 🌐 Multi-Site Disaster Recovery (2-Site Architecture)

### Architecture Overview: 2+3 (Asymmetric with Witness)

For organizations with **2 physical sites** where Site B is always-on DR, deploy 5 nodes total:

```
┌─────────────────────────┐         ┌─────────────────────────────────┐
│      Site A (Primary)   │         │      Site B (DR - Always On)    │
├─────────────────────────┤         ├─────────────────────────────────┤
│ Node 1 (site=a,rack=1)  │◄───────►│ Node 3 (site=b,rack=1)          │
│ Node 2 (site=a,rack=2)  │  Raft   │ Node 4 (site=b,rack=2)          │
│ HAProxy (Primary)       │         │ Node 5 (site=b,rack=3) Witness  │
└─────────────────────────┘         │ HAProxy (Standby)               │
         ▲                           └─────────────────────────────────┘
         │                                    ▲
    Application                          Application
   (Primary Path)                       (Failover Path)
```

**Deployment:**
- **Site A**: 2 full nodes (primary workload)
- **Site B**: 3 nodes (2 full + 1 witness)
- **Total**: 5 nodes
- **Quorum**: 3/5 (majority)

**Witness Node Specs (Minimal):**
- CPU: 1 core
- RAM: 1GB
- Disk: 10GB
- Purpose: Voting only, no data storage

### Setup: Locality Configuration

Add `--locality` flag to each node's systemd service:

**Site A (Node 1 & 2):**
```bash
--locality=site=a,rack=1  # Node 1
--locality=site=a,rack=2  # Node 2
```

**Site B (Node 3, 4, 5):**
```bash
--locality=site=b,rack=1  # Node 3
--locality=site=b,rack=2  # Node 4
--locality=site=b,rack=3  # Node 5 (Witness)
```

### Replication Preferences

Prioritize Site A for write performance:

```sql
ALTER DATABASE defaultdb CONFIGURE ZONE USING 
  num_replicas = 3,
  constraints = '{"+site=a": 2, "+site=b": 1}',
  lease_preferences = '[[+site=a]]';
```

**Explanation:**
- `num_replicas = 3`: Keep 3 copies of data (out of 5 nodes)
- `constraints`: 2 replicas in Site A, 1 in Site B (Node 3 or 4)
- `lease_preferences`: Prefer Site A for leaseholder (write coordinator)
- Node 5 (witness) only participates in voting, doesn't store data

---

### Failover Scenarios

| Scenario | Nodes Down | Quorum | Auto-Failover? | Downtime |
|----------|------------|--------|----------------|----------|
| 1 node down (any) | 1/5 | 4/5 ✅ | ✅ Yes | ~5-10s |
| **Site A down (Node 1+2)** | 2/5 | **3/5 ✅** | ✅ **YES** | ~5-10s |
| Node 5 (witness) down | 1/5 | 4/5 ✅ | ✅ Yes | ~5-10s |

**Key Advantage:**
- ✅ **Automatic failover** when Site A goes down completely
- ✅ Site B (3 nodes) maintains quorum without manual intervention
- ✅ Zero manual steps during disaster

---

### Automatic Failover: Site A Complete Failure

**What Happens Automatically:**

1. **Detection** (~3-5 seconds)
   - Raft detects Node 1 & 2 are unreachable
   - Remaining nodes (3, 4, 5) still have 3/5 quorum ✅

2. **Leader Election** (~2-4 seconds)
   - New leaseholder elected from Site B (Node 3 or 4)
   - Cluster continues accepting writes

3. **HAProxy Failover** (~1-2 seconds)
   - HAProxy marks Node 1 & 2 as DOWN
   - Routes all traffic to Node 3 & 4

**Total Downtime:** ~5-10 seconds (fully automatic)

**Application Action Required:**
- Update connection string from `haproxy-site-a:26257` to `haproxy-site-b:26257`
- Or use DNS CNAME for zero-touch failover

---

### Recovery: Site A Rejoin (Zero Downtime)

**Step 1: Wipe Old Data**
```bash
# On Node 1 & Node 2
sudo systemctl stop cockroach
sudo rm -rf /var/lib/cockroach/cockroach-data/*
# DO NOT delete /var/lib/cockroach/certs/
```

**Step 2: Rejoin as New Nodes**
```bash
cockroach start \
  --certs-dir=/var/lib/cockroach/certs \
  --advertise-addr=<NODE1_IP> \
  --join=<NODE3_IP>,<NODE4_IP>,<NODE5_IP> \
  --locality=site=a,rack=1
```

**Step 3: Restore Replication Preferences**
```sql
ALTER DATABASE defaultdb CONFIGURE ZONE USING 
  num_replicas = 3,
  constraints = '{"+site=a": 2, "+site=b": 1}',
  lease_preferences = '[[+site=a]]';
```

**Step 4: Update Application Connection**
```bash
# Back to Site A (primary)
# From: haproxy-site-b:26257
# To:   haproxy-site-a:26257
```

**Result:** Back to 2+3 topology (Node 6, 7, 3, 4, 5) ✅  
**Downtime:** 0 minutes (cluster was online during entire recovery)

---

### Testing Procedures

**Test 1: Single Node Failure**
```bash
sudo systemctl stop cockroach  # On Node 1
# Cluster should remain online (4/5 quorum)
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE2_IP> -e "SELECT 1;"
```

**Test 2: Complete Site A Failover (Automatic)**
```bash
# Stop Site A
sudo systemctl stop cockroach  # Node 1
sudo systemctl stop cockroach  # Node 2

# Wait 5-10 seconds - cluster should auto-failover
# Verify cluster online from Site B
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP> -e "SELECT 1;"

# Check node status
cockroach node status --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP>
```

**Test 3: Site A Recovery**
```bash
# Follow recovery steps above
# Verify all 5 nodes online
cockroach node status --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP>
```

**Expected Results:**
- Test 1: Auto-failover in ~5-10 seconds
- Test 2: Auto-failover in ~5-10 seconds (no manual intervention)
- Test 3: Zero downtime recovery

---

---

## 📚 Documentation

- **Interactive Guide:** Open `index.html` in browser for complete walkthrough with checklist
- **Multi-Site DR:** See section above for 2-site disaster recovery procedures

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
