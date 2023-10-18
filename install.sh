#!/bin/bash
sudo apt install nano -y
sudo apt install tree -y
sudo apt install htop -y
sudo apt install net-tools -y
sudo apt-get install unzip -y

#Instalación de Docker:
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

sudo usermod -aG docker $USER

newgrp docker

#Instalación de Docker Compose:
sudo apt install docker-compose

echo "Loggin out to complete the process"

sleep 30

exit
