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

# Function to start server with system service integration
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
    
    # Ask user if they want to create a system service
    if [[ "$INIT_SYSTEM" != "none" ]]; then
        if ask_yes_no "Do you want to create a system service for easy management?"; then
            create_web_service "$service_name" "$TEST_SITE_DIR" "$TEST_SITE_PORT"
            
            if ask_yes_no "Do you want to enable the service to start automatically?"; then
                manage_web_service "enable" "$service_name"
                print_colored "$(c_success)" "✅ Service enabled for automatic startup"
            fi
            
            # Start the service
            print_colored "$(c_process)" "🚀 Starting web service..."
            if manage_web_service "start" "$service_name"; then
                print_colored "$(c_success)" "✅ Web service started successfully"
                print_colored "$(c_success)" "   📡 Port: $TEST_SITE_PORT"
                print_colored "$(c_warning)" "   ⚠️  Accessible from local network (bypasses Tor anonymity)"
                print_colored "$(c_secondary)" "   🔧 Manage with: systemctl {start|stop|restart|status} tor-web-${service_name}"
                verbose_log "Web service created and started: tor-web-${service_name}"
                sleep 3
                return 0
            else
                print_colored "$(c_error)" "❌ Failed to start web service"
                print_colored "$(c_warning)" "Falling back to manual startup..."
            fi
        else
            print_colored "$(c_info)" "ℹ️  Creating manual web server (no system service)"
        fi
    fi
    
    # Fallback to manual startup (original method)
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
        print_colored "$(c_secondary)" "   🔧 Manage manually with PID file: $pid_file"
        verbose_log "Web server is running on port $TEST_SITE_PORT with PID $server_pid (manual mode)"
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

# Function to create system service for web server
create_web_service() {
    local service_name="$1"
    local website_dir="$2"
    local port="$3"
    
    print_colored "$(c_process)" "🔧 Creating system service for $service_name..."
    
    case "$INIT_SYSTEM" in
        "systemd")
            create_systemd_service "$service_name" "$website_dir" "$port"
            ;;
        "openrc")
            create_openrc_service "$service_name" "$website_dir" "$port"
            ;;
        "runit")
            create_runit_service "$service_name" "$website_dir" "$port"
            ;;
        "sysv")
            create_sysv_service "$service_name" "$website_dir" "$port"
            ;;
        "s6")
            create_s6_service "$service_name" "$website_dir" "$port"
            ;;
        "dinit")
            create_dinit_service "$service_name" "$website_dir" "$port"
            ;;
        *)
            print_colored "$(c_warning)" "⚠️  No supported init system - using manual PID management only"
            return 1
            ;;
    esac
}

# Function to create systemd service
create_systemd_service() {
    local service_name="$1"
    local website_dir="$2"
    local port="$3"
    
    local service_file="/etc/systemd/system/tor-web-${service_name}.service"
    
    verbose_log "Creating systemd service file: $service_file"
    
    cat > "$service_file" << EOF
[Unit]
Description=Tor Hidden Service Web Server - $service_name
After=network.target tor.service
Wants=tor.service

[Service]
Type=simple
User=debian-tor
Group=debian-tor
WorkingDirectory=$website_dir
ExecStart=/usr/bin/python3 $website_dir/server.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
Environment=PORT=$port

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$website_dir
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    
    print_colored "$(c_success)" "✅ Created systemd service: tor-web-${service_name}"
    verbose_log "Systemd service created and daemon reloaded"
}

# Function to create OpenRC service
create_openrc_service() {
    local service_name="$1"
    local website_dir="$2"
    local port="$3"
    
    local service_file="/etc/init.d/tor-web-${service_name}"
    
    verbose_log "Creating OpenRC service file: $service_file"
    
    cat > "$service_file" << EOF
#!/sbin/openrc-run

name="Tor Web Server - $service_name"
description="Tor Hidden Service Web Server for $service_name"

command="/usr/bin/python3"
command_args="$website_dir/server.py"
command_background="yes"
pidfile="/run/tor-web-${service_name}.pid"
command_user="debian-tor:debian-tor"

directory="$website_dir"

depend() {
    need net
    after tor
}

start_pre() {
    checkpath --directory --owner debian-tor:debian-tor --mode 0755 /run
}
EOF

    chmod +x "$service_file"
    
    print_colored "$(c_success)" "✅ Created OpenRC service: tor-web-${service_name}"
    verbose_log "OpenRC service created and made executable"
}

# Function to create runit service
create_runit_service() {
    local service_name="$1"
    local website_dir="$2"
    local port="$3"
    
    local service_dir="/etc/sv/tor-web-${service_name}"
    
    verbose_log "Creating runit service directory: $service_dir"
    
    mkdir -p "$service_dir"
    
    cat > "$service_dir/run" << EOF
#!/bin/sh
exec chpst -u debian-tor:debian-tor python3 $website_dir/server.py 2>&1
EOF

    cat > "$service_dir/log/run" << EOF
#!/bin/sh
exec svlogd -tt ./
EOF

    chmod +x "$service_dir/run"
    mkdir -p "$service_dir/log"
    chmod +x "$service_dir/log/run"
    
    print_colored "$(c_success)" "✅ Created runit service: tor-web-${service_name}"
    verbose_log "Runit service created with logging"
}

# Function to create SysV service
create_sysv_service() {
    local service_name="$1"
    local website_dir="$2"
    local port="$3"
    
    local service_file="/etc/init.d/tor-web-${service_name}"
    
    verbose_log "Creating SysV init script: $service_file"
    
    cat > "$service_file" << EOF
#!/bin/bash
### BEGIN INIT INFO
# Provides:          tor-web-${service_name}
# Required-Start:    \$network \$remote_fs tor
# Required-Stop:     \$network \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Tor Hidden Service Web Server - $service_name
# Description:       Python web server for Tor hidden service $service_name
### END INIT INFO

NAME="tor-web-${service_name}"
DAEMON="/usr/bin/python3"
DAEMON_ARGS="$website_dir/server.py"
PIDFILE="/var/run/\$NAME.pid"
USER="debian-tor"
WORKDIR="$website_dir"

. /lib/lsb/init-functions

case "\$1" in
    start)
        echo "Starting \$NAME"
        start-stop-daemon --start --quiet --pidfile \$PIDFILE --make-pidfile --background --chuid \$USER --chdir \$WORKDIR --exec \$DAEMON -- \$DAEMON_ARGS
        ;;
    stop)
        echo "Stopping \$NAME"
        start-stop-daemon --stop --quiet --pidfile \$PIDFILE
        rm -f \$PIDFILE
        ;;
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    status)
        status_of_proc -p \$PIDFILE "\$DAEMON" "\$NAME" && exit 0 || exit \$?
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOF

    chmod +x "$service_file"
    
    # Try to add to runlevels
    if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d "tor-web-${service_name}" defaults
    elif command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add "tor-web-${service_name}"
    fi
    
    print_colored "$(c_success)" "✅ Created SysV service: tor-web-${service_name}"
    verbose_log "SysV service created and added to runlevels"
}

# Function to create s6 service
create_s6_service() {
    local service_name="$1"
    local website_dir="$2"
    local port="$3"
    
    local service_dir="/etc/s6/sv/tor-web-${service_name}"
    
    verbose_log "Creating s6 service directory: $service_dir"
    
    mkdir -p "$service_dir"
    
    cat > "$service_dir/run" << EOF
#!/bin/sh
exec s6-setuidgid debian-tor python3 $website_dir/server.py
EOF

    chmod +x "$service_dir/run"
    
    print_colored "$(c_success)" "✅ Created s6 service: tor-web-${service_name}"
    verbose_log "s6 service created"
}

# Function to create dinit service
create_dinit_service() {
    local service_name="$1"
    local website_dir="$2"
    local port="$3"
    
    local service_file="/etc/dinit.d/tor-web-${service_name}"
    
    verbose_log "Creating dinit service file: $service_file"
    
    cat > "$service_file" << EOF
type = process
command = /usr/bin/python3 $website_dir/server.py
working-dir = $website_dir
socket-listen = 127.0.0.1:$port
depends-on = tor
run-as = debian-tor
EOF

    print_colored "$(c_success)" "✅ Created dinit service: tor-web-${service_name}"
    verbose_log "dinit service created"
}

# Function to manage web service (start/stop/enable/disable)
manage_web_service() {
    local action="$1"
    local service_name="$2"
    
    local full_service_name="tor-web-${service_name}"
    
    verbose_log "Managing web service: $action $full_service_name"
    
    case "$INIT_SYSTEM" in
        "systemd")
            case "$action" in
                "start") systemctl start "$full_service_name" ;;
                "stop") systemctl stop "$full_service_name" ;;
                "restart") systemctl restart "$full_service_name" ;;
                "enable") systemctl enable "$full_service_name" ;;
                "disable") systemctl disable "$full_service_name" ;;
                "status") systemctl status "$full_service_name" ;;
            esac
            ;;
        "openrc")
            case "$action" in
                "start") rc-service "$full_service_name" start ;;
                "stop") rc-service "$full_service_name" stop ;;
                "restart") rc-service "$full_service_name" restart ;;
                "enable") rc-update add "$full_service_name" default ;;
                "disable") rc-update del "$full_service_name" default ;;
                "status") rc-service "$full_service_name" status ;;
            esac
            ;;
        "runit")
            case "$action" in
                "start") sv start "$full_service_name" ;;
                "stop") sv stop "$full_service_name" ;;
                "restart") sv restart "$full_service_name" ;;
                "enable") ln -sf "/etc/sv/$full_service_name" "/var/service/" ;;
                "disable") rm -f "/var/service/$full_service_name" ;;
                "status") sv status "$full_service_name" ;;
            esac
            ;;
        "sysv")
            case "$action" in
                "start") service "$full_service_name" start ;;
                "stop") service "$full_service_name" stop ;;
                "restart") service "$full_service_name" restart ;;
                "enable") 
                    if command -v update-rc.d >/dev/null 2>&1; then
                        update-rc.d "$full_service_name" enable
                    elif command -v chkconfig >/dev/null 2>&1; then
                        chkconfig "$full_service_name" on
                    fi
                    ;;
                "disable")
                    if command -v update-rc.d >/dev/null 2>&1; then
                        update-rc.d "$full_service_name" disable
                    elif command -v chkconfig >/dev/null 2>&1; then
                        chkconfig "$full_service_name" off
                    fi
                    ;;
                "status") service "$full_service_name" status ;;
            esac
            ;;
        "s6")
            case "$action" in
                "start") s6-svc -u "/etc/s6/sv/$full_service_name" ;;
                "stop") s6-svc -d "/etc/s6/sv/$full_service_name" ;;
                "restart") s6-svc -r "/etc/s6/sv/$full_service_name" ;;
                "status") s6-svstat "/etc/s6/sv/$full_service_name" ;;
            esac
            ;;
        "dinit")
            case "$action" in
                "start") dinitctl start "$full_service_name" ;;
                "stop") dinitctl stop "$full_service_name" ;;
                "restart") dinitctl restart "$full_service_name" ;;
                "enable") dinitctl enable "$full_service_name" ;;
                "disable") dinitctl disable "$full_service_name" ;;
                "status") dinitctl status "$full_service_name" ;;
            esac
            ;;
        *)
            print_colored "$(c_warning)" "⚠️  No supported init system - cannot manage service"
            return 1
            ;;
    esac
}

# Function to remove web service
remove_web_service() {
    local service_name="$1"
    local full_service_name="tor-web-${service_name}"
    
    verbose_log "Removing web service: $full_service_name"
    
    # Stop service first
    manage_web_service "stop" "$service_name" 2>/dev/null || true
    manage_web_service "disable" "$service_name" 2>/dev/null || true
    
    case "$INIT_SYSTEM" in
        "systemd")
            rm -f "/etc/systemd/system/${full_service_name}.service"
            systemctl daemon-reload
            ;;
        "openrc")
            rm -f "/etc/init.d/${full_service_name}"
            ;;
        "runit")
            rm -rf "/etc/sv/${full_service_name}"
            rm -f "/var/service/${full_service_name}"
            ;;
        "sysv")
            rm -f "/etc/init.d/${full_service_name}"
            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d "${full_service_name}" remove 2>/dev/null || true
            elif command -v chkconfig >/dev/null 2>&1; then
                chkconfig --del "${full_service_name}" 2>/dev/null || true
            fi
            ;;
        "s6")
            rm -rf "/etc/s6/sv/${full_service_name}"
            ;;
        "dinit")
            rm -f "/etc/dinit.d/${full_service_name}"
            ;;
    esac
    
    print_colored "$(c_success)" "✅ Removed web service: $full_service_name"
}

# Function to check if web service exists
web_service_exists() {
    local service_name="$1"
    local full_service_name="tor-web-${service_name}"
    
    case "$INIT_SYSTEM" in
        "systemd")
            [[ -f "/etc/systemd/system/${full_service_name}.service" ]]
            ;;
        "openrc")
            [[ -f "/etc/init.d/${full_service_name}" ]]
            ;;
        "runit")
            [[ -d "/etc/sv/${full_service_name}" ]]
            ;;
        "sysv")
            [[ -f "/etc/init.d/${full_service_name}" ]]
            ;;
        "s6")
            [[ -d "/etc/s6/sv/${full_service_name}" ]]
            ;;
        "dinit")
            [[ -f "/etc/dinit.d/${full_service_name}" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to get web service status
get_web_service_status() {
    local service_name="$1"
    local full_service_name="tor-web-${service_name}"
    
    if ! web_service_exists "$service_name"; then
        echo "NO_SERVICE"
        return 1
    fi
    
    case "$INIT_SYSTEM" in
        "systemd")
            if systemctl is-active "$full_service_name" >/dev/null 2>&1; then
                echo "RUNNING"
            else
                echo "STOPPED"
            fi
            ;;
        "openrc")
            if rc-service "$full_service_name" status >/dev/null 2>&1; then
                echo "RUNNING"
            else
                echo "STOPPED"
            fi
            ;;
        "runit")
            local status=$(sv status "$full_service_name" 2>/dev/null)
            if echo "$status" | grep -q "run"; then
                echo "RUNNING"
            else
                echo "STOPPED"
            fi
            ;;
        "sysv")
            if service "$full_service_name" status >/dev/null 2>&1; then
                echo "RUNNING"
            else
                echo "STOPPED"
            fi
            ;;
        "s6")
            local status=$(s6-svstat "/etc/s6/sv/$full_service_name" 2>/dev/null)
            if echo "$status" | grep -q "up"; then
                echo "RUNNING"
            else
                echo "STOPPED"
            fi
            ;;
        "dinit")
            local status=$(dinitctl status "$full_service_name" 2>/dev/null)
            if echo "$status" | grep -q "STARTED"; then
                echo "RUNNING"
            else
                echo "STOPPED"
            fi
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}
