#!/bin/bash
#
# FreeTAKServer Service Setup Script
# This script sets up the FreeTAKServer service for systemd management
#

set -e

# Configuration
SERVICE_NAME="freetakserver"
SERVICE_USER="freetakserver"
SERVICE_GROUP="freetakserver"
SERVICE_HOME="/var/lib/freetakserver"
CONFIG_DIR="/etc/freetakserver"
LOG_DIR="/var/log/freetakserver"

echo "Setting up FreeTAKServer service..."

# Create system user and group if they don't exist
if ! getent group "$SERVICE_GROUP" > /dev/null 2>&1; then
    echo "Creating group: $SERVICE_GROUP"
    groupadd --system "$SERVICE_GROUP"
fi

if ! getent passwd "$SERVICE_USER" > /dev/null 2>&1; then
    echo "Creating user: $SERVICE_USER"
    useradd --system --gid "$SERVICE_GROUP" \
            --home-dir "$SERVICE_HOME" \
            --shell /bin/false \
            --comment "FreeTAKServer service user" \
            "$SERVICE_USER"
fi

# Create required directories
echo "Creating directories..."
mkdir -p "$SERVICE_HOME"
mkdir -p "$SERVICE_HOME/certs"
mkdir -p "$SERVICE_HOME/data"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

# Set proper ownership and permissions
chown "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR"
chmod 755 "$SERVICE_HOME"
chmod 700 "$SERVICE_HOME/certs"
chmod 755 "$SERVICE_HOME/data"
chmod 755 "$LOG_DIR"

# Create basic configuration file if it doesn't exist
CONFIG_FILE="$CONFIG_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating basic configuration file at $CONFIG_FILE"
    cat > "$CONFIG_FILE" << 'EOF'
# FreeTAKServer Configuration
# For full configuration options, see: https://freetakteam.github.io/FreeTAKServer-User-Docs/

system:
  # Database configuration
  database:
    type: sqlite
    path: /var/lib/freetakserver/data/fts.db

  # Logging configuration
  logging:
    level: INFO
    file: /var/log/freetakserver/fts.log

  # Certificate configuration
  certificates:
    cert_path: /var/lib/freetakserver/certs
    ca_cert: ca.crt
    server_cert: server.crt
    server_key: server.key

network:
  # TCP API port (CoT)
  tcp_port: 8087

  # SSL API port (CoT SSL)
  ssl_port: 8089

  # HTTP API port
  http_port: 8080

  # HTTPS API port
  https_port: 8443

  # Federation port
  federation_port: 9000

security:
  # Enable SSL/TLS
  ssl_enabled: true

  # Authentication settings
  authentication:
    enabled: false
    method: password

ui:
  # Web UI settings
  enabled: true
  port: 5000
  host: 0.0.0.0
EOF
    chown root:root "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
fi

# Create environment file
ENV_FILE="/etc/default/freetakserver"
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating environment file at $ENV_FILE"
    cat > "$ENV_FILE" << 'EOF'
# FreeTAKServer Environment Variables

# Set to false after first successful start
FTS_FIRST_START=true

# Python optimization
PYTHONUNBUFFERED=1
PYTHONOPTIMIZE=1

# Configuration file path
FTS_CONFIG_FILE=/etc/freetakserver/config.yaml

# Data directory
FTS_DATA_DIR=/var/lib/freetakserver/data

# Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
FTS_LOG_LEVEL=INFO
EOF
    chown root:root "$ENV_FILE"
    chmod 644 "$ENV_FILE"
fi

# Create log rotation configuration
LOGROTATE_FILE="/etc/logrotate.d/freetakserver"
if [ ! -f "$LOGROTATE_FILE" ]; then
    echo "Creating log rotation configuration at $LOGROTATE_FILE"
    cat > "$LOGROTATE_FILE" << 'EOF'
/var/log/freetakserver/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 freetakserver freetakserver
    postrotate
        systemctl reload freetakserver || true
    endscript
}
EOF
    chown root:root "$LOGROTATE_FILE"
    chmod 644 "$LOGROTATE_FILE"
fi

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service (but don't start it automatically)
echo "Enabling $SERVICE_NAME service..."
systemctl enable "$SERVICE_NAME"

echo ""
echo "FreeTAKServer service setup completed successfully!"
echo ""
echo "Configuration file: $CONFIG_FILE"
echo "Environment file: $ENV_FILE"
echo "Service home directory: $SERVICE_HOME"
echo "Log directory: $LOG_DIR"
echo ""
echo "IMPORTANT: Before starting the service, you should:"
echo "1. Review and customize $CONFIG_FILE"
echo "2. Generate SSL certificates in $SERVICE_HOME/certs/"
echo "3. Set FTS_FIRST_START=false in $ENV_FILE after first run"
echo ""
echo "To generate self-signed certificates:"
echo "  sudo -u $SERVICE_USER openssl req -x509 -newkey rsa:4096 -keyout $SERVICE_HOME/certs/server.key -out $SERVICE_HOME/certs/server.crt -days 365 -nodes"
echo ""
echo "To start the service:"
echo "  sudo systemctl start $SERVICE_NAME"
echo ""
echo "To check service status:"
echo "  sudo systemctl status $SERVICE_NAME"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo "Default ports:"
echo "  TCP CoT: 8087"
echo "  SSL CoT: 8089"
echo "  HTTP API: 8080"
echo "  HTTPS API: 8443"
echo "  Federation: 9000"
echo "  Web UI: 5000"
echo ""
echo "Please review the configuration and generate certificates before starting the service."
