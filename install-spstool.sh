#!/bin/bash
# install-spstool.sh
# prepared by dicky@bitzen19.com
# last update: November 13th, 2022

# predefined console font color/style
RED='\033[1;41;37m'
BLU='\033[1;94m'
YLW='\033[1;33m'
STD='\033[0m'
BLD='\033[1;97m'

CHECK_USER="orangt"

if [ "$USER" != "$CHECK_USER" ]; then
  echo ""
  echo -e "Please run this installation script as user: ${BLD}${CHECK_USER}${STD}"
  echo ""
  exit
fi

# check internet connection
if ! ping -q -c 1 -W 1 google.com > /dev/null; then
  echo ""
  echo -e "${BLD}No internet connection detected.${STD}"
  echo -e "This installation script requires internet connection to download required libraries/repositories."
  echo -e "Please set proper network and internet connection on this server before proceed."
  echo ""
  exit
fi

# check whether user is root or superuser
if [ $(id -u) -eq 0 ]; then
  echo ""
  echo -e "Please run this script as ${BLD}sudoer user${STD}."
  echo -e "Running this script as root or superuser is prohibited."
  echo -e "Please googling: ${BLD}create sudo user ubuntu linuxize${STD}"
  echo ""
  exit
fi

# check whether user is sudoer or not
NOT_SUDOER=$(sudo -l -U $USER 2>&1 | egrep -c -i "not allowed to run sudo|unknown user")
if [ "$NOT_SUDOER" -ne 0 ]; then
  echo ""
  echo -e "${BLD}user ${USER} is not a sudoer user.${STD}"
  echo -e "Please run this script as sudoer."
  echo -e "Please googling: ${BLD}create sudo user ubuntu linuxize${STD}"
  echo ""
  exit
fi

# Starting specific installation script

if [ ! -d "/home/${CHECK_USER}" ]; then
  echo ""
  echo -e "can not find ${CHECK_USER} home folder: ${BLD}/home/${CHECK_USER}${STD}"
  echo -e "spstool installation is aborted."
  echo ""
  exit
fi

if [ ! -f "/home/${CHECK_USER}/server.env" ]; then
  echo ""
  echo -e "Please define environment for this server. ${BLD}Use all lower case and no spaces${STD}."
  echo -e "Examples: ${BLD}dev${STD}, ${BLD}qa${STD}, ${BLD}production${STD}, ${BLD}prod${STD}, etc."
  echo ""
  echo -e "${BLD}Server environment${STD}:"
  read SERVER_ENVIRONMENT

  echo ""
  echo -e "${YLW}touch /home/${CHECK_USER}/server.env${STD}"
  touch "/home/${CHECK_USER}/server.env"

  echo ""
  echo -e "${YLW}echo SERVER_ENVIRONMENT=${SERVER_ENVIRONMENT} >> /home/${CHECK_USER}/server.env${STD}"
  echo "SERVER_ENVIRONMENT=${SERVER_ENVIRONMENT}" >> "/home/${CHECK_USER}/server.env"
  echo "" >> "/home/${CHECK_USER}/server.env"
fi

echo ""
echo "Downloading required scripts to proper locations..."

if [ ! -f /etc/profile.d/spstool.sh ]; then
  echo -e "${YLW}sudo curl -sS https://cdn.bitzen19.com/script/spstool/etc-profile.d-spstool.sh -o /etc/profile.d/spstool.sh${STD}"
  sudo curl -sS https://cdn.bitzen19.com/script/spstool/etc-profile.d-spstool.sh -o /etc/profile.d/spstool.sh
fi

if [ ! -f /usr/local/bin/spstool ]; then
  echo ""
  echo -e "${YLW}sudo curl -sS https://cdn.bitzen19.com/script/spstool/spstool -o /usr/local/bin/spstool${STD}"
  sudo curl -sS https://cdn.bitzen19.com/script/spstool/spstool -o /usr/local/bin/spstool
  echo ""
  echo "Make /usr/local/bin/spstool executable:"
  echo -e "${YLW}sudo chmod +x /usr/local/bin/spstool${STD}"
  sudo chmod +x /usr/local/bin/spstool
fi

sudo rm -f "/home/${CHECK_USER}/spstool.sh"
echo ""
echo -e "${YLW}curl -sS https://cdn.bitzen19.com/script/spstool/spstool.sh -o /home/${CHECK_USER}/spstool.sh${STD}"
curl -sS https://cdn.bitzen19.com/script/spstool/spstool.sh -o "/home/${CHECK_USER}/spstool.sh"

echo ""
echo -e "${YLW}spstool sysinfo${STD}"
echo ""
spstool sysinfo
