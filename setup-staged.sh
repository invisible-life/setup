#!/bin/bash

set -e

# --- Configuration ---
STAGE_FILE="/tmp/.invisible_setup_stage"
DEPLOY_DIR="/opt/invisible"
CONFIG_IMAGE="invisiblelife/orchestrator-config:latest"

# --- Helper Functions ---
print_header() {
  echo ""
  echo "======================================================================="
  echo "  $1"
  echo "======================================================================="
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  echo "Usage: sudo $0 [OPTIONS]"
  echo "This script provisions the Invisible platform using Docker Hub."
  echo ""
  echo "Options:"
  echo "  --docker-username    <username>       Your Docker Hub username."
  echo "  --docker-password    <password>       Your Docker Hub password or access token."
  echo "  --app-domain         <domain>         The root domain for the application (e.g., example.com)."
  echo "  --stage              <number>         Start from a specific stage (1-6)."
  echo "  --list-stages                         List all available stages."
  echo "  --reset                               Reset setup progress and start fresh."
  echo "  -h, --help                            Display this help message."
}

list_stages() {
  echo "Available setup stages:"
  echo "  1. Install Dependencies (Docker, Docker Compose, UFW)"
  echo "  2. Docker Hub Login"
  echo "  3. Fetch Configuration Files"
  echo "  4. Generate Environment Configuration"
  echo "  5. Pull Images and Start Services"
  echo "  6. Configure Firewall"
}

save_stage() {
  echo "$1" > "$STAGE_FILE"
  echo "✅ Stage $1 completed successfully."
}

get_current_stage() {
  if [ -f "$STAGE_FILE" ]; then
    cat "$STAGE_FILE"
  else
    echo "0"
  fi
}

save_config() {
  # Save configuration for resume
  cat > /tmp/.invisible_setup_config <<EOF
DOCKER_USERNAME="${DOCKER_USERNAME}"
APP_DOMAIN="${APP_DOMAIN}"
EOF
  # Note: We don't save the password for security reasons
}

load_config() {
  if [ -f /tmp/.invisible_setup_config ]; then
    source /tmp/.invisible_setup_config
  fi
}

# --- Stage Functions ---
stage_1_install_dependencies() {
  print_header "Stage 1: Installing Dependencies (Docker, Docker Compose, UFW)"
  
  if ! command_exists docker || ! command_exists docker-compose || ! command_exists ufw; then
    apt-get update
    apt-get install -y docker.io docker-compose jq ufw
    usermod -aG docker ${SUDO_USER}
    echo "Docker, Docker Compose, and UFW installed."
  else
    echo "All dependencies are already installed."
  fi
  
  save_stage 1
}

stage_2_docker_login() {
  print_header "Stage 2: Docker Hub Login"
  
  # Check if already logged in
  if docker pull hello-world >/dev/null 2>&1; then
    echo "Already logged into Docker Hub."
  else
    if [ -z "$DOCKER_PASSWORD" ]; then
      echo "❌ Error: Docker password required for login."
      echo "Please run with --docker-password or provide it interactively."
      exit 1
    fi
    docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD"
  fi
  
  save_stage 2
}

stage_3_fetch_config() {
  print_header "Stage 3: Fetching Configuration from Docker Hub"
  
  mkdir -p "$DEPLOY_DIR"
  chown ${SUDO_USER}:${SUDO_USER} "$DEPLOY_DIR"
  
  echo "Pulling configuration image: $CONFIG_IMAGE"
  sudo -u ${SUDO_USER} docker pull "$CONFIG_IMAGE"
  
  # Create a dummy container to copy files from
  CONTAINER_ID=$(sudo -u ${SUDO_USER} docker create "$CONFIG_IMAGE")
  
  echo "Extracting configuration files to $DEPLOY_DIR..."
  sudo -u ${SUDO_USER} docker cp "$CONTAINER_ID:/config/." "$DEPLOY_DIR"
  
  # Clean up the dummy container
  sudo -u ${SUDO_USER} docker rm -v "$CONTAINER_ID"
  
  save_stage 3
}

stage_4_generate_env() {
  print_header "Stage 4: Generating Environment Configuration"
  
  cd "$DEPLOY_DIR"
  
  export APP_DOMAIN="$APP_DOMAIN"
  export DOCKER_HUB_TOKEN="$DOCKER_PASSWORD"
  
  echo "Running configuration script..."
  sudo -E -u ${SUDO_USER} ./setup.sh
  
  echo "Configuration generated successfully."
  
  save_stage 4
}

stage_5_start_services() {
  print_header "Stage 5: Starting Application Services"
  
  cd "$DEPLOY_DIR"
  
  # Pull all images
  echo "Pulling Docker images..."
  sudo -E -u ${SUDO_USER} docker-compose pull
  
  echo "Starting all services..."
  sudo -E -u ${SUDO_USER} docker-compose up -d
  
  # Wait a bit for services to start
  echo "Waiting for services to initialize..."
  sleep 10
  
  # Check if services are running
  if sudo -u ${SUDO_USER} docker-compose ps | grep -q "Up"; then
    echo "Services started successfully."
  else
    echo "⚠️  Warning: Some services may not have started correctly."
    echo "Check with: cd $DEPLOY_DIR && docker-compose ps"
  fi
  
  save_stage 5
}

stage_6_configure_firewall() {
  print_header "Stage 6: Configuring UFW Firewall"
  
  # Check if UFW is already enabled
  if ufw status | grep -q "Status: active"; then
    echo "UFW is already active. Adding rules..."
  else
    echo "Enabling UFW with necessary rules..."
  fi
  
  # Allow SSH (port 22) - important to do this first
  ufw allow 22/tcp comment 'SSH access'
  
  # Allow HTTP and HTTPS for Caddy reverse proxy
  ufw allow 80/tcp comment 'HTTP for Caddy'
  ufw allow 443/tcp comment 'HTTPS for Caddy'
  ufw allow 443/udp comment 'HTTP/3 QUIC for Caddy'
  
  # Enable UFW if not already enabled
  if ! ufw status | grep -q "Status: active"; then
    ufw --force enable
    echo "UFW firewall enabled with rules for SSH, HTTP, and HTTPS."
  else
    echo "UFW rules updated."
  fi
  
  # Show the final firewall status
  echo ""
  echo "Current firewall status:"
  ufw status numbered
  
  save_stage 6
}

# --- Argument Parsing ---
START_STAGE=""
RESET_SETUP=false

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --docker-username) DOCKER_USERNAME="$2"; shift; shift ;;
    --docker-password) DOCKER_PASSWORD="$2"; shift; shift ;;
    --app-domain) APP_DOMAIN="$2"; shift; shift ;;
    --stage) START_STAGE="$2"; shift; shift ;;
    --list-stages) list_stages; exit 0 ;;
    --reset) RESET_SETUP=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# --- Main Script ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run with sudo."; usage; exit 1
fi

# Reset if requested
if [ "$RESET_SETUP" = true ]; then
  echo "Resetting setup progress..."
  rm -f "$STAGE_FILE" /tmp/.invisible_setup_config
  echo "Setup progress reset. Starting fresh."
fi

# Load saved configuration
load_config

# Get current stage
CURRENT_STAGE=$(get_current_stage)

# Determine starting stage
if [ -n "$START_STAGE" ]; then
  if [ "$START_STAGE" -lt 1 ] || [ "$START_STAGE" -gt 6 ]; then
    echo "Error: Invalid stage number. Must be between 1 and 6."
    list_stages
    exit 1
  fi
  CURRENT_STAGE=$((START_STAGE - 1))
else
  # If we have a saved stage, ask if they want to resume
  if [ "$CURRENT_STAGE" -gt 0 ] && [ "$CURRENT_STAGE" -lt 6 ]; then
    echo "Previous setup detected at stage $CURRENT_STAGE."
    read -p "Do you want to resume from stage $((CURRENT_STAGE + 1))? (y/n): " RESUME
    if [ "$RESUME" != "y" ] && [ "$RESUME" != "Y" ]; then
      CURRENT_STAGE=0
    fi
  fi
fi

print_header "Welcome to the Invisible Platform Setup Script"
echo "Starting from stage $((CURRENT_STAGE + 1))..."

# Interactive prompts for any missing arguments (only if starting fresh or early stages)
if [ "$CURRENT_STAGE" -lt 2 ]; then
  if [ -z "$DOCKER_USERNAME" ]; then
    read -p "Enter your Docker Hub username: " DOCKER_USERNAME
  fi
  
  if [ -z "$DOCKER_PASSWORD" ]; then
    read -sp "Enter your Docker Hub password or access token: " DOCKER_PASSWORD
    echo ""
  fi
fi

if [ "$CURRENT_STAGE" -lt 4 ]; then
  if [ -z "$APP_DOMAIN" ]; then
    read -p "Enter the root domain for the application (e.g., example.com): " APP_DOMAIN
  fi
fi

# Save configuration for potential resume
save_config

# Validate required inputs based on stage
if [ "$CURRENT_STAGE" -lt 2 ] && [ -z "$DOCKER_USERNAME" ]; then
  echo "Error: Docker username is required."; exit 1
fi

if [ "$CURRENT_STAGE" -lt 4 ] && [ -z "$APP_DOMAIN" ]; then
  echo "Error: App domain is required."; exit 1
fi

# Execute stages
if [ "$CURRENT_STAGE" -lt 1 ]; then stage_1_install_dependencies; fi
if [ "$CURRENT_STAGE" -lt 2 ]; then stage_2_docker_login; fi
if [ "$CURRENT_STAGE" -lt 3 ]; then stage_3_fetch_config; fi
if [ "$CURRENT_STAGE" -lt 4 ]; then stage_4_generate_env; fi
if [ "$CURRENT_STAGE" -lt 5 ]; then stage_5_start_services; fi
if [ "$CURRENT_STAGE" -lt 6 ]; then stage_6_configure_firewall; fi

# Cleanup stage file on successful completion
rm -f "$STAGE_FILE" /tmp/.invisible_setup_config

# Get server's public IP
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

print_header "🎉 Invisible Platform Setup Complete! 🎉"

echo ""
echo "✅ COMPLETED SETUP:"
echo "  • Docker & dependencies installed"
echo "  • Environment configured with secure keys"
echo "  • All services started successfully"
echo "  • Firewall configured (ports 22, 80, 443 open)"
echo ""

print_header "📋 REQUIRED: Manual DNS Configuration"

echo ""
echo "You MUST configure the following DNS records for your domain:"
echo ""
echo "Domain: $APP_DOMAIN"
echo "Server IP: $SERVER_IP"
echo ""
echo "Required A Records:"
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │ Type │ Name             │ Value          │ TTL  │ Proxy    │"
echo "  ├──────┼──────────────────┼────────────────┼──────┼──────────┤"
echo "  │ A    │ api.$APP_DOMAIN  │ $SERVER_IP     │ 3600 │ DNS Only │"
echo "  │ A    │ chat.$APP_DOMAIN │ $SERVER_IP     │ 3600 │ DNS Only │"
echo "  │ A    │ hub.$APP_DOMAIN  │ $SERVER_IP     │ 3600 │ DNS Only │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
echo "⚠️  IMPORTANT: If using Cloudflare, set proxy status to 'DNS Only' (gray cloud)"
echo ""

print_header "🔐 Security Checklist"

echo ""
echo "□ DNS records configured (see above)"
echo "□ Domain DNS propagated (check with: nslookup api.$APP_DOMAIN)"
echo "□ SSL certificates auto-provisioned by Caddy (happens on first access)"
echo "□ Change default passwords in production"
echo "□ Set up regular backups for /opt/invisible/.env and database"
echo "□ Monitor disk space (Docker images/logs can grow)"
echo ""

print_header "🚀 Next Steps"

echo ""
echo "1. Configure DNS records as shown above"
echo "2. Wait for DNS propagation (usually 5-30 minutes)"
echo "3. Test DNS resolution:"
echo "   nslookup api.$APP_DOMAIN"
echo "   nslookup chat.$APP_DOMAIN"
echo "   nslookup hub.$APP_DOMAIN"
echo ""
echo "4. Access your applications:"
echo "   • Chat UI: https://chat.$APP_DOMAIN"
echo "   • Hub UI: https://hub.$APP_DOMAIN"
echo "   • API: https://api.$APP_DOMAIN"
echo ""
echo "Note: First access may take 30-60 seconds while Caddy provisions SSL certificates"
echo ""

print_header "🛠️ Useful Management Commands"

echo ""
echo "View service status:"
echo "  cd $DEPLOY_DIR && docker-compose ps"
echo ""
echo "View logs:"
echo "  cd $DEPLOY_DIR && docker-compose logs -f [service_name]"
echo ""
echo "Restart all services:"
echo "  cd $DEPLOY_DIR && docker-compose restart"
echo ""
echo "Update images:"
echo "  cd $DEPLOY_DIR && docker-compose pull && docker-compose up -d"
echo ""
echo "View environment variables:"
echo "  cat $DEPLOY_DIR/.env"
echo ""

print_header "📧 Support"

echo ""
echo "If you encounter issues:"
echo "1. Check service logs: docker-compose logs -f"
echo "2. Verify DNS records are properly configured"
echo "3. Ensure firewall rules are active: sudo ufw status"
echo "4. Check Docker status: docker ps"
echo ""
echo "Setup completed successfully! 🎉"