#!/bin/bash
#
# ----------------------------------------------------------------------------
# Script: MPServerUpgrader.sh
# Version: 1.1
#
# Description:
# Upgrade script will upgrade a current install of the MacPatch server
#
# History:
#
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# How to use:
#
# sudo MPBuildServer.sh, will compile MacPatch server software
#
# sudo MPBuildServer.sh -p, will compile MacPatch server
# software, and create MacPatch server pkg installer. Only for
# Mac OS X.
#
# Linux requires MPBuildServer.sh, then run the buildLinuxPKG.sh
# locates in /Library/MacPatch/tmp/MacPatch/MacPatch PKG/Linux
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

MPBASE="/opt/MacPatch"
MPCONTENT="${MPBASE}/Content"
MPCONTENTLNK="${MPCONTENT}"
MPSRVCONTENT="${MPBASE}/Content/Web"
USECONTENTLNK=false
MPSERVERBASE="/opt/MacPatch/Server"
BUILDROOT="${MPBASE}/.build/server"

MPBASEBACK="/tmp/MPUSrvUpgrade"
GITBRANCH="master"
MOVECONTENT=true
MASTERSERVER=false
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

# Notice text -----------------------------------------------------------

clear
echo
echo "NOTICE..."
echo "This script is EXPERIMENTAL, please proceed with caution."
echo
echo "Before continuing with this script, an actual backup is recommended"
echo "in case anything should go wrong."
echo
echo "This script will backup all config files and nessasary content."
echo "It will then clone the MacPatch master branch and install the"
echo "new software. Once the install is completed. This script will"
echo "put back all of the configuration files and content."
echo
echo

read -p "Would you like to continue (Y/N)? [N]: " UPOK
UPOK=${UPOK:-N}
if [ "$UPOK" == "Y" ] || [ "$UPOK" == "y" ] ; then
	echo
else
	exit 0
fi

# ----------------------------------------------------------------------------
# Backup
# ----------------------------------------------------------------------------
# 1) Shutdown all services
$MPSERVERBASE/conf/scripts/setup/ServerSetup.py --unload All

# etc files
mkdir -p /tmp/MPUSrvUpgrade/Server/etc
cp -r $MPSERVERBASE/etc /tmp/MPUSrvUpgrade/Server/

# py app files
mkdir -p /tmp/MPUSrvUpgrade/Server/apps
cp $MPSERVERBASE/apps/*.cfg /tmp/MPUSrvUpgrade/Server/apps

# Move the content files to tmp location
if $MOVECONTENT; then
    if [[ -L "$MPBASE/Content" && -d "$MPBASE/Content" ]]; then
        #echo "$file is a symlink to a directory"
        USECONTENTLNK=true
        MPCONTENTLNK=`readlink -f ${MPBASE}/Content`
        unlink $MPBASE/Content
    else
        mv $MPSERVERBASE/Content /tmp/MPUSrvUpgrade/Content
    fi
fi

# Move Base Bir
if [ -d /opt/MacPatch_back ]; then
	rm -rf /opt/MacPatch_back
fi

mv /opt/MacPatch /opt/MacPatch_back

# ----------------------------------------------------------------------------
# Download and build
# ----------------------------------------------------------------------------

# Clone new sw
cd /opt
git clone https://github.com/LLNL/MacPatch.git -b $GITBRANCH

# Build new sw
/opt/MacPatch/scripts/MPBuildServer.sh

# ----------------------------------------------------------------------------
# Restore
# ----------------------------------------------------------------------------

# etc
mv $MPSERVERBASE/etc $MPSERVERBASE/etc_orig
mv /tmp/MPUSrvUpgrade/Server/etc $MPSERVERBASE/

# py app
mv $MPSERVERBASE/apps/conf_console.cfg $MPSERVERBASE/apps/conf_console.cfg.back
cp /tmp/MPUSrvUpgrade/Server/apps/conf_console.cfg $MPSERVERBASE/apps/conf_console.cfg

mv $MPSERVERBASE/apps/config.cfg $MPSERVERBASE/apps/config.cfg.back
cp /tmp/MPUSrvUpgrade/Server/apps/config.cfg $MPSERVERBASE/apps/config.cfg

# Content
if $MOVECONTENT; then
    if $USECONTENTLNK; then
        rm -rf $MPSERVERBASE/Content
        ln -s "${MPCONTENTLNK}" "${MPSERVERBASE}/Content"
    else
    	rm -rf $MPSERVERBASE/Content/Web/clients
    	mv /tmp/MPUSrvUpgrade/Content/Web/clients $MPSERVERBASE/Content/Web/clients

    	rm -rf $MPSERVERBASE/Content/Web/patches
    	mv /tmp/MPUSrvUpgrade/Content/Web/patches $MPSERVERBASE/Content/Web/patches

    	rm -rf $MPSERVERBASE/Content/Web/sav
    	mv /tmp/MPUSrvUpgrade/Content/Web/sav $MPSERVERBASE/Content/Web/sav

    	rm -rf $MPSERVERBASE/Content/Web/sw
    	mv /tmp/MPUSrvUpgrade/Content/Web/sw $MPSERVERBASE/Content/Web/sw
    fi 
fi

if $MASTERSERVER; then
	# Update Schema, only on master server
	cd $MPSERVERBASE/apps
	source env/bin/activate
	./mpapi.py db upgrade head
	deactivate
fi

# Start Services
$MPSERVERBASE/conf/scripts/setup/ServerSetup.py --load All
