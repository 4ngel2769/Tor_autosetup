#!/bin/bash

# shellcheck source=utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# services.sh - Service management functions
# This file contains all functions related to managing Tor hidden services

# Function to check if service is script-managed
is_script_managed() {
    local service_name="$1"
    # Script-managed services follow pattern: hidden_service_[random]
    [[ "$service_name" =~ ^hidden_service_[a-z0-9]{9}$ ]]
}

# Function to get PID file path for a service
get_pid_file() {
    local service_name="$1"
    echo "$TORSTP_DIR/${service_name}.pid"
}

# Function to initialize service tracking
init_service_tracking() {
    verbose_log "Initializing service tracking..."
    
    # Create .torstp directory if it doesn't exist
    if [[ ! -d "$TORSTP_DIR" ]]; then
        mkdir -p "$TORSTP_DIR"
        verbose_log "Created .torstp directory: $TORSTP_DIR"
    fi
    
    # Create or update services file
    if [[ ! -f "$SERVICES_FILE" ]]; then
        cat > "$SERVICES_FILE" << 'EOF'
# Tor Hidden Services Registry
# Format: SERVICE_NAME|DIRECTORY|PORT|ONION_ADDRESS|WEBSITE_DIR|STATUS|CREATED_DATE
# Status: ACTIVE, INACTIVE, ERROR
EOF
        verbose_log "Created services registry file: $SERVICES_FILE"
    else
        # Check if header exists, if not add it
        if ! grep -q "^# Tor Hidden Services Registry" "$SERVICES_FILE" 2>/dev/null; then
            local temp_file=$(mktemp)
            cat > "$temp_file" << 'EOF'
# Tor Hidden Services Registry
# Format: SERVICE_NAME|DIRECTORY|PORT|ONION_ADDRESS|WEBSITE_DIR|STATUS|CREATED_DATE
# Status: ACTIVE, INACTIVE, ERROR
EOF
            cat "$SERVICES_FILE" >> "$temp_file"
            mv "$temp_file" "$SERVICES_FILE"
            verbose_log "Added header to existing services registry file"
        fi
    fi
    
    # Scan existing services and update registry
    scan_existing_services
}

# Function to scan existing services from torrc
scan_existing_services() {
    verbose_log "Scanning existing services from torrc..."
    
    if [[ ! -f "$TORRC_FILE" ]]; then
        verbose_log "No torrc file found"
        return 0
    fi
    
    local temp_file=$(mktemp)
    local current_dir=""
    local current_port=""
    
    # Read torrc and find hidden service configurations
    while read -r line; do
        if [[ "$line" =~ ^HiddenServiceDir[[:space:]]+(.+)$ ]]; then
            current_dir="${BASH_REMATCH[1]}"
            current_dir="${current_dir%/}"  # Remove trailing slash
        elif [[ "$line" =~ ^HiddenServicePort[[:space:]]+[0-9]+[[:space:]]+127\.0\.0\.1:([0-9]+)$ ]] && [[ -n "$current_dir" ]]; then
            current_port="${BASH_REMATCH[1]}"
            
            # Extract service name from directory
            local service_name=$(basename "$current_dir")
            local onion_address=""
            local status="INACTIVE"
            
            # Try to read onion address
            if [[ -f "$current_dir/hostname" ]]; then
                onion_address=$(cat "$current_dir/hostname" 2>/dev/null || echo "")
                if [[ -n "$onion_address" ]]; then
                    status="ACTIVE"
                fi
            fi
            
            # Check if service already exists in registry
            if ! grep -q "^$service_name|" "$SERVICES_FILE" 2>/dev/null; then
                local created_date=$(date '+%Y-%m-%d %H:%M:%S')
                local website_dir=""
                # Only set website_dir for script-managed services
                if is_script_managed "$service_name"; then
                    website_dir="$TEST_SITE_BASE_DIR/$service_name"
                fi
                echo "$service_name|$current_dir|$current_port|$onion_address|$website_dir|$status|$created_date" >> "$temp_file"
                verbose_log "Found existing service: $service_name ($current_dir:$current_port) [Managed: $(is_script_managed "$service_name" && echo "YES" || echo "NO")]"
            fi
            
            current_dir=""
            current_port=""
        fi
    done < "$TORRC_FILE"
    
    # Append new services to registry
    if [[ -s "$temp_file" ]]; then
        cat "$temp_file" >> "$SERVICES_FILE"
        verbose_log "Added $(wc -l < "$temp_file") existing services to registry"
    fi
    
    rm -f "$temp_file"
}

# Function to add service to registry
add_service_to_registry() {
    local service_name="$1"
    local directory="$2"
    local port="$3"
    local onion_address="$4"
    local website_dir="$5"
    local status="$6"
    local created_date=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "$service_name|$directory|$port|$onion_address|$website_dir|$status|$created_date" >> "$SERVICES_FILE"
    verbose_log "Added service to registry: $service_name"
}

# Function to update service in registry
update_service_in_registry() {
    local service_name="$1"
    local field="$2"
    local value="$3"
    
    local temp_file=$(mktemp)
    
    while IFS='|' read -r name dir port onion website status created; do
        if [[ "$name" == "$service_name" ]]; then
            case "$field" in
                "onion_address") onion="$value" ;;
                "status") status="$value" ;;
                "website_dir") website="$value" ;;
                "port") port="$value" ;;
            esac
        fi
        echo "$name|$dir|$port|$onion|$website|$status|$created"
    done < "$SERVICES_FILE" > "$temp_file"
    
    mv "$temp_file" "$SERVICES_FILE"
    verbose_log "Updated service $service_name: $field=$value"
}

# Function to sync registry with actual service status
sync_registry_status() {
    verbose_log "Syncing registry with actual service status..."
    
    if [[ ! -f "$SERVICES_FILE" ]]; then
        verbose_log "No services file found, skipping sync"
        return 0
    fi
    
    local temp_file=$(mktemp)
    local updated=false
    
    # Read the services file line by line
    while IFS='|' read -r name dir port onion website status created || [[ -n "$name" ]]; do
        # Skip comments and empty lines
        if [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]]; then
            echo "$name|$dir|$port|$onion|$website|$status|$created" >> "$temp_file"
            continue
        fi
        
        verbose_log "Processing service: $name"
        
        local new_status="$status"
        local new_onion="$onion"
        
        # Check if hostname file exists and read onion address
        if [[ -f "$dir/hostname" ]]; then
            local actual_onion
            actual_onion=$(cat "$dir/hostname" 2>/dev/null | tr -d '\n' | tr -d ' ')
            
            if [[ -n "$actual_onion" ]]; then
                new_status="ACTIVE"
                new_onion="$actual_onion"
                if [[ "$status" != "ACTIVE" ]] || [[ "$onion" != "$actual_onion" ]]; then
                    updated=true
                    verbose_log "Updated $name: status=$new_status, onion=$actual_onion"
                fi
            fi
        else
            # Check if service is supposed to be active but hostname doesn't exist
            if [[ "$status" == "ACTIVE" ]]; then
                new_status="INACTIVE"
                new_onion=""
                updated=true
                verbose_log "Updated $name: status=INACTIVE (hostname missing)"
            fi
        fi
        
        echo "$name|$dir|$port|$new_onion|$website|$new_status|$created" >> "$temp_file"
        
    done < "$SERVICES_FILE"
    
    mv "$temp_file" "$SERVICES_FILE"
    
    if [[ "$updated" == true ]]; then
        verbose_log "Registry status synchronized"
    else
        verbose_log "Registry status already up to date"
    fi
}

# Function to check if web server is actually running and responding
check_web_server_status() {
    local port="$1"
    local timeout=3
    
    # Check if port is listening
    if ! ss -tlpn 2>/dev/null | grep -q ":$port "; then
        echo "NOT_LISTENING"
        return 1
    fi
    
    # Try to curl the service with a short timeout
    if curl -s --connect-timeout "$timeout" --max-time "$timeout" "http://127.0.0.1:$port" >/dev/null 2>&1; then
        echo "RUNNING"
        return 0
    else
        echo "NOT_RESPONDING"
        return 1
    fi
}

# Function to get comprehensive web server status
get_web_server_status() {
    local service_name="$1"
    local port="$2"
    local website_dir="$3"
    
    # For non-script-managed services, check if port is active
    if ! is_script_managed "$service_name"; then
        if [[ -n "$port" ]]; then
            check_web_server_status "$port"
        else
            echo "N/A"
        fi
        return
    fi
    
    # For script-managed services, check both PID and actual response
    local pid_file=$(get_pid_file "$service_name")
    local pid_status="UNKNOWN"
    local web_status="UNKNOWN"
    
    # Check PID file
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            pid_status="PID_ALIVE"
        else
            pid_status="PID_DEAD"
            rm -f "$pid_file" 2>/dev/null
        fi
    else
        pid_status="NO_PID"
    fi
    
    # Check actual web server response
    if [[ -n "$port" ]]; then
        web_status=$(check_web_server_status "$port")
    fi
    
    # Determine final status
    case "$web_status" in
        "RUNNING")
            echo "RUNNING"
            ;;
        "NOT_LISTENING")
            echo "STOPPED"
            ;;
        "NOT_RESPONDING")
            if [[ "$pid_status" == "PID_ALIVE" ]]; then
                echo "UNRESPONSIVE"
            else
                echo "STOPPED"
            fi
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

# Function to start server with PID tracking
start_test_server() {
    print_colored "$BLUE" "🚀 Starting test web server on port $TEST_SITE_PORT..."
    
    local service_name=$(basename "$HIDDEN_SERVICE_DIR")
    local pid_file=$(get_pid_file "$service_name")
    
    # Double-check if port is available
    if ss -tlpn | grep -q ":$TEST_SITE_PORT "; then
        print_colored "$YELLOW" "⚠️  Port $TEST_SITE_PORT became unavailable"
        print_colored "$RED" "❌ Cannot start server - port conflict detected"
        print_colored "$CYAN" "You can manually start it later with:"
        print_colored "$WHITE" "cd $TEST_SITE_DIR && python3 server.py"
        return 1
    fi
    
    # Start server in background and save PID
    cd "$TEST_SITE_DIR" || exit
    nohup python3 server.py > server.log 2>&1 &
    local server_pid=$!
    echo "$server_pid" > "$pid_file"
    
    sleep 2
    
    # Check if server started successfully
    if curl -s "http://127.0.0.1:$TEST_SITE_PORT" >/dev/null 2>&1; then
        print_colored "$GREEN" "✅ Test web server started successfully on port $TEST_SITE_PORT (PID: $server_pid)"
        verbose_log "Web server is running on port $TEST_SITE_PORT with PID $server_pid"
        return 0
    else
        print_colored "$YELLOW" "⚠️  Server may not have started correctly"
        rm -f "$pid_file"
        print_colored "$CYAN" "You can manually start it with:"
        print_colored "$WHITE" "cd $TEST_SITE_DIR && python3 server.py"
        print_colored "$CYAN" "Check logs at: $TEST_SITE_DIR/server.log"
        verbose_log "Web server failed to start on port $TEST_SITE_PORT"
        return 1
    fi
}

# Function to stop web server for a specific service
stop_web_server() {
    local service_name="$1"
    local pid_file=$(get_pid_file "$service_name")
    
    if [[ ! -f "$pid_file" ]]; then
        print_colored "$YELLOW" "⚠️  No PID file found for service: $service_name"
        return 1
    fi
    
    local pid=$(cat "$pid_file")
    
    if [[ -z "$pid" ]]; then
        print_colored "$YELLOW" "⚠️  Invalid PID in file for service: $service_name"
        rm -f "$pid_file"
        return 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        if kill "$pid" 2>/dev/null; then
            print_colored "$GREEN" "✅ Stopped web server for $service_name (PID: $pid)"
            rm -f "$pid_file"
            return 0
        else
            print_colored "$RED" "❌ Failed to stop web server for $service_name (PID: $pid)"
            return 1
        fi
    else
        print_colored "$YELLOW" "⚠️  Process $pid for $service_name is not running"
        rm -f "$pid_file"
        return 1
    fi
}

# Function to remove service from registry
remove_service_from_registry() {
    local service_name="$1"
    local temp_file=$(mktemp)
    
    # Copy all lines except the one we want to remove
    while IFS='|' read -r name dir port onion website status created; do
        if [[ "$name" != "$service_name" ]]; then
            echo "$name|$dir|$port|$onion|$website|$status|$created"
        fi
    done < "$SERVICES_FILE" > "$temp_file"
    
    mv "$temp_file" "$SERVICES_FILE"
    verbose_log "Removed service $service_name from registry"
}

# Function to remove hidden service from torrc
remove_from_torrc() {
    local service_dir="$1"
    local service_name="$2"
    
    verbose_log "Removing hidden service configuration from torrc..."
    
    # Create backup of torrc before modification
    if [[ -f "$TORRC_FILE" ]]; then
        cp "$TORRC_FILE" "$TORRC_FILE.backup.$(date +%s)"
        verbose_log "Created backup of torrc"
    fi
    
    local temp_file=$(mktemp)
    local in_service_block=false
    local service_removed=false
    
    while IFS= read -r line; do
        # Check if we're entering the service block
        if [[ "$line" =~ ^#.*Hidden.*Service.*Configuration.*-.*$service_name$ ]]; then
            in_service_block=true
            service_removed=true
            verbose_log "Found service block for $service_name, removing..."
            continue
        fi
        
        # Check if we're in the service block
        if [[ "$in_service_block" == true ]]; then
            if [[ "$line" =~ ^HiddenServiceDir[[:space:]]+$service_dir/?$ ]]; then
                verbose_log "Removing HiddenServiceDir line"
                continue
            elif [[ "$line" =~ ^HiddenServicePort.*$ ]]; then
                verbose_log "Removing HiddenServicePort line"
                continue
            elif [[ -z "$line" ]]; then
                # Empty line might be end of block, but continue to next line to check
                continue
            elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
                # Whitespace only line
                continue
            elif [[ "$line" =~ ^# ]] || [[ "$line" =~ ^[A-Za-z] ]]; then
                # Hit another comment or config line, end of our block
                in_service_block=false
                echo "$line" >> "$temp_file"
            else
                # Unknown line in block, skip it
                continue
            fi
        else
            # Not in service block, keep the line
            echo "$line" >> "$temp_file"
        fi
    done < "$TORRC_FILE"
    
    mv "$temp_file" "$TORRC_FILE"
    
    if [[ "$service_removed" == true ]]; then
        print_colored "$GREEN" "✅ Removed hidden service configuration from torrc"
    else
        print_colored "$YELLOW" "⚠️  Hidden service configuration not found in torrc (may have been manually removed)"
    fi
}

# Function to safely remove directories
remove_service_directories() {
    local service_dir="$1"
    local website_dir="$2"
    local service_name="$3"
    
    verbose_log "Removing service directories..."
    
    # Remove hidden service directory
    if [[ -d "$service_dir" ]]; then
        verbose_log "Removing hidden service directory: $service_dir"
        if rm -rf "$service_dir" 2>/dev/null; then
            print_colored "$GREEN" "✅ Removed hidden service directory: $service_dir"
        else
            print_colored "$RED" "❌ Failed to remove hidden service directory: $service_dir"
            return 1
        fi
    else
        print_colored "$YELLOW" "⚠️  Hidden service directory not found: $service_dir"
    fi
    
    # Remove website directory if it exists
    if [[ -n "$website_dir" ]] && [[ -d "$website_dir" ]]; then
        verbose_log "Removing website directory: $website_dir"
        if rm -rf "$website_dir" 2>/dev/null; then
            print_colored "$GREEN" "✅ Removed website directory: $website_dir"
        else
            print_colored "$YELLOW" "⚠️  Failed to remove website directory: $website_dir"
        fi
    fi
    
    # Remove PID file if it exists
    local pid_file=$(get_pid_file "$service_name")
    if [[ -f "$pid_file" ]]; then
        verbose_log "Removing PID file: $pid_file"
        rm -f "$pid_file"
    fi
}
