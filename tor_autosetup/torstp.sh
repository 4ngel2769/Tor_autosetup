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

# Configuration
TORRC_FILE="/etc/tor/torrc"
HIDDEN_SERVICE_DIR="/var/lib/tor/hidden_service"
TEST_SITE_PORT=5000
TEST_SITE_DIR="/var/www/tor-test"

# Global variables
DISTRO=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
SERVICE_MANAGER=""

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print header
print_header() {
    clear
    print_colored $PURPLE "╔══════════════════════════════════════════════════════════════╗"
    print_colored $PURPLE "║                    Tor Hidden Service Setup                  ║"
    print_colored $PURPLE "║                   Automated Installation                     ║"
    print_colored $PURPLE "╚══════════════════════════════════════════════════════════════╝"
    echo
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_colored $RED "❌ This script must be run as root!"
        print_colored $YELLOW "Please run: sudo $0"
        exit 1
    fi
}

# Function to detect distribution and package manager
detect_system() {
    print_colored $BLUE "🔍 Detecting system distribution..."
    
    if command -v apt-get >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD="apt-get"
        if [[ -f /etc/debian_version ]]; then
            DISTRO="debian"
        elif [[ -f /etc/ubuntu-release ]] || grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
            DISTRO="ubuntu"
        else
            DISTRO="debian-based"
        fi
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
        INSTALL_CMD="yum"
        DISTRO="rhel-based"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
        INSTALL_CMD="dnf"
        DISTRO="fedora-based"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD="pacman"
        DISTRO="arch-based"
    elif command -v zypper >/dev/null 2>&1; then
        PACKAGE_MANAGER="zypper"
        INSTALL_CMD="zypper"
        DISTRO="suse-based"
    else
        print_colored $RED "❌ Unsupported package manager detected!"
        print_colored $YELLOW "This script supports: apt, yum, dnf, pacman, zypper"
        exit 1
    fi
    
    # Detect service manager
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_MANAGER="systemd"
    elif command -v service >/dev/null 2>&1; then
        SERVICE_MANAGER="sysv"
    else
        print_colored $YELLOW "⚠️  Warning: No supported service manager found"
        SERVICE_MANAGER="none"
    fi
    
    print_colored $GREEN "✅ Detected: $DISTRO ($PACKAGE_MANAGER) with $SERVICE_MANAGER"
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
    
    case $PACKAGE_MANAGER in
        "apt")
            apt-get update -qq
            apt-get install -y "${packages[@]}"
            ;;
        "yum"|"dnf")
            $INSTALL_CMD install -y "${packages[@]}"
            ;;
        "pacman")
            pacman -Syu --noconfirm "${packages[@]}"
            ;;
        "zypper")
            zypper install -y "${packages[@]}"
            ;;
    esac
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

# Function to configure Tor hidden service
configure_tor() {
    print_colored $BLUE "⚙️  Configuring Tor hidden service..."
    
    # Backup original torrc
    if [[ -f "$TORRC_FILE" ]] && [[ ! -f "$TORRC_FILE.backup" ]]; then
        cp "$TORRC_FILE" "$TORRC_FILE.backup"
        print_colored $GREEN "✅ Backed up original torrc file"
    fi
    
    # Add hidden service configuration
    cat >> "$TORRC_FILE" << EOF

# Hidden Service Configuration - Added by setup script
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
    
    case $SERVICE_MANAGER in
        "systemd")
            systemctl restart tor
            if ask_yes_no "Do you want Tor to start automatically on system boot?"; then
                systemctl enable tor
                print_colored $GREEN "✅ Tor enabled for auto-start"
            fi
            ;;
        "sysv")
            service tor restart
            print_colored $YELLOW "⚠️  Auto-start configuration varies by system"
            ;;
    esac
    
    # Wait for Tor to generate the hidden service
    print_colored $BLUE "⏳ Waiting for Tor to generate hidden service..."
    sleep 5
    
    # Check if hidden service directory was created
    local count=0
    while [[ ! -f "$HIDDEN_SERVICE_DIR/hostname" ]] && [[ $count -lt 30 ]]; do
        sleep 2
        ((count++))
        echo -n "."
    done
    echo
    
    if [[ -f "$HIDDEN_SERVICE_DIR/hostname" ]]; then
        print_colored $GREEN "✅ Hidden service generated successfully"
    else
        print_colored $RED "❌ Failed to generate hidden service"
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
    print_colored $BLUE "🚀 Starting test web server..."
    
    # Check if port is already in use
    if netstat -tlpn 2>/dev/null | grep -q ":$TEST_SITE_PORT "; then
        print_colored $YELLOW "⚠️  Port $TEST_SITE_PORT is already in use"
        print_colored $CYAN "You can manually start the server later with:"
        print_colored $WHITE "cd $TEST_SITE_DIR && python3 server.py"
        return 0
    fi
    
    # Start server in background
    cd "$TEST_SITE_DIR"
    nohup python3 server.py > /dev/null 2>&1 &
    
    sleep 2
    
    # Check if server started successfully
    if curl -s http://127.0.0.1:$TEST_SITE_PORT >/dev/null 2>&1; then
        print_colored $GREEN "✅ Test web server started successfully"
        return 0
    else
        print_colored $YELLOW "⚠️  Server may not have started correctly"
        print_colored $CYAN "You can manually start it with:"
        print_colored $WHITE "cd $TEST_SITE_DIR && python3 server.py"
        return 1
    fi
}

# Function to display final results
show_results() {
    clear
    print_header
    
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
        print_colored $YELLOW "🌐 Onion Address: $onion_address"
        print_colored $YELLOW "🔌 Local Port: $TEST_SITE_PORT"
        print_colored $YELLOW "📁 Service Directory: $HIDDEN_SERVICE_DIR"
        echo
        print_colored $CYAN "To access your site:"
        print_colored $WHITE "1. Open Tor Browser"
        print_colored $WHITE "2. Navigate to: http://$onion_address"
        echo
        print_colored $CYAN "To manage your site:"
        print_colored $WHITE "• Test site files: $TEST_SITE_DIR"
        print_colored $WHITE "• Start test server: cd $TEST_SITE_DIR && python3 server.py"
        print_colored $WHITE "• Tor config: $TORRC_FILE"
        print_colored $WHITE "• View .onion address: sudo cat $HIDDEN_SERVICE_DIR/hostname"
        echo
        print_colored $PURPLE "🔒 Remember: Your site is only accessible via Tor Browser!"
        echo
        print_colored $GREEN "💡 TIP: Save your .onion address somewhere safe!"
    else
        print_colored $RED "❌ Setup completed but no .onion address found"
        print_colored $YELLOW "Check Tor logs: journalctl -u tor"
        print_colored $CYAN "The hidden service may take a few more moments to generate."
        print_colored $CYAN "Try checking: sudo cat $HIDDEN_SERVICE_DIR/hostname"
    fi
}

# Main installation flow
main() {
    print_header
    check_root
    detect_system
    
    # Confirmation
    if ! ask_yes_no "Do you want to proceed with Tor hidden service installation?"; then
        print_colored $YELLOW "Installation cancelled by user"
        exit 0
    fi
    
    # Install Tor if needed
    if ! check_tor_installation; then
        install_tor
    fi
    
    # Configure Tor
    configure_tor
    
    # Start Tor
    start_tor
    
    # Ask about test website
    if ask_yes_no "Do you want to set up a test website? (requires Python3)"; then
        install_web_dependencies
        create_test_website
        start_test_server
    fi
    
    # Show results
    show_results
    
    print_colored $GREEN "✨ All done! Enjoy your Tor hidden service!"
}

# Trap to handle cleanup
trap 'print_colored $RED "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"
