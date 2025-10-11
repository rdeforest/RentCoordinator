#!/bin/bash

# Install git hooks for RentCoordinator
# This script creates symlinks from .git/hooks/ to the hooks in this directory

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "  $1"; }

# Get the repository root (one level up from hooks/)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/hooks"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"

# Verify we're in a git repository
if [ ! -d "$GIT_HOOKS_DIR" ]; then
    echo "Error: Not a git repository or .git/hooks directory not found"
    exit 1
fi

echo "Installing git hooks..."
echo

# Install each hook
for hook in pre-push pre-commit; do
    HOOK_SRC="$HOOKS_DIR/$hook"
    HOOK_DST="$GIT_HOOKS_DIR/$hook"

    # Skip if hook doesn't exist in our hooks directory
    if [ ! -f "$HOOK_SRC" ]; then
        continue
    fi

    # Make source hook executable
    chmod +x "$HOOK_SRC"

    # Check if hook already exists
    if [ -e "$HOOK_DST" ] || [ -L "$HOOK_DST" ]; then
        if [ -L "$HOOK_DST" ]; then
            # It's a symlink, remove it
            rm "$HOOK_DST"
            print_info "Removed old symlink: $hook"
        else
            # It's a regular file, back it up
            mv "$HOOK_DST" "$HOOK_DST.backup"
            print_info "Backed up existing hook: $hook -> $hook.backup"
        fi
    fi

    # Create symlink
    ln -s "$HOOK_SRC" "$HOOK_DST"
    print_success "Installed hook: $hook"
done

echo
print_success "Git hooks installed successfully!"
echo
echo "Installed hooks:"
echo "  • pre-push: Runs build and linting before push"
echo
echo "To uninstall, remove symlinks from .git/hooks/ or run:"
echo "  rm .git/hooks/pre-push"
