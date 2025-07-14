#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_header() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

# --- Configuration ---
DEPLOY_DIR="/opt/invisible"
ENV_FILE="$DEPLOY_DIR/.env"

# --- Main Script ---
if [ "$(id -u)" -ne 0 ]; then
  print_error "This script must be run with sudo."
  exit 1
fi

print_header "Add Domain to Invisible Platform"

# Check if the platform is installed
if [ ! -f "$ENV_FILE" ]; then
  print_error "Invisible platform not found at $DEPLOY_DIR"
  print_error "Please run the main setup script first."
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

# Update the .env file with new domain configuration
print_info "Updating environment configuration..."
sed -i.backup "s/^APP_DOMAIN=.*/APP_DOMAIN=$NEW_DOMAIN/" "$ENV_FILE"
sed -i "s/^NO_DOMAIN=.*/NO_DOMAIN=false/" "$ENV_FILE"
sed -i "s|^CHAT_URL=.*|CHAT_URL=https://chat.$NEW_DOMAIN|" "$ENV_FILE"

print_header "Rebuilding UI Components"

# Rebuild UI components with new domain using orchestrator
print_info "Rebuilding UI components with new domain..."
docker run --rm \
  -v "/opt/invisible:/opt/invisible" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /usr/bin/docker:/usr/bin/docker \
  --network host \
  --privileged \
  -w /app \
  invisiblelife/orchestrator:latest \
  bash -c "cd /opt/invisible && /app/setup/setup.sh --rebuild-ui-only"

print_header "Updating Caddy Configuration"

# Update Caddy configuration for domain-based access
cd "$DEPLOY_DIR"
export NO_DOMAIN=false
print_info "Updating Caddy configuration..."
./prepare-caddy.sh

print_header "Restarting Services"

# Use correct docker compose command
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
else
  DOCKER_COMPOSE="docker-compose"
fi

# Restart services to pick up new configuration
print_info "Restarting services..."
sudo -u ${SUDO_USER} $DOCKER_COMPOSE down
sudo -u ${SUDO_USER} $DOCKER_COMPOSE up -d

# Wait for services to be ready
print_info "Waiting for services to initialize..."
sleep 15

# Get server's public IP
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

print_header "Domain Configuration Complete!"

print_success "Your platform is now configured to use: $NEW_DOMAIN"
echo ""
print_info "Access URLs:"
echo "  • UI Hub: https://hub.$NEW_DOMAIN"
echo "  • UI Chat: https://chat.$NEW_DOMAIN"
echo "  • Supabase Studio: https://api.$NEW_DOMAIN/studio"
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