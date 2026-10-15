#!/bin/bash
#
# ----------------------------------------------------------------------------
# Script: MPBuildServer.sh
# Version: 3.8.8
#
# Description:
# This is a very simple script to demonstrate how to automate
# the build process of the MacPatch Server.
#
# Info:
# Simply modify the GITROOT and BUILDROOT variables
#
# History:
# 3.8.8     Added Python version detection and selection
#           Checks for Python 3.14 first (preferred), then any 3.12+
#           Minimum version is 3.12, will use 3.14 if available
#           Skips Python installation if suitable version already present
# 3.8.7     Extended Python script permission handling
#           All .py files in conf/scripts now get 755 (admin/utility scripts)
#           Python scripts with shebangs in both apps and conf/scripts get 755
#           Ensures ServerSetup.py and other admin scripts are executable
# 3.8.6     Improved permission handling with explicit 755 for executables
#           Sets all files to 644 first, then executables to 755 (not 754)
#           Ensures consistent rwxr-xr-x (755) for all executable files
#           Includes nginx binary, shell scripts, venv binaries, Python scripts
#           Service files explicitly set to 644 (not executable)
# 3.8.5     Fixed executable permission handling
#           Explicitly ensures nginx binary remains executable
#           Ensures shell scripts (.sh) remain executable
#           Ensures virtual environment binaries remain executable
#           Ensures Python scripts with shebangs remain executable
#           Added verification step at end of build
# 3.8.4     Added SECRET_KEY validation and generation
#           Checks .mpglobal file for SECRET_KEY presence and length
#           Offers to generate secure 64-character SECRET_KEY
#           Validates existing keys are at least 32 characters
#           Supports graceful key rotation (preserves old key as SECRET_KEY_OLD)
# 3.8.3     Fixed nginx download function output handling
#           Status messages now go to stderr, only path to stdout
#           Prevents command substitution from capturing echo statements
# 3.8.2     Added nginx download with fallback to bundled version
#           Attempts to download latest nginx from nginx.org first
#           Falls back to bundled nginx tar.gz if download fails
#           Validates downloaded file before using it
# 3.8.1     Check if Node.js is already installed before attempting reinstall
#           Skip Node.js installation if version >= 18.0.0 is already present
#           Skip yarn installation if already installed
# 1.4:    Remove Jetty Support
#     Added Tomcat 7.0.57
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
# 3.6.2     Updated, now using npm to install yarn
#           Add redis to server install, updated to python3.11 or python3.12
# 3.7.0     Updated logic for CentOS
# 3.8.0     Python 3.12 is the minimum supported version, 3.14 is recommended (MP_PYTHON
#           selects the interpreter). RHEL 8 now uses python3.12. M2Crypto is no longer
#           installed, nothing uses it, so SWIG is no longer a prerequisite.
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
USECENTOS=false
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
RHEL_MAJOR="0"
py3="python3"
majorVer="0"
minorVer="0"
buildVer="0"
DTS=$(date +%Y%m%d_%H%M%S)

if [[ $platform == 'linux' ]]; then

    distName=`cat /etc/os-release | grep "NAME=" | head -n1`
    if [[ $distName == *"Red"*  || $distName == *"Cent"* ]]; then
        USERHEL=true
        if [[ $distName == *"Cent"* ]]; then
            USECENTOS=true
        fi
        rhel_ver=$(awk -F'=' '/VERSION_ID/{ gsub(/"/,""); print $2}' /etc/os-release)
        
        case $rhel_ver in
        7|7.*)
            RHEL_MAJOR="7"
            ;;
        8|8.*)
            RHEL_MAJOR="8"
            py3="python3.12"
            ;;
        9|9.*)
            RHEL_MAJOR="9"
            py3="python3.12"
            ;;
        esac

        if [ $RHEL_MAJOR == "7" ]; then
            echo "Not running a supported version of RHEL Linux."
            exit 1
        fi

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

# Script Input Args ----------------------------------------------------------

usage() { echo "Usage: $0 [-c ALT_SSL_CERT]" 1>&2; exit 1; }

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
[ -t 1 ] && command -v clear >/dev/null 2>&1 && clear 2>/dev/null || true

if $USEMACOS; then

    if $MACPROMPTFORXCODE; then
        [ -t 1 ] && command -v clear >/dev/null 2>&1 && clear 2>/dev/null || true
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
        echo "This install requires \"Yarn\", \"OpenSSL\" and \"GPM\" to be installed"
        echo "using brew. It's recommended that you install these two"
        echo "applications before continuing."
        echo
        echo "Exapmple: brew install yarn openssl gpm"
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

  if $USERHEL; then
    if $USECENTOS; then
      if dnf repolist enabled | grep -q '^crb'; then
        echo "CRB repo is enabled"
      else
        if ! rpm -q dnf-plugins-core > /dev/null 2>&1; then
          echo "Install dnf-plugins-core"
          yum install -y -q -e 1 dnf-plugins-core
        fi
        echo "Enable CRB repo"
        dnf config-manager --set-enabled crb
      fi
    fi

    if rpm -q epel-release > /dev/null 2>&1; then
      echo "epel-release is installed"
    else
      echo "Install epel-release"
      yum install -y -q -e 1 epel-release
    fi
  fi
fi

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
[ -t 1 ] && command -v clear >/dev/null 2>&1 && clear 2>/dev/null || true
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

    if [ "$needsInstall" -gt 0 ]; then
        echo
        echo
        echo "* Missing Required Software (brew packages)"
        echo "--------------------------------------------"
        if $XOPENSSL; then
            echo "Please install OpenSSL: brew install openssl"
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
        if [ $RHEL_MAJOR == "8" ]; then
            pkgs=("gcc" "gcc-c++" "zlib-devel" "pcre-devel" "openssl-devel" "python3.12" "python3.12-devel" "python3.12-setuptools" "python3.12-pip" "yarn" "redis6")
        elif [ $RHEL_MAJOR == "9" ]; then
            pkgs=("gcc" "gcc-c++" "zlib-devel" "pcre-devel" "openssl-devel" "python3.12" "python3.12-devel" "python3.12-setuptools" "python3.12-pip" "yarn" "redis")
        fi

        for i in "${pkgs[@]}"
        do
            if [ $i == "yarn" ]; then
                # Check if node is already installed with recent enough version
                minNodeVer="18.0.0"
                needsNodeInstall=true

                if command -v node >/dev/null 2>&1; then
                    nodeVer=$(node -v | sed 's/v//g')
                    if [ $(version $nodeVer) -ge $(version $minNodeVer) ]; then
                        echo "Node.js $nodeVer is already installed (minimum required: $minNodeVer)"
                        needsNodeInstall=false
                    else
                        echo "Node.js $nodeVer is installed but below minimum version $minNodeVer"
                    fi
                fi

                if $needsNodeInstall; then
                    curl -sL https://rpm.nodesource.com/setup_22.x | sudo -E bash -
                    echo
                    echo "Install nodejs 22.x"
                    yum clean all
                    yum install -y -q -e 1 nodejs
                fi

                # Check if yarn is already installed
                if ! command -v yarn >/dev/null 2>&1; then
                    echo
                    echo "Install yarn via npm"
                    npm install --global yarn
                else
                    echo "Yarn is already installed"
                fi
            else
                if [ $i == "redis6" ]; then
                    echo " - Install $i"
                    dnf module -y install redis:6
                else
                    p=`rpm -qa --qf '%{NAME}\n' | grep -e ${i}$ | head -1`
                    if [ -z $p ]; then
                        echo " - Install $i"
                        yum install -y -q -e 1 ${i}
                    fi
                fi
            fi
        done
        systemctl enable redis
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
        pkgs=("build-essential" "zlib1g-dev" "libpcre3-dev" "libssl-dev" "python3-dev" "python3-pip" "python3-venv" "yarn")
        for i in "${pkgs[@]}"
        do
            if [ $i == "yarn" ]; then
                # Check if node is already installed with recent enough version
                minNodeVer="18.0.0"
                needsNodeInstall=true

                if command -v node >/dev/null 2>&1; then
                    nodeVer=$(node -v | sed 's/v//g')
                    if [ $(version $nodeVer) -ge $(version $minNodeVer) ]; then
                        echo "Node.js $nodeVer is already installed (minimum required: $minNodeVer)"
                        needsNodeInstall=false
                    else
                        echo "Node.js $nodeVer is installed but below minimum version $minNodeVer"
                    fi
                fi

                if $needsNodeInstall && [ $(version $ubuntuVer) -lt $(version 16.05) ]; then
                    curl -sL https://deb.nodesource.com/setup_22.x | sudo -E bash -
                    echo
                    echo "Install nodejs 22.x"
                    sudo apt-get install -y nodejs
                fi

                # Check if yarn is already installed
                if ! command -v yarn >/dev/null 2>&1; then
                    echo
                    echo "Install yarn via npm"
                    npm install --global yarn
                else
                    echo "Yarn is already installed"
                fi
            else
                p=`dpkg -l | grep '^ii' | grep ${i} | head -n 1 | awk '{print $2}' | grep ^${i}`
                if [ -z $p ]; then
                    echo
                    echo "Install $i"
                    echo
                    apt-get install ${i} -y
                fi
            fi
        done
    fi

    minNodeVer="18.0.0"
    nodeVer=`node -v | sed s/v//g`
    if [ $(version $nodeVer) -le $(version $minNodeVer) ]; then
        [ -t 1 ] && command -v clear >/dev/null 2>&1 && clear 2>/dev/null || true
        echo "***** ERROR *****"
        echo "Node version failed. Expected version \">=18\". Got $nodeVer"
        echo "Please install a newer version of node and re-run this script."
        exit 1
    fi

fi

# ------------------
# Upgrade Python Modules/Binaries
# ------------------



# ------------------
# ------------------
# Download or use bundled NGINX
# ------------------
download_nginx() {
    local nginx_version="${1:-1.31.7}"
    local nginx_url="https://nginx.org/download/nginx-${nginx_version}.tar.gz"
    local build_dir="/tmp/nginx-build-${DTS}"
    local nginx_tar="nginx-${nginx_version}.tar.gz"
    local download_success=false

    # Send status messages to stderr so they don't get captured by command substitution
    echo >&2
    echo "* Downloading NGINX ${nginx_version}" >&2
    echo "-----------------------------------------------------------------------" >&2

    # Create temporary build directory
    mkdir -p "${build_dir}"

    # Try to download nginx from nginx.org
    echo "Attempting to download nginx ${nginx_version} from nginx.org..." >&2
    if curl -f -L -o "${build_dir}/${nginx_tar}" "${nginx_url}" 2>/dev/null; then
        echo "✓ Successfully downloaded nginx ${nginx_version}" >&2
        download_success=true

        # Verify the download is a valid tar.gz
        if tar -tzf "${build_dir}/${nginx_tar}" >/dev/null 2>&1; then
            echo "✓ Download verified as valid tar.gz" >&2
            # Only echo the path to stdout (this gets captured)
            echo "${build_dir}/${nginx_tar}"
            return 0
        else
            echo "✗ Downloaded file is not a valid tar.gz, will use bundled version" >&2
            download_success=false
        fi
    else
        echo "✗ Failed to download nginx from nginx.org" >&2
    fi

    # Fallback to bundled nginx tar.gz
    if ! $download_success; then
        echo "Using bundled nginx from repository..." >&2
        local bundled_nginx=$(find "${SRC_DIR}" -name "nginx-*.tar.gz" -type f | head -n 1)

        if [ -n "$bundled_nginx" ] && [ -f "$bundled_nginx" ]; then
            local bundled_version=$(basename "$bundled_nginx" .tar.gz | sed 's/nginx-//')
            echo "✓ Found bundled nginx ${bundled_version}: $bundled_nginx" >&2
            # Only echo the path to stdout (this gets captured)
            echo "$bundled_nginx"
            return 0
        else
            echo "✗ ERROR: No bundled nginx found in ${SRC_DIR}" >&2
            return 1
        fi
    fi
}

# Build NGINX
# ------------------
echo
echo "* Build and configure NGINX"
echo "-----------------------------------------------------------------------"
echo "See nginx build status in ${MPSERVERBASE}/logs/nginx-build.log"
echo

# Download or get bundled nginx
NGINX_TAR_PATH=$(download_nginx "1.31.2")
if [ $? -ne 0 ] || [ -z "$NGINX_TAR_PATH" ]; then
    echo "ERROR: Failed to obtain nginx source"
    exit 1
fi

NGINX_SW=$(basename "$NGINX_TAR_PATH")
echo "Using nginx: ${NGINX_SW}"
echo

mkdir -p ${BUILDROOT}/nginx
tar xfz "${NGINX_TAR_PATH}" --strip 1 -C ${BUILDROOT}/nginx

# Clean up temporary download if it was downloaded
if [[ "${NGINX_TAR_PATH}" == /tmp/nginx-build-* ]]; then
    echo "Cleaning up temporary download directory..."
    rm -rf "$(dirname "${NGINX_TAR_PATH}")"
fi

cd ${BUILDROOT}/nginx

if $USELINUX; then
    ./configure --prefix=${MPSERVERBASE}/nginx \
    --without-http_autoindex_module \
    --with-http_v2_module \
    --with-http_ssl_module \
    --with-pcre \
    --user=www-data \
    --group=www-data > ${MPSERVERBASE}/logs/nginx-build.log 2>&1
else
    # Now using brew installed openssl and pcre
    OPENSSLPWD=`sudo -u _appserver bash -c "brew --prefix openssl"`
    export KERNEL_BITS=64
    ./configure --prefix=${MPSERVERBASE}/nginx \
    --with-cc-opt="-I${OPENSSLPWD}/include" \
    --with-ld-opt="-L${OPENSSLPWD}/lib" \
    --with-http_v2_module \
    --without-http_autoindex_module \
    --without-http_ssi_module \
    --with-http_ssl_module \
    --with-pcre > ${MPSERVERBASE}/logs/nginx-build.log 2>&1

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

# Ensure critical binaries and scripts have correct permissions (755 for executables, 644 for regular files)
echo "Setting correct file permissions..."

# Set base permissions for all files and directories
find "${MPSERVERBASE}" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "${MPSERVERBASE}" -type f -exec chmod 644 {} \; 2>/dev/null || true

# Now set executable files to 755
echo "Setting executable permissions (755)..."

# Nginx binary
if [ -f "${MPSERVERBASE}/nginx/sbin/nginx" ]; then
    chmod 755 "${MPSERVERBASE}/nginx/sbin/nginx"
fi

# Shell scripts in all locations
find "${MPSERVERBASE}/conf/scripts" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
find "${MPSERVERBASE}/conf/Content/Web/clients" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
find "${MPBASE}/scripts" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true

# Virtual environment binaries (all files in bin directories should be executable)
for venv_bin in "${MPSERVERBASE}/apps/api/venv/bin" "${MPSERVERBASE}/apps/console/venv/bin"; do
    if [ -d "$venv_bin" ]; then
        find "$venv_bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
    fi
done

# Python scripts with shebangs in apps and conf/scripts
find "${MPSERVERBASE}/apps" -type f -name "*.py" -exec grep -l "^#!" {} \; 2>/dev/null | xargs -r chmod 755 2>/dev/null || true
find "${MPSERVERBASE}/conf/scripts" -type f -name "*.py" -exec grep -l "^#!" {} \; 2>/dev/null | xargs -r chmod 755 2>/dev/null || true

# All .py files in conf/scripts should be executable (they're typically admin scripts)
find "${MPSERVERBASE}/conf/scripts" -type f -name "*.py" -exec chmod 755 {} \; 2>/dev/null || true

# Systemd service files should be 644
find "${MPSERVERBASE}/conf/scripts/systemd" -type f -name "*.service" -exec chmod 644 {} \; 2>/dev/null || true

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
cd ${MPSERVERBASE}/apps/console/mpconsole
yarn install --cwd ${MPSERVERBASE}/apps/console/mpconsole --modules-folder static/yarn_components --no-bin-links

# ------------------------------------------------------------
# Check and validate SECRET_KEY in .mpglobal
# ------------------------------------------------------------
echo
echo "* Checking SECRET_KEY configuration"
echo "-----------------------------------------------------------------------"

MPGLOBAL_FILE="${MPSERVERBASE}/apps/.mpglobal"

# Check if .mpglobal exists
if [ ! -f "$MPGLOBAL_FILE" ]; then
    echo "WARNING: .mpglobal file not found at ${MPGLOBAL_FILE}"
    echo "Creating .mpglobal file..."
    echo "# Shared App Variables" > "$MPGLOBAL_FILE"
fi

# Check if SECRET_KEY is set
if ! grep -q "^SECRET_KEY=" "$MPGLOBAL_FILE"; then
    echo
    echo "============================================================================"
    echo "CRITICAL: SECRET_KEY is not set in .mpglobal file!"
    echo "============================================================================"
    echo
    echo "The SECRET_KEY is required for secure session management and token signing."
    echo "You must set a strong, random SECRET_KEY before starting the MacPatch services."
    echo
    echo "Generate a secure key with:"
    echo "  python3 -c 'import secrets; print(secrets.token_hex(32))'"
    echo
    echo "Then add it to ${MPGLOBAL_FILE}:"
    echo "  SECRET_KEY=<your-generated-key>"
    echo
    echo "The SECRET_KEY must be at least 32 characters long."
    echo
    read -p "Would you like to generate and set a SECRET_KEY now? (Y/N) [Y]: " GENERATE_KEY
    GENERATE_KEY=${GENERATE_KEY:-Y}

    if [ "$GENERATE_KEY" == "Y" ] || [ "$GENERATE_KEY" == "y" ]; then
        # Generate a secure random key
        NEW_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

        if [ -n "$NEW_SECRET_KEY" ]; then
            echo >> "$MPGLOBAL_FILE"
            echo "# Flask secret key for session management and token signing" >> "$MPGLOBAL_FILE"
            echo "# Generated: $(date)" >> "$MPGLOBAL_FILE"
            echo "SECRET_KEY=${NEW_SECRET_KEY}" >> "$MPGLOBAL_FILE"

            echo
            echo "✓ SECRET_KEY has been generated and saved to ${MPGLOBAL_FILE}"
            echo
        else
            echo
            echo "ERROR: Failed to generate SECRET_KEY"
            echo "Please set it manually in ${MPGLOBAL_FILE}"
            exit 1
        fi
    else
        echo
        echo "Build will continue, but you MUST set SECRET_KEY before starting services!"
        echo "File location: ${MPGLOBAL_FILE}"
        echo
    fi
else
    # SECRET_KEY exists, validate it
    SECRET_KEY_VALUE=$(grep "^SECRET_KEY=" "$MPGLOBAL_FILE" | cut -d= -f2)
    SECRET_KEY_LENGTH=${#SECRET_KEY_VALUE}

    if [ $SECRET_KEY_LENGTH -lt 32 ]; then
        echo
        echo "============================================================================"
        echo "WARNING: SECRET_KEY is too short (${SECRET_KEY_LENGTH} characters)"
        echo "============================================================================"
        echo
        echo "The SECRET_KEY must be at least 32 characters long for security."
        echo "Current length: ${SECRET_KEY_LENGTH}"
        echo
        echo "Generate a new secure key with:"
        echo "  python3 -c 'import secrets; print(secrets.token_hex(32))'"
        echo
        read -p "Would you like to generate a new SECRET_KEY now? (Y/N) [Y]: " REGEN_KEY
        REGEN_KEY=${REGEN_KEY:-Y}

        if [ "$REGEN_KEY" == "Y" ] || [ "$REGEN_KEY" == "y" ]; then
            NEW_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

            if [ -n "$NEW_SECRET_KEY" ]; then
                # Backup old key as SECRET_KEY_OLD for rotation support
                sed -i.bak "s/^SECRET_KEY=.*/SECRET_KEY_OLD=${SECRET_KEY_VALUE}/" "$MPGLOBAL_FILE"
                echo "SECRET_KEY=${NEW_SECRET_KEY}" >> "$MPGLOBAL_FILE"

                echo
                echo "✓ New SECRET_KEY generated and saved"
                echo "✓ Old key preserved as SECRET_KEY_OLD for graceful rotation"
                echo
            else
                echo
                echo "ERROR: Failed to generate SECRET_KEY"
                exit 1
            fi
        else
            echo
            echo "WARNING: Continuing with short SECRET_KEY - services may fail to start!"
            echo
        fi
    else
        echo "✓ SECRET_KEY is set and valid (${SECRET_KEY_LENGTH} characters)"
    fi
fi

# ------------------------------------------------------------
# Generate self signed certificates
# ------------------------------------------------------------
#[ -t 1 ] && command -v clear >/dev/null 2>&1 && clear 2>/dev/null || true
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


CA_STR=""
if [ "$CA_CERT" != "NA" ]; then
    CA_STR="--cert \"$CA_CERT\""
fi

# Python 3.12 is the minimum supported version and 3.14 is recommended.
# Set MP_PYTHON to use a specific interpreter, e.g. MP_PYTHON=python3.14
# If MP_PYTHON is not set, check for python3.14 first (preferred), then python3.12+
if [ -z "$MP_PYTHON" ]; then
    # Check for python3.14 first (preferred version)
    if command -v python3.14 > /dev/null 2>&1; then
        py3="python3.14"
        echo "Found preferred Python 3.14"
    else
        # Check if default py3 meets minimum version (3.12)
        if command -v "$py3" > /dev/null 2>&1; then
            pyVer=$("$py3" -c 'import sys; print(".".join(map(str, sys.version_info[:2])))' 2>/dev/null)
            if [ -n "$pyVer" ]; then
                pyMajor=$(echo "$pyVer" | cut -d. -f1)
                pyMinor=$(echo "$pyVer" | cut -d. -f2)
                if [ "$pyMajor" -eq 3 ] && [ "$pyMinor" -ge 12 ]; then
                    echo "Found Python $pyVer (meets minimum 3.12)"
                else
                    echo "Python $pyVer found but does not meet minimum version 3.12"
                    py3=""
                fi
            else
                py3=""
            fi
        else
            py3=""
        fi

        # If no suitable Python found, error out
        if [ -z "$py3" ]; then
            echo "MacPatch Server requires Python 3.12 or higher (3.14 is recommended)."
            echo "No suitable Python interpreter found. Install Python 3.12+, or set"
            echo "MP_PYTHON to the interpreter to use, e.g. MP_PYTHON=python3.14"
            exit 1
        fi
    fi
else
    # User specified MP_PYTHON, use it but validate minimum version
    py3="$MP_PYTHON"
    if ! command -v "$py3" > /dev/null 2>&1 || ! "$py3" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)'; then
        echo "MacPatch Server requires Python 3.12 or higher (3.14 is recommended)."
        echo "\"$py3\" was not found or is older than 3.12. Install a newer Python, or set"
        echo "MP_PYTHON to the interpreter to use, e.g. MP_PYTHON=python3.14"
        exit 1
    fi
fi
echo "Using Python: $($py3 --version 2>&1) ($(command -v "$py3"))"

cd "${MPSERVERBASE}/apps"
if $USEMACOS; then
    $py3 -m venv env/server --copies --clear
    $py3 -m venv env/api --copies --clear
    $py3 -m venv env/console --copies --clear
    OPENSSLPWD=`sudo -u _appserver bash -c "brew --prefix openssl"`

    # Server venv
    echo "Creating server scripts virtual env..."
    source ${MPSERVERBASE}/env/server/bin/activate
    ${MPSERVERBASE}/env/server/bin/pip3 -q install --upgrade pip --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install pycrypto --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install simplejson --no-cache-dir--no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install requests --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install mysql-connector-python --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install psutil --no-cache-dir

    env "CFLAGS=-I/usr/local/include -L/usr/local/lib" ${MPSERVERBASE}/env/server/bin/pip3 \
    -q install -r ${MPSERVERBASE}/apps/pyRequiredAPI.txt $CA_STR
    deactivate

    # API venv
    echo "Creating api virtual env..."
    source ${MPSERVERBASE}/env/api/bin/activate
    ${MPSERVERBASE}/env/api/bin/pip3 -q install --upgrade pip --no-cache-dir

    env "CFLAGS=-I/usr/local/include -L/usr/local/lib" ${MPSERVERBASE}/env/api/bin/pip3 -q install \
    -r ${MPSERVERBASE}/apps/pyRequiredAPI.txt $CA_STR --no-cache-dir
    deactivate

    # Console venv
    echo "Creating console virtual env..."
    source ${MPSERVERBASE}/env/console/bin/activate
    ${MPSERVERBASE}/env/console/bin/pip3 -q install --upgrade pip --no-cache-dir

    env "CFLAGS=-I/usr/local/include -L/usr/local/lib" ${MPSERVERBASE}/env/console/bin/pip3 \
    -q install -r ${MPSERVERBASE}/apps/pyRequiredConsole.txt $CA_STR --no-cache-dir
    deactivate

else
    $py3 -m venv "${MPSERVERBASE}/env/server" --copies --clear
    $py3 -m venv "${MPSERVERBASE}/env/api" --copies --clear
    $py3 -m venv "${MPSERVERBASE}/env/console" --copies --clear

    echo "Creating server scripts virtual env..."
    source ${MPSERVERBASE}/env/server/bin/activate
    ${MPSERVERBASE}/env/server/bin/pip3 -q install --upgrade pip --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install pycrypto --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install simplejson --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install requests --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install mysql-connector-python --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install psutil --no-cache-dir
    ${MPSERVERBASE}/env/server/bin/pip3 -q install python-crontab --no-cache-dir
    deactivate

    echo "Creating api virtual env..."
    source ${MPSERVERBASE}/env/api/bin/activate
    ${MPSERVERBASE}/env/api/bin/pip3 -q install --upgrade pip --no-cache-dir
    ${MPSERVERBASE}/env/api/bin/pip3 -q install -r ${MPSERVERBASE}/apps/pyRequiredAPI.txt $CA_STR
    deactivate

    echo "Creating console virtual env..."
    source ${MPSERVERBASE}/env/console/bin/activate
    ${MPSERVERBASE}/env/console/bin/pip3 -q install --upgrade pip --no-cache-dir
    ${MPSERVERBASE}/env/console/bin/pip3 -q install -r ${MPSERVERBASE}/apps/pyRequiredConsole.txt $CA_STR
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
[ -t 1 ] && command -v clear >/dev/null 2>&1 && clear 2>/dev/null || true
echo "Setting Permissions..."
chmod -R 0775 "${MPBASE}/Content"
chown -R $OWNERGRP "${MPBASE}/Content"
chmod -R 0775 "${MPSERVERBASE}/logs"
chmod -R 0775 "${MPSERVERBASE}/etc"
chmod -R 0775 "${MPSERVERBASE}/InvData"
chown -R $OWNERGRP "${MPSERVERBASE}/env"

# Final check: ensure all files have correct permissions (755 for executables, 644 for others)
echo "Final permission verification..."

# Nginx binary
if [ -f "${MPSERVERBASE}/nginx/sbin/nginx" ]; then
    chmod 755 "${MPSERVERBASE}/nginx/sbin/nginx"
    echo "✓ Nginx binary (755)"
fi

# Shell scripts in various locations
for script_dir in "${MPBASE}/scripts" "${MPSERVERBASE}/conf/scripts" "${MPSERVERBASE}/conf/Content/Web/clients"; do
    if [ -d "$script_dir" ]; then
        # Set all .sh files to 755
        find "$script_dir" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
        # Set non-.sh files to 644 (like .service files)
        find "$script_dir" -type f ! -name "*.sh" -exec chmod 644 {} \; 2>/dev/null || true
    fi
done
echo "✓ Shell scripts (755)"

# Virtual environment binaries (API and Console) - all should be 755
for venv_bin in "${MPSERVERBASE}/apps/api/venv/bin" "${MPSERVERBASE}/apps/console/venv/bin"; do
    if [ -d "$venv_bin" ]; then
        find "$venv_bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
    fi
done
echo "✓ Virtual environment binaries (755)"

# Python scripts with shebangs should be 755
find "${MPSERVERBASE}/apps" -type f -name "*.py" -exec grep -l "^#!" {} \; 2>/dev/null | xargs -r chmod 755 2>/dev/null || true
find "${MPSERVERBASE}/conf/scripts" -type f -name "*.py" -exec grep -l "^#!" {} \; 2>/dev/null | xargs -r chmod 755 2>/dev/null || true

# All .py files in conf/scripts should be executable (they're typically admin scripts)
find "${MPSERVERBASE}/conf/scripts" -type f -name "*.py" -exec chmod 755 {} \; 2>/dev/null || true
echo "✓ Python scripts (755)"

# Ensure systemd service files are 644 (not executable)
if [ -d "${MPSERVERBASE}/conf/scripts/systemd" ]; then
    find "${MPSERVERBASE}/conf/scripts/systemd" -type f -name "*.service" -exec chmod 644 {} \; 2>/dev/null || true
    echo "✓ Systemd service files (644)"
fi

echo
echo
echo "-----------------------------------------------------------------------"
echo " * Server build has been completed. Please read the \"Server - Install & Setup\""
echo "   document for the next steps in setting up the MacPatch server."
echo

exit 0;
