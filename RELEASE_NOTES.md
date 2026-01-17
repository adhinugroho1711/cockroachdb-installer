# Release Notes

## Version 1.3 (2026-01-17)

### New Features v1.3 (🎉)

- **Fully Adaptive Optimization**: All installation and load balancer scripts now dynamically calculate parameters (`maxconn`, `timeout`, `somaxconn`, `file-max`) based on actual server RAM and CPU.
- **PgBouncer Integration**: New `setup_pgbouncer.sh` script for production environments with high connection loads (>1000 concurrent connections).
- **Automated Certificate Authority**: New `generate_certs.sh` script that automates the generation of CA, Node, and Client certificates for secure clusters.
- **Dedicated Load Balancer OS Tuning**: New `setup_loadbalancer_os.sh` specifically for optimizing HAProxy/PgBouncer servers.
- **Premium Dashboard Theme**: `index.html` overhauled with a modern Slate & Indigo theme, improved readability, and a more logical installation flow.

### Improvements v1.3 (🛠️)

- **Transparent Huge Pages (THP)**: Added `madvise` mode configuration as recommended by CockroachDB.
- **Enhanced Scheduling**: All systemd services now use `LimitNOFILE=infinity` for unlimited file descriptors.
- **Multi-Threading**: HAProxy now automatically detects CPU cores and sets `nbthread` accordingly.
- **Load Balancing Logic**: Switched default HAProxy algorithm to `roundrobin` per CockroachDB official best practices.
- **Better Security**: Added automated firewall rules for PgBouncer (6432) and HAProxy Stats (8081).

### 🐛 Bug Fixes

- Fixed `leastconn` balancing which could cause hotspots; reverted to `roundrobin`.
- Removed redundant manual certificate generation steps in the interactive guide.
- Fixed timezone detection to be interactive instead of hardcoded.
- Improved terminal contrast in the interactive dashboard for long-term usage.

### 📚 Documentation

- Added `LOADBALANCER_OPTIMIZATION.md` with detailed adaptive parameter calculations.
- Updated `README.md` with new scripts and a production-grade deployment flow.
- Added architectural diagrams with PgBouncer co-location guidance.

---

## Version 1.2 (2026-01-15)

## Version 1.1 (2026-01-14)

### New Features v1.1 (🎉)

- **Dynamic Memory Calculation**: Auto-allocates 25% RAM for cache and SQL memory
- **Multi-OS Support**: Detects and configures Ubuntu/Debian vs RHEL/Rocky/AlmaLinux
- **Firewall Auto-Config**: Supports both UFW (Debian-based) and firewalld (RHEL-based)

### Improvements v1.1 (🛠️)

- Kernel tuning optimized for OLTP workload
- File descriptor limits set to 100,000
- Swap disabled by default for low-latency writes

---

## Version 1.0 (2026-01-13)

### 🎉 Initial Release

- **CockroachDB v23.1.11** installation scripts
- Basic OS optimization (Ubuntu Server LTS)
- Systemd service configuration
- HAProxy load balancer setup
- SQL best practices examples

---

## Roadmap

### Upcoming Features

- [x] TLS/SSL certificate auto-generation scripts (v1.3)
- [ ] Prometheus & Grafana integration templates
- [ ] Ansible playbook for multi-node deployment
- [ ] Backup & restore automation scripts
- [ ] Performance benchmarking tools (TPC-C/YCSB)
- [ ] Dynamic cluster auto-scaling scripts
- [ ] Multi-region cluster configuration guide

---

## Known Issues

### v1.2

- None reported

### v1.1

- HAProxy required manual IP editing (fixed in v1.2)

---

## Migration Guide

For users upgrading from previous versions:

### v1.1 → v1.2

1. Re-run `setup_haproxy.sh` to use interactive IP input
2. No database downtime required
3. Review new interactive checklist at `index.html`

### v1.0 → v1.1

1. Re-run `setup_os.sh` for enhanced OS detection
2. Re-run `setup_cockroach.sh` for dynamic memory tuning
3. Restart CockroachDB service: `sudo systemctl restart cockroach`

---

## Support

For issues and questions:

- **GitHub Issues**: <https://github.com/adhinugroho1711/cockroachdb-installer/issues>
- **Discussions**: <https://github.com/adhinugroho1711/cockroachdb-installer/discussions>
