#!/bin/bash

cp ./systemd/node-red.service ~/.config/systemd/user/node-red.service
loginctl enable-linger
systemctl --user daemon-reload
systemctl --user start node-red.service
systemctl --user enable node-red.service
systemctl --user status node-red.service
