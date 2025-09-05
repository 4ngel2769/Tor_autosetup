#!/bin/bash

# shellcheck source=utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# funcs.sh - Reusable helper functions
# This file contains system detection, package management, and UI functions

# Function to detect distribution and package manager
detect_system() {
    print_colored "$BLUE" "🔍 Detecting system distribution..."
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
        print_colored "$RED" "❌ Unsupported package manager detected!"
        print_colored "$YELLOW" "This script supports: apt, yum, dnf, pacman, zypper"
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
        print_colored "$YELLOW" "⚠️  Warning: No supported service manager found"
        SERVICE_MANAGER="none"
        verbose_log "No supported service manager found"
    fi
    
    print_colored "$GREEN" "✅ Detected: $DISTRO ($PACKAGE_MANAGER) with $SERVICE_MANAGER"
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
        print_colored "$CYAN" "$title"
        echo
        
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                print_colored "$GREEN" "► ${options[$i]}"
            else
                print_colored "$WHITE" "  ${options[$i]}"
            fi
        done
        
        echo
        print_colored "$YELLOW" "Use ↑/↓ arrow keys to navigate, Enter to select"
        
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
    
    print_colored "$BLUE" "📦 Installing packages: ${packages[*]}"
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
        print_colored "$HTB_GREEN" "✅ Tor is already installed"
        sleep 1.5  # Give user time to read the message
        return 0
    else
        print_colored "$HTB_YELLOW" "⚠️  Tor is not installed"
        sleep 1.5
        return 1
    fi
}

# Function to install Tor
install_tor() {
    print_colored "$HTB_NEON_BLUE" "🔧 Installing Tor..."
    
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
    
    print_colored "$HTB_GREEN" "✅ Tor installation completed"
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
    print_colored "$HTB_NEON_BLUE" "📦 Installing web dependencies..."
    
    # Check if Python3 is installed
    if ! command -v python3 >/dev/null 2>&1; then
        verbose_log "Python3 not found, installing..."
        print_colored "$HTB_NEON_BLUE" "🔧 Installing Python3..."
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
        print_colored "$HTB_GREEN" "✅ Python3 installed successfully"
        sleep 1.5 
    else
        print_colored "$HTB_GREEN" "✅ Python3 is already installed"
        verbose_log "Python3 found: $(python3 --version)"
        sleep 1
    fi
    
    # Check if curl is installed (for server testing)
    if ! command -v curl >/dev/null 2>&1; then
        verbose_log "curl not found, installing..."
        print_colored "$HTB_NEON_BLUE" "🔧 Installing curl..."
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
        print_colored "$HTB_GREEN" "✅ curl installed successfully"
        sleep 1.5
    else
        verbose_log "curl is already installed"
    fi
    
    print_colored "$HTB_GREEN" "✅ Web dependencies installed"
    sleep 1.5
}

# Function to configure Tor hidden service
configure_tor() {
    print_colored "$HTB_NEON_BLUE" "⚙️  Configuring Tor hidden service..."
    
    local service_name=$(basename "$HIDDEN_SERVICE_DIR")
    
    # Variables for logging before adding to torrc
    local hs_dir_log="$HIDDEN_SERVICE_DIR"
    local hs_port_log="$TEST_SITE_PORT"
    
    # Backup original torrc
    if [[ -f "$TORRC_FILE" ]] && [[ ! -f "$TORRC_FILE.backup" ]]; then
        cp "$TORRC_FILE" "$TORRC_FILE.backup"
        print_colored "$HTB_GREEN" "✅ Backed up original torrc file"
        sleep 1
    fi
    
    # Check if this hidden service is already configured
    if grep -q "HiddenServiceDir $HIDDEN_SERVICE_DIR" "$TORRC_FILE" 2>/dev/null; then
        print_colored "$HTB_YELLOW" "⚠️  Hidden service already configured in torrc"
        sleep 2
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
    
    print_colored "$HTB_GREEN" "✅ Tor configuration updated"
    sleep 2
}

# Function to start and enable Tor
start_tor() {
    print_colored "$HTB_NEON_BLUE" "🚀 Starting Tor service..."
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
                print_colored "$HTB_GREEN" "✅ Tor service started successfully"
                verbose_log "Tor service started successfully"
                sleep 1.5
            else
                print_colored "$HTB_RED" "❌ Failed to start Tor service"
                update_service_in_registry "$service_name" "status" "ERROR"
                sleep 2
                return 1
            fi
            
            if ask_yes_no "Do you want Tor to start automatically on system boot?"; then
                verbose_log "Enabling Tor service for auto-start..."
                print_colored "$HTB_NEON_BLUE" "🔧 Enabling Tor for auto-start..."
                if systemctl enable tor 2>/dev/null; then
                    print_colored "$HTB_GREEN" "✅ Tor enabled for auto-start"
                    verbose_log "Tor enabled for auto-start"
                    sleep 1.5
                else
                    print_colored "$HTB_YELLOW" "⚠️  Could not enable auto-start (non-critical)"
                    verbose_log "Could not enable auto-start"
                    sleep 2
                fi
            fi
            ;;
        "sysv")
            verbose_log "Using SysV service manager..."
            service tor stop 2>/dev/null || true
            if service tor start; then
                print_colored "$HTB_GREEN" "✅ Tor service started successfully"
                verbose_log "Tor service started with SysV"
                sleep 1.5
            else
                print_colored "$HTB_RED" "❌ Failed to start Tor service"
                update_service_in_registry "$service_name" "status" "ERROR"
                sleep 2
                return 1
            fi
            print_colored "$HTB_YELLOW" "⚠️  Auto-start configuration varies by system"
            sleep 2
            ;;
    esac
    
    # Wait for Tor to generate the hidden service
    print_colored "$HTB_NEON_BLUE" "⏳ Waiting for Tor to generate hidden service..."
    verbose_log "Waiting for hostname file: $HIDDEN_SERVICE_DIR/hostname"
    sleep 1
    
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
            print_colored "$HTB_RED" "❌ Tor process died during startup"
            update_service_in_registry "$service_name" "status" "ERROR"
            sleep 2
            return 1
        fi
    done
    echo
    
    if [[ -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        local onion_addr
        onion_addr=$(cat "$HIDDEN_SERVICE_DIR/hostname")
        
        print_colored "$HTB_GREEN" "✅ Hidden service generated successfully"
        verbose_log "Hostname file found: $HIDDEN_SERVICE_DIR/hostname"
        verbose_log "Generated .onion address: $onion_addr"
        sleep 2
        print_colored "$HTB_GREEN" "🎉 Your hidden service is available at: $onion_addr"
        # Update registry with onion address and active status
        update_service_in_registry "$service_name" "onion_address" "$onion_addr"
        update_service_in_registry "$service_name" "status" "ACTIVE"
        
        return 0
    else
        print_colored "$HTB_RED" "❌ Failed to generate hidden service after ${max_wait} attempts"
        update_service_in_registry "$service_name" "status" "ERROR"
        sleep 3
        return 1
    fi
}

# Function to create test website
create_test_website() {
    print_colored "$HTB_NEON_BLUE" "🌐 Creating test website..."
    
    # Create directory
    mkdir -p "$TEST_SITE_DIR"
    
    # Create simple HTML page with dynamic port
    cat > "$TEST_SITE_DIR/index.html" << EOF
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
            <p><strong>Local Port:</strong> $TEST_SITE_PORT</p>
            <p><strong>Access:</strong> Via Tor Browser only</p>
            <p><strong>Security:</strong> Traffic is automatically encrypted through Tor</p>
        </div>
        
        <div class="info">
            <h3>🔧 Next Steps:</h3>
            <ul style="text-align: left;">
                <li>Replace this test page with your actual website</li>
                <li>Configure your web application to run on port $TEST_SITE_PORT</li>
                <li>Share your .onion address securely with intended users</li>
                <li>Consider additional security measures for production use</li>
            </ul>
        </div>
        
        <p><small>Generated by Tor Hidden Service Setup Script</small></p>
    </div>
</body>
</html>
EOF
    
    # Create simple Python web server script with dynamic port
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

if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        print(f"Serving at http://127.0.0.1:{PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")
EOF
    
    chmod +x "$TEST_SITE_DIR/server.py"
    
    print_colored "$HTB_GREEN" "✅ Test website created at $TEST_SITE_DIR"
    verbose_log "Website created with port $TEST_SITE_PORT"
    sleep 1.5
}

# Function to setup dynamic paths and ports
setup_dynamic_config() {
    print_colored "$BLUE" "🔍 Setting up new hidden service configuration..."
    
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
            print_colored "$RED" "❌ No available ports found"
            exit 1
        fi
    done
    TEST_SITE_PORT="$test_port"
    
    # Set test site directory (but don't create it yet)
    TEST_SITE_DIR="$TEST_SITE_BASE_DIR/$service_name"
    
    verbose_log "Generated service configuration:"
    verbose_log "  Service name: $service_name"
    verbose_log "  Hidden service dir: $HIDDEN_SERVICE_DIR"
    verbose_log "  Port: $TEST_SITE_PORT"
    verbose_log "  Website dir (potential): $TEST_SITE_DIR"
    
    print_colored "$GREEN" "✅ Service name: $service_name"
    print_colored "$GREEN" "✅ Hidden service directory: $HIDDEN_SERVICE_DIR"
    print_colored "$GREEN" "✅ Local port: $TEST_SITE_PORT"
    print_colored "$GREEN" "✅ Website directory: $TEST_SITE_DIR"
    
    # Add to registry (initially with inactive status and no website directory)
    add_service_to_registry "$service_name" "$HIDDEN_SERVICE_DIR" "$TEST_SITE_PORT" "" "" "INACTIVE"
    
    sleep 2
}

# Function to display final results (updated to use registry)
show_results() {
    clear
    print_header
    
    local service_name=$(basename "$HIDDEN_SERVICE_DIR")
    
    # Give one more chance to find the hostname file
    if [[ ! -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        print_colored "$BLUE" "🔍 Making final check for hostname file..."
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
            IFS='|' read -r name dir port onion website status created <<< "$service_info"
            website_dir="$website"
        fi
        
        print_colored "$GREEN" "🎉 Setup Complete!"
        echo
        print_colored "$PURPLE" "╔══════════════════════════════════════════════════════════════════╗"
        print_colored "$PURPLE" "║                        YOUR .ONION ADDRESS                       ║"
        print_colored "$PURPLE" "╠══════════════════════════════════════════════════════════════════╣"
        print_colored "$WHITE"  "║  $onion_address  ║"
        print_colored "$PURPLE" "╚══════════════════════════════════════════════════════════════════╝"
        echo
        print_colored "$CYAN"   "Your Tor Hidden Service Details:"
        print_colored "$WHITE"  "════════════════════════════════════"
        print_colored "$YELLOW" "🏷️ Service Name: $service_name"
        print_colored "$YELLOW" "🌐 Onion Address: $onion_address"
        print_colored "$YELLOW" "🔌 Local Port: $TEST_SITE_PORT"
        print_colored "$YELLOW" "📁 Service Directory: $HIDDEN_SERVICE_DIR"
        
        # Only show website directory if it was actually set up
        if [[ -n "$website_dir" ]] && [[ -d "$website_dir" ]]; then
            print_colored "$YELLOW" "🌍 Website Directory: $website_dir"
        fi
        
        echo
        print_colored "$CYAN"  "To access your site:"
        print_colored "$WHITE" "1. Open Tor Browser"
        print_colored "$WHITE" "2. Navigate to: ${UNDERLINE}https://$onion_address${RESET}"
        echo
        print_colored "$CYAN"  "To manage your services:"
        print_colored "$WHITE" "• List all services: $0 --list"
        
        # Only show test server command if website was set up
        if [[ -n "$website_dir" ]] && [[ -d "$website_dir" ]]; then
            print_colored "$WHITE" "• Start test server: cd $website_dir && python3 server.py"
        fi
        
        print_colored "$WHITE" "• Tor config: $TORRC_FILE"
        print_colored "$WHITE" "• Services registry: $SERVICES_FILE"
        echo
        print_colored "$PURPLE" "🔒 Remember: Your site is only accessible via Tor Browser!"
        echo
        print_colored "$GREEN" "💡 TIP: Use '$0 --list' to see all your hidden services!"
    else
        update_service_in_registry "$service_name" "status" "ERROR"
        print_colored "$RED" "❌ Setup completed but no .onion address found"
        print_colored "$YELLOW" "📋 Troubleshooting Information:"
        print_colored "$WHITE" "• Tor service status: $(systemctl is-active tor 2>/dev/null || echo 'unknown')"
        print_colored "$WHITE" "• Hidden service dir: $HIDDEN_SERVICE_DIR"
        print_colored "$WHITE" "• Torrc config file: $TORRC_FILE"
        echo
        print_colored "$CYAN" "🔧 Manual troubleshooting steps:"
        print_colored "$WHITE" "1. Check Tor logs: journalctl -u tor -f"
        print_colored "$WHITE" "2. Verify config: sudo tor --verify-config"
        print_colored "$WHITE" "3. Restart Tor: sudo systemctl restart tor"
        print_colored "$WHITE" "4. Wait 30 seconds then check: sudo cat $HIDDEN_SERVICE_DIR/hostname"
        print_colored "$WHITE" "5. Check permissions: sudo ls -la $HIDDEN_SERVICE_BASE_DIR"
    fi
}
