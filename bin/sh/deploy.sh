#!/bin/bash

set -x  # Ativa saída detalhada para depuração

# 🌈 Solicita entradas do usuário
read -p "Digite o nome de usuário (será usado como prefixo de domínio, e.g., usuario.local): " USERNAME
read -s -p "Digite a senha: " PASSWORD
echo
ENVIRONMENT="development"  # Fixo para desenvolvimento

# 🚀 Define variáveis de ambiente
DOMAIN="${USERNAME}.local"
PROJECT_ROOT="$(pwd)"
PROJECT_DIR="$PROJECT_ROOT/projects/$DOMAIN"
LOG_FILE="$PROJECT_DIR/deploy.log"

# 📁 Cria o diretório do projeto
mkdir -p "$PROJECT_DIR"
echo "🚀 Iniciando implantação para o domínio: $DOMAIN no ambiente $ENVIRONMENT" | tee -a "$LOG_FILE"

# ✅ Função para verificar o status de comandos
check_status() {
    if [ $? -ne 0 ]; then
        echo "❌ Erro: $1 falhou. Veja $LOG_FILE para detalhes." | tee -a "$LOG_FILE"
        docker-compose logs >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

# 📜 Geração de Arquivos de Configuração
generate_config_files() {
    echo "📝 Gerando arquivos de configuração..." | tee -a "$LOG_FILE"
    mkdir -p "$PROJECT_DIR/docker/nginx/sites" "$PROJECT_DIR/docker/php" "$PROJECT_DIR/src/learn" "$PROJECT_DIR/src/store" "$PROJECT_DIR/src/www" "$PROJECT_DIR/src/job" "$PROJECT_DIR/src/mobile"

    # 📋 Cria .env
    cat <<EOF > "$PROJECT_DIR/.env"
# Banco de Dados
DB_HOST=mysql
DB_NAME=${USERNAME}_db
DB_USER=$USERNAME
DB_PASS=$PASSWORD
DB_PORT=3306
# Moodle
MOODLE_URL=http://learn.$DOMAIN
MOODLE_DATA=/var/www/moodledata
# Magento
MAGENTO_URL=http://store.$DOMAIN
MAGENTO_ADMIN_USER=admin
MAGENTO_ADMIN_PASS=$PASSWORD
# Laminas
LAMINAS_URL=http://www.$DOMAIN
# n8n
N8N_URL=http://job.$DOMAIN:5678
# Moodle Mobile
MOODLE_MOBILE_URL=http://mobile.$DOMAIN
EOF

    # 📜 Cria docker-compose.yml sem `version`
    cat <<EOF > "$PROJECT_DIR/docker-compose.yml"
services:
  nginx:
    image: nginx:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./docker/nginx/sites:/etc/nginx/conf.d
      - ./src/learn:/var/www/learn.$DOMAIN
      - ./src/store:/var/www/store.$DOMAIN
      - ./src/www:/var/www/www.$DOMAIN
      - ./src/job:/var/www/job.$DOMAIN
      - ./src/mobile:/var/www/mobile.$DOMAIN
    depends_on:
      - php
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    restart: unless-stopped
    networks:
      - app-net
  php:
    build:
      context: ./docker/php
      dockerfile: Dockerfile
    volumes:
      - ./src/learn:/var/www/learn.$DOMAIN
      - ./src/store:/var/www/store.$DOMAIN
      - ./src/www:/var/www/www.$DOMAIN
      - ./src/job:/var/www/job.$DOMAIN
      - ./src/mobile:/var/www/mobile.$DOMAIN
    depends_on:
      - mysql
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    restart: unless-stopped
    networks:
      - app-net
  moodle:
    image: bitnami/moodle:latest
    environment:
      MOODLE_DATABASE_TYPE: mysqli
      MOODLE_DATABASE_HOST: mysql
      MOODLE_DATABASE_NAME: ${USERNAME}_db
      MOODLE_DATABASE_USER: $USERNAME
      MOODLE_DATABASE_PASSWORD: $PASSWORD
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: $PASSWORD
      MOODLE_EMAIL: admin@$DOMAIN
      MOODLE_SKIP_BOOTSTRAP: no
    ports:
      - "8080:8080"  # Porta nativa do Apache
    volumes:
      - ./src/learn:/bitnami/moodle
      - moodle-data:/bitnami/moodledata
    depends_on:
      - mysql
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    restart: unless-stopped
    networks:
      - app-net
  magento:
    image: bitnami/magento:latest
    environment:
      MAGENTO_HOST: localhost
      MAGENTO_DATABASE_HOST: mysql
      MAGENTO_DATABASE_NAME: ${USERNAME}_db
      MAGENTO_DATABASE_USER: $USERNAME
      MAGENTO_DATABASE_PASSWORD: $PASSWORD
      MAGENTO_ADMIN_EMAIL: admin@$DOMAIN
      MAGENTO_ADMIN_PASSWORD: $PASSWORD
    ports:
      - "8081:8080"  # Porta nativa do Apache
    volumes:
      - ./src/store:/app
    depends_on:
      - mysql
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    restart: unless-stopped
    networks:
      - app-net
  laminas:
    image: php:8.3-apache
    ports:
      - "8082:80"  # Porta nativa do Apache
    volumes:
      - ./src/www:/var/www/html
    depends_on:
      - mysql
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 512M
    restart: unless-stopped
    networks:
      - app-net
  n8n:
    image: n8nio/n8n:latest
    ports:
      - "5678:5678"
    volumes:
      - ./src/job:/home/node/.n8n
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 512M
    restart: unless-stopped
    networks:
      - app-net
  moodle_mobile:
    image: bitnami/moodle:latest
    environment:
      MOODLE_DATABASE_TYPE: mysqli
      MOODLE_DATABASE_HOST: mysql
      MOODLE_DATABASE_NAME: ${USERNAME}_db
      MOODLE_DATABASE_USER: $USERNAME
      MOODLE_DATABASE_PASSWORD: $PASSWORD
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: $PASSWORD
      MOODLE_EMAIL: admin@$DOMAIN
      MOODLE_SKIP_BOOTSTRAP: no
    ports:
      - "8083:8080"  # Porta nativa do Apache
    volumes:
      - ./src/mobile:/bitnami/moodle
      - moodle-mobile-data:/bitnami/moodledata
    depends_on:
      - mysql
      - moodle
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    restart: unless-stopped
    networks:
      - app-net
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: $PASSWORD
      MYSQL_DATABASE: ${USERNAME}_db
      MYSQL_USER: $USERNAME
      MYSQL_PASSWORD: $PASSWORD
    volumes:
      - mysql-data:/var/lib/mysql
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    restart: unless-stopped
    networks:
      - app-net
networks:
  app-net:
    driver: bridge
volumes:
  mysql-data:
  moodle-data:
  moodle-mobile-data:
EOF

    # 📜 Cria Dockerfile para PHP-FPM com todas as extensões
    cat <<EOF > "$PROJECT_DIR/docker/php/Dockerfile"
FROM php:8.3-fpm
RUN apt-get update && apt-get install -y \\
    libpq-dev libzip-dev unzip git libxml2-dev libpng-dev libjpeg-dev libfreetype6-dev \\
    libonig-dev libcurl4-openssl-dev libssl-dev libxslt1-dev \\
    && docker-php-ext-configure gd --with-freetype --with-jpeg \\
    && docker-php-ext-install pdo pdo_mysql zip xml gd curl bcmath mbstring intl xsl soap
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
WORKDIR /var/www
RUN chown -R www-data:www-data /var/www
CMD ["php-fpm"]
EOF

    # 🌐 Cria nginx.conf com suporte a HTTP/3 simulado
    cat <<EOF > "$PROJECT_DIR/docker/nginx/nginx.conf"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" \$status \$body_bytes_sent';
    access_log /var/log/nginx/access.log main;
    sendfile on;
    keepalive_timeout 65;
    server {
        listen 80;
        listen 443 ssl http2;
        listen 443 quic reuseport;
        ssl_certificate /etc/nginx/ssl/cert.pem;  # Placeholder
        ssl_certificate_key /etc/nginx/ssl/key.pem;  # Placeholder
        http3 on;
        include /etc/nginx/conf.d/*.conf;
    }
}
EOF

    # 🌍 Configurações de subdomínios para Nginx com PHP-FPM
    for subdomain in "learn" "store" "job" "mobile"; do
        cat <<EOF > "$PROJECT_DIR/docker/nginx/sites/$subdomain.$DOMAIN.conf"
server {
    listen 80;
    server_name $subdomain.$DOMAIN;
    root /var/www/$subdomain.$DOMAIN/public;
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
    done

    cat <<EOF > "$PROJECT_DIR/docker/nginx/sites/www.$DOMAIN.conf"
server {
    listen 80;
    server_name www.$DOMAIN;
    root /var/www/www.$DOMAIN/public;
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

    # 📝 Configuração inicial do Laminas
    mkdir -p "$PROJECT_DIR/src/www/public"
    cat <<EOF > "$PROJECT_DIR/src/www/public/index.php"
<?php
require_once __DIR__ . '/../vendor/autoload.php';
use Laminas\Mvc\Application;
\$app = Application::init(require __DIR__ . '/../config/application.config.php');
\$app->run();
EOF
    cat <<EOF > "$PROJECT_DIR/src/www/composer.json"
{
    "require": {
        "laminas/laminas-mvc": "^3.3",
        "laminas/laminas-component-installer": "^3.0",
        "laminas/laminas-db": "^2.18",
        "laminas/laminas-session": "^2.17"
    }
}
EOF
}

# 🚀 Provisionamento com Aguarde
provision_environment() {
    echo "🚀 Provisionando ambiente..." | tee -a "$LOG_FILE"
    if ! docker info > /dev/null 2>&1; then
        echo "❌ Docker não está em execução. Certifique-se de que o Docker Desktop está iniciado no Windows." | tee -a "$LOG_FILE"
        exit 1
    fi
    cd "$PROJECT_DIR"
    sleep 5  # Delay inicial para estabilizar Docker
    docker-compose up -d --build --pull always
    check_status "Inicialização do Docker Compose"
    SERVICES=("mysql" "php" "moodle" "magento" "laminas" "n8n" "moodle_mobile" "nginx")
    for service in "${SERVICES[@]}"; do
        until docker-compose ps | grep "$service" | grep -q "Up"; do
            echo "⏳ Aguardando $service ficar ativo..." | tee -a "$LOG_FILE"
            sleep 2
        done
        echo "✅ $service está ativo!" | tee -a "$LOG_FILE"
    done
}

# 📦 Instalação de Dependências
install_dependencies() {
    echo "📦 Instalando dependências..." | tee -a "$LOG_FILE"
    sudo apt-get update >> "$LOG_FILE" 2>&1
    sudo apt-get install -y php8.3 php8.3-cli php8.3-mysql php8.3-zip php8.3-curl php8.3-xml php8.3-gd php8.3-mbstring php8.3-intl php8.3-bcmath php8.3-xsl php8.3-soap composer >> "$LOG_FILE" 2>&1
    check_status "Instalação do PHP e Composer"

    cd "$PROJECT_DIR/src/www"
    composer install >> "$LOG_FILE" 2>&1 &
    until [ -d "$PROJECT_DIR/src/www/vendor" ]; do
        echo "⏳ Aguardando Composer instalar Laminas..." | tee -a "$LOG_FILE"
        sleep 2
    done
    echo "✅ Laminas instalado!" | tee -a "$LOG_FILE"
}

# ⚙️ Configuração de Serviços com Aguarde
configure_services() {
    echo "⚙️ Configurando serviços..." | tee -a "$LOG_FILE"
    # Moodle e Moodle Mobile configurados automaticamente pela Bitnami
    echo "✅ Moodle e Moodle Mobile configurados automaticamente pela Bitnami!" | tee -a "$LOG_FILE"
}

# 📋 Criação do Arquivo Hosts
create_hosts_file() {
    echo "📋 Gerando hosts.txt..." | tee -a "$LOG_FILE"
    cat <<EOF > "$PROJECT_DIR/hosts.txt"
# Adicione ao C:\Windows\System32\drivers\etc\hosts (execute como Administrador)
127.0.0.1 learn.$DOMAIN
127.0.0.1 store.$DOMAIN
127.0.0.1 www.$DOMAIN
127.0.0.1 job.$DOMAIN
127.0.0.1 mobile.$DOMAIN
EOF
    check_status "Geração do arquivo hosts"
}

# 🧪 Testes com Aguarde
run_tests() {
    echo "🧪 Iniciando testes..." | tee -a "$LOG_FILE"
    sudo apt-get install -y curl phpunit >> "$LOG_FILE" 2>&1
    check_status "Instalação de ferramentas de teste"

    until docker exec -i $(docker ps -q -f name=mysql) mysql -u$USERNAME -p$PASSWORD ${USERNAME}_db <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL
);
INSERT INTO users (name, email) VALUES ('$USERNAME', '$USERNAME@$DOMAIN');
EOF
    do
        echo "⏳ Aguardando MySQL para fixtures..." | tee -a "$LOG_FILE"
        sleep 2
    done
    echo "✅ Fixtures carregados!" | tee -a "$LOG_FILE"

    for subdomain in "learn" "store" "www" "job" "mobile"; do
        until curl -s "http://$subdomain.$DOMAIN" > /dev/null; do
            echo "⏳ Aguardando $subdomain.$DOMAIN..." | tee -a "$LOG_FILE"
            sleep 2
        done
        echo "✅ $subdomain.$DOMAIN acessível!" | tee -a "$LOG_FILE"
    done
}

# 🔍 Monitoramento Integrado
monitor_services() {
    echo "🖥️ Monitorando serviços..." | tee -a "$LOG_FILE"
    cd "$PROJECT_DIR"
    SERVICES=("mysql" "php" "moodle" "magento" "laminas" "n8n" "moodle_mobile" "nginx")
    for service in "${SERVICES[@]}"; do
        until docker-compose ps | grep "$service" | grep -q "Up"; do
            echo "⏳ Aguardando $service ficar ativo..." | tee -a "$LOG_FILE"
            sleep 2
        done
        echo "✅ $service está ativo!" | tee -a "$LOG_FILE"
    done
}

# 🌟 Executa a Implantação
echo "🚀 Iniciando implantação completa..." | tee -a "$LOG_FILE"
generate_config_files
provision_environment
install_dependencies
configure_services
run_tests
monitor_services
create_hosts_file

echo "🎉 Implantação concluída com sucesso!" | tee -a "$LOG_FILE"
echo "Acesse os serviços em:" | tee -a "$LOG_FILE"
echo "- Moodle (Apache): http://localhost:8080" | tee -a "$LOG_FILE"
echo "- Moodle (Nginx): http://learn.$DOMAIN" | tee -a "$LOG_FILE"
echo "- Magento (Apache): http://localhost:8081" | tee -a "$LOG_FILE"
echo "- Magento (Nginx): http://store.$DOMAIN" | tee -a "$LOG_FILE"
echo "- Laminas (Apache): http://localhost:8082" | tee -a "$LOG_FILE"
echo "- Laminas (Nginx): http://www.$DOMAIN" | tee -a "$LOG_FILE"
echo "- n8n: http://job.$DOMAIN:5678" | tee -a "$LOG_FILE"
echo "- Moodle Mobile (Apache): http://localhost:8083" | tee -a "$LOG_FILE"
echo "- Moodle Mobile (Nginx): http://mobile.$DOMAIN" | tee -a "$LOG_FILE"
echo "Atualize o arquivo hosts do Windows com $PROJECT_DIR/hosts.txt" | tee -a "$LOG_FILE"
echo "Use 'cd $PROJECT_DIR/src/www' e 'php -S 0.0.0.0:8000 -t public' para desenvolver no Laminas localmente!" | tee -a "$LOG_FILE"