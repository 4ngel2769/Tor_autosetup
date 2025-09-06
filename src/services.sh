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
            local temp_file; temp_file=$(mktemp)
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

    local temp_file; temp_file=$(mktemp)
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
            local service_name; service_name=$(basename "$current_dir")
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
                local created_date; created_date=$(date '+%Y-%m-%d %H:%M:%S')
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
    local created_date; created_date=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$service_name|$directory|$port|$onion_address|$website_dir|$status|$created_date" >> "$SERVICES_FILE"
    verbose_log "Added service to registry: $service_name"
}

# Function to update service in registry
update_service_in_registry() {
    local service_name="$1"
    local field="$2"
    local value="$3"

    local temp_file; temp_file=$(mktemp)

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

    local temp_file; temp_file=$(mktemp)
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
    
    # Check if port is listening on any interface
    if ! ss -tlpn 2>/dev/null | grep -q ":$port "; then
        echo "NOT_LISTENING"
        return 1
    fi
    
    # Try to curl the service with a short timeout - try both localhost and 0.0.0.0 binding
    if curl -s --connect-timeout "$timeout" --max-time "$timeout" "http://127.0.0.1:$port" >/dev/null 2>&1; then
        echo "RUNNING"
        return 0
    elif curl -s --connect-timeout "$timeout" --max-time "$timeout" "http://localhost:$port" >/dev/null 2>&1; then
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
    local pid_file; pid_file=$(get_pid_file "$service_name")
    local pid_status="UNKNOWN"
    local web_status="UNKNOWN"
    
    # Check PID file
    if [[ -f "$pid_file" ]]; then
        local pid; pid=$(cat "$pid_file" 2>/dev/null)
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
    print_colored "$(c_process)" "🚀 Starting test web server on port $TEST_SITE_PORT..."

    local service_name; service_name=$(basename "$HIDDEN_SERVICE_DIR")
    local pid_file; pid_file=$(get_pid_file "$service_name")

    # Double-check if port is available
    if ss -tlpn | grep -q ":$TEST_SITE_PORT "; then
        print_colored "$(c_warning)" "⚠️  Port $TEST_SITE_PORT became unavailable"
        print_colored "$(c_error)" "❌ Cannot start server - port conflict detected"
        print_colored "$(c_secondary)" "You can manually start it later with:"
        print_colored "$(c_text)" "cd $TEST_SITE_DIR && python3 server.py"
        sleep 3
        return 1
    fi
    
    # Start server in background and save PID
    cd "$TEST_SITE_DIR" || exit
    nohup python3 server.py > server.log 2>&1 &
    local server_pid=$!
    echo "$server_pid" > "$pid_file"
    
    print_colored "$(c_process)" "⏳ Checking if server started correctly..."
    sleep 3
    
    # Check if server started successfully
    if curl -s "http://127.0.0.1:$TEST_SITE_PORT" >/dev/null 2>&1; then
        print_colored "$(c_success)" "✅ Test web server started successfully on all interfaces"
        print_colored "$(c_success)" "   📡 Port: $TEST_SITE_PORT (PID: $server_pid)"
        print_colored "$(c_warning)" "   ⚠️  Accessible from local network (bypasses Tor anonymity)"
        verbose_log "Web server is running on port $TEST_SITE_PORT with PID $server_pid, bound to all interfaces"
        sleep 2
        return 0
    else
        print_colored "$(c_warning)" "⚠️  Server may not have started correctly"
        rm -f "$pid_file"
        print_colored "$(c_secondary)" "You can manually start it with:"
        print_colored "$(c_text)" "cd $TEST_SITE_DIR && python3 server.py"
        print_colored "$(c_secondary)" "Check logs at: $TEST_SITE_DIR/server.log"
        verbose_log "Web server failed to start on port $TEST_SITE_PORT"
        sleep 3
        return 1
    fi
}

# Function to stop web server for a specific service
stop_web_server() {
    local service_name="$1"
    local pid_file; pid_file=$(get_pid_file "$service_name")

    if [[ ! -f "$pid_file" ]]; then
        print_colored "$(c_warning)" "⚠️  No PID file found for service: $service_name"
        return 1
    fi

    local pid; pid=$(cat "$pid_file")

    if [[ -z "$pid" ]]; then
        print_colored "$(c_warning)" "⚠️  Invalid PID in file for service: $service_name"
        rm -f "$pid_file"
        return 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        if kill "$pid" 2>/dev/null; then
            print_colored "$(c_success)" "✅ Stopped web server for $service_name (PID: $pid)"
            rm -f "$pid_file"
            return 0
        else
            print_colored "$(c_error)" "❌ Failed to stop web server for $service_name (PID: $pid)"
            return 1
        fi
    else
        print_colored "$(c_warning)" "⚠️  Process $pid for $service_name is not running"
        rm -f "$pid_file"
        return 1
    fi
}

# Function to remove service from registry
remove_service_from_registry() {
    local service_name="$1"
    local temp_file; temp_file=$(mktemp)

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

    local temp_file; temp_file=$(mktemp)
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
        print_colored "$(c_success)" "✅ Removed hidden service configuration from torrc"
    else
        print_colored "$(c_warning)" "⚠️  Hidden service configuration not found in torrc (may have been manually removed)"
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
            print_colored "$(c_success)" "✅ Removed hidden service directory: $service_dir"
        else
            print_colored "$(c_error)" "❌ Failed to remove hidden service directory: $service_dir"
            return 1
        fi
    else
        print_colored "$(c_warning)" "⚠️  Hidden service directory not found: $service_dir"
    fi
    
    # Remove website directory if it exists (check both provided path and constructed path)
    local website_paths_to_check=()
    
    # Add the website_dir from registry if it exists
    if [[ -n "$website_dir" ]]; then
        website_paths_to_check+=("$website_dir")
    fi
    
    # Also check the standard constructed path for script-managed services
    if is_script_managed "$service_name"; then
        local constructed_website_dir="$TEST_SITE_BASE_DIR/$service_name"
        website_paths_to_check+=("$constructed_website_dir")
    fi
    
    # Remove duplicates and check each path
    local removed_website=false
    for website_path in "${website_paths_to_check[@]}"; do
        if [[ -d "$website_path" ]]; then
            verbose_log "Removing website directory: $website_path"
            if rm -rf "$website_path" 2>/dev/null; then
                print_colored "$(c_success)" "✅ Removed website directory: $website_path"
                removed_website=true
            else
                print_colored "$(c_warning)" "⚠️  Failed to remove website directory: $website_path"
            fi
        fi
    done
    
    if [[ "$removed_website" == false ]] && [[ ${#website_paths_to_check[@]} -gt 0 ]]; then
        print_colored "$(c_warning)" "⚠️  No website directories found to remove"
        verbose_log "Checked paths: ${website_paths_to_check[*]}"
    fi
    
    # Remove PID file if it exists
    local pid_file; pid_file=$(get_pid_file "$service_name")
    if [[ -f "$pid_file" ]]; then
        verbose_log "Removing PID file: $pid_file"
        rm -f "$pid_file"
        print_colored "$(c_success)" "✅ Removed PID file: $pid_file"
    fi
}

# Function to get local IP address for web server display
get_local_ip() {
    # Try multiple methods to get the local IP
    local ip=""
    
    # Method 1: Use ip route (most reliable on Linux)
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[^ ]+' | head -1 2>/dev/null)
    fi
    
    # Method 2: Use hostname -I as fallback
    if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # Method 3: Use ifconfig as fallback
    if [[ -z "$ip" ]] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig 2>/dev/null | grep -E "inet addr:|inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d: -f2)
    fi
    
    # Default to localhost if nothing found
    if [[ -z "$ip" ]] || [[ "$ip" == "127.0.0.1" ]]; then
        echo "localhost"
    else
        echo "$ip"
    fi
}

# Function to detect web server binding address
get_web_server_binding() {
    local port="$1"
    
    # Check what addresses the port is bound to using ss
    local binding_info
    binding_info=$(ss -tlpn 2>/dev/null | grep ":$port ")
    
    if [[ -z "$binding_info" ]]; then
        echo "NOT_BOUND"
        return 1
    fi
    
    # Check if bound to all interfaces (0.0.0.0 or *)
    if echo "$binding_info" | grep -qE "(0\.0\.0\.0:$port|\*:$port)"; then
        echo "ALL_INTERFACES"
        return 0
    # Check if bound to localhost only (127.0.0.1)
    elif echo "$binding_info" | grep -qE "127\.0\.0\.1:$port"; then
        echo "LOCALHOST_ONLY"
        return 0
    # Check for specific IP binding
    elif echo "$binding_info" | grep -qE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:$port"; then
        # Extract the specific IP
        local specific_ip
        specific_ip=$(echo "$binding_info" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo "SPECIFIC_IP:$specific_ip"
        return 0
    else
        echo "UNKNOWN"
        return 1
    fi
}

# Function to get web server display address with proper binding detection
get_web_server_display_address() {
    local port="$1"
    local binding_type
    
    binding_type=$(get_web_server_binding "$port")
    
    case "$binding_type" in
        "ALL_INTERFACES")
            # Server accepts connections from all interfaces
            local local_ip
            local_ip=$(get_local_ip)
            echo "$local_ip:$port"
            ;;
        "LOCALHOST_ONLY")
            # Server only accepts localhost connections
            echo "127.0.0.1:$port"
            ;;
        "SPECIFIC_IP:"*)
            # Server bound to specific IP
            local specific_ip="${binding_type#SPECIFIC_IP:}"
            echo "$specific_ip:$port"
            ;;
        *)
            echo "unknown:$port"
            ;;
    esac
}
