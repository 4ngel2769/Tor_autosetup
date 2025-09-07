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
required_vars=(SSH_USER SSH_HOST SSH_PORT SSH_DIR SCRIPT_NAME SCRIPT_URL_PATH SCRIPTS_BASE_DIR)
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error "Missing required .env variable: $var"
        exit 1
    fi
done

# --- Build script ---
ready "Bundling script using bundler.sh..."
if [[ -x ./bundler.sh ]]; then
    info "Running: ./bundler.sh"
    ./bundler.sh
else
    error "No bundler found (bundler.sh)"
    exit 1
fi

# --- Prepare SSH connection ---
SSH_OPTS=(-P "$SSH_PORT")
if [[ -n "${SSH_KEY_PATH_V2:-}" && -f "$SSH_KEY_PATH_V2" ]]; then
    info "Using SSH key file: $SSH_KEY_PATH_V2"
    SSH_OPTS+=(-i "$SSH_KEY_PATH_V2")
else
    warn "No SSH key file specified, trying ssh-agent..."
fi

# --- Create directory structure and deploy ---
ready "Setting up directory structure for script routing..."

# Create the target directory structure on the server
TARGET_SCRIPT_DIR="$SCRIPTS_BASE_DIR/$SCRIPT_DIR_PATH"
info "Creating directory: $TARGET_SCRIPT_DIR"

ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST" "mkdir -p '$TARGET_SCRIPT_DIR'"

# Transfer the bundled script to the correct location
ready "Transferring $SCRIPT_NAME to $SSH_USER@$SSH_HOST:$TARGET_SCRIPT_DIR"

# First transfer to temp location
scp "${SSH_OPTS[@]}" -p "$SCRIPT_NAME" "$SSH_USER@$SSH_HOST:/tmp/"

# Then move to final location and set up routing
ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST" "
    # Move script to target directory
    mv '/tmp/$SCRIPT_NAME' '$TARGET_SCRIPT_DIR/'
    
    # Make it executable
    chmod +x '$TARGET_SCRIPT_DIR/$SCRIPT_NAME'
    
    # Create a symlink for clean URL routing
    ln -sf '$TARGET_SCRIPT_DIR/$SCRIPT_NAME' '$SCRIPTS_BASE_DIR/$SCRIPT_URL_PATH'
    
    # Set proper permissions
    chmod +x '$SCRIPTS_BASE_DIR/$SCRIPT_URL_PATH'
    
    # Create backup with timestamp
    BACKUP_DIR='$SCRIPTS_BASE_DIR/.backups/$SCRIPT_URL_PATH'
    mkdir -p \"\$BACKUP_DIR\"
    cp '$TARGET_SCRIPT_DIR/$SCRIPT_NAME' \"\$BACKUP_DIR/\$(date +%Y%m%d_%H%M%S)_$SCRIPT_NAME\"
    
    # Keep only last 5 backups
    ls -t \"\$BACKUP_DIR\" | tail -n +6 | xargs -r -I {} rm \"\$BACKUP_DIR/{}\"
"

success "Deployment complete!"
info "Script deployed to: $TARGET_SCRIPT_DIR/$SCRIPT_NAME"
info "Clean URL available at: https://get.adev0.eu/$SCRIPT_URL_PATH"
info "Directory structure:"
info "  $SCRIPTS_BASE_DIR/"
info "  ├── $SCRIPT_URL_PATH (symlink to actual script)"
info "  ├── $SCRIPT_DIR_PATH/"
info "  │   └── $SCRIPT_NAME (actual script file)"
info "  └── .backups/$SCRIPT_URL_PATH/ (timestamped backups)"
info ""
info "Test with: curl -fsSL https://get.adev0.eu/$SCRIPT_URL_PATH | sudo bash"