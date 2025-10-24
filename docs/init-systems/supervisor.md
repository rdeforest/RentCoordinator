# Supervisor Configuration

## External Documentation

- [Supervisor Official Documentation](http://supervisord.org/)
- [Supervisor Configuration Guide](http://supervisord.org/configuration.html)
- [Digital Ocean Supervisor Tutorial](https://www.digitalocean.com/community/tutorials/how-to-install-and-manage-supervisor-on-ubuntu-and-debian-vps)

## Installation

```bash
# Ubuntu/Debian
sudo apt-get install supervisor

# RHEL/CentOS
sudo yum install supervisor

# Or via pip
pip install supervisor
```

## Supervisor Configuration

Create `/etc/supervisor/conf.d/rentcoordinator.conf`:

```ini
[program:rentcoordinator]
command=/usr/bin/npx coffee main.coffee
directory=/opt/rentcoordinator
user=rentcoordinator
autostart=true
autorestart=true
startretries=3
stderr_logfile=/var/log/rentcoordinator/supervisor-error.log
stdout_logfile=/var/log/rentcoordinator/supervisor-output.log
environment=PATH="/usr/local/bin:/usr/bin:/bin",PORT="3000",DB_PATH="/var/lib/rentcoordinator/tenant-coordinator.db"
stopsignal=QUIT
stopasgroup=true
killasgroup=true
```

## Common Commands

```bash
# Reload supervisor configuration
sudo supervisorctl reread
sudo supervisorctl update

# Start application
sudo supervisorctl start rentcoordinator

# Stop application
sudo supervisorctl stop rentcoordinator

# Restart application
sudo supervisorctl restart rentcoordinator

# Check status
sudo supervisorctl status rentcoordinator

# View logs
sudo supervisorctl tail -f rentcoordinator

# Interactive shell
sudo supervisorctl
# Then use commands like: status, start rentcoordinator, stop rentcoordinator

# Start supervisor service
sudo service supervisor start

# Enable supervisor on boot
sudo systemctl enable supervisor  # systemd
# or
sudo update-rc.d supervisor enable  # SysV
```

## Web Interface (Optional)

Add to `/etc/supervisor/supervisord.conf`:

```ini
[inet_http_server]
port = 127.0.0.1:9001
username = admin
password = your_password
```

Then restart supervisor and access http://localhost:9001