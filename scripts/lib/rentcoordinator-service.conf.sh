#!/bin/bash

# RentCoordinator Service Configuration
# Sourced by init system scripts to get service-specific settings

export SERVICE_NAME="rentcoordinator"
export SERVICE_DESCRIPTION="RentCoordinator - Tenant coordination and rent tracking"
export SERVICE_DOCUMENTATION="https://github.com/rdeforest/RentCoordinator"

# These will be set by install.sh before calling init system
# Listed here for documentation purposes
: ${PREFIX:?PREFIX must be set}
: ${APP_USER:?APP_USER must be set}
: ${LOG_DIR:?LOG_DIR must be set}
: ${DB_PATH:?DB_PATH must be set}
: ${PORT:?PORT must be set}

# Computed paths
USER_HOME=$(get_user_home "$APP_USER")
DENO_INSTALL="$USER_HOME/.deno"
