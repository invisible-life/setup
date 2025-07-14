#!/bin/bash

# =====================================================================================
#
#  Invisible - Configure IP Access Script
#
#  This script configures the Invisible platform for IP-based access
#  by updating environment variables and rebuilding UI components.
#
#  Usage:
#     ./configure-ip-access.sh [IP_ADDRESS]
#
#  Example:
#     ./configure-ip-access.sh 192.168.1.100
#     ./configure-ip-access.sh  # Uses auto-detected public IP
#
# =====================================================================================

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

# --- Helper Functions ---
# Helper function to run docker commands with proper user context
run_docker_cmd() {
  if [ -n "${SUDO_USER}" ] && [ "${SUDO_USER}" != "root" ]; then
    sudo -u "${SUDO_USER}" "$@"
  else
    "$@"
  fi
}

# --- Main Script ---
if [ "$(id -u)" -ne 0 ]; then
  print_error "This script must be run with sudo."
  exit 1
fi

# Check if the platform is installed
if [ ! -f "$ENV_FILE" ]; then
  print_error "Invisible platform not found at $DEPLOY_DIR"
  print_error "Please run the main setup script first."
  exit 1
fi

print_header "Configure Invisible Platform for IP Access"

# Get IP address
if [ -n "$1" ]; then
  SERVER_IP="$1"
  print_info "Using provided IP address: $SERVER_IP"
else
  print_info "Auto-detecting public IP address..."
  SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "")
  if [ -z "$SERVER_IP" ]; then
    print_error "Could not auto-detect IP address."
    print_error "Please provide IP address as argument: $0 <IP_ADDRESS>"
    exit 1
  fi
  print_success "Detected IP: $SERVER_IP"
fi

print_header "Updating Configuration"

# Update the main .env file for IP-based access
print_info "Updating environment configuration..."
sed -i.backup "s/^APP_DOMAIN=.*/APP_DOMAIN=$SERVER_IP/" "$ENV_FILE"
sed -i "s/^NO_DOMAIN=.*/NO_DOMAIN=true/" "$ENV_FILE"
sed -i "s|^CHAT_URL=.*|CHAT_URL=https://$SERVER_IP:8082|" "$ENV_FILE"

print_header "Rebuilding UI Components"

# Rebuild UI components with new IP configuration using orchestrator
print_info "Rebuilding UI components with IP-based configuration..."
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

# Update Caddy configuration for IP-based access
cd "$DEPLOY_DIR"
export NO_DOMAIN=true
print_info "Updating Caddy configuration for IP access..."
./prepare-caddy.sh

print_header "Restarting Services"

# Use correct docker compose command
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
else
  DOCKER_COMPOSE="docker-compose"
fi

# Restart services to pick up new configuration
print_info "Restarting services with IP-based configuration..."
run_docker_cmd $DOCKER_COMPOSE down
run_docker_cmd $DOCKER_COMPOSE up -d

# Wait for services to be ready
print_info "Waiting for services to initialize..."
sleep 15

print_header "IP Access Configuration Complete!"

print_success "Your platform is now configured for IP-based access: $SERVER_IP"
echo ""
print_info "Access URLs:"
echo "  • UI Hub: https://$SERVER_IP:8080"
echo "  • UI Chat: https://$SERVER_IP:8082"
echo "  • Supabase Studio: https://$SERVER_IP/api/studio"
echo "  • Mailpit (Email): https://$SERVER_IP/mailpit"
echo ""
print_warning "Certificate Notes:"
echo "  • Using HTTPS with self-signed certificates"
echo "  • Browser will show security warnings - this is normal"
echo "  • Click 'Advanced' and 'Proceed' to access the sites"
echo ""
print_info "The platform will be accessible at the above URLs once services finish starting."