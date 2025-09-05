#!/bin/bash

# Tor Hidden Service Setup Script
# Author: Auto-generated setup script
# Description: Automatically sets up Tor hidden service with optional test website

set -euo pipefail

# Color definitions (using ANSI escape codes - no external dependencies)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global flags
VERBOSE=false

# Configuration
TORRC_FILE="/etc/tor/torrc"
HIDDEN_SERVICE_BASE_DIR="/var/lib/tor"
HIDDEN_SERVICE_DIR=""  # Will be set dynamically
TEST_SITE_BASE_PORT=5000
TEST_SITE_PORT=""  # Will be set dynamically
TEST_SITE_BASE_DIR="/var/www/tor-test"
TEST_SITE_DIR=""  # Will be set dynamically

# Service tracking
SERVICES_FILE="$HOME/.torstp/.services_available"
TORSTP_DIR="$HOME/.torstp"

# Global variables
DISTRO=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
SERVICE_MANAGER=""

# Function to print verbose output
verbose_log() {
    if [[ "$VERBOSE" == true ]]; then
        print_colored $CYAN "[VERBOSE] $1"
    fi
}

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to generate random string
generate_random_string() {
    local length=${1:-9}
    tr -dc 'a-z0-9' < /dev/urandom | head -c "$length"
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
                echo "$service_name|$current_dir|$current_port|$onion_address||$status|$created_date" >> "$temp_file"
                verbose_log "Found existing service: $service_name ($current_dir:$current_port)"
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

# Function to list available services
list_services() {
    print_colored $CYAN "📋 Available Tor Hidden Services:"
    echo
    
    if [[ ! -f "$SERVICES_FILE" ]] || [[ ! -s "$SERVICES_FILE" ]]; then
        print_colored $YELLOW "No services found."
        return 0
    fi
    
    printf "%-20s %-10s %-60s %-8s\n" "SERVICE NAME" "PORT" "ONION ADDRESS" "STATUS"
    print_colored $WHITE "────────────────────────────────────────────────────────────────────────────────────────────────"
    
    while IFS='|' read -r name dir port onion website status created; do
        # Skip comments and empty lines
        [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
        
        local display_onion="$onion"
        if [[ -z "$onion" ]]; then
            display_onion="<not generated>"
        elif [[ ${#onion} -gt 50 ]]; then
            display_onion="${onion:0:47}..."
        fi
        
        local color="$WHITE"
        case "$status" in
            "ACTIVE") color="$GREEN" ;;
            "INACTIVE") color="$YELLOW" ;;
            "ERROR") color="$RED" ;;
        esac
        
        printf "${color}%-20s %-10s %-60s %-8s${NC}\n" "$name" "$port" "$display_onion" "$status"
    done < "$SERVICES_FILE"
    echo
}

# Function to setup dynamic paths and ports
setup_dynamic_config() {
    print_colored $BLUE "🔍 Setting up new hidden service configuration..."
    
    # Initialize service tracking
    init_service_tracking
    
    # Generate random service name
    local random_suffix=$(generate_random_string 9)
    local service_name="hidden_service_$random_suffix"
    
    # Set paths
    HIDDEN_SERVICE_DIR="$HIDDEN_SERVICE_BASE_DIR/$service_name"
    
    # Find available port
    local existing_ports=()
    if [[ -f "$SERVICES_FILE" ]]; then
        while IFS='|' read -r name dir port onion website status created; do
            [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
            [[ -n "$port" ]] && existing_ports+=("$port")
        done < "$SERVICES_FILE"
    fi
    
    local test_port="$TEST_SITE_BASE_PORT"
    while ss -tlpn 2>/dev/null | grep -q ":$test_port " || [[ " ${existing_ports[*]} " =~ " $test_port " ]]; do
        ((test_port++))
        if [[ $test_port -gt 65535 ]]; then
            print_colored $RED "❌ No available ports found"
            exit 1
        fi
    done
    TEST_SITE_PORT="$test_port"
    
    # Set test site directory
    TEST_SITE_DIR="$TEST_SITE_BASE_DIR/$service_name"
    
    verbose_log "Generated service configuration:"
    verbose_log "  Service name: $service_name"
    verbose_log "  Hidden service dir: $HIDDEN_SERVICE_DIR"
    verbose_log "  Port: $TEST_SITE_PORT"
    verbose_log "  Website dir: $TEST_SITE_DIR"
    
    print_colored $GREEN "✅ Service name: $service_name"
    print_colored $GREEN "✅ Hidden service directory: $HIDDEN_SERVICE_DIR"
    print_colored $GREEN "✅ Local port: $TEST_SITE_PORT"
    print_colored $GREEN "✅ Website directory: $TEST_SITE_DIR"
    
    # Add to registry (initially with inactive status)
    add_service_to_registry "$service_name" "$HIDDEN_SERVICE_DIR" "$TEST_SITE_PORT" "" "$TEST_SITE_DIR" "INACTIVE"
    
    sleep 2
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [-V|--verbose] [-l|--list] [-h|--help]"
    echo "Options:"
    echo "  -V, --verbose    Enable verbose output for debugging"
    echo "  -l, --list       List all available hidden services"
    echo "  -h, --help       Show this help message"
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -V|--verbose)
                VERBOSE=true
                print_colored $GREEN "✅ Verbose mode enabled"
                shift
                ;;
            -l|--list)
                init_service_tracking
                list_services
                exit 0
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                print_colored $RED "❌ Unknown option: $1"
                show_usage
                ;;
        esac
    done
}

# Function to print header
print_header() {
    clear
    print_colored $PURPLE "╔══════════════════════════════════════════════════════════════╗"
    print_colored $PURPLE "║                    Tor Hidden Service Setup                  ║"
    print_colored $PURPLE "║                   Automated Installation                     ║"
    print_colored $PURPLE "╚══════════════════════════════════════════════════════════════╝"
    echo
    if [[ "$VERBOSE" == true ]]; then
        print_colored $CYAN "[VERBOSE MODE ENABLED]"
        echo
    fi
}

# Function to check if running as root
check_root() {
    verbose_log "Checking if running as root..."
    if [[ $EUID -ne 0 ]]; then
        print_colored $RED "❌ This script must be run as root!"
        print_colored $YELLOW "Please run: sudo $0"
        exit 1
    fi
    verbose_log "✅ Running as root"
}

# Function to detect distribution and package manager
detect_system() {
    print_colored $BLUE "🔍 Detecting system distribution..."
    verbose_log "Checking available package managers..."
    
    if command -v apt-get >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD="apt-get"
        verbose_log "Found apt-get package manager"
        if [[ -f /etc/debian_version ]]; then
            DISTRO="debian"
            verbose_log "Detected Debian distribution"
        elif [[ -f /etc/ubuntu-release ]] || grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
            DISTRO="ubuntu"
            verbose_log "Detected Ubuntu distribution"
        else
            DISTRO="debian-based"
            verbose_log "Detected Debian-based distribution"
        fi
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
        INSTALL_CMD="yum"
        DISTRO="rhel-based"
        verbose_log "Found yum package manager (RHEL-based)"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
        INSTALL_CMD="dnf"
        DISTRO="fedora-based"
        verbose_log "Found dnf package manager (Fedora-based)"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD="pacman"
        DISTRO="arch-based"
        verbose_log "Found pacman package manager (Arch-based)"
    elif command -v zypper >/dev/null 2>&1; then
        PACKAGE_MANAGER="zypper"
        INSTALL_CMD="zypper"
        DISTRO="suse-based"
        verbose_log "Found zypper package manager (SUSE-based)"
    else
        print_colored $RED "❌ Unsupported package manager detected!"
        print_colored $YELLOW "This script supports: apt, yum, dnf, pacman, zypper"
        exit 1
    fi
    
    # Detect service manager
    verbose_log "Checking service manager..."
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_MANAGER="systemd"
        verbose_log "Found systemd service manager"
    elif command -v service >/dev/null 2>&1; then
        SERVICE_MANAGER="sysv"
        verbose_log "Found SysV service manager"
    else
        print_colored $YELLOW "⚠️  Warning: No supported service manager found"
        SERVICE_MANAGER="none"
        verbose_log "No supported service manager found"
    fi
    
    print_colored $GREEN "✅ Detected: $DISTRO ($PACKAGE_MANAGER) with $SERVICE_MANAGER"
    verbose_log "System detection complete"
    sleep 2
}

# Function to create interactive menu
show_menu() {
    local title=$1
    shift
    local options=("$@")
    local selected=0
    
    while true; do
        clear
        print_header
        print_colored $CYAN "$title"
        echo
        
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                print_colored $GREEN "► ${options[$i]}"
            else
                print_colored $WHITE "  ${options[$i]}"
            fi
        done
        
        echo
        print_colored $YELLOW "Use ↑/↓ arrow keys to navigate, Enter to select"
        
        read -rsn1 key
        case $key in
            $'\x1b')  # ESC sequence
                read -rsn2 key
                case $key in
                    '[A') ((selected > 0)) && ((selected--)) ;;  # Up arrow
                    '[B') ((selected < ${#options[@]} - 1)) && ((selected++)) ;;  # Down arrow
                esac
                ;;
            '') return $selected ;;  # Enter key
        esac
    done
}

# Function to ask yes/no question
ask_yes_no() {
    local question=$1
    local options=("Yes" "No")
    
    show_menu "$question" "${options[@]}"
    return $?
}

# Function to install packages based on distribution
install_packages() {
    local packages=("$@")
    
    print_colored $BLUE "📦 Installing packages: ${packages[*]}"
    verbose_log "Package manager: $PACKAGE_MANAGER"
    verbose_log "Install command: $INSTALL_CMD"
    
    case $PACKAGE_MANAGER in
        "apt")
            verbose_log "Updating package list..."
            apt-get update -qq
            verbose_log "Installing packages with apt-get..."
            apt-get install -y "${packages[@]}"
            ;;
        "yum"|"dnf")
            verbose_log "Installing packages with $INSTALL_CMD..."
            $INSTALL_CMD install -y "${packages[@]}"
            ;;
        "pacman")
            verbose_log "Installing packages with pacman..."
            pacman -Syu --noconfirm "${packages[@]}"
            ;;
        "zypper")
            verbose_log "Installing packages with zypper..."
            zypper install -y "${packages[@]}"
            ;;
    esac
    verbose_log "Package installation completed"
}

# Function to check if Tor is installed
check_tor_installation() {
    if command -v tor >/dev/null 2>&1; then
        print_colored $GREEN "✅ Tor is already installed"
        return 0
    else
        print_colored $YELLOW "⚠️  Tor is not installed"
        return 1
    fi
}

# Function to install Tor
install_tor() {
    print_colored $BLUE "🔧 Installing Tor..."
    
    case $PACKAGE_MANAGER in
        "apt")
            install_packages tor
            ;;
        "yum"|"dnf")
            install_packages tor
            ;;
        "pacman")
            install_packages tor
            ;;
        "zypper")
            install_packages tor
            ;;
    esac
    
    print_colored $GREEN "✅ Tor installation completed"
}

# Function to find available directory with enumeration
find_available_directory() {
    local base_dir=$1
    local counter=1
    local test_dir="$base_dir"
    
    verbose_log "Looking for available directory starting with: $base_dir"
    
    while [[ -d "$test_dir" ]]; do
        verbose_log "Directory $test_dir already exists, trying next..."
        test_dir="${base_dir}_${counter}"
        ((counter++))
    done
    
    verbose_log "Found available directory: $test_dir"
    echo "$test_dir"
}

# Function to find available port
find_available_port() {
    local base_port=$1
    local test_port=$base_port
    
    verbose_log "Looking for available port starting with: $base_port"
    
    while ss -tlpn | grep -q ":$test_port "; do
        verbose_log "Port $test_port is in use, trying next..."
        ((test_port++))
        if [[ $test_port -gt 65535 ]]; then
            print_colored $RED "❌ No available ports found"
            exit 1
        fi
    done
    
    verbose_log "Found available port: $test_port"
    echo "$test_port"
}

# Function to configure Tor hidden service
configure_tor() {
    print_colored $BLUE "⚙️  Configuring Tor hidden service..."
    
    local service_name=$(basename "$HIDDEN_SERVICE_DIR")
    
    # Variables for logging before adding to torrc
    local hs_dir_log="$HIDDEN_SERVICE_DIR"
    local hs_port_log="$TEST_SITE_PORT"
    
    # Backup original torrc
    if [[ -f "$TORRC_FILE" ]] && [[ ! -f "$TORRC_FILE.backup" ]]; then
        cp "$TORRC_FILE" "$TORRC_FILE.backup"
        print_colored $GREEN "✅ Backed up original torrc file"
    fi
    
    # Check if this hidden service is already configured
    if grep -q "HiddenServiceDir $HIDDEN_SERVICE_DIR" "$TORRC_FILE" 2>/dev/null; then
        print_colored $YELLOW "⚠️  Hidden service already configured in torrc"
        return 0
    fi
    
    # Do all verbose logging before heredoc
    verbose_log "Adding hidden service configuration to torrc..."
    verbose_log "Service name: $service_name"
    verbose_log "Hidden service directory: $hs_dir_log"
    verbose_log "Hidden service port mapping: 80 -> 127.0.0.1:$hs_port_log"
    
    # Add hidden service configuration without any logging in between
    cat >> "$TORRC_FILE" << EOF

# Hidden Service Configuration - $service_name
HiddenServiceDir $HIDDEN_SERVICE_DIR/
HiddenServicePort 80 127.0.0.1:$TEST_SITE_PORT
EOF
    
    print_colored $GREEN "✅ Tor configuration updated"
}

# Function to manage Tor service
manage_tor_service() {
    local action=$1
    
    case $SERVICE_MANAGER in
        "systemd")
            systemctl "$action" tor
            ;;
        "sysv")
            service tor "$action"
            ;;
        *)
            print_colored $YELLOW "⚠️  Please manually $action Tor service"
            return 1
            ;;
    esac
}

# Function to start and enable Tor
start_tor() {
    print_colored $BLUE "🚀 Starting Tor service..."
    verbose_log "Service manager: $SERVICE_MANAGER"
    
    local service_name=$(basename "$HIDDEN_SERVICE_DIR")
    
    case $SERVICE_MANAGER in
        "systemd")
            # Stop any existing tor service first
            verbose_log "Stopping existing Tor service..."
            systemctl stop tor 2>/dev/null || true
            
            # Start tor service
            verbose_log "Starting Tor service with systemctl..."
            if systemctl restart tor; then
                print_colored $GREEN "✅ Tor service started successfully"
                verbose_log "Tor service started successfully"
            else
                print_colored $RED "❌ Failed to start Tor service"
                update_service_in_registry "$service_name" "status" "ERROR"
                return 1
            fi
            
            if ask_yes_no "Do you want Tor to start automatically on system boot?"; then
                verbose_log "Enabling Tor service for auto-start..."
                if systemctl enable tor 2>/dev/null; then
                    print_colored $GREEN "✅ Tor enabled for auto-start"
                    verbose_log "Tor enabled for auto-start"
                else
                    print_colored $YELLOW "⚠️  Could not enable auto-start (non-critical)"
                    verbose_log "Could not enable auto-start"
                fi
            fi
            ;;
        "sysv")
            verbose_log "Using SysV service manager..."
            service tor stop 2>/dev/null || true
            if service tor start; then
                print_colored $GREEN "✅ Tor service started successfully"
                verbose_log "Tor service started with SysV"
            else
                print_colored $RED "❌ Failed to start Tor service"
                update_service_in_registry "$service_name" "status" "ERROR"
                return 1
            fi
            print_colored $YELLOW "⚠️  Auto-start configuration varies by system"
            ;;
    esac
    
    # Wait for Tor to generate the hidden service
    print_colored $BLUE "⏳ Waiting for Tor to generate hidden service..."
    verbose_log "Waiting for hostname file: $HIDDEN_SERVICE_DIR/hostname"
    
    # Check if hidden service directory was created
    local count=0
    local max_wait=60  # 2 minutes total wait time
    
    while [[ ! -f "$HIDDEN_SERVICE_DIR/hostname" ]] && [[ $count -lt $max_wait ]]; do
        sleep 2
        ((count++))
        echo -n "."
        
        verbose_log "Wait attempt $count/$max_wait - checking for hostname file..."
        
        # Check if Tor is still running
        if ! pgrep -x tor >/dev/null; then
            echo
            print_colored $RED "❌ Tor process died during startup"
            update_service_in_registry "$service_name" "status" "ERROR"
            return 1
        fi
    done
    echo
    
    if [[ -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        local onion_addr
        onion_addr=$(cat "$HIDDEN_SERVICE_DIR/hostname")
        
        print_colored $GREEN "✅ Hidden service generated successfully"
        verbose_log "Hostname file found: $HIDDEN_SERVICE_DIR/hostname"
        verbose_log "Generated .onion address: $onion_addr"
        
        # Update registry with onion address and active status
        update_service_in_registry "$service_name" "onion_address" "$onion_addr"
        update_service_in_registry "$service_name" "status" "ACTIVE"
        
        return 0
    else
        print_colored $RED "❌ Failed to generate hidden service after ${max_wait} attempts"
        update_service_in_registry "$service_name" "status" "ERROR"
        return 1
    fi
}

# Function to create test website
create_test_website() {
    print_colored $BLUE "🌐 Creating test website..."
    
    # Create directory
    mkdir -p "$TEST_SITE_DIR"
    
    # Create simple HTML page
    cat > "$TEST_SITE_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tor Hidden Service - Test Page</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            max-width: 800px; 
            margin: 0 auto; 
            padding: 20px;
            background: #1a1a1a;
            color: #ffffff;
        }
        .container { 
            text-align: center; 
            background: #2d2d2d;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }
        .success { 
            color: #4CAF50; 
            font-size: 24px;
            margin-bottom: 20px;
        }
        .info { 
            background: #333;
            padding: 20px;
            border-radius: 5px;
            margin: 20px 0;
            text-align: left;
        }
        .onion { 
            font-family: monospace;
            background: #444;
            padding: 10px;
            border-radius: 3px;
            word-break: break-all;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="success">🎉 Your Tor Hidden Service is Working!</div>
        <p>Congratulations! You have successfully set up a Tor hidden service.</p>
        
        <div class="info">
            <h3>📍 Service Information:</h3>
            <p><strong>Local Port:</strong> 5000</p>
            <p><strong>Access:</strong> Via Tor Browser only</p>
            <p><strong>Security:</strong> Traffic is automatically encrypted through Tor</p>
        </div>
        
        <div class="info">
            <h3>🔧 Next Steps:</h3>
            <ul style="text-align: left;">
                <li>Replace this test page with your actual website</li>
                <li>Configure your web application to run on port 5000</li>
                <li>Share your .onion address securely with intended users</li>
                <li>Consider additional security measures for production use</li>
            </ul>
        </div>
        
        <p><small>Generated by Tor Hidden Service Setup Script</small></p>
    </div>
</body>
</html>
EOF
    
    # Create simple Python web server script
    cat > "$TEST_SITE_DIR/server.py" << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import os

PORT = 5000
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        print(f"Serving at http://127.0.0.1:{PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")
EOF
    
    chmod +x "$TEST_SITE_DIR/server.py"
    
    print_colored $GREEN "✅ Test website created at $TEST_SITE_DIR"
}

# Function to install web server dependencies
install_web_dependencies() {
    print_colored $BLUE "📦 Installing web server dependencies..."
    
    case $PACKAGE_MANAGER in
        "apt")
            install_packages python3
            ;;
        "yum"|"dnf")
            install_packages python3
            ;;
        "pacman")
            install_packages python
            ;;
        "zypper")
            install_packages python3
            ;;
    esac
    
    print_colored $GREEN "✅ Web server dependencies installed"
}

# Function to start test web server
start_test_server() {
    print_colored $BLUE "🚀 Starting test web server on port $TEST_SITE_PORT..."
    
    # Double-check if port is available
    if ss -tlpn | grep -q ":$TEST_SITE_PORT "; then
        print_colored $YELLOW "⚠️  Port $TEST_SITE_PORT became unavailable"
        
        # Find a new port
        local old_port=$TEST_SITE_PORT
        local existing_ports=()
        
        # Extract all hidden service ports from torrc
        while read -r line; do
            existing_ports+=("$line")
        done < <(grep -oP 'HiddenServicePort\s+\d+\s+127.0.0.1:\K\d+' "$TORRC_FILE" 2>/dev/null)
        
        # Find next available port
        local test_port=$((TEST_SITE_PORT + 1))
        while ss -tlpn | grep -q ":$test_port " || check_if_in_array "$test_port" "${existing_ports[@]}"; do
            ((test_port++))
            if [[ $test_port -gt 65535 ]]; then
                print_colored $RED "❌ No available ports found"
                return 1
            fi
        done
        
        TEST_SITE_PORT=$test_port
        print_colored $CYAN "📍 Using alternative port: $TEST_SITE_PORT"
        
        # Update the server.py file with new port
        sed -i "s/PORT = [0-9]*/PORT = $TEST_SITE_PORT/" "$TEST_SITE_DIR/server.py"
        
        # Update torrc with new port - be careful to only update our entry
        sed -i "s|HiddenServicePort 80 127.0.0.1:$old_port|HiddenServicePort 80 127.0.0.1:$TEST_SITE_PORT|" "$TORRC_FILE"
        
        # Restart Tor to apply new configuration
        print_colored $BLUE "🔄 Restarting Tor with updated port..."
        manage_tor_service restart
        sleep 3
    fi
    
    # Update HTML with correct port
    sed -i "s|<p><strong>Local Port:</strong> [0-9]*</p>|<p><strong>Local Port:</strong> $TEST_SITE_PORT</p>|" "$TEST_SITE_DIR/index.html"
    
    # Start server in background
    cd "$TEST_SITE_DIR" || exit
    nohup python3 server.py > server.log 2>&1 &
    
    sleep 2
    
    # Check if server started successfully
    if curl -s http://127.0.0.1:$TEST_SITE_PORT >/dev/null 2>&1; then
        print_colored $GREEN "✅ Test web server started successfully on port $TEST_SITE_PORT"
        return 0
    else
        print_colored $YELLOW "⚠️  Server may not have started correctly"
        print_colored $CYAN "You can manually start it with:"
        print_colored $WHITE "cd $TEST_SITE_DIR && python3 server.py"
        print_colored $CYAN "Check logs at: $TEST_SITE_DIR/server.log"
        return 1
    fi
}

# Function to display final results (updated to use registry)
show_results() {
    clear
    print_header
    
    local service_name=$(basename "$HIDDEN_SERVICE_DIR")
    
    # Give one more chance to find the hostname file
    if [[ ! -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        print_colored $BLUE "🔍 Making final check for hostname file..."
        sleep 5
    fi
    
    if [[ -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        local onion_address
        onion_address=$(cat "$HIDDEN_SERVICE_DIR/hostname")
        
        print_colored $GREEN "🎉 Setup Complete!"
        echo
        print_colored $PURPLE "╔══════════════════════════════════════════════════════════════╗"
        print_colored $PURPLE "║                     YOUR .ONION ADDRESS                     ║"
        print_colored $PURPLE "╠══════════════════════════════════════════════════════════════╣"
        print_colored $WHITE "║  $onion_address  ║"
        print_colored $PURPLE "╚══════════════════════════════════════════════════════════════╝"
        echo
        print_colored $CYAN "Your Tor Hidden Service Details:"
        print_colored $WHITE "════════════════════════════════════"
        print_colored $YELLOW "🏷️  Service Name: $service_name"
        print_colored $YELLOW "🌐 Onion Address: $onion_address"
        print_colored $YELLOW "🔌 Local Port: $TEST_SITE_PORT"
        print_colored $YELLOW "📁 Service Directory: $HIDDEN_SERVICE_DIR"
        print_colored $YELLOW "🌍 Website Directory: $TEST_SITE_DIR"
        echo
        print_colored $CYAN "To access your site:"
        print_colored $WHITE "1. Open Tor Browser"
        print_colored $WHITE "2. Navigate to: http://$onion_address"
        echo
        print_colored $CYAN "To manage your services:"
        print_colored $WHITE "• List all services: $0 --list"
        print_colored $WHITE "• Start test server: cd $TEST_SITE_DIR && python3 server.py"
        print_colored $WHITE "• Tor config: $TORRC_FILE"
        print_colored $WHITE "• Services registry: $SERVICES_FILE"
        echo
        print_colored $PURPLE "🔒 Remember: Your site is only accessible via Tor Browser!"
        echo
        print_colored $GREEN "💡 TIP: Use '$0 --list' to see all your hidden services!"
    else
        update_service_in_registry "$service_name" "status" "ERROR"
        print_colored $RED "❌ Setup completed but no .onion address found"
        print_colored $YELLOW "📋 Troubleshooting Information:"
        print_colored $WHITE "• Tor service status: $(systemctl is-active tor 2>/dev/null || echo 'unknown')"
        print_colored $WHITE "• Hidden service dir: $HIDDEN_SERVICE_DIR"
        print_colored $WHITE "• Torrc config file: $TORRC_FILE"
        echo
        print_colored $CYAN "🔧 Manual troubleshooting steps:"
        print_colored $WHITE "1. Check Tor logs: journalctl -u tor -f"
        print_colored $WHITE "2. Verify config: sudo tor --verify-config"
        print_colored $WHITE "3. Restart Tor: sudo systemctl restart tor"
        print_colored $WHITE "4. Wait 30 seconds then check: sudo cat $HIDDEN_SERVICE_DIR/hostname"
        print_colored $WHITE "5. Check permissions: sudo ls -la $HIDDEN_SERVICE_BASE_DIR"
    fi
}

# Main installation flow
main() {
    # Parse command line arguments first
    parse_args "$@"
    
    print_header
    check_root
    detect_system
    
    # Show existing services
    init_service_tracking
    list_services
    
    # Setup dynamic configuration
    setup_dynamic_config
    
    # Confirmation
    if ! ask_yes_no "Do you want to proceed with creating this new Tor hidden service?"; then
        print_colored $YELLOW "Installation cancelled by user"
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
        print_colored $RED "❌ Failed to start Tor service properly"
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
    
    print_colored $GREEN "✨ All done! Enjoy your Tor hidden service!"
    verbose_log "Script completed successfully"
}

# Trap to handle cleanup
trap 'print_colored $RED "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"
