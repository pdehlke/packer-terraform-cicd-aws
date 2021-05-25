#!/bin/bash
set -e

apt_wait () {
  echo '---- waiting for apt locks'
  while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
    sleep 1
  done
  while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do
    sleep 1
  done
  if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
    while sudo fuser /var/log/unattended-upgrades/unattended-upgrades.log >/dev/null 2>&1 ; do
      sleep 1
    done
  fi
}

echo '---- update apt'
apt_wait
DEBIAN_FRONTEND=noninteractive apt-get -y update
apt_wait
echo '---- install apache'
DEBIAN_FRONTEND=noninteractive apt-get -y install apache2

cat > /var/www/html/index.html <<HERE
Your test config worked, pete! It's $(date)
HERE
