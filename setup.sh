#!/bin/bash

set -e

# --- Helper Functions ---

# Function to print a section header
print_header() {
  echo ""
  echo "======================================================================="
  echo "  $1"
  echo "======================================================================="
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to display usage information
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "This script provisions a server to run the Invisible application stack."
  echo ""
  echo "Options:"
  echo "  --docker-username    <username>       Your Docker Hub username."
  echo "  --docker-password    <password>       Your Docker Hub password or access token."
  echo "  --app-domain         <domain>         The root domain for the application (e.g., example.com)."
  echo "  --postgres-password  <password>       The secret password for the Postgres database."
  echo "  --jwt-secret         <secret>         A long, random string for the JWT secret."
  echo "  -h, --help                            Display this help message."
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --docker-username)
      DOCKER_USERNAME="$2"
      shift; shift
      ;;
    --docker-password)
      DOCKER_PASSWORD="$2"
      shift; shift
      ;;
    --app-domain)
      APP_DOMAIN="$2"
      shift; shift
      ;;
    --postgres-password)
      POSTGRES_PASSWORD="$2"
      shift; shift
      ;;
    --jwt-secret)
      JWT_SECRET="$2"
      shift; shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Check for mandatory arguments
if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$APP_DOMAIN" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$JWT_SECRET" ]; then
    echo "Error: Missing one or more required arguments."
    usage
    exit 1
fi

# --- Main Script ---

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run with sudo. Please use 'sudo ./setup.sh'"
  exit 1
fi

print_header "Welcome to the Invisible Application Setup Script"
echo "This script will install Docker, Docker Compose, and set up the environment."

# 2. Install Dependencies
print_header "Installing Dependencies (Docker, Docker Compose, Git)"

if ! command_exists docker || ! command_exists docker-compose;
  apt-get update
  apt-get install -y docker.io docker-compose git

  # Add current user to the docker group to avoid using sudo for docker commands
  usermod -aG docker ${SUDO_USER}

  echo "Docker and Docker Compose installed successfully."
  echo "NOTE: You will need to log out and log back in for Docker group changes to apply."
 else
  echo "Docker and Docker Compose are already installed."
fi

# 3. Log in to Docker Hub
print_header "Logging into Docker Hub"
docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD"

# 4. Prepare Deployment Directory
print_header "Setting up Deployment Directory"

DEPLOY_DIR="/opt/invisible"
mkdir -p "$DEPLOY_DIR"

ORCHESTRATOR_IMAGE="kermankohli/invisible-orchestrator:latest"

echo "Pulling the latest orchestrator image: $ORCHESTRATOR_IMAGE"
docker pull "$ORCHESTRATOR_IMAGE"

# 5. Extract Orchestration Files
echo "Extracting orchestration files to $DEPLOY_DIR"

# Create a temporary container from the orchestrator image
CONTAINER_ID=$(docker create $ORCHESTRATOR_IMAGE)

# Copy all files from the container's /app directory
docker cp "$CONTAINER_ID:/app/." "$DEPLOY_DIR"

# Clean up the temporary container
docker rm -v "$CONTAINER_ID"

# 6. Create .env file
print_header "Creating Production .env File"

ENV_FILE="$DEPLOY_DIR/.env"

cat > "$ENV_FILE" << EOL
# --- Production Environment Variables ---

# Supabase/Postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Supabase/GoTrue
JWT_SECRET=$JWT_SECRET

# Caddy Reverse Proxy
APP_DOMAIN=$APP_DOMAIN
EOL

chown ${SUDO_USER}:${SUDO_USER} -R "$DEPLOY_DIR"

echo ".env file created successfully at $ENV_FILE"

# 7. Final Instructions
print_header "Setup Complete!"
echo "Your application is ready to be launched."
echo ""
echo "IMPORTANT: For Docker permissions to apply, please log out and log back in."
echo ""
echo "Once you have logged back in, you can manage your application with these commands:"
echo "  cd $DEPLOY_DIR"
  echo "  docker-compose pull       # To pull the latest service images"
  echo "  docker-compose up -d        # To start all services"
  echo "  docker-compose down       # To stop all services"
  echo "  docker-compose logs -f    # To view the logs of all services"
echo ""
