#!/bin/bash

if [[ $EUID -ne 0 && ( -z "${BASH_SOURCE-}" || "${BASH_SOURCE[0]-}" == "${0-}" || "$0" == "bash" ) ]]; then
    echo "🔒 This script requires root privileges. Prompting for sudo password..."
    exec sudo -E bash "$0" "$@"
fi

# main.sh - Entry point and CLI logic
# This file contains the main script logic, CLI parsing, and orchestration

set -euo pipefail

# Determine script directory for sourcing other files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required modules
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"
# shellcheck source=funcs.sh  
source "$SCRIPT_DIR/funcs.sh"
# shellcheck source=services.sh
source "$SCRIPT_DIR/services.sh"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -v, --verbose           Enable verbose output for debugging"
    echo "  -l, --list              List all available hidden services with status"
    echo "  -t, --test              Test all services (Tor + web server status)"
    echo "  -s, --stop SERVICE_NAME Stop web server for specific service"
    echo "  -r, --remove SERVICE_NAME Remove hidden service(s) PERMANENTLY"
    echo "  -h, --help              Show this help message"
    echo "  -A, --about             Show detailed information about this script"
    echo "  -V, --version           Show version information"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                                  # Create a new hidden service"
    echo "  $0 --version                        # Show version information"
    echo "  $0 --about                          # Show detailed about information"
    echo "  $0 --list                           # List all services with real-time status"
    echo "  $0 --test                           # Test all services comprehensively"
    echo "  $0 --stop hidden_service_abc123def  # Stop web server for specific service"
    echo "  $0 --remove hidden_service_abc123def # PERMANENTLY remove single hidden service"
    echo ""
    echo "BULK REMOVAL:"
    echo "  $0 -r 'service1,service2,service3'     # Remove multiple services (comma-separated)"
    echo "  $0 -r 'service1 service2 service3'     # Remove multiple services (space-separated)"
    echo "  $0 --remove 'service1, service2'       # Remove multiple services (mixed separators)"
    echo ""
    echo "COMBINED FLAGS:"
    echo "  $0 -Vl                             # Verbose listing"
    echo "  $0 -rV 'service1,service2'         # Verbose bulk removal"
    echo "  $0 -Vt                             # Verbose testing"
    echo ""
    echo "For detailed information about this script, run: $0 --about"
    exit 0
}

# Function to list available services
list_services() {
    print_colored "$(c_info)" "🔍 Checking service status..."
    
    # Sync registry before listing
    sync_registry_status
    
    print_colored "$(c_secondary)" "📋 Available Tor Hidden Services:"
    echo
    
    if [[ ! -f "$SERVICES_FILE" ]] || [[ ! -s "$SERVICES_FILE" ]]; then
        print_colored "$(c_warning)" "No services found."
        return 0
    fi
    
    # Updated header
    printf "%-30s %-6s %-40s %-8s %-10s %-12s %-25s\n" "SERVICE NAME" "PORT" "ONION ADDRESS" "STATUS" "MANAGED" "WEB SERVER" "WEB ADDRESS"
    print_colored "$(c_text)" "───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
    
    while IFS='|' read -r name dir port onion website status system_service created; do
        # Skip comments and empty lines
        [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
        
        # Handle old format (no system_service field)
        if [[ -z "$created" ]] && [[ -n "$system_service" ]]; then
            created="$system_service"
            system_service=""
        fi
        
        # Handle onion address - darker color, no underline, but still clickable
        local display_onion=""
        local onion_display_color=""
        
        if [[ -z "$onion" ]]; then
            display_onion="<not generated>"
            onion_display_color="$(c_muted)"
        elif [[ ${#onion} -gt 35 ]]; then
            display_onion="${onion:0:32}..."
            onion_display_color="$(c_text)"  # Darker color for onion addresses
        else
            display_onion="$onion"
            onion_display_color="$(c_text)"  # Darker color for onion addresses
        fi
        
        # Status color using dynamic colors
        local status_color_bg=""
        case "$status" in
            "ACTIVE") status_color_bg="$(c_success)" ;;
            "INACTIVE") status_color_bg="$(c_error)" ;;
            "ERROR") status_color_bg="$(c_error)" ;;
            *) status_color_bg="$(c_text)" ;;
        esac
        
        # Managed color
        local managed="NO"
        local managed_color_bg=""
        if is_script_managed "$name"; then
            if [[ -n "$system_service" ]]; then
                managed="SYS"  # System service managed
                managed_color_bg="$(c_success)"
            else
                managed="YES"  # Script managed (manual)
                managed_color_bg="$(c_text)"
            fi
        else
            managed_color_bg="$(c_muted)"
        fi
        
        # Get comprehensive web server status
        local web_status=$(get_web_server_status "$name" "$port" "$website")
        local web_color_bg=""
        
        case "$web_status" in
            "RUNNING") web_color_bg="$(c_success)" ;;
            "STOPPED") web_color_bg="$(c_warning)" ;;
            "UNRESPONSIVE") web_color_bg="$(c_error)" ;;
            "NOT_LISTENING") web_color_bg="$(c_error)" ;;
            "NOT_RESPONDING") web_color_bg="$(c_error)" ;;
            "SERVICE_UP_PORT_DOWN") web_color_bg="$(c_warning)" ;;
            "N/A") web_color_bg="$(c_text)" ;;
            *) web_color_bg="$(c_text)" ;;
        esac
        
        # Determine web address with proper binding detection - only show for running servers
        local web_address_raw=""
        local web_address_formatted=""
        
        if [[ "$web_status" == "RUNNING" ]] && [[ -n "$port" ]]; then
            local display_address
            display_address=$(get_web_server_display_address "$port")
            
            # Raw address for spacing calculation
            web_address_raw="http://${display_address}"
            # Formatted address with color and underline
            web_address_formatted="$(c_highlight)${UNDERLINE}http://${display_address}${RESET}"
            
            verbose_log "Web server binding for $name:$port - Address: $display_address"
        else
            web_address_raw="<not running>"
            web_address_formatted="$(c_muted)<not running>${NC}"
        fi
        
        # Print the row - using printf for alignment but with direct echo for the web address
        printf "$(c_primary)%-30s${NC} $(c_blurple)%-6s${NC} ${onion_display_color}%-40s${NC} ${status_color_bg}%-8s${NC} ${managed_color_bg}%-10s${NC} ${web_color_bg}%-12s${NC} " "$name" "$port" "$display_onion" "$status" "$managed" "$web_status"
        
        # Handle web address separately to preserve formatting
        if [[ "$web_status" == "RUNNING" ]] && [[ -n "$port" ]]; then
            echo -e "${web_address_formatted}"
        else
            echo -e "$(c_muted)<not running>${NC}"
        fi
        
        # Add verbose information if enabled
        if [[ "$VERBOSE" == true ]]; then
            verbose_log "Service $name details:"
            verbose_log "  Directory: $dir"
            verbose_log "  Port: $port"
            verbose_log "  Website: $website"
            verbose_log "  System Service: ${system_service:-'none'}"
            verbose_log "  Hostname file: $dir/hostname"
            verbose_log "  Web address: $web_address_raw"
            if [[ -n "$port" ]]; then
                local binding_type
                binding_type=$(get_web_server_binding "$port")
                verbose_log "  Binding type: $binding_type"
            fi
            if [[ -f "$dir/hostname" ]]; then
                verbose_log "  Hostname content: $(cat "$dir/hostname" 2>/dev/null || echo 'ERROR reading file')"
            fi
        fi
        
    done < "$SERVICES_FILE"
    echo
    
    print_colored "$(c_secondary)" "Legend:"
    print_colored "$(c_text)" "• STATUS: Tor hidden service status (ACTIVE/INACTIVE/ERROR)"
    print_colored "$(c_text)" "• MANAGED: Created by this script"
    print_colored "$(c_muted)" "  - NO: External service"
    print_colored "$(c_text)" "  - YES: Script managed (manual)"
    print_colored "$(c_success)" "  - SYS: System service managed"
    print_colored "$(c_text)" "• WEB SERVER: Local web server status"
    print_colored "$(c_success)" "  - RUNNING: Server responding to requests"
    print_colored "$(c_warning)" "  - STOPPED: No server running on port"
    print_colored "$(c_error)" "  - UNRESPONSIVE: Process exists but not responding"
    print_colored "$(c_error)" "  - NOT_LISTENING: Port not listening"
    print_colored "$(c_text)" "  - N/A: Not applicable (external service)"
    print_colored "$(c_text)" "• ONION ADDRESS: .onion domain for the hidden service"
    print_colored "$(c_text)" "• WEB ADDRESS: Local network address (when server is running)"
    echo -e "  - $(c_highlight)${UNDERLINE}Underlined links${RESET} show actual binding address"
    print_colored "$(c_info)" "  - 127.0.0.1:PORT for localhost-only servers"
    print_colored "$(c_info)" "  - [machine-ip]:PORT for servers accepting external connections"
    print_colored "$(c_muted)" "  - <not running> when web server is not active"
    echo
    print_colored "$(c_warning)" "⚠️  Note: 127.0.0.1 access preserves anonymity, machine IP bypasses Tor!"
}

# Function to test all services with real-time status
test_all_services() {
    print_colored "$(c_info)" "🧪 Testing all hidden services..."
    
    # Initialize service tracking first
    init_service_tracking
    
    # Debug: Check if services file exists and has content
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_colored "$(c_warning)" "❌ Services registry file not found: $SERVICES_FILE"
        print_colored "$(c_secondary)" "💡 Try running: $0 to create a new service first"
        return 1
    fi
    
    # Debug: Show file content (only in verbose mode)
    if [[ "$VERBOSE" == true ]]; then
        print_colored "$(c_secondary)" "[DEBUG] Services file content:"
        cat "$SERVICES_FILE"
        echo "---"
    fi
    
    # Sync registry status
    sync_registry_status
    
    verbose_log "Starting service counting phase..."
    
    # Count actual services (excluding header comments)
    local service_count=0
    local line_count=0
    
    while IFS='|' read -r name dir port onion website status created; do
        ((line_count++))
        verbose_log "Reading line $line_count: name='$name'"
        
        # Skip comments and empty lines
        if [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]]; then
            verbose_log "Skipping line $line_count: $name (comment/empty)"
            continue
        fi
        
        ((service_count++))
        verbose_log "Found service $service_count: $name"
        
    done < "$SERVICES_FILE"
    
    verbose_log "Service counting completed: $service_count services found from $line_count lines"
    print_colored "$(c_secondary)" "📊 Found $service_count services in registry (from $line_count total lines)"
    
    if [[ $service_count -eq 0 ]]; then
        print_colored "$(c_warning)" "No active services found to test."
        print_colored "$(c_secondary)" "💡 Create a new service by running: $0"
        return 0
    fi
    
    verbose_log "Starting testing phase..."
    
    local tested=0
    local active=0
    local responsive=0
    
    # Test each service - using a temp file approach
    verbose_log "Beginning service testing loop..."

    local temp_services; temp_services=$(mktemp)
    # First, extract just the service lines to a temp file
    while IFS='|' read -r name dir port onion website status created; do
        # Skip comments and empty lines
        if [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]]; then
            continue
        fi
        echo "$name|$dir|$port|$onion|$website|$status|$created" >> "$temp_services"
    done < "$SERVICES_FILE"
    
    verbose_log "Created temp services file with $(wc -l < "$temp_services") lines"
    
    # Now test each service from the temp file
    while IFS='|' read -r name dir port onion website status created; do
        ((tested++))
        verbose_log "Testing service $tested: $name"
        
        print_colored "$(c_secondary)" "🔍 Testing service $tested/$service_count: $name"
        
        # Debug service details
        verbose_log "Service details: name=$name, dir=$dir, port=$port, status=$status"
        
        # Check Tor service status
        if [[ "$status" == "ACTIVE" ]]; then
            ((active++))
            if [[ -n "$onion" ]]; then
                print_colored "$(c_success)" "  ✅ Tor service: ACTIVE ($onion)"
            else
                print_colored "$(c_success)" "  ✅ Tor service: ACTIVE (onion address not synced)"
            fi
        else
            print_colored "$(c_warning)" "  ⚠️  Tor service: $status"
        fi
        
        # Check web server if port is available
        if [[ -n "$port" ]]; then
            print_colored "$(c_info)" "  🌐 Testing web server on port $port..."
            verbose_log "Calling check_web_server_status for port $port"

            local web_status=$(check_web_server_status "$port")
            verbose_log "Web status result: $web_status"
            
            case "$web_status" in
                "RUNNING")
                    ((responsive++))
                    print_colored "$(c_success)" "  ✅ Web server: RUNNING on port $port"
                    ;;
                "NOT_LISTENING")
                    print_colored "$(c_warning)" "  ⚠️  Web server: NOT LISTENING on port $port"
                    ;;
                "NOT_RESPONDING")
                    print_colored "$(c_error)" "  ❌ Web server: NOT RESPONDING on port $port"
                    ;;
                *)
                    print_colored "$(c_error)" "  ❌ Web server: UNKNOWN STATUS ($web_status)"
                    ;;
            esac
        else
            print_colored "$(c_text)" "  ℹ️  Web server: No port configured"
        fi
        
        echo
        
    done < "$temp_services"
    
    # Clean up temp file
    rm -f "$temp_services"
    
    verbose_log "Testing phase completed"
    
    # Final summary
    print_colored "$(c_secondary)" "📊 Test Summary:"
    print_colored "$(c_text)" "• Total services tested: $tested"
    print_colored "$(c_text)" "• Active Tor services: $active"
    print_colored "$(c_text)" "• Responsive web servers: $responsive"
    
    if [[ $tested -eq 0 ]]; then
        print_colored "$(c_warning)" "⚠️  No services were actually tested - check registry file"
    fi
    
    verbose_log "test_all_services function completed successfully"
}

# Function to stop web server by service name
stop_service_web_server() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        print_colored "$(c_error)" "❌ Service name required"
        return 1
    fi
    
    # Check if service exists in registry
    if ! grep -q "^$service_name|" "$SERVICES_FILE" 2>/dev/null; then
        print_colored "$(c_error)" "❌ Service '$service_name' not found"
        return 1
    fi
    
    # Check if service is script-managed
    if ! is_script_managed "$service_name"; then
        print_colored "$(c_error)" "❌ Service '$service_name' is not managed by this script"
        return 1
    fi
    
    stop_web_server "$service_name"
}

# Function to preview what will be removed
preview_removal() {
    local service_name="$1"
    local service_dir="$2"
    local website_dir="$3"
    local port="$4"
    
    print_colored "$(c_secondary)" "📋 Preview of what will be removed:"
    echo
    print_colored "$(c_text)" "Directories to be deleted:"
    print_colored "$(c_error)" "  • Tor directory: $service_dir"
    
    # Check for website directories (both from registry and constructed path)
    local website_paths_to_remove=()
    if [[ -n "$website_dir" ]] && [[ -d "$website_dir" ]]; then
        website_paths_to_remove+=("$website_dir")
    fi
    
    # Also check constructed path for script-managed services
    if is_script_managed "$service_name"; then
        local constructed_website_dir="$TEST_SITE_BASE_DIR/$service_name"
        if [[ -d "$constructed_website_dir" ]] && [[ "$constructed_website_dir" != "$website_dir" ]]; then
            website_paths_to_remove+=("$constructed_website_dir")
        fi
    fi
    
    if [[ ${#website_paths_to_remove[@]} -gt 0 ]]; then
        for website_path in "${website_paths_to_remove[@]}"; do
            print_colored "$(c_error)" "  • Website directory: $website_path"
        done
    else
        print_colored "$(c_text)" "  • No website directories found"
    fi
    
    echo
    print_colored "$(c_text)" "Torrc configuration lines to be removed:"
    if grep -q "# Hidden Service Configuration - $service_name" "$TORRC_FILE" 2>/dev/null; then
        print_colored "$(c_error)" "  • # Hidden Service Configuration - $service_name"
        print_colored "$(c_error)" "  • HiddenServiceDir $service_dir/"
        print_colored "$(c_error)" "  • HiddenServicePort 80 0.0.0.0:$port"
    else
        print_colored "$(c_warning)" "  • No torrc configuration found for this service"
    fi
    
    echo
    print_colored "$(c_text)" "Registry entry to be removed:"
    print_colored "$(c_error)" "  • Service record for '$service_name'"
    
    if is_script_managed "$service_name"; then
        echo
        print_colored "$(c_text)" "Additional cleanup:"
        print_colored "$(c_error)" "  • PID files and process tracking"
    fi
}

# Function to remove a hidden service completely
remove_hidden_service() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        print_colored "$(c_warning)" "Usage: $0 --remove SERVICE_NAME"
        print_colored "$(c_secondary)" "Available services:"
        if [[ -f "$SERVICES_FILE" ]]; then
            while IFS='|' read -r name dir port onion website status created; do
                [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
                print_colored "$(c_text)" "  • $name"
            done < "$SERVICES_FILE"
        else
            print_colored "$(c_warning)" "  No services found"
        fi
        return 1
    fi
    
    # Check if service exists in registry
    if ! grep -q "^$service_name|" "$SERVICES_FILE" 2>/dev/null; then
        print_colored "$(c_error)" "❌ Service '$service_name' not found in registry"
        print_colored "$(c_secondary)" "Available services:"
        if [[ -f "$SERVICES_FILE" ]]; then
            while IFS='|' read -r name dir port onion website status created; do
                [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
                print_colored "$(c_text)" "  • $name"
            done < "$SERVICES_FILE"
        else
            print_colored "$(c_warning)" "  No services found"
        fi
        return 1
    fi
    
    # Get service details from registry
    local service_info
    service_info=$(grep "^$service_name|" "$SERVICES_FILE" 2>/dev/null)
    
    if [[ -z "$service_info" ]]; then
        print_colored "$(c_error)" "❌ Could not retrieve service information"
        return 1
    fi
    
    IFS='|' read -r name dir port onion website status created <<< "$service_info"
    
    # Display service information
    clear
    print_header
    print_colored "$(c_error)" "⚠️  DANGER: PERMANENT REMOVAL WARNING ⚠️"
    echo
    print_colored "$(c_warning)" "You are about to PERMANENTLY remove the following hidden service:"
    echo
    print_colored "$(c_text)" "Service Name: $name"
    print_colored "$(c_text)" "Onion Address: ${onion:-'<not generated>'}"
    print_colored "$(c_text)" "Port: ${port:-'N/A'}"
    print_colored "$(c_text)" "Hidden Service Directory: $dir"
    print_colored "$(c_text)" "Website Directory: ${website:-'N/A'}"
    print_colored "$(c_text)" "Created: ${created:-'Unknown'}"
    echo
    
    # Show preview of what will be removed
    preview_removal "$service_name" "$dir" "$website" "$port"
    
    echo
    print_colored "$(c_error)" "⚠️  THIS ACTION CANNOT BE UNDONE! ⚠️"
    print_colored "$(c_error)" "⚠️  The .onion address will be LOST FOREVER! ⚠️"
    print_colored "$(c_error)" "⚠️  All website files will be DELETED! ⚠️"
    echo
    
    # Give user time to read the information before showing the first prompt
    print_colored "$(c_warning)" "📖 Please review the above information carefully..."
    print_colored "$(c_secondary)" "Press any key when ready to continue..."
    read -n 1 -s
    
    # Multiple confirmation prompts
    if ! ask_yes_no "Are you ABSOLUTELY SURE you want to remove this hidden service?"; then
        print_colored "$(c_success)" "✅ Removal cancelled - service preserved"
        return 0
    fi
    
    if ! ask_yes_no "This will PERMANENTLY DELETE the .onion address. Continue?"; then
        print_colored "$(c_success)" "✅ Removal cancelled - service preserved"
        return 0
    fi
    
    if ! ask_yes_no "FINAL WARNING: Remove hidden service '$service_name' forever?"; then
        print_colored "$(c_success)" "✅ Removal cancelled - service preserved"
        return 0
    fi
    
    # Stop web server if it's running
    if is_script_managed "$service_name"; then
        print_colored "$(c_process)" "🛑 Stopping web server..."
        stop_web_server "$service_name" 2>/dev/null || true
    fi
    
    print_colored "$(c_process)" "🗑️ Starting removal process..."
    
    # Remove from torrc
    remove_from_torrc "$dir" "$service_name"
    
    # Remove directories
    remove_service_directories "$dir" "$website" "$service_name"
    
    # Remove from registry
    remove_service_from_registry "$service_name"
    
    # Restart Tor to apply changes
    print_colored "$(c_process)" "🔄 Restarting Tor service to apply changes..."
    if systemctl restart tor 2>/dev/null; then
        print_colored "$(c_success)" "✅ Tor service restarted successfully"
    else
        print_colored "$(c_warning)" "⚠️  Please manually restart Tor service: sudo systemctl restart tor"
    fi
    
    print_colored "$(c_success)" "✅ Hidden service '$service_name' has been completely removed"
    print_colored "$(c_warning)" "💡 The .onion address is now permanently inaccessible"
    
    return 0
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
    
    # For script-managed services, check system service first, then fallback to PID
    if web_service_exists "$service_name"; then
        local service_status=$(get_web_service_status "$service_name")
        case "$service_status" in
            "RUNNING")
                # Double-check with actual port test
                if [[ -n "$port" ]]; then
                    local web_status=$(check_web_server_status "$port")
                    if [[ "$web_status" == "RUNNING" ]]; then
                        echo "RUNNING"
                    else
                        echo "SERVICE_UP_PORT_DOWN"
                    fi
                else
                    echo "RUNNING"
                fi
                ;;
            "STOPPED")
                echo "STOPPED"
                ;;
            "NO_SERVICE")
                # Fallback to PID-based checking
                get_web_server_status_pid "$service_name" "$port" "$website_dir"
                ;;
            *)
                echo "UNKNOWN"
                ;;
        esac
    else
        # Fallback to original PID-based method
        get_web_server_status_pid "$service_name" "$port" "$website_dir"
    fi
}

# Function to get web server status using PID method (fallback)
get_web_server_status_pid() {
    local service_name="$1"
    local port="$2"
    local website_dir="$3"
    
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

# Function to parse individual character flags (for combined flags like -Vl)
parse_char_flag() {
    local char="$1"
    case "$char" in
        'V')
            VERBOSE=true
            print_colored "$(c_success)" "✅ Verbose mode enabled"
            ;;
        'v')
            show_version
            exit 0
            ;;
        'l')
            FLAG_LIST=true
            ;;
        't')
            FLAG_TEST=true
            ;;
        's')
            FLAG_STOP=true
            ;;
        'r')
            FLAG_REMOVE=true
            ;;
        'h')
            show_usage
            ;;
        *)
            print_colored "$(c_error)" "❌ Unknown flag: -$char"
            show_usage
            ;;
    esac
}

# Function to parse service names from a comma/space-separated string
# Parse command line arguments with support for combined flags
parse_service_names() {
    local input="$1"
    verbose_log "parse_service_names called with input: '$input'"
    
    # Remove quotes if present
    input="${input%\"}"
    input="${input#\"}"
    verbose_log "After quote removal: '$input'"
    
    # Replace commas with spaces and normalize whitespace
    input=$(echo "$input" | tr ',' ' ' | tr -s ' ')
    verbose_log "After comma/space normalization: '$input'"
    
    # Split into array
    local -a service_names=()
    read -ra service_names <<< "$input"
    verbose_log "Split into ${#service_names[@]} parts: ${service_names[*]}"
    
    # Remove empty elements and print valid service names
    for service in "${service_names[@]}"; do
        service=$(echo "$service" | xargs)  # Trim whitespace
        verbose_log "Processing service part: '$service'"
        if [[ -n "$service" ]]; then
            verbose_log "Outputting valid service: '$service'"
            echo "$service"
        else
            verbose_log "Skipping empty service part"
        fi
    done
}

# Function to validate service names exist in registry
validate_service_names() {
    local -a service_names=("$@")
    local -a valid_services=()
    local -a invalid_services=()
    
    for service_name in "${service_names[@]}"; do
        if grep -q "^$service_name|" "$SERVICES_FILE" 2>/dev/null; then
            valid_services+=("$service_name")
        else
            invalid_services+=("$service_name")
        fi
    done
    
    # Print results
    if [[ ${#invalid_services[@]} -gt 0 ]]; then
        print_colored "$(c_error)" "❌ Invalid service names found:" >&2
        for invalid in "${invalid_services[@]}"; do
            print_colored "$(c_text)" "  • $invalid" >&2
        done
        echo >&2
    fi
    
    if [[ ${#valid_services[@]} -gt 0 ]]; then
        print_colored "$(c_success)" "✅ Valid services to remove:" >&2
        for valid in "${valid_services[@]}"; do
            print_colored "$(c_text)" "  • $valid" >&2
        done
        echo >&2
    fi
    
    # Return the valid services
    printf '%s\n' "${valid_services[@]}"
}


# Function to show bulk removal preview
preview_bulk_removal() {
    local -a service_names=("$@")
    local total_count=${#service_names[@]}
    
    print_colored "$(c_secondary)" "📋 Bulk Removal Preview ($total_count services):"
    echo
    
    local total_dirs=0
    local total_websites=0
    local system_services_count=0
    
    for service_name in "${service_names[@]}"; do
        verbose_log "Processing service for preview: $service_name"
        
        local service_info
        service_info=$(grep "^$service_name|" "$SERVICES_FILE" 2>/dev/null)
        
        if [[ -n "$service_info" ]]; then
            verbose_log "Found service info: $service_info"
            
            # Parse service info (handle both old and new formats)
            local name dir port onion website status system_service created
            IFS='|' read -r name dir port onion website status system_service created <<< "$service_info"
            
            # Handle old format (no system_service field)
            if [[ -z "$created" ]] && [[ -n "$system_service" ]]; then
                created="$system_service"
                system_service=""
            fi
            
            verbose_log "Parsed service: name=$name, dir=$dir, port=$port, website=$website"
            
            print_colored "$(c_primary)" "Service: $service_name"
            print_colored "$(c_text)" "  • Onion: ${onion:-'<not generated>'}"
            print_colored "$(c_text)" "  • Port: ${port:-'N/A'}"
            
            if [[ -n "$dir" ]]; then
                print_colored "$(c_error)" "  • Will remove: $dir"
                ((total_dirs++))
            else
                print_colored "$(c_warning)" "  • No directory found"
            fi
            
            # Check for website directories
            local website_paths_to_remove=()
            if [[ -n "$website" ]] && [[ -d "$website" ]]; then
                website_paths_to_remove+=("$website")
                verbose_log "Found website directory from registry: $website"
            fi
            
            # Also check constructed path for script-managed services
            if is_script_managed "$service_name"; then
                local constructed_website_dir="$TEST_SITE_BASE_DIR/$service_name"
                verbose_log "Checking constructed website dir: $constructed_website_dir"
                if [[ -d "$constructed_website_dir" ]] && [[ "$constructed_website_dir" != "$website" ]]; then
                    website_paths_to_remove+=("$constructed_website_dir")
                    verbose_log "Added constructed website directory: $constructed_website_dir"
                fi
            fi
            
            if [[ ${#website_paths_to_remove[@]} -gt 0 ]]; then
                for website_path in "${website_paths_to_remove[@]}"; do
                    print_colored "$(c_error)" "  • Will remove: $website_path"
                    ((total_websites++))
                done
            fi
            
            # Check for system service
            local has_system_service=false
            if [[ -n "$system_service" ]]; then
                verbose_log "Checking system service from registry: $system_service"
                if web_service_exists "$service_name"; then
                    print_colored "$(c_error)" "  • Will remove system service: $system_service"
                    ((system_services_count++))
                    has_system_service=true
                fi
            fi
            
            # Fallback check for system service if not tracked in registry
            if [[ "$has_system_service" == false ]] && web_service_exists "$service_name"; then
                print_colored "$(c_error)" "  • Will remove system service: tor-web-${service_name}"
                ((system_services_count++))
                verbose_log "Found untracked system service: tor-web-${service_name}"
            fi
            
            echo
        else
            print_colored "$(c_error)" "Service: $service_name (NOT FOUND IN REGISTRY)"
            print_colored "$(c_warning)" "  • This service will be skipped"
            echo
        fi
    done
    
    print_colored "$(c_secondary)" "📊 Bulk Removal Summary:"
    print_colored "$(c_text)" "• Services to remove: $total_count"
    print_colored "$(c_text)" "• Hidden service directories: $total_dirs"
    print_colored "$(c_text)" "• Website directories: $total_websites"
    print_colored "$(c_text)" "• System services: $system_services_count"
    echo
    
    print_colored "$(c_error)" "⚠️  ALL .onion addresses will be LOST FOREVER!"
    print_colored "$(c_error)" "⚠️  ALL website files will be DELETED!"
    print_colored "$(c_error)" "⚠️  THIS ACTION CANNOT BE UNDONE!"
}

# Function to remove multiple hidden services
remove_hidden_services_bulk() {
    local service_names_input="$1"
    
    verbose_log "remove_hidden_services_bulk called with: '$service_names_input'"
    
    if [[ -z "$service_names_input" ]]; then
        print_colored "$(c_error)" "❌ No service names provided"
        print_colored "$(c_warning)" "Usage examples:"
        print_colored "$(c_text)" "  $0 -r 'service1,service2,service3'"
        print_colored "$(c_text)" "  $0 -r 'service1 service2 service3'"
        print_colored "$(c_text)" "  $0 --remove 'service1, service2, service3'"
        return 1
    fi
    
    verbose_log "Parsing service names from: $service_names_input"
    
    # Parse service names
    local -a parsed_services=()
    while IFS= read -r service_name; do
        if [[ -n "$service_name" ]]; then
            parsed_services+=("$service_name")
            verbose_log "Parsed service name: '$service_name'"
        fi
    done < <(parse_service_names "$service_names_input")
    
    verbose_log "Total parsed services: ${#parsed_services[@]}"
    
    if [[ ${#parsed_services[@]} -eq 0 ]]; then
        print_colored "$(c_error)" "❌ No valid service names found in input"
        print_colored "$(c_secondary)" "Input was: '$service_names_input'"
        return 1
    fi
    
    verbose_log "Parsed ${#parsed_services[@]} service names: ${parsed_services[*]}"
    
    # Check if it's actually a single service (fallback to original function)
    if [[ ${#parsed_services[@]} -eq 1 ]]; then
        verbose_log "Single service detected, using original removal function"
        remove_hidden_service "${parsed_services[0]}"
        return $?
    fi
    
    print_colored "$(c_info)" "🔍 Validating service names..."
    
    # Validate service names
    local -a valid_services=()
    while IFS= read -r service_name; do
        if [[ -n "$service_name" ]]; then
            valid_services+=("$service_name")
            verbose_log "Valid service: '$service_name'"
        fi
    done < <(validate_service_names "${parsed_services[@]}")
    
    verbose_log "Total valid services: ${#valid_services[@]}"
    
    if [[ ${#valid_services[@]} -eq 0 ]]; then
        print_colored "$(c_error)" "❌ No valid services found to remove"
        print_colored "$(c_secondary)" "Available services:"
        if [[ -f "$SERVICES_FILE" ]]; then
            while IFS='|' read -r name dir port onion website status created; do
                [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
                print_colored "$(c_text)" "  • $name"
            done < "$SERVICES_FILE"
        else
            print_colored "$(c_warning)" "  No services found"
        fi
        return 1
    fi
    
    # Show bulk removal preview
    verbose_log "Showing bulk removal preview for ${#valid_services[@]} services"
    clear
    print_header
    print_colored "$(c_error)" "⚠️  DANGER: BULK REMOVAL WARNING ⚠️"
    echo
    
    # Call preview function with error handling
    if ! preview_bulk_removal "${valid_services[@]}"; then
        print_colored "$(c_error)" "❌ Failed to generate removal preview"
        verbose_log "preview_bulk_removal function failed"
        return 1
    fi
    
    # Multiple confirmation prompts
    echo
    print_colored "$(c_warning)" "📖 Please review the above information carefully..."
    print_colored "$(c_secondary)" "Press any key when ready to continue..."
    read -n 1 -s
    echo
    
    if ! ask_yes_no "Are you ABSOLUTELY SURE you want to remove ${#valid_services[@]} hidden services?"; then
        print_colored "$(c_success)" "✅ Bulk removal cancelled - all services preserved"
        return 0
    fi
    
    if ! ask_yes_no "This will PERMANENTLY DELETE ${#valid_services[@]} .onion addresses. Continue?"; then
        print_colored "$(c_success)" "✅ Bulk removal cancelled - all services preserved"
        return 0
    fi
    
    if ! ask_yes_no "FINAL WARNING: Remove ${#valid_services[@]} hidden services forever?"; then
        print_colored "$(c_success)" "✅ Bulk removal cancelled - all services preserved"
        return 0
    fi
    
    # Start bulk removal process
    print_colored "$(c_process)" "🗑️ Starting bulk removal process..."
    echo
    
    local removed_count=0
    local failed_count=0
    local -a failed_services=()
    
    # IMPORTANT: Remove set -e temporarily to prevent script exit on individual service failures
    set +e
    
    for service_name in "${valid_services[@]}"; do
        local current_num=$((removed_count + failed_count + 1))
        print_colored "$(c_secondary)" "[$current_num/${#valid_services[@]}] Processing: $service_name"
        
        verbose_log "Processing removal for service: $service_name"
        
        # Get service details from registry
        local service_info
        service_info=$(grep "^$service_name|" "$SERVICES_FILE" 2>/dev/null)
        
        if [[ -n "$service_info" ]]; then
            local name dir port onion website status system_service created
            IFS='|' read -r name dir port onion website status system_service created <<< "$service_info"
            
            # Handle old format (no system_service field)
            if [[ -z "$created" ]] && [[ -n "$system_service" ]]; then
                created="$system_service"
                system_service=""
            fi
            
            verbose_log "Removing service: $service_name (dir: $dir, website: $website)"
            
            # Track success of individual operations
            local operations_success=true
            
            # Stop web server if it's running
            if is_script_managed "$service_name"; then
                print_colored "$(c_process)" "  🛑 Stopping web server..."
                if ! stop_web_server "$service_name" 2>/dev/null; then
                    verbose_log "Warning: Could not stop web server for $service_name (not critical)"
                fi
            fi
            
            # Remove from torrc (not critical if it fails)
            print_colored "$(c_process)" "  📝 Removing from torrc..."
            if ! remove_from_torrc "$dir" "$service_name"; then
                verbose_log "Warning: Could not remove from torrc for $service_name (not critical)"
            fi
            
            # Remove directories and services (this is the critical operation)
            print_colored "$(c_process)" "  🗂️ Removing directories..."
            if remove_service_directories "$dir" "$website" "$service_name"; then
                # Remove from registry
                print_colored "$(c_process)" "  📋 Removing from registry..."
                if remove_service_from_registry "$service_name"; then
                    print_colored "$(c_success)" "  ✅ Successfully removed: $service_name"
                    ((removed_count++))
                else
                    print_colored "$(c_error)" "  ❌ Failed to remove from registry: $service_name"
                    failed_services+=("$service_name")
                    ((failed_count++))
                fi
            else
                print_colored "$(c_error)" "  ❌ Failed to remove directories: $service_name"
                failed_services+=("$service_name")
                ((failed_count++))
            fi
        else
            print_colored "$(c_error)" "  ❌ Service info not found: $service_name"
            failed_services+=("$service_name")
            ((failed_count++))
        fi
        
        echo
    done
    
    # Re-enable set -e
    set -e
    
    # Restart Tor once after all removals
    if [[ $removed_count -gt 0 ]]; then
        print_colored "$(c_process)" "🔄 Restarting Tor service to apply all changes..."
        if systemctl restart tor 2>/dev/null; then
            print_colored "$(c_success)" "✅ Tor service restarted successfully"
        else
            print_colored "$(c_warning)" "⚠️  Please manually restart Tor service: sudo systemctl restart tor"
        fi
    fi
    
    # Show final summary
    echo
    print_colored "$(c_secondary)" "📊 Bulk Removal Summary:"
    print_colored "$(c_success)" "• Successfully removed: $removed_count services"
    
    if [[ $failed_count -gt 0 ]]; then
        print_colored "$(c_error)" "• Failed to remove: $failed_count services"
        print_colored "$(c_warning)" "Failed services:"
        for failed_service in "${failed_services[@]}"; do
            print_colored "$(c_text)" "  • $failed_service"
        done
    fi
    
    if [[ $removed_count -gt 0 ]]; then
        print_colored "$(c_warning)" "💡 ${removed_count} .onion addresses are now permanently inaccessible"
    fi
    
    return 0
}

# Updated parse_args function to handle bulk removal
parse_args() {
    # Initialize flags
    local FLAG_LIST=false
    local FLAG_TEST=false
    local FLAG_STOP=false
    local FLAG_REMOVE=false
    local SERVICE_NAME=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                print_colored "$(c_success)" "✅ Verbose mode enabled"
                shift
                ;;
            -V|--version)
                show_version
                exit 0
                ;;
            -A|--about)
                show_about
                exit 0
                ;;
            -l|--list)
                FLAG_LIST=true
                shift
                ;;
            -t|--test)
                FLAG_TEST=true
                shift
                ;;
            -s|--stop)
                FLAG_STOP=true
                if [[ -z "${2:-}" ]]; then
                    print_colored "$(c_error)" "❌ Service name required for --stop option"
                    print_colored "$(c_warning)" "Usage: $0 --stop SERVICE_NAME"
                    show_usage
                fi
                SERVICE_NAME="$2"
                shift 2
                ;;
            -r|--remove)
                FLAG_REMOVE=true
                if [[ -z "${2:-}" ]]; then
                    print_colored "$(c_error)" "❌ Service name(s) required for --remove option"
                    print_colored "$(c_warning)" "Usage: $0 --remove SERVICE_NAME"
                    print_colored "$(c_warning)" "   or: $0 --remove 'service1,service2,service3'"
                    init_service_tracking
                    remove_hidden_services_bulk ""
                    exit 1
                fi
                SERVICE_NAME="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                ;;
            # Combined short form arguments (like -Vl, -rV, etc.)
            -*)
                local flag_string="${1#-}"  # Remove the leading dash
                local i=0
                
                # Parse each character in the flag string
                while [[ $i -lt ${#flag_string} ]]; do
                    local char="${flag_string:$i:1}"
                    parse_char_flag "$char"
                    ((i++))
                done
                
                # Check if we need a service name for -s or -r flags
                if [[ "$flag_string" == *"s"* ]] || [[ "$flag_string" == *"r"* ]]; then
                    if [[ -z "${2:-}" ]]; then
                        if [[ "$flag_string" == *"s"* ]]; then
                            print_colored "$(c_error)" "❌ Service name required for -s flag"
                            print_colored "$(c_warning)" "Usage: $0 -s SERVICE_NAME or $0 -Vs SERVICE_NAME"
                        else
                            print_colored "$(c_error)" "❌ Service name(s) required for -r flag"
                            print_colored "$(c_warning)" "Usage: $0 -r SERVICE_NAME or $0 -Vr SERVICE_NAME"
                            print_colored "$(c_warning)" "   or: $0 -r 'service1,service2,service3'"
                        fi
                        show_usage
                    fi
                    SERVICE_NAME="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            *)
                print_colored "$(c_error)" "❌ Unknown option: $1"
                show_usage
                ;;
        esac
    done
    
    # Execute the appropriate action based on flags
    if [[ "$FLAG_LIST" == true ]]; then
        init_service_tracking
        list_services
        exit 0
    elif [[ "$FLAG_TEST" == true ]]; then
        print_colored "$(c_process)" "🔧 Initializing service tracking..."
        init_service_tracking
        test_all_services
        exit $?
    elif [[ "$FLAG_STOP" == true ]]; then
        init_service_tracking
        stop_service_web_server "$SERVICE_NAME"
        exit $?
    elif [[ "$FLAG_REMOVE" == true ]]; then
        init_service_tracking
        # Check if SERVICE_NAME contains multiple services (commas or multiple words)
        if [[ "$SERVICE_NAME" == *","* ]] || [[ "$SERVICE_NAME" == *" "* ]]; then
            verbose_log "Detected multiple services in input: $SERVICE_NAME"
            remove_hidden_services_bulk "$SERVICE_NAME"
        else
            verbose_log "Single service detected: $SERVICE_NAME"
            remove_hidden_service "$SERVICE_NAME"
        fi
        exit $?
    fi
}

# Main installation flow
main() {
    # Parse command line arguments first
    parse_args "$@"
    
    print_header
    check_root
    detect_system
    
    # Initialize service tracking for the installation flow
    init_service_tracking
    
    # Setup dynamic configuration
    setup_dynamic_config
    
    # Confirmation
    if ! ask_yes_no "Do you want to proceed with creating this new Tor hidden service?"; then
        print_colored "$(c_warning)" "Installation cancelled by user"
        verbose_log "Installation cancelled by user"
        sleep 2
        exit 0
    fi
    
    # Install Tor if needed
    verbose_log "Checking Tor installation..."
    if ! check_tor_installation; then
        verbose_log "Installing Tor..."
        install_tor
    fi
    
    # Configure Tor
    verbose_log "Configuring Tor..."
    configure_tor
    
    # Start Tor
    verbose_log "Starting Tor service..."
    if ! start_tor; then
        print_colored "$(c_error)" "❌ Failed to start Tor service properly"
        sleep 3
        exit 1
    fi
    
    # Ask about test website
    if ask_yes_no "Do you want to set up a test website? (requires Python3)"; then
        verbose_log "Setting up test website..."
        install_web_dependencies
        create_test_website
        start_test_server
        
        # Update registry with website directory
        local service_name; service_name=$(basename "$HIDDEN_SERVICE_DIR")
        update_service_in_registry "$service_name" "website_dir" "$TEST_SITE_DIR"
    else
        # Update registry to remove website directory since user declined
        local service_name; service_name=$(basename "$HIDDEN_SERVICE_DIR")
        update_service_in_registry "$service_name" "website_dir" ""
        verbose_log "User declined test website setup"
        sleep 1
    fi
    
    # Show results
    verbose_log "Displaying final results..."
    print_colored "$(c_process)" "🎯 Preparing final results..."
    sleep 2
    show_results
    
    print_colored "$(c_success)" "✨ All done! Enjoy your Tor hidden service!"
    verbose_log "Script completed successfully"
}

# Trap to handle cleanup
trap 'print_colored "$(c_error)" "Script interrupted"; exit 1' INT TERM

# Run main function if this script is executed directly
if [[ -z "${BASH_SOURCE-}" || "${BASH_SOURCE[0]-}" == "${0-}" || "$0" == "bash" ]]; then
    main "$@"
fi

### 🍉 materwelmon
### "Nobody expected the spanish inquisition"
###  - Monty Python and the Holy Grail (1975)

### End of src/main.sh
