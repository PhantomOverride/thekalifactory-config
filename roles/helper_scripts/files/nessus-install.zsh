#!/usr/bin/env zsh
set -euo pipefail

echo "Installing Nessus from /opt..."

# Find Nessus package
DEB_FILE=$(find /opt/nessus -maxdepth 1 -type f -name "Nessus-*.deb" | head -n 1)

if [[ -z "$DEB_FILE" ]]; then
  echo "Error: No Nessus .deb package found in /opt"
  exit 1
fi

echo "Package found: $DEB_FILE"

# Install using apt (handles dependencies)
sudo apt update
sudo apt install -y "$DEB_FILE"

# Enable and start service
echo "Enabling and starting nessusd..."
sudo systemctl enable nessusd
sudo systemctl start nessusd

# Wait for it to come up
sleep 5

# Check status
if systemctl is-active --quiet nessusd; then
  echo "Nessus service is running"
else
  echo "Warning: nessusd is not running"
fi

echo ""
echo "Access Nessus at: https://localhost:8834"
echo "Complete setup via the web interface"
