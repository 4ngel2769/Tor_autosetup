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
    print_colored "$BLUE" "🔍 Checking service status..."
    
    # Sync registry before listing
    sync_registry_status
    
    print_colored "$CYAN" "📋 Available Tor Hidden Services:"
    echo
    
    if [[ ! -f "$SERVICES_FILE" ]] || [[ ! -s "$SERVICES_FILE" ]]; then
        print_colored "$YELLOW" "No services found."
        return 0
    fi
    
    printf "%-30s %-6s %-50s %-8s %-10s %-12s\n" "SERVICE NAME" "PORT" "ONION ADDRESS" "STATUS" "MANAGED" "WEB SERVER"
    print_colored "$WHITE" "──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
    
    while IFS='|' read -r name dir port onion website status created; do
        # Skip comments and empty lines
        [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
        
        local display_onion="$onion"
        if [[ -z "$onion" ]]; then
            display_onion="<not generated>"
        elif [[ ${#onion} -gt 45 ]]; then
            display_onion="${onion:0:42}..."
        fi
        
        # Status color
        local status_color_bg=""
        case "$status" in
            "ACTIVE") status_color_bg="${GREEN}" ;;
            "INACTIVE") status_color_bg="${RED}" ;;
            "ERROR") status_color_bg="${RED}" ;;
            *) status_color_bg="${WHITE}" ;;
        esac
        
        # Managed color
        local managed="NO"
        local managed_color_bg=""
        if is_script_managed "$name"; then
            managed="YES"
            managed_color_bg="${WHITE}"
        else
            managed_color_bg="${GREY}"
        fi
        
        # Get comprehensive web server status
        local web_status=$(get_web_server_status "$name" "$port" "$website")
        local web_color_bg=""
        
        case "$web_status" in
            "RUNNING") web_color_bg="${GREEN}" ;;
            "STOPPED") web_color_bg="${YELLOW}" ;;
            "UNRESPONSIVE") web_color_bg="${RED}" ;;
            "NOT_LISTENING") web_color_bg="${RED}" ;;
            "NOT_RESPONDING") web_color_bg="${RED}" ;;
            "N/A") web_color_bg="${WHITE}" ;;
            *) web_color_bg="${WHITE}" ;;
        esac
        
        # Print with custom colors
        printf "${LIME}%-30s${NC} ${BLURPLE}%-6s${NC} ${WHITE}%-50s${NC} ${status_color_bg}%-8s${NC} ${managed_color_bg}%-10s${NC} ${web_color_bg}%-12s${NC}\n" "$name" "$port" "$display_onion" "$status" "$managed" "$web_status"
        
        # Add verbose information if enabled
        if [[ "$VERBOSE" == true ]]; then
            verbose_log "Service $name details:"
            verbose_log "  Directory: $dir"
            verbose_log "  Port: $port"
            verbose_log "  Website: $website"
            verbose_log "  Hostname file: $dir/hostname"
            if [[ -f "$dir/hostname" ]]; then
                verbose_log "  Hostname content: $(cat "$dir/hostname" 2>/dev/null || echo 'ERROR reading file')"
            fi
        fi
        
    done < "$SERVICES_FILE"
    echo
    
    print_colored "$CYAN" "Legend:"
    print_colored "$WHITE" "• STATUS: Tor hidden service status (ACTIVE/INACTIVE/ERROR)"
    print_colored "$WHITE" "• MANAGED: Created by this script (YES/NO)"
    print_colored "$WHITE" "• WEB SERVER: Local web server status"
    print_colored "$GREEN" "  - RUNNING: Server responding to requests"
    print_colored "$YELLOW" "  - STOPPED: No server running on port"
    print_colored "$RED" "  - UNRESPONSIVE: Process exists but not responding"
    print_colored "$RED" "  - NOT_LISTENING: Port not listening"
    print_colored "$WHITE" "  - N/A: Not applicable (external service)"
}

# Function to test all services with real-time status
test_all_services() {
    print_colored "$BLUE" "🧪 Testing all hidden services..."
    
    # Initialize service tracking first
    init_service_tracking
    
    # Debug: Check if services file exists and has content
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_colored "$YELLOW" "❌ Services registry file not found: $SERVICES_FILE"
        print_colored "$CYAN" "💡 Try running: $0 to create a new service first"
        return 1
    fi
    
    # Debug: Show file content (only in verbose mode)
    if [[ "$VERBOSE" == true ]]; then
        print_colored "$CYAN" "[DEBUG] Services file content:"
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
    print_colored "$CYAN" "📊 Found $service_count services in registry (from $line_count total lines)"
    
    if [[ $service_count -eq 0 ]]; then
        print_colored "$YELLOW" "No active services found to test."
        print_colored "$CYAN" "💡 Create a new service by running: $0"
        return 0
    fi
    
    verbose_log "Starting testing phase..."
    
    local tested=0
    local active=0
    local responsive=0
    
    # Test each service - using a temp file approach
    verbose_log "Beginning service testing loop..."
    
    local temp_services=$(mktemp)
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
        
        print_colored "$CYAN" "🔍 Testing service $tested/$service_count: $name"
        
        # Debug service details
        verbose_log "Service details: name=$name, dir=$dir, port=$port, status=$status"
        
        # Check Tor service status
        if [[ "$status" == "ACTIVE" ]]; then
            ((active++))
            if [[ -n "$onion" ]]; then
                print_colored "$GREEN" "  ✅ Tor service: ACTIVE ($onion)"
            else
                print_colored "$GREEN" "  ✅ Tor service: ACTIVE (onion address not synced)"
            fi
        else
            print_colored "$YELLOW" "  ⚠️  Tor service: $status"
        fi
        
        # Check web server if port is available
        if [[ -n "$port" ]]; then
            print_colored "$BLUE" "  🌐 Testing web server on port $port..."
            verbose_log "Calling check_web_server_status for port $port"
            
            local web_status
            web_status=$(check_web_server_status "$port")
            verbose_log "Web status result: $web_status"
            
            case "$web_status" in
                "RUNNING")
                    ((responsive++))
                    print_colored "$GREEN" "  ✅ Web server: RUNNING on port $port"
                    ;;
                "NOT_LISTENING")
                    print_colored "$YELLOW" "  ⚠️  Web server: NOT LISTENING on port $port"
                    ;;
                "NOT_RESPONDING")
                    print_colored "$RED" "  ❌ Web server: NOT RESPONDING on port $port"
                    ;;
                *)
                    print_colored "$RED" "  ❌ Web server: UNKNOWN STATUS ($web_status)"
                    ;;
            esac
        else
            print_colored "$WHITE" "  ℹ️  Web server: No port configured"
        fi
        
        echo
        
    done < "$temp_services"
    
    # Clean up temp file
    rm -f "$temp_services"
    
    verbose_log "Testing phase completed"
    
    # Final summary
    print_colored "$CYAN" "📊 Test Summary:"
    print_colored "$WHITE" "• Total services tested: $tested"
    print_colored "$WHITE" "• Active Tor services: $active"
    print_colored "$WHITE" "• Responsive web servers: $responsive"
    
    if [[ $tested -eq 0 ]]; then
        print_colored "$YELLOW" "⚠️  No services were actually tested - check registry file"
    fi
    
    verbose_log "test_all_services function completed successfully"
}

# Function to stop web server by service name
stop_service_web_server() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        print_colored "$RED" "❌ Service name required"
        return 1
    fi
    
    # Check if service exists in registry
    if ! grep -q "^$service_name|" "$SERVICES_FILE" 2>/dev/null; then
        print_colored "$RED" "❌ Service '$service_name' not found"
        return 1
    fi
    
    # Check if service is script-managed
    if ! is_script_managed "$service_name"; then
        print_colored "$RED" "❌ Service '$service_name' is not managed by this script"
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
    
    print_colored "$CYAN" "📋 Preview of what will be removed:"
    echo
    print_colored "$WHITE" "Directories to be deleted:"
    print_colored "$RED" "  • $service_dir"
    if [[ -n "$website_dir" ]] && [[ -d "$website_dir" ]]; then
        print_colored "$RED" "  • $website_dir"
    fi
    
    echo
    print_colored "$WHITE" "Torrc configuration lines to be removed:"
    if grep -q "# Hidden Service Configuration - $service_name" "$TORRC_FILE" 2>/dev/null; then
        print_colored "$RED" "  • # Hidden Service Configuration - $service_name"
        print_colored "$RED" "  • HiddenServiceDir $service_dir/"
        print_colored "$RED" "  • HiddenServicePort 80 127.0.0.1:$port"
    else
        print_colored "$YELLOW" "  • No torrc configuration found for this service"
    fi
    
    echo
    print_colored "$WHITE" "Registry entry to be removed:"
    print_colored "$RED" "  • Service record for '$service_name'"
    
    if is_script_managed "$service_name"; then
        echo
        print_colored "$WHITE" "Additional cleanup:"
        print_colored "$RED" "  • PID files and process tracking"
    fi
}

# Function to remove a hidden service completely
remove_hidden_service() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        print_colored "$YELLOW" "Usage: $0 --remove SERVICE_NAME"
        print_colored "$CYAN" "Available services:"
        if [[ -f "$SERVICES_FILE" ]]; then
            while IFS='|' read -r name dir port onion website status created; do
                [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
                print_colored "$WHITE" "  • $name"
            done < "$SERVICES_FILE"
        else
            print_colored "$YELLOW" "  No services found"
        fi
        return 1
    fi
    
    # Check if service exists in registry
    if ! grep -q "^$service_name|" "$SERVICES_FILE" 2>/dev/null; then
        print_colored "$RED" "❌ Service '$service_name' not found in registry"
        print_colored "$CYAN" "Available services:"
        if [[ -f "$SERVICES_FILE" ]]; then
            while IFS='|' read -r name dir port onion website status created; do
                [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
                print_colored "$WHITE" "  • $name"
            done < "$SERVICES_FILE"
        else
            print_colored "$YELLOW" "  No services found"
        fi
        return 1
    fi
    
    # Get service details from registry
    local service_info
    service_info=$(grep "^$service_name|" "$SERVICES_FILE" 2>/dev/null)
    
    if [[ -z "$service_info" ]]; then
        print_colored "$RED" "❌ Could not retrieve service information"
        return 1
    fi
    
    IFS='|' read -r name dir port onion website status created <<< "$service_info"
    
    # Display service information
    clear
    print_header
    print_colored "$RED" "⚠️  DANGER: PERMANENT REMOVAL WARNING ⚠️"
    echo
    print_colored "$YELLOW" "You are about to PERMANENTLY remove the following hidden service:"
    echo
    print_colored "$WHITE" "Service Name: $name"
    print_colored "$WHITE" "Onion Address: ${onion:-'<not generated>'}"
    print_colored "$WHITE" "Port: ${port:-'N/A'}"
    print_colored "$WHITE" "Hidden Service Directory: $dir"
    print_colored "$WHITE" "Website Directory: ${website:-'N/A'}"
    print_colored "$WHITE" "Created: ${created:-'Unknown'}"
    echo
    
    # Show preview of what will be removed
    preview_removal "$service_name" "$dir" "$website" "$port"
    
    echo
    print_colored "$RED" "⚠️  THIS ACTION CANNOT BE UNDONE! ⚠️"
    print_colored "$RED" "⚠️  The .onion address will be LOST FOREVER! ⚠️"
    print_colored "$RED" "⚠️  All website files will be DELETED! ⚠️"
    echo
    
    # Multiple confirmation prompts
    if ! ask_yes_no "Are you ABSOLUTELY SURE you want to remove this hidden service?"; then
        print_colored "$GREEN" "✅ Removal cancelled - service preserved"
        return 0
    fi
    
    if ! ask_yes_no "This will PERMANENTLY DELETE the .onion address. Continue?"; then
        print_colored "$GREEN" "✅ Removal cancelled - service preserved"
        return 0
    fi
    
    if ! ask_yes_no "FINAL WARNING: Remove hidden service '$service_name' forever?"; then
        print_colored "$GREEN" "✅ Removal cancelled - service preserved"
        return 0
    fi
    
    # Stop web server if it's running
    if is_script_managed "$service_name"; then
        print_colored "$BLUE" "🛑 Stopping web server..."
        stop_web_server "$service_name" 2>/dev/null || true
    fi
    
    print_colored "$BLUE" "🗑️ Starting removal process..."
    
    # Remove from torrc
    remove_from_torrc "$dir" "$service_name"
    
    # Remove directories
    remove_service_directories "$dir" "$website" "$service_name"
    
    # Remove from registry
    remove_service_from_registry "$service_name"
    
    # Restart Tor to apply changes
    print_colored "$BLUE" "🔄 Restarting Tor service to apply changes..."
    if systemctl restart tor 2>/dev/null; then
        print_colored "$GREEN" "✅ Tor service restarted successfully"
    else
        print_colored "$YELLOW" "⚠️  Please manually restart Tor service: sudo systemctl restart tor"
    fi
    
    print_colored "$GREEN" "✅ Hidden service '$service_name' has been completely removed"
    print_colored "$YELLOW" "💡 The .onion address is now permanently inaccessible"
    
    return 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -V|--verbose)
                VERBOSE=true
                print_colored "$GREEN" "✅ Verbose mode enabled"
                shift
                ;;
            -l|--list)
                init_service_tracking
                list_services
                exit 0
                ;;
            -t|--test)
                print_colored "$BLUE" "🔧 Initializing service tracking..."
                init_service_tracking
                test_all_services
                exit $?
                ;;
            -s|--stop)
                if [[ -z "${2:-}" ]]; then
                    print_colored "$RED" "❌ Service name required for --stop option"
                    print_colored "$YELLOW" "Usage: $0 --stop SERVICE_NAME"
                    show_usage
                fi
                init_service_tracking
                stop_service_web_server "$2"
                exit $?
                ;;
            -r|--remove)
                if [[ -z "${2:-}" ]]; then
                    print_colored "$RED" "❌ Service name required for --remove option"
                    print_colored "$YELLOW" "Usage: $0 --remove SERVICE_NAME"
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
                print_colored "$RED" "❌ Unknown option: $1"
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
        print_colored "$YELLOW" "Installation cancelled by user"
        verbose_log "Installation cancelled by user"
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
        print_colored "$RED" "❌ Failed to start Tor service properly"
        exit 1
    fi
    
    # Ask about test website
    if ask_yes_no "Do you want to set up a test website? (requires Python3)"; then
        verbose_log "Setting up test website..."
        install_web_dependencies
        create_test_website
        start_test_server
    fi
    
    # Show results
    verbose_log "Displaying final results..."
    show_results
    
    print_colored "$GREEN" "✨ All done! Enjoy your Tor hidden service!"
    verbose_log "Script completed successfully"
}

# Trap to handle cleanup
trap 'print_colored "$RED" "Script interrupted"; exit 1' INT TERM

# Run main function if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
