#!/bin/bash
# generate-repo.sh
# Generates the complete xrpl-validator-monitor-dashboard repository structure
# Usage: ./generate-repo.sh [output-directory]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default output directory
OUTPUT_DIR="${1:-xrpl-validator-monitor-dashboard}"

echo -e "${GREEN}=== XRPL Validator Monitor Dashboard - Repository Generator ===${NC}"
echo ""

# Check if directory already exists
if [ -d "$OUTPUT_DIR" ]; then
    echo -e "${YELLOW}Warning: Directory '$OUTPUT_DIR' already exists.${NC}"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    rm -rf "$OUTPUT_DIR"
fi

# Create directory structure
echo "Creating directory structure..."
mkdir -p "$OUTPUT_DIR"/{config,monitoring/{grafana/dashboards,prometheus},scripts,docs}

cd "$OUTPUT_DIR"

# Create .gitignore
echo "Creating .gitignore..."
cat > .gitignore << 'EOF'
# Installation tracking
.install-tracker.json
.install-state/

# Rippled data and logs
data/
logs/
*.log

# Secrets and credentials
*.json.key
validator-keys.json
*.pem
.env

# Docker volumes
docker-data/

# Grafana
monitoring/grafana/data/

# Prometheus
monitoring/prometheus/data/

# Backup files
*.bak
*.backup
*.old

# OS files
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# Temporary files
tmp/
temp/
*.tmp
EOF

# Create LICENSE (MIT)
echo "Creating LICENSE..."
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2025 XRPL Validator Monitor Dashboard Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

echo -e "${GREEN}✓ Repository structure created${NC}"
echo ""
echo "Next steps:"
echo "1. Review the generated files in: $OUTPUT_DIR"
echo "2. Add your Rippled-Dashboard.json to: monitoring/grafana/dashboards/"
echo "3. Initialize git repository:"
echo "   cd $OUTPUT_DIR"
echo "   git init"
echo "   git add ."
echo "   git commit -m 'Initial commit'"
echo "4. Push to GitHub:"
echo "   git remote add origin git@github.com:USERNAME/xrpl-validator-monitor-dashboard.git"
echo "   git push -u origin main"
echo ""
echo -e "${GREEN}Repository structure generated successfully!${NC}"
