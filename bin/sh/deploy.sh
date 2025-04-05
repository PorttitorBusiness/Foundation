#!/bin/bash

set -x  # 📜 Ativa saída detalhada para depuração

# 🚀 Define variáveis de ambiente
PROJECT_ROOT="$(pwd)"
PROJECT_DIR="$PROJECT_ROOT/projects"
LOG_FILE="$PROJECT_DIR/deploy.log"

# 📁 Cria o diretório do projeto
mkdir -p "$PROJECT_DIR"
echo "🚀 Iniciando implantação whitelabel via JSON" | tee -a "$LOG_FILE"

# ✅ Função para verificar o status de comandos
check_status() {
    if [ $? -ne 0 ]; then
        echo "❌ Erro: $1 falhou. Veja $LOG_FILE para detalhes." | tee -a "$LOG_FILE"
        docker-compose logs >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

# 📝 Lê configurações do project_master.json
if [ ! -f "$PROJECT_ROOT/project_master.json" ]; then
    echo "❌ Arquivo project_master.json não encontrado! Crie-o no diretório raiz." | tee -a "$LOG_FILE"
    exit 1
fi
DOMAIN=$(jq -r '.domain' "$PROJECT_ROOT/project_master.json")
PROJECT_NAME=$(jq -r '.project_name' "$PROJECT_ROOT/project_master.json")
ENVIRONMENT=$(jq -r '.environment // "development"' "$PROJECT_ROOT/project_master.json")
NGINX_PORTS=$(jq -r '.nginx.ports[]' "$PROJECT_ROOT/project_master.json" | tr '\n' ' ')
PHP_VERSION=$(jq -r '.php.version // "8.3"' "$PROJECT_ROOT/project_master.json")
REDIS_PASS=$(jq -r '.databases.redis.password // .project_name' "$PROJECT_ROOT/project_master.json")
MONGO_USER=$(jq -r '.databases.mongodb.username // .project_name' "$PROJECT_ROOT/project_master.json")
MONGO_PASS=$(jq -r '.databases.mongodb.password // .project_name' "$PROJECT_ROOT/project_master.json")
MYSQL_USER=$(jq -r '.databases.mysql.username // .project_name' "$PROJECT_ROOT/project_master.json")
MYSQL_PASS=$(jq -r '.databases.mysql.password // .project_name' "$PROJECT_ROOT/project_master.json")
SQLSERVER_PASS=$(jq -r '.databases.sqlserver.password // (.project_name + "@123")' "$PROJECT_ROOT/project_master.json")
ORACLE_PASS=$(jq -r '.databases.oracle.password // .project_name' "$PROJECT_ROOT/project_master.json")
echo "🌟 Configurações lidas: DOMAIN=$DOMAIN, PROJECT_NAME=$PROJECT_NAME, ENVIRONMENT=$ENVIRONMENT" | tee -a "$LOG_FILE"

# 📂 Define diretório específico do projeto
PROJECT_DIR="$PROJECT_DIR/$DOMAIN"
mkdir -p "$PROJECT_DIR"

# 📜 Geração de Arquivos de Configuração
generate_config_files() {
    echo "📝 Gerando arquivos de configuração..." | tee -a "$LOG_FILE"
    mkdir -p "$PROJECT_DIR/docker/nginx/sites" "$PROJECT_DIR/docker/php" "$PROJECT_DIR/src/admin.$DOMAIN" "$PROJECT_DIR/src/api.$DOMAIN" "$PROJECT_DIR/src/www.$DOMAIN" "$PROJECT_DIR/src/packages.$DOMAIN"

    # 📋 Cria .env
    cat <<EOF > "$PROJECT_DIR/.env"
# Projeto
PROJECT_NAME=$PROJECT_NAME
DOMAIN=$DOMAIN
ENVIRONMENT=$ENVIRONMENT
# Bancos
REDIS_HOST=redis
REDIS_PASS=$REDIS_PASS
MONGO_HOST=mongodb
MONGO_USER=$MONGO_USER
MONGO_PASS=$MONGO_PASS
MYSQL_HOST=mysql
MYSQL_USER=$MYSQL_USER
MYSQL_PASS=$MYSQL_PASS
SQLSERVER_HOST=sqlserver
SQLSERVER_PASS=$SQLSERVER_PASS
ORACLE_HOST=oracle
ORACLE_PASS=$ORACLE_PASS
EOF

    # 📜 Cria docker-compose.yml
    cat <<EOF > "$PROJECT_DIR/docker-compose.yml"
services:
  nginx:
    image: nginx:latest
    ports:
      - $NGINX_PORTS
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./docker/nginx/sites:/etc/nginx/conf.d
      - ./src/admin.$DOMAIN:/var/www/admin.$DOMAIN
      - ./src/api.$DOMAIN:/var/www/api.$DOMAIN
      - ./src/www.$DOMAIN:/var/www/www.$DOMAIN
      - ./src/packages.$DOMAIN:/var/www/packages.$DOMAIN
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
      - ./src/admin.$DOMAIN:/var/www/admin.$DOMAIN
      - ./src/api.$DOMAIN:/var/www/api.$DOMAIN
      - ./src/www.$DOMAIN:/var/www/www.$DOMAIN
      - ./src/packages.$DOMAIN:/var/www/packages.$DOMAIN
    depends_on:
      - redis
      - mongodb
      - mysql
      - sqlserver
      - oracle
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    restart: unless-stopped
    networks:
      - app-net
  redis:
    image: redis:latest
    command: redis-server --requirepass $REDIS_PASS
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
    restart: unless-stopped
    networks:
      - app-net
  mongodb:
    image: mongo:latest
    environment:
      MONGO_INITDB_ROOT_USERNAME: $MONGO_USER
      MONGO_INITDB_ROOT_PASSWORD: $MONGO_PASS
    volumes:
      - mongo-data:/data/db
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    restart: unless-stopped
    networks:
      - app-net
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_PASS
      MYSQL_DATABASE: ${PROJECT_NAME}_db
      MYSQL_USER: $MYSQL_USER
      MYSQL_PASSWORD: $MYSQL_PASS
    volumes:
      - mysql-data:/var/lib/mysql
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    restart: unless-stopped
    networks:
      - app-net
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2019-latest
    environment:
      ACCEPT_EULA: Y
      SA_PASSWORD: $SQLSERVER_PASS
      MSSQL_PID: Express
    volumes:
      - sqlserver-data:/var/opt/mssql
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    restart: unless-stopped
    networks:
      - app-net
  oracle:
    image: gvenzl/oracle-xe:latest
    environment:
      ORACLE_PASSWORD: $ORACLE_PASS
    volumes:
      - oracle-data:/opt/oracle/oradata
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
  mongo-data:
  mysql-data:
  sqlserver-data:
  oracle-data:
EOF

    # 📜 Cria Dockerfile para PHP-FPM
    cat <<EOF > "$PROJECT_DIR/docker/php/Dockerfile"
FROM php:$PHP_VERSION-fpm
RUN apt-get update && apt-get install -y \\
    libpq-dev libzip-dev unzip git libxml2-dev libpng-dev libjpeg-dev libfreetype6-dev \\
    libonig-dev libcurl4-openssl-dev libssl-dev libxslt1-dev \\
    && docker-php-ext-configure gd --with-freetype --with-jpeg \\
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql zip xml gd curl bcmath mbstring intl xsl soap
RUN pecl install redis mongodb && docker-php-ext-enable redis mongodb
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
WORKDIR /var/www
RUN chown -R www-data:www-data /var/www
CMD ["php-fpm"]
EOF

    # 🌐 Cria nginx.conf com HTTP/3 simulado
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
    for subdomain in "admin.$DOMAIN" "api.$DOMAIN" "www.$DOMAIN" "packages.$DOMAIN"; do
        cat <<EOF > "$PROJECT_DIR/docker/nginx/sites/$subdomain.conf"
server {
    listen 80;
    server_name $subdomain;
    root /var/www/$subdomain/public;
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

    # 📦 Clona os repositórios específicos
    git clone https://github.com/dotkernel/admin.git "$PROJECT_DIR/src/admin.$DOMAIN" || echo "⚠️ dotkernel/admin já clonado ou erro, prosseguindo..." | tee -a "$LOG_FILE"
    git clone https://github.com/dotkernel/api.git "$PROJECT_DIR/src/api.$DOMAIN" || echo "⚠️ dotkernel/api já clonado ou erro, prosseguindo..." | tee -a "$LOG_FILE"
    git clone https://github.com/project-satisfy/satisfy.git "$PROJECT_DIR/src/packages.$DOMAIN" || echo "⚠️ project-satisfy/satisfy já clonado ou erro, prosseguindo..." | tee -a "$LOG_FILE"
    mkdir -p "$PROJECT_DIR/src/www.$DOMAIN/public" && cd "$PROJECT_DIR/src/www.$DOMAIN" && composer create-project laminas/laminas-mvc-skeleton . || echo "⚠️ Laminas já criado ou erro, prosseguindo..." | tee -a "$LOG_FILE"
}

# 🚀 Provisionamento com Aguarde
provision_environment() {
    echo "🚀 Provisionando ambiente..." | tee -a "$LOG_FILE"
    if ! docker info > /dev/null 2>&1; then
        echo "❌ Docker não está em execução. Certifique-se de que o Docker Desktop está iniciado no Windows." | tee -a "$LOG_FILE"
        exit 1
    fi
    cd "$PROJECT_DIR"
    sleep 5  # ⏳ Delay inicial para estabilizar Docker
    docker-compose up -d --build --pull always
    check_status "Inicialização do Docker Compose"
    SERVICES=("mysql" "redis" "mongodb" "sqlserver" "oracle" "php" "nginx")
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
    sudo apt-get install -y php8.3 php8.3-cli php8.3-mysql php8.3-zip php8.3-curl php8.3-xml php8.3-gd php8.3-mbstring php8.3-intl php8.3-bcmath php8.3-xsl php8.3-soap composer jq >> "$LOG_FILE" 2>&1
    check_status "Instalação do PHP, Composer e jq"

    for dir in "admin.$DOMAIN" "api.$DOMAIN" "www.$DOMAIN" "packages.$DOMAIN"; do
        cd "$PROJECT_DIR/src/$dir"
        composer install >> "$LOG_FILE" 2>&1 &
        until [ -d "$PROJECT_DIR/src/$dir/vendor" ]; do
            echo "⏳ Aguardando Composer em $dir..." | tee -a "$LOG_FILE"
            sleep 2
        done
        echo "✅ Composer concluído em $dir!" | tee -a "$LOG_FILE"
    done
}

# 📋 Geração de Estruturas SQL
generate_sql_structures() {
    echo "📋 Gerando estruturas SQL para todos os bancos..." | tee -a "$LOG_FILE"
    mkdir -p "$PROJECT_DIR/db"

    # MySQL
    cat <<EOF > "$PROJECT_DIR/db/mysql_structure.sql"
CREATE TABLE IF NOT EXISTS projects (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    domain VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO projects (name, domain) VALUES ('$PROJECT_NAME', '$DOMAIN');
EOF

    # SQL Server
    cat <<EOF > "$PROJECT_DIR/db/sqlserver_structure.sql"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'projects')
BEGIN
    CREATE TABLE projects (
        id INT IDENTITY(1,1) PRIMARY KEY,
        name NVARCHAR(255) NOT NULL,
        domain NVARCHAR(255) NOT NULL,
        created_at DATETIME DEFAULT GETDATE()
    );
    INSERT INTO projects (name, domain) VALUES ('$PROJECT_NAME', '$DOMAIN');
END
EOF

    # Oracle
    cat <<EOF > "$PROJECT_DIR/db/oracle_structure.sql"
CREATE TABLE projects (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR2(255) NOT NULL,
    domain VARCHAR2(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO projects (name, domain) VALUES ('$PROJECT_NAME', '$DOMAIN');
EOF

    # MongoDB
    cat <<EOF > "$PROJECT_DIR/db/mongo_init.js"
db.projects.insertOne({
    name: "$PROJECT_NAME",
    domain: "$DOMAIN",
    created_at: new Date()
});
EOF

    # Redis
    cat <<EOF > "$PROJECT_DIR/db/redis_init.sh"
redis-cli -a $REDIS_PASS <<EOL
SET project:$PROJECT_NAME:domain $DOMAIN
EOL
EOF
    chmod +x "$PROJECT_DIR/db/redis_init.sh"
}

# ⚙️ Configuração de Bancos
configure_databases() {
    echo "⚙️ Configurando bancos..." | tee -a "$LOG_FILE"

    # MySQL
    until docker exec -i $(docker ps -q -f name=mysql) mysql -u$MYSQL_USER -p$MYSQL_PASS ${PROJECT_NAME}_db < "$PROJECT_DIR/db/mysql_structure.sql"; do
        echo "⏳ Aguardando MySQL..." | tee -a "$LOG_FILE"
        sleep 2
    done
    echo "✅ MySQL configurado!" | tee -a "$LOG_FILE"

    # SQL Server
    until docker exec -i $(docker ps -q -f name=sqlserver) /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SQLSERVER_PASS" -d master -i "$PROJECT_DIR/db/sqlserver_structure.sql"; do
        echo "⏳ Aguardando SQL Server..." | tee -a "$LOG_FILE"
        sleep 2
    done
    echo "✅ SQL Server configurado!" | tee -a "$LOG_FILE"

    # Oracle
    until docker exec -i $(docker ps -q -f name=oracle) sqlplus -s sys/$ORACLE_PASS@XE as sysdba @"$PROJECT_DIR/db/oracle_structure.sql"; do
        echo "⏳ Aguardando Oracle..." | tee -a "$LOG_FILE"
        sleep 2
    done
    echo "✅ Oracle configurado!" | tee -a "$LOG_FILE"

    # MongoDB
    until docker exec -i $(docker ps -q -f name=mongodb) mongosh -u $MONGO_USER -p $MONGO_PASS --authenticationDatabase admin < "$PROJECT_DIR/db/mongo_init.js"; do
        echo "⏳ Aguardando MongoDB..." | tee -a "$LOG_FILE"
        sleep 2
    done
    echo "✅ MongoDB configurado!" | tee -a "$LOG_FILE"

    # Redis
    until "$PROJECT_DIR/db/redis_init.sh"; do
        echo "⏳ Aguardando Redis..." | tee -a "$LOG_FILE"
        sleep 2
    done
    echo "✅ Redis configurado!" | tee -a "$LOG_FILE"
}

# 🧪 Testes com Aguarde
run_tests() {
    echo "🧪 Iniciando testes..." | tee -a "$LOG_FILE"
    sudo apt-get install -y curl phpunit >> "$LOG_FILE" 2>&1
    check_status "Instalação de ferramentas de teste"

    for subdomain in "admin.$DOMAIN" "api.$DOMAIN" "www.$DOMAIN" "packages.$DOMAIN"; do
        until curl -s "http://$subdomain" > /dev/null; do
            echo "⏳ Aguardando $subdomain..." | tee -a "$LOG_FILE"
            sleep 2
        done
        echo "✅ $subdomain acessível!" | tee -a "$LOG_FILE"
    done

    # Testes do Dotkernel e Laminas
    for dir in "admin.$DOMAIN" "api.$DOMAIN" "www.$DOMAIN"; do
        cd "$PROJECT_DIR/src/$dir"
        phpunit >> "$LOG_FILE" 2>&1
        check_status "Testes do $dir"
    done
}

# 📋 Criação do Arquivo Hosts
create_hosts_file() {
    echo "📋 Gerando hosts.txt..." | tee -a "$LOG_FILE"
    cat <<EOF > "$PROJECT_DIR/hosts.txt"
# Adicione ao C:\Windows\System32\drivers\etc\hosts (execute como Administrador)
127.0.0.1 admin.$DOMAIN
127.0.0.1 api.$DOMAIN
127.0.0.1 www.$DOMAIN
127.0.0.1 packages.$DOMAIN
EOF
    check_status "Geração do arquivo hosts"
}

# 🌟 Executa a Implantação
echo "🚀 Iniciando implantação completa..." | tee -a "$LOG_FILE"
generate_config_files
provision_environment
install_dependencies
generate_sql_structures
configure_databases
run_tests
create_hosts_file

echo "🎉 Implantação concluída com sucesso!" | tee -a "$LOG_FILE"
echo "Acesse os serviços em:" | tee -a "$LOG_FILE"
echo "- Admin: http://admin.$DOMAIN" | tee -a "$LOG_FILE"
echo "- API: http://api.$DOMAIN" | tee -a "$LOG_FILE"
echo "- WWW: http://www.$DOMAIN" | tee -a "$LOG_FILE"
echo "- Packages: http://packages.$DOMAIN" | tee -a "$LOG_FILE"
echo "Atualize o arquivo hosts do Windows com $PROJECT_DIR/hosts.txt" | tee -a "$LOG_FILE"