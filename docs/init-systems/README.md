# Init System and Process Manager Guides

This directory contains links and basic examples for configuring RentCoordinator with various init systems and process managers.

## Init Systems

- [systemd](systemd.md) - Modern Linux init system (Ubuntu 16+, Debian 8+, RHEL 7+)
- [OpenRC](openrc.md) - Gentoo, Alpine Linux, and other distributions
- [runit](runit.md) - Void Linux, Artix Linux
- [SysV init](sysvinit.md) - Traditional Unix System V init
- [Upstart](upstart.md) - Ubuntu 14.04 and older

## Process Managers

- [PM2](pm2.md) - Node.js process manager with built-in load balancer
- [Supervisor](supervisor.md) - Python-based process control system
- [Docker](docker.md) - Container-based deployment

## Choosing an Init System

Your init system is typically determined by your Linux distribution:

| Distribution | Default Init System |
|--------------|--------------------|
| Ubuntu 16+ | systemd |
| Debian 8+ | systemd |
| RHEL/CentOS 7+ | systemd |
| Fedora | systemd |
| OpenSUSE | systemd |
| Arch Linux | systemd |
| Gentoo | OpenRC (systemd optional) |
| Alpine Linux | OpenRC |
| Void Linux | runit |
| Artix Linux | OpenRC/runit/s6 |
| Devuan | SysV init |
| Slackware | SysV init |

To check your init system:
```bash
# Method 1: Check for systemd
if [ -d /run/systemd/system ]; then
    echo "systemd"
fi

# Method 2: Check init process
ls -l /sbin/init

# Method 3: Check process 1
ps -p 1
```