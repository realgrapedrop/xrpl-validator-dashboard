# Troubleshooting Guide

Common issues and solutions for XRPL Validator Monitor Dashboard.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Rippled Validator Issues](#rippled-validator-issues)
- [Monitoring Stack Issues](#monitoring-stack-issues)
- [Performance Issues](#performance-issues)
- [Network Issues](#network-issues)
- [Data and Storage Issues](#data-and-storage-issues)

## Installation Issues

### Docker Not Found

**Symptom:**
```
Error: docker command not found
```

**Solution:**
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Verify
docker --version
```

### Permission Denied

**Symptom:**
```
permission denied while trying to connect to the Docker daemon socket
```

**Solution:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker ps
```

### Port Already in Use

**Symptom:**
```
Error: bind: address already in use
```

**Solution:**
```bash
# Find what's using the port
sudo netstat -tulpn | grep <PORT>

# Stop the conflicting service
sudo systemctl stop <service>

# Or change port in docker-compose.yml
```

## Rippled Validator Issues

### Validator Not Syncing

**Symptoms:**
- Ledger index not increasing
- `server_state` stuck in `disconnected` or `connected`
- No peer connections

**Diagnostics:**
```bash
# Check validator status
docker exec rippledvalidator rippled server_info

# Check peers
docker exec rippledvalidator rippled peers

# Check logs
docker logs -f rippledvalidator
```

**Common Causes & Solutions:**

1. **Port 51235 not accessible**
   ```bash
   # Test from another machine
   nc -zv YOUR_IP 51235
   
   # Check firewall
   sudo ufw status
   sudo ufw allow 51235/tcp
   sudo ufw allow 51235/udp
   ```

2. **Incorrect validators.txt (UNL)**
   ```bash
   # Verify UNL file
   cat ${INSTALL_DIR}/rippled/config/validators.txt
   
   # Should contain validator public keys
   # Download latest UNL if needed
   ```

3. **Network issues**
   - Check internet connectivity
   - Verify DNS resolution
   - Test latency to other validators

### Validator Stuck at "Proposing" State

**Symptoms:**
- `server_state: proposing` but no validation votes
- Low or zero `validation_quorum`

**Solution:**
```bash
# Check validator list subscription
docker exec rippledvalidator rippled validators

# Verify your validator public key is known
docker exec rippledvalidator rippled validation_create

# Check if you're on the UNL
# Your validator must be added to other validators' UNLs
```

### High Memory Usage

**Symptoms:**
- Container using >80% of allocated memory
- OOM (Out of Memory) kills
- System becomes unresponsive

**Diagnostics:**
```bash
# Check memory usage
docker stats rippledvalidator

# Check rippled cache sizes
docker exec rippledvalidator rippled server_info | grep -i cache
```

**Solutions:**

1. **Increase memory limit** (if hardware allows)
   ```yaml
   # In docker-compose.yml
   mem_limit: "96g"  # Increase from 64g
   memswap_limit: "96g"
   ```

2. **Adjust rippled cache settings**
   ```ini
   # In rippled.cfg
   [node_size]
   huge  # Requires 64GB+
   
   # Or reduce to:
   # large  # Requires 32GB
   # medium # Requires 16GB
   ```

3. **Enable online_delete**
   ```ini
   # In rippled.cfg - keeps less history
   [node_db]
   online_delete=256000
   advisory_delete=0
   ```

### Validator Keys Missing

**Symptom:**
```
Error: Cannot read validator keys
```

**Solution:**
```bash
# Generate new keys
docker exec rippledvalidator rippled validation_create

# Or restore from backup
cp backup/validator-keys.json ${INSTALL_DIR}/rippled/config/

# Ensure correct permissions
chmod 600 ${INSTALL_DIR}/rippled/config/validator-keys.json
```

## Monitoring Stack Issues

### Grafana Dashboard Not Loading

**Symptoms:**
- Blank dashboard
- "No data" messages
- Connection errors

**Diagnostics:**
```bash
# Check Grafana logs
docker logs grafana

# Check Prometheus logs
docker logs prometheus

# Test Prometheus query
curl http://localhost:9090/api/v1/query?query=up
```

**Solutions:**

1. **Verify datasource configuration**
   - Open Grafana: http://localhost:3000
   - Go to Configuration → Data Sources
   - Check Prometheus URL: `http://prometheus:9090`
   - Click "Save & Test"

2. **Check Prometheus targets**
   - Open Prometheus: http://localhost:9090/targets
   - All targets should be "UP"
   - If down, check network connectivity

3. **Verify rippled metrics endpoint**
   ```bash
   # Test metrics endpoint
   curl http://localhost:5005/metrics
   
   # Should return Prometheus-format metrics
   ```

### Prometheus Not Scraping

**Symptoms:**
- Targets show as "DOWN" in Prometheus
- Missing metrics in Grafana

**Solutions:**

1. **For Docker rippled:**
   ```yaml
   # prometheus.yml should have:
   - targets: ['rippledvalidator:5005']
   ```

2. **For native rippled:**
   ```yaml
   # prometheus.yml should have:
   - targets: ['localhost:5005']
   
   # AND prometheus must use host network:
   network_mode: host
   ```

3. **Check network connectivity:**
   ```bash
   # From Prometheus container
   docker exec prometheus wget -O- http://rippledvalidator:5005/metrics
   ```

### Metrics Not Appearing

**Symptom:**
- Some or all rippled metrics missing

**Solution:**
```bash
# Verify rippled is exposing metrics
curl http://localhost:5005/metrics | grep rippled_

# Check Prometheus scrape config
docker exec prometheus cat /etc/prometheus/prometheus.yml

# Restart Prometheus to reload config
docker restart prometheus
```

## Performance Issues

### Slow Dashboard Loading

**Causes & Solutions:**

1. **Too many data points**
   - Reduce time range
   - Increase scrape interval
   - Use recording rules

2. **Prometheus overloaded**
   ```bash
   # Check Prometheus resource usage
   docker stats prometheus
   
   # Increase memory if needed
   ```

3. **Slow queries**
   - Optimize PromQL queries
   - Use rate() instead of irate() for large ranges
   - Add recording rules for complex queries

### High CPU Usage

**Symptoms:**
- Docker containers using excessive CPU
- System becomes slow

**Diagnostics:**
```bash
# Check per-container CPU
docker stats

# Check system load
top
htop
```

**Solutions:**

1. **Rippled high CPU (normal during sync)**
   - Wait for initial sync to complete
   - Reduce `validation_quorum` temporarily
   - Check for database corruption

2. **Prometheus high CPU**
   - Reduce scrape frequency
   - Limit metric retention
   - Use recording rules

## Network Issues

### Cannot Access Grafana Remotely

**Symptom:**
```
Connection refused when accessing http://YOUR_IP:3000
```

**Solutions:**

1. **Check if bound to localhost only**
   ```yaml
   # In docker-compose.yml, change:
   ports:
     - "3000:3000"  # Accessible from anywhere
   # Instead of:
     - "127.0.0.1:3000:3000"  # Localhost only
   ```

2. **Check firewall**
   ```bash
   sudo ufw allow 3000/tcp
   ```

3. **Use Cloudflare Tunnel (recommended)**
   - More secure than exposing port
   - Follow separate Cloudflare Tunnel guide

### Peer Connections Dropping

**Symptoms:**
- Peer count fluctuating
- Frequent disconnections

**Solutions:**

1. **Check network stability**
   ```bash
   # Test connectivity
   ping -c 100 8.8.8.8
   
   # Check for packet loss
   mtr xrpl.org
   ```

2. **Verify port forwarding**
   - Ensure 51235 TCP/UDP properly forwarded
   - Check router/firewall settings

3. **Check ISP blocking**
   - Some ISPs block P2P traffic
   - Consider VPS/cloud hosting

## Data and Storage Issues

### Disk Space Full

**Symptoms:**
```
No space left on device
```

**Immediate Solutions:**
```bash
# Check disk usage
df -h

# Find large files
du -sh ${INSTALL_DIR}/*

# Clean Docker
docker system prune -a --volumes
```

**Permanent Solutions:**

1. **Increase online_delete frequency**
   ```ini
   # In rippled.cfg
   [node_db]
   online_delete=128000  # Keep less history
   ```

2. **Reduce Prometheus retention**
   ```yaml
   # In docker-compose.yml
   command:
     - '--storage.tsdb.retention.time=15d'  # Reduce from 30d
   ```

3. **Add more storage**
   - Extend volume
   - Add new disk

### Database Corruption

**Symptoms:**
- Validator fails to start
- Errors about corrupted database
- Unexpected shutdowns

**Solution:**
```bash
# Stop validator
docker stop rippledvalidator

# Backup current data
cp -r ${INSTALL_DIR}/rippled/data ${INSTALL_DIR}/rippled/data.backup

# Clear database (will resync)
rm -rf ${INSTALL_DIR}/rippled/data/*

# Restart validator (will download ledger)
docker start rippledvalidator

# Monitor sync progress
docker logs -f rippledvalidator
```

## Getting Help

### Collect Diagnostic Information

When seeking help, provide:

```bash
# System information
uname -a
lsb_release -a

# Docker versions
docker --version
docker compose version

# Container status
docker ps -a

# Rippled info (if running)
docker exec rippledvalidator rippled server_info

# Recent logs
docker logs --tail 100 rippledvalidator
docker logs --tail 100 prometheus
docker logs --tail 100 grafana

# Resource usage
docker stats --no-stream
df -h
free -h
```

### Where to Get Help

- **GitHub Issues:** https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard/issues
- **XRPL Forum:** https://forum.xrpl.org
- **XRPL Discord:** https://discord.gg/xrpl
- **Official Docs:** https://xrpl.org/docs.html
- **Author:** [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)

### Before Asking for Help

1. Check this troubleshooting guide
2. Search existing GitHub issues
3. Check XRPL documentation
4. Gather diagnostic information
5. Provide clear problem description
6. Include error messages and logs

## Emergency Recovery

### Complete System Failure

If your validator is completely down:

1. **Don't panic** - Your validator keys are safe in `validator-keys.json`
2. **Preserve your keys:**
   ```bash
   # Backup from failed system
   cp ${INSTALL_DIR}/rippled/config/validator-keys.json ~/validator-keys-backup.json
   ```

3. **Fresh installation:**
   - Install on new system
   - Restore validator keys
   - Wait for sync

4. **Notify network:**
   - Update your validator's domain record if changed
   - Contact UNL maintainers if IP changed

### Restore from Backup

```bash
# Stop services
cd ${INSTALL_DIR}
docker compose down

# Restore configs
cp backup/rippled.cfg ${INSTALL_DIR}/rippled/config/
cp backup/validator-keys.json ${INSTALL_DIR}/rippled/config/

# Start services
docker compose up -d

# Verify
docker logs -f rippledvalidator
```

## Prevention Best Practices

1. **Regular backups** of validator keys and configs
2. **Monitor disk space** - set alerts at 80%
3. **Monitor memory usage** - set alerts at 85%
4. **Keep Docker updated** - security patches
5. **Test recovery procedures** - practice restores
6. **Document changes** - maintain runbook
7. **Set up alerts** - Prometheus Alertmanager
8. **Review logs regularly** - catch issues early

## Still Having Issues?

If this guide doesn't solve your problem:

1. Open a GitHub issue with detailed information
2. Join XRPL community channels
3. Consult official XRPL documentation
4. Consider hiring professional support

Remember: Running a validator is a significant responsibility. Take time to understand the system and implement proper monitoring and backup procedures.
