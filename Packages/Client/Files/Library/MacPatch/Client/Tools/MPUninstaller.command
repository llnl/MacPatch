#!/bin/bash

set -u  # Exit on undefined variables

Version="2.2.1"
mpBaseDir="/Library/MacPatch"
mpClientDir="${mpBaseDir}/Client"
mpUpdateDir="${mpBaseDir}/Updater"
FullScriptName=$(basename "$0")
ShowQuitMessage=TRUE
RunScriptAsStandAlone=FALSE
PublicVersion=FALSE

# Get current console user (modern method)
curUser=$(stat -f%Su /dev/console 2>/dev/null)

# Get system version
sysVersion=$(uname -r)
sysMajorVersion=${sysVersion%%.*}
tempMinorVersion=${sysVersion#*.}
sysMinorVersion=${tempMinorVersion%%.*}

ShowVersion()
{
   # Usage:     ShowVersion
   # Summary:   Displays the name and version of script.
   echo "********* ${FullScriptName} ${Version} *********"
}

ExitScript()
{
   # Usage:     ExitScript [$1]
   # Argument:  $1 = The value to pass when calling the exit command.
   # Summary:   Exits the script with the provided exit code.
   local exit_code="${1:-0}"

   if [[ "${ShowQuitMessage}" == "TRUE" && "${RunScriptAsStandAlone}" == "TRUE" ]]; then
      echo
      echo "NOTE: If you double-clicked this script, quit Terminal application now."
      echo
   fi

   # Validate exit code is numeric
   if [[ ! "${exit_code}" =~ ^[0-9]+$ ]]; then
      exit 255
   fi

   exit "${exit_code}"
}

GetAdminPassword()
{
   # Usage:     GetAdminPassword [$1]
   # Argument:  $1 - If TRUE, always prompt for password.
   # Summary:   Gets an admin user password so future sudo commands
   #            can run without prompting. Exits if user is not admin.

   # If root user, no need to prompt for password
   [[ "$(whoami)" == "root" ]] && return 0

   echo

   # If prompt for password
   if [[ "${1:-}" == "TRUE" || "${1:-}" == "true" ]]; then
      ShowVersion
      echo
      sudo -k   # Make sudo require a password the next time it is run
      echo "You must be an admin user to run this script."
   fi

   # A dummy sudo command to get password
   if ! sudo -p "Please enter your admin password: " date >/dev/null 2>&1; then
      echo "You entered an invalid password or you are not an admin user. Script aborted."
      ExitScript 1
   fi
}

exists_and_delete()
{
   # Safely delete a file or directory
   local path="$1"

   if [[ -f "${path}" ]]; then
      echo "Removing file: ${path}"
      rm -f "${path}" 2>/dev/null || echo "Warning: Failed to remove ${path}"
   elif [[ -d "${path}" ]]; then
      echo "Removing directory: ${path}"
      rm -rf "${path}" 2>/dev/null || echo "Warning: Failed to remove ${path}"
   fi
}

find_and_delete()
{
   # Safely find and delete files matching a pattern
   local search_path="$1"
   local pattern="$2"

   if [[ ! -d "${search_path}" ]]; then
      return 0
   fi

   echo "Finding and removing files matching '${pattern}' in ${search_path}"
   find "${search_path}" -name "${pattern}" -type f -delete 2>/dev/null
}

stop_launchditem()
{
   # Stop and unload a LaunchDaemon/LaunchAgent
   local label="$1"
   local plist_path="$2"

   echo "Stopping ${label}"

   # Try bootout for modern macOS (10.11+)
   if [[ ${sysMajorVersion} -ge 15 ]]; then
      if [[ "${plist_path}" =~ LaunchDaemons ]]; then
         launchctl bootout system/"${label}" 2>/dev/null || true
      else
         launchctl bootout gui/$(id -u "${curUser}")/"${label}" 2>/dev/null || true
      fi
   fi

   # Fallback to remove/unload for compatibility
   launchctl remove "${label}" 2>/dev/null || true
   [[ -f "${plist_path}" ]] && launchctl unload -w -F "${plist_path}" 2>/dev/null || true

   sleep 1
}

# *** Beginning of Commands to Execute ***

# Determine if running as standalone (double-clicked) or from command line
if [[ $# -eq 0 ]]; then
   RunScriptAsStandAlone=TRUE
   clear
fi

# Re-run as root if necessary
if [[ "$(whoami)" != "root" ]]; then
   if ${PublicVersion}; then
      GetAdminPassword TRUE
   else
      ShowVersion
      echo
   fi

   # Run this script again as root
   sudo -p "Please enter your admin password: " "$0" "$@"
   ErrorFromSudoCommand=$?

   # If unable to authenticate
   if [[ ${ErrorFromSudoCommand} -eq 1 ]]; then
      echo "You entered an invalid password or you are not an admin user. Script aborted."
      ExitScript 1
   fi

   if ${PublicVersion}; then
      sudo -k
   fi

   exit ${ErrorFromSudoCommand}
fi

# Main uninstall logic
if [[ ! -d "${mpBaseDir}" ]]; then
   echo "MacPatch is not installed (${mpBaseDir} not found)."
   ExitScript 0
fi

echo "Beginning MacPatch uninstallation..."
echo

# Stop Running Services
stop_launchditem "gov.llnl.mp.worker" "/Library/LaunchDaemons/gov.llnl.mp.worker.plist"
stop_launchditem "gov.llnl.mp.agent" "/Library/LaunchDaemons/gov.llnl.mp.agent.plist"
stop_launchditem "gov.llnl.mp.agentUpdater" "/Library/LaunchDaemons/gov.llnl.mp.agentUpdater.plist"
stop_launchditem "gov.llnl.mp.planb" "/Library/LaunchDaemons/gov.llnl.mp.planb.plist"
stop_launchditem "gov.llnl.mp.osqueryd" "/Library/LaunchDaemons/gov.llnl.mp.osqueryd.plist"

# If there is a user logged in, stop LaunchAgents
if [[ -n "${curUser}" && "${curUser}" != "root" && "${curUser}" != "_mbsetupuser" ]]; then
   echo "Stopping LaunchAgents for user: ${curUser}"

   if [[ -f '/Library/LaunchAgents/gov.llnl.MPRebootD.plist' ]]; then
      su -l "${curUser}" -c 'launchctl unload /Library/LaunchAgents/gov.llnl.MPRebootD.plist' 2>/dev/null || true
      sleep 1
   fi

   if [[ -f '/Library/LaunchAgents/gov.llnl.mp.status.plist' ]]; then
      su -l "${curUser}" -c 'launchctl unload /Library/LaunchAgents/gov.llnl.mp.status.plist' 2>/dev/null || true
      sleep 1
   fi
fi

# Remove Auth Plugin
if [[ -f "/Library/MacPatch/Client/MPAuthPluginTool" ]]; then
   echo "Removing auth plugin..."
   /Library/MacPatch/Client/MPAuthPluginTool -d 2>/dev/null || true
   # Note: /System paths are SIP-protected and may require special handling
   exists_and_delete "/System/Library/CoreServices/SecurityAgentPlugins/MPAuthPlugin.bundle"
fi

# Remove LaunchAgents plists
echo "Removing LaunchAgents..."
exists_and_delete "/Library/LaunchAgents/gov.llnl.MPRebootD.plist"
exists_and_delete "/Library/LaunchAgents/gov.llnl.mp.status.plist"
exists_and_delete "/Library/LaunchAgents/gov.llnl.MPLoginAgent.plist"

# Remove LaunchDaemon plists
echo "Removing LaunchDaemons..."
exists_and_delete "/Library/LaunchDaemons/gov.llnl.mp.worker.plist"
exists_and_delete "/Library/LaunchDaemons/gov.llnl.mp.agent.plist"
exists_and_delete "/Library/LaunchDaemons/gov.llnl.mp.agentUpdater.plist"

# Remove Config Plist
find_and_delete "/Library/Preferences" "gov.llnl.mpagent.*"

# Delete MacPatch app
echo "Removing MacPatch application..."
exists_and_delete "/Applications/MacPatch.app"

# Delete MacPatch Client Files
echo "Removing MacPatch client files..."
exists_and_delete "${mpClientDir}"

# Delete MacPatch Updater Files
exists_and_delete "${mpUpdateDir}"

# Delete Client Data
echo "Removing MacPatch data..."
exists_and_delete "/Library/Application Support/MPClientStatus"
exists_and_delete "/Library/Application Support/MacPatch/SW_Data"
exists_and_delete "/Library/Application Support/MacPatch"

# Priv Helper Tool
exists_and_delete "/Library/PrivilegedHelperTools/MPLoginAgent.app"

# Remove PlanB
echo "Removing PlanB components..."
exists_and_delete "/usr/local/sbin/planb"
exists_and_delete "/usr/local/bin/mpPlanB"
exists_and_delete "/Library/LaunchDaemons/gov.llnl.mp.planb.plist"

# Remove MP OSQuery
if [[ -f "/Library/LaunchDaemons/gov.llnl.mp.osqueryd.plist" ]]; then
   echo "Removing OSQuery components..."
   exists_and_delete "/private/var/log/osquery"
   exists_and_delete "/private/var/osquery"
   exists_and_delete "/usr/local/bin/osqueryd"
   exists_and_delete "/usr/local/bin/osqueryctl"
   exists_and_delete "/usr/local/bin/osqueryi"
   exists_and_delete "/Library/LaunchDaemons/gov.llnl.mp.osqueryd.plist"
   /usr/sbin/pkgutil --forget com.facebook.osquery 2>/dev/null || true
fi

# Delete Receipts Files
echo "Removing package receipts..."
exists_and_delete "/Library/Receipts/MacPatch.pkg"
exists_and_delete "/Library/Receipts/MacPatchClientInstall.pkg"
exists_and_delete "/Library/Receipts/MacPatchUpdaterInstall.pkg"
exists_and_delete "/Library/Receipts/MPBaseClient.pkg"
exists_and_delete "/Library/Receipts/MPUpdateClient.pkg"

# Forget packages
echo "Forgetting installed packages..."
/usr/sbin/pkgutil --forget gov.llnl.macpatch.base 2>/dev/null || true
/usr/sbin/pkgutil --forget gov.llnl.macpatch.updater 2>/dev/null || true
/usr/sbin/pkgutil --forget gov.llnl.mp.planb 2>/dev/null || true

echo
echo "========================================"
echo "MacPatch has been fully removed!"
echo "Please reboot the system to complete the uninstallation."
echo "========================================"
echo

ExitScript 0
