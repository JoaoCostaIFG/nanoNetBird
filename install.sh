#/usr/bin/env bash
set -e

# See if netbird is already present and compare versions
if [ -f "/usr/sbin/netbird" ]; then
  VERSION_LOCAL="$(/usr/sbin/netbird version)"
  VERSION_REMOTE="$(curl -sL https://github.com/bc547/nanoNetBird/releases/latest/download/version.txt)"
  echo "Local version: ${VERSION_LOCAL}"
  echo "Remote version: ${VERSION_REMOTE}"
  if [ "$VERSION_LOCAL" == "$VERSION_REMOTE" ]; then
    echo "-> Identical... skipping update"
    exit 0
  fi
fi

# Download latest NetBird client to temporary location
echo "Downloading latest NetBird client..."
curl -sL -o /usr/sbin/netbird.new https://github.com/bc547/nanoNetBird/releases/latest/download/netbird
chmod 555 /usr/sbin/netbird.new

# Move old NetBird client out of the way (if needed)
echo "Installing latest NetBird client..."
if [ -f "/usr/sbin/netbird" ]; then
  rm -f /usr/sbin/netbird.old
  mv /usr/sbin/netbird /usr/sbin/netbird.old
fi
# Move new NetBird client to the correct location
mv /usr/sbin/netbird.new /usr/sbin/netbird

# Install NetBird service (if needed)
if [ ! -f "/etc/init.d/S98netbird" ]; then
  echo "Installing NetBird service... "
  /usr/sbin/netbird service install             # Installs incorrectly as /etc/init.d/netbird
  mv /etc/init.d/netbird /etc/init.d/S98netbird # Rename service file to correct name
  sed -i -e 's#/var/log/netbird/client\.log#console#g' \
    -e 's#/var/log/netbird/\$name\.log#/dev/null#g' \
    -e 's#/var/log/netbird/\$name\.err#/dev/null#g' \
    /etc/init.d/S98netbird
  sed -i '/echo "Unable to start, see \$stdout_log and \$stderr_log"/,/fi/ { /fi/ a \
\
       # Wait for wt0 interface with timeout\
       echo "Waiting for NetBird interface..."\
       for i in $(seq 1 30); do\
         if ip link show wt0 >/dev/null 2>&1; then\
           # allow incoming netbird connections\
           echo "Interface wt0 found, applying firewall rule"\
           iptables -I INPUT -i wt0 -j ACCEPT\
           break\
         fi\
         sleep 5\
       done
}' /etc/init.d/S98netbird
  chmod 755 /etc/init.d/S98netbird
fi

echo "Restarting NetBird service..."
/etc/init.d/S98netbird restart

echo "Done!"
