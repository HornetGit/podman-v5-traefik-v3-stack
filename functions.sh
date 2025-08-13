#!/bin/bash
# PURPOSE: Shared functions library
# USAGE: Source this file in other scripts with: source functions.sh (command line usage not included yet)
# OWNER: XCS HornetGit
# LICENCE: MIT
# CREATED: 04JUL2025
# UPDATED: 29JUL2025
# CHANGES: 
# added: "is_not_empty_file",
# added: "build_with_format" for container build format detection (dockerfile or OCI)

set -e

# DEBUG mode: log into file if true
DEBUG=true
dbg_path=/tmp/debug.log
[ -f "$dbg_path" ] && rm "$dbg_path"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW2='\033[1;33m' # bright yellow (for dark backgrounds)
YELLOW1='\033[38;5;208m'  # Dark orange - better for white backgrounds
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NOK="\e[31mNOK\e[0m"    # bright red
OK="\e[32mOK\e[0m"      # bright green
WARN="\e[33mWARN\e[0m"  # yellow

# Logging functions
log_debugmode(){
    [ "$DEBUG" = true ] && echo -e "$1" >> "$dbg_path"
}

log_info() {
    local msg="${BLUE}ℹ️ $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_success() {
    local msg="${GREEN}✅ $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_warning() {
    local msg="${YELLOW1}⚠️  $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_debug() {
    local msg="${YELLOW1}DEBUG:  $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}

log_error() {
    local msg="${RED}❌ $1${NC}"
    echo -e "$msg"
    log_debugmode "$msg"
}


# continue or abort by the user
# Usage: continue_or_abort [condition]
continue_or_abort() {
    local condition="$1"
    if [ "$condition" = false ]; then
        read -n1 -p "Press y/Y to continue, any other key to abort: " key
        echo    # move to a new line
        if [[ "$key" =~ [yY] ]]; then
            log_success "Continuing..."
        else
            log_error "Aborted by user."
            exit 1
        fi
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        log_error "This script should NOT be run as root"
        exit 1
    fi
}

# Check if user is in sudoers group and has home directory
# Check if user is in sudoers group and has home directory
check_sudoer_with_home() {
    local current_user=$(whoami)
    local user_id=$(id -u)
    local home_dir="$HOME"
    
    # Check if user has a proper home directory
    if [ ! -d "$home_dir" ] || [ "$home_dir" = "/" ]; then
        log_error "User $current_user does not have a valid home directory"
        log_error "Expected: /home/$current_user, Found: $home_dir"
        return 1
    fi
    
    # Check if user is in sudo group (without actually running sudo)
    if ! groups "$current_user" | grep -q '\bsudo\b'; then
        log_error "User $current_user is not in the sudo group"
        log_error "Add user to sudo group: sudo usermod -aG sudo $current_user"
        return 1
    fi
    
    # Check if user ID is not 0 (additional root check)
    if [ "$user_id" -eq 0 ]; then
        log_error "Running as root user (UID 0) - use a regular user with sudo access"
        return 1
    fi
    
    log_success "User validation passed:"
    log_info "  User: $current_user (UID: $user_id)"
    log_info "  Home: $home_dir"
    log_info "  Sudo: User is in sudo group (password required)"
    
    return 0
}

# Check if service is running
service_is_running() {
    local service="$1"
    systemctl --user is-active --quiet "$service" 2>/dev/null
}

# check if a container dockerfile has an ACTIVE healthcheck or not
# ignores commented out healthchecks (lines starting with # or whitespace + #)
detect_healthcheck() {
    local dockerfile="$1"
    [ -f "$dockerfile" ] && grep -q "^[[:space:]]*HEALTHCHECK" "$dockerfile"
}

# define podman build format option (OCI or Dockerfile)
# format: default if no healthcheck in the service docker file
# format: docker if an healthcheck was detected in the service docker file, to prevent the podman HC bug
# bug: WARN[0000] HEALTHCHECK is not supported for OCI image format and will be ignored. Must use `docker` format
# this bug is persistent at least until podman v5.3.1, prevening HC to work as expected
# solutions: use docker format , or upgrade podman if bug fix in podman v5.5.6+
# doc: https://stackoverflow.com/questions/76720076/podman-missing-health-check
build_with_format() {
    local dockerfile="$1"
    
    # Check if dockerfile exists and has healthcheck
    if [ -f "$dockerfile" ] && detect_healthcheck "$dockerfile"; then
        log_info "HEALTHCHECK detected in $dockerfile, requires --format docker"
        echo "--format docker"
    else
        # Return empty string for default OCI format
        echo ""
    fi
}




# Clean up podman containers
# note that podman system reset --force
# will entirely WIPE OUT your setup if any,
# including crun manually installed binaries
cleanup_podman() {
    log_info "Cleaning up podman containers and networks..."
    podman stop --all 2>/dev/null || true
    podman kill --all --force 2>/dev/null || true
    podman rm --all --force 2>/dev/null || true
    podman rmi --all --force 2>/dev/null || true
    podman system prune -af 2>/dev/null || true
    podman network prune -f 2>/dev/null || true
    # podman system reset --force 2>/dev/null || true
}

# reset podman socket
reset_socket(){
    systemctl --user enable podman.socket
    systemctl --user start --now podman.socket
    systemctl --user status podman.socket
    if systemctl --user is-active --quiet podman.socket; then
        if export_podman_socket; then 
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

export_podman_socket() {

    bashrc="$HOME/.bashrc"
    [ ! -f "$bashrc" ] && { echo "ERR: $bashrc not found in export_podman_socket"; return 1; }

    # redundant export of the podman socket
    CURRENT_USER_ID=$(id -u)
    new_line="export MINIAPP_TRAEFIK_PODMAN_SOCK=/run/user/${CURRENT_USER_ID}/podman/podman.sock"
    export MINIAPP_TRAEFIK_PODMAN_SOCK="/run/user/${CURRENT_USER_ID}/podman/podman.sock"

    # bashrc: Remove any existing lines containing this export
    sed -i '/MINIAPP_TRAEFIK_PODMAN_SOCK/d' "$bashrc"
    
    # bashrc: add the up-to-date export
    echo "$new_line" >> "$bashrc"
    
    # source the newly updated bashrc
    source $bashrc 

    # report
    echo "✅ Updated $bashrc with new Podman socket path"
    
    return 0
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log_info "Backed up $file to $backup"
    fi
}

is_empty_file() {
    local file="$1"
    if [ -f "$file" ]; then
        log_info "$file: exists"
        [ -s "$file" ] && { log_info "$file: not empty"; return 1; } || { log_info "$file: empty"; return 0; }
    else
        log_info "$file: does not exist"
        return 0  # Consider non-existent as "empty"
    fi
}

# Secure removal function - handles files, directories, and arrays
# scripting in progress, test soon, see test_rm_secure.sh
# TODO

# Allowing to call the script functions directly from the tty
# example: ./functions.sh reset_socket
# Add debug info to see what's happening
# echo "This script: $0"
# echo "Arguments passed: $@"
# echo "Number of arguments: $#"
# echo "First argument: $1"
# # Handle command line arguments
# if [ $# -gt 0 ]; then
#     # Check if the function exists
#     if declare -f "$1" > /dev/null; then
#         # Call the function with remaining arguments
#         "$@"
#     else
#         echo "Error: Function '$1' not found"
#         echo "Available functions:"
#         declare -F | cut -d' ' -f3
#         exit 1
#     fi
# fi
