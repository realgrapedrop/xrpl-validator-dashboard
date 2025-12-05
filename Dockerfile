FROM python:3.11-slim

LABEL maintainer="XRPL Monitor"
LABEL version="3.0.0"
LABEL description="Real-time XRPL validator monitoring with WebSocket streams and VictoriaMetrics"

# Set working directory
WORKDIR /app

# Install system dependencies
# - curl: for debugging and health checks
# - procps: for ps command (CPU monitoring)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    procps \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (for docker exec fallback - peer metrics and CPU monitoring)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements first (for better caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/

# Create logs and state directories
RUN mkdir -p /app/logs /app/state

# Run as non-root user (but needs docker group access)
# Note: UID 1000 is typically the first non-root user
# Docker socket access requires being in docker group (GID usually 999 or docker host's docker GID)
RUN useradd -m -u 1000 monitor && \
    chown -R monitor:monitor /app

USER monitor

# Set Python path
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
# Disable Python bytecode to prevent .pyc cache issues
ENV PYTHONDONTWRITEBYTECODE=1

# Default command
CMD ["python", "-m", "src.monitor.main"]
