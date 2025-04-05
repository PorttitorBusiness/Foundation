#!/bin/bash

# Load variables
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    read -p "Enter username (e.g., joao): " USERNAME
    read -s -p "Enter password: " PASSWORD
    echo
fi
DOMAIN="${USERNAME}.local"
PROJECT_DIR="$(pwd)/alertlocal"
LOG_FILE="$PROJECT_DIR/test.log"
echo "Testing domain: $DOMAIN" | tee -a "$LOG_FILE"

# Check project directory
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Project directory not found. Run deploy_alertlocal.sh first." | tee -a "$LOG_FILE"
    exit 1
fi

# Install testing tools
echo "Installing testing dependencies..." | tee -a "$LOG_FILE"
sudo apt-get update
sudo apt-get install -y curl apache2-utils phpunit jq >> "$LOG_FILE" 2>&1
check_status "Installing testing tools"

cd "$PROJECT_DIR"

# Wait for services
wait_for_services() {
    echo "Waiting for services to be ready..." | tee -a "$LOG_FILE"
    for subdomain in "www" "api" "auth" "admin"; do
        until curl -s "http://$subdomain.$DOMAIN" > /dev/null; do
            echo "Waiting for $subdomain.$DOMAIN..." | tee -a "$LOG_FILE"
            sleep 2
        done
        echo "$subdomain.$DOMAIN is up!" | tee -a "$LOG_FILE"
    done
}

# Provision test files
provision_tests() {
    echo "Provisioning test files..." | tee -a "$LOG_FILE"

    # Moodle tests (www)
    mkdir -p "$PROJECT_DIR/src/www/tests"
    cat <<EOF > "$PROJECT_DIR/src/www/tests/MoodleTest.php"
<?php
use PHPUnit\Framework\TestCase;

class MoodleTest extends TestCase {
    public function testMoodleConfigExists() {
        \$this->assertFileExists('/var/www/www.$DOMAIN/config.php');
    }

    public function testCourseCreation() {
        \$response = file_get_contents('http://api.$DOMAIN/courses/create?difficulty=intermediate');
        \$data = json_decode(\$response, true);
        \$this->assertArrayHasKey('course_id', \$data);
    }
}
EOF

    # API tests (api)
    mkdir -p "$PROJECT_DIR/src/api/tests"
    cat <<EOF > "$PROJECT_DIR/src/api/tests/ApiTest.php"
<?php
use PHPUnit\Framework\TestCase;

class ApiTest extends TestCase {
    private \$token;

    public function setUp(): void {
        \$ch = curl_init('http://auth.$DOMAIN/token');
        curl_setopt(\$ch, CURLOPT_POST, 1);
        curl_setopt(\$ch, CURLOPT_POSTFIELDS, 'grant_type=password&username=$USERNAME&password=$PASSWORD');
        curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
        \$response = json_decode(curl_exec(\$ch), true);
        curl_close(\$ch);
        \$this->token = \$response['access_token'] ?? '';
    }

    public function testApiRoot() {
        \$response = file_get_contents('http://api.$DOMAIN');
        \$this->assertNotFalse(\$response);
    }

    public function testUserManagement() {
        \$ch = curl_init('http://api.$DOMAIN/users');
        curl_setopt(\$ch, CURLOPT_HTTPHEADER, ["Authorization: Bearer \$this->token"]);
        curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
        \$response = json_decode(curl_exec(\$ch), true);
        curl_close(\$ch);
        \$this->assertArrayHasKey('users', \$response);
    }

    public function testCourseCreation() {
        \$ch = curl_init('http://api.$DOMAIN/courses/create');
        curl_setopt(\$ch, CURLOPT_POST, 1);
        curl_setopt(\$ch, CURLOPT_POSTFIELDS, json_encode(['difficulty' => 'intermediate']));
        curl_setopt(\$ch, CURLOPT_HTTPHEADER, ["Authorization: Bearer \$this->token", "Content-Type: application/json"]);
        curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
        \$response = json_decode(curl_exec(\$ch), true);
        curl_close(\$ch);
        \$this->assertArrayHasKey('course_id', \$response);
    }
}
EOF

    # OAuth2 tests (auth)
    mkdir -p "$PROJECT_DIR/src/auth/tests"
    cat <<EOF > "$PROJECT_DIR/src/auth/tests/OAuth2Test.php"
<?php
use PHPUnit\Framework\TestCase;

class OAuth2Test extends TestCase {
    public function testTokenIssuance() {
        \$ch = curl_init('http://auth.$DOMAIN/token');
        curl_setopt(\$ch, CURLOPT_POST, 1);
        curl_setopt(\$ch, CURLOPT_POSTFIELDS, 'grant_type=password&username=$USERNAME&password=$PASSWORD');
        curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
        \$response = json_decode(curl_exec(\$ch), true);
        curl_close(\$ch);
        \$this->assertArrayHasKey('access_token', \$response);
    }

    public function testInvalidCredentials() {
        \$ch = curl_init('http://auth.$DOMAIN/token');
        curl_setopt(\$ch, CURLOPT_POST, 1);
        curl_setopt(\$ch, CURLOPT_POSTFIELDS, 'grant_type=password&username=wrong&password=wrong');
        curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
        \$response = json_decode(curl_exec(\$ch), true);
        curl_close(\$ch);
        \$this->assertArrayHasKey('error', \$response);
    }
}
EOF

    # Admin tests (admin)
    mkdir -p "$PROJECT_DIR/src/admin/tests"
    cat <<EOF > "$PROJECT_DIR/src/admin/tests/AdminTest.php"
<?php
use PHPUnit\Framework\TestCase;

class AdminTest extends TestCase {
    private \$token;

    public function setUp(): void {
        \$ch = curl_init('http://auth.$DOMAIN/token');
        curl_setopt(\$ch, CURLOPT_POST, 1);
        curl_setopt(\$ch, CURLOPT_POSTFIELDS, 'grant_type=password&username=$USERNAME&password=$PASSWORD');
        curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
        \$response = json_decode(curl_exec(\$ch), true);
        curl_close(\$ch);
        \$this->token = \$response['access_token'] ?? '';
    }

    public function testAdminRoot() {
        \$response = file_get_contents('http://admin.$DOMAIN');
        \$this->assertNotFalse(\$response);
    }

    public function testUserManagement() {
        \$ch = curl_init('http://admin.$DOMAIN/users');
        curl_setopt(\$ch, CURLOPT_HTTPHEADER, ["Authorization: Bearer \$this->token"]);
        curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
        \$response = json_decode(curl_exec(\$ch), true);
        curl_close(\$ch);
        \$this->assertArrayHasKey('users', \$response);
    }
}
EOF
}

# Run unit tests
run_unit_tests() {
    echo "Running unit tests..." | tee -a "$LOG_FILE"
    for service in "www" "api" "auth" "admin"; do
        echo "Testing $service.$DOMAIN..." | tee -a "$LOG_FILE"
        docker exec -it $(docker ps -q -f name=php) phpunit "/var/www/$service.$DOMAIN/tests" >> "$LOG_FILE" 2>&1
        check_status "Unit tests for $service"
    done
}

# Run integration tests
run_integration_tests() {
    echo "Running integration tests..." | tee -a "$LOG_FILE"
    TOKEN=$(curl -s -X POST "http://auth.$DOMAIN/token" -d "grant_type=password&username=$USERNAME&password=$PASSWORD" | jq -r '.access_token')
    if [ -n "$TOKEN" ]; then
        # API -> Moodle course creation
        curl -s -X POST "http://api.$DOMAIN/courses/create" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"difficulty": "intermediate"}' | grep -q "course_id"
        check_status "API to Moodle course creation"

        # API -> Admin user management
        curl -s -H "Authorization: Bearer $TOKEN" "http://api.$DOMAIN/users" | grep -q "users"
        check_status "API to Admin user management"
    else
        echo "Failed to obtain OAuth2 token. Check logs." | tee -a "$LOG_FILE"
        docker-compose logs >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

# Run performance tests
run_performance_tests() {
    echo "Running performance tests..." | tee -a "$LOG_FILE"
    for subdomain in "www" "api" "auth" "admin"; do
        ab -n 200 -c 20 "http://$subdomain.$DOMAIN/" > "$PROJECT_DIR/$subdomain_performance.log" 2>> "$LOG_FILE"
        if grep -q "Requests per second" "$PROJECT_DIR/$subdomain_performance.log"; then
            echo "$subdomain.$DOMAIN performance test passed" | tee -a "$LOG_FILE"
        else
            echo "Performance test failed for $subdomain.$DOMAIN. Check $subdomain_performance.log" | tee -a "$LOG_FILE"
            exit 1
        fi
    done
}

# Run security tests
run_security_tests() {
    echo "Running security tests..." | tee -a "$LOG_FILE"
    for subdomain in "www" "api" "auth" "admin"; do
        # Directory listing
        curl -s "http://$subdomain.$DOMAIN/test_dir/" | grep -q "403" || echo "Warning: Directory listing enabled on $subdomain.$DOMAIN" | tee -a "$LOG_FILE"
        # Admin page exposure
        curl -s "http://$subdomain.$DOMAIN/admin" | grep -q "404\|403" || echo "Warning: Admin page exposed on $subdomain.$DOMAIN" | tee -a "$LOG_FILE"
    done
}

# Main execution
echo "Starting test provisioning..." | tee -a "$LOG_FILE"
wait_for_services
provision_tests
run_unit_tests
run_integration_tests
run_performance_tests
run_security_tests

echo "All tests completed successfully!" | tee -a "$LOG_FILE"
echo "Logs available in $LOG_FILE and $PROJECT_DIR/*_performance.log" | tee -a "$LOG_FILE"