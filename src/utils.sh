#!/bin/bash
# shellcheck disable=SC2034

# utils.sh - Constants and utility definitions
# This file contains all configuration constants and basic utilities

# Color resets
WHITE='\033[1;37m'
NC='\033[0m'
BLACK='\033[0;30m'

# Color definitions (using ANSI escape codes - no external dependencies)
STANDARD_GREEN='\033[0;32m'             # (1) Standard green
STANDARD_ORANGE="\033[38;5;208m"        # (2) Standard orange
STANDARD_PURPLE='\033[0;35m'            # (3) Standard purple
STANDARD_YELLOW='\033[1;33m'            # (4) Standard yellow
STANDARD_BLUE='\033[0;34m'              # (5) Standard blue
STANDARD_RED='\033[0;31m'               # (6) Standard red
STANDARD_CYAN='\033[0;36m'              # (7) Standard cyan
STANDARD_PINK='\033[0;95m'              # (8) Standard pink
STANDARD_GREY='\033[38;5;239m'          # (9) Standard grey
STANDARD_DARK_GREY='\033[1;30m'         # (10) Standard dark grey
STANDARD_LIGHT_GREY='\033[0;37m'        # (11) Standard light grey
STANDARD_NEON_BLUE="\033[38;5;45m"      # (12) Standard neon blue
STANDARD_MATRIX_GREEN="\033[38;5;40m"   # (13) Standard matrix green
STANDARD_LIME="\033[38;5;118m"          # (14) Standard lime green
STANDARD_BLURPLE="\033[38;5;63m"        # (15) Standard blurple

# HTB Color Palette
HTB_GREEN="\033[38;5;82m"               # (1) Bright neon green
HTB_ORANGE="\033[38;5;214m"             # (2) HTB signature orange
HTB_PURPLE="\033[38;5;99m"              # (3) Deep purple
HTB_YELLOW="\033[38;5;226m"             # (4) Bright yellow
HTB_BLUE="\033[38;5;33m"                # (5) Vivid blue
HTB_RED="\033[38;5;196m"                # (6) Bright red
HTB_CYAN="\033[38;5;51m"                # (7) Bright cyan
HTB_PINK="\033[38;5;201m"               # (8) Vibrant pink
HTB_GREY="\033[38;5;246m"               # (9) Medium grey
HTB_DARK_GREY="\033[38;5;240m"          # (10) Dark grey for borders
HTB_LIGHT_GREY="\033[38;5;250m"         # (11) Light grey for text
HTB_NEON_BLUE="\033[38;5;51m"           # (12) Neon blue
HTB_MATRIX_GREEN="\033[38;5;46m"        # (13) Matrix-style green
HTB_LIME="\033[38;5;118m"               # (14) Lime
HTB_BLURPLE="\033[38;5;63m"             # (15) Blurple

# Pastel Soft Color Palette
PASTEL_GREEN="\033[38;5;120m"           # (1) Soft pastel green
PASTEL_ORANGE="\033[38;5;215m"          # (2) Soft pastel orange
PASTEL_PURPLE="\033[38;5;141m"          # (3) Soft pastel purple
PASTEL_YELLOW="\033[38;5;229m"          # (4) Soft pastel yellow
PASTEL_BLUE="\033[38;5;117m"            # (5) Soft pastel blue
PASTEL_RED="\033[38;5;203m"             # (6) Soft pastel red
PASTEL_CYAN="\033[38;5;159m"            # (7) Soft pastel cyan
PASTEL_PINK="\033[38;5;218m"            # (8) Soft pastel pink
PASTEL_GREY="\033[38;5;246m"            # (9) Soft pastel grey
PASTEL_DARK_GREY="\033[38;5;240m"       # (10) Soft pastel dark grey
PASTEL_LIGHT_GREY="\033[38;5;250m"      # (11) Soft pastel light grey
PASTEL_NEON_BLUE="\033[38;5;123m"       # (12) Soft pastel neon blue
PASTEL_MATRIX_GREEN="\033[38;5;120m"    # (13) Soft pastel matrix green
PASTEL_LIME="\033[38;5;118m"            # (14) Soft pastel lime green
PASTEL_BLURPLE="\033[38;5;177m"         # (15) Soft pastel blurple


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
        print_colored "$PASTEL_CYAN" "[VERBOSE] $1"
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
        print_colored "$PASTEL_RED" "❌ This script must be run as root!"
        print_colored "$PASTEL_YELLOW" "Please run: sudo $0"
        exit 1
    fi
    verbose_log "✅ Running as root"
}

# Function to print header
print_header() {
    clear
    echo
    print_colored "$PASTEL_DARK_GREY" "    ╔═══════════════════════════════════════════════════════════════╗"
    print_colored "$PASTEL_DARK_GREY" "    ║$(echo -e "$PASTEL_GREEN                    Tor Hidden Service Setup                   $PASTEL_DARK_GREY")║"
    print_colored "$PASTEL_DARK_GREY" "    ║$(echo -e "$PASTEL_ORANGE                     Automated Deployment                      $PASTEL_DARK_GREY")║"
    print_colored "$PASTEL_DARK_GREY" "    ╠═══════════════════════════════════════════════════════════════╣"
    print_colored "$PASTEL_DARK_GREY" "    ║$(echo -e "$PASTEL_PURPLE         ☁ ANONYMITY ${PASTEL_CYAN}☁ SECURITY ${PASTEL_PINK}☁ PRIVACY ☁        $PASTEL_DARK_GREY")║"
    print_colored "$PASTEL_DARK_GREY" "    ╚═══════════════════════════════════════════════════════════════╝"
    echo
    if [[ "$VERBOSE" == true ]]; then
        print_colored "$PASTEL_CYAN" "    [VERBOSE MODE ENABLED] - Detailed Output    "
        echo
    fi
}

