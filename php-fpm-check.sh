#!/bin/bash
# php-fpm-check.sh
# prepared by dicky.dwijanto@myspsolution.com
# last update: May 19th, 2025

THRESHOLD=84

RED='\033[1;41;37m'
BLU='\033[1;94m'
YLW='\033[1;33m'
STD='\033[0m'
BLD='\033[1;97m'

if ! command -v php &> /dev/null; then
  echo ""
  echo -e "${RED}php is not installed on this system. Exit.${STD}"
  echo ""
  exit 1
fi

PHP_FPM_SERVICE=$(systemctl list-unit-files --type=service --no-legend | awk '{print $1}' | grep -E '^php.*fpm\.service$' | head -n 1)

if [ -n "${PHP_FPM_SERVICE}" ]; then
  # Strip off the .service suffix
  PHP_FPM_SERVICE="${PHP_FPM_SERVICE%.service}"
else
  echo ""
  echo -e "${RED}No php-fpm service detected. Exit.${STD}"
  echo ""
  exit 1
fi

if ! systemctl is-active --quiet "${PHP_FPM_SERVICE}"; then
  echo ""
  echo -e "${RED}${PHP_FPM_SERVICE} service is not active. Exit.${STD}"
  echo ""
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASH_NAME="${DIR}/php-fpm-advisor.sh"

if [ ! -f ${BASH_NAME} ]; then
  echo ""
  echo -e "Required bash file doesn't exists: ${BLD}${BASH_NAME}${STD}. Exit"
  echo ""
  exit 1
fi

IS_SA=0
IS_SUDOER=0

# Check superadmin (EUID=0)
if [ $(id -u) -eq 0 ]; then
  IS_SA=1
fi

# Check sudoer
NOT_SUDOER=$(sudo -l -U $USER 2>&1 | egrep -c -i "not allowed to run sudo|unknown user")
if [ "${NOT_SUDOER}" -eq 0 ]; then
  IS_SUDOER=1
fi

if [ "${IS_SA}" -eq 0 ] && [ "${IS_SUDOER}" -eq 0 ]; then
  echo ""
  echo -e "Please run this script as ${BLD}sudoer or superadmin${STD}"
  echo -e "It's required to stop (temporarily) and restart ${PHP_FPM_SERVICE} service."
  echo ""
  exit 1
fi

# Get current hour (24h format)
HOUR=$(date +%H)
if [ "${HOUR}" -eq 1 ]; then
  echo ""
  echo -e "${BLD}It's 1 AM. No process to avoid conflicting with other background job.${STD}"
  echo ""
  exit 0
fi

if [ "${HOUR}" -eq 2 ]; then
  echo ""
  echo -e "${BLD}It's 2 AM. No process to avoid conflicting with other background job.${STD}"
  echo ""
  exit 0
fi

if [ "${HOUR}" -eq 3 ]; then
  echo ""
  echo -e "${BLD}It's 3 AM. No process to avoid conflicting with other background job.${STD}"
  echo ""
  exit 0
fi

# Calculate CPU usage percentage:
CPU_USAGE_PERCENTAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')
CPU_USAGE_PERCENTAGE_INT=$(echo ${CPU_USAGE_PERCENTAGE} | awk '{print int($1+0.55)}')
# add 1 to increase sensitivity
CPU_USAGE_PERCENTAGE_INT=$((CPU_USAGE_PERCENTAGE_INT + 1))

# Calculate memory usage percentage:
RAM_TOTAL_MB=$(free -m | grep '^Mem:' | awk '{print $2}')
RAM_TOTAL_USABLE_GB=$(awk "BEGIN {printf \"%.1f\",${RAM_TOTAL_MB}/1024}")

RAM_TOTAL_GB=$(echo ${RAM_TOTAL_USABLE_GB} | awk '{print int($1+0.55)}')

RAM_USED_MB=$(free -m | grep '^Mem:' | awk '{print $3}')
RAM_USED_GB=$(awk "BEGIN {printf \"%.1f\",${RAM_USED_MB}/1024}")

RAM_AVAILABLE_MB=$(free -m | grep '^Mem:' | awk '{print $7}')
RAM_AVAILABLE_GB=$(awk "BEGIN {printf \"%.1f\",${RAM_AVAILABLE_MB}/1024}")

RAM_USAGE_PERCENTAGE=$(echo "scale=2; $RAM_USED_MB / $RAM_TOTAL_MB * 100" | bc)
RAM_USAGE_PERCENTAGE_INT=$(echo ${RAM_USAGE_PERCENTAGE} | awk '{print int($1+0.45)}')
# add 1 to increase sensitivity
RAM_USAGE_PERCENTAGE_INT=$((RAM_USAGE_PERCENTAGE_INT + 1))

echo ""
if [ "${CPU_USAGE_PERCENTAGE_INT}" -gt "${THRESHOLD}" ]; then
  echo -e "CPU    usage: ${RED} ${CPU_USAGE_PERCENTAGE_INT}% ${STD}"
else
  echo -e "CPU    usage: ${BLD}${CPU_USAGE_PERCENTAGE_INT}%${STD}"
fi

if [ "${RAM_USAGE_PERCENTAGE_INT}" -gt "${THRESHOLD}" ]; then
  echo -e "Memory usage: ${RED} ${RAM_USAGE_PERCENTAGE_INT}% ${STD}"
else
  echo -e "Memory usage: ${BLD}${RAM_USAGE_PERCENTAGE_INT}%${STD}"
fi

# Run if either above threshold
if [ "${CPU_USAGE_PERCENTAGE_INT}" -gt "${THRESHOLD}" ] || [ "${RAM_USAGE_PERCENTAGE_INT}" -gt "${THRESHOLD}" ]; then
  echo -e "CPU and/or memory usage percentage ${RED} exceeds threshold: ${THRESHOLD}% ${STD}"
  echo -e "running: ${BLD}bash ${BASH_NAME} y${STD}"
  SUPERVISOR_SERVICE=$(systemctl list-units --full -all | grep -E 'supervisor|supervisord' | awk '{print $1}' | head -n 1)

  if [ -n "${SUPERVISOR_SERVICE}" ]; then
    # Strip off the .service suffix
    SUPERVISOR_SERVICE="${SUPERVISOR_SERVICE%.service}"
    echo ""
    echo -e "${BLD}Stopping ${SUPERVISOR_SERVICE} service ...${STD}"
    if [ "${IS_SA}" -eq 1 ]; then
      systemctl stop "${SUPERVISOR_SERVICE}"
    else
      sudo systemctl stop "${SUPERVISOR_SERVICE}"
    fi
  fi

  bash "${BASH_NAME}" y

  if [ -n "${SUPERVISOR_SERVICE}" ]; then
    echo -e "${BLD}Restarting ${SUPERVISOR_SERVICE} service ...${STD}"
    if [ "${IS_SA}" -eq 1 ]; then
      systemctl start "${SUPERVISOR_SERVICE}"
    else
      sudo systemctl start "${SUPERVISOR_SERVICE}"
    fi
  fi

  THE_DATETIME=$(date "+%Y-%m-%d %H:%M:%S")
  if [ "${IS_SA}" -eq 1 ]; then
    rm -f /tmp/last-php-fpm-check-restart.txt
    echo "${THE_DATETIME}" > /tmp/last-php-fpm-check-restart.txt
  else
    sudo rm -f /tmp/last-php-fpm-check-restart.txt
    echo "${THE_DATETIME}" > /tmp/last-php-fpm-check-restart.txt
  fi

  if [ -n "${SUPERVISOR_SERVICE}" ]; then
    echo ""
    # Check if SUPERVISOR_SERVICE is running
    if ! systemctl is-active --quiet "${SUPERVISOR_SERVICE}"; then
      echo -e "${RED}ERROR: ${SUPERVISOR_SERVICE} service failed to start!${STD}"
      echo ""
      exit 1
    else
      echo -e "${BLU}${SUPERVISOR_SERVICE} service started successfully.${STD}"
      echo ""
    fi
  else
    echo ""
  fi

  cat /tmp/last-php-fpm-check-restart.txt
else
  echo -e "CPU and memory percentage are ${BLU}below threshold: ${THRESHOLD}%${STD}, ${BLD}do nothing${STD}."
  THE_DATETIME=$(date "+%Y-%m-%d %H:%M:%S")
  if [ "${IS_SA}" -eq 1 ]; then
    rm -f /tmp/php-fpm-check.txt
    echo "${THE_DATETIME}" > /tmp/php-fpm-check.txt
  else
    sudo rm -f /tmp/php-fpm-check.txt
    echo "${THE_DATETIME}" > /tmp/php-fpm-check.txt
  fi

  echo ""
  cat /tmp/php-fpm-check.txt
fi

echo ""
