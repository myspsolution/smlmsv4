#!/bin/bash
# php-fpm-advisor.sh
# prepared by dicky.dwijanto@myspsolution.com
# last update: May 20th, 2025

# average of orangt per process, in kb, set it when required
MIN_ORANGT_MEM_PER_PROCESS=110000

RED='\033[1;41;37m'
BLU='\033[1;94m'
YLW='\033[1;33m'
STD='\033[0m'
BLD='\033[1;97m'

PARAM1="$1"

# Check if PHP is installed
if ! command -v php &> /dev/null; then
  echo ""
  echo -e "${BLD}PHP is not installed on this system${STD}. Exiting."
  echo ""
  exit 1
fi

# Paths to possible www.conf locations - adjust as appropriate for your system
POSSIBLE_PATHS=(
    "/etc/php-fpm.d/www.conf"             # Common on CentOS/RHEL
    "/etc/php-fpm.conf"                   # much older Linux distros
    "/etc/php/7.0/fpm/pool.d/www.conf"    # Ubuntu example
    "/etc/php/7.1/fpm/pool.d/www.conf"
    "/etc/php/7.2/fpm/pool.d/www.conf"
    "/etc/php/7.3/fpm/pool.d/www.conf"
    "/etc/php/7.4/fpm/pool.d/www.conf"
    "/etc/php/8/fpm/pool.d/www.conf"
    "/etc/php/8.0/fpm/pool.d/www.conf"
    "/etc/php/8.1/fpm/pool.d/www.conf"
    "/etc/php/8.2/fpm/pool.d/www.conf"
    "/etc/php/8.3/fpm/pool.d/www.conf"
    "/etc/php/8.4/fpm/pool.d/www.conf"
    "/etc/php/8.5/fpm/pool.d/www.conf"
    "/etc/php/8.6/fpm/pool.d/www.conf"
    "/etc/php/9/fpm/pool.d/www.conf"
    "/etc/php/9.0/fpm/pool.d/www.conf"
    "/etc/php/9.1/fpm/pool.d/www.conf"
    "/etc/php/9.2/fpm/pool.d/www.conf"
)

WWW_CONF=""

# Find the first existing www.conf
for path in "${POSSIBLE_PATHS[@]}"; do
  if [ -f "${path}" ]; then
    WWW_CONF="${path}"
    break
  fi
done

if [ -z "${WWW_CONF}" ]; then
  echo ""
  echo -e "Could not find file ${BLD}www.conf${STD} in known locations."
  echo ""
  exit 1
fi

WWW_CONF_BACKUP="${WWW_CONF}.before_update"

PHP_FPM_SERVICE=$(systemctl list-unit-files --type=service --no-legend | awk '{print $1}' | grep -E '^php.*fpm\.service$' | head -n 1)

if [ -n "${PHP_FPM_SERVICE}" ]; then
  # Strip off the .service suffix
  PHP_FPM_SERVICE="${PHP_FPM_SERVICE%.service}"
else
  echo ""
  echo -e "No ${BLD}php-fpm${STD} service detected."
  echo ""
  exit 1
fi

# Median, rounded to integer
MEDIAN_PHP_FPM_RAM=$(
  ps aux | grep -E 'php-fpm.*pool' | grep -v grep | awk '{print $6}' | sort -n | awk '{
    a[NR]=$1
  }
  END {
    if (NR % 2) {
      print int(a[(NR + 1) / 2] + 0.5)
    } else {
      m = (a[(NR/2)] + a[(NR/2)+1]) / 2
      print int(m + 0.5)
    }
  }'
)

if [ -z "${MEDIAN_PHP_FPM_RAM}" ]; then
  echo ""
  echo -e "No ${BLD}php-fpm pool${STD} processes found. Exiting."
  exit 1
fi

# Average (Mean), rounded to integer
AVG_PHP_FPM_RAM=$(
  ps aux | grep -E 'php-fpm.*pool' | grep -v grep | awk '{
    sum += $6
    n++
  }
  END {
    if (n > 0)
      print int((sum / n) + 0.5)
    else
      print 0
  }'
)

# get the larger between average and median
if [ "${AVG_PHP_FPM_RAM}" -gt "${MEDIAN_PHP_FPM_RAM}" ]; then
  MEDIAN_PHP_FPM_RAM="${AVG_PHP_FPM_RAM}"
fi

# Ensure MEDIAN_PHP_FPM_RAM is at least MIN_ORANGT_MEM_PER_PROCESS
if [ "${MEDIAN_PHP_FPM_RAM}" -lt ${MIN_ORANGT_MEM_PER_PROCESS} ]; then
  MEDIAN_PHP_FPM_RAM=${MIN_ORANGT_MEM_PER_PROCESS}
fi

# Calculate PHP_FPM_MIN_CHILDREN_INT based on available RAM
RAM_TOTAL_MB=$(free -m | grep '^Mem:' | awk '{print $2}')
RAM_TOTAL_USABLE_GB=$(awk "BEGIN {printf \"%.1f\",${RAM_TOTAL_MB}/1024}")
RAM_TOTAL_GB=$(echo ${RAM_TOTAL_USABLE_GB} | awk '{print int($1+0.55)}')

if awk "BEGIN {exit !(${RAM_TOTAL_USABLE_GB} < 4)}"; then
  PHP_FPM_MIN_CHILDREN_INT=5
elif awk "BEGIN {exit !(${RAM_TOTAL_USABLE_GB} < 8)}"; then
  PHP_FPM_MIN_CHILDREN_INT=10
elif awk "BEGIN {exit !(${RAM_TOTAL_USABLE_GB} < 16)}"; then
  PHP_FPM_MIN_CHILDREN_INT=20
elif awk "BEGIN {exit !(${RAM_TOTAL_USABLE_GB} < 32)}"; then
  PHP_FPM_MIN_CHILDREN_INT=30
else
  PHP_FPM_MIN_CHILDREN_INT=60
fi

echo ""

if [ "${PARAM1}" == "i" ]; then
  # Get PHP version (just for info)
  PHP_VERSION=$(php -v | head -n 1 | awk '{print $2}')
  echo -e "PHP Version           : ${BLD}${PHP_VERSION}${STD}"
fi
echo -e "Conf. file location   : ${BLD}${WWW_CONF}${STD}"
echo -e "PHP service name      : ${BLD}${PHP_FPM_SERVICE}${STD}"
echo -e "Average php fpm RAM   : ${YLW}${MEDIAN_PHP_FPM_RAM}${STD}"
echo -e "Min pm children count : ${YLW}${PHP_FPM_MIN_CHILDREN_INT}${STD}, based on usable RAM: ${BLD}${RAM_TOTAL_USABLE_GB}GB${STD}"
echo ""

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

CURRENT_PM=$(grep "^pm =" "${WWW_CONF}" | awk -F= '{gsub(/^ +| +$/, "", $2); print $2}')

# Grab current pm.max_children (ignoring whitespace and commented lines)
CURRENT_MAX_CHILDREN=$(grep -E '^\s*[^#;]*pm\.max_children\s*=' "${WWW_CONF}" | awk -F= '{gsub(/[ \t]/,"",$2); print $2}' | tail -n 1)

# pm.max_requests, find value and check if commented or >200
CURRENT_MAX_REQUESTS=$(grep -E '^\s*[;#]?\s*pm\.max_requests\s*=' "${WWW_CONF}" | tail -n 1 | awk -F= '{gsub(/[ \t;]/,"",$2); print $2}')

if [ -z "${CURRENT_PM}" ]; then
  echo ""
  echo -e "${RED}pm value not found${STD}"
  echo -e "Please check or unremark line: ${BLD}pm = ${STD} on file: ${BLD}${WWW_CONF}${STD}"
  exit 1
fi

if [ -z "${CURRENT_MAX_CHILDREN}" ]; then
  echo ""
  echo -e "${RED}pm.max_children value not found${STD}"
  echo -e "Please check or unremark line: ${BLD}pm.max_children = ${STD} on file: ${BLD}${WWW_CONF}${STD}"
  exit 1
fi

if [ -z  "${CURRENT_MAX_REQUESTS}" ]; then
  echo ""
  echo -e "${RED}pm.max_requests value not found${STD}"
  echo -e "Please check or unremark line: ${BLD}pm.max_requests = ${STD} on file: ${BLD}${WWW_CONF}${STD}"
  exit 1
fi

if [ "${PARAM1}" == "i" ]; then
  echo "Information only, no changing"
  echo "-----------------------------"
  echo ""
  echo -e "pm = ${YLW}$CURRENT_PM${STD}"
  echo -e "pm.max_children = ${YLW}${CURRENT_MAX_CHILDREN}${STD}"
  echo -e "pm.max_requests = ${YLW}${CURRENT_MAX_REQUESTS}${STD}"
  echo ""
  echo "-----------------------------"
  echo ""
  exit
fi
# if [ "${PARAM1}" == "i" ];

if [ "${PARAM1}" != "y" ]; then
  echo -e "This script will calculate recommended ${BLD}php-fpm www.conf${STD} parameter values"
  echo -e "based on available CPU cores and memory."
  echo -e "It is required to ${BLD}temporarily stop ${PHP_FPM_SERVICE}${STD} service to calculate available memory."
  echo -e "Press ${BLD}y${STD} to continue, or ${BLD}n${STD} to cancel"

  while true; do
    read -p "Continue ? (y/n) " YN
      if [ "$YN" == "y" ] || [ "$YN" == "n" ]; then
      break;
    else
    echo "Please type [y]es or [n]o : "
    fi
  done

  echo ""

  if [ "$YN" == "n" ]; then
    exit
  fi
fi
# if [ "${PARAM1}" != "y" ];

echo -e "${BLD}Stopping ${PHP_FPM_SERVICE} service ...${STD}"
[ "${IS_SA}" -eq 1 ] && systemctl stop "${PHP_FPM_SERVICE}" || sudo systemctl stop "${PHP_FPM_SERVICE}"

sleep 5

AVAILABLE_MEMORY=$(free | grep '^Mem:' | awk '{print $7}')

# Calculate max children (rounding)
PHP_FPM_MAX_CHILDREN_INT=$(echo "${AVAILABLE_MEMORY}/${MEDIAN_PHP_FPM_RAM}" | bc -l | awk '{print int($1+0.45)}')

# Ensure PHP_FPM_MAX_CHILDREN_INT is at least PHP_FPM_MIN_CHILDREN_INT
if [ "${PHP_FPM_MAX_CHILDREN_INT}" -lt "${PHP_FPM_MIN_CHILDREN_INT}" ]; then
  PHP_FPM_MAX_CHILDREN_INT="${PHP_FPM_MIN_CHILDREN_INT}"}
fi

echo ""
echo -e "Total available RAM (kb)             : ${BLD}${AVAILABLE_MEMORY}${STD}"
echo -e "Average php fpm process RAM (kb)     : ${BLD}${MEDIAN_PHP_FPM_RAM}${STD}"
echo -e "Calculated PHP FPM Max Children (int): ${BLD}${AVAILABLE_MEMORY} / ${MEDIAN_PHP_FPM_RAM}${STD} = ${YLW}${PHP_FPM_MAX_CHILDREN_INT}${STD}"

echo ""

if [ "${CURRENT_PM}" != "static" ]; then
  if [ ! -f "${WWW_CONF_BACKUP}" ]; then
    echo -e "Create backup file: ${BLD}${WWW_CONF_BACKUP}${STD} ..."
    [ "${IS_SA}" -eq 1 ] && cp "${WWW_CONF}" "${WWW_CONF_BACKUP}" || sudo cp "${WWW_CONF}" "${WWW_CONF_BACKUP}"
  fi

  echo -e "${BLU}Updating pm from ${CURRENT_PM} to ${YLW}static.${BLU}${STD}"
  sudo sed -i "s/^pm =.*/pm = static/" "${WWW_CONF}"
else
  echo -e "${BLD}pm is already set to static, not changed.${STD}"
fi

if [ "${CURRENT_MAX_REQUESTS}" -gt 200 ]; then
  if [ ! -f "${WWW_CONF_BACKUP}" ]; then
    echo -e "Create backup file: ${BLD}${WWW_CONF_BACKUP}${STD} ..."
    [ "${IS_SA}" -eq 1 ] && cp "${WWW_CONF}" "${WWW_CONF_BACKUP}" || sudo cp "${WWW_CONF}" "${WWW_CONF_BACKUP}"
  fi

  echo -e "${BLU}pm.max_request ${YLW}(${CURRENT_MAX_REQUESTS}) > 200${BLU}, set to ${YLW}200.${BLU}${STD}"
  if [ "${IS_SA}" -eq 1 ]; then
    sed -i "s/^pm\.max_requests *=.*/pm.max_requests = 200/" "${WWW_CONF}"
  else
    sudo sed -i "s/^pm\.max_requests *=.*/pm.max_requests = 200/" "${WWW_CONF}"
  fi
else
  echo -e "${BLD}pm.max_requests (${CURRENT_MAX_REQUESTS}) <= 200, not changed.${STD}"
fi

if [ "${PHP_FPM_MAX_CHILDREN_INT}" -lt "${CURRENT_MAX_CHILDREN}" ]; then
  if [ ! -f "${WWW_CONF_BACKUP}" ]; then
    echo -e "Create backup file: ${BLD}${WWW_CONF_BACKUP}${STD} ..."
    [ "${IS_SA}" -eq 1 ] && cp "${WWW_CONF}" "${WWW_CONF_BACKUP}" || sudo cp "${WWW_CONF}" "${WWW_CONF_BACKUP}"
  fi

  echo -e "${BLU}pm.max_children ${YLW}(${CURRENT_MAX_CHILDREN}) > calculated (${PHP_FPM_MAX_CHILDREN_INT})${BLU}, change applied.${STD}"
  if [ "${IS_SA}" -eq 1 ]; then
    sed -i "s/^pm\.max_children *=.*/pm.max_children = ${PHP_FPM_MAX_CHILDREN_INT}/" "${WWW_CONF}"
  else
    sudo sed -i "s/^pm\.max_children *=.*/pm.max_children = ${PHP_FPM_MAX_CHILDREN_INT}/" "${WWW_CONF}"
  fi
else
  echo -e "${BLD}pm.max_children ($CURRENT_MAX_CHILDREN) <= calculated (${PHP_FPM_MAX_CHILDREN_INT}), not changed.${STD}"
fi

echo ""
echo -e "${BLD}Restarting ${PHP_FPM_SERVICE} service ...${STD}"
if [ "${IS_SA}" -eq 1 ]; then
  systemctl start "${PHP_FPM_SERVICE}"
else
  sudo systemctl start "${PHP_FPM_SERVICE}"
fi

# Grab current pm
CURRENT_PM=$(grep "^pm =" "${WWW_CONF}" | awk -F= '{gsub(/^ +| +$/, "", $2); print $2}')

# Grab current pm.max_children (ignoring whitespace and commented lines)
CURRENT_MAX_CHILDREN=$(grep -E '^\s*[^#;]*pm\.max_children\s*=' "${WWW_CONF}" | awk -F= '{gsub(/[ \t]/,"",$2); print $2}' | tail -n 1)

# pm.max_requests, find value and check if commented or >200
CURRENT_MAX_REQUESTS=$(grep -E '^\s*[;#]?\s*pm\.max_requests\s*=' "${WWW_CONF}" | tail -n 1 | awk -F= '{gsub(/[ \t;]/,"",$2); print $2}')

echo ""
echo -e "php fpm file config: ${YLW}${WWW_CONF}${STD}"
echo ""
echo "--------------------------"
echo ""
echo -e "pm = ${YLW}${CURRENT_PM}${STD}"
echo -e "pm.max_children = ${YLW}${CURRENT_MAX_CHILDREN}${STD}"
echo -e "pm.max_requests = ${YLW}${CURRENT_MAX_REQUESTS}${STD}"
echo ""
echo "--------------------------"
echo ""

# Check if PHP_FPM_SERVICE is running
if ! systemctl is-active --quiet "${PHP_FPM_SERVICE}"; then
  echo -e "${RED}ERROR: ${PHP_FPM_SERVICE} service failed to start!${STD}"
  echo ""
  exit 1
else
  echo -e "${BLU}${PHP_FPM_SERVICE} service started successfully.${STD}"
  echo ""
fi

THE_DATETIME=$(date "+%Y-%m-%d %H:%M:%S")
if [ "${IS_SA}" -eq 1 ]; then
  rm -f /tmp/php-fpm-advisor.txt
  echo "${THE_DATETIME}" > /tmp/php-fpm-advisor.txt
else
  sudo rm -f /tmp/php-fpm-advisor.txt
  echo "${THE_DATETIME}" > /tmp/php-fpm-advisor.txt
fi

cat /tmp/php-fpm-advisor.txt

echo ""
