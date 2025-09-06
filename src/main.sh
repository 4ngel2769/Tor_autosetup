#!/bin/bash

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
    echo "Usage: $0 [-V|--verbose] [-l|--list] [-t|--test] [-s|--stop SERVICE_NAME] [-r|--remove SERVICE_NAME] [-h|--help]"
    echo "Options:"
    echo "  -V, --verbose           Enable verbose output for debugging"
    echo "  -l, --list              List all available hidden services with status"
    echo "  -t, --test              Test all services (Tor + web server status)"
    echo "  -s, --stop SERVICE_NAME Stop web server for specific service"
    echo "  -r, --remove SERVICE_NAME Remove hidden service PERMANENTLY"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                  # Create a new hidden service"
    echo "  $0 --list                           # List all services with real-time status"
    echo "  $0 --test                           # Test all services comprehensively"
    echo "  $0 --stop hidden_service_abc123def  # Stop web server for specific service"
    echo "  $0 --remove hidden_service_abc123def # PERMANENTLY remove hidden service"
    echo "  $0 -V --list                        # Verbose listing with detailed info"
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
    
    # Updated header with new WEB ADDRESS column and shorter ONION ADDRESS
    printf "%-30s %-6s %-40s %-8s %-10s %-12s %-25s\n" "SERVICE NAME" "PORT" "ONION ADDRESS" "STATUS" "MANAGED" "WEB SERVER" "WEB ADDRESS"
    print_colored "$(c_text)" "───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
    
    while IFS='|' read -r name dir port onion website status created; do
        # Skip comments and empty lines
        [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
        
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
            managed="YES"
            managed_color_bg="$(c_text)"
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
    print_colored "$(c_text)" "• MANAGED: Created by this script (YES/NO)"
    print_colored "$(c_text)" "• WEB SERVER: Local web server status"
    print_colored "$(c_success)" "  - RUNNING: Server responding to requests"
    print_colored "$(c_warning)" "  - STOPPED: No server running on port"
    print_colored "$(c_error)" "  - UNRESPONSIVE: Process exists but not responding"
    print_colored "$(c_error)" "  - NOT_LISTENING: Port not listening"
    print_colored "$(c_text)" "  - N/A: Not applicable (external service)"
    print_colored "$(c_text)" "• ONION ADDRESS: .onion domain for Tor access (clickable)"
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
# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -V|--verbose)
                VERBOSE=true
                print_colored "$(c_success)" "✅ Verbose mode enabled"
                shift
                ;;
            -l|--list)
                init_service_tracking
                list_services
                exit 0
                ;;
            -t|--test)
                print_colored "$(c_process)" "🔧 Initializing service tracking..."
                init_service_tracking
                test_all_services
                exit $?
                ;;
            -s|--stop)
                if [[ -z "${2:-}" ]]; then
                    print_colored "$(c_error)" "❌ Service name required for --stop option"
                    print_colored "$(c_warning)" "Usage: $0 --stop SERVICE_NAME"
                    show_usage
                fi
                init_service_tracking
                stop_service_web_server "$2"
                exit $?
                ;;
            -r|--remove)
                if [[ -z "${2:-}" ]]; then
                    print_colored "$(c_error)" "❌ Service name required for --remove option"
                    print_colored "$(c_warning)" "Usage: $0 --remove SERVICE_NAME"
                    init_service_tracking
                    remove_hidden_service ""
                    exit 1
                fi
                init_service_tracking
                remove_hidden_service "$2"
                exit $?
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                print_colored "$(c_error)" "❌ Unknown option: $1"
                show_usage
                ;;
        esac
    done
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
    # local setup_website=false
    if ask_yes_no "Do you want to set up a test website? (requires Python3)"; then
        # setup_website=true
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
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
