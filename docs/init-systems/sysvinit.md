# SysV Init Configuration

## External Documentation

- [Debian SysV Init Guide](https://wiki.debian.org/Daemon)
- [Linux SysV Init Runlevels](https://www.tutorialspoint.com/unix_administration/unix_system_v_init.htm)
- [LSB Init Scripts](https://wiki.debian.org/LSBInitScripts)

## Example Init Script

Create `/etc/init.d/rentcoordinator`:

```bash
#!/bin/bash
### BEGIN INIT INFO
# Provides:          rentcoordinator
# Required-Start:    $network $local_fs
# Required-Stop:     $network $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: RentCoordinator Application
# Description:       Tenant coordination application for tracking work and rent
### END INIT INFO

# Configuration
APP_DIR="/opt/rentcoordinator"
USER="rentcoordinator"
PIDFILE="/var/run/rentcoordinator.pid"
LOGFILE="/var/log/rentcoordinator/app.log"
COFFEE="/usr/bin/npx coffee"

# Source function library
. /lib/lsb/init-functions

start() {
    if [ -f $PIDFILE ] && kill -0 $(cat $PIDFILE) 2>/dev/null; then
        log_warning_msg "RentCoordinator is already running"
        return 1
    fi
    
    log_daemon_msg "Starting RentCoordinator"
    su - $USER -c "cd $APP_DIR && nohup $COFFEE main.coffee > $LOGFILE 2>&1 & echo \$! > $PIDFILE"
    log_end_msg $?
}

stop() {
    if [ ! -f $PIDFILE ]; then
        log_warning_msg "RentCoordinator is not running"
        return 1
    fi
    
    log_daemon_msg "Stopping RentCoordinator"
    kill $(cat $PIDFILE)
    rm -f $PIDFILE
    log_end_msg $?
}

status() {
    if [ -f $PIDFILE ] && kill -0 $(cat $PIDFILE) 2>/dev/null; then
        log_success_msg "RentCoordinator is running (PID: $(cat $PIDFILE))"
    else
        log_failure_msg "RentCoordinator is not running"
        [ -f $PIDFILE ] && rm -f $PIDFILE
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 2; start ;;
    status)  status ;;
    *)       echo "Usage: $0 {start|stop|restart|status}" ;;
esac
```

## Common Commands

```bash
# Make script executable
sudo chmod +x /etc/init.d/rentcoordinator

# Install init script
sudo update-rc.d rentcoordinator defaults

# Or on Red Hat-based systems
sudo chkconfig --add rentcoordinator
sudo chkconfig rentcoordinator on

# Start service
sudo service rentcoordinator start
# or
sudo /etc/init.d/rentcoordinator start

# Stop service
sudo service rentcoordinator stop

# Restart service
sudo service rentcoordinator restart

# Check status
sudo service rentcoordinator status

# Remove from startup
sudo update-rc.d -f rentcoordinator remove
# or on Red Hat
sudo chkconfig rentcoordinator off
```