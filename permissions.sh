#!/bin/bash
cd /home/tomas

sudo chown -R root.docker docker
sudo chmod -R 777 docker
sudo chown -R root.docker backup
sudo chmod -R 777 backup

echo 'Los permisos fueron actualizados.'