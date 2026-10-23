#!/usr/bin/env bash
#
# Installs the Node version .nvmrc names, makes it nvm's default, and installs
# production dependencies. Run as rent-coordinator by the instance bootstrap
# (CloudFormation UserData) and by step 6 of the in-place upgrade in
# docs/deployment.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

. "$HOME/.nvm/nvm.sh" --no-use
nvm install
nvm alias default "$(cat .nvmrc)"
npm ci --omit=dev
