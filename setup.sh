#!/bin/bash

set -e

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
  echo "This script provisions the Invisible platform using only Docker Hub."
  echo ""
  echo "Options:"
  echo "  --docker-username    <username>       Your Docker Hub username."
  echo "  --docker-password    <password>       Your Docker Hub password or access token."
  echo "  --app-domain         <domain>         The root domain for the application (e.g., example.com)."
  echo "  -h, --help                            Display this help message."
}

# --- Argument Parsing & Interactive Prompts ---
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --docker-username) DOCKER_USERNAME="$2"; shift; shift ;;
    --docker-password) DOCKER_PASSWORD="$2"; shift; shift ;;
    --app-domain) APP_DOMAIN="$2"; shift; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Interactive prompts for any missing arguments
if [ -z "$DOCKER_USERNAME" ]; then
  read -p "Enter your Docker Hub username: " DOCKER_USERNAME
fi

if [ -z "$DOCKER_PASSWORD" ]; then
  read -sp "Enter your Docker Hub password or access token: " DOCKER_PASSWORD
  echo ""
fi

if [ -z "$APP_DOMAIN" ]; then
  read -p "Enter the root domain for the application (e.g., example.com): " APP_DOMAIN
fi

# Final validation
if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$APP_DOMAIN" ]; then
    echo "Error: One or more required values were not provided. Aborting."; exit 1
fi

# --- Main Script ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run with sudo."; usage; exit 1
fi

print_header "Welcome to the Invisible Platform Setup Script (Docker Hub Edition)"

# 1. Install Dependencies
print_header "Installing Dependencies (Docker, Docker Compose)"
if ! command_exists docker || ! command_exists docker-compose; then
  apt-get update
  apt-get install -y docker.io docker-compose jq
  usermod -aG docker ${SUDO_USER}
  echo "Docker and Docker Compose installed. You may need to log out and back in for group changes to apply."
else
  echo "Docker and Docker Compose are already installed."
fi

# 2. Log in to Docker Hub
print_header "Logging into Docker Hub"
docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD"

# 3. Fetch and Extract Configuration Files
print_header "Fetching Configuration from Docker Hub"
CONFIG_IMAGE="invisiblelife/orchestrator-config:latest"
DEPLOY_DIR="/opt/invisible"

mkdir -p "$DEPLOY_DIR"
chown ${SUDO_USER}:${SUDO_USER} "$DEPLOY_DIR"

echo "Pulling configuration image: $CONFIG_IMAGE"
sudo -u ${SUDO_USER} docker pull "$CONFIG_IMAGE"

# Create a dummy container to copy files from
CONTAINER_ID=$(sudo -u ${SUDO_USER} docker create "$CONFIG_IMAGE")

echo "Extracting configuration files to $DEPLOY_DIR..."
# Use docker cp to extract the entire config directory from the image
sudo -u ${SUDO_USER} docker cp "$CONTAINER_ID:/config/." "$DEPLOY_DIR"

# Clean up the dummy container
sudo -u ${SUDO_USER} docker rm -v "$CONTAINER_ID"

cd "$DEPLOY_DIR"

# 4. Generate .env and Kong Configuration
print_header "Generating Configuration Files (.env, kong.yml)"

export APP_DOMAIN="$APP_DOMAIN"

echo "Running configuration script..."
# Run the extracted setup script as the original user
sudo -E -u ${SUDO_USER} ./setup.sh

echo "Configuration generated successfully."

# 5. Launch the Application Stack
print_header "Pulling Latest Docker Images and Starting Application"

# Run as the user again
sudo -E -u ${SUDO_USER} docker-compose pull

echo "Starting all services..."
sudo -E -u ${SUDO_USER} docker-compose up -d

print_header "🎉 Invisible Platform Setup Complete! 🎉"
echo "Your application stack is now running."
echo "You can check the status with: cd $DEPLOY_DIR && sudo -u ${SUDO_USER} docker-compose ps"
