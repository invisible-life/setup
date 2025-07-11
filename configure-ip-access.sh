#!/bin/bash

# =====================================================================================
#
#  Invisible - Configure IP Access Script
#
#  This script configures the Invisible platform for IP-based access
#  by updating all necessary environment variables and configurations.
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

# Check if the platform is installed
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Error: Invisible platform not found at $DEPLOY_DIR"
  echo "Please run the main setup script first."
  exit 1
fi

print_header "Configure Invisible Platform for IP Access"

# Get IP address
if [ -n "$1" ]; then
  SERVER_IP="$1"
else
  echo "Auto-detecting public IP address..."
  SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "")
  if [ -z "$SERVER_IP" ]; then
    echo "❌ Error: Could not auto-detect IP address."
    echo "Please provide IP address as argument: $0 <IP_ADDRESS>"
    exit 1
  fi
  echo "Detected IP: $SERVER_IP"
fi

print_header "Creating IP-based Environment Configuration"

# Create an IP-specific env file with all the necessary overrides
cat > "$DEPLOY_DIR/.env.ip-access" <<EOF
# IP-Based Access Configuration
# This file overrides settings for IP-based access

# Base URLs for services
APP_BASE_URL=https://$SERVER_IP
API_BASE_URL=https://$SERVER_IP/api
SUPABASE_URL=https://$SERVER_IP

# Frontend URLs for CORS
FRONTEND_URL=https://$SERVER_IP
FRONTEND_URL_CHAT=https://$SERVER_IP/chat
FRONTEND_URL_HUB=https://$SERVER_IP/hub

# UI Environment Variables
VITE_API_BASE_URL=https://$SERVER_IP/api
VITE_CHAT_API_BASE_URL=https://$SERVER_IP/api
VITE_SUPABASE_URL=https://$SERVER_IP
VITE_SUPABASE_ANON_KEY=\${ANON_KEY}
VITE_PUBLIC_PATH_CHAT=/chat/
VITE_PUBLIC_PATH_HUB=/hub/

# Supabase Auth URLs
GOTRUE_EXTERNAL_URL=https://$SERVER_IP
GOTRUE_MAILER_URLS_SITE_URL=https://$SERVER_IP
API_EXTERNAL_URL=https://$SERVER_IP

# WebSocket Configuration
WS_BASE_URL=wss://$SERVER_IP

# OAuth Redirect URLs (if needed)
GMAIL_REDIRECT_URI=https://$SERVER_IP/auth/gmail/callback
SLACK_REDIRECT_URI=https://$SERVER_IP/auth/slack/callback

# Enable HTTPS for IP access (with self-signed cert)
USE_HTTPS=true
ALLOW_SELF_SIGNED_CERTS=true

EOF

print_header "Updating Docker Compose Override"

# Create a docker-compose override for IP-based access
cat > "$DEPLOY_DIR/docker-compose.override.yml" <<EOF
services:
  # API Service - Add CORS for IP access
  api:
    environment:
      - CORS_ORIGINS=https://$SERVER_IP,http://localhost:8080,http://localhost:8081
      - FRONTEND_URL=https://$SERVER_IP
      - APP_BASE_URL=https://$SERVER_IP
      - USE_HTTPS=true
      - NODE_TLS_REJECT_UNAUTHORIZED=0  # Accept self-signed certs

  # UI Chat - Set API endpoints and public path
  ui-chat:
    environment:
      - VITE_API_BASE_URL=https://$SERVER_IP/api
      - VITE_CHAT_API_BASE_URL=https://$SERVER_IP/api
      - VITE_SUPABASE_URL=https://$SERVER_IP
      - VITE_SUPABASE_ANON_KEY=\${ANON_KEY}
      - PUBLIC_URL=/chat
      - VITE_BASE_PATH=/chat

  # UI Hub - Set API endpoints and public path
  ui-hub:
    environment:
      - VITE_API_BASE_URL=https://$SERVER_IP/api
      - VITE_SUPABASE_URL=https://$SERVER_IP
      - VITE_SUPABASE_ANON_KEY=\${ANON_KEY}
      - PUBLIC_URL=/hub
      - VITE_BASE_PATH=/hub

  # Operations API - Add CORS
  operations-api:
    environment:
      - CORS_ORIGINS=https://$SERVER_IP

  # Supabase Auth - Configure for IP access
  supabase_auth:
    environment:
      - GOTRUE_EXTERNAL_URL=https://$SERVER_IP
      - GOTRUE_MAILER_URLS_SITE_URL=https://$SERVER_IP
      - API_EXTERNAL_URL=https://$SERVER_IP

EOF

print_header "Creating CORS Configuration for API"

# Create a CORS config file that the API can use
cat > "$DEPLOY_DIR/cors-config.json" <<EOF
{
  "allowed_origins": [
    "http://localhost:8080",
    "http://localhost:8081",
    "http://localhost:5173",
    "http://localhost:4200",
    "https://$SERVER_IP"
  ],
  "allowed_methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  "allowed_headers": ["Content-Type", "Authorization", "X-Requested-With"],
  "credentials": true
}
EOF

print_header "Updating Services"

cd "$DEPLOY_DIR"

# Source the environment files
set -o allexport
source "$ENV_FILE"
source "$DEPLOY_DIR/.env.ip-access"
set +o allexport

# Use correct docker compose command
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
else
  DOCKER_COMPOSE="docker-compose"
fi

# Restart services with new configuration
echo "Restarting services with IP-based configuration..."
sudo -E -u ${SUDO_USER} $DOCKER_COMPOSE down
sudo -E -u ${SUDO_USER} $DOCKER_COMPOSE up -d

# Wait for services to start
echo "Waiting for services to initialize..."
sleep 15

print_header "✅ IP Access Configuration Complete!"

echo ""
echo "Your services are now configured for IP-based access:"
echo ""
echo "🌐 Access Points (using path-based routing):"
echo "  • Chat UI: https://$SERVER_IP/ or https://$SERVER_IP/chat"
echo "  • Hub UI: https://$SERVER_IP/hub"
echo "  • API: https://$SERVER_IP/api"
echo "  • Supabase Studio: http://$SERVER_IP:54323"
echo "  • Mailpit (Email): http://$SERVER_IP:54324"
echo ""
echo "📝 Notes:"
echo "  • Using HTTPS with self-signed certificates"
echo "  • You'll see browser warnings about certificates - this is normal"
echo "  • Click 'Advanced' and 'Proceed' to access the sites"
echo "  • CORS configured to accept requests from IP addresses"
echo "  • OAuth callbacks configured for IP-based URLs"
echo ""
echo "🔒 Certificate Warning:"
echo "  Browsers will show security warnings because we're using"
echo "  self-signed certificates. This is expected and safe for"
echo "  your private use. To proceed:"
echo "  1. Click 'Advanced' or 'Show Details'"
echo "  2. Click 'Proceed to $SERVER_IP' or 'Accept the Risk'"
echo ""
echo "🔧 Troubleshooting:"
echo "  • Check service status: docker-compose ps"
echo "  • View logs: docker-compose logs [service-name]"
echo "  • Verify CORS: Check browser console for CORS errors"
echo ""

# Create a helper script to switch between domain and IP modes
cat > "$DEPLOY_DIR/switch-access-mode.sh" <<'SCRIPT'
#!/bin/bash
# Switch between domain and IP access modes

MODE=$1
if [ "$MODE" = "domain" ]; then
  echo "Switching to domain mode..."
  rm -f docker-compose.override.yml
  docker-compose restart
elif [ "$MODE" = "ip" ]; then
  echo "Switching to IP mode..."
  ./configure-ip-access.sh
else
  echo "Usage: $0 [domain|ip]"
fi
SCRIPT

chmod +x "$DEPLOY_DIR/switch-access-mode.sh"

echo "💡 To switch access modes later:"
echo "  • Domain mode: ./switch-access-mode.sh domain"
echo "  • IP mode: ./switch-access-mode.sh ip"
echo ""