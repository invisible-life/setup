#!/bin/bash

set -euo pipefail

# --- Configuration ---
STAGE_FILE="/tmp/.invisible_setup_stage"
LOCK_FILE="/var/lock/invisible_setup.lock"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/invisible}"
CONFIG_IMAGE="${CONFIG_IMAGE:-invisiblelife/orchestrator:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Color codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_header() {
  echo ""
  echo "======================================================================="
  echo "  $1"
  echo "======================================================================="
}

print_error() {
  echo -e "${RED}❌ Error: $1${NC}" >&2
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  Warning: $1${NC}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

check_prerequisites() {
  print_header "Checking Prerequisites"
  
  # Check if running as root
  if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run with sudo."
    exit 1
  fi
  
  # Check SUDO_USER
  if [ -z "${SUDO_USER:-}" ]; then
    SUDO_USER=$(logname 2>/dev/null || echo "root")
    print_warning "SUDO_USER not set, using: $SUDO_USER"
  fi
  
  # Check Ubuntu/Debian
  if [ ! -f /etc/debian_version ]; then
    print_error "This script only supports Ubuntu/Debian systems."
    exit 1
  fi
  
  # Check network connectivity
  print_header "Checking Network Connectivity"
  if ! ping -c 1 -W 2 google.com >/dev/null 2>&1; then
    print_error "No internet connection detected."
    exit 1
  fi
  
  if ! timeout 5 bash -c 'cat < /dev/null > /dev/tcp/hub.docker.com/443' 2>/dev/null; then
    print_warning "Cannot verify Docker Hub connectivity, but continuing..."
  fi
  
  print_success "Network connectivity verified"
}

retry_command() {
  local max_attempts=3
  local attempt=1
  local cmd="$@"
  
  while [ $attempt -le $max_attempts ]; do
    if eval "$cmd"; then
      return 0
    fi
    print_warning "Attempt $attempt failed. Retrying..."
    attempt=$((attempt + 1))
    sleep 2
  done
  
  print_error "Command failed after $max_attempts attempts: $cmd"
  return 1
}

save_stage() {
  echo "$1" > "$STAGE_FILE.tmp"
  mv -f "$STAGE_FILE.tmp" "$STAGE_FILE"
  print_success "Stage $1 completed successfully."
}

get_current_stage() {
  if [ -f "$STAGE_FILE" ]; then
    cat "$STAGE_FILE"
  else
    echo "0"
  fi
}

save_config() {
  cat > /tmp/.invisible_setup_config <<EOF
DOCKER_USERNAME="${DOCKER_USERNAME:-}"
APP_DOMAIN="${APP_DOMAIN:-}"
NO_DOMAIN="${NO_DOMAIN:-false}"
EOF
}

load_config() {
  if [ -f /tmp/.invisible_setup_config ]; then
    source /tmp/.invisible_setup_config
  fi
}

cleanup_on_error() {
  print_error "Setup failed. Cleaning up..."
  rm -f "$LOCK_FILE"
  # Optionally clean up partial installation
  # docker-compose down 2>/dev/null || true
}

wait_for_service() {
  local service=$1
  local timeout=${2:-60}
  local elapsed=0
  
  echo -n "Waiting for $service to start"
  while [ $elapsed -lt $timeout ]; do
    if sudo -u ${SUDO_USER} docker ps | grep -q "$service.*Up"; then
      echo ""
      return 0
    fi
    echo -n "."
    sleep 2
    elapsed=$((elapsed + 2))
  done
  
  echo ""
  print_error "Service $service failed to start within $timeout seconds"
  return 1
}

check_port() {
  local port=$1
  if lsof -i :$port >/dev/null 2>&1; then
    print_warning "Port $port is already in use"
    return 1
  fi
  return 0
}

# --- Stage Functions ---
stage_1_install_dependencies() {
  print_header "Stage 1: Installing Dependencies"
  
  # Update package list
  print_header "Updating package list"
  retry_command "apt-get update -qq"
  
  # Install all required packages
  local packages=(
    "ca-certificates"
    "curl"
    "gnupg"
    "lsb-release"
    "jq"
    "ufw"
    "lsof"
    "netcat-openbsd"
  )
  
  for pkg in "${packages[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
      print_header "Installing $pkg"
      retry_command "apt-get install -y $pkg"
    else
      print_success "$pkg is already installed"
    fi
  done
  
  # Install Docker using official script
  if ! command_exists docker; then
    print_header "Installing Docker"
    retry_command "curl -fsSL https://get.docker.com | sh"
    usermod -aG docker ${SUDO_USER}
  else
    print_success "Docker is already installed"
  fi
  
  # Verify Docker daemon is running
  if ! systemctl is-active --quiet docker; then
    systemctl start docker
    systemctl enable docker
  fi
  
  # Install Docker Compose v2
  if ! docker compose version >/dev/null 2>&1; then
    print_header "Installing Docker Compose"
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    retry_command "curl -SL https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose"
    chmod +x /usr/local/bin/docker-compose
  else
    print_success "Docker Compose is already installed"
  fi
  
  save_stage 1
}

stage_2_docker_login() {
  print_header "Stage 2: Docker Hub Login"
  
  # Check if already logged in by trying to pull a small image
  if docker pull hello-world >/dev/null 2>&1; then
    print_success "Already logged into Docker Hub"
  else
    if [ -z "${DOCKER_PASSWORD:-}" ]; then
      print_error "Docker password required for login."
      echo "Please run with --docker-password or provide it interactively."
      exit 1
    fi
    
    echo "$DOCKER_PASSWORD" | sudo -u ${SUDO_USER} docker login -u "$DOCKER_USERNAME" --password-stdin
    print_success "Logged into Docker Hub successfully"
  fi
  
  save_stage 2
}

stage_3_fetch_config() {
  print_header "Stage 3: Fetching Configuration Files"
  
  # Create deployment directory
  if [ ! -d "$DEPLOY_DIR" ]; then
    mkdir -p "$DEPLOY_DIR"
    chown ${SUDO_USER}:${SUDO_USER} "$DEPLOY_DIR"
  fi
  
  # Pull the orchestrator configuration image
  print_header "Pulling orchestrator configuration image"
  if ! retry_command "sudo -u ${SUDO_USER} docker pull $CONFIG_IMAGE"; then
    print_error "Failed to pull configuration image: $CONFIG_IMAGE"
    exit 1
  fi
  
  # Create a temporary container to extract files
  CONTAINER_ID=$(sudo -u ${SUDO_USER} docker create "$CONFIG_IMAGE")
  
  print_header "Extracting configuration files"
  if ! sudo -u ${SUDO_USER} docker cp "$CONTAINER_ID:/app/." "$DEPLOY_DIR"; then
    print_error "Failed to extract configuration files"
    docker rm -v "$CONTAINER_ID" 2>/dev/null || true
    exit 1
  fi
  
  # Clean up container
  sudo -u ${SUDO_USER} docker rm -v "$CONTAINER_ID"
  
  # Verify essential files
  local required_files=("setup.sh" "docker-compose.yml")
  for file in "${required_files[@]}"; do
    if [ ! -f "$DEPLOY_DIR/$file" ]; then
      print_error "Required file missing: $file"
      exit 1
    fi
  done
  
  # Copy helper scripts if they exist
  if [ -f "$SCRIPT_DIR/configure-ip-access.sh" ]; then
    cp "$SCRIPT_DIR/configure-ip-access.sh" "$DEPLOY_DIR/"
    chmod +x "$DEPLOY_DIR/configure-ip-access.sh"
  fi
  
  if [ -f "$SCRIPT_DIR/get-email-code.sh" ]; then
    cp "$SCRIPT_DIR/get-email-code.sh" "$DEPLOY_DIR/"
    chmod +x "$DEPLOY_DIR/get-email-code.sh"
  fi
  
  print_success "Configuration files extracted successfully"
  
  save_stage 3
}

stage_4_generate_env() {
  print_header "Stage 4: Generating Environment Configuration"
  
  cd "$DEPLOY_DIR"
  
  export APP_DOMAIN="$APP_DOMAIN"
  export DOCKER_HUB_TOKEN="${DOCKER_PASSWORD:-}"
  export NO_DOMAIN="${NO_DOMAIN:-false}"
  
  print_header "Running configuration script"
  if ! sudo -E -u ${SUDO_USER} ./setup.sh; then
    print_error "Configuration script failed"
    exit 1
  fi
  
  # Verify .env was created
  if [ ! -f "$DEPLOY_DIR/.env" ]; then
    print_error "Environment file was not created"
    exit 1
  fi
  
  print_success "Configuration generated successfully"
  
  save_stage 4
}

stage_5_start_services() {
  print_header "Stage 5: Starting Application Services"
  
  cd "$DEPLOY_DIR"
  
  # Check port availability
  local ports=(80 443)
  for port in "${ports[@]}"; do
    if ! check_port $port; then
      print_error "Required port $port is not available"
      exit 1
    fi
  done
  
  # Configure IP access if in no-domain mode
  if [ "$NO_DOMAIN" = "true" ]; then
    print_header "Configuring services for IP-based access"
    if [ -f "$DEPLOY_DIR/configure-ip-access.sh" ]; then
      SERVER_IP=$(curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null || echo "localhost")
      ./configure-ip-access.sh "$SERVER_IP"
    fi
  fi
  
  # Use correct docker compose command
  if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
  else
    DOCKER_COMPOSE="docker-compose"
  fi
  
  # Pull all images with retry
  print_header "Pulling Docker images"
  if ! retry_command "sudo -E -u ${SUDO_USER} $DOCKER_COMPOSE pull"; then
    print_error "Failed to pull Docker images"
    exit 1
  fi
  
  print_header "Starting all services"
  if ! sudo -E -u ${SUDO_USER} $DOCKER_COMPOSE up -d; then
    print_error "Failed to start services"
    exit 1
  fi
  
  # Wait for critical services
  wait_for_service "postgres" 60
  wait_for_service "supabase_kong" 60
  wait_for_service "caddy" 30
  
  # Verify services are running
  local running_count=$(sudo -u ${SUDO_USER} $DOCKER_COMPOSE ps | grep -c "Up" || true)
  if [ "$running_count" -lt 5 ]; then
    print_warning "Some services may not have started correctly"
    sudo -u ${SUDO_USER} $DOCKER_COMPOSE ps
  else
    print_success "All services started successfully"
  fi
  
  save_stage 5
}

stage_6_configure_firewall() {
  print_header "Stage 6: Configuring UFW Firewall"
  
  # Check if UFW is active
  if ! ufw status | grep -q "Status: active"; then
    print_header "Enabling UFW firewall"
    ufw --force enable
  fi
  
  # Configure firewall rules
  ufw allow 22/tcp comment "SSH"
  ufw allow 80/tcp comment "HTTP"
  ufw allow 443/tcp comment "HTTPS"
  
  print_success "Firewall configured successfully"
  ufw status numbered
  
  save_stage 6
}

# --- Argument Parsing ---
usage() {
  echo "Usage: sudo $0 [OPTIONS]"
  echo "This script provisions the Invisible platform using Docker Hub."
  echo ""
  echo "Options:"
  echo "  --docker-username    <username>       Your Docker Hub username."
  echo "  --docker-password    <password>       Your Docker Hub password or access token."
  echo "  --app-domain         <domain>         The root domain for the application."
  echo "  --no-domain                           Set up without a domain (IP access only)."
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

# Parse arguments
START_STAGE=""
RESET_SETUP=false
NO_DOMAIN=false

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --docker-username) DOCKER_USERNAME="$2"; shift; shift ;;
    --docker-password) DOCKER_PASSWORD="$2"; shift; shift ;;
    --app-domain) APP_DOMAIN="$2"; shift; shift ;;
    --no-domain) NO_DOMAIN=true; shift ;;
    --stage) START_STAGE="$2"; shift; shift ;;
    --list-stages) list_stages; exit 0 ;;
    --reset) RESET_SETUP=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# --- Main Script ---

# Set up error handling
trap cleanup_on_error ERR

# Check for lock file
if [ -f "$LOCK_FILE" ]; then
  print_error "Setup is already running (lock file exists at $LOCK_FILE)"
  echo "If you're sure no other instance is running, remove the lock file and try again."
  exit 1
fi

# Create lock file
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# Run prerequisite checks
check_prerequisites

# Reset if requested
if [ "$RESET_SETUP" = true ]; then
  print_header "Resetting setup progress"
  rm -f "$STAGE_FILE" /tmp/.invisible_setup_config
  print_success "Setup progress reset"
fi

# Load saved configuration
load_config

# Get current stage
CURRENT_STAGE=$(get_current_stage)

# Determine starting stage
if [ -n "$START_STAGE" ]; then
  if [ "$START_STAGE" -lt 1 ] || [ "$START_STAGE" -gt 6 ]; then
    print_error "Invalid stage number. Must be between 1 and 6."
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

# Interactive prompts for missing arguments
if [ "$CURRENT_STAGE" -lt 2 ]; then
  if [ -z "${DOCKER_USERNAME:-}" ]; then
    read -p "Enter your Docker Hub username: " DOCKER_USERNAME
  fi
  
  if [ -z "${DOCKER_PASSWORD:-}" ]; then
    read -sp "Enter your Docker Hub password or access token: " DOCKER_PASSWORD
    echo ""
  fi
fi

if [ "$CURRENT_STAGE" -lt 4 ]; then
  if [ "$NO_DOMAIN" = false ] && [ -z "${APP_DOMAIN:-}" ]; then
    echo ""
    echo "Do you want to set up with a domain name?"
    echo "  1) Yes, I have a domain (recommended for production)"
    echo "  2) No, IP access only (for development/testing)"
    read -p "Choose an option (1-2): " DOMAIN_CHOICE
    
    if [ "$DOMAIN_CHOICE" = "1" ]; then
      read -p "Enter the root domain for the application (e.g., example.com): " APP_DOMAIN
    else
      NO_DOMAIN=true
      APP_DOMAIN="localhost"
    fi
  elif [ "$NO_DOMAIN" = true ]; then
    APP_DOMAIN="localhost"
  fi
fi

# Save configuration
save_config

# Validate required inputs
if [ "$CURRENT_STAGE" -lt 2 ] && [ -z "${DOCKER_USERNAME:-}" ]; then
  print_error "Docker username is required."
  exit 1
fi

if [ "$CURRENT_STAGE" -lt 4 ] && [ -z "${APP_DOMAIN:-}" ] && [ "$NO_DOMAIN" = false ]; then
  print_error "App domain is required."
  exit 1
fi

# Execute stages
if [ "$CURRENT_STAGE" -lt 1 ]; then stage_1_install_dependencies; fi
if [ "$CURRENT_STAGE" -lt 2 ]; then stage_2_docker_login; fi
if [ "$CURRENT_STAGE" -lt 3 ]; then stage_3_fetch_config; fi
if [ "$CURRENT_STAGE" -lt 4 ]; then stage_4_generate_env; fi
if [ "$CURRENT_STAGE" -lt 5 ]; then stage_5_start_services; fi
if [ "$CURRENT_STAGE" -lt 6 ]; then stage_6_configure_firewall; fi

# Cleanup
rm -f "$STAGE_FILE" /tmp/.invisible_setup_config

# Get server IP
SERVER_IP=$(curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

# Final output
print_header "🎉 Invisible Platform Setup Complete! 🎉"

echo ""
print_success "COMPLETED SETUP:"
echo "  • Docker & dependencies installed"
echo "  • Environment configured with secure keys"
echo "  • All services started successfully"
echo "  • Firewall configured (ports 22, 80, 443 open)"
echo ""

if [ "$NO_DOMAIN" = false ]; then
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
  print_warning "If using Cloudflare, set proxy status to 'DNS Only' (gray cloud)"
  echo ""
else
  print_header "📋 Local Access Configuration"
  
  echo ""
  echo "Your services are configured for IP-based access."
  echo ""
  echo "To add a domain later, run:"
  echo "  ./add-domain.sh"
  echo ""
fi

print_header "🔐 Security Checklist"

echo ""
if [ "$NO_DOMAIN" = false ]; then
  echo "□ DNS records configured (see above)"
  echo "□ Domain DNS propagated (check with: nslookup api.$APP_DOMAIN)"
  echo "□ SSL certificates auto-provisioned by Caddy (happens on first access)"
fi
echo "□ Change default passwords in production"
echo "□ Set up regular backups for /opt/invisible/.env and database"
echo "□ Monitor disk space (Docker images/logs can grow)"
echo ""

print_header "🚀 Next Steps"

echo ""
if [ "$NO_DOMAIN" = false ]; then
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
else
  echo "Access your applications via IP address:"
  echo "   • Chat UI: https://$SERVER_IP/ or https://$SERVER_IP/chat"
  echo "   • Hub UI: https://$SERVER_IP/hub"
  echo "   • API: https://$SERVER_IP/api"
  echo "   • PostgreSQL: $SERVER_IP:5432"
  echo "   • Mailpit: http://$SERVER_IP:54324"
  echo ""
  print_header "🔒 Certificate Note"
  echo "   Using HTTPS with self-signed certificates."
  echo "   Your browser will show a security warning - this is normal."
  echo "   Click 'Advanced' and 'Proceed' to access the sites."
  echo ""
  echo "✨ Benefits of path-based routing:"
  echo "   • Only need ports 80/443 open in firewall"
  echo "   • Cleaner URLs without port numbers"
  echo "   • All services on single HTTPS endpoint"
  echo ""
  echo "To add a domain later for trusted certificates:"
  echo "   ./add-domain.sh"
fi
echo ""
echo "Note: First access may take 30-60 seconds while services initialize"
echo ""

print_success "Setup completed successfully!"