#!/bin/bash

# shellcheck source=utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# funcs.sh - Reusable helper functions
# This file contains system detection, package management, and UI functions

# Function to detect init system
detect_init_system() {
    verbose_log "Detecting init system..."
    
    # Check for systemd first (most common)
    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
        SERVICE_CMD="systemctl"
        verbose_log "Detected systemd init system"
    # Check for OpenRC
    elif [[ -d /run/openrc ]] && command -v rc-service >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
        SERVICE_CMD="rc-service"
        verbose_log "Detected OpenRC init system"
    # Check for runit
    elif [[ -d /etc/runit ]] && command -v sv >/dev/null 2>&1; then
        INIT_SYSTEM="runit"
        SERVICE_CMD="sv"
        verbose_log "Detected runit init system"
    # Check for SysV init
    elif [[ -d /etc/init.d ]] && command -v service >/dev/null 2>&1; then
        INIT_SYSTEM="sysv"
        SERVICE_CMD="service"
        verbose_log "Detected SysV init system"
    # Check for s6
    elif [[ -d /run/s6 ]] && command -v s6-svc >/dev/null 2>&1; then
        INIT_SYSTEM="s6"
        SERVICE_CMD="s6-svc"
        verbose_log "Detected s6 init system"
    # Check for dinit
    elif [[ -S /run/dinitctl ]] && command -v dinitctl >/dev/null 2>&1; then
        INIT_SYSTEM="dinit"
        SERVICE_CMD="dinitctl"
        verbose_log "Detected dinit init system"
    # Fallback to none
    else
        INIT_SYSTEM="none"
        SERVICE_CMD=""
        verbose_log "No supported init system detected"
        print_colored "$(c_warning)" "⚠️  Warning: No supported init system detected. Services will use manual PID management."
    fi
    
    verbose_log "Init system: $INIT_SYSTEM, Service command: $SERVICE_CMD"
}

# Function to detect distribution and package manager
detect_system() {
    print_colored "$(c_info)" "🔍 Detecting system distribution..."
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
        print_colored "$(c_error)" "❌ Unsupported package manager detected!"
        print_colored "$(c_warning)" "This script supports: apt, yum, dnf, pacman, zypper"
        exit 1
    fi
    
    # Detect init system
    detect_init_system
    
    print_colored "$(c_success)" "✅ Detected: $DISTRO ($PACKAGE_MANAGER) with $INIT_SYSTEM"
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
        print_colored "$(c_highlight)" "$title"
        echo
        
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                print_colored "$(c_success)" "► ${options[$i]}"
            else
                print_colored "$WHITE" "  ${options[$i]}"
            fi
        done
        
        echo
        print_colored "$(c_muted)" "Use ↑/↓ arrow keys to navigate, Enter to select"

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
    
    print_colored "$(c_process)" "📦 Installing packages: ${packages[*]}"
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
        print_colored "$(c_success)" "✅ Tor is already installed"
        sleep 1.5
        return 0
    else
        print_colored "$(c_warning)" "⚠️  Tor is not installed"
        sleep 1.5
        return 1
    fi
}

# Function to install Tor
install_tor() {
    print_colored "$(c_process)" "🔧 Installing Tor..."
    
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
    
    print_colored "$(c_success)" "✅ Tor installation completed"
    sleep 2
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
            print_colored "$RED" "❌ No available ports found"
            exit 1
        fi
    done
    
    verbose_log "Found available port: $test_port"
    echo "$test_port"
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
            print_colored "$YELLOW" "⚠️  Please manually $action Tor service"
            return 1
            ;;
    esac
}

# Function to install web dependencies
install_web_dependencies() {
    print_colored "$(c_process)" "📦 Installing web dependencies..."
    
    # Check if Python3 is installed
    if ! command -v python3 >/dev/null 2>&1; then
        verbose_log "Python3 not found, installing..."
        print_colored "$(c_process)" "🔧 Installing Python3..."
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
        print_colored "$(c_success)" "✅ Python3 installed successfully"
        sleep 1.5 
    else
        print_colored "$(c_success)" "✅ Python3 is already installed"
        verbose_log "Python3 found: $(python3 --version)"
        sleep 1
    fi
    
    # Check if curl is installed (for server testing)
    if ! command -v curl >/dev/null 2>&1; then
        verbose_log "curl not found, installing..."
        print_colored "$(c_process)" "🔧 Installing curl..."
        case $PACKAGE_MANAGER in
            "apt")
                install_packages curl
                ;;
            "yum"|"dnf")
                install_packages curl
                ;;
            "pacman")
                install_packages curl
                ;;
            "zypper")
                install_packages curl
                ;;
        esac
        print_colored "$(c_success)" "✅ curl installed successfully"
        sleep 1.5
    else
        verbose_log "curl is already installed"
    fi
    
    print_colored "$(c_success)" "✅ Web dependencies installed"
    sleep 1.5
}

# Function to configure Tor hidden service
configure_tor() {
    print_colored "$(c_process)" "⚙️  Configuring Tor hidden service..."

    local service_name; service_name=$(basename "$HIDDEN_SERVICE_DIR")

    # Variables for logging before adding to torrc
    local hs_dir_log="$HIDDEN_SERVICE_DIR"
    local hs_port_log="$TEST_SITE_PORT"
    
    # Backup original torrc
    if [[ -f "$TORRC_FILE" ]] && [[ ! -f "$TORRC_FILE.backup" ]]; then
        cp "$TORRC_FILE" "$TORRC_FILE.backup"
        print_colored "$(c_success)" "✅ Backed up original torrc file"
        sleep 1
    fi
    
    # Check if this hidden service is already configured
    if grep -q "HiddenServiceDir $HIDDEN_SERVICE_DIR" "$TORRC_FILE" 2>/dev/null; then
        print_colored "$(c_warning)" "⚠️  Hidden service already configured in torrc"
        sleep 2
        return 0
    fi
    
    # Do all verbose logging before heredoc
    verbose_log "Adding hidden service configuration to torrc..."
    verbose_log "Service name: $service_name"
    verbose_log "Hidden service directory: $hs_dir_log"
    verbose_log "Hidden service port mapping: 80 -> 0.0.0.0:$hs_port_log (all interfaces)"
    
    # Add hidden service configuration without any logging in between
    # Changed from 127.0.0.1 to 0.0.0.0 to allow access from all interfaces
    cat >> "$TORRC_FILE" << EOF

# Hidden Service Configuration - $service_name
HiddenServiceDir $HIDDEN_SERVICE_DIR/
HiddenServicePort 80 0.0.0.0:$TEST_SITE_PORT
EOF
    
    print_colored "$(c_success)" "✅ Tor configuration updated (broadcasting on all interfaces)"
    
    # Restart Tor to apply the new configuration
    print_colored "$(c_process)" "🔄 Restarting Tor to apply configuration changes..."
    verbose_log "Restarting Tor service to pick up torrc changes..."
    
    case "$INIT_SYSTEM" in
        "systemd")
            if systemctl restart tor; then
                print_colored "$(c_success)" "✅ Tor service restarted successfully"
                verbose_log "Tor restarted with systemctl"
            else
                print_colored "$(c_error)" "❌ Failed to restart Tor service"
                update_service_in_registry "$service_name" "status" "ERROR"
                return 1
            fi
            ;;
        "sysv")
            if service tor restart; then
                print_colored "$(c_success)" "✅ Tor service restarted successfully"
                verbose_log "Tor restarted with service command"
            else
                print_colored "$(c_error)" "❌ Failed to restart Tor service"
                update_service_in_registry "$service_name" "status" "ERROR"
                return 1
            fi
            ;;
        *)
            print_colored "$(c_warning)" "⚠️  Please manually restart Tor service to apply changes"
            print_colored "$(c_secondary)" "Run: sudo systemctl restart tor"
            sleep 3
            ;;
    esac
    
    # Give Tor a moment to start up before continuing
    print_colored "$(c_process)" "⏳ Waiting for Tor to start up..."
    sleep 3
    
    # Verify Tor is running
    case "$INIT_SYSTEM" in
        "systemd")
            if systemctl is-active tor >/dev/null 2>&1; then
                print_colored "$(c_success)" "✅ Tor is running and ready"
                verbose_log "Tor service is active"
            else
                print_colored "$(c_error)" "❌ Tor failed to start properly"
                update_service_in_registry "$service_name" "status" "ERROR"
                return 1
            fi
            ;;
        "sysv")
            if pgrep -x tor >/dev/null; then
                print_colored "$(c_success)" "✅ Tor is running and ready"
                verbose_log "Tor process is running"
            else
                print_colored "$(c_error)" "❌ Tor failed to start properly"
                update_service_in_registry "$service_name" "status" "ERROR"
                return 1
            fi
            ;;
    esac
    
    sleep 2
}

# Function to start and enable Tor
start_tor() {
    print_colored "$(c_process)" "🔍 Checking Tor service status..."
    verbose_log "Service manager: $INIT_SYSTEM"

    local service_name; service_name=$(basename "$HIDDEN_SERVICE_DIR")

    # Check if Tor is already running
    case "$INIT_SYSTEM" in
        "systemd")
            if systemctl is-active tor >/dev/null 2>&1; then
                print_colored "$(c_success)" "✅ Tor service is already running"
                verbose_log "Tor service is already active"
            else
                print_colored "$(c_warning)" "⚠️  Tor service not running, starting..."
                if systemctl start tor; then
                    print_colored "$(c_success)" "✅ Tor service started successfully"
                    verbose_log "Tor service started successfully"
                else
                    print_colored "$(c_error)" "❌ Failed to start Tor service"
                    update_service_in_registry "$service_name" "status" "ERROR"
                    return 1
                fi
            fi
            
            if ask_yes_no "Do you want Tor to start automatically on system boot?"; then
                verbose_log "Enabling Tor service for auto-start..."
                print_colored "$(c_process)" "🔧 Enabling Tor for auto-start..."
                if systemctl enable tor 2>/dev/null; then
                    print_colored "$(c_success)" "✅ Tor enabled for auto-start"
                    verbose_log "Tor enabled for auto-start"
                    sleep 1.5
                else
                    print_colored "$(c_warning)" "⚠️  Could not enable auto-start (non-critical)"
                    verbose_log "Could not enable auto-start"
                    sleep 2
                fi
            fi
            ;;
        "sysv")
            verbose_log "Using SysV service manager..."
            if pgrep -x tor >/dev/null; then
                print_colored "$(c_success)" "✅ Tor service is already running"
                verbose_log "Tor process is already running"
            else
                print_colored "$(c_warning)" "⚠️  Tor service not running, starting..."
                if service tor start; then
                    print_colored "$(c_success)" "✅ Tor service started successfully"
                    verbose_log "Tor service started with SysV"
                else
                    print_colored "$(c_error)" "❌ Failed to start Tor service"
                    update_service_in_registry "$service_name" "status" "ERROR"
                    return 1
                fi
            fi
            print_colored "$(c_warning)" "⚠️  Auto-start configuration varies by system"
            sleep 2
            ;;
    esac
    
    # Wait for Tor to generate the hidden service
    print_colored "$(c_process)" "⏳ Waiting for Tor to generate hidden service..."
    verbose_log "Waiting for hostname file: $HIDDEN_SERVICE_DIR/hostname"
    sleep 1
    
    # Check if hidden service directory was created
    local count=0
    local max_wait=30  # Reduced from 60 to 30 since Tor should start faster after restart
    
    while [[ ! -f "$HIDDEN_SERVICE_DIR/hostname" ]] && [[ $count -lt $max_wait ]]; do
        sleep 2
        ((count++))
        echo -n "."
        
        verbose_log "Wait attempt $count/$max_wait - checking for hostname file..."
        
        # Check if Tor is still running
        case "$INIT_SYSTEM" in
            "systemd")
                if ! systemctl is-active tor >/dev/null 2>&1; then
                    echo
                    print_colored "$(c_error)" "❌ Tor service stopped during hostname generation"
                    update_service_in_registry "$service_name" "status" "ERROR"
                    return 1
                fi
                ;;
            "sysv")
                if ! pgrep -x tor >/dev/null; then
                    echo
                    print_colored "$(c_error)" "❌ Tor process died during hostname generation"
                    update_service_in_registry "$service_name" "status" "ERROR"
                    return 1
                fi
                ;;
        esac
    done
    echo
    
    if [[ -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        local onion_addr
        onion_addr=$(cat "$HIDDEN_SERVICE_DIR/hostname")
        
        print_colored "$(c_success)" "✅ Hidden service generated successfully"
        verbose_log "Hostname file found: $HIDDEN_SERVICE_DIR/hostname"
        verbose_log "Generated .onion address: $onion_addr"
        sleep 2
        print_colored "$(c_success)" "🎉 Your hidden service is available at: $onion_addr"
        # Update registry with onion address and active status
        update_service_in_registry "$service_name" "onion_address" "$onion_addr"
        update_service_in_registry "$service_name" "status" "ACTIVE"
        
        return 0
    else
        print_colored "$(c_error)" "❌ Failed to generate hidden service after ${max_wait} attempts"
        print_colored "$(c_warning)" "📋 Troubleshooting suggestions:"
        print_colored "$(c_text)" "• Check Tor logs: journalctl -u tor -n 20"
        print_colored "$(c_text)" "• Verify torrc syntax: sudo tor --verify-config"
        print_colored "$(c_text)" "• Check directory permissions: ls -la $HIDDEN_SERVICE_BASE_DIR"
        update_service_in_registry "$service_name" "status" "ERROR"
        sleep 5
        return 1
    fi
}

# Function to create test website
create_test_website() {
    print_colored "$(c_process)" "🌐 Creating test website..."
    
    # Create directory
    mkdir -p "$TEST_SITE_DIR"
    
    # Get dynamic CSS based on color scheme
    local webpage_style
    webpage_style=$(get_webpage_style)
    
    # Create simple HTML page with dynamic port and styling
    cat > "$TEST_SITE_DIR/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tor Hidden Service - Test Page</title>
    <style>
$webpage_style
        ul {
            color: inherit;
        }
        li {
            margin: 8px 0;
        }
        .scheme-info {
            font-size: 12px;
            opacity: 0.7;
            margin-top: 20px;
        }
        .network-info {
            background: rgba(200, 200, 200, 0.2);
            padding: 15px;
            border-radius: 8px;
            margin: 15px 0;
            border-left: 4px solid #667eea;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="success">🎉 Your Tor Hidden Service is Working!</div>
        <p>Congratulations! You have successfully set up a Tor hidden service.</p>
        
        <div class="info">
            <h3>📍 Service Information:</h3>
            <p><strong>Local Port:</strong> $TEST_SITE_PORT</p>
            <p><strong>Network Binding:</strong> All interfaces (0.0.0.0)</p>
            <p><strong>Access:</strong> Via Tor Browser only</p>
            <p><strong>Security:</strong> Traffic is automatically encrypted through Tor</p>
            <p><strong>Color Scheme:</strong> $COLOR_SCHEME</p>
        </div>
        
        <div class="network-info">
            <h3>🌐 Network Access:</h3>
            <p><strong>Tor Hidden Service:</strong> Accessible globally via .onion address</p>
            <p><strong>Local Network:</strong> Accessible from LAN via port $TEST_SITE_PORT</p>
            <p><strong>Security Note:</strong> Local access bypasses Tor anonymity</p>
        </div>
        
        <div class="info">
            <h3>🔧 Next Steps:</h3>
            <ul style="text-align: left;">
                <li>Replace this test page with your actual website</li>
                <li>Configure your web application to run on port $TEST_SITE_PORT</li>
                <li>Share your .onion address securely with intended users</li>
                <li>Consider additional security measures for production use</li>
                <li>Be aware that local network access bypasses Tor anonymity</li>
            </ul>
        </div>
        
        <div class="scheme-info">
            <p><small>Generated by Tor Hidden Service Setup Script (Theme: $COLOR_SCHEME)</small></p>
        </div>
    </div>
</body>
</html>
EOF
    
    # Create simple Python web server script with dynamic port
    # Changed to bind to 0.0.0.0 instead of 127.0.0.1 for all interfaces
    cat > "$TEST_SITE_DIR/server.py" << EOF
#!/usr/bin/env python3
import http.server
import socketserver
import os

PORT = $TEST_SITE_PORT
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
    
    def log_message(self, format, *args):
        # Enhanced logging with client IP
        client_ip = self.client_address[0]
        print(f"[{self.log_date_time_string()}] {client_ip} - {format % args}")

if __name__ == "__main__":
    # Bind to all interfaces (0.0.0.0) instead of just localhost
    with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
        print(f"🌐 Serving at http://0.0.0.0:{PORT}")
        print(f"📡 Accessible from:")
        print(f"   • Tor Browser: via .onion address")
        print(f"   • Local network: http://localhost:{PORT}")
        print(f"   • LAN devices: http://[your-ip]:{PORT}")
        print(f"⚠️  Note: Local access bypasses Tor anonymity!")
        print("Press Ctrl+C to stop the server")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n🛑 Server stopped.")
EOF
    
    chmod +x "$TEST_SITE_DIR/server.py"
    
    print_colored "$(c_success)" "✅ Test website created at $TEST_SITE_DIR"
    print_colored "$(c_warning)" "⚠️  Server will bind to all interfaces (0.0.0.0:$TEST_SITE_PORT)"
    print_colored "$(c_warning)" "⚠️  Local network access bypasses Tor anonymity!"
    verbose_log "Website created with port $TEST_SITE_PORT using $COLOR_SCHEME theme, binding to all interfaces"
    sleep 1.5
}

# Function to setup dynamic paths and ports
setup_dynamic_config() {
    print_colored "$(c_info)" "🔍 Setting up new hidden service configuration..."
    
    # Initialize service tracking
    init_service_tracking
    
    # Generate guaranteed unique service name
    local service_name
    service_name=$(generate_unique_service_name)
    
    if [[ -z "$service_name" ]]; then
        print_colored "$(c_error)" "❌ Failed to generate unique service name"
        exit 1
    fi
    
    verbose_log "Generated unique service name: $service_name"
    
    # Set paths
    HIDDEN_SERVICE_DIR="$HIDDEN_SERVICE_BASE_DIR/$service_name"
    
    # Find available port
    local existing_ports=()
    if [[ -f "$SERVICES_FILE" ]]; then
        while IFS='|' read -r name dir port onion website status system_service created; do
            [[ "$name" =~ ^#.*$ ]] || [[ -z "$name" ]] && continue
            [[ -n "$port" ]] && existing_ports+=("$port")
        done < "$SERVICES_FILE"
    fi
    
    local test_port="$TEST_SITE_BASE_PORT"
    while ss -tlpn 2>/dev/null | grep -q ":$test_port " || [[ " ${existing_ports[*]} " =~ $test_port ]]; do
        ((test_port++))
        if [[ $test_port -gt 65535 ]]; then
            print_colored "$(c_error)" "❌ No available ports found"
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
    verbose_log "  Website dir (potential): $TEST_SITE_DIR"
    
    print_colored "$(c_success)" "✅ Service name: $service_name"
    print_colored "$(c_success)" "✅ Hidden service directory: $HIDDEN_SERVICE_DIR"
    print_colored "$(c_success)" "✅ Local port: $TEST_SITE_PORT"
    print_colored "$(c_success)" "✅ Website directory: $TEST_SITE_DIR"
    
    # Add to registry (initially with inactive status, no website directory, and no system service)
    add_service_to_registry "$service_name" "$HIDDEN_SERVICE_DIR" "$TEST_SITE_PORT" "" "" "INACTIVE" ""
    
    sleep 2
}

# Function to display final results (updated to use registry and dynamic colors)
show_results() {
    clear
    print_header

    local service_name; service_name=$(basename "$HIDDEN_SERVICE_DIR")

    # Give one more chance to find the hostname file
    if [[ ! -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        print_colored "$(c_info)" "🔍 Making final check for hostname file..."
        sleep 5
    fi
    
    if [[ -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        local onion_address
        onion_address=$(cat "$HIDDEN_SERVICE_DIR/hostname")
        
        # Get service info from registry to check if website was set up
        local service_info
        service_info=$(grep "^$service_name|" "$SERVICES_FILE" 2>/dev/null)
        local website_dir=""
        if [[ -n "$service_info" ]]; then
            # IFS='|' read -r name dir port onion website status created <<< "$service_info"
            IFS='|' read -r _ _ _ _ website_dir _ _ <<< "$service_info"
            website_dir="$website_dir"
        fi
        
        print_colored "$(c_success)" "🎉 Setup Complete!"
        echo
        print_colored "$(c_border)" "    ╔══════════════════════════════════════════════════════════════════╗"
        print_colored "$(c_border)" "    ║$(echo -e "$(c_accent)                        YOUR .ONION ADDRESS                       $(c_border)")║"
        print_colored "$(c_border)" "    ╠══════════════════════════════════════════════════════════════════╣"
        print_colored "$(c_border)" "    ║$(echo -e "$(c_text)  $onion_address  $(c_border)")║"
        print_colored "$(c_border)" "    ╚══════════════════════════════════════════════════════════════════╝"
        echo
        print_colored "$(c_highlight)"   "Your Tor Hidden Service Details:"
        print_colored "$(c_text)"  "════════════════════════════════════"
        print_colored "$(c_warning)" "🏷️ Service Name: $service_name"
        print_colored "$(c_warning)" "🌐 Onion Address: $onion_address"
        print_colored "$(c_warning)" "📁 Service Directory: $HIDDEN_SERVICE_DIR"
        print_colored "$(c_warning)" "🔌 Local Port: $TEST_SITE_PORT"
        # print_colored "$(c_warning)" "🎨 Color Scheme: $COLOR_SCHEME" # Not needed
        
        # Only show website directory if it was actually set up
        if [[ -n "$website_dir" ]] && [[ -d "$website_dir" ]]; then
            print_colored "$(c_warning)" "🌍 Website Directory: $website_dir"
            
            # Show the local web address with proper binding detection and underline
            if [[ -n "$TEST_SITE_PORT" ]]; then
                local web_display_address
                web_display_address=$(get_web_server_display_address "$TEST_SITE_PORT")
                echo -e "$(c_warning)🔗 Local Web Address: $(c_highlight)${UNDERLINE}http://$web_display_address${RESET}"
            fi
        fi
        
        echo
        print_colored "$(c_highlight)"  "To access your site:"
        print_colored "$(c_text)" "1. Open Tor Browser"
        print_colored "$(c_text)" "2. Navigate to: http://$onion_address"
        
        # Show local access information if website exists
        if [[ -n "$website_dir" ]] && [[ -d "$website_dir" ]] && [[ -n "$TEST_SITE_PORT" ]]; then
            echo
            print_colored "$(c_highlight)" "Local network access:"
            local web_display_address
            web_display_address=$(get_web_server_display_address "$TEST_SITE_PORT")
            local binding_type
            binding_type=$(get_web_server_binding "$TEST_SITE_PORT")
            
            case "$binding_type" in
                "ALL_INTERFACES")
                    echo -e "$(c_text)• Direct access: $(c_highlight)${UNDERLINE}http://$web_display_address${RESET}"
                    print_colored "$(c_warning)" "  ⚠️  This bypasses Tor anonymity!"
                    ;;
                "LOCALHOST_ONLY")
                    echo -e "$(c_text)• Localhost only: $(c_highlight)${UNDERLINE}http://$web_display_address${RESET}"
                    print_colored "$(c_success)" "  ✅ Preserves anonymity (localhost only)"
                    ;;
                *)
                    print_colored "$(c_text)" "• Server binding: $binding_type"
                    ;;
            esac
        fi
        
        echo
        print_colored "$(c_highlight)"  "To manage your services:"
        print_colored "$(c_text)" "• List all services: $0 --list"
        
        # Only show test server command if website was set up
        if [[ -n "$website_dir" ]] && [[ -d "$website_dir" ]]; then
            print_colored "$(c_text)" "• Start test server: cd $website_dir && python3 server.py"
        fi
        
        print_colored "$(c_text)" "• Tor config: $TORRC_FILE"
        print_colored "$(c_text)" "• Services registry: $SERVICES_FILE"
        echo
        print_colored "$(c_accent)" "🔒 Remember: Your site is only accessible via Tor Browser!"
        echo
        print_colored "$(c_success)" "💡 TIP: Use '$0 --list' to see all your hidden services!"
    else
        update_service_in_registry "$service_name" "status" "ERROR"
        print_colored "$(c_error)" "❌ Setup completed but no .onion address found"
        print_colored "$(c_warning)" "📋 Troubleshooting Information:"
        print_colored "$(c_text)" "• Tor service status: $(systemctl is-active tor 2>/dev/null || echo 'unknown')"
        print_colored "$(c_text)" "• Hidden service dir: $HIDDEN_SERVICE_DIR"
        print_colored "$(c_text)" "• Torrc config file: $TORRC_FILE"
        echo
        print_colored "$(c_highlight)" "🔧 Manual troubleshooting steps:"
        print_colored "$(c_text)" "1. Check Tor logs: journalctl -u tor -f"
        print_colored "$(c_text)" "2. Verify config: sudo tor --verify-config"
        print_colored "$(c_text)" "3. Restart Tor: sudo systemctl restart tor"
        print_colored "$(c_text)" "4. Wait 30 seconds then check: sudo cat $HIDDEN_SERVICE_DIR/hostname"
        print_colored "$(c_text)" "5. Check permissions: sudo ls -la $HIDDEN_SERVICE_BASE_DIR"
    fi
}

### 🍉 mwatermelon
### "You wouldn't download a car..."
###  - Motion Picture Association (2004)

### End of src/funcs.sh
