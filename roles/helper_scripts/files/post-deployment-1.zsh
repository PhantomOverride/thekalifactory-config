#!/usr/bin/env zsh
set -euo pipefail

# Cleanup
## Device IDs
sudo rm -f /etc/machine-id  
sudo rm -f /var/lib/dbus/machine-id
sudo systemd-machine-id-setup

## Seeds
sudo rm /var/lib/systemd/random-seed

## Logs and history
sudo rm -rf /var/log/*
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
rm -f ~/.bash_history

## Keys
sudo rm -f /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server

echo "Cleanup done! Next step is to reboot. Afterwards please run next script."
read "REPLY?Press Enter to continue..."

reboot
