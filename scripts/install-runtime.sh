#!/usr/bin/env bash
#
# Installs the Node version .nvmrc names, makes it nvm's default, and installs
# production dependencies. Called by the instance bootstrap (UserData) and the
# in-place upgrade in docs/deployment.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

. "$HOME/.nvm/nvm.sh" --no-use
nvm install
nvm alias default "$(cat .nvmrc)"
npm ci --omit=dev
