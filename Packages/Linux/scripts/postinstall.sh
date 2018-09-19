#!/bin/bash
#
# -------------------------------------------------------------
# Script: postinstall.sh
# Version: 1.0.0
#
# Description:
# MacPatch Server post install script for debian/ubuntu package
#
# History:
# 1.0.0:	Initial Script
#	
# -------------------------------------------------------------
MPBASE="/Library/MacPatch"
MPSERVERBASE="/Library/MacPatch/Server"
SRC_DIR="${MPSERVERBASE}/conf/src"

if [ "`whoami`" != "root" ] ; then   # If not root user,
   # Run this script again as root
   echo
   echo "You must be an admin user to run this script."
   echo "Please re-run the script using sudo."
   echo
   exit 1;
fi

# ------------------------------------
# Install Python Packages
# ------------------------------------
if [ -f "/usr/bin/easy_install" ]; then
	${MPSERVERBASE}/conf/scripts/InstallPyMods.sh
else
	echo
	echo "easy_install was not found, python mods will not be installed."
	echo
	exit 1;
fi

# ------------------------------------------------------------
# Generate self signed certificates
# ------------------------------------------------------------
clear
echo
echo "Creating self signed SSL certificate"
echo
if [ ! -d "/Library/MacPatch/Server/conf/apacheCerts" ]; then
	mkdir -p /Library/MacPatch/Server/conf/apacheCerts
else
	# Remove any default certs from file based install
	find "${MPSERVERBASE}/conf/apacheCerts" -name "server.*" -print | xargs -I{} rm -rf {}
fi

USER="MacPatch"
EMAIL="admin@localhost"
ORG="MacPatch"
DOMAIN=`hostname`
COUNTRY="NO"
STATE="State"
LOCATION="Country"

cd /Library/MacPatch/Server/conf/apacheCerts
OPTS=(/C="$COUNTRY"/ST="$STATE"/L="$LOCATION"/O="$ORG"/OU="$USER"/CN="$DOMAIN"/emailAddress="$EMAIL")
COMMAND=(openssl req -new -sha256 -x509 -nodes -days 999 -subj "${OPTS[@]}" -newkey rsa:2048 -keyout server.key -out server.crt)

"${COMMAND[@]}"
if (( $? )) ; then
    echo -e "ERROR: Something went wrong!"
    exit 1
else
	echo "Done!"
	echo
	echo "NOTE: It's strongly recommended that an actual signed certificate be installed"
	echo "if running in a production environment."
	echo
fi

# ------------------
# Set Permissions
# ------------------
${MPSERVERBASE}/conf/scripts/Permissions.sh

