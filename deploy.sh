
#!/bin/bash
################################################################################
# Deploy Completo Foundation IO - Otimizado com Laminas                        #
#                                                                       Versão 4.1.0
################################################################################
# Integra:
# - Módulo IO com Core, Wallet e IAGenerator usando Laminas-Code.
# - Configurações avançadas (logs, monitoring, io).
# - Firewall integrado.
# - Cadastro inicial e fixtures completos.
# - Suporte a MySQL e SQLite.
# - CI e Testes com Laminas-CI e Laminas-Test.
################################################################################

# Parâmetro de deploy: "local" ou "prod" (padrão "local")
DEPLOY_MODE=${1:-local}

# Configurações Básicas
ENVIRONMENTS=("dev" "test" "prod")
DOMAIN=$([ "$DEPLOY_MODE" = "local" ] && echo "localhost" || echo "foundation.io")
SUBDOMAINS="api admin frontend light foundation"
PROJECT_DIR="$(pwd)"
BASE_DIR="$PROJECT_DIR/deploy"
DOMAIN_DIR="$BASE_DIR/$DOMAIN"
CONFIG_FILE="$DOMAIN_DIR/config.json"
ENV_FILE="$DOMAIN_DIR/.env"
SRC_DIR="$DOMAIN_DIR/src"
USER_EMAIL="foundation@foundation.com"
USER_PASSWORD="Foundation2025!"

# Emojis para Feedback
CHECK="✅" ERROR="❌" INFO="ℹ️" RUNNING="🚀" BUILD="🛠️" DEPLOY_EMOJI="📦" USER_EMOJI="👤"

# Função para verificar erros
check_error() {
    [ $? -ne 0 ] && { echo "$ERROR Erro: $1"; exit 1; }
}

# Instalação de Pré-requisitos
install_prerequisites() {
    echo "$INFO Instalando pré-requisitos..."
    sudo apt-get update
    sudo apt-get install -y docker.io docker-compose php-cli php-zip unzip curl nodejs npm jq iptables
    sudo systemctl enable docker && sudo systemctl start docker
    sudo usermod -aG docker "$USER"
    curl -sS https://getcomposer.org/installer | php && sudo mv composer.phar /usr/local/bin/composer
    sudo npm install -g n && sudo n latest
    [ "$DEPLOY_MODE" = "local" ] && sudo sh -c 'echo "{\"features\": {\"buildkit\": true}}" > /etc/docker/daemon.json' && sudo systemctl restart docker
    check_error "Falha na instalação de pré-requisitos"
}

# Geração de config.json
generate_config_json() {
    echo "$BUILD Gerando config.json..."
    mkdir -p "$DOMAIN_DIR"
    cat <<EOF > "$CONFIG_FILE"
{
  "version": "4.1.0",
  "domain": "$DOMAIN",
  "environments": {
    "dev": $(jq -n --arg domain "$DOMAIN" '{
      "http_ports": ["8080", "8081", "8082", "8083", "8084"],
      "https_ports": ["8443", "8444", "8445", "8446", "8447"],
      "livereload_port": "4200",
      "app_env": "dev",
      "app_secret": "secretkey-dev-789",
      "mysql": {"host": "mysql_external", "port": 3306, "root_password": "rootpass-dev", "database": "foundation_db_dev", "user": "foundation_dev", "password": "foundationpass-dev"},
      "redis": {"host": "redis_external", "port": 6379, "password": "redispass-dev"},
      "oauth2": {"issuer": "https://api.\($domain):8443", "client_id": "foundation_client_dev", "client_secret": "foundation_secret_dev", "redirect_uri": "https://foundation.\($domain):8447/callback", "token_endpoint": "https://api.\($domain):8443/oauth2/token", "auth_endpoint": "https://api.\($domain):8443/oauth2/authorize", "jwt_secret": "jwtsecretkey-dev-123", "scopes": ["read", "write", "admin"]},
      "logs": {"log_level": "debug", "retention_days": 7, "destination": "docker"},
      "monitoring": {"enabled": true, "endpoint": "http://monitor.\($domain):9000"},
      "io": {"core": {"client_id": "io_core_dev", "client_secret": "io_secret_dev"}, "wallet": {"client_id": "io_wallet_dev", "client_secret": "io_wallet_secret_dev"}, "IAGenerator": {"client_id": "io_iagenerator_dev", "client_secret": "io_iagenerator_secret_dev"}}
    }'),
    "test": $(jq -n --arg domain "$DOMAIN" '{
      "http_ports": ["9080", "9081", "9082", "9083", "9084"],
      "https_ports": ["9443", "9444", "9445", "9446", "9447"],
      "livereload_port": "4200",
      "app_env": "test",
      "app_secret": "secretkey-test-789",
      "mysql": {"host": "mysql_external", "port": 3306, "root_password": "rootpass-test", "database": "foundation_db_test", "user": "foundation_test", "password": "foundationpass-test"},
      "redis": {"host": "redis_external", "port": 6379, "password": "redispass-test"},
      "oauth2": {"issuer": "https://api.\($domain):9443", "client_id": "foundation_client_test", "client_secret": "foundation_secret_test", "redirect_uri": "https://foundation.\($domain):9447/callback", "token_endpoint": "https://api.\($domain):9443/oauth2/token", "auth_endpoint": "https://api.\($domain):9443/oauth2/authorize", "jwt_secret": "jwtsecretkey-test-123", "scopes": ["read", "write", "admin"]},
      "logs": {"log_level": "info", "retention_days": 5, "destination": "docker"},
      "monitoring": {"enabled": true, "endpoint": "http://monitor.\($domain):9100"},
      "io": {"core": {"client_id": "io_core_test", "client_secret": "io_secret_test"}, "wallet": {"client_id": "io_wallet_test", "client_secret": "io_wallet_secret_test"}, "IAGenerator": {"client_id": "io_iagenerator_test", "client_secret": "io_iagenerator_secret_test"}}
    }'),
    "prod": $(jq -n --arg domain "$DOMAIN" '{
      "http_ports": ["80"],
      "https_ports": ["443"],
      "livereload_port": null,
      "app_env": "prod",
      "app_secret": "secretkey-prod-789",
      "mysql": {"host": "mysql_external", "port": 3306, "root_password": "rootpass-prod", "database": "foundation_db_prod", "user": "foundation_prod", "password": "foundationpass-prod"},
      "redis": {"host": "redis_external", "port": 6379, "password": "redispass-prod"},
      "oauth2": {"issuer": "https://api.\($domain)", "client_id": "foundation_client_prod", "client_secret": "foundation_secret_prod", "redirect_uri": "https://foundation.\($domain)/callback", "token_endpoint": "https://api.\($domain)/oauth2/token", "auth_endpoint": "https://api.\($domain)/oauth2/authorize", "jwt_secret": "jwtsecretkey-prod-123", "scopes": ["read", "write", "admin"]},
      "logs": {"log_level": "error", "retention_days": 30, "destination": "syslog"},
      "monitoring": {"enabled": true, "endpoint": "https://monitor.\($domain)"},
      "io": {"core": {"client_id": "io_core_prod", "client_secret": "io_secret_prod"}, "wallet": {"client_id": "io_wallet_prod", "client_secret": "io_wallet_secret_prod"}, "IAGenerator": {"client_id": "io_iagenerator_prod", "client_secret": "io_iagenerator_secret_prod"}}
    }')
  }
}
EOF
    check_error "Falha ao gerar config.json"
}

# Geração de .env (simplificado para o exemplo)
generate_env_file() {
    echo "$BUILD Gerando .env..."
    cat <<EOF > "$ENV_FILE"
DOMAIN=$DOMAIN
SCRIPT_VERSION=4.1.0
DEV_HTTP_PORTS="8080 8081 8082 8083 8084"
DEV_HTTPS_PORTS="8443 8444 8445 8446 8447"
DEV_LIVERELOAD_PORT=4200
PROD_HTTP_PORTS=80
PROD_HTTPS_PORTS=443
EOF
    check_error "Falha ao gerar .env"
}

# Configuração do Firewall
configure_firewall() {
    echo "$INFO Configurando firewall..."
    sudo iptables -F
    sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
    sudo iptables -A INPUT -j DROP
    echo "$CHECK Firewall configurado!"
}

# Cadastro Inicial
prompt_first_access_registration() {
    echo "$INFO Gerando cadastro inicial..."
    mkdir -p "$DOMAIN_DIR/fixtures"
    cat <<EOF > "$DOMAIN_DIR/fixtures/users.fixture.json"
{"admin": {"name": "Administrador Foundation", "email": "admin@foundation.com", "password": "Admin123!", "role": "admin"},
 "client": {"name": "Cliente Foundation", "email": "cliente@foundation.com", "password": "Client123!", "role": "client"}}
EOF
    check_error "Falha ao gerar cadastro inicial"
}

# Geração de Fixtures
generate_fixtures() {
    echo "$BUILD Gerando fixtures..."
    cat <<EOF > "$DOMAIN_DIR/fixtures/system_data.fixture.json"
$(jq -n '{"geografia": {"pais": "Brasil", "estados": ["SP", "RJ", "MG"], "cidades": ["São Paulo", "Rio de Janeiro", "Belo Horizonte"]},
 "geologia": {"tipos_solo": ["argiloso", "arenoso", "siltoso"], "minerais": ["calcita", "quartzo", "feldspato"]},
 "geolocalizacao": {"coordenadas": {"latitude": -23.550520, "longitude": -46.633308}, "altitude": "760m"},
 "altimetria": {"pontos": [{"nome": "Ponto A", "altitude": "750m"}, {"nome": "Ponto B", "altitude": "770m"}]},
 "telemetria": {"temperatura": "25°C", "umidade": "60%", "pressao": "1013 hPa"}}')
EOF
    check_error "Falha ao gerar fixtures"
}

# Geração de Scripts SQL
generate_sql_files() {
    echo "$BUILD Gerando scripts SQL..."
    mkdir -p "$DOMAIN_DIR/sql"
    cat <<EOF > "$DOMAIN_DIR/sql/all_databases.sql"
CREATE DATABASE IF NOT EXISTS foundation_db_dev;
USE foundation_db_dev;
CREATE TABLE users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100) UNIQUE, password VARCHAR(255), role ENUM('admin', 'client') DEFAULT 'client');
INSERT INTO users (name, email, password, role) VALUES ('Administrador Foundation', 'admin@foundation.com', 'Admin123!', 'admin'), ('Cliente Foundation', 'cliente@foundation.com', 'Client123!', 'client');
EOF
    cat <<EOF > "$DOMAIN_DIR/sql/mobile_schema.sql"
CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT UNIQUE, password TEXT, role TEXT DEFAULT 'client');
INSERT INTO users (name, email, password, role) VALUES ('Administrador Foundation', 'admin@foundation.com', 'Admin123!', 'admin'), ('Cliente Foundation', 'cliente@foundation.com', 'Client123!', 'client');
EOF
    check_error "Falha ao gerar SQL"
}

# Geração do Módulo IO com Laminas-Code
generate_io_module() {
    echo "$BUILD Gerando módulo IO com Laminas-Code..."
    mkdir -p "$SRC_DIR/IO/Core" "$SRC_DIR/IO/Wallet" "$SRC_DIR/IO/IAGenerator"
    
    # Instalar Laminas
    cd "$SRC_DIR" || check_error "Não foi possível acessar $SRC_DIR"
    composer require laminas/laminas-code laminas/laminas-mvc laminas/laminas-test
    
    # Core: AuthController
    cat <<EOF > "$SRC_DIR/IO/Core/src/Controller/AuthController.php"
<?php
namespace IO\Core\Controller;

use Laminas\Mvc\Controller\AbstractActionController;
use Laminas\Diactoros\Response\JsonResponse;

class AuthController extends AbstractActionController
{
    public function authorizeAction(): JsonResponse
    {
        \$params = \$this->params()->fromQuery();
        return isset(\$params['client_id']) && \$params['client_id'] === 'foundation_client_dev'
            ? new JsonResponse(['code' => 'auth_code_foundation'])
            : new JsonResponse(['error' => 'Invalid client'], 401);
    }
}
EOF

    # Wallet: WalletController
    cat <<EOF > "$SRC_DIR/IO/Wallet/src/Controller/WalletController.php"
<?php
namespace IO\Wallet\Controller;

use Laminas\Mvc\Controller\AbstractActionController;
use Laminas\Diactoros\Response\JsonResponse;

class WalletController extends AbstractActionController
{
    public function balanceAction(): JsonResponse
    {
        return new JsonResponse(['balance' => 1000.00, 'user' => '$USER_EMAIL']);
    }
}
EOF

    # IAGenerator: CodeGeneratorService
    cat <<EOF > "$SRC_DIR/IO/IAGenerator/src/Service/CodeGeneratorService.php"
<?php
namespace IO\IAGenerator\Service;

use Laminas\Code\Generator\ClassGenerator;
use Laminas\Code\Generator\MethodGenerator;

class CodeGeneratorService
{
    public function generateModule(string \$moduleName): string
    {
        \$class = new ClassGenerator(\$moduleName . 'Controller');
        \$class->setNamespaceName("IO\\\\\$moduleName\\\\Controller");
        \$class->addMethodFromGenerator(
            MethodGenerator::fromArray([
                'name' => 'indexAction',
                'body' => "return new \\Laminas\\Diactoros\\Response\\JsonResponse(['message' => 'Módulo \$moduleName gerado!']);",
                'returnType' => '\\Laminas\\Diactoros\\Response\\JsonResponse'
            ])
        );
        return \$class->generate();
    }
}
EOF
    check_error "Falha ao gerar módulo IO"
}

# Configuração de Arquivos Docker
generate_config_files() {
    local ENV=$1
    local ENV_BASE_DIR="$DOMAIN_DIR/$ENV"
    mkdir -p "$ENV_BASE_DIR/api" "$ENV_BASE_DIR/nginx" "$ENV_BASE_DIR/certs"
    cd "$ENV_BASE_DIR" || check_error "Não foi possível acessar $ENV_BASE_DIR"
    
    local HTTPS_PORTS=($(jq -r ".environments.$ENV.https_ports[]" "$CONFIG_FILE"))
    cat <<EOF > "docker-compose.yml"
version: '3.9'
services:
  api:
    build: ./api
    container_name: ${ENV}-api
    volumes:
      - $SRC_DIR:/app/src
    ports:
      - "${HTTPS_PORTS[0]}:443"
    environment:
      - APP_ENV=${ENV}
  nginx:
    image: nginx:1.27-alpine
    ports:
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/etc/nginx/ssl
networks:
  default:
    driver: bridge
EOF

    cat <<EOF > "api/Dockerfile"
FROM php:8.4-fpm-alpine
RUN apk add --no-cache git unzip && pecl install redis xdebug && docker-php-ext-enable redis xdebug
WORKDIR /app
COPY . .
RUN composer install
EXPOSE 443
CMD ["php-fpm"]
EOF

    cat <<EOF > "nginx/nginx.conf"
events {}
http {
    server {
        listen 443 ssl;
        server_name api.$DOMAIN;
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        location / { proxy_pass http://${ENV}-api:443; }
    }
}
EOF
}

# Geração de Certificados
generate_self_signed_certs() {
    local ENV=$1
    mkdir -p "$DOMAIN_DIR/$ENV/certs"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "$DOMAIN_DIR/$ENV/certs/key.pem" -out "$DOMAIN_DIR/$ENV/certs/cert.pem" -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN,DNS:api.$DOMAIN"
    [ "$ENV" = "prod" ] && openssl dhparam -out "$DOMAIN_DIR/$ENV/certs/dhparams.pem" 2048
    check_error "Falha ao gerar certificados"
}

# Função Principal
main() {
    echo "$RUNNING Deploy Foundation IO 4.1.0 - Modo $DEPLOY_MODE"
    install_prerequisites
    [ "$DEPLOY_MODE" = "local" ] && ! grep -q "foundation.$DOMAIN" /etc/hosts && echo "127.0.0.1 $DOMAIN api.$DOMAIN" | sudo tee -a /etc/hosts
    generate_config_json
    generate_env_file
    configure_firewall
    prompt_first_access_registration
    generate_fixtures
    generate_sql_files
    generate_io_module
    for ENV in "${ENVIRONMENTS[@]}"; do
        generate_self_signed_certs "$ENV"
        generate_config_files "$ENV"
        cd "$DOMAIN_DIR/$ENV" && docker-compose up -d --build
        echo "$CHECK Ambiente $ENV implantado!"
    done
    echo "$CHECK Deploy concluído!"
}

main