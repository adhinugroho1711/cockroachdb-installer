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
├── README.md                   # This file
├── RELEASE_NOTES.md            # Version history & changelog
├── index.html                  # Interactive checklist & detailed guide
├── scripts/
│   ├── setup_os.sh             # OS optimization (kernel, limits, firewall)
│   ├── setup_cockroach.sh      # CockroachDB installation & systemd
│   └── setup_haproxy.sh        # HAProxy load balancer setup
```

---

## 🚀 Quick Start

### 1. Provision Infrastructure (Multipass Example)

```bash
multipass launch --name n1 --cpus 2 --memory 2G --disk 10G
multipass launch --name n2 --cpus 2 --memory 2G --disk 10G
multipass launch --name n3 --cpus 2 --memory 2G --disk 10G
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
sudo systemctl enable --now cockroach
```

### 5. Initialize Cluster (run once)

```bash
cockroach init --insecure --host=<IP_NODE_1>
```

### 6. Setup Load Balancer

```bash
bash scripts/setup_haproxy.sh
```

### 7. Open Interactive Guide

Open `index.html` in your browser for detailed step-by-step checklist with progress tracking.

---

## 📊 Architecture Transition (PostgreSQL → CockroachDB)

| Component         | PostgreSQL Stack          | CockroachDB Stack       |
|-------------------|---------------------------|-------------------------|
| **HA Manager**    | Patroni + ETCD            | Native Raft Consensus   |
| **Load Balancer** | PgBouncer                 | HAProxy                 |
| **Replication**   | Streaming Replication     | Multi-Raft Ranges       |
| **Failover**      | Manual/Semi-Automatic     | Fully Automatic (~9s)   |

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
