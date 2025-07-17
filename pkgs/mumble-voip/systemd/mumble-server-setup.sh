#!/bin/bash
#
# Mumble Server (Murmur) Service Setup Script
# This script sets up the Mumble server service for systemd management
#

set -e

# Configuration
SERVICE_NAME="mumble-server"
SERVICE_USER="mumble"
SERVICE_GROUP="mumble"
SERVICE_HOME="/var/lib/mumble"
CONFIG_DIR="/etc/mumble"
LOG_DIR="/var/log/mumble"

echo "Setting up Mumble server (Murmur) service..."

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
            --comment "Mumble server service user" \
            "$SERVICE_USER"
fi

# Create required directories
echo "Creating directories..."
mkdir -p "$SERVICE_HOME"
mkdir -p "$SERVICE_HOME/data"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

# Set proper ownership and permissions
chown "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR"
chmod 755 "$SERVICE_HOME"
chmod 755 "$SERVICE_HOME/data"
chmod 755 "$LOG_DIR"

# Create basic configuration file if it doesn't exist
CONFIG_FILE="$CONFIG_DIR/murmur.ini"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating basic configuration file at $CONFIG_FILE"
    cat > "$CONFIG_FILE" << 'EOF'
# Murmur configuration file
# For full configuration options, see: https://wiki.mumble.info/wiki/Murmur.ini

# Database configuration
database=/var/lib/mumble/data/murmur.sqlite

# Network configuration
port=64738
host=0.0.0.0

# Server settings
serverpassword=
welcometext="<br />Welcome to this Mumble server running <b>Murmur</b>.<br />Enjoy your stay!<br />"
registername=Mumble Server
registerpassword=
registerurl=https://www.mumble.info/
registerhostname=

# Logging
logfile=/var/log/mumble/murmur.log
loglevel=1

# Security settings
# SSL certificate paths (optional)
#sslCert=/var/lib/mumble/server.crt
#sslKey=/var/lib/mumble/server.key

# Maximum users
users=100

# Bandwidth settings (bits per second)
bandwidth=72000

# Text message length limit
textmessagelength=5000

# Channel limits
channelnestinglimit=10

# Timeout settings
timeout=30
keepalive=20

# Recording settings
allowhtml=true
rememberchannel=true

# Anti-flood settings
messageburst=5
messagelimit=1
EOF
    chown root:root "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
fi

# Create environment file
ENV_FILE="/etc/default/mumble-server"
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating environment file at $ENV_FILE"
    cat > "$ENV_FILE" << 'EOF'
# Mumble Server Environment Variables

# Configuration file path
MURMUR_CONFIG=/etc/mumble/murmur.ini

# Additional options
MURMUR_OPTS=""

# Log level (0=debug, 1=info, 2=warnings, 3=critical)
MURMUR_LOG_LEVEL=1
EOF
    chown root:root "$ENV_FILE"
    chmod 644 "$ENV_FILE"
fi

# Create log rotation configuration
LOGROTATE_FILE="/etc/logrotate.d/mumble-server"
if [ ! -f "$LOGROTATE_FILE" ]; then
    echo "Creating log rotation configuration at $LOGROTATE_FILE"
    cat > "$LOGROTATE_FILE" << 'EOF'
/var/log/mumble/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 mumble mumble
    postrotate
        systemctl reload mumble-server || true
    endscript
}
EOF
    chown root:root "$LOGROTATE_FILE"
    chmod 644 "$LOGROTATE_FILE"
fi

# Generate SuperUser password if not set
SUPW_FILE="$SERVICE_HOME/superuser_password.txt"
if [ ! -f "$SUPW_FILE" ]; then
    echo "Generating SuperUser password..."
    SUPW=$(openssl rand -base64 32)
    echo "SuperUser password: $SUPW" > "$SUPW_FILE"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$SUPW_FILE"
    chmod 600 "$SUPW_FILE"
    echo "SuperUser password saved to: $SUPW_FILE"
fi

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service (but don't start it automatically)
echo "Enabling $SERVICE_NAME service..."
systemctl enable "$SERVICE_NAME"

echo ""
echo "Mumble server (Murmur) service setup completed successfully!"
echo ""
echo "Configuration file: $CONFIG_FILE"
echo "Environment file: $ENV_FILE"
echo "Service home directory: $SERVICE_HOME"
echo "Log directory: $LOG_DIR"
echo "SuperUser password file: $SUPW_FILE"
echo ""
echo "IMPORTANT: Before starting the service, you should:"
echo "1. Review and customize $CONFIG_FILE"
echo "2. Set a server password in the configuration if desired"
echo "3. Consider generating SSL certificates for encrypted connections"
echo ""
echo "To generate SSL certificates (optional):"
echo "  sudo -u $SERVICE_USER openssl req -x509 -newkey rsa:4096 -keyout $SERVICE_HOME/server.key -out $SERVICE_HOME/server.crt -days 365 -nodes"
echo "  Then uncomment and set sslCert and sslKey in $CONFIG_FILE"
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
echo "Default port: 64738 (TCP/UDP)"
echo ""
echo "SuperUser credentials:"
echo "  Username: SuperUser"
echo "  Password: (see $SUPW_FILE)"
echo ""
echo "Please review the configuration before starting the service."
