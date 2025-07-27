#!/bin/bash
# CREATED: 28MAY2025
# UPDATED: 13JUN2025
# OWNER: XCS

sudo apt-get remove --purge thunderbird libreoffice-* gimp totem* -y
sudo apt-get remove --purge chromium* vlc* transmission* rhythmbox* -y
sudo apt-get autoremove --purge -y
sudo apt-get clean
sudo journalctl --vacuum-time=5d
podman image prune -a -f