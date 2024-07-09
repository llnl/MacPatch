#!/bin/bash
#
# ----------------------------------------------------------------------------
# Script: MPServerGitPull.sh
# Version: 1.0
#
# Description:
# Script will copy MacPatch apps and script in to production location
# after a git pull has been done.
#
# History:
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

APPSDIR=false
CONFDIR=false
USELINUX=false
USEMACOS=false
OWNERGRP="79:70"

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
	OWNERGRP="www-data:www-data"
fi

# Script Variables -----------------------------------------------------------

MPBASE="/opt/MacPatch"
MPSERVERBASE="/opt/MacPatch/Server"

# Script Input Args ----------------------------------------------------------

usage() { echo "Usage: $0 -a (update apps dir) -c (update conf dir)" 1>&2; exit 1; }

while getopts "ach" opt; do
	case $opt in
		a)
			APPSDIR=true
			;;
		c)
			CONFDIR=true
			;;
		h)
			echo
			usage
			exit 1
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

if $APPSDIR; then
	# Copy app config files
	mkdir -p /tmp/MPSrvGitPull/Server/apps
	mkdir -p /tmp/MPSrvGitPull/Server/apps/api/mpapi
	mkdir -p /tmp/MPSrvGitPull/Server/apps/console/mpconsole

	cp $MPSERVERBASE/apps/.mpglobal /tmp/MPSrvGitPull/Server/apps/.mpglobal
	cp $MPSERVERBASE/apps/.mpapi /tmp/MPSrvGitPull/Server/apps/.mpapi
	cp $MPSERVERBASE/apps/.mpconsole /tmp/MPSrvGitPull/Server/apps/.mpconsole
	cp $MPSERVERBASE/apps/api/gunicorn_config.py /tmp/MPSrvGitPull/Server/apps/api/gunicorn_config.py
	cp $MPSERVERBASE/apps/api/mpapi/config.py /tmp/MPSrvGitPull/Server/apps/api/mpapi/config.py
	cp $MPSERVERBASE/apps/console/gunicorn_config.py /tmp/MPSrvGitPull/Server/apps/console/gunicorn_config.py
	cp $MPSERVERBASE/apps/console/mpconsole/config.py /tmp/MPSrvGitPull/Server/apps/console/mpconsole/config.py

	mv $MPSERVERBASE/apps $MPSERVERBASE/apps.back
fi

if $CONFDIR; then
	mv $MPSERVERBASE/conf/scripts $MPSERVERBASE/conf/scripts.back
fi

# ----------------------------------------------------------------------------
# Download and build
# ----------------------------------------------------------------------------

# Clone new sw
cd /opt/MacPatch
git pull

# ------------------
# Clean up structure place holders
# ------------------
find ${MPSERVERBASE} -name ".mpRM" -print | xargs -I{} rm -rf {}

# ----------------------------------------------------------------------------
# Restore
# ----------------------------------------------------------------------------

if $APPSDIR; then
	cp -r $MPBASE/Source/Server/apps $MPSERVERBASE/apps
	cp /tmp/MPSrvGitPull/Server/apps/.mpglobal $MPSERVERBASE/apps/.mpglobal
	cp /tmp/MPSrvGitPull/Server/apps/.mpapi $MPSERVERBASE/apps/.mpapi
	cp /tmp/MPSrvGitPull/Server/apps/.mpconsole $MPSERVERBASE/apps/.mpconsole

	cp /tmp/MPSrvGitPull/Server/apps/api/gunicorn_config.py $MPSERVERBASE/apps/api/gunicorn_config.py
	cp /tmp/MPSrvGitPull/Server/apps/api/mpapi/config.py $MPSERVERBASE/apps/api/mpapi/config.py
	cp /tmp/MPSrvGitPull/Server/apps/console/gunicorn_config.py $MPSERVERBASE/apps/console/gunicorn_config.py
	cp /tmp/MPSrvGitPull/Server/apps/console/mpconsole/config.py $MPSERVERBASE/apps/console/mpconsole/config.py

	if [ -d '/opt/MacPatch/Server/apps.back/console/mpconsole/static/yarn_components' ]; then
		cp -r /opt/MacPatch/Server/apps.back/console/mpconsole/static/yarn_components /opt/MacPatch/Server/apps/console/mpconsole/static/yarn_components
	fi

	# Set Owner
	find /opt/MacPatch/Server/apps -type d -exec chmod 775 {} +
	find /opt/MacPatch/Server/apps -type f -exec chmod 664 {} +
	chown -R $OWNERGRP /opt/MacPatch/Server/apps
fi

if $CONFDIR; then
	cp -r $MPBASE/Source/Server/conf/scripts $MPSERVERBASE/conf/scripts
	find /opt/MacPatch/Server/conf/scripts -type d -exec chmod 775 {} +
fi

# Start Services
$MPSERVERBASE/conf/scripts/setup/ServerSetup.py --load All
