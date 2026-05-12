#!/bin/bash
#
# ----------------------------------------------------------------------------
# Script: MPServerUpgrader.sh
# Version: 2.0
#
# Description:
# Upgrade script will upgrade a current install of the MacPatch server
#
# History:
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
#   - Upgrades MacPatch server from master branch
#   - Creates timestamped backup in /opt/backups/mp
#   - Automatically verifies and rolls back on failure
#
# sudo MPServerUpgrader.sh -b <branch>
#   - Upgrades from specified GitHub branch
#
# sudo MPServerUpgrader.sh -m
#   - Upgrade master/distribution server (includes database migration)
#
# sudo MPServerUpgrader.sh -b develop -m
#   - Upgrade master server from develop branch
#
# Backups are stored in: /opt/backups/mp/upgrade_YYYYMMDD_HHMMSS
# Logs are saved to: <backup_dir>/backup.log
# Old backups are automatically cleaned up (keeps last 5)
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
BACKUP_BASE="/opt/backups/mp"
MPBASEBACK="${BACKUP_BASE}/upgrade_${BACKUP_TIMESTAMP}"
BACKUP_LOG="${MPBASEBACK}/backup.log"
GITBRANCH="master"
MOVECONTENT=true
MASTERSERVER=false
MAX_BACKUPS=5  # Keep last 5 backups
SERVICE_SHUTDOWN_TIMEOUT=60  # Seconds to wait for services to stop
SERVICE_STARTUP_TIMEOUT=60   # Seconds to wait for services to start
# Script Input Args ----------------------------------------------------------

usage() { echo "Usage: $0 [-b GitHub Branch] -m (Is Distribution server)" 1>&2; exit 1; }

while getopts "hb:d" opt; do
	case $opt in
		b)
			GITBRANCH=${OPTARG}
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

    # Check if ServerSetup.py exists
    local serversetup_path="${MPSERVERBASE}/conf/scripts/setup/ServerSetup.py"
    if ! validate_path "$serversetup_path" "file"; then
        echo "ERROR: ServerSetup.py not found at ${serversetup_path}"
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

clear
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
read -p "Would you like to continue (Y/N)? [N]: " UPOK
UPOK=${UPOK:-N}
if [ "$UPOK" == "Y" ] || [ "$UPOK" == "y" ] ; then
	echo
else
	exit 0
fi

# ----------------------------------------------------------------------------
# Helper Functions
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

    # Check critical files exist
    if [ ! -f "${backup_path}/Server/apps/config.cfg" ]; then
        log_message "ERROR: config.cfg backup missing"
        ((error_count++))
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

verify_services_stopped() {
    log_message "Verifying all MacPatch services are stopped..."
    local timeout=$1
    local elapsed=0
    local check_interval=2

    while [ $elapsed -lt $timeout ]; do
        # Check for common MacPatch processes
        local running_processes=$(ps aux | grep -E "(mpapi|mpconsole|gov.llnl.mp)" | grep -v grep | wc -l)

        if [ "$running_processes" -eq 0 ]; then
            log_message "All services stopped successfully"
            return 0
        fi

        log_message "Waiting for services to stop... ($elapsed/${timeout}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    log_message "ERROR: Services did not stop within ${timeout} seconds"
    ps aux | grep -E "(mpapi|mpconsole|gov.llnl.mp)" | grep -v grep | tee -a "${BACKUP_LOG}"
    return 1
}

verify_services_started() {
    log_message "Verifying MacPatch services started successfully..."
    local timeout=$1
    local elapsed=0
    local check_interval=3

    while [ $elapsed -lt $timeout ]; do
        # Check if critical services are running
        local api_running=$(ps aux | grep mpapi | grep -v grep | wc -l)
        local console_running=$(ps aux | grep mpconsole | grep -v grep | wc -l)

        if [ "$api_running" -gt 0 ] && [ "$console_running" -gt 0 ]; then
            log_message "Services started successfully"
            return 0
        fi

        log_message "Waiting for services to start... ($elapsed/${timeout}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    log_message "WARNING: Could not verify all services started within ${timeout} seconds"
    log_message "Current running processes:"
    ps aux | grep -E "(mpapi|mpconsole|gov.llnl.mp)" | grep -v grep | tee -a "${BACKUP_LOG}"
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

    if [ ! -f "${MPSERVERBASE}/apps/mpapi.py" ]; then
        log_message "ERROR: mpapi.py missing"
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
                if [ -f "${MPSERVERBASE}/conf/scripts/setup/ServerSetup.py" ]; then
                    log_message "Attempting to restart services..."
                    "${MPSERVERBASE}/conf/scripts/setup/ServerSetup.py" --load All || log_message "WARNING: Could not restart services"
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

log_message "=== MacPatch Server Upgrade Started ==="
log_message "Backup directory: ${MPBASEBACK}"
log_message "Git branch: ${GITBRANCH}"

# Create backup directory structure
if ! mkdir -p "${MPBASEBACK}/Server/etc"; then
    log_message "ERROR: Failed to create backup directory structure"
    exit 1
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
log_message "Shutting down MacPatch services..."
if ! "${MPSERVERBASE}/conf/scripts/setup/ServerSetup.py" --unload All; then
    log_message "ERROR: Failed to shutdown services"
    exit 1
fi

# Verify services actually stopped
if ! verify_services_stopped "${SERVICE_SHUTDOWN_TIMEOUT}"; then
    log_message "ERROR: Services did not stop properly"
    log_message "Attempting forced shutdown..."

    # Try to kill processes manually
    pkill -f mpapi || true
    pkill -f mpconsole || true
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

# Backup py app files
log_message "Backing up application config files..."
if ! validate_path "${MPSERVERBASE}/apps" "dir"; then
    log_message "ERROR: apps directory not found at ${MPSERVERBASE}/apps"
    exit 1
fi

# Use find to handle files with spaces in names
find "${MPSERVERBASE}/apps" -maxdepth 1 -name "*.cfg" -type f -exec cp -p {} "${MPBASEBACK}/Server/apps/" \; || {
    log_message "ERROR: Failed to backup app config files"
    exit 1
}

# Handle content files
if $MOVECONTENT; then
    log_message "Processing content files..."
    local content_path="${MPBASE}/Content"

    if [[ -L "$content_path" && -d "$content_path" ]]; then
        USECONTENTLNK=true
        # Use the resolve_symlink function for cross-platform compatibility
        MPCONTENTLNK=$(resolve_symlink "$content_path")
        log_message "Content is symlinked to: ${MPCONTENTLNK}"

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
    else
        log_message "Moving content to backup location..."
        local server_content="${MPSERVERBASE}/Content"

        if ! validate_path "$server_content" "dir"; then
            log_message "ERROR: Content directory not found at ${server_content}"
            exit 1
        fi

        if ! mv "$server_content" "${MPBASEBACK}/Content"; then
            log_message "ERROR: Failed to move content directory"
            exit 1
        fi
    fi
fi

# Verify backup before proceeding
if ! verify_backup "${MPBASEBACK}"; then
    log_message "ERROR: Backup verification failed. Aborting upgrade."
    exit 1
fi

# Archive current installation
log_message "Archiving current MacPatch installation..."
local macpatch_src="/opt/MacPatch"
local macpatch_backup="/opt/MacPatch_back"

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

# ----------------------------------------------------------------------------
# Download and build
# ----------------------------------------------------------------------------

log_message "Cloning MacPatch repository (branch: ${GITBRANCH})..."
local clone_dest="/opt/MacPatch"
local build_script="${clone_dest}/scripts/MPBuildServer.sh"

# Change to /opt directory
if ! cd /opt; then
    log_message "ERROR: Cannot change to /opt directory"
    exit 1
fi

# Remove any existing clone attempt
if [ -d "$clone_dest" ]; then
    log_message "WARNING: ${clone_dest} already exists, removing..."
    if ! rm -rf "$clone_dest"; then
        log_message "ERROR: Failed to remove existing directory"
        exit 1
    fi
fi

# Clone repository
if ! git clone https://github.com/LLNL/MacPatch.git -b "$GITBRANCH" "$clone_dest"; then
    log_message "ERROR: Failed to clone repository"
    exit 1
fi

# Verify clone succeeded
if ! validate_path "$clone_dest" "dir"; then
    log_message "ERROR: Clone completed but directory not found at ${clone_dest}"
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

# Restore py app config files
log_message "Restoring application configurations..."
if ! mv "${MPSERVERBASE}/apps/conf_console.cfg" "${MPSERVERBASE}/apps/conf_console.cfg.back"; then
    log_message "WARNING: Failed to backup new conf_console.cfg"
fi
if ! cp "${MPBASEBACK}/Server/apps/conf_console.cfg" "${MPSERVERBASE}/apps/conf_console.cfg"; then
    log_message "ERROR: Failed to restore conf_console.cfg"
    exit 1
fi

if ! mv "${MPSERVERBASE}/apps/config.cfg" "${MPSERVERBASE}/apps/config.cfg.back"; then
    log_message "WARNING: Failed to backup new config.cfg"
fi
if ! cp "${MPBASEBACK}/Server/apps/config.cfg" "${MPSERVERBASE}/apps/config.cfg"; then
    log_message "ERROR: Failed to restore config.cfg"
    exit 1
fi

# Restore content files
if $MOVECONTENT; then
    log_message "Restoring content..."
    local server_content="${MPSERVERBASE}/Content"

    if $USECONTENTLNK; then
        # Remove new content directory if it exists
        if [ -e "$server_content" ]; then
            rm -rf "$server_content"
        fi

        # Read symlink target from backup
        local symlink_file="${MPBASEBACK}/content_symlink.txt"
        if ! validate_path "$symlink_file" "file"; then
            log_message "ERROR: Symlink target file not found"
            exit 1
        fi

        MPCONTENTLNK=$(cat "$symlink_file")
        if [ -z "$MPCONTENTLNK" ]; then
            log_message "ERROR: Symlink target is empty"
            exit 1
        fi

        # Verify symlink target exists
        if ! validate_path "$MPCONTENTLNK" "dir"; then
            log_message "ERROR: Symlink target does not exist: ${MPCONTENTLNK}"
            exit 1
        fi

        # Create symlink
        if ! ln -s "$MPCONTENTLNK" "$server_content"; then
            log_message "ERROR: Failed to restore content symlink"
            exit 1
        fi
        log_message "Content symlink restored to: ${MPCONTENTLNK}"
    else
        # Restore content directories
        for content_dir in clients patches sav sw; do
            log_message "Restoring ${content_dir}..."
            local src_dir="${MPBASEBACK}/Content/Web/${content_dir}"
            local dest_dir="${server_content}/Web/${content_dir}"

            # Verify source exists
            if ! validate_path "$src_dir" "dir"; then
                log_message "WARNING: Source directory not found: ${src_dir}, skipping..."
                continue
            fi

            # Remove destination if exists
            if [ -e "$dest_dir" ]; then
                rm -rf "$dest_dir"
            fi

            # Move directory back
            if ! mv "$src_dir" "$dest_dir"; then
                log_message "ERROR: Failed to restore ${content_dir} directory"
                exit 1
            fi
        done
        log_message "Content directories restored"
    fi
fi

if $MASTERSERVER; then
    log_message "Upgrading database schema (master server)..."

    local apps_dir="${MPSERVERBASE}/apps"
    local venv_dir="${apps_dir}/env"
    local activate_script="${venv_dir}/bin/activate"
    local mpapi_script="${apps_dir}/mpapi.py"
    local config_file="${apps_dir}/config.cfg"

    # Verify Python virtual environment exists
    if ! validate_path "$venv_dir" "dir"; then
        log_message "ERROR: Python virtual environment not found at ${venv_dir}"
        exit 1
    fi

    if ! validate_path "$activate_script" "file"; then
        log_message "ERROR: Python virtual environment activate script not found at ${activate_script}"
        exit 1
    fi

    # Change to apps directory
    if ! cd "$apps_dir"; then
        log_message "ERROR: Cannot change to apps directory: ${apps_dir}"
        exit 1
    fi

    # Activate virtual environment
    # shellcheck disable=SC1090
    if ! source "$activate_script"; then
        log_message "ERROR: Failed to activate Python virtual environment"
        exit 1
    fi

    # Verify mpapi.py exists and is executable
    if ! validate_path "$mpapi_script" "file"; then
        log_message "ERROR: mpapi.py not found at ${mpapi_script}"
        deactivate
        exit 1
    fi

    if [ ! -x "$mpapi_script" ]; then
        log_message "Making mpapi.py executable..."
        if ! chmod +x "$mpapi_script"; then
            log_message "ERROR: Failed to make mpapi.py executable"
            deactivate
            exit 1
        fi
    fi

    # Backup database config before upgrade
    log_message "Backing up database configuration..."
    if [ -f "$config_file" ]; then
        local db_backup="${MPBASEBACK}/Server/apps/config.cfg.pre-dbupgrade"
        if ! cp "$config_file" "$db_backup"; then
            log_message "WARNING: Failed to backup database config"
        fi
    fi

    # Run database upgrade
    log_message "Running database migration..."
    if ! "$mpapi_script" db upgrade head; then
        log_message "ERROR: Database upgrade failed"
        log_message "Database may be in inconsistent state. Check logs carefully."
        deactivate
        exit 1
    fi

    deactivate
    log_message "Database schema upgraded successfully"
fi

# Start Services
log_message "Starting MacPatch services..."
if ! "${MPSERVERBASE}/conf/scripts/setup/ServerSetup.py" --load All; then
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
