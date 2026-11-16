#!/bin/bash
#
# ----------------------------------------------------------------------------
# Script: MPServerUpgrader.sh
# Version: 3.4.4
#
# Description:
# Upgrade script will upgrade a current install of the MacPatch server
#
# History:
# 3.4.4 - Fixed terminal handling and added auto-confirm:
#       - Made clear command conditional (only runs if terminal present)
#       - Prevents "unknown terminal type" errors in non-interactive mode
#       - Added -y flag to skip interactive confirmation prompt
#       - Enables fully automated upgrade runs via cron/CI
# 3.4.3 - Extended Python script permission handling:
#       - All .py files in conf/scripts now get 755 (admin/utility scripts)
#       - Python scripts with shebangs in both apps and conf/scripts get 755
#       - Ensures ServerSetup.py and other admin scripts remain executable
# 3.4.2 - Improved permission handling:
#       - Sets executables to explicit 755 (not just +x which gave 754)
#       - All executable files now get rwxr-xr-x (755) permissions
#       - Includes nginx binary, shell scripts, venv binaries, Python scripts
#       - Service files explicitly set to 644 (not executable)
#       - Fixes issue where files had 754 instead of 755
# 3.4.1 - Permission handling fix:
#       - Fixed issue where virtual environment binaries lost execute permissions
#       - Now preserves execute bit on files that already have it
#       - Explicitly ensures venv/bin/* files remain executable
#       - Uses find with ! -perm -111 to only chmod non-executable files
# 3.4 - Local source directory support:
#       - Added -g flag to enable GitHub cloning (now opt-in)
#       - Default behavior: uses parent directory of script as source
#       - Typical workflow: clone to /tmp, run script from /tmp/MacPatch/scripts
#       - Eliminates need for GitHub access if repo already cloned locally
#       - Validates source directory structure in pre-flight checks
# 3.3 - No migration option:
#       - Added -n flag to skip content migration (keep in /opt/MacPatch/Content)
#       - Traditional mode: backs up and restores content as regular directory
#       - Symlink mode (default): migrates to /opt/MPContent with symlink
#       - -n and -c flags are mutually exclusive
#       - Tracks content mode in backup for proper restoration
# 3.2 - Content directory customization:
#       - Added -c option to specify custom content directory location
#       - Default location: /opt/MPContent (can be changed with -c flag)
#       - Creates parent directories if they don't exist
#       - Enhanced usage help with examples
# 3.1 - Content management improvements:
#       - Migrates content to /opt/MPContent (outside MacPatch directory)
#       - Creates symlink /opt/MacPatch/Content -> /opt/MPContent
#       - Content survives upgrades without being backed up/restored
#       - Handles existing symlinks and migrates real directories automatically
# 3.0 - Major service management overhaul:
#       - Added platform detection (Linux vs macOS)
#       - Proper systemctl support for Linux (systemd services)
#       - Proper launchctl support for macOS (launchd services)
#       - Server type detection (master/distribution vs console-only)
#       - Dynamic service list based on server type
#       - Removed dependency on ServerSetup.py for service management
#       - Services: MPNginx, MPAPI, MPConsole, MPInventoryD, MPRsyncServer
# 2.2 - Updated for new server architecture:
#       - Removed obsolete mpapi.py (now uses Flask-Migrate)
#       - Updated to use apps/api/app.py and apps/console/app.py structure
#       - Updated database migration to use Flask-Migrate (flask db upgrade)
#       - Split database migrations for API and Console separately
#       - Updated installation verification for new directory structure
# 2.1 - Updated configuration file handling:
#       - Changed from config.cfg/conf_console.cfg to .mpglobal/.mpapi/.mpconsole
#       - Updated backup and restore logic for new config format
# 2.0 - Major improvements:
#       - Enhanced backup strategy with timestamped backups
#       - Added automatic backup cleanup (keeps last 5 backups)
#       - Comprehensive backup integrity verification
#       - Pre-flight safety checks (disk space, git connectivity, branch validation)
#       - Service verification (confirm shutdown/startup with configurable timeouts)
#       - Build verification after installation
#       - Automatic rollback on failure with service restart attempt
#       - Cross-platform path handling and symlink resolution
#       - Path validation throughout script
#       - Comprehensive error handling with set -euo pipefail
#       - Detailed logging with timestamps
#       - Database upgrade safety checks
# 1.1 - Initial version
#
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# How to use:
#
# sudo MPServerUpgrader.sh
#   - Upgrades MacPatch server from local source directory
#   - Uses parent directory of script as source (e.g., /tmp/MacPatch)
#   - Creates timestamped backup in /opt/MacPatch_Backup
#   - Content stored at /opt/MPContent (default)
#   - Automatically verifies and rolls back on failure
#
# sudo MPServerUpgrader.sh -g -b <branch>
#   - Upgrades from specified GitHub branch (requires -g flag)
#
# sudo MPServerUpgrader.sh -c <path>
#   - Use custom content directory location (default: /opt/MPContent)
#
# sudo MPServerUpgrader.sh -m
#   - Upgrade master/distribution server (includes database migration)
#
# sudo MPServerUpgrader.sh -g -b develop -c /data/MPContent -m
#   - Clone from GitHub develop branch with custom content location
#
# What it does:
# 1. Stops running services (tracks which ones to restart)
# 2. Backs up /opt/MacPatch to /opt/MacPatch_Backup/upgrade_YYYYMMDD_HHMMSS
# 3. Handles content (two modes):
#    a) Default: Migrates to $CONTENT_DIR, creates symlink
#    b) With -n: Backs up/restores to /opt/MacPatch/Content (traditional)
# 4. Installs MacPatch (two modes):
#    a) Default: Copies from local source directory (parent of script)
#    b) With -g: Clones from GitHub (master or specified branch)
# 5. Runs MPBuildServer.sh to build new version
# 6. Restores config files: .mpapi, .mpglobal, .mpconsole, etc/, nginx/conf/sites
# 7. Restores content per mode (symlink or direct)
# 8. Sets correct permissions on /opt/MacPatch
# 9. Starts only the services that were running before
#
# Options:
#   -b <branch>  : GitHub branch to clone (default: master, requires -g)
#   -c <path>    : Content directory location (default: /opt/MPContent)
#   -g           : Clone from GitHub (default: use local source)
#   -n           : No migration - keep content in /opt/MacPatch/Content
#   -m           : Master/Distribution server flag (includes DB migration)
#   -h           : Show help
#
# Note: -n and -c are mutually exclusive
#
# Backups are stored in: /opt/MacPatch_Backup/upgrade_YYYYMMDD_HHMMSS
# Logs are saved to: <backup_dir>/backup.log
# Old backups are automatically cleaned up (keeps last 5)
#
# Services managed: MPNginx, MPAPI, MPConsole, MPInventoryD, MPRsyncServer
#
# Typical workflow:
#   cd /tmp
#   git clone https://github.com/LLNL/MacPatch.git -b <branch>
#   cd MacPatch/scripts
#   sudo ./MPServerUpgrader.sh -m
#
# ----------------------------------------------------------------------------


# Make Sure User is root -----------------------------------------------------

if [ "`whoami`" != "root" ] ; then   # If not root user,
   # Run this script again as root
   echo
   echo "You must be an admin user to run this script."
   echo "Please re-run the script using sudo."
   echo
   exit 1;
fi

# Script Variables -----------------------------------------------------------
set -euo pipefail

MPBASE="/opt/MacPatch"
MPCONTENT="${MPBASE}/Content"
MPCONTENTLNK="${MPCONTENT}"
MPSRVCONTENT="${MPBASE}/Content/Web"
USECONTENTLNK=false
MPSERVERBASE="/opt/MacPatch/Server"
BUILDROOT="${MPBASE}/.build/server"

# Timestamped backup directory
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE="/opt/MacPatch_Backup"
MPBASEBACK="${BACKUP_BASE}/upgrade_${BACKUP_TIMESTAMP}"
BACKUP_LOG="${MPBASEBACK}/backup.log"
GITBRANCH="master"
MOVECONTENT=true
MASTERSERVER=false
CONTENT_DIR="/opt/MPContent"  # Default content directory location
SKIP_CONTENT_MIGRATION=false  # If true, keep content in /opt/MacPatch/Content (no symlink)
USE_GIT_CLONE=false  # If true, clone from GitHub; if false, use local source directory
AUTO_CONFIRM=false  # If true, skip interactive confirmation prompt
MAX_BACKUPS=5  # Keep last 5 backups
SERVICE_SHUTDOWN_TIMEOUT=60  # Seconds to wait for services to stop
SERVICE_STARTUP_TIMEOUT=60   # Seconds to wait for services to start

# Determine script directory and parent (source) directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"

# Detect platform
platform='unknown'
unamestr=$(uname)
if [[ "$unamestr" == 'Linux' ]]; then
   platform='linux'
elif [[ "$unamestr" == 'Darwin' ]]; then
   platform='mac'
fi

# Service lists based on server type
# Core services for all servers
CORE_SERVICES=("MPNginx")

# Distribution/Master server services (includes API)
MASTER_SERVICES=("MPAPI" "MPInventoryD" "MPRsyncServer")

# Console services
CONSOLE_SERVICES=("MPConsole")

# Track which services were actually running before shutdown
RUNNING_SERVICES=()

# Script Input Args ----------------------------------------------------------

usage() {
	echo "Usage: $0 [-b GitHub Branch] [-c Content Directory] [-g] [-n] [-m] [-y]" 1>&2
	echo "" 1>&2
	echo "Options:" 1>&2
	echo "  -b <branch>    GitHub branch to clone (default: master, requires -g)" 1>&2
	echo "  -c <path>      Content directory location (default: /opt/MPContent)" 1>&2
	echo "  -g             Clone from GitHub (default: use local source directory)" 1>&2
	echo "  -n             No migration - keep content in /opt/MacPatch/Content (no symlink)" 1>&2
	echo "  -m             Master/Distribution server (includes database migration)" 1>&2
	echo "  -y             Auto-confirm - skip interactive confirmation prompt" 1>&2
	echo "  -h             Show this help message" 1>&2
	echo "" 1>&2
	echo "Examples:" 1>&2
	echo "  $0                           # Upgrade from local source, migrate content" 1>&2
	echo "  $0 -g                        # Clone from GitHub master branch" 1>&2
	echo "  $0 -g -b 4.4.0-dev -m        # Clone from specific branch, upgrade master" 1>&2
	echo "  $0 -n                        # Use local source, keep content in place" 1>&2
	echo "  $0 -c /data/MPContent -m     # Use custom content directory" 1>&2
	echo "  $0 -g -b develop -m          # Clone develop branch, master server" 1>&2
	echo "" 1>&2
	echo "Note: By default, the script uses the parent directory of the script location" 1>&2
	echo "      as the source (e.g., if script is at /tmp/MacPatch/scripts/MPServerUpgrader.sh," 1>&2
	echo "      it uses /tmp/MacPatch as the source). Use -g to clone from GitHub instead." 1>&2
	echo "      Options -n and -c are mutually exclusive." 1>&2
	exit 1
}

while getopts "hb:c:gnmy" opt; do
	case $opt in
		b)
			GITBRANCH=${OPTARG}
			;;
		c)
			CONTENT_DIR=${OPTARG}
			# Remove trailing slash if present
			CONTENT_DIR="${CONTENT_DIR%/}"
			;;
		g)
			USE_GIT_CLONE=true
			;;
		n)
			SKIP_CONTENT_MIGRATION=true
			;;
		y)
			AUTO_CONFIRM=true
			;;
		h)
			echo
			usage
			exit 1
			;;
		m)
			MASTERSERVER=true
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			echo
			usage
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			echo
			usage
			exit 1
			;;
	esac
done

# Validate mutually exclusive options
if $SKIP_CONTENT_MIGRATION && [ "$CONTENT_DIR" != "/opt/MPContent" ]; then
	echo "ERROR: Options -n and -c are mutually exclusive." >&2
	echo "Use -n to keep content in /opt/MacPatch/Content (no migration)" >&2
	echo "OR use -c to specify a custom content location (with migration)" >&2
	exit 1
fi

# ----------------------------------------------------------------------------
# Helper Functions (must be defined before preflight_checks)
# ----------------------------------------------------------------------------

log_message() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "${BACKUP_LOG}" 2>/dev/null || true
}

normalize_path() {
    local path="$1"
    # Remove trailing slashes
    path="${path%/}"
    echo "$path"
}

resolve_symlink() {
    local path="$1"

    # Try readlink with -f flag (Linux)
    if readlink -f "$path" 2>/dev/null; then
        return 0
    fi

    # Try without -f flag (macOS)
    if [[ -L "$path" ]]; then
        local target
        target=$(readlink "$path")
        # If relative path, make it absolute
        if [[ "$target" != /* ]]; then
            local dir
            dir=$(dirname "$path")
            target="${dir}/${target}"
        fi
        echo "$target"
        return 0
    fi

    # Not a symlink or readlink failed, return original path
    echo "$path"
    return 0
}

validate_path() {
    local path="$1"
    local path_type="$2"  # "file" or "dir"

    if [ -z "$path" ]; then
        log_message "ERROR: Empty path provided for validation"
        return 1
    fi

    if [[ "$path" =~ [[:space:]] ]]; then
        log_message "WARNING: Path contains spaces: $path"
    fi

    case "$path_type" in
        file)
            if [ ! -f "$path" ]; then
                log_message "ERROR: File not found: $path"
                return 1
            fi
            ;;
        dir)
            if [ ! -d "$path" ]; then
                log_message "ERROR: Directory not found: $path"
                return 1
            fi
            ;;
        *)
            if [ ! -e "$path" ]; then
                log_message "ERROR: Path does not exist: $path"
                return 1
            fi
            ;;
    esac

    return 0
}

check_disk_space() {
    local required_mb=$1
    local path="$2"
    local available_mb

    if [ ! -e "$path" ]; then
        log_message "ERROR: Cannot check disk space - path does not exist: $path"
        return 1
    fi

    available_mb=$(df -m "$path" | awk 'NR==2 {print $4}')

    if [ "$available_mb" -lt "$required_mb" ]; then
        log_message "ERROR: Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi
    log_message "Disk space check passed: ${available_mb}MB available"
    return 0
}

# ----------------------------------------------------------------------------
# Pre-flight Safety Checks
# ----------------------------------------------------------------------------

preflight_checks() {
    local error_count=0

    echo "Running pre-flight safety checks..."

    # Normalize and validate paths
    MPBASE=$(normalize_path "$MPBASE")
    MPSERVERBASE=$(normalize_path "$MPSERVERBASE")
    BACKUP_BASE=$(normalize_path "$BACKUP_BASE")

    # Check if MacPatch installation exists
    if ! validate_path "$MPBASE" "dir"; then
        echo "ERROR: MacPatch installation not found at ${MPBASE}"
        ((error_count++))
    fi

    if ! validate_path "$MPSERVERBASE" "dir"; then
        echo "ERROR: MacPatch Server not found at ${MPSERVERBASE}"
        ((error_count++))
    fi

    # Check if /opt directory is accessible and writable
    if [ ! -d "/opt" ]; then
        echo "ERROR: /opt directory not accessible"
        ((error_count++))
    elif [ ! -w "/opt" ]; then
        echo "ERROR: /opt directory is not writable"
        ((error_count++))
    fi

    if $USE_GIT_CLONE; then
        # Git clone mode - check git and GitHub connectivity
        echo "Using Git clone mode..."

        # Check if git is installed
        if ! command -v git >/dev/null 2>&1; then
            echo "ERROR: git is not installed"
            ((error_count++))
        fi

        # Check if we can reach GitHub
        if ! git ls-remote https://github.com/LLNL/MacPatch.git HEAD >/dev/null 2>&1; then
            echo "ERROR: Cannot connect to GitHub repository"
            ((error_count++))
        fi

        # Check if branch exists
        if ! git ls-remote --heads https://github.com/LLNL/MacPatch.git "${GITBRANCH}" | grep -q "${GITBRANCH}"; then
            echo "ERROR: Branch '${GITBRANCH}' does not exist in repository"
            ((error_count++))
        fi
    else
        # Local source mode - validate source directory
        echo "Using local source directory: ${SOURCE_DIR}"

        # Prevent SOURCE_DIR from being the same as MPBASE
        if [ "$(normalize_path "$SOURCE_DIR")" = "$(normalize_path "$MPBASE")" ]; then
            echo "ERROR: Cannot upgrade from /opt/MacPatch to itself"
            echo "The source directory ($SOURCE_DIR) cannot be the same as the installation directory ($MPBASE)"
            echo ""
            echo "Solution: Clone MacPatch to a temporary location first:"
            echo "  cd /tmp"
            echo "  git clone https://github.com/LLNL/MacPatch.git"
            echo "  sudo /tmp/MacPatch/scripts/MPServerUpgrader.sh -n -y"
            echo ""
            echo "Or use -g flag to clone from GitHub automatically"
            ((error_count++))
        fi

        if ! validate_path "$SOURCE_DIR" "dir"; then
            echo "ERROR: Source directory not found at ${SOURCE_DIR}"
            ((error_count++))
        fi

        # Check for MPBuildServer.sh in source
        if [ ! -f "${SOURCE_DIR}/scripts/MPBuildServer.sh" ]; then
            echo "ERROR: MPBuildServer.sh not found at ${SOURCE_DIR}/scripts/"
            echo "Source directory does not appear to be a valid MacPatch repository"
            ((error_count++))
        fi
    fi

    # Check available disk space
    local opt_avail=$(df -m /opt | awk 'NR==2 {print $4}')
    if [ "$opt_avail" -lt 7168 ]; then
        echo "ERROR: Insufficient disk space on /opt. Required: 7GB (5GB install + 2GB backup), Available: ${opt_avail}MB"
        ((error_count++))
    fi

    # Check if backup directory is writable
    if ! mkdir -p "${BACKUP_BASE}" 2>/dev/null; then
        echo "ERROR: Cannot create backup directory at ${BACKUP_BASE}"
        ((error_count++))
    fi

    if [ "$error_count" -gt 0 ]; then
        echo
        echo "Pre-flight checks failed with $error_count error(s)."
        echo "Please resolve these issues before continuing."
        return 1
    fi

    echo "Pre-flight checks passed."
    return 0
}

# Notice text -----------------------------------------------------------

# Only clear screen if we have a proper terminal
if [ -t 1 ] && command -v clear >/dev/null 2>&1; then
    clear 2>/dev/null || true
fi
echo
echo "NOTICE..."
echo "This script is EXPERIMENTAL, please proceed with caution."
echo
echo "Before continuing with this script, an actual backup is recommended"
echo "in case anything should go wrong."
echo
echo "This script will backup all config files and necessary content."
echo "It will then clone the MacPatch master branch and install the"
echo "new software. Once the install is completed. This script will"
echo "put back all of the configuration files and content."
echo
echo

# Run pre-flight checks
if ! preflight_checks; then
    exit 1
fi

echo
if [ "$AUTO_CONFIRM" = true ]; then
	echo "Auto-confirm enabled, proceeding with upgrade..."
	UPOK="Y"
else
	read -p "Would you like to continue (Y/N)? [N]: " UPOK
	UPOK=${UPOK:-N}
fi

if [ "$UPOK" == "Y" ] || [ "$UPOK" == "y" ] ; then
	echo
else
	exit 0
fi


verify_backup() {
    local backup_path="$1"
    local error_count=0

    log_message "Verifying backup integrity..."

    if ! validate_path "$backup_path" "dir"; then
        log_message "ERROR: Backup directory does not exist: $backup_path"
        return 1
    fi

    # Check critical directories exist
    if [ ! -d "${backup_path}/Server/etc" ]; then
        log_message "ERROR: etc directory backup missing"
        ((error_count++))
    fi

    if [ ! -d "${backup_path}/Server/apps" ]; then
        log_message "ERROR: apps directory backup missing"
        ((error_count++))
    fi

    # Check critical files exist (new config format)
    if [ ! -f "${backup_path}/Server/apps/.mpglobal" ]; then
        log_message "WARNING: .mpglobal backup missing"
    fi

    if [ ! -f "${backup_path}/Server/apps/.mpapi" ]; then
        log_message "WARNING: .mpapi backup missing"
    fi

    if [ ! -f "${backup_path}/Server/apps/.mpconsole" ]; then
        log_message "WARNING: .mpconsole backup missing"
    fi

    if [ "$error_count" -gt 0 ]; then
        log_message "ERROR: Backup verification failed with $error_count errors"
        return 1
    fi

    log_message "Backup verification passed"
    return 0
}

cleanup_old_backups() {
    log_message "Cleaning up old backups (keeping last ${MAX_BACKUPS})..."

    if [ ! -d "${BACKUP_BASE}" ]; then
        return 0
    fi

    # List backup directories, sorted by date, skip the newest MAX_BACKUPS
    local old_backups=$(ls -dt "${BACKUP_BASE}"/upgrade_* 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)))

    if [ -n "$old_backups" ]; then
        echo "$old_backups" | while read -r backup_dir; do
            log_message "Removing old backup: $backup_dir"
            rm -rf "$backup_dir"
        done
    else
        log_message "No old backups to remove"
    fi
}

stop_services() {
    log_message "Stopping MacPatch services and tracking which ones are running..."
    local services_to_check=()
    RUNNING_SERVICES=()

    # Build service list based on server type
    services_to_check+=("${CORE_SERVICES[@]}")

    if $MASTERSERVER; then
        services_to_check+=("${MASTER_SERVICES[@]}")
        services_to_check+=("${CONSOLE_SERVICES[@]}")
    else
        # Console-only server
        services_to_check+=("${CONSOLE_SERVICES[@]}")
    fi

    if [[ "$platform" == "linux" ]]; then
        # Use systemctl for Linux
        log_message "Using systemctl to stop services..."
        for service in "${services_to_check[@]}"; do
            if systemctl is-active --quiet "${service}"; then
                log_message "Stopping ${service} (was running)..."
                RUNNING_SERVICES+=("${service}")
                if ! systemctl stop "${service}"; then
                    log_message "WARNING: Failed to stop ${service}"
                fi
            else
                log_message "${service} is not running, skipping..."
            fi
        done
    else
        # Use launchctl for macOS
        log_message "Using launchctl to stop services..."
        local launchd_services=(
            "gov.llnl.mp.nginx:MPNginx"
        )

        if $MASTERSERVER; then
            launchd_services+=(
                "gov.llnl.mp.py.api:MPAPI"
                "gov.llnl.mp.invd:MPInventoryD"
                "gov.llnl.mp.rsync:MPRsyncServer"
            )
        fi

        launchd_services+=("gov.llnl.mp.py.console:MPConsole")

        for service_pair in "${launchd_services[@]}"; do
            local launchd_name="${service_pair%%:*}"
            local service_name="${service_pair##*:}"

            if launchctl list | grep -q "${launchd_name}"; then
                log_message "Stopping ${service_name} (was running)..."
                RUNNING_SERVICES+=("${service_name}")
                if ! launchctl unload "/Library/LaunchDaemons/${launchd_name}.plist" 2>/dev/null; then
                    log_message "WARNING: Failed to unload ${launchd_name}"
                fi
            else
                log_message "${service_name} is not loaded, skipping..."
            fi
        done
    fi

    # Log which services were running
    if [ ${#RUNNING_SERVICES[@]} -gt 0 ]; then
        log_message "Services that were running: ${RUNNING_SERVICES[*]}"
        echo "${RUNNING_SERVICES[@]}" > "${MPBASEBACK}/running_services.txt"
    else
        log_message "No services were running"
    fi
}

start_services() {
    log_message "Starting MacPatch services that were previously running..."

    # If no services were tracked, try to read from backup file
    if [ ${#RUNNING_SERVICES[@]} -eq 0 ] && [ -f "${MPBASEBACK}/running_services.txt" ]; then
        RUNNING_SERVICES=($(cat "${MPBASEBACK}/running_services.txt"))
        log_message "Loaded service list from backup: ${RUNNING_SERVICES[*]}"
    fi

    # If still no services, warn and exit
    if [ ${#RUNNING_SERVICES[@]} -eq 0 ]; then
        log_message "WARNING: No services to start (none were running before)"
        return 0
    fi

    if [[ "$platform" == "linux" ]]; then
        # Use systemctl for Linux
        log_message "Using systemctl to start services..."
        for service in "${RUNNING_SERVICES[@]}"; do
            log_message "Starting ${service}..."
            if ! systemctl start "${service}"; then
                log_message "ERROR: Failed to start ${service}"
                return 1
            fi
        done
    else
        # Use launchctl for macOS - map service names to launchd names
        log_message "Using launchctl to start services..."
        for service in "${RUNNING_SERVICES[@]}"; do
            local launchd_name=""
            case "$service" in
                MPNginx)
                    launchd_name="gov.llnl.mp.nginx"
                    ;;
                MPAPI)
                    launchd_name="gov.llnl.mp.py.api"
                    ;;
                MPConsole)
                    launchd_name="gov.llnl.mp.py.console"
                    ;;
                MPInventoryD)
                    launchd_name="gov.llnl.mp.invd"
                    ;;
                MPRsyncServer)
                    launchd_name="gov.llnl.mp.rsync"
                    ;;
                *)
                    log_message "WARNING: Unknown service ${service}, skipping..."
                    continue
                    ;;
            esac

            log_message "Starting ${service} (${launchd_name})..."
            if ! launchctl load "/Library/LaunchDaemons/${launchd_name}.plist"; then
                log_message "ERROR: Failed to load ${launchd_name}"
                return 1
            fi
        done
    fi
}

verify_services_stopped() {
    log_message "Verifying all MacPatch services are stopped..."
    local timeout=$1
    local elapsed=0
    local check_interval=2

    while [ $elapsed -lt $timeout ]; do
        local running_count=0

        if [[ "$platform" == "linux" ]]; then
            # Check systemd services
            local all_services=("${CORE_SERVICES[@]}")
            if $MASTERSERVER; then
                all_services+=("${MASTER_SERVICES[@]}")
                all_services+=("${CONSOLE_SERVICES[@]}")
            else
                all_services+=("${CONSOLE_SERVICES[@]}")
            fi

            for service in "${all_services[@]}"; do
                if systemctl is-active --quiet "${service}"; then
                    ((running_count++))
                fi
            done
        else
            # Check for common MacPatch processes on macOS
            running_count=$(ps aux | grep -E "(mpapi|mpconsole|gov.llnl.mp)" | grep -v grep | wc -l)
        fi

        if [ "$running_count" -eq 0 ]; then
            log_message "All services stopped successfully"
            return 0
        fi

        log_message "Waiting for services to stop... ($elapsed/${timeout}s, $running_count services still running)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    log_message "ERROR: Services did not stop within ${timeout} seconds"
    if [[ "$platform" == "linux" ]]; then
        systemctl status MP* --no-pager | tee -a "${BACKUP_LOG}"
    else
        ps aux | grep -E "(mpapi|mpconsole|gov.llnl.mp)" | grep -v grep | tee -a "${BACKUP_LOG}"
    fi
    return 1
}

verify_services_started() {
    log_message "Verifying MacPatch services started successfully..."
    local timeout=$1
    local elapsed=0
    local check_interval=3
    local expected_count=0
    local running_count=0

    # Calculate expected service count
    expected_count=${#CORE_SERVICES[@]}
    if $MASTERSERVER; then
        expected_count=$((expected_count + ${#MASTER_SERVICES[@]} + ${#CONSOLE_SERVICES[@]}))
    else
        expected_count=$((expected_count + ${#CONSOLE_SERVICES[@]}))
    fi

    while [ $elapsed -lt $timeout ]; do
        running_count=0

        if [[ "$platform" == "linux" ]]; then
            # Check systemd services
            local all_services=("${CORE_SERVICES[@]}")
            if $MASTERSERVER; then
                all_services+=("${MASTER_SERVICES[@]}")
                all_services+=("${CONSOLE_SERVICES[@]}")
            else
                all_services+=("${CONSOLE_SERVICES[@]}")
            fi

            for service in "${all_services[@]}"; do
                if systemctl is-active --quiet "${service}"; then
                    ((running_count++))
                fi
            done
        else
            # Check for MacPatch processes on macOS
            local api_running=$(ps aux | grep "mpapi" | grep -v grep | wc -l)
            local console_running=$(ps aux | grep "mpconsole" | grep -v grep | wc -l)
            local nginx_running=$(ps aux | grep "nginx.*MacPatch" | grep -v grep | wc -l)

            running_count=0
            if [ "$nginx_running" -gt 0 ]; then ((running_count++)); fi
            if [ "$console_running" -gt 0 ]; then ((running_count++)); fi
            if $MASTERSERVER; then
                if [ "$api_running" -gt 0 ]; then ((running_count++)); fi
            fi
        fi

        if [ "$running_count" -ge "$expected_count" ]; then
            log_message "Services started successfully ($running_count/$expected_count running)"
            return 0
        fi

        log_message "Waiting for services to start... ($elapsed/${timeout}s, $running_count/$expected_count running)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    log_message "WARNING: Could not verify all services started within ${timeout} seconds"
    log_message "Current status: $running_count/$expected_count services running"

    if [[ "$platform" == "linux" ]]; then
        systemctl status MP* --no-pager | tee -a "${BACKUP_LOG}"
    else
        log_message "Current running processes:"
        ps aux | grep -E "(mpapi|mpconsole|gov.llnl.mp)" | grep -v grep | tee -a "${BACKUP_LOG}"
    fi
    return 1
}

verify_installation() {
    log_message "Verifying new installation..."
    local error_count=0

    # Check critical directories
    if [ ! -d "${MPSERVERBASE}/conf" ]; then
        log_message "ERROR: conf directory missing"
        ((error_count++))
    fi

    if [ ! -d "${MPSERVERBASE}/apps" ]; then
        log_message "ERROR: apps directory missing"
        ((error_count++))
    fi

    # Check for new API structure
    if [ ! -d "${MPSERVERBASE}/apps/api" ]; then
        log_message "ERROR: apps/api directory missing"
        ((error_count++))
    fi

    if [ ! -f "${MPSERVERBASE}/apps/api/app.py" ]; then
        log_message "ERROR: apps/api/app.py missing"
        ((error_count++))
    fi

    # Check for Console structure
    if [ ! -d "${MPSERVERBASE}/apps/console" ]; then
        log_message "ERROR: apps/console directory missing"
        ((error_count++))
    fi

    if [ ! -f "${MPSERVERBASE}/apps/console/app.py" ]; then
        log_message "ERROR: apps/console/app.py missing"
        ((error_count++))
    fi

    if [ ! -f "/opt/MacPatch/scripts/MPBuildServer.sh" ]; then
        log_message "ERROR: MPBuildServer.sh missing - build may have failed"
        ((error_count++))
    fi

    if [ "$error_count" -gt 0 ]; then
        log_message "ERROR: Installation verification failed with $error_count errors"
        return 1
    fi

    log_message "Installation verification passed"
    return 0
}

rollback() {
    log_message "ERROR: Upgrade failed. Attempting rollback..."

    # Restore from backup if it exists
    if [ -d "${MPBASEBACK}" ]; then
        if [ -d "/opt/MacPatch" ]; then
            log_message "Moving failed installation to /opt/MacPatch_failed_${BACKUP_TIMESTAMP}"
            mv "/opt/MacPatch" "/opt/MacPatch_failed_${BACKUP_TIMESTAMP}" || true
        fi

        if [ -d "/opt/MacPatch_back" ]; then
            log_message "Restoring previous installation from /opt/MacPatch_back"
            if mv "/opt/MacPatch_back" "/opt/MacPatch"; then
                log_message "Rolled back to previous MacPatch installation"

                # Try to restart services
                log_message "Attempting to restart services..."
                if start_services; then
                    log_message "Services restarted successfully"
                else
                    log_message "WARNING: Could not restart services automatically"
                    log_message "Please start services manually"
                fi
            else
                log_message "ERROR: Failed to restore previous installation"
            fi
        fi
    fi

    log_message "Rollback attempt completed. Please review logs at: ${BACKUP_LOG}"
    exit 1
}

# Set trap for errors
trap rollback ERR

# ----------------------------------------------------------------------------
# Backup
# ----------------------------------------------------------------------------

# Create backup directory structure FIRST before any logging
if ! mkdir -p "${MPBASEBACK}/Server/etc"; then
    echo "ERROR: Failed to create backup directory structure at ${MPBASEBACK}"
    exit 1
fi

if ! mkdir -p "${MPBASEBACK}/Server/apps"; then
    echo "ERROR: Failed to create apps backup directory"
    exit 1
fi

# Now we can log since backup directory exists
log_message "=== MacPatch Server Upgrade Started ==="
log_message "Backup directory: ${MPBASEBACK}"
if $USE_GIT_CLONE; then
    log_message "Source: GitHub clone (branch: ${GITBRANCH})"
else
    log_message "Source: Local directory (${SOURCE_DIR})"
fi

if ! mkdir -p "${MPBASEBACK}/Server/apps"; then
    log_message "ERROR: Failed to create apps backup directory"
    exit 1
fi

# Verify backup directories were created
if ! validate_path "${MPBASEBACK}/Server/etc" "dir"; then
    log_message "ERROR: Failed to verify backup directory creation"
    exit 1
fi

# Check available disk space (estimate: 2GB needed)
if ! check_disk_space 2048 "/opt"; then
    log_message "ERROR: Insufficient disk space for backup"
    exit 1
fi

# 1) Shutdown all services
stop_services

# Verify services actually stopped
if ! verify_services_stopped "${SERVICE_SHUTDOWN_TIMEOUT}"; then
    log_message "ERROR: Services did not stop properly"
    log_message "Attempting forced shutdown..."

    if [[ "$platform" == "linux" ]]; then
        # Force stop systemd services
        local all_services=("${CORE_SERVICES[@]}")
        if $MASTERSERVER; then
            all_services+=("${MASTER_SERVICES[@]}")
            all_services+=("${CONSOLE_SERVICES[@]}")
        else
            all_services+=("${CONSOLE_SERVICES[@]}")
        fi

        for service in "${all_services[@]}"; do
            systemctl kill "${service}" 2>/dev/null || true
        done
    else
        # Try to kill processes manually on macOS
        pkill -f mpapi || true
        pkill -f mpconsole || true
        pkill -f "nginx.*MacPatch" || true
    fi

    sleep 2

    # Check again
    if ! verify_services_stopped 10; then
        log_message "ERROR: Could not stop services. Manual intervention required."
        exit 1
    fi
fi
log_message "Services shutdown verified"

# Backup etc files
log_message "Backing up configuration files..."
if ! validate_path "${MPSERVERBASE}/etc" "dir"; then
    log_message "ERROR: etc directory not found at ${MPSERVERBASE}/etc"
    exit 1
fi

if ! cp -rp "${MPSERVERBASE}/etc" "${MPBASEBACK}/Server/"; then
    log_message "ERROR: Failed to backup etc directory"
    exit 1
fi

# Backup nginx sites configuration
log_message "Backing up nginx sites configuration..."
# Check production location: /opt/MacPatch/Server/nginx/conf/sites
if [ -d "${MPSERVERBASE}/nginx/conf/sites" ]; then
    if ! mkdir -p "${MPBASEBACK}/Server/nginx/conf"; then
        log_message "ERROR: Failed to create nginx backup directory"
        exit 1
    fi
    if ! cp -rp "${MPSERVERBASE}/nginx/conf/sites" "${MPBASEBACK}/Server/nginx/conf/"; then
        log_message "ERROR: Failed to backup nginx sites from ${MPSERVERBASE}/nginx/conf/sites"
        exit 1
    fi
    log_message "Nginx sites backed up successfully from ${MPSERVERBASE}/nginx/conf/sites"
# Fallback: check alternate location Server/conf/nginx/sites
elif [ -d "${MPSERVERBASE}/conf/nginx/sites" ]; then
    if ! mkdir -p "${MPBASEBACK}/Server/nginx/conf"; then
        log_message "ERROR: Failed to create nginx backup directory"
        exit 1
    fi
    if ! cp -rp "${MPSERVERBASE}/conf/nginx/sites" "${MPBASEBACK}/Server/nginx/conf/"; then
        log_message "ERROR: Failed to backup nginx sites from ${MPSERVERBASE}/conf/nginx/sites"
        exit 1
    fi
    log_message "Nginx sites backed up successfully from ${MPSERVERBASE}/conf/nginx/sites"
else
    log_message "WARNING: nginx sites directory not found at ${MPSERVERBASE}/nginx/conf/sites or ${MPSERVERBASE}/conf/nginx/sites, skipping..."
fi

# Backup py app files
log_message "Backing up application config files..."
if ! validate_path "${MPSERVERBASE}/apps" "dir"; then
    log_message "ERROR: apps directory not found at ${MPSERVERBASE}/apps"
    exit 1
fi

# Backup new config files (.mpglobal, .mpapi, .mpconsole)
log_message "Backing up .mpglobal configuration..."
if [ -f "${MPSERVERBASE}/apps/.mpglobal" ]; then
    if ! cp -p "${MPSERVERBASE}/apps/.mpglobal" "${MPBASEBACK}/Server/apps/"; then
        log_message "ERROR: Failed to backup .mpglobal"
        exit 1
    fi
else
    log_message "WARNING: .mpglobal not found at ${MPSERVERBASE}/apps/"
fi

log_message "Backing up .mpapi configuration..."
if [ -f "${MPSERVERBASE}/apps/.mpapi" ]; then
    if ! cp -p "${MPSERVERBASE}/apps/.mpapi" "${MPBASEBACK}/Server/apps/"; then
        log_message "ERROR: Failed to backup .mpapi"
        exit 1
    fi
else
    log_message "WARNING: .mpapi not found at ${MPSERVERBASE}/apps/"
fi

log_message "Backing up .mpconsole configuration..."
if [ -f "${MPSERVERBASE}/apps/.mpconsole" ]; then
    if ! cp -p "${MPSERVERBASE}/apps/.mpconsole" "${MPBASEBACK}/Server/apps/"; then
        log_message "ERROR: Failed to backup .mpconsole"
        exit 1
    fi
else
    log_message "WARNING: .mpconsole not found at ${MPSERVERBASE}/apps/"
fi

# Also backup any legacy .cfg files if they exist (for backwards compatibility)
if ls "${MPSERVERBASE}/apps/"*.cfg 1> /dev/null 2>&1; then
    log_message "Backing up legacy .cfg files..."
    find "${MPSERVERBASE}/apps" -maxdepth 1 -name "*.cfg" -type f -exec cp -p {} "${MPBASEBACK}/Server/apps/" \; || {
        log_message "WARNING: Failed to backup some legacy .cfg files"
    }
fi

# Handle content files
if $MOVECONTENT; then
    log_message "Processing content files..."
    content_path="${MPBASE}/Content"

    if $SKIP_CONTENT_MIGRATION; then
        # -n flag: No migration, keep content in place
        log_message "Content migration disabled (-n flag)"
        log_message "Content will remain at ${content_path} (not backed up or moved)"

        # Verify Content exists
        if [ -d "$content_path" ]; then
            log_message "Content directory verified at ${content_path}"
        elif [[ -L "$content_path" ]]; then
            log_message "WARNING: Content is a symlink - it will remain as-is"
        else
            log_message "WARNING: Content directory not found at ${content_path}"
        fi

        USECONTENTLNK=false
        echo "no_migration" > "${MPBASEBACK}/content_mode.txt"

    else
        # Default behavior: Migrate to $CONTENT_DIR with symlink
        log_message "Content directory location: ${CONTENT_DIR}"
        mpcontent_path="${CONTENT_DIR}"

        if [[ -L "$content_path" ]]; then
            # Content is already a symlink
            USECONTENTLNK=true
            MPCONTENTLNK=$(resolve_symlink "$content_path")
            log_message "Content is already symlinked to: ${MPCONTENTLNK}"

            # Save symlink target for restoration
            if ! echo "${MPCONTENTLNK}" > "${MPBASEBACK}/content_symlink.txt"; then
                log_message "ERROR: Failed to save symlink information"
                exit 1
            fi

            # Remove the symlink
            if ! unlink "$content_path"; then
                log_message "ERROR: Failed to unlink content symlink"
                exit 1
            fi
        elif [ -d "$content_path" ]; then
            # Content is a real directory - migrate to $CONTENT_DIR
            log_message "Content is a directory, migrating to ${mpcontent_path}..."

            # Validate that parent directory exists
            parent_dir=$(dirname "$mpcontent_path")
            if [ ! -d "$parent_dir" ]; then
                log_message "Creating parent directory: ${parent_dir}"
                if ! mkdir -p "$parent_dir"; then
                    log_message "ERROR: Failed to create parent directory ${parent_dir}"
                    exit 1
                fi
            fi

            # Check if content directory already exists at target location
            if [ -e "$mpcontent_path" ]; then
                log_message "WARNING: ${mpcontent_path} already exists, backing up to ${mpcontent_path}.old"
                if ! mv "$mpcontent_path" "${mpcontent_path}.old"; then
                    log_message "ERROR: Failed to backup existing ${mpcontent_path}"
                    exit 1
                fi
            fi

            # Move content to target location
            if ! mv "$content_path" "$mpcontent_path"; then
                log_message "ERROR: Failed to move content to ${mpcontent_path}"
                exit 1
            fi

            USECONTENTLNK=true
            MPCONTENTLNK="$mpcontent_path"
            log_message "Content moved to ${mpcontent_path}"

            # Save the new symlink target
            if ! echo "${MPCONTENTLNK}" > "${MPBASEBACK}/content_symlink.txt"; then
                log_message "ERROR: Failed to save symlink information"
                exit 1
            fi
        else
            log_message "WARNING: Content directory not found at ${content_path}"
            USECONTENTLNK=false
        fi

        echo "use_symlink" > "${MPBASEBACK}/content_mode.txt"
    fi
fi

# Verify backup before proceeding
if ! verify_backup "${MPBASEBACK}"; then
    log_message "ERROR: Backup verification failed. Aborting upgrade."
    exit 1
fi

# Archive or clean current installation
if $SKIP_CONTENT_MIGRATION; then
    # -n flag: Delete everything except Content
    log_message "Cleaning MacPatch installation (preserving Content)..."
    macpatch_src="/opt/MacPatch"

    if ! validate_path "$macpatch_src" "dir"; then
        log_message "ERROR: MacPatch directory not found"
        exit 1
    fi

    # Delete everything in /opt/MacPatch except Content
    log_message "Removing all files/directories except Content..."
    cd "$macpatch_src" || exit 1

    for item in *; do
        if [ "$item" != "Content" ]; then
            log_message "Removing: ${item}"
            rm -rf "$item"
        fi
    done

    # Also remove hidden files/directories except .build if it exists
    for item in .[^.]*; do
        if [ -e "$item" ] && [ "$item" != ".build" ]; then
            log_message "Removing: ${item}"
            rm -rf "$item"
        fi
    done

    log_message "MacPatch cleaned (Content preserved)"

else
    # Default: Archive entire installation
    log_message "Archiving current MacPatch installation..."
    macpatch_src="/opt/MacPatch"
    macpatch_backup="/opt/MacPatch_back"

    if [ -d "$macpatch_backup" ]; then
        log_message "Removing previous MacPatch_back directory..."
        if ! rm -rf "$macpatch_backup"; then
            log_message "ERROR: Failed to remove old backup directory"
            exit 1
        fi
    fi

    if ! validate_path "$macpatch_src" "dir"; then
        log_message "ERROR: Cannot archive - MacPatch directory not found"
        exit 1
    fi

    if ! mv "$macpatch_src" "$macpatch_backup"; then
        log_message "ERROR: Failed to archive current installation"
        exit 1
    fi
    log_message "Current installation archived successfully"
fi

# ----------------------------------------------------------------------------
# Download/Copy and build
# ----------------------------------------------------------------------------

install_dest="/opt/MacPatch"
build_script="${install_dest}/scripts/MPBuildServer.sh"

if $USE_GIT_CLONE; then
    # Git clone mode
    log_message "Cloning MacPatch repository from GitHub (branch: ${GITBRANCH})..."

    if $SKIP_CONTENT_MIGRATION; then
        # -n flag: Clone into existing directory (Content already there)
        log_message "Cloning into existing directory (Content preserved)..."

        if ! cd "$install_dest"; then
            log_message "ERROR: Cannot change to ${install_dest}"
            exit 1
        fi

        # Clone to temp location
        if ! git clone https://github.com/LLNL/MacPatch.git -b "$GITBRANCH" "${install_dest}/.tmp_clone"; then
            log_message "ERROR: Failed to clone repository to temp location"
            exit 1
        fi

        # Move files from temp clone to current directory
        log_message "Moving cloned files into place..."
        if ! mv "${install_dest}/.tmp_clone"/* "${install_dest}/" 2>/dev/null; then
            # Try with dotfiles too
            mv "${install_dest}/.tmp_clone"/.[^.]* "${install_dest}/" 2>/dev/null || true
        fi
        mv "${install_dest}/.tmp_clone"/* "${install_dest}/" 2>/dev/null || true

        # Remove temp clone directory
        rm -rf "${install_dest}/.tmp_clone"

        log_message "Repository cloned successfully (Content preserved)"

    else
        # Default: Clone to fresh directory
        if ! cd /opt; then
            log_message "ERROR: Cannot change to /opt directory"
            exit 1
        fi

        # Remove any existing directory
        if [ -d "$install_dest" ]; then
            log_message "WARNING: ${install_dest} already exists, removing..."
            if ! rm -rf "$install_dest"; then
                log_message "ERROR: Failed to remove existing directory"
                exit 1
            fi
        fi

        # Clone repository
        if ! git clone https://github.com/LLNL/MacPatch.git -b "$GITBRANCH" "$install_dest"; then
            log_message "ERROR: Failed to clone repository"
            exit 1
        fi

        log_message "Repository cloned successfully"
    fi

else
    # Local source mode - copy from SOURCE_DIR
    log_message "Copying MacPatch from local source: ${SOURCE_DIR}"

    if $SKIP_CONTENT_MIGRATION; then
        # -n flag: Copy into existing directory (Content already there)
        log_message "Copying into existing directory (Content preserved)..."

        if ! cd "$install_dest"; then
            log_message "ERROR: Cannot change to ${install_dest}"
            exit 1
        fi

        # Copy everything except Content directory
        log_message "Copying files from source (excluding Content)..."
        for item in "${SOURCE_DIR}"/*; do
            item_name=$(basename "$item")
            if [ "$item_name" != "Content" ]; then
                if ! cp -rp "$item" "${install_dest}/"; then
                    log_message "ERROR: Failed to copy $item_name"
                    exit 1
                fi
            fi
        done

        # Copy hidden files/directories
        for item in "${SOURCE_DIR}"/.[^.]*; do
            if [ -e "$item" ]; then
                item_name=$(basename "$item")
                if [ "$item_name" != ".git" ]; then  # Skip .git directory
                    cp -rp "$item" "${install_dest}/" 2>/dev/null || true
                fi
            fi
        done

        log_message "Source copied successfully (Content preserved)"

    else
        # Default: Copy to fresh directory
        if ! cd /opt; then
            log_message "ERROR: Cannot change to /opt directory"
            exit 1
        fi

        # Remove any existing directory
        if [ -d "$install_dest" ]; then
            log_message "WARNING: ${install_dest} already exists, removing..."
            if ! rm -rf "$install_dest"; then
                log_message "ERROR: Failed to remove existing directory"
                exit 1
            fi
        fi

        # Copy source directory to install destination
        log_message "Copying source directory to ${install_dest}..."
        if ! cp -rp "$SOURCE_DIR" "$install_dest"; then
            log_message "ERROR: Failed to copy source directory"
            exit 1
        fi

        log_message "Source copied successfully"
    fi
fi

# Verify installation destination
if ! validate_path "$install_dest" "dir"; then
    log_message "ERROR: Installation directory not found at ${install_dest}"
    exit 1
fi

if ! validate_path "$build_script" "file"; then
    log_message "ERROR: MPBuildServer.sh not found at ${build_script}"
    exit 1
fi

# Make build script executable if needed
if [ ! -x "$build_script" ]; then
    log_message "Making build script executable..."
    chmod +x "$build_script"
fi

log_message "Repository cloned successfully"

log_message "Building MacPatch server..."
if ! "$build_script"; then
    log_message "ERROR: Build failed"
    exit 1
fi

# Verify build completed
if ! verify_installation; then
    log_message "ERROR: Build verification failed"
    exit 1
fi
log_message "Build completed and verified successfully"

# ----------------------------------------------------------------------------
# Restore
# ----------------------------------------------------------------------------

log_message "Restoring configuration and content..."

# Restore etc files
log_message "Restoring etc configuration..."
if ! mv "${MPSERVERBASE}/etc" "${MPSERVERBASE}/etc_orig"; then
    log_message "ERROR: Failed to backup new etc directory"
    exit 1
fi
if ! mv "${MPBASEBACK}/Server/etc" "${MPSERVERBASE}/"; then
    log_message "ERROR: Failed to restore etc directory"
    exit 1
fi

# Restore nginx sites configuration
log_message "Restoring nginx sites configuration..."
if [ -d "${MPBASEBACK}/Server/nginx/conf/sites" ]; then
    # Ensure the nginx/conf directory exists at production location
    if ! mkdir -p "${MPSERVERBASE}/nginx/conf"; then
        log_message "ERROR: Failed to create nginx conf directory at ${MPSERVERBASE}/nginx/conf"
        exit 1
    fi

    # Backup new sites if they exist
    if [ -d "${MPSERVERBASE}/nginx/conf/sites" ]; then
        if ! mv "${MPSERVERBASE}/nginx/conf/sites" "${MPSERVERBASE}/nginx/conf/sites_orig"; then
            log_message "WARNING: Failed to backup new nginx sites directory"
        fi
    fi

    # Restore sites to production location: /opt/MacPatch/Server/nginx/conf/sites
    if ! cp -rp "${MPBASEBACK}/Server/nginx/conf/sites" "${MPSERVERBASE}/nginx/conf/"; then
        log_message "ERROR: Failed to restore nginx sites to ${MPSERVERBASE}/nginx/conf/"
        exit 1
    fi
    log_message "Nginx sites restored successfully to ${MPSERVERBASE}/nginx/conf/sites"
else
    log_message "WARNING: nginx sites not found in backup, skipping..."
fi

# Restore application config files (new format: .mpglobal, .mpapi, .mpconsole)
log_message "Restoring application configurations..."

# Restore .mpglobal
if [ -f "${MPBASEBACK}/Server/apps/.mpglobal" ]; then
    if [ -f "${MPSERVERBASE}/apps/.mpglobal" ]; then
        if ! mv "${MPSERVERBASE}/apps/.mpglobal" "${MPSERVERBASE}/apps/.mpglobal.new"; then
            log_message "WARNING: Failed to backup new .mpglobal"
        fi
    fi
    if ! cp -p "${MPBASEBACK}/Server/apps/.mpglobal" "${MPSERVERBASE}/apps/.mpglobal"; then
        log_message "ERROR: Failed to restore .mpglobal"
        exit 1
    fi
    log_message ".mpglobal restored successfully"
else
    log_message "WARNING: .mpglobal not found in backup, skipping"
fi

# Restore .mpapi
if [ -f "${MPBASEBACK}/Server/apps/.mpapi" ]; then
    if [ -f "${MPSERVERBASE}/apps/.mpapi" ]; then
        if ! mv "${MPSERVERBASE}/apps/.mpapi" "${MPSERVERBASE}/apps/.mpapi.new"; then
            log_message "WARNING: Failed to backup new .mpapi"
        fi
    fi
    if ! cp -p "${MPBASEBACK}/Server/apps/.mpapi" "${MPSERVERBASE}/apps/.mpapi"; then
        log_message "ERROR: Failed to restore .mpapi"
        exit 1
    fi
    log_message ".mpapi restored successfully"
else
    log_message "WARNING: .mpapi not found in backup, skipping"
fi

# Restore .mpconsole
if [ -f "${MPBASEBACK}/Server/apps/.mpconsole" ]; then
    if [ -f "${MPSERVERBASE}/apps/.mpconsole" ]; then
        if ! mv "${MPSERVERBASE}/apps/.mpconsole" "${MPSERVERBASE}/apps/.mpconsole.new"; then
            log_message "WARNING: Failed to backup new .mpconsole"
        fi
    fi
    if ! cp -p "${MPBASEBACK}/Server/apps/.mpconsole" "${MPSERVERBASE}/apps/.mpconsole"; then
        log_message "ERROR: Failed to restore .mpconsole"
        exit 1
    fi
    log_message ".mpconsole restored successfully"
else
    log_message "WARNING: .mpconsole not found in backup, skipping"
fi

# Handle legacy .cfg files if they exist in backup (backwards compatibility)
if ls "${MPBASEBACK}/Server/apps/"*.cfg 1> /dev/null 2>&1; then
    log_message "Restoring legacy .cfg files (if any)..."
    for cfg_file in "${MPBASEBACK}/Server/apps/"*.cfg; do
        if [ -f "$cfg_file" ]; then
            cfg_name=$(basename "$cfg_file")
            if [ -f "${MPSERVERBASE}/apps/$cfg_name" ]; then
                mv "${MPSERVERBASE}/apps/$cfg_name" "${MPSERVERBASE}/apps/${cfg_name}.new" || \
                    log_message "WARNING: Failed to backup new $cfg_name"
            fi
            cp -p "$cfg_file" "${MPSERVERBASE}/apps/" || \
                log_message "WARNING: Failed to restore $cfg_name"
        fi
    done
fi

# Restore content files
if $MOVECONTENT; then
    log_message "Restoring content..."
    server_content="${MPBASE}/Content"

    # Check content mode from backup FIRST
    content_mode="use_symlink"  # default
    if [ -f "${MPBASEBACK}/content_mode.txt" ]; then
        content_mode=$(cat "${MPBASEBACK}/content_mode.txt")
        log_message "Content mode from backup: ${content_mode}"
    fi

    if [ "$content_mode" = "no_migration" ]; then
        # Content was preserved in place - DO NOT remove it!
        log_message "Content was preserved in place at ${server_content}"

        # Verify Content still exists
        if [ -d "$server_content" ]; then
            log_message "Content verified at ${server_content}"
        else
            log_message "ERROR: Content directory missing at ${server_content}"
            exit 1
        fi

    else
        # Restore content with symlink - remove any existing content first
        log_message "Content directory location: ${CONTENT_DIR}"
        mpcontent_path="${CONTENT_DIR}"

        # Remove any existing content directory/symlink in new installation
        if [ -e "$server_content" ]; then
            if [ -L "$server_content" ]; then
                log_message "Removing new installation symlink..."
                unlink "$server_content"
            else
                log_message "Removing new installation content directory..."
                rm -rf "$server_content"
            fi
        fi

        # Determine content location from backup
        if [ -f "${MPBASEBACK}/content_symlink.txt" ]; then
            MPCONTENTLNK=$(cat "${MPBASEBACK}/content_symlink.txt")
            log_message "Content location from backup: ${MPCONTENTLNK}"
        else
            # No symlink file - content was in standard location, use $CONTENT_DIR
            MPCONTENTLNK="$mpcontent_path"
            log_message "No symlink file found, using default location: ${MPCONTENTLNK}"
        fi

        # Verify content directory exists
        if ! validate_path "$MPCONTENTLNK" "dir"; then
            log_message "ERROR: Content directory does not exist at ${MPCONTENTLNK}"
            log_message "Expected content location may have been moved or deleted"
            exit 1
        fi

        # Create symlink from /opt/MacPatch/Content to actual content location
        log_message "Creating symlink: ${server_content} -> ${MPCONTENTLNK}"
        if ! ln -s "$MPCONTENTLNK" "$server_content"; then
            log_message "ERROR: Failed to create content symlink"
            exit 1
        fi

        log_message "Content symlink created successfully: ${server_content} -> ${MPCONTENTLNK}"

        # Verify symlink works
        if [ ! -d "$server_content" ]; then
            log_message "ERROR: Content symlink verification failed"
            exit 1
        fi
    fi
fi

# Fix permissions on MacPatch directory
log_message "Setting correct permissions on ${MPBASE}..."
if [[ "$platform" == "linux" ]]; then
    # Linux: set ownership to appropriate user (usually www-data or nginx)
    if id "www-data" >/dev/null 2>&1; then
        MP_USER="www-data"
    elif id "nginx" >/dev/null 2>&1; then
        MP_USER="nginx"
    else
        MP_USER="root"
        log_message "WARNING: Could not find www-data or nginx user, using root"
    fi

    log_message "Setting ownership to ${MP_USER}..."
    chown -R ${MP_USER}:${MP_USER} "${MPBASE}" || log_message "WARNING: Failed to set ownership"

    # Set directory permissions to 755
    find "${MPBASE}" -type d -exec chmod 755 {} \; || log_message "WARNING: Failed to set directory permissions"

    # Set all file permissions to 644 first (base permission for non-executables)
    log_message "Setting base file permissions (644)..."
    find "${MPBASE}" -type f -exec chmod 644 {} \; 2>/dev/null || log_message "WARNING: Failed to set some file permissions"

    # Now set executable files to 755 (not just +x, but explicit 755)
    log_message "Setting executable permissions (755)..."

    # Nginx binary
    if [ -f "${MPSERVERBASE}/nginx/sbin/nginx" ]; then
        chmod 755 "${MPSERVERBASE}/nginx/sbin/nginx"
        log_message "Set nginx binary to 755"
    fi

    # Virtual environment binaries - all files in venv/bin should be 755
    for venv_bin in "${MPSERVERBASE}/env/api/bin" "${MPSERVERBASE}/env/console/bin" "${MPSERVERBASE}/env/server/bin"; do
        if [ -d "$venv_bin" ]; then
            log_message "Setting venv binaries to 755: $venv_bin"
            find "$venv_bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
        fi
    done

    # Shell scripts in all locations - set to 755
    find "${MPBASE}/scripts" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    find "${MPBASE}/Server/conf/scripts" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    find "${MPBASE}/Server/conf/Content/Web/clients" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true

    # Python scripts with shebangs - set to 755
    find "${MPSERVERBASE}/apps" -type f -name "*.py" -exec grep -l "^#!" {} \; 2>/dev/null | xargs -r chmod 755 2>/dev/null || true
    find "${MPSERVERBASE}/conf/scripts" -type f -name "*.py" -exec grep -l "^#!" {} \; 2>/dev/null | xargs -r chmod 755 2>/dev/null || true

    # All .py files in conf/scripts should be executable (they're typically admin scripts)
    find "${MPSERVERBASE}/conf/scripts" -type f -name "*.py" -exec chmod 755 {} \; 2>/dev/null || true

    # Systemd service files should remain 644 (not executable)
    find "${MPBASE}/Server/conf/scripts/systemd" -type f -name "*.service" -exec chmod 644 {} \; 2>/dev/null || true
else
    # macOS: set ownership to _appserver
    log_message "Setting ownership to _appserver..."
    chown -R _appserver:_appserver "${MPBASE}" || log_message "WARNING: Failed to set ownership"

    # Set directory permissions to 755
    find "${MPBASE}" -type d -exec chmod 755 {} \; || log_message "WARNING: Failed to set directory permissions"

    # Set all file permissions to 644 first (base permission for non-executables)
    log_message "Setting base file permissions (644)..."
    find "${MPBASE}" -type f -exec chmod 644 {} \; 2>/dev/null || log_message "WARNING: Failed to set some file permissions"

    # Now set executable files to 755 (not just +x, but explicit 755)
    log_message "Setting executable permissions (755)..."

    # Nginx binary
    if [ -f "${MPSERVERBASE}/nginx/sbin/nginx" ]; then
        chmod 755 "${MPSERVERBASE}/nginx/sbin/nginx"
        log_message "Set nginx binary to 755"
    fi

    # Virtual environment binaries - all files in venv/bin should be 755
    for venv_bin in "${MPSERVERBASE}/env/api/bin" "${MPSERVERBASE}/env/console/bin" "${MPSERVERBASE}/env/server/bin"; do
        if [ -d "$venv_bin" ]; then
            log_message "Setting venv binaries to 755: $venv_bin"
            find "$venv_bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
        fi
    done

    # Shell scripts in all locations - set to 755
    find "${MPBASE}/scripts" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    find "${MPBASE}/Server/conf/scripts" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    find "${MPBASE}/Server/conf/Content/Web/clients" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true

    # Python scripts with shebangs - set to 755
    find "${MPSERVERBASE}/apps" -type f -name "*.py" -exec grep -l "^#!" {} \; 2>/dev/null | xargs -r chmod 755 2>/dev/null || true
    find "${MPSERVERBASE}/conf/scripts" -type f -name "*.py" -exec grep -l "^#!" {} \; 2>/dev/null | xargs -r chmod 755 2>/dev/null || true

    # All .py files in conf/scripts should be executable (they're typically admin scripts)
    find "${MPSERVERBASE}/conf/scripts" -type f -name "*.py" -exec chmod 755 {} \; 2>/dev/null || true

    # Systemd service files should remain 644 (not executable)
    find "${MPBASE}/Server/conf/scripts/systemd" -type f -name "*.service" -exec chmod 644 {} \; 2>/dev/null || true
fi

# Set special permissions for Content directory
if [ -d "${MPCONTENT}" ]; then
    log_message "Setting write permissions on Content directory..."
    chmod -R 775 "${MPCONTENT}" || log_message "WARNING: Failed to set Content permissions"
fi

log_message "Permissions set successfully"

if $MASTERSERVER; then
    log_message "Upgrading database schema (master server)..."

    local apps_api_dir="${MPSERVERBASE}/apps/api"
    local apps_console_dir="${MPSERVERBASE}/apps/console"
    local config_global="${MPSERVERBASE}/apps/.mpglobal"
    local config_api="${MPSERVERBASE}/apps/.mpapi"

    # Backup database config before upgrade
    log_message "Backing up database configuration..."
    if [ -f "$config_global" ]; then
        db_backup="${MPBASEBACK}/Server/apps/.mpglobal.pre-dbupgrade"
        if ! cp "$config_global" "$db_backup"; then
            log_message "WARNING: Failed to backup .mpglobal config"
        fi
    fi
    if [ -f "$config_api" ]; then
        db_backup="${MPBASEBACK}/Server/apps/.mpapi.pre-dbupgrade"
        if ! cp "$config_api" "$db_backup"; then
            log_message "WARNING: Failed to backup .mpapi config"
        fi
    fi

    # Upgrade API database schema using Flask-Migrate
    log_message "Running API database migration (Flask-Migrate)..."
    if ! validate_path "$apps_api_dir" "dir"; then
        log_message "ERROR: API directory not found at ${apps_api_dir}"
        exit 1
    fi

    # Change to API directory
    if ! cd "$apps_api_dir"; then
        log_message "ERROR: Cannot change to API directory: ${apps_api_dir}"
        exit 1
    fi

    # Run Flask database upgrade using the API's virtual environment
    # Note: The virtual environment activation happens via runapp.sh or directly with flask command
    if command -v flask >/dev/null 2>&1; then
        log_message "Running Flask database upgrade for API..."
        if ! flask db upgrade; then
            log_message "ERROR: API database upgrade failed"
            log_message "Database may be in inconsistent state. Check logs carefully."
            exit 1
        fi
        log_message "API database schema upgraded successfully"
    else
        log_message "WARNING: Flask command not found, skipping API database migration"
        log_message "You may need to run 'flask db upgrade' manually in ${apps_api_dir}"
    fi

    # Upgrade Console database schema using Flask-Migrate
    log_message "Running Console database migration (Flask-Migrate)..."
    if ! validate_path "$apps_console_dir" "dir"; then
        log_message "ERROR: Console directory not found at ${apps_console_dir}"
        exit 1
    fi

    # Change to Console directory
    if ! cd "$apps_console_dir"; then
        log_message "ERROR: Cannot change to Console directory: ${apps_console_dir}"
        exit 1
    fi

    # Run Flask database upgrade using the Console's virtual environment
    if command -v flask >/dev/null 2>&1; then
        log_message "Running Flask database upgrade for Console..."
        if ! flask db upgrade; then
            log_message "ERROR: Console database upgrade failed"
            log_message "Database may be in inconsistent state. Check logs carefully."
            exit 1
        fi
        log_message "Console database schema upgraded successfully"
    else
        log_message "WARNING: Flask command not found, skipping Console database migration"
        log_message "You may need to run 'flask db upgrade' manually in ${apps_console_dir}"
    fi

    log_message "All database migrations completed successfully"
fi

# Start Services
if ! start_services; then
    log_message "ERROR: Failed to start services"
    exit 1
fi

# Verify services started
if ! verify_services_started "${SERVICE_STARTUP_TIMEOUT}"; then
    log_message "WARNING: Could not verify all services started properly"
    log_message "Please check service status manually after upgrade completes"
else
    log_message "Services started and verified successfully"
fi

# Clean up old backups
cleanup_old_backups

# Disable error trap since we succeeded
trap - ERR

log_message "=== MacPatch Server Upgrade Completed Successfully ==="
log_message "Backup preserved at: ${MPBASEBACK}"
log_message "Log file: ${BACKUP_LOG}"
echo
echo "Upgrade completed successfully!"
echo "Backup location: ${MPBASEBACK}"
echo "Log file: ${BACKUP_LOG}"
