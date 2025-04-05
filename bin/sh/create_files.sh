#!/bin/bash

# Variables from main script: USERNAME, PASSWORD, DOMAIN, PROJECT_DIR

create_docker_compose() {
    cat <<EOF > "$PROJECT_DIR/docker-compose.yml"
version: '3.8'

services:
  nginx:
    image: nginx:latest
    ports:
      - "80:80"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./docker/nginx/sites:/etc/nginx/conf.d
      - ./src/www:/var/www/www.$DOMAIN
      - ./src/api:/var/www/api.$DOMAIN
      - ./src/auth:/var/www/auth.$DOMAIN
      - ./src/admin:/var/www/admin.$DOMAIN
    depends_on:
      - php
    networks:
      - alertlocal-net

  php:
    build:
      context: ./docker/php
      dockerfile: Dockerfile
    volumes:
      - ./src/www:/var/www/www.$DOMAIN
      - ./src/api:/var/www/api.$DOMAIN
      - ./src/auth:/var/www/auth.$DOMAIN
      - ./src/admin:/var/www/admin.$DOMAIN
    depends_on:
      - mysql
    networks:
      - alertlocal-net

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: ${USERNAME}_db
      MYSQL_USER: $USERNAME
      MYSQL_PASSWORD: $PASSWORD
    volumes:
      - mysql-data:/var/lib/mysql
    networks:
      - alertlocal-net

networks:
  alertlocal-net:
    driver: bridge

volumes:
  mysql-data:
EOF
}

create_php_dockerfile() {
    cat <<EOF > "$PROJECT_DIR/docker/php/Dockerfile"
FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \\
    libpq-dev \\
    libzip-dev \\
    unzip \\
    && docker-php-ext-install \\
    pdo_mysql \\
    zip

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /var/www

RUN chown -R www-data:www-data /var/www
EOF
}

create_nginx_conf() {
    cat <<EOF > "$PROJECT_DIR/docker/nginx/nginx.conf"
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;

    include /etc/nginx/conf.d/*.conf;
}
EOF
}

create_subdomain_confs() {
    # www.$DOMAIN
    cat <<EOF > "$PROJECT_DIR/docker/nginx/sites/www.$DOMAIN.conf"
server {
    listen 80;
    server_name www.$DOMAIN;

    root /var/www/www.$DOMAIN;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

    # api.$DOMAIN
    cat <<EOF > "$PROJECT_DIR/docker/nginx/sites/api.$DOMAIN.conf"
server {
    listen 80;
    server_name api.$DOMAIN;

    root /var/www/api.$DOMAIN/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

    # auth.$DOMAIN
    cat <<EOF > "$PROJECT_DIR/docker/nginx/sites/auth.$DOMAIN.conf"
server {
    listen 80;
    server_name auth.$DOMAIN;

    root /var/www/auth.$DOMAIN/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

    # admin.$DOMAIN
    cat <<EOF > "$PROJECT_DIR/docker/nginx/sites/admin.$DOMAIN.conf"
server {
    listen 80;
    server_name admin.$DOMAIN;

    root /var/www/admin.$DOMAIN/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
}

create_env_file() {
    cat <<EOF > "$PROJECT_DIR/.env"
DB_HOST=mysql
DB_NAME=${USERNAME}_db
DB_USER=$USERNAME
DB_PASS=$PASSWORD
OAUTH2_PRIVATE_KEY=/var/www/auth.$DOMAIN/private.key
OAUTH2_PUBLIC_KEY=/var/www/auth.$DOMAIN/public.key
EOF
}

create_readme() {
    cat <<EOF > "$PROJECT_DIR/README.md"
# $DOMAIN Deployment
Local setup for $DOMAIN using Docker.

## Setup
1. Run \`./deploy_alertlocal.sh\`
2. Access:
   - Moodle: http://www.$DOMAIN
   - API: http://api.$DOMAIN
   - OAuth2: http://auth.$DOMAIN
   - Admin: http://admin.$DOMAIN
EOF
}