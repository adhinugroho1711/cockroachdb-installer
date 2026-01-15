# Release Notes

## Version 1.2 (2026-01-15)

### 🎉 New Features

- **Interactive HTML Checklist**: Complete web-based progress tracker with auto-save functionality
- **Auto-Detection Enhancement**: Full support for ARM64 (Apple Silicon, AWS Graviton)
- **HAProxy Interactive Prompt**: No more hardcoded localhost, script asks for node IPs
- **Consolidated Documentation**: All guides merged into single interactive experience

### 🛠️ Improvements

- **Error Handling**: Enhanced download failure detection in installation scripts
- **Variable Safety**: Added fallback for `$VERSION_ID` in non-standard distros
- **Shebang Addition**: All scripts now have proper `#!/bin/bash` header

### 🐛 Bug Fixes

- Fixed missing shebang in `setup_os.sh` and `setup_cockroach.sh`
- Fixed HAProxy localhost hardcoding issue
- Fixed VERSION_ID undefined variable error on custom Linux distros

### 📚 Documentation

- Added comprehensive migration guide from PostgreSQL
- Added failover testing procedures with Multipass examples
- Added troubleshooting section with common issues

---

## Version 1.1 (2026-01-14)

### 🎉 New Features

- **Dynamic Memory Calculation**: Auto-allocates 25% RAM for cache and SQL memory
- **Multi-OS Support**: Detects and configures Ubuntu/Debian vs RHEL/Rocky/AlmaLinux
- **Firewall Auto-Config**: Supports both UFW (Debian-based) and firewalld (RHEL-based)

### 🛠️ Improvements

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

- [ ] TLS/SSL certificate auto-generation scripts
- [ ] Prometheus & Grafana integration templates
- [ ] Ansible playbook for multi-node deployment
- [ ] Backup & restore automation scripts
- [ ] Performance benchmarking tools (TPC-C/YCSB)

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
