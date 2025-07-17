#!/bin/bash
#
# Node-RED Service Setup Script
# This script sets up the Node-RED service for systemd management
#

set -e

# Configuration
SERVICE_NAME="node-red"
SERVICE_USER="nodered"
SERVICE_GROUP="nodered"
SERVICE_HOME="/var/lib/node-red"
CONFIG_DIR="/etc/node-red"
LOG_DIR="/var/log/node-red"

echo "Setting up Node-RED service..."

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
            --comment "Node-RED service user" \
            "$SERVICE_USER"
fi

# Create required directories
echo "Creating directories..."
mkdir -p "$SERVICE_HOME"
mkdir -p "$SERVICE_HOME/flows"
mkdir -p "$SERVICE_HOME/lib"
mkdir -p "$SERVICE_HOME/lib/flows"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

# Set proper ownership and permissions
chown "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR"
chmod 755 "$SERVICE_HOME"
chmod 755 "$SERVICE_HOME/flows"
chmod 755 "$SERVICE_HOME/lib"
chmod 755 "$LOG_DIR"

# Create basic settings file if it doesn't exist
SETTINGS_FILE="$SERVICE_HOME/settings.js"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Creating basic settings file at $SETTINGS_FILE"
    cat > "$SETTINGS_FILE" << 'EOF'
/**
 * Node-RED Settings File
 */
module.exports = {
    // The tcp port that the Node-RED web server is listening on
    uiPort: process.env.PORT || 1880,

    // The maximum length, in characters, of messages sent to the debug sidebar
    debugMaxLength: 1000,

    // The file containing the flows
    flowFile: 'flows.json',

    // The file containing the flow credentials
    credentialsFile: 'flows_cred.json',

    // By default, the Node-RED UI accepts connections on all IPv4 interfaces
    // To listen on all IPv6 addresses, set uiHost to "::",
    // The following property can be used to listen on a specific interface
    uiHost: "0.0.0.0",

    // Retry time in milliseconds for MQTT connections
    mqttReconnectTime: 15000,

    // Retry time in milliseconds for Serial port connections
    serialReconnectTime: 15000,

    // Retry time in milliseconds for TCP socket connections
    socketReconnectTime: 10000,

    // Timeout in milliseconds for TCP server socket connections
    socketTimeout: 120000,

    // The maximum length, in characters, of any message sent to the debug sidebar
    debugMaxLength: 1000,

    // The maximum number of messages nodes will buffer internally as part of their
    // operation. This applies across a range of nodes that operate on a flow of
    // messages.
    nodeMessageBufferMaxLength: 0,

    // To disable the runtime version check
    runtimeState: {
        enabled: false,
        ui: false,
    },

    // Configure the logging output
    logging: {
        // Console logging
        console: {
            level: "info",
            metrics: false,
            audit: false
        },
        // File logging
        file: {
            level: "info",
            filename: "/var/log/node-red/node-red.log",
            maxFiles: 5,
            maxSize: "10MB"
        }
    },

    // The file containing the context storage configuration
    contextStorage: {
        default: {
            module: "memory"
        },
        file: {
            module: "localfilesystem"
        }
    },

    // The following property can be used to order the categories in the editor
    // palette. If a node's category is not in the list, the category will get
    // added to the end of the palette.
    paletteCategories: ['subflows', 'common', 'function', 'network', 'sequence', 'parser', 'storage'],

    // Configure the directory for installing nodes
    userDir: '/var/lib/node-red/',

    // Node-RED scans the `nodes` directory in the userDir to find local node files
    nodesDir: '/var/lib/node-red/nodes/',

    // By default, credentials are encrypted in storage using a generated key
    // To specify your own secret, set this property
    credentialSecret: false,

    // By default, all user data is stored in the Node-RED install directory
    // To use a different location, the following property can be used
    userDir: '/var/lib/node-red/',

    // Node-RED will, by default, honor the 'http_proxy' and 'https_proxy'
    // environment variables. If you need to use a proxy please set this property
    httpProxy: process.env.HTTP_PROXY || process.env.http_proxy,
    httpsProxy: process.env.HTTPS_PROXY || process.env.https_proxy,

    // The following property can be used to disable the editor
    disableEditor: false,

    // The following property can be used to configure cross-origin resource sharing
    // in the HTTP nodes.
    httpNodeCors: {
        origin: "*",
        methods: "GET,PUT,POST,DELETE"
    },

    // The following property can be used to configure cross-origin resource sharing
    // for the editor and admin API.
    httpAdminCors: {
        origin: "*",
        methods: "GET,PUT,POST,DELETE"
    },

    // Anything in this hash is globally available to all functions.
    functionGlobalContext: {
        // os:require('os'),
    },

    // The following property can be used to set predefined values in Global Context
    functionGlobalContext: {

    },

    // Context Storage
    contextStorage: {
        default: "memoryOnly",
        memoryOnly: { module: 'memory' },
        file: { module: 'localfilesystem' }
    },

    // Export HTTP Static path
    httpStatic: '/var/lib/node-red/public/',

    // Securing Node-RED
    // adminAuth: {
    //     type: "credentials",
    //     users: [{
    //         username: "admin",
    //         password: "$2a$08$zZWtXTja0fB1pzD4sHCMyOCMYz2Z6dNbM6tl8sJogENOMcxWV9DN.",
    //         permissions: "*"
    //     }]
    // },

    // Customising the editor
    editorTheme: {
        projects: {
            enabled: false
        }
    }
}
EOF
    chown "$SERVICE_USER:$SERVICE_GROUP" "$SETTINGS_FILE"
    chmod 644 "$SETTINGS_FILE"
fi

# Create package.json if it doesn't exist
PACKAGE_FILE="$SERVICE_HOME/package.json"
if [ ! -f "$PACKAGE_FILE" ]; then
    echo "Creating package.json at $PACKAGE_FILE"
    cat > "$PACKAGE_FILE" << 'EOF'
{
    "name": "node-red-project",
    "description": "Node-RED project",
    "version": "0.0.1",
    "private": true,
    "dependencies": {
    }
}
EOF
    chown "$SERVICE_USER:$SERVICE_GROUP" "$PACKAGE_FILE"
    chmod 644 "$PACKAGE_FILE"
fi

# Create environment file
ENV_FILE="/etc/default/node-red"
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating environment file at $ENV_FILE"
    cat > "$ENV_FILE" << 'EOF'
# Node-RED Environment Variables

# Node.js environment
NODE_ENV=production

# Node-RED options
NODE_RED_OPTIONS="-v"

# Node.js module path
NODE_PATH=/opt/conda/lib/node_modules

# Port configuration
PORT=1880

# User directory
NODE_RED_USER_DIR=/var/lib/node-red

# Logging level
NODE_RED_LOG_LEVEL=info

# Memory settings
NODE_OPTIONS="--max-old-space-size=512"
EOF
    chown root:root "$ENV_FILE"
    chmod 644 "$ENV_FILE"
fi

# Create log rotation configuration
LOGROTATE_FILE="/etc/logrotate.d/node-red"
if [ ! -f "$LOGROTATE_FILE" ]; then
    echo "Creating log rotation configuration at $LOGROTATE_FILE"
    cat > "$LOGROTATE_FILE" << 'EOF'
/var/log/node-red/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 nodered nodered
    postrotate
        systemctl reload node-red || true
    endscript
}
EOF
    chown root:root "$LOGROTATE_FILE"
    chmod 644 "$LOGROTATE_FILE"
fi

# Create public directory for static files
PUBLIC_DIR="$SERVICE_HOME/public"
if [ ! -d "$PUBLIC_DIR" ]; then
    mkdir -p "$PUBLIC_DIR"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$PUBLIC_DIR"
    chmod 755 "$PUBLIC_DIR"
fi

# Create nodes directory for custom nodes
NODES_DIR="$SERVICE_HOME/nodes"
if [ ! -d "$NODES_DIR" ]; then
    mkdir -p "$NODES_DIR"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$NODES_DIR"
    chmod 755 "$NODES_DIR"
fi

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service (but don't start it automatically)
echo "Enabling $SERVICE_NAME service..."
systemctl enable "$SERVICE_NAME"

echo ""
echo "Node-RED service setup completed successfully!"
echo ""
echo "Settings file: $SETTINGS_FILE"
echo "Environment file: $ENV_FILE"
echo "Service home directory: $SERVICE_HOME"
echo "Log directory: $LOG_DIR"
echo "Public directory: $PUBLIC_DIR"
echo "Custom nodes directory: $NODES_DIR"
echo ""
echo "IMPORTANT: Before starting the service, you should:"
echo "1. Review and customize $SETTINGS_FILE"
echo "2. Consider enabling authentication (uncomment adminAuth section)"
echo "3. Install additional Node-RED nodes if needed"
echo ""
echo "To install additional nodes:"
echo "  sudo -u $SERVICE_USER npm install --prefix $SERVICE_HOME <node-name>"
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
echo "Default access:"
echo "  Web Interface: http://localhost:1880"
echo "  API Endpoint: http://localhost:1880/api"
echo ""
echo "Security Note: Authentication is disabled by default."
echo "Please enable authentication in $SETTINGS_FILE before exposing to network."
