#!/bin/bash
#
# ----------------------------------------------------------------------------
# Script: MPBuildReposadoServer.sh
# Version: 1.0.0
#
# Description:
# This is a very simple script to demonstrate how to automate
# the build process of the MacPatch Server.
#
# Info:
#
# History:
#
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# How to use:
#
# sudo MPBuildReposadoServer.sh, will compile MacPatch Reposado server software
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

# Server expectations --------------------------------------------------------

echo
echo "* Server Expectations"
echo "-----------------------------------------------------------------------"
echo
echo "The MacPatch Reposado server is intended to be installed as a"
echo "standalone server. While Reposado can be installed side by side with"
echo "a MacPatch master or distribution server. The added disk space"
echo "requirements and server resources maybe to much."
echo 
echo "This script is intended to install a standalone Reposado server."
echo "If this host is already setup as a master or distribution server"
echo "Please do not run the script as it will damage your current server"
echo "instance on this host."
echo
read -p "Would you like to continue (Y/N)? [Y]: " SERVEROK
XCODEOK=${XCODEOK:-Y}
if [ "$XCODEOK" == "Y" ] || [ "$XCODEOK" == "y" ] ; then
	echo
else
	exit 1
fi

# Script Variables -----------------------------------------------------------

platform='unknown'
unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
   platform='linux'
elif [[ "$unamestr" == 'Darwin' ]]; then
   platform='mac'
fi

USELINUX=false
USERHEL=false
USEUBUNTU=false
USEMACOS=false
MACPROMPTFORXCODE=true
ASUSSERVER="swscan.apple.com"
LOCALHOST=`hostname`
ENABLESSL=false

MPBASE="/opt/MacPatch"
MPSRVCONTENT="${MPBASE}/Content"
MPSERVERBASE="/opt/MacPatch/Server"
BUILDROOT="${MPBASE}/.build/server"
TMP_DIR="${MPBASE}/.build/tmp"
SRC_DIR="${MPSERVERBASE}/conf/src/server"
OWNERGRP="79:70"
CA_CERT="NA"

majorVer="0"
minorVer="0"
buildVer="0"

if [[ $platform == 'linux' ]]; then
	USELINUX=true
	OWNERGRP="www-data:www-data"
	LNXDIST=`python -c "import platform;print(platform.linux_distribution()[0])"`
	if [[ $LNXDIST == *"Red"*  || $LNXDIST == *"Cent"* ]]; then
		USERHEL=true
	else
		USEUBUNTU=true
	fi

	if ( ! $USERHEL && ! $USEUBUNTU ); then
		echo "Not running a supported version of Linux."
		exit 1;
	fi

elif [[ "$unamestr" == 'Darwin' ]]; then
	USEMACOS=true

	systemVersion=`/usr/bin/sw_vers -productVersion`
	majorVer=`echo $systemVersion | cut -d . -f 1,2  | sed 's/\.//g'`
	minorVer=`echo $systemVersion | cut -d . -f 2`
	buildVer=`echo $systemVersion | cut -d . -f 3`
fi

# Script Input Args ----------------------------------------------------------

usage() { echo "Usage: $0 [-p Build Mac PKG]" 1>&2; exit 1; }

while getopts "hc:" opt; do
	case $opt in
		c)
			CA_CERT=${OPTARG}
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

# ----------------------------------------------------------------------------
# Requirements
# ----------------------------------------------------------------------------
clear

if $USEMACOS; then
	if $MACPROMPTFORXCODE; then
		clear
		echo
		echo "* Xcode requirements"
		echo "-----------------------------------------------------------------------"
		echo
		echo "Server Build Requires Xcode Command line tools to be installed"
		echo "and the license agreement accepted. If you have not done this,"
		echo "parts of the install will fail."
		echo
		echo "It is recommended that you run \"sudo xcrun --show-sdk-version\""
		echo "prior to continuing with this script."
		echo
		read -p "Would you like to continue (Y/N)? [Y]: " XCODEOK
		XCODEOK=${XCODEOK:-Y}
		if [ "$XCODEOK" == "Y" ] || [ "$XCODEOK" == "y" ] ; then
			echo
		else
			exit 1
		fi
	fi
fi

# ----------------------------------------------------------------------------
# Make Sure Linux has Right User
# ----------------------------------------------------------------------------

# Check and set os type
if $USELINUX; then
  echo
  echo "* Checking for required user (www-data)."
  echo "-----------------------------------------------------------------------"

  getent passwd www-data > /dev/null 2>&1
  if [ $? -eq 0 ]; then
	echo "www-data user exists"
  else
	  echo "Create user www-data"
	useradd -r -M -s /dev/null -U www-data
  fi
fi

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
clear
echo
echo "* Begin MacPatch Reposado Server build."
echo "-----------------------------------------------------------------------"

# Create Build Root
if [ -d "$BUILDROOT" ]; then
  rm -rf ${BUILDROOT}
else
  mkdir -p ${BUILDROOT}
fi

# Create TMP Dir for builds
if [ -d "$TMP_DIR" ]; then
  rm -rf ${TMP_DIR}
else
  mkdir -p ${TMP_DIR}
fi

# ------------------
# Global Functions
# ------------------
function mkdirP {
  #
  # Function for creating directory and echo it
  #
  if [ ! -n "$1" ]; then
	echo "Enter a directory name"
  elif [ -d $1 ]; then
	echo "$1 already exists"
  else
	echo " - Creating directory $1"
	mkdir -p $1
  fi
}

function rmF {
  #
  # Function for remove files and dirs and echos
  #
  if [ ! -n "$1" ]; then
	echo "Enter a path"
  elif [ -d $1 ]; then
	echo " - Removing $1"
	rm -rf $1
  elif [ -f $1 ]; then
	echo " - Removing $1"
	rm -rf $1
  fi
}

function command_exists () {
	type "$1" &> /dev/null ;
}

function ver {
	printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}

# ------------------
# Create Skeleton Dir Structure
# ------------------
echo
echo "* Create MacPatch server directory structure."
echo "-----------------------------------------------------------------------"
mkdirP ${MPBASE}
mkdirP ${MPSRVCONTENT}/Reposado
mkdirP ${MPSRVCONTENT}/Reposado/html
mkdirP ${MPSRVCONTENT}/Reposado/metadata
mkdirP ${MPSERVERBASE}/Reposado
mkdirP ${MPSERVERBASE}/lib
mkdirP ${MPSERVERBASE}/logs

# ------------------
# Copy compiled files
# ------------------
if $USEMACOS; then
	echo
	echo "* Uncompress source files needed for build"
	echo "-----------------------------------------------------------------------"

	PCRE_SW=`find "${SRC_DIR}" -name "pcre-"* -type f -exec basename {} \; | head -n 1`
	OSSL_SW=`find "${SRC_DIR}" -name "openssl-"* -type f -exec basename {} \; | head -n 1`

	# PCRE
	echo " - Uncompress ${PCRE_SW}"
	mkdir -p ${TMP_DIR}/pcre
	tar xfz ${SRC_DIR}/${PCRE_SW} --strip 1 -C ${TMP_DIR}/pcre

	# OpenSSL
	echo " - Uncompress ${OSSL_SW}"
	mkdir -p ${TMP_DIR}/openssl
	tar xfz ${SRC_DIR}/${OSSL_SW} --strip 1 -C ${TMP_DIR}/openssl
fi

# ------------------
# Install required packages
# ------------------
if $USELINUX; then
	echo
	echo "* Install required linux packages"
	echo "-----------------------------------------------------------------------"
	if $USERHEL; then
		# Check if needed packges are installed or install
		pkgs=("gcc" "gcc-c++" "zlib-devel" "pcre-devel" "openssl-devel" "epel-release")
		for i in "${pkgs[@]}"
		do
			p=`rpm -qa --qf '%{NAME}\n' | grep -e ${i}$ | head -1`
			if [ -z $p ]; then
				echo " - Install $i"
				yum install -y -q -e 1 ${i}
			fi
		done
	elif $USEUBUNTU; then
		#statements
		pkgs=("build-essential" "zlib1g-dev" "libpcre3-dev" "libssl-dev")
		for i in "${pkgs[@]}"
		do
			p=`dpkg -l | grep '^ii' | grep ${i} | head -n 1 | awk '{print $2}' | grep ^${i}`
			if [ -z $p ]; then
				echo
				echo "Install $i"
				echo
				apt-get install ${i} -y
			fi
		done
	fi
fi

# ------------------
# Build NGINX
# ------------------
echo
echo "* Build and configure NGINX"
echo "-----------------------------------------------------------------------"
echo "See nginx build status in ${MPSERVERBASE}/logs/nginx-build.log"
echo
NGINX_SW=`find "${SRC_DIR}" -name "nginx-"* -type f -exec basename {} \; | head -n 1`

mkdir -p ${BUILDROOT}/nginx
tar xfz ${SRC_DIR}/${NGINX_SW} --strip 1 -C ${BUILDROOT}/nginx
cd ${BUILDROOT}/nginx

if $USELINUX; then
	./configure --prefix=${MPSERVERBASE}/nginx \
	--with-http_ssl_module \
	--with-pcre \
	--user=www-data \
	--group=www-data > ${MPSERVERBASE}/logs/nginx-build.log 2>&1
else
	export KERNEL_BITS=64
	./configure --prefix=${MPSERVERBASE}/nginx \
	--without-http_autoindex_module \
	--without-http_ssi_module \
	--with-http_ssl_module \
	--with-openssl=${TMP_DIR}/openssl \
	--with-pcre=${TMP_DIR}/pcre  > ${MPSERVERBASE}/logs/nginx-build.log 2>&1
fi

make  >> ${MPSERVERBASE}/logs/nginx-build.log 2>&1
make install >> ${MPSERVERBASE}/logs/nginx-build.log 2>&1
 
# Backup and Copy NGINX config files 
mv ${MPSERVERBASE}/nginx/conf/nginx.conf ${MPSERVERBASE}/nginx/conf/nginx.conf.orig
if $USEMACOS; then
	echo " - Copy nginx.conf.mac to ${MPSERVERBASE}/nginx/conf/nginx.conf"
	cp ${MPSERVERBASE}/conf/nginx/nginx.conf.repo.mac ${MPSERVERBASE}/nginx/conf/nginx.conf
	cp ${MPSERVERBASE}/conf/launchd/gov.llnl.mp.nginx.plist /Library/LaunchDaemons/gov.llnl.mp.nginx.plist
	chown root:wheel /Library/LaunchDaemons/gov.llnl.mp.nginx.plist
	chmod 644 /Library/LaunchDaemons/gov.llnl.mp.nginx.plist
else
	echo " - Copy nginx.conf to ${MPSERVERBASE}/nginx/conf/nginx.conf"
	cp ${MPSERVERBASE}/conf/nginx/nginx.conf.repo ${MPSERVERBASE}/nginx/conf/nginx.conf
	cp ${MPSERVERBASE}/conf/systemd/MPNginx3.service /etc/systemd/system/MPNginx3.service
fi
perl -pi -e "s#\[SRVBASE\]#$MPSERVERBASE#g" $MPSERVERBASE/nginx/conf/nginx.conf
perl -pi -e "s#\[SRVCONTENT\]#$MPSRVCONTENT#g" $MPSERVERBASE/nginx/conf/nginx.conf


echo
echo "* Enable SSL support"
echo "-----------------------------------------------------------------------"

echo
echo "Would you like to enable ssl support for Reposado content?"
echo "Note, http support for content will still be enabled."
echo
read -p "Enable ssl support for Reposado content (Y/N)? [Y]: " SUSSSL
SUSSSL=${SUSSSL:-Y}
if [ "$SUSSSL" == "Y" ] || [ "$SUSSSL" == "y" ] ; then
	ENABLESSL=true
fi

if $ENABLESSL; then
	echo " - Copy nginx sites to ${MPSERVERBASE}/nginx/conf/sites"
	cp -r ${MPSERVERBASE}/conf/nginx/sites/reposado_ssl.conf ${MPSERVERBASE}/nginx/conf/sites/reposado_ssl.conf
	FILES=$MPSERVERBASE/nginx/conf/sites/*.conf
	for f in $FILES
	do
		perl -pi -e "s#\[SRVBASE\]#$MPSERVERBASE#g" $f
		perl -pi -e "s#\[SRVCONTENT\]#$MPSRVCONTENT#g" $f
	done
fi

echo
echo "* Clone Reposado software"
echo "-----------------------------------------------------------------------"
cd /opt/MacPatch/Server
git clone https://github.com/wdas/Reposado.git
if [ $? != 0 ]l; then
	unzip /opt/MacPatch/Server/src/server/reposado-master.zip
	mv reposado-master Reposado
fi

# Copy Reposado Plist and set variables
cp ${MPSERVERBASE}/conf/reposado/preferences.plist ${MPSERVERBASE}/Reposado/code/preferences.plist
perl -pi -e "s#\[SRVBASE\]#$MPSERVERBASE#g" ${MPSERVERBASE}/Reposado/code/preferences.plist
perl -pi -e "s#\[SRVCONTENT\]#$MPSRVCONTENT#g" ${MPSERVERBASE}/Reposado/code/preferences.plist
perl -pi -e "s#\[SRVCONTENT\]#$MPSRVCONTENT#g" ${MPSERVERBASE}/Reposado/code/preferences.plist
# ask if you want to change hostanme & default sus-content server
perl -pi -e "s#\[SUS-BASE-SERVER\]#$ASUSSERVER#g" ${MPSERVERBASE}/Reposado/code/preferences.plist
perl -pi -e "s#\[SUS-SERVER-NAME\]#$LOCALHOST#g" ${MPSERVERBASE}/Reposado/code/preferences.plist


# ------------------
# Link & Set Permissions
# ------------------
chown -R $OWNERGRP ${MPSERVERBASE}
chown -R $OWNERGRP ${MPSRVCONTENT}

# Set Permissions
if $USEMACOS; then
	chown -R $OWNERGRP ${MPSERVERBASE}/logs
	chmod 0775 ${MPSERVERBASE}
	chown root:wheel ${MPSERVERBASE}/conf/launchd/*.plist
	chmod 0644 ${MPSERVERBASE}/conf/launchd/*.plist
fi

# ------------------------------------------------------------
# Generate self signed certificates
# ------------------------------------------------------------
if $ENABLESSL; then
	echo
	echo "* Creating self signed SSL certificate"
	echo "-----------------------------------------------------------------------"

	certsDir="${MPSERVERBASE}/etc/ssl"
	if [ ! -d "${certsDir}" ]; then
		mkdirP "${certsDir}"
	fi

	USER="MacPatch"
	EMAIL="admin@localhost"
	ORG="MacPatch"
	DOMAIN="$LOCALHOST"
	COUNTRY="NO"
	STATE="State"
	LOCATION="Country"

	cd ${certsDir}
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
		echo "The NGINX ssl certs and keys live in $certsDir"
		echo
	fi
fi

# ------------------
# Clean up structure place holders
# ------------------
echo
echo "* Clean up Server dirtectory"
echo "-----------------------------------------------------------------------"
find ${MPBASE} -name ".mpRM" -print | xargs -I{} rm -rf {}
rm -rf ${BUILDROOT}

# ------------------
# Set Permissions
# ------------------
clear
echo "Setting Permissions..."
chmod -R 0775 "${MPSERVERBASE}/logs"
chmod -R 0775 "${MPSERVERBASE}/etc"

# ------------------
# Set Auto Sync
# ------------------
if $USEMACOS; then
	echo " - Add launchd job to auto start reposado content sync"
	cp ${MPSERVERBASE}/conf/launchd/gov.llnl.mp.reposado.sync.plist /Library/LaunchDaemons/gov.llnl.mp.reposado.sync.plist
	chown root:wheel /Library/LaunchDaemons/gov.llnl.mp.reposado.sync.plist
	chmod 0644 /Library/LaunchDaemons/gov.llnl.mp.reposado.sync.plist
else
	echo " - Add cron job to auto start reposado content sync"
	crontab -l > /tmp/mycron
	#echo new cron into cron file
	echo "0 */8 * * * /bin/sudo -u www-data /opt/MacPatch/Reposado/code/repo_sync" >> /tmp/mycron
	#install new cron file
	crontab /tmp/mycron
	rm /tmp/mycron
fi


clear
echo
echo "-----------------------------------------------------------------------"
echo " * Reposado Server build has been completed."
echo
echo "   To make the server fully functional, please sync the content then"
echo "   start the NGINX server."	
echo
echo "   Sync Content:"
echo "   % /opt/MacPatch/Server/Reposado/code/repo_sync"
echo 
if $USEMACOS; then
echo "   Start NGINX:"
echo "   sudo launchctl start /Libaray/LaunchDaemons/gov.llnl.mp.nginx.plist"
echo
else
echo "   Start NGINX:"
echo "   sudo systemctl enable MPNginx3.service"
echo "   sudo systemctl start MPNginx3.service"
echo
	if $ENABLESSL; then
		echo
		echo "   NOTE: SSL is enabled"
		echo
		echo "   This server IS using a self-signed certificate."
		echo "   It's strongly recommended that an actual signed certificate be installed"
		echo
		echo "   The NGINX ssl certs and keys live in $certsDir"
		echo
	fi
fi
exit 0;
