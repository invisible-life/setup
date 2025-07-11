#!/bin/bash

set -e

# --- Configuration ---
DEPLOY_DIR="/opt/invisible"
ENV_FILE="$DEPLOY_DIR/.env"

# --- Helper Functions ---
print_header() {
  echo ""
  echo "======================================================================="
  echo "  $1"
  echo "======================================================================="
}

# --- Main Script ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run with sudo."
  exit 1
fi

print_header "Add Domain to Invisible Platform"

# Check if the platform is installed
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Error: Invisible platform not found at $DEPLOY_DIR"
  echo "Please run the main setup script first."
  exit 1
fi

# Get the new domain
echo ""
read -p "Enter the root domain for the application (e.g., example.com): " NEW_DOMAIN

if [ -z "$NEW_DOMAIN" ]; then
  echo "❌ Error: Domain cannot be empty."
  exit 1
fi

print_header "Updating Configuration"

# Update the .env file
echo "Updating environment configuration..."
sed -i.backup "s/^APP_DOMAIN=.*/APP_DOMAIN=$NEW_DOMAIN/" "$ENV_FILE"
sed -i "s/^NO_DOMAIN=.*/NO_DOMAIN=false/" "$ENV_FILE"

# Update Caddy configuration
cd "$DEPLOY_DIR"
export NO_DOMAIN=false
echo "Updating Caddy configuration..."
./prepare-caddy.sh

print_header "Restarting Services"

# Restart Caddy to pick up the new configuration
echo "Restarting Caddy..."
sudo -u ${SUDO_USER} docker-compose restart caddy

# Wait for Caddy to be ready
sleep 5

# Get server's public IP
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

print_header "✅ Domain Configuration Complete!"

echo ""
echo "Your platform is now configured to use: $NEW_DOMAIN"
echo ""

print_header "📋 REQUIRED: Manual DNS Configuration"

echo ""
echo "You MUST configure the following DNS records for your domain:"
echo ""
echo "Domain: $NEW_DOMAIN"
echo "Server IP: $SERVER_IP"
echo ""
echo "Required A Records:"
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │ Type │ Name              │ Value          │ TTL  │ Proxy    │"
echo "  ├──────┼───────────────────┼────────────────┼──────┼──────────┤"
echo "  │ A    │ api.$NEW_DOMAIN   │ $SERVER_IP     │ 3600 │ DNS Only │"
echo "  │ A    │ chat.$NEW_DOMAIN  │ $SERVER_IP     │ 3600 │ DNS Only │"
echo "  │ A    │ hub.$NEW_DOMAIN   │ $SERVER_IP     │ 3600 │ DNS Only │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
echo "⚠️  IMPORTANT: If using Cloudflare, set proxy status to 'DNS Only' (gray cloud)"
echo ""

print_header "🚀 Next Steps"

echo ""
echo "1. Configure DNS records as shown above"
echo "2. Wait for DNS propagation (usually 5-30 minutes)"
echo "3. Test DNS resolution:"
echo "   nslookup api.$NEW_DOMAIN"
echo "   nslookup chat.$NEW_DOMAIN"
echo "   nslookup hub.$NEW_DOMAIN"
echo ""
echo "4. Access your applications:"
echo "   • Chat UI: https://chat.$NEW_DOMAIN"
echo "   • Hub UI: https://hub.$NEW_DOMAIN"
echo "   • API: https://api.$NEW_DOMAIN"
echo ""
echo "Note: Caddy will automatically provision SSL certificates on first access."
echo ""