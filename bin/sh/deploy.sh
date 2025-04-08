#!/bin/bash

# Emojis para feedback
CHECK="✅"
ERROR="❌"
INFO="ℹ️"
RUNNING="🚀"
WARNING="⚠️"

# Caminho base no WSL2
BASE_DIR="/home/developer/workspace/deploy_project/deploy"
BIN_DIR="/home/developer/workspace/deploy_project/bin/sh/server"
STACK_NAME="php-dev-server"
NETWORK_NAME="php-dev-network"
LOG_DIR="$BASE_DIR/logs"

# Verifica ambiente
echo "$INFO Verificando ambiente..." | tee -a "$LOG_DIR/deploy.log"
if [ ! -d "$BIN_DIR" ]; then
    echo "$ERROR Diretório $BIN_DIR não encontrado! Criando estrutura..." | tee -a "$LOG_DIR/deploy.log"
    mkdir -p "$BIN_DIR" || { echo "$ERROR Falha ao criar diretórios!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }
fi

cd "$BIN_DIR" || { echo "$ERROR Não foi possível acessar $BIN_DIR!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }

# Criação do diretório do projeto e logs
echo "$INFO Criando diretório do projeto em $BASE_DIR..." | tee -a "$LOG_DIR/deploy.log"
mkdir -p "$BASE_DIR" "$LOG_DIR" || { echo "$ERROR Falha ao criar $BASE_DIR ou $LOG_DIR!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }
cd "$BASE_DIR" || { echo "$ERROR Não foi possível acessar $BASE_DIR!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }

# Criação da rede Docker
echo "$RUNNING Criando rede Docker: $NETWORK_NAME $CHECK" | tee -a "$LOG_DIR/deploy.log"
docker network create $NETWORK_NAME 2>/dev/null || echo "$WARNING Rede já existe" | tee -a "$LOG_DIR/deploy.log"

# Criação de volumes Docker
echo "$RUNNING Criando volumes Docker $CHECK" | tee -a "$LOG_DIR/deploy.log"
docker volume create mysql-data 2>/dev/null || echo "$WARNING Volume mysql-data já existe" | tee -a "$LOG_DIR/deploy.log"
docker volume create redis-data 2>/dev/null || echo "$WARNING Volume redis-data já existe" | tee -a "$LOG_DIR/deploy.log"

# Criação do docker-compose.yml
echo "$RUNNING Gerando docker-compose.yml $CHECK" | tee -a "$LOG_DIR/deploy.log"
cat <<EOF > "$BASE_DIR/docker-compose.yml"
version: '3.8'

services:
  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: api
    volumes:
      - ./api:/var/www/api
    ports:
      - "8080:80"
      - "443:443"  # HTTP/3 via QUIC
      - "1883:1883"  # MQTT para IoT (TCP)
      - "1883:1883/udp"  # MQTT para IoT (UDP)
    environment:
      - APP_ENV=development
      - REDIS_HOST=\${REDIS_HOST}
      - REDIS_PORT=\${REDIS_PORT}
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
    depends_on:
      - mysql
      - redis
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
    container_name: admin
    volumes:
      - ./admin:/var/www/admin
    ports:
      - "8081:80"
    environment:
      - APP_ENV=development
    depends_on:
      - mysql
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
    container_name: frontend
    volumes:
      - ./frontend:/var/www/frontend
    ports:
      - "8082:80"
    environment:
      - APP_ENV=development
      - REDIS_HOST=\${REDIS_HOST}
      - REDIS_PORT=\${REDIS_PORT}
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
    depends_on:
      - mysql
      - redis
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
    container_name: light
    volumes:
      - ./light:/var/www/light
    ports:
      - "8083:80"
    environment:
      - APP_ENV=development
    depends_on:
      - mysql
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    networks:
      - $NETWORK_NAME

  nginx:
    image: nginx:1.25  # Suporte a HTTP/3
    container_name: nginx
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf
    ports:
      - "80:80"
      - "443:443"  # HTTP/3 via QUIC
      - "443:443/udp"  # QUIC requer UDP
    command: ["nginx", "-g", "daemon off;"]
    depends_on:
      - api
      - admin
      - frontend
      - light
    networks:
      - $NETWORK_NAME

  mysql:
    image: mysql:8.0
    container_name: mysql
    volumes:
      - mysql-data:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=\${MYSQL_DATABASE}
      - MYSQL_USER=\${MYSQL_USER}
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    networks:
      - $NETWORK_NAME

  redis:
    image: redis:7.0
    container_name: redis
    volumes:
      - redis-data:/data
    command: redis-server --requirepass \${REDIS_PASSWORD}
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
    networks:
      - $NETWORK_NAME

networks:
  $NETWORK_NAME:
    external: true

volumes:
  mysql-data:
    external: true
  redis-data:
    external: true
EOF

# Criação dos Dockerfiles com Doctrine e Redis
echo "$RUNNING Gerando Dockerfiles $CHECK" | tee -a "$LOG_DIR/deploy.log"
for SERVICE in api admin frontend light; do
    mkdir -p "$BASE_DIR/$SERVICE"
    PHP_VERSION="8.1"
    if [ "$SERVICE" = "frontend" ] || [ "$SERVICE" = "light" ]; then
        PHP_VERSION="8.2"
    fi
    cat <<EOF > "$BASE_DIR/$SERVICE/Dockerfile"
FROM php:$PHP_VERSION-fpm
RUN apt-get update && apt-get install -y git unzip libpq-dev && \\
    docker-php-ext-install pdo_mysql && \\
    pecl install redis && docker-php-ext-enable redis
WORKDIR /var/www/$SERVICE
COPY . .
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN composer install --no-dev --optimize-autoloader
EXPOSE 80
CMD ["php-fpm"]
EOF
done

# Configuração do Nginx com HTTP/3
echo "$RUNNING Configurando Nginx com HTTP/3 $CHECK" | tee -a "$LOG_DIR/deploy.log"
mkdir -p "$BASE_DIR/nginx"
cat <<EOF > "$BASE_DIR/nginx/nginx.conf"
server {
    listen 80;
    listen 443 ssl http2;
    listen 443 quic reuseport;  # HTTP/3 via QUIC
    server_name api.localhost;
    ssl_certificate /etc/nginx/ssl/cert.pem;  # Placeholder
    ssl_certificate_key /etc/nginx/ssl/key.pem;  # Placeholder
    location / {
        proxy_pass http://api:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

server {
    listen 80;
    server_name admin.localhost;
    location / {
        proxy_pass http://admin:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

server {
    listen 80;
    server_name frontend.localhost;
    location / {
        proxy_pass http://frontend:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

server {
    listen 80;
    server_name light.localhost;
    location / {
        proxy_pass http://light:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

# Geração do .env
echo "$RUNNING Gerando .env $CHECK" | tee -a "$LOG_DIR/deploy.log"
cat <<EOF > "$BASE_DIR/.env"
# Geral
APP_ENV=development
APP_SECRET=devsecretkey789

# MySQL
MYSQL_ROOT_PASSWORD=rootpass
MYSQL_DATABASE=dotkernel_db
MYSQL_USER=dotkernel
MYSQL_PASSWORD=dotpass

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=redispass

# OAuth2 (API como provedor)
OAUTH2_ISSUER=http://api.localhost
OAUTH2_CLIENT_ID=dotkernel_client
OAUTH2_CLIENT_SECRET=dotkernel_secret
OAUTH2_REDIRECT_URI=http://api.localhost/oauth/callback
OAUTH2_TOKEN_ENDPOINT=http://api.localhost/oauth/token
OAUTH2_AUTH_ENDPOINT=http://api.localhost/oauth/authorize
JWT_SECRET=jwtsecretkey123
EOF

# Clonagem dos repositórios
echo "$RUNNING Clonando repositórios Dotkernel $CHECK" | tee -a "$LOG_DIR/deploy.log"
for REPO in api admin frontend light; do
    if [ ! -d "$BASE_DIR/$REPO/.git" ]; then
        git clone "https://github.com/dotkernel/$REPO.git" "$BASE_DIR/$REPO" || { echo "$ERROR Falha ao clonar $REPO!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }
    else
        echo "$WARNING Repositório $REPO já clonado" | tee -a "$LOG_DIR/deploy.log"
    fi
done

# Configuração do Doctrine e OAuth2
echo "$RUNNING Configurando Doctrine e OAuth2 $CHECK" | tee -a "$LOG_DIR/deploy.log"
for SERVICE in api admin frontend light; do
    cd "$BASE_DIR/$SERVICE" || { echo "$ERROR Não foi possível acessar $SERVICE!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }
    # Doctrine
    if [ -f "config/autoload/doctrine.local.php.dist" ]; then
        cp config/autoload/doctrine.local.php.dist config/autoload/doctrine.local.php
        sed -i "s|'dbname' => '.*'|'dbname' => 'dotkernel_db'|" config/autoload/doctrine.local.php
        sed -i "s|'user' => '.*'|'user' => 'dotkernel'|" config/autoload/doctrine.local.php
        sed -i "s|'password' => '.*'|'password' => 'dotpass'|" config/autoload/doctrine.local.php
        sed -i "s|'host' => '.*'|'host' => 'mysql'|" config/autoload/doctrine.local.php
    fi
    # OAuth2 na API
    if [ "$SERVICE" = "api" ]; then
        cat <<EOF > config/autoload/oauth2.local.php
<?php
return [
    'oauth2' => [
        'issuer' => 'http://api.localhost',
        'client_id' => 'dotkernel_client',
        'client_secret' => 'dotkernel_secret',
        'redirect_uri' => 'http://api.localhost/oauth/callback',
        'token_endpoint' => 'http://api.localhost/oauth/token',
        'authorize_endpoint' => 'http://api.localhost/oauth/authorize',
        'jwt_secret' => 'jwtsecretkey123',
        'scopes' => ['read', 'write', 'admin'],
    ],
];
EOF
    fi
    # Redis no Frontend
    if [ "$SERVICE" = "frontend" ]; then
        cat <<EOF > config/autoload/redis.local.php
<?php
return [
    'redis' => [
        'host' => 'redis',
        'port' => 6379,
        'password' => 'redispass',
    ],
];
EOF
    fi
done

# Implantação da stack
echo "$RUNNING Implantando stack $STACK_NAME $CHECK" | tee -a "$LOG_DIR/deploy.log"
docker-compose -f "$BASE_DIR/docker-compose.yml" up -d --build || { echo "$ERROR Falha ao implantar stack!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }

# Aguarda serviços
echo "$RUNNING Aguardando serviços $CHECK" | tee -a "$LOG_DIR/deploy.log"
until docker exec mysql mysqladmin ping -h localhost -u root -prootpass >/dev/null 2>&1; do
    echo "$INFO Aguardando MySQL..." | tee -a "$LOG_DIR/deploy.log"
    sleep 5
done
until docker exec redis redis-cli -a redispass PING >/dev/null 2>&1; do
    echo "$INFO Aguardando Redis..." | tee -a "$LOG_DIR/deploy.log"
    sleep 5
done

# Executa fixtures e testes
echo "$RUNNING Executando fixtures e testes $CHECK" | tee -a "$LOG_DIR/deploy.log"
for SERVICE in api admin frontend light; do
    cd "$BASE_DIR/$SERVICE" || { echo "$ERROR Não foi possível acessar $SERVICE!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }
    docker build -t "dotkernel-$SERVICE" . || { echo "$ERROR Falha ao construir $SERVICE!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }
    docker run --rm -v "$(pwd):/var/www/$SERVICE" --network $NETWORK_NAME "dotkernel-$SERVICE" composer install || { echo "$ERROR Falha ao instalar dependências de $SERVICE!" | tee -a "$LOG_DIR/deploy.log"; exit 1; }
    # Fixtures
    docker run --rm -v "$(pwd):/var/www/$SERVICE" --network $NETWORK_NAME "dotkernel-$SERVICE" php bin/doctrine orm:schema-tool:update --force --dump-sql > "$LOG_DIR/$SERVICE-fixtures.log" 2>&1
    docker run --rm -v "$(pwd):/var/www/$SERVICE" --network $NETWORK_NAME "dotkernel-$SERVICE" php bin/doctrine fixtures:load --no-interaction >> "$LOG_DIR/$SERVICE-fixtures.log" 2>&1 || echo "$WARNING Fixtures não disponíveis em $SERVICE" | tee -a "$LOG_DIR/deploy.log"
    # Testes
    docker run --rm -v "$(pwd):/var/www/$SERVICE" --network $NETWORK_NAME "dotkernel-$SERVICE" vendor/bin/phpunit --log-junit "$LOG_DIR/$SERVICE-phpunit.xml" >> "$LOG_DIR/$SERVICE-tests.log" 2>&1 || echo "$WARNING PHPUnit falhou ou não configurado em $SERVICE" | tee -a "$LOG_DIR/deploy.log"
    if [ -f "vendor/bin/behat" ]; then
        docker run --rm -v "$(pwd):/var/www/$SERVICE" --network $NETWORK_NAME "dotkernel-$SERVICE" vendor/bin/behat >> "$LOG_DIR/$SERVICE-behat.log" 2>&1 || echo "$WARNING Behat falhou ou não configurado em $SERVICE" | tee -a "$LOG_DIR/deploy.log"
    fi
done

# Configuração do Redis para usuários com ACL
echo "$RUNNING Configurando Redis para usuários com ACL $CHECK" | tee -a "$LOG_DIR/deploy.log"
docker exec redis redis-cli -a redispass <<EOF
SET user:1 '{"id": 1, "name": "Admin User", "email": "admin@example.com", "roles": ["admin"], "permissions": {"read": true, "write": true, "delete": true}, "capabilities": {"iot_control": true}, "capillarity": {"devices": ["device1", "device2"]}}'
SET user:2 '{"id": 2, "name": "Regular User", "email": "user@example.com", "roles": ["user"], "permissions": {"read": true, "write": false, "delete": false}, "capabilities": {"iot_control": false}, "capillarity": {"devices": ["device3"]}}'
EOF

# Geração do desinstalador
echo "$RUNNING Gerando desinstalador uninstall.sh $CHECK" | tee -a "$LOG_DIR/deploy.log"
cat <<EOF > "$BIN_DIR/uninstall.sh"
#!/bin/bash
echo "$INFO Desinstalando stack $STACK_NAME..." | tee -a "$LOG_DIR/uninstall.log"
cd "$BASE_DIR" || { echo "$ERROR Não foi possível acessar $BASE_DIR!" | tee -a "$LOG_DIR/uninstall.log"; exit 1; }
docker-compose down -v
docker network rm $NETWORK_NAME 2>/dev/null || echo "$WARNING Rede já removida" | tee -a "$LOG_DIR/uninstall.log"
docker volume rm mysql-data redis-data 2>/dev/null || echo "$WARNING Volumes já removidos" | tee -a "$LOG_DIR/uninstall.log"
rm -rf "$BASE_DIR"
echo "$CHECK Stack $STACK_NAME desinstalado com sucesso!" | tee -a "$LOG_DIR/uninstall.log"
EOF
chmod +x "$BIN_DIR/uninstall.sh"

# Exibir resultados
echo "$CHECK Deploy concluído!" | tee -a "$LOG_DIR/deploy.log"
echo "Acesse os serviços em:" | tee -a "$LOG_DIR/deploy.log"
echo " - API (OAuth2): http://api.localhost" | tee -a "$LOG_DIR/deploy.log"
echo " - Admin: http://admin.localhost" | tee -a "$LOG_DIR/deploy.log"
echo " - Frontend: http://frontend.localhost" | tee -a "$LOG_DIR/deploy.log"
echo " - Light: http://light.localhost" | tee -a "$LOG_DIR/deploy.log"
echo "Valores do .env:" | tee -a "$LOG_DIR/deploy.log"
cat "$BASE_DIR/.env" | tee -a "$LOG_DIR/deploy.log"
echo "Logs disponíveis em: $LOG_DIR" | tee -a "$LOG_DIR/deploy.log"
echo "Para desinstalar, execute: $BIN_DIR/uninstall.sh" | tee -a "$LOG_DIR/deploy.log"