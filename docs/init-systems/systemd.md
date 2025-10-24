# systemd Configuration

## External Documentation

- [Official systemd Documentation](https://www.freedesktop.org/wiki/Software/systemd/)
- [Arch Linux systemd Guide](https://wiki.archlinux.org/title/Systemd)
- [Red Hat systemd Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/system_administrators_guide/chap-managing_services_with_systemd)
- [systemd for Developers](https://0pointer.de/blog/projects/systemd-for-admins-1.html)

## Example Service File

Create `/etc/systemd/system/rentcoordinator.service`:

```ini
[Unit]
Description=RentCoordinator Application
After=network.target

[Service]
Type=simple
User=rentcoordinator
Group=rentcoordinator
WorkingDirectory=/opt/rentcoordinator
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="PORT=3000"
Environment="DB_PATH=/var/lib/rentcoordinator/tenant-coordinator.db"
ExecStart=/usr/bin/npx coffee main.coffee
Restart=always
RestartSec=10

# Security options (optional but recommended)
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

## Common Commands

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable service (auto-start on boot)
sudo systemctl enable rentcoordinator

# Start service
sudo systemctl start rentcoordinator

# Stop service
sudo systemctl stop rentcoordinator

# Restart service
sudo systemctl restart rentcoordinator

# Check status
sudo systemctl status rentcoordinator

# View logs
sudo journalctl -u rentcoordinator -f

# View logs from last boot
sudo journalctl -u rentcoordinator -b
```