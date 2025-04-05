#!/bin/bash

# Prompt for username and password
read -p "Enter username (will also be used as domain prefix, e.g., username.local): " USERNAME
read -s -p "Enter password: " PASSWORD
echo

# Set domain and project directory
DOMAIN="${USERNAME}.local"
PROJECT_DIR="$(pwd)/alertlocal"
LOG_FILE="$PROJECT_DIR/deploy.log"
echo "Deploying for domain: $DOMAIN" | tee -a "$LOG_FILE"
echo "Project directory: $PROJECT_DIR" | tee -a "$LOG_FILE"

# Function to check if a command succeeded
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed. See $LOG_FILE for details." | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Create project structure
echo "Creating project structure..." | tee -a "$LOG_FILE"
mkdir -p "$PROJECT_DIR/docker/nginx/sites" "$PROJECT_DIR/docker/php" "$PROJECT_DIR/src/www" "$PROJECT_DIR/src/api" "$PROJECT_DIR/src/auth" "$PROJECT_DIR/src/admin"
check_status "Directory creation"

# Source helper scripts
source ./create_files.sh
source ./provision.sh

# Create all necessary files
create_docker_compose
create_php_dockerfile
create_nginx_conf
create_subdomain_confs
create_env_file
create_readme

# Provision the environment
provision_environment

# Wait for services and log status
echo "Waiting for services to start..." | tee -a "$LOG_FILE"
sleep 10
docker-compose ps >> "$LOG_FILE" 2>&1
check_status "Docker services startup"

echo "Deployment complete! Run ./test_alertlocal.sh to verify." | tee -a "$LOG_FILE"
echo "Access your services at:" | tee -a "$LOG_FILE"
echo "- Moodle: http://www.$DOMAIN" | tee -a "$LOG_FILE"
echo "- API: http://api.$DOMAIN" | tee -a "$LOG_FILE"
echo "- OAuth2: http://auth.$DOMAIN" | tee -a "$LOG_FILE"
echo "- Admin: http://admin.$DOMAIN" | tee -a "$LOG_FILE"