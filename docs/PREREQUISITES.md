# Prerequisites

Complete prerequisites for installing and running the XRPL Validator Monitor Dashboard.

## Table of Contents

- [Operating System](#operating-system)
- [Software Requirements](#software-requirements)
- [Hardware Requirements](#hardware-requirements)
- [Network Requirements](#network-requirements)
- [Knowledge Requirements](#knowledge-requirements)

## Operating System

### Supported
- **Ubuntu 24.04 LTS (Noble)** - Recommended and tested
- Ubuntu 22.04 LTS (Jammy) - Should work
- Debian 12 (Bookworm) - Should work

### Not Officially Supported
- Other Linux distributions may work but are not tested
- Windows (use WSL2 with Ubuntu)
- macOS (for development/testing only, not production validators)

### Installation

**Ubuntu 24.04:**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install basic utilities
sudo apt install -y curl wget git jq net-tools
```

## Software Requirements

### Docker Engine

**Minimum Version:** 28.3.3 or later

**Installation on Ubuntu:**
```bash
# Remove old versions
sudo apt remove docker docker-engine docker.io containerd runc

# Install dependencies
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
docker --version
sudo docker run hello-world

# Add your user to docker group (optional, avoids sudo)
sudo usermod -aG docker $USER
newgrp docker
```

**Official Documentation:** https://docs.docker.com/engine/install/ubuntu/

### Docker Compose

**Minimum Version:** v2.39.1 or later

Docker Compose v2 is included with Docker Engine installation above (as a plugin).

**Verify:**
```bash
docker compose version
```

**Official Documentation:** https://docs.docker.com/compose/install/

### Grafana

**Version:** 11.2.0 (included in monitoring stack)

Grafana is installed via Docker Compose. No separate installation required.

**Official Documentation:** https://grafana.com/docs/grafana/latest/

### Prometheus

**Version:** 2.54.1 (included in monitoring stack)

Prometheus is installed via Docker Compose. No separate installation required.

**Official Documentation:** https://prometheus.io/docs/introduction/overview/

### Node Exporter

**Version:** 1.8.2 (included in monitoring stack)

Node Exporter is installed via Docker Compose. No separate installation required.

**Official Documentation:** https://prometheus.io/docs/guides/node-exporter/

## Hardware Requirements

Hardware requirements vary significantly based on your use case.

### Full Validator (node_size: huge) - Recommended

**For production XRPL validators running with `node_size: huge`:**

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **CPU** | 8 cores | 24 cores | High single-thread performance preferred |
| **RAM** | 64GB | 96GB+ | Required for `node_size: huge` |
| **Storage** | 1.5TB NVMe SSD | 2TB+ NVMe SSD | Fast I/O critical for validator performance |
| **Network** | 100 Mbps | 1 Gbps | Low latency essential |

**Storage Details:**
- Full ledger history requires ~1TB+
- NVMe SSD strongly recommended (no HDD)
- Plan for 20-30% growth per year
- Separate partition recommended

**CPU Details:**
- Modern Intel Xeon or AMD EPYC
- High clock speed (3.0+ GHz) preferred
- AVX2 instruction set support

### Monitoring Only Installation

**If only installing monitoring stack (rippled already running elsewhere):**

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 2 cores | 4 cores |
| **RAM** | 4GB | 8GB |
| **Storage** | 50GB SSD | 100GB SSD |
| **Network** | 10 Mbps | 100 Mbps |

**Storage Details:**
- Prometheus data retention: ~1GB per day (default 30 days retention)
- Grafana database: ~100MB

### Resource Planning Examples

**Example 1: Dedicated Validator Server**
- CPU: AMD EPYC 7443 (24 cores)
- RAM: 96GB DDR4
- Storage: 2TB NVMe SSD (Samsung 980 PRO or similar)
- Network: 1Gbps dedicated
- **Cost:** ~$3,000-5,000

**Example 2: Cloud Instance (AWS)**
- Instance: r6i.4xlarge (16 vCPUs, 128GB RAM)
- Storage: 2TB io2 EBS (16,000 IOPS)
- Network: Up to 25 Gbps
- **Cost:** ~$1,500-2,000/month

**Example 3: Budget Validator**
- CPU: Intel Core i7-12700 (12 cores)
- RAM: 64GB DDR4
- Storage: 1.5TB NVMe SSD
- Network: 1Gbps residential
- **Cost:** ~$1,500-2,000 (one-time)
- **Note:** Minimum for `node_size: huge`, not recommended for critical validators

## Network Requirements

### Ports

**Required Open Ports:**

| Port | Protocol | Direction | Purpose | Public? |
|------|----------|-----------|---------|---------|
| 51235 | TCP/UDP | Inbound/Outbound | Peer protocol | ✅ Yes |
| 5005 | TCP | Localhost only | Admin API / Metrics | ❌ No |
| 6006 | TCP | Localhost only | Admin WebSocket | ❌ No |
| 3000 | TCP | Optional | Grafana UI | ⚠️ Optional |
| 9090 | TCP | Optional | Prometheus UI | ⚠️ Optional |

**Important:**
- **Port 51235 MUST be publicly accessible** for validator to participate in consensus
- **Admin ports (5005, 6006) MUST NOT be publicly exposed** - security risk
- Grafana/Prometheus ports should only be exposed if you need remote access (use Cloudflare Tunnel or VPN)

### Bandwidth

- **Minimum:** 100 Mbps up/down
- **Recommended:** 1 Gbps up/down
- **Typical Usage:** 50-200 GB/month
- **Latency:** <50ms to other validators (lower is better)

### Firewall Configuration

**Ubuntu UFW Example:**
```bash
# Allow SSH (adjust port if needed)
sudo ufw allow 22/tcp

# Allow rippled peer port
sudo ufw allow 51235/tcp
sudo ufw allow 51235/udp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status
```

### Static IP

**Highly Recommended:**
- Static IP or DDNS for consistent peer connections
- IPv4 required, IPv6 optional but beneficial

## Knowledge Requirements

### Essential Skills

**System Administration:**
- Linux command line proficiency
- SSH and remote server management
- Log file analysis and troubleshooting
- Basic networking concepts

**Docker:**
- Docker and Docker Compose basics
- Container lifecycle management
- Volume and network management
- Reading docker logs

**Monitoring:**
- Understanding metrics and time-series data
- Basic Prometheus query language (PromQL)
- Grafana dashboard navigation

### Recommended Skills

- Understanding of blockchain/DLT concepts
- XRPL protocol basics
- Security best practices
- Backup and disaster recovery

### Helpful Resources

**XRPL:**
- Official Documentation: https://xrpl.org/docs.html
- Validator Setup Guide: https://xrpl.org/install-rippled.html
- Forum: https://forum.xrpl.org

**Docker:**
- Get Started: https://docs.docker.com/get-started/
- Best Practices: https://docs.docker.com/develop/dev-best-practices/

**Prometheus:**
- Getting Started: https://prometheus.io/docs/prometheus/latest/getting_started/
- Query Basics: https://prometheus.io/docs/prometheus/latest/querying/basics/

**Grafana:**
- Getting Started: https://grafana.com/docs/grafana/latest/getting-started/
- Dashboard Best Practices: https://grafana.com/docs/grafana/latest/best-practices/

## Pre-Installation Checklist

Before installing, verify:

- [ ] Operating system is Ubuntu 24.04 LTS or compatible
- [ ] Docker Engine 28.3.3+ installed
- [ ] Docker Compose v2.39.1+ installed
- [ ] Hardware meets minimum requirements for your use case
- [ ] Port 51235 is open and publicly accessible
- [ ] Admin ports (5005, 6006) are NOT publicly accessible
- [ ] Static IP or DDNS configured (for validators)
- [ ] Adequate storage space available (1.5TB+ for full validator)
- [ ] You have root/sudo access
- [ ] You have backed up any existing validator keys (if migrating)

## Common Issues

### Insufficient Resources

**Symptom:** Validator falls out of sync, high memory usage
**Solution:** Upgrade hardware to meet recommended specs

### Port Conflicts

**Symptom:** Docker containers fail to start with "port already in use"
**Solution:** Check and stop conflicting services:
```bash
sudo netstat -tulpn | grep -E "51235|5005|3000|9090"
```

### Docker Permission Issues

**Symptom:** "permission denied" when running docker commands
**Solution:** Add user to docker group:
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Disk Space

**Symptom:** Database fills up, validator stops
**Solution:** Monitor disk usage, increase retention policies:
```bash
df -h
docker system df
```

## Next Steps

Once prerequisites are met, proceed to:
- [Installation Guide](INSTALLATION.md)
- [Main README](../README.md)
