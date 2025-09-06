#!/bin/bash
# shellcheck disable=SC2034

# utils.sh - Constants and utility definitions
# This file contains all configuration constants and basic utilities

# ================================================================================
# COLOR SCHEME CONFIGURATION
# ================================================================================
# Change this value to switch color schemes throughout the entire script
# Valid options: "STANDARD", "HTB", "PASTEL"
COLOR_SCHEME="PASTEL"

# Color resets
WHITE='\033[1;37m'
NC='\033[0m'
BLACK='\033[0;30m'

# ================================================================================
# STANDARD COLOR PALETTE
# ================================================================================
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

# ================================================================================
# HTB COLOR PALETTE (Hack The Box inspired)
# ================================================================================
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

# ================================================================================
# PASTEL COLOR PALETTE (Soft and pleasant)
# ================================================================================
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

# ================================================================================
# DYNAMIC COLOR MAPPING FUNCTIONS
# ================================================================================
# These functions return the appropriate color based on COLOR_SCHEME setting

get_color() {
    local color_name="$1"
    case "$COLOR_SCHEME" in
        "STANDARD")
            case "$color_name" in
                "PRIMARY") echo "$STANDARD_GREEN" ;;
                "SECONDARY") echo "$STANDARD_ORANGE" ;;
                "ACCENT") echo "$STANDARD_PURPLE" ;;
                "WARNING") echo "$STANDARD_YELLOW" ;;
                "INFO") echo "$STANDARD_BLUE" ;;
                "ERROR") echo "$STANDARD_RED" ;;
                "SUCCESS") echo "$STANDARD_GREEN" ;;
                "HIGHLIGHT") echo "$STANDARD_CYAN" ;;
                "SPECIAL") echo "$STANDARD_PINK" ;;
                "MUTED") echo "$STANDARD_GREY" ;;
                "BORDER") echo "$STANDARD_DARK_GREY" ;;
                "TEXT") echo "$STANDARD_LIGHT_GREY" ;;
                "PROCESS") echo "$STANDARD_NEON_BLUE" ;;
                "MATRIX") echo "$STANDARD_MATRIX_GREEN" ;;
                "BRIGHT") echo "$STANDARD_LIME" ;;
                "BLURPLE") echo "$STANDARD_BLURPLE" ;;
                *) echo "$NC" ;;
            esac
            ;;
        "HTB")
            case "$color_name" in
                "PRIMARY") echo "$HTB_GREEN" ;;
                "SECONDARY") echo "$HTB_ORANGE" ;;
                "ACCENT") echo "$HTB_PURPLE" ;;
                "WARNING") echo "$HTB_YELLOW" ;;
                "INFO") echo "$HTB_BLUE" ;;
                "ERROR") echo "$HTB_RED" ;;
                "SUCCESS") echo "$HTB_GREEN" ;;
                "HIGHLIGHT") echo "$HTB_CYAN" ;;
                "SPECIAL") echo "$HTB_PINK" ;;
                "MUTED") echo "$HTB_GREY" ;;
                "BORDER") echo "$HTB_DARK_GREY" ;;
                "TEXT") echo "$HTB_LIGHT_GREY" ;;
                "PROCESS") echo "$HTB_NEON_BLUE" ;;
                "MATRIX") echo "$HTB_MATRIX_GREEN" ;;
                "BRIGHT") echo "$HTB_LIME" ;;
                "BLURPLE") echo "$HTB_BLURPLE" ;;
                *) echo "$NC" ;;
            esac
            ;;
        "PASTEL")
            case "$color_name" in
                "PRIMARY") echo "$PASTEL_GREEN" ;;
                "SECONDARY") echo "$PASTEL_ORANGE" ;;
                "ACCENT") echo "$PASTEL_PURPLE" ;;
                "WARNING") echo "$PASTEL_YELLOW" ;;
                "INFO") echo "$PASTEL_BLUE" ;;
                "ERROR") echo "$PASTEL_RED" ;;
                "SUCCESS") echo "$PASTEL_GREEN" ;;
                "HIGHLIGHT") echo "$PASTEL_CYAN" ;;
                "SPECIAL") echo "$PASTEL_PINK" ;;
                "MUTED") echo "$PASTEL_GREY" ;;
                "BORDER") echo "$PASTEL_DARK_GREY" ;;
                "TEXT") echo "$PASTEL_LIGHT_GREY" ;;
                "PROCESS") echo "$PASTEL_NEON_BLUE" ;;
                "MATRIX") echo "$PASTEL_MATRIX_GREEN" ;;
                "BRIGHT") echo "$PASTEL_LIME" ;;
                "BLURPLE") echo "$PASTEL_BLURPLE" ;;
                *) echo "$NC" ;;
            esac
            ;;
        *)
            echo "$NC"
            ;;
    esac
}

# Convenience functions for common colors
c_primary() { get_color "PRIMARY"; }
c_secondary() { get_color "SECONDARY"; }
c_accent() { get_color "ACCENT"; }
c_warning() { get_color "WARNING"; }
c_info() { get_color "INFO"; }
c_error() { get_color "ERROR"; }
c_success() { get_color "SUCCESS"; }
c_highlight() { get_color "HIGHLIGHT"; }
c_special() { get_color "SPECIAL"; }
c_muted() { get_color "MUTED"; }
c_border() { get_color "BORDER"; }
c_text() { get_color "TEXT"; }
c_process() { get_color "PROCESS"; }
c_matrix() { get_color "MATRIX"; }
c_bright() { get_color "BRIGHT"; }
c_blurple() { get_color "BLURPLE"; }

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
INIT_SYSTEM=""
SERVICE_CMD=""

# Function to print verbose output
verbose_log() {
    if [[ "$VERBOSE" == true ]]; then
        print_colored "$(c_highlight)" "[VERBOSE] $1"
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
    # Use multiple entropy sources for better randomness
    if [[ -r /dev/urandom ]]; then
        tr -dc 'a-z0-9' < /dev/urandom | head -c "$length"
    elif [[ -r /dev/random ]]; then
        tr -dc 'a-z0-9' < /dev/random | head -c "$length"
    else
        # Fallback to timestamp + random
        local timestamp; timestamp=$(date +%s%N | tail -c 10)
        local random_part; random_part=$(shuf -i 1000-9999 -n 1)
        echo "${timestamp}${random_part}" | tr -dc 'a-z0-9' | head -c "$length"
    fi
}

# Function to generate guaranteed unique service name
generate_unique_service_name() {
    local max_attempts=50
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local random_suffix; random_suffix=$(generate_random_string 9)
        local candidate_name="hidden_service_$random_suffix"
        
        # Check registry file
        if [[ -f "$SERVICES_FILE" ]] && grep -q "^$candidate_name|" "$SERVICES_FILE" 2>/dev/null; then
            ((attempt++))
            continue
        fi
        
        # Check filesystem
        if [[ -d "$HIDDEN_SERVICE_BASE_DIR/$candidate_name" ]]; then
            ((attempt++))
            continue
        fi
        
        # Check if any existing torrc entries exist
        if [[ -f "$TORRC_FILE" ]] && grep -q "$candidate_name" "$TORRC_FILE" 2>/dev/null; then
            ((attempt++))
            continue
        fi
        
        echo "$candidate_name"
        return 0
    done

    print_colored "$(c_error)" "❌ CRITICAL: Unable to generate unique service name after $max_attempts attempts"
    print_colored "$(c_warning)" "This indicates either:"
    print_colored "$(c_warning)" "  • Insufficient entropy source"
    print_colored "$(c_warning)" "  • Corrupted services registry"
    print_colored "$(c_warning)" "  • Filesystem issues"
    return 1
}

# Function to check if running as root
check_root() {
    verbose_log "Checking if running as root..."
    if [[ $EUID -ne 0 ]]; then
        print_colored "$(c_error)" "❌ This script must be run as root!"
        print_colored "$(c_warning)" "Please run: sudo $0"
        exit 1
    fi
    verbose_log "✅ Running as root"
}

# Function to get header symbols based on color scheme
get_header_symbols() {
    case "$COLOR_SCHEME" in
        "HTB")
            echo "[▓▓▓] ANONYMITY ▓ SECURITY ▓ PRIVACY [▓▓▓]"
            ;;
        "PASTEL")
            echo "☁ ANONYMITY ☁ SECURITY ☁ PRIVACY ☁"
            ;;
        "STANDARD")
            echo "● ANONYMITY ● SECURITY ● PRIVACY ●"
            ;;
        *)
            echo "● ANONYMITY ● SECURITY ● PRIVACY ●"
            ;;
    esac
}

# Function to print header with dynamic colors and symbols

# note to self: absolute nightmare to format this header like this
print_header() {
    clear
    echo
    print_colored "$(c_border)" "    ╔═══════════════════════════════════════════════════════════════╗"
    print_colored "$(c_border)" "    ║$(echo -e "$(c_primary)                    Tor Hidden Service Setup                   $(c_border)")║"
    print_colored "$(c_border)" "    ║$(echo -e "$(c_secondary)                     Automated Deployment                      $(c_border)")║"
    print_colored "$(c_border)" "    ╠═══════════════════════════════════════════════════════════════╣"
    local symbols
    symbols=$(get_header_symbols)
    case "$COLOR_SCHEME" in
        "HTB")
            print_colored "$(c_border)" "    ║$(echo -e "$(c_matrix)      $symbols        $(c_border)")║"
            ;;
        "PASTEL")
            print_colored "$(c_border)" "    ║$(echo -e "$(c_accent)         $(c_highlight)☁ ANONYMITY $(c_special)☁ SECURITY $(c_primary)☁ PRIVACY ☁        $(c_border)")║"
            ;;
        *)
            print_colored "$(c_border)" "    ║$(echo -e "$(c_accent)         $symbols        $(c_border)")║"
            ;;
    esac
    print_colored "$(c_border)" "    ╚═══════════════════════════════════════════════════════════════╝"
    echo
    if [[ "$VERBOSE" == true ]]; then
        print_colored "$(c_highlight)" "    [VERBOSE MODE ENABLED] - Enhanced logging active ($COLOR_SCHEME colors)"
        echo
    fi
}

# Function to get web page style based on color scheme

# note to self: also a nightmare to write css in a .sh with no syntax highlight
# should move to a separate .css file but whatever
get_webpage_style() {
    case "$COLOR_SCHEME" in
        "HTB")
            cat << 'EOF'
        body { 
            font-family: 'Courier New', monospace; 
            max-width: 800px; 
            margin: 0 auto; 
            padding: 20px;
            background: #0d1117;
            color: #9be9a8;
            line-height: 1.6;
        }
        .container { 
            text-align: center; 
            background: #161b22;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 8px 16px rgba(0,0,0,0.3);
            border: 1px solid #30363d;
        }
        .success { 
            color: #7c3aed; 
            font-size: 28px;
            margin-bottom: 20px;
            font-weight: bold;
            text-shadow: 0 0 10px #7c3aed;
        }
        .info { 
            background: #21262d;
            padding: 25px;
            border-radius: 6px;
            margin: 20px 0;
            text-align: left;
            border-left: 4px solid #f59e0b;
        }
        h3 {
            color: #f59e0b;
            margin-top: 0;
        }
EOF
            ;;
        "PASTEL")
            cat << 'EOF'
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            max-width: 800px; 
            margin: 0 auto; 
            padding: 20px;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            color: #4a5568;
            line-height: 1.6;
        }
        .container { 
            text-align: center; 
            background: rgba(255, 255, 255, 0.9);
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        .success { 
            color: #48bb78; 
            font-size: 28px;
            margin-bottom: 20px;
            font-weight: 600;
        }
        .info { 
            background: rgba(237, 242, 247, 0.8);
            padding: 25px;
            border-radius: 10px;
            margin: 20px 0;
            text-align: left;
            border-left: 4px solid #667eea;
        }
        h3 {
            color: #667eea;
            margin-top: 0;
        }
EOF
            ;;
        *)
            cat << 'EOF'
        body { 
            font-family: Arial, sans-serif; 
            max-width: 800px; 
            margin: 0 auto; 
            padding: 20px;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }
        .container { 
            text-align: center; 
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border: 1px solid #ddd;
        }
        .success { 
            color: #28a745; 
            font-size: 28px;
            margin-bottom: 20px;
            font-weight: bold;
        }
        .info { 
            background: #f8f9fa;
            padding: 25px;
            border-radius: 5px;
            margin: 20px 0;
            text-align: left;
            border-left: 4px solid #007bff;
        }
        h3 {
            color: #007bff;
            margin-top: 0;
        }
EOF
            ;;
    esac
}

