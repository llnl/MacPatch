#!/bin/sh

Version="2.0.2"
mpBaseDir="/Library/MacPatch"
mpClientDir="${mpBaseDir}/Client"
mpUpdateDir="${mpBaseDir}/Updater"
FullScriptName=`basename "$0"`
ShowQuitMessage=TRUE
curUser=`who | grep console | awk '{print $1}'`
# Get system version
sysVersion=$(uname -r)
sysMajorVersion=${sysVersion%%.*}
tempMinorVersion=${sysVersion#*.}
sysMinorVersion=${tempMinorVersion%%.*}

ShowVersion()
{
   # Usage:     ShowVersion
   # Summary:   Displays the name and version of script.
   #
   echo "********* $FullScriptName $Version *********"
}

ExitScript()
{
   # Usage:     ExitScript [$1]
   # Argument:  $1 = The value to pass when calling the exit command.
   # Summary:   Checks to see if ShowQuitMessage and RunScriptAsStandAlone
   #            variables are set to TRUE. If so, a message is displayed;
   #            otherwise, no message is displayed. The script is then
   #            exited and passes $1 to exit command. If nothing is passed
   #            to $1, then 0 is passed to exit command. If a non-integer
   #            is passed to $1, then 255 is passed to exit command.
   #
   if [ $ShowQuitMessage = TRUE -a $RunScriptAsStandAlone = TRUE ] ; then
      echo
      echo "NOTE: If you double-clicked this script, quit Terminal application now."
      echo
   fi
   [ -z "$1" ] && exit 0
   [ -z "`expr "$1" / 1 2>/dev/null`" ] && exit 255
   exit $1
}

GetAdminPassword()
{
   # Usage:     GetAdminPassword [$1]
   # Argument:  $1 - Prompt for password. If TRUE is passed, a user that
   #                 is not root will always be asked for a password. If
   #                 something other than TRUE is passed or if nothing is
   #                 passed, then a user that is not root will only be
   #                 prompted for a password if authentication has lapsed.
   # Summary:   Gets an admin user password from the user so that
   #            future sudo commands can be run without a password
   #            prompt. The script is exited with a value of 1 if
   #            the user enters an invalid password or if the user
   #            is not an admin user. If the user is the root user,
   #            then there is no prompt for a password (there is
   #            no need for a password when user is root).
   #            NOTE: Make sure ExitScript function is in the script.
   #
   # If root user, no need to prompt for password
   [ "`whoami`" = "root" ] && return 0
   echo
   # If prompt for password
   if [ "$1" = "TRUE" -o "$1" = "true" ] ; then
      ShowVersion
      echo
      sudo -k   # Make sudo require a password the next time it is run
      echo "You must be an admin user to run this script."
   fi
   # A dummy sudo command to get password
   sudo -p "Please enter your admin password: " date 2>/dev/null 1>&2
   if [ ! $? = 0 ] ; then       # If failed to get password, alert user and exit script
      echo "You entered an invalid password or you are not an admin user. Script aborted."
      ExitScript 1
   fi
}

existsAndDelete () 
{
	if [ -f "$1" ]; then
		echo "Removing (rm -f) file $1"
		rm -f "$1" 2>/dev/null
	elif [ -d "$1" ]; then
		echo "Removing (rm -rf) directory $1"
		rm -rf "$1" 2>/dev/null
	fi
}

findAndDelete ()
{
	find $1 -name $2 -exec rm {} \;
}

stopLaunchDItem () 
{
	# Stop Running Services
	echo "Stopping $1"
	/bin/launchctl remove "$1" 2>/dev/null
	/bin/launchctl unload -w -F "$2" 2>/dev/null
	sleep 1
}

# *** Beginning of Commands to Execute ***

if [ $# -eq 0 ] ; then   # If no arguments were passed to script
   # Run script as if it was double-clicked in Finder so that
   # screen will be cleared and quit message will be displayed.
   RunScriptAsStandAlone=TRUE
else
   # Run script in command line mode so that
   # screen won't be cleared and quit message won't be displayed.
   RunScriptAsStandAlone=FALSE
fi
if $RunScriptAsStandAlone ; then
   clear
fi

if [ "`whoami`" != "root" ] ; then   # If not root user,
   if $PublicVersion ; then
      GetAdminPassword TRUE   #    Prompt user for admin password
   else
      ShowVersion
      echo
   fi
   # Run this script again as root
   sudo -p "Please enter your admin password: " "$0" "$@"
   ErrorFromSudoCommand=$?
   # If unable to authenticate
   if [ $ErrorFromSudoCommand -eq 1 ] ; then
      echo "You entered an invalid password or you are not an admin user. Script aborted."
      ExitScript 1
   fi
   if $PublicVersion ; then
      sudo -k   # Make sudo require a password the next time it is run
   fi
   exit $ErrorFromSudoCommand #    Exit so script doesn't run again
fi



# MacPatch Deployment Dir
if [ -d $mpBaseDir ]; then

	# Stop Running Services
	stopLaunchDItem "gov.llnl.mp.worker" "/Library/LaunchDaemons/gov.llnl.mp.worker.plist"
	stopLaunchDItem "gov.llnl.mp.agent" "/Library/LaunchDaemons/gov.llnl.mp.agent.plist"
	stopLaunchDItem "gov.llnl.mp.agentUpdater" "/Library/LaunchDaemons/gov.llnl.mp.agentUpdater.plist"
	
	# If there is a user logged in ...
	if [ ! -z "$curUser" ]; then

		if [ -f '/Library/LaunchAgents/gov.llnl.MPRebootD.plist' ]; then
			su -l $curUser -c 'launchctl unload /Library/LaunchAgents/gov.llnl.MPRebootD.plist'
			sleep 2
		fi

		if [ -f '/Library/LaunchAgents/gov.llnl.mp.status.plist' ]; then
			su -l $curUser -c 'launchctl unload /Library/LaunchAgents/gov.llnl.mp.status.plist'
			sleep 2
		fi 
	fi	
	
	# Remove Auth Plugin 
	if [ -f "/Library/MacPatch/Client/MPAuthPluginTool" ]; then
		/Library/MacPatch/Client/MPAuthPluginTool -d
		existsAndDelete "/System/Library/CoreServices/SecurityAgentPlugins/MPAuthPlugin.bundle"
	fi
	
	# Remove LaunchAgents plists
	existsAndDelete "/Library/LaunchAgents/gov.llnl.MPRebootD.plist"
	existsAndDelete "/Library/LaunchAgents/gov.llnl.mp.status.plist"
	existsAndDelete "/Library/LaunchAgents/gov.llnl.MPLoginAgent.plist"
	
	# Remove LaunchDaemon plists
	existsAndDelete "/Library/LaunchDaemons/gov.llnl.mp.worker.plist"
	existsAndDelete "/Library/LaunchDaemons/gov.llnl.mp.agent.plist"
	existsAndDelete "/Library/LaunchDaemons/gov.llnl.mp.agentUpdater.plist"
	
	# Remove Config Plist
	findAndDelete "/Library/Preferences" "gov.llnl.mpagent.*"
	
	# Delete MacPatch Client Files
	existsAndDelete "$mpClientDir"
	
	# Delete MacPatch Updater Files
	existsAndDelete "$mpUpdateDir"
	
	# Delete Client Data
	existsAndDelete "/Library/Application Support/MPClientStatus"
	existsAndDelete "/Library/Application Support/MacPatch/SW_Data"

	# Priv Helper Tool
	existsAndDelete "/Library/PrivilegedHelperTools/MPLoginAgent.app"	
	
	# Delete Receipts Files
	echo "Delete Receipts"
	existsAndDelete "/Library/Receipts/MacPatch.pkg"
	existsAndDelete "/Library/Receipts/MacPatchClientInstall.pkg"
	existsAndDelete "/Library/Receipts/MacPatchUpdaterInstall.pkg"

	existsAndDelete "/Library/Receipts/MPBaseClient.pkg"
	existsAndDelete "/Library/Receipts/MPUpdateClient.pkg"
	
	# Drop Packages
	/usr/sbin/pkgutil --forget gov.llnl.macpatch.base 2>/dev/null
	/usr/sbin/pkgutil --forget gov.llnl.macpatch.updater 2>/dev/null
	
	echo "MacPatch Software has been fully removed!"
	echo "Please reboot the system..."
fi
