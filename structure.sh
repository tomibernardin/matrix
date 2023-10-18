#!/bin/bash
cd /home/tomas
mkdir docker 
#mkdir backup backup/duplicati
cd docker
#mkdir homeassistant homeassistant/config
#mkdir mariadb mariadb/config
#mkdir node-red node-red/config
#mkdir duplicati duplicati/config
mkdir homer homer/config
mkdir filebrowser filebrowser/config filebrowser/database
mkdir nginxpm nginxpm/config nginxpm/etc
mkdir pihole pihole/config pihole/dnsmasq
mkdir plex plex/config plex/temp plex/media plex/media/anime plex/media/movies plex/media/series plex/media/homevideos
mkdir transmission transmission/config transmission/watch transmission/downloads transmission/downloads/complete transmission/downloads/incomplete
mkdir sonarr sonarr/config radarr radarr/config
mkdir jackett jackett/config
echo 'Los directorios fueron actualizados.'
cd /home/tomas