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
        print_colored "$GREEN" "✅ Tor is already installed"
        return 0
    else
        print_colored "$YELLOW" "⚠️  Tor is not installed"
        return 1
    fi
}

# Function to install Tor
install_tor() {
    print_colored "$BLUE" "🔧 Installing Tor..."
    
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
    
    print_colored "$GREEN" "✅ Tor installation completed"
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
    print_colored "$BLUE" "📦 Installing web dependencies..."
    
    # Check if Python3 is installed
    if ! command -v python3 >/dev/null 2>&1; then
        verbose_log "Python3 not found, installing..."
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
    else
        print_colored "$GREEN" "✅ Python3 is already installed"
        verbose_log "Python3 found: $(python3 --version)"
    fi
    
    # Check if curl is installed (for server testing)
    if ! command -v curl >/dev/null 2>&1; then
        verbose_log "curl not found, installing..."
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
    else
        verbose_log "curl is already installed"
    fi
    
    print_colored "$GREEN" "✅ Web dependencies installed"
}
