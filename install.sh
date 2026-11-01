#/usr/bin/env bash
set -e

OWNER="JoaoCostaIFG"
REPO="nanoNetBird"

# See if netbird is already present and compare versions
if [ -f "/usr/sbin/netbird" ]; then
  VERSION_LOCAL="$(/usr/sbin/netbird version)"
  VERSION_REMOTE="$(curl -sL https://github.com/${OWNER}/${REPO}/releases/latest/download/version.txt)"
  echo "Local version: ${VERSION_LOCAL}"
  echo "Remote version: ${VERSION_REMOTE}"
  if [ "$VERSION_LOCAL" == "$VERSION_REMOTE" ]; then
    echo "-> Identical... skipping update"
    exit 0
  fi
fi

# Download latest NetBird client to temporary location
echo "Downloading latest NetBird client..."
curl -sL -o /usr/sbin/netbird.new https://github.com/${OWNER}/${REPO}/releases/latest/download/netbird
chmod 555 /usr/sbin/netbird.new

# Move old NetBird client out of the way (if needed)
echo "Installing latest NetBird client..."
if [ -f "/usr/sbin/netbird" ]; then
  rm -f /usr/sbin/netbird.old
  mv /usr/sbin/netbird /usr/sbin/netbird.old
fi
# Move new NetBird client to the correct location
mv /usr/sbin/netbird.new /usr/sbin/netbird

# Install/regenerate NetBird service script.
# Regenerated on every update so that service script fixes reach
# already-installed devices (the script only lives in flash otherwise).
echo "Installing NetBird service..."
# Stop and remove the incorrectly-named service from a stray
# `netbird service install`, if present (it would make install fail)
if [ -f /etc/init.d/netbird ]; then
  /etc/init.d/netbird stop >/dev/null 2>&1 || true
  rm -f /etc/init.d/netbird
fi
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
           # allow incoming netbird connections (idempotent: never duplicates)\
           echo "Interface wt0 found, applying firewall rule"\
           iptables -C INPUT -i wt0 -j ACCEPT 2>/dev/null || iptables -I INPUT -i wt0 -j ACCEPT\
           break\
         fi\
         sleep 5\
       done
}' /etc/init.d/S98netbird
chmod 755 /etc/init.d/S98netbird
# Warn if the upstream init template changed and the patch no longer applies
grep -q "iptables -C INPUT -i wt0" /etc/init.d/S98netbird ||
  echo "WARNING: firewall patch did not apply to the service script!"

# Purge duplicate firewall rules accumulated by older service scripts
# (the service re-adds a single rule on restart)
while iptables -D INPUT -i wt0 -j ACCEPT 2>/dev/null; do :; done

echo "Restarting NetBird service..."
/etc/init.d/S98netbird restart

echo "Done!"
