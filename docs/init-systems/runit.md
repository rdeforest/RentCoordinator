# runit Configuration

## External Documentation

- [Void Linux runit Guide](https://docs.voidlinux.org/config/services/index.html)
- [Artix Linux runit Guide](https://wiki.artixlinux.org/Main/Runit)
- [runit Official Site](http://smarden.org/runit/)

## Example Service

Create service directory:
```bash
sudo mkdir -p /etc/sv/rentcoordinator
```

Create `/etc/sv/rentcoordinator/run`:
```bash
#!/bin/sh
exec 2>&1
exec chpst -u rentcoordinator:rentcoordinator \
    /home/rentcoordinator/.deno/bin/deno run \
    --allow-read --allow-write --allow-env --allow-net --unstable-kv \
    /opt/rentcoordinator/dist/main.js
```

Create `/etc/sv/rentcoordinator/log/run` (optional logging):
```bash
#!/bin/sh
exec svlogd -tt /var/log/rentcoordinator
```

## Common Commands

```bash
# Make scripts executable
sudo chmod +x /etc/sv/rentcoordinator/run
sudo chmod +x /etc/sv/rentcoordinator/log/run

# Enable service (create symlink)
sudo ln -s /etc/sv/rentcoordinator /var/service/

# Check status
sudo sv status rentcoordinator

# Start service
sudo sv start rentcoordinator

# Stop service
sudo sv stop rentcoordinator

# Restart service
sudo sv restart rentcoordinator

# Disable service
sudo rm /var/service/rentcoordinator

# View logs
tail -f /var/log/rentcoordinator/current
```