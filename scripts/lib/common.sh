#!/bin/bash


readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_dry_run() { echo -e "${BLUE}[DRY RUN]${NC} $1"; }

export PATH="$PATH:/sbin:/usr/sbin"

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_FAMILY=$ID_LIKE
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_FAMILY="rhel fedora"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_FAMILY="debian"
    else
        OS=$(uname -s)
        OS_FAMILY=""
    fi
}

check_root() {
    local operation="${1:-this operation}"

    if [ "$EUID" -ne 0 ]; then
        print_error "$operation requires root privileges"
        print_info "Try: sudo $0"
        return 1
    fi
    return 0
}

is_root() {
    [ "$EUID" -eq 0 ]
}

run_as_root() {
    if is_root; then
        "$@"
    else
        sudo "$@"
    fi
}


get_user_home() {
    local username="$1"

    if command -v getent >/dev/null 2>&1; then
        getent passwd "$username" | cut -d: -f6
    else
        eval echo ~"$username"
    fi
}

get_deno_install_path() {
    local username="$1"
    local user_home=$(get_user_home "$username")
    echo "$user_home/.deno"
}

get_current_user() {
    whoami
}


user_exists() {
    local username="$1"
    id "$username" &>/dev/null
}

create_user() {
    local username="$1"

    if user_exists "$username"; then
        print_warning "User $username already exists"
        return 0
    fi

    print_info "Creating user: $username"

    adduser=adduser
    if ! command -v adduser 2>/dev/null; then
      if command -v useradd 2>/dev/null; then
        adduser=useradd
      else
        print_error "No useradd or adduser found in $PATH"
        return 1
      fi
    fi

    if ! run_as_root "$adduser" -m -s /bin/bash "$username"; then
      print_error "adduser failed"
      return 1
    fi

    print_success "User created: $username"
    return 0
}

remove_user() {
    local username="$1"

    if ! user_exists "$username"; then
        print_info "User $username does not exist"
        return 0
    fi

    if [ "$(get_current_user)" = "$username" ]; then
        print_warning "Cannot remove current user"
        return 1
    fi

    print_info "Removing user: $username"

    deluser=deluser
    if ! command -v deluser 2>/dev/null; then
      if command -v userdel 2>/dev/null; then
        adduser=userdel
      else
        print_error "No userdel or deluser found in $PATH"
        return 1
      fi
    fi

    if ! run_as_root "$deluser_path" --remove-home "$username" 2>/dev/null ||
         run_as_root "$deluser_path"               "$username" 2>/dev/null; then
      print_error "User removal failed"
      return 1
    fi

    print_success "User removed: $username"
    return 0
}


command_exists() {
    command -v "$1" &>/dev/null
}

require_command() {
    local cmd="$1"
    local msg="${2:-Command '$cmd' is required but not found}"

    if ! command_exists "$cmd"; then
        print_error "$msg"
        exit 1
    fi
}

directory_writable() {
    local dir="$1"
    [ -d "$dir" ] && [ -w "$dir" ]
}

create_directory() {
    local dir="$1"
    local owner="$2"

    run_as_root mkdir -p "$dir" || return 1

    if [ -n "$owner" ]; then
        run_as_root chown -R "$owner" "$dir" || return 1
    fi

    return 0
}


find_processes() {
    local pattern="$1"
    pgrep -f "$pattern" 2>/dev/null || echo ""
}

process_running() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

stop_process() {
    local pid="$1"

    if ! process_running "$pid"; then
        return 0
    fi

    kill "$pid" 2>/dev/null
    sleep 2

    if process_running "$pid"; then
        kill -9 "$pid" 2>/dev/null
        sleep 1
    fi

    return 0
}

stop_processes_matching() {
    local pattern="$1"
    local pids=$(find_processes "$pattern")

    if [ -z "$pids" ]; then
        return 0
    fi

    for pid in $pids; do
        stop_process "$pid"
    done

    return 0
}


safe_remove() {
    local path="$1"
    local dry_run="${2:-false}"

    if [ ! -e "$path" ]; then
        return 0
    fi

    if [ "$dry_run" = "true" ]; then
        print_dry_run "Would remove: $path"
        if [ -d "$path" ]; then
            du -sh "$path" 2>/dev/null | awk '{print "  Size: " $1}'
        fi
        return 0
    fi

    rm -rf "$path"
    return 0
}

set_ownership() {
    local path="$1"
    local owner="$2"

    if [ ! -e "$path" ]; then
        return 1
    fi

    run_as_root chown -R "$owner" "$path"
    return $?
}


install_deno() {
    local username="$1"
    local user_home=$(get_user_home "$username")
    local deno_install="$user_home/.deno"

    print_info "Installing Deno for $username..."

    if [ -f "$deno_install/bin/deno" ]; then
        if "$deno_install/bin/deno" --version &>/dev/null; then
            print_success "Deno already installed at $deno_install"
            return 0
        fi
        print_warning "Deno exists but not working, reinstalling..."
    fi

    local install_script="/tmp/deno-install-$$.sh"

    if command_exists curl; then
        curl -fsSL https://deno.land/install.sh -o "$install_script" || {
            print_error "Failed to download Deno installer"
            return 1
        }
    elif command_exists wget; then
        wget -qO "$install_script" https://deno.land/install.sh || {
            print_error "Failed to download Deno installer"
            return 1
        }
    else
        print_error "Neither curl nor wget found"
        return 1
    fi

    # XXX: Deno installer tries to access /dev/tty for progress bars and interactive features
    # XXX: Redirecting stdin from /dev/null makes it non-interactive to prevent TTY errors
    # XXX: Installer may exit non-zero due to TTY errors but still successfully install the binary
    if [ "$(get_current_user)" = "$username" ]; then
        sh "$install_script" < /dev/null || true
    else
        local user_home=$(get_user_home "$username")
        sudo -u "$username" -H sh -c "cd '$user_home' && sh '$install_script'" < /dev/null || true
    fi

    rm -f "$install_script"

    if [ ! -f "$deno_install/bin/deno" ]; then
        print_error "Deno installation failed - binary not found at $deno_install/bin/deno"
        return 1
    fi

    if ! "$deno_install/bin/deno" --version &>/dev/null; then
        print_error "Deno installed but does not execute properly"
        return 1
    fi

    if is_root && [ "$(get_current_user)" != "$username" ]; then
        if ! grep -q "DENO_INSTALL.*$deno_install" "$user_home/.bashrc" 2>/dev/null; then
            echo "export DENO_INSTALL=\"$deno_install\"" >> "$user_home/.bashrc"
            echo "export PATH=\"\$DENO_INSTALL/bin:\$PATH\"" >> "$user_home/.bashrc"
        fi
    fi

    print_success "Deno installed and verified at $deno_install"
    return 0
}


confirm() {
    local prompt="$1"
    local force="${2:-false}"

    if [ "$force" = "true" ]; then
        return 0
    fi

    read -p "$prompt (yes/no): " REPLY
    [ "$REPLY" = "yes" ]
}


export -f print_success print_error print_warning print_info print_dry_run
export -f detect_os check_root is_root run_as_root
export -f get_user_home get_deno_install_path get_current_user
export -f user_exists create_user remove_user
export -f command_exists require_command directory_writable create_directory
export -f find_processes process_running stop_process stop_processes_matching
export -f safe_remove set_ownership
export -f install_deno
export -f confirm
