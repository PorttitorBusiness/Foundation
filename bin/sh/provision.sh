#!/bin/bash

provision_environment() {
    echo "Provisioning environment..." | tee -a "$LOG_FILE"

    # Update /etc/hosts
    if ! grep -q "www.$DOMAIN" /etc/hosts; then
        echo "127.0.0.1 www.$DOMAIN api.$DOMAIN auth.$DOMAIN admin.$DOMAIN" | sudo tee -a /etc/hosts
        check_status "Updating /etc/hosts"
    fi

    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..." | tee -a "$LOG_FILE"
        sudo apt-get update
        sudo apt-get install -y docker.io docker-compose
        sudo usermod -aG docker $USER
        check_status "Docker installation"
    fi

    # Start Docker Compose
    cd "$PROJECT_DIR"
    docker-compose up -d --build >> "$LOG_FILE" 2>&1
    check_status "Docker Compose startup"

    # Install Moodle
    if [ ! -f "$PROJECT_DIR/src/www/config.php" ]; then
        echo "Downloading and configuring Moodle..." | tee -a "$LOG_FILE"
        wget -q https://download.moodle.org/stable404/moodle-latest-404.tgz -O /tmp/moodle.tgz
        tar -xzf /tmp/moodle.tgz -C "$PROJECT_DIR/src/www" --strip-components=1
        cat <<EOF > "$PROJECT_DIR/src/www/config.php"
<?php
\$CFG = new stdClass();
\$CFG->dbtype    = 'mysqli';
\$CFG->dbhost    = 'mysql';
\$CFG->dbname    = '${USERNAME}_db';
\$CFG->dbuser    = '$USERNAME';
\$CFG->dbpass    = '$PASSWORD';
\$CFG->wwwroot   = 'http://www.$DOMAIN';
\$CFG->dataroot  = '/var/www/www.$DOMAIN/moodledata';
\$CFG->admin     = 'admin';
require_once(__DIR__ . '/lib/setup.php');
EOF
        mkdir -p "$PROJECT_DIR/src/www/moodledata"
        chmod -R 777 "$PROJECT_DIR/src/www/moodledata"
    fi

    # Install Laminas API
    if [ ! -d "$PROJECT_DIR/src/api/vendor" ]; then
        echo "Installing Laminas API..." | tee -a "$LOG_FILE"
        docker exec -it $(docker ps -q -f name=php) composer create-project -s dev laminas-api-tools/api-tools-skeleton /var/www/api.$DOMAIN >> "$LOG_FILE" 2>&1
    fi

    # Install OAuth2 Server
    if [ ! -d "$PROJECT_DIR/src/auth/vendor" ]; then
        echo "Installing OAuth2 Server..." | tee -a "$LOG_FILE"
        docker exec -it $(docker ps -q -f name=php) composer create-project laminas/laminas-mvc-skeleton /var/www/auth.$DOMAIN >> "$LOG_FILE" 2>&1
        docker exec -it $(docker ps -q -f name=php) composer require league/oauth2-server -d /var/www/auth.$DOMAIN >> "$LOG_FILE" 2>&1
        docker exec -it $(docker ps -q -f name=php) bash -c "cd /var/www/auth.$DOMAIN && openssl genrsa -out private.key 2048 && openssl rsa -in private.key -pubout -out public.key" >> "$LOG_FILE" 2>&1
    fi

    # Install Admin Panel
    if [ ! -d "$PROJECT_DIR/src/admin/vendor" ]; then
        echo "Installing Admin Panel..." | tee -a "$LOG_FILE"
        docker exec -it $(docker ps -q -f name=php) composer create-project laminas/laminas-mvc-skeleton /var/www/admin.$DOMAIN >> "$LOG_FILE" 2>&1
    fi
}

test_subdomains() {
    echo "Testing subdomains..." | tee -a "$LOG_FILE"
    for subdomain in "www" "api" "auth" "admin"; do
        if curl -s "http://$subdomain.$DOMAIN" > /dev/null; then
            echo "$subdomain.$DOMAIN is up!" | tee -a "$LOG_FILE"
        else
            echo "Error: $subdomain.$DOMAIN is not responding. Check docker-compose logs." | tee -a "$LOG_FILE"
            docker-compose logs >> "$LOG_FILE" 2>&1
            exit 1
        fi
    done
}