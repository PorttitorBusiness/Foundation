#!/bin/bash

# 🚀 Script de deploy do projeto Foundation no WSL2 Ubuntu 24.04
# Gera tudo em deploy/localhost/ com SSL, dhparams e HTTP/3 em prod

# Emojis para feedback
CHECK="✅"
ERROR="❌"
INFO="ℹ️"
RUNNING="🚀"
WARNING="⚠️"
BUILD="🛠️"
TEST="🧪"
DEPLOY="📦"
USER="👤"
REDIS="🔴"
OAUTH="🔒"
CONFIG="📋"
DB="🗄️"
SHELL="🐚"

# Versão do script
SCRIPT_VERSION="2.5.0"

# Configurações básicas
ENVIRONMENTS=("dev" "test" "prod")
DOMAIN="localhost"
SUBDOMAINS="api admin frontend light foundation"
PROJECT_DIR="$(pwd)"
BASE_DIR="$PROJECT_DIR/deploy"
DOMAIN_DIR="$BASE_DIR/$DOMAIN"
CONFIG_FILE="$DOMAIN_DIR/config.json"
ENV_FILE="$DOMAIN_DIR/.env"
USER_EMAIL="foundation@foundation.com"
USER_PASSWORD="Foundation2025!"

# Função para verificar erros (CI-friendly)
check_error() {
    if [ $? -ne 0 ]; then
        echo "$ERROR Erro: $1"
        exit 1
    fi
}

# Função para instalar pré-requisitos no WSL2
install_prerequisites() {
    echo "$INFO Instalando pré-requisitos no WSL2 Ubuntu 24.04 $CHECK"
    sudo apt-get update
    sudo apt-get install -y docker.io docker-compose php-cli php-zip unzip curl nodejs npm jq
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker "$USER"
    curl -sS https://getcomposer.org/installer | php
    sudo mv composer.phar /usr/local/bin/composer
    sudo npm install -g n
    sudo n latest
    # Configurar Docker para WSL2 (evitar falhas comuns)
    sudo sh -c 'echo "{\"features\": {\"buildkit\": true}}" > /etc/docker/daemon.json'
    sudo systemctl restart docker
    check_error "Falha ao instalar pré-requisitos"
}

# Função para gerar config.json
generate_config_json() {
    echo "$CONFIG Gerando config.json $CHECK" | tee -a "$DOMAIN_DIR/deploy.log"
    mkdir -p "$DOMAIN_DIR"
    cat <<EOF > "$CONFIG_FILE"
{
  "version": "$SCRIPT_VERSION",
  "domain": "$DOMAIN",
  "environments": {
    "dev": {
      "http_ports": ["8080", "8081", "8082", "8083", "8084"],
      "https_ports": ["8443", "8444", "8445", "8446", "8447"],
      "livereload_port": "4200",
      "app_env": "dev",
      "app_secret": "secretkey-dev-789",
      "mysql": {
        "host": "mysql_external",
        "port": 3306,
        "root_password": "rootpass-dev",
        "database": "foundation_db_dev",
        "user": "foundation_dev",
        "password": "foundationpass-dev"
      },
      "redis": {
        "host": "redis_external",
        "port": 6379,
        "password": "redispass-dev"
      },
      "oauth2": {
        "issuer": "https://api.$DOMAIN:8443",
        "client_id": "foundation_client_dev",
        "client_secret": "foundation_secret_dev",
        "redirect_uri": "https://foundation.$DOMAIN:8447/callback",
        "token_endpoint": "https://api.$DOMAIN:8443/oauth2/token",
        "auth_endpoint": "https://api.$DOMAIN:8443/oauth2/authorize",
        "jwt_secret": "jwtsecretkey-dev-123",
        "scopes": ["read", "write", "admin"]
      }
    },
    "test": {
      "http_ports": ["9080", "9081", "9082", "9083", "9084"],
      "https_ports": ["9443", "9444", "9445", "9446", "9447"],
      "livereload_port": "4200",
      "app_env": "test",
      "app_secret": "secretkey-test-789",
      "mysql": {
        "host": "mysql_external",
        "port": 3306,
        "root_password": "rootpass-test",
        "database": "foundation_db_test",
        "user": "foundation_test",
        "password": "foundationpass-test"
      },
      "redis": {
        "host": "redis_external",
        "port": 6379,
        "password": "redispass-test"
      },
      "oauth2": {
        "issuer": "https://api.$DOMAIN:9443",
        "client_id": "foundation_client_test",
        "client_secret": "foundation_secret_test",
        "redirect_uri": "https://foundation.$DOMAIN:9447/callback",
        "token_endpoint": "https://api.$DOMAIN:9443/oauth2/token",
        "auth_endpoint": "https://api.$DOMAIN:9443/oauth2/authorize",
        "jwt_secret": "jwtsecretkey-test-123",
        "scopes": ["read", "write", "admin"]
      }
    },
    "prod": {
      "http_ports": ["80"],
      "https_ports": ["443"],
      "livereload_port": null,
      "app_env": "prod",
      "app_secret": "secretkey-prod-789",
      "mysql": {
        "host": "mysql_external",
        "port": 3306,
        "root_password": "rootpass-prod",
        "database": "foundation_db_prod",
        "user": "foundation_prod",
        "password": "foundationpass-prod"
      },
      "redis": {
        "host": "redis_external",
        "port": 6379,
        "password": "redispass-prod"
      },
      "oauth2": {
        "issuer": "https://api.$DOMAIN",
        "client_id": "foundation_client_prod",
        "client_secret": "foundation_secret_prod",
        "redirect_uri": "https://foundation.$DOMAIN/callback",
        "token_endpoint": "https://api.$DOMAIN/oauth2/token",
        "auth_endpoint": "https://api.$DOMAIN/oauth2/authorize",
        "jwt_secret": "jwtsecretkey-prod-123",
        "scopes": ["read", "write", "admin"]
      }
    }
  }
}
EOF
    check_error "Falha ao gerar config.json"
}

# Função para gerar .env
generate_env_file() {
    echo "$CONFIG Gerando .env $CHECK" | tee -a "$DOMAIN_DIR/deploy.log"
    cat <<EOF > "$ENV_FILE"
# Configurações globais
DOMAIN=$DOMAIN
SCRIPT_VERSION=$SCRIPT_VERSION

# Dev
DEV_HTTP_PORTS=8080 8081 8082 8083 8084
DEV_HTTPS_PORTS=8443 8444 8445 8446 8447
DEV_LIVERELOAD_PORT=4200
DEV_APP_ENV=dev
DEV_APP_SECRET=secretkey-dev-789
DEV_MYSQL_HOST=mysql_external
DEV_MYSQL_PORT=3306
DEV_MYSQL_ROOT_PASSWORD=rootpass-dev
DEV_MYSQL_DATABASE=foundation_db_dev
DEV_MYSQL_USER=foundation médicale_dev
DEV_MYSQL_PASSWORD=foundationpass-dev
DEV_REDIS_HOST=redis_external
DEV_REDIS_PORT=6379
DEV_REDIS_PASSWORD=redispass-dev
DEV_OAUTH2_ISSUER=https://api.$DOMAIN:8443
DEV_OAUTH2_CLIENT_ID=foundation_client_dev
DEV_OAUTH2_CLIENT_SECRET=foundation_secret_dev
DEV_OAUTH2_REDIRECT_URI=https://foundation.$DOMAIN:8447/callback
DEV_OAUTH2_TOKEN_ENDPOINT=https://api.$DOMAIN:8443/oauth2/token
DEV_OAUTH2_AUTH_ENDPOINT=https://api.$DOMAIN:8443/oauth2/authorize
DEV_OAUTH2_JWT_SECRET=jwtsecretkey-dev-123

# Test
TEST_HTTP_PORTS=9080 9081 9082 9083 9084
TEST_HTTPS_PORTS=9443 9444 9445 9446 9447
TEST_LIVERELOAD_PORT=4200
TEST_APP_ENV=test
TEST_APP_SECRET=secretkey-test-789
TEST_MYSQL_HOST=mysql_external
TEST_MYSQL_PORT=3306
TEST_MYSQL_ROOT_PASSWORD=rootpass-test
TEST_MYSQL_DATABASE=foundation_db_test
TEST_MYSQL_USER=foundation_test
TEST_MYSQL_PASSWORD=foundationpass-test
TEST_REDIS_HOST=redis_external
TEST_REDIS_PORT=6379
TEST_REDIS_PASSWORD=redispass-test
TEST_OAUTH2_ISSUER=https://api.$DOMAIN:9443
TEST_OAUTH2_CLIENT_ID=foundation_client_test
TEST_OAUTH2_CLIENT_SECRET=foundation_secret_test
TEST_OAUTH2_REDIRECT_URI=https://foundation.$DOMAIN:9447/callback
TEST_OAUTH2_TOKEN_ENDPOINT=https://api.$DOMAIN:9443/oauth2/token
TEST_OAUTH2_AUTH_ENDPOINT=https://api.$DOMAIN:9443/oauth2/authorize
TEST_OAUTH2_JWT_SECRET=jwtsecretkey-test-123

# Prod
PROD_HTTP_PORTS=80
PROD_HTTPS_PORTS=443
PROD_APP_ENV=prod
PROD_APP_SECRET=secretkey-prod-789
PROD_MYSQL_HOST=mysql_external
PROD_MYSQL_PORT=3306
PROD_MYSQL_ROOT_PASSWORD=rootpass-prod
PROD_MYSQL_DATABASE=foundation_db_prod
PROD_MYSQL_USER=foundation_prod
PROD_MYSQL_PASSWORD=foundationpass-prod
PROD_REDIS_HOST=redis_external
PROD_REDIS_PORT=6379
PROD_REDIS_PASSWORD=redispass-prod
PROD_OAUTH2_ISSUER=https://api.$DOMAIN
PROD_OAUTH2_CLIENT_ID=foundation_client_prod
PROD_OAUTH2_CLIENT_SECRET=foundation_secret_prod
PROD_OAUTH2_REDIRECT_URI=https://foundation.$DOMAIN/callback
PROD_OAUTH2_TOKEN_ENDPOINT=https://api.$DOMAIN/oauth2/token
PROD_OAUTH2_AUTH_ENDPOINT=https://api.$DOMAIN/oauth2/authorize
PROD_OAUTH2_JWT_SECRET=jwtsecretkey-prod-123
EOF
    check_error "Falha ao gerar .env"
}

# Função para gerar certificados autoassinados e dhparams
generate_self_signed_certs() {
    local ENV=$1
    local CERT_DIR="$DOMAIN_DIR/$ENV/certs"
    echo "$RUNNING Gerando certificados e dhparams para $ENV $CHECK" | tee -a "$DOMAIN_DIR/$ENV/logs/deploy.log"
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" \
        -out "$CERT_DIR/cert.pem" \
        -subj "/C=BR/ST=SP/L=SaoPaulo/O=Foundation/OU=IT/CN=$DOMAIN" \
        -addext "subjectAltName=DNS:$DOMAIN,DNS:api.$DOMAIN,DNS:admin.$DOMAIN,DNS:frontend.$DOMAIN,DNS:light.$DOMAIN,DNS:foundation.$DOMAIN" \
        2>>"$DOMAIN_DIR/$ENV/logs/cert_errors.log"
    if [ "$ENV" = "prod" ]; then
        openssl dhparam -out "$CERT_DIR/dhparams.pem" 2048 2>>"$DOMAIN_DIR/$ENV/logs/cert_errors.log"
    fi
    check_error "Falha ao gerar certificados/dhparams para $ENV"
}

# Função para gerar arquivos de configuração por ambiente
generate_config_files() {
    local ENV=$1
    local ENV_BASE_DIR="$DOMAIN_DIR/$ENV"
    local LOG_DIR="$ENV_BASE_DIR/logs"
    local CERT_DIR="$ENV_BASE_DIR/certs"
    local STACK_NAME="foundation-$ENV-server"
    local NETWORK_NAME="foundation-$ENV-network"

    echo "$BUILD Gerando arquivos de configuração para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    mkdir -p "$ENV_BASE_DIR" "$LOG_DIR" "$CERT_DIR" "$ENV_BASE_DIR"/{api,admin,frontend,light,foundation}/{Core,Wallet,IAGenerator} "$ENV_BASE_DIR/nginx"
    check_error "Falha ao criar diretórios para $ENV"

    cd "$ENV_BASE_DIR" || check_error "Não foi possível acessar $ENV_BASE_DIR"

    # Extrair configurações do JSON
    local HTTP_PORTS=($(jq -r ".environments.$ENV.http_ports[]" "$CONFIG_FILE"))
    local HTTPS_PORTS=($(jq -r ".environments.$ENV.https_ports[]" "$CONFIG_FILE"))
    local LIVERELOAD_PORT=$(jq -r ".environments.$ENV.livereload_port" "$CONFIG_FILE"))

    # Geração do docker-compose.yml
    echo "$BUILD Gerando docker-compose.yml para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    if [ "$ENV" = "prod" ]; then
        cat <<EOF > "docker-compose.yml"
version: '3.9'

services:
  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: $ENV-api
    volumes:
      - ./api:/app
    environment:
      - APP_ENV=\${PROD_APP_ENV}
      - OAUTH2_CLIENT_ID=\${PROD_OAUTH2_CLIENT_ID}
      - OAUTH2_CLIENT_SECRET=\${PROD_OAUTH2_CLIENT_SECRET}
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  admin:
    build:
      context: ./admin
      dockerfile: Dockerfile
    container_name: $ENV-admin
    volumes:
      - ./admin:/app
    environment:
      - APP_ENV=\${PROD_APP_ENV}
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: $ENV-frontend
    volumes:
      - ./frontend:/app
    environment:
      - APP_ENV=\${PROD_APP_ENV}
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  light:
    build:
      context: ./light
      dockerfile: Dockerfile
    container_name: $ENV-light
    volumes:
      - ./light:/app
    environment:
      - APP_ENV=\${PROD_APP_ENV}
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  foundation:
    build:
      context: ./foundation
      dockerfile: Dockerfile
    container_name: $ENV-foundation
    volumes:
      - ./foundation:/app
    environment:
      - APP_ENV=\${PROD_APP_ENV}
      - REDIS_HOST=\${PROD_REDIS_HOST}
      - REDIS_PORT=\${PROD_REDIS_PORT}
      - REDIS_PASSWORD=\${PROD_REDIS_PASSWORD}
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  nginx:
    image: nginx:1.27-alpine
    container_name: $ENV-nginx
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/etc/nginx/ssl
    ports:
      - "${HTTP_PORTS[0]}:80"
      - "${HTTPS_PORTS[0]}:443"
      - "${HTTPS_PORTS[0]}:443/udp"
    command: ["nginx", "-g", "daemon off;"]
    depends_on:
      - api
      - admin
      - frontend
      - light
      - foundation
    networks:
      - $NETWORK_NAME

networks:
  $NETWORK_NAME:
    driver: bridge
EOF
    else
        cat <<EOF > "docker-compose.yml"
version: '3.9'

services:
  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: $ENV-api
    volumes:
      - ./api:/app
    ports:
      - "${HTTP_PORTS[0]}:80"
      - "${HTTPS_PORTS[0]}:443"
    environment:
      - APP_ENV=\${${ENV^^}_APP_ENV}
      - OAUTH2_CLIENT_ID=\${${ENV^^}_OAUTH2_CLIENT_ID}
      - OAUTH2_CLIENT_SECRET=\${${ENV^^}_OAUTH2_CLIENT_SECRET}
      - XDEBUG_MODE=debug
      - XDEBUG_CONFIG=client_host=host.docker.internal client_port=9003
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  admin:
    build:
      context: ./admin
      dockerfile: Dockerfile
    container_name: $ENV-admin
    volumes:
      - ./admin:/app
    ports:
      - "${HTTP_PORTS[1]}:80"
      - "${HTTPS_PORTS[1]}:443"
    environment:
      - APP_ENV=\${${ENV^^}_APP_ENV}
      - XDEBUG_MODE=debug
      - XDEBUG_CONFIG=client_host=host.docker.internal client_port=9003
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: $ENV-frontend
    volumes:
      - ./frontend:/app
    ports:
      - "${HTTP_PORTS[2]}:80"
      - "${HTTPS_PORTS[2]}:443"
    environment:
      - APP_ENV=\${${ENV^^}_APP_ENV}
      - XDEBUG_MODE=debug
      - XDEBUG_CONFIG=client_host=host.docker.internal client_port=9003
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  light:
    build:
      context: ./light
      dockerfile: Dockerfile
    container_name: $ENV-light
    volumes:
      - ./light:/app
    ports:
      - "${HTTP_PORTS[3]}:80"
      - "${HTTPS_PORTS[3]}:443"
    environment:
      - APP_ENV=\${${ENV^^}_APP_ENV}
      - XDEBUG_MODE=debug
      - XDEBUG_CONFIG=client_host=host.docker.internal client_port=9003
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  foundation:
    build:
      context: ./foundation
      dockerfile: Dockerfile
    container_name: $ENV-foundation
    volumes:
      - ./foundation:/app
    ports:
      - "${HTTP_PORTS[4]}:80"
      - "${HTTPS_PORTS[4]}:443"
      - "$LIVERELOAD_PORT:$LIVERELOAD_PORT"
    environment:
      - APP_ENV=\${${ENV^^}_APP_ENV}
      - REDIS_HOST=\${${ENV^^}_REDIS_HOST}
      - REDIS_PORT=\${${ENV^^}_REDIS_PORT}
      - REDIS_PASSWORD=\${${ENV^^}_REDIS_PASSWORD}
      - XDEBUG_MODE=debug
      - XDEBUG_CONFIG=client_host=host.docker.internal client_port=9003
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  nginx:
    image: nginx:1.27-alpine
    container_name: $ENV-nginx
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/etc/nginx/ssl
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    command: ["nginx", "-g", "daemon off;"]
    depends_on:
      - api
      - admin
      - frontend
      - light
      - foundation
    networks:
      - $NETWORK_NAME

networks:
  $NETWORK_NAME:
    driver: bridge
EOF
    fi

    # Geração dos Dockerfiles
    echo "$BUILD Gerando Dockerfiles para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    for SERVICE in api admin frontend light foundation; do
        mkdir -p "$SERVICE/Core" "$SERVICE/Wallet" "$SERVICE/IAGenerator"
        if [ "$SERVICE" = "foundation" ]; then
            if [ "$ENV" = "prod" ]; then
                cat <<EOF > "$SERVICE/Dockerfile"
FROM php:8.4-fpm-alpine
RUN apk add --no-cache git unzip libpq-dev nodejs npm \
    && docker-php-ext-install pdo_mysql \
    && pecl install redis \
    && docker-php-ext-enable redis
WORKDIR /app
COPY . .
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN composer install --no-dev --optimize-autoloader
RUN npm install -g @angular/cli@18
RUN if [ -d "frontend" ]; then cd frontend && npm install && ng build --prod && cp -r dist/* ../public/; fi
EXPOSE 80
CMD ["php-fpm"]
EOF
            else
                cat <<EOF > "$SERVICE/Dockerfile"
FROM php:8.4-fpm-alpine
RUN apk add --no-cache git unzip libpq-dev nodejs npm \
    && docker-php-ext-install pdo_mysql \
    && pecl install redis xdebug \
    && docker-php-ext-enable redis xdebug
WORKDIR /app
COPY . .
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN composer install --no-dev --optimize-autoloader
RUN npm install -g @angular/cli@18
RUN if [ -d "frontend" ]; then cd frontend && npm install; fi
EXPOSE 80 $LIVERELOAD_PORT
CMD bash -c "php-fpm -D && if [ -d 'frontend' ]; then cd frontend && ng serve --host 0.0.0.0 --port $LIVERELOAD_PORT; else php-fpm; fi"
EOF
            fi
        else
            if [ "$ENV" = "prod" ]; then
                cat <<EOF > "$SERVICE/Dockerfile"
FROM php:8.4-fpm-alpine
RUN apk add --no-cache git unzip libpq-dev \
    && docker-php-ext-install pdo_mysql \
    && pecl install redis \
    && docker-php-ext-enable redis
WORKDIR /app
COPY . .
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN composer install --no-dev --optimize-autoloader
EXPOSE 80
CMD ["php-fpm"]
EOF
            else
                cat <<EOF > "$SERVICE/Dockerfile"
FROM php:8.4-fpm-alpine
RUN apk add --no-cache git unzip libpq-dev \
    && docker-php-ext-install pdo_mysql \
    && pecl install redis xdebug \
    && docker-php-ext-enable redis xdebug
WORKDIR /app
COPY . .
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN composer install --no-dev --optimize-autoloader
EXPOSE 80
CMD ["php-fpm"]
EOF
            fi
        fi
    done

    # Configuração do Nginx com HTTP/3 em prod
    echo "$BUILD Configurando Nginx para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    if [ "$ENV" = "prod" ]; then
        cat <<EOF > "nginx/nginx.conf"
events {}
http {
    server {
        listen 80;
        server_name $DOMAIN api.$DOMAIN admin.$DOMAIN frontend.$DOMAIN light.$DOMAIN foundation.$DOMAIN;
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl http2;
        listen 443 quic reuseport;
        server_name api.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_dhparam /etc/nginx/ssl/dhparams.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        http3 on;
        location / {
            proxy_pass http://$ENV-api:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 443 ssl http2;
        listen 443 quic reuseport;
        server_name admin.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_dhparam /etc/nginx/ssl/dhparams.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        http3 on;
        location / {
            proxy_pass http://$ENV-admin:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 443 ssl http2;
        listen 443 quic reuseport;
        server_name frontend.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_dhparam /etc/nginx/ssl/dhparams.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        http3 on;
        location / {
            proxy_pass http://$ENV-frontend:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 443 ssl http2;
        listen 443 quic reuseport;
        server_name light.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_dhparam /etc/nginx/ssl/dhparams.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        http3 on;
        location / {
            proxy_pass http://$ENV-light:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 443 ssl http2;
        listen 443 quic reuseport;
        server_name foundation.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_dhparam /etc/nginx/ssl/dhparams.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        http3 on;
        location / {
            proxy_pass http://$ENV-foundation:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
EOF
    else
        cat <<EOF > "nginx/nginx.conf"
events {}
http {
    server {
        listen 80;
        server_name $DOMAIN api.$DOMAIN admin.$DOMAIN frontend.$DOMAIN light.$DOMAIN foundation.$DOMAIN;
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name api.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        location / {
            proxy_pass http://$ENV-api:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 443 ssl;
        server_name admin.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        location / {
            proxy_pass http://$ENV-admin:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 443 ssl;
        server_name frontend.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        location / {
            proxy_pass http://$ENV-frontend:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 443 ssl;
        server_name light.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        location / {
            proxy_pass http://$ENV-light:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    server {
        listen 443 ssl;
        server_name foundation.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        location / {
            proxy_pass http://$ENV-foundation:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
        location /$LIVERELOAD_PORT {
            proxy_pass http://$ENV-foundation:$LIVERELOAD_PORT;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
EOF
    fi

    # Configuração do Core (OAuth2)
    echo "$CONFIG Configurando Core para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    mkdir -p "foundation/Core/src/Controller"
    cat <<EOF > "foundation/Core/src/Controller/AuthController.php"
<?php
namespace Core\Controller;

use Laminas\Diactoros\Response\JsonResponse;

class AuthController
{
    public function authorizeAction(): JsonResponse
    {
        \$params = \$_GET;
        return isset(\$params['client_id']) && \$params['client_id'] === 'foundation_client_$ENV'
            ? new JsonResponse(['code' => 'auth_code_foundation_$ENV'])
            : new JsonResponse(['error' => 'Invalid client'], 401);
    }

    public function tokenAction(): JsonResponse
    {
        return new JsonResponse([
            'access_token' => 'token_foundation_2025_$ENV',
            'expires_in' => 3600,
            'user' => ['email' => '$USER_EMAIL']
        ]);
    }
}
EOF

    cat <<EOF > "foundation/Core/config/module.config.php"
<?php
return [
    'router' => [
        'routes' => [
            'oauth2_authorize' => [
                'type' => 'Literal',
                'options' => [
                    'route' => '/oauth2/authorize',
                    'defaults' => [
                        'controller' => Core\Controller\AuthController::class,
                        'action' => 'authorize',
                    ],
                ],
            ],
            'oauth2_token' => [
                'type' => 'Literal',
                'options' => [
                    'route' => '/oauth2/token',
                    'defaults' => [
                        'controller' => Core\Controller\AuthController::class,
                        'action' => 'token',
                    ],
                ],
            ],
        ],
    ],
];
EOF

    # Configuração do Wallet
    echo "$CONFIG Configurando Wallet para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    mkdir -p "foundation/Wallet/src/Controller"
    cat <<EOF > "foundation/Wallet/src/Controller/WalletController.php"
<?php
namespace Wallet\Controller;

use Laminas\Diactoros\Response\JsonResponse;

class WalletController
{
    public function balanceAction(): JsonResponse
    {
        return new JsonResponse(['balance' => 1000.00, 'user' => '$USER_EMAIL']);
    }
}
EOF

    cat <<EOF > "foundation/Wallet/config/module.config.php"
<?php
return [
    'router' => [
        'routes' => [
            'wallet_balance' => [
                'type' => 'Literal',
                'options' => [
                    'route' => '/wallet/balance',
                    'defaults' => [
                        'controller' => Wallet\Controller\WalletController::class,
                        'action' => 'balance',
                    ],
                ],
            ],
        ],
    ],
];
EOF

    # Configuração do IAGenerator
    echo "$CONFIG Configurando IAGenerator para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    mkdir -p "foundation/IAGenerator/src/Service"
    cat <<EOF > "foundation/IAGenerator/src/Service/CodeGeneratorService.php"
<?php
namespace IAGenerator\Service;

class CodeGeneratorService
{
    public function generateModule(string \$moduleName): string
    {
        return "<?php\nnamespace \$moduleName;\nclass IndexController\n{\n    public function indexAction(): string\n    {\n        return 'Módulo \$moduleName gerado!';\n    }\n}";
    }
}
EOF

    cat <<EOF > "foundation/IAGenerator/config/module.config.php"
<?php
return [
    'service_manager' => [
        'factories' => [
            IAGenerator\Service\CodeGeneratorService::class => function() {
                return new IAGenerator\Service\CodeGeneratorService();
            },
        ],
    ],
];
EOF

    # Configuração do LiveReload (Angular)
    echo "$CONFIG Configurando LiveReload (Angular) para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    mkdir -p "foundation/frontend"
    cd "foundation/frontend" || check_error "Não foi possível acessar foundation/frontend"
    npx @angular/cli@18 new foundation-frontend --skip-install --defaults --minimal
    cat <<EOF > "src/app/app.component.html"
<h1>Bem-vindo ao Foundation! 🎉</h1>
<p><a href="https://api.$DOMAIN:${HTTPS_PORTS[0]}/oauth2/authorize?client_id=foundation_client_$ENV&redirect_uri=https://foundation.$DOMAIN:${HTTPS_PORTS[4]}/callback&response_type=code">Login OAuth2</a></p>
EOF
    cd "$ENV_BASE_DIR" || check_error "Não foi possível voltar ao diretório raiz"

    # Instalar Dotkernel no serviço 'foundation'
    echo "$DEPLOY Instalando Dotkernel para $ENV $CHECK" | tee -a "$LOG_DIR/deploy.log"
    cd "foundation" || check_error "Não foi possível acessar foundation/"
    composer create-project dotkernel/dotkernel . -n --no-scripts
    check_error "Falha ao instalar Dotkernel"
    cd "$ENV_BASE_DIR" || check_error "Não foi possível voltar ao diretório raiz"
}

# Função principal
main() {
    echo "$RUNNING Iniciando deploy do projeto Foundation no WSL2 versão $SCRIPT_VERSION $CHECK"

    # Instalar pré-requisitos
    install_prerequisites

    # Adicionar subdomínios ao /etc/hosts (necessário no WSL2)
    if ! grep -q "foundation.$DOMAIN" /etc/hosts; then
        echo "127.0.0.1 $DOMAIN api.$DOMAIN admin.$DOMAIN frontend.$DOMAIN light.$DOMAIN foundation.$DOMAIN" | sudo tee -a /etc/hosts
        check_error "Falha ao configurar /etc/hosts"
    fi

    # Gerar config.json e .env primeiro
    generate_config_json
    generate_env_file

    # Processar cada ambiente
    for ENV in "${ENVIRONMENTS[@]}"; do
        echo "$INFO Processando ambiente: $ENV $CHECK"
        generate_self_signed_certs "$ENV"
        generate_config_files "$ENV"

        # Criar rede Docker se não existir
        docker network ls | grep -q "foundation-$ENV-network" || docker network create "foundation-$ENV-network"
        check_error "Falha ao criar rede Docker para $ENV"

        # Iniciar containers
        cd "$DOMAIN_DIR/$ENV" || check_error "Não foi possível acessar $DOMAIN_DIR/$ENV"
        echo "$DEPLOY Iniciando containers para $ENV $CHECK" | tee -a "logs/deploy.log"
        docker-compose up -d --build
        check_error "Falha ao iniciar containers para $ENV"

        # Exibir informações de acesso
        local HTTP_PORTS=($(jq -r ".environments.$ENV.http_ports[]" "$CONFIG_FILE"))
        local HTTPS_PORTS=($(jq -r ".environments.$ENV.https_ports[]" "$CONFIG_FILE"))
        local LIVERELOAD_PORT=$(jq -r ".environments.$ENV.livereload_port" "$CONFIG_FILE")
        echo "🎉 Deploy do ambiente $ENV concluído!"
        echo "--------------------------------------------------"
        echo "🔗 Links de Acesso ($ENV):"
        echo "API: https://api.$DOMAIN:${HTTPS_PORTS[0]}"
        echo "Admin: https://admin.$DOMAIN:${HTTPS_PORTS[1]}"
        echo "Frontend: https://frontend.$DOMAIN:${HTTPS_PORTS[2]}"
        echo "Light: https://light.$DOMAIN:${HTTPS_PORTS[3]}"
        echo "Foundation (Backend): https://foundation.$DOMAIN:${HTTPS_PORTS[4]}"
        [ "$ENV" != "prod" ] && echo "Foundation (LiveReload): https://foundation.$DOMAIN:$LIVERELOAD_PORT"
        echo "OAuth2 Authorize: https://api.$DOMAIN:${HTTPS_PORTS[0]}/oauth2/authorize?client_id=foundation_client_$ENV&redirect_uri=https://foundation.$DOMAIN:${HTTPS_PORTS[4]}/callback&response_type=code"
        echo "OAuth2 Token: https://api.$DOMAIN:${HTTPS_PORTS[0]}/oauth2/token"
        echo "--------------------------------------------------"
        echo "$USER Usuário Simulado:"
        echo "Email: $USER_EMAIL"
        echo "Senha: $USER_PASSWORD"
        echo "--------------------------------------------------"
    done

    echo "$CHECK Deploy completo para todos os ambientes!"
    echo "🔍 Verifique os containers com: docker ps"
}

# Executar função principal
main