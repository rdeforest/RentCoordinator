# RentCoordinator TODO

Post-v1.0 improvements and technical debt.

## Installation Scripts Refactoring (Post-v1.0)

### Problem Statement
The scripts in `scripts/` contain **significant redundant code** that needs comprehensive refactoring:
- `install.sh` and `uninstall.sh` duplicate: color functions, output helpers, user/path utilities, OS detection, process management
- Init system handling duplicated within each script (systemd, openrc detection/setup)
- Deno installation logic is complex and could be reusable
- Argument parsing patterns repeated across scripts
- Path resolution and validation logic duplicated

**Scope**: This is broader than just abstracting init systems - the entire scripts directory needs DRY refactoring.

### Goal
Modularize install/uninstall scripts to eliminate all duplication and improve maintainability.

### Tasks

#### 1. Create Shared Library (`scripts/lib/common.sh`)
Extract shared functionality from `install.sh` and `uninstall.sh`:

- **Color definitions and output functions**
  - `print_success()`, `print_error()`, `print_warning()`, `print_info()`
  - Color codes (RED, GREEN, YELLOW, BLUE, NC)

- **Path and user utilities**
  - `get_user_home()` - Get actual home directory (not hardcoded `/home/`)
  - `get_deno_install_path()` - Determine Deno installation location
  - `detect_os()` - OS detection logic

- **Permission and validation utilities**
  - `check_root()` - Verify root access when needed
  - `check_command()` - Check if command exists
  - `verify_directory()` - Check directory existence and permissions
  - `verify_user_exists()` - Check if user account exists

- **Process management utilities**
  - `find_rentcoordinator_processes()` - Find running RC processes
  - `stop_process()` - Gracefully stop process with fallback to SIGKILL

#### 2. Modularize Init System Handlers

Create separate modules for each init system in `scripts/lib/init-systems/`:

```
scripts/lib/init-systems/
├── systemd.sh
├── openrc.sh
├── sysvinit.sh
├── runit.sh
└── upstart.sh
```

**Each init system module must implement:**

```bash
# Interface functions that all init system modules must provide:

# Returns 0 if this init system is in use on the current system, 1 otherwise
is_available() { ... }

# Install/configure service for this init system
# Args: $1=prefix, $2=user, $3=log_dir, $4=db_path, $5=port
install_service() { ... }

# Uninstall/remove service for this init system
uninstall_service() { ... }

# Start service using this init system
start_service() { ... }

# Stop service using this init system
stop_service() { ... }

# Get service status using this init system
# Returns: 0 if running, 1 if stopped
get_service_status() { ... }
```

**Example: `scripts/lib/init-systems/systemd.sh`**

```bash
#!/bin/bash

is_available() {
    [ -d /run/systemd/system ]
}

install_service() {
    local prefix="$1"
    local user="$2"
    local log_dir="$3"
    local db_path="$4"
    local port="$5"

    # Create systemd service file
    # Enable and optionally start service
}

uninstall_service() {
    systemctl stop rentcoordinator 2>/dev/null || true
    systemctl disable rentcoordinator 2>/dev/null || true
    rm -f /etc/systemd/system/rentcoordinator.service
    systemctl daemon-reload
}

# ... implement other interface functions
```

#### 3. Create Init System Manager (`scripts/lib/init-manager.sh`)

Central module that discovers and delegates to appropriate init system:

```bash
#!/bin/bash

# Source all init system modules
for init_system in "$(dirname "$0")/init-systems"/*.sh; do
    source "$init_system"
done

# Detect which init system is available
detect_init_system() {
    for system in systemd openrc runit upstart sysvinit; do
        if "${system}_is_available" 2>/dev/null; then
            echo "$system"
            return 0
        fi
    done
    echo "unknown"
    return 1
}

# Delegate to appropriate init system
install_init_service() {
    local init_system=$(detect_init_system)
    if [ "$init_system" != "unknown" ]; then
        "${init_system}_install_service" "$@"
    else
        print_warning "No supported init system detected"
        return 1
    fi
}

# Similar delegation functions for uninstall, start, stop, status
```

#### 4. Update Main Scripts

**install.sh** becomes:
```bash
#!/bin/bash

# Source shared library
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/init-manager.sh"

# Parse arguments
parse_arguments "$@"

# Main installation
main() {
    check_root
    create_user
    create_initial_directories
    install_deno
    clone_repository
    create_additional_directories
    build_application
    create_config
    create_management_script
    install_init_service "$PREFIX" "$APP_USER" "$LOG_DIR" "$DB_PATH" "$PORT"
    show_summary
}

main
```

**uninstall.sh** becomes:
```bash
#!/bin/bash

# Source shared library
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/init-manager.sh"

# Parse arguments
parse_arguments "$@"

# Main uninstallation
main() {
    check_root
    show_removal_plan
    confirm_uninstall
    stop_application
    uninstall_init_service
    remove_application
    remove_data
    remove_logs
    remove_user
    show_summary
}

main
```

### Benefits

1. **DRY Principle** - No duplicated code between install and uninstall
2. **Maintainability** - Changes to init system support in one place
3. **Extensibility** - Add new init systems by creating new module file
4. **Testability** - Each module can be tested independently
5. **Separation of Concerns** - Main scripts don't know about init system details
6. **Pluggability** - Init systems self-report availability

### Implementation Notes

- Main scripts should not import init system modules directly
- Init manager handles all init system detection and delegation
- Each init system module is completely self-contained
- Interface compliance is critical - all modules must implement all interface functions
- Graceful degradation if no init system is available

### Estimated Effort
- Medium (4-8 hours)
- Low risk - refactoring existing working code
- High value - makes future maintenance much easier

---

## Other Future Improvements

### Documentation
- [ ] Add architecture diagrams showing module relationships
- [ ] Create developer guide for adding new init systems
- [ ] Document testing procedures for install/uninstall scripts

### Testing
- [ ] Create test suite for install/uninstall scripts
- [ ] Add shellcheck integration to CI/CD
- [ ] Test installation on various distributions (Debian, Ubuntu, Fedora, Arch, Alpine)

### Features
- [ ] Add `--update` option to install script for in-place upgrades
- [ ] Add backup/restore functionality to uninstall script
- [ ] Support installing multiple instances on same server
- [ ] Add migration scripts for version upgrades

### Distribution
- [ ] Create distribution packages (deb, rpm, apk)
- [ ] Add to package repositories (apt, yum, etc.)
- [ ] Create Docker image
- [ ] Create snap/flatpak packages
