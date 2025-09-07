#!/bin/bash

set -euo pipefail

# --- Helper functions ---
status()   { echo -e "🔧 $*"; }
info()     { echo -e "📡 $*"; }
ready()    { echo -e "🚀 $*"; }
success()  { echo -e "✅ $*"; }
error()    { echo -e "❌ $*" >&2; }
warn()     { echo -e "⚠️  $*"; }

# --- .env ---
status "Loading .env variables..."
if [[ ! -f .env ]]; then
    error ".env file not found!"
    exit 1
fi

while IFS='=' read -r key value; do
    key="${key%%*( )}"
    key="${key//$'\r'/}"
    value="${value%%*( )}"
    value="${value//$'\r'/}"
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        export "$key"="$value"
    fi
done < .env

# --- Check required variables ---
status "Checking required variables..."
for var in SSH_USER SSH_HOST SSH_PORT SSH_DIR SCRIPT_NAME; do
    if [[ -z "${!var:-}" ]]; then
        error "Missing required .env variable: $var"
        exit 1
    fi
done

ready "Bundling script using bundler.sh..."
if [[ -x ./bundler.sh ]]; then
    info "Running: ./bundler.sh"
    ./bundler.sh
else
    error "No bundler found (bundler.sh)"
    exit 1
fi

# --- Transfer to remote host ---
ready "Transferring $SCRIPT_NAME to $SSH_USER@$SSH_HOST:$SSH_DIR"

if [[ -n "${SSH_KEY_PATH_V2:-}" && -f "$SSH_KEY_PATH_V2" ]]; then
    info "Using SSH key file: $SSH_KEY_PATH_V2"
    scp -P "$SSH_PORT" -i "$SSH_KEY_PATH_V2" -p "$SCRIPT_NAME" "$SSH_USER@$SSH_HOST:$SSH_DIR"
else
    warn "No SSH key file specified, trying ssh-agent..."
    scp -P "$SSH_PORT" -p "$SCRIPT_NAME" "$SSH_USER@$SSH_HOST:$SSH_DIR"
fi

success "Deployment complete!"
info "On target: chmod +x $SCRIPT_NAME && ./$SCRIPT_NAME --help"
