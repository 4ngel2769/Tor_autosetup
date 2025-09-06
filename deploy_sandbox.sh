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
for var in SSH_USER SSH_HOST SSH_PORT SSH_KEY_PATH_V1 SSH_KEY_PATH_V2 SSH_DIR SCRIPT_NAME; do
    if [[ -z "${!var:-}" ]]; then
        error "Missing required .env variable: $var"
        exit 1
    fi
done

ready "Bundling script using bundler.sh..."
if [[ -x ./bundler.sh ]]; then
    info "Running: ./bundler.sh"
    ./bundler.sh
# elif [[ -x ./bundle.sh ]]; then
    # info "Running: ./bundle.sh"
    # ./bundle.sh
else
    error "No bundler found (bundle.sh or bundler.sh)"
    exit 1
fi

# --- Transfer to remote host ---
ready "Transferring $SCRIPT_NAME to $SSH_USER@$SSH_HOST:$SSH_DIR"
info "Using SSH key: $SSH_KEY_PATH_V2"
info "Running: scp -P $SSH_PORT -i $SSH_KEY_PATH_V2 -p $SCRIPT_NAME $SSH_USER@$SSH_HOST:$SSH_DIR"
scp -P "$SSH_PORT" -i "$SSH_KEY_PATH_V2" -p "$SCRIPT_NAME" "$SSH_USER@$SSH_HOST:$SSH_DIR"

success "Deployment complete!"
info "On target: chmod +x $SCRIPT_NAME && ./$SCRIPT_NAME --help"


### 🍉 wamterwelomn
### "Why is the rum gone?"
###  - Captain Jack Sparrow, The Curse of the Black Pearl (2003)

### End of deploy_sandbox.sh
