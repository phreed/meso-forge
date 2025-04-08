#!/bin/bash

# SYSD_USER_DIR=$(pkg-config systemd --variable=systemduserunitdir)
SYSD_USER_DIR="$HOME/.config/systemd"

cat <<"EOF" > $SYSD_USER_DIR/fts.service
Description=FreeTAKServer service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
StandardOutput=append:$SYSD_USER_LOG/fts/fts-stdout.log
StandardError=append:$SYSD_USER_LOG/fts-stderr.log
Environment="FTS_FIRST_START=false"
ExecStart=fts-service {{ fts_venv }}/bin/python3 -m FreeTAKServer.controllers.services.FTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

loginctl enable-linger
systemctl --user daemon-reload
systemctl --user start fts.service
systemctl --user enable fts.service
systemctl --user status fts.service
