FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy application files
COPY src/ ./src/
COPY config.yaml .

# Expose metrics port
EXPOSE 9094

# Run the monitoring service
CMD ["python3", "src/collectors/fast_poller.py"]
