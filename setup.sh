#!/bin/bash
#
# Sentry Self-Hosted Setup Script
# This script clones official Sentry repo and prepares configuration
# Usage: ./setup.sh
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Output functions
log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Prompt with default
prompt_input() {
    local prompt_text=$1
    local default_value=$2
    local input_value

    read -p "  ${prompt_text} [${default_value}]: " input_value
    echo "${input_value:-$default_value}"
}

# Validate domain
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ \. ]]; then
        log_error "Invalid domain: $domain (must contain a dot)"
    fi
}

# Validate retention
validate_retention() {
    local retention=$1
    if ! [[ $retention =~ ^[0-9]+$ ]]; then
        log_error "Invalid retention: $retention (must be a number)"
    fi
    if [ "$retention" -lt 7 ]; then
        log_warning "Retention ${retention} days is very short (minimum: 7)"
    fi
}

# Clone official Sentry repo
clone_sentry_repo() {
    if [ -d "self-hosted" ]; then
        log_warning "self-hosted/ directory exists, skipping clone"
        return
    fi

    log_info "Cloning official Sentry self-hosted repository..."
    if git clone https://github.com/getsentry/self-hosted.git; then
        log_success "Cloned Sentry repository"
    else
        log_error "Failed to clone Sentry repository"
    fi
}

# Copy config files from examples
copy_config_files() {
    log_info "Copying configuration files..."

    if [ ! -f "self-hosted/sentry/config.yml" ]; then
        if [ ! -f "self-hosted/sentry/config.example.yml" ]; then
            log_error "File not found: self-hosted/sentry/config.example.yml"
        fi
        cp "self-hosted/sentry/config.example.yml" "self-hosted/sentry/config.yml"
        log_success "Created self-hosted/sentry/config.yml"
    else
        log_warning "self-hosted/sentry/config.yml exists, skipping"
    fi

    if [ ! -f "self-hosted/sentry/sentry.conf.py" ]; then
        if [ ! -f "self-hosted/sentry/sentry.conf.example.py" ]; then
            log_error "File not found: self-hosted/sentry/sentry.conf.example.py"
        fi
        cp "self-hosted/sentry/sentry.conf.example.py" "self-hosted/sentry/sentry.conf.py"
        log_success "Created self-hosted/sentry/sentry.conf.py"
    else
        log_warning "self-hosted/sentry/sentry.conf.py exists, skipping"
    fi
}

# Update config.yml
update_config_yml() {
    local domain=$1
    local mail_hostname=$2

    log_info "Updating configuration with domain and mail..."

    cd self-hosted

    if grep -q "^# system.url-prefix:" "sentry/config.yml"; then
        sed -i.bak "s|^# system.url-prefix:.*|system.url-prefix: 'https://${domain}'|" "sentry/config.yml"
        log_success "Set domain: https://${domain}"
    fi

    if grep -q "^# mail.list-namespace:" "sentry/config.yml"; then
        sed -i.bak "s|^# mail.list-namespace:.*|mail.list-namespace: '${mail_hostname}'|" "sentry/config.yml"
        log_success "Set mail hostname: ${mail_hostname}"
    fi

    rm -f "sentry/config.yml.bak"

    cd ..
}

# Generate .env.custom
generate_env_custom() {
    local retention=$1
    local mail_hostname=$2

    log_info "Generating .env.custom..."

    cat > self-hosted/.env.custom <<EOF
# Sentry Custom Configuration
COMPOSE_PROFILES=feature-complete
SENTRY_EVENT_RETENTION_DAYS=${retention}
SENTRY_MAIL_HOST=${mail_hostname}
SENTRY_TASKWORKER_CONCURRENCY=4
EOF

    log_success "Generated .env.custom"
}

# Generate docker-compose override
generate_docker_compose_override() {
    local network=$1

    log_info "Generating docker-compose.override.yml for network ${network}..."

    cat > self-hosted/docker-compose.override.yml <<'OVERRIDE_EOF'
version: '3.8'

services:
  web:
    networks:
      - custom-net
  worker:
    networks:
      - custom-net
  ingest-consumer:
    networks:
      - custom-net
  post-process-forwarder:
    networks:
      - custom-net
  snuba-api:
    networks:
      - custom-net
  snuba-consumer:
    networks:
      - custom-net
  snuba-replacer:
    networks:
      - custom-net
  snuba-subscription-scheduler:
    networks:
      - custom-net
  snuba-subscription-executor:
    networks:
      - custom-net
  symbolicator:
    networks:
      - custom-net
  vroom:
    networks:
      - custom-net
  relay:
    networks:
      - custom-net
  uptime-checker:
    networks:
      - custom-net
  taskworker:
    networks:
      - custom-net
  taskbroker:
    networks:
      - custom-net
  postgres:
    networks:
      - custom-net
  redis:
    networks:
      - custom-net
  kafka:
    networks:
      - custom-net
  clickhouse:
    networks:
      - custom-net
  memcached:
    networks:
      - custom-net
  seaweedfs:
    networks:
      - custom-net
  smtp:
    networks:
      - custom-net

networks:
  custom-net:
    external: true
    name: ${network}
OVERRIDE_EOF

    log_success "Added all services to network: ${network}"
}

# Generate Nginx configuration
generate_nginx_config() {
    local domain=$1

    log_info "Generating Nginx configuration..."

    cat > nginx-sentry.conf <<'NGINX_EOF'
# Sentry Self-Hosted Nginx Configuration
# Domain: {DOMAIN}
# Upstream: sentry-web:9000

server {
    listen 80;
    listen [::]:80;
    server_name {DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name {DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/{DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{DOMAIN}/privkey.pem;

    add_header Strict-Transport-Security "max-age=63072000" always;
    client_max_body_size 100m;

    # SDK Ingest Endpoints
    location ~ ^/api/[0-9]+/(envelope|minidump|security|store|unreal|csp-report|nel)/ {
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Credentials false always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, OPTIONS" always;
        add_header Access-Control-Allow-Headers "sentry-trace, baggage, content-type" always;

        if ($request_method = 'OPTIONS') {
            add_header Content-Length 0;
            return 204;
        }

        proxy_pass http://sentry-web:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 120s;
    }

    # Main UI and API
    location / {
        proxy_pass http://sentry-web:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 90s;
    }
}
NGINX_EOF

    sed -i.bak "s/{DOMAIN}/${domain}/g" nginx-sentry.conf
    log_success "Generated nginx-sentry.conf"
    rm -f nginx-sentry.conf.bak
}

# Display summary
display_summary() {
    local domain=$1
    local retention=$2
    local mail_hostname=$3
    local network=$4

    log_section "Configuration Summary"

    echo "${GREEN}Domain:${NC} https://${domain}"
    echo "${GREEN}Retention:${NC} ${retention} days"
    echo "${GREEN}Mail:${NC} ${mail_hostname}"
    echo "${GREEN}Network:${NC} ${network}"
    echo ""
}

# Display next steps
display_next_steps() {
    log_section "Next Steps"

    echo "${GREEN}1. Run installation:${NC}"
    echo "   cd self-hosted"
    echo "   ./install.sh"
    echo ""

    echo "${GREEN}2. Start services:${NC}"
    echo "   docker compose --env-file .env --env-file .env.custom up -d"
    echo ""

    echo "${GREEN}3. Copy Nginx configuration:${NC}"
    echo "   cp ../nginx-sentry.conf /root/nginx-proxy/conf.d/sentry.conf"
    echo ""

    echo "${GREEN}4. Reload Nginx:${NC}"
    echo "   cd /root/nginx-proxy"
    echo "   docker compose exec nginx nginx -s reload"
    echo ""
}

# Main
main() {
    log_section "Sentry Self-Hosted Setup"

    log_info "Configuration inputs (press Enter for defaults):"
    echo ""

    DOMAIN=$(prompt_input "Domain name" "sentry.example.org")
    validate_domain "$DOMAIN"

    RETENTION=$(prompt_input "Retention days" "150")
    validate_retention "$RETENTION"

    MAIL_HOSTNAME=$(prompt_input "Mail hostname" "example.org")

    NETWORK=$(prompt_input "Docker network name" "gitlab-net")

    echo ""
    display_summary "$DOMAIN" "$RETENTION" "$MAIL_HOSTNAME" "$NETWORK"

    read -p "  ${BLUE}Proceed? (yes/no):${NC} " confirm
    if [[ ! $confirm =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
        log_error "Cancelled"
    fi

    echo ""
    log_section "Setting Up"

    clone_sentry_repo
    copy_config_files
    update_config_yml "$DOMAIN" "$MAIL_HOSTNAME"
    generate_env_custom "$RETENTION" "$MAIL_HOSTNAME"
    generate_docker_compose_override "$NETWORK"
    generate_nginx_config "$DOMAIN"

    echo ""
    log_section "✓ Complete"
    display_next_steps

    log_success "Setup finished! Run: cd self-hosted && ./install.sh"
}

main "$@"
