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
DARK_GREEN="\033[38;5;22m"
ORANGE="\033[38;5;208m"

# HTB Color Palette
HTB_GREEN="\033[38;5;82m"           # Bright neon green
HTB_ORANGE="\033[38;5;214m"         # HTB signature orange
HTB_PURPLE="\033[38;5;99m"          # Deep purple
HTB_YELLOW="\033[38;5;226m"         # Bright yellow
HTB_BLUE="\033[38;5;33m"            # Vivid blue
HTB_RED="\033[38;5;196m"            # Bright red
HTB_DARK_GREY="\033[38;5;240m"      # Dark grey for borders
HTB_LIGHT_GREY="\033[38;5;250m"     # Light grey for text
HTB_NEON_BLUE="\033[38;5;51m"       # Neon blue
HTB_MATRIX_GREEN="\033[38;5;46m"    # Matrix-style green
BLURPLE="\033[38;5;63m"

# Pastel Soft Color Palette
PASTEL_GREEN="\033[38;5;120m"
PASTEL_ORANGE="\033[38;5;215m"
PASTEL_PURPLE="\033[38;5;141m"
PASTEL_YELLOW="\033[38;5;229m"
PASTEL_BLUE="\033[38;5;117m"
PASTEL_RED="\033[38;5;203m"
PASTEL_CYAN="\033[38;5;159m"
PASTEL_PINK="\033[38;5;218m"
PASTEL_GREY="\033[38;5;246m"
PASTEL_DARK_GREY="\033[38;5;240m"
PASTEL_LIGHT_GREY="\033[38;5;250m"


# DARKOLIVEGREEN3="\033[48;5;149m"

# Text styles
UNDERLINE="\033[4m"
BOLD="\033[1m"
RESET="\033[0m"

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
        print_colored "$HTB_NEON_BLUE" "[VERBOSE] $1"
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
        print_colored "$HTB_RED" "❌ This script must be run as root!"
        print_colored "$HTB_YELLOW" "Please run: sudo $0"
        exit 1
    fi
    verbose_log "✅ Running as root"
}

# Function to print header
print_header() {
    clear
    echo
    print_colored "$HTB_DARK_GREY" "    ╔═══════════════════════════════════════════════════════════════╗"
    print_colored "$HTB_DARK_GREY" "    ║$(echo -e "$HTB_GREEN                    Tor Hidden Service Setup                   $HTB_DARK_GREY")║"
    print_colored "$HTB_DARK_GREY" "    ║$(echo -e "$HTB_ORANGE                     Automated Deployment                      $HTB_DARK_GREY")║"
    # print_colored "$HTB_DARK_GREY" "    ╠═══════════════════════════════════════════════════════════════╣"
    # print_colored "$HTB_DARK_GREY" "    ║$(echo -e "${HTB_MATRIX_GREEN}            [▓▓▓]${HTB_LIGHT_GREY} ANONYMITY ${HTB_MATRIX_GREEN}▓${HTB_LIGHT_GREY} SECURITY ${HTB_MATRIX_GREEN}▓${HTB_LIGHT_GREY} PRIVACY ${HTB_MATRIX_GREEN}[▓▓▓]           ${HTB_PURPLE}")║"
    print_colored "$HTB_DARK_GREY" "    ╚═══════════════════════════════════════════════════════════════╝"
    echo
    if [[ "$VERBOSE" == true ]]; then
        print_colored "$HTB_NEON_BLUE" "    [VERBOSE MODE ENABLED] - Enhanced logging active"
        echo
    fi
}

