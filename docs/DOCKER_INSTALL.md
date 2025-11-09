# Docker Installation Guide for Ubuntu

This guide walks you through installing Docker and Docker Compose on Ubuntu, step by step.

**Note:** The XRPL Validator Dashboard installer (`./install.sh`) automates this entire process in Part 1. This guide is provided for reference or manual installation.

## What is Docker?

Docker is a platform that runs applications in isolated containers. The XRPL Validator Dashboard uses Docker to run:
- **Grafana** - Dashboard visualization
- **Prometheus** - Metrics storage
- **Node Exporter** - System metrics collector

Your XRPL validator (rippled) also likely runs in Docker.

## System Requirements

- **Ubuntu 20.04 LTS or newer** (also works on Debian-based distributions)
- **64-bit system** (x86_64/amd64 or arm64)
- **Sudo access** (admin privileges)
- **Internet connection** for downloading packages

---

## Step-by-Step Installation

### Step 1: Update Your System

First, ensure your package list is up to date:

```bash
sudo apt update
sudo apt upgrade -y
```

### Step 2: Install Prerequisites

Install packages needed for Docker's repository:

```bash
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
```

### Step 3: Add Docker's Official GPG Key

This verifies packages are authentic:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

### Step 4: Add Docker Repository

Add Docker's official repository to your system:

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### Step 5: Install Docker Engine

Update package list and install Docker:

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

This installs:
- **docker-ce** - Docker Engine
- **docker-ce-cli** - Command-line interface
- **containerd.io** - Container runtime
- **docker-compose-plugin** - Docker Compose V2

### Step 6: Verify Docker Installation

Check that Docker is running:

```bash
sudo systemctl status docker
```

You should see `active (running)` in green.

Test Docker with a simple command:

```bash
sudo docker run hello-world
```

If you see "Hello from Docker!", it's working!

### Step 7: Add Your User to Docker Group

**Important:** This lets you run Docker commands without `sudo`.

```bash
sudo usermod -aG docker $USER
```

**You must log out and log back in** for this to take effect.

After logging back in, verify you can run Docker without sudo:

```bash
docker ps
```

If this works without errors, you're set!

### Step 8: Verify Docker Compose

Docker Compose V2 is installed as a plugin. Verify it works:

```bash
docker compose version
```

You should see version 2.x or newer (e.g., `Docker Compose version v2.20.0`).

---

## Post-Installation: Enable Docker on Boot

Ensure Docker starts automatically when your system boots:

```bash
sudo systemctl enable docker
sudo systemctl enable containerd
```

---

## Quick Verification Checklist

Run these commands to verify everything is ready:

```bash
# Check Docker version
docker --version
# Should show: Docker version 20.10+ or newer

# Check Docker Compose version
docker compose version
# Should show: Docker Compose version v2.0+ or newer

# Check Docker is running
docker ps
# Should show list of containers (may be empty)

# Check you can run without sudo
docker run --rm hello-world
# Should print "Hello from Docker!"
```

---

## Common Issues & Solutions

### Issue: "permission denied" when running docker commands

**Solution:** You need to add your user to the docker group and log out/in:

```bash
sudo usermod -aG docker $USER
```

Then **log out completely** and log back in.

### Issue: "Cannot connect to the Docker daemon"

**Solution:** Start the Docker service:

```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### Issue: "docker: command not found"

**Solution:** Docker didn't install correctly. Try:

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### Issue: Old Docker Compose V1 installed (shows version 1.x)

**Solution:** V2 is installed as `docker compose` (with space), not `docker-compose` (with dash):

```bash
# V2 (correct)
docker compose version

# V1 (old, don't use)
docker-compose version
```

The dashboard uses V2 syntax.

---

## Uninstalling Old Docker Versions (If Needed)

If you have an old Docker installation, remove it first:

```bash
sudo apt remove docker docker-engine docker.io containerd runc
```

Then follow the installation steps above.

---

## Next Steps

Once Docker is installed and verified, you're ready to install the XRPL Validator Dashboard!

**Important:** Log out and log back in first to activate Docker group permissions.

Then continue with:

```bash
git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git
cd xrpl-validator-dashboard
./install.sh
```

The installer will detect that Docker is already installed (Part 1 complete) and proceed directly to Part 2 (Dashboard Setup).

For detailed installation instructions, see: [docs/INSTALL.md](docs/INSTALL.md)

---

## Additional Resources

- **Official Docker Documentation:** https://docs.docker.com/engine/install/ubuntu/
- **Docker Compose Documentation:** https://docs.docker.com/compose/
- **Docker Hub:** https://hub.docker.com/ (browse container images)

## Other Operating Systems

This guide is for Ubuntu/Debian. For other systems:

- **CentOS/RHEL/Fedora:** https://docs.docker.com/engine/install/centos/
- **macOS:** https://docs.docker.com/desktop/install/mac-install/
- **Windows:** https://docs.docker.com/desktop/install/windows-install/

---

**Need Help?**

If you encounter issues not covered here:
1. Check the official Docker documentation
2. Open an issue: https://github.com/realgrapedrop/xrpl-validator-dashboard/issues
3. Include your Ubuntu version (`lsb_release -a`) and error messages
