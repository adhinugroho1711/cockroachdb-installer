# 🌐 Multi-Site Disaster Recovery Guide

## Overview

This guide covers **2-Site Disaster Recovery** setup for CockroachDB without cloud/third-site access.

**Architecture:** 2+2 (Symmetric)
- Site A: 2 nodes (Primary)
- Site B: 2 nodes (DR)
- Total: 4 nodes

---

## 🏗️ Architecture Diagram

```
┌─────────────────────────┐         ┌─────────────────────────┐
│      Site A (Primary)   │         │      Site B (DR)        │
├─────────────────────────┤         ├─────────────────────────┤
│ Node 1 (site=a,rack=1)  │◄───────►│ Node 3 (site=b,rack=1)  │
│ Node 2 (site=a,rack=2)  │  Raft   │ Node 4 (site=b,rack=2)  │
│ HAProxy (Primary)       │         │ HAProxy (Standby)       │
└─────────────────────────┘         └─────────────────────────┘
         ▲                                    ▲
         │                                    │
    Application                          Application
   (Primary Path)                       (Failover Path)
```

---

## 📋 Initial Setup

### 1. Deploy Nodes with Locality

**Node 1 (Site A):**
```bash
cockroach start \
  --certs-dir=/var/lib/cockroach/certs \
  --advertise-addr=<NODE1_IP> \
  --join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP> \
  --locality=site=a,rack=1 \
  --cache=25% \
  --max-sql-memory=25%
```

**Node 2 (Site A):**
```bash
cockroach start \
  --certs-dir=/var/lib/cockroach/certs \
  --advertise-addr=<NODE2_IP> \
  --join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP> \
  --locality=site=a,rack=2 \
  --cache=25% \
  --max-sql-memory=25%
```

**Node 3 (Site B):**
```bash
cockroach start \
  --certs-dir=/var/lib/cockroach/certs \
  --advertise-addr=<NODE3_IP> \
  --join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP> \
  --locality=site=b,rack=1 \
  --cache=25% \
  --max-sql-memory=25%
```

**Node 4 (Site B):**
```bash
cockroach start \
  --certs-dir=/var/lib/cockroach/certs \
  --advertise-addr=<NODE4_IP> \
  --join=<NODE1_IP>,<NODE2_IP>,<NODE3_IP>,<NODE4_IP> \
  --locality=site=b,rack=2 \
  --cache=25% \
  --max-sql-memory=25%
```

### 2. Initialize Cluster (Run Once)

```bash
cockroach init --certs-dir=/var/lib/cockroach/certs --host=<NODE1_IP>
```

### 3. Configure Replication Preferences

```sql
-- Prioritize Site A for better write performance
ALTER DATABASE defaultdb CONFIGURE ZONE USING 
  num_replicas = 3,
  constraints = '{"+site=a": 2, "+site=b": 1}',
  lease_preferences = '[[+site=a]]';
```

**Explanation:**
- `num_replicas = 3`: Keep 3 copies of data (out of 4 nodes)
- `constraints = '{"+site=a": 2}'`: 2 replicas must be in Site A
- `lease_preferences = '[[+site=a]]'`: Prefer Site A for leaseholder (write coordinator)

---

## 🔥 Runbook: Site A Complete Failure

### Phase 1: Emergency Failover (Site A → Site B)

#### Initial State
```
Site A: Node 1 ❌, Node 2 ❌ (DOWN)
Site B: Node 3 ✅, Node 4 ✅ (UP)
Status: Cluster OFFLINE (2/4 quorum insufficient)
```

#### Step 1: Spin Up Temporary Node 5

```bash
# On a temporary server in Site B
cockroach start \
  --certs-dir=/var/lib/cockroach/certs \
  --advertise-addr=<NODE5_IP> \
  --join=<NODE3_IP>,<NODE4_IP> \
  --locality=site=b,rack=3 \
  --cache=25% \
  --max-sql-memory=25%
```

#### Step 2: Decommission Dead Nodes (Site A)

```bash
# From Node 3 or Node 4
cockroach node decommission 1 2 \
  --certs-dir=/var/lib/cockroach/certs \
  --host=<NODE3_IP>
```

**Wait for decommission to complete:**
```bash
cockroach node status \
  --certs-dir=/var/lib/cockroach/certs \
  --host=<NODE3_IP>
```

#### Step 3: Verify Cluster Health

```bash
# Check cluster status
cockroach node status \
  --certs-dir=/var/lib/cockroach/certs \
  --host=<NODE3_IP>

# Should show: Node 3, 4, 5 = LIVE (3/3 quorum ✅)
```

#### Step 4: Update Application Connection

```bash
# Update application connection string
# From: postgresql://user:pass@haproxy-site-a:26257/db
# To:   postgresql://user:pass@haproxy-site-b:26257/db
```

**Status After Failover:**
```
Site A: Node 1 ❌, Node 2 ❌ (Decommissioned)
Site B: Node 3 ✅, Node 4 ✅, Node 5 ✅ (ACTIVE)
Status: Cluster ONLINE ✅
Downtime: ~5-15 minutes
```

---

## 🔄 Runbook: Site A Recovery

### Phase 2: Site A Rejoin (After Hardware Restored)

#### Initial State
```
Site A: Node 1 🔄, Node 2 🔄 (Hardware UP, not in cluster)
Site B: Node 3 ✅, Node 4 ✅, Node 5 ✅ (Cluster active)
```

#### Step 1: Wipe Old Data on Site A Nodes

```bash
# On Node 1 (Site A)
sudo systemctl stop cockroach
sudo rm -rf /var/lib/cockroach/cockroach-data/*
# DO NOT delete /var/lib/cockroach/certs/

# On Node 2 (Site A)
sudo systemctl stop cockroach
sudo rm -rf /var/lib/cockroach/cockroach-data/*
```

**⚠️ WARNING:** Old data is invalid because cluster continued without them.

#### Step 2: Rejoin Node 1 & Node 2 as New Nodes

```bash
# On Node 1 (Site A)
cockroach start \
  --certs-dir=/var/lib/cockroach/certs \
  --advertise-addr=<NODE1_IP> \
  --join=<NODE3_IP>,<NODE4_IP>,<NODE5_IP> \
  --locality=site=a,rack=1 \
  --cache=25% \
  --max-sql-memory=25%

# On Node 2 (Site A)
cockroach start \
  --certs-dir=/var/lib/cockroach/certs \
  --advertise-addr=<NODE2_IP> \
  --join=<NODE3_IP>,<NODE4_IP>,<NODE5_IP> \
  --locality=site=a,rack=2 \
  --cache=25% \
  --max-sql-memory=25%
```

**Note:** They will get new Node IDs (e.g., Node 6 & Node 7).

#### Step 3: Monitor Rebalancing

```bash
# Watch replication progress
watch -n 5 'cockroach node status --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP>'

# Check range distribution
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP> \
  -e "SELECT * FROM crdb_internal.ranges LIMIT 10;"
```

**Rebalancing Time Estimates:**
- 10GB: ~5-10 minutes
- 100GB: ~30-60 minutes
- 1TB: ~several hours

#### Step 4: Decommission Temporary Node 5

```bash
# After Node 1 & 2 (now Node 6 & 7) are fully synced
cockroach node decommission 5 \
  --certs-dir=/var/lib/cockroach/certs \
  --host=<NODE3_IP>

# Wait for status = "decommissioned"
cockroach node status \
  --certs-dir=/var/lib/cockroach/certs \
  --host=<NODE3_IP>

# Then stop Node 5
sudo systemctl stop cockroach  # On Node 5
```

#### Step 5: Restore Replication Preferences

```sql
-- Restore Site A as primary
ALTER DATABASE defaultdb CONFIGURE ZONE USING 
  num_replicas = 3,
  constraints = '{"+site=a": 2, "+site=b": 1}',
  lease_preferences = '[[+site=a]]';
```

#### Step 6: Update Application Connection (Back to Site A)

```bash
# Update application connection string
# From: postgresql://user:pass@haproxy-site-b:26257/db
# To:   postgresql://user:pass@haproxy-site-a:26257/db
```

**Final Status:**
```
Site A: Node 6 ✅, Node 7 ✅ (Rejoined as new nodes)
Site B: Node 3 ✅, Node 4 ✅
Status: Cluster ONLINE ✅ (4/4 quorum)
Topology: Back to 2+2 (Site A primary)
Downtime: 0 minutes (zero downtime recovery)
```

---

## 📊 Failover Scenarios Summary

| Scenario | Nodes Down | Quorum | Auto-Failover? | Downtime |
|----------|------------|--------|----------------|----------|
| 1 node down (any site) | 1/4 | 3/4 ✅ | ✅ Yes | ~5-10s |
| 2 nodes down (different sites) | 2/4 | 2/4 ❌ | ❌ No | Manual |
| Site A down (Node 1+2) | 2/4 | 2/4 ❌ | ❌ No | ~5-15min |
| Site B down (Node 3+4) | 2/4 | 2/4 ❌ | ❌ No | ~5-15min |

---

## ⚠️ Important Notes

### 1. Node ID Changes
When nodes rejoin after being decommissioned, they get **new Node IDs**. This is normal and expected.

### 2. Temporary Node Requirements
Node 5 (temporary) can be:
- A spare server
- A VM/container spun up on-demand
- Minimum specs: 1 CPU, 2GB RAM (for voting only)

### 3. Data Consistency
CockroachDB guarantees **no data loss** during failover because:
- Raft consensus requires majority (3/4) for writes
- Decommissioning ensures data is replicated before node removal

### 4. Application Connection String
Use **DNS** or **load balancer** for application connection to easily switch between sites:
```
# Use DNS CNAME
db.example.com → haproxy-site-a (normal)
db.example.com → haproxy-site-b (failover)
```

---

## 🧪 Testing Procedure

### Test 1: Single Node Failure
```bash
# Stop Node 1
sudo systemctl stop cockroach  # On Node 1

# Verify cluster still online
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE2_IP> \
  -e "SELECT 1;"

# Restart Node 1
sudo systemctl start cockroach  # On Node 1
```

### Test 2: Complete Site Failover (Controlled)
```bash
# 1. Stop Site A nodes
sudo systemctl stop cockroach  # On Node 1
sudo systemctl stop cockroach  # On Node 2

# 2. Follow "Phase 1: Emergency Failover" runbook

# 3. Verify cluster online from Site B
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP> \
  -e "SELECT * FROM cluster_test;"

# 4. Follow "Phase 2: Site A Recovery" runbook
```

---

## � References

- [CockroachDB Multi-Region Deployment](https://www.cockroachlabs.com/docs/stable/multiregion-overview.html)
- [Locality Configuration](https://www.cockroachlabs.com/docs/stable/cockroach-start.html#locality)
- [Replication Zones](https://www.cockroachlabs.com/docs/stable/configure-replication-zones.html)
- [Node Decommissioning](https://www.cockroachlabs.com/docs/stable/node-shutdown.html)

---

## 🆘 Troubleshooting

### Issue: Decommission Stuck
```bash
# Check decommission progress
cockroach node status --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP>

# If stuck, check replica count
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP> \
  -e "SHOW RANGES FROM DATABASE defaultdb;"
```

### Issue: Rebalancing Too Slow
```bash
# Increase rebalance rate (default: 8MB/s)
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP> \
  -e "SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '64MiB';"
```

### Issue: Cannot Connect After Failover
```bash
# Check HAProxy status
sudo systemctl status haproxy

# Check backend health
curl http://<HAPROXY_IP>:8081

# Test direct connection to node
cockroach sql --certs-dir=/var/lib/cockroach/certs --host=<NODE3_IP>
```
