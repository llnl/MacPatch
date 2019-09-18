#!/bin/bash

# -------------------------------------------------------------
# Script: MPBuildClient.sh
# Version: 2.2
#
# Description:
# This is a very simple script to demonstrate how to automate
# the build process of the MacPatch Agent.
#
# History:
#	1.1		Added Code Signbing Support
#   1.2		Added ability to save CODESIGNIDENTITY
#   1.4		Script No Longer is static location
#	1.5		Changed Vars for MP 3.1
#	1.6		Updated version numbers
#	1.7		Add OS Query to agent install
# 	1.8		Add PlanB support to base package as an option
#	1.9		Update to PlanB syntax
#   2.0		Updated to support new 3.2 agent and package name
#   2.1     Add support external scripts for customizing
#   2.2     Added planB save server address
#
# -------------------------------------------------------------

SCRIPT_PARENT=$(dirname $(dirname $0))
SRCROOT="$SCRIPT_PARENT/Source"
PKGROOT="$SCRIPT_PARENT/Packages"
DATETIME=`date "+%Y%m%d-%H%M%S"`
BUILDROOT="/private/var/tmp/MP/Client32/$DATETIME"
PLANB_BUILDROOT=`mktemp -d /tmp/mpPlanB_XXXXXX`
BUILD_NO_STR=`date +%Y%m%d-%H%M%S`

AGENTVER="3.3.1.1"
UPDATEVER="3.3.1.1"

PKG_STATE=""
CODESIGNIDENTITY="*"
MIN_OS="10.12"
INCPlanBSource=false
MPPLANB_SRV_ADDR="localhost"
BUILDPLIST="/Library/Preferences/mp.build.client32.plist"

# Extenral scripts run pre xcode compile
EXTERNALSCRIPTS=false
EXTERNALSCRIPTSDIR="/tmp/foo"
# Post Extenral script, just befor pkg build
PEXTERNALSCRIPTS=false
PEXTERNALSCRIPTSDIR="/tmp/foo"


# Script Input Args ----------------------------------------------------------

usage() { echo "Usage: $0 [-s External Scripts Dir] [-p Post External Scripts Dir]" 1>&2; exit 1; }

while getopts "hs:p:" opt; do
    case $opt in
        s)
            EXTERNALSCRIPTS=true
            EXTERNALSCRIPTSDIR=${OPTARG}
            ;;
        p)
            PEXTERNALSCRIPTS=true
            PEXTERNALSCRIPTSDIR=${OPTARG}
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
            #echo "Option -$OPTARG requires an argument." >&2
            #echo
            #usage
            #exit 1
            ;;
    esac
done

runExternalScripts () 
{
    if [ -z "$1" ]; then
        # Scripts path is blank
        return
    fi

   spath="$1"
   
    FILES="$1/*.sh"
    for f in $FILES 
    do
        echo "Processing $f file..."
        bash $f "$SCRIPT_PARENT" "$BUILDROOT"
    done

    return
}




if [ -f "$BUILDPLIST" ]; then
	CODESIGNIDENTITYALT=`defaults read ${BUILDPLIST} name 2> /dev/null`
fi

if [ -d "$BUILDROOT" ]; then
	rm -rf ${BUILDROOT}
else
	mkdir -p ${BUILDROOT}
	mkdir -p ${BUILDROOT}/logs
fi

#clear
echo " ------------------------------------------------------------"
echo "  Building MacPatch Client"
echo " ------------------------------------------------------------"
echo

# ------------------------------------------------------------
# Choose to include PlanB as part of base package
# ------------------------------------------------------------

# Convert bool to string
if $INCPlanBSource; then
	INC_PLANB_VAR="Y"
else
	INC_PLANB_VAR="N"
fi

# If There is a saved plist read it, and set string value
if [ -f "$BUILDPLIST" ]; then
	INC_PLANB_VAR=`defaults read ${BUILDPLIST} incPlanB 2> /dev/null`
	if (($? > 0)); then
		if $INCOSQUERY; then
			INC_PLANB_VAR="Y"
		else
			INC_PLANB_VAR="N"
		fi
	else
		if [[ $INC_PLANB_VAR == 1 ]]; then
			INC_PLANB_VAR="Y"
		else	
			INC_PLANB_VAR="N"
		fi
	fi
fi

echo
echo " - Include PlanB with MacPatch Installer "
read -p "Would you like to include PlanB with MacPatch (Y/N)? [$INC_PLANB_VAR]: " INC_PLANB_TXT
INC_PLANB_TXT=${INC_PLANB_TXT:-${INC_PLANB_VAR}}
INC_PLANB_TXT=`echo $INC_PLANB_TXT | awk '{print toupper($0)}'`
if [ "$INC_PLANB_TXT" != "$INC_PLANB_VAR" ]; then
	if [[ "$INC_PLANB_TXT" == "Y" ]]; then
		defaults write ${BUILDPLIST} incPlanB -bool YES
	else 
		defaults write ${BUILDPLIST} incPlanB -bool NO
	fi
fi

if [[ "$INC_PLANB_TXT" == "Y" ]]; then
	INCPlanBSource=true
else 
	INCPlanBSource=false
fi


if $INCPlanBSource; then
    PLANBSRV=$MPPLANB_SRV_ADDR
    if [ -f "$BUILDPLIST" ]; then
        PLANBSRV=`defaults read ${BUILDPLIST} planbServer 2> /dev/null`
        if (($? > 0)); then
            PLANBSRV=$MPPLANB_SRV_ADDR
        fi
    fi

	echo
	echo
	read -p "Would you like to set the server address for PlanB, default is localhost. (Y/N)? [Y]: " MPPLANB_SRV
	MPPLANB_SRV=${MPPLANB_SRV:-Y}
	MPPLANB_SRV=`echo $MPPLANB_SRV | awk '{print toupper($0)}'`
	if [[ "$MPPLANB_SRV" == "Y" ]] ; then
		echo
		read -p "Server address [$PLANBSRV]: " MPPLANB_SRV_ADDR
		MPPLANB_SRV_ADDR=${MPPLANB_SRV_ADDR:-${PLANBSRV}}
        defaults write ${BUILDPLIST} planbServer "${MPPLANB_SRV_ADDR}"
	fi
fi

# ------------------------------------------------------------
# Set Client Version
# ------------------------------------------------------------
AGENT_VERS="3.2.0"
if [ -f "$BUILDPLIST" ]; then
	AGENT_VERS=`defaults read ${BUILDPLIST} client_version 2> /dev/null`
	if (($? > 0)); then
		AGENT_VERS="3.2.0"
	fi
fi
echo
echo " - Set overall MacPatch Client version ( e.g. 3.2.0 ) "
read -p "Set MacPatch Client version [$AGENT_VERS]: " AGENT_VER
AGENT_VER=${AGENT_VER:-$AGENT_VERS}
defaults write ${BUILDPLIST} client_version "${AGENT_VER}"

# ------------------------------------------------------------
# Set Client Build Number
# ------------------------------------------------------------
AGENT_BUILDS="1"
if [ -f "$BUILDPLIST" ]; then
	AGENT_BUILDS=`defaults read ${BUILDPLIST} client_build 2> /dev/null`
	if (($? > 0)); then
		AGENT_BUILDS=1
	fi
fi
echo
echo " - Set overall MacPatch Client build number "
echo " use \"i\" to increment or type in a number "
read -p "Set MacPatch Client build number (current $AGENT_BUILDS),  [i]: " AGENT_BUILD
AGENT_BUILD=${AGENT_BUILD:-$AGENT_BUILDS}

BUILD_NO=0
if [ "$AGENT_BUILD" == "i" ] || [ "$AGENT_BUILD" == "I" ]; then
	let "BUILD_NO=AGENT_BUILDS+1"
else
	BUILD_NO=$AGENT_BUILD
fi

re='^[0-9]+$'
if ! [[ $BUILD_NO =~ $re ]] ; then
   echo "Error: Build number is not a number" >&2; exit 1
fi
defaults write ${BUILDPLIST} client_build "${BUILD_NO}"
AGENTVER="${AGENT_VER}.${BUILD_NO}"

# ------------------------------------------------------------
# MacPatch Client Release Level
# ------------------------------------------------------------
PKGSTATES="R"
if [ -f "$BUILDPLIST" ]; then
	PKGSTATES=`defaults read ${BUILDPLIST} package_state 2> /dev/null`
	if (($? > 0)); then
		PKGSTATES="R"
	fi
fi

echo
read -p "Please choose the desired state (R[elease]/B[eta]/A[lpha])? [$PKGSTATES]: " PKGSTATE
PKGSTATE=${PKGSTATE:-$PKGSTATES}
#PKGSTATE=${PKGSTATE:-R}
PKGSTATE=`echo $PKGSTATE | awk '{print toupper($0)}'`
defaults write ${BUILDPLIST} package_state "${PKGSTATE}"
if [ "$PKGSTATE" == "B" ]; then
	PKG_STATE="- (Beta)"
elif [ "$PKGSTATE" == "A" ]; then
	PKG_STATE="- (Alpha)"
else
	echo "Setting Package desired state to \"Release\""
fi

# ------------------------------------------------------------
# Client Master Key
# ------------------------------------------------------------
SHOW_MASTER_KEY=false
setMasterKey=false
MASTER_KEY_SET="Y"
ClientMasterKey="SuperSimpleKeyPleaseChangeThisInProduction"

echo
echo " - Client Master Key "
read -p "Would you like to set the client master key, no will gen a random key (Y/N)? [$MASTER_KEY_SET]: " MASTER_KEY_TXT
MASTER_KEY_TXT=${MASTER_KEY_TXT:-${MASTER_KEY_SET}}
MASTER_KEY_TXT=`echo $MASTER_KEY_TXT | awk '{print toupper($0)}'`
if [[ "$MASTER_KEY_TXT" == "Y" ]]; then
    setMasterKey=true
else
    ClientMasterKey=`env LC_CTYPE=C LC_ALL=C tr -dc "a-zA-Z0-9-_\$\?" < /dev/urandom | head -c 20; echo`
    SHOW_MASTER_KEY=true
fi


if $setMasterKey; then
    MASTERKEY=$ClientMasterKey
    if [ -f "$BUILDPLIST" ]; then
        MASTERKEY=`defaults read ${BUILDPLIST} masterKey 2> /dev/null`
        if (($? > 0)); then
            MASTERKEY=$ClientMasterKey
        fi
    fi

    echo
    echo
    read -p "Client Master Key [$MASTERKEY]: " CMASTERKEY
    ClientMasterKey=${CMASTERKEY:-${MASTERKEY}}
    defaults write ${BUILDPLIST} masterKey "${ClientMasterKey}"
fi



# ------------------------------------------------------------
# Sign all binaries?
# ------------------------------------------------------------
SIGNCODES="Y"
if [ -f "$BUILDPLIST" ]; then
	SIGNCODES=`defaults read ${BUILDPLIST} code_sign 2> /dev/null`
	if (($? > 0)); then
		SIGNCODES="Y"
	fi
fi

echo
echo " - Code Signing"
read -p "Would you like to code sign all binaries (Y/N)? [$SIGNCODES]: " SIGNCODE
#SIGNCODE=${SIGNCODE:-Y}
SIGNCODE=${SIGNCODE:-$SIGNCODES}
SIGNCODE=`echo $SIGNCODE | awk '{print toupper($0)}'`
defaults write ${BUILDPLIST} code_sign $SIGNCODE
if [ "$SIGNCODE" == "N" ] || [ "$SIGNCODE" == "Y" ]; then

    if $EXTERNALSCRIPTS; then
        runExternalScripts $EXTERNALSCRIPTSDIR
    fi

    cp "${SRCROOT}/MacPatch/MPLibrary/AgentData.m" /private/tmp/AgentData.m.bak
    sed -i '' "s/SimpleSecretKey/${ClientMasterKey}/g" "${SRCROOT}/MacPatch/MPLibrary/AgentData.m"

	if [ "$SIGNCODE" == "Y" ] ; then
		# Compile the agent components
		read -p "Please enter your code sigining identity [$CODESIGNIDENTITYALT]: " CODESIGNIDENTITY
		CODESIGNIDENTITY=${CODESIGNIDENTITY:-$CODESIGNIDENTITYALT}
		if [ "$CODESIGNIDENTITY" != "$CODESIGNIDENTITYALT" ]; then
			defaults write ${BUILDPLIST} name "${CODESIGNIDENTITY}"
		fi
		echo
		echo "------------------------------------------------------------"
		echo "Compiling MacPatch Client Components"
		echo "------------------------------------------------------------"
		echo
		echo " - Compiling MacPatch"
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MacPatch SYMROOT=${BUILDROOT} -configuration Release CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}" | grep -A 5 error:
		echo " - Compiling gov.llnl.mp.helper"
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme gov.llnl.mp.helper SYMROOT=${BUILDROOT} -configuration Release CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}" | grep -A 5 error:
		echo " - Compiling MPClientStatus"
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPClientStatus SYMROOT=${BUILDROOT} -configuration Release CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}" | grep -A 5 error:
		#echo " - Compiling MPAgentExec"
		#xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPAgentExec SYMROOT=${BUILDROOT} -configuration Release CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}" | grep -A 5 error:
		echo " - Compiling MPAgent"
        sed -i '' "s/\[BUILD\]/$BUILD_NO_STR/g" "${SRCROOT}/MacPatch/MPAgent/MPAgent/main.m"
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPAgent SYMROOT=${BUILDROOT} -configuration Release CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}" | grep -A 5 error:
        sed -i '' "s/$BUILD_NO_STR/\[BUILD\]/g" "${SRCROOT}/MacPatch/MPAgent/MPAgent/main.m"
		echo " - Compiling MPLoginAgent"
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPLoginAgent SYMROOT=${BUILDROOT} -configuration Release CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}" | grep -A 5 error:
		echo " - Compiling MPUpdater"
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPUpdater SYMROOT=${BUILDROOT} -configuration Release CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}" | grep -A 5 error:

		if $INCPlanBSource; then
			echo " - Compiling Plan B"
			xcodebuild build -configuration Release -project ${SRCROOT}/Client/planb/planb.xcodeproj -target planb SYMROOT=${PLANB_BUILDROOT} CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}" | grep -A 5 error:
		fi
		echo
		echo "Compiling completed."
		echo
	else

        if $EXTERNALSCRIPTS; then
            runExternalScripts $EXTERNALSCRIPTSDIR
        fi

		# Compile the agent components
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MacPatch SYMROOT=${BUILDROOT} -configuration Release 
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme gov.llnl.mp.helper SYMROOT=${BUILDROOT} -configuration Release
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPClientStatus SYMROOT=${BUILDROOT} -configuration Release
		#xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPAgentExec SYMROOT=${BUILDROOT} -configuration Release
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPAgent SYMROOT=${BUILDROOT} -configuration Release
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPLoginAgent SYMROOT=${BUILDROOT} -configuration Release
		xcodebuild build -workspace ${SRCROOT}/MacPatch/MacPatch.xcworkspace -scheme MPUpdater SYMROOT=${BUILDROOT} -configuration Release

		if $INCPlanBSource; then
			xcodebuild clean build -configuration Release -project ${SRCROOT}/Client/planb/planb.xcodeproj -target planb SYMROOT=${PLANB_BUILD_ROOT}
		fi
	fi

    sed -i '' "s/${ClientMasterKey}/SimpleSecretKey/g" "${SRCROOT}/MacPatch/MPLibrary/AgentData.m"
else
	echo "Invalid entry, now exiting."
	exit 1
fi

# ------------------------------------------------------------
# Remove the build and symbol files
# ------------------------------------------------------------
find ${BUILDROOT} -name "*.build" -print | xargs -I{} rm -rf {}
find ${BUILDROOT} -name "*.dSYM" -print | xargs -I{} rm -rf {}

# ------------------------------------------------------------
# Remove the static library and header files
# ------------------------------------------------------------
if [ -f "${BUILDROOT}/Release/libMacPatch.a" ]; then
	rm ${BUILDROOT}/Release/libMacPatch.a
fi
if [ -f "${BUILDROOT}/Release/libcrypto.a" ]; then
	rm ${BUILDROOT}/Release/libcrypto.a
fi
if [ -f "${BUILDROOT}/Release/libssl.a" ]; then
	rm ${BUILDROOT}/Release/libssl.a
fi
if [ -d "${BUILDROOT}/Release/usr" ]; then
	rm -r ${BUILDROOT}/Release/usr
fi

# ------------------------------------------------------------
# Copy files to package roots
# ------------------------------------------------------------

cp -R ${PKGROOT}/Client ${BUILDROOT}
cp -R ${PKGROOT}/Updater ${BUILDROOT}
cp -R ${PKGROOT}/Combined ${BUILDROOT}

mv ${BUILDROOT}/Release/MacPatch.app ${BUILDROOT}/Client/Files/Applications/
mv ${BUILDROOT}/Release/gov.llnl.mp.helper ${BUILDROOT}/Client/Files/Library/PrivilegedHelperTools/
mv ${BUILDROOT}/Release/MPClientStatus.app ${BUILDROOT}/Client/Files/Library/MacPatch/Client
#mv ${BUILDROOT}/Release/MPAgentExec ${BUILDROOT}/Client/Files/Library/MacPatch/Client
mv ${BUILDROOT}/Release/MPAgent ${BUILDROOT}/Client/Files/Library/MacPatch/Client
mv ${BUILDROOT}/Release/MPLoginAgent.app ${BUILDROOT}/Client/Files/Library/PrivilegedHelperTools/

mv ${BUILDROOT}/Release/MPUpdater ${BUILDROOT}/Updater/Files/Library/MacPatch/Updater/


# ------------------------------------------------------------
# Copy PlanB files to base package root
# ------------------------------------------------------------
if $INCPlanBSource; then

	mkdir -p ${BUILDROOT}/Client/Files/usr/local/bin/
	mkdir -p ${BUILDROOT}/Client/Files/usr/local/sbin/
    mkdir -p ${BUILDROOT}/Client/Files/Library/Preferences/

	cp ${PLANB_BUILDROOT}/Release/planb ${BUILDROOT}/Client/Files/usr/local/sbin/
	cp ${SRCROOT}/Client/planb/mpPlanB ${BUILDROOT}/Client/Files/usr/local/bin/
	cp ${SRCROOT}/Client/planb/gov.llnl.mp.planb.plist ${BUILDROOT}/Client/Files/Library/LaunchDaemons/
    cp ${SRCROOT}/Client/planb/Preferences/gov.llnl.planb.plist ${BUILDROOT}/Client/Files/Library/Preferences/

    #agentHash=`md5 -q ${BUILDROOT}/Client/Files/Library/MacPatch/Client/MPAgent`
	#sed -i '' "s/MPSERVER=\"localhost\"/MPSERVER=\"${MPPLANB_SRV_ADDR}\"/g" "${BUILDROOT}/Client/Files/usr/local/bin/mpPlanB"
    #sed -i '' "s/MPHASH=\"0\"/MPHASH=\"${agentHash}\"/g" "${BUILDROOT}/Client/Files/usr/local/bin/mpPlanB"
fi

# ------------------------------------------------------------
# Get Versions, set version info
# ------------------------------------------------------------
agent_ver=`${BUILDROOT}/Client/Files/Library/MacPatch/Client/MPAgent -v`
update_ver=`${BUILDROOT}/Updater/Files/Library/MacPatch/Updater/MPUpdater -v`

sleep 5

# Agent
# @AGENTVER@
sed -i '' "s/@AGENTVER@/$agent_ver/g" "${BUILDROOT}/Client/Resources/mpInfo.plist"
sed -i '' "s/@AGENTVER@/$agent_ver/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @APPVER@
sed -i '' "s/@APPVER@/$AGENT_VER/g" "${BUILDROOT}/Client/Resources/mpInfo.plist"
sed -i '' "s/@APPVER@/$AGENT_VER/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @AMINOS@
sed -i '' "s/@AMINOS@/$MIN_OS/g" "${BUILDROOT}/Client/Resources/mpInfo.plist"
sed -i '' "s/@AMINOS@/$MIN_OS/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @ABUILD@
sed -i '' "s/@ABUILD@/$BUILD_NO/g" "${BUILDROOT}/Client/Resources/mpInfo.plist"
sed -i '' "s/@ABUILD@/$BUILD_NO/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"

# Updater
# @UPDATEVER@
sed -i '' "s/@UPDATEVER@/$update_ver/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @APPVER@
sed -i '' "s/@APPVER@/$AGENT_VER/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @UMINOS@
sed -i '' "s/@UMINOS@/$MIN_OS/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @UBUILD@
sed -i '' "s/@UBUILD@/$BUILD_NO/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"

# Find and remove .mpRM files, these are here as place holders so that GIT will keep the
# directory structure
find ${BUILDROOT} -name ".mpRM" -print | xargs -I{} rm -rf {}

# Remove the compiled Release directory now that all of the files have been copied
# rm -r ${BUILDROOT}/Release

# Run the post external scripts
if $PEXTERNALSCRIPTS; then
    runExternalScripts $PEXTERNALSCRIPTSDIR
fi

mkdir ${BUILDROOT}/Combined/Packages

# Remove the compiled Release directory now that all of the files have been copied
# rm -r ${BUILDROOT}/Release
# --sign "Developer ID Installer: Charles Heizer" \

# ------------------------------------------------------------
# Create the Client pkg
# ------------------------------------------------------------
pkgbuild --root ${BUILDROOT}/Client/Files \
--component-plist ${BUILDROOT}/Client/Components.plist \
--identifier gov.llnl.mp.agent.client \
--install-location / \
--scripts ${BUILDROOT}/Client/Scripts \
--version $AGENTVER \
${BUILDROOT}/Combined/Packages/Base.pkg

# ------------------------------------------------------------
# Create the Updater pkg
# ------------------------------------------------------------
pkgbuild --root ${BUILDROOT}/Updater/Files/Library \
--identifier gov.llnl.mp.agent.updater \
--install-location /Library \
--scripts ${BUILDROOT}/Updater/Scripts \
--version $UPDATEVER \
${BUILDROOT}/Combined/Packages/Updater.pkg

# ------------------------------------------------------------
# Set Version Info in text files
# ------------------------------------------------------------
AGENT_VER_BUILD="$AGENTVER"
sed -i '' "s/\[AGENT_VER\]/$AGENT_VER_BUILD/g" "${BUILDROOT}/Combined/Resources/Welcome.rtf"
sed -i '' "s/\[BUILD_NO\]/$BUILD_NO_STR/g" "${BUILDROOT}/Combined/Resources/Welcome.rtf"
sed -i '' "s/\[STATE\]/$PKG_STATE/g" "${BUILDROOT}/Combined/Resources/Welcome.rtf"

BUILD_FILE="${BUILDROOT}/Combined/MP-$BASEPKGVER-$BUILD_NO_STR$PKG_STATE"
echo "MP-$AGENT_VER_BUILD-$BUILD_NO_STR$PKG_STATE" > "${BUILD_FILE}"

# ------------------------------------------------------------
# Create the almost final package
# --sign "Developer ID Installer: Charles Heizer" \
# ------------------------------------------------------------
productbuild --distribution ${BUILDROOT}/Combined/Distribution \
--resources ${BUILDROOT}/Combined/Resources \
--package-path ${BUILDROOT}/Combined/Packages \
${BUILDROOT}/Combined/MacPatchDist.pkg


# Expand the newly created package so we can add the nessasary files
pkgutil --expand ${BUILDROOT}/Combined/MacPatchDist.pkg ${BUILDROOT}/Combined/.MacPatchPKG


# Copy MacPatch Package Info file for the web service
cp ${BUILDROOT}/Combined/Resources/mpInfo.ini ${BUILDROOT}/Combined/.MacPatchPKG/Resources/mpInfo.ini
cp ${BUILDROOT}/Combined/Resources/mpInfo.plist ${BUILDROOT}/Combined/.MacPatchPKG/Resources/mpInfo.plist
cp ${BUILDROOT}/Combined/Resources/Background_done.png ${BUILDROOT}/Combined/.MacPatchPKG/Resources/Background_done.png

# Re-compress expanded package
pkgutil --flatten ${BUILDROOT}/Combined/.MacPatchPKG ${BUILDROOT}/Combined/MacPatch.pkg

# Clean Up
rm -rf ${BUILDROOT}/Combined/.MacPatchPKG
#rm -rf ${BUILDROOT}/Combined/MacPatchDist.pkg

# Compress for upload
ditto -c -k ${BUILDROOT}/Combined/MacPatch.pkg ${BUILDROOT}/Combined/MacPatch.pkg.zip

echo
read -p "Would you like to copy the installer to repo location for a pull request? (Y/N)? [N]: " COPYINSTALLPKG
COPYINSTALLPKG=${COPYINSTALLPKG:-N}
COPYINSTALLPKG=`echo $COPYINSTALLPKG | awk '{print toupper($0)}'`
if [ "$COPYINSTALLPKG" == "Y" ]; then
	rm -rf "${SRCROOT}/Agent"
	mkdir "${SRCROOT}/Agent"
	cp "${BUILDROOT}/Combined/MacPatch.pkg.zip" "${SRCROOT}/Agent/"
	cp "$BUILD_FILE" "${SRCROOT}/Agent/InstallerBuildInfo.txt"
fi

echo
echo "New Client is located in $BUILDROOT"
open ${BUILDROOT}

if $SHOW_MASTER_KEY; then
    echo
    echo "A random master client key has been set. Please write this down in a secure location."
    echo "$ClientMasterKey"
    echo
fi


