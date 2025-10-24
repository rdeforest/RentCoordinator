# Upstart Configuration

## External Documentation

- [Upstart Cookbook](http://upstart.ubuntu.com/cookbook/)
- [Ubuntu Upstart Documentation](https://help.ubuntu.com/community/UpstartHowto)

## Note

Upstart is deprecated in favor of systemd on most modern distributions. It was the default init system for:
- Ubuntu 6.10 through 14.10
- RHEL 6

## Example Configuration

Create `/etc/init/rentcoordinator.conf`:

```bash
# RentCoordinator - Tenant coordination application
#
# This service manages the RentCoordinator application

description "RentCoordinator Application"
author "Your Name"

# Start when networking is available
start on runlevel [2345]
stop on runlevel [!2345]

# Automatically respawn
respawn
respawn limit 10 5

# Run as specific user
setuid rentcoordinator
setgid rentcoordinator

# Set environment
env PORT=3000
env DB_PATH=/var/lib/rentcoordinator/tenant-coordinator.db
env PATH=/usr/local/bin:/usr/bin:/bin

# Change to app directory
chdir /opt/rentcoordinator

# Start the application
exec /usr/bin/npx coffee main.coffee

# Log output
console log
```

## Common Commands

```bash
# Start service
sudo start rentcoordinator

# Stop service
sudo stop rentcoordinator

# Restart service
sudo restart rentcoordinator

# Check status
sudo status rentcoordinator

# View logs
sudo tail -f /var/log/upstart/rentcoordinator.log

# Reload configuration
sudo initctl reload-configuration
```