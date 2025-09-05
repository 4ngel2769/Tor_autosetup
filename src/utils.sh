#!/bin/bash
# shellcheck disable=SC2034

# utils.sh - Constants and utility definitions
# This file contains all configuration constants and basic utilities

# Color definitions (using ANSI escape codes - no external dependencies)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
GREY='\033[38;5;239m'
LIME="\033[38;5;10m"
#C_GREY23="\033[48;5;252m"
BLURPLE="\033[38;5;63m"
# DARKOLIVEGREEN3="\033[48;5;149m"

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
        print_colored "$CYAN" "[VERBOSE] $1"
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

# Function to check if running as root
check_root() {
    verbose_log "Checking if running as root..."
    if [[ $EUID -ne 0 ]]; then
        print_colored "$RED" "❌ This script must be run as root!"
        print_colored "$YELLOW" "Please run: sudo $0"
        exit 1
    fi
    verbose_log "✅ Running as root"
}

# Function to print header
print_header() {
    clear
    print_colored "$PURPLE" "╔══════════════════════════════════════════════════════════════╗"
    print_colored "$PURPLE" "║                   Tor Hidden Service Setup                   ║"
    print_colored "$PURPLE" "║                    Automated Installation                    ║"
    print_colored "$PURPLE" "╚══════════════════════════════════════════════════════════════╝"
    echo
    if [[ "$VERBOSE" == true ]]; then
        print_colored "$CYAN" "[VERBOSE MODE ENABLED]"
        echo
    fi
}
