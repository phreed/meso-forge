#!/bin/bash
#
# MediaMTX Service Setup Script
# This script sets up the MediaMTX service for systemd management
#

set -e

# Configuration
SERVICE_NAME="mediamtx"
SERVICE_USER="mediamtx"
SERVICE_GROUP="mediamtx"
SERVICE_HOME="/var/lib/mediamtx"
CONFIG_DIR="/etc/mediamtx"
LOG_DIR="/var/log/mediamtx"

echo "Setting up MediaMTX service..."

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
            --comment "MediaMTX service user" \
            "$SERVICE_USER"
fi

# Create required directories
echo "Creating directories..."
mkdir -p "$SERVICE_HOME"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

# Set proper ownership and permissions
chown "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR"
chmod 755 "$SERVICE_HOME"
chmod 755 "$LOG_DIR"

# Create basic configuration file if it doesn't exist
CONFIG_FILE="$CONFIG_DIR/mediamtx.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating basic configuration file at $CONFIG_FILE"
    cat > "$CONFIG_FILE" << 'EOF'
# MediaMTX configuration file
# For full configuration options, see: https://github.com/bluenviron/mediamtx

# General settings
logLevel: info
logDestinations: [stdout]

# API settings
api: yes
apiAddress: 127.0.0.1:9997

# Metrics settings
metrics: yes
metricsAddress: 127.0.0.1:9998

# RTSP settings
rtspAddress: :8554
protocols: [udp, multicast, tcp]

# RTMP settings
rtmpAddress: :1935

# HLS settings
hlsAddress: :8888
hlsAllowOrigin: "*"

# WebRTC settings
webrtcAddress: :8889
webrtcAllowOrigin: "*"

# Paths (streams configuration)
paths:
  all:
    # Allow publishing and reading from any client
    publishUser: ""
    publishPass: ""
    readUser: ""
    readPass: ""
EOF
    chown root:root "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
fi

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service (but don't start it automatically)
echo "Enabling $SERVICE_NAME service..."
systemctl enable "$SERVICE_NAME"

echo ""
echo "MediaMTX service setup completed successfully!"
echo ""
echo "Configuration file: $CONFIG_FILE"
echo "Service home directory: $SERVICE_HOME"
echo "Log directory: $LOG_DIR"
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
echo "  RTSP: 8554"
echo "  RTMP: 1935"
echo "  HLS: 8888"
echo "  WebRTC: 8889"
echo "  API: 9997"
echo "  Metrics: 9998"
echo ""
echo "Please review and customize $CONFIG_FILE before starting the service."
