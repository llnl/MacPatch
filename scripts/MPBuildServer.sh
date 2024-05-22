#!/bin/bash
#
# ----------------------------------------------------------------------------
# Script: MPBuildServer.sh
# Version: 3.7.1
#
# Description:
# This is a very simple script to demonstrate how to automate
# the build process of the MacPatch Server.
#
# Info:
# Simply modify the GITROOT and BUILDROOT variables
#
# History:
# 1.4:      Remove Jetty Support
#           Added Tomcat 7.0.57
# 1.5:      Added Tomcat 7.0.63
# 1.6:      Variableized the tomcat config
#           removed all Jetty refs
# 1.6.1:    Now using InstallPyMods.sh script to install python modules
# 1.6.2:    Fix cp paths
# 1.6.3:    Updated OpenJDK to 1.8.0
# 1.6.4:    Updated to install Ubuntu packages
# 1.6.5:    More ubuntu updates
# 2.0.0:    Apache HTTPD removed
#           Single Tomcat Instance, supports webservices and console
# 2.0.1:    Updated java version check
# 2.0.2:    Updated linux package requirements
# 2.0.3:    Added Mac PKG support
# 2.0.4:    Added compile for Mac MPServerAdmin.app
#           Removed create archive (aka zip)
# 2.0.5     Disabled the MPServerAdmin app build, having issue
#           with the launch services.
# 3.0.0     Rewritten for new Python Env
# 3.1.0     Updates to remove tomcat and use new console
# 3.1.1     All of MP now uses a virtualenv
# 3.2.0     Replaced bower with yarn for javascript package management
# 3.3.0     Add python 3 support
# 3.4.0     Added a node version check for yarn packages
# 3.5.0     All python now ref as python3
#           Changed Linux dist detection to /etc/os-release
# 3.6.0     M2Crypto has been updated to install without special flags
# 3.6.1     Updated Nodejs install for yarn
# 3.7.0     Update for MacOS and tweaks to install options
#           Check for Python 3 version requirement.
# 3.7.1     Added IPv6 to nginx build
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
MACPROMPTFORBREW=true
USEOLDPY=false

MPBASE="/opt/MacPatch"
MPSRVCONTENT="${MPBASE}/Content/Web"
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

    distName=`cat /etc/os-release | grep "NAME=" | head -n1`
    if [[ $distName == *"Red"*  || $distName == *"Cent"* ]]; then
        USERHEL=true
    elif [[ $LNXDIST == "Ubuntu" ]]; then
        USEUBUNTU=true
    else
        echo "Not running a supported version of Linux."
        exit 1
    fi

    USELINUX=true
    OWNERGRP="www-data:www-data"

elif [[ "$unamestr" == 'Darwin' ]]; then
    USEMACOS=true

    systemVersion=`/usr/bin/sw_vers -productVersion`
    majorVer=`echo $systemVersion | cut -d . -f 1,2  | sed 's/\.//g'`
    minorVer=`echo $systemVersion | cut -d . -f 2`
    buildVer=`echo $systemVersion | cut -d . -f 3`

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

function version {
    printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}

function versionMinor {
    major=`echo $1 | cut -d. -f1`
    minor=`echo $1 | cut -d. -f2`
    _newVer="$major.$minor"
    printf "%03d%03d%03d%03d" $(echo "$_newVer" | tr '.' ' ')
}

# Script Input Args ----------------------------------------------------------

usage() { echo "Usage: $0" 1>&2; exit 1; }

while getopts "h" opt; do
    case $opt in
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

    if $MACPROMPTFORBREW; then
        echo
        echo "* Brew requirements"
        echo "-----------------------------------------------------------------------"
        echo
        echo "Server Build Requires Brew to be installed."
        echo
        echo "To install brew go to https://brew.sh and follow the install"
        echo "directions."
        echo
        echo "This install requires \"Yarn\", \"OpenSSL\", \"SWIG\" and \"GPM\" and \"Python 3.11\" to be installed"
        echo "using brew. It's recommended that you install these two"
        echo "applications before continuing."
        echo
        echo "Exapmple: brew install yarn openssl swig gpm python3.12"
        echo
        read -p "Would you like to continue (Y/N)? [Y]: " BREWOK
        BREWOK=${BREWOK:-Y}
        if [ "$BREWOK" == "Y" ] || [ "$BREWOK" == "y" ] ; then
            echo
        else
            exit 1
        fi
    fi
fi

# ----------------------------------------------------------------------------
# Check Python Version
# ----------------------------------------------------------------------------

pyFound=false
pyMin="NA"
pyMax="NA"
pyApp="NA"
pyLst=$(ls /usr/bin/python* & ls /usr/local/bin/python*)
for f in $pyLst; do
    pyver=$(echo "`$f --version | awk '{print \$2}'`")
    if ! [[ $pyver =~ ^[0-9]+(\.[0-9]+){2,3}$ ]]; then
        # Skip Non Version Number Strings
        continue
    fi
    if [ $(versionMinor $pyver) -eq $(versionMinor 3.11) ]; then
        pyMin="$f"
        pyFound=true
        continue
    fi
    if [ $(versionMinor $pyver) -eq $(versionMinor 3.12) ]; then
        pyMax="$f"
        pyFound=true
        pyApp=${f}
        continue
    fi
done

if !$pyFound; then
    clear
    echo
    echo "* WARNING"
    echo "* Python Requirement"
    echo "-----------------------------------------------------------------------"
    echo
    echo "Server Build Requires Python 3.11.x or higher. This script will not"
    echo "continue until Python requirement is completed."
    echo
    exit 1    
else
    if [ ! $pyMax == "NA" ]; then
        pyApp=${pyMax}
    else
        pyApp=${pyMin}
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
echo "* Begin MacPatch Server build."
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
# Create Skeleton Dir Structure
# ------------------
echo
echo "* Create MacPatch server directory structure."
echo "-----------------------------------------------------------------------"
mkdirP ${MPBASE}
mkdirP ${MPBASE}/Content
mkdirP ${MPBASE}/Content/Web
mkdirP ${MPBASE}/Content/Web/clients
mkdirP ${MPBASE}/Content/Web/patches
mkdirP ${MPBASE}/Content/Web/sav
mkdirP ${MPBASE}/Content/Web/sw
mkdirP ${MPBASE}/Content/Web/tools
cp -rp ${MPBASE}/Source/Server ${MPSERVERBASE}
mkdirP ${MPSERVERBASE}/InvData/files
mkdirP ${MPSERVERBASE}/lib
mkdirP ${MPSERVERBASE}/logs

# ------------------
# Copy compiled files
# ------------------
if $USEMACOS; then

    # Copy Agent Uploader
    cp ${MPSERVERBASE}/conf/Content/Web/tools/MPAgentUploader.zip ${MPBASE}/Content/Web/tools/

    # BREW Software Check
    XOPENSSL=false
    declare -i needsInstall=0
    sudo -u _appserver bash -c "brew list | grep openssl > /dev/null 2>&1"
    if [ $? != 0 ] ; then
        # echo "OpenSSL is not installed using brew. Please install openssl."
        needsInstall=1
        XOPENSSL=true
    fi

    XSWIG=false
    sudo -u _appserver bash -c "brew list | grep swig > /dev/null 2>&1"
    if [ $? != 0 ] ; then
        # echo "SWIG is not installed using brew. Please install swig."
        needsInstall=1
        XSWIG=true
    fi

    if [ "$needsInstall" -gt 0 ]; then
        echo
        echo
        echo "* Missing Required Software (brew packages)"
        echo "--------------------------------------------"
        if $XOPENSSL; then
            echo "Please install OpenSSL: brew install openssl"
        fi
        if $XSWIG; then
            echo "Please install SWIG: brew install swig"
        fi
        echo
        echo "Please open a new terminal and install the missing packages"
        echo "and continue with the script."
        echo
        read -p "Ready to continue (Y/N)? [Y]: " BREWSWOK
        BREWSWOK=${BREWSWOK:-Y}
        if [ "$BREWSWOK" == "Y" ] || [ "$BREWSWOK" == "y" ] ; then
            echo
        else
            exit 1
        fi
    fi
fi

# ------------------
# Install required packages
# ------------------
if $USELINUX; then
    echo
    echo "* Install required linux packages"
    echo "-----------------------------------------------------------------------"
    if $USERHEL; then
        # Add the Yarn repo
        curl -sLk https://dl.yarnpkg.com/rpm/yarn.repo -o /etc/yum.repos.d/yarn.repo
        # Check if needed packges are installed or install
        pkgs=("gcc" "gcc-c++" "zlib-devel" "pcre-devel" "openssl-devel" "epel-release" "swig" "yarn")
        for i in "${pkgs[@]}"
        do
            if [ $i == "yarn" ]; then
                #curl -sL https://rpm.nodesource.com/setup_14.x | sudo -E bash -
                curl -sL https://rpm.nodesource.com/setup_20.x | sudo -E bash -
                echo
                echo "Install nodejs 20.x"
                #yum clean all
                yum install -y -q -e 1 nodejs
                echo
            fi

            p=`rpm -qa --qf '%{NAME}\n' | grep -e ${i}$ | head -1`
            if [ -z $p ]; then
                echo " - Install $i"
                yum install -y -q -e 1 ${i}
            fi
        done
    elif $USEUBUNTU; then
        # Add additional Repo
        apt-add-repository universe
        apt-get update

        ubuntuVer=`cat /etc/lsb_release | grep DISTRIB_RELEASE | awk -F= '{print $2}'`

        # Yarn not getting installed
        # Add the Yarn repo
        curl -sSk https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
        echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
        #statements
        pkgs=("build-essential" "zlib1g-dev" "libpcre3-dev" "libssl-dev" "swig" "yarn")
        for i in "${pkgs[@]}"
        do
            if [ $i == "yarn" ]; then
                if [ $(version $ubuntuVer) -lt $(version 16.05) ]; then
                    #curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
                    curl -sL https://deb.nodesource.com/setup_20.x | sudo -E bash -
                    echo
                    echo "Install nodejs 20.x"
                    sudo apt-get install -y nodejs
                    echo
                fi
            fi

            p=`dpkg -l | grep '^ii' | grep ${i} | head -n 1 | awk '{print $2}' | grep ^${i}`
            if [ -z $p ]; then
                echo
                echo "Install $i"
                echo
                apt-get install ${i} -y
            fi
        done
    fi

    minNodeVer="8.0.0"
    nodeVer=`node -v | sed s/v//g`
    if [ $(version $nodeVer) -le $(version $minNodeVer) ]; then
        clear
        echo "***** ERROR *****"
        echo "Node version failed. Expected version \">=8\". Got $nodeVer"
        echo "Please install a newer version of node and re-run this script."
        exit 1
    fi

fi

# ------------------
# Upgrade Python Modules/Binaries
# ------------------



# ------------------
# Build NGINX
# ------------------
echo
echo "* Build and configure NGINX"
echo "-----------------------------------------------------------------------"
echo "See nginx build status in ${MPSERVERBASE}/logs/nginx-build.log"
echo
NGINX_SW=`find "${SRC_DIR}" -name "nginx-"* -type f -exec basename {} \; | tail -n +1 | head -n 1`
PCRE_SW=`find "${SRC_DIR}" -name "pcre-"* -type f -exec basename {} \; | tail -n +1 | head -n 1`
OSSL_SW=`find "${SRC_DIR}" -name "openssl-"* -type f -exec basename {} \; | tail -n +1 | head -n 1`

mkdir -p ${BUILDROOT}/nginx
tar xfz ${SRC_DIR}/${NGINX_SW} --strip 1 -C ${BUILDROOT}/nginx
cd ${BUILDROOT}/nginx

if $USELINUX; then
    ./configure --prefix=${MPSERVERBASE}/nginx \
    --without-http_autoindex_module \
    --with-http_v2_module \
    --with-http_ssl_module \
    --with-pcre \
    --with-ipv6 \
    --user=www-data \
    --group=www-data > ${MPSERVERBASE}/logs/nginx-build.log 2>&1
else
    mkdir -p ${BUILDROOT}/pcre
    tar xfz ${SRC_DIR}/${PCRE_SW} --strip 1 -C ${BUILDROOT}/pcre

    mkdir -p ${BUILDROOT}/openssl
    tar xfz ${SRC_DIR}/${OSSL_SW} --strip 1 -C ${BUILDROOT}/openssl

    # Now using brew installed openssl and pcre
    export KERNEL_BITS=64
    ./configure --prefix=${MPSERVERBASE}/nginx \
    --with-http_v2_module \
    --with-ipv6 \
    --without-http_autoindex_module \
    --without-http_ssi_module \
    --with-http_ssl_module \
    --with-openssl=${BUILDROOT}/openssl \
    --with-pcre=${BUILDROOT}/pcre > ${MPSERVERBASE}/logs/nginx-build.log 2>&1
fi

make  >> ${MPSERVERBASE}/logs/nginx-build.log 2>&1
make install >> ${MPSERVERBASE}/logs/nginx-build.log 2>&1

mv ${MPSERVERBASE}/nginx/conf/nginx.conf ${MPSERVERBASE}/nginx/conf/nginx.conf.orig
if $USEMACOS; then
    echo " - Copy nginx.conf.mac to ${MPSERVERBASE}/nginx/conf/nginx.conf"
    cp ${MPSERVERBASE}/conf/nginx/nginx.conf.mac ${MPSERVERBASE}/nginx/conf/nginx.conf
else
    echo " - Copy nginx.conf to ${MPSERVERBASE}/nginx/conf/nginx.conf"
    cp ${MPSERVERBASE}/conf/nginx/nginx.conf ${MPSERVERBASE}/nginx/conf/nginx.conf
fi
echo " - Copy nginx sites to ${MPSERVERBASE}/nginx/conf/sites"
cp -r ${MPSERVERBASE}/conf/nginx/sites ${MPSERVERBASE}/nginx/conf/sites

perl -pi -e "s#\[SRVBASE\]#$MPSERVERBASE#g" $MPSERVERBASE/nginx/conf/nginx.conf
FILES=$MPSERVERBASE/nginx/conf/sites/*.conf
for f in $FILES
do
    #echo "$f"
    perl -pi -e "s#\[SRVBASE\]#$MPSERVERBASE#g" $f
    perl -pi -e "s#\[SRVCONTENT\]#$MPSRVCONTENT#g" $f
done

# ------------------
# Link & Set Permissions
# ------------------
ln -s ${MPSERVERBASE}/conf/Content/Doc ${MPBASE}/Content/Doc
chown -R $OWNERGRP ${MPSERVERBASE}

# Admin Site - App
echo
echo "* Configuring Console app"
echo "-----------------------------------------------------------------------"

# Set Permissions
if $USEMACOS; then
    chown -R $OWNERGRP ${MPSERVERBASE}/logs
    chmod 0775 ${MPSERVERBASE}
    chown root:wheel ${MPSERVERBASE}/conf/launchd/*.plist
    chmod 0644 ${MPSERVERBASE}/conf/launchd/*.plist
fi

echo
echo "* Installing Javascript modules"
echo
cd ${MPSERVERBASE}/apps/mpconsole
yarn install --cwd ${MPSERVERBASE}/apps/mpconsole --modules-folder static/yarn_components --no-bin-links

# ------------------------------------------------------------
# Generate self signed certificates
# ------------------------------------------------------------
#clear
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
DOMAIN=`hostname`
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
fi

# ------------------------------------------------------------
# Create Virtualenv
# ------------------------------------------------------------
echo
echo "* Create Virtualenv for Web services app"
echo "-----------------------------------------------------------------------"

mkdir -p "${MPSERVERBASE}/apps/log"
chown $OWNERGRP "${MPSERVERBASE}/apps/log"
chmod 2777 "${MPSERVERBASE}/apps/log"

cd "${MPSERVERBASE}"
if $USEMACOS; then
    /usr/local/bin/python3 -m venv env/server --copies --clear
    /usr/local/bin/python3 -m venv env/api --copies --clear
    /usr/local/bin/python3 -m venv env/console --copies --clear
else
    eval "$pyApp -m venv env/server --copies --clear"
    eval "$pyApp -m venv env/api --copies --clear"
    eval "$pyApp -m venv env/console --copies --clear"
fi

cd "${MPSERVERBASE}/apps"
if $USEMACOS; then
    OPENSSLPWD=`brew --prefix openssl@1.1 | awk -F@ '{print $1}'`

    # Server venv
    echo "Creating server scripts virtual env..."
    source ${MPSERVERBASE}/env/server/bin/activate
    ${MPSERVERBASE}/env/server/bin/pip3 -q install --upgrade pip --no-cache-dir

    env CFLAGS="-I/usr/local/include -I${OPENSSLPWD}/include -L/usr/local/lib -L${OPENSSLPWD}/lib" ${MPSERVERBASE}/env/server/bin/pip3 \
    -q install -r ${MPSERVERBASE}/apps/pyRequiredServer.txt
    deactivate

    # API venv
    echo "Creating api virtual env..."
    source ${MPSERVERBASE}/env/api/bin/activate
    ${MPSERVERBASE}/env/api/bin/pip3 -q install --upgrade pip --no-cache-dir

    env "CFLAGS=-I/usr/local/include -L/usr/local/lib" ${MPSERVERBASE}/env/api/bin/pip3 -q install \
    -r ${MPSERVERBASE}/apps/pyRequiredAPI.txt --no-cache-dir
    deactivate

    # Console venv
    echo "Creating console virtual env..."
    source ${MPSERVERBASE}/env/console/bin/activate
    ${MPSERVERBASE}/env/console/bin/pip3 -q install --upgrade pip --no-cache-dir

    env CFLAGS="-I/usr/local/include -I${OPENSSLPWD}/include -L/usr/local/lib -L${OPENSSLPWD}/lib" ${MPSERVERBASE}/env/console/bin/pip3 \
    -q install -r ${MPSERVERBASE}/apps/pyRequiredConsole.txt --no-cache-dir
    deactivate

else
    echo "Creating server scripts virtual env..."
    source ${MPSERVERBASE}/env/server/bin/activate
    ${MPSERVERBASE}/env/server/bin/pip3 -q install --upgrade pip --no-cache-dir
    ${MPSERVERBASE}/env/api/bin/pip3 -q install -r ${MPSERVERBASE}/apps/pyRequiredServer.txt
    deactivate

    echo "Creating api virtual env..."
    source ${MPSERVERBASE}/env/api/bin/activate
    ${MPSERVERBASE}/env/api/bin/pip3 -q install --upgrade pip --no-cache-dir
    ${MPSERVERBASE}/env/api/bin/pip3 -q install -r ${MPSERVERBASE}/apps/pyRequiredAPI.txt
    deactivate

    echo "Creating console virtual env..."
    source ${MPSERVERBASE}/env/console/bin/activate
    ${MPSERVERBASE}/env/console/bin/pip3 -q install --upgrade pip --no-cache-dir
    ${MPSERVERBASE}/env/console/bin/pip3 -q install -r ${MPSERVERBASE}/apps/pyRequiredConsole.txt
    deactivate
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
#clear
echo "Setting Permissions..."
chmod -R 0775 "${MPBASE}/Content"
chown -R $OWNERGRP "${MPBASE}/Content"
chmod -R 0775 "${MPSERVERBASE}/logs"
chmod -R 0775 "${MPSERVERBASE}/etc"
chmod -R 0775 "${MPSERVERBASE}/InvData"
chown -R $OWNERGRP "${MPSERVERBASE}/env"

echo
echo
echo "-----------------------------------------------------------------------"
echo " * Server build has been completed. Please read the \"Server - Install & Setup\""
echo "   document for the next steps in setting up the MacPatch server."
echo

exit 0;
