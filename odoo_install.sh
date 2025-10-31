#!/bin/bash
################################################################################
#
# MOVEOPlus Odoo 19 installer
# ---------------------------
# This script provisions an Odoo 19 environment based on the
# https://github.com/phatdangminh/odoo19.git mirror (which embeds the upstream
# Odoo source as a `source/` submodule).
#
# Tested on Ubuntu 22.04/24.04 and Debian 12. Run as root or with sudo.
#
################################################################################

set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This installer must be run with root privileges." >&2
  exit 1
fi

info()  { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn()  { printf '\n\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

# ------------------------------------------------------------------------------
# Configuration (override by exporting env vars before running the script)
# ------------------------------------------------------------------------------
OE_USER="${OE_USER:-odoo}"
OE_GROUP="${OE_GROUP:-$OE_USER}"
OE_HOME="/${OE_USER}"
OE_HOME_EXT="${OE_HOME}/${OE_USER}-19"
ODOO_MIRROR_URL="${ODOO_MIRROR_URL:-https://github.com/phatdangminh/odoo19.git}"
ODOO_MIRROR_BRANCH="${ODOO_MIRROR_BRANCH:-19.0}"
ODOO_SOURCE_DIR="${OE_HOME_EXT}/source"
ODOO_VENV_DIR="${OE_HOME_EXT}/venv"
OE_CONFIG="${OE_CONFIG:-${OE_USER}-server}"
OE_SERVICE_NAME="${OE_SERVICE_NAME:-odoo19}"
OE_PORT="${OE_PORT:-8069}"
LONGPOLLING_PORT="${LONGPOLLING_PORT:-8072}"
INSTALL_WKHTMLTOPDF="${INSTALL_WKHTMLTOPDF:-True}"
INSTALL_POSTGRESQL_SIXTEEN="${INSTALL_POSTGRESQL_SIXTEEN:-True}"
INSTALL_NGINX="${INSTALL_NGINX:-False}"
ENABLE_SSL="${ENABLE_SSL:-False}"
ADMIN_EMAIL="${ADMIN_EMAIL:-odoo@example.com}"
WEBSITE_NAME="${WEBSITE_NAME:-_}"
IS_ENTERPRISE="${IS_ENTERPRISE:-False}"
GENERATE_RANDOM_PASSWORD="${GENERATE_RANDOM_PASSWORD:-True}"
OE_SUPERADMIN="${OE_SUPERADMIN:-admin}"
CUSTOM_ADDONS_DIR="${CUSTOM_ADDONS_DIR:-${OE_HOME_EXT}/custom-addons}"
OE_LOG_DIR="/var/log/${OE_USER}"
OE_CONFIG_PATH="/etc/${OE_CONFIG}.conf"

# ------------------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------------------

system_has_command() {
  command -v "$1" >/dev/null 2>&1
}

ensure_user_exists() {
  if ! id "$OE_USER" >/dev/null 2>&1; then
    info "Creating system user ${OE_USER}"
    adduser --system --quiet --shell=/bin/bash --home="$OE_HOME" --gecos 'Odoo Service' --group "$OE_USER"
  fi

  if ! id -nG "$OE_USER" | grep -qw sudo; then
    info "Adding ${OE_USER} to sudo group"
    adduser "$OE_USER" sudo
  fi
}

generate_superadmin_password() {
  if [[ "${GENERATE_RANDOM_PASSWORD}" == "True" ]]; then
    OE_SUPERADMIN="$(python3 - <<'PY'
import secrets
alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
print("".join(secrets.choice(alphabet) for _ in range(32)))
PY
)"
  fi
}

add_pg_repository_and_install() {
  info "Installing PostgreSQL 16"
  apt-get install -y curl gnupg
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
  echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list
  apt-get update -y
  apt-get install -y postgresql-16

  systemctl enable --now postgresql

  if [[ "${IS_ENTERPRISE}" == "True" ]]; then
    info "Installing pgvector extension for Enterprise AI features"
    apt-get install -y postgresql-16-pgvector
  fi
}

install_postgresql() {
  if [[ "${INSTALL_POSTGRESQL_SIXTEEN}" == "True" ]]; then
    add_pg_repository_and_install
  else
    info "Installing distribution PostgreSQL packages"
    apt-get install -y postgresql
  fi
}

install_wkhtmltopdf() {
  if [[ "${INSTALL_WKHTMLTOPDF}" != "True" ]]; then
    warn "Skipping wkhtmltopdf installation per configuration"
    return 0
  fi

  info "Installing wkhtmltopdf"
  if apt-cache show wkhtmltopdf >/dev/null 2>&1; then
    if apt-get install -y wkhtmltopdf; then
      return 0
    fi
    warn "wkhtmltopdf package install failed via apt, will try manual download."
    return 1
  else
    warn "wkhtmltopdf package not found in repositories; skipping"
    return 1
  fi
}

install_os_dependencies() {
  info "Installing system dependencies"
  apt-get update -y
  apt-get upgrade -y

  apt-get install -y \
    git curl wget build-essential \
    python3 python3-dev python3-pip python3-venv python3-wheel python3-setuptools python3-babel \
    libpq-dev libldap2-dev libsasl2-dev libxml2-dev libxslt1-dev libjpeg-dev zlib1g-dev \
    libfreetype6-dev liblcms2-dev libblas-dev libatlas-base-dev \
    libtiff5-dev libopenjp2-7-dev libwebp-dev libharfbuzz-dev libfribidi-dev \
    libxrender1 libxext6 libfontconfig1 libffi-dev libssl-dev nodejs npm gdebi-core \
    lsb-release

  npm install -g rtlcss
}

install_wkhtmltox_from_github() {
  local arch url tmp_dir tmp_file
  arch="$(getconf LONG_BIT)"
  if [[ "$arch" == "64" ]]; then
    url="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.$(lsb_release -cs)_amd64.deb"
  else
    url="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.$(lsb_release -cs)_i386.deb"
  fi

  tmp_dir="$(mktemp -d)"
  tmp_file="${tmp_dir}/wkhtmltox.deb"
  info "Attempting wkhtmltopdf install from ${url}"
  if wget -qO "$tmp_file" "$url"; then
    if gdebi --non-interactive "$tmp_file"; then
      rm -rf "$tmp_dir"
      return 0
    fi
    if dpkg -i "$tmp_file"; then
      rm -rf "$tmp_dir"
      return 0
    fi
    apt-get install -f -y
    rm -rf "$tmp_dir"
    return 0
  else
    warn "Unable to download wkhtmltopdf from ${url}; continuing without it."
    rm -rf "$tmp_dir"
    return 1
  fi
}

ensure_wkhtmltopdf() {
  if [[ "${INSTALL_WKHTMLTOPDF}" != "True" ]]; then
    return
  fi

  if system_has_command wkhtmltopdf; then
    info "wkhtmltopdf already available"
    return
  fi

  if ! install_wkhtmltopdf; then
    if ! install_wkhtmltox_from_github; then
      warn "wkhtmltopdf installation failed; PDF exports may not work."
    fi
  fi
}

clone_or_update_repo() {
  info "Fetching MOVEOPlus Odoo source mirror"
  sudo -u "$OE_USER" mkdir -p "$OE_HOME_EXT"
  if [[ -d "${OE_HOME_EXT}/.git" ]]; then
    sudo -u "$OE_USER" git -C "$OE_HOME_EXT" fetch --all
    sudo -u "$OE_USER" git -C "$OE_HOME_EXT" checkout "$ODOO_MIRROR_BRANCH"
    sudo -u "$OE_USER" git -C "$OE_HOME_EXT" pull --ff-only origin "$ODOO_MIRROR_BRANCH"
  else
    sudo -u "$OE_USER" git clone --branch "$ODOO_MIRROR_BRANCH" "$ODOO_MIRROR_URL" "$OE_HOME_EXT"
  fi

  sudo -u "$OE_USER" git -C "$OE_HOME_EXT" submodule update --init --recursive
}

prepare_python_venv() {
  info "Provisioning Python virtual environment"
  sudo -u "$OE_USER" python3 -m venv "$ODOO_VENV_DIR"
  sudo -u "$OE_USER" "$ODOO_VENV_DIR/bin/pip" install --upgrade pip wheel setuptools
  sudo -u "$OE_USER" "$ODOO_VENV_DIR/bin/pip" install -r "${ODOO_SOURCE_DIR}/requirements.txt"

  if [[ "${IS_ENTERPRISE}" == "True" ]]; then
    sudo -u "$OE_USER" "$ODOO_VENV_DIR/bin/pip" install psycopg2-binary num2words ebaysdk
  fi
}

setup_log_directory() {
  info "Creating log directory ${OE_LOG_DIR}"
  mkdir -p "$OE_LOG_DIR"
  chown "$OE_USER:$OE_GROUP" "$OE_LOG_DIR"
}

create_config_file() {
  local addons_path="${ODOO_SOURCE_DIR}/odoo/addons,${ODOO_SOURCE_DIR}/addons"
  mkdir -p "$CUSTOM_ADDONS_DIR"
  chown -R "$OE_USER:$OE_GROUP" "$CUSTOM_ADDONS_DIR"
  addons_path="${addons_path},${CUSTOM_ADDONS_DIR}"

  info "Writing configuration to ${OE_CONFIG_PATH}"
  cat > "$OE_CONFIG_PATH" <<EOF
[options]
admin_passwd = ${OE_SUPERADMIN}
db_host = False
db_port = False
db_user = ${OE_USER}
db_password = False
addons_path = ${addons_path}
logfile = ${OE_LOG_DIR}/${OE_CONFIG}.log
xmlrpc_port = ${OE_PORT}
longpolling_port = ${LONGPOLLING_PORT}
proxy_mode = True
EOF

  chown "$OE_USER:$OE_GROUP" "$OE_CONFIG_PATH"
  chmod 640 "$OE_CONFIG_PATH"
}

create_systemd_service() {
  info "Creating systemd service ${OE_SERVICE_NAME}"
  cat > "/etc/systemd/system/${OE_SERVICE_NAME}.service" <<EOF
[Unit]
Description=MOVEOPlus (Odoo 19.0)
Documentation=https://github.com/phatdangminh/odoo19
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
SyslogIdentifier=${OE_SERVICE_NAME}
User=${OE_USER}
Group=${OE_GROUP}
LimitNOFILE=65535
WorkingDirectory=${ODOO_SOURCE_DIR}
ExecStart=${ODOO_VENV_DIR}/bin/python3 ${ODOO_SOURCE_DIR}/odoo-bin -c ${OE_CONFIG_PATH}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${OE_SERVICE_NAME}"
}

setup_postgres_user() {
  info "Ensuring PostgreSQL role ${OE_USER}"
  sudo -u postgres createuser -s "$OE_USER" 2>/dev/null || true
}

install_nginx_stack() {
  if [[ "${INSTALL_NGINX}" != "True" ]]; then
    warn "Skipping Nginx installation per configuration"
    return
  fi

  if [[ "${WEBSITE_NAME}" == "_" ]]; then
    error "WEBSITE_NAME must be set when INSTALL_NGINX=True"
    exit 1
  fi

  info "Installing and configuring Nginx reverse proxy"
  apt-get install -y nginx
  cat > "/etc/nginx/sites-available/${WEBSITE_NAME}" <<EOF
server {
  listen 80;
  server_name ${WEBSITE_NAME};

  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Client-IP \$remote_addr;

  access_log /var/log/nginx/${OE_USER}-access.log;
  error_log  /var/log/nginx/${OE_USER}-error.log;

  proxy_read_timeout 900s;
  proxy_connect_timeout 900s;
  proxy_send_timeout 900s;
  proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

  location / {
    proxy_pass http://127.0.0.1:${OE_PORT};
    proxy_redirect off;
  }

  location /longpolling {
    proxy_pass http://127.0.0.1:${LONGPOLLING_PORT};
  }

  location ~* \\.(js|css|png|jpg|jpeg|gif|ico)$ {
    proxy_pass http://127.0.0.1:${OE_PORT};
    expires 2d;
    add_header Cache-Control "public, no-transform";
  }

  location ~ /[a-zA-Z0-9_-]*/static/ {
    proxy_cache_valid 200 302 60m;
    proxy_cache_valid 404      1m;
    proxy_buffering    on;
    expires 864000;
    proxy_pass http://127.0.0.1:${OE_PORT};
  }
}
EOF

  ln -sf "/etc/nginx/sites-available/${WEBSITE_NAME}" "/etc/nginx/sites-enabled/${WEBSITE_NAME}"
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx
}

enable_ssl_if_requested() {
  if [[ "${INSTALL_NGINX}" != "True" || "${ENABLE_SSL}" != "True" ]]; then
    return
  fi

  if [[ "${ADMIN_EMAIL}" == "odoo@example.com" ]]; then
    warn "Skipping SSL issuance: ADMIN_EMAIL still set to default placeholder."
    return
  fi

  info "Installing Certbot for SSL certificate provisioning"
  apt-get install -y snapd python3-certbot-nginx
  snap install core && snap refresh core
  snap install --classic certbot
  ln -sf /snap/bin/certbot /usr/bin/certbot

  certbot --nginx -d "${WEBSITE_NAME}" --non-interactive --agree-tos --email "${ADMIN_EMAIL}" --redirect
  systemctl reload nginx
}

summary() {
  cat <<EOF
-----------------------------------------------------------
Odoo installation completed
-----------------------------------------------------------
Service name:   ${OE_SERVICE_NAME}
Config file:    ${OE_CONFIG_PATH}
Log directory:  ${OE_LOG_DIR}
Code location:  ${OE_HOME_EXT}
Odoo source:    ${ODOO_SOURCE_DIR}
Python venv:    ${ODOO_VENV_DIR}
Addons path:    ${CUSTOM_ADDONS_DIR}
Default port:   ${OE_PORT}
Longpoll port:  ${LONGPOLLING_PORT}
DB superuser:   ${OE_USER}
Admin password: ${OE_SUPERADMIN}
Start service:  systemctl start ${OE_SERVICE_NAME}
Stop service:   systemctl stop ${OE_SERVICE_NAME}
Restart:        systemctl restart ${OE_SERVICE_NAME}
Status:         systemctl status ${OE_SERVICE_NAME}
-----------------------------------------------------------
EOF
}

# ------------------------------------------------------------------------------
# Execution flow
# ------------------------------------------------------------------------------
install_os_dependencies
install_postgresql
setup_postgres_user
ensure_user_exists
ensure_wkhtmltopdf
clone_or_update_repo
prepare_python_venv
setup_log_directory
generate_superadmin_password
create_config_file
create_systemd_service
install_nginx_stack
enable_ssl_if_requested
summary
