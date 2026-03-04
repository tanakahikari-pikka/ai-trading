#!/bin/bash
# Load Saxo Bank API credentials from .env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# Skip .env loading if credentials are already in environment (e.g. CI)
if [[ -z "$SAXO_ACCESS_TOKEN" ]]; then
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "Error: .env file not found at $ENV_FILE" >&2
        echo "Please copy .env.example to .env and configure your credentials." >&2
        exit 1
    fi

    # Load environment variables
    set -a
    source "$ENV_FILE"
    set +a
fi

# Validate required variables
if [[ -z "$SAXO_ACCESS_TOKEN" || "$SAXO_ACCESS_TOKEN" == "your_access_token_here" ]]; then
    echo "Error: SAXO_ACCESS_TOKEN is not configured in .env" >&2
    exit 1
fi

if [[ -z "$SAXO_BASE_URL" ]]; then
    export SAXO_BASE_URL="https://gateway.saxobank.com/sim/openapi"
fi
