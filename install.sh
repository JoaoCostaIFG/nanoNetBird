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

# Install/regenerate the NetBird watchdog service. It restarts the daemon
# if it dies unexpectedly (typically the kernel OOM killer on this
# low-memory device) and re-applies the firewall rule if it goes missing
# (e.g. after an /etc/init.d/S35iptables restart). Like the service
# script, it is regenerated on every update.
echo "Installing NetBird watchdog..."
cat >/etc/init.d/S99netbird-watchdog.new <<'WATCHDOG_EOF'
#!/bin/sh
# NetBird watchdog (managed by nanoNetBird's install.sh; local edits are
# overwritten on update).
#
# Restarts the NetBird service when its daemon dies unexpectedly and
# re-applies the wt0 firewall rule if it goes missing (e.g. after an
# /etc/init.d/S35iptables restart restores /etc/iptables.conf).
#
# Auto-restart is keyed on a STALE pid file (pid file present, process
# gone): a deliberate `/etc/init.d/S98netbird stop` removes the pid file
# and is therefore left alone. To keep the watchdog from restarting an
# already-dead netbird (e.g. while debugging), create the pause file
# below and remove it to resume supervision.

name=netbird-watchdog
script=$(readlink -f "$0")
pid_file=/var/run/$name.pid
pause_file=/var/run/$name.pause
netbird_pid_file=/var/run/S98netbird.pid
netbird_init=/etc/init.d/S98netbird

check_interval=15 # seconds between health checks
max_wait=300      # cap for the restart backoff
stable_uptime=60  # seconds of uptime before the backoff resets

get_pid() {
  cat "$pid_file" 2>/dev/null
}

is_running() {
  pid=$(get_pid)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

log() {
  echo "$name: $*"
  logger -t "$name" "$*" 2>/dev/null
}

watch_loop() {
  failures=0
  last_start=0 # when the last start attempt came up (epoch seconds)
  prev_ok=1    # did the last start attempt come up?

  while :; do
    sleep "$check_interval"

    [ -e "$pause_file" ] && continue

    now=$(date +%s)

    if "$netbird_init" status >/dev/null 2>&1; then
      # Healthy: forget past failures once the daemon has been up for
      # a while, and keep the firewall rule in place (it can be wiped
      # by an /etc/init.d/S35iptables restart).
      if [ "$last_start" -gt 0 ] && [ $((now - last_start)) -ge "$stable_uptime" ]; then
        failures=0
      fi
      iptables -C INPUT -i wt0 -j ACCEPT 2>/dev/null ||
        iptables -I INPUT -i wt0 -j ACCEPT
      continue
    fi

    # Service down: only restart it if the pid file is stale, meaning
    # the daemon died on its own (a clean stop removes the pid file).
    [ -f "$netbird_pid_file" ] || continue

    if [ "$prev_ok" -eq 0 ]; then
      failures=$((failures + 1)) # last attempt never even came up
    elif [ $((now - last_start)) -lt "$stable_uptime" ]; then
      failures=$((failures + 1)) # came up, but died quickly again
    else
      failures=0 # ran stably before dying; treat as a fresh incident
    fi

    log "NetBird is down (stale pid file), restarting"
    "$netbird_init" start >/dev/null 2>&1
    if "$netbird_init" status >/dev/null 2>&1; then
      last_start=$(date +%s)
      prev_ok=1
    else
      prev_ok=0
    fi

    if [ "$failures" -gt 0 ]; then
      wait_secs=$((check_interval * (failures + 1)))
      [ "$wait_secs" -gt "$max_wait" ] && wait_secs=$max_wait
      log "NetBird failing repeatedly ($failures quick deaths), next check in ${wait_secs}s"
      sleep "$wait_secs"
    fi
  done
}

case "$1" in
  --loop)
    watch_loop
    ;;
  start)
    if is_running; then
      echo "Already started"
    else
      echo "Starting $name"
      rm -f "$pause_file"
      "$script" --loop >/dev/console 2>&1 &
      echo $! >"$pid_file"
    fi
    ;;
  stop)
    if is_running; then
      echo "Stopping $name"
      kill $(get_pid)
      rm -f "$pid_file"
    else
      echo "Not running"
    fi
    ;;
  restart)
    "$script" stop
    "$script" start
    ;;
  status)
    if is_running; then
      echo "Running"
    else
      echo "Stopped"
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
exit 0
WATCHDOG_EOF
chmod 755 /etc/init.d/S99netbird-watchdog.new
# Atomic replace: safe even if an older watchdog loop is running
mv /etc/init.d/S99netbird-watchdog.new /etc/init.d/S99netbird-watchdog

echo "Restarting NetBird service..."
/etc/init.d/S98netbird restart

echo "Restarting NetBird watchdog..."
/etc/init.d/S99netbird-watchdog restart

echo "Done!"
