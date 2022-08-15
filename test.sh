#!/bin/bash

DIST_BASE="ubuntu"

sudo apt update && sudo apt dist-upgrade -y
sudo apt autoremove -y && sudo apt autoclean -y

apt-get install \
jq \
wget \
curl \
udisks2 \
libglib2.0-bin \
network-manager \
dbus -y

curl -fsSL get.docker.com | sh

wget https://github.com/home-assistant/os-agent/releases/download/1.3.0/os-agent_1.3.0_linux_x86_64.deb

sudo dpkg -i os-agent_1.3.0_linux_x86_64.deb
wget https://github.com/home-assistant/supervised-installer/releases/latest/download/homeassistant-supervised.deb
dpkg -i homeassistant-supervised.deb


docker run hello-world
docker volume create portainer_data
docker run -d -p 8000:8000 -p 9000:9000 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce

apt-get install -y docker-compose

sudo apt autoremove -y && sudo apt autoclean -y

reboot

exit
