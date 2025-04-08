#!/bin/bash

# SYSD_USER_DIR=$(pkg-config systemd --variable=systemduserunitdir)
SYSD_USER_DIR="$HOME/.config/systemd"

cat <<"EOF" > $SYSD_USER_DIR/node-red.service
[Unit]
Description=Node-Red Service
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/path/to/your/working/directory
ExecStart=%h/.pixi/bin/pixi run start
Restart=on-failure
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

loginctl enable-linger
systemctl --user daemon-reload
systemctl --user start node-red.service
systemctl --user enable node-red.service
systemctl --user status node-red.service
