# OpenRC Configuration

## External Documentation

- [Gentoo OpenRC Guide](https://wiki.gentoo.org/wiki/OpenRC)
- [Alpine Linux OpenRC Guide](https://wiki.alpinelinux.org/wiki/OpenRC)
- [OpenRC GitHub Project](https://github.com/OpenRC/openrc)

## Example Init Script

Create `/etc/init.d/rentcoordinator`:

```bash
#!/sbin/openrc-run

name="RentCoordinator"
description="RentCoordinator Application"

command="/usr/bin/npx"
command_args="coffee main.coffee"
command_user="rentcoordinator:rentcoordinator"
directory="/opt/rentcoordinator"
command_background=true
pidfile="/var/run/${RC_SVCNAME}.pid"
output_log="/var/log/rentcoordinator/app.log"
error_log="/var/log/rentcoordinator/error.log"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -d -o "${command_user}" "${pidfile%/*}"
    checkpath -d -o "${command_user}" "/var/log/rentcoordinator"
}

stop() {
    ebegin "Stopping ${name}"
    start-stop-daemon --stop --pidfile "${pidfile}" --retry=TERM/30/KILL/5
    eend $?
}
```

## Common Commands

```bash
# Make script executable
sudo chmod +x /etc/init.d/rentcoordinator

# Add to default runlevel
sudo rc-update add rentcoordinator default

# Start service
sudo rc-service rentcoordinator start

# Stop service
sudo rc-service rentcoordinator stop

# Restart service
sudo rc-service rentcoordinator restart

# Check status
sudo rc-service rentcoordinator status

# Remove from runlevel
sudo rc-update del rentcoordinator
```