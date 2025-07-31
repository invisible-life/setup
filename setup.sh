#!/bin/bash
set -euo pipefail

# Invisible Platform Setup - Interactive Launcher
# This script provides an interactive setup experience for the Invisible platform

DEPLOY_DIR="/opt/invisible"
SCRIPT_VERSION="2.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print functions
print_header() {
  echo -e "\n${PURPLE}=======================================================================${NC}"
  echo -e "${PURPLE}  $1${NC}"
  echo -e "${PURPLE}=======================================================================${NC}\n"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_question() {
  echo -e "${CYAN}❓ $1${NC}"
}

# Usage function
usage() {
  echo -e "${CYAN}Invisible Platform Setup v${SCRIPT_VERSION}${NC}"
  echo "Usage: sudo $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --reset               Complete reset - remove all containers, images, and data"
  echo "  --non-interactive     Run in non-interactive mode (requires all parameters)"
  echo "  -u, --username USER   Docker Hub username"
  echo "  -p, --password PASS   Docker Hub password"
  echo "  -d, --domain DOMAIN   Custom domain (optional)"
  echo "  --no-domain          Use IP-based access instead of domain"
  echo "  --help               Show this help message"
  echo ""
  echo "Examples:"
  echo "  sudo $0                                    # Interactive setup"
  echo "  sudo $0 --reset                           # Complete system reset"
  echo "  sudo $0 --non-interactive -u user -p pass --no-domain"
}

# Reset function - completely wipe everything
reset_system() {
  print_header "COMPLETE SYSTEM RESET"
  print_warning "This will completely remove all Invisible platform components!"
  print_warning "This includes:"
  echo "  • All Kubernetes/k3s resources and cluster"
  echo "  • All Docker containers and images"
  echo "  • All platform data and configurations"
  echo "  • All port bindings and network configurations"
  echo "  • Deployment directory: $DEPLOY_DIR"
  echo ""
  
  if [ "$INTERACTIVE" = "true" ]; then
    print_question "Are you absolutely sure you want to proceed? (type 'YES' to confirm)"
    read -r confirmation
    if [ "$confirmation" != "YES" ]; then
      print_info "Reset cancelled."
      exit 0
    fi
  fi
  
  print_info "Starting complete system reset..."
  
  # Check if k3s/kubectl is available and clean up Kubernetes resources
  if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    print_info "Removing Kubernetes resources..."
    
    # Delete all resources in invisible namespace
    print_info "Deleting invisible namespace and all resources..."
    kubectl delete namespace invisible --force --grace-period=0 2>/dev/null || true
    
    # Delete ArgoCD if it exists
    print_info "Removing ArgoCD..."
    kubectl delete namespace argocd --force --grace-period=0 2>/dev/null || true
    
    # Delete any remaining PVCs in all namespaces
    print_info "Cleaning up persistent volume claims..."
    kubectl delete pvc --all --all-namespaces --force --grace-period=0 2>/dev/null || true
    
    # Delete any remaining PVs
    print_info "Cleaning up persistent volumes..."
    kubectl delete pv --all --force --grace-period=0 2>/dev/null || true
  fi
  
  # Uninstall k3s completely if it exists
  if command -v k3s-uninstall.sh >/dev/null 2>&1; then
    print_info "Uninstalling k3s..."
    k3s-uninstall.sh 2>/dev/null || true
  fi
  
  # Clean up k3s data directory if it still exists
  if [ -d "/var/lib/rancher/k3s" ]; then
    print_info "Removing k3s data directory..."
    rm -rf /var/lib/rancher/k3s
  fi
  
  # Clean up k3s config directory
  if [ -d "/etc/rancher/k3s" ]; then
    print_info "Removing k3s config directory..."
    rm -rf /etc/rancher/k3s
  fi
  
  # Stop all running containers
  print_info "Stopping all Docker containers..."
  docker stop $(docker ps -aq) 2>/dev/null || true
  
  # Remove all containers
  print_info "Removing all Docker containers..."
  docker rm $(docker ps -aq) 2>/dev/null || true
  
  # Remove all images
  print_info "Removing all Docker images..."
  docker rmi $(docker images -aq) 2>/dev/null || true
  
  # Clean up Docker system
  print_info "Cleaning up Docker system..."
  docker system prune -af --volumes 2>/dev/null || true
  
  # Remove Invisible-specific volumes
  print_info "Removing Invisible platform volumes..."
  for volume in $(docker volume ls -q | grep -E "^(app_|invisible_|k8s_)"); do
    docker volume rm "$volume" 2>/dev/null || true
  done
  
  # Remove deployment directory
  if [ -d "$DEPLOY_DIR" ]; then
    print_info "Removing deployment directory..."
    rm -rf "$DEPLOY_DIR"
  fi
  
  # Remove any .env files in the current directory
  print_info "Removing environment files from current directory..."
  rm -f .env .env.* *.env 2>/dev/null || true
  
  # Remove kubeconfig if it exists
  if [ -f "$HOME/.kube/config" ]; then
    print_info "Removing kubeconfig..."
    rm -f "$HOME/.kube/config"
  fi
  
  # Kill any processes using common ports
  print_info "Freeing up common ports..."
  for port in 80 443 8080 3000 4300 4400 4500 5432 6379 6443 8000 8098 30080 30081 30082 30083 30084; do
    lsof -ti:$port | xargs kill -9 2>/dev/null || true
  done
  
  # Clean up any CNI network interfaces
  print_info "Cleaning up network interfaces..."
  ip link show | grep -E "cni0|flannel|cali|vxlan" | awk -F: '{print $2}' | xargs -I {} ip link delete {} 2>/dev/null || true
  
  # Clean up iptables rules added by k3s
  print_info "Cleaning up iptables rules..."
  iptables -F 2>/dev/null || true
  iptables -X 2>/dev/null || true
  iptables -t nat -F 2>/dev/null || true
  iptables -t nat -X 2>/dev/null || true
  iptables -t mangle -F 2>/dev/null || true
  iptables -t mangle -X 2>/dev/null || true
  iptables -P INPUT ACCEPT 2>/dev/null || true
  iptables -P FORWARD ACCEPT 2>/dev/null || true
  iptables -P OUTPUT ACCEPT 2>/dev/null || true
  
  # Reset firewall rules (if ufw is installed)
  if command -v ufw >/dev/null 2>&1; then
    print_info "Resetting firewall rules..."
    ufw --force reset 2>/dev/null || true
  fi
  
  # Remove any systemd services created by k3s
  print_info "Cleaning up systemd services..."
  systemctl stop k3s k3s-agent 2>/dev/null || true
  systemctl disable k3s k3s-agent 2>/dev/null || true
  rm -f /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  
  print_success "System reset completed successfully!"
  print_info "You can now run the setup script again to reinstall the platform."
  exit 0
}

# Interactive prompts
prompt_docker_credentials() {
  if [ -z "$DOCKER_USERNAME" ]; then
    print_question "Enter your Docker Hub username:"
    read -r DOCKER_USERNAME
  fi
  
  if [ -z "$DOCKER_PASSWORD" ]; then
    print_question "Enter your Docker Hub password/token:"
    read -rs DOCKER_PASSWORD
    echo
  fi
  
  if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
    print_error "Docker credentials are required!"
    exit 1
  fi
}

prompt_domain_setup() {
  if [ -z "$DOMAIN" ] && [ "$NO_DOMAIN" != "true" ]; then
    print_question "Do you want to set up a custom domain? (y/n)"
    read -r setup_domain
    
    if [[ $setup_domain =~ ^[Yy]$ ]]; then
      print_question "Enter your domain name (e.g., example.com):"
      read -r DOMAIN
    else
      NO_DOMAIN="true"
    fi
  fi
}

confirm_setup() {
  print_header "SETUP CONFIRMATION"
  echo "Docker Username: $DOCKER_USERNAME"
  if [ "$NO_DOMAIN" = "true" ]; then
    echo "Access Method: IP-based access"
  else
    echo "Domain: $DOMAIN"
  fi
  echo ""
  print_question "Proceed with setup? (y/n)"
  read -r confirm
  
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    print_info "Setup cancelled."
    exit 0
  fi
}

# Check if running as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
  fi
}

# Install Docker if not present
install_docker() {
  if ! command -v docker &> /dev/null; then
    print_info "Docker not found. Installing Docker..."
    
    # Detect package manager and install Docker
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq
      curl -fsSL https://get.docker.com -o get-docker.sh
      sh get-docker.sh
      rm get-docker.sh
      systemctl start docker
      systemctl enable docker
    elif command -v yum >/dev/null 2>&1; then
      yum update -y
      curl -fsSL https://get.docker.com -o get-docker.sh
      sh get-docker.sh
      rm get-docker.sh
      systemctl start docker
      systemctl enable docker
    else
      print_error "Unsupported package manager. Please install Docker manually."
      exit 1
    fi
    
    print_success "Docker installed successfully!"
  else
    print_info "Docker is already installed."
  fi
}

# Main setup function
run_setup() {
  print_header "INVISIBLE PLATFORM SETUP"
  
  # Login to Docker Hub
  print_info "Logging into Docker Hub..."
  if echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin; then
    print_success "Docker Hub login successful!"
  else
    print_error "Docker Hub login failed!"
    exit 1
  fi
  
  # Create deployment directory
  print_info "Setting up deployment directory..."
  mkdir -p "$DEPLOY_DIR"
  
  # Auto-detect server IP if using IP-based access
  if [ "$NO_DOMAIN" = "true" ]; then
    print_info "Auto-detecting server IP address..."
    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "")
    if [ -n "$SERVER_IP" ]; then
      print_success "Detected IP: $SERVER_IP"
    else
      print_warning "Could not auto-detect IP. The setup will continue but you may need to configure it manually."
    fi
  fi
  
  # Check if user wants Kubernetes deployment
  print_question "Do you want to deploy with Kubernetes (k3s)? (y/n)"
  print_info "Choose 'n' for Docker Compose deployment"
  read -r use_kubernetes
  
  if [[ $use_kubernetes =~ ^[Yy]$ ]]; then
    # Install k3s on the host if not present
    if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
      print_info "Installing k3s on host system..."
      curl -sfL https://get.k3s.io | sh -
      
      # Wait for k3s to be ready
      print_info "Waiting for k3s to be ready..."
      sleep 10
      
      # Export kubeconfig for current session
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      
      # Wait for node to be ready
      print_info "Waiting for k3s node to be ready..."
      until kubectl get nodes | grep -q " Ready"; do
        echo -n "."
        sleep 5
      done
      echo ""
      print_success "k3s installed successfully!"
    else
      print_info "Kubernetes cluster already detected"
    fi
  fi
  
  # Prepare deployment arguments
  DEPLOY_ARGS=()
  DEPLOY_ARGS+=("--docker-username" "$DOCKER_USERNAME")
  DEPLOY_ARGS+=("--docker-password" "$DOCKER_PASSWORD")
  
  # Add deployment mode flag
  if [[ $use_kubernetes =~ ^[Yy]$ ]]; then
    # Kubernetes deployment - no flag needed as it's default
    :
  else
    # Use Docker Compose
    DEPLOY_ARGS+=("--docker-compose")
  fi
  
  if [ "$NO_DOMAIN" = "true" ]; then
    DEPLOY_ARGS+=("--no-domain")
    if [ -n "$SERVER_IP" ]; then
      DEPLOY_ARGS+=("--ip" "$SERVER_IP")
    fi
  elif [ -n "$DOMAIN" ]; then
    DEPLOY_ARGS+=("--domain" "$DOMAIN")
  fi
  
  # Run deployment container
  print_info "Running deployment container..."
  echo ""
  echo "=== Deployment Container Started ==="
  
  # Mount kubeconfig if using Kubernetes
  KUBECONFIG_MOUNT=""
  if [[ $use_kubernetes =~ ^[Yy]$ ]] && [ -f /etc/rancher/k3s/k3s.yaml ]; then
    KUBECONFIG_MOUNT="-v /etc/rancher/k3s/k3s.yaml:/root/.kube/config:ro"
  fi
  
  docker run --rm -it \
    -v "$DEPLOY_DIR:/opt/invisible" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    $KUBECONFIG_MOUNT \
    -e "DOCKER_USERNAME=$DOCKER_USERNAME" \
    -e "DOCKER_PASSWORD=$DOCKER_PASSWORD" \
    -e "SERVER_IP=${SERVER_IP:-}" \
    -e "API_PUBLIC_URL=${NO_DOMAIN:+http://${SERVER_IP}:30084}" \
    -e "SUPABASE_PUBLIC_URL=${NO_DOMAIN:+http://${SERVER_IP}:30082}" \
    -e "SITE_URL=${NO_DOMAIN:+http://${SERVER_IP}:30080}" \
    -e "API_EXTERNAL_URL=${NO_DOMAIN:+http://${SERVER_IP}:30082}" \
    --network host \
    --privileged \
    -w /app \
    invisiblelife/deploy:latest \
    scripts/setup.sh "${DEPLOY_ARGS[@]}"
}

# Initialize variables
INTERACTIVE="true"
DOCKER_USERNAME=""
DOCKER_PASSWORD=""
DOMAIN=""
NO_DOMAIN="false"
RESET="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --reset)
      RESET="true"
      shift
      ;;
    --non-interactive)
      INTERACTIVE="false"
      shift
      ;;
    -u|--username)
      DOCKER_USERNAME="$2"
      shift 2
      ;;
    -p|--password)
      DOCKER_PASSWORD="$2"
      shift 2
      ;;
    -d|--domain)
      DOMAIN="$2"
      shift 2
      ;;
    --no-domain)
      NO_DOMAIN="true"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Main execution
check_root

# Handle reset option
if [ "$RESET" = "true" ]; then
  reset_system
fi

# Show welcome message
print_header "INVISIBLE PLATFORM SETUP v${SCRIPT_VERSION}"
print_info "Welcome to the Invisible Platform interactive setup!"
echo ""

# Install Docker if needed
install_docker

# Interactive prompts (if in interactive mode)
if [ "$INTERACTIVE" = "true" ]; then
  prompt_docker_credentials
  prompt_domain_setup
  confirm_setup
else
  # Non-interactive mode validation
  if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
    print_error "Non-interactive mode requires Docker credentials (-u and -p)"
    exit 1
  fi
  
  if [ "$NO_DOMAIN" != "true" ] && [ -z "$DOMAIN" ]; then
    print_error "Non-interactive mode requires either --no-domain or -d DOMAIN"
    exit 1
  fi
fi

# Run the setup
run_setup

print_success "Setup completed! Check the output above for any final instructions."